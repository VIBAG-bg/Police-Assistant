-- Cooperative frame state machine: no threads, wait(), sleeps or recursive resumes.
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local M={}; local Executor={}; Executor.__index=Executor
local function unsafe(ctx)
    return ctx.focused~=true or ctx.paused~=false or ctx.blocked~=false or
        (ctx.window~=false and ctx.ownWindow~=true) or ctx.editingHud==true
end
local function validTarget(self,target)
    local ok,result=pcall(self.env.validate,target)
    return ok and core.capturedTargetValid(result) and result.id==target.id and result.ped==target.ped and result.name==target.name
end
function M.new(env) return setmetatable({env=env,status='Готово.',queue=nil},Executor) end
function Executor:event(kind,q,reason)
    if self.env.event then pcall(self.env.event,kind,q,reason) end
end
function Executor:cancel(reason)
    local q=self.queue; self.queue=nil
    if q then self.status=reason or 'Отменено.'; self:event('cancelled',q,self.status) end
end
function Executor:start(plan,demo,interval)
    if self.queue then return nil,'Другой сценарий уже выполняется.' end
    if type(plan)~='table' or not model.array(plan.steps,64) or #plan.steps==0 then return nil,'Нет подготовленного сценария.' end
    if type(demo)~='boolean' or not core.finite(interval) or interval<1000 or interval>5000 then return nil,'Неверные параметры запуска.' end
    if plan.demo~=demo then return nil,'Режим изменился после предпросмотра.' end
    local ctx=self.env.context(); local now=self.env.now()
    if not core.finite(now) or not ctx.session or unsafe(ctx) or (not demo and ctx.alive~=true) then return nil,'Игра или ввод сейчас недоступны.' end
    if plan.session~=ctx.session then return nil,'Подключение изменилось после подготовки.' end
    if (plan.alert or plan.automatic or plan.rpSignature or plan.textSignature) and self.env.planValid and not self.env.planValid(plan) then return nil,'Данные действия изменились. Подготовьте его заново.' end
    local preparedAge=core.elapsed(now,plan.createdAt); if not preparedAge or preparedAge>60000 then return nil,'Предпросмотр устарел. Подготовьте сценарий заново.' end
    if not demo then
        for _, target in ipairs({plan.target or false,plan.closest or false}) do
            if target and not validTarget(self,target) then return nil,'Выбранный человек недоступен.' end
        end
        if plan.requirements.target and not plan.target then return nil,'Нужен выбранный человек.' end
    end
    local q={plan=model.copy(plan),demo=demo,interval=interval,index=1,startedAt=now,lastTick=now,
        session=ctx.session,sent=0,previewed=0,keyArmed=false}
    self.queue=q; self.status=plan.binding.name..': начато.'; self:event('started',q)
    return true
end
function Executor:step()
    local q=self.queue; if not q then return end
    local now=self.env.now(); local ctx=self.env.context()
    local age=core.elapsed(now,q.startedAt); local delta=core.elapsed(now,q.lastTick)
    if not age or not delta or age>600000 or ctx.session~=q.session or self.env.demo()~=q.demo or
        unsafe(ctx) or (not q.demo and ctx.alive~=true) then
        self:cancel('Сценарий остановлен: контекст игры изменился.'); return
    end
    q.lastTick=now
    if (q.plan.alert or q.plan.automatic or q.plan.rpSignature or q.plan.textSignature) and self.env.planValid and not self.env.planValid(q.plan) then
        self:cancel('Данные действия изменились. Отправка остановлена.');return
    end
    if not q.demo then
        for _,target in ipairs({q.plan.target or false,q.plan.closest or false}) do
            if target and not validTarget(self,target) then self:cancel('Цель потеряна или ID переиспользован.'); return end
        end
    end
    local step=q.plan.steps[q.index]
    if not step then self.queue=nil; self.status='Сценарий завершён; результат команды определяет сервер.'; self:event('completed',q); return end
    local advanced=false
    if step.kind=='message' then
        local last=self.env.lastSent(); local elapsed=last and core.elapsed(now,last)
        if last and not elapsed then self:cancel('Таймер отправки сбросился.'); return end
        if last and elapsed<q.interval then self.status='Ожидание интервала отправки…'; return end
        if q.demo then q.previewed=q.previewed+1; self:event('preview_line',q,step.text)
        else
            local ok,result=pcall(self.env.send,step.wire)
            if not ok or result~=true then self:cancel('Ошибка отправки. Автоматического повтора нет.'); return end
            q.sent=q.sent+1; self:event('sent_line',q,step.text)
        end
        self.env.markSent(now,q.demo); advanced=true
    elseif step.kind=='wait' then
        if not q.waitAt then q.waitAt=now end
        local waited=core.elapsed(now,q.waitAt)
        if not waited then self:cancel('Таймер ожидания сбросился.'); return end
        self.status='Пауза: '..math.max(0,math.ceil((step.ms-waited)/1000))..' с'
        advanced=waited>=step.ms
    elseif step.kind=='key' then
        if not q.waitAt then q.waitAt=now end
        if core.elapsed(now,q.waitAt)>90000 then self:cancel('Время ожидания клавиши истекло.'); return end
        if ctx.typing==true or ctx.recording==true then q.keyArmed=false
        else
            if not self.env.down(step.key) then q.keyArmed=true end
            advanced=q.keyArmed and self.env.pressed(step.key)==true
        end
        self.status='Ожидание '..model.keyName(step.key)..' · End/Esc — остановить'
    elseif step.kind=='cancel' then
        self:cancel('Взаимодействие завершено шагом @cancel.')
        if self.env.clearTarget then self.env.clearTarget() end
        return
    elseif step.kind=='check' then
        if not q.demo and ((step.target and not q.plan.target) or (q.plan.target and not validTarget(self,q.plan.target))) then self:cancel('Проверка цели не пройдена.'); return end; advanced=true
    elseif step.kind=='sound' or step.kind=='screen' then
        if q.demo then advanced=true
        else local fn=step.kind=='sound' and self.env.sound or self.env.screen; local ok,result=pcall(fn or function() return false end,step.sound)
            if not ok or result~=true then self:cancel('Дополнительный шаг недоступен.'); return end; advanced=true end
    else self:cancel('Неизвестный подготовленный шаг.'); return end
    if advanced then q.index=q.index+1; q.waitAt=nil; q.keyArmed=false
        if q.index>#q.plan.steps then self.queue=nil; self.status=q.demo and 'Демо завершено. Отправок: 0.' or 'Все строки переданы клиенту; результат определяет сервер.'; self:event('completed',q) end
    end
end
return M

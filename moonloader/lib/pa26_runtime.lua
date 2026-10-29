-- Original state machine with an injected game adapter. Nothing sends on its own.
local core = require 'pa26_core'
local wheelModel = require 'pa26_wheel'
local M = {}
local Runtime = {}
Runtime.__index = Runtime

function M.new(env, cfg)
    assert(core.validateSettings(cfg))
    return setmetatable({env = env, cfg = cfg, demo = cfg.main.demo_mode,
        revision = 1, epoch = 0, session = nil, wheel = nil, queue = nil,
        lastSentAt = nil, lastTickAt = nil, status = 'Готово.'}, Runtime)
end

function Runtime:report(message,kind)
    self.status = message
    if self.lastReport ~= message then
        self.lastReport = message
        pcall(self.env.log, message)
    end
    if kind~='info'and type(self.env.feedback)=='function'then pcall(self.env.feedback,message)end
end

function Runtime:cancel(reason)
    local pending = self.wheel ~= nil or self.queue ~= nil
    self.wheel, self.queue = nil, nil
    if pending and reason then self:report(reason,'info') end
    return pending
end

function Runtime:setDemo(enabled)
    if type(enabled) ~= 'boolean' then return false end
    if self.demo ~= enabled then
        self:cancel('Действие отменено: режим изменён.')
        self.demo = enabled
        self:report(enabled and 'Деморежим: отправка отключена.' or 'Реальный режим включён.','info')
    end
    return true
end

local function validIndex(index)
    return core.finite(index) and index == math.floor(index) and core.actions[index] ~= nil
end
local function catalogueCurrent(self)
    local ok,revision=pcall(self.env.wheelRevision)
    return ok and core.finite(revision) and revision==self.wheel.catalog.revision
end

function Runtime:applyConfig(cfg)
    local ok, err = core.validateSettings(cfg)
    if not ok then return nil, err end
    for _, a in ipairs(core.actions) do
        local e
        e, err = core.validateAction(cfg[a.key])
        if not e then return nil, a.label .. ': ' .. err end
        local rpSettings,nickname;if self.env.rpSettings then rpSettings,nickname=self.env.rpSettings()end
        if e.enabled and not core.prepareAction(e, 1003, self.env.codec,rpSettings,nickname)then
            return nil, a.label .. ': строка не подходит для чата.'
        end
    end
    self:cancel('Действие отменено: настройки изменены.')
    self.cfg, self.demo = cfg, cfg.main.demo_mode
    self.revision = self.revision + 1
    return true
end

function Runtime:refresh()
    local timeOk, now = pcall(self.env.now)
    if not timeOk or not core.finite(now) or now ~= math.floor(now) then
        self:cancel('Ошибка игрового таймера. Действие отменено.')
        return nil
    end
    if self.lastTickAt and core.elapsed(now, self.lastTickAt) == nil then
        self:cancel('Игровой таймер сбросился. Действие отменено.')
        self.lastSentAt = now
    end
    self.lastTickAt = now
    local ok, ctx = pcall(self.env.context)
    if not ok or type(ctx) ~= 'table' then
        self:cancel('Ошибка проверки состояния игры. Действие отменено.')
        return nil
    end
    local session = type(ctx.session) == 'string' and ctx.session ~= '' and ctx.session or nil
    if session ~= self.session then
        self:cancel('Подключение изменилось. Действие отменено.')
        self.session, self.epoch = session, self.epoch + 1
        self.lastSentAt = nil
    end
    self.context = ctx
    if not session or ctx.focused ~= true or ctx.paused ~= false or ctx.blocked ~= false or
        ctx.window ~= false or (not self.demo and ctx.alive ~= true) then
        self:cancel('Действие отменено: игра или ввод сейчас недоступны.')
        return nil
    end
    if self.wheel then
        local age = core.elapsed(now, self.wheel.openedAt)
        if not age then
            self:cancel('Игровой таймер сбросился. Колесо закрыто.')
        elseif self.wheel.epoch ~= self.epoch or self.wheel.revision ~= self.revision or
            self.wheel.demo ~= self.demo then
            self:cancel('Контекст колеса изменился. Действие отменено.')
        elseif self.wheel.catalog and self.env.wheelRevision and not catalogueCurrent(self) then
            self:cancel('Библиотека или настройки меню изменились. Откройте колесо заново.')
        elseif not self.demo and self.wheel.target ~= nil then
            local valid, target = pcall(self.env.validate, self.wheel.target, self.cfg.main.max_distance)
            if not valid or not target then self:cancel('Цель больше не доступна. Колесо закрыто.') end
        end
    end
    return now
end

function Runtime:openWheel()
    local now = self:refresh()
    if not now or self.wheel or self.queue then return false end
    local catalogue
    if self.env.wheelCatalog then
        local ok,result=pcall(self.env.wheelCatalog)
        if not ok then self:report('Не удалось подготовить меню.'); return false end
        catalogue=result
    end
    local target
    local targetNote
    if not self.demo then
        local ok, result, reason = pcall(self.env.acquire, self.cfg.main.max_distance)
        if ok and core.capturedTargetValid(result) then target = result
        else
            if not ok then pcall(self.env.log, '[Ошибка выбора цели] ' .. tostring(result)) end
            if ok then targetNote = reason
            else targetNote = 'Ошибка определения цели; подробности проверки доступны в журнале.' end
            if type(targetNote) ~= 'string' or targetNote == '' then
                targetNote = 'Нет видимой цели рядом. Наведите центр экрана на игрока.'
            end
            if not catalogue then self:report(targetNote,'info')end
        end
    end
    self.wheel = {target = target, choice = nil, openedAt = now, drawnAt = nil,
        demo = self.demo, epoch = self.epoch, revision = self.revision, targetNote = targetNote,catalog=catalogue,nav={}}
    return true
end
function Runtime:setBindingChoice(route,drawnAt)
    local wheel=self.wheel
    if not wheel or not wheel.catalog then return end
    wheel.choice=wheelModel.available(wheel.catalog,route,wheel.demo,wheel.target) and core.finite(drawnAt) and
        {kind=route.kind,id=route.id,category=route.category} or nil
    wheel.drawnAt=drawnAt
end
function Runtime:commitBindingWheel(clicked)
    if self.wheel and self.wheel.editConsumed then self.wheel=nil;return false end
    local now=self:refresh(); local wheel=self.wheel; self.wheel=nil
    if not now or not wheel or not wheel.catalog then return false end
    local route=clicked or wheel.choice
    local age=wheel.drawnAt and core.elapsed(now,wheel.drawnAt)
    local hold=core.elapsed(now,wheel.openedAt)
    if not wheelModel.sameRoute(route,wheel.choice) or not age or age>250 or not hold or hold<120 or
        not wheelModel.available(wheel.catalog,route,wheel.demo,wheel.target) then return false end
    if route.kind~='binding' then
        if not self.env.wheelNavigate then return false end
        local ok,result=pcall(self.env.wheelNavigate,route,wheel.catalog.profile,wheel.target)
        if not ok then self:report('Не удалось открыть раздел. Колесо закрыто; отправок нет.') end
        return ok and result==true
    end
    if self.queue then return false end
    if not wheel.demo and self.lastSentAt then
        local elapsed=core.elapsed(now,self.lastSentAt)
        if not elapsed or elapsed<2000 then self:report('Подождите две секунды после последней строки.'); return false end
    end
    local item=wheel.catalog.byId[route.id]
    if not self.env.startWheelBinding then self:report('Запуск бинда недоступен.'); return false end
    local ok,result=pcall(self.env.startWheelBinding,item,wheel.target,wheel.demo)
    if not ok then self:report('Не удалось запустить действие. Повтор автоматически не выполняется.') end
    return ok and result==true
end

function Runtime:setChoice(index)
    if not self.wheel then return end
    self.wheel.choice = (self.wheel.demo or self.wheel.target ~= nil) and validIndex(index) and index or nil
    local ok, now = pcall(self.env.now)
    self.wheel.drawnAt = ok and now or nil
end

function Runtime:preview(index, entry)
    if not validIndex(index) then return nil, 'Нет такого действия.' end
    local rpSettings,nickname;if self.env.rpSettings then rpSettings,nickname=self.env.rpSettings()end
    local plan, err = core.prepareAction(entry or self.cfg[core.actions[index].key], 42, self.env.codec,rpSettings,nickname)
    if not plan then self:report(err); return nil, err end
    pcall(self.env.log, '[ДЕМО] ' .. core.actions[index].label .. ' | пример ID 42')
    for _, line in ipairs(plan.lines) do pcall(self.env.log, '[ДЕМО] ' .. line) end
    self.status = 'Предпросмотр: отправки нет.'
    return plan
end

function Runtime:commitWheel(clickedIndex)
    if self.wheel and self.wheel.editConsumed then self.wheel=nil;return false end
    if self.wheel and self.wheel.catalog then return self:commitBindingWheel(clickedIndex) end
    local now = self:refresh()
    local wheel = self.wheel
    self.wheel = nil -- every release/click is consumed at most once
    if not now or not wheel then return false end
    local drawAge = wheel.drawnAt and core.elapsed(now, wheel.drawnAt)
    local holdAge = core.elapsed(now, wheel.openedAt)
    local index = clickedIndex or wheel.choice
    if not validIndex(index) or not drawAge or drawAge > 250 or not holdAge or holdAge < 120 then return false end
    if wheel.demo then
        if self.env.startBinding then return self.env.startBinding(index,nil,true) end
        return self:preview(index) ~= nil
    end
    if wheel.target == nil then self:report('Нет цели. Отправка отключена.'); return false end
    if self.queue then return false end
    if self.lastSentAt then
        local elapsed = core.elapsed(now, self.lastSentAt)
        if not elapsed or elapsed < 2000 then self:report('Подождите две секунды после последней строки.'); return false end
    end
    local ok, target = pcall(self.env.validate, wheel.target, self.cfg.main.max_distance)
    if not ok or not target then self:report('Цель изменилась. Отправка отменена.'); return false end
    if self.env.startBinding then return self.env.startBinding(index,target,false) end
    local rpSettings,nickname;if self.env.rpSettings then rpSettings,nickname=self.env.rpSettings()end
    local plan, err = core.prepareAction(self.cfg[core.actions[index].key], target.id, self.env.codec,rpSettings,nickname)
    if not plan then self:report(err); return false end
    self.queue = {plan = plan, index = 1, target = target, startedAt = now,
        interval = self.cfg.main.interval_ms, epoch = self.epoch, revision = self.revision}
    self.status = core.actions[index].label .. ': ожидается отправка ' .. #plan.lines .. ' строк.'
    return true
end

function Runtime:step()
    local now = self:refresh()
    local q = self.queue
    if not now or not q then return end
    local age = core.elapsed(now, q.startedAt)
    if self.demo or q.epoch ~= self.epoch or q.revision ~= self.revision or not age or age > 20000+(q.plan.rpExtraSteps or 0)*self.cfg.main.interval_ms or
        (q.plan.rpSignature and self.env.rpValid and not self.env.rpValid(q.plan.rpSignature))then
        self:cancel('Очередь устарела или режим изменён. Отправка отменена.')
        return
    end
    local ok, target = pcall(self.env.validate, q.target, self.cfg.main.max_distance)
    if not ok or not target then self:cancel('Цель пропала или изменилась. Остальные строки отменены.'); return end
    if self.lastSentAt then
        local elapsed = core.elapsed(now, self.lastSentAt)
        if not elapsed then self:cancel('Ошибка таймера. Отправка отменена.'); return end
        if elapsed < q.interval then return end
    end
    local sentOk, result = pcall(self.env.send, q.plan.wire[q.index])
    if not sentOk or result ~= true then
        self:cancel('Ошибка отправки. Повтор автоматически не выполняется.')
        return
    end
    self.lastSentAt = now
    pcall(self.env.log, '[ПЕРЕДАНО ЧАТУ] ' .. q.plan.lines[q.index])
    q.index = q.index + 1
    if q.index > #q.plan.lines then
        self.queue = nil
        self.status = 'Строки переданы чату клиента; результат команды определяет сервер.'
    end
end

return M

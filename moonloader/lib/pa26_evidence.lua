-- Explicit consent -> optional verified command -> wait -> user F8 -> verify new file.
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local shared=require 'pa26_patrol_settings'
local M={};local Evidence={};Evidence.__index=Evidence
local function safe(s)return s and s.session and s.alive and s.focused and not s.paused and not s.blocked end
local function clock(self)local ok,value=pcall(self.env.files.clock);if ok and core.finite(value)then return value end end
function M.new(env)return setmetatable({env=env,serial=0,life=1},Evidence)end
function Evidence:warn(message)
    self.message=message
    if type(self.env.feedback)=='function'then pcall(self.env.feedback,message)end
end
function Evidence:valid(p,executing)
    local s=self.state;local cfg=self.env.settings();local age=p and core.elapsed(self.now,p.at)
    return p and cfg.enabled and safe(s)and p.life==self.life and p.session==s.session and p.ped==s.ped and p.demo==s.demo and
        age and(executing or age<=cfg.confirmation_ms)and self.env.equal(p.cfg,cfg)or false
end
function Evidence:propose(label)
    if self.active or self.intent or self.queued or self.pendingRecord then return nil,'Завершите текущую фиксацию или сохраните её журнал.'end
    local cfg=self.env.settings();local s=self.state
    if not cfg.enabled or not safe(s)then return nil,'Включите фиксацию; игра и персонаж должны быть доступны.'end
    label=shared.text(label,160);if not label or label==''then return nil,'Кратко назовите, что вы фиксируете.'end
    local fileClock=self.fileClock;if not fileClock and not s.demo then return nil,'Проверка новых файлов недоступна в этом клиенте.'end
    local steps,lines={},{}
    if cfg.time_enabled then
        if not cfg.time_verified or cfg.time_source==''then return nil,'Команда времени не подтверждена.'end
        local ok,wire=pcall(self.env.codec.encode,cfg.time_command)
        if not ok or type(wire)~='string'or #wire>144 then return nil,'Команда времени не кодируется для клиента.'end
        steps[1]={kind='message',text=cfg.time_command,wire=wire};lines[1]=cfg.time_command
    end
    steps[#steps+1]={kind='wait',ms=cfg.delay_ms}
    self.serial=self.serial+1
    return {token='evidence:'..self.life..':'..self.serial,label=label,cfg=model.copy(cfg),life=self.life,session=s.session,ped=s.ped,demo=s.demo,
        at=self.now,steps=steps,lines=lines,area=s.area or '',clock=fileClock}
end
function Evidence:accept(p)
    if self.intent or self.queued or self.active or self.pendingRecord then return nil,'Фиксация уже запущена.'end
    if not self:valid(p)then return nil,'Настройки или игровая сцена изменились. Подтвердите заново.'end
    self.intent=model.copy(p);return true
end
function Evidence:validPlan(plan)
    local p=self.queued
    return p and plan.evidenceAction and plan.evidenceAction.token==p.token and self:valid(p,true)and
        self.env.equal(plan.steps,p.steps)and not self.state.typing and not self.state.modal or false
end
function Evidence:record(status,path,details)
    local p=self.active or self.queued or self.intent
    if not p then return end
    self.pendingRecord={status=status,demo=p.demo,verified=status=='verified',date=self.env.date(),label=p.label,path=path or '',details=details or ''}
    self.active=nil;self.queued=nil;self.intent=nil;self.checkRequest=nil;self.autoPath=nil;self.sample=nil;self.recordAttempted=false
end
function Evidence:cancel(reason)
    local p=self.queued;self:record('cancelled','',reason or 'Отменено пользователем.')
    if p and self.env.cancel then self.env.cancel(p.token,reason)end
    self.life=self.life+1;self.message=reason or 'Фиксация отменена.'
end
function Evidence:onExecution(kind,q)
    local p=self.queued;if not p or not q.plan.evidenceAction or q.plan.evidenceAction.token~=p.token then return end
    if kind=='completed'then
        self.queued=nil;self.active=p;p.waitAt=self.now;p.clock=clock(self);self.message=p.cfg.prompt
        if not p.clock and not p.demo then self:record('cancelled','','Недоступно время создания файла.');self:warn('Не удалось подготовить проверку нового файла.');return end
        if p.demo then self:record('demo','','Демо: команда и снимок не создавались.');self.message='Демо завершено. Снимок не создавался.'end
    elseif kind=='cancelled'then self:record('cancelled','','Передача команды или ожидание отменены.');self.message='Фиксация прервана без повтора.'end
end
function Evidence:check(path)
    if not self.active or self.active.demo then return nil,'Сначала начните фиксацию и дождитесь подсказки.'end
    path=shared.text(path,1024);if not path or path==''then return nil,'Укажите полный путь к снимку.'end
    self.checkRequest=path;self.sample=nil;self.checkAt=nil;return true
end
function Evidence:retrySave()if self.pendingRecord then self.recordAttempted=false end end
function Evidence:proposeArchive()
 if self.active or self.intent or self.queued or self.archiveRequest then return nil,'Завершите фиксацию перед переносом снимков.'end
 if not self.scan or self.scan.maxIndex<0 then return nil,'Обновите состояние каталога: снимки SA:MP пока не найдены.'end
 return {dir=self.scan.dir,count=self.scan.count,maxIndex=self.scan.maxIndex,session=self.state and self.state.session,demo=self.state and self.state.demo}
end
function Evidence:archive(p)
 if self.active or self.intent or self.queued or self.archiveRequest or not p or not self.state or p.session~=self.state.session or p.demo~=self.state.demo or not self.scan or p.dir~=self.scan.dir then return nil,'Состояние фиксации или папка изменились. Подтвердите архив заново.'end
 self.archiveRequest=model.copy(p);return true
end
function Evidence:tick(state,now)
    local previous=self.state;self.state=model.copy(state);self.now=now
    if previous and(previous.session~=state.session or previous.ped~=state.ped or previous.demo~=state.demo or not core.elapsed(now,self.lastTick))then self:cancel('Игровая сцена изменилась.')end
    self.lastTick=now
    local cfg=self.env.settings()
    if self.archiveRequest then
        local p=self.archiveRequest;self.archiveRequest=nil
        if not safe(state)or p.session~=state.session or p.demo~=state.demo then self:warn('Перенос отменён: игровая сцена изменилась.')
        elseif p.demo then self:warn('ДЕМО: снимки не перемещались.')
        else
            local ok,result,err=pcall(self.env.files.archiveScreens,p.dir,os.date('%Y%m%d-%H%M%S'))
            if not ok or not result then self:warn(err or'Не удалось перенести снимки. Исходные файлы сохранены.')
            else self:warn('Перенесено: '..result.moved..'. Оставлено на месте: '..result.skipped..'. Архив: '..result.archiveDir)end
            self.scanAt=nil;self.scan=nil
        end
    end
    local scanAge=self.scanAt and core.elapsed(now,self.scanAt)
    local scanInterval=self.active and(cfg.scan_ms or 500)or(cfg.idle_scan_ms or 5000)
    if cfg.auto_scan~=false and self.env.files.scanScreens and(not scanAge or scanAge>=scanInterval)then
        self.scanAt=now;local ok,scan,err=pcall(self.env.files.scanScreens,cfg.screens_dir or'')
        self.scan=ok and scan or nil;self.scanError=ok and err or'Проверка папки снимков недоступна.'
        local p=self.active
        if p and self.scan and self.scan.latestFile and self.scan.latestCreated>=p.clock and self.scan.latestWritten>=p.clock and not self.checkRequest then
            self.autoPath=self.scan.latestFile
        end
    end
    if self.env.settings().enabled then self.fileClock=clock(self)else self.fileClock=nil end
    if not safe(state)or not self.env.settings().enabled then if self.intent or self.queued or self.active then self:cancel('Фиксация отменена: игра недоступна или функция выключена.')end end
    if self.intent then
        local p=self.intent
        if not self:valid(p)then self:cancel('Подтверждение фиксации устарело.')
        elseif not state.busy and not state.modal and not state.typing and not state.recording and not state.wheel and not state.alertPending then
            self.intent=nil;self.queued=p
            local b=model.newBinding(999999992);b.name='Фиксация · '..p.label
            local plan={binding=b,requirements={target=false},session=p.session,createdAt=now,demo=p.demo,has_command=#p.lines>0,
                steps=model.copy(p.steps),lines=model.copy(p.lines),automatic={kind='evidence'},evidenceAction={token=p.token}}
            local ok,err=self.env.start(plan)
            if ok then if self.env.hideUi then self.env.hideUi()end else self.queued=nil;self:warn('Не запущено: '..tostring(err))end
        end
    end
    local p=self.active
    if p then
        local elapsed=core.elapsed(now,p.waitAt)
        if not elapsed or elapsed>p.cfg.timeout_ms then self:record('timeout','','Истекло время ожидания снимка.');self:warn('Снимок не подтверждён: время ожидания истекло.')
        elseif not self.env.equal(p.cfg,self.env.settings())then self:cancel('Настройки фиксации изменились.')
        elseif (self.checkRequest or self.autoPath)and(not self.checkAt or(core.elapsed(now,self.checkAt)or 0)>=(cfg.scan_ms or 500))then
            self.checkAt=now
            local manual=self.checkRequest~=nil;local path=self.checkRequest or self.autoPath
            local ok,file,err=pcall(self.env.files.verify,path,p.clock)
            if not ok or not file then if manual then self:warn(err or 'Проверка файла не удалась.')end;self.checkRequest=nil;self.autoPath=nil;self.sample=nil
            elseif self.sample and self.sample.key==file.key then
                self:record('verified',file.path,'Новый файл PNG/JPG прочитан; размер и время записи стабильны. Это не проверка содержания доказательства.')
                self.message='Файл снимка проверен. Содержание проверьте самостоятельно.'
            else self.sample=file;self.message='Снимок найден. Проверяю завершение записи…'end
        end
    end
    if self.pendingRecord and not self.recordAttempted then
        self.recordAttempted=true;local ok,err=self.env.record(self.pendingRecord)
        if ok then self.pendingRecord=nil else self:warn('Журнал не сохранён: '..tostring(err)..'. Повторите запись в помощнике.')end
    end
end
function Evidence:view()
    return {active=model.copy(self.active),pending=self.intent~=nil or self.queued~=nil,unsaved=model.copy(self.pendingRecord),message=self.message,
        screens=self.scan and {dir=self.scan.dir,count=self.scan.count,maxIndex=self.scan.maxIndex,nearLimit=self.scan.nearLimit,full=self.scan.full}or nil,scanError=self.scanError}
end
return M

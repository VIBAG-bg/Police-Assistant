-- One routine clock, main() only. Emergency reports and binders share its queue.
local core=require 'pa26_core'
local M={};local Patrol={};Patrol.__index=Patrol
local function valid(s)return s and s.session and s.ped and s.alive==true and s.onDuty==true and s.radioEnabled==true end
local function safe(s)return valid(s) and s.focused==true and s.paused==false and s.blocked==false and
    s.typing~=true and s.recording~=true and s.editingHud~=true and s.draggingHud~=true end
local function canTick(s,countDuringInput)
    return valid(s)and s.focused==true and s.paused==false and not s.patrolSuspended and(countDuringInput~=false or safe(s))
end
function M.new(env)return setmetatable({env=env,remaining=nil,active=false,cycle=0},Patrol)end
function Patrol:reset()
    if self.currentKey and self.env.drop then self.env.drop(self.currentKey)end
    self.cycle=self.cycle+1;self.currentKey=nil;self.state=nil;self.anchor=nil;self.lastNow=nil;self.remaining=nil;self.active=false;self.signature=nil;self.phase='off';self.error=nil;self.loggedError=nil
end
function Patrol:problem(reason,cfg,stage)
    local raw=type(reason)=='string'and reason~=''and reason or'Подготовка доклада не удалась: обработчик не передал причину.'
    if not core.validUtf8(raw)then raw='Причина получена в неподдерживаемой кодировке; проверьте журнал PA.'end
    self.error=raw:gsub('%c',' '):gsub('%s+',' '):match('^%s*(.-)%s*$')
    local detail='Периодический доклад: '..raw..' [режим='..tostring(cfg.mode)..'; канал='..tostring(cfg[cfg.mode..'_channel'])..
        '; интервал='..tostring(cfg[cfg.mode..'_interval_ms'])..' мс; этап='..tostring(stage)..']'
    if detail~=self.loggedError and self.env.log then pcall(self.env.log,detail)end
    self.loggedError=detail
end
function Patrol:tick(state,now)
    local cfg=self.env.settings();local kind=cfg.mode;local interval=cfg[kind..'_interval_ms']
    if not cfg.enabled then self:reset();return end
    if core.elapsed(now,now)==nil then self.lastNow=nil;self.phase='paused';return end
    if not valid(state)or state.patrolSuspended then self.state=state;self.lastNow=now;self.phase='paused';return end
    local signature=table.concat({kind,tostring(interval),tostring(cfg.confirmation),cfg[kind..'_channel'],cfg[kind..'_template'],cfg.post,cfg.session_key or ''},'\0')
    local dt=self.lastNow and core.elapsed(now,self.lastNow)
    local anchor=self.anchor
    local changed=not anchor or anchor.session~=state.session or anchor.demo~=state.demo or self.signature~=signature or
        (anchor.ped~=state.ped and not(state.local_nick and state.local_nick~=''and state.local_nick==anchor.local_nick))
    if changed then
        if self.currentKey and self.env.drop then self.env.drop(self.currentKey)end
        self.remaining=interval;self.cycle=self.cycle+1;self.currentKey=nil;self.error=nil;self.loggedError=nil
    end
    -- Input postpones delivery, not the clock. Focus/pause and stalls do not
    -- invent elapsed time or create a catch-up burst.
    local policy=not self.env.clockPolicy or self.env.clockPolicy()~=false
    if not changed and canTick(state,policy)and canTick(self.state,policy)and dt and dt<=5000 then self.remaining=math.max(0,self.remaining-dt)end
    self.state=state;self.anchor=state;self.lastNow=now;self.signature=signature;self.active=true;self.interval=interval
    self.phase=not canTick(state,policy)and'paused'or self.remaining>0 and'countdown'or'waiting'
    local key='patrol:'..kind..':'..self.cycle
    if self.env.preview and self.remaining<=(self.env.lead and self.env.lead()or 30000)then
        self.currentKey=key
        local phase,err=self.env.preview(key,cfg,self.remaining)
        if phase=='cancelled' or phase=='invalid' or phase=='unavailable' or phase=='sent' or phase=='handed'then
            if self.env.retire then self.env.retire(key)end
            self.remaining=interval;self.cycle=self.cycle+1;self.currentKey=nil;self.phase='countdown'
            if phase=='invalid'or phase=='unavailable'then self:problem(err,cfg,phase)
            else self.error=nil;self.loggedError=nil end
            return
        end
        if phase=='confirm'then self.phase='confirmation';self.error=nil;self.loggedError=nil;return end
        if phase=='queued'then self.phase='sending';self.error=nil;self.loggedError=nil;return end
    end
    local pending=self.env.pending and self.env.pending()
    if pending and pending.kind==kind then self.phase='confirmation';return end
    if self.remaining>0 or not safe(state) or state.busy or state.wheel or pending then return end
    if self.env.ready and not self.env.ready(key)then self.phase='prewarning';return end
    local ok,err=self.env.dispatch(kind,cfg.confirmation,key)
    if ok==true then
        -- The occurrence remains cancellable through confirmation and the
        -- global send interval. Restart only after its terminal outcome.
        if self.env.preview then self.phase=cfg.confirmation and 'confirmation' or 'sending';self.error=nil;return end
        if self.env.retire then self.env.retire(key)end
        self.remaining=interval;self.cycle=self.cycle+1;self.currentKey=nil;self.phase=cfg.confirmation and 'confirmation' or 'sending';self.error=nil
    else
        -- Invalid/missing text is displayed and retried no more than once per
        -- interval, rather than flooding chat/logs every frame.
        if self.env.retire then self.env.retire(key)end
        self.remaining=interval;self.cycle=self.cycle+1;self.currentKey=nil;self.phase='error'
        self:problem(err,cfg,'dispatch')
    end
end
function Patrol:view()
    local cfg=self.env.settings()
    if not cfg.hud or not self.active then return {visible=false} end
    local label=cfg.mode=='police' and 'Патруль' or 'Охрана тюрьмы'
    local phase=self.phase
    local warning=self.currentKey and self.env.view and self.env.view(self.currentKey)
    local remaining=warning and math.max(self.remaining,warning.lead)or self.remaining
    local status=phase=='confirmation' and 'Подтвердите доклад · Y / N' or phase=='paused' and 'Доклад: таймер на паузе' or
        phase=='waiting' and 'Доклад ожидает свободную очередь' or phase=='sending' and 'Передача доклада…' or
        self.error and('Проверьте настройки доклада ('..self.error..')') or 'До доклада: '..string.format('%02d:%02d',math.floor(self.remaining/60000),math.ceil(self.remaining/1000)%60)
    local seconds=math.max(0,math.ceil(remaining/1000))
    if phase=='countdown' and not self.error then status=string.format('До доклада: %02d:%02d',math.floor(seconds/60),seconds%60)end
    if phase=='prewarning'then status='Доклад: ожидает предупреждения/очереди'end
    return {visible=true,label=label,status=status,remaining=remaining,interval=self.interval,
        progress=math.max(0,math.min(1,1-self.remaining/self.interval)),phase=phase,error=self.error}
end
M.safe=safe;M.canTick=canTick
return M

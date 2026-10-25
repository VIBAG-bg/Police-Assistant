-- Every scheduled IC line owns a cancellable occurrence before entering the
-- shared executor. Rendering only acknowledges a visible preview; never sends.
local core=require 'pa26_core'
local mapGrid=require 'pa26_map_grid'
local model=require 'pa26_bindings'
local prefs=require 'pa26_preferences'
local radio=require 'pa26_radio_text'
local M={};local Guard={};Guard.__index=Guard
local function lead(cfg,spec)return math.min(cfg.lead_ms,spec.interval_ms or cfg.lead_ms)end
function M.safe(s)
    return s and s.session and core.finite(s.ped) and s.alive==true and s.onDuty==true and s.radioEnabled==true and
        s.focused==true and s.paused==false and s.blocked==false and s.typing~=true and s.recording~=true and
        s.editingHud~=true and s.draggingHud~=true and not s.alertPending and not s.modal
end
local function identity(s,template)
    local out={};for key in pairs(prefs.radioVariables)do if key~='area'and key~='duration'and key~='direction'and key~='map_square'and key~='location'and key~='square'then out[#out+1]=key..'='..tostring(s[key] or '')end end
    table.sort(out);return table.concat(out,'\0')
end
local function signature(spec,s)
    return table.concat({spec.name,spec.template,spec.channel,tostring(spec.confirmation),tostring(spec.interval_ms),identity(s,spec.template),mapGrid.reportPolicy(s,spec.template)},'\0')
end
function M.prepare(spec,s,codec,now,life)
    local template,err=prefs.template(spec.template,prefs.radioVariables);if not template then return nil,err end
    if spec.channel~='/r' and spec.channel~='/f' and spec.channel~='/d' then return nil,'Канал автодоклада: /r, /f или /d.'end
    local source=mapGrid.reportValues(s,template)
    local values={}
    for key in pairs(prefs.radioVariables)do
        local used=template:find('{'..key..'}',1,true)
        local v='';if used then v=model.clean(source[key] or '',key:match('^crew')and 4096 or(key=='area'or key=='location')and 1024 or 240)end
        if not v then return nil,'Неверное поле: '..key end
        local tag=key=='local_tag' or key=='prison_tag' or key=='global_tag'
        if v=='' and not tag and template:find('{'..key..'}',1,true) then return nil,'Заполните поле: '..key end
        values[key]=tag and v~='' and v..' ' or v
    end
    local line=spec.channel..' '..template:gsub('{([a-z_]+)}',function(key)return values[key]end):match('^%s*(.-)%s*$')
    local prepared;prepared,err=radio.prepare(spec.channel,line:sub(#spec.channel+2),codec,s.radioText,s.rpText,s.my_nick);if not prepared then return nil,err end
    local binding=model.newBinding(999999997);binding.name=spec.name;binding.category='Автодоклады';binding.script=line
    return {binding=binding,requirements={target=false,closest=false},session=s.session,createdAt=now,demo=s.demo,
        has_command=true,steps=prepared.steps,lines=prepared.lines,wire=prepared.wires,textSignature=prepared.textSignature,rpSignature=prepared.rpSignature,
        automatic={kind='auto_report',life=life,ped=s.ped}}
end
function M.new(env)return setmetatable({env=env,life=1,serial=0,tickets={},jobs={}},Guard)end
function M.patrolSpec(cfg)
    local kind=cfg.mode
    return {source='patrol',kind=kind,name=kind=='police' and 'Патруль · рация' or 'Охрана тюрьмы · рация',
        template=cfg[kind..'_template'],channel=cfg[kind..'_channel'],interval_ms=cfg[kind..'_interval_ms'],confirmation=cfg.confirmation}
end
function Guard:currentSpec(t)
    if t.spec.source=='patrol' and self.env.patrol then
        local cfg=self.env.patrol();if not cfg.enabled or cfg.mode~=t.spec.kind then return nil end
        return M.patrolSpec(cfg)
    elseif t.spec.source=='custom' then
        for _,r in ipairs(self.env.settings().custom)do if r.id==t.spec.id and r.enabled then local spec=model.copy(r);spec.source='custom';return spec end end
        return nil
    end
    return t.spec
end
function Guard:retire(key)
    local t=self.tickets[key];if t then t.released=true end
end
function Guard:reset()
    self.life=self.life+1;self.tickets={};self.jobs={};self.state=nil;self.now=nil;self.latest=nil
end
function Guard:find(token)
    for _,t in pairs(self.tickets)do if t.token==token then return t end end
end
function Guard:finish(t,phase,reason)
    if not t or t.phase=='sent' or t.phase=='cancelled' or t.phase=='handed' then return false end
    t.phase=phase;t.reason=reason
    if phase=='cancelled' and self.env.cancel then self.env.cancel(t.token)end
    return true
end
function Guard:cancel(token)
    local t=token and self:find(token) or self:first()
    return self:finish(t,'cancelled','Ближайший доклад пропущен.')
end
function Guard:track(key,spec,remaining)
    local s=self.state;local cfg=self.env.settings()
    if not s or not core.finite(remaining) then return 'unavailable' end
    local t=self.tickets[key];local sig=signature(spec,s)
    if t and t.signature~=sig then self:finish(t,'cancelled','Данные доклада изменились.');return 'cancelled' end
    if not t then
        -- Producers have at most one occurrence; completed old cycles are pruned.
        local count=0;for k,old in pairs(self.tickets)do
            if old.released and(old.phase=='sent' or old.phase=='handed' or old.phase=='cancelled')then self.tickets[k]=nil else count=count+1 end
        end
        if count>=20 then return 'unavailable','Слишком много ожидающих докладов.'end
        local plan,err=M.prepare(spec,s,self.env.codec,self.now,self.life)
        if not plan then return 'invalid',err end
        self.serial=self.serial+1
        t={key=key,token='radio:'..self.life..':'..self.serial,order=self.serial,spec=model.copy(spec),signature=sig,phase='pending',
            createdAt=self.now,lead=lead(cfg,spec),remaining=remaining,plan=plan,seen=false,bodyAt=self.now}
        self.tickets[key]=t
    elseif t.phase=='pending' or t.phase=='confirm' then
        local plan,err=M.prepare(spec,s,self.env.codec,self.now,self.life)
        if not plan then self:finish(t,'cancelled',err);return 'invalid',err end
        if radio.key(plan)~=radio.key(t.plan) then t.bodyAt=self.now;t.paintedWire=nil;t.accepted=nil end
        t.plan=plan;t.remaining=remaining
    end
    return t.phase,nil,t
end
function Guard:ready(key)
    local t=self.tickets[key]
    local age=t and t.paintedAt and core.elapsed(self.now,t.paintedAt)
    return t and t.phase=='pending' and t.seen and t.lead<=0 and t.remaining<=0 and
        age and age<=math.max(250,self.dt or 0)+50 and t.paintedWire==radio.key(t.plan) and M.safe(self.state) or false
end
function Guard:shown(token)
    local t=self:find(token)
    if t and(t.phase=='pending' or t.phase=='confirm' or t.phase=='queued')then
        local gap=t.paintedAt and core.elapsed(self.now,t.paintedAt)
        if t.phase=='pending'and gap and gap>5000 then t.lead=lead(self.env.settings(),t.spec);t.seen=false;t.toastAt=nil end
        if not t.seen then t.seen=true;t.toastAt=self.now end
        t.paintedWire=radio.key(t.plan);t.paintedAt=self.now
    end
end
function Guard:dispatch(key)
    local t=self.tickets[key]
    if not self:ready(key) then return nil,'Предупреждение ещё не завершено.'end
    if self.state.busy or self.state.wheel or self.state.alertPending or self.state.reloadPending then return nil,'Очередь занята.'end
    if t.spec.confirmation and not t.accepted then t.phase='confirm';t.confirmAt=nil;t.seen=false;return true,'confirmation' end
    local plan,err=M.prepare(t.spec,self.state,self.env.codec,self.now,self.life)
    if not plan then self:finish(t,'cancelled',err);return nil,err end
    if radio.key(plan)~=t.paintedWire then return nil,'Предпросмотр обновляется.'end
    plan.radioGuard={token=t.token,signature=t.signature,life=self.life}
    t.plan=plan;t.phase='queued'
    local ok;ok,err=self.env.start(plan)
    if not ok then self:finish(t,'cancelled',err or 'Доклад не запущен.')end
    return ok,err
end
function Guard:handoff(key)
    local t=self.tickets[key];if not self:ready(key)then return false end
    t.phase='handed';return true
end
function Guard:decide(token,yes)
    local t=self:find(token);if not t or t.phase~='confirm' or not M.safe(self.state) or self.state.alertPending then return false end
    if not yes then return self:cancel(token)end
    if t.paintedWire~=radio.key(t.plan)then return false end
    t.accepted=true;t.phase='pending';return true
end
function Guard:tick(state,now)
    local previous=self.state;local dt=self.now and core.elapsed(now,self.now)
    if not core.finite(now) or now~=math.floor(now)then self:reset();return end
    if previous and(not dt or previous.session~=state.session or previous.ped~=state.ped or previous.demo~=state.demo or previous.alive~=state.alive)then self:reset();previous=nil;dt=nil end
    self.state=state;self.now=now
    self.dt=dt
    if self.env.uiAvailable and not self.env.uiAvailable()then self:reset();self.state=state;self.now=now;return end
    if not state.session or not state.ped or not state.alive or not state.onDuty or not state.radioEnabled then self:reset();self.state=state;self.now=now;return end
    local cfg=self.env.settings();local changed=self.cfgSignature and self.cfgSignature~=table.concat({cfg.lead_ms,cfg.toast_ms},':')
    self.cfgSignature=table.concat({cfg.lead_ms,cfg.toast_ms},':')
    for _,t in pairs(self.tickets)do
        if changed then self:finish(t,'cancelled','Настройки предупреждения изменились.')end
        local current=self:currentSpec(t)
        if not current or signature(current,state)~=t.signature then self:finish(t,'cancelled','Доклад отключён или данные изменились.')end
        if t.phase=='pending' or t.phase=='confirm' then
            if previous and not M.safe(previous) and M.safe(state)then t.lead=lead(cfg,t.spec);t.seen=false;t.toastAt=nil;t.confirmAt=nil;t.paintedWire=nil;t.accepted=nil;t.phase='pending'end
            if dt and dt>5000 then t.lead=lead(cfg,t.spec);t.seen=false;t.toastAt=nil;t.paintedWire=nil end
            if t.seen and dt and dt<=5000 and M.safe(state)and M.safe(previous)then t.lead=math.max(0,t.lead-dt)end
            if t.phase=='confirm' and t.seen then
                t.confirmAt=t.confirmAt or now
                if core.elapsed(now,t.confirmAt)>=15000 then self:cancel(t.token)end
            end
        end
    end
    local active={}
    for _,row in ipairs(cfg.custom)do if row.enabled then
        local spec=model.copy(row);spec.source='custom'
        local key='custom:'..spec.id;active[key]=true
        local sig=signature(spec,state);local job=self.jobs[key]
        local decremented=false
        if not job or job.signature~=sig then
            if job and job.token then local old=self:find(job.token);self:cancel(job.token);if old then self:retire(old.key)end end
            job={signature=sig,remaining=spec.interval_ms,cycle=(job and job.cycle or 0)+1};self.jobs[key]=job
        elseif dt and dt<=5000 and M.safe(state)and M.safe(previous)and not job.token then job.remaining=math.max(0,job.remaining-dt);decremented=true end
        if job.remaining<=cfg.lead_ms or job.token then
            local occurrence=key..':'..job.cycle
            local phase,err,t=self:track(occurrence,spec,job.remaining)
            if t then job.token=t.token end
            if phase=='cancelled' or phase=='sent' or phase=='handed' or phase=='invalid' or phase=='unavailable' then
                self.tickets[occurrence]=nil
                job.remaining=spec.interval_ms;job.cycle=job.cycle+1;job.token=nil
                if err and self.env.log then self.env.log('Автодоклад: '..err)end
            elseif t and t.phase=='confirm' then
                -- Its explicit Y/N owns the next transition.
            elseif t then
                if not decremented and dt and dt<=5000 and M.safe(state)and M.safe(previous)then job.remaining=math.max(0,job.remaining-dt);t.remaining=job.remaining end
                if self:ready(occurrence)then self:dispatch(occurrence)end
            end
        end
    end end
    for key,job in pairs(self.jobs)do if not active[key]then
        if job.token then local old=self:find(job.token);self:cancel(job.token);if old then self:retire(old.key)end end
        self.jobs[key]=nil
    end end
    for key,t in pairs(self.tickets)do if t.released and(t.phase=='sent'or t.phase=='cancelled'or t.phase=='handed')then self.tickets[key]=nil end end
end
function Guard:validPlan(plan)
    local mark=plan.radioGuard;if not mark then return true end
    local t=self:find(mark.token)
    if not t or t.phase~='queued' or mark.life~=self.life or mark.signature~=t.signature or not M.safe(self.state)then return false end
    local spec=self:currentSpec(t);if not spec then return false end
    if t.started then return signature(spec,self.state)==t.signature and radio.key(plan)==radio.key(t.plan)end
    local paintedAge=t.paintedAt and core.elapsed(self.now,t.paintedAt)
    if not paintedAge or paintedAge>math.max(250,self.dt or 0)+50 then return false end
    local current=M.prepare(spec,self.state,self.env.codec,self.now,self.life)
    return current and signature(spec,self.state)==t.signature and radio.key(current)==radio.key(plan) and t.paintedWire==radio.key(plan) or false
end
function Guard:onExecution(kind,q)
    local mark=q and q.plan and q.plan.radioGuard;if not mark then return end
    local t=self:find(mark.token);if not t then return end
    if kind=='sent_line' or kind=='preview_line' then
        if q.plan.steps and q.index and q.index<#q.plan.steps then t.started=true;return end
        t.phase='sent'
    elseif kind=='cancelled' then self:finish(t,'cancelled','Отправка остановлена; повтора нет.')end
end
function Guard:candidates()
    local out={};local cfg=self.env.settings()
    for _,t in pairs(self.tickets)do if t.phase=='pending' or t.phase=='queued' or t.phase=='confirm' then
        local remaining=math.max(t.remaining,t.lead)
        local full=not t.toastAt or (core.elapsed(self.now,t.toastAt)or 0)<cfg.toast_ms or t.phase=='confirm'
        out[#out+1]={owner='radio',token=t.token,title=t.phase=='confirm' and 'Передать доклад?'or t.spec.name,
            body=table.concat(t.plan.lines,'\n'),mode=t.phase=='confirm' and 'confirm' or 'radio',full=full,unseen=not t.seen,
            priority=t.phase=='confirm' and 70 or 40,serial=t.order,remaining=remaining,
            status=t.phase=='queued' and 'Ожидает отправки · ещё можно отменить' or not M.safe(self.state)and 'Отсчёт на паузе' or
                remaining>0 and ('Доклад через '..math.ceil(remaining/1000)..' с')or 'Ожидает свободную очередь',
            hint=(t.spec.template:find('{area}',1,true)or t.spec.template:find('{location}',1,true))and('Место на момент отправки: '..tostring(mapGrid.reportValues(self.state,t.spec.template)[t.spec.template:find('{location}',1,true)and 'location'or 'area'] or 'не определено'))or 'Текст и канал из сохранённых настроек',
            yes='Передать',no='Отменить',shortcut=cfg.skip_shortcut}
    end end
    table.sort(out,function(a,b)if a.remaining==b.remaining then return a.serial<b.serial end;return a.remaining<b.remaining end)
    return out
end
function Guard:first()
    local c=self:candidates()[1];return c and self:find(c.token)
end
function Guard:view()
    local t=self:first();if not t then return {visible=false}end
    return {visible=true,token=t.token,name=t.spec.name,remaining=math.max(t.remaining,t.lead),phase=t.phase}
end
return M

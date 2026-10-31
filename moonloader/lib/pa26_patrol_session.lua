-- Explicit local service session. A report reaching the client is not a server
-- success. No chat parsing, automatic accusations, global player scan or retry.
local core=require 'pa26_core'
local mapGrid=require 'pa26_map_grid'
local model=require 'pa26_bindings'
local settings=require 'pa26_patrol_settings'
local store=require 'pa26_library'
local radio=require 'pa26_radio_text'
local M={};local Session={};Session.__index=Session
-- Read once outside draw. PID plus process creation time distinguishes a PA
-- reload from a new GTA process, even if Windows reuses the PID.
-- https://learn.microsoft.com/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocesstimes
function M.clientInstance(ffi)
    if not ffi or ffi.os~='Windows'then return nil end
    for _,declaration in ipairs({'void* __stdcall GetCurrentProcess(void);',
        'unsigned long __stdcall GetCurrentProcessId(void);',
        'int __stdcall GetProcessTimes(void*,void*,void*,void*,void*);'})do pcall(ffi.cdef,declaration)end
    local ok,key=pcall(function()
        local k=ffi.load('kernel32');local created=ffi.new('unsigned long[2]')
        local exited,cpu,user=ffi.new('unsigned long[2]'),ffi.new('unsigned long[2]'),ffi.new('unsigned long[2]')
        if k.GetProcessTimes(k.GetCurrentProcess(),created,exited,cpu,user)==0 then return nil end
        return string.format('%.0f:%08x%08x',tonumber(k.GetCurrentProcessId()),tonumber(created[1]),tonumber(created[0]))
    end)
    return ok and key or nil
end
local function baseSafe(s)
    return s and s.session and core.finite(s.ped)and s.alive==true and s.focused==true and s.paused==false and
        s.blocked==false and s.onDuty==true and s.radioEnabled==true and s.recording~=true and s.editingHud~=true and s.draggingHud~=true
end
local function safe(s)return baseSafe(s)and not s.typing and not s.modal end
function M.defaults()return {schema=1,next_id=1,history={}}end
local function record(raw)
    if type(raw)~='table'or not settings.integer(raw.id,1,999999998)or not settings.integer(raw.elapsed_ms,0,31536000000)or
        not settings.array(raw.crew,8)or type(raw.demo)~='boolean'then return nil end
    if raw.unit_auto~=nil and type(raw.unit_auto)~='boolean'or raw.unit_number~=nil and not settings.integer(raw.unit_number,1,999)then return nil end
    if raw.last_tick~=nil and core.elapsed(raw.last_tick,raw.last_tick)==nil then return nil end
    local instance=settings.text(raw.client_instance or '',96);if not instance then return nil end
    local out={client_instance=instance,last_tick=raw.last_tick,id=raw.id,elapsed_ms=raw.elapsed_ms,demo=raw.demo,crew={},unit_auto=raw.unit_auto==true,unit_number=raw.unit_number or 1}
    for _,key in ipairs({'server','local_nick','officer','callsign','mode','station','unit','vehicle','sector','post','started','ended','reason','report_status','status'})do
        out[key]=settings.text(raw[key]or '',240);if not out[key]then return nil end
    end
    if out.status~='active'and out.status~='paused'and out.status~='finished'and out.status~='interrupted'then return nil end
    if out.mode~='police'and out.mode~='prison'and out.mode~='foot'then return nil end
    local seen={}
    for _,r in ipairs(raw.crew)do
        if type(r)~='table'or not settings.integer(r.contact_id,1,999999999)or seen[r.contact_id]then return nil end
        seen[r.contact_id]=true;local v={contact_id=r.contact_id}
        for _,k in ipairs({'nickname','ic_name','callsign','role'})do v[k]=settings.text(r[k]or '',120);if not v[k]then return nil end end
        if v.nickname==''or v.ic_name==''then return nil end
        out.crew[#out.crew+1]=v -- Native IDs never survive a restart.
    end
    return out
end
function M.validate(raw)
    if type(raw)~='table'or raw.schema~=1 or not settings.integer(raw.next_id,1,999999999)or not settings.array(raw.history,50)then return nil,'Повреждён журнал патрулей.'end
    local out=M.defaults();out.next_id=raw.next_id;local ids={}
    for _,r in ipairs(raw.history)do
        local v=record(r);if not v or v.id>=out.next_id or ids[v.id]or(v.status~='finished'and v.status~='interrupted')then return nil,'Неверный итог патруля.'end
        ids[v.id]=true;out.history[#out.history+1]=v
    end
    if raw.active~=nil then
        out.active=record(raw.active)
        if not out.active or out.active.id>=out.next_id or ids[out.active.id]or(out.active.status~='active'and out.active.status~='paused')then return nil,'Неверный сохранённый патруль.'end
    end
    return out
end
function M.new(env)
    local data,warnings,fresh=M.defaults(),{},true
    if env.path then data,warnings,fresh=store.load(env.path,env.json,M.validate,M.defaults,env.fs)end
    local self=setmetatable({env=env,data=data,warnings=warnings,revision=1,serial=0,generations={},dirty=false},Session)
    self.clientInstance=env.clientInstance
    if data.active then
        self.resumeWasActive=data.active.status=='active'
        self.recoverable=data.active;data.active=nil;self.recoverable.status='paused'
        self.recoverable.reason='PA был перезапущен. Проверьте состав и продолжите вручную.'
    end
    return self
end
function Session:note(message)self.message=message;if self.env.log then self.env.log(message)end end
function Session:changed()self.revision=self.revision+1;self.dirty=true end
function Session:save(force)
    if not self.dirty or not self.env.path then return true end
    local age=self.savedAt and core.elapsed(self.now,self.savedAt)
    if not force and age and age<15000 then return end
    self.savedAt=self.now
    local data=model.copy(self.data);data.active=data.active or self.recoverable
    local ok,err=store.save(self.env.path,data,self.env.json,M.validate,self.env.fs)
    if ok then self.dirty=false;self.saveError=nil else self.saveError=err end
    return ok,err
end
function Session:cancelQueued(reason)
    local queued=self.queued;self.queued=nil;self.intent=nil
    if queued and self.data.active then
        self.data.active.report_status='Доклад отменён · без повтора';self.awaitingReport=false;self.dirty=true
    end
    if queued and self.env.cancel then self.env.cancel(queued.token,reason)end
end
function Session:pause(reason)
    local a=self.data.active;if not a then return false end
    reason=reason or 'Пауза по вашему решению.'
    if a.status=='paused'and a.reason==reason and not self.queued and not self.intent then return true end
    self:cancelQueued(reason);a.status='paused';a.reason=reason
    self:changed();self.lastNow=self.now;self:save(true);return true
end
function Session:archive(reason,status)
    local a=self.data.active or self.recoverable;if not a then return false end
    self:cancelQueued(reason);a.status=status or 'finished';a.reason=reason or '';a.ended=self.env.date and self.env.date()or ''
    self.data.history[#self.data.history+1]=a;if #self.data.history>50 then table.remove(self.data.history,1)end
    self.data.active=nil;self.recoverable=nil;self:changed();self:save(true);return true
end
function Session:interrupt(reason)
    if self.data.active then self:archive(reason or 'Игровая сцена изменилась.','interrupted')end
end
function Session:playerChanged(id)
    if not core.validId(id)then return end
    self.generations[id]=(self.generations[id]or 0)+1
    local a=self.data.active
    if a then for _,r in ipairs(a.crew)do if r.player_id==id then
        r.available=false;r.issue='Игрок вышел или его ID был выдан заново.'
        self:cancelQueued(r.issue);self:changed()
        if self.env.settings().pause_on_crew_change then self:pause(r.issue)end
    end end end
end
function Session:collectCrew(cfg)
    local out={};local contacts=self.env.contacts()
    for _,r in ipairs(cfg.crew)do
        local contact;for _,p in ipairs(contacts)do if p.id==r.contact_id then contact=p;break end end
        if not contact then return nil,'Контакт экипажа удалён. Обновите состав.'end
        if r.ic_name==''then return nil,'Укажите IC-имя напарника '..contact.nickname..'. Ник сам по себе не подтверждает имя.'end
        local found=self.env.resolve(contact.nickname,cfg.bind_distance)
        if not found or not core.validId(found.id)or type(found.name)~='string'or found.name:lower()~=contact.nickname:lower()then return nil,'Напарник '..contact.nickname..' должен быть виден рядом для проверки ID.'end
        out[#out+1]={contact_id=r.contact_id,nickname=found.name,ic_name=r.ic_name,callsign=contact.callsign,role=r.role,
            player_id=found.id,generation=self.generations[found.id]or 0,available=true}
    end
    return out
end
function Session:crewText(a)
    local names={a.officer..(a.callsign~=''and(' ('..a.callsign..')')or '')}
    for _,r in ipairs(a.crew)do
        if r.available~=false then names[#names+1]=r.ic_name..(r.callsign~=''and(' ('..r.callsign..')')or '')end
    end
    return table.concat(names,', '),#names
end
function Session:values(s,a,override)
    if type(s)~='table'or a~=nil and type(a)~='table'then return nil,'Нет данных сеанса патруля для доклада.'end
    local out=model.copy(s);if not a then return out end
    local profile=self.env.profile()or{}
    local cfg=override or self.env.settings()
    if type(profile)~='table'or type(cfg)~='table'or cfg.grammar~=nil and type(cfg.grammar)~='table'then return nil,'Проверьте профиль и формы фраз патруля.'end
    if type(a.officer)~='string'or type(a.callsign)~='string'or type(a.crew)~='table'or not core.finite(a.elapsed_ms)then return nil,'Повреждены данные экипажа патруля.'end
    for _,row in ipairs(a.crew)do if type(row)~='table'or type(row.ic_name)~='string'or type(row.callsign)~='string'or type(row.role)~='string'then return nil,'Повреждены данные напарника в патруле.'end end
    for key,fallback in pairs({city='не определён',direction='не определено',map_square='не определён',rank='сотрудник'})do
        if out[key]==nil or out[key]==''then out[key]=profile[key]and profile[key]~=''and profile[key]or fallback end
    end
    for _,k in ipairs({'officer','callsign','station','unit','vehicle','sector','post'})do out[k]=a[k]end
    local count=settings.crewCount(s,a.crew)
    out.unit_crew_count=tostring(count)
    if a.unit_auto then out.unit=settings.autoUnit(profile,s,count,a.unit_number)end
    local grammar=cfg.grammar or settings.grammarDefaults();local form=count>=2 and'team'or'solo'
    for _,key in ipairs({'start','resume','finish','moving','available'})do
        if type(grammar[key..'_'..form])~='string'then return nil,'Проверьте форму фразы патруля: '..key..'_'..form end
        out['patrol_'..key]=core.expandGender(grammar[key..'_'..form],s.gender or profile.gender)
    end
    out.crew,out.crew_count=self:crewText(a);out.crew_count=tostring(out.crew_count)
    local roles={a.officer};local callsigns={}
    if a.callsign~=''then callsigns[#callsigns+1]=a.callsign end
    for _,r in ipairs(a.crew)do if r.available~=false then
        roles[#roles+1]=r.ic_name..' · '..r.role
        if r.callsign~=''then callsigns[#callsigns+1]=r.callsign end
    end end
    out.crew_roles=table.concat(roles,', ');out.crew_callsigns=table.concat(callsigns,', ')
    out.duration=settings.duration(a.elapsed_ms);out.patrol_id=tostring(a.id)
    return out
end
function Session:makeRecord(cfg,s)
    local profile=self.env.profile();local officer=settings.text(profile.name or '',120)
    if not officer or officer==''then return nil,'Заполните ваше IC-имя в профиле. Игровой ник не используется как паспортные данные.'end
    local crew,err=self:collectCrew(cfg);if not crew then return nil,err end
    if self.data.next_id>=999999999 then return nil,'Достигнут предел номеров патрулей.'end
    local a={id=self.data.next_id,server=s.session,local_nick=s.local_nick or '',officer=officer,callsign=profile.callsign,
        client_instance=self.clientInstance or'',last_tick=self.now,demo=s.demo,elapsed_ms=0,status='active',report_status='Ожидает доклада',crew=crew,started=self.env.date and self.env.date()or '',ended='',reason=''}
    for _,k in ipairs({'mode','station','unit','vehicle','sector','post'})do a[k]=cfg[k]end
    a.unit_auto=cfg.unit=='';a.unit_number=cfg.unit_number or 1
    if a.unit_auto then a.unit=settings.autoUnit(profile,s,settings.crewCount(s,crew),a.unit_number)end
    if a.station==''then a.station=s.colleagues and s.colleagues.station or profile.department or'EPD'end
    return a
end
function Session:prepareLine(action,a,s,cfg)
    if type(action)~='string'or type(cfg)~='table'then return nil,'Проверьте действие и настройки доклада патруля.'end
    local values,err=self:values(s,a,cfg);if not values then return nil,err end
    local template=cfg[action..'_template'];local checked;checked,err=settings.template(template)
    if not checked then return nil,err end
    checked,err=require('pa26_report_context').directionTemplate(checked,values)
    if not checked then return nil,err end
    values,err=mapGrid.reportValues(values,checked);if not values then return nil,err end
    local missing
    local body=core.expandGender(checked,s.gender):gsub('{([a-z_]+)}',function(key)
        if values[key]~=nil and type(values[key])~='string'and not core.finite(values[key])then missing=key;return ''end
        local v=settings.text(tostring(values[key]or ''),1024)
        local tag=key=='local_tag'or key=='prison_tag'or key=='global_tag'
        if not v or v==''and not tag then missing=key;return ''end
        return tag and v~=''and(v..' ')or v
    end):match('^%s*(.-)%s*$')
    if missing then return nil,'Заполните поле доклада: '..missing end
    return radio.prepare(cfg.channel,body,self.env.codec,s.radioText,s.rpText,s.my_nick)
end
function Session:propose(action)
    local cfg=self.env.settings();local s=self.state
    if action~='discard'and not cfg.enabled then return nil,'Включите сеансы патруля в настройках.'end
    if action~='discard'and(self.suspended or not baseSafe(s))then return nil,'Нужны живой персонаж, служебный режим и доступная рация.'end
    s=s or {}
    local a=self.data.active
    if action=='start'then
        if a or self.recoverable then return nil,'Сначала завершите или восстановите прежний патруль.'end
        local err;a,err=self:makeRecord(cfg,s);if not a then return nil,err end
    elseif action=='restore'then
        if a or not self.recoverable then return nil,'Нет сохранённого сеанса.'end
        a=model.copy(self.recoverable)
        if a.server~=s.session or a.local_nick~=(s.local_nick or '')or a.demo~=s.demo then return nil,'Сохранённый патруль относится к другому серверу, персонажу или режиму.'end
        local err;a.crew,err=self:collectCrew(cfg);if not a.crew then return nil,err end
        a.status='active';a.reason=''
    elseif action=='discard'then
        a=a or self.recoverable;if not a then return nil,'Нет патруля для завершения.'end
        a=model.copy(a)
    elseif action=='resume'or action=='crew'or action=='finish'then
        if not a then return nil,'Патруль ещё не начат.'end
        if action=='resume'and a.status~='paused'then return nil,'Патруль уже активен.'end
        a=model.copy(a)
        if action~='finish'then
            local err;a.crew,err=self:collectCrew(cfg);if not a.crew then return nil,err end
            for _,k in ipairs({'station','unit','vehicle','sector','post'})do a[k]=cfg[k]end
        end
    else return nil,'Неизвестное действие патруля.'end
    if action=='restore'or action=='resume'or action=='crew'then
        a.unit_auto=cfg.unit=='';a.unit_number=cfg.unit_number or 1
        if a.unit_auto then a.unit=settings.autoUnit(self.env.profile(),s,settings.crewCount(s,a.crew),a.unit_number)else a.unit=cfg.unit end
        if a.station==''then a.station=s.colleagues and s.colleagues.station or self.env.profile().department or'EPD'end
    end
    local line,err
    local noReport=cfg.reporter_self==false
    if action~='discard'and not noReport then line,err=self:prepareLine(action=='restore'and 'resume'or action,a,s,cfg);if not line then return nil,err end end
    self.serial=self.serial+1
    return {token=self.serial,action=action,record=a,line=line and line.line,wire=line and line.wire,
        prepared=line,no_report=noReport,revision=self.revision,at=self.now,session=s.session,ped=s.ped,demo=s.demo,
        cfg=model.copy(cfg),profile=model.copy(self.env.profile()),area=s.area}
end
function Session:proposalValid(p)
    local age=p and core.elapsed(self.now,p.at)
    if not p or p.revision~=self.revision or not age or age>60000 then return false end
    if p.action=='discard'then return (self.data.active or self.recoverable)~=nil end
    if self.suspended or not baseSafe(self.state)or
        self.state.session~=p.session or self.state.ped~=p.ped or self.state.demo~=p.demo then return false end
    local cfg=self.env.settings()
    -- A fresh proposal is required after changing any form/template/roster field.
    if not self.env.equal(cfg,p.cfg)or not self.env.equal(self.env.profile(),p.profile)then return false end
    local template=p.action~='discard'and cfg[(p.action=='restore'and 'resume'or p.action)..'_template']or ''
    if not p.no_report and not p.started then
        local fresh=self:prepareLine(p.action=='restore'and 'resume'or p.action,p.record,self.state,cfg)
        if not fresh or radio.key(fresh)~=radio.key(p.prepared)then return false end
    end
    for _,r in ipairs(p.record.crew)do
        if r.available~=false then
            local found=self.env.observe(r.player_id)
            if r.generation~=(self.generations[r.player_id]or 0)or not found or not found.connected or found.name~=r.nickname then return false end
        end
    end
    return true
end
function Session:accept(proposal)
    if self.intent or self.queued then return nil,'Доклад патруля уже ожидает отправки.'end
    if not self:proposalValid(proposal)then return nil,'Состав, настройки или игровая ситуация изменились. Проверьте доклад заново.'end
    self.intent=model.copy(proposal);return true -- No send from GUI.
end
function Session:validPlan(plan)
    local p=self.queued
    if not p or not plan.patrolSession or plan.patrolSession.token~=p.token or not safe(self.state)then return false end
    return self:proposalValid(p)and radio.key(plan)==table.concat(p.prepared.wires,'\0')
end
function Session:dispatch()
    local p=self.intent;if not p then return end
    if not self:proposalValid(p)then self.intent=nil;self:note('Доклад отменён: данные изменились.');return end
    if p.action~='discard'and(not safe(self.state)or self.state.busy or self.state.alertPending or self.state.wheel)then return end
    self.intent=nil
    if p.action=='discard'then self:archive('Завершён вручную без доклада.');return end
    if p.no_report then
        self.data.active=model.copy(p.record)
        if p.action=='start'then self.data.next_id=self.data.next_id+1 end
        if p.action=='restore'then self.recoverable=nil end
        self.data.active.status='active';self.data.active.reason='';self.data.active.report_status='Рацию ведёт напарник · без отправки PA'
        self.awaitingReport=false;self:changed();self:save(true)
        if p.action=='finish'then self:archive('Завершён локально · рацию ведёт напарник.')end
        return
    end
    local binding=model.newBinding(999999996);binding.name='Патруль · '..p.action;binding.category='Служба';binding.script=p.line
    local plan={binding=binding,requirements={target=false,closest=false},session=p.session,createdAt=self.now,demo=p.demo,
        has_command=true,steps=model.copy(p.prepared.steps),lines=model.copy(p.prepared.lines),wire=model.copy(p.prepared.wires),
        textSignature=p.prepared.textSignature,rpSignature=p.prepared.rpSignature,
        automatic={kind='patrol_session'},patrolSession={token=p.token}}
    self.queued=p
    local ok,err=self.env.start(plan)
    if not ok then self.queued=nil;self:note('Доклад не запущен: '..tostring(err));return end
    -- Local service begins on confirmed action. Radio delivery is a separate field.
    if p.action=='start'then self.data.active=model.copy(p.record);self.data.next_id=self.data.next_id+1
    elseif p.action=='restore'then self.data.active=model.copy(p.record);self.recoverable=nil
    elseif p.action~='finish'then self.data.active=model.copy(p.record)end
    local a=self.data.active;a.status=p.action=='finish'and a.status or 'active';a.reason='';a.report_status='В очереди'
    self:changed();p.revision=self.revision;self.queued=p
    self.awaitingReport=true;self:save(true)
end
function Session:onExecution(kind,q)
    local p=self.queued;local mark=q and q.plan and q.plan.patrolSession
    if not p or not mark or mark.token~=p.token then return end
    local a=self.data.active
    if kind=='sent_line'or kind=='preview_line'then
        if q.plan.steps and q.index and q.index<#q.plan.steps then
            p.started=true
            if a then a.report_status='Доклад передаётся · '..q.index..' / '..#q.plan.steps end
            return
        end
        if a then a.report_status=kind=='sent_line'and 'Передан клиенту'or 'Демо · не отправлен'end
        self.awaitingReport=false
        self.queued=nil
        if p.action=='finish'then self:archive('Завершён после подтверждения доклада.')else self:changed()end
        self:save(true)
    elseif kind=='cancelled'then
        self.queued=nil;self.awaitingReport=false
        if a then a.report_status='Доклад отменён · без повтора';self:changed()end
    end
end
function Session:effectivePatrol(legacy)
    local cfg=self.env.settings();local a=self.data.active
    if not cfg.enabled and not a and not self.recoverable then return legacy end
    local out=model.copy(legacy);out.enabled=cfg.enabled and cfg.reporter_self~=false and a~=nil and a.status=='active'and cfg.periodic and not self.awaitingReport
    out.mode=a and a.mode=='prison'and 'prison'or 'police';out.hud=cfg.hud;out.confirmation=cfg.confirmation
    out.session_key=a and tostring(a.id)or 'idle';out.post=a and a.post or cfg.post
    for _,kind in ipairs({'police','prison'})do out[kind..'_interval_ms']=cfg.interval_ms;out[kind..'_channel']=cfg.channel;out[kind..'_template']=cfg.periodic_template end
    return out
end
function Session:restoreLocal(state,now,cfg)
    local a=self.recoverable
    local age=a and a.last_tick and core.elapsed(now,a.last_tick)
    if not a or not self.resumeWasActive or not cfg.auto_resume_reload or not cfg.enabled or
        type(self.clientInstance)~='string'or self.clientInstance==''or a.client_instance~=self.clientInstance or
        not age or age>cfg.reload_grace_ms or state.alive~=true or not core.finite(state.ped)or state.onDuty~=true or state.radioEnabled~=true or state.session~=a.server or
        type(state.local_nick)~='string'or state.local_nick==''or state.local_nick~=a.local_nick then return false end
    local roster=model.copy(cfg);roster.crew={}
    for _,r in ipairs(a.crew)do
        local contact;for _,p in ipairs(self.env.contacts())do if p.id==r.contact_id and p.nickname==r.nickname then contact=p end end
        if not contact then return false end
        roster.crew[#roster.crew+1]={contact_id=r.contact_id,ic_name=r.ic_name,role=r.role}
    end
    local crew=self:collectCrew(roster);if not crew then return false end
    a.crew=crew;a.status='active';a.reason='';a.demo=state.demo
    a.report_status='Патруль восстановлен · прежние доклады не повторяются'
    self.data.active=a;self.recoverable=nil;self.resumeWasActive=nil
    self.intent=nil;self.queued=nil;self.awaitingReport=false;self:changed()
    return true
end
function Session:recoverUi(wasActive)
    self:cancelQueued('Окно PA восстановлено. Прежний доклад не повторяется.')
    local a=self.data.active
    if a and wasActive and a.status=='paused'and a.reason=='Доклад не передан. Проверьте ситуацию и продолжите вручную.'then
        a.status='active';a.reason='';self:changed()
    end
end
function Session:tick(state,now)
    state=state or{}
    if core.elapsed(now,now)==nil then
        self.state=model.copy(state);self.suspended=true;self.suspendedReason='Нет достоверного времени игры.'
        self.lastNow=nil;self.previousTrusted=false;self:cancelQueued('Таймер недоступен. Подтверждение нужно подготовить заново.');return
    end
    local previous=self.state;local dt=self.lastNow and core.elapsed(now,self.lastNow)
    self.now=now;self.state=model.copy(state)
    if self.lastNow and not dt then
        dt=0;self.previousTrusted=false
        self:cancelQueued('Отсчёт времени переустановлен. Прежний доклад не повторяется.');self:changed()
    end
    local cfg=self.env.settings();local restored=self:restoreLocal(state,now,cfg)
    local a=self.data.active;local trusted=false
    self.suspended=false;self.suspendedReason=nil
    if a and state.respawnConfirmed then self:interrupt('Подтверждён респавн персонажа.');a=nil end
    if a then
        if type(state.demo)=='boolean'and a.demo~=state.demo then
            self:cancelQueued('Режим изменён. Прежний доклад не повторяется.')
            a.demo=state.demo;self:changed()
        end
        local nick=state.local_nick
        local cause=type(state.session)=='string'and state.session~=''and state.session~=a.server and('server:'..state.session)or
            type(nick)=='string'and nick~=''and nick~=a.local_nick and('character:'..nick)or nil
        trusted=not cause and state.session==a.server and type(nick)=='string'and nick~=''and nick==a.local_nick and
            core.finite(state.ped)and state.alive==true
        if not trusted then
            self.suspended=true;self.suspendedReason='Ожидаю достоверные данные персонажа · время сохранено'
            self:cancelQueued('Данные персонажа временно недоступны. Прежний доклад не повторяется.')
        end
        if cause then
            local c=self.interruptCandidate
            if not c or c.cause~=cause then c={cause=cause,elapsed=0};self.interruptCandidate=c
            elseif dt and dt<=5000 then c.elapsed=c.elapsed+dt end
            if c.elapsed>=cfg.interrupt_grace_ms then
                self:interrupt('Подтверждена смена сервера или персонажа.');a=nil
            end
        else self.interruptCandidate=nil end
        if a and(not cfg.enabled or state.onDuty==false or state.radioEnabled==false)then
            local reason='Сеанс или служебная связь отключены.'
            if a.status~='paused'or a.reason~=reason or self.queued then self:pause(reason)end
        elseif a and a.status=='active'and trusted and self.previousTrusted and not restored and dt and dt<=5000 and
            previous and previous.focused and state.focused and not previous.paused and not state.paused then
            a.elapsed_ms=math.min(31536000000,a.elapsed_ms+dt);self.dirty=true
        end
        if a and trusted then
            a.client_instance=self.clientInstance or'';a.last_tick=now
            if not self.pollAt or(core.elapsed(now,self.pollAt)or 1000)>=1000 then
                self.pollAt=now
                for _,r in ipairs(a.crew)do if r.available~=false then
                    local found=self.env.observe(r.player_id)
                    if not found or found.connected~=true or found.name~=r.nickname or r.generation~=(self.generations[r.player_id]or 0)then
                        r.available=false;r.issue='Напарник недоступен. Перепроверьте состав.';self:changed();self:cancelQueued(r.issue)
                        if cfg.pause_on_crew_change then self:pause(r.issue)end
                    end
                end end
            end
        end
    else self.interruptCandidate=nil end
    self.previousTrusted=trusted;self.lastNow=now;self:dispatch()
    if not a and self.data.active then self.previousTrusted=baseSafe(state)and state.local_nick==self.data.active.local_nick end
    self:save(false)
end
function Session:view(timer)
    local a=self.data.active;local cfg=self.env.settings();local out={active=a and model.copy(a),recoverable=self.recoverable and model.copy(self.recoverable),
        enabled=cfg.enabled,message=self.message,saveError=self.saveError,history=model.copy(self.data.history),pending=self.intent~=nil or self.queued~=nil}
    if not a then return out end
    local crew,count=self:crewText(a);out.crew=crew;out.duration=settings.duration(a.elapsed_ms)
    out.hud={visible=cfg.hud,label=(a.status=='paused'and 'Патруль · пауза'or 'Патруль')..' '..out.duration,
        status=self.suspended and self.suspendedReason or a.status=='paused'and a.reason or timer and timer.visible and timer.status or a.report_status,
        crew='Экипаж: '..count..' · '..a.unit,remaining=timer and timer.remaining or 0,interval=timer and timer.interval or cfg.interval_ms,
        progress=timer and timer.progress or 0,phase=a.status}
    return out
end
M.safe=safe
return M

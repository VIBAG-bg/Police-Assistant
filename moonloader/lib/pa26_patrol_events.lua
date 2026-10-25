-- Attempts, explicitly acknowledged facts and radio delivery are separate.
-- No server-success regexes: actual server reply adapters need verified samples.
local core=require 'pa26_core'
local mapGrid=require 'pa26_map_grid'
local model=require 'pa26_bindings'
local shared=require 'pa26_patrol_settings'
local prefs=require 'pa26_patrol_event_settings'
local store=require 'pa26_library'
local radio=require 'pa26_radio_text'
local noticeSafe=require('pa26_notifications').safe
local M={};local Events={};Events.__index=Events
local kinds={};for _,r in ipairs(prefs.catalog)do kinds[r[1]]=true end
local function reportContext(state,template)
    local parts={}
    for key in pairs(shared.variables)do
        if key~='area'and key~='map_square'and key~='location'and key~='square'and key~='duration'and key~='direction'and template:find('{'..key..'}',1,true)then parts[#parts+1]=key..'='..tostring(state[key]or '')end
    end
    table.sort(parts);return table.concat(parts,'\0')
end
function M.defaults()return {schema=1,next_id=1,events={},facts={},reports={}}end
function M.validate(raw)
    if type(raw)~='table'or raw.schema~=1 or not shared.integer(raw.next_id,1,999999999)or not shared.array(raw.events,300)then return nil,'Повреждён журнал событий патруля.'end
    local out=M.defaults();out.next_id=raw.next_id;local ids={}
    for _,r in ipairs(raw.events)do
        if type(r)~='table'or not shared.integer(r.id,1,out.next_id-1)or ids[r.id]or not kinds[r.kind]or
            type(r.demo)~='boolean'or r.source~='manual'or not shared.integer(r.patrol_id,0,999999999)then return nil,'Неверный факт в журнале патруля.'end
        local v={id=r.id,kind=r.kind,demo=r.demo,source='manual',patrol_id=r.patrol_id}
        for _,k in ipairs({'name','date','server','local_nick','subject','basis','destination','details','attempt','report_status','report_line'})do
            v[k]=shared.text(r[k]or '',k=='attempt'and 512 or 768);if not v[k]then return nil,'Повреждён текст события.'end
        end
        if v.report_status~='local'and v.report_status~='pending'and v.report_status~='client'and v.report_status~='demo'and v.report_status~='cancelled'then return nil,'Неверный статус передачи.'end
        if v.report_status=='pending'then v.report_status='cancelled'end -- Never restore an old outgoing action.
        ids[r.id]=true;out.events[#out.events+1]=v
    end
    for _,key in ipairs({'facts','reports'})do
        if type(raw[key])~='table'then return nil,'Повреждены счётчики событий.'end
        for k,n in pairs(raw[key])do if not kinds[k]or not shared.integer(n,0,999999999)then return nil,'Неверный счётчик события.'end;out[key][k]=n end
    end
    return out
end
local function safe(s)
    return s and s.session and s.alive==true and core.finite(s.ped)and s.focused==true and s.paused==false and
        s.blocked==false and not s.recording and not s.editingHud and not s.draggingHud
end
function M.new(env)
    local data,warnings=M.defaults(),{}
    if env.path then data,warnings=store.load(env.path,env.json,M.validate,M.defaults,env.fs)end
    return setmetatable({env=env,data=data,warnings=warnings,attempts={},serial=0,life=1,used={},
        queues=setmetatable({},{__mode='k'}),followups={},dirty=false},Events)
end
function Events:save(force)
    if not self.dirty or not self.env.path then return true end
    local age=self.savedAt and core.elapsed(self.now,self.savedAt)
    if not force and age and age<15000 then return end
    self.savedAt=self.now
    local ok,err=store.save(self.env.path,self.data,self.env.json,M.validate,self.env.fs)
    if ok then self.dirty=false;self.saveError=nil else self.saveError=err end
    return ok,err
end
function Events:cancelReport(reason)
    local q=self.queued;self.queued=nil;self.intent=nil
    if q then
        q.event.report_status='cancelled';self.dirty=true
        if self.env.cancel then self.env.cancel(q.token,reason)end
    end
end
function Events:reset(reason)
    self:cancelReport(reason);self.life=self.life+1;self.attempts={};self.followups={};self.used={};self.lastCommand=nil;self.lastFact=nil;self.reviewRequested=nil
end
local function followupSignature(cfg)
    return table.concat({tostring(cfg.followup_enabled),tostring(cfg.rights_reminder_enabled),tostring(cfg.force_reminder_enabled),tostring(cfg.remind_clear),
        cfg.followup_ms,cfg.followup_ttl_ms,cfg.followup_snooze_ms,cfg.followup_limit,cfg.followup_title,cfg.rights_reminder,cfg.force_reminder,cfg.clear_reminder},'\0')
end
function Events:addFollowup(e,p)
    local cfg=self.env.settings()
    if not cfg.followup_enabled or e.demo then return end
    local kind,body
    if e.kind=='detention'and cfg.rights_reminder_enabled then kind='rights';body=cfg.rights_reminder
    elseif e.kind=='force_used'and cfg.force_reminder_enabled then kind='force';body=cfg.force_reminder
    elseif e.kind=='jail'and cfg.remind_clear and cfg.clear_reminder~=''then kind='clear';body=cfg.clear_reminder end
    if not kind then return end
    -- The trigger is the separately confirmed manual fact, never the outgoing command.
    for i=#self.followups,1,-1 do local r=self.followups[i]
        if r.kind==kind and r.stamp==p.form.target_stamp and r.subject==p.form.subject then table.remove(self.followups,i)end
    end
    self.followups[#self.followups+1]={token='patrol-followup:'..self.life..':'..e.id,kind=kind,body=body,event=e.name,
        subject=p.form.subject,target=model.copy(p.form.target),stamp=p.form.target_stamp,at=self.now,due=self.now,
        remaining=cfg.followup_ms,serial=e.id,signature=followupSignature(cfg)}
    while #self.followups>cfg.followup_limit do table.remove(self.followups,1)end
end
function Events:followup(token)
    for _,r in ipairs(self.followups)do if r.token==token then return r end end
end
local function noticeSignature(cfg,row)
    return table.concat({tostring(cfg.toast_enabled),cfg.toast_mode,tostring(cfg.toast_ms),cfg.toast_title,cfg.toast_template,cfg.toast_hint,
        tostring(cfg.suggest_commands),row.command,row.name,tostring(row.enabled),tostring(row.suggest)},'\0')
end
function Events:available()
    local cfg=self.env.settings();local a=self.env.patrol()
    return cfg.enabled and safe(self.state)and(not cfg.require_patrol or a~=nil)
end
function Events:targetStamp()return self.env.targetStamp and self.env.targetStamp()or 0 end
function Events:command(line,origin,target)
    local state=self.state;local cfg=self.env.settings()
    -- onSendCommand can arrive before the chat closes. Observation is allowed
    -- there; showing a prompt, confirming a fact and sending still require safe().
    if not cfg.enabled or not cfg.suggest_commands or not state or state.demo or not state.session or not state.alive or
        not core.finite(state.ped)or not state.focused or state.paused or(cfg.require_patrol and not self.env.patrol())then return false end
    if type(line)~='string'or line:sub(1,1)~='/'then return false end
    line=shared.text(line,512);if not line then return false end
    local command,tail=line:match('^/([A-Za-z][A-Za-z0-9_]*)(.*)$')
    if tail and tail~=''and not tail:match('^%s')then return false end
    command=command and command:lower()
    if not command or command:match('^pa26')then return false end
    local matches={}
    for _,row in ipairs(prefs.catalog)do local c=cfg.events[row[1]];if c.enabled and c.suggest and c.command==command then matches[#matches+1]=row[1]end end
    if #matches==0 then return false end
    local key=line..'\0'..tostring(target and target.id or '')..'\0'..tostring(target and target.name or '')
    local elapsed=self.lastCommand and core.elapsed(self.now,self.lastCommand.at)
    if self.lastCommand and self.lastCommand.key==key and elapsed and elapsed<500 then return false end
    self.lastCommand={key=key,at=self.now}
    for _,kind in ipairs(matches)do
        self.serial=self.serial+1
        self.attempts[#self.attempts+1]={id=self.serial,kind=kind,line=line,origin=origin or 'Введено вручную',
            target=target and model.copy(target),target_stamp=self:targetStamp(),at=self.now,life=self.life,patrol_id=self.env.patrol()and self.env.patrol().id or 0,
            notice_token='patrol-attempt:'..self.life..':'..self.serial,notice_remaining=cfg.toast_ms,
            notice_signature=noticeSignature(cfg,cfg.events[kind]),notice_dismissed=not cfg.toast_enabled}
    end
    while #self.attempts>20 do table.remove(self.attempts,1)end
    return true
end
function Events:onExecution(kind,q)
    if kind=='sent_line'and q and not q.demo and not q.plan.automatic and not q.plan.alert then
        local step=q.plan.steps[q.index];local seen=self.queues[q]or {};self.queues[q]=seen
        if step and step.kind=='message'and not seen[q.index]then
            seen[q.index]=true;self:command(step.text,'Биндер · передано клиенту',q.plan.target)
        end
    end
    local p=self.queued;local mark=q and q.plan and q.plan.patrolEvent
    if not p or not mark or mark.token~=p.token then return end
    if kind=='sent_line'or kind=='preview_line'then
        p.sent_any=true
        if q.plan.steps and q.index and q.index<#q.plan.steps then return end
        p.event.report_status=kind=='sent_line'and 'client'or 'demo'
        if kind=='sent_line'and not p.event.demo then self.data.reports[p.event.kind]=math.min(999999999,(self.data.reports[p.event.kind]or 0)+1)end
        self.queued=nil;self.dirty=true;self:save(true)
    elseif kind=='cancelled'then self:cancelReport('Передача события отменена.');self:save(true)end
end
function Events:attempt(id)
    for _,a in ipairs(self.attempts)do if a.id==id and a.life==self.life and not a.confirmed then return a end end
end
function Events:form(kind,attemptId)
    local cfg=self.env.settings();local row=cfg.events[kind]
    if not self:available()or not row or not row.enabled then return nil,'Событие недоступно. Включите события и проверьте сеанс патруля.'end
    local a=attemptId and self:attempt(attemptId)
    if attemptId and(not a or a.kind~=kind)then return nil,'Попытка устарела или уже подтверждена.'end
    if a and a.target and a.target_stamp~=self:targetStamp()then return nil,'Выбор человека изменился после команды. Создайте новое событие с проверенной целью.'end
    self.serial=self.serial+1
    local target;if a then target=model.copy(a.target)else target=self.env.target()end
    return {id=self.serial,kind=kind,attempt_id=attemptId,target=target,
        subject='',basis='',destination='',details='',acknowledged=false,life=self.life,base_id=self.data.next_id,target_stamp=self:targetStamp()}
end
function Events:bindTarget(form)
    if not self:available()or not form or form.life~=self.life or form.base_id~=self.data.next_id or self.used[form.id]then
        return nil,'Сначала создайте доступную форму события.'
    end
    local attempt=form.attempt_id and self:attempt(form.attempt_id)
    if form.attempt_id and(not attempt or attempt.target)then return nil,'Для этой попытки нельзя заменить запомненную цель. Создайте новое событие.'end
    local target=self.env.target()
    if not target or not self.env.validTarget(target)then return nil,'Сначала выберите доступного человека рядом.'end
    form.target=model.copy(target);form.target_stamp=self:targetStamp();form.target_manual=true
    return true
end
function Events:line(form,cfg)
    local row=cfg.events[form.kind];if not row then return nil,'Неизвестное событие.'end
    local template,err=prefs.template(row.template);if not template then return nil,err end
    local values=model.copy(self.state or {})
    for _,k in ipairs({'subject','basis','destination','details'})do
        values[k]=shared.text(form[k]or '',240);if not values[k]then return nil,'Неверный текст: '..k end
    end
    values=mapGrid.reportValues(values,template)
    local missing
    local body=template:gsub('{([a-z_]+)}',function(k)
        local v=shared.text(tostring(values[k]or ''),1024);local tag=k=='local_tag'or k=='prison_tag'or k=='global_tag'
        if not v or v==''and not tag then missing=k;return ''end
        return tag and v~=''and(v..' ')or v
    end)
    if missing then return nil,'Заполните поле доклада: '..missing end
    return radio.prepare(row.channel,body,self.env.codec,self.state.radioText,self.state.rpText,self.state.my_nick)
end
function Events:propose(form,report)
    local cfg=self.env.settings();local row=form and cfg.events[form.kind]
    if not self:available()or not row or not row.enabled or form.life~=self.life or form.base_id~=self.data.next_id or self.used[form.id]then return nil,'Форма или игровой контекст устарели.'end
    if not form.acknowledged then return nil,'Подтвердите факт выполнения. Команда сама по себе его не доказывает.'end
    local attempt=form.attempt_id and self:attempt(form.attempt_id)
    if form.attempt_id and not attempt then return nil,'Попытка устарела или уже учтена.'end
    if row.require_target then
        if form.target_stamp~=self:targetStamp()or not form.target or not self.env.validTarget(form.target)then return nil,'Выбранный человек изменился или недоступен.'end
    end
    local copy=model.copy(form)
    for _,k in ipairs({'subject','basis','destination','details'})do copy[k]=shared.text(copy[k]or '',240);if not copy[k]then return nil,'Проверьте текст события.'end end
    if copy.kind~='custom'and copy.subject==''then return nil,'Укажите IC-имя или известные приметы. Ник не подставляется как IC-имя.'end
    local line,err;if report then
        if not self.state.onDuty or not self.state.radioEnabled then return nil,'Служебная рация отключена. Можно записать факт без доклада.'end
        line,err=self:line(copy,cfg);if not line then return nil,err end
    end
    local a=self.env.patrol();local fingerprint=table.concat({copy.kind,copy.subject,copy.basis,copy.destination,copy.details,
        tostring(copy.target and copy.target.id or ''),tostring(copy.target and copy.target.name or '')},'\0')
    local gap=self.lastFact and core.elapsed(self.now,self.lastFact.at)
    if self.lastFact and self.lastFact.key==fingerprint and gap and gap<cfg.duplicate_ms then return nil,'Такой факт только что записан. Двойной учёт остановлен.'end
    return {token='event:'..self.life..':'..copy.id,form=copy,at=self.now,life=self.life,session=self.state.session,ped=self.state.ped,
        demo=self.state.demo,patrol_id=a and a.id or 0,fingerprint=fingerprint,report=report==true,line=line and line.line,wire=line and line.wire,
        prepared=line,cfg=model.copy(cfg),area=self.state.area,context=reportContext(self.state,row.template)}
end
function Events:proposalValid(p)
    local age=p and core.elapsed(self.now,p.at);local a=self.env.patrol()
    if not p or p.life~=self.life or not age or age>60000 or not self:available()or p.session~=self.state.session or
        p.ped~=self.state.ped or p.demo~=self.state.demo or p.patrol_id~=(a and a.id or 0)or not self.env.equal(p.cfg,self.env.settings())then return false end
    if not p.committed and(p.form.base_id~=self.data.next_id or p.form.attempt_id and not self:attempt(p.form.attempt_id))then return false end
    if p.cfg.events[p.form.kind].require_target and(p.form.target_stamp~=self:targetStamp()or not self.env.validTarget(p.form.target))then return false end
    if p.report then
        if not self.state.onDuty or not self.state.radioEnabled then return false end
        local row=p.cfg.events[p.form.kind]
        if not p.sent_any then
            local fresh=self:line(p.form,p.cfg)
            if not fresh or radio.key(fresh)~=radio.key(p.prepared)then return false end
        end
        if reportContext(self.state,row.template)~=p.context then return false end
    end
    return true
end
function Events:accept(p)
    if self.intent or self.queued then return nil,'Дождитесь текущего доклада события.'end
    if self.used[p and p.form.id]or not self:proposalValid(p)then return nil,'Данные события изменились. Подготовьте подтверждение снова.'end
    self.intent=model.copy(p);return true
end
function Events:validPlan(plan)
    local p=self.queued
    return p and plan.patrolEvent and p.token==plan.patrolEvent.token and self:proposalValid(p)and
        not self.state.typing and not self.state.modal and radio.key(plan)==table.concat(p.prepared.wires,'\0')or false
end
function Events:dispatch()
    local p=self.intent;if not p then return end
    if not self:proposalValid(p)then self.intent=nil;self.message='Подтверждение события отменено: контекст изменился.';return end
    if self.state.typing or self.state.modal or self.state.recording then return end
    self.intent=nil
    if self.data.next_id>=999999999 then self.message='Журнал достиг предела номеров.';return end
    local row=p.cfg.events[p.form.kind]
    local e={id=self.data.next_id,kind=p.form.kind,name=row.name,demo=p.demo,source='manual',patrol_id=p.patrol_id,
        date=self.env.date and self.env.date()or '',server=p.session,local_nick=self.state.local_nick or '',
        attempt=p.form.attempt_id and self:attempt(p.form.attempt_id).line or '',report_status=p.report and 'pending'or 'local',report_line=p.line or ''}
    for _,k in ipairs({'subject','basis','destination','details'})do e[k]=p.form[k]end
    self.data.next_id=self.data.next_id+1;self.data.events[#self.data.events+1]=e
    if #self.data.events>300 then table.remove(self.data.events,1)end
    if not p.demo then self.data.facts[e.kind]=math.min(999999999,(self.data.facts[e.kind]or 0)+1)end
    if p.form.attempt_id then self:attempt(p.form.attempt_id).confirmed=true end
    self.used[p.form.id]=self.now;self.lastFact={key=p.fingerprint,at=self.now};self.dirty=true
    self.message='Факт записан по вашему подтверждению'..(p.demo and ' · демо, без статистики.'or '.')
    if e.kind=='jail'and p.cfg.remind_clear and p.cfg.clear_reminder~=''then self.message=self.message..' '..p.cfg.clear_reminder end
    self:addFollowup(e,p)
    if p.report then p.committed=true;p.event=e;self.queued=p end
    self:save(true)
end
function Events:sendQueued()
    local p=self.queued;if not p or p.started then return end
    if not self:proposalValid(p)then self:cancelReport('Доклад устарел. Факт остался в журнале.');return end
    if self.state.busy or self.state.alertPending or self.state.wheel or self.state.typing or self.state.modal then return end
    local b=model.newBinding(999999995);b.name='Событие · '..p.event.name;b.category='Служба';b.script=p.line
    local plan={binding=b,requirements={target=false,closest=false},session=p.session,createdAt=self.now,demo=p.demo,
        has_command=true,steps=model.copy(p.prepared.steps),lines=model.copy(p.prepared.lines),wire=model.copy(p.prepared.wires),rpSignature=p.prepared.rpSignature,textSignature=p.prepared.textSignature,
        automatic={kind='patrol_event'},patrolEvent={token=p.token}}
    p.started=true
    local ok,err=self.env.start(plan)
    if not ok then self:cancelReport('Доклад не запущен.');self.message='Факт сохранён, доклад не передан: '..tostring(err)end
end
function Events:tick(state,now)
    local previous=self.state;local previousNow=self.now;local dt=self.now and core.elapsed(now,self.now)
    if not core.finite(now)or now~=math.floor(now)then self:reset('Таймер изменился.');return end
    self.state=model.copy(state);self.now=now
    if previous and(not dt or previous.session~=state.session or previous.ped~=state.ped or previous.demo~=state.demo or
        previous.local_nick~=state.local_nick or previous.alive~=state.alive or previous.patrol_id~=state.patrol_id)then self:reset('Сцена патруля изменилась.')end
    local cfg=self.env.settings()
    if not cfg.enabled then
        if self.enabled~=false then self:reset('События отключены.')end
        self.enabled=false;self:save(false);return
    end
    self.enabled=true
    for i=#self.followups,1,-1 do local r=self.followups[i]
        local age=core.elapsed(now,r.at)
        if not age or age>=cfg.followup_ttl_ms or not cfg.followup_enabled or r.signature~=followupSignature(cfg)or
            r.stamp~=self:targetStamp()or r.target and not self.env.validTarget(r.target)then table.remove(self.followups,i)
        elseif r.painted==previousNow and dt and dt<=5000 and noticeSafe(previous)and noticeSafe(state)then
            r.remaining=math.max(0,r.remaining-dt)
            if r.remaining<=0 then table.remove(self.followups,i)end
        end
    end
    for id,at in pairs(self.used)do local age=core.elapsed(now,at);if not age or age>60000 then self.used[id]=nil end end
    for i=#self.attempts,1,-1 do local a=self.attempts[i];local age=core.elapsed(now,a.at)
        if not age or age>cfg.attempt_ttl_ms or a.confirmed then table.remove(self.attempts,i)
        else
            if a.notice_signature~=noticeSignature(cfg,cfg.events[a.kind])or a.target_stamp~=self:targetStamp()or
                a.target and not self.env.validTarget(a.target)then a.notice_dismissed=true end
            if not a.notice_dismissed and a.notice_painted==previousNow and dt and dt<=5000 and noticeSafe(previous)and noticeSafe(state)then
                a.notice_remaining=math.max(0,a.notice_remaining-dt)
                if a.notice_remaining<=0 then a.notice_dismissed=true end
            end
        end
    end
    self:dispatch();self:sendQueued();self:save(false)
end
function Events:notice(token)
    for _,a in ipairs(self.attempts)do if a.notice_token==token and not a.notice_dismissed and not a.confirmed then return a end end
end
function Events:shown(token)
    local r=self:followup(token);if r then r.seen=true;r.painted=self.now;return end
    local a=self:notice(token);if a then a.notice_seen=true;a.notice_painted=self.now end
end
function Events:decideNotice(token,yes)
    local r=self:followup(token)
    if r then
        local cfg=self.env.settings();local age=core.elapsed(self.now,r.at);local due=core.elapsed(self.now,r.due)
        if type(yes)~='boolean'or not r.seen or not self:available()or not noticeSafe(self.state)or not age or age>=cfg.followup_ttl_ms or
            not due or r.stamp~=self:targetStamp()or r.signature~=followupSignature(cfg)or r.target and not self.env.validTarget(r.target)then return false end
        if yes then for i,v in ipairs(self.followups)do if v==r then table.remove(self.followups,i);break end end
        else r.due=self.now+cfg.followup_snooze_ms;r.remaining=cfg.followup_ms;r.seen=nil;r.painted=nil end
        return true
    end
    local a=self:notice(token)
    if type(yes)~='boolean'or not a or not self:available()or not noticeSafe(self.state)or not a.notice_seen or
        a.notice_signature~=noticeSignature(self.env.settings(),self.env.settings().events[a.kind])or a.target_stamp~=self:targetStamp()or
        a.target and not self.env.validTarget(a.target)then return false end
    a.notice_dismissed=true
    if yes then self.reviewRequested={kind=a.kind,attempt=a.id}end
    return true
end
function Events:takeNoticeReview()
    local request=self.reviewRequested;self.reviewRequested=nil
    if not request then return end
    return self:form(request.kind,request.attempt)
end
function Events:candidates()
    local cfg=self.env.settings();local out={}
    if not self:available()then return out end
    for _,r in ipairs(self.followups)do if core.elapsed(self.now,r.due)then
        out[#out+1]={owner='patrol',token=r.token,title=cfg.followup_title,body=r.body..'\nЧеловек: '..r.subject,
            hint='Готово — скрыть; Позже — напомнить через '..math.floor(cfg.followup_snooze_ms/1000)..' с. Команда и доклад не отправляются.',
            status=r.event..' · вы подтвердили событие',mode='action',full=true,unseen=not r.seen,priority=15,
            serial=r.serial,remaining=r.remaining,duration=cfg.followup_ms,yes='Готово',no='Позже',shortcut={key=0,ctrl=false,alt=false,shift=false}}
    end end
    for _,a in ipairs(self.attempts)do if cfg.toast_enabled and not a.notice_dismissed and not a.confirmed and a.notice_remaining>0 then
        local row=cfg.events[a.kind]
        out[#out+1]={owner='patrol',token=a.notice_token,title=cfg.toast_title,
            body=prefs.noticePreview(cfg.toast_template,{command=a.line,event=row.name,origin=a.origin,
                target=a.target and(a.target.name..' ['..a.target.id..']')or 'цель не была выбрана'}),
            hint=cfg.toast_hint,status=row.name,mode=cfg.toast_mode=='confirm'and 'confirm'or 'action',full=true,
            unseen=not a.notice_seen,priority=20,serial=a.id,remaining=a.notice_remaining,duration=cfg.toast_ms,
            yes='Проверить',no='Позже',shortcut={key=0,ctrl=false,alt=false,shift=false}}
    end end
    return out
end
function Events:view()
    return {attempts=model.copy(self.attempts),events=model.copy(self.data.events),facts=model.copy(self.data.facts),reports=model.copy(self.data.reports),
        message=self.message,saveError=self.saveError,pending=self.intent~=nil or self.queued~=nil}
end
M.safe=safe
return M

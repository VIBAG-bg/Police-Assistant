-- Coordinates the library, previews and journal. process() is called only by main.
local model=require 'pa26_bindings'
local binder=require 'pa26_binder'
local store=require 'pa26_library'
local execution=require 'pa26_executor'
local journalModule=require 'pa26_journal'
local core=require 'pa26_core'
local targetModule=require 'pa26_target'
local operationsModule=require 'pa26_operations'
local userFiles=require 'pa26_user_files'
local M={}; local Workspace={}; Workspace.__index=Workspace
local function names(nick)
    local full=nick:gsub('_',' '); local first,last=full:match('^(%S+)%s+(.*)$'); return full,first or full,last or ''
end
function M.new(env,cfg,base)
    local self=setmetatable({env=env,cfg=cfg,base=base,pending=nil,selectedTarget=nil,status='Готово.',commandDirty=true,libraryRevision=0},Workspace)
    self.json={encode=env.encodeJson,decode=env.decodeJson}
    local notes,fresh
    self.userFiles=userFiles.new(base,self.json,self.cfg)
    self.library,notes,fresh=self.userFiles:load()
    self.libraryFresh=fresh; self.warnings=notes
    self.targets=targetModule.new({inspect=env.inspectSelected,event=function(kind,target,reason)
        self.selectedTarget=self.targets.target
        if kind~='selected' then
            local q=self.executor and self.executor.queue
            local independent=(q and (q.plan.alert or q.plan.automatic)) or
                (self.pending and self.pending.plan and (self.pending.plan.alert or self.pending.plan.automatic))
            if not independent then self:cancel('Выбор человека изменился. Сценарий остановлен.') end
        end
        if env.targetEvent then env.targetEvent(kind,target,reason) end
    end})
    local data,jnotes=store.load(base..'_journal.json',self.json,journalModule.validate,journalModule.defaults)
    for _,note in ipairs(jnotes) do self.warnings[#self.warnings+1]=note end
    self.journal=journalModule.new(data)
    self.operations=operationsModule.new({settings=function()return self.library.operations end,
        path=base..'_operations.json',json=self.json})
    for _,note in ipairs(self.operations.warnings)do self.warnings[#self.warnings+1]=note end
    local demoSent
    self.executor=execution.new({context=env.context,now=env.now,validate=function(t) return env.validate(t,self.cfg.main.max_distance) end,
        demo=env.demo,send=env.send,pressed=env.pressed,down=env.down,sound=env.sound,planValid=env.planValid,
        clearTarget=function() self:clearTarget('manual') end,
        lastSent=function() return env.demo() and demoSent or env.lastSent() end,
        markSent=function(now,demo) if demo then demoSent=now else env.markSent(now) end end,
        event=function(kind,q,reason)
            local observed=reason
            if kind=='sent_line'and self.operationLineOverride~=nil then observed=self.operationLineOverride end
            self.operations:onExecution(kind,q,observed)
            if env.executionEvent then pcall(env.executionEvent,kind,q,reason) end
            if kind=='completed' or kind=='cancelled' then self.journal:record(q,kind,reason); self.status=self.executor.status
                env.log(kind=='cancelled' and ('[СЦЕНАРИЙ ОСТАНОВЛЕН] '..tostring(reason)) or '[СЦЕНАРИЙ] '..self.status)
            elseif kind=='preview_line' then env.log('[ДЕМО БИНД] '..reason)
            elseif kind=='sent_line' then env.log('[ПЕРЕДАНО ЧАТУ] '..reason) end
        end})
    return self
end
function Workspace:selectTarget(target)
    return self.targets:select(target,self.env.context().session)
end
function Workspace:clearTarget(reason) self.targets:clear(reason) end
function Workspace:refreshTarget()
    self.targets:refresh(self.env.context(),self.env.now(),{action_distance=self.cfg.main.max_distance,
        retain_distance=self.library.settings.retain_distance,retain_grace_ms=self.library.settings.retain_grace_ms})
    self.selectedTarget=self.targets.target
end
function Workspace:cancel(reason)
    self.pending=nil; self.executor:cancel(reason); self.prepared=nil
    if self.studio then self.studio.confirmPlan=nil end
end
function Workspace:saveLayout(value)
    local clean,why=require('pa26_window_layout').validate(value);if not clean then return nil,why end
    local candidate=model.copy(self.library);candidate.settings.window_layout=clean
    local ok,err=self.userFiles:save(candidate);if not ok then return nil,err end
    self.library=candidate
    if self.studio then self.studio:setLibrary(candidate)end
    return true
end
function Workspace:save(lib)
    local clean,err=model.validate(lib,self.cfg); if not clean then return nil,err end
    if self.executor.queue then
        for _,key in ipairs({'quick_key','tips_key','cancel_key'}) do
            if clean.settings[key]~=self.library.settings[key] then return nil,'Остановите сценарий перед изменением клавиш окон и отмены.' end
        end
    end
    for _,b in ipairs(clean.bindings) do local parsed; parsed,err=binder.parse(b.script); if not parsed then return nil,b.name..': '..err end end
    local ok,note=self.userFiles:save(clean)
    if not ok then return nil,note end
    -- An executing plan already owns a frozen copy; edits apply to future runs.
    self.pending=nil; self.prepared=nil
    if self.studio then self.studio.confirmPlan=nil end
    self.library=clean; self.libraryFresh=false; self.commandDirty=true; self.libraryRevision=self.libraryRevision+1
    if self.studio then self.studio:setLibrary(clean) end
    return true,note
end
function Workspace:saveJournal()
    local ok,err=store.save(self.base..'_journal.json',self.journal.data,self.json,journalModule.validate)
    if ok then self.journal.dirty=false else self.status=err; self.env.log(err) end
    return ok,err
end
-- Persist only this preference, preserving the already displayed frozen plan
-- and any unrelated unsaved editor fields. Checking this never means YES.
function Workspace:setBindingConfirmation(id,value)
    if type(value)~='boolean'then return nil,'Неверное значение подтверждения.'end
    local binding=model.find(self.library,id)
    if not binding then return nil,'Сначала сохраните бинд, чтобы запомнить его настройку.'end
    local candidate=model.copy(self.library);model.find(candidate,id).skip_confirmation=value
    local plan=self.studio and self.studio.confirmPlan;local prepared=self.prepared
    local ok,err=self:save(candidate);if not ok then return nil,err end
    self.prepared=prepared
    if plan then
        if plan.binding.id==id then plan.binding.skip_confirmation=value end
        self.studio.confirmPlan=plan
    end
    if self.studio and self.studio.draft and self.studio.draft.id==id then
        self.studio.draft.skip_confirmation=value
    end
    return true,err
end
function Workspace:notifyRequest(request,kind)
    -- Success is already presented by its preview, confirmation or progress
    -- window. Do not put a second acknowledgement in front of that decision.
    if kind=='info'then return end
    if self.studio then
        local id=request.binding and request.binding.id or request.id or (request.plan and request.plan.binding.id)
        self.studio:notify(self.status,request.returnTo or 'quick',id or false,kind)
    end
end
function Workspace:request(request)
    if self.pending or self.executor.queue then
        self.status='Сначала завершите или остановите текущий сценарий.'
        self:notifyRequest(request); self.env.log(self.status); return false
    end
    self.pending=request; return true
end
function Workspace:snapshot(binding,request)
    local context=self.env.context(); local demo=self.env.demo(); local profile=self.library.profile
    local req=binder.requirements(binding)
    local localValues=self.env.readLocal(); local values=model.copy(localValues or {})
    if demo then
        values.my_id=values.my_id or '42'; values.my_nick=values.my_nick or 'Demo_Officer'; values.area=values.area or 'Ganton'
    end
    if values.my_nick then values.my_name,values.my_firstname,values.my_lastname=names(values.my_nick) end
    if profile.name~='' then values.my_name,values.my_firstname,values.my_lastname=names(profile.name) end
    for _,key in ipairs({'local_tag','global_tag','prison_tag','department','rank','accent'}) do values[key]=profile[key] end
    values.my_mark=profile.callsign
    for _,key in ipairs({'my_plate','select_plate','closest_plate'}) do if profile[key]~='' then values[key]=profile[key] end end
    if self.library.map_grid.auto_city==false and profile.city~=''then values.city=profile.city
    elseif not values.city and profile.city~=''then values.city=profile.city end
    if not self.library.map_grid.auto_square and profile.square~=''then values.square=profile.square end
    local date=profile.timezone=='local' and os.date('*t') or os.date('!*t',os.time()+(profile.timezone=='moscow' and 10800 or 0))
    for _,pair in ipairs({{'s','sec'},{'m','min'},{'h','hour'},{'D','day'},{'M','month'}}) do values[pair[1]]=string.format('%02d',date[pair[2]]) end
    values.Y=tostring(date.year); values.greeting=date.hour<5 and 'Доброй ночи' or date.hour<12 and 'Доброе утро' or date.hour<18 and 'Добрый день' or 'Добрый вечер'
    local target=request.target or self.selectedTarget
    if demo then target={ped=0,id=42,name='Demo_Player'}
    elseif req.target then
        if target then local ok,value=pcall(self.env.validate,target,self.cfg.main.max_distance)
            if not ok or not core.capturedTargetValid(value) or value.id~=target.id or value.ped~=target.ped or value.name~=target.name then return nil,'Сохранённая цель потеряна. Выберите человека повторно.' end
            target=value
        end
        if not target then local ok,value=pcall(self.env.acquire,self.cfg.main.max_distance); target=ok and value or nil end
    else target=nil end
    if req.target and not target then return nil,binder.requirementError(req,'target')..' Выберите его через оружейное наведение и X.' end
    if target then
        values.id=tostring(target.id); values.select_id=values.id; values.select_nick=target.name
        values.select_name,values.select_firstname,values.select_lastname=names(target.name); values.suspect_name=values.select_name
        if not demo then self:selectTarget(target); for key,value in pairs(self.env.readPed(target.ped) or {}) do values['select_'..key]=value end end
    end
    local closest
    if req.nearby then
        local crew,nearby={},{}
        if demo then nearby={{ped=1,id=43,name='Demo_Partner',distance=3,callsign='P-1 (демо)'}}
        else nearby=self.env.nearby(self.cfg.main.max_distance) or {} end
        if req.closest then
            table.sort(nearby,function(a,b) return a.distance<b.distance end)
            if demo then closest=nearby[1]
            elseif nearby[1] and (not nearby[2] or nearby[2].distance-nearby[1].distance>.25) then closest=nearby[1] end
            if closest then values.closest_id=tostring(closest.id); values.closest_nick=closest.name
                values.closest_name,values.closest_firstname,values.closest_lastname=names(closest.name)
                if not demo then for key,value in pairs(self.env.readPed(closest.ped) or {}) do values['closest_'..key]=value end end
            end
        end
        for _,near in ipairs(nearby) do for _,contact in ipairs(self.library.partners) do if near.name:lower()==contact.nickname:lower() then local row=model.copy(near); row.callsign=contact.callsign; crew[#crew+1]=row; break end end end
        if demo and #self.library.partners==0 then crew=nearby end
        local ids,nicks,full,callsigns={},{},{},{}
        for _,person in ipairs(crew) do ids[#ids+1]=tostring(person.id); nicks[#nicks+1]=person.name; full[#full+1]=(names(person.name)); callsigns[#callsigns+1]=person.callsign and person.callsign~='' and person.callsign or 'без позывного' end
        values.team_count=tostring(#crew); values.team_id=table.concat(ids,', '); values.team_nick=table.concat(callsigns,', '); values.team_player_nick=table.concat(nicks,', ')
        values.team_name=#full==0 and 'нет видимых напарников рядом' or table.concat(full,', '); values.team=values.team_name
    end
    if demo then
        for _,prefix in ipairs({'my_','select_','closest_'}) do values[prefix..'weapon']=values[prefix..'weapon'] or 'Дубинка (демо)'; values[prefix..'vehicle']=values[prefix..'vehicle'] or 'GTA model 596 (демо)'; values[prefix..'speed']=values[prefix..'speed'] or '0' end
    end
    return {values=values,gender=profile.gender,target=req.target and target or nil,closest=closest,session=context.session,now=self.env.now(),demo=demo}
end
function Workspace:process()
    local pending=self.pending
    if not pending then return end
    local now=self.env.now()
    if pending.kind~='preview' and not pending.hiddenAt then pending.hiddenAt=now; self.env.hideUi(); return end
    if pending.hiddenAt then local age=core.elapsed(now,pending.hiddenAt)
        if not age or age>2000 then self.pending=nil; self.status='Ввод недоступен. Повторите запуск после закрытия серверного окна.'; self:notifyRequest(pending); self.env.openReturn(pending.returnTo); return end
        if age<100 or self.env.context().blocked then return end
    end
    self.pending=nil
    if pending.kind=='startPlan' then
        local ok,err=self.executor:start(pending.plan,self.env.demo(),self.cfg.main.interval_ms); self.status=err or self.executor.status
        self:notifyRequest(pending,ok and'info'or'warning'); return
    end
    local binding=pending.binding or model.find(self.library,pending.id)
    if not binding then self.status='Сценарий не найден.'; self:notifyRequest(pending); self.env.openReturn(pending.returnTo); return end
    local snapshot,err=self:snapshot(binding,pending)
    local plan
    if snapshot then plan,err=binder.compile(binding,snapshot,pending.args,self.env.codec,math.random,
        {rpSettings=self.library.rp_text,sound=self.env.soundAvailable(),screen=false,reservedKeys={[0x1B]=true,[self.library.settings.cancel_key]=true,
            [self.cfg.main.menu_key]=true,[self.cfg.main.radial_key]=true,[self.library.settings.quick_key]=true,[self.library.settings.tips_key]=true}}) end
    if not plan then self.status=err or 'Подготовка не выполнена.'; self:notifyRequest(pending); self.env.openReturn(pending.returnTo); return end
    if self.studio then self.studio.plan=plan end
    self.status='Предпросмотр подготовлен. Отправки нет.'
    local outcomeKind='info'
    self.prepared=plan
    if pending.kind=='preview' then
        self.env.preview(); self.status='Предпросмотр: отправки нет.'
        for _,line in ipairs(plan.lines) do self.env.log('[ПРЕДПРОСМОТР] '..line) end
    elseif pending.start then
        if not self.env.demo() and not binding.skip_confirmation and (plan.has_command or #binding.parameters>0 or plan.requirements.closest) then
            if self.studio then self.studio.confirmPlan=plan end; self.env.openConfirm()
        else local ok; ok,err=self.executor:start(plan,self.env.demo(),self.cfg.main.interval_ms); self.status=err or self.executor.status; if not ok then outcomeKind='warning';self.env.openReturn(pending.returnTo) end end
    end
    self:notifyRequest(pending,outcomeKind)
end
function Workspace:tick()
    self:refreshTarget(); self:process(); self.executor:step()
    local now=self.env.now()
    if self.libraryFresh then local ok,err=self:save(self.library); self.libraryFresh=false; if not ok then self.status=err; self.env.log(err) end end
    if self.journal.dirty and (not self.lastSave or (core.elapsed(now,self.lastSave) or 0)>=15000) then self.lastSave=now; self:saveJournal() end
end
function Workspace:export(kind,id)
    kind=kind or'binds'
    local payload,err=userFiles.exchange(self.library,kind,id);if not payload then return nil,err end
    local path=self.base..'_'..kind..'_exchange.json'
    local ok,note=store.save(path,payload,self.json,function(v)return userFiles.validate(kind,v)end)
    return ok,note or(ok and('Экспорт сохранённых '..(kind=='binds'and'биндов' or'заметок')..': '..path)or nil)
end
function Workspace:prepareImport(kind)
    kind=kind or'binds'
    local path=self.base..'_'..kind..'_exchange.json'
    local text=store.fs.read(path)
    if not text then text=store.fs.read(self.base..'_exchange.json')end
    if not text then return nil,'Файл обмена не найден. Поместите полученный JSON в '..path end
    return userFiles.decodeExchange(text,self.json,kind)
end
function Workspace:import(data)
    if type(data)~='table'then return nil,'Неверный файл обмена.'end
    local kind=data.format=='police-assistant.binds'and'binds'or data.format=='police-assistant.notes'and'notes'
    if not kind then return nil,'Выберите отдельный файл биндов или заметок.'end
    local payload,err=userFiles.validate(kind,data);if not payload then return nil,err end
    local copy=model.copy(self.library)
    if kind=='binds'then
        for _,b in ipairs(payload.bindings)do
            local row=model.copy(b);row.id=copy.next_id;copy.next_id=copy.next_id+1
            row.enabled=false;row.skip_confirmation=false;row.command='';row.command_alias='';row.shortcut={key=0,ctrl=false,alt=false,shift=false}
            copy.bindings[#copy.bindings+1]=row
        end
    else
        for _,n in ipairs(payload.notes)do local row=model.copy(n);row.id=copy.next_note_id;copy.next_note_id=copy.next_note_id+1;copy.notes[#copy.notes+1]=row end
    end
    return self:save(copy)
end
return M

-- Local IC observations declared by the user. No nickname-to-passport inference,
-- mask heuristics, unverified chat patterns or persistence across game scenes.
local core=require 'pa26_core'
local shared=require 'pa26_patrol_settings'
local model={copy=shared.copy,clean=function(v,max)
    if type(v)~='string'or #v>max or not core.validUtf8(v)or v:find('[%z\1-\8\11\12\14-\31\127]')then return nil end
    return v:gsub('\r\n','\n'):match('^%s*(.-)%s*$')
end}
local M={};local Identity={};Identity.__index=Identity
local enums={passport_seen=true,mask=true,face_before=true,phone_known=true}
local fields={passport_seen='unknown',ic_name='',passport_number='',mask='unknown',face_before='unknown',appearance='',
    phone_known='unknown',phone_number='',phone_source=''}
local groups={passport={'passport_seen','ic_name','passport_number'},face={'mask','face_before'},appearance={'appearance'},phone={'phone_known','phone_number','phone_source'}}
local groupFor={};for group,keys in pairs(groups)do for _,k in ipairs(keys)do groupFor[k]=group end end
function M.defaults()return {enabled=true,retain_after_switch=false,expiry_ms=1800000,passport_revision=2,
    passport_chat=true,passport_server='',passport_phrase='достал паспорт и показал его',passport_distance=30,passport_flexible=true,passport_diagnostics=true}end
function M.validate(raw)
    local out=M.defaults();if raw==nil then return out end
    if type(raw)~='table'then return nil,'Повреждены настройки IC-сведений.'end
    if raw.passport_revision~=nil and raw.passport_revision~=2 then return nil,'Неизвестная версия распознавания паспорта.'end
    for _,k in ipairs({'enabled','retain_after_switch','passport_chat','passport_flexible','passport_diagnostics'})do
        if raw[k]~=nil then if type(raw[k])~='boolean'then return nil,'Неверный переключатель IC-сведений.'end;out[k]=raw[k]end
    end
    local n=raw.expiry_ms;if n==nil then n=out.expiry_ms end
    if n~=0 and not shared.integer(n,1000,86400000)then return nil,'Срок IC-сведений: 0 или от 1 до 86400 секунд.'end
    out.expiry_ms=n
    out.passport_server=shared.text(raw.passport_server or out.passport_server,120)
    -- The former stock IP was not a user-selected server restriction.
    if raw.passport_revision==nil and out.passport_server=='185.207.214.114:7777'then out.passport_server=''end
    out.passport_phrase=shared.text(raw.passport_phrase or out.passport_phrase,240)
    if not out.passport_server or not out.passport_phrase or out.passport_phrase==''then return nil,'Укажите сервер и точную фразу показа паспорта.'end
    out.passport_distance=raw.passport_distance or out.passport_distance
    if not shared.integer(out.passport_distance,5,100)then return nil,'Проверка показа паспорта: от 5 до 100 м.'end
    return out
end
function M.new(env)return setmetatable({env=env,records={},serial=0,revision=0,mail={},evidence={},wantedMemory={}},Identity)end
function M.passportMessage(line,phrase,flexible)
    if type(line)~='string'or #line>1024 or not core.validUtf8(line)or line:find('[%z\1-\31\127]')then return end
    line=line:gsub('{%x%x%x%x%x%x}',''):match('^%s*(.-)%s*$')
    if flexible then
        line=line:gsub('{%x%x%x%x%x%x%x%x}','')
        line=line:gsub('^%[%d%d:%d%d:%d%d%]%s*',''):gsub('^%[%d%d:%d%d%]%s*','')
        line=line:gsub('^%d%d:%d%d:%d%d%s+',''):gsub('^%d%d:%d%d%s+','')
        local marked=line:match('^%[ME%]')or line:match('^ME%s+')or line:match('^%*%s+')
        line=line:gsub('^%[ME%]%s*',''):gsub('^ME%s+',''):gsub('^%*%s+','')
        line=line:gsub('([%w_%.]+)%s*%[%d+%]', '%1'):gsub('([%w_%.]+)%s*%(%d+%)','%1')
        if marked then line=line:gsub('^([%w_%.]+):%s*','%1 ')end
        line=line:gsub('%.$',''):gsub('%s+',' ')
    end
    line=line:gsub('^%[ME%]%s*','')
    local actor,body,recipient=line:match('^([%w_%[%]%.]+)%s+(.+)%s+([%w_%[%]%.]+)$')
    if actor and body==phrase and actor~=recipient then return actor,recipient end
end
function Identity:serverMessage(line)
    local cfg=self.env.settings();local s=self.state
    if not cfg.enabled or not cfg.passport_chat or not s or not s.alive or not self.now or
        cfg.passport_server~=''and cfg.passport_server~=s.session then
        if cfg.passport_diagnostics and type(line)=='string'and line:find('паспорт',1,true)then
            if not cfg.enabled or not cfg.passport_chat then self.passportStatus='Распознавание паспорта отключено.'
            elseif not s or not s.alive or not self.now then self.passportStatus='Показ пока не принят: игровая сцена недоступна.'
            else self.passportStatus='Показ не принят: проверьте ограничение адреса сервера в настройках.'end
        end
        return false
    end
    local actor,recipient=M.passportMessage(line,cfg.passport_phrase,cfg.passport_flexible)
    if not actor or recipient~=s.local_nick or #self.mail>=16 then
        if cfg.passport_diagnostics and type(line)=='string'and line:find('паспорт',1,true)then
            self.passportStatus=actor and 'Показ не принят: документ показали другому человеку.'or 'Показ не принят: текст не совпал с настроенной системной фразой.'
        end
        return false
    end
    self.passportStatus='Показ адресован вам; проверяется показавший игрок рядом.'
    self.mail[#self.mail+1]={actor=actor,recipient=recipient,at=self.now,session=s.session,ped=s.ped,phrase=cfg.passport_phrase}
    return true -- No native API or mutation of a form inside an RPC callback.
end
local function key(state,target,stamp)
    if not state or not state.session or not core.capturedTargetValid(target)or not shared.integer(stamp,0,999999999)then return nil end
    return table.concat({state.session,tostring(target.id),target.name,tostring(target.ped)},'\0')
end
function Identity:clear(reason)
    if self.current or next(self.records)then self.revision=self.revision+1 end
    self.records={};self.current=nil;self.intent=nil;self.message=reason;self.mail={};self.evidence={};self.wantedMemory={};self.passportStatus=nil
end
function Identity:playerChanged(id)
    if not core.validId(id)then return end
    for k,r in pairs(self.records)do if r.target.id==id then self.records[k]=nil;if self.current==k then self.current=nil end;self.revision=self.revision+1 end end
    for k,e in pairs(self.evidence)do if e.target.id==id then self.evidence[k]=nil end end
    for k,r in pairs(self.wantedMemory)do if r.target.id==id then self.wantedMemory[k]=nil end end
    self.mail={} -- A quit/join between reception and resolution cannot rebind an old signal.
    if self.intent and not self.records[self.intent.key]then self.intent=nil end
end
function Identity:tick(state,target,stamp,now)
    if not core.finite(now)or now~=math.floor(now)then self:clear('Игровой таймер изменился. Уточните IC-сведения заново.');return end
    local previous=self.state;local dt=self.now and core.elapsed(now,self.now)
    self.now=now;self.state={session=state.session,ped=state.ped,alive=state.alive,demo=state.demo,local_nick=state.local_nick}
    if previous and(not dt or previous.session~=state.session or previous.ped~=state.ped or previous.demo~=state.demo or
        previous.local_nick~=state.local_nick or previous.alive~=state.alive)then self:clear('Игровая сцена изменилась. Прежние сведения удалены.')end
    local cfg=self.env.settings()
    if not cfg.enabled or not state.alive or not state.session then self:clear('IC-сведения отключены или персонаж недоступен.');return end
    local mail=self.mail;self.mail={}
    for _,event in ipairs(mail)do
        local age=core.elapsed(now,event.at)
        if cfg.passport_chat and (cfg.passport_server==''or cfg.passport_server==state.session)and
            event.session==state.session and event.ped==state.ped and event.recipient==state.local_nick and
            event.phrase==cfg.passport_phrase and age and age<=5000 then
            local found=self.env.resolvePassport and self.env.resolvePassport(event.actor,cfg.passport_distance)
            if found and found.name==event.actor then
                local k=key(state,found,0)
                if k then
                    self.serial=self.serial+1;self.evidence[k]={target=model.copy(found),at=now,serial=self.serial}
                    self:rememberWanted(found,{passport_seen='yes',passport_source='server',at={passport=now}})
                end
                self.passportStatus='Показ паспорта подтверждён. Сведения применятся при выборе этого саспекта.'
            elseif cfg.passport_diagnostics then self.passportStatus='Показ распознан, но игрок сейчас не виден или вне настроенной дистанции.'
            end
        end
    end
    local evidenceCount=0
    for k,e in pairs(self.evidence)do
        local age=core.elapsed(now,e.at)
        if not age or cfg.expiry_ms>0 and age>=cfg.expiry_ms then self.evidence[k]=nil else evidenceCount=evidenceCount+1 end
    end
    while evidenceCount>16 do
        local oldest,serial;for k,e in pairs(self.evidence)do if not serial or e.serial<serial then oldest=k;serial=e.serial end end
        self.evidence[oldest]=nil;evidenceCount=evidenceCount-1
    end
    local nextKey=key(state,target,stamp)
    if nextKey~=self.current then
        if not cfg.retain_after_switch then self.records={}end
        self.current=nextKey;self.intent=nil;self.revision=self.revision+1
        if nextKey and not self.records[nextKey]then
            self.serial=self.serial+1
            local r={target=model.copy(target),stamp=stamp,nonce=self.serial,version=1,display_revision=1,at={},source='manual'}
            for k,v in pairs(fields)do r[k]=v end
            self.records[nextKey]=r
            local count=0;for _ in pairs(self.records)do count=count+1 end
            if count>16 then
                local oldest,serial
                for k,row in pairs(self.records)do if k~=nextKey and(not serial or row.nonce<serial)then oldest=k;serial=row.nonce end end
                if oldest then self.records[oldest]=nil end
            end
        elseif nextKey then
            self.serial=self.serial+1
            self.records[nextKey].nonce=self.serial;self.records[nextKey].stamp=stamp
        end
    end
    for k,row in pairs(self.wantedMemory)do
        if cfg.expiry_ms>0 then for group,at in pairs(row.at)do
            local age=core.elapsed(now,at)
            if not age or age>=cfg.expiry_ms then
                for _,field in ipairs(groups[group])do row[field]=fields[field]end
                row.at[group]=nil;row.version=row.version+1
                if group=='passport'then row.passport_source=nil end
            end
        end end
    end
    local r=self.current and self.records[self.current]
    if r and r.stamp~=stamp then
        if not cfg.retain_after_switch then
            for k,v in pairs(fields)do r[k]=v end;r.at={};r.display_revision=r.display_revision+1
            r.passport_source=nil;r.evidence_serial=nil
        end
        self.serial=self.serial+1;r.nonce=self.serial;r.stamp=stamp;self.intent=nil;self.revision=self.revision+1
    end
    if cfg.expiry_ms>0 then for _,row in pairs(self.records)do
        for group,at in pairs(row.at)do local age=core.elapsed(now,at)
            if not age or age>=cfg.expiry_ms then
                for _,field in ipairs(groups[group])do row[field]=fields[field]end
                row.at[group]=nil;if group=='passport'then row.passport_source=nil;row.evidence_serial=nil end
                row.version=row.version+1;row.display_revision=row.display_revision+1;self.revision=self.revision+1
                if row==r then self.message='Часть сведений устарела. Подтвердите их заново.'end
            end
        end
    end end
    local evidence=self.current and self.evidence[self.current]
    if cfg.passport_chat and r and evidence and r.evidence_serial~=evidence.serial then
        r.passport_seen='yes';r.passport_source='server';r.evidence_serial=evidence.serial;r.at.passport=evidence.at
        r.version=r.version+1;r.display_revision=r.display_revision+1;self.revision=self.revision+1
        self.message='Паспорт '..r.target.name..' показан вам · распознано системное сообщение.'
    end
    local intent=self.intent;self.intent=nil
    if intent and r and intent.key==self.current and intent.nonce==r.nonce then
        for field,value in pairs(intent.patch)do
            if field=='passport_seen'then r.passport_source='manual';r.evidence_serial=nil;self.evidence[self.current]=nil end
            if r[field]~=value then
                r[field]=value;r.at[groupFor[field]]=now;r.version=r.version+1;self.revision=self.revision+1
            end
        end
        self:rememberWanted(r.target,r)
    end
end
-- Evidence for wanted may survive walking away or selecting another person.
-- It remains session/life scoped, expires per group, and is purged on ID reuse.
function Identity:rememberWanted(target,patch)
    if not target or not core.validId(target.id)or type(target.name)~='string'then return end
    local k=tostring(target.id)..':'..target.name
    local r=self.wantedMemory[k]
    if not r then
        self.serial=self.serial+1;r={target=model.copy(target),nonce=self.serial,version=1,at={}}
        for field,value in pairs(fields)do r[field]=value end
        self.wantedMemory[k]=r
    end
    local changed=false
    for field in pairs(fields)do if patch[field]~=nil and r[field]~=patch[field]then r[field]=patch[field];changed=true end end
    if patch.passport_source~=nil and r.passport_source~=patch.passport_source then r.passport_source=patch.passport_source;changed=true end
    for group,at in pairs(patch.at or {})do if r.at[group]~=at then r.at[group]=at;changed=true end end
    if changed then r.version=r.version+1 end
    local count=0;for _ in pairs(self.wantedMemory)do count=count+1 end
    if count>16 then
        local oldest,serial
        for key,row in pairs(self.wantedMemory)do if key~=k and(not serial or row.nonce<serial)then oldest=key;serial=row.nonce end end
        if oldest then self.wantedMemory[oldest]=nil end
    end
end
function Identity:wantedRecord(target)
    local cfg=self.env.settings()
    if not cfg.enabled or not self.state or not self.state.alive or not target then return end
    local r=self.wantedMemory[tostring(target.id)..':'..tostring(target.name)]
    if not r then return end
    if r.passport_source=='server'and not cfg.passport_chat then
        r=model.copy(r);r.passport_seen='unknown';r.passport_source=nil
    end
    return model.copy(r)
end
function Identity:update(patch,expectedKey,nonce)
    local r=self.current and self.records[self.current]
    if not r or expectedKey~=self.current or nonce~=r.nonce then return nil,'Человек или сцена изменились. Откройте текущую карточку заново.'end
    if type(patch)~='table'then return nil,'Неверные IC-сведения.'end
    local safe={};local count=0
    for k,v in pairs(patch)do
        if fields[k]==nil then return nil,'Неизвестное поле IC-сведений.'end
        if enums[k]then
            if v~='unknown'and v~='yes'and v~='no'then return nil,'Выберите: неизвестно, да или нет.'end
        else
            v=k=='appearance'and model.clean(v,768,true)or shared.text(v,k=='ic_name'and 120 or k=='phone_source'and 240 or 80)
            if not v then return nil,'Проверьте введённый текст.'end
        end
        safe[k]=v;count=count+1
    end
    if count==0 then return true end
    local intent=self.intent
    if not intent or intent.key~=expectedKey or intent.nonce~=nonce then intent={key=expectedKey,nonce=nonce,patch={}}end
    for k,v in pairs(safe)do intent.patch[k]=v end
    self.intent=intent;return true -- Updated in main(), never from a native RPC.
end
function Identity:subject(target,stamp)
    local r=self.current and self.records[self.current]
    if not r or not target or stamp~=r.stamp or target.id~=r.target.id or target.name~=r.target.name or target.ped~=r.target.ped then return nil,'IC-сведения относятся к другому выбору человека.'end
    if r.passport_seen=='yes'and r.ic_name~=''then return r.ic_name,r.passport_source=='server'and
        'Показ паспорта распознан · IC-имя введено вами вручную'or 'IC-имя из паспорта · отмечено вами вручную'end
    local appearance=r.appearance:gsub('%s+',' '):match('^%s*(.-)%s*$')
    if appearance~=''then return appearance,'Известные приметы · записано вами вручную'end
    return nil,'Нет подтверждённого вами IC-имени или описания примет.'
end
function Identity:view()
    local r=self.current and self.records[self.current]
    local cfg=self.env.settings()
    return {key=self.current,record=r and model.copy(r),revision=self.revision,message=self.message,passportStatus=cfg.passport_diagnostics and self.passportStatus or nil,enabled=cfg.enabled}
end
function Identity:forget(expectedKey,nonce)
    local r=self.current and self.records[self.current]
    if not r or self.current~=expectedKey or r.nonce~=nonce then return nil,'Выбор человека изменился.'end
    for k,v in pairs(fields)do r[k]=v end
    self.evidence[self.current]=nil;r.passport_source=nil;r.evidence_serial=nil
    self.wantedMemory[tostring(r.target.id)..':'..r.target.name]=nil
    r.at={};r.version=r.version+1;r.display_revision=r.display_revision+1;self.revision=self.revision+1;self.intent=nil;self.message='Сведения о выбранном человеке очищены.'
    return true
end
return M

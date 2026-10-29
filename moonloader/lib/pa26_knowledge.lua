-- Local, data-only knowledge catalogue. Nothing read from the forum is executed.
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local store=require 'pa26_library'
local binder=require 'pa26_binder'
local editModule=require 'pa26_knowledge_edits'
local M={MAX_BYTES=4*1024*1024,SCHEMA=1}
local Knowledge={};Knowledge.__index=Knowledge
M.groups={{'offenses','Нарушения'},{'commands','Команды'},{'rules','Правила'},
    {'scenario_catalog','Процедуры'},{'articles','Все статьи'},{'radio','Рация'},
    {'drafts','RP-тексты'},{'patrol','Патруль'},{'gaps','Уточнения'},{'sources','Источники'}}
local limits={offenses=250,commands=200,rules=300,scenario_catalog=200,articles=2500,radio=200,drafts=100,gaps=200,sources=200}
local statuses={reviewed_source_summary='Разобран источник',forum_requirement_confirmed='RP подтверждено',
    source_index='Указатель статьи',source_example_pending_implementation='Пример процедуры',
    original_draft_pending_user_review='Наш RP-черновик',snapshot_reviewed='Источник проверен',
    source_recommendation_confirmed='Рекомендованный текст форума',
    conflict_pending='Есть расхождение',reviewed_data_pending_runtime='Данные для патруля',
    not_published='Не опубликовано',reference_only='Справочный материал',needs_review='Источник изменился — нужно сравнение',
    historical_source_index='Архивная редакция',user_observed_game_menu='Подтверждено игровыми скриншотами пользователя'}
local function clean(s,max,multi)
    return type(s)=='string' and #s<=max and core.validUtf8(s) and not s:find('[%z\1-\8\11\12\14-\31\127]')
        and (multi or not s:find('[\r\n]'))
end
local function folded(s) return model.casefold(s or ''):gsub('ё','е') end
M.casefold=folded
local function title(item) return item.title or item.reference or item.command or item.id end
function M.validate(raw)
    if type(raw)~='table' or raw.schema_version~=M.SCHEMA or not clean(raw.catalog_version,120) then
        return nil,'Эта версия формата базы не поддерживается.'
    end
    local sources={}
    if not model.array(raw.sources,limits.sources) or #raw.sources==0 then return nil,'Нет списка источников.' end
    for _,item in ipairs(raw.sources) do
        if type(item)~='table' or not clean(item.id,100) or sources[item.id] or not clean(item.title,900) or
            not clean(item.url,600) or not item.url:match('^https://forum%.exsellentrp%.com/') then return nil,'Повреждён источник базы.' end
        sources[item.id]=true
    end
    local function reference(r)
        return type(r)=='table' and sources[tostring(r.source_id)] and clean(r.url,600) and
            r.url:match('^https://forum%.exsellentrp%.com/') and (r.locator==nil or clean(r.locator,900))
    end
    for group,max in pairs(limits) do
        if not model.array(raw[group],max) then return nil,'Повреждён раздел '..group end
        local ids={}
        for _,item in ipairs(raw[group]) do
            if type(item)~='table' or not clean(item.id,100) or ids[item.id] or not clean(title(item),900) then
                return nil,'Повторная или повреждённая запись: '..group
            end
            ids[item.id]=true
            for _,name in ipairs({'reference','command','meaning','criterion','text','design','notes','note','resolution','requirement',
                'verification_status','interpretation_status','reviewed_on','source_reviewed_on','read_on','group','type','qualification',
                'origin','source_recommended_text','legal_disclaimer','binder_variant_note','local_text','local_source_url','brief','order','exceptions','operation_id','topic'}) do
                if item[name]~=nil and not clean(item[name],name=='text'and 64000 or 12000,true) then return nil,'Повреждено поле '..name end
            end
            if item.article~=nil and(type(item.article)~='string'or not item.article:match('^%d+%.?%d*$'))then return nil,'Номер статьи должен сохранять дробную часть.'end
            for _,n in ipairs({'manual_volume','occurrence'})do if item[n]~=nil and(not core.finite(item[n])or item[n]%1~=0 or item[n]<1 or item[n]>100)then return nil,'Неверное вхождение пункта Мануала.'end end
            if item.operation_id~=nil then
                if item.operation_id~=item.id or not item.id:match('^operation:[a-z_]+$')or not clean(item.brief,12000,true)or not clean(item.order,12000,true)or not clean(item.exceptions,12000,true)then return nil,'Повреждена оперативная карточка.'end
                if not({road=true,rights=true,wanted=true,radio=true,force=true,law=true})[item.topic]then return nil,'Неверная тема оперативной карточки.'end
            end
            for _,name in ipairs({'aliases','departments','commands','source_ids','application_conditions','legal_basis','game_reasons'}) do
                if item[name]~=nil then
                    if not model.array(item[name],100) then return nil,'Повреждено поле '..name end
                    for _,value in ipairs(item[name]) do if not clean(value,900) then return nil,'Повреждено поле '..name end end
                end
            end
            if item.source and not reference(item.source) then return nil,'Источник записи отсутствует.' end
            if item.duplicate_source and not reference(item.duplicate_source) then return nil,'Второй источник отсутствует.' end
            if item.sources then
                if not model.array(item.sources,20) then return nil,'Неверные ссылки на источники.' end
                for _,r in ipairs(item.sources) do if not reference(r) then return nil,'Источник записи отсутствует.' end end
            end
            if item.department_notes~=nil then
                if not model.array(item.department_notes,3)then return nil,'Неверные ведомственные пояснения.'end
                local seen={}
                for _,note in ipairs(item.department_notes)do
                    if type(note)~='table'or not({EPD=true,FBI=true,Alcatraz=true})[note.department]or seen[note.department]or
                        not clean(note.text,8000,true)or not model.array(note.sources,8)then return nil,'Повреждено ведомственное пояснение.'end
                    seen[note.department]=true
                    for _,r in ipairs(note.sources)do if not reference(r)then return nil,'Источник ведомственного пояснения отсутствует.'end end
                end
            end
            if group=='commands' and (type(item.rp_required)~='boolean' or
                not clean(item.command,100)or not item.command:match('^/[a-z][a-z0-9_]*$')) then return nil,'Неверная матрица команд.' end
            if item.sanctions~=nil then
                if not model.array(item.sanctions,30) then return nil,'Неверные ветви санкции.' end
                for _,s in ipairs(item.sanctions) do
                    if type(s)~='table' or not clean(s.kind,80) or (s.unit~=nil and not clean(s.unit,80)) or
                        (s.condition~=nil and not clean(s.condition,2000,true))or
                        (s.alternative~=nil and not clean(s.alternative,2000,true)) then return nil,'Повреждена санкция.' end
                    if s.source_text_sha256~=nil then
                        if type(s.source_text_sha256)~='string'or #s.source_text_sha256~=64 or not s.source_text_sha256:match('^%x+$')or
                         s.source_text_sha256~=item.source_text_sha256 or not clean(s.source_excerpt,2000,true)or
                         type(item.text)~='string'or not item.text:find(s.source_excerpt,1,true)then return nil,'Ветвь санкции не совпадает с её первоисточником.'end
                    end
                    for _,n in ipairs({'min','max'}) do if s[n]~=nil and (not core.finite(s[n]) or s[n]<0) then return nil,'Неверная величина санкции.' end end
                    if s.min~=nil and s.max~=nil and s.min>s.max then return nil,'Минимальная санкция больше максимальной.'end
                    if s.life_alternative~=nil and type(s.life_alternative)~='boolean' then return nil,'Повреждена альтернатива санкции.' end
                end
            end
            if item.steps~=nil then
                if not model.array(item.steps,100) then return nil,'Повреждён RP-черновик.' end
                for _,s in ipairs(item.steps) do
                    if type(s)~='table' or not clean(s.type,60) or (s.text~=nil and not clean(s.text,2000,true)) or
                        (s.label~=nil and not clean(s.label,900,true)) then return nil,'Повреждён шаг черновика.' end
                end
            end
        end
    end
    local p=raw.patrol_profile
    if type(p)~='table' or not model.array(p.original_templates_not_mandated,20) or not model.array(p.events,20) then
        return nil,'Повреждён профиль патруля.'
    end
    if not model.array(p.sources,20)then return nil,'Неверные источники патруля.'end
    for _,r in ipairs(p.sources)do if not reference(r)then return nil,'Источник патруля отсутствует.'end end
    for _,t in ipairs(p.original_templates_not_mandated) do
        if type(t)~='table' or not clean(t.id,100) or not clean(t.text,2000) then return nil,'Неверный шаблон патруля.' end
    end
    for _,e in ipairs(p.events) do
        if type(e)~='table' or not clean(e.id,100) or not clean(e.radio_code,100) then return nil,'Неверное событие патруля.' end
    end
    for _,name in ipairs({'dispatch_min_crew','danger_zone_arrest_min_crew'}) do
        if p[name]~=nil and (not core.finite(p[name]) or p[name]<0)then return nil,'Неверный состав патруля.'end
    end
    return raw
end
function M.personalDefaults() return {schema_version=1,department='EPD',favorites={},recent={},notes={},mappings={},view={reset_enabled=true,reset_minutes=10,catalog_mode='current'}} end
function M.validatePersonal(raw)
    if type(raw)~='table' or raw.schema_version~=1 or not ({EPD=true,FBI=true,Alcatraz=true})[raw.department] or
        not model.array(raw.favorites,500) or not model.array(raw.recent,40) or type(raw.notes)~='table' or
        type(raw.mappings)~='table' then return nil,'Личные данные базы повреждены.' end
    local view=raw.view==nil and{reset_enabled=true,reset_minutes=10}or raw.view
    if type(view)~='table'or type(view.reset_enabled)~='boolean'or not core.finite(view.reset_minutes)or
        view.reset_minutes~=math.floor(view.reset_minutes)or view.reset_minutes<1 or view.reset_minutes>1440 then return nil,'Интервал сброса раздела: от 1 до 1440 минут.'end
    local out={schema_version=1,department=raw.department,favorites={},recent={},notes={},mappings={},
        view={reset_enabled=view.reset_enabled,reset_minutes=view.reset_minutes,catalog_mode=view.catalog_mode or'current'}}
    if out.view.catalog_mode~='current'and out.view.catalog_mode~='all'then return nil,'Выберите режим базы: актуальное или все записи.'end
    for _,key in ipairs({'favorites','recent'}) do
        local seen={}
        for _,id in ipairs(raw[key]) do
            if not clean(id,160) or seen[id] then return nil,'Повреждён список личных записей.' end
            seen[id]=true;out[key][#out[key]+1]=id
        end
    end
    local count=0
    for id,note in pairs(raw.notes) do
        count=count+1;if count>500 or not clean(id,160) or not clean(note,4000,true) then return nil,'Личная заметка слишком велика.' end
        out.notes[id]=note
    end
    count=0
    for id,row in pairs(raw.mappings) do
        count=count+1;if count>500 or not clean(id,160) or type(row)~='table' then return nil,'Личное значение повреждено.' end
        local copy={}
        for _,key in ipairs({'stars','fine','minutes'}) do
            local v=row[key] or ''
            if not clean(v,16) or (v~='' and not v:match('^%d+$')) then return nil,'Введите целое неотрицательное число или оставьте поле пустым.' end
            copy[key]=v
        end
        copy.origin='manual';out.mappings[id]=copy
    end
    return out
end
function M.new(options)
    options=options or {}
    local editPath=options.editPath
    if not editPath and options.personalPath then
        local derived,count=options.personalPath:gsub('_personal%.json$','_edits.json')
        editPath=count==1 and derived or options.personalPath..'_edits.json'
    end
    local edits=editModule.new({json=options.json,fs=options.fs,path=editPath,stamp=options.stamp})
    return setmetatable({json=options.json,fs=options.fs or store.fs,path=options.path,bundle=options.bundle,
        policyPath=options.policyPath,personalPath=options.personalPath,now=options.now or function() return 0 end,
        personal=M.personalDefaults(),records={},byKey={},sources={},revision=0,cache={},loaded=false,policies={},edits=edits},Knowledge)
end
function Knowledge:read(path,validate)
    local ok,text=pcall(self.fs.read,path,M.MAX_BYTES)
    if not ok or not text then return nil,'Файл не найден или недоступен.' end
    return store.decode(text,self.json,validate,M.MAX_BYTES)
end
local function refs(item)
    local out={}
    if item.source then out[#out+1]=item.source end
    if item.duplicate_source then out[#out+1]=item.duplicate_source end
    for _,r in ipairs(item.sources or {}) do out[#out+1]=r end
    for _,id in ipairs(item.source_ids or {}) do out[#out+1]={source_id=id} end
    return out
end
function Knowledge:activate(data)
    if data.project=='Police Assistant 2026'and data.server=='Exsellent RP'then
        local catalog=require 'pa26_wanted_catalog';local present,sourceIds={},{}
        for _,r in ipairs(data.rules)do present[r.id]=true end
        for _,r in ipairs(data.sources)do sourceIds[tostring(r.id)]=true end
        local extra={}
        for _,r in ipairs(catalog.rows)do if not present[r.knowledge_card.id]then
            local card=model.copy(r.knowledge_card);local sources={}
            for _,ref in ipairs(card.sources)do if sourceIds[tostring(ref.source_id)]then sources[#sources+1]=ref end end
            card.sources=sources;extra[#extra+1]=card
        end end
        local hasWanted=false;for _,r in ipairs(data.commands)do if r.command=='/wanted'then hasWanted=true end end
        if #extra>0 or not hasWanted then
            data=model.copy(data)
            for _,r in ipairs(extra)do data.rules[#data.rules+1]=r end
            if not hasWanted then data.commands[#data.commands+1]=model.copy(catalog.wanted_command)end
        end
    end
    self.data=data;self.records={};self.byKey={};self.baseByKey={};self.sources={};self.cache={};self.detachedEdits={}
    for _,s in ipairs(data.sources) do self.sources[s.id]=s end
    local function add(group,item)
        local key=group..':'..item.id
        self.baseByKey[key]=item
        local edit=self.edits:inspect(key,item,self.sources);item=edit.item
        local row={key=key,group=group,item=item,title=title(item),refs=refs(item),departments={},edit=edit}
        local text={row.title,item.id,item.reference or '',item.command or '',item.meaning or '',item.criterion or '',
            item.text or '',item.design or '',item.notes or '',item.note or '',item.resolution or '',item.local_text or '',item.brief or'',item.order or'',item.exceptions or''}
        for _,v in ipairs(item.aliases or {}) do text[#text+1]=v end
        for _,v in ipairs(item.departments or {}) do row.departments[v]=true end
        if group=='sources' then row.departments[item.group or '']=true end
        for _,r in ipairs(row.refs) do
            local source=self.sources[tostring(r.source_id)]
            if source then text[#text+1]=source.title;row.departments[source.group or '']=true end
        end
        row.commonSearch=folded(table.concat(text,' '));row.departmentSearch={}
        local all={row.commonSearch}
        for _,note in ipairs(item.department_notes or{})do
            row.departments[note.department]=true
            row.departmentSearch[note.department]=folded(row.commonSearch..' '..note.text)
            all[#all+1]=note.text
        end
        row.search=folded(table.concat(all,' '));row.titleSearch=folded(row.title)
        self.records[#self.records+1]=row;self.byKey[key]=row
    end
    for _,g in ipairs(M.groups) do
        if g[1]=='patrol' then
            local p=data.patrol_profile
            add('patrol',{id='profile',title='Патруль EPD: условия и доклады',verification_status=p.status,
                departments={'EPD'},sources=p.sources,text='Состав экипажа, доклады, VICTOR, FOXTROT и передача задержанного',profile=p})
        else for _,item in ipairs(data[g[1]]) do add(g[1],item) end end
    end
    -- Custom records never replace a source record with a colliding identity.
    local customKeys={};for key,e in pairs(self.edits.state.entries)do
        if e.kind=='custom'then customKeys[#customKeys+1]=key
        elseif not self.baseByKey[key]then self.detachedEdits[#self.detachedEdits+1]={key=key,status='orphan',entry=e}end
    end
    table.sort(customKeys)
    for _,key in ipairs(customKeys)do
        local e=self.edits.state.entries[key]
        if self.baseByKey[key]then self.detachedEdits[#self.detachedEdits+1]={key=key,status='collision',entry=e}
        else
            local valid,err=self:validateEditedItem(e.group,e.item)
            if valid then
                -- Keep the base lookup empty: this is a personal record, not an imported original.
                add(e.group,e.item);self.baseByKey[key]=nil
                self.byKey[key].edit={status='custom',entry=e,item=e.item}
            else self.detachedEdits[#self.detachedEdits+1]={key=key,status='invalid',entry=e,error=err}end
        end
    end
    self.revision=self.revision+1;self.loaded=true
end
function Knowledge:load()
    local active,err=self:read(self.path,M.validate)
    if not active then active=self:read(self.bundle,M.validate);self.loadNote=active and 'Используется комплектная база.' or err end
    self.edits:load()
    if active then self:activate(active) else self.loaded=true;self.error='База недоступна. Бинды и остальные разделы работают.' end
    local personal,notes=store.load(self.personalPath,self.json,M.validatePersonal,M.personalDefaults,self.fs)
    self.personal=personal;self.personalWarning=notes[1]
    if self.policyPath then
        local policy=self:read(self.policyPath,function(v)
            if type(v)~='table' or v.schema_version~=1 or not model.array(v.decisions,40) then return nil end
            for _,d in ipairs(v.decisions) do
                if type(d)~='table' or not clean(d.id,100) or not clean(d.note,3000,true) then return nil end
            end
            return v
        end)
        if policy then for _,d in ipairs(policy.decisions) do
            self.policies[d.id]=d
            local aliases=({taser_copy={'taser'},vehicle_fire={'force'},camera_360={'bodycam'},ten_force={'10-66'}})[d.id]
            for _,id in ipairs(aliases or {})do self.policies[id]=d end
        end end
    end
    return active~=nil
end
function M.status(row)
    if row.edit then
        if row.edit.status=='conflict'or row.edit.status=='collision'then return 'Моя правка: нужно сравнение'end
        if row.edit.status=='custom'then return 'Моя карточка'end
        if row.edit.status=='override'then return 'Моя правка'end
    end
    local item=row.item;local value=item.interpretation_status
    if value~='reference_only' and value~='not_published' then value=item.verification_status end
    if row.group=='gaps' then return item.type=='resolved'and'Уточнено по новой редакции'or item.type=='conflict' and 'Есть расхождение' or 'Нужно уточнить' end
    return statuses[value] or 'Не проверено в игре'
end
function M.tone(row)
    if row.edit and(row.edit.status=='conflict'or row.edit.status=='collision')then return 'warning'end
    if row.edit and row.edit.status~='source'then return 'muted'end
    local s=row.item.verification_status
    if s=='historical_source_index'or(row.group=='gaps'and row.item.type=='resolved')then return 'muted'end
    if row.group=='gaps' or s=='conflict_pending'or s=='needs_review' then return 'warning' end
    if row.group=='articles' or row.group=='drafts' or row.group=='scenario_catalog' or
        row.item.interpretation_status=='reference_only' or row.item.interpretation_status=='not_published' then return 'muted' end
    return 'good'
end
function Knowledge:isFavorite(key)
    for _,id in ipairs(self.personal.favorites) do if key==id then return true end end
    return false
end
function Knowledge:department(value)
    if not ({EPD=true,FBI=true,Alcatraz=true})[value]then return nil end
    self.personal.department=value;self:changed();return true
end
function Knowledge:viewSettings(enabled,minutes)
    local copy=model.copy(self.personal);copy.view.reset_enabled=enabled;copy.view.reset_minutes=minutes
    local valid,err=M.validatePersonal(copy);if not valid then return nil,err end
    self.personal=valid;self:changed();return true
end
function Knowledge:changed(delay)
    self.personalDirty=true;self.personalChangedAt=self.now();self.personalDelay=delay or 0;self.personalError=nil;self.cache={}
end
function Knowledge:favorite(key)
    if not self.byKey[key] then return nil end
    for n,id in ipairs(self.personal.favorites) do if id==key then table.remove(self.personal.favorites,n);self:changed();return true end end
    if #self.personal.favorites>=500 then return nil,'Достигнут лимит избранного.' end
    self.personal.favorites[#self.personal.favorites+1]=key;self:changed();return true
end
function Knowledge:opened(key)
    if not self.byKey[key] then return end
    local out={key};for _,id in ipairs(self.personal.recent) do if id~=key and #out<40 then out[#out+1]=id end end
    self.personal.recent=out;self:changed()
end
function Knowledge:note(key,text)
    if not self.byKey[key] or not clean(text,4000,true) then return nil,'Заметка слишком велика.' end
    self.personal.notes[key]=text;self:changed(600);return true
end
function Knowledge:mapping(key,value)
    if not self.byKey[key] then return nil,'Запись недоступна.' end
    local candidate=model.copy(self.personal);candidate.mappings[key]=value
    local cleanValue,err=M.validatePersonal(candidate);if not cleanValue then return nil,err end
    self.personal=cleanValue;self:changed(600);return true
end
function Knowledge:flush()
    if not self.personalDirty then return true end
    local ok,err=store.save(self.personalPath,self.personal,self.json,M.validatePersonal,self.fs)
    if ok then self.personalDirty=false;self.personalError=nil else self.personalError=err end
    return ok,err
end
function Knowledge:tick()
    if self.personalDirty and not self.personalError and (core.elapsed(self.now(),self.personalChangedAt) or 0)>=self.personalDelay then self:flush() end
    local action=self.action;self.action=nil
    if action=='load' then
        if self.loaded and self.personalDirty and not self:flush() then self.operationError='Сначала сохраните личные правки.';return end
        self:load()
    elseif action=='preview_import'or action=='preview_bundle' then
        local path=action=='preview_bundle'and self.bundle or self.personalPath:gsub('_personal%.json$','_import.json')
        local data,err=self:read(path,M.validate)
        self.candidate=data;self.candidateSource=action=='preview_bundle'and'bundle'or'import';self.operationError=err
    elseif action=='apply_import' and self.candidate then
        local candidate=self.candidate;local ok,err=store.save(self.path,candidate,self.json,M.validate,self.fs,M.MAX_BYTES)
        if ok then self:activate(candidate);self.candidate=nil;self.loadNote='Обновлена локальная база.' end
        self.operationError=err
    elseif action=='rollback' then
        local prior,err=self:read(self.path..'.bak',M.validate)
        if prior then
            local ok;ok,err=store.save(self.path,prior,self.json,M.validate,self.fs,M.MAX_BYTES)
            if ok then self:activate(prior);self.loadNote='Возвращена предыдущая база.' end
        end
        self.operationError=err
    end
    if self.editAction then self:processEdit()end
end

function Knowledge:validateEditedItem(group,item)
    if type(item)~='table'or not clean(item.id,100)or not clean(title(item),900)or title(item):match('^%s*$')then
        return nil,'Введите название карточки.'
    end
    for _,field in ipairs(editModule.fields(group)or{})do
        if item[field]~=nil and not editModule.validField(field,item[field])then return nil,'Проверьте поле «'..(editModule.labels[field]or field)..'».'end
    end
    if group=='patrol'then return true end
    local candidate={schema_version=M.SCHEMA,catalog_version=self.data.catalog_version,
        sources=self.data.sources,patrol_profile=self.data.patrol_profile}
    for name in pairs(limits)do if name~='sources'then candidate[name]={}end end
    if group=='sources'then
        candidate.sources={};for n,s in ipairs(self.data.sources)do candidate.sources[n]=s.id==item.id and item or s end
    else candidate[group]={item}end
    local ok,valid,err=pcall(M.validate,candidate)
    if not ok then return nil,'Не удалось проверить поля личной карточки.'end
    return valid~=nil,err
end
function Knowledge:editSnapshot(key,group)
    local base=self.baseByKey[key]
    return {item=base and model.copy(base)or nil,sources=editModule.sourceStamp(base or(self.byKey[key]and self.byKey[key].item)or{id=key},self.sources,group),
        entry=self.edits.state.entries[key]and model.copy(self.edits.state.entries[key])or nil}
end
function Knowledge:processEdit()
    local a=self.editAction;self.editAction=nil;local ok,err,key
    local base=a.key and self.baseByKey[a.key]
    local function validate(group,item)return self:validateEditedItem(group,item)end
    if a.kind=='save'then
        key,err=self.edits:put(a.key,a.group,a.item,base,self.sources,self.data.catalog_version,validate,a.expected);ok=key~=nil
    elseif a.kind=='reset'then ok,err=self.edits:remove(a.key);key=a.key
    elseif a.kind=='resolve'then
        ok,err=self.edits:resolve(a.key,base,self.sources,a.choices,a.ackSource,a.expected,self.data.catalog_version,validate);key=a.key
    elseif a.kind=='export'then
        if self.edits.blocked then err='Сначала восстановите повреждённый файл личных карточек.'
        else ok,err=store.save(self.edits.path:gsub('_edits%.json$','_edits_export.json'),self.edits.state,self.json,editModule.validate,self.fs)end
    elseif a.kind=='preview_import'then
        self.editCandidate,err=self:read(self.edits.path:gsub('_edits%.json$','_edits_import.json'),editModule.validate)
        ok=self.editCandidate~=nil
    elseif a.kind=='import'and self.editCandidate then
        ok,err=self.edits:save(self.editCandidate,true);if ok then self.editCandidate=nil end
    else err='Неизвестное действие с личными карточками.'end
    if ok and a.kind~='export'and a.kind~='preview_import'then self:activate(self.data)end
    self.editResult={request=a,ok=ok==true,key=key,error=err}
end
function Knowledge:search(query,filters)
    filters=filters or {};query=folded(query):sub(1,1024)
    local key=table.concat({query,filters.group or '',filters.department or '',filters.status or '',tostring(filters.rp or ''),
        tostring(filters.favorite),tostring(filters.recent),filters.mode or'',filters.topic or'',tostring(filters.home)},'\0')
    if self.cache[key] then return self.cache[key] end
    local tokens={};for t in query:gmatch('%S+') do tokens[#tokens+1]=t end
    local recent={};for n,id in ipairs(self.personal.recent) do recent[id]=n end
    local result={}
    for _,r in ipairs(self.records) do
        local broad=not r.departments.EPD and not r.departments.FBI and not r.departments.Alcatraz
        local ok=(not filters.group or filters.group=='all' or r.group==filters.group) and
            (not filters.home or r.item.operation_id~=nil)and
            (filters.mode~='current'or not self:isArchived(r)and r.group~='gaps')and
            (not filters.topic or filters.topic=='all'or self:topic(r,filters.topic))and
            (not filters.department or filters.department=='all' or broad or r.departments[filters.department]) and
            (not filters.favorite or self:isFavorite(r.key)) and (not filters.recent or recent[r.key]) and
            (filters.rp==nil or (r.group=='commands' and r.item.rp_required==filters.rp))
        local status=filters.status
        if status=='index' then ok=ok and r.group=='articles'
        elseif status=='conflict' then ok=ok and ((r.group=='gaps'and r.item.type~='resolved')or r.item.verification_status=='conflict_pending'or r.item.verification_status=='needs_review')
        elseif status=='summary' then ok=ok and M.tone(r)=='good'
        elseif status=='personal'then ok=ok and r.edit and r.edit.entry~=nil
        elseif status=='personal_conflict'then ok=ok and r.edit and(r.edit.status=='conflict'or r.edit.status=='collision')
        elseif status=='rp_required' then ok=ok and r.group=='commands'and r.item.rp_required==true
        elseif status=='rp_free' then ok=ok and r.group=='commands'and r.item.rp_required==false end
        local searchText=r.search
        if filters.department and filters.department~='all'then searchText=r.departmentSearch[filters.department]or r.commonSearch end
        if ok then for _,t in ipairs(tokens) do if not searchText:find(t,1,true) then ok=false;break end end end
        if ok then
            local exact=query~='' and (r.titleSearch==query or folded(r.item.reference)==query or folded(r.item.id)==query)
            local score=exact and 100 or (query~='' and r.titleSearch:find(query,1,true) and 20 or 0)
            if r.group~='articles' then score=score+2 end
            if query==''and r.item.operation_id then score=score+30 end
            if r.departments[self.personal.department]then score=score+.5 end
            result[#result+1]={row=r,score=score,recency=recent[r.key] or 999}
        end
    end
    table.sort(result,function(a,b)
        if filters.recent and a.recency~=b.recency then return a.recency<b.recency end
        if a.score~=b.score then return a.score>b.score end
        if a.row.group==b.row.group then
            local ac,an=a.row.item.id:match('^([^:]+):(%d+%.?%d*)$');local bc,bn=b.row.item.id:match('^([^:]+):(%d+%.?%d*)$')
            if ac and bc and ac==bc and tonumber(an)~=tonumber(bn)then return tonumber(an)<tonumber(bn)end
        end
        return a.row.key<b.row.key
    end)
    local rows={};for _,r in ipairs(result) do rows[#rows+1]=r.row end
    self.cache={[key]=rows};return rows
end
local units={PM='ПМ (стоимость в валюте не установлена)',IC_years='IC лет',hours='часов',days='дней'}
function M.sanction(s)
    local amount=s.min~=nil and tostring(s.min) or 'не указано'
    if s.max~=nil and s.max~=s.min then amount=amount..'–'..s.max end
    local kind=({fine='Штраф',imprisonment='Лишение свободы'})[s.kind] or s.kind
    return kind..': '..amount..' '..(units[s.unit] or s.unit or '(единица не указана)')..(s.life_alternative and '; возможен пожизненный срок' or '')..
        (s.condition and (' · '..s.condition) or '')
        ..(s.alternative and s.alternative~=''and('; альтернатива: '..s.alternative)or'')
end
function Knowledge:isArchived(row)
    if not row or type(row.item)~='table'then return false end
    local item=row.item
    if item.verification_status=='historical_source_index'or item.kind=='archived_law'then return true end
    if (row.group=='articles'or row.group=='offenses')and type(item.source)=='table'then
        local source=self.sources[tostring(item.source.source_id)]
        return source~=nil and source.kind=='archived_law'
    end
    return false
end
function Knowledge:topic(row,topic)
    local i=row.item;if i.topic then return i.topic==topic end
    if topic=='law'then return row.group=='articles'or row.group=='sources'end
    if topic=='radio'then return row.group=='radio'or i.command and({['/r']=true,['/rn']=true,['/f']=true,['/fn']=true,['/d']=true,['/l']=true})[i.command]or false end
    local tokens=({road={'останов','транспорт','штраф','10-55','пдд'},rights={'задерж','адвокат','миранд','права','обыск'},wanted={'розыск','пеленг','/su','/setmark','/clear'},force={'оруж','тайзер','силы','10-66','колёс'}})[topic]or{}
    for _,token in ipairs(tokens)do if row.search:find(folded(token),1,true)then return true end end
    return false
end
function Knowledge:detail(row,department)
    local i=row.item;local lines={}
    local function add(label,value) if value~=nil and value~='' then lines[#lines+1]={label=label,text=tostring(value)} end end
    if row.edit and row.edit.status=='override'then add('Личная версия','Эту карточку изменили вручную. Исходник сохранён отдельно; личная правка не подтверждает норму сервера.')
    elseif row.edit and row.edit.status=='custom'then add('Моя карточка','Добавлена вручную. Она не входит в опубликованную базу сервера.')
    elseif row.edit and row.edit.status=='conflict'then add('Нужно сравнение','Изменился исходник или связанная тема. Сейчас показана новая карточка базы, личная правка сохранена и ждёт вашего решения.')end
    if self:isArchived(row)then add('Архивная редакция','Этот текст сохранён для прежних ссылок и заметок. Для текущего основания откройте действующую редакцию закона; подготовка розыска и штрафа по архивной статье недоступна.')end
    add('Моё пояснение',i.local_text)
    if i.verification_status=='needs_review'then add('Нужно сравнение','Связанный источник изменился после разбора карточки. Проверьте новую редакцию перед применением.')end
    if row.group=='offenses' then
        add('Условия',i.criterion)
        local personalSanctions=row.edit and(row.edit.status=='custom'or(row.edit.entry and row.edit.entry.patch and row.edit.entry.patch.sanctions))
        for _,s in ipairs(i.sanctions or {}) do add(personalSanctions and'Моя санкция (введена вручную)'or'По закону',M.sanction(s)) end
        add('Примечание',i.notes)
        add('В игре','Закон не устанавливает перевод IC-лет или ПМ в звёзды. Подтверждённые игровые пункты и их условные связи приведены отдельно ниже; минуты и суммы не выводятся по догадке.')
    elseif row.group=='commands' then
        add('RP',i.rp_required and 'Отыгровка обязательна перед командой.' or 'Эта команда не требует отыгровки по таблице Раздела XI.')
        add('В игре',i.note);add('Параметры','Аргументы, ранг, дальность и ответ сервера ещё не проверены.')
    elseif row.group=='rules' then
        add('Обязательность',({mandatory='Обязательно',conditional='При выполнении условий',optional='Дополнительно',informational='Информация'})[i.requirement] or i.requirement)
        add('Правило',i.text)
    elseif row.group=='scenario_catalog' then add('Процедура',i.design);add('Статус','Это пример для подготовки сценария, а не готовая автоматическая команда.')
    elseif row.group=='articles' then
        add('Закон',i.law_label);add('Статус',i.origin=='user_supplied_verbatim'and'Полный переданный текст статьи · актуальность подтверждена пользователем 28.10.2026; квалификацию проверяет офицер.'or'В базе есть номер и заголовок. Условия и санкция ещё не разобраны. Откройте источник перед применением.')
        add('Точный текст источника',i.text);add('Редакция',i.notes)
        local card=self.byKey['offenses:'..i.id];if card then add('Карточка','Для этой статьи есть разобранная карточка в разделе «Нарушения».') end
    elseif row.group=='radio' then add('Значение',i.meaning);add('Происхождение',i.origin)
    elseif row.group=='drafts' then
        if i.origin=='forum_recommendation' then
            add('Текст из темы форума',i.source_recommended_text)
            add('Как применяется название «Миранда»',i.legal_disclaimer)
            for _,text in ipairs(i.application_conditions or {})do add('Когда и как разъяснять права',text)end
            for _,text in ipairs(i.legal_basis or {})do add('Правовое основание',text)end
            if row.edit and row.edit.status=='override'and row.edit.entry.patch.steps then
                add('Мой вариант для бинда','Реплики ниже изменены вручную. Они могут отличаться от рекомендации из темы; сравните их с полным текстом выше.')
                if row.edit.entry.patch.binder_variant_note then add('Моё пояснение к репликам',i.binder_variant_note)end
            else add('Вариант для бинда',i.binder_variant_note)end
            for n,s in ipairs(i.steps or {})do add(s.type=='manual_field'and'Перед запуском' or 'Реплика '..(n-1),s.text or s.label or s.type)end
        else
            add('Происхождение','Наш вариант фраз. Сервер не устанавливает эти слова дословно.')
            for n,s in ipairs(i.steps or {}) do add('Шаг '..n,s.text or s.label or s.type) end
        end
    elseif row.group=='gaps' then add('Вопрос',i.text);add('До уточнения',i.resolution)
    elseif row.group=='sources' then
        add('Раздел',i.group);add('Проверен',i.source_reviewed_on or i.read_on)
        add('Охват',i.interpretation_status=='not_published' and 'Содержимое процедуры не опубликовано.' or
            i.interpretation_status=='reference_only' and 'Справочная тема; операционная процедура не выведена.' or 'Проверены текст и структура. Игровые механики этим не подтверждены.')
        add('Адрес',i.url)
    elseif row.group=='patrol' then
        local p=i.profile
        add('Экипаж','Выезд на вызов: минимум '..tostring(p.dispatch_min_crew or '?')..'; задержание в опасной зоне: минимум '..tostring(p.danger_zone_arrest_min_crew or '?')..'. Общий минимум обычного патруля не установлен.')
        add('Доклады','Обязательный фиксированный интервал не найден. 30 с предупреждения и toast на 10 с — наши настройки PA.')
        add('Запись','Для операции требуется реальная видеозапись. /me о включении камеры не включает запись игры.')
        for _,e in ipairs(p.events) do add('Событие',e.id..' · '..e.radio_code) end
        for _,t in ipairs(p.original_templates_not_mandated) do add('Наш шаблон '..t.id,t.text) end
        add('В PA','Патруль и экипаж настраиваются в «Инструменты → Патруль». {patrol_crew} берётся из подтверждённого состава. Команда, доклад и факт события учитываются отдельно.')
    end
    for _,id in ipairs(i.game_reasons or require('pa26_wanted_catalog').related(i.id))do
        local r=require('pa26_wanted_catalog').byId[id]
        if r then add('Игровой пункт /su · '..r.id,r.group_title..' / '..r.title..' · '..r.stars..' ур. '..r.mapping_status..'. '..r.note)end
    end
    for _,note in ipairs(i.department_notes or{})do
        if not department or department=='all'or department==note.department then add('Для '..note.department,note.text)end
    end
    local policy=self.policies[i.id]
    if policy then add('Решение для PA · '..(policy.date or ''),policy.note) end
    return lines
end
function Knowledge:sourceLines(row,department)
    local out={}
    local references={};for _,r in ipairs(row.refs)do references[#references+1]=r end
    for _,note in ipairs(row.item.department_notes or{})do
        if not department or department=='all'or department==note.department then
            for _,r in ipairs(note.sources)do references[#references+1]=r end
        end
    end
    local seen={}
    for _,r in ipairs(references) do
        local s=self.sources[tostring(r.source_id)]
        local key=tostring(r.source_id)..'\0'..(r.locator or'')
        if s and not seen[key]then seen[key]=true;out[#out+1]={title=s.title,locator=r.locator or '',date=s.source_reviewed_on or s.read_on or '',url=r.url or s.url} end
    end
    if row.item.local_source_url and row.item.local_source_url~=''then
        out[#out+1]={title='Указанный мною источник',locator='Личная ссылка; не проверена обновлятором',date=row.edit and row.edit.entry and row.edit.entry.updated_at or'вручную',url=row.item.local_source_url}
    end
    return out
end
-- These are editable bind drafts, never an implicit issuance. The player supplies
-- the command contract; there is no fabricated /su, fine, PM or stars conversion.
function Knowledge:compose(row,form,id,codec)
    if not row or (row.group~='offenses' and row.group~='articles') then return nil,'Выберите статью.' end
    if self:isArchived(row)then return nil,'Это архивная редакция. Выберите статью действующего закона.'end
    if row.edit and(row.edit.status=='conflict'or row.edit.status=='collision')then return nil,'Сначала сравните личную правку с обновившейся базой.'end
    if type(row.item.reference)~='string'or not row.item.reference:find('%S')then return nil,'Укажите в карточке номер статьи или точное обозначение основания.'end
    local kind=form.kind
    if kind~='wanted' and kind~='fine' then return nil,'Неизвестная процедура.' end
    if kind=='wanted'then return nil,'Для розыска откройте помощник и выберите игровой раздел/подпункт. Статья УК/АК и количество звёзд не являются аргументами /su.'end
    if not clean(form.part or '',32) or not clean(form.reason or '',180) then return nil,'Основание слишком велико.' end
    for _,text in ipairs({row.item.reference or row.title,form.part or '',form.reason or '',form.ic_name or ''})do
        if text:find('[{}@]')then return nil,'В статье, имени и основании используйте обычный текст без функций биндера.'end
    end
    local amount=kind=='wanted' and form.stars or form.fine
    if not clean(amount or '',16) or not amount:match('^%d+$') or tonumber(amount)<1 then return nil,'Укажите звёзды / сумму вручную.' end
    if not ({passport=true,appearance=true,ooc=true})[form.identity] then return nil,'Укажите, откуда известна личность.' end
    if kind=='fine' and form.identity=='ooc' then return nil,'OOC-режим для штрафа здесь не настроен.' end
    if kind=='fine' and form.masked then return nil,'Для IC штрафа сначала установите личность без маски.' end
    if form.identity=='passport' and not clean(form.ic_name or '',120) then return nil,'Проверьте IC имя.' end
    if form.identity=='passport' and (form.ic_name or ''):match('^%s*$') then return nil,'Введите IC имя из увиденного паспорта. Ник не заменяет паспорт.' end
    if form.identity=='appearance' and form.masked and not form.face_known then return nil,'Лицо под маской не установлено. Для розыска выберите отдельно OOC, если ситуация это допускает.' end
    if form.identity=='ooc' and form.ooc_ack~=true then return nil,'Подтвердите осознанный OOC-розыск.' end
    local command=form.command or ''
    if not clean(command,400) or not command:match('^/[a-z][a-z0-9_]*%s') or not command:find('{select_id}',1,true) or
        not command:find('{param1}',1,true) or not command:find('{param2}',1,true) then
        return nil,'Введите вашу проверенную команду с {select_id}, {param1} и {param2}. Порядок параметров сервер ещё не подтверждён.'
    end
    local verb=command:match('^/([a-z][a-z0-9_]*)')
    if kind=='wanted' and verb~='su' then return nil,'Для розыска требуется ваша проверенная команда /su.' end
    if kind=='fine' and ({su=true,me=true,['do']=true,r=true,rn=true,f=true,fn=true,d=true})[verb] then return nil,'Нужна команда выдачи штрафа.' end
    local allowed={select_id=true,param1=true,param2=true}
    for token in command:gmatch('{([^{}]+)}')do if not allowed[token]then return nil,'В шаблоне используйте только {select_id}, {param1} и {param2}.'end end
    local reason=(row.item.reference or row.title)..(form.part~='' and (' ч. '..form.part) or '')..(form.reason~='' and (' · '..form.reason) or '')
    local text
    if form.identity=='ooc' then text=command
    elseif kind=='fine' then text='/me заполнил постановление, указав основание: '..reason..'\n'..command
    elseif form.identity=='passport' then
        text='/me передал диспетчеру паспортные данные {param:ic_name} и основание розыска: '..reason..'\n'..command
    else text='/me передал диспетчеру установленные приметы и основание розыска: '..reason..'\n'..command end
    -- Named parameters use the existing binder's defaults. Positional param1/2
    -- do not read declared parameter defaults and must not be left in the draft.
    text=text:gsub('{param1}','{param:amount}'):gsub('{param2}','{param:basis}')
    -- Validate the actual RP line and the largest supported target ID.
    for line in text:gmatch('[^\n]+') do
        local example=line:gsub('{select_id}','1003'):gsub('{param:amount}',function()return amount end):
            gsub('{param:basis}',function()return reason end):gsub('{param:ic_name}',function()return form.ic_name or '' end)
        local _,err=core.encodeWire(example,codec);if err then return nil,'Сократите фразу / команду: '..err end
    end
    local b=model.newBinding(id);b.name=(kind=='wanted' and 'Розыск · ' or 'Штраф · ')..(row.item.reference or row.title)
    b.category='Из базы знаний';b.target_required=true;b.script=text
    b.stat=kind=='fine'and'fine_player'or'none'
    local sourceUrl=row.item.source and row.item.source.url or row.item.local_source_url or''
    if not sourceUrl:match('^https://forum%.exsellentrp%.com/')then return nil,'Для подготовки наказания укажите в своей карточке ссылку на статью официального форума.'end
    b.knowledge={catalog_version=self.data.catalog_version,article_id=row.item.id,reference=row.item.reference or row.title,
        source_url=sourceUrl,procedure=kind,identity=form.identity,manual_command_contract=true}
    if row.edit and(row.edit.status=='custom'or row.edit.status=='override')then
        b.knowledge.personal_origin=row.edit.status;b.knowledge.personal_updated_at=row.edit.entry.updated_at
    end
    b.parameters={{name='amount',label=kind=='wanted'and'Звёзды (вручную)'or'Сумма (вручную)',default=amount,type='integer',required=true},
        {name='basis',label='Статья и основание',default=reason,type='text',required=true}}
    if kind=='wanted'and form.identity=='passport'then
        b.parameters[#b.parameters+1]={name='ic_name',label='IC имя из увиденного паспорта (для текущей цели)',default='',type='text',required=true}
    end
    local parsed,err=binder.parse(text);if not parsed then return nil,err end
    return model.validateBinding(b)
end
return M

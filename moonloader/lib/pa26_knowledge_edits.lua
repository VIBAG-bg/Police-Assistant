-- Personal catalogue edits. The shipped/imported source catalogue is immutable.
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local store=require 'pa26_library'
local M={LIMIT=300};local Edits={};Edits.__index=Edits
local common={'title','reference','aliases','local_text','local_source_url'}
local specific={offenses={'criterion','notes','sanctions'},commands={'command','rp_required','note'},
    rules={'text','requirement','departments','department_notes'},scenario_catalog={'design','commands'},
    articles={'law_label'},radio={'meaning'},drafts={'steps','binder_variant_note'},
    gaps={'text','resolution'},sources={},patrol={}}
M.labels={title='Название',reference='Статья или обозначение',aliases='Слова для поиска',local_text='Моё пояснение',
    local_source_url='Моя ссылка',criterion='Когда применяется',notes='Примечание',sanctions='Санкции',
    command='Команда',rp_required='Требуется отыгровка',note='Пояснение',text='Текст',requirement='Обязательность',
    departments='Ведомства',design='Порядок действий',commands='Связанные команды',law_label='Название закона',
    meaning='Значение кода',steps='Реплики и шаги',binder_variant_note='Пояснение к варианту для бинда',resolution='До уточнения',
    department_notes='Пояснения для ведомств'}
function M.newItem(group)
    local item={title='Моя карточка',reference='',aliases={},local_text='',local_source_url=''}
    if group=='offenses'then item.criterion='';item.notes='';item.sanctions={}
    elseif group=='commands'then item.command='/mycommand';item.rp_required=true;item.note='';item.runtime_verified=false;item.sources={}
    elseif group=='rules'then item.text='';item.requirement='informational';item.departments={};item.sources={}
    elseif group=='scenario_catalog'then item.design='';item.commands={}
    elseif group=='articles'then item.law_label=''
    elseif group=='radio'then item.meaning=''
    elseif group=='drafts'then item.steps={};item.binder_variant_note='';item.source_ids={};item.origin='manual'
    elseif group=='gaps'then item.type='knowledge';item.text='';item.resolution='';item.sources={}
    else return nil end
    return item
end
function M.fields(group)
    if not specific[group]then return nil end
    local out={};for _,v in ipairs(common)do out[#out+1]=v end
    for _,v in ipairs(specific[group])do out[#out+1]=v end
    return out
end
local function clean(value,max,multi)
    return type(value)=='string'and #value<=max and core.validUtf8(value)and
        not value:find('[%z\1-\8\11\12\14-\31\127]')and(multi or not value:find('[\r\n]'))
end
local function validField(field,value)
    if field=='rp_required'then return type(value)=='boolean'end
    if field=='department_notes'then
        if not model.array(value,3)then return false end
        local seen={}
        for _,note in ipairs(value)do
            if type(note)~='table'or not({EPD=true,FBI=true,Alcatraz=true})[note.department]or seen[note.department]or
                not clean(note.text,8000,true)or not model.array(note.sources,8)then return false end
            seen[note.department]=true
            for _,r in ipairs(note.sources)do
                if type(r)~='table'or not clean(r.source_id,100)or not clean(r.url,600)or
                    not r.url:match('^https://forum%.exsellentrp%.com/')or(r.locator~=nil and not clean(r.locator,900))then return false end
            end
        end
        return true
    elseif field=='aliases'or field=='departments'or field=='commands'then
        if not model.array(value,100)then return false end
        for _,v in ipairs(value)do if not clean(v,900)then return false end end
        return true
    elseif field=='sanctions'then
        if not model.array(value,30)then return false end
        for _,s in ipairs(value)do
            if type(s)~='table'or not clean(s.kind,80)or(s.unit~=nil and not clean(s.unit,80))or
                (s.condition~=nil and not clean(s.condition,2000,true))or
                (s.alternative~=nil and not clean(s.alternative,2000,true))then return false end
            for _,k in ipairs({'min','max'})do if s[k]~=nil and(not core.finite(s[k])or s[k]<0)then return false end end
            if s.min~=nil and s.max~=nil and s.min>s.max then return false end
            if s.life_alternative~=nil and type(s.life_alternative)~='boolean'then return false end
        end
        return true
    elseif field=='steps'then
        if not model.array(value,100)then return false end
        for _,s in ipairs(value)do
            if type(s)~='table'or not clean(s.type,60)or(s.text~=nil and not clean(s.text,2000,true))or
                (s.label~=nil and not clean(s.label,900,true))or(s.key~=nil and not clean(s.key,100))then return false end
        end
        return true
    end
    if field=='local_source_url'then return clean(value,600)and(value==''or value:match('^https?://[^%s]+$')~=nil)end
    if field=='title'then return clean(value,900)and not value:match('^%s*$')end
    if field=='reference'or field=='law_label'then return clean(value,900)end
    if field=='command'then return clean(value,100)and value:match('^/[a-z][a-z0-9_]*$')~=nil end
    if field=='requirement'then return({mandatory=true,conditional=true,optional=true,informational=true})[value]==true end
    return clean(value,12000,true)
end
M.validField=validField
function M.equal(a,b)
    if type(a)~=type(b)then return false end
    if type(a)~='table'then return a==b end
    for k,v in pairs(a)do if not M.equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end
    return true
end
local function jsonValue(v,depth,budget)
    budget.n=budget.n+1
    if budget.n>100000 or depth>20 then return false end
    if type(v)=='table'then
        for k,item in pairs(v)do
            if not((type(k)=='string'and clean(k,200))or(type(k)=='number'and core.finite(k)and k>=1 and k==math.floor(k)))or
                not jsonValue(item,depth+1,budget)then return false end
        end
        return true
    end
    return(type(v)=='string'and clean(v,16000,true))or type(v)=='boolean'or(type(v)=='number'and core.finite(v))
end
function M.defaults()return {schema_version=1,next_id=1,entries={}}end
function M.validate(raw)
    if type(raw)~='table'or raw.schema_version~=1 or not core.finite(raw.next_id)or raw.next_id<1 or
        raw.next_id~=math.floor(raw.next_id)or raw.next_id>1000000000 or type(raw.entries)~='table'then
        return nil,'Формат файла личных карточек не поддерживается.'
    end
    local count,budget=0,{n=0}
    for key,e in pairs(raw.entries)do
        count=count+1
        if count>M.LIMIT or not clean(key,160)or type(e)~='table'or not specific[e.group]or
            not clean(e.id,100)or key~=e.group..':'..e.id or not clean(e.updated_at,80)then return nil,'Повреждена личная карточка.'end
        if e.kind=='override'then
            if not clean(e.base_version,120)or type(e.base_item)~='table'or e.base_item.id~=e.id or
                type(e.patch)~='table'or not model.array(e.base_sources,60)then return nil,'Повреждён исходник личной правки.'end
            local allowed={};for _,field in ipairs(M.fields(e.group))do allowed[field]=true end
            for field,value in pairs(e.patch)do
                if not allowed[field]or not validField(field,value)then return nil,'Повреждено поле личной правки: '..tostring(field)end
            end
            for _,s in ipairs(e.base_sources)do
                if type(s)~='table'or not clean(s.id,100)or not clean(s.url,600)or not clean(s.hash,100)then return nil,'Повреждена версия источника.'end
            end
        elseif e.kind=='custom'then
            if e.group=='sources'or e.group=='patrol'or type(e.item)~='table'or e.item.id~=e.id or
                not e.id:match('^local%-%d+$')or tonumber(e.id:match('(%d+)$'))>=raw.next_id then return nil,'Повреждена моя карточка.'end
            for _,field in ipairs(M.fields(e.group))do
                if e.item[field]~=nil and not validField(field,e.item[field])then return nil,'Повреждено поле моей карточки: '..field end
            end
        else return nil,'Неизвестный вид личной правки.'end
        if not jsonValue(e,0,budget)then return nil,'Личная карточка слишком велика или повреждена.'end
    end
    return raw
end
function M.sourceStamp(item,sources,group)
    local ids={}
    if group=='sources'then ids[item.id]=true end
    for _,name in ipairs({'source','duplicate_source'})do local s=item[name];if s then ids[tostring(s.source_id)]=true end end
    for _,s in ipairs(item.sources or{})do ids[tostring(s.source_id)]=true end
    for _,note in ipairs(item.department_notes or{})do for _,s in ipairs(note.sources or{})do ids[tostring(s.source_id)]=true end end
    for _,id in ipairs(item.source_ids or{})do ids[tostring(id)]=true end
    local out={}
    for id in pairs(ids)do
        local s=sources[id];out[#out+1]={id=id,url=s and s.url or'',hash=s and(s.snapshot_sha256 or'')or''}
    end
    table.sort(out,function(a,b)return a.id<b.id end)
    return out
end
function M.new(options)
    return setmetatable({json=options.json,fs=options.fs or store.fs,path=options.path,
        stamp=options.stamp or function()return os.date('!%Y-%m-%dT%H:%M:%SZ')end,state=M.defaults()},Edits)
end
function Edits:load()
    if not self.path then self.warnings={'Путь личных карточек не настроен.'};self.blocked=true;return end
    self.state,self.warnings=store.load(self.path,self.json,M.validate,M.defaults,self.fs)
    local present,valid=false,false
    for _,suffix in ipairs({'','.rollback','.bak'})do
        local ok,raw=pcall(self.fs.read,self.path..suffix)
        if ok and raw then present=true;if store.decode(raw,self.json,M.validate)then valid=true end end
    end
    self.blocked=present and not valid
    if self.blocked then self.warnings={'Не удалось прочитать личные карточки. Повреждённые файлы сохранены; импортируйте исправную копию.'}end
end
function Edits:save(state,repair)
    if self.blocked and not repair then return nil,'Файл личных карточек повреждён. В «Данных» импортируйте сохранённую копию; исходные файлы пока сохранены.'end
    if not self.path then return nil,'Путь личных карточек не настроен.'end
    local ok,err=store.save(self.path,state,self.json,M.validate,self.fs)
    if ok then self.state=state;self.blocked=false;self.warnings={}end
    return ok,err
end
function Edits:inspect(key,base,sources)
    local e=self.state.entries[key]
    if not e then return {status='source',item=base}end
    if e.kind=='custom'then return {status=base and'collision'or'custom',entry=e,item=base or e.item}end
    if not base then return {status='orphan',entry=e}end
    local conflicts={}
    for _,field in ipairs(M.fields(e.group))do
        if e.patch[field]~=nil and not M.equal(base[field],e.base_item[field])then conflicts[#conflicts+1]=field end
    end
    local sourceChanged=not M.equal(M.sourceStamp(base,sources,e.group),e.base_sources)or
        base.source_text_sha256~=e.base_item.source_text_sha256
    if #conflicts>0 or sourceChanged then
        return {status='conflict',entry=e,item=base,fields=conflicts,sourceChanged=sourceChanged}
    end
    local item=model.copy(base);for field,value in pairs(e.patch)do item[field]=model.copy(value)end
    return {status='override',entry=e,item=item}
end
function Edits:put(key,group,item,base,sources,version,validateItem,expected)
    if not specific[group]then return nil,'Этот раздел нельзя редактировать.'end
    if key and key:sub(1,#group+1)~=group..':'then return nil,'Раздел карточки изменился.'end
    if expected and(not M.equal(expected.item,base)or not M.equal(expected.sources,M.sourceStamp(base or item,sources,group))or
        not M.equal(expected.entry,self.state.entries[key]))then
        return nil,'Исходник изменился, пока карточка была открыта. Сначала сравните новые данные.'
    end
    local current=key and self.state.entries[key]
    if current and current.kind=='custom'and base then return nil,'Идентификатор личной карточки совпал с новой записью базы. Сначала сохраните её экспортом и разрешите совпадение.'end
    if current and current.kind=='override'and self:inspect(key,base,sources).status=='conflict'then
        return nil,'Сначала сравните личную правку с обновлённым исходником.'
    end
    local candidate=model.copy(self.state);local id
    if not key then
        if group=='sources'or group=='patrol'then return nil,'Новые источники и правила профиля добавляются через проверку базы.'end
        id=string.format('local-%06d',candidate.next_id);key=group..':'..id;candidate.next_id=candidate.next_id+1
    else id=key:sub(#group+2)end
    local result
    if base then
        result=model.copy(base)
        for _,field in ipairs(M.fields(group))do if item[field]~=nil then result[field]=model.copy(item[field])end end
    else result=model.copy(item)end
    result.id=id
    local valid,err=validateItem(group,result);if not valid then return nil,err end
    if base then
        local patch={}
        for _,field in ipairs(M.fields(group))do if not M.equal(result[field],base[field])then patch[field]=model.copy(result[field])end end
        candidate.entries[key]=next(patch)and{kind='override',group=group,id=id,base_version=version,base_item=model.copy(base),
            base_sources=M.sourceStamp(base,sources,group),patch=patch,updated_at=self.stamp()}or nil
    else
        candidate.entries[key]={kind='custom',group=group,id=id,item=result,updated_at=self.stamp()}
    end
    local ok,saveErr=self:save(candidate);return ok and key or nil,saveErr
end
function Edits:remove(key)
    if not self.state.entries[key]then return nil,'Личной правки уже нет.'end
    local candidate=model.copy(self.state);candidate.entries[key]=nil
    return self:save(candidate)
end
function Edits:resolve(key,base,sources,choices,ackSource,expected,version,validateItem)
    local e=self.state.entries[key]
    if not e or e.kind~='override'or not base then return nil,'Исходник этой правки недоступен.'end
    if not expected or not M.equal(expected.item,base)or not M.equal(expected.sources,M.sourceStamp(base,sources,e.group))or not M.equal(expected.entry,e)then
        return nil,'База снова изменилась. Откройте сравнение заново.'
    end
    local inspected=self:inspect(key,base,sources)
    if inspected.sourceChanged and not ackSource then return nil,'Подтвердите, что сверили обновившийся источник.'end
    local conflictSet={};for _,field in ipairs(inspected.fields or{})do conflictSet[field]=true end
    local patch={}
    for field,value in pairs(e.patch)do
        if conflictSet[field]and choices[field]~='mine'and choices[field]~='source'then return nil,'Выберите вариант для каждого изменившегося поля.'end
        if not conflictSet[field]or choices[field]=='mine'then if not M.equal(value,base[field])then patch[field]=model.copy(value)end end
    end
    local result=model.copy(base);for field,value in pairs(patch)do result[field]=model.copy(value)end
    local valid,err=validateItem(e.group,result);if not valid then return nil,err end
    local candidate=model.copy(self.state)
    candidate.entries[key]=next(patch)and{kind='override',group=e.group,id=e.id,base_version=version,base_item=model.copy(base),
        base_sources=M.sourceStamp(base,sources,e.group),patch=patch,updated_at=self.stamp()}or nil
    return self:save(candidate)
end
function M.summary(state)
    local changed,created=0,0
    for _,e in pairs(state.entries)do if e.kind=='custom'then created=created+1 else changed=changed+1 end end
    return changed,created
end
return M

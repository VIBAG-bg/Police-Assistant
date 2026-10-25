-- Separate on-disk documents; the UI still receives one in-memory model.
-- A small recovery record makes multi-document saves all-or-nothing on restart.
local model=require 'pa26_bindings'
local store=require 'pa26_library'
local M={SCHEMA=1}
local UserFiles={};UserFiles.__index=UserFiles
local kinds={'binds','notes','settings'}
local formats={binds='police-assistant.binds',notes='police-assistant.notes',settings='police-assistant.settings'}
local separated={bindings=true,next_id=true,wheel=true,notes=true,next_note_id=true}
local function checksum(text)
    local a,b=1,0
    for i=1,#text do a=(a+text:byte(i))%65521;b=(b+a)%65521 end
    return #text..':'..a..':'..b
end
local function legacy(raw,cfg)
    local known=model.defaults(cfg)
    if type(raw)~='table'then return nil,'Неверная библиотека.'end
    for k in pairs(raw)do if known[k]==nil then return nil,'Неизвестное поле старой библиотеки: '..tostring(k)..'. Перенос остановлен, исходный файл сохранён.'end end
    return model.validate(raw,cfg)
end
local function equal(a,b)
    if type(a)~=type(b)then return false end
    if type(a)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end
    return true
end
local function empty()
    local v=model.defaults();v.bindings={};v.next_id=1;v.notes={};v.next_note_id=1;v.wheel={0,0,0,0,0,0}
    v.settings.quick_key=0;v.settings.tips_key=0;v.settings.cancel_key=0
    return v
end
function M.partition(lib)
    local p={binds={format=formats.binds,schema=M.SCHEMA,next_id=lib.next_id,bindings=model.copy(lib.bindings),wheel=model.copy(lib.wheel)},
        notes={format=formats.notes,schema=M.SCHEMA,next_note_id=lib.next_note_id,notes=model.copy(lib.notes)},
        settings={format=formats.settings,schema=M.SCHEMA,data={}}}
    for k,v in pairs(lib)do if not separated[k]then p.settings.data[k]=model.copy(v)end end
    return p
end
function M.validate(kind,raw,cfg)
    if not formats[kind]or type(raw)~='table'or raw.format~=formats[kind]or raw.schema~=M.SCHEMA then
        return nil,'Неверный тип или версия файла: '..tostring(kind)..'.'
    end
    local allowed=kind=='binds'and{format=true,schema=true,next_id=true,bindings=true,wheel=true}or
        kind=='notes'and{format=true,schema=true,next_note_id=true,notes=true}or{format=true,schema=true,data=true}
    for k in pairs(raw)do if not allowed[k]then return nil,'В отдельном файле обнаружены посторонние данные: '..tostring(k)..'.'end end
    local v=empty()
    if kind=='settings'then
        if type(raw.data)~='table'then return nil,'Нет настроек.'end
        for k,x in pairs(raw.data)do
            if separated[k]then return nil,'Бинды и заметки должны храниться отдельно.'end
            if v[k]==nil then return nil,'Неизвестное поле настроек: '..tostring(k)..'.'end
            v[k]=model.copy(x)
        end
    elseif kind=='binds'then v.bindings=raw.bindings;v.next_id=raw.next_id;v.wheel=raw.wheel
    else v.notes=raw.notes;v.next_note_id=raw.next_note_id end
    local clean,err=model.validate(v,kind=='settings'and cfg or nil)
    if not clean then return nil,err end
    return M.partition(clean)[kind]
end
function M.combine(parts,cfg)
    local v=model.copy(parts.settings.data)
    v.bindings=model.copy(parts.binds.bindings);v.next_id=parts.binds.next_id;v.wheel=model.copy(parts.binds.wheel)
    v.notes=model.copy(parts.notes.notes);v.next_note_id=parts.notes.next_note_id
    return model.validate(v,cfg)
end
function M.exchange(lib,kind,id)
    if kind~='binds'and kind~='notes'then return nil,'Выберите бинды или заметки.'end
    local p=M.partition(lib)[kind]
    if id then
        local field=kind=='binds'and'bindings'or'notes';local found
        for _,row in ipairs(p[field])do if row.id==id then found=row;break end end
        if not found then return nil,'Сначала сохраните выбранную запись.'end
        p[field]={found};if kind=='binds'then p.wheel={0,0,0,0,0,0}end
    end
    return M.validate(kind,p)
end
function M.decodeExchange(text,json,kind)
    if kind~='binds'and kind~='notes'then return nil,'Неизвестный вид обмена.'end
    return store.decode(text,json,function(raw)
        if raw.format then return M.validate(kind,raw)end
        -- Read an old exchange/library, but take only the explicitly chosen kind.
        local prior,err=legacy(raw);if not prior then return nil,err end
        return M.exchange(prior,kind)
    end)
end
local function call(fs,name,...)
    local ok,a,b=pcall(fs[name],...);if not ok then return nil,'Ошибка файла: '..name end;return a,b
end
local function present(fs,path)
    return call(fs,'exists',path)or call(fs,'exists',path..'.rollback')or call(fs,'exists',path..'.bak')
end
local function transaction(raw)
    if type(raw)~='table'or raw.format~='police-assistant.storage-transaction'or raw.schema~=1 or
        not({prepared=true,committed=true})[raw.phase]or type(raw.files)~='table'then return nil,'Неверная запись восстановления.'end
    local out={format=raw.format,schema=1,phase=raw.phase,files={}};local count=0
    for kind,row in pairs(raw.files)do
        if not formats[kind]or type(row)~='table'or type(row.had_original)~='boolean'or
            type(row.after_checksum)~='string'or #row.after_checksum>50 or not row.after_checksum:match('^%d+:%d+:%d+$')or
            (row.had_original and(type(row.before_checksum)~='string'or #row.before_checksum>50 or not row.before_checksum:match('^%d+:%d+:%d+$')))or
            (not row.had_original and row.before_checksum~=false)then return nil,'Неверный раздел восстановления.'end
        out.files[kind]={had_original=row.had_original,before_checksum=row.before_checksum,after_checksum=row.after_checksum};count=count+1
    end
    if count==0 or count>3 then return nil,'Пустая запись восстановления.'end
    return out
end
function M.new(base,json,cfg,fs)
    return setmetatable({base=base,json=json,cfg=cfg,fs=fs or store.fs,known={},raw={}},UserFiles)
end
function UserFiles:path(kind)return self.base..'_'..kind..'.json'end
function UserFiles:validator(kind)return function(raw)return M.validate(kind,raw,self.cfg)end end
function UserFiles:read(kind)
    local path=self:path(kind)
    for _,suffix in ipairs({'','.rollback','.bak'})do
        local text=call(self.fs,'read',path..suffix)
        local value=text and store.decode(text,self.json,self:validator(kind))
        if value then return value,suffix~=''and('Восстановлен '..path..suffix)or nil end
    end
    return nil,'Не удалось прочитать '..path..'. Файл сохранён; запись заблокирована до восстановления.'
end
function UserFiles:clearTransaction()
    local path=self.base..'_files_pending.json'
    -- Keep the current decision until all older decisions have gone.
    for _,suffix in ipairs({'.bak','.rollback','.tmp',''})do
        if call(self.fs,'exists',path..suffix)and not call(self.fs,'remove',path..suffix)then return nil,'Не удалось завершить сохранение; запись восстановления сохранена.'end
    end
    for _,kind in ipairs(kinds)do for _,suffix in ipairs({'.pa26-next','.pa26-previous','.pa26-restore','.pa26-displaced'})do
        local p=self:path(kind)..suffix;if call(self.fs,'exists',p)then call(self.fs,'remove',p)end
    end end
    return true
end
function UserFiles:restore(path,text)
    if text==nil then
        if call(self.fs,'exists',path)and not call(self.fs,'remove',path)then return nil,'Не удалось отменить неполную запись.'end
        return true
    end
    if call(self.fs,'read',path)==text then return true end
    local temp,displaced=path..'.pa26-restore',path..'.pa26-displaced'
    if not call(self.fs,'write',temp,text)or call(self.fs,'read',temp)~=text then return nil,'Не удалось подготовить восстановление.'end
    if call(self.fs,'exists',displaced)and not call(self.fs,'remove',displaced)then return nil,'Копия восстановления занята.'end
    if call(self.fs,'exists',path)and not call(self.fs,'rename',path,displaced)then return nil,'Файл восстановления занят.'end
    if not call(self.fs,'rename',temp,path)or call(self.fs,'read',path)~=text then return nil,'Восстановление не завершено; сохранён повтор.'end
    return true
end
function UserFiles:recover()
    local path=self.base..'_files_pending.json'
    if not present(self.fs,path)then return true end
    local tx
    for _,suffix in ipairs({'','.rollback','.bak'})do
        local text=call(self.fs,'read',path..suffix);tx=text and store.decode(text,self.json,transaction)
        if tx then break end
    end
    if not tx then return nil,'Повреждена запись восстановления. Исходные файлы сохранены; запись заблокирована.'end
    -- Read and check every recovery source before touching any destination.
    local texts={}
    for _,kind in ipairs(kinds)do local row=tx.files[kind];if row then
        local required=tx.phase=='committed'or row.had_original
        local text=required and call(self.fs,'read',self:path(kind)..(tx.phase=='committed'and'.pa26-next'or'.pa26-previous'))or nil
        if required and type(text)~='string'then return nil,'Не хватает копии восстановления: '..kind..'.'end
        if required and checksum(text)~=(tx.phase=='committed'and row.after_checksum or row.before_checksum)then return nil,'Копия восстановления повреждена: '..kind..'. Исходные файлы сохранены.'end
        if tx.phase=='committed'and not store.decode(text,self.json,self:validator(kind))then return nil,'Неверная копия восстановления: '..kind..'.'end
        texts[kind]=text or false
    end end
    for _,kind in ipairs(kinds)do if tx.files[kind]then
        local ok,err=self:restore(self:path(kind),texts[kind]or nil);if not ok then return nil,err end
        if tx.phase=='prepared'and not tx.files[kind].had_original then
            -- A failed first save must not revive its uncommitted .bak later.
            for _,suffix in ipairs({'.bak','.rollback'})do local p=self:path(kind)..suffix
                if call(self.fs,'exists',p)and not call(self.fs,'remove',p)then return nil,'Не удалось убрать неполную резервную копию.'end
            end
        end
    end end
    return self:clearTransaction()
end
function UserFiles:load()
    local warnings={};local ok,err=self:recover()
    if not ok then self.blocked=err;warnings[#warnings+1]=err end
    local parts={};local active=present(self.fs,self:path('settings'))
    if active and not self.blocked then
        for _,kind in ipairs(kinds)do
            local value,note=self:read(kind);parts[kind]=value
            if note then warnings[#warnings+1]=note end
            if not value then self.blocked=note;break end
        end
        if not self.blocked then
            local lib,note=M.combine(parts,self.cfg)
            if lib then
                self.known=model.copy(parts);for _,kind in ipairs(kinds)do self.raw[kind]=call(self.fs,'read',self:path(kind))or false end
                return lib,warnings,false
            end
            self.blocked=note;warnings[#warnings+1]=note
        end
    elseif not self.blocked and(present(self.fs,self:path('binds'))or present(self.fs,self:path('notes')))then
        self.blocked='Найдены отдельные файлы без настроек. Сначала восстановите комплект; существующие файлы не заменены.'
        warnings[#warnings+1]=self.blocked
    end
    local legacyPath=self.base..'_library.json';local lib
    if present(self.fs,legacyPath)then
        for _,suffix in ipairs({'','.rollback','.bak'})do
            local text=call(self.fs,'read',legacyPath..suffix)
            lib=text and store.decode(text,self.json,function(v)return legacy(v,self.cfg)end)
            if lib then break end
        end
        if not lib then self.blocked='Старая библиотека повреждена. Исходные файлы сохранены; перенос заблокирован.';warnings[#warnings+1]=self.blocked end
    end
    lib=lib or model.defaults(self.cfg)
    if self.blocked then
        -- Do not enable fallback/demo bindings when the user's real file is missing.
        for _,b in ipairs(lib.bindings)do b.enabled=false end
        return lib,warnings,false
    end
    for _,kind in ipairs(kinds)do self.raw[kind]=false end
    self.legacy=present(self.fs,legacyPath)and true or false
    return lib,warnings,true
end
function UserFiles:save(lib)
    if self.blocked then return nil,self.blocked end
    local ok,err=self:recover();if not ok then return nil,err end
    lib,err=model.validate(lib,self.cfg);if not lib then return nil,err end
    local parts=M.partition(lib);local changed={};local texts={}
    for _,kind in ipairs(kinds)do
        if not equal(parts[kind],self.known[kind])then
            local encoded,value=pcall(self.json.encode,parts[kind])
            if not encoded or not store.decode(value,self.json,self:validator(kind))then return nil,'Не удалось подготовить отдельный файл: '..kind..'.'end
            texts[kind]=value;changed[kind]={had_original=call(self.fs,'exists',self:path(kind))and true or false,after_checksum=checksum(value),before_checksum=false}
        end
    end
    if not next(changed)then return true end
    for _,kind in ipairs(kinds)do
        if (call(self.fs,'read',self:path(kind))or false)~=self.raw[kind]then return nil,'Файл '..kind..' изменён вне PA. Перезапустите PA перед сохранением.'end
    end
    local count=0;local only
    for kind in pairs(changed)do count=count+1;only=kind end
    if count==1 then
        ok,err=store.save(self:path(only),parts[only],self.json,self:validator(only),self.fs)
        if not ok then return nil,err end
        self.known[only]=model.copy(parts[only]);self.raw[only]=call(self.fs,'read',self:path(only))or false
        return true,err
    end
    for _,kind in ipairs(kinds)do if changed[kind]then
        local path=self:path(kind);local text=texts[kind]
        if not call(self.fs,'write',path..'.pa26-next',text)or call(self.fs,'read',path..'.pa26-next')~=text then return nil,'Не удалось подготовить '..kind..'; прежние файлы сохранены.'end
        if changed[kind].had_original then
            local previous=call(self.fs,'read',path)
            if type(previous)~='string'or #previous>store.MAX_BYTES or not call(self.fs,'write',path..'.pa26-previous',previous)or
                call(self.fs,'read',path..'.pa26-previous')~=previous then return nil,'Не удалось сохранить резервную копию '..kind..'.'end
            changed[kind].before_checksum=checksum(previous)
        end
    end end
    local tx={format='police-assistant.storage-transaction',schema=1,phase='prepared',files=changed}
    local pending=self.base..'_files_pending.json'
    ok,err=store.save(pending,tx,self.json,transaction,self.fs);if not ok then return nil,err end
    for _,kind in ipairs(kinds)do if changed[kind]then
        ok,err=store.save(self:path(kind),parts[kind],self.json,self:validator(kind),self.fs)
        if not ok then local restored,note=self:recover();return nil,restored and err or(err..' '..tostring(note))end
    end end
    tx.phase='committed';ok,err=store.save(pending,tx,self.json,transaction,self.fs)
    if not ok then local restored,note=self:recover();return nil,restored and err or(err..' '..tostring(note))end
    self.known=model.copy(parts);for _,kind in ipairs(kinds)do self.raw[kind]=call(self.fs,'read',self:path(kind))or false end
    local cleared,note=self:clearTransaction()
    local migrated=self.legacy;self.legacy=false
    return true,not cleared and note or(migrated and'Бинды и заметки перенесены в отдельные файлы. Старая библиотека оставлена резервной копией.'or nil)
end
return M

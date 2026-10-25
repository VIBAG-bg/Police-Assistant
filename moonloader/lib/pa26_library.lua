-- Bounded JSON and verified replacement. Uses MoonLoader JSON through injection.
local config=require 'pa26_config'
local core=require 'pa26_core'
local M={MAX_BYTES=1024*1024}
M.fs={exists=config.fs.exists,write=config.fs.write,rename=config.fs.rename,remove=config.fs.remove,
    read=function(path)
        local f,err=io.open(path,'rb'); if not f then return nil,err end
        local text=f:read(M.MAX_BYTES+1); f:close(); return text or ''
    end}
local function call(fs,name,...)
    local ok,a,b=pcall(fs[name],...); if not ok then return nil,'Ошибка файла: '..name end; return a,b
end
function M.decode(text,json,validate)
    if type(text)~='string' or #text>M.MAX_BYTES or text:find('\0',1,true) or not core.validUtf8(text) then return nil,'JSON повреждён или слишком велик.' end
    local quoted,escaped,depth=false,false,0
    for i=1,#text do local c=text:sub(i,i)
        if quoted then if escaped then escaped=false elseif c=='\\' then escaped=true elseif c=='"' then quoted=false end
        elseif c=='"' then quoted=true elseif c=='{' or c=='[' then depth=depth+1; if depth>24 then return nil,'JSON вложен слишком глубоко.' end
        elseif c=='}' or c==']' then depth=depth-1; if depth<0 then return nil,'Повреждён JSON.' end end
    end
    local ok,value=pcall(json.decode,text:gsub('^\239\187\191',''))
    if not ok or type(value)~='table' then return nil,'Не удалось разобрать JSON.' end
    local checked,result,err=pcall(validate,value)
    if not checked then return nil,'Неверная структура JSON.' end
    return result,err
end
function M.load(path,json,validate,defaults,fs)
    fs=fs or M.fs
    if not call(fs,'exists',path) and not call(fs,'exists',path..'.rollback') and not call(fs,'exists',path..'.bak') then return defaults(),{},true end
    for _,suffix in ipairs({'','.rollback','.bak'}) do
        local text=call(fs,'read',path..suffix)
        local value=text and M.decode(text,json,validate)
        if value then return value,suffix=='' and {} or {'Восстановлена резервная копия '..path..suffix},false end
    end
    return defaults(),{'Библиотека повреждена. Исходные файлы сохранены; включите демо перед восстановлением.'},false
end
function M.save(path,value,json,validate,fs)
    fs=fs or M.fs
    local safe,err=validate(value); if not safe then return nil,err end
    local ok,text=pcall(json.encode,safe); if not ok or type(text)~='string' or #text>M.MAX_BYTES then return nil,'JSON не удалось подготовить.' end
    if not M.decode(text,json,validate) then return nil,'Подготовленный JSON не прошёл проверку.' end
    local temp,rollback=path..'.tmp',path..'.rollback'
    if call(fs,'exists',rollback) then
        if not call(fs,'exists',path) then if not call(fs,'rename',rollback,path) then return nil,'Не удалось восстановить .rollback.' end
        else local prior=call(fs,'read',rollback); local valid=prior and M.decode(prior,json,validate)
            local destination=path..(valid and '.bak' or '.rejected')
            if call(fs,'exists',destination) and not call(fs,'remove',destination) then return nil,'Резервная копия занята.' end
            if not call(fs,'rename',rollback,destination) then return nil,'Прежний .rollback сохранён.' end end
    end
    if not call(fs,'write',temp,text) or call(fs,'read',temp)~=text then return nil,'Запись не прошла проверку; прежний файл сохранён.' end
    local original=call(fs,'exists',path)
    if original and not call(fs,'rename',path,rollback) then return nil,'Не удалось подготовить замену.' end
    if not call(fs,'rename',temp,path) then
        if original then call(fs,'rename',rollback,path) end
        return nil,'Замена не выполнена. Проверьте исходный файл и .rollback.'
    end
    if original then
        local previous=call(fs,'read',rollback); local valid=previous and M.decode(previous,json,validate)
        local backup=path..(valid and '.bak' or '.rejected')
        if call(fs,'exists',backup) and not call(fs,'remove',backup) then return true,'Сохранено; прежний файл в .rollback.' end
        if not call(fs,'rename',rollback,backup) then return true,'Сохранено; прежний файл в .rollback.' end
    end
    return true
end
return M

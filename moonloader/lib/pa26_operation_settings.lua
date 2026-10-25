local shared=require 'pa26_patrol_settings'
local M={}
function M.defaults()
    return {enabled=false,manual=true,binder=true,demo=true,capture_chat=false,chat_window_ms=10000,chat_limit=10,
        timeout_ms=30000,confirm_ms=60000,history_limit=200,
        commands={'su','clear','cuff','uncuff','frisk','arrest','unmask','takelic','take','skip','unskip','break','hold','unhold','setmark'}}
end
function M.command(value)
    if type(value)~='string'then return nil end
    local name=value:match('^%s*/?([A-Za-z][A-Za-z0-9_]*)%s*$')
    if not name or #name>32 or name:lower():match('^pa26')then return nil end
    return name:lower()
end
function M.parseCommands(text)
    if type(text)~='string'or #text>4096 then return nil,'Список команд слишком длинный.'end
    local out,seen={},{}
    for line in text:gmatch('[^\r\n]+')do
        if not line:match('^%s*$')then
            local name=M.command(line)
            if not name then return nil,'Каждая строка — одно имя команды без аргументов, например cuff.'end
            if not seen[name]then seen[name]=true;out[#out+1]=name end
        end
    end
    if #out>64 then return nil,'В списке допускается до 64 команд.'end
    return out
end
function M.validate(raw)
    local out=M.defaults();if raw==nil then return out end
    if type(raw)~='table'then return nil,'Повреждены настройки журнала действий.'end
    for _,key in ipairs({'enabled','manual','binder','demo','capture_chat'})do
        if raw[key]~=nil then
            if type(raw[key])~='boolean'then return nil,'Неверный переключатель журнала: '..key end
            out[key]=raw[key]
        end
    end
    for _,row in ipairs({{'timeout_ms',1000,3600000},{'confirm_ms',1000,300000},{'history_limit',20,500},
        {'chat_window_ms',1000,120000},{'chat_limit',1,20}})do
        local value=raw[row[1]];if value==nil then value=out[row[1]]end
        if not shared.integer(value,row[2],row[3])then return nil,'Недопустимое значение: '..row[1]end
        out[row[1]]=value
    end
    if raw.commands~=nil then
        if not shared.array(raw.commands,64)then return nil,'Неверный список наблюдаемых команд.'end
        local seen={};out.commands={}
        for _,value in ipairs(raw.commands)do
            local name=M.command(value)
            if not name or seen[name]then return nil,'В списке нужны уникальные имена команд без аргументов.'end
            seen[name]=true;out.commands[#out.commands+1]=name
        end
    end
    return out
end
return M

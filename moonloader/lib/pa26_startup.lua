-- A bounded runtime handshake, separate from every user document.
local M={LIMIT=2048}
function M.path(directory)return directory..'\\config\\police_assistant_2026_startup.flag'end
function M.clear(directory)
    return os.remove(M.path(directory))
end
local function write(directory,status,message)
    local file=io.open(M.path(directory),'wb');if not file then return false end
    local body=status..'\n'..tostring(message or''):gsub('[%z\r\n]',' '):sub(1,M.LIMIT-16)
    local ok=file:write(body);local flushed=file:flush();local closed=file:close()
    return ok~=nil and flushed~=nil and closed~=nil
end
function M.block(directory,message)return write(directory,'blocked',message)end
function M.ready(directory)return write(directory,'ready','')end
function M.read(directory)
    local file=io.open(M.path(directory),'rb');if not file then return end
    local value=file:read(M.LIMIT+1);file:close()
    if not value or #value>M.LIMIT then return end
    local state,message=value:match('^(%a+)\n([^%z\r\n]*)$')
    if state=='blocked'or state=='ready'then return state,message end
end
function M.announce(message,encoding,api)
    api=api or _G
    if type(api.print)=='function'then api.print('[PA26] '..message)end
    if type(api.sampAddChatMessage)~='function'or type(api.isSampAvailable)~='function'then return false end
    local ok,available=pcall(api.isSampAvailable)
    if not ok or not available then return false end
    local text='[PA] '..message
    if encoding and encoding.CP1251 then
        local good,encoded=pcall(encoding.CP1251.encode,encoding.CP1251,text,'UTF-8')
        if good then return pcall(api.sampAddChatMessage,encoded,-1)end
    end
    return pcall(api.sampAddChatMessage,'[PA] Startup failed. Check MoonLoader libraries and moonloader.log.',-1)
end
return M

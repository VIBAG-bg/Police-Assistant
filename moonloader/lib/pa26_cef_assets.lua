-- Bounded browser-asset IO is deliberately separate from the 32 KiB INI reader.
-- Only our script tag and endpoint are changed; the server HUD code stays intact.
local M={MAX_BYTES=1048576,MARKER='<!-- PA26 CEF chat adapter -->'}
M.TAG=M.MARKER..'<script src="pa26-chat.js"></script>'
M.fs={}
function M.fs.read(path)
    local f,err=io.open(path,'rb');if not f then return nil,err end
    local text=f:read(M.MAX_BYTES+1)or'';f:close()
    if #text>M.MAX_BYTES then return nil,'asset_too_large' end
    return text
end
function M.fs.write(path,text)
    local f,err=io.open(path,'wb');if not f then return nil,err end
    local ok,note=f:write(text);if ok then ok,note=f:flush()end
    local closed,closeErr=f:close();if not ok or not closed then return nil,note or closeErr end
    return true
end
M.fs.remove=os.remove
function M.fs.replace(from,to)
    -- Same-directory replacement: no interval with a missing index.html.
    local ffi=require'ffi'
    if ffi.os~='Windows'then return os.rename(from,to)end
    ffi.cdef('int __stdcall MoveFileExA(const char*, const char*, unsigned long);')
    return ffi.load('kernel32').MoveFileExA(from,to,9)~=0
end
local function call(fs,name,...)
    local ok,a,b=pcall(fs[name],...);if ok then return a,b end
end
function M.commit(path,text,fs,expected)
    fs=fs or M.fs
    local tmp=path..'.pa26-tmp'
    if not call(fs,'write',tmp,text)or call(fs,'read',tmp)~=text then
        call(fs,'remove',tmp);return false,'asset_write'
    end
    -- Do not overwrite a launcher update that arrived during preparation.
    if expected and call(fs,'read',path)~=expected then
        call(fs,'remove',tmp);return false,'asset_changed'
    end
    if not call(fs,'replace',tmp,path)then call(fs,'remove',tmp);return false,'asset_replace'end
    if call(fs,'read',path)~=text then return false,'asset_verify'end
    return true
end
function M.ensure(path,fs,repair)
    fs=fs or M.fs
    local html,err=call(fs,'read',path..'index.html')
    if type(html)~='string'then return false,err=='asset_too_large'and err or'asset_missing'end
    if #html>M.MAX_BYTES then return false,'asset_too_large'end
    local script=call(fs,'read',path..'pa26-chat.js')
    if type(script)~='string'or #script==0 then return false,'adapter_file_missing'end
    local remaining,count=html:gsub(M.TAG:gsub('([^%w])','%%%1'),'')
    if count>1 or remaining:find(M.MARKER,1,true)or remaining:find('pa26-chat.js',1,true)then return false,'asset_tag_conflict'end
    if count==1 then return true,'asset_ready'end
    if not repair then return false,'adapter_missing'end
    local lower=html:lower();local at=lower:find('</body%s*>')
    if not at or html:find('%z')or not html:find('chatInputField',1,true)or not html:find('main.js',1,true)then
        return false,'asset_contract'
    end
    local backup=path..'index.html.pa26-before-repair'
    if not call(fs,'write',backup,html)or call(fs,'read',backup)~=html then return false,'asset_backup'end
    local ok,reason=M.commit(path..'index.html',html:sub(1,at-1)..M.TAG..html:sub(at),fs,html)
    return ok,ok and'asset_restored'or reason
end
return M

-- One read/hash at PA startup, never an input/frame-time file probe.
-- Unknown launcher code is not permission to patch its HTML or start IPC.
local M={reviewed='c458636ad5201c00aaf1e21e80bbf7fa74670734fcd0f66c812d495c893bd410',max_bytes=4194304}
function M.read(path)
 local f=io.open(path,'rb');if not f then return end
 local text=f:read(M.max_bytes+1);f:close()
 if type(text)=='string'and #text>0 and #text<=M.max_bytes then return text end
end
function M.new(path,read,hash)
 local cached,reason
 return function()
  if cached~=nil then return cached,reason end
  cached=false;reason='cef_contract_unreviewed'
  local ok,text=pcall(read or M.read,path..'main.js')
  if not ok or type(text)~='string'or #text==0 or #text>M.max_bytes then reason='cef_contract_missing';return false,reason end
  local good,digest=pcall(function()return(hash or require('pa26_author_io').hash)(text)end)
  if good and digest==M.reviewed then cached=true;reason='cef_contract_reviewed'end
  return cached,reason
 end
end
return M

-- Actual Windows x86 SHA capability, read-only launcher observation, no GTA process.
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/');local root=assert(source:match('^(.*)/tests/'))
local game=os.getenv('LOCALAPPDATA')..'/Exsellent Launcher/game/'
package.path=root..'/moonloader/lib/?.lua;'..game..'moonloader/lib/?.lua;'..package.path
package.cpath=game..'moonloader/lib/?.dll;'..package.cpath
local hash=require('pa26_author_io').hash;local compat=require 'pa26_cef_compat'
assert(hash('abc')=='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
local readCount,hashCount=0,0
local function read(p)readCount=readCount+1;return compat.read(p)end
local function digest(text)hashCount=hashCount+1;return hash(text)end
local check=compat.new(game..'cef/assets/hud/',read,digest)
local clock=require('pa26_chat_perf').clock(require 'ffi');local at=clock();local allowed,reason=check();local elapsed=clock()-at
for i=1,1000 do local again=check();assert(again==allowed)end
assert(readCount==1 and hashCount<=1)
local report=string.format('{"status":"passed","checks":1003,"reviewed_contract":%s,"reason":"%s","startup_ms":%.6f,"file_reads":%d,"hash_calls":%d,"game_started":false,"live_file_written":false}',tostring(allowed),reason,elapsed,readCount,hashCount)
local f=assert(io.open(root..'/tests/CEF_CONTRACT_NATIVE32_0440.json','wb'));f:write(report);f:close();print(report)

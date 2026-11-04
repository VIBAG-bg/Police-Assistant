-- Real x86 Windows job/crypto/file path; game files are READ ONLY.
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/');local root=assert(source:match('^(.*)/tests/'))
local game='C:/Users/35987/AppData/Local/Exsellent Launcher/game/'
package.path=root..'/moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path
package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
local json=require'cjson';local socket=require'socket';local compat=require'pa26_cef_compat'
local box=root..'/tests/cef-contract-sandbox/native-job'
local c=compat.runtime(box..'/MoonLoader',json,{cacheRoot=box,hudRoot=game..'cef/assets/hud'})
local began=socket.gettime();local r
repeat r=c:check(math.floor((socket.gettime()-began)*1000));if not c.done then socket.sleep(.02)end until c.done or socket.gettime()-began>25
assert(c.done and r.allowed and r.state=='CONTRACT_COMPATIBLE',json.encode(r))
assert(r.sha256=='d7526b3e76b4d9492407e77728be4ac8383b535600e62a3885fd1c785a4d29d2'and not r.known)
local elapsed=(socket.gettime()-began)*1000;local at=socket.gettime()
for i=1,100000 do assert(c:check(i)==r)end
local cached=(socket.gettime()-at)*1000;c:close()
local result={status='passed',checks=100004,initialization_ms=elapsed,cached_100000_calls_ms=cached,
 environment='Windows x86 LuaJIT + child Windows PowerShell 5.1 + shared verifier',report=r,game_started=false,live_game_written=false}
local f=assert(io.open(root..'/tests/CEF_ADAPTIVE_NATIVE32_0450.json','wb'));f:write(json.encode(result));f:close();print(json.encode(result))

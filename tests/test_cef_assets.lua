local assets=require'pa26_cef_assets'
local storage=require'pa26_config'
local bridgeModule=require'pa26_chat_bridge'
local function make()
    local original='<html><head><script src="main.js"></script></head><body><input id="chatInputField">'..string.rep(' ',86000)..'</body></html>'
    local files={['hud/index.html']=original,['hud/pa26-chat.js']='window.PA26Chat={};'}
    local writes,removed={},{}
    local fs={read=function(path)return files[path]end,
        write=function(path,text)writes[#writes+1]=path;files[path]=text;return true end,
        replace=function(from,to)files[to]=files[from];files[from]=nil;return true end,
        remove=function(path)removed[#removed+1]=path;files[path]=nil;return true end}
    return files,fs,original,writes,removed
end
local f,fs,original,writes=make()
local ok,reason=assets.ensure('hud/',fs,true);check(ok);eq(reason,'asset_restored')
eq(f['hud/index.html.pa26-before-repair'],original)
eq(f['hud/index.html']:gsub(assets.TAG:gsub('([^%w])','%%%1'),''),original)
local count=#writes;check(assets.ensure('hud/',fs,true));eq(#writes,count,'no rewrite on an ordinary check')
check(#f['hud/index.html']>32768);check(not f['hud/index.html']:sub(1,32769):find(assets.MARKER,1,true))
-- Actual production readers: the INI bound is kept; the asset reader sees the tag.
check(assets.fs.write(TEST_TEMP_PATH,f['hud/index.html']))
eq(#storage.fs.read(TEST_TEMP_PATH),32769)
eq(assets.fs.read(TEST_TEMP_PATH),f['hud/index.html'])
check(assets.fs.write(TEST_TEMP_PATH,string.rep('x',assets.MAX_BYTES+1)))
local raw,err=assets.fs.read(TEST_TEMP_PATH);eq(raw,nil);eq(err,'asset_too_large')
-- Removing the launcher tag is repaired idempotently, never by editing main.js.
f['hud/index.html']=original;check(assets.ensure('hud/',fs,true))
for _,p in ipairs(writes)do check(not p:find('main.js',1,true));check(not p:find('.dll',1,true))end
for _,case in ipairs({'missing','js_missing','js_empty','large','nul','structure','conflict','double','extra'})do
    local f,fs,original,writes=make()
    if case=='missing'then f['hud/index.html']=nil
    elseif case=='js_missing'then f['hud/pa26-chat.js']=nil
    elseif case=='js_empty'then f['hud/pa26-chat.js']=''
    elseif case=='large'then f['hud/index.html']=string.rep('x',assets.MAX_BYTES+1)
    elseif case=='nul'then f['hud/index.html']=original..'\0'
    elseif case=='structure'then f['hud/index.html']='<body>different HUD</body>'
    elseif case=='conflict'then f['hud/index.html']=original..assets.MARKER
    elseif case=='extra'then f['hud/index.html']=original..assets.TAG..assets.MARKER
    else f['hud/index.html']=original..assets.TAG..assets.TAG end
    local old=f['hud/index.html'];check(not assets.ensure('hud/',fs,true));eq(f['hud/index.html'],old);eq(#writes,0)
end
for _,fail in ipairs({'backup_write','backup_verify','tmp_write','tmp_verify','replace','changed','verify'})do
    local f,fs,original=make();local read,write,replace=fs.read,fs.write,fs.replace
    fs.write=function(path,text)
        if fail=='backup_write'and path:find('before-repair',1,true)or fail=='tmp_write'and path:find('pa26-tmp',1,true)then return nil end
        local ok=write(path,text)
        if fail=='backup_verify'and path:find('before-repair',1,true)or fail=='tmp_verify'and path:find('pa26-tmp',1,true)then f[path]='broken'end
        if fail=='changed'and path:find('pa26-tmp',1,true)then f['hud/index.html']='new launcher HTML'end
        return ok
    end
    fs.replace=function(from,to)
        if fail=='replace'then return nil end
        local ok=replace(from,to);if fail=='verify'then f[to]='new launcher HTML'end;return ok
    end
    check(not assets.ensure('hud/',fs,true))
    if fail~='changed'and fail~='verify'then eq(f['hud/index.html'],original)end
    eq(f['hud/index.html.pa26-tmp'],nil)
end
f,fs,original,writes=make();check(not assets.ensure('hud/',fs,false));eq(#writes,0)
-- The same production adapter and bounded reader are used by the bridge.
local files,assetFs,html,assetWrites=make();local enabled=true;local attempts=0;local logs={}
local server={}
for _,name in ipairs({'settimeout','bind','listen','close'})do server[name]=function()return 1 end end
function server:getsockname()return'127.0.0.1','39001'end
function server:accept()return nil,'timeout'end
local env={path='hud/',assetFs=assetFs,fs={read=function()error('INI reader must not read HTML')end},
    token=function()return string.rep('a',48)end,json={encode=function(v)return TEST_JSON_ENCODE(v)end,decode=function(v)return TEST_JSON_DECODE(v)end},
    settings=function()return{enabled=enabled,diagnostics=true}end,log=function(text)logs[#logs+1]=text end,
    socket=function()attempts=attempts+1;if attempts==1 then error('temporarily unavailable')end;return{tcp=function()return server end}end,
    message=function()end,command=function()end}
local b=bridgeModule.new(env);check(not b:start());eq(b.reason,'socket_module')
b:tick(10);check(b.server);eq(b.reason,'endpoint_published');eq(attempts,2)
local endpoint=files['hud/pa26-chat-endpoint.js'];check(type(endpoint)=='string')
files['hud/pa26-chat-endpoint.js']=nil;b:tick(5010);eq(files['hud/pa26-chat-endpoint.js'],endpoint)
files['hud/index.html']=html;b:tick(10010);check(files['hud/index.html']:find(assets.TAG,1,true))
local n=#assetWrites;b:tick(10011);eq(#assetWrites,n,'no frame-by-frame filesystem writes')
b:close();files['hud/pa26-chat-endpoint.js']=nil;b:tick(20000);eq(files['hud/pa26-chat-endpoint.js'],nil);eq(b.server,nil)
-- Backoff, disable/enable, timer reset and close are all independent of game APIs.
enabled=false;b=bridgeModule.new(env);n=#assetWrites;check(not b:start());eq(b.status,'disabled');eq(#assetWrites,n)
b:tick(10);local calls=attempts;enabled=true;b:tick(100);eq(attempts,calls)
b:tick(2510);check(b.server);b:close()
local fails=0;env.socket=function()fails=fails+1;error('offline')end
b=bridgeModule.new(env);b:tick(10);eq(fails,1)
for now=11,2509 do b:tick(now)end;eq(fails,1)
b:tick(2510);eq(fails,2);b:tick(1);eq(fails,3,'clock reset must not stall recovery')
local before=#logs;for now=2,2500 do b:tick(now)end;eq(#logs,before,'same failure does not flood the log')
check(not table.concat(logs,'\n'):find(string.rep('a',48),1,true));b:close()
env.socket=function()return{tcp=function()return server end}end
b=bridgeModule.new(env);check(b:start());b.state={at=1,busy=true};b.pending={{old=true}};b.pages.old={ack=9}
server.accept=function()return nil,'closed'end;b:tick(5000)
eq(b.server,nil);eq(b.reason,'socket_accept');eq(b.state,nil);eq(b.pending,nil);eq(b.pages.old.ack,9)
server.accept=function()return nil,'timeout'end;b:tick(7499);eq(b.server,nil)
b:tick(7500);check(b.server);eq(b.reason,'endpoint_published')
local replayed=0;b.commands.example=function()replayed=replayed+1 end
check(b:exchange(TEST_JSON_ENCODE({schema=1,page='old',chat=false,dialog=false,busy=false,events={{id=9,kind='local',text='/example'}}}),7510))
b:dispatch(7511);eq(replayed,0,'lost acknowledgement must not repeat an accepted command')
check(b:exchange(TEST_JSON_ENCODE({schema=1,page='old',chat=false,dialog=false,busy=false,events={{id=10,kind='local',text='/example'}}}),7512))
b:dispatch(7513);eq(replayed,1,'a new event after reconnect still works');b:close()
-- Early main initialization must run before the first SA:MP wait/yield.
local fixture=require'support.fixture'
files,assetFs,html=make()
local fixtureFs={}
for _,name in ipairs({'read','write','replace','remove'})do
    fixtureFs[name]=function(path,...)
        local mapped='hud/'..path:match('([^/\\]+)$')
        if name=='replace'then local to=...;return assetFs.replace(mapped,'hud/'..to:match('([^/\\]+)$'))end
        return assetFs[name](mapped,...)
    end
end
local s=fixture({available=false,cefAssets=fixtureFs})
check(files['hud/index.html']:find(assets.TAG,1,true));eq(s.waits[1],100);eq(s.commands.pa26,nil)
onScriptTerminate(s.script)

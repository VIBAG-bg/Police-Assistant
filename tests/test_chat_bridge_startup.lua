local m=require'pa26_chat_bridge'
local function create(options)
    options=options or{};local logs,writes={},{}
    local server={closed=false}
    function server:settimeout()if options.fail=='socket_timeout'then return nil end;return 1 end
    function server:bind()if options.fail=='socket_bind'then return nil end;return 1 end
    function server:listen()if options.fail=='socket_listen'then return nil end;return 1 end
    function server:getsockname()return options.address or'127.0.0.1',options.port==nil and'39001'or options.port end
    function server:close()self.closed=true;return 1 end
    function server:accept()return nil,'timeout'end
    local env={path='hud/',fs={read=function()return options.missing and''or m.MARKER end,exists=function()return true end,
        write=function(path,text)if options.fail=='endpoint_write'then return nil end;writes[path]=text;return true end},
        token=function()return options.weak and'bad'or string.rep('a',48)end,
        json={encode=function(v)if options.fail=='endpoint_encode'then error('unavailable')end;return TEST_JSON_ENCODE(v)end,decode=TEST_JSON_DECODE},
        socket=function()if options.fail=='socket_module'then error('missing')end;return{tcp=function()if options.fail=='socket_create'then return nil end;return server end}end,
        settings=function()return{enabled=true,accentEnabled=true,diagnostics=options.log~=false,accent='PRIVATE_PREFIX'}end,
        log=function(text)logs[#logs+1]=text end,message=function()end,command=function()end}
    return m.new(env),server,logs,writes
end
for _,port in ipairs({39001,'39001',1,'1',65535,'65535'})do
    local b,s,logs,writes=create({port=port});check(b:start());eq(b.status,'waiting');eq(b.reason,'endpoint_published')
    check(writes['hud/pa26-chat-endpoint.js']:find(':'..tonumber(port)..'/',1,true))
    check(#logs>=2);check(b:start());b:close();check(s.closed)
end
for _,port in ipairs({0,'0',65536,'65536',-1,'-1',1.5,'1.5','1e3','abc',false,'','39001/path'})do
    local b,s=create({port=port});check(not b:start());eq(b.reason,'socket_address');check(s.closed)
end
local b,s=create({address='0.0.0.0'});check(not b:start());eq(b.reason,'socket_address');check(s.closed)
for _,reason in ipairs({'socket_module','socket_create','socket_timeout','socket_bind','socket_listen','endpoint_encode','endpoint_write'})do
    local b,s,logs=create({fail=reason});check(not b:start());eq(b.status,'unavailable');eq(b.reason,reason)
    check(table.concat(logs,'\n'):find(reason,1,true));check(not table.concat(logs,'\n'):find('PRIVATE_PREFIX',1,true))
end
b,s=create({weak=true});check(not b:start());eq(b.reason,'token')
b,s=create({missing=true});check(not b:start());eq(b.reason,'adapter_missing')
local logs,writes;b,s,logs,writes=create({log=false});check(b:start());eq(#logs,0);b:tick(1);b:tick(6000);eq(b.reason,'browser_no_exchange');eq(#logs,0);b:close()
b,s,logs=create();check(b:start());b:tick(1);b:tick(6000);eq(b.reason,'browser_no_exchange')
local before=#logs;b:tick(7000);b:tick(8000);eq(#logs,before,'no repeated waiting log every frame')
local packet={schema=1,page='new',chat=false,dialog=false,busy=false,events={},diagnostics={field=true,sendHook=true,accentConfigured=true,applied=1,submitted=1,rejected=0}}
check(b:exchange(TEST_JSON_ENCODE(packet),9000));eq(b.status,'connected');eq(b.reason,'browser_exchange')
local joined=table.concat(logs,'\n');check(joined:find('browser_ready',1,true));check(joined:find('manual_counts',1,true))
check(not joined:find(string.rep('a',48),1,true));check(not joined:find('PRIVATE_PREFIX',1,true))
before=#logs;check(b:exchange(TEST_JSON_ENCODE(packet),9010));eq(#logs,before)
packet.diagnostics.applied=2;check(b:exchange(TEST_JSON_ENCODE(packet),9020));eq(#logs,before,'counter logging is limited')
check(b:exchange(TEST_JSON_ENCODE(packet),15000));check(#logs>before)
packet.diagnostics.applied=-1;before=#logs;check(b:exchange(TEST_JSON_ENCODE(packet),15010));eq(#logs,before,'invalid diagnostics are never logged')
check(not b:busy(18000));eq(b.reason,'heartbeat_lost');b:close()
-- Diagnostics is opt-in via validated settings; old files gain the default,
-- explicit off survives validation and any update.
local model=require'pa26_bindings';local core=require'pa26_core'
local seed=model.defaults(core.defaults());eq(seed.settings.cef_chat_diagnostics,true)
seed.settings.cef_chat_diagnostics=false;eq(assert(model.validate(seed,core.defaults())).settings.cef_chat_diagnostics,false)
seed.settings.cef_chat_diagnostics=nil;eq(assert(model.validate(seed,core.defaults())).settings.cef_chat_diagnostics,true)
local fixture=require'support.fixture';local f=fixture({demo=false,library=seed});f.step();if not f.frames[1].condition()then f.commands.pa26()end
f.page('settings');f.click='Профиль##settings-tab-profile';f.render()
f.toggle='Диагностика чата##cef-chat-diagnostics';f.render();f.step(650)
eq(f.workspace.library.settings.cef_chat_diagnostics,false)
local saved=f.savedLibrary();eq(saved.settings.cef_chat_diagnostics,false)
onScriptTerminate(f.script)

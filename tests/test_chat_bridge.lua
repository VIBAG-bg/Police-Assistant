local bridgeModule=require 'pa26_chat_bridge'
local messages,commands,logs,writes={},{},{},{}
local json={encode=function(value)return TEST_JSON_ENCODE(value)end,decode=function(value)return TEST_JSON_DECODE(value)end}
local active=true
local b=bridgeModule.new({path='cef/',json=json,fs={read=function()return bridgeModule.MARKER end,exists=function()return true end,
    write=function(path,text)writes[path]=text;return true end},settings=function()return{enabled=active,accentEnabled=true,accent='[Русский акцент]:',filters={}}end,
    message=function(text)messages[#messages+1]=text end,command=function(text)commands[#commands+1]=text end,log=function(text)logs[#logs+1]=text end})
local function body(events,page,chat)
    return json.encode({schema=1,page=page or'page',chat=chat==true,dialog=false,busy=chat==true,events=events or{}})
end
local localCalls=0;b.commands.pa26=function(args)localCalls=localCalls+1;eq(args,'hello')end
local events={{id=1,kind='message',text='Паспорт показан.'},{id=2,kind='command',text='/tazer'},{id=3,kind='local',text='/pa26 hello'}}
local r=json.decode(assert(b:exchange(body(events,nil,true),100)))
eq(r.ack,3);eq(#messages,1);eq(#commands,1);eq(localCalls,0)
local busy,chat,dialog=b:busy(101);check(busy and chat and not dialog)
check(b:exchange(body(events),110));eq(#messages,1);eq(#commands,1)
b:dispatch(120);eq(localCalls,1);b:dispatch(120);eq(localCalls,1)
check(not b:busy(1700));eq(b.status,'waiting')
-- Full validation happens before any message, focus update or action is accepted.
local bad={{id=4,kind='message',text='Не принимать.'},{id=5,kind='local',text='/pa26 hello\n/su 1 6 test'}}
check(not b:exchange(body(bad),1800));eq(#messages,1)
check(not b:exchange(body({{id=5,kind='message',text='A'},{id=4,kind='message',text='B'}}),1800));eq(#messages,1)
active=false;assert(b:exchange(body({{id=4,kind='local',text='/pa26 hello'},{id=5,kind='message',text='Отключено.'}}),1900));b:dispatch(1901);eq(localCalls,1);eq(#messages,1);active=true
-- Repeated HUD reloads do not exhaust a permanent page limit.
for i=1,20 do assert(b:exchange(body({},'reload'..i),2000+i))end
local pages=0;for _ in pairs(b.pages)do pages=pages+1 end;eq(pages,4)
assert(b:exchange(body({{id=1,kind='local',text='/pa26 hello'}},'last'),2200));b:dispatch(5500);eq(localCalls,1);eq(#logs,1)
-- Deduplicate only opposite backends; identical messages from one backend are real events.
check(b:observe('Текст.','native',10000));check(b:observe('Текст.','native',10001))
check(not b:observe('Текст.','cef',10002));check(not b:observe('Текст.','cef',10003));check(b:observe('Текст.','cef',10004))
check(b:observe('Текст.','native',13000));check(b:observe('Другое.','cef',13001))
-- Bounded HTTP, origin and request-token enforcement, including partial requests.
b.route='/'..string.rep('a',48)..'/exchange'
local function request(payload,extra,method,path)
    return(method or'POST')..' '..(path or b.route)..' HTTP/1.1\r\nOrigin: sampcef://assets\r\nContent-Type: application/json\r\nContent-Length: '..#payload..'\r\n'..(extra or'')..'\r\n'..payload
end
local good=request(body({}))
check(b:request(good,20000):find('200 OK',1,true));check(b:request(good:sub(1,-5),20000)==nil)
check(b:request(good:gsub('sampcef://assets','https://foreign.example'),20000):find('403 Forbidden',1,true))
check(b:request(request(body({}),nil,nil,'/wrong'),20000):find('403 Forbidden',1,true))
check(b:request(request(body({}),'Transfer-Encoding: chunked\r\n'),20000):find('400 Bad Request',1,true))
check(b:request(request(body({}),'Content-Length: 2\r\n'),20000):find('400 Bad Request',1,true))
check(b:request(request(body({}),nil,'OPTIONS'),20000):find('204 No Content',1,true))
check(b:request(request(body({}),nil,'GET'),20000):find('405 Method Not Allowed',1,true))
check(b:request(string.rep('a',4100),20000):find('400 Bad Request',1,true))
-- A real-shaped socket interface: nonblocking reads and partial writes.
local client={at=1,output='',closed=false}
function client:getpeername()return'127.0.0.1',1000 end
function client:settimeout(value)eq(value,0);return 1 end
function client:receive(size)local part=good:sub(self.at,self.at+19);self.at=self.at+#part;return nil,'timeout',part end
function client:send(text,first)local last=math.min(#text,first+22);self.output=self.output..text:sub(first,last);if last==#text then return last end;return nil,'timeout',last end
function client:close()self.closed=true;return 1 end
local server={accepted=false}
function server:accept()if self.accepted then return nil,'timeout'end;self.accepted=true;return client end
function server:close()return 1 end
b.server=server
for now=21000,22000,10 do b:tick(now)end
check(client.closed);check(client.output:find('200 OK',1,true));eq(#b.clients,0)
b:close();check(b.closed);eq(b.server,nil)
-- Startup binds only loopback and does not load a browser DLL or fixed port.
local startServer={}
function startServer:settimeout(n)eq(n,0);return 1 end
function startServer:bind(ip,port)eq(ip,'127.0.0.1');eq(port,0);return 1 end
function startServer:listen(n)eq(n,6);return 1 end
function startServer:getsockname()return'127.0.0.1',39001 end
function startServer:close()return 1 end
b.closed=false;b.env.token=function()return string.rep('a',48)end;b.env.socket=function()return{tcp=function()return startServer end}end
check(b:start());check(writes['cef/pa26-chat-endpoint.js']:find('http://127.0.0.1:39001/',1,true));b:close()
b.closed=false;b.env.token=function()return'weak'end;check(not b:start());eq(b.status,'unavailable')
-- Old queued input cannot cross a reconnect or a disabled adapter.
local session='one';b.env.session=function()return session end
b.commands.pa26=function()localCalls=localCalls+1 end
local packet={schema=1,page='sessions',chat=false,dialog=false,busy=false,events={{id=1,kind='local',text='/pa26',session='one'}}}
check(b:exchange(json.encode(packet),30000));session='two';b:dispatch(30001);eq(localCalls,1)
packet.events={{id=2,kind='local',text='/pa26',session='one'}};check(b:exchange(json.encode(packet),30002));b:dispatch(30003);eq(localCalls,1)
packet.events={{id=3,kind='local',text='/pa26',session='two'}};check(b:exchange(json.encode(packet),30004));active=false;b:dispatch(30005);eq(localCalls,1)

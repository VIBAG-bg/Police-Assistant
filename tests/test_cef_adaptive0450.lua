local m=require 'pa26_chat_bridge';local json={encode=TEST_JSON_ENCODE,decode=TEST_JSON_DECODE}
local called=0
local function bridge(known)
 local b=m.new({json=json,compatibility=function()end,settings=function()return{enabled=true}end,message=function()called=called+1 end})
 b.handshakeChallenge=string.rep('c',48);b.compatibilityReport={known=known,state='CONTRACT_COMPATIBLE',fingerprint='profile',runtime='WAITING'}
 return b
end
local function send(b,hello,now,events)
 return json.decode(assert(b:exchange(json.encode({schema=1,page='page',chat=true,dialog=false,busy=true,events=events or {},compatibility=hello}),now or 1)))
end
for _,known in ipairs({true,false})do
 local b=bridge(known);local event={{id=1,kind='message',text='PRIVATE test content'}}
 local r=send(b,nil,1,event);check(not r.enabled);eq(called,0);eq(b.state,nil)
 local h={protocol=2,challenge=b.handshakeChallenge,fingerprint='profile',phase='hello',capabilities={dom=true,send=true,emit=true,incoming=true,focus=true}}
 r=send(b,h,2,event);check(not r.enabled);eq(r.compatibility.phase,'ack');eq(called,0)
 h.phase='confirmed';r=send(b,h,3,event);check(r.enabled);eq(called,1)
 eq(b.compatibilityReport.state,known and'KNOWN_VERIFIED'or'RUNTIME_VERIFIED');eq(b.compatibilityReport.runtime,'CONFIRMED')
 for _=1,100 do send(b,h,4,event)end;eq(called,1,'Retries cannot duplicate incoming events')
 h.challenge=string.rep('b',48);r=send(b,h,5,event);check(not r.enabled);eq(called,1)
 called=0
end
for _,missing in ipairs({'dom','send','emit','incoming','focus'})do
 local b=bridge(false);local h={protocol=2,challenge=b.handshakeChallenge,fingerprint='profile',phase='hello',capabilities={dom=true,send=true,emit=true,incoming=true,focus=true}}
 h.capabilities[missing]=false;check(not send(b,h,0).enabled);h.phase='confirmed';check(not send(b,h,1).enabled)
 local r=send(b,h,12001);check(not r.enabled);eq(b.compatibilityReport.runtime,'FAILED');eq(b.compatibilityReport.fallback,'handshake_timeout')
end
local b=bridge(false);local h={protocol=9,challenge=b.handshakeChallenge,phase='confirmed'};check(not send(b,h,0).enabled)
local logs={};b.env.log=function(text)logs[#logs+1]=text end
send(b,h,12001,{{id=1,kind='message',text='PRIVATE test content'}});eq(called,0)
for _,text in ipairs(logs)do check(not text:find('PRIVATE',1,true))end

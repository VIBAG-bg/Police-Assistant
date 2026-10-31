local m=require 'pa26_chat_bridge';local policy=require 'pa26_chat_text';local calls=0;local original=policy.policy
policy.policy=function(...)calls=calls+1;return original(...)end
local settings={enabled=true,accentEnabled=true,accent='[Акцент]:',filters={},manual_chat=require('pa26_manual_chat').defaults(),rp_text=require('pa26_rp_settings').defaults()}
local version=1;local b=m.new({settings=function()return settings end,commandsRevision=function()return version end,
 json={encode=TEST_JSON_ENCODE,decode=TEST_JSON_DECODE},session=function()return'one'end})
local function exchange(rev)return TEST_JSON_DECODE(assert(b:exchange(TEST_JSON_ENCODE({schema=1,page='page',chat=true,dialog=false,busy=true,events={},policyRevision=rev}),100)))end
local initial=exchange();eq(calls,1);local revision=initial.policyRevision
for _=1,100 do local r=exchange(revision);eq(calls,1,'Unchanged settings must not be revalidated');eq(r.policyUnchanged,true);eq(r.chatText,nil);check(#TEST_JSON_ENCODE(r)<300)end
settings.rp_text.body_limit=91;local changed=exchange(revision);eq(calls,2);check(changed.chatText);eq(changed.chatText.manual.threshold,91)
revision=changed.policyRevision;b.commands.add=function()end;version=2;changed=exchange(revision);check(changed.localCommands[1]=='add');eq(calls,3)
settings.enabled=false;changed=exchange(changed.policyRevision);eq(changed.enabled,false)
local legacy=exchange();check(legacy.chatText,'Old adapters keep the full contract')
-- Losing the lease while the native cursor still owns text must not trigger IO.
local reads=0;local native=true;local enabled=true
local guarded=m.new({path='virtual/',assetFs={read=function()reads=reads+1 end},inputActive=function()return native end,
 settings=function()return{enabled=enabled}end})
guarded.server={accept=function()return nil,'timeout'end};guarded.waitWarned=true
for now=1,1000 do guarded:tick(now)end;eq(reads,0)
native=false;enabled=false;guarded:tick(5001);local at=guarded.assetAt
for now=5002,5100 do guarded:tick(now)end;eq(guarded.assetAt,at);eq(reads,0,'Disabled integration still uses a bounded deadline')
local perf=require 'pa26_chat_perf';local now=0;local logs={};local p=perf.new(function()return now end,function(line)logs[#logs+1]=line end)
local f=p:wrap('context',function()now=now+.1;return 7 end);eq(f(),7);eq(next(p.rows),nil)
p:setEnabled(true);for _=1,100 do eq(f(),7)end;p:record('chat contents must not be accepted',10);p:setEnabled(false)
eq(#logs,1);check(logs[1]:find('context:',1,true));check(not logs[1]:find('contents',1,true))

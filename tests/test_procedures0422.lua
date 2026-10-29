local parser=require 'pa26_procedure_input';local model=require 'pa26_bindings';local prefs=require 'pa26_procedure_settings'
for _,head in ipairs({'ticket','setmark'})do
 local p=assert(parser.parse(head,''));check(not p.id);eq(p.kind,head=='ticket'and'fine'or'mark')
 p=assert(parser.parse(head,' 37 '));eq(p.id,37)
 for _,bad in ipairs({'-1','1.2','nan','37\n/r spam','999999'})do check(not parser.parse(head,bad))end
end
local p=assert(parser.parse('ticket','37 00150 Запрещающий сигнал'));eq(p.amount,'150');eq(p.basis,'Запрещающий сигнал')
for _,bad in ipairs({'37 0 Причина','37 -1 Причина','37 10','37 1e3 Причина','37 10\tПричина','37 9999999999 Причина'})do check(not parser.parse('ticket',bad))end
check(not parser.parse('setmark','37 555123'));check(not parser.parse('other','37'))
local cfg=assert(prefs.validate(nil));eq(cfg.pm_rate,0);eq(cfg.fine_command,'/ticket {id} {amount} {basis}');check(cfg.fine_verified)
for _,v in ipairs({-1,1000001,0/0,1.1,'1'})do local c=model.copy(cfg);c.pm_rate=v;check(not prefs.validate(c))end
local old=model.copy(cfg);old.fine_command='';old.fine_verified=false;old.fine_source='';old.fine_intercept=nil;old.mark_intercept=nil;old.pm_rate=nil
local migrated=assert(prefs.validate(old));check(migrated.fine_verified);eq(migrated.fine_command,cfg.fine_command);eq(old.fine_command,'')
old.fine_source='Я отключил команду';local own=assert(prefs.validate(old));eq(own.fine_command,'');check(not own.fine_verified)
old.fine_command='/myfine {id} {amount} {basis}';own=assert(prefs.validate(old));eq(own.fine_command,old.fine_command)
local sanctions=require 'pa26_sanctions';local raw=TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON)
check(require('pa26_knowledge').validate(raw));local cat=sanctions.new(raw);eq(#cat.rows,150)
local rules=parser.trackingRules(raw);eq(#rules,9);eq(#parser.trackingRules(nil),0)
for i,text in ipairs(rules)do check(text:match('^6%.'..(i+8)..'%.'));local exact=false
 for _,row in ipairs(raw.rules)do if row.id:match('^reg%-current:')and row.text:find(text,1,true)then exact=true end end
 check(exact,'Rule and notes must be an exact current-source excerpt')
end
check(rules[3]:find('Примечание:',1,true));check(rules[7]:find('смерти',1,true));check(not rules[9]:find('Спойлер:',1,true))
local count=0
for _,r in ipairs(cat.rows)do for _,b in ipairs(r.branches)do
 count=count+1;check(r.text:find(b.source_excerpt,1,true));eq(b.source_text_sha256,r.hash);check(b.min<=b.max)
end end;eq(count,145)
eq(cat:branch('AK:40',1).min,1);check(cat:branch('AK:40',1).alternative:find('предупреждение',1,true))
eq(cat:branch('AK:41',1).min,3);eq(cat:branch('AK:41',2).max,15)
eq(cat:branch('AK:42',2).min,10);eq(cat:branch('AK:47',2).max,100)
eq(#cat:search('','road'),13);eq(#cat:search('страхов','all'),1)
local b=cat:branch('AK:41',1);check(not sanctions.money(b,0,'min'));eq(sanctions.money(b,100,'min'),'300');eq(sanctions.money(b,101,'mid'),'505')
check(not sanctions.money({min=1000000,max=1000000},1000000,'max'))
local f={amount='222',basis='Мой текст'};check(sanctions.select(f,cat.byId['AK:41'],2));eq(f.amount,'222');check(cat:valid(f));f.sanction_hash='changed';check(not cat:valid(f))
local flow=require 'pa26_procedure_flow';local clock=1000;local state={session='s',localId=5,local_nick='Officer',demo=false,alive=true,focused=true,paused=false,blocked=false}
local generation=1;local opened,passed,notices={},{},{};cfg.enabled=true
local c=flow.new({settings=function()return cfg end,codec=codec,now=function()return clock end,context=function()return state end,
 epoch=function()return 1 end,generation=function()return generation end,suggest=function()return{id=37}end,
 resolve=function(kind,id,g)return{id=id,name='Driver',generation=g}end,
 open=function(kind,args,target)opened[#opened+1]={kind=kind,p=args,t=target}end,
 pass=function(raw)passed[#passed+1]=raw end,notice=function(why)notices[#notices+1]=why end})
check(c:capture('ticket','37 200 Причина'));state.blocked=true;c:tick(state,clock);eq(#opened,0);state.blocked=false;c:tick(state,clock);eq(#opened,1);eq(opened[1].p.amount,'200')
check(c:capture('setmark','37'));generation=2;c:tick(state,clock);eq(#opened,1);eq(#notices,1)
check(c:capture('setmark','37'));clock=clock+6000;c:tick(state,clock);eq(#opened,1)
cfg.mark_intercept=false;check(c:capture('setmark','37 raw server arguments'));c:tick(state,clock);eq(passed[1],'/setmark 37 raw server arguments')
cfg.enabled=false;check(c:capture('ticket','37 1 server reason'));c:tick(state,clock);eq(#passed,2)

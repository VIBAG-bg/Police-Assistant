local C=require 'pa26_coord_share';local cfg=require('pa26_field_settings').defaults().coordinates
cfg.enabled=true;cfg.observe=true
local s={session='s',ped=1,x=1,y=2,z=3,interior=0,focused=true,paused=false,blocked=false,alive=true}
local p=assert(C.parse('[FN] 13:44 Player[55]: Мои координаты: -1984 442 35 (Doherty, квадрат H-18)'))
eq(p.x,-1984);eq(p.y,442);eq(p.z,35);eq(p.sender_verified,false)
p=assert(C.parse('Мои координаты: 0 0'));check(p.height_unknown);eq(p.x,0)
for _,text in ipairs({'/fn Мои координаты: 1 2 3','Мои координаты: 1 2 3 4','Мои координаты: 1 2 3 /cuff 4',
 'Мои координаты: nan 1 2','Мои координаты: 99999 1 2','Мои координаты: 1 2 (unclosed',
 'Мои координаты: 1,2,3','Мои координаты: 1 2 3 (OK) garbage','Мои координаты: 1 2 3\n/setmark 1',
 'Мои координаты: 1 2 3 Мои координаты: 4 5 6'})do check(not C.parse(text),text)end
local packet=assert(C.format(s,cfg,codec,'Ganton','H-18'));check(packet.line:match('^/fn '));check(#packet.wire<=127)
cfg.channel='/sms';check(not C.format(s,cfg,codec));cfg.sms_verified=true;cfg.phone='1234';check(not C.format(s,cfg,codec))
cfg.phone='123456';packet=assert(C.format(s,cfg,codec));check(packet.line:find('/sms 123456 (( ',1,true));cfg.channel='/fn'
local c=C.new({});c:tick(s,0,cfg);check(c:observe('[FN] X: Мои координаты: 1 2 3',0,s,cfg))
local token=c.offer.token;check(not c:decide(token,true),'Unpainted offer cannot be accepted')
c:shown(token);s.typing=true;c:tick(s,1,cfg);check(not c:decide(token,true));s.typing=false;c:tick(s,2,cfg)
check(c:decide(token,false));eq(c.accepted,nil)
check(not c:observe('[FN] X: Мои координаты: 1 2 3',3,s,cfg))
check(c:observe('[FN] X: Мои координаты: 1 2 3',6000,s,cfg));token=c.offer.token;c:shown(token)
check(c:decide(token,true));check(c.accepted and c.accepted.x==1)
for i=1,1000 do c.offer=nil;c:observe('Мои координаты: '..i..' 2 3',6000+i*3001,s,cfg)end
check(#c.order<=32);local count=0;for _ in pairs(c.cache)do count=count+1 end;check(count<=32)
s.session='new';c:tick(s,4000000,cfg);eq(c.offer,nil);c:reset();eq(next(c.cache),nil)

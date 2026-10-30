local B=require 'pa26_stolen_bulletin';local grid=require 'pa26_map_grid';local cfg=require('pa26_copilot_settings').defaults();local copy=require('pa26_bindings').copy
local b=B.new(function()return cfg end);local msg='[Внимание] Угнан транспорт Bobcat (Цвет: Бордовый). Последний раз замечен в районе Garcia (Неизвестное место)'
check(b:observe(msg,100));check(not b:observe(msg,1001));local map=grid.defaults();map.enabled=true
local row=b:view(1002,map);check(row);eq(row.model,'Bobcat');eq(row.color,'Бордовый');eq(row.area,'Garcia');check(row.targetCell);local zone=B.zone('Garcia');check(zone)
eq(row.square,grid.cell(map,zone.x,zone.y,0).label);check(row.targetLabel:find('приблизительно',1,true))
map.cell_size=500;eq(b:view(1003,map).square,grid.cell(map,zone.x,zone.y,0).label)
check(not b:correct({model='Injected\n/su 42'},1004,row.revision));check(b:correct({model='Sultan',area='Unknown district'},1004,row.revision));row=b:view(1005,map);eq(row.model,'Sultan');check(not row.targetCell);eq(row.square,'')
check(not b:correct({area='Garcia'},1005,row.revision-1));check(not b:correct({area={}},1005,row.revision));check(not b:view(600101,map))
cfg.stolen_enabled=false;check(not b:observe(msg,1006));cfg.stolen_enabled=true;check(b:observe(msg,10000));cfg.stolen_highlight=false;check(not b:view(10001,map).targetCell);cfg.stolen_highlight=true
for _,bad in ipairs({'/do '..msg,msg..' ( Intruder_Name )','[Внимание] Угнан транспорт\nBobcat',string.rep('x',2049),'Игрок сказал: '..msg})do check(not B.parse(bad),bad)end
b:clear();check(not b:view(10002,map));local missing=B.values(nil);check(not missing.stolen_location:find('Garcia',1,true));eq(missing.stolen_model,'')
local target=grid.cell(map,zone.x,zone.y,0);local view={kind='map',a=.1,b=0,c=0,d=-.1,ox=400,oy=400,left=0,top=0,right=800,bottom=800}
local geometry=grid.geometry(map,view,nil,target,'УГОН: Garcia');local border=0;for _,line in ipairs(geometry.lines)do if line.target then border=border+1 end end;eq(border,4)
map.enabled=false;eq(#grid.geometry(map,view,nil,target).lines,0)
local cp,v,s=require('support.copilot_fixture')();s.cfg.require_patrol=true;cp.env.bulletin=function()return {model='Bobcat',color='Бордовый',area='Garcia',square='J-6'}end
local plan=assert(cp:propose('dispatch_stolen'));local text=table.concat(plan.prepared.lines,'\n');check(text:find('Garcia',1,true));check(text:find('Doherty',1,true));check(not text:find('курс неизвестно',1,true))
local p=require 'pa26_fast_pt';local a={id=42,name='First_Name',ped=8,generation=1,distance=49,source='current'};local state={ped=1}
local far=copy(a);far.id=43;far.distance=51;local close=copy(a);close.id=44;close.distance=1;close.source='selected'
eq(p.resolve({a,close},state,50).id,42);eq(p.resolve({far,close},state,50).id,44)
close.fallback=true;close.visible=true;close.colleague=true;check(not p.resolve({close},state,50));close.colleague=false;check(p.resolve({close},state,50));close.visible=false;check(not p.resolve({close},state,50))
cp,v,s=require('support.copilot_fixture')();cp.fastPtLive=copy(a);cp.fastPtLiveAt=s.now;check(cp:requestFastPt({a}));local offer=s.has('fast_pt');check(offer);eq(#offer.prepared.lines,1);eq(offer.prepared.lines[1],'/pt 42');check(not offer.needsPatrol)
cp.fastPtLive.generation=2;check(not cp:accept(offer));cp.fastPtLive=copy(a);offer.seen=true;check(cp:decide(offer.token,false));eq(#s.plans,0)
check(cp:requestFastPt({a}));offer=s.has('fast_pt');check(cp:accept(offer));cp.fastPtLiveAt=s.now+1;s.tick(1);local sent=s.plans[#s.plans];check(sent);eq(#sent.lines,1);eq(sent.lines[1],'/pt 42')
cp.fastPtLive.distance=51;check(not cp:validPlan(sent));cp.fastPtLive.distance=1;cp.fastPtLive.name='Reused_Id';check(not cp:validPlan(sent))
local malformed=copy(a);malformed.ped=nil;check(not p.valid(malformed,state,50));malformed=copy(a);malformed.generation=nil;check(not p.valid(malformed,state,50))
cp,v,s=require('support.copilot_fixture')();local bulletin={model='Bobcat',color='Бордовый',area='Garcia',square='J-6',revision=1}
cp.env.bulletin=function()return bulletin end;local request=assert(cp:propose('dispatch_stolen'));check(cp:accept(request));s.tick()
local active=s.plans[#s.plans];cp:onExecution('sent_line',{plan=active},active.lines[1]);bulletin.revision=2;check(not cp:validPlan(active),'Changing a bulletin after RP invalidates its old radio report')

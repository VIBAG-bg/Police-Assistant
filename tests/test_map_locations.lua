local grid=require 'pa26_map_grid';local model=require 'pa26_bindings';local core=require 'pa26_core'
local alerts=require 'pa26_alerts';local guard=require 'pa26_radio_guard';local prefs=require 'pa26_preferences'
local session=require 'pa26_patrol_session';local events=require 'pa26_patrol_events';local eventSettings=require 'pa26_patrol_event_settings'
local vehicle=require 'pa26_vehicle';local vehicleSettings=require 'pa26_vehicle_settings';local radio=require 'pa26_radio_text'
local function equal(a,b)
    if type(a)~='table'or type(b)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local base={session='test',ped=1,alive=true,demo=false,focused=true,paused=false,blocked=false,onDuty=true,radioEnabled=true,
    health=20,area='Doherty',city='Сан-Фиерро',map_square='H-18',square='Ручной сектор',map_grid=grid.defaults(),unit='P-01',station='SFPS',
    crew='Victor Auditore',duration='00:12:00',my_name='Victor Auditore',local_tag='',model='PoliceCar',
    vehicle_description='PoliceCar, белый',direction='Север',radioText={split_enabled=true,max_lines=8,continuation='...'}}
local location='Doherty, квадрат H-18'
eq(grid.location(base),location)
local values=grid.reportValues(base,'10-20: {area}.');eq(values.area,location);eq(base.area,'Doherty')
eq(grid.reportValues(base,'{area}, {map_square}.').area,'Doherty')
eq(grid.reportValues(base,'{area}, {square}.').area,'Doherty')
eq(grid.reportValues(base,'{location}; {area}.').area,'Doherty')
eq(grid.reportValues(base,'{area}.',false).area,'Doherty')
local old=grid.defaults();old.report_area=nil;old.location_template=nil
local valid=assert(grid.validate(old));check(valid.report_area);eq(valid.location_template,grid.defaults().location_template)
for _,bad in ipairs({'','{area}','{map_square}','{area} {map_square} {area}','{area} {map_square} {id}',
    '/r {area} {map_square}','{area}\n{map_square}',string.rep('д',140)..'{area}{map_square}'})do
    local c=grid.defaults();c.location_template=bad;check(not grid.validate(c),bad)
end
local c=grid.defaults();c.report_area=1;check(not grid.validate(c))
for _,reason in ipairs({'interior','outside','no_coordinates','disabled'})do
    local s=model.copy(base);s.map_square=nil
    if reason=='disabled'then s.map_square='H-18';s.map_grid.enabled=false end
    eq(grid.location(s),'Doherty',reason);eq(grid.reportValues(s,'{area}').area,'Doherty')
end
c=model.copy(base);c.map_grid.report_area=false
eq(grid.reportValues(c,'{area}').area,'Doherty');eq(grid.reportValues(c,'{location}').location,location)
c.map_grid.location_template='{map_square} / {area}';eq(grid.location(c),'H-18 / Doherty')
check(not grid.location({map_square='H-18'}),'No invented district')
-- Personal templates are not rewritten, even when the library is saved/reloaded.
local library=model.defaults(core.defaults());library.alerts.shots_template='Личный доклад. Место: {area}.'
library.patrol_session.start_template='{unit}: мой патруль, {area}.'
local personal=TEST_JSON_DECODE(TEST_JSON_ENCODE(library));local migrated=assert(model.validate(personal,core.defaults()))
eq(migrated.alerts.shots_template,library.alerts.shots_template);eq(migrated.patrol_session.start_template,library.patrol_session.start_template)
local function prepared(p)
    check(p~=nil);check(#p.lines>0)
    for i,line in ipairs(p.lines)do
        local wire=p.wires and p.wires[i]or p.wire[i]
        check(#wire<=127,line);check(#codec.encode(line:match('^/%w+ (.*)$')or line)<=90,line)
    end
    return p
end
-- Every IC channel uses the identical location formatter and existing 90-char splitter.
local samples={}
for _,channel in ipairs({'/r','/f','/d'})do
    local cfg=model.alertDefaults();cfg.code1_enabled=true;cfg.code4_enabled=true;cfg.channel=channel
    cfg.patrol.enabled=true
    for _,kind in ipairs({'shots','sos','code0','code1','code4','police'})do
        if kind=='police'then cfg.patrol.police_channel=channel end
        local p=prepared(assert(alerts.prepare(kind,base,cfg,codec,1000,1)))
        check(p.binding.script:find(location,1,true),kind);eq(p.lines[1]:sub(1,2),channel)
        local missing=model.copy(base);missing.area='Interior 1';missing.map_square=nil
        local fallback=prepared(assert(alerts.prepare(kind,missing,cfg,codec,1000,1)))
        check(fallback.binding.script:find('Interior 1',1,true));check(not fallback.binding.script:find('квадрат',1,true),kind)
        if channel=='/r'then samples[kind]=p.lines end
    end
end
local cfg=model.alertDefaults();cfg.sos_template='Мой текст: {area}.'
eq(assert(alerts.prepare('sos',base,cfg,codec,1000,1)).binding.script,'/r Мой текст: '..location..'.')
cfg.sos_template='{area}, квадрат {map_square}.'
eq(assert(alerts.prepare('sos',base,cfg,codec,1000,1)).binding.script,'/r '..location..'.')
cfg.sos_template='{area}, сектор {square}.'
eq(assert(alerts.prepare('sos',base,cfg,codec,1000,1)).binding.script,'/r Doherty, сектор Ручной сектор.')
cfg.sos_template='Помощь.';local absent=model.copy(base);absent.area=nil;absent.map_square=nil
check(alerts.prepare('sos',absent,cfg,codec,1000,1),'Unused location cannot block an emergency')
-- Verified extra command parameters do not acquire a prose location suffix.
cfg=model.alertDefaults();cfg.help_enabled=true;cfg.help_verified=true;cfg.help_source='/help';cfg.help_command='/helpme {area}'
local help=assert(alerts.prepare('sos',base,cfg,codec,1000,1));eq(help.lines[#help.lines],'/helpme Doherty')
-- A long crew/custom format still splits with the full location and no truncated words.
local long=model.copy(base);long.crew=string.rep('Officer Test, ',12)..'Victor Auditore'
local scfg=require('pa26_patrol_settings').defaults();scfg.unit='P-01'
local officer={id=1,officer='Victor Auditore',callsign='P-01',crew={},elapsed_ms=0}
local patrol=session.new({settings=function()return scfg end,profile=function()return {name='Victor Auditore',callsign='P-01'}end,
    contacts=function()return {}end,codec=codec,equal=equal})
for _,action in ipairs({'start','resume','periodic'})do
    officer.unit='P-01';local p=prepared(assert(patrol:prepareLine(action,officer,base,scfg)))
    check(p.line:find('H-18',1,true));samples['patrol_'..action]=p.lines
end
local gspec={name='Длинный доклад',channel='/r',template='{crew}. 10-20: {area}.',interval_ms=60000,confirmation=true}
local gp=prepared(assert(guard.prepare(gspec,long,codec,1000,1)));check(#gp.lines>2)
eq(radio.key(gp),table.concat(gp.wire,'\0'))
for i,line in ipairs(gp.lines)do
    if i<#gp.lines then check(line:sub(-3)=='...')end
    if i>1 then check(line:sub(1,6)=='/r ...')end
end
local ecfg=eventSettings.defaults();ecfg.enabled=true
local ev=events.new({settings=function()return ecfg end,codec=codec});ev.state=model.copy(base)
for _,row in ipairs(eventSettings.catalog)do
    local p=prepared(assert(ev:line({kind=row[1],subject='саспект',basis='основание',destination='дежурный',details='проверка'},ecfg)))
    if row[3]:find('{area}',1,true)then check(p.line:find('H-18',1,true));samples['event_'..row[1]]=p.lines
    else check(not p.line:find('H-18',1,true),'No unsolicited location in a location-free template')end
end
base.occupants_text='внутри один';base.tac='TAC 1';base.armed_text='';base.stop_outcome='проведена беседа'
local vcfg=vehicleSettings.defaults()
for _,action in ipairs({'traffic_stop','pursuit','pursuit_periodic','finish'})do
    local p=prepared(assert(vehicle.preview(action,vcfg,base,codec,base.radioText)))
    check(p.line:find('H-18',1,true),action);samples[action]=p.lines
end
vcfg.megaphone_template='Место: {area}.'
eq(assert(vehicle.preview('megaphone',vcfg,base,codec,base.radioText)).line,'/m Место: Doherty.')
vcfg.approach_template='проверил район {area}.'
eq(assert(vehicle.preview('approach',vcfg,base,codec,base.radioText)).line,'/me проверил район Doherty.')
vcfg.megaphone_template='Место: {location}.'
check(assert(vehicle.preview('megaphone',vcfg,base,codec,base.radioText)).line:find(location,1,true),'Explicit variable still works in megaphone')
-- Crossing every cell never changes the report timer's identity/policy.
local policy=grid.reportPolicy(base,'{area}')
for row=1,24 do for col=1,24 do
    local s=model.copy(base);s.map_square=grid.cell(s.map_grid,-3000+(col-.5)*250,3000-(row-.5)*250,0).label
    eq(grid.reportPolicy(s,'{area}'),policy)
    check(assert(alerts.prepare('sos',s,model.alertDefaults(),codec,1000,1)).binding.script:find(s.map_square,1,true))
end end
-- Confirmed reports invalidate an unstarted location; after the first part they
-- retain one consistent snapshot and never mix a new square into a continuation.
local acfg=model.alertDefaults();local ac=alerts.new({settings=function()return acfg end,codec=codec})
ac.state=model.copy(base);ac.now=1000
local ap=assert(alerts.prepare('sos',ac.state,acfg,codec,1000,ac.life));check(ac:validPlan(ap))
ac.state.map_square='H-19';check(not ac:validPlan(ap))
ac.state.map_square='H-18';ac:onExecution('sent_line',{plan=ap});ac.state.map_square='H-19';check(ac:validPlan(ap))
ac.state.focused=false;check(not ac:validPlan(ap),'Focus safety still applies after first part')
-- Pending routine previews update without restarting the 30s countdown.
local gcfg=prefs.radioGuardDefaults();local gc=guard.new({settings=function()return gcfg end,codec=codec})
gc:tick(model.copy(base),1000)
local spec={name='Патруль',channel='/r',template='Место: {area}.',interval_ms=60000,confirmation=true}
local _,_,ticket=gc:track('patrol',spec,30000);gc:shown(ticket.token)
local moved=model.copy(base);moved.map_square='H-19';moved.square='H-19'
gc:tick(moved,2000);local left=ticket.lead;gc:track('patrol',spec,29000)
eq(ticket.phase,'pending');eq(ticket.lead,left);check(not ticket.paintedWire);check(table.concat(ticket.plan.lines,' '):find('H-19',1,true))
-- Current square participates in the real first-send validation for patrols.
scfg.enabled=true;patrol.state=model.copy(base);patrol.now=1000
local proposal=assert(patrol:propose('start'));check(patrol:proposalValid(proposal))
patrol.state.map_square='H-19';check(not patrol:proposalValid(proposal));proposal.started=true;check(patrol:proposalValid(proposal))
-- Equivalent checks for vehicle and event flows, including a changing format.
vcfg=vehicleSettings.defaults();vcfg.enabled=true;vcfg.require_patrol=false
local car={id=1,handle=10,model_id=597,model_name='PoliceCar',color1=0,color2=1,distance=5}
local vc=vehicle.new({settings=function()return vcfg end,codec=codec,equal=equal,ownCar=function()end,scan=function()return {car}end,resolve=function()return car end})
vc:tick(model.copy(base),1000);assert(vc:selectNearest());local vp=assert(vc:propose('traffic_stop'))
check(vc:proposalValid(vp));vc.state.map_square='H-19';check(not vc:proposalValid(vp));vp.started=true;check(vc:proposalValid(vp))
vc.state.focused=false;check(not vc:proposalValid(vp))
ecfg.require_patrol=false
ev=events.new({settings=function()return ecfg end,codec=codec,equal=equal,patrol=function()end,target=function()end,targetStamp=function()return 'none'end})
ev:tick(model.copy(base),1000)
local form=assert(ev:form('custom'));form.details='Проверка';form.acknowledged=true
local ep=assert(ev:propose(form,true));check(ev:proposalValid(ep));ev.state.map_square='H-19';check(not ev:proposalValid(ep))
ep.sent_any=true;check(ev:proposalValid(ep))
-- Main(), GUI persistence, HUD, live district and real executor on both chat paths.
local fixture=require 'support.fixture'
for _,cef in ipairs({false,true})do
    local s=fixture({demo=false,alerts=true});s.zoneKey='DOH';s.step()
    if s.frames[1].condition()then s.commands.pa26();s.step()end
    if cef then
        local bridge=s.chatBridge
        check(bridge:exchange(encodeJson({schema=1,page='map-location-test',chat=false,dialog=false,busy=false,events={}}),s.now))
        s.step()
    else s.workspace.library.settings.cef_chat_support=false end
    local actual=grid.cell(s.workspace.library.map_grid,0,0,0).label
    local drawn=table.concat(s.drawnText,'\n');check(drawn:find('Квадрат карты: ',1,true));check(drawn:find(actual,1,true),'Map value is rendered separately in the larger heading font')
    s.alerts:request('sos');s.step();check(s.alerts.pending);eq(#s.sent,0)
    local pending=s.alerts.pending;local original=table.concat(pending.plan.wire,'\0')
    check(pending.plan.binding.script:find('Doherty, квадрат '..actual,1,true))
    s.down={};s.step(150);s.step();s.down={[0x59]=true};s.step();s.down={}
    for i=1,8 do s.step(1500)end
    local sent={};for _,r in ipairs(s.sent)do sent[#sent+1]=codec.encode(r.line)end
    eq(table.concat(sent,'\0'),original,'Approved preview must equal all outgoing parts, CEF='..tostring(cef))
    if not s.frames[1].condition()then s.commands.pa26();s.step()end
    require('support.ui_routes').screen(s,'map')
    s.toggle='Квадрат рядом с районом в докладах##map-report-area';s.render();s.step(700)
    check(not s.workspace.library.map_grid.report_area)
    local saved=s.savedLibrary()
    check(not saved.map_grid.report_area);eq(saved.alerts.sos_template,s.workspace.library.alerts.sos_template)
    local noSquare=assert(alerts.prepare('sos',s.alerts.state,s.workspace.library.alerts,codec,s.now,s.alerts.life))
    check(not noSquare.binding.script:find('квадрат',1,true),'Saved GUI switch must apply to real report state')
    s.edits={['##Формат места##map-location-template']='{map_square} / {area}'};s.render();s.edits={};s.step(700)
    eq(s.workspace.library.map_grid.location_template,'{map_square} / {area}')
    s.zoneKey='GAN';s.step(16);eq(s.alerts.state.area,'Ganton','District must refresh with the square, without HUD 500ms cache')
    check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);eq(s.invalidIOReads,0)
    onScriptTerminate(s.script)
end
local live=require('support.fixture')({demo=false,alerts=true});live.step()
if live.frames[1].condition()then live.commands.pa26();live.step()end
live.alerts:request('sos');live.step();local beforeMove=live.alerts.pending.token
local originalCoordinates=getCharCoordinates
getCharCoordinates=function(ped)if ped==1 then return 251,0,0 end;return originalCoordinates(ped)end
live.down={[0x59]=true};live.step(150)
check(live.alerts.pending and live.alerts.pending.token~=beforeMove,'Cell change must rearm an emergency confirmation')
eq(#live.sent,0,'Held Y cannot approve a replacement location')
check(live.alerts.pending.plan.binding.script:find('M-14',1,true))
getCharActiveInterior=function()return 2 end;live.down={};live.step(150)
check(live.alerts.pending);check(live.alerts.pending.plan.binding.script:find('Interior 2',1,true))
check(not live.alerts.pending.plan.binding.script:find('M-14',1,true),'Interior cannot retain an outdoor square')
eq(#live.sent,0);onScriptTerminate(live.script)
local f=assert(io.open('tests/LOCATION_SAMPLES.json','wb'));f:write(TEST_JSON_ENCODE(samples));f:close()

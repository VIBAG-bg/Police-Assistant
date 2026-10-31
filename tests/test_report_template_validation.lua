local core=require 'pa26_core'
local model=require 'pa26_bindings'
local grid=require 'pa26_map_grid'
local context=require 'pa26_report_context'
local settings=require 'pa26_patrol_settings'
local alerts=require 'pa26_alerts'
local radioGuard=require 'pa26_radio_guard'
local function rejected(name,fn,fragment)
 local ok,value,why=pcall(fn);check(ok,name..': '..tostring(value));eq(value,nil,name)
 check(type(why)=='string'and why:find('%S'),name..' must preserve an actionable error')
 if fragment then check(why:find(fragment,1,true),name..': '..why)end
end
local function result(name,fn)
 local ok,value,why=pcall(fn);check(ok,name..': '..tostring(value));check(value,name..': '..tostring(why));return value
end
local state={session='test:7777',ped=1,alive=true,demo=false,focused=true,paused=false,blocked=false,onDuty=true,radioEnabled=true,
 health=20,gender='male',area='Doherty',city='Сан-Фиерро',map_square='J-6',square='Сектор',map_grid=grid.defaults(),
 unit='1-L-1',crew='Victor Auditore',post='КПП',local_tag='',direction='север',directionKnown=true,my_nick='Victor_Auditore',
 radioText={split_enabled=true,max_lines=8,continuation='...'}}
local cfg=settings.defaults();cfg.enabled=true;cfg.unit='1-L-1'
local session=require('pa26_patrol_session').new({settings=function()return cfg end,profile=function()return {name='Victor Auditore',callsign='A-1'}end,
 contacts=function()return {}end,codec=codec})
session.now=1000
local record=assert(session:makeRecord(cfg,state))
local actions={'start','resume','finish','crew','periodic'}
for _,action in ipairs(actions)do
 cfg=settings.defaults();cfg.enabled=true;cfg.unit='1-L-1'
 local stock=cfg[action..'_template']
 local known=result(action..' known stock',function()return session:prepareLine(action,record,state,cfg)end)
 check(type(known.line)=='string');eq(cfg[action..'_template'],stock)
 local unknown=model.copy(state);unknown.direction=nil;unknown.directionKnown=false
 local p=result(action..' unknown stock',function()return session:prepareLine(action,record,unknown,cfg)end)
 check(not p.line:find('{direction}',1,true));check(not p.line:find('на неизвестно',1,true));check(not p.line:find(', ,',1,true))
 local custom='{unit}: мой '..action..', курс {direction}.';cfg[action..'_template']=custom
 local prepared=result(action..' known custom',function()return session:prepareLine(action,record,state,cfg)end)
 eq(prepared.line,'/r 1-L-1: мой '..action..', курс север.')
 rejected(action..' unknown custom',function()return session:prepareLine(action,record,unknown,cfg)end,'{direction}')
 eq(cfg[action..'_template'],custom)
 cfg[action..'_template']='{unit}: мой '..action..'.'
 unknown.area=nil;unknown.map_square=nil;unknown.map_grid=nil
 eq(result(action..' unused location',function()return session:prepareLine(action,record,unknown,cfg)end).line,'/r 1-L-1: мой '..action..'.')
 for _,bad in ipairs({false,42,{},'', '   ','{not_a_patrol_field}'})do
  cfg[action..'_template']=bad
  rejected(action..' invalid template',function()return session:prepareLine(action,record,state,cfg)end)
 end
end
for _,row in ipairs({{}, {direction=''}, {direction='неизвестно'}, {direction='не определено'}, {direction='не определён'},
 {direction='не определен'}, {direction='Неизвестно'}, {direction='   '}, {direction=false}, {direction=42}, {direction={}},
 {direction='север',directionKnown=false}, {direction='север',directionKnown={}}, {direction='\255'}})do
 check(not context.directionKnown(row))
 rejected('unknown direction',function()return context.directionTemplate('Личный курс {direction}.',row)end,'{direction}')
 eq(assert(context.directionTemplate('Без курса.',row)),'Без курса.')
end
for _,direction in ipairs({'север','юг','восток','запад','Северо-Восток','Северо-Запад','Юго-Восток','Юго-Запад'})do
 for _,known in ipairs({{direction=direction},{direction=direction,directionKnown=true}})do
  check(context.directionKnown(known));eq(assert(context.directionTemplate('Курс {direction}.',known)),'Курс {direction}.')
 end
end
for _,bad in ipairs({false,42,'bad'})do
 check(not context.directionKnown(bad));rejected('invalid direction context',function()return context.directionTemplate('Доклад.',bad)end)
 rejected('invalid patrol state',function()return session:prepareLine('start',record,bad,cfg)end)
 rejected('invalid patrol settings',function()return session:prepareLine('start',record,state,bad)end)
 rejected('invalid map values',function()return grid.reportValues(bad,'{area}')end)
 rejected('invalid map policy',function()return grid.reportPolicy(bad,'{area}')end)
 rejected('invalid location values',function()return grid.location(bad)end)
end
for _,fn in ipairs({function()return context.directionTemplate(nil,state)end,function()return context.directionTemplate('Текст.',nil)end,
 function()return grid.reportValues(nil,'{area}')end,function()return grid.reportPolicy(nil,'{area}')end,function()return grid.location(nil)end,
 function()return session:prepareLine('start',record,nil,cfg)end,function()return session:prepareLine('start',record,state,nil)end,
 function()return session:prepareLine({},record,state,cfg)end})do rejected('nil/malformed input',fn)end
for _,bad in ipairs({false,1,{},'','  '})do
 rejected('map template',function()return grid.reportValues(state,bad)end)
 rejected('policy template',function()return grid.reportPolicy(state,bad)end)
end
rejected('nil map template',function()return grid.reportValues(state,nil)end)
rejected('nil policy template',function()return grid.reportPolicy(state,nil)end)
cfg=settings.defaults();cfg.unit='1-L-1'
for _,change in ipairs({function(r)r.officer={}end,function(r)r.crew=false end,function(r)r.crew={false}end,
 function(r)r.elapsed_ms=false end,function(r)r.crew={{ic_name='John',callsign='A-2',role={}}}end})do
 local malformed=model.copy(record);change(malformed)
 rejected('malformed crew record',function()return session:prepareLine('start',malformed,state,cfg)end)
end
local invalidGrammar=model.copy(cfg);invalidGrammar.grammar=false
rejected('invalid grammar table',function()return session:prepareLine('start',record,state,invalidGrammar)end)
invalidGrammar.grammar={start_solo=false}
rejected('invalid grammar phrase',function()return session:prepareLine('start',record,state,invalidGrammar)end)
local invalidUnit=model.copy(state);invalidUnit.unit={} -- Session derives its unit from the record, not this unrelated value.
check(session:prepareLine('start',record,invalidUnit,cfg))
eq(grid.location({area='Doherty'}),'Doherty');eq(grid.location({area=''}),nil);eq(grid.location({}),nil)
eq(grid.reportPolicy({},'{unit}'),'');check(grid.reportValues({},'{unit}'))
local location=model.copy(state);local original=location.area
for _,template in ipairs({'{area}','{location}','{area} / {map_square}','{area} / {square}','{unit}'})do
 local out=result('map formatting',function()return grid.reportValues(location,template)end)
 eq(location.area,original);eq(out.location,'Doherty, квадрат J-6')
 if template=='{area}'then eq(out.area,out.location)else eq(out.area,original)end
 check(type(grid.reportPolicy(location,template))=='string')
end
location.map_grid.location_template='[{map_square}] {area}'
eq(grid.location(location),'[J-6] Doherty');location.map_square='S-19';eq(grid.location(location),'[S-19] Doherty')
location.area='Pershing Square';eq(grid.location(location),'[S-19] Pershing Square')
location.map_grid.enabled=false;eq(grid.location(location),'Pershing Square')
location.map_grid.enabled=true;location.map_square=nil;eq(grid.location(location),'Pershing Square')
location.map_square='J-6';location.map_grid.report_area=false;eq(grid.reportValues(location,'{area}').area,'Pershing Square')
for _,bad in ipairs({false,42,'bad',{enabled='yes'},{report_area={}},{enabled=true,location_template=false},
 {enabled=true,location_template='{area}'},{enabled=true,location_template='/r {area} {map_square}'}})do
 local broken=model.copy(state);broken.map_grid=bad
 rejected('malformed map setting',function()return grid.reportValues(broken,'{area}')end)
 rejected('malformed map policy',function()return grid.reportPolicy(broken,'{area}')end)
 rejected('malformed location',function()return grid.location(broken)end)
end
for _,field in ipairs({'area','map_square'})do for _,bad in ipairs({false,42,{}})do
 local broken=model.copy(state);broken[field]=bad
 rejected('malformed '..field,function()return grid.reportValues(broken,'{area}')end)
end end
-- SOS, Shots fired, CODE 0/1/4 and the two existing patrol channels.
for _,kind in ipairs({'sos','shots','code0','code1','code4','police','prison'})do
 local a=model.alertDefaults();a.enabled=true;a.on_duty=true;a.code1_enabled=true;a.code4_enabled=true;a.patrol.enabled=true;a.patrol.mode=kind=='prison'and'prison'or'police'
 local source=(kind=='police'or kind=='prison')and a.patrol or a
 result(kind..' stock',function()return alerts.prepare(kind,state,a,codec,1000,1)end)
 source[kind..'_template']='{unit}: курс {direction}.'
 local known=result(kind..' known',function()return alerts.prepare(kind,state,a,codec,1000,1)end)
 check(known.lines[1]:find('курс север.',1,true))
 local unknown=model.copy(state);unknown.directionKnown=false;unknown.direction=nil
 rejected(kind..' unknown',function()return alerts.prepare(kind,unknown,a,codec,1000,1)end,'{direction}')
 eq(source[kind..'_template'],'{unit}: курс {direction}.')
 source[kind..'_template']='{unit}: готово.'
 check(alerts.prepare(kind,unknown,a,codec,1000,1))
end
for _,bad in ipairs({false,42,'bad',{session={},ped=1,demo=false}})do rejected('bad alert state',function()return alerts.prepare('sos',bad,model.alertDefaults(),codec,1000,1)end)end
rejected('nil alert state',function()return alerts.prepare('sos',nil,model.alertDefaults(),codec,1000,1)end)
local spec={name='Проверка',channel='/r',template='{unit}: курс {direction}.',interval_ms=60000,confirmation=true}
local unknown=model.copy(state);unknown.directionKnown=false
rejected('radio guard direction',function()return radioGuard.prepare(spec,unknown,codec,1000,1)end,'{direction}')
rejected('Copilot direction',function()return require('pa26_copilot').expand(spec.template,unknown)end,'{direction}')
local vcfg=require('pa26_vehicle_settings').defaults();vcfg.traffic_stop_template=spec.template
rejected('vehicle direction',function()return require('pa26_vehicle').preview('traffic_stop',vcfg,unknown,codec,state.radioText)end,'{direction}')
local ecfg=require('pa26_patrol_event_settings').defaults();ecfg.events.frisk.template=spec.template
local ev=require('pa26_patrol_events').new({settings=function()return ecfg end,codec=codec});ev.state=unknown
rejected('patrol event direction',function()return ev:line({kind='frisk'},ecfg)end,'{direction}')
for _,bad in ipairs({false,42,'bad'})do
 rejected('bad guard spec',function()return radioGuard.prepare(bad,state,codec,1000,1)end)
 rejected('bad vehicle context',function()return require('pa26_vehicle').preview('traffic_stop',vcfg,bad,codec)end)
 rejected('bad event form',function()return ev:line(bad,ecfg)end)
end
-- A lost map context revokes a pending report and its hint cannot nil-index.
local rg=radioGuard.new({settings=function()return model.defaults(core.defaults()).radio_guard end,codec=codec})
rg.state=model.copy(state);rg.now=1000
spec.template='{unit}: {area}.'
local phase,why,ticket=rg:track('test',spec,1000);eq(phase,'pending',why);check(ticket)
rg.state.map_grid=false
local cards=result('invalid-map candidate hint',function()return rg:candidates()end);check(type(cards[1].hint)=='string')
phase,why=rg:track('test',spec,1000);eq(phase,'invalid');check(type(why)=='string');eq(ticket.phase,'cancelled')

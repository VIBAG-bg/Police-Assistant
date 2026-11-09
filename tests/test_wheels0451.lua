local m=require 'pa26_bindings';local core=require 'pa26_core';local author=require 'pa26_author_presets';local wheel=require 'pa26_wheel'
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return TEST_JSON_DECODE(s)end
local o=read('docs/qa/0.45.1/AUTHOR_ORACLE.json').expected;local cfg=core.defaults();local lib=m.defaults(cfg)
lib.bindings={};lib.next_id=1;lib.wheel={0,0,0,0,0,0};lib.settings.wheel_car_classic={0,0,0,0,0,0}
lib=assert(author.prepare('binds',read('presets/pa-binds.json'),lib,cfg)).library
lib=assert(author.prepare('settings',read('presets/pa-settings.json'),lib,cfg)).library
lib.alerts.on_duty=true;lib.alerts.enabled=true;lib.vehicle.enabled=true;lib.vehicle.copilot.enabled=true
lib.procedures.wanted_wheel=true;lib.procedures.wanted_enabled=true;lib.procedures.wanted_assistant_enabled=true
for _,car in ipairs({false,true})do
 local state={inVehicle=car,onDuty=true,copilot={car={id=1},phase='10-55'}}
 local catalog=wheel.build(lib,1,true,state);eq(#catalog.categories,car and 6 or 8)
 eq(catalog.bySystem['pa-gps-clear'],nil)
 local expected=car and o.car or o.foot;local root=car and o.car_order.root or o.foot_order.root
 for i,g in ipairs(root)do eq(catalog.categories[i].id,g)
  local actual={};for _,item in ipairs(catalog.byCategory[g].items)do actual[#actual+1]=item.id end
  local activeExpected={}
  for _,id in ipairs(expected[g])do if id~='pa-gps-clear'then activeExpected[#activeExpected+1]=id end end
  for n,id in ipairs(activeExpected)do eq(actual[n],id,(car and'car'or'foot')..' '..g..' '..n..': '..tostring(actual[n]))end
  local entries=wheel.entries(catalog.byCategory[g]);local limit=15
  for n=1,math.min(limit,#activeExpected)do eq(entries[n].id,activeExpected[n])end
 end
 if car then
  for _,id in ipairs({20,25,26,27,45})do eq(catalog.byId[id],nil)end
  check(wheel.available(catalog,{kind='binding',id=53,category='custom'},false,{id=37,ped=3,name='Target'}))
 else
  eq(#catalog.byCategory.custom.items,0)
  for _,id in ipairs({46,47,48,49,68,69,70,71,72,74,75,88})do eq(catalog.byId[id],nil)end
 end
end
local b=m.newBinding(100);b.wheel_visible=true;b.quick=true;lib.bindings[#lib.bindings+1]=b;lib.next_id=101
local c=wheel.build(lib,1,true,{inVehicle=false,onDuty=true});eq(c.byCategory.custom.items[1].id,100)
lib.settings.wheel_names.citizen='Personal name';lib.settings.wheel_order.root={'custom','citizen'}
local kept=assert(m.validate(lib,cfg));eq(kept.settings.wheel_names.citizen,'Personal name');eq(kept.settings.wheel_order.root[1],'custom')

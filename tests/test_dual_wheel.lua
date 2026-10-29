local scope=require 'pa26_wheel_scope';local model=require 'pa26_bindings';local core=require 'pa26_core';local wheel=require 'pa26_wheel';local users=require 'pa26_user_files'
local lib=assert(model.validate(model.defaults(core.defaults()),core.defaults()))
eq(scope.active(lib,{inVehicle=false}),'foot');eq(scope.active(lib,{inVehicle=true}),'car');eq(scope.active(lib,{}),'foot')
lib.settings.wheel_car_separate=false;eq(scope.active(lib,{inVehicle=true}),'foot');lib.settings.wheel_car_separate=true
local old=model.copy(lib)
for k in pairs(old.settings)do if k:match('^wheel_car_')then old.settings[k]=nil end end
for _,b in ipairs(old.bindings)do b.wheel_car_visible=nil;b.wheel_car_group=nil end
old.settings.wheel_names.citizen='Личная секция';old.settings.wheel_order.root={'wanted','citizen'}
local migrated=assert(model.validate(old,core.defaults()));eq(migrated.settings.wheel_car_separate,false)
eq(migrated.settings.wheel_car_names.citizen,'Личная секция');eq(migrated.settings.wheel_car_order.root[1],'wanted')
local foot=model.copy(lib.settings.wheel_names);lib.settings.wheel_car_names.citizen='Авто секция';lib.settings.wheel_car_profile='full'
lib.settings.wheel_car_system_groups['procedure-wanted']='disabled';lib.settings.wheel_car_order.root={'wanted','citizen'}
lib.bindings[1].wheel_car_visible=false;lib.bindings[2].wheel_car_visible=true;lib.bindings[2].wheel_car_group='custom'
local a=wheel.build(lib,1,true,{inVehicle=false,onDuty=true});local b=wheel.build(lib,2,true,{inVehicle=true,onDuty=true})
eq(a.scope,'foot');eq(b.scope,'car');eq(a.profile,'compact');eq(b.profile,'full');eq(b.categories[1].id,'wanted')
check(a.byId[1]);eq(b.byId[1],nil);eq(b.byId[2].category,'custom');eq(lib.settings.wheel_names.citizen,foot.citizen)
check(a.bySystem['procedure-wanted']);eq(b.bySystem['procedure-wanted'],nil)
for _,mode in ipairs({'classic','categories'})do for _,carMode in ipairs({'classic','categories'})do
 lib.settings.wheel_mode=mode;lib.settings.wheel_car_mode=carMode
 eq(wheel.build(lib,1,true,{inVehicle=false})==nil,mode=='classic');eq(wheel.build(lib,1,true,{inVehicle=true})==nil,carMode=='classic')
end end
lib.settings.wheel_car_classic={6,5,4,3,2,1};local p=users.partition(lib)
eq(p.binds.wheel_car_classic[1],6);eq(p.settings.data.settings.wheel_car_classic,nil)
for _,kind in ipairs({'binds','settings','notes'})do p[kind]=assert(users.validate(kind,p[kind]))end
local restored=assert(users.combine(p,core.defaults()));eq(restored.settings.wheel_car_classic[1],6);eq(restored.bindings[2].wheel_car_group,'custom')
eq(users.exchange(lib,'binds',2).wheel_car_classic[1],0)
for _,patch in ipairs({{wheel_car_separate='yes'},{wheel_car_child_limit=17},{wheel_car_names={bad='x'}},{wheel_car_system_groups={bad='wanted'}},{wheel_car_classic=false},{wheel_car_classic={1,2,3}},{wheel_car_order={root={'wanted','wanted'}}}})do
 local copy=model.copy(lib);for k,v in pairs(patch)do copy.settings[k]=v end;check(not model.validate(copy,core.defaults()))
end
local fixture=require 'support.fixture'
local s=fixture({library=restored,productionWindows=true,demo=true});s.step();s.page('settings');check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);eq(#s.sent,0)
s.click='3. Управление и колесо##settings-tab-options';s.render()
local studio=s.workspace.studio;studio.wheelEditScope='car';s.render()
s.combo='##Способ выбора##wheel-mode';s.click='По категориям##Способ выбора##wheel-modecategories';s.render();s.combo=nil
s.combo='##Количество категорий##wheel-profile';s.click='6##Количество категорий##wheel-profileextended';s.render();s.combo=nil;s.step()
eq(s.savedLibrary().settings.wheel_car_profile,'extended');eq(s.savedLibrary().settings.wheel_profile,restored.settings.wheel_profile)
studio.wheelEditScope='foot';s.render();check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)
-- Context change invalidates even a classic wheel, without executing a slot.
local rt=require('pa26_runtime');local current='car';local state={session='x',focused=true,paused=false,blocked=false,window=false,alive=true}
local r=rt.new({now=function()return 1000 end,context=function()return state end,wheelScope=function()return current end,acquire=function()return{id=1,name='Target'}end,log=function()end,report=function()end},core.defaults())
r:setDemo(true);check(r:openWheel());eq(r.wheel.scope,'car');current='foot';r:refresh();eq(r.wheel,nil)
local t=fixture({library=model.defaults(core.defaults()),productionWindows=true,demo=true,categoryWheel=true});t.step()
if t.frames[1].condition()then t.commands.pa26();t.step()end
t.vehicle=true;t.step();t.down[0x58]=true;t.step(16,{[0x58]=true})
check(t.runtime.wheel);eq(t.runtime.wheel.scope,'car');eq(t.runtime.wheel.catalog.scope,'car')
local l=wheel.layout(t.io.DisplaySize.x,t.io.DisplaySize.y,#t.runtime.wheel.catalog.categories)
local function point(index)local a=-math.pi/2+(index-.5)*l.step;local rr=(l.inner+l.rootOuter)/2;t.io.MousePos.x=l.cx+math.cos(a)*rr;t.io.MousePos.y=l.cy+math.sin(a)*rr end
local first,second=t.runtime.wheel.catalog.categories[1].id,t.runtime.wheel.catalog.categories[2].id
point(1);t.down[0x11]=true;t.io.MouseDown[0]=true;t.mouseClicks={[0]=true};t.render();t.mouseClicks=nil
point(2);t.render();t.io.MouseDown[0]=false;t.render();t.step()
eq(t.savedLibrary().settings.wheel_car_order.root[1],second);eq(t.savedLibrary().settings.wheel_order.root,nil)
t.down[0x58]=false;t.down[0x11]=false;t.step();eq(#t.sent,0)
t.down[0x58]=true;t.step(16,{[0x58]=true});check(t.runtime.wheel)
point(1);t.down[0x11]=true;t.io.MouseDown[0]=true;t.mouseClicks={[0]=true};t.render();t.mouseClicks=nil
point(2);t.io.MouseDown[0]=false;t.render();t.vehicle=false;t.step();eq(t.runtime.wheel,nil)
eq(t.savedLibrary().settings.wheel_car_order.root[1],second);eq(t.savedLibrary().settings.wheel_order.root,nil);eq(#t.sent,0)
check(not t.hasLog('Ошибка интерфейса'));eq(t.invalidIOReads,0);eq(#t.scopes,0)

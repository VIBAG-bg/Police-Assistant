local model=require 'pa26_bindings';local core=require 'pa26_core';local wheel=require 'pa26_wheel'
local lib=model.defaults(core.defaults());lib.procedures.enabled=true;lib.patrol_session.enabled=true
lib.settings.wheel_names.citizen='Экстренное';lib.settings.wheel_system_groups={code0='citizen',['procedure-wanted']='detention',['procedure-wanted_list']='custom'}
for _,profile in ipairs({'compact','extended','full'})do
 lib.settings.wheel_profile=profile;local clean=assert(model.validate(lib,core.defaults()))
 local cat=wheel.build(clean,1,true,{health=1});eq(cat.bySystem.code0.category,'citizen')
 eq(cat.bySystem['procedure-wanted'].category,'detention')
 eq(cat.bySystem['procedure-wanted_list'].category,profile=='compact'and'service'or'custom')
 local seen={};for _,group in ipairs(cat.categories)do for _,item in ipairs(group.items)do
  if item.kind then check(not seen[item.id],item.id);seen[item.id]=true;eq(item.category,group.id)end
 end end
 local route={kind='alert',id='code0',category='citizen'};check(wheel.available(cat,route,false,nil))
 check(not wheel.available(cat,{kind='alert',id='code0',category='service'},false,nil))
end
for _,limit in ipairs({1,5,10,16})do for _,total in ipairs({0,1,5,10,11,17,30})do
 lib.settings.wheel_child_limit=limit;local clean=assert(model.validate(lib,core.defaults()))
 local cat={id='custom',child_limit=clean.settings.wheel_child_limit,items={}}
 for i=1,total do cat.items[i]={id=i,name='Действие '..i}end
 local entries=wheel.entries(cat)
 if total==0 then eq(entries[1].kind,'settings')else
  eq(#entries,math.min(limit,total)+(total>limit and 1 or 0))
  if total>limit then eq(entries[#entries].kind,'more')end
 end
 local arc=wheel.arc(assert(wheel.layout(1920,1080,8)),3,#entries);check(arc.span<=math.pi*1.61)
end end
for _,value in ipairs({-1,17,1.5,'10'})do local bad=model.copy(lib);bad.settings.wheel_child_limit=value;check(not model.validate(bad,core.defaults()))end
local bad=model.copy(lib);bad.settings.wheel_system_groups.code0='missing';check(not model.validate(bad,core.defaults()))
bad=model.copy(lib);bad.settings.wheel_system_groups.unknown='service';check(not model.validate(bad,core.defaults()))
local users=require 'pa26_user_files';local back=assert(users.combine(users.partition(lib),core.defaults()))
eq(back.settings.wheel_system_groups.code0,'citizen');eq(back.settings.wheel_child_limit,16)
local fixture=require 'support.fixture';local s=fixture({library=lib,demo=false,alerts=true,categoryWheel=true});s.step();s.commands.pa26quick();s.step()
s.workspace.studio.quickWheelCategory='citizen';s.buttonCalls={};s.render()
local found=false;for _,r in ipairs(s.buttonCalls)do if r.label:find('##quick%-system%-code0')then found=true end end
check(found,'Moved system actions must also appear in that category search');onScriptTerminate(s.script)

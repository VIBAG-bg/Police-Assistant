local order=require 'pa26_wheel_order';local wheel=require 'pa26_wheel';local model=require 'pa26_bindings';local core=require 'pa26_core';local fixture=require 'support.fixture'
for _,bad in ipairs({false,'x',{unknown={}},{root={'citizen','citizen'}},{root={'bad'}},{citizen={'../x'}},{citizen={[2]='b:1'}}})do check(not order.validate(bad))end
local merged=assert(order.swap({'s:hidden','b:1','s:future','b:2'},{'b:1','b:2'},'b:1','b:2'))
eq(table.concat(merged,','),'s:hidden,b:2,s:future,b:1');check(not order.swap({}, {'b:1'},'b:1','b:1'))
local lib=model.defaults(core.defaults());lib.procedures.enabled=true
for _,r in ipairs(wheel.systemRows)do lib.settings.wheel_system_groups[r[1]]='disabled'end
check(model.validate(lib,core.defaults()));local cat=wheel.build(lib,1,true,{onDuty=true})
for _,r in ipairs(wheel.systemRows)do eq(cat.bySystem[r[1]],nil)end
eq(wheel.systemCategoryChoices({})[1][1],'disabled');check(wheel.categoryChoices({})[1][1]~='disabled')
local function healthy(s)check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0)end
local function open(seed)
 local s=fixture({productionWindows=true,categoryWheel=true,library=seed,demo=true});s.step()
 if s.frames[1].condition()then s.commands.pa26();s.step()end
 s.down[0x58]=true;s.step(16,{[0x58]=true});healthy(s)
 local w=s.runtime.wheel;check(w);local l=wheel.layout(s.io.DisplaySize.x,s.io.DisplaySize.y,#w.catalog.categories)
 return s,w,l
end
local function point(s,l,index,outer,n)
 local angle,radius
 if outer then local arc=wheel.arc(l,index,n);angle=arc.first+(outer-.5)*arc.step;radius=(l.childInner+l.outer)/2
 else angle=-math.pi/2+(index-.5)*l.step;radius=(l.inner+l.rootOuter)/2 end
 s.io.MousePos.x=l.cx+math.cos(angle)*radius;s.io.MousePos.y=l.cy+math.sin(angle)*radius
end
local s,w,l=open();point(s,l,1);s.step();s.step(120)
local a,b=w.catalog.categories[1].id,w.catalog.categories[2].id
s.down[0x11]=true;s.io.MouseDown[0]=true;s.mouseClicks={[0]=true};s.render();s.mouseClicks=nil;check(w.drag)
point(s,l,2);s.render();s.io.MouseDown[0]=false;s.render();check(w.pendingEdit);eq(s.workspace.library.settings.wheel_order.root,nil,'Renderer must not persist')
s.step();eq(s.workspace.library.settings.wheel_order.root[1],b);eq(s.workspace.library.settings.wheel_order.root[2],a)
eq(s.savedLibrary().settings.wheel_order.root[1],b);check(w.editConsumed);s.down[0x58]=false;s.down[0x11]=false;s.step();eq(#s.sent,0);healthy(s)
local saved=s.savedLibrary();onScriptTerminate(s.script);local rebuilt=wheel.build(saved);eq(rebuilt.categories[1].id,b)
-- A child drag can reorder a disabled bind; releasing the menu cannot launch it.
lib=model.defaults(core.defaults());for _,v in ipairs(lib.bindings)do v.wheel_visible=false end
for i=1,3 do lib.bindings[i].wheel_visible=true;lib.bindings[i].wheel_group='citizen'end;lib.bindings[1].enabled=false
s,w,l=open(lib);point(s,l,1);s.step();s.step(120);local entries=wheel.entries(w.catalog.categories[1]);check(#entries>=2)
point(s,l,1,1,#entries);s.down[0x11]=true;s.io.MouseDown[0]=true;s.mouseClicks={[0]=true};s.render();s.mouseClicks=nil;check(w.drag)
point(s,l,1,2,#entries);s.render();s.io.MouseDown[0]=false;s.render();s.step();check(s.workspace.library.settings.wheel_order.citizen)
eq(s.runtime.wheel.catalog.categories[1].items[1].id,lib.bindings[2].id);s.down[0x58]=false;s.down[0x11]=false;s.step();eq(#s.sent,0);healthy(s);onScriptTerminate(s.script)
-- Pure gesture guards: Ctrl release, cross-ring drop, unchanged source and revision changes.
local edit=require 'pa26_wheel_edit';local hit={ring='root',category='root',key='citizen',index=1,name='A'}
for _,mode in ipairs({'ctrl','ring','revision','same'})do
 local q={nav={}};edit.update(q,hit,{ctrl=true,clicked=true,down=true,now=1},1)
 local target={ring=mode=='ring'and'child'or'root',category='root',key=mode=='same'and'citizen'or'wanted',index=2,name='B'}
 check(not edit.update(q,target,{ctrl=mode~='ctrl',released=true,down=false,now=2},mode=='revision'and 2 or 1));check(q.editConsumed)
end
-- Classic six-slot wheel follows the same intent-only gesture and release guard.
lib=model.defaults(core.defaults());lib.settings.wheel_mode='classic'
s=fixture({productionWindows=true,library=lib,demo=true});s.step();if s.frames[1].condition()then s.commands.pa26();s.step()end
s.down[0x58]=true;s.step(16,{[0x58]=true});check(s.runtime.wheel);local before=model.copy(s.workspace.library.wheel)
local scale=math.min(1,(s.io.DisplaySize.x-32)/600,(s.io.DisplaySize.y-32)/650)
local cx,cy=s.io.DisplaySize.x/2,(s.io.DisplaySize.y-650*scale)/2+325*scale
local function classic(slot)local a=-math.pi/2+(slot-.5)*math.pi/3;s.io.MousePos.x=cx+math.cos(a)*150*scale;s.io.MousePos.y=cy+math.sin(a)*150*scale end
classic(1);s.down[0x11]=true;s.io.MouseDown[0]=true;s.mouseClicks={[0]=true};s.render();s.mouseClicks=nil
classic(2);s.render();s.io.MouseDown[0]=false;s.render();s.step()
local first,second=core.wheelSlots[1],core.wheelSlots[2]
eq(s.workspace.library.wheel[first],before[second]);eq(s.workspace.library.wheel[second],before[first])
s.down[0x58]=false;s.down[0x11]=false;s.step();eq(#s.sent,0);check(not s.hasLog('[ДЕМО БИНД]'));healthy(s);onScriptTerminate(s.script)

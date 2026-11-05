local fixture=require 'support.fixture';local m=require 'pa26_bindings';local core=require 'pa26_core'
local function setup()
 local lib=m.defaults(core.defaults());lib.profile.gender='female';lib.settings.manual_actions.enabled=false
 local b=m.newBinding(7);b.name='Context test';b.quick=true;b.favorite=true;b.command_alias='contexttest';b.skip_confirmation=true
 b.script='/m Автомобиль, остановитесь!\n@wait(1400)\n/m Водитель, руки на виду!'
 b.rp_context={vehicle='traffic',bike_script='/m Мотоцикл, остановитесь!\n@wait(1400)\n/m Водитель мотоцикла, руки на виду!',checkpoints={{before=1,prompt='Этап один?'},{before=2,prompt='Этап два?'}}}
 b.shortcut={key=0x74,ctrl=false,alt=false,shift=false};lib.bindings[#lib.bindings+1]=b;lib.next_id=8
 local s=fixture({productionWindows=true,demo=false,library=lib,categoryWheel=true});s.step()
 if s.frames[1].condition()then s.commands.pa26();s.step()end
 return s,b
end
for _,entry in ipairs({'manual','F9','F4','wheel','hotkey'})do
 local s,b=setup()
 if entry=='manual'then s.commands.contexttest('')
 elseif entry=='wheel'then check(s.runtime.env.startWheelBinding({binding=b,category='custom'},nil))
 elseif entry=='hotkey'then s.step(20,{[0x74]=true});s.step(20,{})
 else check(s.workspace:request({kind='prepare',id=7,start=true,args={},returnTo=entry=='F4'and'quick'or'binds'}))end
 for _=1,4 do s.step(200)end
 check(s.workspace.studio.bindingVariant,entry..' must offer manual vehicle choice');eq(#s.sent,0)
 s.render();check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)
 local intent=s.workspace.studio:modalIntent({});local preview=table.concat(intent.lines,'\n')
 check(preview:find('/m Автомобиль, остановитесь!',1,true));check(preview:find('/m Мотоцикл, остановитесь!',1,true))
 s.click='Мотоцикл / внешний осмотр##rp-variant-bike';s.render();eq(s.click,nil)
 for _=1,5 do s.step(200)end
 check(s.workspace.studio.executionConfirm,table.concat(s.logs,'\n'));eq(#s.sent,0)
 s.click='ДА##confirm-yes';s.render();eq(s.click,nil)
 for _=1,12 do s.step(200)end
 eq(#s.sent,1);eq(s.sent[1].line,'/m Мотоцикл, остановитесь!');check(s.workspace.studio.executionConfirm)
 s.click='НЕТ##confirm-no';s.render();s.step(200);eq(#s.sent,1);eq(s.workspace.executor.queue,nil)
 check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);onScriptTerminate(s.script)
end

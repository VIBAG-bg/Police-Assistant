local model=require 'pa26_bindings';local core=require 'pa26_core';local wheel=require 'pa26_wheel';local fixture=require 'support.fixture'
local seed=model.defaults(core.defaults());seed.settings.wheel_names={citizen='Общение',service='Радиосвязь',wanted='Нормы и санкции'}
for _,profile in ipairs({'compact','extended','full'})do
    seed.settings.wheel_profile=profile;local clean,err=model.validate(seed,core.defaults());check(clean,err)
    local cat=wheel.build(clean,1,true,{health=100});eq(cat.byCategory.citizen.name,'Общение');eq(cat.byCategory.service.label,'Радиосвязь')
    eq(cat.byId[1].category,'citizen');check(cat.bySystem.sos)
end
seed.settings.wheel_names.citizen='';local clean=model.validate(seed,core.defaults());eq(wheel.build(clean,1).byCategory.citizen.name,'Гражданин')
seed.settings.wheel_names.unknown='x';check(not model.validate(seed,core.defaults()));seed.settings.wheel_names.unknown=nil
local s=fixture({demo=false,alerts=true,notifications=true,categoryWheel=true});s.step();if s.frames[1].condition()then s.commands.pa26();s.step()end
s.down[0x58]=true;s.step(16,{[0x58]=true});check(s.runtime.wheel)
for i=1,25 do s.step(5000);check(s.runtime.wheel,'wheel stays open while X is held');eq(#s.sent,0)end
s.paused=true;s.step();check(not s.runtime.wheel);s.paused=false;s.down[0x58]=false;s.step();eq(#s.sent,0)
s.commands.pa26();s.step();s.page('settings');s.click='Доступ##settings-tab-options';s.render()
s.edits={['##Категория 1##wheel-name-citizen']='Свои обращения'};s.render();s.edits={};s.step(650)
eq(s.workspace.library.settings.wheel_names.citizen,'Свои обращения');eq(wheel.build(s.workspace.library,1).byCategory.citizen.name,'Свои обращения')
check(not s.hasLog('Ошибка интерфейса'));onScriptTerminate(s.script)

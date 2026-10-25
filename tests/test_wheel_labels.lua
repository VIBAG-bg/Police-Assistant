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
-- The editor and the category's More/search heading share saved custom names.
-- IDs and compact-profile folding remain stable when captions are renamed.
local names=s.workspace.library.settings.wheel_names
names.service='Радиосвязь';names.documents='Документы отдела';names.frisk='Проверки';names.custom='Мои действия'
local choices=wheel.categoryChoices(names)
eq(choices[1][1],'auto');eq(choices[1][2],'По категории бинда')
eq(#choices,9)
for i,id in ipairs(wheel.profiles.full)do eq(choices[i+1][1],id);eq(choices[i+1][2],wheel.categoryName(id,names))end
eq(wheel.categoryName('citizen',names),'Свои обращения')
eq(wheel.categoryName('documents',names),'Документы отдела')
eq(wheel.categoryName('service',{service=''}),'Служба')
eq(wheel.categoryName('service',{service='   '}),'Служба')
names.citizen='Одинаково';names.service='Одинаково'
choices=wheel.categoryChoices(names);eq(choices[2][1],'citizen');eq(choices[7][1],'service');eq(choices[2][2],choices[7][2])
names.citizen='Свои обращения';names.service='Радиосвязь'
s.page('binds');local studio=s.workspace.studio;studio:select(1);studio.editorTab='general'
local rendered;local originalChoice=studio.choice
studio.choice=function(self,label,value,items,ui)
    if label=='Категория колеса##bind-wheel-group'then rendered=items end
    return originalChoice(self,label,value,items,ui)
end
s.render();check(rendered);eq(rendered[2][2],'Свои обращения');eq(rendered[7][2],'Радиосвязь')
s.combo='##Категория колеса##bind-wheel-group'
s.click='Радиосвязь##Категория колеса##bind-wheel-groupservice';s.render();s.combo=nil
eq(s.click,nil);eq(studio.draft.wheel_group,'service')
-- A settings save/reload changes captions without touching the binding draft.
local reloaded=model.copy(s.workspace.library);reloaded.settings.wheel_names.service='Связь экипажа'
s.workspace.library=reloaded;studio:setLibrary(reloaded);s.render();eq(rendered[7][2],'Связь экипажа');eq(studio.draft.wheel_group,'service')
onScriptTerminate(s.script)
s=fixture({demo=false,library=reloaded});s.step();s.commands.pa26quick();s.step()
studio=s.workspace.studio;studio.quickWheelCategory='service';s.drawnText={};s.render()
check(table.concat(s.drawnText,'\n'):find('Колесо → Связь экипажа',1,true),table.concat(s.drawnText,' | '))
check(not s.hasLog('Ошибка интерфейса'));onScriptTerminate(s.script)

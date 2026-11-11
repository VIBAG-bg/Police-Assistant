local core=require 'pa26_core'
local model=require 'pa26_bindings'
local help=require 'pa26_help'
local fixture=require 'support.fixture'

local overlay=help.new(help.defaults())
local function labels(menu,wheel,assist)
    return overlay:shortcuts(menu,wheel,{key=assist,alt=true,ctrl=false,shift=false})
end
local keys=labels(0x77,0x56,0x73)
eq(keys.menuLabel,'F8');eq(keys.wheelLabel,'V');eq(keys.assistLabel,'Alt+F4')
eq(labels(0x77,0x56,0x73),keys)
local changed=labels(0x79,0x42,0)
eq(changed.assistLabel,'Не назначена');check(changed~=keys)
local copy=table.concat(help.instructions(keys),'\n')
for _,value in ipairs({'F8','V','Alt+F4','Copilot','Esc','RP','HUD'}) do check(copy:find(value,1,true),value) end
for _,size in ipairs({{640,480},{1152,864},{1366,768},{1920,1080},{2560,1440}}) do
    for _,pos in ipairs({{}, {x=0,y=0},{x=1,y=1}}) do
        local x,y,w,h=help.geometry(size[1],size[2],size[1]+40,size[2]+40,pos.x and pos or nil)
        check(x>=0 and y>=0 and x+w<=size[1] and y+h<=size[2])
    end
end
local _,y=help.geometry(640,480,225,120,nil,{x=394,y=137,w=234,h=180})
check(y>317 and y+120<=480)
check(not help.validate({position={x=-1,y=.4}}))
check(not help.validate({opacity=0}))

local lib=model.defaults(core.defaults())
lib.settings.help.welcome=true
lib.assist.open_shortcut={key=0x73,alt=true,ctrl=false,shift=false}
local s=fixture({productionWindows=true,library=lib,helpKeys={0x77,0x56}})
local frame=s.frames[#s.frames]
local studio=s.workspace.studio
s.spawned=false;s.step()
eq(studio.helpGuide,nil)
s.spawned=true;s.chat=true;s.step()
eq(studio.helpGuide,nil);check(not frame.condition())
s.chat=false
s.dialog=true;s.step()
eq(studio.helpGuide,nil);check(not frame.condition())
s.renderEnabled=false
s.dialog=false;s.step()
check(studio.helpGuide and studio.helpGuide.automatic)
s.dialog=true;s.step()
eq(studio.helpGuide,nil) -- Dialog opened after the offer but before the guide rendered.
eq(s.workspace.library.settings.help.welcome,true)
s.renderEnabled=true
s.dialog=false;s.step()
check(studio.helpGuide and studio.helpGuide.automatic)
local intent=studio:modalIntent({})
check(table.concat(intent.lines,'\n'):find('Alt+F4',1,true));check(not frame.condition())
s.click='Начать работу##pa26-help-start';s.render()
eq(s.click,nil);eq(studio.helpGuide,nil)
for _=1,4 do s.step(200)end
eq(s.workspace.library.settings.help.welcome,false)
eq(studio.helpGuide,nil)
local saved=model.copy(s.workspace.library)
if not s.frames[1].condition() then s.commands.pa26();s.step()end
s.click='Инструкции##pa26-instructions';s.render();eq(s.click,nil)
check(studio.helpGuide and not studio.helpGuide.automatic)
s.click='Закрыть##pa26-help-close';s.render();eq(s.click,nil)
if s.frames[1].condition()then s.commands.pa26();s.step()end
check(frame.condition() and frame.HideCursor and not frame.LockPlayer)
check(s.overlayAlpha and s.overlayAlpha>.7)
for _,key in ipairs({'paused','dialog','chat','console'}) do
    s[key]=true;s.step();check(not frame.condition(),key)
    s[key]=false;s.step();check(frame.condition(),key)
end
check(not s.hasLog('Подсказки клавиш отключены'));check(not s.hasLog('Ошибка интерфейса'))
onScriptTerminate(s.script)

local next=fixture({productionWindows=true,library=saved})
next.step()
eq(next.workspace.studio.helpGuide,nil)
local nextFrame=next.frames[#next.frames]
if not next.frames[1].condition()then next.commands.pa26();next.step()end
next.page('settings')
next.click='6. Экран, HUD и карта##settings-tab-general';next.render();eq(next.click,nil)
next.workspace.studio.screenSettingsPage='hud';next.render()
next.floatEdits={['Прозрачность##pa26-help-opacity']=.42,['Масштаб##pa26-help-scale']=1.2}
next.render();next.step(250)
check(math.abs(next.workspace.library.settings.help.opacity-.42)<.001)
check(math.abs(next.workspace.library.settings.help.scale-1.2)<.001)
next.click='Изменить положение##pa26-help-edit';next.render();eq(next.click,nil)
next.step();check(nextFrame.condition())
next.activeItem='Перетащить##pa26-help-drag';next.io.MouseDown[0]=true
next.io.MouseDelta.x=-50;next.io.MouseDelta.y=25;next.dragging=true;next.render()
next.io.MouseDown[0]=false;next.dragging=false
next.click='Сохранить##pa26-help-place';next.render();eq(next.click,nil)
next.step(250)
local pos=next.workspace.library.settings.help.position
check(pos and pos.x<1 and pos.y>.075)
next.click='Сбросить положение##pa26-help-reset';next.render();eq(next.click,nil);next.step(250)
eq(next.workspace.library.settings.help.position,nil)
next.click='Изменить положение##pa26-help-edit';next.render();next.step()
next.click='Скрыть подсказки##pa26-help-hide';next.render();eq(next.click,nil);next.step(250)
eq(next.workspace.library.settings.help.visible,false)
next.click='Открыть инструкции##pa26-help-open';next.render();eq(next.click,nil)
check(next.workspace.studio.helpGuide)
next.click='Больше не показывать автоматически##pa26-help-disable';next.render();eq(next.click,nil)
check(not next.hasLog('Ошибка интерфейса'))
onScriptTerminate(next.script)

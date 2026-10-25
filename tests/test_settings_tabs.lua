local fixture=require 'support.fixture'
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local bit=require 'bit'
local path='moonloader\\config\\police_assistant_2026_library.json'
local s=fixture(); s.step()
local button=s.imgui.Button
s.imgui.Button=function(label,size,...)
    local key=label:match('##settings%-tab%-(%a+)$')
    if key then s.settingsButtons[key]=label; check(size.x>0 and size.y==38) end
    return button(label,size,...)
end
local slider=s.imgui.SliderFloat
s.imgui.SliderFloat=function(label,value,min,max)
    if label=='Непрозрачность' and s.alphaEdit then value[0]=s.alphaEdit; s.alphaEdit=nil; return true end
    return slider(label,value,min,max)
end
local function fresh()
    s.drawnText={}; s.childCalls={}; s.settingsButtons={}; s.render()
end
local function drawn(needle)
    for _,text in ipairs(s.drawnText) do if text:find(needle,1,true) then return true end end
    return false
end
local function tab(key)
    fresh(); check(s.settingsButtons[key],'missing tab '..key)
    s.click=s.settingsButtons[key]; fresh(); eq(s.click,nil,'unconsumed tab '..tostring(s.click)..' | '..table.concat(s.logs,'\n'))
end
s.settingsButtons={}; s.page('settings'); fresh()
check(drawn('Режим работы')); check(drawn('Компактный виджет'))
check(not drawn('Профиль персонажа и ручные переменные')); check(not drawn('Клавиши отдельных окон'))
local before=s.savedBytes()
tab('profile')
check(drawn('Профиль персонажа и ручные переменные')); check(drawn('Экипаж и рация'))
check(not drawn('Режим работы')); check(not drawn('Клавиши отдельных окон'))
s.edits={['RP-имя##profile']='Officer Tabs',['Позывной экипажа##profile']='P-63',['Город (вручную)##profile']='Los Santos'}
fresh()
tab('options')
check(drawn('Клавиши отдельных окон')); check(drawn('Оформление окон')); check(drawn('Радиальное меню'))
check(not drawn('RP-имя')); check(not drawn('Режим работы'))
eq(s.savedBytes(),before,'navigation and unsaved profile edits must not write JSON')
s.alphaEdit=.62; fresh(); s.toggle='Компактные отступы'; fresh()
tab('general'); check(drawn('Режим работы'));s.step()
local appearance=s.savedLibrary();check(math.abs(appearance.settings.opacity-.62)<.001);check(appearance.settings.compact)
check(appearance.profile.name~='Officer Tabs','text gets a short debounce independently from checkboxes')
s.step(650);tab('profile')
local raw=s.savedLibrary(); eq(raw.profile.name,'Officer Tabs'); eq(raw.profile.callsign,'P-63'); eq(raw.profile.city,'Los Santos')
check(not drawn('Сохранить профиль'));tab('options');raw=s.savedLibrary()
check(math.abs(raw.settings.opacity-.62)<.001); check(raw.settings.compact); eq(raw.profile.callsign,'P-63')
check(model.validate(raw,core.defaults()))

-- Main-menu key changes are persisted immediately, without a Save button.
tab('general'); s.click='F10##Клавиша окна4'; fresh()
tab('profile'); tab('options'); tab('general')
fresh(); eq(s.saved.main.menu_key,0x79)
eq(s.savedLibrary().profile.name,'Officer Tabs')

-- The fixed tab bar is a separate non-scrolling child; only content scrolls.
fresh(); local bar,content
for _,child in ipairs(s.childCalls) do
    if child.name=='settings-tabs##pa26' then bar=child end
    if child.name=='content##pa26' then content=child end
end
check(bar and content); eq(bar.height,54); check(content.height>0)
check(bit.band(bar.flags,s.imgui.WindowFlags.NoScrollbar)~=0)
check(bit.band(bar.flags,s.imgui.WindowFlags.NoScrollWithMouse)~=0)
check(bit.band(content.flags,s.imgui.WindowFlags.NoScrollbar)==0)

-- All three sections remain accessible on a narrow game viewport.
s.io.DisplaySize.x,s.io.DisplaySize.y=640,480
for _,key in ipairs({'general','profile','options'}) do
    tab(key); eq(s.invalidIOReads,0); eq(#s.scopes,0)
    check(s.settingsButtons.general and s.settingsButtons.profile and s.settingsButtons.options)
end
onScriptTerminate(s.script)

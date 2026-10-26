local fixture=require 'support.fixture'
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local bit=require 'bit'
local routes=require 'support.ui_routes'
local s=fixture();s.step()
local button=s.imgui.Button
local sizes={}
s.imgui.Button=function(label,size,...)
    local key=label:match('##settings%-tab%-(%a+)$')
    if key then sizes[key]={x=size.x,y=size.y};check(size.x>0 and size.y>=38)end
    return button(label,size,...)
end
local function fresh()
    s.drawnText={};s.childCalls={};sizes={};s.render()
end
local function drawn(needle)
    for _,text in ipairs(s.drawnText)do if text:find(needle,1,true)then return true end end
    return false
end
local function tab(key)
    routes.settings(s,key);fresh()
    check(sizes[key]);check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);eq(s.invalidIOReads,0)
end
s.page('settings');fresh()
check(drawn('Персонаж и служба'));check(drawn('Экипаж и рация'))
check(not drawn('Клавиши отдельных окон'));check(not drawn('Поддержка чата лаунчера'))
local before=s.savedBytes()
s.edits={['RP-имя##profile']='Officer Tabs',['Позывной экипажа##profile']='P-63',['Город (вручную)##profile']='Los Santos'}
fresh();s.edits={}
tab('options')
check(drawn('Клавиши отдельных окон'));check(drawn('Радиальное меню'));check(not drawn('Оформление окон'))
check(not drawn('RP-имя'));check(not drawn('Режим работы'))
eq(s.savedBytes(),before,'navigation and unsaved profile edits must not write JSON')
routes.screen(s,'windows');fresh();check(drawn('Оформление окон'));check(drawn('Режим работы'));check(not drawn('Клавиши отдельных окон'))
s.floatEdits={['Непрозрачность']=.62};fresh();s.floatEdits={};s.toggle='Компактные отступы';fresh();s.step()
local appearance=s.savedLibrary();check(math.abs(appearance.settings.opacity-.62)<.001);check(appearance.settings.compact)
check(appearance.profile.name~='Officer Tabs','text gets a short debounce independently from checkboxes')
s.step(650);tab('profile')
local raw=s.savedLibrary();eq(raw.profile.name,'Officer Tabs');eq(raw.profile.callsign,'P-63');eq(raw.profile.city,'Los Santos')
check(not drawn('Сохранить профиль'));tab('options');raw=s.savedLibrary()
check(math.abs(raw.settings.opacity-.62)<.001);check(raw.settings.compact);eq(raw.profile.callsign,'P-63');check(model.validate(raw,core.defaults()))
-- The existing main-menu key remains in Controls and saves immediately.
s.click='F10##Клавиша окна4';fresh();tab('profile');tab('chat');tab('options');fresh()
eq(s.saved.main.menu_key,0x79);eq(s.savedLibrary().profile.name,'Officer Tabs')
-- The tab bar never scrolls; all six tabs fit in two rows on a narrow viewport.
for _,display in ipairs({{640,480},{1366,768},{2560,1440}})do
 s.io.DisplaySize.x,s.io.DisplaySize.y=display[1],display[2]
 for _,key in ipairs({'profile','chat','options','radio','weapons','general'})do
  tab(key)
  local bar,content
  for _,c in ipairs(s.childCalls)do if c.name=='settings-tabs##pa26'then bar=c elseif c.name=='content##pa26'then content=c end end
  check(bar and content);check(content.height>0)
  for _,k in ipairs({'profile','chat','options','radio','weapons','general'})do check(sizes[k],'Tab lost: '..k)end
  check(bar.height>=sizes.profile.y+16)
  if display[1]==640 then eq(bar.height,16+sizes.profile.y*2+8)end
  check(bit.band(bar.flags,s.imgui.WindowFlags.NoScrollbar)~=0)
  check(bit.band(bar.flags,s.imgui.WindowFlags.NoScrollWithMouse)~=0)
  check(bit.band(content.flags,s.imgui.WindowFlags.NoScrollbar)==0)
 end
end
onScriptTerminate(s.script)

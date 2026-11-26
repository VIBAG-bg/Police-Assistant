-- Native x86 ImGui layout and draw geometry. No GTA or game-file writes.
local root=assert(os.getenv('PA_SOURCE_ROOT'),'Set PA_SOURCE_ROOT')
local game=assert(os.getenv('PA_NATIVE_GAME'),'Set PA_NATIVE_GAME')..'/'
package.path=root..'/moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path
package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
getWorkingDirectory=function()return game..'MoonLoader'end
local ffi=require 'ffi'
local im=require 'mimgui.imgui'
local json=require 'cjson'
getWorkingDirectory=function()return root..'/moonloader'end
for name,prefix in pairs{HoveredFlags='ImGuiHoveredFlags_',Cond='ImGuiCond_',WindowFlags='ImGuiWindowFlags_',
 Col='ImGuiCol_',StyleVar='ImGuiStyleVar_',MouseCursor='ImGuiMouseCursor_',InputTextFlags='ImGuiInputTextFlags_',
 DrawCornerFlags='ImDrawCornerFlags_'}do
 im[name]=setmetatable({},{__index=function(_,k)return im.lib[prefix..k]end})
end
im.new={char=setmetatable({},{__index=function(_,n)return ffi.typeof('char['..n..']')end}),
 int=function(n)return ffi.new('int[1]',n)end,float=function(n)return ffi.new('float[1]',n)end,
 bool=function(n)return ffi.new('bool[1]',n)end}
local ctx=im.CreateContext(nil)
local gui=im.GetIO();gui.IniFilename=nil;gui.LogFilename=nil;gui.DeltaTime=1/60
local builder=im.ImFontGlyphRangesBuilder();builder:AddRanges(gui.Fonts:GetGlyphRangesCyrillic())
builder:AddText('–—…•×−№«»→✓★')
local ranges=im.ImVector_ImWchar();builder:BuildRanges(ranges)
local function font(name,size)return assert(gui.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/'..name,size,nil,ranges[0].Data))end
local fonts={body=font('segoeui.ttf',18),heading=font('segoeuib.ttf',24),brand=font('segoeuib.ttf',24),
 button=font('segoeuib.ttf',18),compact=font('segoeuib.ttf',16),small=font('segoeui.ttf',16),id=font('segoeuib.ttf',26)}
gui.FontDefault=fonts.body
local icons=require 'pa26_icons';assert(icons.initialize(im,ffi,fonts.button))
local pixels,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]')
gui.Fonts:GetTexDataAsRGBA32(pixels,w,h,nil)
gui.MousePos=im.ImVec2(-1000,-1000)
local texture=0
im.CreateTextureFromFile=function()texture=texture+1;return ffi.cast('void*',texture)end

local checks,frames=0,0
local function check(ok,why)checks=checks+1;assert(ok,why)end
local menu=require 'pa26_menu'
local settings=require 'pa26_settings_ui'
local wheel=require 'pa26_wheel'
local model=require 'pa26_bindings'
local theme=require 'pa26_theme'
local lib=model.defaults(require('pa26_core').defaults())
lib.settings.wheel_profile='full';lib.profile.name='Officer Demo'
local studio=require('pa26_studio').new(im,ffi,lib,function()return 1000 end)
studio.buttonFont=fonts.button;studio.headingFont=fonts.heading
local actions={actions=function()end,updates=function()end,openInstructions=function()end,openAssist=function()end,
 openPatrol=function()end,openSettings=function()end,applyProfilePreset=function()end,close=function()end,
 finishWork=function()end,save=function()error('No writes in an untouched render')end,
 patrolPreview=function()return '/f 1-L-1, продолжаю патруль.'end}
local function newUi()
 local stack={}
 return {push=function(fn)stack[#stack+1]=fn end,finish=function()assert(table.remove(stack))()end,
         text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end},stack
end
local colorDepth,varDepth=0,0
local colorPush,colorPop=im.PushStyleColor,im.PopStyleColor
local varFloat,varVec,varPop=im.PushStyleVarFloat,im.PushStyleVarVec2,im.PopStyleVar
im.PushStyleColor=function(...)colorDepth=colorDepth+1;return colorPush(...)end
im.PopStyleColor=function(n)colorDepth=colorDepth-(n or 1);return colorPop(n)end
im.PushStyleVarFloat=function(...)varDepth=varDepth+1;return varFloat(...)end
im.PushStyleVarVec2=function(...)varDepth=varDepth+1;return varVec(...)end
im.PopStyleVar=function(n)varDepth=varDepth-(n or 1);return varPop(n)end
local function drawFrame(shell,display,name,body)
 gui.DisplaySize=im.ImVec2(display[1],display[2]);gui.FontGlobalScale=1
 im.NewFrame()
 local ui,stack=newUi();shell:pushTheme(im,ui);local styles=#stack
 if name:find('##home-',1,true)then assert(shell:prepareWindow(im,'main'))
 else
  im.SetNextWindowPos(im.ImVec2(12,12),im.Cond.Always)
  im.SetNextWindowSize(im.ImVec2(display[1]-24,display[2]-24),im.Cond.Always)
 end
 im.Begin(name,nil,im.WindowFlags.NoTitleBar+im.WindowFlags.NoSavedSettings)
 studio.currentUi=ui
 body(ui)
 check(#stack==styles,name..' unmatched UI scope')
 im.End()
 while #stack>0 do ui.finish()end
 im.Render()
 check(im.GetDrawData().Valid,name..' invalid draw data')
 check(colorDepth==0 and varDepth==0,name..' ImGui style stack')
 frames=frames+1
end

local children,scroll,nav,presetButtons={},{},{},0
local oldBeginChild,oldEndChild,oldButton=im.BeginChild,im.EndChild,im.Button
im.BeginChild=function(name,...)children[#children+1]=name;return oldBeginChild(name,...)end
im.EndChild=function(...)
 local name=table.remove(children);scroll[name]=im.GetScrollMaxY()
 return oldEndChild(...)
end
im.Button=function(label,...)
 local clicked=oldButton(label,...)
 if label:find('##nav',1,true)then
  local a,b=im.GetItemRectMin(),im.GetItemRectMax()
  local origin,size=im.GetWindowPos(),im.GetWindowSize()
  check(a.x>=origin.x-1 and a.y>=origin.y-1 and b.x<=origin.x+size.x+1 and b.y<=origin.y+size.y+1,label..' outside navigation')
  nav[#nav+1]=label
 elseif label:find('##home-duty-preset-',1,true)then
  local a,b=im.GetItemRectMin(),im.GetItemRectMax()
  local origin,size=im.GetWindowPos(),im.GetWindowSize()
  check(a.y>=origin.y-1 and b.y<=origin.y+size.y+1,label..' outside profile')
  presetButtons=presetButtons+1
 end
 return clicked
end
local home={}
for _,row in ipairs(theme.choices)do
 for _,display in ipairs({{1920,1080},{2560,1440}})do
  for _,count in ipairs({0,3})do
   local shell=menu.new();shell.theme=row[1];shell:configureAssets(root..'/moonloader/resource/pa26')
   local data={connected=true,nickname='Officer_Demo',id=37,demo=false,caseNumber='Демо-профиль',
    todayRuns=18,todaySent=33,todayCuffs=2,todayFrisks=4,todayDocuments=8,profilePresets={}}
   if count>0 then data.profilePresets={{id=1,name='Патруль LSPS'},{id=2,name='SWAT'},{id=3,name='FBI'}};data.activeProfilePreset=1 end
   local key=row[1]..'-'..display[1]..'-'..count
   for _=1,3 do
    nav={};scroll={};presetButtons=0
    drawFrame(shell,display,'Police Assistant##home-'..key,function(ui)shell:draw(im,ui,data,actions,fonts)end)
   end
   check(#nav==8,key..' all eight navigation entries')
   check(presetButtons==count,key..' preset buttons')
   check(scroll['content##pa26']==0,key..' content scroll '..tostring(scroll['content##pa26']))
   check(scroll['navigation##pa26']==0,key..' navigation scroll '..tostring(scroll['navigation##pa26']))
   check(scroll['profile##pa26']==0,key..' profile scroll '..tostring(scroll['profile##pa26']))
   home[#home+1]={theme=row[1],width=display[1],height=display[2],presets=count,homeScroll=0,navScroll=0,navItems=#nav}
  end
 end
end
im.Button=oldButton;im.BeginChild=oldBeginChild;im.EndChild=oldEndChild

local responses={vehicle_description='Синяя машина',vehicle_plate='QA-42',occupants_text='1 водитель',unit='1-L-1'}
local data={demo=false,copilot={phase='10-55',car={id=42,distance=14,armed=true},driver={id=21},values=responses,
 stopWarnings=1,stopWarningLimit=5,windowActive=true,contactAvailable=true,stopWarningStatus='Требования остановиться · 1/5'},
 patrolSession={active={status='paused',id=1,unit='1-L-1',report_status='Ожидает',reason='Ручная пауза'},duration='00:04:12',unit='1-L-1'}}
local combo,columns=im.BeginCombo,im.Columns;local wheelControls,groups
im.BeginCombo=function(label,...)
 if wheelControls and label:find('##wheel-system-',1,true)then wheelControls[label]=true end
 return combo(label,...)
end
im.Columns=function(n,id,...)
 if groups and n==2 and id and id:find('wheel-actions-',1,true)then groups=groups+1 end
 return columns(n,id,...)
end
for _,row in ipairs(theme.choices)do
 local shell=menu.new();shell.theme=row[1]
 local screens={'F4','Патруль','Профиль','Управление','Окна','Чат'}
 for _,screen in ipairs(screens)do
  drawFrame(shell,{1366,768},screen..'##polish-'..row[1],function(ui)
   if screen=='F4' then studio.copilotPage='work';require('pa26_copilot_ui').draw(studio,ui,data,actions)
   elseif screen=='Патруль'then require('pa26_patrol_ui').draw(studio,ui,data,actions,'partners')
   elseif screen=='Профиль'then studio:drawProfile(ui,data,actions,'profile')
   elseif screen=='Управление'then
    studio.wheelActionsOpen={};wheelControls={};groups=0
    studio:drawOptions(ui,data,actions,'controls')
    check(next(wheelControls)==nil,'Wheel groups begin collapsed')
    studio.wheelActionsOpen={['foot-emergency']=true,['foot-patrol']=true,['foot-procedures']=true,['foot-traffic']=true}
    studio:drawOptions(ui,data,actions,'controls')
    local count=0;for _ in pairs(wheelControls)do count=count+1 end
    check(count==#wheel.systemRows and groups==4,'Every wheel action keeps its ID and uses the wide layout')
    wheelControls=nil;groups=nil
   elseif screen=='Окна'then
    require('pa26_interface_settings').draw(studio,ui,data,actions,shell,'windows')
    studio:drawOptions(ui,data,actions,'appearance')
   else require('pa26_interface_settings').draw(studio,ui,data,actions,shell,'chat')end
  end)
 end
end
im.BeginCombo=combo;im.Columns=columns

local tooltip,tooltipCount=im.BeginTooltip,0
im.BeginTooltip=function(...)tooltipCount=tooltipCount+1;return tooltip(...)end
for _,row in ipairs(theme.choices)do
 local shell=menu.new();shell.theme=row[1]
 local palette=theme.get(row[1]);local cursor
 im.Button=function(label,...)
  local result=oldButton(label,...)
  if label=='##settings-info-polish-tooltip'then
   local a,b=im.GetItemRectMin(),im.GetItemRectMax()
   cursor=im.ImVec2((a.x+b.x)/2,(a.y+b.y)/2)
  elseif label:find('##polish%-tone')then
   local expected=label:find('Основная',1,true)and palette.btnPrimary or palette.btnDanger
   local actual=im.GetStyleColorVec4(im.Col.Button)
   check(math.abs(actual.x-expected[1])<.001 and math.abs(actual.y-expected[2])<.001 and
    math.abs(actual.z-expected[3])<.001,row[1]..' semantic color')
  end
  return result
 end
 local function helpAndButtons(ui)
  studio:settingsHeading(ui,'Справка','Дополнительные условия параметра доступны внутри этой подсказки.','polish-tooltip')
  studio:button('Основная##polish-tone-primary',ui,nil,'primary')
  studio:button('Опасная##polish-tone-danger',ui,nil,'danger')
 end
 gui.MousePos=im.ImVec2(-1000,-1000)
 drawFrame(shell,{1366,768},'Справка##polish-tooltip-'..row[1],helpAndButtons)
 local previous=tooltipCount
 gui.MousePos=assert(cursor)
 drawFrame(shell,{1366,768},'Справка##polish-tooltip-'..row[1],helpAndButtons)
 check(tooltipCount==previous+1,row[1]..' tooltip opens at hover')
end
im.BeginTooltip=tooltip;im.Button=oldButton
gui.MousePos=im.ImVec2(-1000,-1000)

for _,name in pairs(icons.wheel)do check(icons.font:FindGlyphNoFallback(icons.points[name])~=nil,name..' missing from atlas')end
local catalog=wheel.build(lib,1,false)
check(#catalog.categories==8)
local drawIcon=icons.draw
local layout,painted
local function sector(rect,category)
 local center=-math.pi/2+(category-.5)*layout.step
 for _,x in ipairs({rect.x,rect.x+rect.w})do for _,y in ipairs({rect.y,rect.y+rect.w})do
  local dx,dy=x-layout.cx,y-layout.cy
  local radius=math.sqrt(dx*dx+dy*dy)
  local delta=(math.atan2(dy,dx)-center+math.pi)%(2*math.pi)-math.pi
  check(radius>=layout.inner and radius<=layout.rootOuter and math.abs(delta)<layout.step/2,'Wheel icon crosses a wedge')
 end end
end
icons.draw=function(imgui,name,x,y,size,...)
 local result=drawIcon(imgui,name,x,y,size,...)
 if result then
  local i
  for n,cat in ipairs(catalog.categories)do if icons.wheel[cat.id]==name then i=n;break end end
  sector({x=x,y=y,w=size},assert(i));painted=painted+1
 end
 return result
end
local resolutions={{640,480},{800,600},{800,1100},{1024,768},{1366,768},{1920,1080},{2560,1440}}
local wheelCases={}
for _,display in ipairs(resolutions)do
 for _,enabled in ipairs({true,false})do
  icons.setEnabled(enabled);layout=assert(wheel.layout(display[1],display[2],8));painted=0
  local shell=menu.new();shell.theme='swat'
  drawFrame(shell,display,'Wheel##polish-'..display[1]..'x'..display[2],function()
   wheel.draw(im,layout,catalog,{active=1,choice=wheel.entries(catalog.categories[1])[1]},
    {demo=true,key='X',theme='swat',icons=enabled},fonts)
  end)
  if enabled and layout.scale>=.72 then check(painted>0,'Expected at least one fitted icon')
  else check(painted==0,'Wheel icon mode or minimum scale')end
  if display[1]>=1920 and enabled then check(painted==8,'All standard wedges at full size should have icons')end
  wheelCases[#wheelCases+1]={width=display[1],height=display[2],enabled=enabled,icons=painted}
 end
end
icons.draw=drawIcon;icons.clear();im.DestroyContext(ctx)
local out=assert(io.open(root..'/tests/UX_NATIVE32_0470.json','wb'))
out:write(json.encode({status='passed',checks=checks,frames=frames,home=home,wheel=wheelCases,game_started=false,game_written=false}));out:close()
print('0.47.0 native x86: '..checks..' checks; '..frames..' frames; '..#home..' Home variants; '..#wheelCases..' wheel variants.')

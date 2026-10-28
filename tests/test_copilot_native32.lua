-- Actual installed x86 ImGui, CPU-only. No GTA, input injection or sends.
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/');local root=assert(source:match('^(.*)/tests/'))
local game=os.getenv('LOCALAPPDATA')..'/Exsellent Launcher/game/'
package.path=root..'/moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path
package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
getWorkingDirectory=function()return game..'MoonLoader'end
local ffi=require 'ffi';local im=require 'mimgui.imgui'
for name,prefix in pairs{HoveredFlags='ImGuiHoveredFlags_',Cond='ImGuiCond_',WindowFlags='ImGuiWindowFlags_',Col='ImGuiCol_',StyleVar='ImGuiStyleVar_',MouseCursor='ImGuiMouseCursor_',InputTextFlags='ImGuiInputTextFlags_',DrawCornerFlags='ImDrawCornerFlags_'}do im[name]=setmetatable({},{__index=function(_,k)return im.lib[prefix..k]end})end
im.new={char=setmetatable({},{__index=function(_,n)return ffi.typeof('char['..n..']')end}),int=function(n)return ffi.new('int[1]',n)end,float=function(n)return ffi.new('float[1]',n)end,bool=function(n)return ffi.new('bool[1]',n)end}
local ctx=im.CreateContext(nil);local io=im.GetIO();io.IniFilename=nil;io.LogFilename=nil;io.DeltaTime=1/60
io.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeui.ttf',16,nil,io.Fonts:GetGlyphRangesCyrillic())
local pixels,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]');io.Fonts:GetTexDataAsRGBA32(pixels,w,h,nil)
local model=require 'pa26_bindings';local core=require 'pa26_core';local Studio=require 'pa26_studio';local uiModule=require 'pa26_copilot_ui';local menu=require 'pa26_menu'
local s=Studio.new(im,ffi,model.defaults(core.defaults()),function()return 1000 end)
local stack={};local ui={push=function(f)stack[#stack+1]=f end,finish=function()assert(table.remove(stack))()end,text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
local data={copilot={phase='Преследование',car={id=142,occupants=2,distance=15,armed=true},driver={id=37},values={model='Sultan',vehicle_color='Чёрный',vehicle_plate='не установлен',occupants_text='внутри двое',unit='2-A-1'},colleagues={nearbyOfficers={},nearbyCruisers=2,ownCruiserRole='navigator'},pinned='fast_wanted',tireStatus='Предупреждений: 1/5. Проверьте условия применения силы.'}}
local cb={copilotPreview=function()return'Предпросмотр с сохранёнными значениями.'end}
s.currentUi=ui;s.preferenceContext=true
local checks,frames=0,0
local function check(v,why)checks=checks+1;assert(v,why)end
for _,display in ipairs({{640,480},{800,600},{1024,768},{1152,864},{1366,768},{1920,1080},{2560,1440}})do
 io.DisplaySize=im.ImVec2(display[1],display[2])
 for _,page in ipairs({'work','settings'})do for frame=1,3 do
  s.copilotPage=page;im.NewFrame();im.SetNextWindowPos(im.ImVec2(16,16),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(display[1]-32,display[2]-32),im.Cond.Always)
  im.Begin('copilot-native',nil,im.WindowFlags.NoSavedSettings);im.BeginChild('content',im.ImVec2(0,0),false)
  uiModule.draw(s,ui,data,cb);check(#stack==0,'Balanced content scopes');im.EndChild();im.End();im.Render();check(im.GetDrawData().Valid);frames=frames+1
 end end
 -- Every new RP/radio editor is rendered with actual Cyrillic font metrics.
 for _,entry in ipairs(require('pa26_dispatch').templates)do
  s.copilotPage='settings';s.copilotTemplate=entry[1]
  im.NewFrame();im.SetNextWindowPos(im.ImVec2(16,16),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(display[1]-32,display[2]-32),im.Cond.Always)
  im.Begin('dispatch-native',nil,im.WindowFlags.NoSavedSettings);im.BeginChild('content',im.ImVec2(0,0),false)
  uiModule.draw(s,ui,data,cb);check(#stack==0,'Dispatch editor scopes');im.EndChild();im.End();im.Render();check(im.GetDrawData().Valid);frames=frames+1
 end
 im.NewFrame()
 local hud=require('pa26_hud').new(core.widgetDefaults(),{decode=function(v)return v end});hud.settings.scale=.8
 local vv=model.copy(data.copilot);vv.visible=true;vv.duration=15;vv.cooldown=0
 local controller={state={mouseAllowed=false,demo=true},life=1,now=1000,view=function()return vv end}
 local fonts={body=im.GetFont(),heading=im.GetFont()}
 uiModule.reserve(controller,im,hud,fonts,0);uiModule.place(controller,im,hud,fonts)
 check(controller.bounds,'Tactical card fits the HUD lane')
 local box=controller.bounds;check(box.x>=0 and box.y>=0 and box.x+box.w<=display[1]and box.y+box.h<=display[2],'HUD card within viewport')
 uiModule.drawHud(controller,im);im.Render();frames=frames+1
 for _,phase in ipairs({'patrol','10-55','10-66','Преследование','10-57 FOXTROT'})do
  im.NewFrame();hud:setEquipmentHeight(0);hud:setConfirmationHeight(68)
  vv.phase=phase~='patrol'and phase or nil;vv.car=phase~='patrol'and model.copy(data.copilot.car)or nil
  vv.statusTitle=phase=='patrol'and'ПАТРУЛЬ · КОД 4'or phase..' · КОД 3';vv.statusCode=phase=='patrol'and 4 or 3
  vv.values={unit='1-A-3',city='Лос-Сантос',direction='Северо-восток',area='Район с длинным названием',map_square='H-17',crew='Иван Петров, Мария Иванова',model='Sultan',occupants_text='внутри двое'}
  uiModule.reserve(controller,im,hud,fonts,62);uiModule.place(controller,im,hud,fonts)
  local b=controller.bounds;check(b~=nil,'Patrol/traffic card plus Taser and SOS must fit '..display[1]..' '..phase)
  check(b.x>=0 and b.y>=0 and b.x+b.w<=display[1]and b.y+b.h<=display[2],'Entire card within screen')
  local lane=hud:attachmentLayout(im,fonts);check(lane and lane.confirmation and lane.equipment,'All attachments reserved')
  check(b.y>=lane.confirmation.y+lane.confirmation.h or b.x+b.w<=lane.confirmation.x or b.x>=lane.confirmation.x+lane.confirmation.w,'No SOS overlap')
  check(b.y>=lane.equipment.y+62,'No Taser overlap');check(controller.hudMetrics.traffic==(phase~='patrol'),'Traffic buttons only during traffic')
  uiModule.drawHud(controller,im);im.Render();check(im.GetDrawData().Valid);frames=frames+1
 end
 hud:setConfirmationHeight(0)
 -- Full confirmation text is paginated, never internally scrolled.
 local lines={};for i=1,24 do lines[i]='Строка '..i..': длинное RP-сообщение и отдельное подтверждение действия с выбранным водителем.'end
 im.NewFrame();im.Begin('layout-check',nil,im.WindowFlags.NoSavedSettings)
 local layout=menu.confirmationLayout(im,{title='Подтвердить ориентировку и розыск?',lines=lines,titleFont=im.GetFont(),buttonFont=im.GetFont(),pageState={},columns=2,buttons={'ДА','НЕТ'}})
 check(layout.width<=display[1]-20,'Modal width');check(layout.height<=display[2]-20,'Modal height');im.End();im.Render();frames=frames+1
 local cfg=require('pa26_copilot_settings').defaults();local dispatchLines={cfg.robbery_warning,cfg.dispatch_confirmation_note}
 for line in(cfg.templates.dispatch_business_rp..'\n'..cfg.templates.robbery_business..'\n'):gmatch('(.-)\n')do dispatchLines[#dispatchLines+1]=line end
 im.NewFrame();im.Begin('dispatch-modal-layout',nil,im.WindowFlags.NoSavedSettings)
 local risk=menu.confirmationLayout(im,{title='Ограбление бизнеса · проверьте состав патруля',lines=dispatchLines,titleFont=im.GetFont(),buttonFont=im.GetFont(),pageState={},columns=2,buttons={'ДА','НЕТ'}})
 check(risk.width<=display[1]-20,'Business warning width');check(risk.height<=display[2]-20,'Business warning paginates within screen');im.End();im.Render();frames=frames+1
end
im.DestroyContext(ctx);print('Copilot native32: '..checks..' checks; '..frames..' frames; seven screen sizes; patrol/traffic, SOS and Taser; no game writes.')

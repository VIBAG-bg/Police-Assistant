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
local model=require 'pa26_bindings';local core=require 'pa26_core';local Studio=require 'pa26_studio'
local studio=Studio.new(im,ffi,model.defaults(core.defaults()),function()return 1000 end)
local stack={};local ui={push=function(f)stack[#stack+1]=f end,finish=function()assert(table.remove(stack))()end,text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
local prefs=require 'pa26_copilot_settings';local speech=require 'pa26_ground_speech'
local request={kind='stop',token='native:ground',groundTarget={id=42,name='Driver_Name'},groundCar={id=12}}
studio.groundForm={request=request,cfg=prefs.defaults()};studio.groundForm.cfg.stop_ground='wrong_way'
local cb={groundValid=function()return true end,groundSpeech=function(f)return speech.text(f.cfg,f.cfg.stop_ground,'female')end,
 groundPreview=function(f)return{lines={'/s '..(f.cfg._ground_speech or 'Точная речь для проверки окна.')}}end,
 copilotPreview=function()return 'Предпросмотр реплики с текущими настройками.'end}
local frames=0
for _,display in ipairs({{640,480},{800,600},{1024,768},{1152,864},{1366,768},{1920,1080},{2560,1440}})do
 io.DisplaySize=im.ImVec2(display[1],display[2])
 for _,page in ipairs({'form','settings','report'})do for frame=1,3 do
  im.NewFrame();im.SetNextWindowPos(im.ImVec2(12,12),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(display[1]-24,display[2]-24),im.Cond.Always)
  im.Begin('PA QoL native32',nil,im.WindowFlags.NoSavedSettings);im.BeginChild('content',im.ImVec2(0,0),false)
  if page=='report'then
   studio.reportEdit={proposal={token='report:native'},values={unit='1-L-42',crew='Иван Петров, Мария Иванова',city='Сан-Фиерро',area='Garcia',map_square='J-6',direction='неизвестно'}}
   require('pa26_copilot_ui').editReport(studio,ui,cb)
  else studio.reportEdit=nil;studio.groundPage=page;require('pa26_ground_window').draw(studio,ui,{copilot={values={model='Sultan',vehicle_color='Чёрный'}}},cb)end
  assert(#stack==0,'Unbalanced scope');im.EndChild();im.End();im.Render();assert(im.GetDrawData().Valid);frames=frames+1
 end end
end
im.DestroyContext(ctx)
print('QoL native32: '..frames..' frames; scrollable grounds, editable speech, report editor; seven screen sizes; no game writes.')

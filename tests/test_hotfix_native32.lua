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

local checks,frames=0,0
local function check(ok,why)checks=checks+1;assert(ok,why)end
local encoding=require 'encoding';encoding.default='CP1251'
local codec={encode=function(text)return encoding.UTF8:decode(text)end,decode=function(text)return encoding.UTF8(text)end}
local data={codec=codec,localNickname='Officer_Name',chatFiltersAvailable=true,patrolSession={history={}}}
s.currentUi=ui;s.preferenceContext=true
local oldColumns=im.Columns;local columns=0
im.Columns=function(count,...)if count==2 then columns=columns+1 end;return oldColumns(count,...)end
for _,screen in ipairs({{640,480},{800,600},{1024,768},{1152,864},{1366,768},{1920,1080},{2560,1440}})do
 io.DisplaySize=im.ImVec2(screen[1],screen[2])
 for _,page in ipairs({'commands','taser','patrol'})do
  for frame=1,3 do
   im.NewFrame();im.SetNextWindowPos(im.ImVec2(16,16),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(screen[1]-32,screen[2]-32),im.Cond.Always)
   im.Begin('hotfix-settings',nil,im.WindowFlags.NoSavedSettings);im.BeginChild('hotfix-content',im.ImVec2(0,0),false)
   local before=columns
   if page=='commands'then
    require('pa26_manual_actions').draw(s,ui)
    check((columns>before)==(im.GetWindowWidth()>=620),'Checkbox columns adapt to the actual available width')
   elseif page=='taser'then s:drawTaser(ui,data,{})
   else require('pa26_patrol_ui').draw(s,ui,data,{patrolPreview=function()return'2-A-1, начинаем патруль, доступны.'end})end
   check(#stack==0,'Balanced UI scopes')
   im.EndChild();im.End();im.Render();check(im.GetDrawData().Valid,'Valid native frame');frames=frames+1
  end
 end
end
im.Columns=oldColumns;im.DestroyContext(ctx)
local instance=require('pa26_patrol_session').clientInstance(ffi)
check(type(instance)=='string'and #instance>0,'Process continuity token uses real native API')
check(instance==require('pa26_patrol_session').clientInstance(ffi),'Token is stable within this process')
print('Hotfix native32: '..checks..' checks; '..frames..' frames; command checklist and independent taser RP on seven screen sizes; no game writes.')

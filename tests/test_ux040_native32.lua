-- Real installed 32-bit LuaJIT/ImGui; CPU-only frames, never a GTA process.
local src=debug.getinfo(1,'S').source:sub(2):gsub('\\','/')
local tests=assert(src:match('^(.*[/])'));local release=tests..'../'
local game=assert(os.getenv('LOCALAPPDATA'), 'LOCALAPPDATA required')..'/Exsellent Launcher/game/'
getWorkingDirectory=function()return game..'MoonLoader'end
package.path=release..'moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path
package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
local ffi=require 'ffi';local im=require 'mimgui.imgui'
for field,prefix in pairs{HoveredFlags='ImGuiHoveredFlags_',Cond='ImGuiCond_',WindowFlags='ImGuiWindowFlags_',Col='ImGuiCol_',
    StyleVar='ImGuiStyleVar_',MouseCursor='ImGuiMouseCursor_',InputTextFlags='ImGuiInputTextFlags_',DrawCornerFlags='ImDrawCornerFlags_'}do
    im[field]=setmetatable({},{__index=function(_,key)return im.lib[prefix..key]end})
end
im.new={char=setmetatable({},{__index=function(_,n)return ffi.typeof('char['..n..']')end}),
    int=function(v)return ffi.new('int[1]',v)end,float=function(v)return ffi.new('float[1]',v)end,bool=function(v)return ffi.new('bool[1]',v)end}
local ctx=im.CreateContext(nil);local guiIo=im.GetIO();guiIo.IniFilename=nil;guiIo.LogFilename=nil;guiIo.DeltaTime=1/60
guiIo.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeui.ttf',16,nil,guiIo.Fonts:GetGlyphRangesCyrillic())
local pixels,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]');guiIo.Fonts:GetTexDataAsRGBA32(pixels,w,h,nil)

local model=require 'pa26_bindings';local core=require 'pa26_core';local Studio=require 'pa26_studio'
local settings=require 'pa26_settings_ui';local menu=require 'pa26_menu'
local editor=Studio.new(im,ffi,model.defaults(core.defaults()),function()return 1000 end)
local enc=require('encoding').CP1251
local codec={encode=function(t)return enc:encode(t,'UTF-8')end,decode=function(t)return enc:decode(t,'UTF-8')end}
local data={demo=true,codec=codec,radioState={area='Doherty'},vehicle={},nearby={enabled=true,rows={}},chatFiltersAvailable=true,accentInputAvailable=true}
local stack={};local ui={push=function(f)stack[#stack+1]=f end,finish=function()assert(table.remove(stack))()end,
 text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
local cb=setmetatable({vehiclePreview=function()return nil,'Выберите машину.'end},{__index=function()return function()error('Native QA must not execute actions')end end})
local frames,checks=0,0;local function check(ok,why)checks=checks+1;assert(ok,why)end
local tabRects={};local button=im.Button
im.Button=function(label,...)
 local out=button(label,...)
 if label:find('##settings%-tab%-')then
  local a,b=im.GetItemRectMin(),im.GetItemRectMax();local p,z=im.GetWindowPos(),im.GetWindowSize()
  check(a.x>=p.x and b.x<=p.x+z.x,'Settings tab escapes width: '..label)
  check(a.y>=p.y and b.y<=p.y+z.y,'Settings tab escapes height: '..label)
  tabRects[label]=true
 end
 return out
end
local pages={{'profile'},{'chat','accent'},{'chat','split'},{'chat','commands'},{'chat','filters'},
 {'options'},{'radio','emergency'},{'radio','patrol'},{'radio','automatic'},{'weapons','draw'},{'weapons','taser'},{'weapons','warning'},
 {'general','windows'},{'general','hud'},{'general','map'},{'general','recovery'}}
for _,display in ipairs({{640,480},{1366,768},{1920,1080},{2560,1440}})do
 guiIo.DisplaySize=im.ImVec2(display[1],display[2])
 for _,page in ipairs(pages)do
  editor.chatSettingsPage=page[1]=='chat'and page[2]or'accent';editor.screenSettingsPage=page[1]=='general'and page[2]or'windows'
  editor.radioPage=page[1]=='radio'and page[2]or'emergency';editor.weaponPage=page[1]=='weapons'and page[2]or'draw'
  for frame=1,4 do
   im.NewFrame();im.SetNextWindowPos(im.ImVec2(16,16),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(display[1]-32,display[2]-32),im.Cond.Always)
   im.Begin('ux-native',nil,im.WindowFlags.NoSavedSettings+im.WindowFlags.NoMove+im.WindowFlags.NoResize)
   local available=im.GetContentRegionAvail().x;local tab=settings.tabLayout(available+16,im.GetFont())
   im.BeginChild('tabs',im.ImVec2(0,tab.total),false,im.WindowFlags.NoScrollbar+im.WindowFlags.NoScrollWithMouse)
   settings.drawTabs(editor,ui,page[1],function()error('No clicks in native QA')end,im.GetFont());im.EndChild()
   im.BeginChild('content',im.ImVec2(0,0),false)
   settings.draw(editor,ui,data,cb,page[1],{menu=menu.new(),general=function(name)ui.text('Main controls: '..name)end})
   im.EndChild();check(#stack==0,'Scope imbalance: '..page[1]);im.End();im.Render();check(im.GetDrawData().Valid,'No draw data');frames=frames+1
  end
 end
end
for _,row in ipairs(settings.tabs)do check(tabRects[row[2]..'##settings-tab-'..row[1]],'Missing native tab '..row[1])end
im.DestroyContext(ctx)
print('Native UX040: '..checks..' checks; '..frames..' frames; 640x480 through 2560x1440; no game writes.')

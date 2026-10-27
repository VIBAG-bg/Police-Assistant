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
local largeFont=guiIo.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeui.ttf',24,nil,guiIo.Fonts:GetGlyphRangesCyrillic())
local pixels,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]');guiIo.Fonts:GetTexDataAsRGBA32(pixels,w,h,nil)



local model=require 'pa26_bindings';local core=require 'pa26_core';local Studio=require 'pa26_studio';local menu=require 'pa26_menu'
local lib=model.defaults(core.defaults());for i=7,83 do local b=model.copy(lib.bindings[1]);b.id=i;b.name='Сценарий '..i..' · проверка документов';lib.bindings[i]=b end;lib.next_id=84
local s=Studio.new(im,ffi,lib,function()return 1000 end);s:select(1)
local fonts={};local data={demo=false,connected=true,nearby={enabled=true,rows={}},journal={session={}},stats={}}
local stack={};local ui={push=function(f)stack[#stack+1]=f end,finish=function()assert(table.remove(stack))()end,text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
local m=menu.new();m.section='binds';local cb={close=function()end,binds=function()s:draw('binds',ui,data,{openQuick=function()end})end,actions=function()end,settings=function()end}
local sizes,rects,children={},{},{};local child,endChild,button=im.BeginChild,im.EndChild,im.Button
im.BeginChild=function(name,size,...)
 local ok=child(name,size,...);children[#children+1]=name
 local z=im.GetWindowSize();sizes[name]={w=z.x,h=z.y};return ok
end
im.EndChild=function()local name=table.remove(children);sizes[name].scroll=im.GetScrollMaxY();return endChild()end
im.Button=function(name,...)
 local result=button(name,...);local a,b=im.GetItemRectMin(),im.GetItemRectMax();rects[name]={x=(a.x+b.x)/2,y=(a.y+b.y)/2,visible=im.IsItemVisible()};return result
end
local checks,frames=0,0;local function check(v,why)checks=checks+1;assert(v,why)end
local function fontSetup(big)
 if big then im.PushFont(largeFont)end
 for _,key in ipairs({'body','small','compact','button','heading','brand'})do fonts[key]=im.GetFont()end;s.buttonFont=im.GetFont()
end
local function frame(res,fraction,big,warning)
 guiIo.DisplaySize=im.ImVec2(res[1],res[2]);im.NewFrame();fontSetup(big)
 if warning then
  im.SetNextWindowPos(im.ImVec2(0,0),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(1,1),im.Cond.Always)
  im.Begin('PA##warning-host',nil,im.WindowFlags.NoDecoration+im.WindowFlags.NoSavedSettings+im.WindowFlags.NoBackground+im.WindowFlags.NoInputs)
  s:drawModal(ui,data,{})
 else
  im.SetNextWindowPos(im.ImVec2(16,16),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(math.max(608,res[1]*fraction-32),math.max(448,res[2]*fraction-32)),im.Cond.Always)
  im.Begin('hotfix',nil,im.WindowFlags.NoSavedSettings);m:pushTheme(im,ui);m:draw(im,ui,data,cb,fonts)
 end
 while #stack>0 do ui.finish()end;im.End();if big then im.PopFont()end;im.Render();frames=frames+1;check(im.GetDrawData().Valid,'Draw data');check(#children==0,'Balanced children')
end
for _,res in ipairs({{1152,864},{640,480},{1366,768},{1920,1080},{2560,1440}})do
 for _,fraction in ipairs({1,.7})do for _,big in ipairs({false,true})do for _,pane in ipairs({'list','editor'})do
  s.bindPane=pane;sizes={};for _=1,4 do frame(res,fraction,big)end
  local rows=sizes['bindrows##studio'];local editor=sizes['bind-editor-body##studio'];local root=sizes['binding-workspace##studio']
  check(root and root.h>0,'Workspace must exist')
  if rows then check(rows.h>=120,'Usable list height: '..rows.h)end
  if editor then check(editor.h>=80,'Usable editor body: '..editor.h)end
  if res[1]==1152 and fraction==1 and not big then
   check(rows and rows.h>=200,'1152x864 must show multiple binding cards');check(editor and editor.h>=200,'1152x864 must have a usable editor')
   if pane=='list'then print('1152x864 fullscreen: list '..rows.h..' px; editor '..editor.h..' px.')end
  end
  if res[1]==640 then check(root.scroll>0,'Short screens must allow access through outer scrolling')end
 end end end
end
-- Real mouse press/release on the management menu. Each original action remains reachable.
s.bindPane='list';rects={};for _=1,4 do frame({1152,864},1,false)end
local target=assert(rects['Действия с биндами##bind-tools']);guiIo.MousePos=im.ImVec2(target.x,target.y);frame({1152,864},1,false)
guiIo.MouseDown[0]=true;frame({1152,864},1,false);guiIo.MouseDown[0]=false;frame({1152,864},1,false);frame({1152,864},1,false)
for _,name in ipairs({'Дублировать##bind','Удалить##bind','Экспорт всех биндов','Импорт биндов','Экспорт выбранного бинда','Файлы обмена##bind-files'})do check(rects[name]and rects[name].visible,'Management action must be visible: '..name)end
-- Close that popup by clicking outside, then click the exact standalone OK path.
guiIo.MousePos=im.ImVec2(20,20);guiIo.MouseDown[0]=true;frame({1152,864},1,false);guiIo.MouseDown[0]=false;frame({1152,864},1,false)
s:notify('Набор сохранён. Резервная копия: D:\\GTA 140K BY DAPO SHOW1221\\moonloader\\config\\police_assistant_2026_preset_backup_9ef01f8d1c08be47aef2a0c7faa21057. Нажмите ОК — PA перезапустится и применит новые значения. Игра продолжит работать.','updates',false,'info')
rects={};for _=1,4 do frame({1152,864},1,false,true)end;target=assert(rects['ОК##warning-ok']);check(target.visible,'OK is visible')
guiIo.MousePos=im.ImVec2(target.x,target.y);frame({1152,864},1,false,true);guiIo.MouseDown[0]=true;frame({1152,864},1,false,true);guiIo.MouseDown[0]=false;frame({1152,864},1,false,true)
check(not s:hasWarning(),'Real mouse release must acknowledge the standalone dialog')
im.DestroyContext(ctx);print('Hotfix0404 native32: '..checks..' checks; '..frames..' frames; five resolutions, 70%/full windows, 16/24px fonts, real menu/OK clicks; no GTA.')

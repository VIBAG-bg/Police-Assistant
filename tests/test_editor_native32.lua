-- Installed 32-bit ImGui, CPU-only. This does not start GTA or write game files.
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
local bold=guiIo.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeuib.ttf',18,nil,guiIo.Fonts:GetGlyphRangesCyrillic())
local pixels,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]');guiIo.Fonts:GetTexDataAsRGBA32(pixels,w,h,nil)
local model=require 'pa26_bindings';local core=require 'pa26_core';local Studio=require 'pa26_studio'

local editor=Studio.new(im,ffi,model.defaults(core.defaults()),function()return 1000 end)
editor:select(1)
local checks,frames=0,0
local function check(v,why)checks=checks+1;assert(v,why)end
local stack={};local ui={push=function(fn)stack[#stack+1]=fn end,finish=function()assert(table.remove(stack))()end,
 text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
editor.currentUi=ui
local long='/me '..string.rep('осмотрел документы и сверил подпись с фотографией. ',45)
editor.draft.script=long
local fieldRect,saveRect
local input=im.InputTextMultiline
im.InputTextMultiline=function(label,...)
 local result=input(label,...);local a,b=im.GetItemRectMin(),im.GetItemRectMax()
 fieldRect={x=a.x,y=a.y,w=b.x-a.x,h=b.y-a.y};return result
end
local function fieldFrame()
 im.SetNextWindowPos(im.ImVec2(60,50),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(620,520),im.Cond.Always)
 im.Begin('Long text QA',nil,im.WindowFlags.NoSavedSettings+im.WindowFlags.NoResize+im.WindowFlags.NoMove)
 editor.currentUi=ui;local value,changed=editor:field('##native-long','script',long,16385,true,220);if changed then long=value;editor.draft.script=value end
 im.End()
end
local draw=fieldFrame
local function frame()
 im.NewFrame();draw();check(#stack==0,'unbalanced UI scopes');im.Render();frames=frames+1
end
for _,key in ipairs({'End','Home','LeftArrow','RightArrow'})do
 local vk=({End=0x23,Home=0x24,LeftArrow=0x25,RightArrow=0x27})[key]
 guiIo.KeyMap[im.lib['ImGuiKey_'..key]]=vk
end
guiIo.DisplaySize=im.ImVec2(1280,720);guiIo.MousePos=im.ImVec2(-100,-100)
for i=1,4 do frame()end
check(editor.textViews.script.content>editor.textViews.script.viewport*5,'text should exceed the viewport')
local viewX,viewY=fieldRect.x,fieldRect.y
-- Real mouse focus followed by End and Shift+Left. No synthetic caret injection.
guiIo.MousePos=im.ImVec2(viewX+25,viewY+8);guiIo.MouseDown[0]=true;frame();guiIo.MouseDown[0]=false;frame()
guiIo.KeysDown[0x23]=true;frame();guiIo.KeysDown[0x23]=false
for i=1,4 do frame()end
local v=editor.textViews.script
check(v.cursor==#long,'End must reach the end of UTF-8 text')
check(v.scroll>1000,'End should scroll the external viewport to the tail: '..tostring(v.scroll)..' content='..v.content..' width='..v.viewport..' cursor='..tostring(v.cursor)..' first='..tostring(v.first)..' active='..tostring(v.active)..' max='..tostring(v.maximum))
local tailScroll=v.scroll
guiIo.KeyShift=true
for i=1,8 do guiIo.KeysDown[0x25]=true;frame();guiIo.KeysDown[0x25]=false;frame()end
guiIo.KeyShift=false
check(v.first~=v.last,'Shift+Left must select the tail')
check(v.cursor>#long-100,'selection must not reset the cursor to the beginning')
check(v.scroll>=tailScroll-200,'selection must keep the tail visible')
check(ffi.string(editor.cache.script)==long,'selection cannot modify the text')
-- Drag selection inside the visible tail; ensure no snap to the beginning.
guiIo.MousePos=im.ImVec2(viewX+v.viewport-45,viewY+8);guiIo.MouseDown[0]=true;frame()
guiIo.MousePos=im.ImVec2(viewX+v.viewport-125,viewY+8);frame();guiIo.MouseDown[0]=false;frame()
check(v.first~=v.last,'mouse drag should select a tail substring')
check(v.cursor>#long-200,'mouse selection must remain near the tail')
check(v.scroll>1000,'mouse selection must not reset horizontal scroll')
check(ffi.string(editor.cache.script)==long,'mouse selection changed the text')
editor.variable='select_id';check(editor:insertVariable(),'prepare variable at tail selection')
for i=1,3 do frame()end
check(long:find('{select_id}',1,true),'variable did not replace the selected tail')
check(v.cursor>#long-200,'variable insertion lost the tail position')
editor.feedback:clear()
-- A real horizontal scrollbar exists and has a nonzero range.
check(v.content-v.viewport>1000)
-- Full editor: save stays outside the scroll body and at the same screen Y.
local oldButton=im.Button
im.Button=function(label,...)
 local result=oldButton(label,...)
 if label=='Сохранить сценарий'then local p=im.GetItemRectMin();saveRect={x=p.x,y=p.y}end
 return result
end
editor.editorTab='text';editor.editor='steps';editor:clearSteps();editor.cache={};editor.draft.script=long..'\n@wait(1500)\n'..long
local scrollBody=false;local begin=im.BeginChild
im.BeginChild=function(label,...)
 local result=begin(label,...)
 if scrollBody and label=='bind-editor-body##studio'then im.SetScrollY(10000)end
 return result
end
draw=function()
 im.SetNextWindowPos(im.ImVec2(50,40),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(650,580),im.Cond.Always)
 im.Begin('Full editor QA',nil,im.WindowFlags.NoSavedSettings+im.WindowFlags.NoResize+im.WindowFlags.NoMove)
 editor.currentUi=ui;editor:drawEditor(ui,{demo=true},{save=function()error('native test must not save')end})
 im.End()
end
guiIo.MousePos=im.ImVec2(-100,-100)
for i=1,4 do frame()end
local pinned=assert(saveRect).y;scrollBody=true
for i=1,4 do frame();check(saveRect.y==pinned,'save button moved with the editor body')end
editor:release();im.DestroyContext(ctx)
local f=assert(io.open(tests..'EDITOR_NATIVE32_RESULTS.json','wb'))
f:write(string.format('{"status":"passed","checks":%d,"frames":%d,"real_keyboard_selection":true,"real_mouse_selection":true,"horizontal_viewport":true,"pinned_save":true,"gta_started":false,"game_files_written":false}\n',checks,frames));f:close()
print('Editor native32: '..checks..' checks, '..frames..' frames; real keyboard and mouse selection passed.')

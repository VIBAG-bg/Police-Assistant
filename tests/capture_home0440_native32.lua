-- Synthetic CPU preview of the real F9 renderer. No GTA, sends, or settings I/O.
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/');local root=assert(source:match('^(.*)/tests/'))
local game=os.getenv('LOCALAPPDATA')..'/Exsellent Launcher/game/'
package.path=root..'/moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path
package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
getWorkingDirectory=function()return game..'MoonLoader'end
local ffi=require 'ffi';local im=require 'mimgui.imgui';local json=require 'cjson'
for name,prefix in pairs{HoveredFlags='ImGuiHoveredFlags_',Cond='ImGuiCond_',WindowFlags='ImGuiWindowFlags_',Col='ImGuiCol_',StyleVar='ImGuiStyleVar_',MouseCursor='ImGuiMouseCursor_',InputTextFlags='ImGuiInputTextFlags_',DrawCornerFlags='ImDrawCornerFlags_'}do
 im[name]=setmetatable({},{__index=function(_,k)return im.lib[prefix..k]end})
end
local ctx=im.CreateContext(nil);local gui=im.GetIO();gui.IniFilename=nil;gui.LogFilename=nil;gui.DeltaTime=1/60
local builder=im.ImFontGlyphRangesBuilder();builder:AddRanges(gui.Fonts:GetGlyphRangesCyrillic())
builder:AddText('‐‑‒–—―…•×−≈≠≤≥→←↑↓↔№«»„“”‘’✓✔▲▼★☆')
local ranges=im.ImVector_ImWchar();builder:BuildRanges(ranges)
local function font(name,size)return gui.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/'..name,size,nil,ranges[0].Data)end
local fonts={heading=font('segoeuib.ttf',24),brand=font('segoeuib.ttf',24),button=font('segoeuib.ttf',18),compact=font('segoeuib.ttf',16),small=font('segoeui.ttf',16)}
local body=font('segoeui.ttf',18);gui.FontDefault=body
local icons=require 'pa26_icons';assert(icons.initialize(im,ffi,fonts.button))
local pixels,aw,ah=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]');gui.Fonts:GetTexDataAsRGBA32(pixels,aw,ah,nil)
local function write(name,bytes)local f=assert(io.open(root..'/tests/home0440/'..name,'wb'));f:write(bytes);f:close()end
write('atlas.rgba',ffi.string(pixels[0],aw[0]*ah[0]*4))
local textures={};im.CreateTextureFromFile=function(path)
 local id=#textures+1;textures[id]={id=tostring(id),path=path:gsub('\\','/')};return ffi.cast('void*',id)
end
local originalButton=im.Button;local nav,navScroll={},nil
local childNames={};local bodyScroll
local beginChild,endChild=im.BeginChild,im.EndChild
im.BeginChild=function(name,...)
 childNames[#childNames+1]=name;return beginChild(name,...)
end
im.EndChild=function(...)
 if childNames[#childNames]=='content##pa26'then bodyScroll=im.GetScrollMaxY()end
 childNames[#childNames]=nil;return endChild(...)
end
im.Button=function(label,...)
 local result=originalButton(label,...)
 if label:find('##nav',1,true)then
  local a,b=im.GetItemRectMin(),im.GetItemRectMax();local p,s=im.GetWindowPos(),im.GetWindowSize()
  nav[#nav+1]={label=label,x=a.x,y=a.y,w=b.x-a.x,h=b.y-a.y,inside=a.y>=p.y-1 and b.y<=p.y+s.y+1}
  navScroll=im.GetScrollMaxY()
 end
 return result
end
local menuModule=require 'pa26_menu';local results={}
local callbacks={actions=function()error('Unexpected old home route')end,updates=function()error('No update request')end,
 openAssist=function()error('No input')end,openPatrol=function()error('No input')end,openSettings=function()error('No input')end,
 finishWork=function()error('No input')end,updateLabel='Обновления PA'}
local model={connected=true,nickname='Officer_Demo',id=37,ping=42,district='Doherty',mapSquare='J-6',clock='01.11.2026 12:00',
 demo=false,menuKey='F9',wheelKey='X',quickKey='F11',tipsKey='F12',assistKey='F4',caseNumber='Демо-профиль',evidence={screens={nearLimit=false}}}
for _,display in ipairs({{1920,1080},{2560,1440}})do
 local m=menuModule.new();m.section='home';m.opacity=.8299999833107;m.compact=false
 m:configureAssets(root..'/moonloader/resource/pa26')
 gui.DisplaySize=im.ImVec2(display[1],display[2]);gui.MousePos=im.ImVec2(-1000,-1000);gui.FontGlobalScale=1
 local capture
 for frame=1,4 do
  nav={};im.NewFrame();assert(m:prepareWindow(im,'main'))
  local stack={};local ui={push=function(fn)stack[#stack+1]=fn end,finish=function()assert(table.remove(stack))()end,
   text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
  im.PushFont(body);m:pushTheme(im,ui)
  local flags=im.WindowFlags.NoTitleBar+im.WindowFlags.NoSavedSettings+im.WindowFlags.NoCollapse+im.WindowFlags.NoScrollbar+im.WindowFlags.NoScrollWithMouse+im.WindowFlags.NoResize+im.WindowFlags.NoMove
  im.Begin('Police Assistant 2026##pa26-main',nil,flags)
  m:resizeWindow(im,ui,'main');m:draw(im,ui,model,callbacks,fonts)
  local p,s=im.GetWindowPos(),im.GetWindowSize();capture={x=p.x,y=p.y,w=s.x,h=s.y}
  im.End();while #stack>0 do ui.finish()end;im.PopFont();im.Render()
 end
 assert(#nav==8,'All 8 navigation sections must render');for _,r in ipairs(nav)do assert(r.inside,r.label..' clipped')end
 assert(navScroll<=1,'Navigation unexpectedly scrolls')
 assert(bodyScroll and bodyScroll<=1,'Home content unexpectedly scrolls: '..tostring(bodyScroll))
 local dd=im.GetDrawData();local lists={};local name='F9-Home-'..display[1]..'x'..display[2]
 for i=0,dd.CmdListsCount-1 do
  local list=dd.CmdLists[i];local cmds={}
  for n=0,list.CmdBuffer.Size-1 do local c=list.CmdBuffer.Data[n];cmds[#cmds+1]={count=c.ElemCount,clip={c.ClipRect.x,c.ClipRect.y,c.ClipRect.z,c.ClipRect.w},texture=tostring(tonumber(ffi.cast('uintptr_t',c.TextureId)))}end
  write(name..'-'..i..'.verts',ffi.string(list.VtxBuffer.Data,list.VtxBuffer.Size*ffi.sizeof('ImDrawVert')))
  write(name..'-'..i..'.indices',ffi.string(list.IdxBuffer.Data,list.IdxBuffer.Size*ffi.sizeof('ImDrawIdx')))
  lists[#lists+1]={file=name..'-'..i,commands=cmds}
 end
 write(name..'.json',json.encode({width=display[1],height=display[2],atlas={w=tonumber(aw[0]),h=tonumber(ah[0])},lists=lists,textures=textures}))
 results[#results+1]={resolution=display,window=capture,navigation=nav,navigation_scroll=navScroll,content_scroll=bodyScroll,profile='representative_demo',status='passed'}
end
icons.clear();im.DestroyContext(ctx)
local f=assert(io.open(root..'/tests/HOME_PREVIEWS0440.json','wb'));f:write(json.encode({kind='synthetic_real_native_cpu_mesh',game_started=false,user_data_modified=false,version='0.44.0',results=results}));f:close()
print('Synthetic F9 Home captured at 1920x1080 and 2560x1440; all eight sections visible.')

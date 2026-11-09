-- Native x86 CPU UI frames and optional mesh captures. No GTA or network writes.
local root=assert(os.getenv('PA_SOURCE_ROOT'),'Set PA_SOURCE_ROOT to the candidate directory')
local game=(os.getenv('PA_NATIVE_GAME')or os.getenv('LOCALAPPDATA')..'/Exsellent Launcher/game')..'/'
package.path=root..'/moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path
package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
getWorkingDirectory=function()return game..'MoonLoader'end -- Read-only native library lookup.
local ffi=require 'ffi';local im=require 'mimgui.imgui';local json=require 'cjson'
getWorkingDirectory=function()return root..'/moonloader'end -- All subsequent PA paths stay in the candidate.
for name,prefix in pairs{HoveredFlags='ImGuiHoveredFlags_',Cond='ImGuiCond_',WindowFlags='ImGuiWindowFlags_',Col='ImGuiCol_',StyleVar='ImGuiStyleVar_',MouseCursor='ImGuiMouseCursor_',InputTextFlags='ImGuiInputTextFlags_',DrawCornerFlags='ImDrawCornerFlags_'}do im[name]=setmetatable({},{__index=function(_,k)return im.lib[prefix..k]end})end
im.new={char=setmetatable({},{__index=function(_,n)return ffi.typeof('char['..n..']')end}),int=function(n)return ffi.new('int[1]',n)end,float=function(n)return ffi.new('float[1]',n)end,bool=function(n)return ffi.new('bool[1]',n)end}
local ctx=im.CreateContext(nil);local io=im.GetIO();io.IniFilename=nil;io.LogFilename=nil;io.DeltaTime=1/60
local builder=im.ImFontGlyphRangesBuilder();builder:AddRanges(io.Fonts:GetGlyphRangesCyrillic());builder:AddText('–—…•№«»→✓★')
local ranges=im.ImVector_ImWchar();builder:BuildRanges(ranges)
local body=io.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeui.ttf',18,nil,ranges[0].Data)
local heading=io.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeuib.ttf',24,nil,ranges[0].Data)
local button=io.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeuib.ttf',18,nil,ranges[0].Data)
local icons=require 'pa26_icons';assert(icons.initialize(im,ffi,button));io.FontDefault=body
local pixels,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]');io.Fonts:GetTexDataAsRGBA32(pixels,w,h,nil)
local function read(path)local f=assert(_G.io.open(root..'/'..path,'rb'));local text=f:read('*a');f:close();return text end
local kb=json.decode(read('moonloader/resource/pa26/knowledge-base.json'))
local k=require('pa26_knowledge').new({json=json});k:activate(kb);k.important=require('pa26_knowledge_important').build(k)
local model=require 'pa26_bindings';local lib=model.defaults(require('pa26_core').defaults());lib.profile.name='Officer Demo'
local studio=require('pa26_studio').new(im,ffi,lib,function()return 1000 end);studio.buttonFont=button
local view=require('pa26_knowledge_ui').new(im,ffi,k);view.headingFont=heading;view.buttonFont=button
local stack={};local ui={push=function(fn)stack[#stack+1]=fn end,finish=function()assert(table.remove(stack))()end,
 text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
studio.currentUi=ui
local callbacks={save=function()error('No save from an untouched draw')end,patrolPreview=function()return '/f 1-L-1, продолжаю патруль.'end}
local screens={'patrol','patrol-settings','f4','f4-dispatch','f4-shell','f9-shell','home','knowledge','guide','appearance','field-coordinates','field-cruiser','field-pinned','field-leadership','field-briefings','pinned-overlay','ooc-marker','cef-diagnostics','help-guide','help-overlay','help-position'}
local hotkeys=require 'pa26_help'
local help=hotkeys.new(lib.settings.help)
local helpKeys=help:shortcuts(0x77,0x56,{key=0x73,ctrl=false,alt=true,shift=false})
local frames,checks=0,0;local function check(ok,why)checks=checks+1;assert(ok,why)end
local data={radioState={area='Doherty',city='Сан-Фиерро',map_square='J-6'},patrolSession={},copilot={phase='10-55',
 car={id=42,distance=12},driver={id=37,name='Known_Driver'},values={model='Sultan',vehicle_color='Чёрный',vehicle_plate='PA-42',occupants_text='Водитель и 1 пассажир',unit='1-A-12'},
 colleagues={nearbyOfficers={},nearbyCruisers=1},stopWarnings=1,stopWarningLimit=5,stopWarningStatus='Требования остановиться: 1/5',tireStatus='Огонь по колёсам требует проверки условий.'}}
local function write(path,bytes)local f=assert(_G.io.open(root..'/'..path,'wb'));f:write(bytes);f:close()end
local capture=os.getenv('PA_CAPTURE_NATIVE')=='1'
local function mesh(name,display)
 local dd=im.GetDrawData();local lists={};local stem='tests/native0450/'..name
 for i=0,dd.CmdListsCount-1 do local list=dd.CmdLists[i];local cmds={}
  for n=0,list.CmdBuffer.Size-1 do local cmd=list.CmdBuffer.Data[n];cmds[#cmds+1]={count=cmd.ElemCount,clip={cmd.ClipRect.x,cmd.ClipRect.y,cmd.ClipRect.z,cmd.ClipRect.w}}end
  write(stem..'-'..i..'.verts',ffi.string(list.VtxBuffer.Data,list.VtxBuffer.Size*ffi.sizeof('ImDrawVert')))
  write(stem..'-'..i..'.indices',ffi.string(list.IdxBuffer.Data,list.IdxBuffer.Size*ffi.sizeof('ImDrawIdx')))
  lists[#lists+1]={file=name..'-'..i,commands=cmds}
 end
 write(stem..'.json',json.encode({width=display[1],height=display[2],atlas={w=tonumber(w[0]),h=tonumber(h[0])},lists=lists}))
end
if capture then write('tests/native0450/atlas.rgba',ffi.string(pixels[0],w[0]*h[0]*4))end
for _,display in ipairs({{640,480},{800,600},{800,1100},{1024,768},{1366,768},{1920,1080},{2560,1440}})do
 for _,scale in ipairs({1,1.25})do for _,enabled in ipairs({false,true})do for _,screen in ipairs(screens)do
  io.DisplaySize=im.ImVec2(display[1],display[2]);io.FontGlobalScale=scale;icons.setEnabled(enabled)
  studio.copilotPage='work';studio.dispatchIncident=screen=='f4-dispatch'and'dispatch_gas'or'none'
  view.importantView={query='',card=screen=='guide'and'fines'or nil,tab='*'}
  for pass=1,2 do
   im.NewFrame();im.SetNextWindowPos(im.ImVec2(14,14),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(display[1]-28,display[2]-28),im.Cond.Always)
   im.Begin('Police Assistant 0.45.0 · '..screen,nil,im.WindowFlags.NoSavedSettings)
   local theme=require('pa26_menu').new();theme:pushTheme(im,ui)
   local themeDepth=#stack
   im.BeginChild('body',im.ImVec2(0,0),false,im.WindowFlags.AlwaysUseWindowPadding)
   if screen=='f9-shell'or screen=='home'then
    local shell=require('pa26_menu').new();shell.section=screen=='home'and'home'or'partners'
    shell:draw(im,ui,{connected=true,nickname='Officer_Demo',id=45,ping=61,district='Doherty',clock='01.11.2026',menuKey='F9'},
     {partners=function()studio:drawPartners(ui,data,callbacks)end,actions=function()end,
      updates=function()end,openInstructions=function()end,openAssist=function()error('Unexpected navigation')end,openPatrol=function()error('Unexpected navigation')end,openSettings=function()error('Unexpected navigation')end},
     {heading=heading,brand=heading,button=button,compact=button,small=body})
   elseif screen=='f4-shell'then studio.assistPage='traffic';require('pa26_assist_ui').draw(studio,ui,data,callbacks)
   elseif screen=='patrol'then require('pa26_patrol_ui').draw(studio,ui,data,callbacks,'partners')
   elseif screen=='patrol-settings'then require('pa26_patrol_ui').drawSessionSettings(studio,ui,data,callbacks)
   elseif screen=='f4-dispatch'then require('pa26_copilot_ui').dispatch(studio,ui,callbacks)
   elseif screen=='f4' then require('pa26_copilot_ui').draw(studio,ui,data,callbacks)
   elseif screen:match('^field%-')then
    studio.fieldPage=screen=='field-briefings'and'leadership'or screen:sub(7)
    studio.leaderPage=screen=='field-briefings'and'briefing'or'news';studio.briefingIndex=1
    require('pa26_field_ui').settings(studio,ui,data,callbacks)
   elseif screen=='pinned-overlay'then
    local cfg=require('pa26_field_settings').defaults().pinned;cfg.enabled=true;cfg.note_id=1
    local pin=require('pa26_pinned_note').new();pin:update({{id=1,name='Памятка',body=string.rep('Строка памятки. ',600)}},cfg,1)
    pin:draw(im,cfg,display[1],display[2],false)
   elseif screen=='ooc-marker'then
    local view={a=.1,b=0,c=0,d=.1,ox=200,oy=200,left=0,top=0,right=display[1],bottom=display[2]}
    local cfg=require('pa26_field_settings').defaults().navigation
    assert(require('pa26_coord_share').drawMarker(im,view,{x=100,y=100},cfg.opacity))
   elseif screen=='cef-diagnostics'then
    studio.showCefDiagnostics=true;data.cefCompatibility={state='RUNTIME_VERIFIED',known=false,sha256=string.rep('d',64),fingerprint='exsellent-chat-v1:demo',mode='cef',runtime='CONFIRMED',capabilities={dom=true,outgoing=true,incoming=true,payloads=true,lifecycle=true,focus=true,ipc=true,adapter_order=true},reason='normalized_contract_and_dom'}
    studio:drawProfile(ui,data,callbacks,'chat_cef')
   elseif screen=='help-guide'then
    studio.helpGuide={automatic=true};studio.helpKeys=helpKeys
    studio:drawModal(ui,data,callbacks);check(studio.helpGuide.shown,'Welcome popup did not draw')
    studio.helpGuide=nil;studio:drawModal(ui,data,callbacks);studio.modalToken=nil
   elseif screen=='help-overlay'or screen=='help-position'then
    help.editing=screen=='help-position'and{}or nil
    help:draw(im,ui,lib.settings.help,helpKeys,studio)
    check(#help.layout.rows>=5 and help.layout.keys==helpKeys,'Native shortcut text missing')
   elseif screen=='appearance'then studio:drawOptions(ui,data,callbacks,'appearance')
   else require('pa26_knowledge_important_ui').draw(view,ui,callbacks)end
   im.EndChild();check(#stack==themeDepth,'Unbalanced view scopes');while #stack>0 do ui.finish()end
   im.End();im.Render();check(im.GetDrawData().Valid);frames=frames+1
   if capture and pass==2 and enabled and scale==1 and(display[1]==1366 or display[1]==800 and display[2]==1100)then mesh(screen..'-'..display[1]..'x'..display[2],display)end
  end
 end end end
end
-- Drive actual x86 mouse frames through F4's production geometry, including the fallback path.
local m26=require 'pa26_menu'
local initial={x=220,y=115,width=730,height=500,displayW=1366,displayH=768}
io.DisplaySize=im.ImVec2(initial.displayW,initial.displayH);io.FontGlobalScale=1
local edges={{'left',-1,0},{'right',1,0},{'top',0,-1},{'bottom',0,1},
 {'tl',-1,-1},{'tr',1,-1},{'bl',-1,1},{'br',1,1}}
for _,native in ipairs({false,true})do
 io.BackendFlags=native and 2 or 0
 io.ConfigWindowsResizeFromEdges=native
 for _,edge in ipairs(edges)do
  local m=m26.new();m.windows.assist=model.copy(initial);m.forceWindows={assist=true}
  local saved
  m.geometryChanged=function(_,rect)saved=model.copy(rect)end
  local function frame(x,y,down)
   io.MousePos=im.ImVec2(x,y);io.MouseDown[0]=down
   im.NewFrame();check(m:prepareWindow(im,'assist'))
   local flags=im.WindowFlags.NoCollapse+im.WindowFlags.NoSavedSettings+im.WindowFlags.NoMove+
    im.WindowFlags.NoResize+im.WindowFlags.NoScrollbar+im.WindowFlags.NoScrollWithMouse
   im.Begin('F4 geometry##'..tostring(native)..edge[1],nil,flags)
   m:resizeWindow(im,ui,'assist')
   check(#stack==0,'Resize scope closed')
   im.End();im.Render();frames=frames+1
  end
  local dx,dy=edge[2],edge[3]
  local x=initial.x+(dx<0 and 2 or dx>0 and initial.width-3 or initial.width/2)
  local y=initial.y+(dy<0 and 2 or dy>0 and initial.height-3 or initial.height/2)
  frame(x,y,false);frame(x,y,false);frame(x,y,true)
  frame(x+dx*27,y+dy*23,true);frame(x+dx*27,y+dy*23,false)
  frame(x+dx*27,y+dy*23,false)
  check(saved and (dx==0 or saved.width>initial.width) and (dy==0 or saved.height>initial.height),
   ('F4 edge %s, native=%s, got %.1fx%.1f'):format(edge[1],tostring(native),saved and saved.width or 0,saved and saved.height or 0))
  local reopened=m26.windowRect(initial.displayW,initial.displayH,'assist',saved)
  check(reopened.width==saved.width and reopened.height==saved.height,'Saved F4 dimensions restore')
 end
end
icons.clear();im.DestroyContext(ctx)
write(os.getenv('PA_NATIVE_REPORT')or'tests/UX_NATIVE32_0452.json',json.encode({status='passed',checks=checks,frames=frames,screen_sizes=7,views=#screens,font_scales=2,icon_states=2,game_started=false,game_written=false}))
print('UX 0.45.2 native32: '..frames..' frames; '..#screens..' views, seven sizes, two scales and icon states.')

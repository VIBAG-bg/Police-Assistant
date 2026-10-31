-- Real x86 LuaJIT + ImGui, isolated CPU frames. Never launch or write GTA.
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
local encoding=require 'encoding';encoding.default='CP1251'
local codec={encode=function(t)return encoding.UTF8:decode(t)end,decode=function(t)return encoding.UTF8:encode(t)end}
local model=require 'pa26_bindings';local core=require 'pa26_core';local Studio=require 'pa26_studio'
local Session=require 'pa26_patrol_session';local grid=require 'pa26_map_grid'
local checks,frames,sends=0,0,0
local function check(v,why)checks=checks+1;assert(v,why)end
local displays={{640,480},{800,600},{1024,768},{1152,864},{1366,768},{1920,1080},{2560,1440}}
for _,display in ipairs(displays)do for _,scenario in ipairs({'known-custom','unknown-custom','unknown-stock'})do
 io.DisplaySize=im.ImVec2(display[1],display[2])
 local lib=model.defaults(core.defaults());lib.profile.name='Victor Auditore';lib.profile.callsign='A-1';lib.patrol_session.unit='1-L-1';lib.patrol_session.enabled=true
 if scenario~='unknown-stock'then for _,key in ipairs({'start','resume','finish','crew','periodic'})do lib.patrol_session[key..'_template']='{unit}: '..key..', курс {direction}.'end end
 local saved=model.copy(lib.patrol_session)
 local state={session='test',ped=1,alive=true,demo=false,gender='male',area='Doherty',city='Сан-Фиерро',map_square='J-6',map_grid=grid.defaults(),
  direction=scenario=='known-custom'and'север'or nil,directionKnown=scenario=='known-custom',local_tag='',my_nick='Victor_Auditore'}
 local session=Session.new({settings=function()return lib.patrol_session end,profile=function()return lib.profile end,contacts=function()return{}end,codec=codec,
  start=function()sends=sends+1;error('A preview must never queue a command')end})
 session.now=1000
 local studio=Studio.new(im,ffi,lib,function()return 1000 end);studio.partnerPage='patrol'
 local stack={};local warnings,previews=0,0
 local ui={push=function(f)stack[#stack+1]=f end,finish=function()assert(table.remove(stack))()end,
  text=function(text)if text:find('{direction}:',1,true)then warnings=warnings+1 end;im.PushTextWrapPos(0);im.TextUnformatted(text);im.PopTextWrapPos()end}
 local callbacks={save=function()return true end,openPatrol=function()end,
  patrolPreview=function(action,draft)
   previews=previews+1
   local record,why=session:makeRecord(draft,state);if not record then return nil,why end
   local line;line,why=session:prepareLine(action,record,state,draft)
   if scenario=='unknown-custom'then check(line==nil and type(why)=='string'and why:find('{direction}',1,true),why)
   else check(line~=nil,why)end
   return line and line.line,why
  end}
 studio.currentUi=ui
 for frame=1,4 do
  warnings,previews=0,0
  im.NewFrame();im.SetNextWindowPos(im.ImVec2(12,12),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(display[1]-24,display[2]-24),im.Cond.Always)
  im.Begin('F9 patrol validation',nil,im.WindowFlags.NoSavedSettings);im.BeginChild('content',im.ImVec2(0,0),false)
  local data={radioState=state};if frame==2 then data.patrolSession={}elseif frame>=3 then data.patrolSession={history={}}end
  studio:drawPartners(ui,data,callbacks)
  check(previews==5,'All five preview actions must run');check(warnings==(scenario=='unknown-custom'and 5 or 0),'Independent warning text')
  check(#stack==0,'Unbalanced ImGui scope');im.EndChild();im.End();im.Render();check(im.GetDrawData().Valid)
  for _,key in ipairs({'start','resume','finish','crew','periodic'})do check(studio.patrolSessionDraft[key..'_template']==saved[key..'_template'],'Personal template changed')end
  check(sends==0);frames=frames+1
 end
end end
im.DestroyContext(ctx)
local file=assert(_G.io.open(root..'/tests/F9_NATIVE32_RESULTS.json','wb'))
file:write(string.format('{"status":"passed","checks":%d,"frames":%d,"screen_sizes":%d,"game_written":false,"game_started":false,"command_sends":%d}\n',checks,frames,#displays,sends));file:close()
print('F9 patrol native32: '..checks..' checks, '..frames..' frames, seven screen sizes; no game writes or sends.')

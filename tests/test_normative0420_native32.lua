-- Real installed x86 ImGui; all seven resolutions, 70%/full, 16/24 px fonts.
-- Read-only game DLL loading, no GTA process, writes, sends or input injection.
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/')
local tests=assert(source:match('^(.*[/])'));local root=tests..'../'
local game=os.getenv('LOCALAPPDATA')..'/Exsellent Launcher/game/'
getWorkingDirectory=function()return game..'MoonLoader'end
package.path=root..'moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path
package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
local ffi=require 'ffi';local im=require 'mimgui.imgui'
for field,prefix in pairs{HoveredFlags='ImGuiHoveredFlags_',Cond='ImGuiCond_',WindowFlags='ImGuiWindowFlags_',Col='ImGuiCol_',StyleVar='ImGuiStyleVar_',MouseCursor='ImGuiMouseCursor_',InputTextFlags='ImGuiInputTextFlags_',DrawCornerFlags='ImDrawCornerFlags_'}do im[field]=setmetatable({},{__index=function(_,key)return im.lib[prefix..key]end})end
im.new={char=setmetatable({},{__index=function(_,n)return ffi.typeof('char['..n..']')end}),int=function(v)return ffi.new('int[1]',v)end,float=function(v)return ffi.new('float[1]',v)end,bool=function(v)return ffi.new('bool[1]',v)end}
local ctx=im.CreateContext(nil);local gui=im.GetIO();gui.IniFilename=nil;gui.LogFilename=nil;gui.DeltaTime=1/60
local fonts={};for _,size in ipairs({16,24})do fonts[size]=gui.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeui.ttf',size,nil,gui.Fonts:GetGlyphRangesCyrillic())end
local px,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]');gui.Fonts:GetTexDataAsRGBA32(px,w,h,nil)
local model=require 'pa26_bindings';local core=require 'pa26_core';local Studio=require 'pa26_studio'
local s=Studio.new(im,ffi,model.defaults(core.defaults()),function()return 1000 end)
local knowledge=require 'pa26_knowledge';local k=knowledge.new()
local f=assert(io.open(root..'moonloader/resource/pa26/knowledge-base.json','rb'));local raw=f:read('*a');f:close()
local json=require 'cjson';local decoded=json.decode(raw)
local function stripNull(t)for key,value in pairs(t)do if value==json.null then t[key]=nil elseif type(value)=='table'then stripNull(value)end end end
stripNull(decoded);k:activate(assert(knowledge.validate(decoded)))
local view=require('pa26_knowledge_ui').new(im,ffi,k)
local stack={};local ui={push=function(fn)stack[#stack+1]=fn end,finish=function()assert(table.remove(stack))()end,text=function(text)im.PushTextWrapPos(0);im.TextUnformatted(text);im.PopTextWrapPos()end}
s.currentUi=ui;s.preferenceContext=true
local data={copilot={phase='10-55',car={id=7,distance=10,occupants=2},values={model='Sultan',vehicle_color='чёрный',vehicle_plate='SA-007',unit='1-A-1'},colleagues={}},
 detentionTimers={id=1,target={id=37,name='Longest_Player_Name'},stage='lawyer_response',title='Ответ адвоката',remaining=300,official=true},caseForms={reminders={}}}
local cb={copilotPreview=function(key,cfg)return cfg.templates[key]or cfg[key]or''end,groundHandoff=function()error('No native QA actions')end,detentionAction=function()error('No native QA actions')end,openAssist=function()error('No native QA actions')end}
local checks,frames=0,0;local pageNow='';local detached=false
local function check(v,msg)checks=checks+1;assert(v,msg)end
for _,name in ipairs({'Button','InputText','InputTextMultiline','InputInt','SliderFloat','BeginCombo'})do
 local original=im[name]
 im[name]=function(label,...)
  local result=original(label,...)
  if im.IsItemVisible()then
   local a,b=im.GetItemRectMin(),im.GetItemRectMax();local p,z=im.GetWindowPos(),im.GetWindowSize()
   check(a.x>=p.x-1 and b.x<=p.x+z.x+1,'Horizontal overflow: '..pageNow..' '..label)
   if detached then check(a.y>=p.y and b.y<=p.y+z.y-8,'Detached control clipped: '..pageNow..' '..label)end
  end
  return result
 end
end
local wanted=require 'pa26_wanted_window';local forms=require 'pa26_case_forms';local prefs=s.lib.procedures
local target={id=37,ped=99,name='Longest_Player_Name'}
local state={session='native',ped=1,alive=true,demo=false,focused=true,paused=false,blocked=false,inVehicle=false}
local controller=forms.new({settings=function()return prefs end,target=function()return target,1 end,identity=function()return{}end,validTarget=function()return true end,equal=function()return true end})
controller:tick(state,1000)
local wantedCb={caseValid=function(v)return controller:validForm(v)end}
for _,res in ipairs({{640,480},{800,600},{1024,768},{1152,864},{1366,768},{1920,1080},{2560,1440}})do
 gui.DisplaySize=im.ImVec2(res[1],res[2])
 for _,fraction in ipairs({.7,1})do for _,size in ipairs({16,24})do
  local width=math.min(res[1]-24,math.max(300,math.floor(res[1]*fraction)))
  local height=math.min(res[2]-24,math.max(290,math.floor(res[2]*fraction)))
  for _,page in ipairs({'grounds','rights','settings','knowledge','tracking_phone','tracking_stars'})do
   pageNow=page;detached=page:match('^tracking_')~=nil
   s.copilotPage=page;s.wantedIdentityPage=detached and page or nil;s.caseForm=assert(controller:begin('wanted'));s.caseForm.mode='ooc'
   for frame=1,4 do
    im.NewFrame();im.PushFont(fonts[size]);s.buttonFont=fonts[size];view.buttonFont=fonts[size];view.headingFont=fonts[size]
    im.SetNextWindowPos(im.ImVec2(12,12),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(width,height),im.Cond.Always)
    im.Begin('normative0420-'..page,nil,im.WindowFlags.NoSavedSettings+im.WindowFlags.NoResize+im.WindowFlags.NoMove)
    if detached then wanted.draw(s,ui,data,wantedCb)
    elseif page=='knowledge'then view:draw(ui,{})
    else im.BeginChild('scrolling-settings',im.ImVec2(0,0),false);require('pa26_copilot_ui').draw(s,ui,data,cb);im.EndChild()end
    if detached and frame>=3 then check(im.GetScrollMaxY()<1,'Detached page scroll: '..page..' '..res[1]..'x'..res[2]..' font '..size)end
    check(#stack==0,'Unbalanced scope: '..page);im.End();im.PopFont();im.Render();check(im.GetDrawData().Valid,'Invalid draw data');frames=frames+1
   end
  end
 end end
end
im.DestroyContext(ctx)
local out=assert(io.open(tests..'NORMATIVE0420_NATIVE32_RESULTS.json','wb'))
out:write(string.format('{"status":"passed","checks":%d,"frames":%d,"resolutions":7,"window_fractions":[0.7,1],"fonts":[16,24],"gta_started":false,"game_written":false}\n',checks,frames));out:close()
print('Normative0420 native32: '..checks..' checks; '..frames..' frames; seven resolutions, 70%%/full, 16/24px; no GTA or sends.')

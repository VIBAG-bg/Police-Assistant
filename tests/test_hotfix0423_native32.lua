-- Real installed x86 ImGui and bundled source catalogue; no game writes or sends.
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/');local root=assert(source:match('^(.*[/])'))..'../'
local game=os.getenv('LOCALAPPDATA')..'/Exsellent Launcher/game/'
getWorkingDirectory=function()return game..'MoonLoader'end
package.path=root..'moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path;package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
local ffi=require 'ffi';local im=require 'mimgui.imgui'
for field,prefix in pairs{HoveredFlags='ImGuiHoveredFlags_',Cond='ImGuiCond_',WindowFlags='ImGuiWindowFlags_',Col='ImGuiCol_',StyleVar='ImGuiStyleVar_',MouseCursor='ImGuiMouseCursor_',InputTextFlags='ImGuiInputTextFlags_',DrawCornerFlags='ImDrawCornerFlags_'}do im[field]=setmetatable({},{__index=function(_,key)return im.lib[prefix..key]end})end
im.new={char=setmetatable({},{__index=function(_,n)return ffi.typeof('char['..n..']')end}),int=function(v)return ffi.new('int[1]',v)end,float=function(v)return ffi.new('float[1]',v)end,bool=function(v)return ffi.new('bool[1]',v)end}
local ctx=im.CreateContext(nil);local gui=im.GetIO();gui.IniFilename=nil;gui.LogFilename=nil;gui.DeltaTime=1/60
local fonts={};for _,size in ipairs({16,24})do fonts[size]=gui.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeui.ttf',size,nil,gui.Fonts:GetGlyphRangesCyrillic())end
local px,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]');gui.Fonts:GetTexDataAsRGBA32(px,w,h,nil)

local model=require 'pa26_bindings';local core=require 'pa26_core';local Studio=require 'pa26_studio';local menu=require 'pa26_menu'
local s=Studio.new(im,ffi,model.defaults(core.defaults()),function()return 1000 end)
local stack={};local ui={push=function(f)stack[#stack+1]=f end,finish=function()assert(table.remove(stack))()end,text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
local checks,frames=0,0;local phase='';local backVisible=false;local function check(v,why)checks=checks+1;assert(v,why)end
local original=im.Button
im.Button=function(label,...)
 local result=original(label,...)
 if im.IsItemVisible()then local a,b=im.GetItemRectMin(),im.GetItemRectMax();local p,z=im.GetWindowPos(),im.GetWindowSize()
  check(a.x>=p.x-1 and b.x<=p.x+z.x+1,'Horizontal overflow '..phase..' '..label)
  if label=='Назад · сведения##wanted-back-identity'and a.y>=p.y and b.y<=p.y+z.y-8 then backVisible=true end
  if label=='ОК##status-info-ok'or label:find('##confirm%-yes$')or label:find('##confirm%-no$')then
   check(a.y>=p.y and b.y<=p.y+z.y-8,'Status/confirmation button clipped '..phase..' '..label)
  end
 end;return result
end
local cb={caseValid=function()return true end,caseFillWanted=function()end,caseBranch=function()return'passport'end,
 caseSuggestOoc=function()return false end,casePreview=function()return{ready=true,lines={'/me оформил ориентировку.','/do Данные переданы.','/su 37 1 1'}}end}
for _,screen in ipairs({{640,480},{800,600},{1024,768},{1152,864},{1366,768},{1920,1080},{2560,1440}})do
 for _,size in ipairs({16,24})do
  gui.DisplaySize=im.ImVec2(screen[1],screen[2]);s.buttonFont=fonts[size];s.headingFont=fonts[size]
  for _,length in ipairs({1,6,28})do
   s.statusInfo={key='test',message=string.rep('Проверка состояния: длинная строка без потери кнопки. ',length)}
   for n=1,3 do
    phase='status '..screen[1]..' '..size..' '..length;im.NewFrame();im.PushFont(fonts[size])
    im.SetNextWindowPos(im.ImVec2(0,0),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(screen[1],screen[2]),im.Cond.Always)
    im.PushStyleVarVec2(im.StyleVar.WindowPadding,im.ImVec2(0,0));im.Begin('zero-padding-parent',nil,im.WindowFlags.NoSavedSettings)
    s:drawStatusInfo(ui);check(#stack==0,'Scope balance');im.End();im.PopStyleVar(1);im.PopFont();im.Render();frames=frames+1
   end
  end
  s.statusInfo=nil
  for _,stage in ipairs({'identity','basis','preview'})do
   local f={kind='wanted',id=1,stage=stage,target={id=37,name='Longest_Player_Name'},reason_group='all',reason_id='01.01',mode='ic',
      life_ack=true,passport_seen='yes',mask='no',ic_name='Longest Player Name',passport_number='37',facts=''}
   s.caseForm=f;s.wantedIdentityPage=nil;s.wantedBasisDetails=nil;backVisible=false
   for n=1,4 do
    phase='wanted '..screen[1]..' '..size..' '..stage;im.NewFrame();im.PushFont(fonts[size])
    local b=menu.windowBounds(screen[1],screen[2],'wanted',70)
    im.SetNextWindowPos(im.ImVec2(12,12),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(b.width,b.height),im.Cond.Always)
    im.Begin('wanted-viewport',nil,im.WindowFlags.NoSavedSettings)
    menu.scrollBody(im,ui,'wanted-body',function()require('pa26_wanted_window').draw(s,ui,{},cb);if n==2 then im.SetScrollY(im.GetScrollMaxY())end end,12)
    if stage=='basis'then check(s.wantedMatchedCount==31,'All 31 reasons are searchable');check(s.wantedPerPage>=2 and s.wantedPerPage<=8,'Adaptive page bound')end
    check(#stack==0,'Wanted scope balance');im.End();im.PopFont();im.Render();frames=frames+1
   end
   if stage=='basis'then check(backVisible,'Wanted footer must be reachable at '..screen[1]..' font '..size)end
  end
 end
end
local hud=require('pa26_hud').new(require('pa26_core').widgetDefaults(),{})
hud.connected=true;hud.data={identity='Officer[5]',district='Los Santos',clock='29.10.2026'};hud.mapSquare='J-6'
for _,screen in ipairs({{640,480},{1152,864},{1920,1080}})do
 for _,text in ipairs({'Не задана переменная {unit}: укажите экипаж.',string.rep('Причина: неизвестное поле доклада. ',80)})do
  gui.DisplaySize=im.ImVec2(screen[1],screen[2]);hud.patrol={visible=true,label='Патруль 00:05:00',status='Проверьте настройки доклада ('..text..')',crew='Экипаж: 1 · 1-L-1',progress=.4}
  im.NewFrame();hud:draw(im,fonts[16],fonts[24]);check(hud.bounds~=nil,'Long error must not hide HUD')
  check(hud.bounds.y+hud.bounds.h<=screen[2]+1,'Error HUD exceeds screen');check(#hud.patrolStatusRows>1,'Patrol reason must wrap')
  if #text>1000 then check(hud.patrolStatusRows[12]=='Продолжение — в журнале PA.','Full reason remains available in PA log')end
  im.Render();frames=frames+1
 end
end
s:release();im.DestroyContext(ctx)
local out=assert(io.open(root..'tests/HOTFIX0423_NATIVE32_RESULTS.json','wb'));out:write(string.format('{"status":"passed","checks":%d,"frames":%d,"screens":7,"fonts":[16,24],"game_written":false}\n',checks,frames));out:close()
print('Hotfix 0.42.3 native32: '..checks..' checks; '..frames..' frames; seven resolutions and 16/24px fonts; no game writes.')

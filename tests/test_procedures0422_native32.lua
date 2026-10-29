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
local file=assert(io.open(root..'moonloader/resource/pa26/knowledge-base.json','rb'));local json=require 'cjson';local data=json.decode(file:read('*a'));file:close()
local function strip(t)for k,v in pairs(t)do if v==json.null then t[k]=nil elseif type(v)=='table'then strip(v)end end end;strip(data)
assert(require('pa26_knowledge').validate(data));local catalog=require('pa26_sanctions').new(data)
local s=Studio.new(im,ffi,model.defaults(core.defaults()),function()return 1000 end)
local stack={};local ui={push=function(f)stack[#stack+1]=f end,finish=function()assert(table.remove(stack))()end,text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
local view={caseForms={reminders={}},copilot={values={model='Sultan',vehicle_color='чёрный'}}}
local cb={sanctions=function()return catalog end,caseValid=function()return true end,caseTemplatePreview=function(t)return t end,
 casePreview=function(f)return{ready=true,lines={'/me оформил постановление.','/ticket 37 500 Проверенное основание'}}end,
 save=function()return true end,groundValid=function()return true end,groundPreview=function()return{lines={'/s Причина остановки: запрещающий сигнал.','/s Предъявите документы.'}}end,
 copilotPreview=function(k,cfg)return cfg.templates[k]end,trackingRules=function()return{'6.13. Снять технические звёзды сразу после пеленгации.'}end}
local checks,frames=0,0;local page=''
local function check(v,why)checks=checks+1;assert(v,why)end
local children={};local beginChild,endChild=im.BeginChild,im.EndChild
im.BeginChild=function(name,...)
 children[#children+1]=tostring(name):find('text-viewport##',1,true)~=nil
 return beginChild(name,...)
end
im.EndChild=function(...)
 local editor=table.remove(children);local result=endChild(...)
 if editor and im.IsItemVisible()then
  local a,b=im.GetItemRectMin(),im.GetItemRectMax();local p,z=im.GetWindowPos(),im.GetWindowSize()
  check(a.x>=p.x-1 and b.x<=p.x+z.x+1,'Visible text viewport exceeds parent')
 end
 return result
end
for _,key in ipairs({'Button','Checkbox','InputText','InputTextMultiline','InputInt','BeginCombo'})do local original=im[key]
 im[key]=function(label,...)
  local result=original(label,...)
  if im.IsItemVisible()and not(key=='InputTextMultiline'and children[#children])then local a,b=im.GetItemRectMin(),im.GetItemRectMax();local p,z=im.GetWindowPos(),im.GetWindowSize()
   check(a.x>=p.x-1 and b.x<=p.x+z.x+1,string.format('Horizontal overflow: %s %s rect %.1f..%.1f parent %.1f..%.1f screen %.0f',page,label,a.x,b.x,p.x,p.x+z.x,gui.DisplaySize.x))
  end;return result
 end
end
for _,resolution in ipairs({{640,480},{800,600},{1024,768},{1152,864},{1366,768},{1920,1080},{2560,1440}})do
 for _,font in ipairs({16,24})do
  for _,spec in ipairs({{'fine','identity'},{'fine','basis'},{'fine','preview'},{'fine','catalog'},{'fine','settings'},
   {'mark','identity'},{'mark','basis'},{'mark','preview'},{'mark','rules'},{'mark','settings'},{'ground','form'},{'ground','settings'}})do
   gui.DisplaySize=im.ImVec2(resolution[1],resolution[2]);page=spec[1]..':'..spec[2]..':'..font
   local key=spec[1];local bounds=assert(menu.windowBounds(resolution[1],resolution[2],key,70));check(bounds.width<=resolution[1]);check(bounds.height<=resolution[2])
   local f={id=1,kind=key,stage=spec[2],target={id=37,name='Longest_Driver_Name'},passport_seen='yes',ic_name='Longest Driver Name',mask='no',
    amount='500',basis='Проверенное основание',phone_number='555123',phone_source='Данные КПК',phone_known='yes',phone_active='yes',prior_ic_stars='no',reason_id='08.01',life_ack=true,ooc_ack=true}
   if key=='fine'then require('pa26_sanctions').select(f,catalog.byId['AK:41'],1)end
   s.caseForm=f;s[key..'Page']=(spec[2]=='catalog'or spec[2]=='settings'or spec[2]=='rules')and spec[2]or'form'
   s.groundForm={request={kind='stop',groundTarget={id=37,name='Longest_Driver_Name'},groundCar={id=7}},cfg=model.copy(s.lib.vehicle.copilot)}
   s.groundForm.cfg.stop_ground='signal';s.groundForm.cfg.stop_branch='first'
   im.NewFrame();im.PushFont(fonts[font]);im.SetNextWindowPos(im.ImVec2(12,12),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(bounds.width,bounds.height),im.Cond.Always)
   im.Begin('PA 0.42.2 QA',nil,im.WindowFlags.NoSavedSettings)
   s.currentUi=ui;menu.scrollBody(im,ui,'body##'..key,function()require('pa26_'..key..'_window').draw(s,ui,view,cb)end)
   check(#stack==0,'Balanced UI scopes');im.End();im.PopFont();im.Render();check(im.GetDrawData().Valid,'Valid native draw data');frames=frames+1
  end
 end
end
im.DestroyContext(ctx);print('Procedures native32: '..checks..' checks; '..frames..' frames; seven screen sizes and 16/24px fonts; no game writes.')

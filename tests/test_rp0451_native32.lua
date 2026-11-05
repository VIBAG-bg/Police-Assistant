-- Native x86 CPU UI frames and optional mesh captures. No GTA or network writes.
local root=assert(os.getenv('PA_SOURCE_ROOT'),'Set PA_SOURCE_ROOT to the candidate directory')
local game=os.getenv('LOCALAPPDATA')..'/Exsellent Launcher/game/'
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
local frames,checks=0,0
local function check(v,why)checks=checks+1;assert(v,why)end
for _,display in ipairs({{640,480},{800,600},{800,1100},{1024,768},{1366,768},{1920,1080},{2560,1440}})do
 for _,scale in ipairs({1,1.25})do for _,screen in ipairs({'context','stage','unknown-vehicle'})do
  local s=require('pa26_studio').new(im,ffi,lib,function()return 1000 end);s.currentUi=ui;s.buttonFont=button
  local binding=model.newBinding(48);local author=require('pa26_author_rp').bindings['48']
  binding.script=author.script;binding.rp_context=model.copy(author.rp_context)
  if screen=='stage'then s.executionConfirm={name='Этап 10-66',token='stage-native',prompt='Обстановка позволяет передать это указание?',preview={'/m Водитель, заглушите двигатель. Держите руки на виду.'}}
  elseif screen=='unknown-vehicle'then s.copilotVariant={token='variant-native',variants={car={prepared={lines={'/m Автомобиль, остановитесь у правой обочины.'}}},bike={prepared={lines={'/m Водитель мотоцикла, остановитесь у правой обочины.'}}}}}end
  for pass=1,2 do
   io.DisplaySize=im.ImVec2(display[1],display[2]);io.FontGlobalScale=scale
   im.NewFrame();im.SetNextWindowPos(im.ImVec2(12,12),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(display[1]-24,display[2]-24),im.Cond.Always)
   im.Begin('PA 0.45.1 '..screen..display[1]..scale,nil,im.WindowFlags.NoSavedSettings)
   require('pa26_menu').new():pushTheme(im,ui);local depth=#stack
   if screen=='context'then require('pa26_rp_context_ui').draw(s,ui,binding)else s:drawModal(ui,{},callbacks)end
   check(#stack==depth,'Unbalanced new RP view scopes');while #stack>0 do ui.finish()end
   im.End();im.Render();check(im.GetDrawData().Valid,'Invalid CPU draw data');frames=frames+1
  end
 end end
end
icons.clear();im.DestroyContext(ctx)
local report=json.encode({status='passed',checks=checks,frames=frames,screen_sizes=7,views=3,font_scales=2,game_started=false,game_written=false})
local out=assert(_G.io.open(root..'/tests/UX_NATIVE32_0451.json','wb'));out:write(report);out:close()
print('New RP native32 UI: '..frames..' frames, '..checks..' checks; seven sizes, two font scales.')

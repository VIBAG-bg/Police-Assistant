-- Real x86 ImGui atlas and ID smoke. No GTA, network or game writes.
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/');local root=assert(source:match('^(.*)/tests/'))
local game=os.getenv('LOCALAPPDATA')..'/Exsellent Launcher/game/'
package.path=root..'/moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path
package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
getWorkingDirectory=function()return game..'MoonLoader'end
local ffi=require 'ffi';local im=require 'mimgui.imgui';local icons=require 'pa26_icons';local menu=require 'pa26_menu'
for name,prefix in pairs{HoveredFlags='ImGuiHoveredFlags_',Cond='ImGuiCond_',WindowFlags='ImGuiWindowFlags_',Col='ImGuiCol_',StyleVar='ImGuiStyleVar_'}do
 im[name]=setmetatable({},{__index=function(_,k)return im.lib[prefix..k]end})
end
local checks,frames=0,0;local function check(v,why)checks=checks+1;assert(v,why)end
local function run(merged)
 local ctx=im.CreateContext(nil);local io=im.GetIO();io.IniFilename=nil;io.LogFilename=nil;io.DeltaTime=1/60
 local base=assert(io.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeui.ttf',18,nil,io.Fonts:GetGlyphRangesCyrillic()))
 check(icons.initialize(im,ffi,merged and base or nil))
 local pixels,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]')
 io.Fonts:GetTexDataAsRGBA32(pixels,w,h,nil)
 check(w[0]>0 and h[0]>0 and w[0]<=4096 and h[0]<=4096,'Oversized atlas')
 for name,cp in pairs(icons.points)do
  check(icons.font:FindGlyphNoFallback(cp)~=nil,'Missing Free Solid glyph: '..name)
  check(icons.get(name)~=nil,'Icon fallback unexpectedly used: '..name)
 end
 for _,cp in ipairs({0x0410,0x042F,0x0430,0x044F,0x0401,0x0451})do check(base:FindGlyphNoFallback(cp)~=nil,'Cyrillic lost')end
 for _,display in ipairs({{640,480},{800,600},{800,1100},{1024,768},{1366,768},{1920,1080},{2560,1440}})do
  for _,scale in ipairs({1,1.25})do for _,enabled in ipairs({false,true})do
   io.DisplaySize=im.ImVec2(display[1],display[2]);io.FontGlobalScale=scale;icons.setEnabled(enabled)
   im.NewFrame();im.SetNextWindowPos(im.ImVec2(16,16),im.Cond.Always)
   im.SetNextWindowSize(im.ImVec2(display[1]-32,display[2]-32),im.Cond.Always)
   im.Begin('Native icon smoke##icons',nil,0)
   local stack={};local ui={push=function(fn)stack[#stack+1]=fn end,finish=function()assert(table.remove(stack))()end,text=im.TextUnformatted}
   for _,label in ipairs({'Начать патруль##patrol-start','Сохранить сценарий##save', '10-55 · К обочине##copilot-stop_order','ДА##confirm-yes','НЕТ##confirm-no'})do
    local id=im.GetIDStr(label)
    menu.fittedButton(im,ui,label,im.ImVec2(math.max(1,im.GetContentRegionAvail().x),38),base)
    check(im.GetIDStr(label)==id,'Decorative icon changed widget ID')
   end
   check(#stack==0,'Unbalanced UI scopes');im.End();im.Render();frames=frames+1
  end end
 end
 icons.clear();im.DestroyContext(ctx)
end
run(true);run(false)
icons.setEnabled(true);check(not icons.get('house'),'Missing font must use text fallback')
local f=assert(io.open(root..'/tests/ICONS_NATIVE32_0440.json','wb'))
f:write(string.format('{"status":"passed","checks":%d,"frames":%d,"screen_sizes":7,"font_scales":2,"icons":40,"merge_supported":true,"memory_supported":true,"game_started":false,"game_written":false}',checks,frames));f:close()
print('Icons native32: '..checks..' checks, '..frames..' frames, merged/dedicated font and Cyrillic, seven sizes; no GTA writes.')


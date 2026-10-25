-- Real installed ImGui + the actual Studio:field implementation, CPU only.
-- No GTA process, native desktop window, network, or game input is involved.
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/')
local tests=assert(source:match('^(.*[/])'));local release=tests..'../'
local game=assert(os.getenv('LOCALAPPDATA'), 'LOCALAPPDATA required')..'/Exsellent Launcher/game/'
getWorkingDirectory=function()return game..'MoonLoader'end
package.path=release..'moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path
package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
local ffi=require'ffi';local im=require'mimgui.imgui';local menu=require'pa26_menu'
for field,prefix in pairs{HoveredFlags='ImGuiHoveredFlags_',Cond='ImGuiCond_',WindowFlags='ImGuiWindowFlags_',Col='ImGuiCol_',
    StyleVar='ImGuiStyleVar_',MouseCursor='ImGuiMouseCursor_',InputTextFlags='ImGuiInputTextFlags_'}do
    im[field]=setmetatable({},{__index=function(_,key)return im.lib[prefix..key]end})
end
im.new={char=setmetatable({},{__index=function(_,count)return ffi.typeof('char['..count..']')end})}
local context=im.CreateContext(nil);local guiIo=im.GetIO()
guiIo.DisplaySize=im.ImVec2(1280,720);guiIo.DeltaTime=1/60;guiIo.IniFilename=nil;guiIo.LogFilename=nil
guiIo.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeui.ttf',16,nil,guiIo.Fonts:GetGlyphRangesCyrillic())
local pixels,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]')
guiIo.Fonts:GetTexDataAsRGBA32(pixels,w,h,nil)


local model=require'pa26_bindings';local Studio=require'pa26_studio';local KB=require'pa26_knowledge_ui'
guiIo.DisplaySize=im.ImVec2(1920,1080)
local checks=0;local function check(v,why)checks=checks+1;assert(v,why)end
local function scope()
    local stack={}
    return {push=function(fn)stack[#stack+1]=fn end,finish=function()assert(table.remove(stack))()end,
        text=function(text)im.PushTextWrapPos(0);im.TextUnformatted(text);im.PopTextWrapPos()end},stack
end
local originalInfo,originalModal=im.BeginPopup,im.BeginPopupModal
local popup,frame
local function observed(shown)
    if shown then
        local p,s=im.GetWindowPos(),im.GetWindowSize();popup={x=p.x,y=p.y,w=s.x,h=s.y}
        if frame==8 then im.CloseCurrentPopup()end
    end
    return shown
end
im.BeginPopup=function(...)return observed(originalInfo(...))end
im.BeginPopupModal=function(...)return observed(originalModal(...))end
local editor=Studio.new(im,ffi,model.defaults(require'pa26_core'.defaults()))
local knowledge=KB.new(im,ffi,{})
for _,kind in ipairs({'info','knowledge'})do
    guiIo.DisplaySize=im.ImVec2(1920,1080)
    local start,point;popup=nil
    if kind=='info'then editor.infoBinding=1;editor.infoPending=true
    else knowledge.confirm={kind='update',version='Local-only test'}end
    for n=1,8 do
        if n==8 then guiIo.DisplaySize=im.ImVec2(640,480)end
        frame=n;guiIo.MouseDown[0]=false;guiIo.MouseDown[1]=n>=3 and n<=6
        guiIo.MousePos=point and im.ImVec2(point.x+(n>=4 and 90 or 0),point.y+(n>=4 and 45 or 0))or im.ImVec2(0,0)
        im.NewFrame();im.Begin('extra-popup-host',nil,im.WindowFlags.NoSavedSettings)
        local ui,stack=scope()
        if kind=='info'then editor:drawBindingInfo(ui,{demo=true},{})else knowledge:drawModal(ui)end
        if n==2 then assert(popup);start=popup;point={x=popup.x+55,y=popup.y+65}end
        if n==7 then
            check(math.abs(popup.x-(start.x+90))<1 and math.abs(popup.y-(start.y+45))<1,kind..' popup did not move with RMB')
            check(popup.x>=0 and popup.y>=0 and popup.x+popup.w<=1920 and popup.y+popup.h<=1080,'Popup escaped the display')
        end
        if n==8 then check(popup.w<=608 and popup.h<=448 and popup.x+popup.w<=625 and popup.y+popup.h<=465,'Popup did not fit after changing resolution')end
        check(#stack==0,'Unbalanced popup scope');im.End();im.Render()
    end
end
check(knowledge.knowledge.action==nil,'Right drag applied a knowledge update')
im.BeginPopup=originalInfo;im.BeginPopupModal=originalModal;editor:release();im.DestroyContext(context)
local out=assert(io.open(release..'tests/EXTRA_POPUPS_NATIVE32_RESULTS.json','wb'))
out:write(require'cjson'.encode({status='passed',checks=checks,real_installed_imgui=true,cpu_only=true,
    binding_info_right_drag=true,knowledge_confirmation_right_drag=true,gta_launched=false,game_server_contacted=false}));out:close()
print('Native extra popups: '..checks..' checks passed.')

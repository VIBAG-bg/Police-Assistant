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

local model=require'pa26_bindings';local Studio=require'pa26_studio'
local checks=0
local function check(v,why)checks=checks+1;assert(v,why)end
local function scope()
    local stack={}
    return {push=function(fn)stack[#stack+1]=fn end,finish=function()assert(table.remove(stack))()end,
        text=function(text)im.PushTextWrapPos(0);im.TextUnformatted(text);im.PopTextWrapPos()end},stack
end
for _,display in ipairs({{640,480},{1366,768},{1920,1080},{2560,1440}})do
    guiIo.DisplaySize=im.ImVec2(display[1],display[2])
    for _,key in ipairs({'main','quick','tips','assist'})do
        local m=menu.new();local start,point;local beforeItem,afterItem;local activated=0
        for frame=1,8 do
            guiIo.MouseDown[0]=false;guiIo.MouseDown[1]=frame>=3 and frame<=6
            if point then guiIo.MousePos=im.ImVec2(point.x+(frame>=4 and 90 or 0),point.y+(frame>=4 and 45 or 0))
            else guiIo.MousePos=im.ImVec2(0,0)end
            im.NewFrame();assert(m:prepareWindow(im,key))
            im.Begin('native-'..key..'-'..display[1],nil,im.WindowFlags.NoSavedSettings+im.WindowFlags.NoMove+im.WindowFlags.NoResize+im.WindowFlags.NoTitleBar)
            local ui,stack=scope();local p,s=im.GetWindowPos(),im.GetWindowSize()
            if frame==1 then start={x=p.x,y=p.y};point={x=p.x+80,y=p.y+90}end
            m:resizeWindow(im,ui,key)
            im.BeginChild('child',im.ImVec2(0,math.min(160,s.y-30)),true)
            if im.Button('Right click must not press this button',im.ImVec2(180,110))then activated=activated+1 end
            local item=im.GetItemRectMin()
            if frame==2 then beforeItem={x=item.x-p.x,y=item.y-p.y}end
            if frame==7 then afterItem={x=item.x-p.x,y=item.y-p.y}end
            im.EndChild()
            if frame==7 then
                local expectedX=math.min(start.x+90,display[1]-s.x-16)
                local expectedY=math.min(start.y+45,display[2]-s.y-16)
                check(math.abs(p.x-expectedX)<1 and math.abs(p.y-expectedY)<1,'RMB from inside a child must move the parent before Begin: '..key)
                check(p.x>=16 and p.y>=16 and p.x+s.x<=display[1]-15 and p.y+s.y<=display[2]-15,'Moved window escapes its screen')
            end
            check(#stack==0,'Native scope imbalance');im.End();im.Render()
        end
        check(activated==0,'RMB activated a left-click control')
        check(math.abs(beforeItem.x-afterItem.x)<1 and math.abs(beforeItem.y-afterItem.y)<1,'Content and clipping geometry did not move with the window')
    end
end
guiIo.DisplaySize=im.ImVec2(1920,1080);guiIo.MouseDown[1]=false
local editor=Studio.new(im,ffi,model.defaults(require'pa26_core'.defaults()))
editor:select(1);editor.draft.script='Изменённый текст.';editor.dirty=true
local actions=0;editor:requestNavigation(function()actions=actions+1 end,'закрыть PA')
local popup,start,point;local original=im.BeginPopupModal
im.BeginPopupModal=function(...)
    local shown=original(...)
    if shown then local p,s=im.GetWindowPos(),im.GetWindowSize();popup={x=p.x,y=p.y,w=s.x,h=s.y}end
    return shown
end
for frame=1,8 do
    guiIo.MouseDown[0]=false;guiIo.MouseDown[1]=frame>=3 and frame<=6
    if point then guiIo.MousePos=im.ImVec2(point.x+(frame>=4 and 110 or 0),point.y+(frame>=4 and 60 or 0))else guiIo.MousePos=im.ImVec2(0,0)end
    im.NewFrame();im.SetNextWindowPos(im.ImVec2(0,0),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(1,1),im.Cond.Always)
    im.Begin('modal-host',nil,im.WindowFlags.NoSavedSettings+im.WindowFlags.NoInputs)
    local ui,stack=scope();editor:drawModal(ui,{}, {cancelCapture=function()end,save=function()actions=actions+1;return true end})
    if frame==2 then assert(popup);start=popup;point={x=popup.x+50,y=popup.y+65}end
    if frame==7 then
        check(math.abs(popup.x-(start.x+110))<1 and math.abs(popup.y-(start.y+60))<1,'YES/NO/save popup did not retain its RMB position')
        check(actions==0 and editor.dirty and editor.pendingNavigation,'Dragging must not save, discard or resolve a confirmation')
    end
    check(#stack==0,'Popup scope imbalance');im.End();im.Render()
end
im.BeginPopupModal=original;editor:release();im.DestroyContext(context)
local out=assert(io.open(release..'tests/WINDOW_NATIVE32_RESULTS.json','wb'))
out:write(require'cjson'.encode({status='passed',checks=checks,real_installed_imgui=true,cpu_only=true,
    screen_sizes={ {640,480},{1366,768},{1920,1080},{2560,1440} },right_drag_children=true,right_drag_modal=true,
    native_game_tested=false,gta_launched=false,game_server_contacted=false}));out:close()
print('Native window layout and RMB dragging: '..checks..' checks passed.')

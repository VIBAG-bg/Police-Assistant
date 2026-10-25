-- CPU-only test of the installed Dear ImGui DLL. No GTA, window or DX renderer.
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/')
local tests=assert(source:match('^(.*[/])'))
local release=tests..'../'
local game=assert(os.getenv('LOCALAPPDATA'), 'LOCALAPPDATA required')..'/Exsellent Launcher/game/'
getWorkingDirectory=function()return game..'MoonLoader'end
package.path=release..'moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path
package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
local ffi=require'ffi';local im=require'mimgui.imgui';local menu=require'pa26_menu'
-- Mirror only init.lua's enum aliases; never load its GTA/DX initialization.
for field,prefix in pairs{Cond='ImGuiCond_',WindowFlags='ImGuiWindowFlags_',Col='ImGuiCol_',
    StyleVar='ImGuiStyleVar_',MouseCursor='ImGuiMouseCursor_'}do
    im[field]=setmetatable({},{__index=function(_,key)return im.lib[prefix..key]end})
end
local context=im.CreateContext(nil);local guiIo=im.GetIO()
guiIo.DisplaySize=im.ImVec2(1280,720);guiIo.DeltaTime=1/60;guiIo.IniFilename=nil;guiIo.LogFilename=nil
guiIo.Fonts:AddFontDefault(nil)
local pixels,width,height=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]')
guiIo.Fonts:GetTexDataAsRGBA32(pixels,width,height,nil)
local checks=0;local function check(v,why)checks=checks+1;assert(v,why)end
local function ui()
    local stack={}
    return{push=function(fn)stack[#stack+1]=fn end,finish=function()local fn=table.remove(stack);assert(fn);fn()end,
        text=function(text)im.TextUnformatted(text)end},stack
end
local function run(fixed,rows,frames)
    local owner=menu.new();local history={};local name=fixed and'fixed-scroll' or'legacy-scroll'
    for frame=1,frames do
        guiIo.MousePos=im.ImVec2(150,150);guiIo.MouseWheel=-3
        im.NewFrame();im.SetNextWindowPos(im.ImVec2(40,40),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(500,420),im.Cond.Always)
        local flags=im.WindowFlags.NoSavedSettings+im.WindowFlags.NoResize+im.WindowFlags.NoMove
        if fixed then flags=flags+im.WindowFlags.NoScrollbar+im.WindowFlags.NoScrollWithMouse end
        im.Begin(name,nil,flags)
        local scope,stack=ui();owner:resizeWindow(im,scope,'quick')
        local maximum,position
        local function body()
            for n=1,rows do im.TextUnformatted('Content row '..n)end
            maximum,position=im.GetScrollMaxY(),im.GetScrollY()
            im.SetScrollY(100000)
        end
        if fixed then menu.scrollBody(im,scope,'body##'..name,body)else body()end
        local rootPosition=im.GetScrollY()
        im.End();im.Render();check(#stack==0,'unbalanced scope')
        history[#history+1]={maximum=maximum,position=position,rootPosition=rootPosition}
    end
    return history
end
local legacy=run(false,3,20)
local short=run(true,3,20)
local long=run(true,100,20)
check(legacy[20].maximum>legacy[5].maximum,'legacy resize chrome must reproduce the growing blank scroll range')
check(short[20].maximum==0,'short content cannot scroll into blank space')
check(long[20].maximum>0,'long content keeps its scrollbar')
for n=6,20 do
    check(short[n].position==0 and short[n].rootPosition==0,'short body or chrome scrolled')
    check(long[n].maximum==long[6].maximum,'long content range grows beyond its end')
    check(long[n].position<=long[n].maximum,'long body scrolled past content')
    check(long[n].rootPosition==0,'root chrome moved with the body')
end
local json=require'cjson'
local report={status='passed',checks=checks,imgui_version=ffi.string(im.GetVersion()),
    real_installed_imgui=true,cpu_only=true,gta_launched=false,game_server_contacted=false,
    legacy_max_early=legacy[5].maximum,legacy_max_late=legacy[20].maximum,
    fixed_short_max=short[20].maximum,fixed_long_max=long[20].maximum}
im.DestroyContext(context)
local file=assert(io.open(release..'tests/SCROLL_NATIVE32_RESULTS.json','wb'));file:write(json.encode(report));file:close()
print('Real Dear ImGui scroll: '..checks..' checks passed; old blank scrolling reproduced, fixed ranges bounded.')

-- Real installed 32-bit LuaJIT/ImGui; CPU-only frames, never a GTA process.
local src=debug.getinfo(1,'S').source:sub(2):gsub('\\','/')
local tests=assert(src:match('^(.*[/])'));local release=tests..'../'
local game=assert(os.getenv('LOCALAPPDATA'), 'LOCALAPPDATA required')..'/Exsellent Launcher/game/'
getWorkingDirectory=function()return game..'MoonLoader'end
package.path=release..'moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path
package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
local ffi=require 'ffi';local im=require 'mimgui.imgui'
for field,prefix in pairs{HoveredFlags='ImGuiHoveredFlags_',Cond='ImGuiCond_',WindowFlags='ImGuiWindowFlags_',Col='ImGuiCol_',
    StyleVar='ImGuiStyleVar_',MouseCursor='ImGuiMouseCursor_',InputTextFlags='ImGuiInputTextFlags_',DrawCornerFlags='ImDrawCornerFlags_'}do
    im[field]=setmetatable({},{__index=function(_,key)return im.lib[prefix..key]end})
end
im.new={char=setmetatable({},{__index=function(_,n)return ffi.typeof('char['..n..']')end}),
    int=function(v)return ffi.new('int[1]',v)end,float=function(v)return ffi.new('float[1]',v)end,bool=function(v)return ffi.new('bool[1]',v)end}
local ctx=im.CreateContext(nil);local guiIo=im.GetIO();guiIo.IniFilename=nil;guiIo.LogFilename=nil;guiIo.DeltaTime=1/60
guiIo.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeui.ttf',16,nil,guiIo.Fonts:GetGlyphRangesCyrillic())
local pixels,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]');guiIo.Fonts:GetTexDataAsRGBA32(pixels,w,h,nil)
local model=require 'pa26_bindings';local grid=require 'pa26_map_grid';local Studio=require 'pa26_studio';local adapter=require 'pa26_map_adapter'
local hud=require('pa26_hud').new(require('pa26_core').widgetDefaults(),{})
hud.connected=true;hud.data={identity='Victor_Auditore[14] | Ping: 42',district='Whitewood Estates',clock='22.10.2026 22:30'};hud.mapSquare='H-18'
hud.patrol={visible=true,label='Патруль № 1',status='До доклада: 03:12',crew='Victor Auditore, Officer Test',progress=.4}
local n=0;local function check(v,message)n=n+1;assert(v,message)end
local native=adapter.new(ffi)
check(not native:safeView({connected=true,focused=true,interior=0,x=0,y=0,paused=false},800,600,grid.defaults()),'The test host must never call game functions')
check(native.status=='process'or native.status=='image','Actual 32-bit Windows capability detection failed: '..native.status)
check(not native.reader.worldFn,'A non-GTA host bound a game function')
local editor=Studio.new(im,ffi,model.defaults(require('pa26_core').defaults()),function()return 1000 end)
local stack={};local ui={push=function(fn)stack[#stack+1]=fn end,finish=function()assert(table.remove(stack))()end,
    text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
local data={mapState={x=0,y=0,interior=0,area='Doherty'},mapAdapterStatus='Тест проекции без запуска GTA.',queued=nil}
local maxX=0
local function instrument(name)
    local original=im[name]
    im[name]=function(label,...)
        local result=original(label,...)
        if label:find('##map-',1,true)and im.IsItemVisible()then
            local item=im.GetItemRectMax();local pos=im.GetWindowPos();local width=im.GetWindowSize().x
            check(item.x<=pos.x+width-7,'Map control exceeds window width: '..label)
            maxX=math.max(maxX,item.x-pos.x)
        end
        return result
    end
end
for _,name in ipairs({'Checkbox','InputInt','SliderInt','SliderFloat','InputText','InputTextMultiline'})do instrument(name)end
local frames=0;local lastMax=0
for _,display in ipairs({{640,480},{1366,768},{1920,1080},{2560,1440}})do
    guiIo.DisplaySize=im.ImVec2(display[1],display[2])
    for _,width in ipairs({300,500,math.min(display[1]-32,1100)})do
        for frame=1,12 do
            im.NewFrame();im.SetNextWindowPos(im.ImVec2(16,16),im.Cond.Always)
            im.SetNextWindowSize(im.ImVec2(width,display[2]-32),im.Cond.Always)
            im.Begin('map-settings-native',nil,im.WindowFlags.NoSavedSettings+im.WindowFlags.NoResize+im.WindowFlags.NoMove)
            editor:draw('map',ui,data,{})
            check(#stack==0,'Map settings leaked an ImGui scope')
            if frame>=3 then check(im.GetScrollY()<=im.GetScrollMaxY()+1,'Map settings overscroll below content')end
            if frame%2==0 then lastMax=im.GetScrollMaxY();im.SetScrollY(lastMax*math.min(1,frame/10))end
            im.End()
            local view={kind='radar',a=.15,b=.08,c=.08,d=-.15,ox=100,oy=display[2]-90,
                left=20,top=display[2]-160,right=180,bottom=display[2]-20,
                ellipse={cx=100,cy=display[2]-90,rx=80,ry=70}}
            local lines,labels=grid.draw(im,im.GetFont(),grid.defaults(),view,grid.cell(grid.defaults(),0,0,0))
            check(lines>0 and labels>=0,'No native radar geometry produced')
            local rect=hud:layout(display[1],display[2]);check(rect and rect.x+rect.w<=display[1]and rect.y+rect.h<=display[2],'HUD with a square/crew exceeds the display')
            hud:draw(im,im.GetFont(),im.GetFont())
            im.Render();local dd=im.GetDrawData();check(dd~=nil and dd.Valid and dd.TotalVtxCount>0,'Native ImGui produced no render data')
            frames=frames+1
        end
    end
end
editor:release();im.DestroyContext(ctx)
local file=assert(io.open(tests..'MAP_NATIVE32_RESULTS.json','wb'))
file:write(string.format('{"status":"passed","checks":%d,"frames":%d,"resolutions":4,"min_window_width":300,"max_control_x":%.2f,"last_scroll_max":%.2f,"gta_started":false,"game_functions_bound":false,"renderer":"installed 32-bit ImGui, CPU only"}\n',n,frames,maxX,lastMax))
file:close();print('Map native32: '..n..' checks; '..frames..' frames passed; no GTA.')

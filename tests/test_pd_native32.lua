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

local model=require 'pa26_bindings';local core=require 'pa26_core';local Studio=require 'pa26_studio';local nearby=require 'pa26_nearby';local vehicleUi=require 'pa26_vehicle_ui'
local editor=Studio.new(im,ffi,model.defaults(core.defaults()),function()return 1000 end)
local n,frames=0,0;local seenControls={};local testWidth=0;local function check(v,message)n=n+1;assert(v,message)end
local stack={};local ui={push=function(fn)stack[#stack+1]=fn end,finish=function()assert(table.remove(stack))()end,
    text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
local data={nearby={enabled=true,rows={},revision=1},vehicle={},radioState={area='Doherty',map_square='M-4',map_grid=editor.lib.map_grid}}
for i=1,16 do data.nearby.rows[i]={id=900+i,ped=100+i,name='Longest_Player_Name_Long',distance=i,generation=0}end
local callbacks={selectNearby=function()error('Native UI test cannot select or send')end,vehiclePreview=function()return nil,'Выберите машину для предпросмотра.'end}
for _,name in ipairs({'Checkbox','InputInt','SliderInt','SliderFloat','InputText','InputTextMultiline','Button'})do
    local original=im[name]
    im[name]=function(label,...)
        local result=original(label,...)
        if (label:find('##nearby',1,true)or label:find('##vehicle',1,true))and im.IsItemVisible()then
            local edge=im.GetItemRectMax();local pos=im.GetWindowPos();local width=im.GetWindowSize().x
            if name=='InputTextMultiline'then
                -- Check the scrolling editor viewport, not its logical text width.
                check(pos.x>=22 and pos.x+width<=16+testWidth-6,'Text viewport exceeds parent: '..label)
            else check(edge.x<=pos.x+width-6,'Control exceeds its window: '..label)end
            seenControls[tostring(testWidth)..':'..label]=true
        end
        return result
    end
end
local originalTitle=editor.rowTitle
editor.rowTitle=function(self,ui,label,selected,width,height)
    local font=self.buttonFont or im.GetFont();local lay=require('pa26_menu').labelLayout(font,tonumber(font.FontSize),width-28,label:match('^(.-)##'))
    check(lay.height+16<=height,'Nearby title exceeds its card height')
    local identity=label:match('###(.*)')
    check(identity and im.GetIDStr(label)==im.GetIDStr('Distance updated###'..identity),'Distance text changed the native button ID')
    return originalTitle(self,ui,label,selected,width,height)
end
for _,display in ipairs({{640,480},{1366,768},{1920,1080},{2560,1440}})do
    guiIo.DisplaySize=im.ImVec2(display[1],display[2])
    for _,width in ipairs({300,500,math.min(display[1]-32,1100)})do
        testWidth=width
        for _,page in ipairs({'people','settings','vehicle'})do
            local bottomFrames=0
            for frame=1,100 do
                im.NewFrame();im.SetNextWindowPos(im.ImVec2(16,16),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(width,display[2]-32),im.Cond.Always)
                im.Begin('pd-native-'..page,nil,im.WindowFlags.NoSavedSettings+im.WindowFlags.NoResize+im.WindowFlags.NoMove)
                if frame==1 then im.SetScrollY(0)end
                editor.currentUi=ui;editor.preferenceContext=true
                if page=='people'then nearby.draw(editor,ui,data,callbacks)
                elseif page=='settings'then nearby.settings(editor,ui)
                else vehicleUi.draw(editor,ui,data,callbacks)end
                check(#stack==0,'Leaked scope: '..page)
                if frame>=3 then check(im.GetScrollY()<=im.GetScrollMaxY()+1,'Scroll passed end: '..page)end
                local atBottom=frame>=3 and im.GetScrollY()>=im.GetScrollMaxY()-1
                bottomFrames=atBottom and bottomFrames+1 or 0
                if frame>=2 then im.SetScrollY(math.min(im.GetScrollMaxY(),im.GetScrollY()+math.max(100,(display[2]-32)*.55)))end
                im.End();im.Render();local dd=im.GetDrawData();check(dd~=nil and dd.Valid and dd.TotalVtxCount>0,'No draw data: '..page);frames=frames+1
                if bottomFrames>=2 then break end
            end
        end
    end
end
for _,label in ipairs({'##vehicle-cone_angle','##vehicle-height_tolerance','##nearby-distance','##nearby-max_people','##nearby-interval_ms'})do
    check(seenControls['300:'..label],'Required new control was never visible at 300px: '..label)
end
editor:release();im.DestroyContext(ctx)
local out=assert(io.open(tests..'PD_NATIVE32_RESULTS.json','wb'))
out:write(string.format('{"status":"passed","checks":%d,"frames":%d,"resolutions":4,"min_window_width":300,"gta_started":false,"server_contacted":false,"renderer":"installed 32-bit ImGui, CPU only"}\n',n,frames))
out:close();print('PD native32: '..n..' checks; '..frames..' frames passed; no GTA.')

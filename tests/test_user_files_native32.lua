-- Installed 32-bit ImGui, CPU-only. This does not start GTA or write game files.
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
local model=require 'pa26_bindings';local core=require 'pa26_core';local Studio=require 'pa26_studio'
local editor=Studio.new(im,ffi,model.defaults(core.defaults()),function()return 1000 end)
local checks,frames=0,0;local function check(ok,message)checks=checks+1;assert(ok,message)end
local stack={};local ui={push=function(fn)stack[#stack+1]=fn end,finish=function()assert(table.remove(stack))()end,
    text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
local data={demo=true};local callbacks=setmetatable({},{__index=function()return function()error('Native UI test must not execute actions')end end})
local wanted={['Экспорт всех биндов']=true,['Импорт биндов']=true,['Экспорт выбранного бинда']=true,['Файлы обмена##bind-files']=true,
    ['Экспорт всех заметок##notes-export']=true,['Импорт заметок##notes-import']=true,['Экспорт выбранной заметки##notes-export-one']=true}
local seen={};local widthNow
local originalButton=im.Button
im.Button=function(label,...)
    local result=originalButton(label,...)
    if wanted[label]then
        local pos,size=im.GetWindowPos(),im.GetWindowSize();local lo,hi=im.GetItemRectMin(),im.GetItemRectMax()
        check(lo.x>=pos.x-1 and hi.x<=pos.x+size.x+1,'Control outside horizontal bounds: '..label)
        if im.IsItemVisible()then seen[widthNow..':'..label]=true end
    end
    return result
end
for _,display in ipairs({{640,480},{1366,768},{1920,1080},{2560,1440}})do
    guiIo.DisplaySize=im.ImVec2(display[1],display[2])
    for _,width in ipairs({300,500,math.min(display[1]-32,1100)})do
        widthNow=width
        for _,page in ipairs({'binds','notes'})do
            local bottom=0
            for frame=1,60 do
                im.NewFrame();im.SetNextWindowPos(im.ImVec2(16,16),im.Cond.Always);im.SetNextWindowSize(im.ImVec2(width,display[2]-32),im.Cond.Always)
                im.Begin('user-files-native-'..page,nil,im.WindowFlags.NoSavedSettings+im.WindowFlags.NoResize+im.WindowFlags.NoMove)
                if frame==1 then im.SetScrollY(0)end
                editor.currentUi=ui
                if page=='binds'then editor:drawBindingList(ui,data,callbacks,'')else editor:drawNotes(ui,data,callbacks,false)end
                check(#stack==0,'Unbalanced UI scopes')
                local atBottom=frame>=3 and im.GetScrollY()>=im.GetScrollMaxY()-1
                bottom=atBottom and bottom+1 or 0
                if frame>=2 then im.SetScrollY(math.min(im.GetScrollMaxY(),im.GetScrollY()+math.max(100,(display[2]-32)*.55)))end
                im.End();im.Render();check(im.GetDrawData().Valid,'Invalid draw data');frames=frames+1
                if bottom>=2 then break end
            end
        end
    end
end
for label in pairs(wanted)do check(seen['300:'..label],'Control unreachable at narrow width: '..label)end
editor:release();im.DestroyContext(ctx)
local out=assert(io.open(tests..'USER_FILES_NATIVE32_RESULTS.json','wb'))
out:write(string.format('{"status":"passed","checks":%d,"frames":%d,"resolutions":4,"min_window_width":300,"gta_started":false,"game_files_written":false,"renderer":"installed 32-bit ImGui, CPU only"}\n',checks,frames));out:close()
print('User files native32: '..checks..' checks; '..frames..' frames; no GTA.')

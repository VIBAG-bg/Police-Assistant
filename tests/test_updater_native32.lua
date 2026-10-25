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
local bold=guiIo.Fonts:AddFontFromFileTTF('C:/Windows/Fonts/segoeuib.ttf',18,nil,guiIo.Fonts:GetGlyphRangesCyrillic())
local pixels,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]');guiIo.Fonts:GetTexDataAsRGBA32(pixels,w,h,nil)

local model=require 'pa26_bindings';local core=require 'pa26_core';local Studio=require 'pa26_studio'
local platform=require 'pa26_update_platform';local module=require 'pa26_updater'
local checks,frames=0,0
local function check(v,why)checks=checks+1;assert(v,why)end
local fake=tests..'update-sandbox/native-юникод & path/game/MoonLoader'
local lfs=require 'lfs'
local parent=tests..'update-sandbox';lfs.mkdir(parent)
local pieces={'native-юникод & path','game','MoonLoader','resource','pa26','updater'}
local cursor=parent
-- Native wide filesystem creates the non-ASCII branch; the protocol helper
-- must work even when the ANSI Lua io functions cannot represent the path.
local p=assert(platform.new(fake))
for _,part in ipairs(pieces)do cursor=cursor..'/'..part;assert(p:mkdir(cursor))end
local f=assert(io.open(release..'moonloader/resource/pa26/updater/pa26-update.ps1','rb'));local helper=f:read('*a');f:close()
assert(p:write(p.ml..'\\resource\\pa26\\updater\\pa26-update.ps1',helper))
local message='Проверка сохранения: заметки и бинды.'
assert(p:write(p.ml..'\\native-данные.txt',message));check(p:read(p.ml..'\\native-данные.txt',1024)==message,'UTF-16 filesystem bridge')
local request='{"product":"police-assistant-2026","moonloader":"'..p.ml:gsub('\\','\\\\')..'","repository":"","include_prerelease":false,"timeout_seconds":1,"approved":false}'
local job=assert(p:start('Check',request));local json
ffi.cdef 'void __stdcall Sleep(unsigned long);';local kernel=ffi.load('kernel32')
for _=1,500 do json=p:poll(job);if json and json:find('invalid_repository',1,true)then break end;kernel.Sleep(20)end
check(json and json:find('invalid_repository',1,true),'real hidden helper process and receipt handshake')
check(not p:exists(p.ml..'\\pa26-update.pending'),'empty source never stages runtime replacement')
check(p:read(p.ml..'\\native-данные.txt',1024)==message,'helper preserves existing files')
local studio=Studio.new(im,ffi,model.defaults(core.defaults()),function()return 1000 end)
local stack={};local ui={push=function(fn)stack[#stack+1]=fn end,finish=function()assert(table.remove(stack))()end,
    text=function(t)im.PushTextWrapPos(0);im.TextUnformatted(t);im.PopTextWrapPos()end}
local updater={phase='idle',env={platform=nil}}
local cb={save=function()error('native UI test must not save user data')end}
for _,size in ipairs({{640,480},{1280,720},{1920,1080}})do
    for _=1,3 do
        guiIo.DisplaySize=im.ImVec2(size[1],size[2]);im.NewFrame()
        im.SetNextWindowPos(im.ImVec2(20,20),im.Cond.Always)
        im.SetNextWindowSize(im.ImVec2(size[1]-40,size[2]-40),im.Cond.Always)
        im.Begin('Updates native',nil,im.WindowFlags.NoSavedSettings)
        require('pa26_update_ui').draw(studio,ui,updater,cb)
        check(#stack==0,'balanced UI scopes');im.End();im.Render();frames=frames+1
    end
end
studio:release();im.DestroyContext(ctx)
local out=assert(io.open(tests..'UPDATER_NATIVE32_RESULTS.json','wb'))
out:write(string.format('{"status":"passed","checks":%d,"frames":%d,"native_unicode_io":true,"hidden_worker_handshake":true,"network_requests":0,"real_game_written":false,"gta_started":false}\n',checks,frames));out:close()
print('Updater native32: '..checks..' checks; hidden process/Unicode receipt and UI passed; no network or GTA.')

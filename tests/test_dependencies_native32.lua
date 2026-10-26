-- Optional: real pinned x86 library binaries in an isolated setup fixture.
-- The host Lua runtime is read-only; GTA is never started.
local root=assert(os.getenv('PA_DEPENDENCY_LIB'),'Set PA_DEPENDENCY_LIB to staged lib')
getWorkingDirectory=function()return root..'/..'end
package.path=root..'/?.lua;'..package.path
package.cpath=root..'/?.dll;'..package.cpath
local ffi=require 'ffi'
local im=require 'mimgui.imgui'
local encoding=require 'encoding'
encoding.default='CP1251'
local checks=0
local function check(v,why)checks=checks+1;assert(v,why)end
local cp=encoding.UTF8:decode('Проверка: паспорт и розыск')
check(encoding.UTF8(cp)=='Проверка: паспорт и розыск','real iconv round trip')
local ctx=im.CreateContext(nil)
local guiIo=im.GetIO();guiIo.IniFilename=nil;guiIo.LogFilename=nil;guiIo.DeltaTime=1/60
guiIo.DisplaySize=im.ImVec2(1280,720)
check(guiIo.Fonts:AddFontDefault(nil)~=nil,'pinned font atlas')
local pixels,w,h=ffi.new('unsigned char*[1]'),ffi.new('int[1]'),ffi.new('int[1]')
guiIo.Fonts:GetTexDataAsRGBA32(pixels,w,h,nil)
check(w[0]>0 and h[0]>0,'pinned DLL builds font texture')
for _=1,4 do
 im.NewFrame();im.Begin('PA pinned dependencies',nil,0)
 im.TextUnformatted('Police Assistant');im.InputText('Name',ffi.new('char[128]','Example'),128,0,nil,nil)
 im.End();im.Render();check(im.GetDrawData()~=nil,'pinned DLL produces draw data')
end
im.DestroyContext(ctx)
print('Pinned dependencies x86: '..checks..' checks passed; no GTA started.')

-- Exercises real Unicode scans/moves in a task-owned test directory only.
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/');local root=assert(source:match('^(.*)/tests/'))
local game=os.getenv('LOCALAPPDATA')..'/Exsellent Launcher/game/'
package.path=root..'/moonloader/lib/?.lua;'..game..'MoonLoader/lib/?.lua;'..package.path;package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
local ffi=require 'ffi';local lfs=require 'lfs'
-- Same WinAPI declaration order as actual PA startup, including frozen platform.
assert(require('pa26_update_platform').new(root..'/tests/update-sandbox/abi/MoonLoader'))
local files=require('pa26_evidence_files').new()
ffi.cdef[[void __stdcall Sleep(unsigned long);]]
local base=root..'/tests/update-sandbox/screens-'..os.time();local function mkdir(path)if not lfs.attributes(path)then local parent=path:match('^(.*)/[^/]+$');if parent then mkdir(parent)end;assert(lfs.mkdir(path))end end
mkdir(base)
local function read(path)local f=assert(io.open(path,'rb'));local b=f:read('*a');f:close();return b end
local bytes=read(root..'/moonloader/resource/pa26/sidebar-police-assistant.png')
local function write(name,text)local f=assert(io.open(base..'/'..name,'wb'));f:write(text);f:close()end
write('sa-mp-990.png',bytes);write('sa-mp-999.png',bytes);write('holiday.png',bytes);write('sa-mp-001.jpg','incomplete')
local scan=assert(files.scanScreens(base));assert(scan.nearLimit and scan.full);assert(scan.maxIndex==999);assert(scan.count==4)
assert(not files.scanScreens(base..'/..'));assert(not files.archiveScreens(base,'../bad'))
ffi.load('kernel32').Sleep(1100)
local moved=assert(files.archiveScreens(base,'20261027-120000'));assert(moved.moved==2);assert(moved.skipped==1)
assert(read(moved.archiveDir..'/sa-mp-999.png')==bytes);assert(read(base..'/holiday.png')==bytes);assert(read(base..'/sa-mp-001.jpg')=='incomplete')
scan=assert(files.scanScreens(base));assert(scan.maxIndex==1 and scan.count==2)
write('sa-mp-999.png',bytes);ffi.load('kernel32').Sleep(1100);local again=assert(files.archiveScreens(base,'20261027-120000'));assert(again.archiveDir~=moved.archiveDir)
assert(read(moved.archiveDir..'/sa-mp-999.png')==bytes);assert(read(again.archiveDir..'/sa-mp-999.png')==bytes)
print('Screens native32: scans, 990/999 limits, invalid paths, incomplete files, collision-safe archives and byte preservation passed; no game writes.')

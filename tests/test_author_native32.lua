-- Native SHA-256, exclusive lock and Unicode file transaction; no GTA or game writes.
local src=debug.getinfo(1,'S').source:sub(2):gsub('\\','/');local root=assert(src:match('^(.*)/tests/'))
package.path=root..'/moonloader/lib/?.lua;'..package.path
package.cpath=os.getenv('LOCALAPPDATA')..'/Exsellent Launcher/game/MoonLoader/lib/?.dll;'..package.cpath
local ffi=require 'ffi';local ioModule=require 'pa26_author_io';local lfs=require 'lfs'
local folder=root..'/tests/update-sandbox/author-native-'..os.time()
local function mkdir(p)if not lfs.attributes(p)then local parent=p:match('^(.*)/[^/]+$');if parent then mkdir(parent)end;assert(lfs.mkdir(p))end end
mkdir(folder..'/game/MoonLoader/config')
local adapter=assert(ioModule.new(folder..'/game/MoonLoader'))
assert(ioModule.hash('abc')=='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
assert(ioModule.hash('')=='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
local path=folder..'/game/MoonLoader/config/test.dat'
assert(adapter.fs.write(path,'SAMPLE UTF-8: '..string.char(208,144)))
assert(adapter.fs.read(path)=='SAMPLE UTF-8: '..string.char(208,144))
assert(adapter.fs.rename(path,path..'.moved'));assert(not adapter.fs.exists(path));assert(adapter.fs.remove(path..'.moved'))
local unlock=assert(ioModule.lock(path..'.lock'));assert(not ioModule.lock(path..'.lock'));unlock()
unlock=assert(ioModule.lock(path..'.lock'));unlock()
assert(not adapter.fs.exists(path..'.lock'))
print('Author native32: 10 checks passed; SHA-256, write-through IO and exclusive lock; no GTA.')

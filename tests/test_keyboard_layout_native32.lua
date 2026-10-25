-- Run in the installed x86 LuaJIT host. Never activates a window or changes a layout.
local source=debug.getinfo(1,'S').source:sub(2):gsub('\\','/')
local tests=assert(source:match('^(.*[/])'))
local game=assert(os.getenv('LOCALAPPDATA'), 'LOCALAPPDATA required')..'/Exsellent Launcher/game/'
package.path=tests..'../moonloader/lib/?.lua;'..package.path
package.cpath=game..'MoonLoader/lib/?.dll;'..package.cpath
local ffi=require'ffi';local json=require'cjson';local m=require'pa26_keyboard_layout'
local checks=0
local function check(v,message)checks=checks+1;assert(v,message)end
check(ffi.abi('32bit'),'The installed 32-bit runtime is required')
local api=assert(m.native(ffi));check(tonumber(api.process())>0)
for _,row in ipairs({{0x419,'RU'},{0x409,'EN'},{0x809,'EN'},{0x402,'BG'},{0x422,'UK'},{0x411,'JA'},{0x464,'FIL'}})do
    check(m.language(ffi,api,ffi.cast('void*',row[1]))==row[2],row[2])
end
check(m.language(ffi,api,ffi.cast('void*',0))==nil)
check(m.language(ffi,api,ffi.cast('void*',0xf0190419))=='RU','high HKL bits are not part of the language identifier')
local read=m.reader(ffi,api)
local window=api.foreground();local owner=ffi.new('unsigned long[1]')
local thread=window~=nil and tonumber(api.windowThread(window,owner))or 0
local observed=read()
if thread>0 and tonumber(owner[0])~=tonumber(api.process())then
    check(observed==nil,'The helper must ignore another application')
else check(observed==nil or observed:match('^[A-Z][A-Z][A-Z]?$'))end
local result={status='passed',checks=checks,real_installed_x86_luajit=true,real_win32_locale_api=true,
    foreground_api_called=true,keyboard_hooks_installed=false,keyboard_layout_changed=false,gta_launched=false,
    game_focus_and_physical_switching_tested=false}
local f=assert(io.open(tests..'KEYBOARD_NATIVE32_RESULTS.json','wb'));f:write(json.encode(result));f:close()
print('Native x86 keyboard language: '..checks..' checks passed; no keyboard state changed.')

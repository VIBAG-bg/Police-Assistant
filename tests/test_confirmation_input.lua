local module=dofile('moonloader/lib/pa26_input.lua')
local raw={};local calls={}
local reader=module.new(function(key)calls[#calls+1]=key;return raw[key] or 0 end)
local value=reader:read();check(value.physical);check(not value.y and not value.n and not value.mods)
eq(#calls,7)
raw[0x59]=1;value=reader:read();check(not value.y,'low recently-pressed bit must not accept a confirmation')
raw[0x59]=-32768;value=reader:read();check(value.y and not value.n)
raw[0x4e]=32769;value=reader:read();check(value.y and value.n)
for _,key in ipairs({0x11,0x12,0x10,0x5b,0x5c}) do raw[key]=-32768;check(reader:read().mods);raw[key]=0 end
for _,bad in ipairs({false,'pressed',0/0,math.huge,2.5,999999}) do
    local invalid=module.new(function()return bad end);eq(invalid:read(),nil)
end
eq(module.new(function()error('missing native API')end):read(),nil)
local configured={}
for _,row in ipairs(require('pa26_bindings').featureKeys)do configured[#configured+1]={key=0x34}end
configured[#configured+1]={key=0x78};configured[#configured+1]={key=0x1b};configured[#configured+1]={key=0x23}
check(#configured>16 and #configured<=module.MAX_SHORTCUTS)
raw[0x34]=-32768;calls={};value=reader:read(configured);check(value and value.keys[0x34])
eq(#calls,11,'Duplicate assignments cause only one physical read per key')
for i=#configured+1,module.MAX_SHORTCUTS+1 do configured[i]={key=0x34}end
eq(reader:read(configured),nil,'A bounded configured-key inventory remains enforced')

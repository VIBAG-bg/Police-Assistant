local m=require 'pa26_map_adapter';local grid=require 'pa26_map_grid';local ffi=require 'ffi'
local function reader()
    local p=m.profile;local r={calls=0,bound=0,reads=0,baseAddress=p.base}
    r.strings={[p.base]='MZ',[p.base+128]='PE\0\0',[p.screen]=p.screenBytes,[p.world]=p.worldBytes}
    r.ints={[p.base+60]=128,[p.base+128+8]=p.timestamp,[p.base+128+52]=p.base,[p.base+128+80]=0x1177000}
    r.shorts={[p.base+128+4]=0x14C,[p.base+128+24]=0x10B}
    r.bytesData={[0xBA68A5]=5,[0xBA67A1]=0,[0xBAA3FB]=0}
    r.floats={[0xBA67AC]=280,[0xBA67B0]=320,[0xBA67B4]=224,[0xBA8314]=2990,[0xBAA248]=0,[0xBAA24C]=0,[0xBA8310]=0,[0xBA830C]=1}
    function r:base()self.reads=self.reads+1;return self.baseAddress end
    function r:bytes(addr,n)self.reads=self.reads+1;return self.strings[addr]end
    function r:u32(addr)self.reads=self.reads+1;return self.ints[addr]end
    function r:u16(addr)self.reads=self.reads+1;return self.shorts[addr]end
    function r:byte(addr)self.reads=self.reads+1;return self.bytesData[addr]end
    function r:float(addr)self.reads=self.reads+1;return self.floats[addr]end
    function r:executable(addr,n)return not self.noExec end
    function r:bind()self.bound=self.bound+1 end
    function r:worldScreen(x,y)self.calls=self.calls+1;return 100+x*.1,100-y*.1 end
    function r:radarScreen(x,y)self.calls=self.calls+1;return 100+x*50,100-y*50 end
    return r
end
local state={connected=true,focused=true,interior=0,x=0,y=0,paused=false};local settings=grid.defaults()
for _,mutate in ipairs({
    function(r)r.baseAddress=0 end,function(r)r.strings[m.profile.base]='NO'end,
    function(r)r.ints[m.profile.base+60]=math.huge end,function(r)r.shorts[m.profile.base+128+4]=0x8664 end,
    function(r)r.ints[m.profile.base+128+8]=0 end,function(r)r.ints[m.profile.base+128+80]=1 end,
    function(r)r.noExec=true end,function(r)r.strings[m.profile.screen]='bad'end,function(r)r.strings[m.profile.world]='bad'end,
})do
    local r=reader();mutate(r);local a=m.new(nil,r);check(not a:safeView(state,300,300,settings));eq(r.bound,0);eq(r.calls,0)
    local before=r.reads;check(not a:safeView(state,300,300,settings));eq(r.reads,before,'Unsupported image must not be probed every frame')
end
local r=reader();local a=m.new(nil,r);local v=assert(a:safeView(state,300,300,settings));eq(a.status,'ready');eq(r.bound,1)
check(grid.validView(v));eq(v.kind,'radar');check(v.ellipse);check(math.abs(v.a-.1)<1e-6);check(math.abs(v.d+.1)<1e-6)
check(a:safeView(state,300,300,settings));eq(r.bound,1)
local hiddenCalls=r.calls;r.bytesData[0xBAA3FB]=1;check(not a:safeView(state,300,300,settings));eq(r.calls,hiddenCalls)
r.bytesData[0xBAA3FB]=nil;check(not a:safeView(state,300,300,settings));eq(a.status,'memory');eq(r.calls,hiddenCalls)
r.bytesData[0xBAA3FB]=0
local before=r.calls;state.paused=true;v=assert(a:safeView(state,1280,896,settings));eq(v.kind,'map');eq(r.calls,before,'Pause-map projection must not call a radar function with a reset drawing flag')
local x,y=grid.project(v,0,0);eq(x,640);eq(y,448);x,y=grid.project(v,2990,2990);eq(x,1200);eq(y,-112)
r.bytesData[0xBA68A5]=6;check(not a:safeView(state,1280,896,settings));eq(r.calls,before)
r.bytesData[0xBA68A5]=5;r.floats[0xBA67AC]=nil;check(not a:safeView(state,1280,896,settings));eq(a.status,'memory');eq(r.calls,before)
r.floats[0xBA67AC]=280;r.floats[0xBA8314]=350;check(not a:safeView(state,1280,896,settings));eq(a.status,'map_not_ready')
r.floats[0xBA8314]=2990;state.paused=false;r.strings[m.profile.world]='changed after initialization'
check(not a:safeView(state,300,300,settings));eq(a.status,'signature');eq(r.calls,before)
r.strings[m.profile.world]=m.profile.worldBytes;a:reset();check(a:safeView(state,300,300,settings));eq(r.bound,2)
for k,value in pairs({focused=false,connected=false,interior=1})do local s={};for key,vv in pairs(state)do s[key]=vv end;s[k]=value
    before=r.calls;check(not a:safeView(s,300,300,settings));eq(r.calls,before)
end
before=r.calls;check(not a:safeView(state,0,300,settings));eq(r.calls,before)
settings.enabled=false;check(not a:safeView(state,300,300,settings));eq(a.status,'disabled');eq(r.calls,before)
settings.enabled=true;r.worldScreen=function()error('Injected renderer error')end
check(not a:safeView(state,300,300,settings));eq(a.status,'failed');check(a.failed)
a:reset();check(not a.failed)
-- Outside GTA the real backend is rejected before binding any game function.
local actual=m.new(ffi);check(not actual:safeView(state,300,300,settings));check(not actual.reader or actual.reader.worldFn==nil)

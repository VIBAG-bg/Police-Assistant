-- Optional read-only adapter for the verified GTA SA 1.0 US radar layout.
-- No game writes/hooks, path finding, process scanning or launcher/CEF changes.
local core=require 'pa26_core'
local grid=require 'pa26_map_grid'
local M={};local Adapter={};Adapter.__index=Adapter
local function unhex(s)return(s:gsub('..',function(x)return string.char(tonumber(x,16))end))end
M.profile={base=0x400000,timestamp=0x427101CA,screen=0x583480,world=0x583530,
    screenBytes=unhex('a0a167ba008b4c240484c08b4424087423d905ac67ba00d808d805b067ba00d919d905ac67ba00d84804d82db467ba00d95904c3db054470c100d80d20958500'),
    worldBytes=unhex('83ec088b442410d900d82548a2ba00d940048b44240cd8254ca2ba00d90524868500d8351483ba00d9c0d8cbd95c2400d8c9dddaddd8d9050c83ba00d8c9d905')}
M.reasons={unchecked='Адаптер карты ещё не проверен.',ready='Поддерживаемая проекция GTA SA 1.0 US.',
    platform='Для проекции карты нужен 32-битный игровой LuaJIT.',kernel='Не удалось подключить проверку памяти Windows.',
    process='Процесс игры не соответствует поддерживаемому размещению GTA.',image='Не подтверждена версия исполняемого файла GTA.',
    signature='Проекция радара изменена или версия GTA пока не поддерживается.',memory='Данные карты недоступны для безопасного чтения.',
    geometry='Проекция карты вернула некорректные координаты.',map_not_ready='Карта GTA ещё не подготовлена к отрисовке.',
    hidden='Сетка скрыта в текущем экране.',disabled='Квадраты карты выключены.',failed='Отрисовка сетки остановлена после ошибки.'}
-- The reader is injected for deterministic tests. Every read in the real backend checks VirtualQuery first.
function M.verify(reader)
    local p=M.profile;local base=reader:base()
    if base~=p.base then return nil,'process'end
    if reader:bytes(base,2)~='MZ'then return nil,'image'end
    local off=reader:u32(base+60)
    if not core.finite(off)or off<64 or off>0x100000 or off~=math.floor(off)then return nil,'image'end
    local pe=base+off
    if reader:bytes(pe,4)~='PE\0\0'or reader:u16(pe+4)~=0x14C or reader:u16(pe+24)~=0x10B or
        reader:u32(pe+8)~=p.timestamp or reader:u32(pe+52)~=p.base then return nil,'image'end
    local size=reader:u32(pe+80)
    if not core.finite(size)or size<0xC00000 or size>0x4000000 then return nil,'image'end
    if not reader:executable(p.screen,#p.screenBytes)or not reader:executable(p.world,#p.worldBytes)or
        reader:bytes(p.screen,#p.screenBytes)~=p.screenBytes or reader:bytes(p.world,#p.worldBytes)~=p.worldBytes then return nil,'signature'end
    return true,'ready'
end
local function backend(ffi)
    if not ffi or not ffi.abi('32bit')or not ffi.abi('win')then return nil,'platform'end
    ffi.cdef[[
      typedef struct {void *BaseAddress;void *AllocationBase;unsigned long AllocationProtect;
        unsigned long RegionSize;unsigned long State;unsigned long Protect;unsigned long Type;} PA31_MapMemoryInfo;
      typedef struct {float x;float y;} PA31_MapVector;
      void* __stdcall GetModuleHandleA(const char* name);
      unsigned long __stdcall VirtualQuery(const void* address,PA31_MapMemoryInfo* info,unsigned long size);
    ]]
    local kernel=ffi.load('kernel32');local bit=require 'bit'
    local r={info=ffi.new('PA31_MapMemoryInfo[1]')}
    function r:base()return tonumber(ffi.cast('uintptr_t',kernel.GetModuleHandleA(nil)))end
    function r:range(addr,n,exec)
        if not core.finite(addr)or addr<0x10000 or addr>0x7FFFFFFF or not core.finite(n)or n<1 or n>512 then return false end
        local pointer=ffi.cast('const void*',addr)
        if kernel.VirtualQuery(pointer,self.info,ffi.sizeof(self.info[0]))~=ffi.sizeof(self.info[0])then return false end
        local i=self.info[0];local start=tonumber(ffi.cast('uintptr_t',i.BaseAddress));local protect=tonumber(i.Protect)
        if tonumber(i.State)~=0x1000 or bit.band(protect,0x101)~=0 or addr+n>start+tonumber(i.RegionSize)or
            tonumber(ffi.cast('uintptr_t',i.AllocationBase))~=M.profile.base then return false end
        return bit.band(protect,exec and 0xF0 or 0xEE)~=0
    end
    function r:executable(addr,n)return self:range(addr,n,true)end
    function r:bytes(addr,n)if self:range(addr,n,false)then return ffi.string(ffi.cast('const char*',addr),n)end end
    function r:u32(addr)if self:range(addr,4,false)then return tonumber(ffi.cast('const unsigned int*',addr)[0])end end
    function r:u16(addr)if self:range(addr,2,false)then return tonumber(ffi.cast('const unsigned short*',addr)[0])end end
    function r:byte(addr)if self:range(addr,1,false)then return tonumber(ffi.cast('const unsigned char*',addr)[0])end end
    function r:float(addr)if self:range(addr,4,false)then return tonumber(ffi.cast('const float*',addr)[0])end end
    function r:bind()
        self.input=ffi.new('PA31_MapVector[1]');self.radar=ffi.new('PA31_MapVector[1]');self.output=ffi.new('PA31_MapVector[1]')
        self.worldFn=ffi.cast('void (__cdecl *)(PA31_MapVector*,const PA31_MapVector*)',M.profile.world)
        self.screenFn=ffi.cast('void (__cdecl *)(PA31_MapVector*,const PA31_MapVector*)',M.profile.screen)
    end
    function r:worldScreen(x,y)
        self.input[0].x=x;self.input[0].y=y;self.worldFn(self.radar,self.input);self.screenFn(self.output,self.radar)
        return tonumber(self.output[0].x),tonumber(self.output[0].y)
    end
    function r:radarScreen(x,y)
        self.radar[0].x=x;self.radar[0].y=y;self.screenFn(self.output,self.radar)
        return tonumber(self.output[0].x),tonumber(self.output[0].y)
    end
    return r
end
function M.new(ffi,reader)
    local out=setmetatable({status='unchecked'},Adapter)
    if reader then out.reader=reader;return out end
    local ok,r,reason=pcall(backend,ffi)
    if ok and r then out.reader=r else out.status=ok and reason or 'kernel'end
    return out
end
function Adapter:reset()self.checked=nil;self.status=self.reader and'unchecked'or self.status;self.failed=nil end
function Adapter:message()return M.reasons[self.status]or M.reasons.failed end
function Adapter:probe()
    if self.failed or not self.reader then return false end
    if self.checked~=nil then return self.checked==true end
    local ok,valid,reason=pcall(M.verify,self.reader)
    self.status=ok and reason or'memory';self.checked=ok and valid==true or false
    if self.checked then
        local bound=pcall(self.reader.bind,self.reader);if not bound then self.checked=false;self.status='memory'end
    end
    return self.checked
end
function Adapter:view(state,width,height,s)
    if not s.enabled then self.status='disabled';return nil end
    if not state or not state.connected or state.focused~=true or state.interior~=0 or not core.finite(width)or not core.finite(height)or
        width<200 or height<200 or width>16384 or height>16384 then return nil end
    if not self:probe()then return nil end
    local r=self.reader
    -- Reject new hooks/changed permissions before any call into GTA; unknown builds never reach bind/worldScreen.
    local p=M.profile
    if not r:executable(p.screen,#p.screenBytes)or not r:executable(p.world,#p.worldBytes)or
        r:bytes(p.screen,#p.screenBytes)~=p.screenBytes or r:bytes(p.world,#p.worldBytes)~=p.worldBytes then
        self.checked=false;self.status='signature';return nil
    end
    if state.paused then
        if not s.pause_map or r:byte(0xBA68A5)~=5 then self.status='hidden';return nil end
        -- The front-end drawing flag is temporary. Read the prepared map transform instead of
        -- forcing this flag or calling the radar-screen function after the front-end has reset it.
        local zoom,ox,oy=r:float(0xBA67AC),r:float(0xBA67B0),r:float(0xBA67B4)
        local range,wx,wy=r:float(0xBA8314),r:float(0xBAA248),r:float(0xBAA24C)
        local sn,cs=r:float(0xBA8310),r:float(0xBA830C)
        if not(core.finite(zoom)and core.finite(ox)and core.finite(oy)and core.finite(range)and core.finite(wx)and core.finite(wy)and core.finite(sn)and core.finite(cs))then self.status='memory';return nil end
        if zoom<10 or zoom>10000 or math.abs(ox)>20000 or math.abs(oy)>20000 or range<1000 or range>10000 or
            math.abs(wx)>.01 or math.abs(wy)>.01 or math.abs(sn)>.001 or math.abs(cs-1)>.001 then self.status='map_not_ready';return nil end
        local sx,sy=width/640,height/448
        self.status='ready';return {kind='map',a=zoom/range*sx,b=0,c=0,d=-zoom/range*sy,ox=ox*sx,oy=oy*sy,
            left=0,top=0,right=width,bottom=height}
    end
    if not s.radar or r:byte(0xBA67A1)~=0 or not core.finite(state.x)or not core.finite(state.y)then return nil end
    local radarHidden=r:byte(0xBAA3FB)
    if radarHidden~=0 then self.status=radarHidden==nil and'memory'or'hidden';return nil end
    local x0,y0=r:worldScreen(state.x,state.y);local xx,yx=r:worldScreen(state.x+128,state.y);local xy,yy=r:worldScreen(state.x,state.y+128)
    local cx,cy=r:radarScreen(0,0);local lx,ly=r:radarScreen(-1,0);local rx,ry=r:radarScreen(1,0)
    local tx,ty=r:radarScreen(0,1);local bx,by=r:radarScreen(0,-1)
    local all={x0,y0,xx,yx,xy,yy,cx,cy,lx,ly,rx,ry,tx,ty,bx,by}
    if #all~=16 then self.status='geometry';return nil end
    for _,n in ipairs(all)do if not core.finite(n)or math.abs(n)>1e7 then self.status='geometry';return nil end end
    local a,b,c,d=(xx-x0)/128,(xy-x0)/128,(yx-y0)/128,(yy-y0)/128
    local erx,ery=math.abs(rx-lx)/2,math.abs(by-ty)/2
    if erx<10 or ery<10 or erx>width/2 or ery>height/2 or cx-erx<0 or cy-ery<0 or cx+erx>width or cy+ery>height then self.status='geometry';return nil end
    local margin=math.max(2,s.line_width/2+2)
    local v={kind='radar',a=a,b=b,c=c,d=d,ox=x0-a*state.x-b*state.y,oy=y0-c*state.x-d*state.y,
        left=cx-erx+margin,top=cy-ery+margin,right=cx+erx-margin,bottom=cy+ery-margin,ellipse={cx=cx,cy=cy,rx=erx-margin,ry=ery-margin}}
    if not grid.validView(v)then self.status='geometry';return nil end
    self.status='ready';return v
end
function Adapter:safeView(...)
    if self.failed then return nil end
    local ok,v=pcall(self.view,self,...)
    if not ok then self.status='failed';self.failed=true;return nil end
    return v
end
return M

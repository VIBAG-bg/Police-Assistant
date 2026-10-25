local model=require 'pa26_bindings';local prefs=require 'pa26_preferences';local input=require 'pa26_input'
local module=require 'pa26_notifications'
local raw,calls={},{}
local reader=input.new(function(key)calls[#calls+1]=key;return raw[key]or 0 end)
local keys=reader:read({prefs.radioGuardDefaults().skip_shortcut,prefs.weaponWarningDefaults().shortcut})
eq(#calls,8,'seven confirmation keys and only one additional configured VK');check(keys.physical);check(not keys.keys[0x57])
raw[0x12]=-32768;raw[0x57]=1;keys=reader:read({prefs.weaponWarningDefaults().shortcut});check(keys.alt and not keys.keys[0x57])
raw[0x57]=-32768;check(reader:read({prefs.weaponWarningDefaults().shortcut}).keys[0x57])
check(not reader:read({{key='W'}}));check(not reader:read({{key=999}}))
local function physical(held,mods)
    held=held or {};mods=mods or {}
    return {physical=true,keys=held,y=held[0x59]or false,n=held[0x4e]or false,
        ctrl=mods.ctrl or false,alt=mods.alt or false,shift=mods.shift or false,super=mods.super or false,
        mods=mods.ctrl or mods.alt or mods.shift or mods.super or false}
end
local font={CalcTextSizeA=function(_,size,_,wrap,text)
    local width=math.min(wrap,#text*size*.3);return {x=width,y=size*math.max(1,math.ceil(#text*size*.3/wrap))}
end}
local io={DisplaySize={x=1280,y=720},MousePos={x=0,y=0}}
local list={AddRectFilled=function()end,AddTextFontPtr=function()end}
local clicked=false
local im={GetIO=function()return io end,GetFont=function()return font end,GetForegroundDrawList=function()return list end,
    ImVec2=function(x,y)return{x=x,y=y}end,ImVec4=function(...)return{...}end,ColorConvertFloat4ToU32=function(v)return v end,
    IsMouseClicked=function()return clicked end}
local function setup(mode)
    local s={now=1000,actions={},skips={},painted={},state={focused=true,paused=false,blocked=false,typing=false,recording=false,mouseAllowed=false,demo=false}}
    local c=module.new({skipShortcut=function()return prefs.radioGuardDefaults().skip_shortcut end,
        warnShortcut=function()return prefs.weaponWarningDefaults().shortcut end,lead=function()return 30000 end,
        weaponDuration=function()return 10000 end,action=function(owner,token,yes)s.actions[#s.actions+1]={owner,token,yes}end,
        skip=function(token)s.skips[#s.skips+1]=token or 'nearest'end,shown=function(owner,token)s.painted[#s.painted+1]={owner,token}end})
    s.candidate={owner='weapon',token='weapon:1',title='Тайзер · предупреждение',body='/s Предупреждение.',status='После вашего действия',hint='Проверьте ситуацию',
        mode=mode or 'confirm',full=true,unseen=false,priority=50,remaining=10000,serial=1000,yes='Предупредить',no='Позже',shortcut=prefs.weaponWarningDefaults().shortcut}
    function s.tick(ms,keys,paint)
        s.now=s.now+(ms or 16);c:tick({model.copy(s.candidate)},s.state,s.now,keys or physical())
        if paint~=false then c:draw(im,{body=font,heading=font},{})end
    end
    s.tick(0);return c,s
end
-- A held pre-existing Y never accepts the new surface. A release/new press does.
local c,s=setup();s.tick(150,physical({[0x59]=true}));s.tick(16,physical({[0x59]=true}));eq(#s.actions,0)
s.tick(16);s.tick(16,physical({[0x59]=true}));eq(#s.actions,1);check(s.actions[1][3]);s.tick(16,physical({[0x59]=true}));eq(#s.actions,1)
c,s=setup();s.tick(150);s.tick(16,physical({[0x59]=true,[0x4e]=true}));eq(#s.actions,0)
s.tick();s.tick(16,physical({[0x59]=true},{ctrl=true}));eq(#s.actions,0)
for _,flag in ipairs({'typing','recording','blocked','modal','alertPending','paused'})do
    c,s=setup();s.tick(150);s.state[flag]=true;s.tick(16,physical({[0x59]=true}));eq(#s.actions,0,flag)
    s.state[flag]=false;s.tick(16,physical({[0x59]=true}));eq(#s.actions,0,'held after pause');s.tick(150);s.tick(16,physical({[0x59]=true}));eq(#s.actions,1)
end
-- Toast mode uses its exact configurable chord and rejects extra modifiers.
c,s=setup('weapon');s.tick(150);s.tick(16,physical({[0x57]=true}));eq(#s.actions,0)
s.tick();s.tick(16,physical({[0x57]=true},{alt=true,ctrl=true}));eq(#s.actions,0)
s.tick();s.tick(16,physical({[0x57]=true},{alt=true}));eq(#s.actions,1)
-- Skip is independent from speech and does not stop an unrelated binder.
c,s=setup('weapon');s.tick(150);s.tick(16,physical({[0x4e]=true},{alt=true}));eq(#s.skips,1);eq(s.skips[1],'nearest');eq(#s.actions,0)
-- Mouse needs a cursor; stale click tokens cannot affect replacement content.
c,s=setup();s.tick(150);local b=c.buttons.yes;io.MousePos={x=b.x+3,y=b.y+3};clicked=true
s.tick();s.tick();eq(#s.actions,0)
s.state.mouseAllowed=true;s.tick();clicked=false;s.candidate.token='weapon:2';s.tick();eq(#s.actions,0)
s.tick(150);b=c.buttons.no;io.MousePos={x=b.x+3,y=b.y+3};clicked=true;s.tick();clicked=false;s.tick();eq(#s.actions,1);check(not s.actions[1][3])
-- Click already in progress when a new card appears cannot accept it.
c,s=setup();s.state.mouseAllowed=true;b=c.buttons.yes;io.MousePos={x=b.x+3,y=b.y+3};clicked=true
s.tick(150);s.tick();eq(#s.actions,0);clicked=false;s.tick();clicked=true;s.tick();clicked=false;s.tick();eq(#s.actions,1)
-- Long readable content, compact mode and blockers fit supported viewports.
for _,size in ipairs({{640,480},{1280,720},{1920,1080},{2560,1440}})do
    c,s=setup();io.DisplaySize={x=size[1],y=size[2]};s.candidate.body='/s '..string.rep('Текст ',18);s.tick()
    local r=c.bounds;check(r and r.x>=0 and r.y>=0 and r.x+r.w<=size[1]and r.y+r.h<=size[2])
    s.candidate.owner='radio';s.candidate.mode='radio';s.candidate.full=false;s.candidate.status='Доклад через 20 с';s.tick();check(c.bounds)
    local avoid={{x=c.bounds.x,y=c.bounds.y,w=c.bounds.w,h=c.bounds.h}}
    local moved=c:measure(im,{body=font,heading=font},avoid);check(not moved or not module.overlaps(moved,avoid[1]))
end
io.DisplaySize={x=1280,y=720};io.MousePos={x=0,y=0};clicked=false

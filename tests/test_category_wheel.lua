local core=require 'pa26_core'
local model=require 'pa26_bindings'
local wheel=require 'pa26_wheel'
local runtime=require 'pa26_runtime'
local cfg=core.defaults(); local lib=model.defaults(cfg)
check(not wheel.available(wheel.build(lib,1),{kind='binding',id=3},false,{id=37,ped=99,name='Person'}),'Unverified fresh wanted example is disabled')
lib.bindings[3].enabled=true -- generic geometry below uses an explicitly enabled personal fixture
local function legacy(v)
    local copy=model.copy(v); copy.settings.wheel_mode=nil; copy.settings.wheel_profile=nil
    for _,b in ipairs(copy.bindings) do b.wheel_visible=nil; b.wheel_group=nil end
    return copy
end
local old=legacy(lib); old.bindings[3].quick=false
local migrated=model.validate(old,cfg); check(migrated)
eq(migrated.settings.wheel_mode,'categories'); eq(migrated.settings.wheel_profile,'compact')
check(migrated.bindings[3].wheel_visible,'old pinned slot survives with F11 disabled')
eq(migrated.bindings[3].script,lib.bindings[3].script); eq(migrated.next_id,lib.next_id)
local bad=model.copy(lib); bad.settings.wheel_profile='invalid'; check(not model.validate(bad,cfg))
bad=model.copy(lib); bad.bindings[1].wheel_group='unknown'; check(not model.validate(bad,cfg))
bad=model.copy(lib); bad.bindings[1].wheel_visible=1; check(not model.validate(bad,cfg))

for _,profile in ipairs({'compact','extended','full'}) do
    lib.settings.wheel_profile=profile; local catalogue=wheel.build(lib,5)
    eq(#catalogue.categories,#wheel.profiles[profile]); eq(catalogue.revision,5)
    eq(catalogue.byId[2].category,profile=='full' and 'documents' or 'citizen')
    eq(catalogue.byId[4].category,profile=='full' and 'frisk' or 'detention')
    local total=0;for _,cat in ipairs(catalogue.categories) do total=total+#cat.items end;eq(total,6)
    for _,viewport in ipairs({{640,480},{1280,720},{1920,1080},{2560,1440}}) do
        local layout=wheel.layout(viewport[1],viewport[2],#catalogue.categories);check(layout)
        check(layout.left>=16);check(layout.top>=16)
        check(layout.cx-layout.outer>=16);check(layout.cx+layout.outer<=viewport[1]-16)
        check(layout.cy-layout.outer>=16);check(layout.cy+layout.outer<=viewport[2]-16)
        for i,cat in ipairs(catalogue.categories) do
            local middle=-math.pi/2+(i-.5)*layout.step; local r=(layout.inner+layout.rootOuter)/2
            local dx,dy=math.cos(middle)*r,math.sin(middle)*r
            eq(wheel.rootAt(layout,dx,dy),i)
            local nav={};eq(wheel.hover(nav,catalogue,layout,dx,dy,1000,false,true),nil);eq(nav.active,nil)
            wheel.hover(nav,catalogue,layout,dx,dy,1111,false,true);eq(nav.active,i);eq(nav.choice,nil)
            wheel.hover(nav,catalogue,layout,dx/ r*(layout.rootOuter+layout.childInner)/2,dy/r*(layout.rootOuter+layout.childInner)/2,1120,false,true)
            eq(nav.active,i);eq(nav.choice,nil)
            local entries=wheel.entries(cat);local arc=wheel.arc(layout,i,#entries)
            for n,entry in ipairs(entries) do
                local a=arc.first+(n-.5)*arc.step;local distance=(layout.childInner+layout.outer)/2
                local route=wheel.hover(nav,catalogue,layout,math.cos(a)*distance,math.sin(a)*distance,1140,false,true)
                check(wheel.sameRoute(route,entry));eq(nav.active,i)
            end
            wheel.hover(nav,catalogue,layout,0,0,1160,false,true);eq(nav.active,nil);eq(nav.choice,nil)
            wheel.hover(nav,catalogue,layout,layout.outer+10,0,1170,false,true);eq(nav.choice,nil)
        end
    end
end
eq(wheel.layout(0/0,720,4),nil);eq(wheel.layout(100,100,4),nil);eq(wheel.layout(1280,720,5),nil)
-- Native text is measured within wedge boundaries, including long names.
local font={CalcTextSizeA=function(_,size,_,wrap,text)
    local lines,width,x=1,0,0
    for glyph in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        if glyph=='\n' then width=math.max(width,x);x=0;lines=lines+1
        else if wrap>0 and x>0 and x+size*.5>wrap then width=math.max(width,x);x=0;lines=lines+1 end;x=x+size*.5 end
    end
    return {x=math.max(width,x),y=lines*size}
end}
for _,count in ipairs({4,6,8}) do for index=1,count do
    local layout=wheel.layout(1280,720,count);local arc=wheel.arc(layout,index,6)
    for n=1,6 do
        local middle=arc.first+(n-.5)*arc.step
        local size,extent,display=wheel.fitLabel(font,'Очень длинное название полицейской процедуры',17,120,188,306,middle,arc.step)
        check(size>=11);check(display~='' and core.validUtf8(display))
        local x,y=math.cos(middle)*247,math.sin(middle)*247
        for _,dx in ipairs({-extent.x/2,extent.x/2})do for _,dy in ipairs({-extent.y/2,extent.y/2})do
            local radius=math.sqrt((x+dx)^2+(y+dy)^2)
            local delta=(math.atan2(y+dy,x+dx)-middle+math.pi)%(2*math.pi)-math.pi
            check(radius>=193-.01 and radius<=301+.01);check(math.abs(delta)<=arc.step/2-.023)
        end end
    end
end end
lib.settings.wheel_mode='classic';eq(wheel.build(lib,6),nil);lib.settings.wheel_mode='categories';lib.settings.wheel_profile='compact'
local cat=wheel.build(lib,6); local source=cat.byId[1].binding.script
lib.bindings[1].script='Изменённый текст';eq(cat.byId[1].binding.script,source,'catalogue owns its snapshot')
local route={kind='binding',id=1,category='citizen'}
check(not wheel.available(cat,route,false,nil));check(wheel.available(cat,route,true,nil))
cat.byId[1].binding.enabled=false;check(not wheel.available(cat,route,true,nil));cat.byId[1].binding.enabled=true
check(not wheel.available(cat,{kind='binding',id=1,category='service'},true,nil))
check(not wheel.available(cat,{kind='more',category='citizen'},true,nil))

-- Many actions produce five rows plus More, not an oversized ring.
for id=7,14 do local b=model.newBinding(id);b.wheel_visible=true;b.wheel_group='citizen';lib.bindings[#lib.bindings+1]=b;lib.next_id=id+1 end
cat=wheel.build(lib,6);local entries=wheel.entries(cat.byCategory.citizen);eq(#entries,6);eq(entries[6].kind,'more')
check(wheel.available(cat,entries[6],true,nil))
local long='Очень длинное название тестовой процедуры с кириллицей и лишними словами'
local short=wheel.shortLabel(long);check(core.validUtf8(short));check(#short<#long);check(short:find('…',1,true))

-- The retained runtime validates snapshots, identity/context, freshness and once-only commit.
local function runtimeFixture(demo)
    local s={now=10000,revision=6,valid=true,started={},navigated={},ctx={session='test',focused=true,paused=false,blocked=false,window=false,alive=true}}
    local captured={id=37,ped=99,name='Player_Name'}
    local env={now=function()return s.now end,context=function()return s.ctx end,acquire=function()return s.valid and captured or nil end,
        validate=function()return s.valid and captured or nil end,log=function()end,codec=codec,
        wheelCatalog=function()return wheel.build(lib,s.revision)end,wheelRevision=function()return s.revision end,
        startWheelBinding=function(item,target,isDemo)s.started[#s.started+1]={item=item,target=target,demo=isDemo};return true end,
        wheelNavigate=function(value,profile)s.navigated[#s.navigated+1]={value=value,profile=profile};return true end}
    local config=core.defaults();config.main.demo_mode=demo==true
    return runtime.new(env,config),s
end
local r,s=runtimeFixture(true);check(r:openWheel());s.now=s.now+150;r:setBindingChoice(route,s.now)
check(r:commitWheel(route));eq(#s.started,1);check(not r:commitWheel(route));eq(#s.started,1)
r,s=runtimeFixture(true);check(r:openWheel());s.now=s.now+150;r:setBindingChoice(route,s.now)
check(not r:commitWheel({kind='binding',id=2,category='citizen'}));eq(#s.started,0)
r,s=runtimeFixture(true);check(r:openWheel());s.now=s.now+50;r:setBindingChoice(route,s.now);check(not r:commitWheel());eq(#s.started,0)
r,s=runtimeFixture(true);check(r:openWheel());s.now=s.now+150;r:setBindingChoice(route,s.now);s.now=s.now+251
check(not r:commitWheel());eq(#s.started,0)
r,s=runtimeFixture(true);check(r:openWheel());s.now=s.now+150;r:setBindingChoice(route,s.now);s.revision=7
check(not r:commitWheel());eq(#s.started,0)
r,s=runtimeFixture();check(r:openWheel());s.now=s.now+150;r:setBindingChoice(route,s.now);s.valid=false
check(not r:commitWheel());eq(#s.started,0)
for _,context in ipairs({{'focused',false},{'paused',true},{'blocked',true},{'window',true},{'session','other'}}) do
    r,s=runtimeFixture(true);check(r:openWheel());s.now=s.now+150;r:setBindingChoice(route,s.now);s.ctx[context[1]]=context[2]
    check(not r:commitWheel());eq(#s.started,0)
end
r,s=runtimeFixture(true);check(r:openWheel());s.now=s.now+150;r:setBindingChoice(entries[6],s.now)
check(r:commitWheel());eq(#s.started,0);eq(#s.navigated,1)
-- A self-only binding can be chosen with no target; a targeted one cannot.
r,s=runtimeFixture();s.valid=false;check(r:openWheel());s.now=s.now+150;r:setBindingChoice(route,s.now)
check(not r:commitWheel());eq(#s.started,0)
r,s=runtimeFixture();s.valid=false;check(r:openWheel());s.now=s.now+150
r:setBindingChoice({kind='binding',id=7,category='citizen'},s.now);check(r:commitWheel());eq(#s.started,1);eq(s.started[1].target,nil)

-- A brief visit cannot accrue hover time outside the root sector or behind HUD.
local layout=wheel.layout(1280,720,4);local middle=-math.pi/2+layout.step/2
local dx,dy=math.cos(middle)*130*layout.scale,math.sin(middle)*130*layout.scale
for _,leave in ipairs({'bridge','hud','invalid','gap','outside','center'}) do
    local nav={};wheel.hover(nav,cat,layout,dx,dy,1000,false,true)
    if leave=='bridge' then wheel.hover(nav,cat,layout,dx/130*183,dy/130*183,1050,false,true)
    elseif leave=='hud' then wheel.hover(nav,cat,layout,dx,dy,1050,true,true)
    elseif leave=='invalid' then wheel.hover(nav,cat,layout,0/0,dy,1050,false,true)
    elseif leave=='gap' then wheel.hover(nav,cat,layout,0,-130*layout.scale,1050,false,true)
    elseif leave=='outside' then wheel.hover(nav,cat,layout,layout.outer+1,0,1050,false,true)
    else wheel.hover(nav,cat,layout,0,0,1050,false,true) end
    eq(nav.candidate,nil,leave)
    wheel.hover(nav,cat,layout,dx,dy,1300,false,true);eq(nav.active,nil,leave)
    wheel.hover(nav,cat,layout,dx,dy,1410,false,true);eq(nav.active,1,leave)
end
local nav={};wheel.hover(nav,cat,layout,dx,dy,1000,false,true)
wheel.hover(nav,cat,layout,dx,dy,500,false,true);eq(nav.active,nil)
wheel.hover(nav,cat,layout,dx,dy,611,false,true);eq(nav.active,1)
-- Callback failures consume the wheel exactly once without escaping into main().
for _,broken in ipairs({'wheelRevision','startWheelBinding','wheelNavigate'}) do
    r,s=runtimeFixture(true);check(r:openWheel());s.now=s.now+150
    r:setBindingChoice(broken=='wheelNavigate' and entries[6] or route,s.now)
    r.env[broken]=function()error('injected adapter failure')end
    local ok,result=pcall(r.commitWheel,r);check(ok);eq(result,false);eq(r.wheel,nil)
    eq(#s.started,0);eq(#s.navigated,0)
end

local model=require 'pa26_bindings'
local prefs=require 'pa26_preferences'
local module=require 'pa26_patrol'
local function fixture()
    local s={now=1000,cfg=prefs.patrolDefaults(),calls={},state={session='test',ped=1,demo=false,onDuty=true,radioEnabled=true,
        alive=true,focused=true,paused=false,blocked=false,typing=false,recording=false,editingHud=false,draggingHud=false}}
    s.cfg.enabled=true;s.cfg.police_interval_ms=60000
    local c=module.new({settings=function()return s.cfg end,pending=function()return s.pending end,
        dispatch=function(kind,confirmation)s.calls[#s.calls+1]={kind,confirmation};return s.accepted~=false,s.error end})
    function s.tick(ms)s.now=s.now+(ms or 1000);c:tick(model.copy(s.state),s.now)end
    function s.advance(ms)for i=1,ms/1000 do s.tick(1000)end end
    s.tick(0);return c,s
end
local c,s=fixture();eq(c.remaining,60000);s.advance(59000);eq(#s.calls,0);eq(c:view().status,'До доклада: 00:01')
s.tick(1000);eq(#s.calls,1);eq(s.calls[1][1],'police');check(s.calls[1][2]);eq(c.remaining,60000)
s.pending={kind='police'};s.tick();eq(c:view().phase,'confirmation');eq(#s.calls,1)
s.pending=nil;s.advance(58000);eq(#s.calls,1);s.tick();eq(#s.calls,2)
for _,key in ipairs({'blocked','typing','recording','editingHud','draggingHud','paused','focused'})do
    c,s=fixture();s.advance(20000);s.state[key]=key~='focused';s.tick();local remaining=c.remaining
    s.advance(60000);eq(c.remaining,remaining,key);eq(#s.calls,0)
    s.state[key]=key=='focused';s.tick();eq(#s.calls,0);s.advance(remaining);eq(#s.calls,1)
end
c,s=fixture();s.state.busy='binder';s.advance(120000);eq(#s.calls,0);eq(c:view().phase,'waiting')
s.state.busy=nil;s.tick();eq(#s.calls,1);s.tick();eq(#s.calls,1,'no catch-up burst')
c,s=fixture();s.tick(600000);eq(#s.calls,0);eq(c.remaining,60000,'stalled client must not catch up')
c,s=fixture();s.advance(30000);s.state.session='other';s.tick();eq(c.remaining,60000);eq(#s.calls,0)
s.cfg.mode='prison';s.cfg.prison_interval_ms=60000;s.cfg.confirmation=false;s.tick();s.advance(60000)
eq(s.calls[1][1],'prison');eq(s.calls[1][2],false)
c,s=fixture();s.accepted=false;s.error='Нет поста';s.advance(60000);eq(#s.calls,1);check(c:view().status:find('настройки',1,true))
s.advance(59000);eq(#s.calls,1);s.cfg.police_template='Новое';s.tick();eq(c.remaining,60000)
c,s=fixture();s.cfg.enabled=false;s.tick();check(not c:view().visible);s.cfg.enabled=true;s.tick();eq(c.remaining,60000)
c,s=fixture();s.now=4294967280;c:reset();s.tick(0);s.now=0;c:tick(s.state,s.now);eq(c.remaining,59984)

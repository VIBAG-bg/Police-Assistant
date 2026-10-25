local module=require 'pa26_weapons'
local prefs=require 'pa26_preferences'
local model=require 'pa26_bindings'
local function setup()
    local s={now=1000,cfg=prefs.weaponDefaults(),plans={},state={session='erp',ped=1,alive=true,focused=true,paused=false,
        blocked=false,typing=false,recording=false,editingHud=false,draggingHud=false,onDuty=true,demo=false,weapon=0}}
    s.cfg.enabled=true
    local w=module.new({settings=function()return s.cfg end,codec=codec,start=function(plan)s.plans[#s.plans+1]=plan;return true end})
    function s.tick(ms)s.now=s.now+(ms or 16);w:tick(model.copy(s.state),s.now)end
    function s.draw(id)s.state.weapon=id;s.tick();s.tick(5000);check(w:validPlan(s.plans[#s.plans]));w:onExecution('sent_line',{plan=s.plans[#s.plans]})end
    s.tick();return w,s
end
local w,s=setup();s.draw(31);check(w.drawn);s.state.weapon=0;s.tick();s.tick(1499);eq(#s.plans,1)
s.tick(1);eq(#s.plans,2);eq(s.plans[2].automatic.kind,'weapon_holster');check(s.plans[2].lines[1]:find('на предохранитель',1,true));check(w:validPlan(s.plans[2]))
s.tick(10000);eq(#s.plans,2,'Holster is a single event')
w,s=setup();s.state.weapon=31;s.tick();s.tick(1000);s.state.weapon=0;s.tick();s.tick(5000);eq(#s.plans,0,'Never holster a draw that was never delivered')
w,s=setup();s.draw(24);s.state.weapon=0;s.tick();s.tick(1000);s.state.weapon=24;s.tick();s.tick(2000);eq(#s.plans,1,'Fast return cancels stale holster')
w,s=setup();s.draw(17);s.state.weapon=0;s.tick();s.tick(2000);eq(#s.plans,1,'A thrown grenade is not narrated as returned to the belt')
w,s=setup();s.draw(31);s.state.weapon=0;s.tick();s.cfg.holster_enabled=false;s.tick(2000);eq(#s.plans,1)
w,s=setup();s.draw(31);s.state.weapon=0;s.tick();s.tick(1500);local plan=s.plans[2];s.state.weapon=31;s.tick();check(not w:validPlan(plan),'Selecting the old weapon invalidates its queued holster')
w,s=setup();s.state.weapon=24;s.tick();s.state.taserActive=true;s.state.taserRoleItem={name='Taser X26',template='достаёт {weapon}',holster_enabled=true,holster_template='убирает {weapon}'}
s.tick();s.tick(5000);check(s.plans[1].lines[1]:find('Taser X26',1,true));w:onExecution('sent_line',{plan=s.plans[1]})
s.state.taserActive=false;s.tick();s.tick(1500);check(s.plans[2].lines[1]:find('Taser X26',1,true))
w,s=setup();s.draw(31);s.state.weapon=0;s.tick();s.tick(1500);plan=s.plans[2];s.cfg.items['31'].holster_enabled=false;check(not w:validPlan(plan),'Disabling an individual weapon invalidates its queued holster')

local module=require 'pa26_taser'
local prefs=require 'pa26_preferences'
local model=require 'pa26_bindings'
local function setup()
    local s={now=1000,cfg=prefs.taserDefaults(),plans={},state={session='erp',ped=1,alive=true,focused=true,paused=false,
        blocked=false,typing=false,recording=false,editingHud=false,draggingHud=false,onDuty=true,demo=false,weapon=24}}
    local t=module.new({settings=function()return s.cfg end,codec=codec,observed=function()return true end,start=function(plan)s.plans[#s.plans+1]=plan;return true end})
    function s.tick(ms)s.now=s.now+(ms or 16);t:tick(model.copy(s.state),s.now)end
    s.tick();return t,s
end
local t,s=setup();eq(s.cfg.weapon_id,24);eq(s.cfg.command,'/taser');check(not t:activeFor());check(not t:bullet({weaponId=24}));check(not t:view().ready)
check(not t:command('/tazer'));check(t:command('/taser'));s.tick();eq(t.mode,'unknown');check(not t:bullet({weaponId=24}),'A command attempt is not a success response')
s.tick(10001);check(not t:activeFor());check(not t.pendingMode)
check(t:confirmMode(true));s.tick();check(t:activeFor());eq(t.modeSource,'manual');check(t:bullet({weaponId=24}));s.tick();eq(t.shots,1)
check(t:confirmMode(false));s.tick();check(not t:bullet({weaponId=24}));eq(t.shots,1)
check(t:confirmMode(true));s.tick();eq(t.shots,1,'Mode switches cannot refill RP charges')
s.tick(5000);check(t:bullet({weaponId=24}));s.tick();check(t.queued);eq(#s.plans,1)
t,s=setup();s.cfg.active_reply='Тайзер включён';s.cfg.inactive_reply='Тайзер выключен'
check(not t:serverMessage('Тайзер включён'),'Unsolicited reply cannot activate the mode')
check(t:command('/taser'));check(t:serverMessage('{FFFFFF}Тайзер включён'));s.tick();check(t:activeFor());eq(t.modeSource,'server')
check(t:command('/taser'));s.tick();check(t:serverMessage('Тайзер выключен'));s.tick();check(not t:activeFor())
t,s=setup();s.state.weapon=23;s.tick();check(not t:command('/taser'));check(not t:bullet({weaponId=23}))
t,s=setup();check(t:confirmMode(true));s.state.session='another';s.tick();check(not t:activeFor(),'Old manual consent cannot cross a connection')
t,s=setup();check(t:command('/taser'));s.state.alive=false;s.tick();s.state.alive=true;s.tick();check(not t:activeFor())
local legacy=assert(prefs.validateTaser({enabled=true,weapon_id=23}));eq(legacy.activation,'weapon');eq(legacy.weapon_id,23)
eq(legacy.command,'/tazer','Legacy normalization is preserved until the explicit GUI update')
local saved=model.copy(prefs.taserDefaults());saved.command='/tazer';eq(assert(prefs.validateTaser(saved)).command,'/tazer')
for _,key in ipairs({'command','name','draw_template','active_reply'})do local c=prefs.taserDefaults();c[key]='bad\n/r injected';check(not prefs.validateTaser(c),key)end

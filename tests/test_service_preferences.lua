local core=require 'pa26_core'
local model=require 'pa26_bindings'
local prefs=require 'pa26_preferences'
local old=model.defaults(core.defaults());old.alerts.patrol=nil;old.weapons=nil;old.taser=nil
old.settings.wheel_enabled=nil;old.settings.interaction_notices=nil
old.alerts.shots_channel=nil;old.alerts.sos_channel=nil;old.alerts.code0_channel=nil
old.alerts.channel='/d';old.profile.callsign='P-7';old.bindings[1].script='Личный текст'
local migrated,err=model.validate(old,core.defaults());check(migrated,err)
eq(migrated.alerts.channel,'/d');eq(migrated.alerts.shots_channel,'');eq(migrated.profile.callsign,'P-7')
eq(migrated.bindings[1].script,'Личный текст');check(not migrated.alerts.patrol.enabled);check(not migrated.weapons.enabled)
check(migrated.taser.enabled and migrated.taser.auto_reload);eq(migrated.taser.cooldown_ms,5000)
eq(prefs.weaponName(migrated.weapons,23),'SD Pistol');eq(#prefs.weaponCatalog,43)
local round=model.validate(TEST_JSON_DECODE(TEST_JSON_ENCODE(migrated)),core.defaults());check(round)
eq(round.weapons.items['17'].name,'Газовая граната');eq(round.taser.weapon_id,24);eq(round.taser.activation,'command')
for _,spec in ipairs({{'enabled',1},{'mode','both'},{'confirmation','yes'},{'post','bad\npost'},
    {'police_interval_ms',999},{'prison_interval_ms',math.huge},{'prison_channel','/rn'},
    {'police_template','/r text'},{'police_template','{select_id}'},{'prison_template','{bad}'}})do
    local cfg=prefs.patrolDefaults();cfg[spec[1]]=spec[2];check(not prefs.validatePatrol(cfg),spec[1])
end
for _,spec in ipairs({{'shots_enabled',1},{'auto_code0',1},{'code0_health',0/0},{'code0_health',51},
    {'code0_template','{select_nick}'},{'shots_channel','/rn'},{'sos_channel','/d\n/r'}})do
    local cfg=model.alertDefaults();cfg[spec[1]]=spec[2];check(not model.validateAlerts(cfg),spec[1])
end
for _,spec in ipairs({{'delay_ms',999},{'cooldown_ms',999}})do local cfg=prefs.weaponDefaults();cfg[spec[1]]=spec[2];check(not prefs.validateWeapons(cfg))end
local oneSecond=prefs.weaponDefaults();oneSecond.delay_ms=1000;check(prefs.validateWeapons(oneSecond));eq(prefs.weaponDefaults().delay_ms,5000)
local cfg=prefs.weaponDefaults();cfg.items['99']={enabled=true,name='X',template='X'};check(not prefs.validateWeapons(cfg))
for _,value in ipairs({'/me bad','@wait(5)','{select_id}','broken\nline','{weapon}{unknown}'})do
    cfg=prefs.weaponDefaults();cfg.items['23'].template=value;check(not prefs.validateWeapons(cfg))
end
cfg=prefs.weaponDefaults();cfg.items['17'].name='Дымовая граната';cfg.items['17'].template='берёт «{weapon}» в руку'
cfg=prefs.validateWeapons(cfg);check(cfg);eq(prefs.weaponName(cfg,17),'Дымовая граната')
for _,spec in ipairs({{'enabled',1},{'weapon_id',0},{'weapon_id',23.5},{'cooldown_ms',999},{'reload_template','/taser'},
    {'reload_template','x\n/me y'},{'reload_template','{id}'}})do
    local cfg=prefs.taserDefaults();cfg[spec[1]]=spec[2];check(not prefs.validateTaser(cfg),spec[1])
end
local cfg=model.alertDefaults();cfg.shots_template='{callsign} {my_name} {department} {rank} {area}';check(model.validateAlerts(cfg))

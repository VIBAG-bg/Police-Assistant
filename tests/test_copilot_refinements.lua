local core=require 'pa26_core';local fixture=require 'support.fixture'
for _,res in ipairs({{1280,720},{1920,1080}})do
 local s=fixture({demo=false,nearby=false,legacyWanted=true});s.aimed=false;s.io.DisplaySize.x=res[1];s.io.DisplaySize.y=res[2]
 s.sx=res[1]/2;s.sy=res[2]/2;s.liveAction();s.step(1500);s.step(1500);eq(s.sent[#s.sent].line,'/wanted 37','Window-pixel camera selection')
 eq(core.cameraScore(res[1]*.53,res[2]*.4,res[1],res[2],res[1]*.53,res[2]*.4),0)
 check(not core.cameraScore(res[1]*.53,res[2]*.4,res[1],res[2]),'Single centre, not two simultaneous anchors')
end
-- Firearm damage is remembered even outside any vehicle situation.
do
 local cfg=require('pa26_preferences').taserDefaults();cfg.enabled=true;cfg.hud=true;cfg.activation='weapon';cfg.auto_reload=false
 local t=require('pa26_taser').new({settings=function()return cfg end,observed=function()return true end})
 local s={session='s',ped=1,alive=true,focused=true,paused=false,blocked=false,onDuty=true,weapon=cfg.weapon_id,demo=false,
  taserCombatEnabled=true,taserCombatMs=10000,taserCombatTemplate='Моё предупреждение о перестрелке.'}
 t:tick(s,1000);t:damage(24);t:tick(s,1500);eq(t:combatWarning(),s.taserCombatTemplate);eq(t:view().combatWarning,s.taserCombatTemplate)
 t:tick(s,12000);check(not t:combatWarning());t:damage(3);t:tick(s,12500);check(not t:combatWarning())
end
for _,case in ipairs({'own','other','wall'})do
 local s=fixture({demo=false,nearby=false,legacyWanted=true});s.aimed=false;s.clear=false;s.collision=case=='other'and 60 or 50;s.targetCarHandle=50;s.worldClear=case~='wall'
 s.actors={[99]={id=37,name='Target_Player',x=0,y=5,z=0,vehicle=true,sx=640,sy=360}}
 s.liveAction();s.step(1500);s.step(1500)
 if case=='own'then eq(s.sent[#s.sent].line,'/wanted 37')else eq(#s.sent,0,case..' must block selection')end
end
local settings=require 'pa26_vehicle_settings';local fresh=settings.defaults();check(fresh.enabled);check(fresh.megaphone_enabled);check(not fresh.require_patrol)
local old=require('pa26_bindings').copy(fresh);old.enabled=false;old.megaphone_enabled=false;old.require_patrol=true
local normalized=assert(settings.validate(old));check(not normalized.enabled);check(not normalized.megaphone_enabled);check(normalized.require_patrol)
local manual=require 'pa26_manual_actions';local lib=require('pa26_bindings').defaults(core.defaults())
lib.settings.manual_actions.frisk_mode='primary';check(manual.rule(lib,'frisk').rp:find('без перчаток',1,true));check(not manual.source(lib,'frisk'))
lib.settings.manual_actions.frisk_mode='full';check(manual.rule(lib,'frisk').rp:find('зип',1,true));check(manual.validate(lib.settings.manual_actions))
local warnings=require('pa26_server_commands').bindingWarnings({script='/blacklist 37\n/unblacklist 37'});eq(#warnings,2)

for _,res in ipairs({{1280,720},{1920,1080}})do
 for _,mode in ipairs({53,55,4})do
  local s=fixture({demo=false,nearby=false,legacyWanted=true});s.aimed=false;s.io.DisplaySize.x=res[1];s.io.DisplaySize.y=res[2];s.sx=res[1]*.53;s.sy=res[2]*.40;s.aimControl=true
  s.step();s.events.onSendAimSync({camMode=mode});s.liveAction();s.step(1500);s.step(1500)
  if mode==53 or mode==55 then check(#s.sent>0,'Fresh third-person anchor')else eq(#s.sent,0,'A fresh non-aim mode must remove the offset anchor')end
 end
end

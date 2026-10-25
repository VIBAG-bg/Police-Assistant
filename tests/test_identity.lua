local module=require 'pa26_identity'
local shared=require 'pa26_patrol_settings'
local function fixture()
    local s={now=1000,stamp=1,cfg=module.defaults(),target={id=37,ped=99,name='Player_Name'},
        state={session='erp',ped=1,alive=true,demo=false,local_nick='Officer_One'}}
    local c=module.new({settings=function()return s.cfg end})
    function s.tick(ms)s.now=s.now+(ms or 0);c:tick(s.state,s.target,s.stamp,s.now)end
    function s.patch(p)local v=c:view();check(c:update(p,v.key,v.record.nonce));s.tick(0)end
    s.tick();return c,s
end
check(module.validate(nil));check(not module.validate(false))
for _,n in ipairs({false,-1,1,0/0,86400001})do check(not module.validate({expiry_ms=n}))end
check(module.validate({expiry_ms=0}));check(module.validate({expiry_ms=60000}))
local c,s=fixture();local v=c:view();eq(v.record.passport_seen,'unknown');eq(v.record.mask,'unknown');eq(v.record.ic_name,'');eq(v.record.source,'manual')
check(not c:subject(s.target,s.stamp),'Nickname is never an IC name')
check(c:update({ic_name='John Smith'},v.key,v.record.nonce));eq(c:view().record.ic_name,'','GUI writes are queued until main tick')
s.tick();eq(c:view().record.ic_name,'John Smith');check(not c:subject(s.target,s.stamp),'An unacknowledged typed name is not passport evidence')
s.patch({passport_seen='yes',passport_number='123456'});local subject,source=c:subject(s.target,s.stamp)
eq(subject,'John Smith');check(source:find('вручную',1,true));eq(c:view().record.mask,'unknown','Passport cannot detect a mask')
s.patch({appearance='Синяя куртка,\nчёрные брюки',passport_seen='no'});eq(c:subject(s.target,s.stamp),'Синяя куртка, чёрные брюки')
local before=c:view();check(not c:update({mask='maybe'},before.key,before.record.nonce));check(not c:update({ic_name='Wrong',injected='bad'},before.key,before.record.nonce));eq(c:view().record.ic_name,'John Smith')
check(not c:update({ic_name='name\n/r injected'},before.key,before.record.nonce));check(not c:update({ic_name='\255'},before.key,before.record.nonce))
local external=c:view();external.record.ic_name='Edited outside';eq(c:view().record.ic_name,'John Smith')
-- Editing phone evidence never renews the separate passport proof.
c,s=fixture();s.cfg.expiry_ms=60000;s.patch({passport_seen='yes',ic_name='John Smith'});s.tick(30000)
s.patch({phone_known='yes',phone_number='555123',phone_source='Сообщил в разговоре'});s.tick(30000)
eq(c:view().record.passport_seen,'unknown');eq(c:view().record.ic_name,'');eq(c:view().record.phone_number,'555123')
s.tick(30000);eq(c:view().record.phone_known,'unknown');eq(c:view().record.phone_number,'')
c,s=fixture();s.cfg.expiry_ms=0;s.patch({passport_seen='yes',ic_name='John Smith'});s.tick(1800001);eq(c:view().record.passport_seen,'yes')
-- Default switching drops old facts; explicitly retained records get a new form nonce.
c,s=fixture();s.patch({passport_seen='yes',ic_name='John Smith'});local old=c:view()
s.target={id=38,ped=100,name='Other_Player'};s.stamp=2;s.tick();eq(c:view().record.passport_seen,'unknown')
check(not c:update({ic_name='Wrong'},old.key,old.record.nonce));s.target=old.record.target;s.stamp=3;s.tick();eq(c:view().record.passport_seen,'unknown')
c,s=fixture();s.cfg.retain_after_switch=true;s.patch({passport_seen='yes',ic_name='John Smith'});old=c:view()
s.target={id=38,ped=100,name='Other_Player'};s.stamp=2;s.tick();s.target=old.record.target;s.stamp=3;s.tick()
eq(c:view().record.ic_name,'John Smith');check(c:view().record.nonce~=old.record.nonce);check(not c:update({ic_name='stale'},old.key,old.record.nonce))
check(not c:subject(s.target,1));eq(c:subject(s.target,3),'John Smith')
-- Even identical native handles/names after a quit/join cannot revive evidence.
c:playerChanged(37);s.tick();eq(c:view().record.passport_seen,'unknown');eq(c:view().record.ic_name,'')
c,s=fixture();s.patch({ic_name='John Smith',passport_seen='yes'});s.stamp=2;s.tick();eq(c:view().record.passport_seen,'unknown')
c,s=fixture();v=c:view();check(c:update({mask='yes'},v.key,v.record.nonce));c:playerChanged(100);s.tick();eq(c:view().record.mask,'yes','Unrelated join cannot discard this edit')
-- Every life/server/player/mode boundary invalidates manual facts.
for _,field in ipairs({'session','ped','local_nick','alive','demo'})do
    c,s=fixture();s.patch({passport_seen='yes',ic_name='John Smith'})
    if field=='alive'then s.state.alive=false elseif field=='demo'then s.state.demo=true else s.state[field]='other'end
    s.tick();check(not c:view().record or c:view().record.passport_seen=='unknown',field)
end
c,s=fixture();s.patch({mask='yes'});s.cfg.enabled=false;s.tick();check(not c:view().record);s.cfg.enabled=true;s.tick();eq(c:view().record.mask,'unknown')
c,s=fixture();s.patch({ic_name='John Smith'});old=c:view();check(c:forget(old.key,old.record.nonce));eq(c:view().record.ic_name,'')
-- Bounded memory, monotonic/wrapped timer and independent editor ownership.
c,s=fixture();s.cfg.retain_after_switch=true
for i=1,40 do s.target={id=i,ped=i+100,name='Player_'..i};s.stamp=i;s.tick();s.patch({appearance='Человек '..i})end
local count=0;for _ in pairs(c.records)do count=count+1 end;eq(count,16);eq(c:view().record.target.id,40)
c,s=fixture();s.now=4294967280;s.tick();s.patch({mask='yes'});s.now=16;c:tick(s.state,s.target,s.stamp,s.now);eq(c:view().record.mask,'yes')
c,s=fixture();v=c:view();local display=v.record.display_revision;s.patch({ic_name='John Smith'});eq(c:view().record.display_revision,display,'Typing must not recreate an input buffer')

local module=require 'pa26_identity'
local shared=require 'pa26_patrol_settings'
local function setup()
    local s={now=1000,cfg=module.defaults(),target={id=37,name='Rafayel_Barvello',ped=99},stamp=1,
        state={session='185.207.214.114:7777',ped=1,alive=true,demo=false,local_nick='Victor_Auditore'}}
    local c=module.new({settings=function()return s.cfg end,resolvePassport=function(name,distance)eq(distance,30);return s.available~=false and name==s.target.name and shared.copy(s.target)or nil end})
    function s.tick(ms)s.now=s.now+(ms or 16);c:tick(s.state,s.selected,s.stamp,s.now)end
    s.tick();return c,s
end
local phrase='Rafayel_Barvello достал паспорт и показал его Victor_Auditore'
local c,s=setup();check(c:serverMessage(phrase));check(not c:view().record);s.tick();s.selected=s.target;s.tick()
local r=c:view().record;eq(r.passport_seen,'yes');eq(r.passport_source,'server');eq(r.ic_name,'');eq(r.passport_number,'');eq(r.mask,'unknown')
check(not c:subject(s.target,s.stamp),'A nickname is not silently converted into passport data')
local v=c:view();check(c:update({ic_name='Rafayel Barvello'},v.key,v.record.nonce));s.tick();eq(c:subject(s.target,s.stamp),'Rafayel Barvello')
for _,line in ipairs({'Victor_Auditore достал паспорт и показал его Rafayel_Barvello',
    'Rafayel_Barvello достал паспорт и показал его Other_Player','[OOC] '..phrase,'/me '..phrase,
    'Rafayel_Barvello хочет показать паспорт Victor_Auditore',phrase..'\n/r injected'})do
    c,s=setup();check(not c:serverMessage(line),line)
end
c,s=setup();check(c:serverMessage('{FFFFFF}[ME] '..phrase));s.available=false;s.tick();s.selected=s.target;s.tick();eq(c:view().record.passport_seen,'unknown')
c,s=setup();check(c:serverMessage(phrase));c:playerChanged(37);s.tick();s.selected=s.target;s.tick();eq(c:view().record.passport_seen,'unknown')
c,s=setup();s.cfg.passport_server='185.207.214.114:7777';s.state.session='other';s.tick();check(not c:serverMessage(phrase))
c,s=setup();s.cfg.passport_chat=false;check(not c:serverMessage(phrase))
c,s=setup();check(c:serverMessage(phrase));s.tick(5001);s.selected=s.target;s.tick();eq(c:view().record.passport_seen,'unknown')
c,s=setup();s.cfg.expiry_ms=60000;check(c:serverMessage(phrase));s.tick();s.selected=s.target;s.tick();eq(c:view().record.passport_seen,'yes')
s.tick(60000);eq(c:view().record.passport_seen,'unknown')
c,s=setup();check(c:serverMessage(phrase));s.tick();s.selected=s.target;s.tick();v=c:view();check(c:forget(v.key,v.record.nonce));s.tick();eq(c:view().record.passport_seen,'unknown')
c,s=setup();check(c:serverMessage(phrase));s.tick();s.selected=s.target;s.tick();s.stamp=s.stamp+1;s.tick();eq(c:view().record.passport_seen,'yes','Same-instance proof survives a target display revision')
v=c:view();check(c:update({passport_seen='no'},v.key,v.record.nonce));s.tick();s.stamp=s.stamp+1;s.tick();check(c:view().record.passport_seen~='yes','Manual rejection supersedes cached automatic proof')

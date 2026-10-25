local identity=require 'pa26_identity';local copy=require('pa26_patrol_settings').copy
local cfg=identity.defaults();cfg.expiry_ms=60000
local target={id=37,name='Remote_Player',ped=99}
local state={session='test',ped=1,alive=true,demo=false,local_nick='Local_Officer'}
local now=1000;local selected;local available=true
local c=identity.new({settings=function()return cfg end,
    resolvePassport=function(name)return available and name==target.name and copy(target)or nil end})
local function tick(ms)now=now+(ms or 16);c:tick(state,selected,1,now)end
local function signal()check(c:serverMessage('Remote_Player '..cfg.passport_phrase..' Local_Officer'));tick()end
tick();signal();local r=assert(c:wantedRecord({id=37,name='Remote_Player',account=true}));eq(r.passport_seen,'yes');eq(r.passport_source,'server')
local version=r.version;available=false;selected=nil;tick();eq(c:wantedRecord(target).version,version,'Walking away must preserve the observed passport')
selected={id=38,name='Other_Player',ped=100};tick();eq(c:wantedRecord(target).passport_seen,'yes','Changing physical interaction must not discard a passport already shown')
check(not c:wantedRecord({id=37,name='Other_Player'}));check(not c:wantedRecord({id=38,name='Remote_Player'}))
tick(60000);eq(c:wantedRecord(target).passport_seen,'unknown','Passport expires independently of subject distance')
available=true;signal();c:playerChanged(37);check(not c:wantedRecord(target),'Quit/join invalidates passport even with the same nickname')
signal();state.alive=false;tick();check(not c:wantedRecord(target));state.alive=true;tick();check(not c:wantedRecord(target))
signal();state.session='other';tick();check(not c:wantedRecord(target))
signal();cfg.passport_chat=false;check(c:wantedRecord(target).passport_seen~='yes');cfg.passport_chat=true
selected=target;tick();local v=c:view();check(v.record);check(c:forget(v.key,v.record.nonce));check(not c:wantedRecord(target))
tick();v=c:view();check(c:update({passport_seen='yes',ic_name='Личное имя',appearance='высокий'},v.key,v.record.nonce));tick()
r=c:wantedRecord(target);eq(r.passport_seen,'yes');eq(r.ic_name,'Личное имя');eq(r.appearance,'высокий')
selected=nil;tick();eq(c:wantedRecord(target).ic_name,'Личное имя')
cfg.enabled=false;check(not c:wantedRecord(target));tick();cfg.enabled=true;tick();check(not c:wantedRecord(target))

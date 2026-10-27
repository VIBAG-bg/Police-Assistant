local m=require 'pa26_author_presets';local model=require 'pa26_bindings';local core=require 'pa26_core';local users=require 'pa26_user_files';local store=require 'pa26_author_store'
local root='.'
local function read(name)local f=assert(io.open(root..'/presets/'..name,'rb'));local s=f:read('*a');f:close();return s end
local json={encode=function(v)return TEST_JSON_ENCODE(v)end,decode=function(v)return TEST_JSON_DECODE(v)end}
local binds=assert(m.decode('binds',read('pa-binds.json'),json));eq(#binds.bindings,83)
local settings=assert(m.decode('settings',read('pa-settings.json'),json))
local baseline=TEST_JSON_DECODE(read('baseline.json'));eq(#baseline.notes.notes,2)
eq(settings.settings.data.profile.name,'');eq(#settings.settings.data.partners,0)
local cfg=core.defaults();cfg.main.demo_mode=false
local lib=model.defaults(cfg);lib.profile.name='Private Officer';lib.notes[1].body='PRIVATE NOTE'
lib.settings.updates.repository='Private/Repo';lib.settings.wheel_names.citizen='MY WHEEL'
local a=assert(m.prepare('binds',binds,lib,cfg));eq(#a.library.bindings,83);check(m.equal(a.library.notes,lib.notes));check(m.equal(a.library.settings,lib.settings));eq(a.library.profile.name,'Private Officer')
local b=assert(m.prepare('settings',settings,lib,cfg));check(m.equal(b.library.bindings,lib.bindings));check(m.equal(b.library.notes,lib.notes));check(m.equal(b.library.profile,lib.profile));eq(b.library.settings.updates.repository,'Private/Repo');check(not b.config.main.demo_mode)
local demoCfg=model.copy(cfg);demoCfg.main.demo_mode=true;check(assert(m.prepare('settings',settings,lib,demoCfg)).config.main.demo_mode,'Applying settings preserves an explicit demo choice')
check(m.equal(b.library.settings.window_layout,settings.settings.data.settings.window_layout));check(m.equal(b.library.settings.wheel_names,settings.settings.data.settings.wheel_names))
check(not m.decode('binds','{bad',json));check(not m.decode('binds',read('pa-settings.json'),json));check(not m.decode('settings',read('pa-binds.json'),json));check(not m.decode('settings',string.rep('x',m.MAX_BYTES+1),json))
local tampered=model.copy(settings);tampered.inject='command';check(not m.decode('settings',json.encode(tampered),json))
local base='TEST/config/police_assistant_2026'
local function hash(s)local h=1;for i=1,#s do h=(h*31+s:byte(i))%2147483647 end;return string.format('%08x',h)..string.rep('0',56)end
local initial={[base..'.ini']=assert(require('pa26_config').serialize(cfg)),[base..'_settings.json']=json.encode(users.partition(lib).settings),[base..'_binds.json']=json.encode(users.partition(lib).binds),[base..'_notes.json']='PRIVATE NOTES BYTES'}
local function filesystem(original)
 local state={mem=model.copy(original),n=0};local fs={}
 local function op()state.n=state.n+1;if state.fail and state.n>=state.fail then error('power loss')end end
 function fs.exists(p)return state.mem[p]~=nil end
 function fs.read(p)return state.mem[p]end
 function fs.write(p,s)op();state.mem[p]=s;return true end
 function fs.remove(p)op();state.mem[p]=nil;return true end
 function fs.rename(a,b)op();if not state.mem[a]or state.mem[b]then return nil end;state.mem[b]=state.mem[a];state.mem[a]=nil;return true end
 return fs,state
end
local held=false;local function lock()if held then return end;held=true;return function()held=false end end
for _,prepared in ipairs({a,b})do
 local fs,state=filesystem(initial);local before=store.snapshot(base,prepared.kind,fs)
 local ok,why=store.apply(base,prepared,before,json,fs,hash,lock,string.rep('a',32));check(ok,why)
 eq(state.mem[base..'_notes.json'],initial[base..'_notes.json']);check(not held)
 if prepared.kind=='binds'then eq(state.mem[base..'_settings.json'],initial[base..'_settings.json']);eq(state.mem[base..'.ini'],initial[base..'.ini'])else eq(state.mem[base..'_binds.json'],initial[base..'_binds.json'])end
 check(not state.mem[base..'_preset_pending.json']);check(state.mem[base..'_preset_backup_'..string.rep('a',32)..'_'..(prepared.kind=='binds'and'binds'or'settings')..'.before'])
end
-- Interrupt every storage mutation, then restart against the same surviving bytes.
for fail=1,60 do
 local fs,state=filesystem(initial);local before=store.snapshot(base,'settings',fs);state.fail=fail
 store.apply(base,b,before,json,fs,hash,lock,string.format('%032x',fail));state.fail=nil
 local ok,why=store.recover(base,json,fs,hash,lock);check(ok,why);check(not held)
 local old=state.mem[base..'.ini']==initial[base..'.ini'] and state.mem[base..'_settings.json']==initial[base..'_settings.json']
 local new=state.mem[base..'.ini']==require('pa26_config').serialize(b.config) and m.equal(TEST_JSON_DECODE(state.mem[base..'_settings.json']),users.partition(b.library).settings)
 check(old or new,'restart must recover a complete old or new settings pair at '..fail)
 eq(state.mem[base..'_notes.json'],initial[base..'_notes.json']);eq(state.mem[base..'_binds.json'],initial[base..'_binds.json'])
end
local fs,state=filesystem(initial);local before=store.snapshot(base,'settings',fs);state.mem[base..'.ini']='EXTERNAL EDIT'
check(not store.apply(base,b,before,json,fs,hash,lock,string.rep('b',32)));eq(state.mem[base..'.ini'],'EXTERNAL EDIT')
held=true;check(not store.apply(base,a,store.snapshot(base,'binds',fs),json,fs,hash,lock,string.rep('c',32)));held=false
state.mem[base..'_preset_pending.json']='BROKEN JOURNAL';check(not store.recover(base,json,fs,hash,lock));eq(state.mem[base..'_notes.json'],'PRIVATE NOTES BYTES')
-- Download -> NO never writes, YES creates backup, acknowledgement precedes reload.
fs,state=filesystem(initial);local s={autosaves={},notices={}}
function s:hasModal()return self.authorPresetConfirm~=nil or self.warning end
function s:flushAutosave()end
function s:notify(text,scope,id,kind)self.notices[#self.notices+1]=text;self.warning=true end
local now=0;local fakeIO={};function fakeIO:start(kind)return{id=string.rep('d',32),kind=kind}end
function fakeIO:poll(job)return read(job.kind=='binds'and'pa-binds.json'or'pa-settings.json'),nil,'v0.40.3'end
local current=model.copy(lib);current.settings.updates.repository='Owner/Repo';local reloads=0
local w={base=base,library=current,userFiles={}}
local c=require('pa26_author_controller').new({studio=s,workspace=w,json=json,fs=fs,hash=hash,lock=lock,io=fakeIO,now=function()return now end,config=function()return cfg end,busy=function()return false end,callbacks={},reload=function()reloads=reloads+1 end,install=function(p)w.library=p.library end})
check(c:start('binds'));check(not c:start('settings'));now=1;c:tick();check(s.authorPresetConfirm);eq(state.mem[base..'_binds.json'],initial[base..'_binds.json'])
s.authorPresetConfirm=nil;check(not c:accept());eq(state.mem[base..'_binds.json'],initial[base..'_binds.json'])
check(c:start('binds'));c:tick();check(c:accept());c:tick();eq(reloads,0);check(s.warning);s.warning=false;c:tick();eq(reloads,1)
-- A different repository must never inherit a downloaded or displayed payload.
fs,state=filesystem(initial);s.warning=false;s.authorPresetConfirm=nil;s.dirty=true
c=require('pa26_author_controller').new({studio=s,workspace=w,json=json,fs=fs,hash=hash,lock=lock,io=fakeIO,now=function()return now end,config=function()return cfg end,busy=function()return false end,callbacks={}})
s.dirty=false;check(c:start('binds'));s.dirty=true;c:tick();check(c.ready);s.dirty=false
w.library.settings.updates.repository='Changed/Repo';c:tick();check(not c.ready);check(not s.authorPresetConfirm);eq(state.mem[base..'_binds.json'],initial[base..'_binds.json'])
s.warning=false;check(c:start('binds'));c:tick();check(s.authorPresetConfirm)
w.library.settings.updates.repository='Owner/Repo';check(not c:accept());eq(state.mem[base..'_binds.json'],initial[base..'_binds.json'])

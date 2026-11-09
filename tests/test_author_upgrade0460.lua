local core=require 'pa26_core'
local model=require 'pa26_bindings'
local author=require 'pa26_author_presets'
local config=require 'pa26_config'
local users=require 'pa26_user_files'
local store=require 'pa26_author_store'
local upgrade=require 'pa26_author_upgrade0460'
local bundle=require 'pa26_author_defaults0460'
local json={encode=function(v)return TEST_JSON_ENCODE(v)end,decode=function(v)return TEST_JSON_DECODE(v)end}
local f=assert(io.open('presets/baseline.json','rb'));local baseline=json.decode(f:read('*a'));f:close()
local cfg=core.normalizeConfig(baseline.config)
local lib=assert(users.combine(baseline,cfg))
local settings=assert(author.decode('settings',bundle.settings,json)).settings.data
local p,why=upgrade.prepare(lib,cfg,json);check(p,why)
eq(p.library.settings.opacity,settings.settings.opacity)
eq(p.library.settings.wheel_child_limit,15)
eq(p.library.settings.wheel_car_child_limit,15)
local items={};for i=1,20 do items[i]={id=i,name='Action '..i}end
for _,key in ipairs({'wheel_child_limit','wheel_car_child_limit'})do
 local entries=require('pa26_wheel').entries({items=items,id='custom',child_limit=p.library.settings[key]})
 eq(#entries,16);eq(entries[15].id,15);eq(entries[16].kind,'more')
end
eq(p.library.settings.accent_live_input,settings.settings.accent_live_input)
eq(p.library.vehicle.channel,settings.vehicle.channel)
eq(p.config.widget.x,json.decode(bundle.settings).config.widget.x)
check(p.library.settings.applied_author_defaults_0460)
check(not lib.settings.applied_author_defaults_0460)
local hasAuthor={};for _,b in ipairs(p.library.bindings)do if b.author_ref then hasAuthor[b.author_ref]=true end end
for _,b in ipairs(json.decode(bundle.binds).bindings)do check(hasAuthor[b.author_ref],b.author_ref)end

lib.profile.name='Personal Officer';lib.profile.gender='female';lib.profile.badge_number='MY-42'
lib.partners={{id=1,nickname='Known_Partner',callsign='Adam-77'}};lib.next_partner_id=2
lib.notes[1].body='PRIVATE NOTES — EXACT'
lib.settings.wheel_names.citizen='My Citizen Wheel'
lib.settings.wheel_order.root={'custom','citizen'};lib.settings.wheel_order.custom={'b:14'}
lib.settings.wheel_child_limit=12;lib.settings.wheel_car_child_limit=6
lib.settings.updates.repository='Another/Source'
lib.patrol_session.start_template='Мой личный доклад {unit}.'
lib.settings.manual_actions.rules.cuff.rp='/me применил личный сценарий.'
lib.settings.cef_chat_support=false
lib.alerts.on_duty=false
cfg.main.demo_mode=true
cfg.widget.x=444
local custom=model.newBinding(14);custom.script='/me личная отыгровка.';custom.favorite=true;custom.wheel_visible=true
custom.shortcut={key=0x75,ctrl=true,alt=false,shift=false};custom.command_alias='mine14'
lib.bindings[#lib.bindings+1]=custom;lib.next_id=15
lib=assert(model.validate(lib,cfg))
p,why=upgrade.prepare(lib,cfg,json);check(p,why)
eq(p.library.settings.opacity,settings.settings.opacity,'Author setting replaces stock only')
eq(p.library.settings.wheel_names.citizen,'My Citizen Wheel')
eq(p.library.settings.wheel_order.root[1],'custom');eq(p.library.settings.wheel_order.custom[1],'b:14')
eq(p.library.settings.wheel_child_limit,12);eq(p.library.settings.wheel_car_child_limit,15)
eq(p.library.settings.updates.repository,'Another/Source')
eq(p.library.settings.manual_actions.rules.cuff.rp,'/me применил личный сценарий.')
eq(p.library.patrol_session.start_template,'Мой личный доклад {unit}.')
eq(p.library.settings.cef_chat_support,false)
eq(p.library.alerts.on_duty,false)
eq(p.config.widget.x,444);check(p.config.main.demo_mode)
check(author.equal(model.find(lib,14),model.find(p.library,14)))
check(author.equal(p.library.profile,lib.profile));check(author.equal(p.library.partners,lib.partners));check(author.equal(p.library.notes,lib.notes))
local duplicate
for _,b in ipairs(p.library.bindings)do if b.author_ref=='A14' then duplicate=b end end
check(duplicate and duplicate.id~=14);check(not duplicate.skip_confirmation)
local explicit=assert(author.prepare('settings',json.decode(bundle.settings),p.library,p.config))
check(explicit.library.settings.applied_author_defaults_0460,'Voluntary settings import preserves completion marker')
check(not upgrade.prepare(lib,cfg,json,{binds='broken',settings=bundle.settings,baseline=bundle.baseline}))

local base='TEST/config/police_assistant_2026'
local parts=users.partition(lib)
local initial={[base..'.ini']=assert(config.serialize(cfg))}
for k,v in pairs(parts)do initial[base..'_'..k..'.json']=json.encode(v)end
local function memory()
 local values=model.copy(initial);local fs={};local state={n=0}
 local function write()state.n=state.n+1;if state.fail and state.n>=state.fail then error('simulated interrupt')end end
 function fs.exists(path)return values[path]~=nil end
 function fs.read(path)return values[path]end
 function fs.write(path,text)write();values[path]=text;return true end
 function fs.remove(path)write();values[path]=nil;return true end
 function fs.rename(old,new)write();if not values[old]or values[new]then return nil end;values[new]=values[old];values[old]=nil;return true end
 return fs,values,state
end
local function hash(s)
 local h=1;for i=1,#s do h=(h*31+s:byte(i))%2147483647 end
 return string.format('%08x',h)..string.rep('0',56)
end
local function lock()return function()end end
local id=string.rep('a',32);local function newId()return id end
local fs,values,state=memory()
local function workspaceFor(storage)
 local userFiles=users.new(base,json,cfg,storage)
 local loaded=userFiles:load()
 return {library=loaded,userFiles=userFiles,base=base,json=json}
end
local w=workspaceFor(fs)
local ok,backup,applied=upgrade.apply(w,cfg,{fs=fs},hash,lock,newId)
check(ok,backup);check(applied.library.settings.applied_author_defaults_0460)
eq(values[base..'_notes.json'],initial[base..'_notes.json'])
for key,old in pairs({binds='_binds.json',settings='_settings.json',config='.ini'})do eq(values[backup..'_'..key..'.before'],initial[base..old])end
local restarted=users.new(base,json,applied.config,fs)
local upgraded=restarted:load()
check(upgraded.settings.applied_author_defaults_0460)
check(author.equal(model.find(upgraded,14),model.find(lib,14)))
local writes=state.n
check(upgrade.apply({library=upgraded},applied.config,{fs=fs},hash,lock,newId))
eq(state.n,writes,'Second startup must not write anything')
fs,values,state=memory();w=workspaceFor(fs)
values[base..'_settings.json']='EXTERNAL EDIT'
check(not upgrade.apply(w,cfg,{fs=fs},hash,lock,newId));eq(values[base..'_settings.json'],'EXTERNAL EDIT');eq(state.n,0)
local prevVersion=core.VERSION;core.VERSION='0.46.1'
check(upgrade.apply(w,cfg,{fs=fs},hash,lock,newId));eq(state.n,0)
core.VERSION=prevVersion

for n=1,60 do
 fs,values,state=memory();state.fail=n
 store.apply(base,p,store.snapshot(base,p.kind,fs),json,fs,hash,lock,id)
 state.fail=nil
 local recovered,err=store.recover(base,json,fs,hash,lock);check(recovered,err)
 local b,settingsText,ini=values[base..'_binds.json'],values[base..'_settings.json'],values[base..'.ini']
 local previous=b==initial[base..'_binds.json'] and settingsText==initial[base..'_settings.json'] and ini==initial[base..'.ini']
 local newer=b and settingsText and author.equal(json.decode(b),users.partition(p.library).binds) and
  author.equal(json.decode(settingsText),users.partition(p.library).settings) and ini==config.serialize(p.config)
 check(previous or newer,'Recovered all three files from one transaction at '..n)
 eq(values[base..'_notes.json'],initial[base..'_notes.json'])
end

-- The normal main loop consumes a successful Status receipt. Typing defers
-- the one-time transaction and automatic script reload until the chat closes.
local fixture=require 'support.fixture'
local platform={ml='moonloader'}
function platform:gate()return false end
function platform:start(mode)
 eq(mode,'Status');return {id=id,mode=mode,root='virtual'}
end
function platform:poll()
 return json.encode({product='police-assistant-2026',moonloader=self.ml,phase='installed',
  message='update_installed',details={version='0.46.0'},job=id,receipt_seen=true})
end
local realPlatform,realIO=package.loaded.pa26_update_platform,package.loaded.pa26_author_io
package.loaded.pa26_update_platform={new=function()return platform end}
package.loaded.pa26_author_io={new=function()return {fs=require('pa26_library').fs} end,hash=hash,lock=lock,newId=newId}
local live=fixture({library=lib,demo=true,render=false})
local gameBase='moonloader\\config\\police_assistant_2026'
live.files[gameBase..'.ini']=assert(config.serialize(live.workspace.cfg))
local reloads=0;live.script.reload=function()reloads=reloads+1 end
live.chat=true
live.step();live.step(400)
eq(reloads,0);check(not live.savedLibrary().settings.applied_author_defaults_0460)
local exactNotes=live.files[gameBase..'_notes.json']
live.chat=false;live.step(400)
eq(reloads,1);check(live.savedLibrary().settings.applied_author_defaults_0460)
eq(live.files[gameBase..'_notes.json'],exactNotes);eq(#live.sent,0)
for _=1,3 do live.step(300)end
eq(reloads,1)
onScriptTerminate(live.script)
package.loaded.pa26_update_platform,package.loaded.pa26_author_io=realPlatform,realIO

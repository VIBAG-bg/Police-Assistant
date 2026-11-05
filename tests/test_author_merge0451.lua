local model=require 'pa26_bindings';local cfg=require('pa26_core').defaults();local author=require 'pa26_author_presets';local users=require 'pa26_user_files'
local f=assert(io.open('presets/pa-binds.json','rb'));local payload=TEST_JSON_DECODE(f:read('*a'));f:close()
local lib=assert(model.validate(model.defaults(cfg),cfg));lib.bindings={}
for _,b in pairs(require('pa26_author_rp').previous)do lib.bindings[#lib.bindings+1]=model.copy(b)end
table.sort(lib.bindings,function(a,b)return a.id<b.id end);lib.next_id=89;lib=assert(model.validate(lib,cfg))
lib.profile.name='Personal';lib.profile.badge_number='EPD-77';lib.settings.wheel_names.citizen='My wheel';lib.settings.wheel_order.root={'custom','citizen'}
local private=model.find(lib,14);private.script='/me моя сохранённая отыгровка.';private.favorite=true
private.shortcut={key=0x75,ctrl=true,alt=false,shift=false};local saved=model.copy(private)
model.find(lib,13).favorite=false;model.find(lib,13).wheel_group='custom'
local original=TEST_JSON_ENCODE(lib)
local p,why=author.prepare('binds',payload,lib,cfg);check(p,why)
eq(TEST_JSON_ENCODE(lib),original,'Prepare must not mutate source data')
eq(#p.library.bindings,84);check(author.equal(model.find(p.library,14),saved),'Personal fork preserved exactly')
eq(model.find(p.library,13).favorite,false);eq(model.find(p.library,13).wheel_group,'custom')
eq(p.library.profile.badge_number,'EPD-77');eq(p.library.settings.wheel_names.citizen,'My wheel');eq(p.library.settings.wheel_order.root[1],'custom')
local copy;for _,b in ipairs(p.library.bindings)do if b.author_ref=='A14'then copy=b end end
check(copy and copy.id~=14);check(copy.rp_context and copy.rp_context.vehicle=='traffic');check(not copy.skip_confirmation)
check(copy.command~=private.command or copy.command=='');check(copy.command_alias~=private.command_alias or copy.command_alias=='')
local again=assert(author.prepare('binds',payload,p.library,cfg));eq(#again.library.bindings,84,'Repeated update must not duplicate authored copies')
check(author.equal(again.library,p.library),'Repeated application is idempotent')
eq(users.partition(p.library).binds.schema,2,'Old clients must reject staged documents')
local exchanged=assert(users.decodeExchange(TEST_JSON_ENCODE(users.exchange(p.library,'binds',copy.id)),{encode=function(v)return TEST_JSON_ENCODE(v)end,decode=function(v)return TEST_JSON_DECODE(v)end},'binds'))
eq(exchanged.schema,2);check(exchanged.bindings[1].rp_context)
-- Full personal library: fail before any write or removal, with the original intact.
local full=assert(model.validate(model.defaults(cfg),cfg));full.bindings={};full.wheel={0,0,0,0,0,0};full.settings.wheel_car_classic={0,0,0,0,0,0}
for id=100,227 do local b=model.newBinding(id);b.script='Мой личный сценарий '..id;full.bindings[#full.bindings+1]=b end;full.next_id=228
local bytes=TEST_JSON_ENCODE(full);check(not author.prepare('binds',payload,full,cfg));eq(TEST_JSON_ENCODE(full),bytes)
-- Rebase author order after a conflicting personal ID remains occupied.
local order=require('pa26_author_rp').foot_order
local rebased=require('pa26_author_merge').rebaseOrder(order,p.library)
local found=false;for _,key in ipairs(rebased.citizen)do if key=='b:'..copy.id then found=true end;check(key~='b:14')end;check(found)

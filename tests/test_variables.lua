local core=require 'pa26_core'
local model=require 'pa26_bindings'
local binder=require 'pa26_binder'
local store=require 'pa26_library'
local files={}
store.fs={exists=function(p) return files[p]~=nil end,read=function(p) return files[p] end,
    write=function(p,v) files[p]=v; return true end,remove=function(p) files[p]=nil; return true end,
    rename=function(a,b) if not files[a] or files[b] then return nil end; files[b]=files[a]; files[a]=nil; return true end}
local target={id=37,ped=99,name='Visible_Person',distance=3}
local localValues={my_id='7',my_nick='Own_Officer',area='Ganton',map_square='M-13',location='Ganton, квадрат M-13',my_weapon='MP5',my_vehicle='GTA model 596',my_speed='12.5'}
local env={encodeJson=TEST_JSON_ENCODE,decodeJson=TEST_JSON_DECODE,context=function() return {session='test',focused=true,paused=false,blocked=false,window=false,alive=true} end,
    now=function() return 10000 end,demo=function() return false end,log=function() end,codec=codec,
    validate=function(t) return t end,acquire=function() return target end,nearby=function() return {target} end,
    readLocal=function() return localValues end,readPed=function() return {weapon='M4',vehicle='GTA model 597',speed='7.5'} end,
    send=function() return true end,lastSent=function() end,markSent=function() end}
local workspace=require 'pa26_workspace'.new(env,core.defaults(),'test-variables')
local profile=workspace.library.profile
profile.name='Profile Officer'; profile.my_plate='MY-123'; profile.select_plate='SEL-123'; profile.closest_plate='NEAR-123'
profile.callsign='P-12'; profile.city='Los Santos'; profile.square='A-3'
profile.local_tag='PD'; profile.global_tag='SAPD'; profile.prison_tag='DOC'; profile.department='SAPD'; profile.rank='Officer'; profile.accent='Без акцента'
workspace.library.partners={{id=1,nickname='Visible_Person',callsign='P-2'}}; workspace.library.next_partner_id=2
check(model.validate(workspace.library,core.defaults()))
local args={}; for i=1,8 do args['param'..i]='arg'..i end
local counts={}; local seen={}
for _,entry in ipairs(model.variables) do
    local name=entry[1]; check(not seen[name]); seen[name]=true
    local info=model.variableInfo(name)
    check(info and info.kind and info.source~='' and info.detail~='','metadata for '..name)
    counts[info.kind]=(counts[info.kind] or 0)+1
    local b=model.newBinding(7); b.script='{'..name..'}'
    local snapshot,err=workspace:snapshot(b,{})
    check(snapshot,name..': '..tostring(err))
    local plan; plan,err=binder.compile(b,snapshot,args,codec)
    check(plan,name..': '..tostring(err)); eq(#plan.lines,1); check(plan.lines[1]~='')
end
eq(#model.variables,63)
eq(counts.api,17); eq(counts.profile,12); eq(counts.derived,12); eq(counts.clock,7); eq(counts.team,6); eq(counts.argument,9)
local b=model.newBinding(7); b.script='{my_name} {my_firstname} {my_lastname}'
local snapshot=workspace:snapshot(b,{})
local plan=binder.compile(b,snapshot,{},codec); eq(plan.lines[1],'Profile Officer Profile Officer')

-- Empty/manual fields and unsupported API values remain unavailable, not invented.
for _,name in ipairs({'city','square','my_plate','select_plate','closest_plate'}) do
    profile[name]=''; b.script='{'..name..'}'; snapshot=workspace:snapshot(b,{})
    local err; plan,err=binder.compile(b,snapshot,{},codec)
    check(not plan); check(err:find('{'..name..'}',1,true))
end
localValues.my_weapon=nil; b.script='{my_weapon}'; snapshot=workspace:snapshot(b,{})
local err; plan,err=binder.compile(b,snapshot,{},codec)
check(not plan); check(err:find('{my_weapon}',1,true))
eq(model.variableInfo('invented'),nil)

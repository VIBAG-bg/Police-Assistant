local m=require 'pa26_bindings';local core=require 'pa26_core';local binder=require 'pa26_binder'
local author=require 'pa26_author_presets';local manual=require 'pa26_manual_actions'
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return TEST_JSON_DECODE(s)end
local oracle=read('docs/qa/0.45.1/AUTHOR_ORACLE.json');local binds=read('presets/pa-binds.json')
local cfg=core.defaults();local original=m.defaults(cfg)
original.bindings={};original.next_id=1;original.wheel={0,0,0,0,0,0};original.settings.wheel_car_classic={0,0,0,0,0,0}
local prepared=assert(author.prepare('binds',binds,original,cfg));local lib=prepared.library
eq(#lib.bindings,83);eq(lib.next_id,89)
local settings=read('presets/pa-settings.json');lib=assert(author.prepare('settings',settings,lib,cfg)).library
local values={};for _,v in ipairs(m.variables)do values[v[1]]='Demo'end
for k,v in pairs({my_id='42',my_nick='Demo_Officer',select_id='37',id='37',select_nick='Demo_Suspect',select_name='Demo Suspect',select_firstname='Demo',select_lastname='Suspect',badge_number='EPD-101'})do values[k]=v end
local ctx={values=values,target={id=37,ped=2,name='Demo_Suspect'},closest={id=38,ped=3,name='Demo_Partner'},session='test',now=1000,demo=false}
local args={param1='37',param2='100',param3='Test',param4='Test',arg1='Test',arg2='100',arg3='Test'}
for _,b in ipairs(lib.bindings)do
 local expected=oracle.expected.bindings[tostring(b.id)];check(expected);eq(b.script,expected.script,'Author text A'..b.id)
 for _,gender in ipairs({'male','female'})do
  ctx.gender=gender
  for _,variant in ipairs({'car','bike'})do
   local source={car={id=1,model_id=variant=='car'and 596 or 522},phase='10-55',life=1,inspect_bike=lib.vehicle.copilot.templates.inspect_bike}
   local resolved,why=require('pa26_rp_context').resolve(b,source);check(resolved,why)
   local plan,err=binder.compile(resolved,ctx,args,codec,nil,{rpSettings=lib.rp_text});check(plan,'A'..b.id..' '..variant..' '..gender..': '..tostring(err))
   check(#plan.steps<=64);check(#plan.lines>0)
   for _,line in ipairs(plan.lines)do check(not line:find('{',1,true));check(not line:find('}',1,true));check(#assert(core.encodeWire(line,codec))<=127)
    if line:match('^/todo ')then local a=line:match('%*(.*)$');check(a and #assert(codec.encode(a))<=60)end
   end
   if variant=='bike'and(b.id==14 or b.id==46 or b.id==48 or b.id==38)then
    local body=table.concat(plan.lines,'\n');for _,w in ipairs({'багажник','салон','дверь','через окно'})do check(not body:find(w,1,true),w)end
   end
   if b.id==48 then local count=0;for _,step in ipairs(plan.steps)do if step.kind=='confirm'then count=count+1;check(#step.preview>0)end end;eq(count,3)end
  end
 end
end
local count=0
for head,expected in pairs(oracle.expected.manual)do
 count=count+1;eq(manual.defaults().rules[head].rp,expected,'default /'..head)
 eq(lib.settings.manual_actions.rules[head].rp,expected,'preset /'..head)
 for _,gender in ipairs({'male','female'})do
  ctx.gender=gender;local candidate=m.copy(lib);candidate.settings.manual_actions.rules[head].enabled=true
  local plan,why=manual.plan(candidate,head,'/'..head..' 37',{param1='37',param2='100'},ctx,nil,codec,lib.rp_text);check(plan,head..': '..tostring(why))
  eq(plan.lines[#plan.lines],'/'..head..' 37','Arguments must not be rewritten')
 end
end
eq(count,34)
eq(manual.defaults().frisk_full_rp,oracle.manual_source.frisk[2])
local stock40=m.find(lib,40);eq(stock40.script,oracle.source['40'].scripts[1]);eq(stock40.rp_context,nil)
check(not table.concat({m.find(lib,53).script,m.find(lib,47).script},'\n'):find('CODE 1',1,true))
check(m.find(lib,55).script:find('10-8',1,true));check(not m.find(lib,55).script:find('10-6',1,true))
local withoutBadge=m.copy(ctx);withoutBadge.values.badge_number='';check(not binder.compile(m.find(lib,13),withoutBadge,args,codec))

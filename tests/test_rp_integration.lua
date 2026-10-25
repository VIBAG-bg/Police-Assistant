local rp=require 'pa26_rp_text'
local settings=require 'pa26_rp_settings'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local binder=require 'pa26_binder'
local body=string.rep('осмотрелся вокруг и проверил обстановку ',4):match('^(.-)%s*$')
local cfg=settings.defaults();local nickname='Victor_Auditore'
local b=model.newBinding(7);b.enabled=true;b.target_required=false;b.script='/me '..body..'\n/do '..body..'\n/r Готово.'
local ctx={values={my_nick=nickname},session='mock',now=1000,demo=false}
local p,err=binder.compile(b,ctx,{},codec,nil,{rpSettings=cfg});check(p,err)
check(#p.lines>3);check(p.rpSignature);check(p.rpExtraSteps>0);eq(p.lines[#p.lines],'/r Готово.')
eq(p.rpSignature,rp.signature(cfg,nickname));eq(#p.steps,#p.lines);check(p.has_command)
for _,line in ipairs(p.lines)do check(core.encodeWire(line,codec))end
local action={enabled=true,me=body,do_text=body,command='/frisk {id}'}
p=assert(core.prepareAction(action,37,codec,cfg,nickname));check(#p.lines>3);eq(p.lines[#p.lines],'/frisk 37');check(p.rpExtraSteps>0)
local w=require 'pa26_weapons';local s={session='erp',ped=1,alive=true,focused=true,paused=false,blocked=false,typing=false,
    recording=false,editingHud=false,draggingHud=false,onDuty=true,demo=false,weapon=0,rpText=cfg,my_nick=nickname,sendIntervalMs=5000}
local prefs=require('pa26_preferences').weaponDefaults();prefs.enabled=true;prefs.items['31'].template=body
local now=1000;local plans={};local c=w.new({settings=function()return prefs end,codec=codec,start=function(plan)plans[#plans+1]=plan;return true end})
c:tick(s,now);s.weapon=31;now=now+1;c:tick(s,now);now=now+5000;c:tick(s,now);p=plans[1];check(p);check(#p.lines>=2)
now=now+6000;c:tick(s,now);check(c:validPlan(p),'A split narration must stay valid beyond the old 5-second single-message guard')
s.weapon=0;now=now+1;c:tick(s,now);check(not c:validPlan(p))
local vehicle=require 'pa26_vehicle';local vc=require('pa26_vehicle_settings').defaults();vc.approach_template=body
p=assert(vehicle.preview('approach',vc,{rpText=cfg,my_nick=nickname},codec,{}));check(#p.lines>1);check(p.rpSignature)
local radio=require 'pa26_radio_text';p=assert(radio.prepare('/do',body,codec,{split_enabled=false},cfg,nickname));check(#p.lines>1)
-- Forms preview is split before consent, while the mock command stays one final step.
local forms=require 'pa26_case_forms';local pc=require('pa26_procedure_settings').defaults();pc.enabled=true
pc.wanted_command='/su {id} {amount} {basis}';pc.wanted_verified=true;pc.wanted_source='LOCAL MOCK ONLY';pc.wanted_appearance_rp='/me '..body
local target={id=37,ped=99,name='Other_Name'}
local f=forms.new({settings=function()return pc end,rpSettings=function()return cfg,nickname end,codec=codec,
    target=function()return target,1 end,identity=function()return {}end,validTarget=function()return true end,
    equal=function(a,b)return true end})
s.inVehicle=false;f:tick(s,now);local form=assert(f:begin('wanted'));form.life_ack=true;form.passport_seen='no';form.mask='no';form.appearance='синяя куртка';form.reason_id='01.01'
local preview,why=f:preview(form);check(preview,why);check(preview.rpCount>=2);check(preview.rpSignature);eq(preview.lines[#preview.lines],'/su 37 1 1')

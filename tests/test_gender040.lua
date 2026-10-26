local core=require 'pa26_core';local model=require 'pa26_bindings';local prefs=require 'pa26_preferences'
local procedure=require 'pa26_procedure_settings';local vehicle=require 'pa26_vehicle';local vehicles=require 'pa26_vehicle_settings'
local patrol=require 'pa26_patrol_settings';local events=require 'pa26_patrol_event_settings'
local token='{gender:проверил|проверила}'
for _,plain in ipairs({'старый текст %s.','100% без переменных.','/me прежняя строка.'})do
    eq(core.expandGender(plain,'male'),plain);eq(core.expandGender(plain,'female'),plain)
end
eq(core.expandGender(token,'male'),'проверил');eq(core.expandGender(token,'female'),'проверила')
eq(core.expandGender('{gender:100%|%s}','female'),'%s');eq(core.expandGender('{gender:|а}','male'),'')
eq(core.expandGender(nil,'female'),nil)
check(require('pa26_manual_actions').preview('/me '..token..' {param1}.','female'):find('проверила 37.',1,true))
for _,gender in ipairs({'male','female'})do
    local word=gender=='female'and'проверила'or'проверил'
    check(prefs.template(token..' {weapon}.',{weapon=true}));check(patrol.template(token..' патруль.'))
    check(vehicles.template(token..' машину.'))
    local p=procedure.defaults();p.fine_appearance_rp='/me '..token..' данные.';check(procedure.validate(p))
    local e=events.defaults();e.events.frisk.template=token..' имущество.';check(events.validate(e))
    local ac=model.defaults(core.defaults()).alerts;ac.on_duty=true;ac.sos_template=token..' обстановку.'
    local state={session='gender-test',ped=1,demo=true,gender=gender,weapon=24,area='Ganton',alive=true,focused=true,paused=false,blocked=false,onDuty=true}
    local a=assert(require('pa26_alerts').prepare('sos',state,ac,codec,1000,1));check(a.lines[1]:find(word,1,true));check(not a.lines[1]:find('{gender:',1,true))
    local warning=prefs.weaponWarningDefaults();warning.firearm_template=token..' {weapon}.'
    local w=assert(require('pa26_weapon_warning').prepare(warning,state,'Deagle','firearm',codec,1000,1));check(w.lines[1]:find(word,1,true))
    local vc=vehicles.defaults();vc.approach_template=token..' {model}.'
    local v=assert(vehicle.preview('approach',vc,{gender=gender,model='Infernus'},codec));check(v.line:find(word,1,true))
    vc.description_template=token..' {model}.'
    local description=assert(vehicle.describe({id=1,model_id=411,model_name='Infernus',color1=0,color2=1},vc,gender))
    check(description.vehicle_description:find(word,1,true))
    -- Actual weapon draw/holster controllers use the same token and reject stale gender.
    local wc=prefs.weaponDefaults();wc.enabled=true;wc.delay_ms=1000;wc.holster_enabled=true;wc.holster_delay_ms=1000
    wc.items['24'].template=token..' {weapon}.';wc.items['24'].holster_template=token..' подсумок.';wc.items['24'].holster_enabled=true
    local plans={};local weapon=require('pa26_weapons').new({settings=function()return wc end,codec=codec,start=function(p)plans[#plans+1]=p;return true end})
    state.weapon=0;weapon:tick(model.copy(state),1000);state.weapon=24;weapon:tick(model.copy(state),1100);weapon:tick(model.copy(state),2100)
    eq(#plans,1);check(plans[1].lines[1]:find(word,1,true));check(weapon:validPlan(plans[1]))
    weapon:onExecution('preview_line',{plan=plans[1]});state.weapon=0;weapon:tick(model.copy(state),2200);weapon:tick(model.copy(state),3200)
    eq(#plans,2);check(plans[2].lines[1]:find(word,1,true));check(weapon:validPlan(plans[2]))
    state.gender=gender=='male'and'female'or'male';weapon:tick(model.copy(state),3300);check(not weapon:validPlan(plans[2]))
    -- Patrol and event report builders share exactly the same expansion.
    local pc=patrol.defaults();pc.start_template=token..' патруль.'
    local session=require('pa26_patrol_session').new({codec=codec})
    local report=assert(session:prepareLine('start',nil,{gender=gender},pc));check(report.line:find(word,1,true))
    local event=require('pa26_patrol_events').new({codec=codec});event.state={gender=gender}
    report=assert(event:line({kind='frisk'},e));check(report.line:find(word,1,true))
    -- Taser reload count stays intact if the grammatical profile changes.
    local tc=prefs.taserDefaults();tc.enabled=true;tc.activation='weapon';tc.auto_reload=false;tc.reload_template=token..' тайзер.'
    local tp={};local t=require('pa26_taser').new({settings=function()return tc end,codec=codec,start=function(plan)tp[#tp+1]=plan;return true end})
    state.gender=gender;state.weapon=tc.weapon_id;t:tick(model.copy(state),4000);check(t:bullet({weaponId=tc.weapon_id}));t:tick(model.copy(state),4100)
    check(t:requestReload());t:tick(model.copy(state),4200);eq(#tp,1);check(tp[1].lines[1]:find(word,1,true));check(t:validPlan(tp[1]))
    local shots=t.shots;state.gender=gender=='female'and'male'or'female';t:tick(model.copy(state),4300);eq(t.shots,shots);check(not t:validPlan(tp[1]))
    -- Wanted/fine previews and the fallback template preview use profile gender.
    local forms=require('pa26_case_forms').new({settings=function()return p end,gender=function()return gender end})
    local f={ic_name='John Smith',target={id=37,name='John_Smith'},appearance='куртка'}
    local line=assert(forms:templatePreview('/me '..token..' {ic_name}.',f));check(line:find(word,1,true))
end
for _,bad in ipairs({'{gender:a|b|c}','{gender:a}','{gender:{id}|b}','{gender:a|b\n} ','{gender:a|b'})do
    check(not prefs.template(bad,{weapon=true}),bad);check(not patrol.template(bad),bad);check(not vehicles.template(bad),bad)
    local p=procedure.defaults();p.fine_appearance_rp='/me '..bad;check(not procedure.validate(p),bad)
end
-- Gender substitutions are RP text, never new server command arguments.
local p=procedure.defaults();p.wanted_direct_command='/su {id} {gender:1|2} 1';check(not procedure.validate(p))
check(not prefs.helpCommand('/sos {gender:1|2}'))
local lib=model.defaults(core.defaults());lib.profile.gender='female';lib.weapons.items['24'].template=token..' оружие.'
local parts=require('pa26_user_files').partition(lib);local restored=assert(require('pa26_user_files').combine(parts,core.defaults()))
eq(restored.profile.gender,'female');eq(restored.weapons.items['24'].template,lib.weapons.items['24'].template)
local presets=require('pa26_rp_presets')
for _,row in ipairs(presets.items)do if not row.binding_id and row.old[1]~=row.text then local parent=lib;for i=1,#row.path-1 do parent=parent[row.path[i]]end;parent[row.path[#row.path]]=row.old[1];break end end
local old=model.copy(lib.bindings);local updated=assert(presets.apply(lib,presets.plan(lib)))
for i,b in ipairs(old)do eq(updated.bindings[i].script,b.script)end

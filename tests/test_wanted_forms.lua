local mod=require 'pa26_case_forms'
local prefs=require 'pa26_procedure_settings'
local model=require 'pa26_bindings'
local catalog=require 'pa26_wanted_catalog'
local function equal(a,b)
    if type(a)~='table'or type(b)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end;return true
end
local function fixture()
    local s={cfg=prefs.defaults(),now=1000,stamp=1,target={id=37,ped=99,name='Player_Name'},plans={},saved={},
        state={session='test:7777',ped=1,alive=true,demo=false,focused=true,paused=false,blocked=false,inVehicle=false,
            typing=false,modal=false,recording=false,editingHud=false,draggingHud=false}}
    local c;c=mod.new({settings=function()return s.cfg end,target=function()return s.target,s.stamp end,codec=codec,
        identity=function()return s.identity end,equal=equal,wall=function()return 123456 end,
        validTarget=function(t,stamp)return t and s.target and t.id==s.target.id and t.ped==s.target.ped and t.name==s.target.name and stamp==s.stamp end,
        start=function(p)check(c:validPlan(p));s.plans[#s.plans+1]=p;return true end,
        saveReminders=function(rows)if s.saveError then return nil,'disk busy'end;s.saved=model.copy(rows);return true end,
        cancel=function()s.cancelled=true end})
    function s.tick(ms)s.now=s.now+(ms or 0);c:tick(s.state,s.now)end
    function s.form(kind)
        local f=assert(c:begin(kind or 'wanted'));f.life_ack=true;f.passport_seen='no';f.mask='no';f.appearance='синяя куртка';f.reason_id='01.01';return f
    end
    function s.prepare(f)
        local p=assert(c:offer(f));check(c:accept(p));s.tick();local plan=s.plans[#s.plans]
        for _,line in ipairs(plan.lines)do check(line:match('^/me ')or line:match('^/do '),'Preparation may send only RP')end
        c:onExecution('completed',{plan=plan});check(c.awaitingCommand);return assert(c:takeCommandConfirmation())
    end
    function s.finish(p)check(c:accept(p));s.tick();local plan=s.plans[#s.plans];c:onExecution('completed',{plan=plan});return plan end
    s.tick();return c,s
end
local expected={{1,5},{3,6},{2,1,3},{2,2,3,3},{2},{2,3},{2,1,2,2},{2,1},{3},{1,3,4},{3,4,5},{6},{1,4,4}}
eq(#catalog.rows,31);eq(#catalog.groups,13)
for gi,items in ipairs(expected)do for item,stars in ipairs(items)do
    local id=string.format('%02d.%02d',gi,item);local row=catalog.byId[id];check(row);eq(row.stars,stars)
    local c,s=fixture();local f=s.form();f.reason_id=id
    local p=assert(c:preview(f));eq(p.values.game_category,tostring(gi));eq(p.values.game_item,tostring(item))
    eq(p.lines[#p.lines],'/su 37 '..gi..' '..item)
    local final=s.prepare(f);eq(#s.plans,1);eq(final.phase,'command');eq(#final.lines,1)
    eq(final.lines[1],'/su 37 '..gi..' '..item);check(not c:takeCommandConfirmation(),'Do not reopen a presented confirmation')
    s.tick(1000);eq(#s.plans,1,'No command before a separate YES')
    local plan=s.finish(final);eq(#s.plans,2);eq(#plan.steps,1);eq(plan.lines[1],final.lines[1]);check(not c:accept(final),'No replay')
end end
local c,s=fixture();local f=s.form();f.life_ack=false;check(not c:preview(f));f.life_ack=true
f.mask='unknown';f.passport_seen='yes';f.ic_name='John Smith';check(not c:branch(f),'Mask question remains explicit')
f.mask='yes';check(not c:branch(f),'A previous passport is insufficient after losing sight behind an RP mask')
f.face_before='yes';eq(c:branch(f),'passport');f.passport_seen='no';f.face_before='no';check(not c:branch(f));f.face_before='yes';eq(c:branch(f),'appearance')
f.reason_id='1.1';check(not c:preview(f));f.reason_id='04.03';check(c:preview(f).gameReason.mapping_status:find('не найдено',1,true))
f.appearance='синяя\nкуртка';eq(c:preview(f).values.appearance,'синяя куртка')
for _,change in ipairs({'stamp','target','ped','session','inVehicle','demo','alive','cfg','identity'})do
    c,s=fixture();f=s.form()
    if change=='identity'then s.identity={record={stamp=1,target=s.target,nonce=1,version=1,mask='no',passport_seen='no',appearance='синяя куртка'}};f=s.form()end
    local p=s.prepare(f)
    if change=='stamp'then s.stamp=2 elseif change=='target'then s.target.name='Other_Player'
    elseif change=='cfg'then s.cfg.wanted_send_mode='menu' elseif change=='identity'then s.identity.record.version=2
    elseif change=='inVehicle'then s.state.inVehicle=true elseif change=='demo'then s.state.demo=true
    elseif change=='alive'then s.state.alive=false else s.state[change]='other'end
    s.tick();check(not c:accept(p),change);eq(#s.plans,1,change)
end
c,s=fixture();f=s.form();local p=s.prepare(f);check(c:cancelCommandConfirmation(p.token));check(not c:accept(p));s.tick();eq(#s.plans,1)
c,s=fixture();f=s.form();p=s.prepare(f);s.tick(60001);check(not c:accept(p),'Final confirmation expires');eq(#s.plans,1)
c,s=fixture();s.cfg.wanted_send_mode='menu';f=s.form();p=s.prepare(f);eq(s.finish(p).lines[1],'/su 37')
c,s=fixture();s.target=nil;f=s.form('wanted_list');p=s.prepare(f);eq(s.finish(p).lines[1],'/wanted');eq(#c.reminders,0)
c,s=fixture();s.state.inVehicle=nil;s.tick();check(not c:begin('wanted'),'Do not guess unavailable device context')
c,s=fixture();s.state.inVehicle=true;s.tick();f=s.form();p=c:preview(f);check(p.lines[1]:find('бортовому',1,true));check(not table.concat(p.lines):find('КПК',1,true))
c,s=fixture();f=s.form();f.mode='ooc';check(not c:preview(f));f.ooc_ack=true
for _,retired in ipairs({'invalid','pt','arrest','dm'})do f.ooc_reason=retired;check(not c:preview(f),'Retired OOC purpose must be blocked: '..retired)end
f.ooc_reason='tracking';check(not c:preview(f),'IC phone/source required even after explicit acknowledgement')
f.phone_known='yes';f.phone_number='555123';f.phone_source='Паспорт и разговор в текущей ситуации.'
for _,key in ipairs({'phone_number','phone_source'})do
    local saved=f[key]
    for _,bad in ipairs({'','   ','bad\n/r spam'})do f[key]=bad;check(not c:preview(f),'Invalid tracking evidence must be blocked')end
    f[key]=saved
end
local phonePreview=assert(c:preview(f));eq(phonePreview.values.phone_number,'555123')
eq(phonePreview.values.phone_source,'Паспорт и разговор в текущей ситуации.')
check(table.concat(phonePreview.lines,'\n'):find('555123',1,true),'Editable tracking RP receives the IC phone variable')
p=s.prepare(f);eq(#c.reminders,0);s.finish(p);eq(#c.reminders,1);eq(c.reminders[1].status,'check','Sending does not prove stars were issued')
c:flush();eq(#s.saved,1);check(prefs.validateReminders(s.saved));local token=c.reminders[1].token
check(c:changeReminder(token,'issued'));s.saveError=true;c:flush();check(c.remindersDirty);s.saveError=false;s.tick(10001);c:flush();eq(s.saved[1].status,'issued')
s.tick(s.cfg.wanted_reminder_delay_ms);local candidates=c:candidates();eq(#candidates,1);check(not c:decideReminder(token,true),'Must have been painted')
c:shownReminder(token);check(c:decideReminder(token,false));eq(#c:candidates(),0);s.tick(s.cfg.wanted_reminder_snooze_ms);eq(#c:candidates(),1)
c:shownReminder(token);s.tick(251);check(not c:decideReminder(token,true),'No stale clicks');c:shownReminder(token);check(c:decideReminder(token,true));check(c.reviewReminders)
check(c:changeReminder(token,'resolved'));c:flush();eq(#s.saved,0);eq(#s.plans,2,'Reminder actions never send commands')
c,s=fixture();s.state.demo=true;s.tick();f=s.form();f.mode='ooc';f.ooc_ack=true;f.phone_known='yes';f.phone_number='555123';f.phone_source='Назван владельцем по RP.';p=s.prepare(f);s.finish(p);eq(#c.reminders,0,'Demo does not create real obligations')
local cfg=prefs.defaults();cfg.wanted_direct_command='/su {id} {amount} {basis}';check(not prefs.validate(cfg))
cfg=prefs.defaults();cfg.wanted_command='/su {id} {amount} {basis}';cfg.wanted_verified=true;cfg.wanted_source='Legacy personal syntax';check(prefs.validate(cfg),'Preserve a legacy field without using it')
local lib=model.defaults(require('pa26_core').defaults());lib.wanted_reminders=s.saved;check(model.validate(lib));lib.wanted_reminders={{token='bad'}};check(not model.validate(lib))

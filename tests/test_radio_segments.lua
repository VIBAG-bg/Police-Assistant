local radio=require 'pa26_radio_text'
local core=require 'pa26_core'
local prefs=require 'pa26_preferences'
local model=require 'pa26_bindings'
local cfg=prefs.radioGuardDefaults()
local body='P-01, начинаем патрулирование по городу Сан-Фиерро. Экипаж: Victor Auditore, Rafayel Barvello. Район: Доэрти. Направление: Северо-запад. Далее доступны.'
local p=assert(radio.prepare('/r',body,codec,cfg));check(#p.lines>1);eq(#p.lines,#p.wires)
for i,line in ipairs(p.lines)do check(#p.wires[i]<=core.WIRE_LIMIT);eq(codec.decode(p.wires[i]),line);check(line:match('^/r '))end
local restored={};for i,line in ipairs(p.lines)do local v=line:sub(4);if i>1 then v=v:sub(#cfg.continuation+2)end;if i<#p.lines then v=v:sub(1,-#cfg.continuation-2)end;restored[#restored+1]=v end
eq(table.concat(restored,' '),body,'No word, partner name or clause is lost')
check(not radio.prepare('/r',body,codec,{split_enabled=false}));check(not radio.prepare('/r',string.rep('Я',200),codec,cfg))
check(not radio.prepare('/r','Доклад\n/r injection',codec,cfg));check(not radio.prepare('/r','Тест 🦄',codec,cfg))
cfg.max_lines=1;check(not radio.prepare('/r',body,codec,cfg));cfg.max_lines=6
local session=require 'pa26_patrol_session'
local scfg=require('pa26_patrol_settings').defaults();scfg.enabled=true;scfg.unit='P-01';scfg.start_template=body
local state={session='erp',ped=1,local_nick='Victor_Auditore',alive=true,focused=true,paused=false,blocked=false,onDuty=true,radioEnabled=true,
    demo=false,area='Доэрти',radioText=cfg}
local capture;local active=session.new({settings=function()return scfg end,codec=codec,profile=function()return {name='Victor Auditore',callsign='P-01'}end,
    contacts=function()return {}end,start=function(plan)capture=plan;return true end,equal=function()return true end,observe=function()return {}end})
active:tick(state,1000);local proposal=assert(active:propose('start'));check(active:accept(proposal));active:tick(state,1016)
check(capture and #capture.steps>1);active:onExecution('sent_line',{plan=capture,index=1});check(active.queued);check(active.awaitingReport)
active:onExecution('sent_line',{plan=capture,index=#capture.steps});check(not active.queued);check(not active.awaitingReport)
local guards=require 'pa26_radio_guard';local spec={name='Тест',channel='/r',template=body,confirmation=false,interval_ms=60000}
local gp=assert(guards.prepare(spec,state,codec,1000,1));eq(#gp.lines,#p.lines)
local changed=model.copy(gp);changed.wire[#changed.wire]=changed.wire[#changed.wire]..' changed'
check(radio.key(gp)~=radio.key(changed),'Changes in continuation lines invalidate the entire preview')
-- Driver may delegate radio duty; a local session must not duplicate a partner's reports.
scfg.reporter_self=false;capture=nil
active=session.new({settings=function()return scfg end,codec=codec,profile=function()return {name='Victor Auditore',callsign='P-01'}end,
    contacts=function()return {}end,start=function(plan)capture=plan;return true end,equal=function()return true end})
active:tick(state,2000);proposal=assert(active:propose('start'));check(proposal.no_report);check(not proposal.line);check(active:accept(proposal))
active:tick(state,2016);check(active.data.active);check(not capture);check(not active:effectivePatrol(prefs.patrolDefaults()).enabled)
active:tick(state,3016);check(active.data.active.elapsed_ms>0)
proposal=assert(active:propose('finish'));check(active:accept(proposal));active:tick(state,3032);check(not active.data.active);eq(#active.data.history,1);check(not capture)

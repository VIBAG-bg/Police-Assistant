local events=require 'pa26_patrol_events'
local prefs=require 'pa26_patrol_event_settings'
local model=require 'pa26_bindings'
local function fixture()
    local s={now=1000,cfg=prefs.defaults(),target={id=4,ped=5,name='Player_Name'},stamp=1,
        state={session='test:7777',ped=1,alive=true,demo=false,focused=true,paused=false,blocked=false,typing=false,
            modal=false,recording=false,editingHud=false,draggingHud=false,local_nick='Officer_One',patrol_id='1'}}
    s.cfg.enabled=true
    local c=events.new({settings=function()return s.cfg end,patrol=function()return {id=1}end,
        target=function()return s.target end,targetStamp=function()return s.stamp end,
        validTarget=function(t)return s.target and t.id==s.target.id and t.name==s.target.name and t.ped==s.target.ped end})
    function s.tick(ms)s.now=s.now+(ms or 16);c:tick(s.state,s.now)end
    function s.command()check(c:command('/cuff 4','native',s.target));return c.attempts[#c.attempts]end
    s.tick(0);return c,s
end
for _,patch in ipairs({{toast_ms=0},{toast_ms=31000},{toast_ms=false},{toast_mode=false},{toast_template=false},{toast_mode='automatic'},{toast_template='{unknown}'},
    {toast_title=''},{toast_hint='\255'},{toast_template='\0bad'}})do
    local cfg=prefs.defaults();for k,v in pairs(patch)do cfg[k]=v end;check(not prefs.validate(cfg))
end
check(prefs.noticeText('Проверить\n{event}?',true));check(prefs.validate(nil))
local c,s=fixture();local a=s.command();local candidate=c:candidates()[1]
eq(candidate.owner,'patrol');eq(candidate.mode,'confirm');check(candidate.priority<50)
check(candidate.body:find('/cuff 4',1,true));eq(#c.data.events,0)
check(not c:decideNotice(a.notice_token,true),'No choice before rendering')
c:shown(a.notice_token);check(c:decideNotice(a.notice_token,true));check(not c:decideNotice(a.notice_token,true))
local form=assert(c:takeNoticeReview());eq(form.attempt_id,a.id);check(not form.acknowledged);eq(form.subject,'')
eq(#c.data.events,0);eq(c.data.facts.detention,nil);check(not c:takeNoticeReview())
c,s=fixture();a=s.command();c:shown(a.notice_token);check(c:decideNotice(a.notice_token,false))
eq(#c:candidates(),0);check(c:attempt(a.id),'NO keeps the attempt for later manual review');check(not c:takeNoticeReview())
-- Countdown uses visible frames, not wall time spent behind the chat or SOS.
c,s=fixture();a=s.command();s.tick(1000);eq(a.notice_remaining,10000)
c:shown(a.notice_token);s.tick(1000);eq(a.notice_remaining,9000)
s.tick(1000);eq(a.notice_remaining,9000,'Not painted during the previous frame')
c:shown(a.notice_token);s.state.alertPending=true;s.tick(1000);eq(a.notice_remaining,9000)
c:shown(a.notice_token);s.state.alertPending=false;s.tick(1000);eq(a.notice_remaining,9000,'First frame after a blocked surface')
for _=1,9 do c:shown(a.notice_token);s.tick(1000)end
eq(a.notice_remaining,0);eq(#c:candidates(),0);check(c:attempt(a.id));eq(#c.data.events,0)
-- Context/config invalidation, bounded lifetime, and no unseen resurfacing.
for _,change in ipairs({'target','stamp','settings','disable','ttl','session'})do
    c,s=fixture();a=s.command();c:shown(a.notice_token)
    if change=='target'then s.target.name='Other_Player'
    elseif change=='stamp'then s.stamp=2
    elseif change=='settings'then s.cfg.toast_title='Изменено'
    elseif change=='disable'then s.cfg.toast_enabled=false
    elseif change=='session'then s.state.session='other:7777'end
    s.tick(change=='ttl'and 300001 or 16);eq(#c:candidates(),0,change);check(not c:decideNotice(a.notice_token,true))
end
c,s=fixture();s.cfg.toast_mode='buttons';a=s.command();eq(c:candidates()[1].mode,'action')
for i=1,30 do s.tick(500);check(c:command('/cuff '..i,'native',s.target))end
eq(#c.attempts,20);eq(#c:candidates(),20);eq(#c.data.events,0)
c,s=fixture();s.state.demo=true;s.tick();check(not c:command('/cuff 4'));eq(#c:candidates(),0)
-- An observed native command can arrive while the input window is still open.
c,s=fixture();s.state.blocked=true;s.state.typing=true;s.tick();a=s.command();eq(#c:candidates(),0)
s.state.blocked=false;s.state.typing=false;s.tick();eq(#c:candidates(),1)
c:reset('new scene');eq(#c:candidates(),0);check(not c:takeNoticeReview())

local tracker=require 'pa26_target'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local fixture=require 'support.fixture'

-- Known-person retention is independent of command range, line of sight and ped lifetime.
local ctx={session='A',alive=true}; local now=10000; local t={id=37,ped=99,name='Player_Name'}
local observed={connected=true,name=t.name,visible=true,distance=5,validated=t}
local events={}
local tr=tracker.new({inspect=function() return observed end,event=function(k,target,reason) events[#events+1]={k,target,reason} end})
local settings={action_distance=8,retain_distance=40,retain_grace_ms=1500}
check(tr:select(t,ctx.session)); check(tr:select(t,ctx.session)); eq(#events,1)
tr:refresh(ctx,now,settings); eq(tr.state,'available')
observed={connected=true,name=t.name}; now=now+300; tr:refresh(ctx,now,settings)
eq(tr.state,'unavailable'); eq(tr.target.id,37); eq(#events,1)
observed={connected=true,name=t.name,visible=true,distance=15}; now=now+300; tr:refresh(ctx,now,settings)
eq(tr.state,'out_of_range'); eq(tr.target.id,37)
observed.distance=45; now=now+300; tr:refresh(ctx,now,settings); eq(tr.state,'too_far')
now=now+1000; tr:refresh(ctx,now,settings); check(tr.target)
observed.distance=5; observed.validated=t; now=now+300; tr:refresh(ctx,now,settings); eq(tr.state,'available')
observed.distance=45; now=now+300; tr:refresh(ctx,now,settings)
now=now+1500; tr:refresh(ctx,now,settings); eq(tr.target,nil); eq(events[#events][3],'distance')
tr:clear('manual'); eq(#events,2)
check(tr:select(t,ctx.session)); observed={connected=true,name='Different_Name'}; now=now+300; tr:refresh(ctx,now,settings)
eq(tr.target,nil); eq(events[#events][3],'identity')
check(tr:select(t,ctx.session)); tr:quit(38); check(tr.target); tr:quit(37); eq(tr.target,nil)
check(tr:select(t,ctx.session)); tr:join(37); eq(tr.target,nil)
check(tr:select(t,ctx.session)); ctx.session='B'; tr:refresh(ctx,now,settings); eq(tr.target,nil)
check(tr:select(t,ctx.session)); ctx.alive=false; tr:refresh(ctx,now,settings); eq(tr.target,nil)
ctx.alive=true; check(tr:select(t,ctx.session)); observed={connected=true,name=t.name,visible=true,distance=5,validated={id=37,ped=100,name=t.name}}
now=now+300; tr:refresh(ctx,now,settings); eq(tr.target.ped,100); eq(events[#events][1],'rebound')
now=now-1000; tr:refresh(ctx,now,settings); eq(tr.target,nil)

-- A 0.5 library migrates without replacing the user's bindings/profile.
local old=model.defaults(core.defaults()); old.settings.retain_distance=nil; old.settings.retain_grace_ms=nil
old.bindings[1].name='Мой сохранённый сценарий'; local migrated=model.validate(old,core.defaults())
check(migrated); eq(migrated.settings.retain_distance,40); eq(migrated.bindings[1].name,old.bindings[1].name)
for _,value in ipairs({0,19,201,0/0}) do local bad=model.copy(migrated); bad.settings.retain_distance=value; check(not model.validate(bad,core.defaults())) end

local function drawn(s,needle)
    return table.concat(s.drawnText,'\n'):find(needle,1,true)~=nil
end
local function selectPerson(s)
    s.step(); s.commands.pa26select('37'); s.step(300)
    check(drawn(s,'Игрок: Player_Name [37]')); eq(#s.localChat,0); eq(#s.sent,0)
end
local s=fixture({demo=false}); selectPerson(s)
s.onScreen=false; s.step(300); check(drawn(s,'Недоступен · выбор сохранён')); eq(#s.localChat,0)
s.onScreen=true; s.streamed=false; s.step(300); eq(#s.localChat,0)
s.streamed=true; s.step(300); eq(#s.localChat,0)
s.aimed=false; s.commands.pa26(); s.down[0x58]=true; s.step(16,{[0x58]=true})
check(s.frames[2].condition()); eq(s.poolReads,0,'existing selection must not scan or silently choose a neighbour')
s.io.MousePos.x,s.io.MousePos.y=s.io.DisplaySize.x/2,s.io.DisplaySize.y/2
s.render(); s.down[0x58]=false; s.step(150); s.step(300); eq(#s.sent,0); eq(#s.localChat,0)
s.vehicle=true; s.step(300); s.vehicle=false; s.step(300); eq(#s.localChat,0)
s.distance=15; s.step(300); check(drawn(s,'Вне дистанции действия')); eq(#s.localChat,0)
s.distance=45; s.step(300); s.step(1000); eq(#s.localChat,0); s.step(600); eq(#s.localChat,0)
check(drawn(s,'Игрок слишком далеко.')); s.step(1000); eq(#s.localChat,0)

-- Native polling still detects a real disconnect when SAMP.Lua is absent.
s=fixture({demo=false,sampEvents=false}); selectPerson(s); s.targetConnected=false; s.step(300)
eq(#s.localChat,0); check(drawn(s,'Игрок вышел с сервера.')); s.step(300); eq(#s.localChat,0)
-- Unknown API result is not a false disconnect announcement.
s=fixture({demo=false}); selectPerson(s); s.identityError=true; s.step(300); eq(#s.localChat,0)
s.identityError=false; s.step(300); eq(#s.localChat,0)
s.events.onPlayerQuit(37,1); eq(#s.localChat,0); s.events.onPlayerJoin(37,0,false,'Player_Name'); eq(#s.localChat,0)
s.step(300); check(drawn(s,'Игрок: —')); onScriptTerminate(s.script)
eq(s.events.onPlayerQuit,nil); eq(s.events.onPlayerJoin,nil)

-- Prepare a target-specific three-line Miranda-style bind through the real editor.
local original='Права для {select_nick}.\n@wait(3000)\nВы вправе получить юридическую помощь.\n@wait(3000)\nПринуждение к признанию запрещено.'
local function startRights()
    local state=fixture({demo=false}); state.step(); state.page('binds')
    state.edits={['##script']=original}; state.render(); state.click='Сохранить сценарий'; state.render()
    state.commands.pa26select('37'); state.commands.pa26run('1'); state.step(); state.step(100)
    eq(#state.sent,1); eq(state.sent[1].line,'Права для Player_Name.')
    return state
end
s=startRights(); s.step(16,{[0x7B]=true}); check(s.frames[4].condition())
s.io.WantTextInput=true; s.render(); s.step(100,{[0x23]=true}) -- End is an editor key while typing.
s.commands.pa26(); s.page('binds'); s.edits={['##script']='Новый текст следующего запуска.'}; s.render()
s.click='Сохранить сценарий'; s.render();s.ackInfo()
s.step(3100); s.step(); eq(#s.sent,2); eq(s.sent[2].line,'Вы вправе получить юридическую помощь.')
s.io.WantTextInput=false; s.render(); s.step(16,{[0x7A]=true}); check(s.frames[4].condition())
s.down[0x1B]=true; onWindowMessage(0x0100,0x1B); s.step(16,{[0x1B]=true})
check(not s.frames[1].condition()); s.down[0x1B]=false; s.step(); s.step(3100); s.step()
eq(#s.sent,3); eq(s.sent[3].line,'Принуждение к признанию запрещено.')
check(s.hasLog('Все строки переданы')); eq(#s.localChat,0)

-- No second run gets inserted in the first sequence.
s=startRights(); s.commands.pa26tips(); s.commands.pa26run('1'); s.step(); s.step(3100); s.step(); eq(#s.sent,2)
check(s.hasLog('Сначала завершите') or drawn(s,'Сначала завершите'))
for _,condition in ipairs({'chat','dialog','paused','disconnect','identity','unselect','cancel','focus','End','Esc'}) do
    s=startRights(); s.commands.pa26tips(); s.step()
    if condition=='chat' then s.chat=true
    elseif condition=='dialog' then s.dialog=true
    elseif condition=='paused' then s.paused=true
    elseif condition=='disconnect' then s.events.onPlayerQuit(37,1)
    elseif condition=='identity' then s.name='Reused_ID'
    elseif condition=='unselect' then s.commands.pa26select('off')
    elseif condition=='cancel' then s.commands.pa26cancel()
    elseif condition=='focus' then onWindowMessage(0x0008,0)
    elseif condition=='End' then s.step(16,{[0x23]=true})
    else onWindowMessage(0x0100,0x1B); s.step(); onWindowMessage(0x0100,0x1B) end
    s.step(3500); s.step(3500); eq(#s.sent,1,'remaining rights lines must be dropped: '..condition)
end

-- Keyboard continuation cannot be stolen by an editor, even if the key is held.
local execution=require 'pa26_executor'; local binder=require 'pa26_binder'
local state={session='A',focused=true,paused=false,blocked=false,alive=true,window=true,ownWindow=true,typing=true}
local clock=10000; local down,pressed=true,true; local sends={}
local b=model.copy(migrated.bindings[1]); b.target_required=false; b.script='@sleep(F6)\nПродолжение.'
local plan=binder.compile(b,{session='A',now=clock,demo=false,values={}}, {},codec)
local ex=execution.new({context=function() return state end,now=function() return clock end,demo=function() return false end,
    send=function(wire) sends[#sends+1]=wire; return true end,validate=function(t) return t end,
    lastSent=function() return nil end,markSent=function() end,pressed=function() return pressed end,down=function() return down end})
check(ex:start(plan,false,1500)); ex:step(); eq(ex.queue.index,1)
state.typing=false; ex:step(); eq(ex.queue.index,1)
down=false; pressed=false; ex:step(); down=true; pressed=true; ex:step(); eq(ex.queue.index,2)
ex:step(); eq(#sends,1)

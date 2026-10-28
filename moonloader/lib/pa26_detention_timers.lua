-- Procedural reminders only. No native calls, sanctions or invented 60-min clock.
local core=require 'pa26_core'
local copy=require('pa26_bindings').copy
local M={};local T={};T.__index=T
local stages={lawyer_response={seconds=300,key='lawyer_response_seconds',title='Ответ адвоката'},
 lawyer_arrival={seconds=600,key='lawyer_arrival_seconds',title='Прибытие адвоката'},
 phone_call={seconds=180,key='phone_call_seconds',title='Телефонный звонок'}}
M.stages=stages
function M.new(env)return setmetatable({env=env,serial=0,life=1},T)end
function T:reset(reason)self.case=nil;self.mail=nil;self.life=self.life+1;self.message=reason end
function T:request(action)
 if type(action)~='string'or #action>48 then return false end
 if self.mail then return false end
 self.mail={action=action,life=self.life,at=self.now};return true
end
function T:valid(c)
 local s=self.state
 return c and s and s.alive and s.session==c.session and s.ped==c.ped and s.demo==c.demo and
  s.localId==c.localId and s.local_nick==c.local_nick and self.env.valid(c.target)or false
end
function T:start(stage)
 local spec=stages[stage];local cfg=self.env.settings()
 local seconds=cfg[spec.key]
 if not core.finite(seconds)or seconds%1~=0 or seconds<1 or seconds>3600 then return nil,'Проверьте длительность таймера.'end
 self.case.stage=stage;self.case.started=self.now;self.case.seconds=seconds;self.case.expired=false;self.case.announced=false
 return true
end
function T:act(action)
 local c=self.case;local s=self.state;local cfg=self.env.settings()
 if not cfg.detention_timers or not s or not s.session or not s.alive or not s.focused or s.paused or s.blocked then return nil,'Таймеры выключены или игровая сцена недоступна.'end
 if action=='begin'then
  if c then return nil,'Сначала завершите текущую процедуру. Таймер другого человека не заменяется.'end
  local target=self.env.target();if not target or not self.env.valid(target)then return nil,'Сначала выберите подключённого человека для процедуры.'end
  self.serial=self.serial+1
  self.case={id=self.serial,target=copy(target),session=s.session,ped=s.ped,demo=s.demo,localId=s.localId,local_nick=s.local_nick,stage='ready',history={}}
  self.message=nil;return true
 end
 if not self:valid(c)then return nil,'Процедура устарела: человек, жизнь или подключение изменились.'end
 local stage=c.stage;local nextStage
 if action=='lawyer_request'and not c.lawyer_requested and(stage=='ready'or stage=='phone_done')then nextStage='lawyer_response'
 elseif action=='lawyer_answered'and stage=='lawyer_response'then c.frozen=true;nextStage='lawyer_arrival'
 elseif action=='lawyer_unavailable'and(stage=='lawyer_response'or stage=='lawyer_arrival')then c.stage='lawyer_unavailable';c.frozen=false
 elseif action=='lawyer_arrived'and stage=='lawyer_arrival'then c.stage='lawyer_arrived';c.frozen=false
 elseif action=='lawyer_timeout_verified'and c.expired and(stage=='lawyer_response'or stage=='lawyer_arrival')then c.stage='lawyer_timeout_verified';c.frozen=false
 elseif action=='phone_start'and not c.phone_used and not stages[stage]then nextStage='phone_call'
 elseif action=='phone_finished'and stage=='phone_call'then c.stage='phone_done'
 elseif action=='phone_timeout_verified'and stage=='phone_call'and c.expired then c.stage='phone_done'
 elseif action=='finish'then self:reset('Процедура завершена офицером. Серверный арест этим не подтверждён.');return true
 else return nil,'Это действие не относится к текущему этапу.'end
 if nextStage then
  local ok,err=self:start(nextStage);if not ok then return nil,err end
  if action=='phone_start'then c.phone_used=true elseif action=='lawyer_request'then c.lawyer_requested=true end
 end
 c.history[#c.history+1]={action=action,at=self.now};if #c.history>64 then table.remove(c.history,1)end
 if nextStage then return true end
 c.started=nil;c.expired=false;c.announced=false;return true
end
function T:tick(s,now)
 if not core.finite(now)or now%1~=0 then self:reset('Таймер сцены недоступен.');self.now=nil;self.state=nil;return end
 if self.now and not core.elapsed(now,self.now)then self:reset('Ход игрового времени изменился.')end
 self.now=now;self.state=copy(s)
 local cfg=self.env.settings()
 if self.case and(not cfg.detention_timers or not self:valid(self.case))then self:reset('Таймер остановлен: изменились жизнь, подключение или выбранный аккаунт; проверьте процедуру.')end
 local mail=self.mail;self.mail=nil
 if mail and mail.life==self.life and(core.elapsed(now,mail.at)or math.huge)<=5000 then
  local ok,err=self:act(mail.action);if not ok and self.env.notice then self.env.notice(err)end
 end
 local c=self.case
 if c and c.started and stages[c.stage]then
  local elapsed=core.elapsed(now,c.started)
  if not elapsed then self:reset('Таймер истёк некорректно. Проверьте факты вручную.');return end
  if elapsed>=c.seconds*1000 then
   c.expired=true
   if not c.announced and s.focused and not s.paused and not s.blocked then
    c.announced=true
    if self.env.notice then self.env.notice(stages[c.stage].title..': срок истёк. Проверьте фактический результат в игре. Таймер сам не считает право реализованным. В «Трафик и погоня → Задержание и права» доступны отметка результата и фиксация /time + F8.')end
   end
  end
 end
end
function T:view()
 local c=copy(self.case);if not c then return {message=self.message}end
 c.remaining=c.started and math.max(0,c.seconds-math.floor((core.elapsed(self.now,c.started)or 0)/1000))or nil
 c.title=stages[c.stage]and stages[c.stage].title or'Проверьте следующий шаг'
 if stages[c.stage]then c.official=c.seconds==stages[c.stage].seconds end
 return c
end
return M

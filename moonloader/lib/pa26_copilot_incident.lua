-- Contact and observations for the existing 10-55 Copilot.
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local vehicle=require 'pa26_vehicle'
local vehicleTypes=require 'pa26_vehicle_types'
local M={}

local function same(a,b)
 return a and b and a.id==b.id and a.name==b.name and a.generation==b.generation and a.ped==b.ped
end
local function point(v)
 return v and core.finite(v.x)and core.finite(v.y)and core.finite(v.z)
end
local function dist(a,b)
 if point(a)and point(b)then return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)end
end
local function remove(self,action)
 for index=#self.offers,1,-1 do
  if self.offers[index].action==action then table.remove(self.offers,index)end
 end
end
local function canPrompt(s)
 return s and s.session and s.alive and s.focused and not s.paused and not s.blocked and s.onDuty and s.radioEnabled and
  not s.modal and not s.typing and not s.recording and not s.wheel and not s.alertPending and not s.ownUi and not s.busy
end

function M.install(C)
 function C:beginIncident()
  if self.phase~='10-55'or not self.car then return end
  if not self.incident then
   self.incident={life=self.life,car=model.copy(self.car),own=model.copy(self.env.vehicle.lastOwnIdentity or self.env.vehicle.own),
    area=self.state.area or'',square=self.state.map_square or'',origin=model.copy(self.car)}
  end
  if not self.car.stale then self.lastCar=model.copy(self.car)end
  return self.incident
 end

 function C:stopDriver(atWindow,cfg)
  local s,c,driver=self.state,self.car,self.driverLive
  if self.phase~='10-55'or not s or not s.session or not s.alive or s.incapacitated or s.inVehicle or
   not c or c.stale or not driver or driver.stale or not same(driver,self.driver)then return end
  local radius=atWindow and cfg.window_interaction_distance or self.env.vehicle.env.settings().approach_distance+2
  if not core.finite(c.distance)or c.distance>radius or not core.finite(driver.distance)or driver.distance>radius then return end
  if atWindow then
   local class=vehicleTypes.class(c.model_id)
   if not(class=='car'or class=='van'or class=='truck'or class=='bus')or not self:seatedDriver()then return end
  end
  return driver
 end

 function C:stopContactStarted()
  local i=self.incident
  return i and(i.greeted or i.documentsRequested or i.reasonExplained)or false
 end

 function C:recordStopContact(stage)
  local i=self:beginIncident()
  if not i then return false end
  i[stage]=true
  i.onFoot=true
  if stage=='documentsChecked'then
   i.documentsRequested=true
   local p=self.env.position and self.env.position()
   i.checkedPosition=point(p)and{x=p.x,y=p.y,z=p.z}or nil
  end
  self.windowAwait=nil
  remove(self,'approach');remove(self,'window_question');remove(self,'window_knock')
  if stage=='introduced'then i.greeted=true;i.badge=true;remove(self,'greet_stop')end
  if i.documentsRequested then remove(self,'documents')end
  if i.reasonExplained then remove(self,'explain_stop')end
  return true
 end

 function C:markStopContact(stage)
  if not self.env.settings().enabled or not self:stopDriver(false)or self.intent or self.queued then
   return nil,'Подойдите к водителю текущей 10-55 и дождитесь окончания действия.'
  end
  if stage~='introduced'and stage~='documentsRequested'and stage~='documentsChecked'and stage~='reasonExplained'then return false end
  return self:recordStopContact(stage)
 end

 function C:observeManualCommand(line)
  if self.phase~='10-55'or not self.state or self.state.demo or type(line)~='string'or #line>4096 or not core.validUtf8(line)then return false end
  local head,args=line:match('^%s*/([A-Za-z]+)%s*(.-)%s*$');head=head and head:lower()
  if head=='ud'then
   local driver=self:stopDriver(false)
   if not driver or not args:match('^%d+$')or tonumber(args)~=driver.id then return false end
   local i=self:beginIncident();i.ud=true
   return self:recordStopContact('introduced')
  elseif head=='r'or head=='f'then
   local body=model.casefold(args)
   for _,word in ipairs({'10-99','заверш','отмен','ранее','прошл','планир','не провожу','не начина','обсужд','пример'})do if body:find(word,1,true)then return false end end
   local direct=body:find('провожу остановку',1,true)or body:find('провожу 10-55',1,true)or body:find('начинаю 10-55',1,true)
   local lead=body:gsub('^%s*%b[]%s*',''):gsub('^%s*%d+%-%a%-%d+%s*[,:%-]?%s*','')
   if direct or lead:match('^10%-55[%s,%.]')or lead=='10-55'then
    self.done.stop=true;self.stopReportOffered=true;remove(self,'stop');return true
   end
  end
  return false
 end

 function C:observeContactBinding(q)
  if self.phase~='10-55'then return end
  local p=q.plan
  local ref=p.binding and p.binding.author_ref
  if q.demo or p.demo or not q.sent or q.sent==0 or(ref~='A02'and ref~='A14')then return end
  local driver=self:stopDriver(false)
  local target=p.target
  -- A verified executor target may predate generation-aware binding snapshots.
  if not driver or not target or target.id~=driver.id or target.name~=driver.name or target.ped~=driver.ped or
   (target.generation~=nil and target.generation~=driver.generation)then return end
  local stamp=p.bindingContext
  if ref=='A14'and stamp and stamp.life==self.life and vehicle.same(stamp.car,self.car)then
   local stock=require('pa26_author_rp').bindings['14']
   if p.binding.script==stock.script or p.binding.script==stock.rp_context.bike_script then
    self.done.approach=true
    self.inspectedDriver=model.copy(driver)
   end
  end
  local speech=model.casefold(table.concat(p.lines or{},' '))
  if speech:find('паспорт',1,true)and speech:find('лицензи',1,true)and
   (speech:find('предъявите',1,true)or speech:find('передайте',1,true))then
   self:recordStopContact('documentsRequested')
  end
 end

 function C:windowTiming(q)
  local s,cfg=self.state,self.env.settings()
  if not q or not cfg.enabled or not s or not s.onDuty or not s.radioEnabled or not s.focused or
   q.life~=self.life or q.session~=s.session or q.ped~=s.ped or q.demo~=s.demo or
   not vehicle.same(q.car,self.car)or not same(q.driver,self:stopDriver(true,cfg))then return end
  local age=core.elapsed(self.now,q.at)
  local shownAge=q.shownAt and core.elapsed(self.now,q.shownAt)
  if not age or q.shownAt and(not shownAge or shownAge>=q.duration)or not q.shownAt and age>=q.delay+q.duration then return end
  return age>=q.delay,q.duration-(shownAge or 0)
 end

 function C:windowCandidate()
  local q=self.windowAwait
  if not q or not canPrompt(self.state)or self.intent or self.queued then return end
  local ready,remaining=self:windowTiming(q)
  if not ready then return end
  return {owner='vehicle',token=q.token,mode='confirm',title=q.title,status='10-55 · '..q.driver.name..' ['..q.driver.id..']',
   body='Отметьте, что ответил водитель.',hint='ДА — перейти к представлению. НЕТ — предложить постучать.',
   full=true,priority=45,serial=q.at,remaining=remaining,duration=q.duration,unseen=q.shownAt==nil,shortcut={key=0}}
 end

 function C:windowAnswer(answer,token)
  local q=self.windowAwait
  if not q or token and(token~=q.token or not q.shownAt or not canPrompt(self.state))then
   return nil,'Ответ об окне устарел. При необходимости задайте вопрос заново.'
  end
  local ready=self:windowTiming(q)
  if ready==nil or answer~='skip'and(not ready or(answer~='open'and answer~='closed'))then
   return nil,'Дождитесь вопроса об окне у текущего водителя.'
  end
  self.windowAwait=nil
  if answer=='skip'then self.windowSkipped=true;return true end
  self.windowReply=answer
  return true
 end

 function C:advanceStopContact(s,i,cfg)
  if not canPrompt(s)or self.windowAwait or self.groundRequest or not self:stopDriver(false)then return end
  if self:stopContactStarted()then
   if not cfg.ground_offer then return end
   if i.documentsRequested then
    if not i.reasonExplained then self:offer('explain_stop')end
   elseif i.greeted and not i.introduced and not i.reasonExplained and(not i.badge or cfg.stop_greeting_ud)then
    self:offer('greet_stop')
   elseif not i.reasonExplained and self:documentsNeedGround(cfg)then
    self:offer('explain_stop')
   else
    self:offer('documents')
   end
   return
  end
  if self.windowReply=='closed'and self:stopDriver(true,cfg)then
   self:offer('window_knock')
   return
  end
  if self.windowReply=='open'or self.windowSkipped or self.done.approach and(not cfg.window_offer or not self:seatedDriver()or
   not self:windowVehicle())then
   if cfg.ground_offer then self:offer('greet_stop')end
   return
  end
  if cfg.window_offer and self.done.approach and self:stopDriver(true,cfg)then self:offer('window_question')end
 end

 function C:windowVehicle()
  local class=self.car and vehicleTypes.class(self.car.model_id)
  return class=='car'or class=='van'or class=='truck'or class=='bus'
 end

 function C:incidentStep(s,now)
  local i=self:beginIncident();if not i then return end
  local c=self.car;local cfg=self.env.settings()
  if not i.own and s.inVehicle then i.own=model.copy(self.env.vehicle.lastOwnIdentity or self.env.vehicle.own)end
  if not c.stale and point(c)then
   local age=i.lastPoint and core.elapsed(now,i.lastPoint.at);local delta=dist(c,i.lastPoint)
   local travelled=dist(c,i.origin)or 0
   local moving=age and age>=100 and age<=5000 and delta and delta<=self.env.vehicle.env.settings().max_motion_distance
   local fleeing=moving and self:seatedDriver()and delta*1000/age>=cfg.flight_min_speed and
    travelled>=cfg.departure_distance and travelled>i.lastPoint.travelled
   if age and age>=100 then
    i.flightSamples=fleeing and(i.flightSamples or 0)+1 or 0
    i.confirmedFlight=i.flightSamples>=cfg.flight_min_samples
    if i.confirmedFlight then i.flightAt=now end
   end
   if age and age>0 and age<=5000 and delta and delta>=cfg.stationary_delta and delta<=self.env.vehicle.env.settings().max_motion_distance and
    travelled>=cfg.departure_distance then i.departed=true end
   if not age or age>=100 then i.lastPoint={x=c.x,y=c.y,z=c.z,travelled=travelled,at=now}end
  else i.flightSamples=0;i.confirmedFlight=false;i.flightAt=nil end
  if not self:seatedDriver()then i.flightAt=nil end

  local own=self.env.vehicle.own
  local returned=i.onFoot and s.inVehicle and own and i.own and own.handle==i.own.handle and
   (i.own.id==nil or own.id==i.own.id)and(i.own.model_id==nil or own.model_id==i.own.model_id)
  local live=self.driverLive
  local away=live and core.finite(live.distance)and live.distance>=cfg.departure_distance or c.stale==true
  if self:seatedDriver()and core.finite(c.distance)and c.distance>=cfg.departure_distance then away=true end
  local checkedAndLeft=i.documentsChecked and(away or not live)and
   (dist(i.checkedPosition,self.env.position and self.env.position())or 0)>=cfg.departure_distance
  local readyToFinish=i.reasonExplained and(returned or away)or checkedAndLeft
  if not readyToFinish then
   remove(self,'finish')
   if not i.finishDeclined then i.finishOffered=nil end
  elseif cfg.finish_offer and canPrompt(s)and not(cfg.flee_offer and cfg.immediate_flight_offer and self:canEscalateStop())then
   if not i.finishDeclined then remove(self,'pursuit')end
   if i.finishOffered and not i.finishDeclined and not self.intent and not self.queued and(core.elapsed(now,i.finishOfferAt)or 0)>=cfg.toast_ms then
    local present=false;for _,p in ipairs(self.offers)do if p.action=='finish'then present=true;break end end
    if not present then i.finishOffered=nil end
   end
   if not i.finishOffered then
    self:offer('finish')
    for _,p in ipairs(self.offers)do if p.action=='finish'then i.finishOffered=true;i.finishOfferAt=now;break end end
   end
  end

  if self.windowAwait and self:windowTiming(self.windowAwait)==nil then
   self.windowAwait=nil
  end
  self:advanceStopContact(s,i,cfg)
 end

 function C:incidentLine(p,index)
  local stage=p.prepared.contactSteps[index]
  if stage=='window_question'then
   self.windowReply=nil;self.windowSkipped=nil
   self.done.window_knock=nil;self.dismissed.window_knock=nil
   self.windowAwait={token=p.token..':answer',at=self.now,life=self.life,session=p.session,ped=p.ped,demo=p.demo,
    car=model.copy(p.car),driver=model.copy(p.contactDriver),title=p.prepared.windowPrompt,
    delay=p.cfg.window_answer_delay_ms,duration=p.cfg.window_reply_ms}
  elseif stage=='window_knock'then
   self.windowReply=nil
   self.done.window_question=nil;self.dismissed.window_question=nil
  elseif stage and self.phase=='10-55'and p.contactDriver then
   self:recordStopContact(stage)
  end
 end
end
return M

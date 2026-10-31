-- Pure incident/contact observations; extends the existing confirmed Copilot flow.
local core=require 'pa26_core';local model=require 'pa26_bindings';local vehicle=require 'pa26_vehicle'
local M={}
local function same(a,b)return a and b and a.id==b.id and a.name==b.name and a.generation==b.generation end
local function point(v)return v and core.finite(v.x)and core.finite(v.y)and core.finite(v.z)end
local function dist(a,b)if point(a)and point(b)then return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)end end
local function remove(self,action)local keep={};for _,p in ipairs(self.offers)do if p.action~=action then keep[#keep+1]=p end end;self.offers=keep end
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
 function C:observeManualCommand(line,source)
  if self.state and self.state.demo or type(line)~='string'or #line>4096 or not core.validUtf8(line)then return false end
  local i=self:beginIncident();if not i then return false end
  local head,args=line:match('^%s*/([A-Za-z]+)%s*(.-)%s*$');head=head and head:lower()
  if head=='ud'then
   if self.state.inVehicle or not self.car or self.car.stale or not self.driverLive or not same(self.driver,self.driverLive)then return false end
   local radius=self.env.vehicle.env.settings().approach_distance+2
   if not core.finite(self.car.distance)or self.car.distance>radius or not core.finite(self.driverLive.distance)or self.driverLive.distance>radius then return false end
   if args~=''and(not args:match('^%d+$')or tonumber(args)~=self.driver.id)then return false end
   self.manualUdDone=true;i.onFoot=true;self.windowAwait=nil;remove(self,'explain_stop');return true
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
 function C:incidentStep(s,now)
  local i=self:beginIncident();if not i then return end
  local c=self.car;local cfg=self.env.settings()
  if not i.own and s.inVehicle then i.own=model.copy(self.env.vehicle.lastOwnIdentity or self.env.vehicle.own)end
  if not c.stale and point(c)then
   local age=i.lastPoint and core.elapsed(now,i.lastPoint.at);local delta=dist(c,i.lastPoint)
   if age and age>0 and age<=5000 and delta and delta>=cfg.stationary_delta and delta<=self.env.vehicle.env.settings().max_motion_distance and
    (dist(c,i.origin)or 0)>=cfg.departure_distance then i.departed=true end
   i.lastPoint={x=c.x,y=c.y,z=c.z,at=now}
  end
  local contact=self.manualUdDone or self.done.explain_stop
  if contact and not s.inVehicle then i.onFoot=true end
  local own=self.env.vehicle.own
  local returned=contact and i.onFoot and s.inVehicle and own and i.own and own.handle==i.own.handle and
   (i.own.id==nil or own.id==i.own.id)and(i.own.model_id==nil or own.model_id==i.own.model_id)
  local unavailable=self.manualUdDone and c.stale==true
  local canOffer=not s.modal and not s.typing and not s.recording and not s.wheel and not s.alertPending and not s.ownUi and not s.busy
  if contact and cfg.finish_offer and canOffer and(returned or i.departed or unavailable)then
   if not i.finishDeclined then remove(self,'pursuit')end
   if i.finishOffered and not i.finishDeclined and not self.intent and not self.queued and(core.elapsed(now,i.finishOfferAt)or 0)>=cfg.toast_ms then
    local present=false;for _,p in ipairs(self.offers)do if p.action=='finish'then present=true;break end end
    if not present then i.finishOffered=nil end
   end
   if not i.finishOffered then
    self:offer('finish')
    for _,p in ipairs(self.offers)do if p.action=='finish'then i.finishOffered=true;i.finishOfferAt=now;break end end
   elseif i.finishDeclined and i.departed and not i.pursuitOffered then i.pursuitOffered=true;self.dismissed.pursuit=nil;self:offer('pursuit')end
  end
  if self.windowAwait then
   local age=core.elapsed(now,self.windowAwait.at)
   if c.stale or not same(self.windowAwait.driver,self.driverLive)or not age or age>cfg.window_reply_ms then self.windowAwait=nil end
  end
  if cfg.window_offer and self.done.approach and not contact and not c.stale and not s.inVehicle and self.driverLive and
   core.finite(self.driverLive.distance)and self.driverLive.distance<=cfg.window_interaction_distance then self:offer('window_question')end
 end
 function C:windowAnswer(answer,manual)
  local i=self.incident;local q=self.windowAwait or self.windowQuestion
  if not i or self.phase~='10-55'or not self.car or self.car.stale or not self.driverLive or not same(self.driver,self.driverLive)then return false end
  if not manual and(not q or not same(q.driver,self.driverLive)or q.life~=self.life)then return false end
  self.windowAwait=nil
  remove(self,'window_question');remove(self,'window_knock');self.dismissed.window_question=true
  if answer=='skip'then self.windowSkipped=true;self.windowQuestion=nil;self.windowReply=nil;return true end
  if answer~='open'and answer~='closed'then return false end
  self.windowReply=answer
  if answer=='open'then
   remove(self,'window_knock')
   if not self.manualUdDone and not self.done.explain_stop then self:offer('explain_stop')end
  elseif not self.manualUdDone and not self.done.explain_stop then self:offer('window_knock')end
  return true
 end
 function C:observeWindowReply(line)
  if not self.state or self.state.demo then return false end
  local q=self.windowAwait or self.windowReply=='closed'and self.windowQuestion
  if not q or type(line)~='string'or #line>1024 or not core.validUtf8(line)then return false end
  local age=core.elapsed(self.now,q.at);if not age or age>self.env.settings().window_reply_ms then return false end
  local text=line:gsub('{%x%x%x%x%x%x}',''):gsub('%s+',' ')
  local body,nick=text:match('^%s*(.-)%s*%(%s*([A-Za-z_][A-Za-z_0-9]*)%s*%)%s*$')
  if not body or not same(q.driver,self.driverLive)or q.life~=self.life or nick:lower()~=q.driver.name:lower()or nick:lower()==tostring(self.state.local_nick or self.state.my_nick):lower()then return false end
  body=model.casefold(body):gsub('[%.!%?]+$',''):match('^%s*(.-)%s*$')
  local open={['окно открыто']=true,['да']=true,['да, открыто']=true,['открыто']=true}
  local closed={['окно закрыто']=true,['нет']=true,['нет, закрыто']=true,['закрыто']=true}
  return(open[body]or closed[body])and self:windowAnswer(open[body]and'open'or'closed',false)or false
 end
 function C:repeatWindowQuestion()
  if not self.incident or self.phase~='10-55'then return nil,'Нет активной остановки.'end
  self.done.window_question=nil;self.dismissed.window_question=nil;self.windowAwait=nil;self.windowSkipped=nil;self.windowQuestion=nil;self.windowReply=nil
  remove(self,'window_question');self:offer('window_question');return true
 end
 function C:incidentCompleted(action,p)
  if action=='explain_stop'and self.incident and not self.state.inVehicle then self.incident.onFoot=true end
  if action=='window_question'then
   local q={at=self.now,life=self.life,driver=model.copy(self.driverLive)}
   self.windowQuestion=q;self.windowAwait=not p.demo and model.copy(q)or nil;self.windowReply=nil;self.windowSkipped=nil
  elseif action=='window_knock'and not self.manualUdDone and not self.done.explain_stop then self:offer('explain_stop')end
 end
end
return M

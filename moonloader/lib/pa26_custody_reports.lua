-- A real outgoing /cuff or /arrest proposes a radio report, never a second command.
-- No chat editing hooks, scans, persistence or automatic server-success claims.
local core=require 'pa26_core';local model=require 'pa26_bindings'
local prefs=require 'pa26_custody_settings';local radio=require 'pa26_radio_text'
local notices=require 'pa26_notifications';local grid=require 'pa26_map_grid'
local shared=require 'pa26_patrol_settings'
local M={};local C={};C.__index=C
local kinds={cuff='detention',arrest='jail'}
local function canObserve(s)return s and s.session and s.alive==true and s.focused==true and not s.paused and not s.demo and core.finite(s.ped)end
function M.new(env)return setmetatable({env=env,offers={},serial=0,epoch=1,recent={}},C)end
function C:settings()return self.env.settings()or prefs.defaults()end
function C:reset(reason)
 if self.queued and self.env.cancel then self.env.cancel(self.queued.token,reason)end
 self.offers={};self.intent=nil;self.queued=nil;self.recent={};self.epoch=self.epoch+1
end
function C:invalidate(id)
 for i=#self.offers,1,-1 do if self.offers[i].id==id then table.remove(self.offers,i)end end
 if self.intent and self.intent.id==id then self.intent=nil end
 if self.queued and self.queued.id==id then self:reset('Участник команды изменился.')end
 self.recent[id]=nil
end
function C:line(kind,values,cfg)
 cfg=cfg or self:settings();local row=cfg[kind]
 if not row then return nil,'Неизвестный доклад.'end
 local template,err=prefs.template(row.template);if not template then return nil,err end
 local v=model.copy(values or{});v.count='1';v.subject=v.subject or'один подозреваемый'
 template,err=require('pa26_report_context').directionTemplate(template,v);if not template then return nil,err end
 v,err=grid.reportValues(v,template);if not v then return nil,err end
 local missing
 local body=core.expandGender(template,v.gender):gsub('{([a-z_]+)}',function(k)
  local value=v[k];if value==nil or type(value)~='string'and not core.finite(value)then missing=k;return''end
  value=shared.text(tostring(value),1024);if not value then missing=k;return''end
  if value==''and k~='local_tag'and k~='prison_tag'and k~='global_tag'then missing=k end
  if(k=='local_tag'or k=='prison_tag'or k=='global_tag')and value~=''then return value..' 'end
  return value
 end)
 if missing then return nil,'Заполните данные доклада: {'..missing..'}.'end
 return radio.prepare(row.channel,body,self.env.codec,v.radioText,v.rpText,v.my_nick)
end
function C:create(kind,id,source)
 local cfg=self:settings();local s=self.state
 if not cfg.enabled or not cfg[kind]or not cfg[kind].enabled then return nil,'Этот доклад отключён в настройках событий.'end
 if not canObserve(s)or not s.onDuty or not s.radioEnabled then return nil,'Включите службу и рацию PA; демо не создаёт реальные доклады.'end
 if #self.offers>=cfg.queue_limit then return nil,'Очередь докладов заполнена. Подтвердите или отклоните текущие.'end
 local values=self.env.values and self.env.values(s)or model.copy(s)
 local prepared,err=self:line(kind,values,cfg);if not prepared then self.message=err;return nil,err end
 local identity=id and self.env.identity and self.env.identity(id)
 self.serial=self.serial+1
 local p={kind=kind,id=id,identity=identity and model.copy(identity),session=s.session,ped=s.ped,at=self.now,
  token='custody:'..self.epoch..':'..self.serial,serial=self.serial,remaining=cfg.toast_ms,source=source or'F4',
  values=model.copy(values),prepared=prepared,cfg=model.copy(cfg),epoch=self.epoch}
 self.offers[#self.offers+1]=p;self.message=nil;return p
end
function C:observe(line)
 if type(line)~='string'or #line>512 or line:find('%c')then return false end
 local head,id,tail=line:match('^/([A-Za-z]+)%s+(%d+)(.*)$');head=head and head:lower();id=tonumber(id)
 if not core.validId(id)or tail~=''and not tail:match('^%s')then return false end
 if head=='uncuff'then self:invalidate(id);return false end
 local kind=kinds[head];if not kind or not canObserve(self.state)then return false end
 local old=self.recent[id];local age=old and core.elapsed(self.now,old.at)
 if old and age and age<self:settings().duplicate_ms and old.kind==kind then return false end
 if kind=='jail'then for i=#self.offers,1,-1 do if self.offers[i].id==id and self.offers[i].kind=='detention'then table.remove(self.offers,i)end end end
 local p,err=self:create(kind,id,'/'..head..' '..id..' · передано клиенту')
 if p then
  self.recent[id]={at=self.now,kind=kind}
  local n=0;for _ in pairs(self.recent)do n=n+1 end;if n>32 then self.recent={[id]=self.recent[id]}end
 end
 if not p and err and self:settings().enabled and self:settings()[kind].enabled and self.env.notice then self.env.notice(err)end
 return p~=nil
end
function C:observed(line)
 if type(line)~='string'then return false end
 local head,id=line:match('^/([A-Za-z]+)%s+(%d+)');head=head and head:lower();id=tonumber(id)
 local r=id and self.recent[id];local age=r and core.elapsed(self.now,r.at)
 return r and age and age<self:settings().duplicate_ms and r.kind==kinds[head]or false
end
function C:find(token)for _,p in ipairs(self.offers)do if p.token==token then return p end end end
function C:valid(p)
 local s=self.state;local cfg=self:settings();local age=p and core.elapsed(self.now,p.at)
 if not p or not canObserve(s)or p.epoch~=self.epoch or p.session~=s.session or p.ped~=s.ped or not age or age>=cfg.ttl_ms or
  not s.onDuty or not s.radioEnabled or not self.env.equal(p.cfg,cfg)then return false end
 if p.id and self.env.identity then local fresh=self.env.identity(p.id)
  if not self.env.equal(p.identity,fresh)then return false end
 end
 local current=self.env.values and self.env.values(s)or s
 if current.unit~=p.values.unit then return false end
 local values=model.copy(p.values);values.radioText=current.radioText;values.rpText=current.rpText;values.my_nick=current.my_nick
 local ready=self:line(p.kind,values,cfg)
 return ready and radio.key(ready)==radio.key(p.prepared)and ready.rpSignature==p.prepared.rpSignature and ready.textSignature==p.prepared.textSignature or false
end
function C:shown(token)local p=self:find(token);if p then p.seen=true;p.painted=self.now end end
function C:decide(token,yes)
 local p=self:find(token)
 if type(yes)~='boolean'or not p or not p.seen or not notices.safe(self.state)or not self:valid(p)then return false end
 for i,r in ipairs(self.offers)do if r==p then table.remove(self.offers,i);break end end
 if yes then if self.intent or self.queued then return false end;self.intent=p end
 return true
end
function C:validPlan(plan)
 local p=self.queued
 return p and plan.custodyReport and plan.custodyReport.token==p.token and self:valid(p)and
  not self.state.typing and not self.state.modal and radio.key(plan)==radio.key(p.prepared)or false
end
function C:onExecution(kind,q)
 local p=self.queued
 if not p or not q or not q.plan.custodyReport or q.plan.custodyReport.token~=p.token then return end
 if kind=='sent_line'then
  if not core.finite(q.index)or not p.prepared.steps[q.index]then return end
  p.sentSteps=p.sentSteps or{};if p.sentSteps[q.index]then return end;p.sentSteps[q.index]=true
  p.sent=(p.sent or 0)+1
  if p.sent>=#p.prepared.steps then self.queued=nil;self.message='Доклад передан клиенту; принятие определяет сервер.'end
 elseif kind=='cancelled'then self.queued=nil;self.message='Доклад отменён. Уже переданные строки не повторяются.'end
end
function C:tick(s,now)
 local previous=self.state;local oldNow=self.now;local dt=oldNow and core.elapsed(now,oldNow)
 if not core.finite(now)then self:reset('Таймер недоступен.');return end
 self.state=s;self.now=now
 if previous and(not dt or previous.session~=s.session or previous.ped~=s.ped or previous.demo~=s.demo or not s.alive)then self:reset('Сеанс или персонаж изменился.')end
 local cfg=self:settings()
 if self.cfgRef~=cfg then
  if self.cfgSnapshot and not self.env.equal(self.cfgSnapshot,cfg)then self:reset('Настройки доклада изменились.')end
  self.cfgRef=cfg;self.cfgSnapshot=model.copy(cfg)
 end
 if not cfg.enabled then if #self.offers>0 or self.intent or self.queued then self:reset('Доклады отключены.')end;return end
 for i=#self.offers,1,-1 do local p=self.offers[i];local age=core.elapsed(now,p.at)
  if not age or age>=cfg.ttl_ms then table.remove(self.offers,i)
  elseif p.painted==oldNow and dt and dt<=5000 and notices.safe(previous)and notices.safe(s)then
   p.remaining=math.max(0,p.remaining-dt);if p.remaining==0 then table.remove(self.offers,i)end
  end
 end
 if self.queued and not self:valid(self.queued)then self:reset('Доклад устарел.');return end
 local p=self.intent
 if p then
  if not self:valid(p)then self.intent=nil;self.message='Доклад устарел. Подготовьте его снова в F4.';return end
  if s.typing or s.modal or s.blocked then self.intent=nil;self.message='Доклад отменён при открытии ввода. Повторите его из F4.';return end
  if s.busy or not notices.safe(s)or s.wheel then return end
  self.intent=nil;self.queued=p
  local b=model.newBinding(999999982);b.name=p.cfg[p.kind].title;b.category='Доклады';b.script=p.prepared.line
  local plan={binding=b,requirements={target=false,closest=false},session=p.session,createdAt=now,demo=false,has_command=true,
   steps=model.copy(p.prepared.steps),lines=model.copy(p.prepared.lines),wire=model.copy(p.prepared.wires),
   rpSignature=p.prepared.rpSignature,textSignature=p.prepared.textSignature,automatic={kind='custody_report'},custodyReport={token=p.token}}
  local ok,err=self.env.start(plan)
  if not ok then self.queued=nil;self.message='Доклад не передан: '..tostring(err);if self.env.notice then self.env.notice(self.message)end end
 end
end
function C:candidates()
 local out={};local s=self.state
 if not canObserve(s)or not s.onDuty or not s.radioEnabled or self.intent or self.queued then return out end
 for _,p in ipairs(self.offers)do
  out[#out+1]={owner='custody',token=p.token,title=p.cfg[p.kind].title,body=p.prepared.line,
   hint=p.cfg.hint,status=p.source,mode='confirm',full=true,unseen=not p.seen,priority=18,serial=p.serial,
   remaining=p.remaining,duration=p.cfg.toast_ms,yes='Y · Передать',no='N · Не передавать',shortcut={key=0,ctrl=false,alt=false,shift=false}}
 end
 return out
end
function C:view()return {pending=self.intent~=nil or self.queued~=nil,message=self.message,offers=#self.offers}end
return M

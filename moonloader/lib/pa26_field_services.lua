-- One opt-in service owner in the existing main loop. No independent thread,
-- chat input listener, filesystem polling or native address dereference.
local core=require 'pa26_core';local copy=require('pa26_bindings').copy
local nav=require 'pa26_navigation';local M={};local F={};F.__index=F
function M.new(env)
 local path=(env.openRoads or env.roadSources)and require('pa26_navigation_roads').new({open=env.openRoads,hash=env.roadHash,
  openCandidate=env.roadSources and function(index,custom)return env.roadSources:open(index,custom)end})or require('pa26_navigation_path').new()
 local instance=setmetatable({env=env,navigation=nav.new({path=path,clock=env.clock}),
  coordinates=require('pa26_coord_share').new(env),cruiser=require('pa26_cruiser_assist').new(),
  pinned=require('pa26_pinned_note').new(),serial=0,snapshot={status='Новые сервисы выключены'}},F)
 if env.perf then
  if path.tick then path.tick=env.perf:wrap('fieldPath',path.tick)end
  for _,r in ipairs({{instance.navigation,'tick','fieldNavigation'},{instance.navigation,'calculate','fieldPath'},
   {instance.coordinates,'observe','fieldCoordinates'},{instance.cruiser,'tick','fieldCruiser'},
   {instance.pinned,'draw','fieldPinned'},{instance,'reset','fieldCleanup'}})do r[1][r[2]]=env.perf:wrap(r[3],r[1][r[2]])end
 end
 return instance
end
function F:reset(reason)
 if self.navigation.env.path.reset then self.navigation.env.path:reset()end
 self.navigation:reset(nil);self.coordinates:reset();self.cruiser:release(reason);self.intent=nil;self.queued=nil
 self.proposal=nil;self.state=nil;self.previewContext=nil;self.previewAt=nil;self.markSettingsSource=nil
 self.snapshot={status=reason or'Отключено'};self.observedAt=nil;self.sampleAt=nil;self.on=false;self.serial=self.serial+1
 self.renderFailed=nil;self.projection=nil;self.renderCache={};self.routeRevision=nil;self.routePoints=nil;self.routeMaximum=nil
end
function F:observe(text,source,now)
 local cfg=self.env.library().field;if not cfg.enabled or not cfg.coordinates.enabled or not cfg.coordinates.observe or not self.state then return end
 self.coordinates:observe(text,now,self.state,cfg.coordinates)
end
function F:checkpoint(kind,p)
 local cfg=self.env.library().field;if not cfg.enabled or not cfg.navigation.enabled or not self.state then return end
 if p then self.navigation:put(kind,p,self.now)else self.navigation:remove(kind,self.now)end
end
function F:tick(s,gameNow,input)
 local lib=self.env.library();local cfg=lib.field
 if not cfg.enabled then if self.on then self:reset('Новые сервисы выключены')end;return end
 self.on=true
 local now=self.env.clock and self.env.clock()or gameNow
 if not core.finite(now)then self:reset('Монотонный таймер недоступен');return end
 if self.state and(self.state.session~=s.session or self.state.ped~=s.ped or self.now and now<self.now)then self:reset('Сеанс изменился');self.on=true end
 self.now=now;self.state=s
 local path=self.navigation.env.path
 if path.tick then
  if cfg.navigation.enabled then
   if path.prepare and path:prepare(cfg.navigation.road_external)then self.navigation:invalidatePath()end
   -- The ordinary Esc map owns a cursor. It must not be confused with chat,
   -- a server dialog or a PA editor: pure data search may continue there.
   local pauseMenu=input and input.paused==true and input.focused==true and input.alive==true and
    input.menuBlocked==false and input.chatActive==false and input.dialogActive==false and
    not input.window and not input.typing and not input.recording and not input.incapacitated
   path:tick(cfg.navigation,s.focused==true and not s.typing and(not s.blocked or pauseMenu)and s.interior==0)
  elseif path.phase~='idle'then path:reset()end
 end
 if self.navigation.session~=s.session then self.navigation:reset(s.session)end
 -- Safety release is immediate; the native backend is intentionally absent.
 self.cruiser:tick(s,cfg.cruiser)
 -- Approval safety follows current input ownership, independently of slow world sampling.
 self.coordinates:tick(s,now,cfg.coordinates)
 if not cfg.coordinates.enabled and self.navigation.sources.mark then self.navigation:remove('mark',now);self.sampleAt=nil end
 local observe=s.paused and math.min(50,cfg.navigation.observe_ms)or cfg.navigation.observe_ms
 local due=not self.sampleAt or now-self.sampleAt>=observe
 if due then
  self.sampleAt=now
  if cfg.navigation.enabled and cfg.navigation.observe_waypoint and s.session and s.interior==0 and self.env.waypoint then
   local ok,a,x,y,z=pcall(self.env.waypoint)
   if not ok then a=nil end
   local status,p=nav.waypoint(a,x,y,z)
   self.navigation:observe(status,p,now,cfg.navigation)
  end
  local effective=cfg.navigation
  if cfg.coordinates.enabled and not effective.enabled then
   if self.markSettingsSource~=effective then self.markSettings=copy(effective);self.markSettings.enabled=true;self.markSettings.native_path=false;self.markSettingsSource=effective end
   effective=self.markSettings
  end
  self.navigation:tick(s,now,effective)
  local accepted=self.coordinates.accepted;self.coordinates.accepted=nil
  if accepted and accepted.session==s.session and accepted.ped==s.ped then self.navigation:put('mark',accepted,now,cfg.coordinates.ttl_ms)end
  if accepted and nav.point(s)then self.navigation.distance=nav.distance(s,accepted);self.navigation.distanceKind='по прямой';self.navigation.status='Временная OOC-метка'end
  local mark=self.navigation.sources.mark
  if mark and cfg.coordinates.arrival_clear and s.interior==0 and nav.point(s)and not mark.height_unknown and math.abs((s.z or 0)-mark.z)<8 and nav.distance(s,mark)<cfg.navigation.arrival then self.navigation:remove('mark',now)end
  self.pinned:update(lib.notes,cfg.pinned,self.env.revision())
  local view=self.navigation:view();view.cruiser=self.cruiser:view();view.roads=path.view and path:view()or{available=false,status='Дорожный backend недоступен'}
  if self.routeRevision~=view.revision or self.routeMaximum~=cfg.navigation.max_segments then
   self.routeRevision=view.revision;self.routeMaximum=cfg.navigation.max_segments
   self.routePoints=require('pa26_navigation_render').simplify(view.points,cfg.navigation.max_segments+1)
  end
  view.points=self.routePoints
  if view.target and view.distance and cfg.navigation.hud then
   local source=({waypoint='GTA',mark='OOC',server='Сервер',race='Checkpoint',bulletin='Примерный район'})[view.target.kind]or'Метка'
   view.hud=string.format('Навигация · %s · %.0f м (%s)',source,view.distance,view.distanceKind or'по прямой')
  end
  self.snapshot=view
 end
 -- Confirmation validity uses revisions/tokens; no full settings serialization.
 if self.intent then
  local p=self.intent
  if not self:valid(p)then self.intent=nil;self.env.notice('Действие отменено: сцена или настройки изменились.');return end
  if s.typing or s.modal or s.blocked then self.intent=nil;return end
  if s.busy or s.wheel then return end
  self.intent=nil;self.queued=p
  local ok,why=self.env.start(p.plan);if not ok then self.queued=nil;self.env.notice(why)end
 end
end
function F:valid(p)
 local s=self.state;local age=p and core.elapsed(self.env.gameNow(),p.gameAt)
 return p and s and age and age<60000 and p.session==s.session and p.ped==s.ped and p.demo==s.demo and
  p.revision==self.env.revision()and s.focused and not s.paused and not s.typing and not s.blocked and s.alive and self.env.library().field.enabled
end
function F:previewText(text)
 local now=self.env.gameNow();local revision=self.env.revision()
 if not self.previewContext or self.previewRevision~=revision or not self.previewAt or not core.elapsed(now,self.previewAt)or core.elapsed(now,self.previewAt)>500 then
  self.previewContext=self.env.templateContext and self.env.templateContext()or{values={},gender='male'};self.previewRevision=revision;self.previewAt=now
 end
 local ctx=self.previewContext;local missing
 text=core.expandGender(text,ctx.gender):gsub('{([^{}]+)}',function(k)local v=ctx.values[k];if v==nil then missing=k;return''end;return tostring(v)end)
 if missing then return nil,'Не заполнена {'..missing..'}.'end;return text
end
function F:propose(kind,arg)
 local s=self.state;local lib=self.env.library();local cfg=lib.field
 if not cfg.enabled or not s or not s.session or not s.focused or s.paused or not s.alive then return nil,'Включите новые сервисы и дождитесь игровой сцены.'end
 local lines={};local label
 if kind=='share'then
  if not cfg.coordinates.enabled then return nil,'OOC-координаты выключены.'end
  local p,why=require('pa26_coord_share').format(s,cfg.coordinates,self.env.codec,s.area,s.map_square);if not p then return nil,why end
  lines={p.line};label='Передать координаты (OOC)?'
 elseif kind=='gnews'then
  local d=cfg.leadership
  if not d.enabled or not d.verified or d.source==''then return nil,'Сначала подтвердите синтаксис /gnews и доступ в настройках руководства.'end
  for _,line in ipairs(d.lines)do if line~=''then
   if line:find('[\r\n]')or line:match('^%s*[/@]')then return nil,'Объявление должно быть текстом без команд.'end
   lines[#lines+1]=d.command..' '..(d.tag~=''and d.tag..' | 'or'')..line
  end end
  if #lines~=1 and #lines~=3 then return nil,'Заполните одну или три строки объявления.'end
  label='Передать государственные новости?'
 elseif kind=='briefing'then
  local d=cfg.leadership;local r=d.briefings[arg and arg.index or 0];local i=arg and arg.line or 0
  if not d.enabled or not r or not r.lines[i]then return nil,'Выберите сохранённый инструктаж и строку.'end
  if r.lines[i]:match('^%s*[/@]')then return nil,'Строка инструктажа не должна начинаться с команды.'end
  lines={r.lines[i]};label='Произнести строку инструктажа?'
 else return nil,'Неизвестное действие.'end
 local steps={};local speechPlan={steps={},lines={},wire={}}
 for i,line in ipairs(lines)do
  local ctx=self.env.templateContext and self.env.templateContext()or{values={},gender='male'}
  local missing
  line=core.expandGender(line,ctx.gender):gsub('{([^{}]+)}',function(k)
   local value=ctx.values[k];if value==nil then missing=k;return''end;return tostring(value)
  end)
  if missing then return nil,'Не заполнена переменная {'..missing..'}.'end
  lines[i]=line
  if kind=='briefing'then
   local ready,why=require('pa26_rp_text').line(line,self.env.codec,lib.rp_text,ctx.values.my_nick)
   if not ready then return nil,why end
   local ok;ok,why=require('pa26_rp_text').append(speechPlan,ready);if not ok then return nil,why end
   steps=speechPlan.steps
  else
   local wire,why=core.encodeWire(line,self.env.codec);if not wire then return nil,why end
   if kind=='gnews'and #wire>cfg.leadership.channel_limit then return nil,'Строка /gnews превышает подтверждённый лимит.'end
   steps[#steps+1]={kind='message',text=line,wire=wire}
  end
  if kind=='gnews'and i<#lines then steps[#steps+1]={kind='wait',ms=cfg.leadership.delay_ms}end
 end
 if kind=='briefing'then lines=speechPlan.lines end
 self.serial=self.serial+1
 local p={token='field:'..self.serial,kind=kind,label=label,lines=lines,session=s.session,ped=s.ped,demo=s.demo,
  revision=self.env.revision(),gameAt=self.env.gameNow()}
 p.plan={binding={id=999999981,name=label,stat='none'},requirements={},session=s.session,createdAt=p.gameAt,demo=s.demo,
  steps=steps,lines=lines,has_command=kind~='briefing',fieldAction={token=p.token}}
 p.plan.rpSignature=speechPlan.rpSignature;p.plan.textSignature=speechPlan.textSignature
 self.proposal=p;return p
end
function F:accept(p)
 if self.proposal~=p or not self:valid(p)or self.intent or self.queued then return nil,'Предпросмотр устарел или другое действие ещё выполняется.'end
 self.proposal=nil;self.intent=p;return true
end
function F:validPlan(plan)return self.queued and plan.fieldAction and plan.fieldAction.token==self.queued.token and self:valid(self.queued)or false end
function F:execution(kind,q,line)
 if q and q.plan.fieldAction and self.queued and q.plan.fieldAction.token==self.queued.token and(kind=='completed'or kind=='cancelled')then self.queued=nil end
end
function F:clear(kind)
 if kind=='roads'then
  local path=self.navigation.env.path;if path.reset then path:reset()end
  self.navigation:invalidatePath()
 elseif kind=='mark'then self.navigation:remove('mark',self.now or 0)
 elseif kind=='resume'then self.navigation:resume(self.now or 0)
 else self.navigation:clear(self.now or 0)end
 self.sampleAt=nil
end
function F:paste(text)
 if not self.env.library().field.enabled or not self.env.library().field.coordinates.enabled then return nil,'Включите OOC-координаты в настройках инструментов.'end
 local p=require('pa26_coord_share').parse('Мои координаты: '..tostring(text or''))
 if not p then return nil,'Введите X Y Z, например: -1984 442 35.'end
 if not self.state or self.state.interior~=0 then return nil,'Выйдите из интерьера.'end
 self.serial=self.serial+1;p.token='coordinates:'..self.serial;p.serial=self.serial;p.at=self.now;p.duration=self.env.library().field.coordinates.offer_ms
 p.session=self.state.session;p.ped=self.state.ped;self.coordinates.offer=p;return true
end
return M

-- Pure tactical state machine. Native observation lives in main/world modules.
-- Suggestions never send; each accepted frozen plan uses the ordinary executor.
local core=require 'pa26_core';local model=require 'pa26_bindings';local radio=require 'pa26_radio_text'
local settings=require 'pa26_copilot_settings';local vehicleModel=require 'pa26_vehicle'
local dispatch=require 'pa26_dispatch'
local M={};local C={};C.__index=C
M.actions={{'stop_order','10-55 · Мегафон: остановиться у обочины'}, {'stop','10-55 · Доклад об остановке'},
 {'approach','10-55 · Подойти к фаре и осмотреть салон'}, {'high_risk','10-66 · CODE 3 и запрос экипажей'},
 {'risk_order','10-66 · Выбросить ключи и выйти'}, {'pursuit','10-57 VICTOR · Начать погоню'},
 {'foot','10-57 FOXTROT · Пешая погоня'}, {'finish','Завершить ситуацию'}}
M.actions[#M.actions+1]={'explain_stop','10-55 · Назвать причину и запросить документы'}
M.actions[#M.actions+1]={'explain_detention','Задержание · Основание и права'}
M.quick={{'call911','Вызов 9-1-1 · Код 3'},{'arrived','Прибыл на место · опрос граждан'},{'break_report','Перерыв · Код 7, до 15 минут'},{'lost','Потерян · Код 4 АДАМ'}}
M.dispatchActions=dispatch.actions
local carFree={call911=true,arrived=true,break_report=true,lost=true,explain_stop=true,documents=true,explain_detention=true}
for _,row in ipairs(dispatch.actions)do carFree[row[1]]=true end
 local labels={stop_order='Машина выбрана · Предложить остановиться?',tire='Погоня продолжается · Предупредить об огне по колёсам?',stop='Машина остановилась · Доложить о 10-55?',return_car='Водитель вышел · Потребовать вернуться?',
 pursuit='Машина уезжает · Начать 10-57 VICTOR?',foot='Водитель убегает · 10-57 FOXTROT?',
 approach='Вы подошли к машине · Осмотреть салон?',high_risk='Машина остановилась после погони · 10-66?',
 armed='Вооружённый водитель · Запросить поддержку?',combat='Попадание по офицеру · Передать CODE 0?',
 taser_warning='Пешая погоня · Предупредить о тайзере?',pursuit_mark='Повторить только /pt · без розыска?',fast_wanted='Ориентировка и розыск 8.1 + /pt?',combat_wanted='Подтверждённое нападение · Розыск 2.2 + /pt?'}
 for _,row in ipairs(M.quick)do labels[row[1]]=row[2]end
 for _,row in ipairs(dispatch.actions)do labels[row[1]]=row[2]end
 labels.explain_stop='Назвать причину остановки?';labels.documents='Попросить документы по выбранному основанию?';labels.explain_detention='Назвать основание задержания и разъяснить права?'
 local fast={fast_wanted=true,combat_wanted=true,pursuit_mark=true}
local function safe(s)return s and s.session and s.alive and s.focused and not s.paused and not s.blocked and s.onDuty and s.radioEnabled end
local function idSame(a,b)return a and b and a.id==b.id and a.name==b.name and a.generation==b.generation end
local function coord(c)return c and core.finite(c.x)and core.finite(c.y)and core.finite(c.z)end
local function distance(a,b)if not coord(a)or not coord(b)then return end;return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)end
function M.expand(text,values)
 local missing
 local t=core.expandGender(text,values.gender):gsub('{([a-z_]+)}',function(k)
  local v=values[k];if v==nil then missing=k;return''end
  return k=='local_tag'and(v~=''and tostring(v)..' 'or'')or tostring(v)
 end)
 if missing then return nil,'Недоступно поле: {'..missing..'}.'end
 if t:find('[{}]')then return nil,'Проверьте переменные в тексте Copilot.'end;return t
end
function M.new(env)return setmetatable({env=env,life=1,serial=0,offers={},dismissed={},done={},tireWarnings=0,phase=nil},C)end
function C:rememberPartial(p)
 if p and fast[p.action]and p.suSent then
  self.done[p.action]=true;self.pinned=not p.ptSent and'pursuit_mark'or nil
 end
end
function C:cancel(reason)
 local q=self.queued;self:rememberPartial(q);self.queued=nil;self.intent=nil;self.offers={}
 if q and self.env.cancel then self.env.cancel(q.token,reason)end
end
function C:reset(reason)
 self:cancel(reason);self.life=self.life+1;self.phase=nil;self.car=nil;self.driver=nil;self.driverLive=nil;self.motion=nil;self.stillAt=nil
 self.done={};self.dismissed={};self.pinned=nil;self.pendingTaser=false;self.hadDriver=false;self.tireWarnings=0;self.lastMegaphoneAt=nil;self.startedAt=nil;self.lastDamage=nil;self.attackConfirmed=false;self.enteredDangerInPursuit=false;self.lastArea=nil;self.wasDanger=false;self.ownMotion=nil;self.ownStillAt=nil;self.lastDriverPoint=nil
 self.pursuitStarted=false;self.stopReportOffered=false;self.damageMail=nil;self.hiddenLife=nil;self.repeatPaused=false;self.repeatAt=nil;self.lastStopOrderAt=nil;self.lastDriverSeen=nil;self.targetStopped=nil;self.lastStopReason=nil;self.groundRequest=nil;self.groundHandoff=nil
end
function C:groundNavigation(action)
 local target,stamp
 if action=='explain_detention'and self.env.target then target,stamp=self.env.target()end
 if not target and self.driverLive then target=model.copy(self.driverLive);stamp=nil end
 if not target and self.env.target then target,stamp=self.env.target()end
 if not target then return nil,'Сначала выберите водителя либо человека для задержания.'end
 if action=='explain_stop'and not self.car then return nil,'Сначала выберите машину остановки.'end
 self.serial=self.serial+1
 return {navigation=true,token='ground:'..self.life..':'..self.serial,action=action,kind=action=='explain_stop'and'stop'or'detention',
  label=action=='explain_stop'and'Осмотр выполнен · Представиться и назвать причину 10-55?'or'Выбрать основание задержания?',
  life=self.life,at=self.now,session=self.state.session,ped=self.state.ped,demo=self.state.demo,
  cfg=model.copy(self.env.settings()),vehicleCfg=model.copy(self.env.vehicle.env.settings()),
  groundTarget=model.copy(target),groundStamp=stamp,groundCar=not stamp and model.copy(self.car)or nil}
end
function C:groundContextValid(p,extended)
 local age=p and core.elapsed(self.now,p.at)
 if not p or p.life~=self.life or not safe(self.state)or p.session~=self.state.session or p.ped~=self.state.ped or p.demo~=self.state.demo or
  not age or age>(extended and 600000 or self.env.settings().toast_ms)or not self.env.equal(p.cfg,self.env.settings())or
  not self.env.equal(p.vehicleCfg,self.env.vehicle.env.settings())then return false end
 if p.groundCar and(not vehicleModel.same(p.groundCar,self.car)or self.car.stale)then return false end
 if p.groundStamp then return self.env.validTarget and self.env.validTarget(p.groundTarget,p.groundStamp)or false end
 return idSame(p.groundTarget,self.driverLive)or false
end
function C:proposeGround(request,cfg,ground,handoff)
 if not self:groundContextValid(request,true)then return nil,'Водитель, машина или сцена изменились. Выберите основание заново.'end
 return self:propose(request.action,{cfg=cfg,request=request,ground=ground,handoff=handoff})
end
function C:pursuing()
 return self.pursuitStarted and(self.phase=='Преследование'or self.phase=='10-57 FOXTROT')or false
end
function C:inPursuit()
 local cfg=self.env.settings();return cfg.enabled and cfg.pursuit_retention and self:pursuing()or false
end
function C:retentionFor(target)
 if not target or not self:inPursuit()or not idSame(target,self.driver)then return end
 local cfg=self.env.settings();return{distance=cfg.pursuit_retain_distance,grace=cfg.pursuit_retain_grace_ms}
end
function C:observeDriver(target)
 if not target then return end
 local live=self.env.driver(target.id)
 if live then
  if not idSame(target,live)then return end
  if self:inPursuit()and(not core.finite(live.distance)or live.distance>self.env.settings().pursuit_retain_distance)then return end
  self.lastDriverSeen=self.now;return live
 end
 if not self:inPursuit()or not self.env.driverAccount then return end
 local account=self.env.driverAccount(target.id);local age=self.lastDriverSeen and core.elapsed(self.now,self.lastDriverSeen)
 if not idSame(target,account)or account.incompatible or not age or age>self.env.settings().pursuit_retain_grace_ms then return end
 account=model.copy(account);account.stale=true;return account
end
function C:hideHud()self.hiddenLife=self.life;return true end
function C:pauseRepeats()
 self.repeatPaused=not self.repeatPaused
 local out={};for _,p in ipairs(self.offers)do if not p.repeatOffer then out[#out+1]=p end end;self.offers=out
 self.repeatAt=self.now;return true
end
function C:damage(id,weapon,at)
 if core.validId(id)and core.finite(weapon)and weapon>=22 and weapon<=38 then self.damageMail={id=id,weapon=weapon,at=at,session=self.state and self.state.session}end
end
function C:values(override)
 local s=self.state;if not s then return nil,'Дождитесь подключения к игре.'end
 local v,err=self.env.vehicle:values(s,self.car);if not v then return nil,err end
 local cfg=override or self.env.settings();local c=self.car or{}
 local colleagues=s.colleagues or{};local profile=self.env.profile()or{}
 if not v.unit or v.unit==''then v.unit=profile.callsign~=''and profile.callsign or colleagues.autoCallsign or'1-L-1'end
 if not v.station or v.station==''then v.station=colleagues.station or'LSPS'end
 if not v.crew or v.crew==''then v.crew=profile.name~=''and profile.name or s.my_name or'Офицер'end
 v.local_tag=v.local_tag or'';v.area=v.area or v.location or'не определён';v.map_square=v.map_square or'не определён';v.direction=v.direction or'не определено';v.city=v.city or'не определён'
 v.occupants=tostring(c.occupants or 0);v.occupants_text=({[0]='салон пуст',[1]='внутри один',[2]='внутри двое',[3]='внутри трое',[4]='внутри четверо'})[c.occupants or 0]or('внутри '..tostring(c.occupants)..' чел.')
 v.vehicle_plate=vehicleModel.plate(c,cfg)
 v.driver_id=self.driver and tostring(self.driver.id)or'';v.driver_name=self.driver and self.driver.name:gsub('_',' ')or'Водитель'
 v.tac=cfg.tac_channel;v.stop_outcome=cfg.stop_outcome;v.armed_text=(c.armed or cfg.pursuit_armed or self.driverLive and self.driverLive.armed)and' Подозреваемые вооружены!'or''
 v.my_firstname=(profile.name~=''and profile.name or s.my_name or s.my_nick or'Офицер'):gsub('_',' '):match('^%S+')or'Офицер'
 if not self.car then v.vehicle_description=cfg.lost_vehicle_fallback end
 v.dispatch_officers=dispatch.officers(s);v.robbery_min_officers=cfg.robbery_min_officers
 v.officers=#(colleagues.nearbyOfficers or{})+1;v.min_officers=cfg.min_officers
 v.warnings=self.tireWarnings;v.warning_count=cfg.warning_count;v.ooc_warning_count=cfg.ooc_warning_count
 local grounds=require 'pa26_operational'
 local stop=grounds.ground('stop',cfg.stop_ground,cfg.stop_branch,cfg.stop_custom)
 local detention=grounds.ground('detention',cfg.detention_ground,nil,cfg.detention_custom)
 v.stop_ground=stop and stop.title or'причина не выбрана';v.detention_ground=detention and detention.title or'основание не выбрано'
 v.ground_article=stop and stop.article or'';v.rank=profile.rank~=''and profile.rank or self.state.rank or'офицер';v.my_name=profile.name~=''and profile.name or self.state.my_name or self.state.my_nick or'Офицер'
 return v
end
function C:prepare(action,override)
 action=dispatch.aliases[action]or action
 local cfg=override or self.env.settings();local values,why=self:values(cfg);if not values then return nil,why end
 if override and override._ground_target then values.driver_id=tostring(override._ground_target.id);values.driver_name=override._ground_target.name:gsub('_',' ')end
 local lines,wires,steps={},{},{};local rpSignature,textSignature
 local function add(channel,text)
  local body,err=M.expand(text,values);if not body then return nil,err end
  local p
  if channel=='/me'or channel=='/do'or channel=='/try'or channel=='/todo'then p,err=require('pa26_rp_text').line(channel..' '..body,self.env.codec,self.state.rpText,self.state.my_nick)
  else p,err=radio.prepare(channel,body,self.env.codec,self.state.radioText,self.state.rpText,self.state.my_nick)end
  if not p then return nil,err end;rpSignature=rpSignature or p.rpSignature;textSignature=textSignature or p.textSignature
  for _,x in ipairs(p.steps)do steps[#steps+1]=model.copy(x)end
  for _,x in ipairs(p.lines)do lines[#lines+1]=x end;for _,x in ipairs(p.wires)do wires[#wires+1]=x end
  if #steps>64 then return nil,'План слишком длинный: сократите тексты.'end;return true
 end
 local function template(key,channel)
  if type(cfg.templates[key])~='string'then return nil,'Заполните текст Copilot: '..tostring(key)end
  for line in(cfg.templates[key]..'\n'):gmatch('(.-)\n')do if line~=''then local ok,err=add(channel,line);if not ok then return nil,err end end end;return true
 end
 local function explicitRp(key)
  if type(cfg.templates[key])~='string'then return nil,'Заполните RP Copilot: '..tostring(key)end
  for line in(cfg.templates[key]..'\n'):gmatch('(.-)\n')do if line~=''then local cmd,body=line:match('^(/%l+)%s+(.+)$')
   if cmd~='/me'and cmd~='/do'and cmd~='/try'and cmd~='/todo'then return nil,'В RP допустимы только /me, /do, /try и /todo.'end
   local ok,err=add(cmd,body);if not ok then return nil,err end
  end end;return true
 end
 local function command(text)local w,err=core.encodeWire(text,self.env.codec);if not w then return nil,err end
  steps[#steps+1]={kind='message',text=text,wire=w};lines[#lines+1]=text;wires[#wires+1]=w;return true end
 local channel=self.env.vehicle.env.settings().channel;local ok,err
 local dispatchAction=dispatch.byAction[action]
 if dispatchAction then
  if not cfg.dispatch_enabled then return nil,'Включите «Вызовы и спецситуации» в настройках Copilot.'end
  if dispatchAction.mega then ok,err=template(dispatchAction.radio,self.env.vehicle.env.settings().megaphone_channel)
  else
   ok=true
   if cfg.dispatch_rp_enabled then ok,err=explicitRp(self.state.inVehicle and dispatchAction.rp or dispatchAction.foot)end
   if ok then ok,err=template(dispatchAction.radio,channel)end
  end
 elseif action=='explain_stop'or action=='documents'or action=='explain_detention'then
  local kind=action=='explain_detention'and'detention'or'stop'
  local ground;ground,err=require('pa26_operational').ground(kind,cfg[kind..'_ground'],cfg[kind..'_branch'],cfg[kind..'_custom'])
  if not ground then return nil,err end
  values.ground_article=ground.article
  ok=true
  if cfg.ground_intro then
   ok,err=template('intro',cfg.ground_channel or'/s');if ok then ok,err=template('badge','/me')end
   if ok and cfg.ground_ud then
    if values.driver_id==''then return nil,'Для /ud нужен установленный собеседник.'end
    ok,err=command('/ud '..values.driver_id)
   end
  end
  if ok then ok,err=template(action,cfg.ground_channel or'/s')end
  if ok and action=='explain_stop'then ok,err=template('documents',cfg.ground_channel or'/s')end
  if ok and action=='explain_detention'and cfg.ground_miranda then ok,err=template('miranda',cfg.ground_channel or'/s');if ok then ok,err=template('rights_extra',cfg.ground_channel or'/s')end end
 elseif fast[action]then
  if self.done[action]then return nil,'Это действие розыска уже передано в этой ситуации. Для нового случая завершите текущую ситуацию.'end
  if not self.driverLive or not idSame(self.driverLive,self.driver)then return nil,'Водитель не установлен или его ID уже сменил владельца.'end
  if action=='combat_wanted'and not self.attackConfirmed then return nil,'Нет подтверждённого нападения этого водителя.'end
  if action=='fast_wanted'and not self.pursuitStarted then return nil,'Сначала подтвердите начало погони и основание неподчинения.'end
  if action=='pursuit_mark'then ok=true else
   ok,err=explicitRp(action=='combat_wanted'and'combat_rp'or'wanted_rp');if ok then ok,err=command('/su '..self.driver.id..(action=='combat_wanted'and' 2 2'or' 8 1'))end
  end
  if ok then ok,err=command('/pt '..self.driver.id)end
 elseif action=='taser_warning'then
  if not self.driverLive or not core.finite(self.driverLive.distance)or self.driverLive.distance>20 or self.driverLive.armed or cfg.pursuit_armed or self.state.taserCombatText or(self.lastDamage and(core.elapsed(self.now,self.lastDamage)or 0)<=cfg.combat_ms)or(self.env.taserActive and not self.env.taserActive(self.state))then return nil,'В перестрелке, против вооружённого или без активного тайзера предложение отключено.'end
  ok,err=template('taser_warning','/s')
 elseif action=='approach'then
  if self.state.inVehicle or not self.car or self.car.distance>self.env.vehicle.env.settings().approach_distance then return nil,'Выйдите из машины и подойдите к выбранному автомобилю.'end
  local h=self.state.gameHour;local night=core.finite(h)and(h<6 or h>=21)and cfg.night_flashlight
  ok,err=template(night and'approach_night'or'approach_day','/me');if ok then ok,err=template('window','/do')end
  if ok and cfg.window_ooc_hint then ok,err=template('ooc_hint','/n')end
 elseif action=='risk_order'then
  ok,err=template((self.car.occupants or 0)>=2 and'risk_multi'or'risk_single','/m')
 elseif action=='stop_order'or action=='return_car'or action=='tire'then
  if action=='tire'and self.lastMegaphoneAt and(core.elapsed(self.now,self.lastMegaphoneAt)or 0)<cfg.warning_cooldown_ms then return nil,'Дождитесь интервала между предупреждениями.'end
  ok,err=template(action,action=='return_car'and not self.state.inVehicle and'/s'or'/m')
 else
  if not cfg.templates[action]then return nil,'Неизвестное действие Copilot.'end
  ok,err=template(action,channel)
  if ok and cfg.backup_mark and(action=='high_risk'or action=='combat')then ok,err=template(action=='combat'and'backup_combat'or'backup_risk','/mark')end
 end
 if not ok then return nil,err end
 return {lines=lines,wires=wires,steps=steps,rpSignature=rpSignature,textSignature=textSignature}
end
function C:previewTemplate(key,cfg)
 local values,err=self:values(cfg);if not values then return nil,err end
 if key=='explain_detention'then local g=require('pa26_operational').ground('detention',cfg.detention_ground,nil,cfg.detention_custom);values.ground_article=g and g.article or'основание не выбрано'end
 local note=({robbery_warning=true,dispatch_confirmation_note=true,gas_confirmation_note=true})[key]
 local text=note and cfg[key]or cfg.templates[key];if not text then return nil,'Неизвестная реплика.'end
 local body;body,err=M.expand(text,values);if not body then return nil,err end
 if note then return body end
 local channels={explain_stop='/s',documents='/s',explain_detention='/s',miranda='/s',rights_extra='/s',approach_day='/me',approach_night='/me',window='/do',ooc_hint='/n',risk_single='/m',risk_multi='/m',return_car=self.state.inVehicle and'/m'or'/s',stop_order='/m',tire='/m',taser_warning='/s',backup_risk='/mark',backup_combat='/mark'}
 local channel=channels[key]or key=='gas_order'and self.env.vehicle.env.settings().megaphone_channel or self.env.vehicle.env.settings().channel
 if dispatch.isRp(key)then return body end
 local out={};for line in(body..'\n'):gmatch('(.-)\n')do if line~=''then out[#out+1]=channel..' '..line end end;return table.concat(out,'\n')
end
function C:propose(action,options)
 action=dispatch.aliases[action]or action
 local cfg=self.env.settings();local s=self.state;local v=self.env.vehicle
 if not cfg.enabled or not v.env.settings().enabled or not safe(s)then return nil,'Включите Copilot, транспорт, службу и рацию.'end
 local vcfg=v.env.settings();local dispatchAction=dispatch.byAction[action]
 local mega=({stop_order=true,risk_order=true,tire=true,return_car=true})[action]or dispatchAction and dispatchAction.mega
 if mega and not vcfg.megaphone_enabled then return nil,'Включите мегафон в настройках.'end
 local patrol=v.env.patrol and v.env.patrol();local needsPatrol=vcfg.require_patrol or mega and vcfg.megaphone_require_patrol
 if needsPatrol and(not patrol or patrol.status~='active')then return nil,'Сначала начните патруль или измените условие доступа.'end
 if not carFree[action]and not self.car then return nil,'Сначала выберите видимую машину.'end
 if self.car and self.car.stale and not fast[action]and not carFree[action]and action~='finish'then return nil,'Нужно свежее наблюдение машины. Сохранена только ситуация погони.'end
 if self.intent or self.queued then return nil,'Дождитесь текущего действия.'end
 if (action=='explain_stop'or action=='explain_detention')and not options then return self:groundNavigation(action)end
 local prepared,err=self:prepare(action,options and options.cfg);if not prepared then return nil,err end
 local note=fast[action]and action~='pursuit_mark'and'Автомобильная ориентировка PA: описание и номер передаются диспетчеру. Пустой ручной номер заменяется условным номером из ID авто, если эта настройка включена. Вопросов о маске и паспорте в этом пути нет. Проверьте водителя, основание и предпросмотр. ДА передаёт показанные команды; результат определяет сервер.'or nil
 local guardRisk=action=='dispatch_business'and cfg.robbery_guard and dispatch.officers(s)<cfg.robbery_min_officers or false
 if dispatchAction then
  local values=self:values();note,err=M.expand(dispatchAction.mega and cfg.gas_confirmation_note or cfg.dispatch_confirmation_note,values)
  if not note then return nil,err end
  if guardRisk then local warning;warning,err=M.expand(cfg.robbery_warning,values);if not warning then return nil,err end;note=warning..'\n\n'..note end
 end
 self.serial=self.serial+1
 return {token='copilot:'..self.life..':'..self.serial,action=action,life=self.life,session=s.session,ped=s.ped,demo=s.demo,at=self.now,
  groundCfg=options and model.copy(options.cfg),groundContext=options and model.copy(options.request),groundData=options and model.copy(options.ground),handoff=options and options.handoff,
  copilot=true,carFree=carFree[action]==true,needsPatrol=needsPatrol,patrol_id=patrol and patrol.id,target=not carFree[action]and model.copy(self.car)or nil,cfg=model.copy(cfg),car=not carFree[action]and model.copy(self.car)or nil,driver=fast[action]and model.copy(self.driver)or nil,prepared=prepared,
  phase=self.phase,label=labels[action]or action,assault=action=='combat_wanted',description=(self:values()or{}).vehicle_description,
  confirmationNote=note,confirmationTitle=guardRisk and'Ограбление бизнеса · проверьте состав патруля'or nil,
  dispatchAction=dispatchAction~=nil,dispatchRp=dispatchAction~=nil and not dispatchAction.mega and cfg.dispatch_rp_enabled,
  inVehicle=s.inVehicle==true,guardRisk=guardRisk,
  vehicleCfg=model.copy(v.env.settings())}
end
function C:valid(p,started)
 local s=self.state;local age=p and core.elapsed(self.now,p.at)
 if not p or p.life~=self.life or not safe(s)or p.session~=s.session or p.ped~=s.ped or p.demo~=s.demo or not age or age>(started and 600000 or self.env.settings().toast_ms)or
  not self.env.equal(p.cfg,self.env.settings())or not self.env.equal(p.vehicleCfg,self.env.vehicle.env.settings())then return false end
 if p.navigation then return self:groundContextValid(p,true)end
 if p.groundData and self.env.validGroundSource and not self.env.validGroundSource(p.groundData)then return false end
 if p.groundContext and not self:groundContextValid(p.groundContext,true)then return false end
 if p.carFree~=(carFree[p.action]==true)then return false end
 if p.dispatchRp and p.inVehicle~=(s.inVehicle==true)then return false end
 if p.action=='dispatch_business'and self.env.settings().robbery_guard and p.guardRisk~=(dispatch.officers(s)<self.env.settings().robbery_min_officers)then return false end
 if not p.carFree and(not vehicleModel.same(p.car,self.car)or p.car.color1~=self.car.color1 or p.car.color2~=self.car.color2)then return false end
 local patrol=self.env.vehicle.env.patrol and self.env.vehicle.env.patrol()
 if p.needsPatrol and(not patrol or patrol.status~='active'or p.patrol_id~=patrol.id)then return false end
 if p.action=='taser_warning'and(self.driverLive and self.driverLive.armed or self.env.settings().pursuit_armed or self.state.taserCombatText)then return false end
 if p.action=='foot'and(self.env.settings().pursuit_armed or self.driverLive and self.driverLive.armed) then return false end
 if p.driver and not idSame(p.driver,self.driverLive)then return false end
 if p.repeatOffer and(self.targetStopped or self.repeatPaused or not self.env.settings().repeat_megaphone or self.car and self.car.stale)then return false end
 if p.assault and not self.attackConfirmed then return false end
 if not started then local ready=self:prepare(p.action,p.groundCfg);if not ready or radio.key(ready)~=radio.key(p.prepared)then return false end end
 return true
end
function C:accept(p)
 if p and p.navigation then
  if not self:valid(p)then return nil,'Выбор причины устарел.'end
  self.groundRequest=model.copy(p);self.offers={};return true
 end
 if self.intent or self.queued or not self:valid(p)then return nil,'Сцена, водитель, текст или настройки изменились. Подготовьте действие заново.'end
 self.intent=model.copy(p);self.offers={};return true
end
function C:validPlan(plan)
 local p=self.queued
 if p and p.driver and not idSame(p.driver,self:observeDriver(p.driver))then return false end
 return p and plan.copilotAction and plan.copilotAction.token==p.token and self:valid(p,p.started)and
  radio.key(plan)==table.concat(p.prepared.wires,'\0')and not self.state.typing and not self.state.modal or false
end
function C:onExecution(kind,q,line)
 if q.plan.vehicleAction and kind=='completed'then
  local old=self.env.vehicle.queued
  if old and old.token==q.plan.vehicleAction.token and old.target and vehicleModel.same(old.target,self.env.vehicle.selected)then
   if not vehicleModel.same(self.car,old.target)then self:reset('Ситуация начата через прежние инструменты.');self.car=model.copy(old.target)end
   if old.action=='traffic_stop'then self.phase='10-55';self.stopReportOffered=true;self.done.stop=true;self.startedAt=self.startedAt or self.now
   elseif old.action=='pursuit'then self.phase='Преследование';self.pursuitStarted=true;if not self.done.fast_wanted and not self.done.combat_wanted then self.pinned='fast_wanted'end;self.startedAt=self.startedAt or self.now
   elseif old.action=='finish'then self:reset('Ситуация завершена.');return end
   local slot=tonumber(old.action:match('^megaphone_(%d+)$'))
   local counted=self.env.settings().legacy_tire_enabled and slot and(settings.ids(self.env.settings().count_legacy_phrases,1,8)or{})[slot]
   if counted and self.phase then self.tireWarnings=math.min(self.env.settings().warning_count,self.tireWarnings+1);self.lastMegaphoneAt=self.now end
  end
 end
 local p=self.queued;if not p or not q.plan.copilotAction or q.plan.copilotAction.token~=p.token then return end
 if kind=='sent_line'or kind=='preview_line'then
  p.started=true
  if type(line)=='string'and line:match('^/su ')then p.suSent=true elseif type(line)=='string'and line:match('^/pt ')then p.ptSent=true end
 end
 if kind=='completed'then
  self.queued=nil;self.done[p.action]=true
  if p.groundData then
   if p.action=='explain_stop'then self.lastStopReason={ground=model.copy(p.groundData),context=model.copy(p.groundContext)}end
   if p.handoff then self.groundHandoff={kind=p.handoff,ground=model.copy(p.groundData),context=model.copy(p.groundContext)}end
  end
  if p.action=='approach'and self.env.settings().ground_offer then self:offer('explain_stop')end
  if p.action=='stop_order'then self.phase=self.phase or'10-55';self.startedAt=self.startedAt or self.now;self.lastStopOrderAt=self.now;self.repeatAt=self.now
  elseif p.action=='stop'then self.phase='10-55';self.stopReportOffered=true
  elseif p.action=='pursuit'then self.phase='Преследование';self.pursuitStarted=true;if not self.done.fast_wanted and not self.done.combat_wanted then self.pinned='fast_wanted'end;self.motion=nil
  elseif p.action=='foot'then self.phase='10-57 FOXTROT';self.pursuitStarted=true;if not self.done.fast_wanted and not self.done.combat_wanted then self.pinned='fast_wanted'end
  elseif p.action=='high_risk'then self.phase='10-66'
  elseif p.action=='combat'then if self.attackConfirmed then self.pinned='combat_wanted'end
  elseif fast[p.action]then self.pinned=nil;if self.phase=='10-57 FOXTROT'and self.env.settings().taser_offer then self.pendingTaser=true end
  elseif p.action=='finish'or p.action=='lost'then self:reset('Ситуация завершена.');self.env.vehicle.phase=nil;return end
  if p.action=='tire'then self.tireWarnings=math.min(self.env.settings().warning_count,self.tireWarnings+1);self.lastMegaphoneAt=self.now;self.repeatAt=self.now end
  self.env.vehicle.phase=self.phase
 elseif kind=='cancelled'then
  self.queued=nil;self.dismissed[p.action]=true
  self:rememberPartial(p)
 end
end
function C:offer(action,repeatOffer)
 if self.done[action]or self.dismissed[action]or self.intent or self.queued then return end
 if self.state.colleagues and self.state.colleagues.ownCruiserRole=='driver'and self.env.settings().adam_driver_mute_radio and
  ({stop=true,pursuit=true,foot=true,high_risk=true})[action]then return end
 for _,p in ipairs(self.offers)do if p.action==action then return end end
 local p=self:propose(action);if p then p.repeatOffer=repeatOffer==true;self.offers[#self.offers+1]=p end
end
function C:shown(token)for _,p in ipairs(self.offers)do if p.token==token then p.seen=true end end end
function C:decide(token,yes)
 for i,p in ipairs(self.offers)do if p.token==token and p.seen then
  table.remove(self.offers,i);if yes then return self:accept(p)end
  self.dismissed[p.action]=true;if p.action=='stop_order'or p.action=='tire'then self.repeatAt=self.now end;if fast[p.action]then self.pinned=p.action end;return true
 end end;return nil,'Предложение устарело.'
end
function C:candidates()
 if self.state and self.state.ownUi then return{}end
 local out={};for _,p in ipairs(self.offers)do if self:valid(p)then
  out[#out+1]={owner='vehicle',token=p.token,mode='confirm',title=p.label,status=self.phase or'Машина выбрана',body=p.navigation and'Откроется отдельное окно выбора основания. Пока ничего не отправляется.'or(p.confirmationNote and p.confirmationNote..'\n'or'')..table.concat(p.prepared.lines,'\n'),
   full=true,priority=p.action=='combat'and 100 or 35,serial=p.at+p.life,remaining=math.max(0,self.env.settings().toast_ms-(core.elapsed(self.now,p.at)or 0)),duration=self.env.settings().toast_ms,
   unseen=not p.seen,yes=p.navigation and'Выбрать причину (Y)'or'Выполнить (Y)',no='Позже (N)',shortcut={key=0,ctrl=false,alt=false,shift=false},hint=p.repeatOffer and'N — отложить на заданный интервал. «Пауза /m» в карточке прекращает повторы. Отправка только после ДА.'or'Только после ДА. N откладывает действие; повторы /m отключаются в карточке и настройках. Предпросмотр: F4.'}
 end end;return out
end
function C:tick(s,now)
 if s.incapacitated then
  self.state=model.copy(s);self.now=now;self:cancel('Персонаж ранен. Ситуация и счётчики сохранены.');return
 end
 local old=self.state
 if old and old.incapacitated and old.session==s.session and old.local_nick==s.local_nick then old=model.copy(old);old.ped=s.ped;old.alive=s.alive end
 local age=self.now and core.elapsed(now,self.now)
 if old and(not age or old.session~=s.session or old.ped~=s.ped or old.demo~=s.demo or not s.alive)then self:reset('Сцена изменилась.')end
 self.state=model.copy(s);self.now=now
 local car=self.env.vehicle.selected
 if not car and self.car and self.env.vehicle.retainedByStream and self:inPursuit()and self.driver then
  local retained=self:observeDriver(self.driver)
  if retained then self.car.stale=true;self.car.distance=nil
  else self:reset('Наблюдение цели погони потеряно.');self.env.vehicle.phase=nil end
 elseif(car or self.car)and not vehicleModel.same(car,self.car)then self:reset('Выбрана другая машина.');self.car=model.copy(car)
 else self.car=model.copy(car)end
 local cfg=self.env.settings()
 if not cfg.enabled or not safe(s)then self:cancel('Игра или Copilot недоступны.');self.motion=nil;self.stillAt=nil;return end
 if not self.car then self:dispatch();return end
 self.startedAt=self.startedAt or now
 local c=self.car
 local danger=require('pa26_colleagues').guard(cfg,s.area,0,false)~=nil
 if self.pursuitStarted and self.lastArea and not self.wasDanger and danger then self.enteredDangerInPursuit=true end
 self.lastArea=s.area;self.wasDanger=danger
 if not self.phase and self.env.vehicle.phase then self.phase=self.env.vehicle.phase;self.pursuitStarted=self.phase=='Преследование'or self.phase=='10-57 FOXTROT'end
 if c.driver_id~=nil then
  local live=self.env.driver(c.driver_id)
  if live and live.ped==c.driver_ped then
   if self.hadDriver and not idSame(self.driver,live)then self:reset('Водитель сменился.');self.env.vehicle.phase=nil;self.car=c end
   self.driver=model.copy(live);self.lastDriverSeen=now;self.hadDriver=true;if coord(live)then self.lastDriverPoint={x=live.x,y=live.y,z=live.z}end
  end
 end
 self.driverLive=self.driver and self:observeDriver(self.driver)or nil
 if self.driver and not idSame(self.driver,self.driverLive)then self.offers={};self.pinned=nil;self.driver=nil;self.driverLive=nil end
 if c.stale then
  self.motion=nil;self.stillAt=nil
  if cfg.fast_wanted and self.pinned and self.driverLive then self:offer(self.pinned)end
  local keep={};for _,p in ipairs(self.offers)do if self:valid(p)then keep[#keep+1]=p end end;self.offers=keep
  self:dispatch();return
 end
 local mail=self.damageMail;self.damageMail=nil
 if mail and mail.session==s.session and(core.elapsed(now,mail.at)or math.huge)<=cfg.combat_ms then
  self.lastDamage=now;if self.driver and mail.id==self.driver.id then self.attackConfirmed=true end;self:offer('combat')
 end
 if self.driverLive and self.driverLive.armed and cfg.exit_offer and self.phase then self:offer('armed')end
 local own=self.env.vehicle.own
 local ownMoved=distance(own,self.ownMotion)
 if not self.ownMotion or ownMoved and ownMoved>=cfg.stationary_delta then self.ownMotion=coord(own)and{x=own.x,y=own.y,z=own.z}or nil;self.ownStillAt=now end
 local ownStill=not s.inVehicle or(coord(own)and self.ownStillAt and(core.elapsed(now,self.ownStillAt)or 0)>=cfg.stop_ms)
 local moved=distance(c,self.motion);local sampleAge=self.motion and core.elapsed(now,self.motion.at)
 if not self.motion or not sampleAge or moved and moved>=cfg.stationary_delta then self.motion={x=c.x,y=c.y,z=c.z,at=now};self.stillAt=now end
 local still=coord(c)and self.stillAt and(core.elapsed(now,self.stillAt)or 0)or 0
 local stopped=still>=cfg.stop_ms
 if self.targetStopped and not stopped then
  self.stopReportOffered=false;self.done.stop=nil;self.dismissed.stop=nil
 end
 self.targetStopped=stopped
 if self.phase=='10-55'then
  if cfg.stationary_offer and not self.stopReportOffered and ownStill and c.distance<=cfg.stop_distance and still>=cfg.stop_ms then self:offer('stop')end
  if cfg.approach_offer and not s.inVehicle and c.distance<=self.env.vehicle.env.settings().approach_distance then self:offer('approach')end
  if cfg.flee_offer and c.distance>cfg.flee_distance and moved and moved>=cfg.stationary_delta then self:offer('pursuit')end
 end
 local exited=self.hadDriver and c.driver_known==true and c.driver_id==nil and self.driverLive~=nil
 if exited and cfg.exit_offer and(self.phase=='10-55'or self.phase=='Преследование')then
  if self.phase=='10-55'then self:offer('return_car')end
  if not self.driverLive.armed and not cfg.pursuit_armed and(self.phase=='Преследование'or(self.driverLive.distance or 0)>cfg.foot_distance and(distance(self.driverLive,self.lastDriverPoint)or 0)>=cfg.stationary_delta)then self:offer('foot')end
 end
 if cfg.high_risk_offer and self.phase=='Преследование'and c.driver_known==true and c.distance<=cfg.risk_distance and still>=cfg.risk_stop_ms and not exited then self:offer('high_risk')end
 if self.pendingTaser then self:offer('taser_warning')end
 if cfg.repeat_megaphone and not self.repeatPaused and not stopped and moved and moved>=cfg.stationary_delta and
  self.repeatAt and(core.elapsed(now,self.repeatAt)or 0)>=cfg.warning_cooldown_ms and not self.intent and not self.queued then
  local action=self:pursuing()and'tire'or'stop_order'
  self.done[action]=nil;self.dismissed[action]=nil;self.repeatAt=now;self:offer(action,true)
 end
 if cfg.fast_wanted and self.pinned and not self.done[self.pinned]and self.driverLive then self:offer(self.pinned)end
 local keep={};for _,p in ipairs(self.offers)do if self:valid(p)then keep[#keep+1]=p end end;self.offers=keep
 self:dispatch()
end
function C:dispatch()
 local s,now=self.state,self.now
 if self.intent then
  local p=self.intent
  if not self:valid(p)then self.intent=nil
  elseif not s.busy and not s.modal and not s.typing and not s.recording and not s.wheel and not s.alertPending then
   self.intent=nil;local b=model.newBinding(999999991);b.name='Copilot · '..p.action;b.stat='none'
   local plan={binding=b,requirements={target=false,closest=false},session=p.session,createdAt=now,demo=p.demo,has_command=true,
    steps=model.copy(p.prepared.steps),lines=model.copy(p.prepared.lines),wire=model.copy(p.prepared.wires),rpSignature=p.prepared.rpSignature,textSignature=p.prepared.textSignature,
    automatic={kind='copilot'},copilotAction={token=p.token}}
   self.queued=p;local ok,err=self.env.start(plan);if not ok then self.queued=nil;if self.env.notice then self.env.notice(err)end end
  end
 end
end
function C:view()
 local cfg=self.env.settings();local text=cfg.tire_zero
 if self.tireWarnings>=cfg.warning_count then text=cfg.tire_done elseif self.tireWarnings>=cfg.ooc_warning_count then text=cfg.tire_partial end
 text=text:gsub('{warnings}',tostring(self.tireWarnings)):gsub('{warning_count}',tostring(cfg.warning_count)):gsub('{ooc_warning_count}',tostring(cfg.ooc_warning_count))
 local s=self.state;local live=s and s.session and s.alive and s.focused and not s.paused and not s.blocked and s.onDuty
 local patrol=s and s.patrolActive;local visible=cfg.enabled and cfg.hud and live and self.hiddenLife~=self.life and(self.car~=nil or self.phase~=nil or patrol or cfg.always_show_on_duty and s.inVehicle)or false
 local phase=self.phase;local combat=self.lastDamage and(core.elapsed(self.now,self.lastDamage)or math.huge)<=cfg.combat_ms or false
 local title=({['10-55']='ТРАФИК-СТОП 10-55 · КОД 4',['10-66']='ОСТАНОВКА 10-66 · КОД 3',['Преследование']='ПОГОНЯ 10-57 VICTOR · КОД 3',['10-57 FOXTROT']='ПЕШАЯ ПОГОНЯ · КОД 3'})[phase]or(s and s.patrolStatus=='paused'and'ПАТРУЛЬ · ПАУЗА'or'ПАТРУЛЬ · КОД 4')
 if combat then title='ПОПАДАНИЕ ПО ОФИЦЕРУ · CODE 0'end
 return{visible=visible,phase=phase,statusTitle=title,statusCode=combat and 0 or(phase=='10-66'or phase=='Преследование'or phase=='10-57 FOXTROT')and 3 or 4,car=model.copy(self.car),driver=model.copy(self.driver),values=s and self:values()or nil,
  colleagues=self.state and model.copy(self.state.colleagues),pinned=self.pinned,tireWarnings=self.tireWarnings,tireStatus=text,
  duration=math.floor((self.startedAt and core.elapsed(self.now,self.startedAt)or 0)/1000),cooldown=math.max(0,cfg.warning_cooldown_ms-(self.lastMegaphoneAt and(core.elapsed(self.now,self.lastMegaphoneAt)or 0)or cfg.warning_cooldown_ms)),
  moscowTime=self.state and self.state.moscowTime,raidAllowed=self.state and self.state.moscowTime and self.state.moscowTime.hour*60+self.state.moscowTime.min>=cfg.raid_start_hour*60 and self.state.moscowTime.hour*60+self.state.moscowTime.min<cfg.raid_end_hour*60,
  repeatPaused=self.repeatPaused,combat=combat,attackConfirmed=self.attackConfirmed}
end
return M

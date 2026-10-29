-- Render plain cached observations only. Buttons create intents; main executes.
local copy=require('pa26_bindings').copy;local menu=require 'pa26_menu';local prefs=require 'pa26_copilot_settings'
local M={}
function M.offer(s,callbacks,action)
 local p,err=callbacks.copilotOffer(action)
 if p then if p.navigation then callbacks.openGround(p)else s.vehicleConfirm=p end else s:notify(err,'vehicle',false)end
end
function M.quick(s,ui,callbacks,offer)
 s:settingsHeading(ui,'Вызовы и спецситуации (RP + Рация)')
 ui.text('Ручная отыгровка полученного вызова: в машине используется терминал, пешком — КПК и рация. Затем идёт доклад. Проверьте место в предпросмотре: это текущие город, район, квадрат и курс офицера. Серверная GPS-метка не устанавливается.')
 for _,r in ipairs(require('pa26_copilot').dispatchActions)do if s:button(r[2]..'##copilot-dispatch-'..r[1],ui)then if offer then offer(r[1])else M.offer(s,callbacks,r[1])end end end
 s:settingsHeading(ui,'Быстрые доклады')
 ui.text('Каждая кнопка открывает предпросмотр и ДА/НЕТ. Отправки без подтверждения нет. Тексты и канал меняются в «Трафик и погоня → Настройки и тексты». Перерыв — только доклад, без таймера.')
 for _,r in ipairs(require('pa26_copilot').quick)do if s:button(r[2]..'##copilot-quick-'..r[1],ui)then if offer then offer(r[1])else M.offer(s,callbacks,r[1])end end end
end
function M.draw(s,ui,data,callbacks)
 local im=s.imgui;local v=data.copilot or{};local c=v.car;local values=v.values or{}
 s.currentNoticeScope='vehicle';s:settingsHeading(ui,'Трафик и погоня')
 for _,r in ipairs({{'on_duty','На службе · автофункции PA'},{'enabled','Связь · разрешить доклады PA'}})do
  local value,changed=s:check(r[2]..'##copilot-alert-'..r[1],s.lib.alerts[r[1]])
  if changed then
   local lib=copy(s.lib);lib.alerts[r[1]]=value;local ok,err=callbacks.save(lib)
   if ok then if s.alertDraft then s.alertDraft[r[1]]=value end else s:notify(err,'vehicle',false)end
  end
 end
 ui.text('Это режим PA. Серверную смену он не заменяет.')
 s.copilotPage=s:choice('Раздел##copilot-page',s.copilotPage or'work',{{'work','Ситуация'},{'grounds','Причина и основание'},{'rights','Задержание и права'},{'settings','Настройки и тексты'}},ui)
 local d=s.vehicleDraft or copy(s.lib.vehicle);local cfg=d.copilot or prefs.defaults();d.copilot=cfg
 if s.copilotPage=='work'then
  if c then
   s:settingsHeading(ui,(values.model or'Машина')..' ['..c.id..'] · '..(v.phase or'Выбрана'))
   ui.text((values.vehicle_color or'Цвет неизвестен')..' · Гос. номер: '..(values.vehicle_plate or'не установлен'))
   ui.text((values.occupants_text or'Салон не определён')..' · Водитель: '..(v.driver and('ID '..v.driver.id)or'не установлен')..' · '..(c.stale and'последнее наблюдение'or math.floor(c.distance or 0)..' м'))
   if c.armed or v.phase=='10-66'or v.phase=='Преследование'then ui.text('Повышенный риск · рассмотрите 10-66. Наличие оружия не подтверждает стрельбу.')end
  else ui.text('Выберите видимую машину. Если автовыбор водителя включён, его ID станет целью биндов и обычного взаимодействия.')end
  if s:button('Выбрать ближайшую впереди##copilot-select',ui)then local ok,err=callbacks.copilotSelect();if not ok then s:notify(err,'vehicle',false)end end
  ui.text('Дальность захвата авто, м (5–150)');local radius=im.new.int(d.radius);im.PushItemWidth(-1)
  if im.SliderInt('##copilot-radius',radius,5,150)then d.radius=radius[0];d.retain_distance=math.max(d.retain_distance,d.radius)end;im.PopItemWidth()
  d.sync_driver_target=s:check('Водитель — цель биндов##copilot-sync-driver',d.sync_driver_target)
  ui.text('Работает пешком и из машины, включая близкую видимую цель сбоку. Автовыбор не подменяет вручную выбранного человека при фоновом обновлении; повторный выбор машины привязывает её водителя заново.')
  local colleagues=v.colleagues or{};local roles={driver='Водитель ADAM',navigator='Штурман-координатор ADAM',solo='Одиночный LINCOLN'}
  ui.text('Маркировка: '..(values.unit or colleagues.autoCallsign or'—')..' · '..(roles[colleagues.ownCruiserRole]or'Пешком'))
  ui.text('Сотрудников ПД рядом: '..#(colleagues.nearbyOfficers or{})..' · экипажей: '..(colleagues.nearbyCruisers or 0))
  ui.text('Радар — ориентир по форме, рации и вашим контактам; он не подтверждает IC-личность или полномочия человека.')
  cfg.pursuit_armed=s:check('Подозреваемые вооружены · моя отметка##copilot-armed',cfg.pursuit_armed)
  d.channel=s:choice('Канал докладов##copilot-radio-channel',d.channel,require('pa26_server_commands').radioChoices,ui)
  cfg.tac_channel=s:choice('Тактический канал##copilot-tac',cfg.tac_channel,{{'TAC 1','TAC 1'},{'TAC 2','TAC 2'},{'TAC 3','TAC 3'}},ui)
  cfg.select_plate=s:field('Ручной госномер · пусто = условный номер PA##copilot-plate','copilot:plate',cfg.select_plate,256)
  local outcomes={{'проведена беседа','Беседа'},{'выписан штраф','Штраф'},{'подозреваемый задержан','Задержан'},{'Код 4 АДАМ, подозреваемый потерян','CODE 4 ADAM · потерян'}}
  local known=false;for _,row in ipairs(outcomes)do if row[1]==cfg.stop_outcome then known=true end end;if not known then outcomes[#outcomes+1]={cfg.stop_outcome,'Свой итог: '..cfg.stop_outcome}end
  cfg.stop_outcome=s:choice('Итог##copilot-outcome',cfg.stop_outcome,outcomes,ui)
  local function offer(action)
   s.vehicleDraft=d;s:autoSettings('vehicle',{'vehicle'},d,'vehicleDraft');s:flushAutosave(callbacks,true)
   if not s.autosaves.vehicle then M.offer(s,callbacks,action)else s:notify('Исправьте и сохраните настройки транспорта.','vehicle',false)end
  end
  M.quick(s,ui,callbacks,offer)
  for _,r in ipairs(require('pa26_copilot').actions)do if s:button(r[2]..'##copilot-'..r[1],ui)then offer(r[1])end end
  if v.pinned and s:button((v.pinned=='pursuit_mark'and'Только /pt · без повторного /su'or v.pinned=='combat_wanted'and'Розыск 2.2 + /pt'or'Розыск 8.1 + /pt')..'##copilot-wanted',ui)then offer(v.pinned)end
  if v.phase then
   ui.text(v.tireStatus or'')
   if s:button('/m Предупреждение (+1)##copilot-tire',ui)then offer('tire')end
  end
  ui.text('Розыск по машине: ориентировка диспетчеру и одно ДА, без вопросов о маске и паспорте. Условный номер из ID — выбранная RP-конвенция PA. Это не чтение серверной регистрации. Обычный /su ID открывает полный помощник. N сохраняет кнопку на карточке.')
 elseif s.copilotPage=='grounds'then
  local op=require 'pa26_operational_ui'
  op.ground(s,ui,cfg,'stop',callbacks);op.ground(s,ui,cfg,'detention',callbacks)
  for _,r in ipairs({{'explain_stop','Назвать причину остановки · предпросмотр'},{'documents','Запросить документы · предпросмотр'},{'explain_detention','Основание и полная Миранда · предпросмотр'}})do
   if s:button(r[2]..'##ground-send-'..r[1],ui)then
    s.vehicleDraft=d;s:autoSettings('vehicle',{'vehicle'},d,'vehicleDraft');s:flushAutosave(callbacks,true)
    if not s.autosaves.vehicle then M.offer(s,callbacks,r[1])else s:notify('Проверьте настройки основания.','vehicle',false)end
   end
  end
  ui.text('Все реплики редактируются в «Настройки и тексты». Предпросмотр показывает точные строки до ДА. Полный текст источника отдельно сохранён в базе знаний. ПМ и игровые звёзды из статей PA не вычисляет.')
 elseif s.copilotPage=='rights'then
  require('pa26_operational_ui').timers(s,ui,data,callbacks)
 else
  if v.moscowTime then ui.text(string.format('МСК %02d:%02d · сохранённое окно %02d:00–%02d:00: ',v.moscowTime.hour,v.moscowTime.min,cfg.raid_start_hour,cfg.raid_end_hour)..(v.raidAllowed and'внутри интервала'or'вне интервала'))end
  ui.text('В источнике есть расхождение: регламент 4.3 — 14:00–22:00; 10.9 запрещает 20:00–13:00. Часовой пояс там не указан. Настройка PA — ваша трактовка, а не разрешение на рейд.')
  ui.text('Изменения сохраняются автоматически. Старые значения остальных функций и ваши бинды остаются своими.')
  d.enabled=s:check('Включить транспортные действия PA##copilot-vehicle-enabled',d.enabled)
  d.require_patrol=s:check('Транспорт только в активном патруле##copilot-vehicle-patrol',d.require_patrol)
  d.megaphone_enabled=s:check('Включить мегафон##copilot-megaphone-enabled',d.megaphone_enabled)
  for _,r in ipairs(prefs.booleans)do
   if r[1]:match('^ground_')then cfg[r[1]]=require('pa26_procedure_window').check(s,ui,r[2]..'##copilot-setting-'..r[1],cfg[r[1]])
   else cfg[r[1]]=s:check(r[2]..'##copilot-setting-'..r[1],cfg[r[1]])end
  end
  cfg.ground_channel=s:choice('Речь в формах основания##copilot-ground-channel',cfg.ground_channel or'/s',{{'','Обычный чат'},{'/s','Речь /s'}},ui)
  for _,r in ipairs(prefs.numbers)do
   ui.text(r[2]);im.PushItemWidth(-1)
   local n=im.new.int(cfg[r[1]]);if im.InputInt('##copilot-setting-'..r[1],n)then cfg[r[1]]=n[0]end;im.PopItemWidth()
  end
  ui.text('Удержание до 300 м действует только после подтверждённого начала автомобильной или пешей погони. Дальности наручников, обыска и других близких действий не меняются. В обычном режиме используются ваши прежние настройки. Крестик скрывает карточку без сброса погони.')
  ui.text('Повтор /m — только новое предложение после интервала, отправка требует ДА. N откладывает повтор; «Пауза подсказок /m» выключает повторы для этой ситуации.')
  ui.text('Порог неподвижности, м');im.PushItemWidth(-1)
  local delta=im.new.float(cfg.stationary_delta);if im.SliderFloat('##copilot-stationary',delta,.05,5)then cfg.stationary_delta=delta[0]end;im.PopItemWidth()
  for _,r in ipairs(prefs.texts)do
   cfg[r[1]]=s:field(r[2]..'##copilot-text-'..r[1],'copilot:text:'..r[1],cfg[r[1]],r[3]*2+1,true,64)
   if({robbery_warning=true,dispatch_confirmation_note=true,gas_confirmation_note=true})[r[1]]then
    local preview,why=callbacks.copilotPreview(r[1],cfg);ui.text('Предпросмотр: '..tostring(preview or why))
   end
  end
  ui.text('В напоминании о районе: {officers}, {min_officers}; в счётчике: {warnings}, {warning_count}, {ooc_warning_count}.')
  ui.text('Официальные интервалы Мануала 210: ответ 300 с, прибытие 600 с, звонок 180 с. Иные значения — личная длительность, они не меняют правило сервера. Настройки не заменяют уже запущенный таймер.')
  local choices={};for _,r in ipairs(prefs.templates)do choices[#choices+1]=r end
  s.copilotTemplate=s:choice('Изменить реплику##copilot-template',s.copilotTemplate or'stop',choices,ui)
  local key=s.copilotTemplate
  if s:button('Взять стандартный текст PA 0.42 · только выбранную реплику##copilot-default',ui)then
   cfg.templates[key]=prefs.defaults().templates[key];s:setBuffer('copilot:rp:'..key,cfg.templates[key],8193)
   s:notify('Выбранный текст заменён стандартным. Остальные ваши реплики сохранены.','vehicle',false)
  end
  cfg.templates[key]=s:field('Реплика##copilot-rp','copilot:rp:'..key,cfg.templates[key],8193,true,140)
  ui.text('Для RP розыска и вызовов — отдельные строки /me, /do, /try или /todo. У вызовов есть варианты в машине и пешком. Для докладов и требования на АЗС — текст без /команды; канал добавляется отдельно. Род: {gender:передал|передала}.')
  ui.text('Переменные: {unit}, {station}, {crew}, {vehicle_type}, {vehicle_type_gen}, {model}, {vehicle_id}, {vehicle_color}, {vehicle_description}, {vehicle_plate}, {occupants_text}, {driver_id}, {driver_name}, {city}, {area}, {map_square}, {direction}, {tac}, {stop_outcome}, {armed_text}, {my_firstname}.')
  local text,err=callbacks.copilotPreview(key,cfg);ui.text('Предпросмотр: '..tostring(text or err))
  ui.text('Состав на ограбление: порог подсказки по умолчанию 2 (п. 3.1 / 10.4). В предупреждении доступны {dispatch_officers}, {robbery_min_officers}. Число по радару/салону — оценка; реальный совместный выезд подтверждаете вы. Для всех подсказок доступны остальные переменные Copilot.')
  ui.text('База источников: 28.10.2026. Слоты мегафона учитываются только после отдельного включения и проверки, что их текст предупреждает об огне по колёсам. Обычное «остановитесь» не считается. По Мануалу также нужны погоня свыше 10 минут, место вне города, парный назначенный патруль и условия применения силы; исключения проверяются отдельно. Счётчик не разрешает огонь.')
 end
 s.vehicleDraft=d;s:autoSettings('vehicle',{'vehicle'},d,'vehicleDraft');s:autosaveHint(ui,'vehicle');s:drawNotice(ui)
end
local function inside(r,x,y)return r and x>=r.x and y>=r.y and x<=r.x+r.w and y<=r.y+r.h end
function M.reserve(controller,im,hud,fonts,taserHeight)
 controller.hudMetrics=nil;controller.bounds=nil
 local v=controller:view();if not v.visible then return end
 local io=im.GetIO();local r=hud:layout(io.DisplaySize.x,io.DisplaySize.y);if not r then return end
 local scale=math.max(.7,math.min(r.scale,1));local w=r.w;local wrap=w-24*scale
 local font=fonts.body or im.GetFont();local heading=fonts.heading or font
 local values=v.values or{};local colleagues=v.colleagues or{}
 local title=(controller.state and controller.state.demo and'ДЕМО · 'or'')..(v.statusTitle or v.phase or'ПАТРУЛЬ · КОД 4')
 local roles={driver='водитель ADAM',navigator='штурман ADAM',solo='LINCOLN'}
 local rows={
  (values.unit or colleagues.autoCallsign or'1-L-1')..' · '..(roles[colleagues.ownCruiserRole]or'пешком'),
  'Курс: '..(values.direction or'не определён')..' · '..(values.city or'город не определён'),
  (values.area or'Район не определён')..' · '..(values.map_square or'квадрат неизвестен'),
  'Экипаж: '..(values.crew or'одиночный')..' · рядом ПД: '..#(colleagues.nearbyOfficers or{})..', авто: '..(colleagues.nearbyCruisers or 0)}
 if v.car then
  rows[#rows+1]=(values.vehicle_type or'Транспорт')..' '..(values.model or'')..' ['..tostring(v.car.id)..']'
  rows[#rows+1]='Цвет: '..(values.vehicle_color or'неизвестен')..' · '..(values.occupants_text or'салон не определён')
  rows[#rows+1]='Водитель: '..(v.driver and((v.driver.name or'Игрок')..' ['..v.driver.id..']')or'не установлен')..' · '..(v.car.stale and'последнее наблюдение'or math.floor(v.car.distance or 0)..' м')
 end
 local traffic=v.phase~=nil and v.car~=nil
 if traffic then rows[#rows+1]=v.tireStatus or''end
 local text=table.concat(rows,'\n')
 local th=heading:CalcTextSizeA(14*scale,100000,math.max(1,wrap-30*scale),title).y;local bh=font:CalcTextSizeA(12*scale,100000,wrap,text).y
 local h=th+bh+(traffic and 108 or 30)*scale;local base=taserHeight or 0
 controller.hudMetrics={view=v,w=w,wrap=wrap,h=h,scale=scale,title=title,text=text,titleH=th,bodyH=bh,body=font,heading=heading,traffic=traffic,offset=base>0 and base+8*scale or 0}
 hud:setEquipmentHeight(controller.hudMetrics.offset+h)
end
function M.place(controller,im,hud,fonts)
 local m=controller.hudMetrics;if not m then return end
 local lane=hud:attachmentLayout(im,fonts)
 if lane and lane.equipment then local e=lane.equipment;controller.bounds={x=e.x,y=e.y+m.offset,w=m.w,h=m.h}end
end
function M.over(controller,im)local p=im.GetIO().MousePos;return inside(controller.bounds,p.x,p.y)or false end
function M.drawHud(controller,im)
 local m,r=controller.hudMetrics,controller.bounds;if not m or not r then return end
 local s=m.scale;local list=im.GetForegroundDrawList();local vec=im.ImVec2;local io=im.GetIO()
 local function color(a,b,c,d)return im.ColorConvertFloat4ToU32(im.ImVec4(a,b,c,d or 1))end
 local white=color(.96,.98,1);local x,y=r.x+12*s,r.y+10*s
 local accent=m.view.statusCode==0 and color(.95,.23,.25)or m.view.statusCode==3 and color(1,.67,.20)or color(.18,.72,.80)
 list:AddRectFilled(vec(r.x,r.y),vec(r.x+r.w,r.y+r.h),color(.025,.10,.18,.94),10*s)
 list:AddRectFilled(vec(r.x,r.y),vec(r.x+4*s,r.y+r.h),accent,2*s)
 local function text(t,font,size,xx,yy)list:AddTextFontPtr(font,size*s,vec(xx,yy),white,t,nil,m.wrap)end
 local close={x=r.x+r.w-32*s,y=r.y+8*s,w=24*s,h=24*s}
 list:AddRectFilled(vec(close.x,close.y),vec(close.x+close.w,close.y+close.h),color(.18,.30,.40),4*s)
 list:AddTextFontPtr(m.heading,14*s,vec(close.x+7*s,close.y+3*s),white,'X')
 if controller.state and controller.state.mouseAllowed and not controller.state.modal and inside(close,io.MousePos.x,io.MousePos.y)and im.IsMouseClicked(0)then
  controller.widgetMail={action='hide',life=controller.life,at=controller.now}
 end
 list:AddTextFontPtr(m.heading,14*s,vec(x,y),white,m.title,nil,math.max(1,m.wrap-30*s));y=y+m.titleH+6*s;text(m.text,m.body,12,x,y);y=y+m.bodyH+5*s
 if not m.traffic then return end
 local primary=m.view.phase=='10-55'and{'explain_stop','Причина'}or m.view.phase=='10-66'and{'explain_detention','Основание'}or{'tire','/m +1'}
 local buttons={primary,{m.view.pinned or'high_risk',m.view.pinned=='pursuit_mark'and'Только /pt'or m.view.pinned and'Розыск + /pt'or'10-66'},{'finish','Завершить'}}
 local width=(m.wrap-8*s)/3
 for i,b in ipairs(buttons)do
  local box={x=x+(i-1)*(width+4*s),y=y,w=width,h=32*s}
  list:AddRectFilled(vec(box.x,box.y),vec(box.x+box.w,box.y+box.h),color(.12,.34,.50),5*s)
  local ext=m.body:CalcTextSizeA(11*s,100000,width-4*s,b[2]);text(b[2],m.body,11,box.x+(width-ext.x)/2,box.y+7*s)
  if controller.state and controller.state.mouseAllowed and not controller.state.modal and inside(box,io.MousePos.x,io.MousePos.y)and im.IsMouseClicked(0)then
   controller.widgetMail={action=b[1],life=controller.life,at=controller.now}
  end
 end
 y=y+37*s
 local pause={x=x,y=y,w=m.wrap,h=22*s}
 list:AddRectFilled(vec(x,y),vec(x+m.wrap,y+22*s),color(.10,.25,.34),4*s)
 text(m.view.repeatPaused and'Возобновить подсказки /m'or'Пауза подсказок /m',m.body,11,x+6*s,y+3*s)
 if controller.state and controller.state.mouseAllowed and not controller.state.modal and inside(pause,io.MousePos.x,io.MousePos.y)and im.IsMouseClicked(0)then
  controller.widgetMail={action='repeat_pause',life=controller.life,at=controller.now}
 end
 y=y+26*s;text(m.view.cooldown>0 and('Следующее предупреждение через '..math.ceil(m.view.cooldown/1000)..' с')or'Alt — курсор · F4 — полная консоль',m.body,11,x,y)
end
return M

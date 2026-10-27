-- Render plain cached observations only. Buttons create intents; main executes.
local copy=require('pa26_bindings').copy;local menu=require 'pa26_menu';local prefs=require 'pa26_copilot_settings'
local M={}
function M.offer(s,callbacks,action)
 local p,err=callbacks.copilotOffer(action)
 if p then s.vehicleConfirm=p else s:notify(err,'vehicle',false)end
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
 s.copilotPage=s:choice('Раздел##copilot-page',s.copilotPage or'work',{{'work','Ситуация'},{'settings','Настройки и тексты'}},ui)
 local d=s.vehicleDraft or copy(s.lib.vehicle);local cfg=d.copilot or prefs.defaults();d.copilot=cfg
 if s.copilotPage=='work'then
  if c then
   s:settingsHeading(ui,(values.model or'Машина')..' ['..c.id..'] · '..(v.phase or'Выбрана'))
   ui.text((values.vehicle_color or'Цвет неизвестен')..' · Гос. номер: '..(values.vehicle_plate or'не установлен'))
   ui.text((values.occupants_text or'Салон не определён')..' · Водитель: '..(v.driver and('ID '..v.driver.id)or'не установлен')..' · '..math.floor(c.distance)..' м')
   if c.armed or v.phase=='10-66'or v.phase=='Преследование'then ui.text('Повышенный риск · рассмотрите 10-66. Наличие оружия не подтверждает стрельбу.')end
  else ui.text('Выберите видимую машину впереди. Выбор машины не меняет человека для обычного взаимодействия.')end
  if s:button('Выбрать ближайшую впереди##copilot-select',ui)then local ok,err=callbacks.copilotSelect();if not ok then s:notify(err,'vehicle',false)end end
  local colleagues=v.colleagues or{};local roles={driver='Водитель ADAM',navigator='Штурман-координатор ADAM',solo='Одиночный LINCOLN'}
  ui.text('Маркировка: '..(values.unit or colleagues.autoCallsign or'—')..' · '..(roles[colleagues.ownCruiserRole]or'Пешком'))
  ui.text('Сотрудников ПД рядом: '..#(colleagues.nearbyOfficers or{})..' · экипажей: '..(colleagues.nearbyCruisers or 0))
  ui.text('Радар — ориентир по форме, рации и вашим контактам; он не подтверждает IC-личность или полномочия человека.')
  cfg.pursuit_armed=s:check('Подозреваемые вооружены · моя отметка##copilot-armed',cfg.pursuit_armed)
  d.channel=s:choice('Канал докладов##copilot-radio-channel',d.channel,require('pa26_server_commands').radioChoices,ui)
  cfg.tac_channel=s:choice('Тактический канал##copilot-tac',cfg.tac_channel,{{'TAC 1','TAC 1'},{'TAC 2','TAC 2'},{'TAC 3','TAC 3'}},ui)
  cfg.select_plate=s:field('Госномер, известный по RP · можно оставить пустым##copilot-plate','copilot:plate',cfg.select_plate,256)
  local outcomes={{'проведена беседа','Беседа'},{'выписан штраф','Штраф'},{'подозреваемый задержан','Задержан'},{'Код 4 АДАМ, подозреваемый потерян','CODE 4 ADAM · потерян'}}
  local known=false;for _,row in ipairs(outcomes)do if row[1]==cfg.stop_outcome then known=true end end;if not known then outcomes[#outcomes+1]={cfg.stop_outcome,'Свой итог: '..cfg.stop_outcome}end
  cfg.stop_outcome=s:choice('Итог##copilot-outcome',cfg.stop_outcome,outcomes,ui)
  local function offer(action)
   s.vehicleDraft=d;s:autoSettings('vehicle',{'vehicle'},d,'vehicleDraft');s:flushAutosave(callbacks,true)
   if not s.autosaves.vehicle then M.offer(s,callbacks,action)else s:notify('Исправьте и сохраните настройки транспорта.','vehicle',false)end
  end
  for _,r in ipairs(require('pa26_copilot').actions)do if s:button(r[2]..'##copilot-'..r[1],ui)then offer(r[1])end end
  if v.pinned and s:button((v.pinned=='pursuit_mark'and'Только /pt · без повторного /su'or v.pinned=='combat_wanted'and'Розыск 2.2 + /pt'or'Розыск 8.1 + /pt')..'##copilot-wanted',ui)then offer(v.pinned)end
  if v.phase then
   ui.text(v.tireStatus or'')
   if s:button('/m Предупреждение (+1)##copilot-tire',ui)then offer('tire')end
  end
  ui.text('Розыск по машине — отдельное подтверждение IC-основания и установленного водителя. ID машины не считается госномером. ДА отправляет показанные строки; факт выдачи определяет сервер. N сохраняет кнопку на карточке.')
 else
  if v.moscowTime then ui.text(string.format('МСК %02d:%02d · окно рейдов: ',v.moscowTime.hour,v.moscowTime.min)..(v.raidAllowed and'открыто'or'закрыто')..'. Допустимость конкретной операции проверяется отдельно.')end
  ui.text('Изменения сохраняются автоматически. Старые значения остальных функций и ваши бинды остаются своими.')
  d.enabled=s:check('Включить транспортные действия PA##copilot-vehicle-enabled',d.enabled)
  d.require_patrol=s:check('Транспорт только в активном патруле##copilot-vehicle-patrol',d.require_patrol)
  d.megaphone_enabled=s:check('Включить мегафон##copilot-megaphone-enabled',d.megaphone_enabled)
  for _,r in ipairs(prefs.booleans)do cfg[r[1]]=s:check(r[2]..'##copilot-setting-'..r[1],cfg[r[1]])end
  for _,r in ipairs(prefs.numbers)do
   local n=im.new.int(cfg[r[1]]);if im.InputInt(r[2]..'##copilot-setting-'..r[1],n)then cfg[r[1]]=n[0]end
  end
  local delta=im.new.float(cfg.stationary_delta);if im.SliderFloat('Порог неподвижности, м##copilot-stationary',delta,.05,5)then cfg.stationary_delta=delta[0]end
  for _,r in ipairs(prefs.texts)do cfg[r[1]]=s:field(r[2]..'##copilot-text-'..r[1],'copilot:text:'..r[1],cfg[r[1]],r[3]*2+1,true,64)end
  ui.text('В напоминании о районе: {officers}, {min_officers}; в счётчике: {warnings}, {warning_count}, {ooc_warning_count}.')
  local choices={};for _,r in ipairs(prefs.templates)do choices[#choices+1]=r end
  s.copilotTemplate=s:choice('Изменить реплику##copilot-template',s.copilotTemplate or'stop',choices,ui)
  local key=s.copilotTemplate
  cfg.templates[key]=s:field('Реплика##copilot-rp','copilot:rp:'..key,cfg.templates[key],8193,true,140)
  ui.text('Для ориентировки перед розыском — строки /me, /do, /try или /todo. Для остальных реплик — текст без /команды; несколько строк допускаются. Род: {gender:передал|передала}.')
  ui.text('Переменные: {unit}, {station}, {crew}, {model}, {vehicle_id}, {vehicle_color}, {vehicle_description}, {vehicle_plate}, {occupants_text}, {driver_id}, {driver_name}, {area}, {map_square}, {direction}, {tac}, {stop_outcome}, {armed_text}, {my_firstname}.')
  local text,err=callbacks.copilotPreview(key,cfg);ui.text('Предпросмотр: '..tostring(text or err))
  ui.text('Подсказки правил основаны на сохранённой базе от 25.10.2026. Счётчик предупреждений не является разрешением на огонь; форму, ситуацию и применимость исключений проверяет офицер.')
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
 local title=(controller.state and controller.state.demo and'ДЕМО · 'or'')..v.phase..' · '..(v.values and v.values.model or'Машина')..' ['..v.car.id..'] · '..string.format('%02d:%02d',math.floor(v.duration/60),v.duration%60)
 local text=(v.values and v.values.occupants_text or'')..'\n'..v.tireStatus
 local th=heading:CalcTextSizeA(14*scale,100000,wrap,title).y;local bh=font:CalcTextSizeA(12*scale,100000,wrap,text).y
 local h=th+bh+94*scale;local base=taserHeight or 0
 controller.hudMetrics={view=v,w=w,wrap=wrap,h=h,scale=scale,title=title,text=text,titleH=th,bodyH=bh,body=font,heading=heading,offset=base>0 and base+8*scale or 0}
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
 list:AddRectFilled(vec(r.x,r.y),vec(r.x+r.w,r.y+r.h),color(.025,.10,.18,.94),10*s)
 local function text(t,font,size,xx,yy)list:AddTextFontPtr(font,size*s,vec(xx,yy),white,t,nil,m.wrap)end
 text(m.title,m.heading,14,x,y);y=y+m.titleH+6*s;text(m.text,m.body,12,x,y);y=y+m.bodyH+5*s
 local buttons={{'tire','/m +1'},{m.view.pinned or'high_risk',m.view.pinned=='pursuit_mark'and'Только /pt'or m.view.pinned and'Розыск + /pt'or'10-66'},{'finish','Завершить'}}
 local width=(m.wrap-8*s)/3
 for i,b in ipairs(buttons)do
  local box={x=x+(i-1)*(width+4*s),y=y,w=width,h=32*s}
  list:AddRectFilled(vec(box.x,box.y),vec(box.x+box.w,box.y+box.h),color(.12,.34,.50),5*s)
  local ext=m.body:CalcTextSizeA(11*s,100000,width-4*s,b[2]);text(b[2],m.body,11,box.x+(width-ext.x)/2,box.y+7*s)
  if controller.state and controller.state.mouseAllowed and not controller.state.modal and inside(box,io.MousePos.x,io.MousePos.y)and im.IsMouseClicked(0)then
   controller.widgetMail={action=b[1],life=controller.life,at=controller.now}
  end
 end
 y=y+37*s;text(m.view.cooldown>0 and('Следующее предупреждение через '..math.ceil(m.view.cooldown/1000)..' с')or'Alt — курсор · F4 — полная консоль',m.body,11,x,y)
end
return M

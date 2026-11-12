-- Render plain cached observations only. Buttons create intents; main executes.
local copy=require('pa26_bindings').copy;local menu=require 'pa26_menu';local prefs=require 'pa26_copilot_settings'
local M={}
function M.present(s,callbacks,p,err)
 if not p then s:notify(err,'vehicle',false)
 elseif p.rpVariants then s.copilotVariant=p
 elseif p.navigation then callbacks.openGround(p)
 else s.vehicleConfirm=p end
end
function M.offer(s,callbacks,action)
 local p,err=callbacks.copilotOffer(action)
 M.present(s,callbacks,p,err)
end
function M.editReport(s,ui,callbacks)
 if s.reportEdit then
  local f=s.reportEdit
  s:settingsHeading(ui,'Изменить данные доклада')
  ui.text('Проверьте юнит и состав экипажа. Эти правки относятся только к этому докладу; перед отправкой появится новый предпросмотр.')
  for _,r in ipairs(require('pa26_report_context').fields)do
   f.values[r[1]]=s:field(r[2]..'##report-edit-'..r[1],f.proposal.token..':'..r[1],f.values[r[1]]or'Не задано',1025,r[1]=='crew',64)
  end
  if s:button('Вернуться к предпросмотру##report-edit-preview',ui)then
   local p,why=callbacks.copilotEditReport(f.proposal,f.values)
   if p then s.vehicleConfirm=p;s.reportEdit=nil else s:notify(why,'vehicle',false)end
  end
  if s:button('Отменить доклад##report-edit-cancel',ui)then s.reportEdit=nil end
  return true
 end
 return false
end
local groups=require 'pa26_ui_groups'
local dispatch=require 'pa26_dispatch'
M.dispatchFamilies={}
local dispatchChoices,dispatchById={},{}
for _,row in ipairs(dispatch.primaryActions)do
 if row[1]~='gas_order'then
  M.dispatchFamilies[#M.dispatchFamilies+1]=row
  dispatchChoices[#dispatchChoices+1]={row[1],row[2]..'##dispatch-family-'..row[1]}
  dispatchById[row[1]]=row
 end
end
function M.quick(s,ui,callbacks)
 local send=function(action)M.offer(s,callbacks,action)end
 s:settingsHeading(ui,'Быстрые доклады')
 ui.text('Работают и без сеанса патруля. Перед отправкой — предпросмотр, юнит и экипаж, ДА / НЕТ.')
 local quick={};for _,r in ipairs(require('pa26_copilot').quick)do quick[#quick+1]={r[1],r[2]..'##copilot-quick-'..r[1]}end
 groups.buttons(s,ui,quick,send,true)
 if callbacks.custodyReport then
  groups.buttons(s,ui,{{'detention','Задержан · доклад##custody-detention'},{'jail','КПЗ · доклад##custody-jail'}},function(kind)
   local ok,err=callbacks.custodyReport(kind);if not ok then s:notify(err,'vehicle',false)end
  end,true)
  ui.text('После /cuff ID и /arrest ID PA также предлагает эти доклады автоматически.')
 end
 local cfg=s.lib.vehicle.copilot
 if cfg.swat_reports then
  s:settingsHeading(ui,'Доклады SWAT')
  local reports={}
  for _,row in ipairs(prefs.swatReports)do reports[#reports+1]={row[1],row[2]..'##copilot-quick-'..row[1]}end
  groups.buttons(s,ui,reports,send,true)
  ui.text('Передайте статус группы в '..cfg.swat_channel..' после предпросмотра. Сеанс обычного патруля не меняется.')
 end
end
function M.dispatch(s,ui,callbacks)
 s:settingsHeading(ui,'Спецвызовы')
 local r=dispatchById[s.dispatchIncident]
 if not r then
  ui.text('Выберите вид вызова, затем нужный этап доклада.')
  groups.buttons(s,ui,dispatchChoices,function(action)s.dispatchIncident=action end,true)
  return
 end
 if s:button('Все спецвызовы##dispatch-back',ui)then s.dispatchIncident=nil;return end
 local send=function(action)M.offer(s,callbacks,action)end
 if r then
  s:settingsHeading(ui,r[2])
  local stage=callbacks.dispatchStatus and callbacks.dispatchStatus();if stage then ui.text((stage.demo and'Последний демо-этап: 'or'Последний переданный этап: ')..stage.label)end
  ui.text('Выберите текущий этап. Это ваша оценка ситуации: PA не подтверждает прибытие, личность или результат по метке. Отправка только после ДА.')
  local rows={{r[1],(r[1]=='dispatch_search'and'Начинаю поиск'or'Выехал')..'##copilot-dispatch-'..r[1]}}
  for _,sub in ipairs(dispatch.followups[r[1]]or{})do rows[#rows+1]={sub[1],sub[2]..'##copilot-dispatch-'..sub[1]}end
  if r[1]=='dispatch_gas'then rows[#rows+1]={'gas_order',dispatch.byAction.gas_order.label..'##copilot-dispatch-gas_order'}end
  groups.buttons(s,ui,rows,send,true)
  if r[1]=='dispatch_search'or r[1]=='dispatch_colleague'then ui.text(require('pa26_field_radio').source)end
 end
end
function M.draw(s,ui,data,callbacks)
 local im=s.imgui;local v=data.copilot or{};local c=v.car;local values=v.values or{}
 s.currentNoticeScope='vehicle';s:settingsHeading(ui,'Трафик и погоня')
 s.copilotPage=s:choice('Раздел##copilot-page',s.copilotPage or'work',{{'work','Ситуация'},{'grounds','Причина и основание'},{'rights','Задержание и права'},{'settings','Настройки и тексты'}},ui)
 local d=s.vehicleDraft or copy(s.lib.vehicle);local cfg=d.copilot or prefs.defaults();d.copilot=cfg
 local function offer(action)
  s.vehicleDraft=d;s:autoSettings('vehicle',{'vehicle'},d,'vehicleDraft');s:flushAutosave(callbacks,true)
  if not s.autosaves.vehicle then M.offer(s,callbacks,action)else s:notify('Исправьте и сохраните настройки транспорта.','vehicle',false)end
 end
 if s.copilotPage=='work'then
  if s.copilotDuty then
   s:settingsHeading(ui,'Доступность экипажа · выберите доклад')
   groups.buttons(s,ui,{{'busy_report','Временно занят · 10-8##wheel-duty-busy'},{'break_report','Перерыв · Код 7##wheel-duty-break'},{'patrol_continue','Снова доступен · Код 4##wheel-duty-available'}},offer)
   ui.text('Это отдельный доклад с предпросмотром. Таймер и состояние сеанса патруля меняются в разделе «Патруль и экипаж».')
   if s:button('Скрыть выбор доступности##wheel-duty-close',ui)then s.copilotDuty=nil end
  end
  if not s.lib.alerts.on_duty or not s.lib.alerts.enabled then
   ui.text('Включите режим «На службе» и связь, чтобы отправлять доклады и начинать операции.')
   if s:button('Открыть настройки службы##copilot-duty-settings',ui)then s.copilotPage='settings';return end
  end
  if c then
   s:settingsHeading(ui,(values.vehicle_description or values.model or'Машина')..' ['..c.id..'] · '..(v.phase or'Выбрана'))
   ui.text('Гос. номер: '..(values.vehicle_plate or'не установлен'))
   ui.text((values.occupants_text or'Салон не определён')..' · Водитель: '..(v.driver and('ID '..v.driver.id)or'не установлен')..' · '..(c.stale and'последнее наблюдение'or math.floor(c.distance or 0)..' м'))
   if c.armed or v.phase=='10-66'or v.phase=='Преследование'then ui.text('Повышенный риск · рассмотрите 10-66. Наличие оружия не подтверждает стрельбу.')end
  else ui.text('Выберите видимую машину. Если автовыбор водителя включён, его ID станет целью биндов и обычного взаимодействия.')end
  if v.phase=='10-55'then ui.text(v.stopWarningStatus or'')end
  local startLabel=v.phase=='10-55'and'Повторить требование'or'Начать 10-55'
  local primary={{'stop_order',startLabel..'##copilot-stop_order'},{'pursuit','10-57 · Начать погоню##copilot-pursuit'},
   {'explain_stop','Причина остановки##copilot-explain_stop','Выберите и озвучьте причину 10-55. Copilot продолжит с текущего шага. Отправка после подтверждения.'},{'finish','10-99 · Завершить##copilot-finish'}}
  if v.phase=='10-55'and v.stopWarnings>=v.stopWarningLimit then table.remove(primary,1)end
  groups.buttons(s,ui,primary,function(action)
   if action=='stop_order'or action=='pursuit'then
    s.vehicleDraft=d;s:autoSettings('vehicle',{'vehicle'},d,'vehicleDraft');s:flushAutosave(callbacks,true)
    if s.autosaves.vehicle then s:notify('Исправьте и сохраните настройки транспорта.','vehicle',false);return end
    local ok,err=callbacks.requestVehicleAction(action);if not ok then s:notify(err,'vehicle',false)end
   else offer(action)end
  end,true)
  if v.phase=='Преследование'or v.phase=='10-57 FOXTROT'then
   groups.buttons(s,ui,{{'wanted','Причина розыска##copilot-pursuit-wanted'},{'pursuit_mark','Метка /pt##copilot-pursuit-mark'}},function(action)
    if action=='wanted'then
     local ok,err=callbacks.pursuitWanted();if not ok then s:notify(err,'vehicle',false)end
    else offer(action)end
   end,true)
  end
  if v.pinned and v.pinned~='pursuit_mark'and s:button((v.pinned=='combat_wanted'and'Розыск 2.2 · отдельно от /pt'or'Розыск 8.1 · отдельно от /pt')..'##copilot-wanted',ui)then offer(v.pinned)end
  if s:button((s.copilotMore and 'Скрыть дополнительные действия'or'Доклады, осмотр и 10-66')..'##copilot-more',ui)then s.copilotMore=not s.copilotMore end
  if s.copilotMore then
   groups.buttons(s,ui,{{'stop','Доклад 10-55##copilot-stop'},{'high_risk','10-66 · CODE 3##copilot-high_risk'},
    {'approach','Осмотр транспорта##copilot-approach'},{'risk_order','10-66 · Указания водителю##copilot-risk_order'},
    {'foot','10-57 FOXTROT##copilot-foot'},{'tire','Мегафон: колёса (+1)##copilot-tire'},
    {'explain_detention','Основание и права##copilot-explain_detention'},{'select','Выбрать машину впереди##copilot-select'},
    {'pt','Быстрый /pt рядом##copilot-fast-pt'}},function(action)
     if action=='pt'then callbacks.fastPt()
     elseif action=='select'then local ok,err=callbacks.copilotSelect();if not ok then s:notify(err,'vehicle',false)end
     else offer(action)end
    end,true)
   if v.phase then ui.text(v.tireStatus or'')end
  end
  local bulletin=v.stolen
  if bulletin then
   s:settingsHeading(ui,'Ориентировка об угоне')
   ui.text(bulletin.model..(bulletin.color and bulletin.color~=''and' · '..bulletin.color or'')..' · '..bulletin.area..' · ещё '..bulletin.remaining..' с')
   ui.text(bulletin.targetLabel or'Квадрат района не установлен. Точной позиции автомобиля в ориентировке нет.')
   if s:button('Уточнить ориентировку##stolen-edit',ui)then s.stolenDraft=copy(bulletin)end
   if s.stolenDraft then
    local draft=s.stolenDraft
    for _,r in ipairs({{'model','Модель'},{'color','Цвет'},{'area','Район из ориентировки'},{'place','Уточнение места'}})do draft[r[1]]=s:field(r[2]..'##stolen-'..r[1],'stolen:'..draft.revision..':'..r[1],draft[r[1]],513)end
    if s:button('Применить мои уточнения##stolen-apply',ui)then local ok,why=callbacks.stolenCorrect(draft,draft.revision);if ok then s.stolenDraft=nil;s:notify('Ориентировка уточнена. Перед докладом проверьте новый предпросмотр.','vehicle',false)else s:notify(why,'vehicle',false)end end
    if s:button('Отменить уточнения##stolen-cancel',ui)then s.stolenDraft=nil end
   end
   if s:button('Убрать ориентировку и выделение##stolen-clear',ui)then callbacks.stolenClear();s.stolenDraft=nil end
  end
  if v.windowActive then
   s:settingsHeading(ui,'Разговор с водителем')
   if v.windowAwait then
    ui.text(v.windowReady and'Отметьте ответ водителя об окне.'or'Вопрос об окне передан. Ожидаем ответ водителя.')
    if v.windowReady then
     groups.buttons(s,ui,{{'open','Да · окно открыто##window-open'},{'closed','Нет · окно закрыто##window-closed'}},function(answer)
      local ok,why=callbacks.copilotWindow(answer)
      if not ok then s:notify(why,'vehicle',false)end
     end,true)
    end
    if s:button('Пропустить вопрос об окне##window-skip',ui)then
     local ok,why=callbacks.copilotWindow('skip')
     if not ok then s:notify(why,'vehicle',false)end
    end
   end
   local stage=v.documentsChecked and'Документы проверены' or v.reasonExplained and'Причина озвучена' or
    v.documentsRequested and'Паспорт и лицензии запрошены' or v.contactIntroduced and'Представление завершено' or
    v.windowReply=='open'and'Окно открыто' or v.windowReply=='closed'and'Окно закрыто'
   if stage then ui.text(stage..'.')end
   if v.contactAvailable then
    local actions={}
    if not v.contactIntroduced and not v.documentsRequested and not v.reasonExplained then
     actions[#actions+1]={'greet_stop','Представиться и показать удостоверение##copilot-greet-stop'}
     if not v.windowAwait and v.windowVehicle then actions[#actions+1]={'window_question','Спросить об окне##copilot-window-question'}end
    end
    if not v.documentsRequested then actions[#actions+1]={'documents','Запросить паспорт и лицензии##copilot-request-documents'}end
    groups.buttons(s,ui,actions,offer,true)
    local marks={}
    if not v.contactIntroduced and not v.documentsRequested and not v.reasonExplained then
     marks[#marks+1]={'introduced','Уже представился и показал удостоверение##copilot-mark-intro'}
    end
    if not v.documentsRequested then marks[#marks+1]={'documentsRequested','Уже запросил документы##copilot-mark-request'}end
    if not v.documentsChecked then marks[#marks+1]={'documentsChecked','Документы проверены##copilot-mark-documents'}end
    if not v.reasonExplained then marks[#marks+1]={'reasonExplained','Причину уже объяснил##copilot-mark-reason'}end
    if #marks>0 then
     if s:button((s.copilotContactMarks and'Скрыть отметки'or'Отметить выполненный шаг')..'##copilot-contact-marks',ui)then
      s.copilotContactMarks=not s.copilotContactMarks
     end
     if s.copilotContactMarks then
      ui.text('Отмечайте шаги, которые уже выполнили сами. Эти кнопки не пишут в чат.')
      groups.buttons(s,ui,marks,function(mark)
       local ok,why=callbacks.copilotContact(mark)
       if not ok then s:notify(why,'vehicle',false)end
      end,true)
     end
    end
   end
  end
  if s:button((s.fastPtChooseId and'Скрыть выбор человека'or'Выбрать человека по ID для /pt')..'##copilot-pt-manual',ui)then s.fastPtChooseId=not s.fastPtChooseId end
  if s.fastPtChooseId then
   ui.text('/pt: водитель ситуации → выбранный человек → водитель выбранной машины. Данные серверного списка розыска сейчас не доступны PA; случайный прохожий не выбирается.')
   local text=s:field('ID игрока##copilot-pt-id','copilot:pt-id','',16)
   if s:button('Выбрать человека##copilot-pt-select-id',ui)then
    local id=text:match('^%s*(%d+)%s*$');local ok,why=callbacks.selectNearbyId(id and tonumber(id)or nil)
    if not ok then s:notify(why,'vehicle',false)end
   end
  end
  s:settingsHeading(ui,'Связь и итог ситуации')
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
  ui.text('Розыск по машине использует вашу RP-конвенцию номера из ID. /su и /pt подтверждаются отдельно; обычный /su ID открывает полный помощник.')
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
 for _,r in ipairs({{'on_duty','На службе · автофункции PA'},{'enabled','Связь · разрешить доклады PA'}})do
  local value,changed=s:check(r[2]..'##copilot-alert-'..r[1],s.lib.alerts[r[1]])
  if changed then
   local lib=copy(s.lib);lib.alerts[r[1]]=value;local ok,err=callbacks.save(lib)
   if ok then if s.alertDraft then s.alertDraft[r[1]]=value end else s:notify(err,'vehicle',false)end
  end
 end
 ui.text('Это режим PA. Серверную смену он не заменяет.')
  ui.text('Дальность захвата авто, м (5–150)');local radius=im.new.int(d.radius);im.PushItemWidth(-1)
  if im.SliderInt('##copilot-radius',radius,5,150)then d.radius=radius[0];d.retain_distance=math.max(d.retain_distance,d.radius)end;im.PopItemWidth()
  d.sync_driver_target=s:check('Водитель — цель биндов##copilot-sync-driver',d.sync_driver_target)
  ui.text('Работает пешком и из машины, включая близкую видимую цель сбоку. Автовыбор не подменяет вручную выбранного человека при фоновом обновлении; повторный выбор машины привязывает её водителя заново.')
  if v.moscowTime then ui.text(string.format('МСК %02d:%02d · сохранённое окно %02d:00–%02d:00: ',v.moscowTime.hour,v.moscowTime.min,cfg.raid_start_hour,cfg.raid_end_hour)..(v.raidAllowed and'внутри интервала'or'вне интервала'))end
  ui.text('В источнике есть расхождение: регламент 4.3 — 14:00–22:00; 10.9 запрещает 20:00–13:00. Часовой пояс там не указан. Настройка PA — ваша трактовка, а не разрешение на рейд.')
  ui.text('Изменения сохраняются автоматически. Старые значения остальных функций и ваши бинды остаются своими.')
  ui.text('Быстрый /pt: '..require('pa26_bindings').shortcutName(d.fast_pt_shortcut))
  if s:button('Назначить клавишу быстрого /pt##copilot-pt-key',ui)then callbacks.capture({kind='feature',group='vehicle',field='fast_pt_shortcut'})end
  if d.fast_pt_shortcut.key~=0 and s:button('Убрать клавишу /pt##copilot-pt-key-clear',ui)then d.fast_pt_shortcut={key=0,ctrl=false,alt=false,shift=false}end
  d.enabled=s:check('Включить транспортные действия PA##copilot-vehicle-enabled',d.enabled)
  d.require_patrol=s:check('Дополнительные действия транспорта только в патруле##copilot-vehicle-patrol',d.require_patrol)
  ui.text('10-55, 10-57 и действия текущей ситуации доступны во время смены без запущенного патруля.')
  d.megaphone_enabled=s:check('Включить мегафон##copilot-megaphone-enabled',d.megaphone_enabled)
  for _,r in ipairs(prefs.booleans)do
   if r[1]:match('^ground_')then cfg[r[1]]=require('pa26_procedure_window').check(s,ui,r[2]..'##copilot-setting-'..r[1],cfg[r[1]])
   else cfg[r[1]]=s:check(r[2]..'##copilot-setting-'..r[1],cfg[r[1]])end
  end
  cfg.ground_channel=s:choice('Канал речи при общении и в формах##copilot-ground-channel',cfg.ground_channel or'/s',{{'','Обычный чат'},{'/s','Речь /s'}},ui)
  cfg.swat_channel=s:choice('Канал докладов SWAT##copilot-swat-channel',cfg.swat_channel,require('pa26_server_commands').radioChoices,ui)
  ui.text('10-55: после вопроса /do Copilot ждёт вашу отметку Да / Нет. Задержка и срок показа настраиваются ниже.')
  ui.text('Доклад о возможном оружии предлагается после RP-осмотра транспорта, если оружие у водителя ещё видно. Канал берётся из настроек докладов Copilot. Тексты докладов и реплики общения доступны в списке реплик.')
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
   if prefs.promptKeys[r[1]]then
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
  ui.text('SWAT: {unit}, {area}, {map_square}, {patrol_start}, {patrol_resume}, {patrol_finish}.')
  ui.text('Переменные: {unit}, {station}, {crew}, {vehicle_type}, {vehicle_type_gen}, {model}, {vehicle_id}, {vehicle_color}, {vehicle_description}, {vehicle_plate}, {occupants_text}, {driver_id}, {driver_name}, {city}, {area}, {map_square}, {direction}, {tac}, {stop_outcome}, {armed_text}, {my_firstname}. {patrol_return} добавляет настроенную фразу о продолжении, пока сеанс патруля активен. Мегафон: {officer_intro} собирает звание, отдел и фамилию из профиля. Доступны отдельно {rank}, {department}, {my_lastname}.')
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
  rows[#rows+1]=(values.vehicle_description or values.model or'Транспорт')..' ['..tostring(v.car.id)..'] · '..(values.occupants_text or'салон не определён')
  rows[#rows+1]='Водитель: '..(v.driver and((v.driver.name or'Игрок')..' ['..v.driver.id..']')or'не установлен')..' · '..(v.car.stale and'последнее наблюдение'or math.floor(v.car.distance or 0)..' м')
 end
 local traffic=v.phase~=nil and v.car~=nil
 if traffic then rows[#rows+1]=v.phase=='10-55'and(v.stopWarningStatus or'')or(v.tireStatus or'')end
 local text=table.concat(rows,'\n')
 local th=heading:CalcTextSizeA(14*scale,100000,math.max(1,wrap-30*scale),title).y;local bh=font:CalcTextSizeA(12*scale,100000,wrap,text).y
 local buttons={{'high_risk','10-66'},{'pursuit','10-57'}}
 if v.phase~='10-55'or v.stopWarnings<v.stopWarningLimit then
  buttons[#buttons+1]={'megaphone_order','Мегафон: приказ'}
 end
 if v.phase=='10-55'then buttons[#buttons+1]={'explain_stop','Причина остановки'}
 elseif v.phase=='10-66'then buttons[#buttons+1]={'explain_detention','Основание задержания'}end
 if v.phase=='Преследование'or v.phase=='10-57 FOXTROT'then
  buttons[#buttons+1]={'pursuit_wanted','Причина розыска'}
  buttons[#buttons+1]={'pursuit_mark','Метка /pt'}
  buttons[#buttons+1]={'tire','Мегафон: колёса'}
 end
 if v.pinned and v.pinned~='pursuit_mark'then buttons[#buttons+1]={v.pinned,'Предложение розыска'}end
 if v.phase then buttons[#buttons+1]={'finish','Завершить'}end
 local h=th+bh+(30+math.ceil(#buttons/2)*38+(traffic and 49 or 0))*scale
 local base=taserHeight or 0
 controller.hudMetrics={view=v,w=w,wrap=wrap,h=h,scale=scale,title=title,text=text,titleH=th,bodyH=bh,body=font,heading=heading,
  traffic=traffic,buttons=buttons,offset=base>0 and base+8*scale or 0}
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
 local width=(m.wrap-4*s)/2
 for i,b in ipairs(m.buttons)do
  local box={x=x+(i-1)%2*(width+4*s),y=y+math.floor((i-1)/2)*38*s,w=width,h=34*s}
  list:AddRectFilled(vec(box.x,box.y),vec(box.x+box.w,box.y+box.h),color(.12,.34,.50),5*s)
  local wrap=math.max(1,width-8*s)
  local ext=m.body:CalcTextSizeA(11*s,100000,wrap,b[2])
  list:AddTextFontPtr(m.body,11*s,vec(box.x+(width-ext.x)/2,box.y+(box.h-ext.y)/2),white,b[2],nil,wrap)
  if controller.state and controller.state.mouseAllowed and not controller.state.modal and inside(box,io.MousePos.x,io.MousePos.y)and im.IsMouseClicked(0)then
   controller.widgetMail={action=b[1],life=controller.life,at=controller.now}
  end
 end
 if not m.traffic then return end
 y=y+math.ceil(#m.buttons/2)*38*s
 local pause={x=x,y=y,w=m.wrap,h=22*s}
 list:AddRectFilled(vec(x,y),vec(x+m.wrap,y+22*s),color(.10,.25,.34),4*s)
 text(m.view.repeatPaused and'Возобновить подсказки /m'or'Пауза подсказок /m',m.body,11,x+6*s,y+3*s)
 if controller.state and controller.state.mouseAllowed and not controller.state.modal and inside(pause,io.MousePos.x,io.MousePos.y)and im.IsMouseClicked(0)then
  controller.widgetMail={action='repeat_pause',life=controller.life,at=controller.now}
 end
 y=y+26*s;text(m.view.cooldown>0 and('Следующее предупреждение через '..math.ceil(m.view.cooldown/1000)..' с')or'Alt — курсор · F4 — полная консоль',m.body,11,x,y)
end
return M

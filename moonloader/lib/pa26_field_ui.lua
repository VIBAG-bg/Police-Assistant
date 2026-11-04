-- Existing Studio widgets, persistence and acknowledgment windows; no native work.
local core=require 'pa26_core';local model=require 'pa26_bindings';local menu=require 'pa26_menu';local M={}
local tabs={{'navigation','Навигация'},{'coordinates','Координаты (OOC)'},{'cruiser','Помощь водителю'},{'pinned','Памятка поверх игры'},{'leadership','Руководство'}}
local function offer(s,callbacks,kind,arg)
 local p,why=callbacks.fieldOffer(kind,arg)
 if p then s.assistConfirm={kind='field',proposal=p}else s:notify(why,'field',false)end
end
local function number(s,ui,d,key,label,min,max)
 ui.text(label);s.imgui.PushItemWidth(-1);local n=s.imgui.new.float(d[key])
 if s.imgui.SliderFloat('##field-'..key,n,min,max)then d[key]=n[0]end;s.imgui.PopItemWidth()
end
local function save(s,callbacks,d)
 local candidate=model.copy(s.lib);candidate.field=d
 local ok,why=callbacks.save(candidate)
 s:notify(ok and'Настройки инструментов сохранены.'or why,'field',false,ok and'info'or'warning')
 if ok then s.fieldDraft=nil end;return ok
end
local function roadStatus(ui,v)
 local r=v.roads or{};local loading=r.phase=='loading'
 ui.text('Дорожный GPS: '..(r.available and'доступен'or loading and'подготовка'or'недоступен'))
 ui.text('Граф: '..(r.source or'Включите навигацию для подготовки'))
 if r.validation then ui.text(r.validation)end
 if loading then ui.text('Подготовка: '..tostring(r.progress or 0)..'% · '..(r.status or''))
 elseif r.status and not r.available then ui.text(r.status)end
 if r.fallback then ui.text('Резервный источник: '..r.fallback)end
 ui.text('Маршрут: '..(v.points and #v.points>=2 and'построен'or v.target and'ожидает построения'or'выберите метку на карте'))
end
function M.shareControl(s,ui,callbacks)
 if not s.lib.field.enabled or not s.lib.field.coordinates.enabled then return end
 if s:button('Мои координаты (OOC)##field-share-compact',ui)then offer(s,callbacks,'share')end
end
function M.quick(s,ui,data,callbacks,embedded)
 local cfg=s.lib.field;local v=data.field or{}
 s:settingsHeading(ui,'Навигация и координаты')
 if not cfg.enabled then ui.text('Новые инструменты выключены. Их можно включить в настройках F9.');return end
 ui.text(v.status or'Назначение не выбрано')
 if cfg.navigation.enabled and not embedded then roadStatus(ui,v);if data.mapAdapterStatus then ui.text('Проекция: '..data.mapAdapterStatus)end end
 if v.resumable and s:button('Возобновить маршрут PA##field-resume',ui)then callbacks.fieldClear('resume')end
 if v.target then
  if v.target.marker_missing then ui.text('PA сохраняет назначение; штатный маркер GTA исчез.')end
  ui.text(({waypoint='Метка GTA',mark='OOC-координаты',server='Серверная точка',race='Серверная гонка',bulletin='Примерный сектор ориентировки'})[v.target.kind]or'Назначение')
  if v.distance then ui.text(string.format('%.0f м (%s)',v.distance,v.distanceKind or'по прямой'))end
  if s:button('Сбросить маршрут PA##field-clear',ui)then callbacks.fieldClear()end
 end
 if s:button('Передать мои координаты (OOC)##field-share',ui)then offer(s,callbacks,'share')end
 local text=s:field('Полученные X Y Z##field-paste','field:paste','',160)
 if s:button('Показать на карте · с подтверждением##field-paste-map',ui)then local ok,why=callbacks.fieldPaste(text);if not ok then s:notify(why,'field',false)end end
 if s:button('Убрать OOC-метку##field-mark-clear',ui)then callbacks.fieldClear('mark')end
 ui.text('Координаты OOC. Принятие предложения не устанавливает IC-местоположение человека.')
 if s:button('Открыть настройки инструментов в F9##field-settings-open',ui)then callbacks.openField()end
end
function M.settings(s,ui,data,callbacks)
 local d=s.fieldDraft or model.copy(s.lib.field);s.fieldDraft=d;s.currentNoticeScope='field';s.preferenceContext=true
 s:settingsHeading(ui,'Навигация и инструменты службы')
 d.enabled=s:check('Включить новые инструменты · общий выключатель##field-master',d.enabled)
 ui.text('Выключение останавливает наблюдение, временные маршруты и подсказки этих инструментов. Остальные функции PA сохраняются.')
 if s:button('Сохранить настройки инструментов##field-save',ui)then save(s,callbacks,d);return end
 s.fieldPage=menu.choiceControl(s.imgui,ui,'##field-pages','',s.fieldPage or'navigation',tabs,s,{buttons=true,font=s.buttonFont})
 local page=s.fieldPage;local c=d[page]
 if page=='navigation'then
  c.enabled=s:check('Навигация PA##nav-enabled',c.enabled)
  c.observe_waypoint=s:check('Наблюдать штатную метку GTA на Esc-карте##nav-observe',c.observe_waypoint)
  c.overlay=s:check('Показывать метку и доступный маршрут##nav-overlay',c.overlay)
  c.hud=s:check('Источник и расстояние в компактном HUD##nav-hud',c.hud)
  c.radar=s:check('Маршрут на радаре##nav-radar',c.radar);c.pause_map=s:check('Маршрут поверх Esc-карты##nav-map',c.pause_map)
  c.native_path=s:check('Дорожный маршрут PA · экспериментальный##nav-roads',c.native_path)
  c.keep_waypoint=s:check('Сохранять маршрут PA, если лаунчер убрал метку GTA##nav-keep',c.keep_waypoint)
  ui.text('Карта дорог входит в PA: ничего скачивать или копировать вручную не нужно. Сеть готовится заранее при включённой навигации, затем используется из памяти. Путь строится небольшими порциями; ввод в чат приостанавливает расчёт. Граф двумерный: этаж и высота не подтверждаются.')
  roadStatus(ui,data.field or{})
  c.road_external=s:field('Дополнительный файл дорог · необязательно, используется при ошибке встроенного##nav-external','field:road-external',c.road_external,1024)
  ui.text('Обычно оставьте поле пустым. Сначала проверяется встроенный граф PA, затем выбранный файл и известные резервные папки игры. PA не изменяет эти файлы и не ищет их по всему диску.')
  number(s,ui,c,'road_snap','Максимум до ближайшей дороги, м',25,600)
  number(s,ui,c,'road_work','Предел операций поиска за кадр',16,1024)
  number(s,ui,c,'road_budget_ms','CPU-бюджет расчёта, мс',.25,3)
  if s:button('Перезагрузить дорожный граф##nav-roads-reload',ui)then callbacks.fieldClear('roads');s:notify('Кэш очищен. Граф подготовится заново при включённой навигации, даже до выбора назначения.','field',false)end
  ui.text('Прямое расстояние подписано «по прямой». Это не дорожный маршрут. PA не перехватывает клики карты и не удаляет вашу красную метку.')
  number(s,ui,c,'observe_ms','Наблюдение метки, мс',200,2000)
  number(s,ui,c,'recalculate_ms','Минимальная пауза поиска, мс',1500,10000)
  number(s,ui,c,'movement','Перемещение для нового поиска, м',5,200)
  number(s,ui,c,'missing_grace_ms','Подтверждение удаления метки, мс',200,5000)
  number(s,ui,c,'retry_ms','Повтор после пустого маршрута, мс',1000,30000)
  number(s,ui,c,'arrival','Радиус прибытия к временной метке, м',1,100)
  number(s,ui,c,'max_segments','Предел сегментов отрисовки',16,256)
  number(s,ui,c,'line_width','Толщина линии',1,8);number(s,ui,c,'opacity','Прозрачность маршрута',.1,1)
  if data.mapAdapterStatus then ui.text('Проекция: '..data.mapAdapterStatus)end
  M.quick(s,ui,data,callbacks,true)
 elseif page=='coordinates'then
  c.enabled=s:check('Разрешить передачу координат##coord-enabled',c.enabled)
  c.observe=s:check('Предлагать полученные OOC-координаты##coord-observe',c.observe)
  c.arrival_clear=s:check('Убирать временную метку после прибытия##coord-arrival',c.arrival_clear)
  c.channel=s:choice('Канал OOC##coord-channel',c.channel,{{'/rn','/rn · подразделение'},{'/fn','/fn · организация'},{'/ln','/ln · требует проверки'},{'/sms','/sms · требует проверки'}},ui)
  c.phone=s:field('Телефон получателя /sms##coord-phone','field:phone',c.phone,24)
  c.ln_verified=s:check('Я проверил формат и доступ к /ln на сервере##coord-ln',c.ln_verified)
  c.sms_verified=s:check('Я проверил /sms номер текст на сервере##coord-sms',c.sms_verified)
  number(s,ui,c,'ttl_ms','Срок временной метки, мс',1000,1800000)
  number(s,ui,c,'offer_ms','Время предложения, мс',1000,60000)
  ui.text('Формат: Мои координаты: X Y Z (Район, квадрат H-18). Предпросмотр показывает полную команду; длинный пакет не обрезается. Непроверенные /ln и /sms отключены по умолчанию.')
  require('pa26_assist_ui').shortcut(s,ui,callbacks,'field','share_shortcut','Открыть предпросмотр координат')
  if s:button('Предпросмотр передачи координат##coord-preview',ui)then if save(s,callbacks,d)then offer(s,callbacks,'share')end end
 elseif page=='cruiser'then
  c.enabled=s:check('Помощь водителю##cruiser-enabled',c.enabled);c.cruise=s:check('Круиз-контроль · после проверки backend##cruiser-cruise',c.cruise)
  c.signals=s:check('Локальные поворотники и аварийка##cruiser-signals',c.signals)
  c.auto_hazard=s:check('Предлагать аварийку при 10-55##cruiser-auto',c.auto_hazard)
  number(s,ui,c,'target_speed','Заданная скорость · требует калибровки',5,250);number(s,ui,c,'speed_step','Шаг скорости',1,20)
  ui.text('В этой сборке native-управление и геометрия огней не подтверждены. Функции остаются недоступны; клавиши газа и тормоза PA не нажимает. Индикаторы только локальные, без обещания сетевой видимости.')
 elseif page=='pinned'then
  c.enabled=s:check('Показывать закреплённую памятку##pin-enabled',c.enabled)
  local rows={{0,'Не выбрана'}};for _,n in ipairs(s.lib.notes)do rows[#rows+1]={n.id,n.name}end
  c.note_id=s:choice('Сохранённая заметка##pin-note',c.note_id,rows,ui)
  number(s,ui,c,'x','Положение по горизонтали · доля экрана',0,1);number(s,ui,c,'y','Положение по вертикали · доля экрана',0,1)
  number(s,ui,c,'width','Ширина · доля экрана',.15,.9);number(s,ui,c,'height','Высота · доля экрана',.12,.85)
  number(s,ui,c,'opacity','Непрозрачность памятки',.1,1);number(s,ui,c,'font_scale','Масштаб текста',.7,2)
  if s:button('Восстановить положение и размер памятки##pin-reset',ui)then local f=require('pa26_field_settings').defaults().pinned;for _,k in ipairs({'x','y','width','height','opacity','font_scale'})do c[k]=f[k]end;save(s,callbacks,d);return end
  ui.text('В игре памятка пропускает мышь и клавиши. Размеры и положение меняются только здесь в F9. Исходный текст остаётся в отдельном файле заметок; длинный текст полностью доступен в разделе памяток.')
 elseif page=='leadership'then M.leadership(s,ui,data,callbacks,d)end
 s:autoSettings('field',{'field'},d,'fieldDraft');s:autosaveHint(ui,'field')
end
function M.leadership(s,ui,data,callbacks,d)
 local c=d.leadership
 c.enabled=s:check('Инструменты руководства##leader-enabled',c.enabled)
 s.leaderPage=s:choice('Раздел руководства##leader-page',s.leaderPage or'news',{{'news','Госновости'},{'briefing','Инструктажи'}},ui)
 if s.leaderPage=='news'then
  c.tag=s:field('Тег /gnews##leader-tag','field:news:tag',c.tag,256)
  for i=1,3 do c.lines[i]=s:field('Строка '..i..'##leader-line-'..i,'field:news:'..i,c.lines[i],4097,true,70)
   local raw='/gnews '..(c.tag~=''and c.tag..' | 'or'')..c.lines[i];local wire,why=core.encodeWire(raw,callbacks.codec)
   if callbacks.fieldPreview then local expanded,err=callbacks.fieldPreview(raw);wire,why=expanded and core.encodeWire(expanded,callbacks.codec),err;ui.text(expanded and('Предпросмотр: '..expanded)or tostring(err))end
   ui.text(wire and('Команда после подстановки: '..#wire..' / '..c.channel_limit..' байт CP1251')or tostring(why or'Проверка кодировки при предпросмотре'))
  end
  c.source=s:field('Где проверены формат, доступ и лимит##leader-source','field:leader:source',c.source,1025,true,64)
  c.verified=s:check('Я проверил /gnews Тег | текст и свои полномочия##leader-verified',c.verified)
  number(s,ui,c,'channel_limit','Проверенный предел полной команды, байт',16,127)
  number(s,ui,c,'delay_ms','Пауза между объявлениями, мс',1000,10000)
  ui.text('Одна или три строки. Сначала проверяются все строки, затем ДА / НЕТ. Уже отправленные строки после отмены не повторяются. Синтаксис, звание и cooldown PA сам не подтверждает.')
  if s:button('Предпросмотр /gnews##leader-preview',ui)then if save(s,callbacks,d)then offer(s,callbacks,'gnews')end end
  s.leaderPresetName=s:field('Название набора##leader-preset-name','field:preset:name',s.leaderPresetName or'',161)
  if s:button('Сохранить объявление в набор##leader-save-preset',ui)then
   if s.leaderPresetName==''or #c.presets>=32 then s:notify('Введите название; не больше 32 наборов.','field',false)
   else c.presets[#c.presets+1]={name=s.leaderPresetName,tag=c.tag,lines=model.copy(c.lines)};save(s,callbacks,d)end
  end
  for i,p in ipairs(c.presets)do
   if s:button(p.name..'##leader-preset-'..i,ui)then c.tag=p.tag;c.lines=model.copy(p.lines);s:clearPreferenceCache('field:news:')end
   if s:button('Дублировать набор##leader-clone-'..i,ui)then if #c.presets<32 then local clone=model.copy(p);clone.name=p.name..' · копия';c.presets[#c.presets+1]=clone;save(s,callbacks,d);return end end
   if s:button('Удалить набор##leader-remove-'..i,ui)then table.remove(c.presets,i);save(s,callbacks,d);break end
  end
 else
  ui.text('Личные редактируемые конспекты. Действующие исходники и полный Мануал находятся в РЕЕСТРЕ. Передаётся только выбранная строка после ДА.')
  local query=s:field('Поиск инструктажей##briefing-search','field:briefing:search','',160)
  if s:button('Добавить инструктаж##briefing-add',ui)and #c.briefings<32 then c.briefings[#c.briefings+1]={name='Новый инструктаж',tag='',department='EPD',lines={'Текст инструктажа.'},favorite=false};save(s,callbacks,d)end
  s.briefingDepartment=s:choice('Ведомство в списке##briefing-filter',s.briefingDepartment or'all',{{'all','Все'},{'EPD','EPD'},{'FBI','FBI'},{'Alcatraz','Alcatraz'}},ui)
  local order={};for i in ipairs(c.briefings)do order[#order+1]=i end
  table.sort(order,function(a,b)local x,y=c.briefings[a],c.briefings[b];if x.favorite~=y.favorite then return x.favorite end;return a<b end)
  for _,i in ipairs(order)do local r=c.briefings[i];if(s.briefingDepartment=='all'or r.department==s.briefingDepartment)and(query==''or model.casefold(r.name):find(model.casefold(query),1,true))then
   if s:button(r.name..'##briefing-select-'..i,ui)then s.briefingIndex=i;s.briefingLine=1 end
  end end
  local r=c.briefings[s.briefingIndex or 0]
  if r then
   ui.text(require('pa26_field_briefings').source(r))
   ui.text('Передаётся одна выбранная строка. Автоматического чтения всего инструктажа нет.')
   r.name=s:field('Название##briefing-name','field:briefing:name:'..s.briefingIndex,r.name,161)
   r.department=s:choice('Ведомство##briefing-dept',r.department,{{'EPD','EPD'},{'FBI','FBI'},{'Alcatraz','Alcatraz'}},ui)
   r.favorite=s:check('Избранный инструктаж##briefing-star',r.favorite)
   local body=s:field('Строки инструктажа##briefing-body','field:briefing:body:'..s.briefingIndex,table.concat(r.lines,'\n'),8193,true,160)
   r.lines={};for line in(body..'\n'):gmatch('(.-)\n')do if line~=''then r.lines[#r.lines+1]=line end end
   local count=#r.lines;s.briefingLine=math.min(math.max(1,s.briefingLine or 1),math.max(1,count))
   local choices={};for i=1,count do choices[#choices+1]={i,'Строка '..i..' / '..count}end
   if count>0 then s.briefingLine=s:choice('Следующая строка##briefing-next',s.briefingLine,choices,ui);ui.text(r.lines[s.briefingLine])end
   if s:button('Предпросмотр выбранной строки##briefing-preview',ui)then if save(s,callbacks,d)then offer(s,callbacks,'briefing',{index=s.briefingIndex,line=s.briefingLine})end end
   if s:button('Удалить инструктаж##briefing-delete',ui)then table.remove(c.briefings,s.briefingIndex);s.briefingIndex=nil;save(s,callbacks,d)end
  end
 end
end
return M

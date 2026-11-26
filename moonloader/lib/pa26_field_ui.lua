-- Existing Studio widgets, persistence and acknowledgment windows; no native work.
local core=require 'pa26_core';local model=require 'pa26_bindings';local menu=require 'pa26_menu';local M={}
local tabs={{'coordinates','Координаты (OOC)'},{'pinned','Памятка поверх игры'},{'leadership','Руководство'}}
local function offer(s,callbacks,kind,arg)
 local function prepare()
  local p,why=callbacks.fieldOffer(kind,arg)
  if p then s.assistConfirm={kind='field',proposal=p}else s:notify(why,'field',false)end
  return true
 end
 if not callbacks.afterUi then return prepare()end
 local ok,why=callbacks.afterUi(prepare)
 if not ok then s:notify(why,'field',false)end
end
local function number(s,ui,d,key,label,min,max)
 ui.text(label);s.imgui.PushItemWidth(-1);local n=s.imgui.new.float(d[key])
 if s.imgui.SliderFloat('##field-'..key,n,min,max)then d[key]=n[0]end;s.imgui.PopItemWidth()
end
local function intNumber(s,ui,d,key,label,min,max)
 local im=s.imgui
 local n=im.new.int(math.max(min,math.min(max,math.floor(d[key]+.5))))
 ui.text(label);im.PushItemWidth(-1)
 im.SliderInt('##field-'..key,n,min,max)
 im.PopItemWidth()
 d[key]=math.max(min,math.min(max,n[0]))
end
local function save(s,callbacks,d,quiet)
 local candidate=model.copy(s.lib);candidate.field=d
 local ok,why=callbacks.save(candidate)
 if not ok or not quiet then s:notify(ok and'Настройки инструментов сохранены.'or why,'field',false,ok and'info'or'warning')end
 if ok then
  s.fieldDraft=nil
  if s.autosaves then s.autosaves.field=nil end
 end
 return ok
end
function M.settings(s,ui,data,callbacks)
 local d=s.fieldDraft or model.copy(s.lib.field);s.fieldDraft=d;s.currentNoticeScope='field';s.preferenceContext=true
 s:settingsHeading(ui,'Инструменты службы')
 d.enabled=s:check('Включить инструменты службы · общий выключатель##field-master',d.enabled)
 ui.text('Выключение останавливает наблюдение, временные метки и подсказки этих инструментов. Остальные функции PA сохраняются.')
 if s.fieldPage=='navigation'or s.fieldPage=='cruiser'then s.fieldPage='coordinates'end
 s.fieldPage=menu.choiceControl(s.imgui,ui,'##field-pages','',s.fieldPage or'coordinates',tabs,s,{buttons=true,font=s.buttonFont})
 local page=s.fieldPage;local c=d[page]
 if page=='coordinates'then
  local mark=d.navigation
  c.enabled=s:check('Разрешить координаты OOC##coord-enabled',c.enabled)
  c.observe=s:check('Предлагать полученные OOC-координаты##coord-observe',c.observe)
  mark.hud=s:check('Расстояние до метки в HUD##coord-hud',mark.hud)
  mark.radar=s:check('Метка на радаре##coord-radar',mark.radar)
  mark.pause_map=s:check('Метка на карте Esc##coord-map',mark.pause_map)
  number(s,ui,mark,'opacity','Непрозрачность метки',.1,1)
  intNumber(s,ui,mark,'observe_ms','Обновление расстояния в HUD, мс',200,2000)
  c.arrival_clear=s:check('Убирать временную метку после прибытия##coord-arrival',c.arrival_clear)
  intNumber(s,ui,mark,'arrival','Радиус прибытия к временной метке, м',1,100)
  c.channel=s:choice('Канал OOC##coord-channel',c.channel,{{'/rn','/rn · подразделение'},{'/fn','/fn · организация'},{'/ln','/ln · требует проверки'},{'/sms','/sms · требует проверки'}},ui)
  c.phone=s:field('Телефон получателя /sms##coord-phone','field:phone',c.phone,24)
  c.ln_verified=s:check('Я проверил формат и доступ к /ln на сервере##coord-ln',c.ln_verified)
  c.sms_verified=s:check('Я проверил /sms номер текст на сервере##coord-sms',c.sms_verified)
  intNumber(s,ui,c,'ttl_ms','Срок временной метки, мс',1000,1800000)
  intNumber(s,ui,c,'offer_ms','Время предложения, мс',1000,60000)
  ui.text('Формат: Мои координаты: X Y Z (Район, квадрат H-18). Предпросмотр показывает полную команду; длинный пакет не обрезается. Непроверенные /ln и /sms отключены по умолчанию.')
  require('pa26_assist_ui').shortcut(s,ui,callbacks,'field','share_shortcut','Открыть предпросмотр координат')
  if s:button('Предпросмотр передачи координат##coord-preview',ui)then if save(s,callbacks,d,true)then offer(s,callbacks,'share')end end
  local v=data.field or{}
  if v.target then
   ui.text(v.distance and string.format('Временная метка · %.0f м по прямой',v.distance)or'Временная OOC-метка')
   if s:button('Убрать OOC-метку##field-mark-clear',ui)then callbacks.fieldClear()end
  end
  local text=s:field('Полученные X Y Z##field-paste','field:paste','',160)
  if s:button('Показать на карте · с подтверждением##field-paste-map',ui)then
   local ok,why=callbacks.fieldPaste(text);if not ok then s:notify(why,'field',false)end
  end
  ui.text('Координаты относятся к OOC. Место персонажа устанавливается в RP отдельно.')
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
  intNumber(s,ui,c,'channel_limit','Проверенный предел полной команды, байт',16,127)
  intNumber(s,ui,c,'delay_ms','Пауза между объявлениями, мс',1000,10000)
  ui.text('Одна или три строки. Сначала проверяются все строки, затем ДА / НЕТ. Уже отправленные строки после отмены не повторяются. Синтаксис, звание и cooldown PA сам не подтверждает.')
  if s:button('Предпросмотр /gnews##leader-preview',ui)then if save(s,callbacks,d,true)then offer(s,callbacks,'gnews')end end
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
  local completed=data.field and data.field.lastBriefingCompleted
  if completed and s.briefingCompletedToken~=completed.token then
   s.briefingCompletedToken=completed.token
   if s.briefingIndex==completed.index and s.briefingLine==completed.line and c.briefings[completed.index]then
    s.briefingLine=math.min(#c.briefings[completed.index].lines,completed.line+1)
   end
  end
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
   local body,changed=s:field('Строки инструктажа##briefing-body','field:briefing:body:'..s.briefingIndex,table.concat(r.lines,'\n'),8193,true,160)
   if body:find('%S')then
    if changed then
     local lines={}
     for line in(body..'\n'):gmatch('(.-)\n')do
      if line:find('%S')then lines[#lines+1]=line:gsub('\r$','')end
     end
     r.lines=lines
    end
    local count=#r.lines
    if count>0 then
     s.briefingLine=math.min(math.max(1,s.briefingLine or 1),count)
     local choices={};for i=1,count do choices[#choices+1]={i,'Строка '..i..' / '..count}end
     s.briefingLine=s:choice('Следующая строка##briefing-next',s.briefingLine,choices,ui)
     ui.text(r.lines[s.briefingLine])
     if s:button('Предпросмотр выбранной строки##briefing-preview',ui)and save(s,callbacks,d,true)then
      offer(s,callbacks,'briefing',{index=s.briefingIndex,line=s.briefingLine})
     end
    end
   else
    ui.text('Добавьте хотя бы одну непустую строку, чтобы сохранить изменения.')
   end
   if s:button('Удалить инструктаж##briefing-delete',ui)then
    table.remove(c.briefings,s.briefingIndex);s.briefingIndex=nil
    s:clearPreferenceCache('field:briefing:body:');s:clearPreferenceCache('field:briefing:name:')
    save(s,callbacks,d)
   end
  end
 end
end
return M

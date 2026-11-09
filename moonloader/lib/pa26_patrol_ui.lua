-- Patrol form reuses the studio's auto-save, wrapping, keys and central modal.
local model=require 'pa26_bindings'
local settings=require 'pa26_patrol_settings'
local M={}
function M.offer(studio,action,callbacks)
    local proposal,err=callbacks.patrolOffer(action)
    if proposal then studio.patrolConfirm=proposal else studio:notify(err,'patrol_session',false)end
end
local groups=require 'pa26_ui_groups'
local function begin(studio)
 studio.currentNoticeScope='patrol_session';studio.preferenceContext=true
 return studio.patrolSessionDraft or model.copy(studio.lib.patrol_session)
end
local function save(studio,ui,draft)
 studio.patrolSessionDraft=draft
 studio:autoSettings('patrol_session',{'patrol_session'},draft,'patrolSessionDraft')
 studio:autosaveHint(ui,'patrol_session');studio:drawNotice(ui)
end
function M.drawSessionSettings(studio,ui,data,callbacks)
 local im=studio.imgui;local draft=begin(studio);local v,edit
 studio:settingsHeading(ui,'Патруль · настройки и тексты')
 if studio:button('Открыть патруль и смену##session-workspace',ui)then callbacks.openPatrol()end
    for _,row in ipairs({{'hud','Показывать патруль в HUD'},
        {'restore_offer','Предлагать восстановление после перезапуска PA'},{'auto_resume_reload','Продолжать патруль после быстрой перезагрузки PA в той же игре'},{'pause_on_crew_change','Пауза при выходе или замене ID напарника'},
        {'count_map_time','Считать активный патруль на карте Esc'},{'confirmation','Подтверждать каждый периодический доклад'}})do
        local v,edit=studio:check(row[2]..'##session-'..row[1],draft[row[1]]);if edit then draft[row[1]]=v end
    end
    for _,r in ipairs({{'interrupt_grace_ms','Подтверждать смену сервера или персонажа, с##session-grace'},{'reload_grace_ms','Перерыв для автовосстановления PA, с##session-reload-grace'}})do
        local n=im.new.int(draft[r[1]]/1000);if im.InputInt(r[2],n)then draft[r[1]]=n[0]*1000 end
    end
    ui.text('Короткая потеря данных и 0 HP не завершают патруль. Ранение с возможностью реанимации сохраняет сцену; RP и команды ждут восстановления. Автовосстановление требует тот же процесс GTA, сервер и персонажа; ручная пауза сохраняется. Старые доклады не повторяются. Отсчёт при F6 настраивается в «Предупреждения и свои автодоклады».')
    for _,r in ipairs({{'downed_hp','Порог ранения: блокировать действия при HP не выше##session-downed-hp',1},{'respawn_distance','Перемещение для проверки респавна, м##session-respawn-distance',1},{'respawn_position_tolerance','Допуск совпадения с точкой спавна, м##session-respawn-tolerance',1},{'respawn_evidence_ms','Срок связи событий респавна, с##session-respawn-evidence',1000}})do
        local n=im.new.int(draft[r[1]]/r[3]);if im.InputInt(r[2],n)then draft[r[1]]=n[0]*r[3]end
    end
    ui.text('Ни здоровье, ни дверь больницы, ни запрос спавна сами по себе не означают смерть. Нужны новая наблюдаемая позиция и связанные события спавна/телепорта от сервера. Неизвестный сценарий сохраняет патруль; его можно завершить вручную.')
    ui.text('Включённый сеанс заменяет старый таймер полиции/тюрьмы. До начала сеанса периодических докладов нет. Все автодоклады проходят предупреждение и отмену.')
    ui.text('Если рацию ведёт напарник, снимите флажок «Рацию в экипаже веду я»: начало, продолжение, смена состава и завершение сохраняются локально; периодические доклады PA не отправляются. Ручные SOS и мегафон остаются отдельными действиями.')
    local seconds=im.new.int(draft.interval_ms/1000)
    if im.InputInt('Интервал докладов, с##session-interval',seconds)then draft.interval_ms=seconds[0]*1000 end
    local gap=im.new.int((draft.map_max_gap_ms or 3600000)/1000)
    if im.InputInt('Наибольший достоверный перерыв карты, с##session-map-gap',gap)then draft.map_max_gap_ms=gap[0]*1000 end
    ui.text('На карте Esc время активного патруля идёт, но PA ничего не отправляет. После возврата — не больше одного текущего доклада с обычным подтверждением. Ручная пауза патруля и потеря фокуса время не учитывают. Слишком большой разрыв часов пропускается.')
    local distance=im.new.int(draft.bind_distance)
    if im.InputInt('Проверка напарника рядом, м##session-distance',distance)then draft.bind_distance=distance[0]end
    studio:settingsHeading(ui,'Реплики и предпросмотр')
    ui.text('Грамматический род: {gender:передал|передала}. Без /r, /f или /d: канал добавляется отдельно. Переменные: {officer}, {callsign}, {crew}, {crew_count}, {crew_roles}, {crew_callsigns}, {unit}, {station}, {vehicle}, {sector}, {post}, {area}, {location}, {map_square}, {direction}, {duration}, {patrol_id}; также теги и поля профиля. Длинный итог может не поместиться в лимит чата — предпросмотр это проверяет.')
    if studio:button('Вставить пример докладов SFPS##patrol-sfps-preset',ui)then
        local stock=settings.defaults();for _,key in ipairs({'start','resume','periodic','finish'})do draft[key..'_template']=stock[key..'_template']end
        for k in pairs(studio.cache)do if k:match('^session:template:')then studio.cache[k]=nil end end
    end
    studio:settingsHeading(ui,'Формы фраз: один / экипаж')
    draft.grammar=draft.grammar or settings.grammarDefaults()
    studio.patrolGrammar=studio:choice('Форма фразы##patrol-grammar',studio.patrolGrammar or'start_solo',settings.grammarRows,ui)
    local grammarKey=studio.patrolGrammar
    draft.grammar[grammarKey]=studio:field('Текст формы##patrol-grammar-text','session:grammar:'..grammarKey,draft.grammar[grammarKey],1024,true,64)
    ui.text('В стандартных докладах {patrol_start}, {patrol_resume}, {patrol_finish}, {patrol_moving}, {patrol_available} выбирают единственное или множественное число. В машине учитываются распознанные напарники в салоне; пешком — подтверждённый состав сеанса. {unit_crew_count} — это количество участников юнита.')
    ui.text('Предпросмотр формы: '..require('pa26_core').expandGender(draft.grammar[grammarKey],studio.lib.profile.gender))
    local names={start='Начало патруля',resume='Продолжение патруля',finish='Завершение патруля',crew='Смена экипажа',periodic='Периодический доклад'}
    for _,key in ipairs({'start','resume','finish','crew','periodic'})do
        draft[key..'_template']=studio:field(names[key]..'##session-template-'..key,'session:template:'..key,draft[key..'_template'],2048,true,82)
        local line,err=callbacks.patrolPreview(key,draft)
        ui.text(line and('Предпросмотр: '..line)or('Для предпросмотра: '..tostring(err)))
    end
    studio:settingsHeading(ui,'Быстрый доступ')
    for _,row in ipairs(settings.shortcutNames)do
        ui.text(row[2]..': '..model.shortcutName(draft[row[1]]))
        if studio:button('Назначить##session-key-'..row[1],ui)then callbacks.capture({kind='feature',group='patrol_session',field=row[1]})end
        if draft[row[1]].key~=0 and studio:button('Снять назначение##session-clear-'..row[1],ui)then draft[row[1]]={key=0,ctrl=false,alt=false,shift=false}end
    end
 save(studio,ui,draft)
end
function M.draw(studio,ui,data,callbacks,host)
 local im=studio.imgui;local draft=begin(studio)
 local view=type(data.patrolSession)=='table'and data.patrolSession or {};local a=view.active
 studio:settingsHeading(ui,'Смена')
 ui.text(a and ((a.status=='paused'and 'Пауза'or 'На службе')..' · '..tostring(view.duration)..' · № '..a.id)or 'Патруль не начат')
 if a then
  ui.text('Экипаж: '..(view.crew or 'не определён')..' · Доклад: '..tostring(a.report_status))
  if a.status=='paused'then ui.text(a.reason)end
  if view.pending then ui.text('Подтверждённый доклад ожидает свободную очередь.')end
 end
 local actions={}
 if a then
  actions={{a.status=='paused'and'resume'or'pause',a.status=='paused'and 'Продолжить патруль'or 'Пауза патруля'},
   {'crew','Применить новый состав##patrol-crew'},{'finish','Завершить с докладом##patrol-finish'},{'discard','Завершить без доклада##patrol-discard'}}
 elseif view.recoverable then
  ui.text('Сохранён патруль № '..view.recoverable.id..' · '..settings.duration(view.recoverable.elapsed_ms))
  ui.text('Перед восстановлением проверьте сервер, персонажа и экипаж.')
  if draft.restore_offer then actions[#actions+1]={'restore','Восстановить патруль##patrol-restore'}end
  actions[#actions+1]={'discard','Закрыть сохранённый патруль##patrol-discard'}
 else actions={{'start','Начать патруль##patrol-start'}}end
 groups.buttons(studio,ui,actions,function(action)if action=='pause'then callbacks.patrolPause()else M.offer(studio,action,callbacks)end end)
 if studio:button('Трафик-стоп и преследование##patrol-vehicle',ui)then
  if callbacks.patrolTraffic then callbacks.patrolTraffic(host)elseif host=='assist'then studio.assistPage='traffic'else studio.partnerPage='vehicle'end
 end
 studio:observeStatus('patrol_session',view.message,'patrol_session')
 studio:passiveWarning('patrol-save',view.saveError and('Не удалось сохранить сеанс: '..view.saveError),'patrol_session')
 im.Separator();studio:settingsHeading(ui,'Юнит и связь')
 for _,row in ipairs({{'enabled','Включить сеансы патруля'},{'periodic','Периодические доклады в сеансе'},{'reporter_self','Рацию в экипаже веду я'}})do
  draft[row[1]]=studio:check(row[2]..'##session-'..row[1],draft[row[1]])
 end
 draft.mode=studio:choice('Вид службы##session-mode',draft.mode,{{'police','Автомобильный патруль'},{'foot','Пеший патруль'},{'prison','Охрана тюрьмы'}},ui)
 for _,row in ipairs({{'unit','Юнит вручную · пусто = автоматически'},{'station','Станция / подразделение'}})do
  draft[row[1]]=studio:field(row[2]..'##session-'..row[1],'session:'..row[1],draft[row[1]],512)
 end
 local number=im.new.int(draft.unit_number or 1)
 if im.InputInt('Номер автоматического юнита##session-unit-number',number)then draft.unit_number=number[0]end
 draft.channel=studio:choice('Канал сеанса##session-channel',draft.channel,require('pa26_server_commands').radioChoices,ui)
 ui.text('Автоюнит: LINCOLN — один сотрудник, ADAM — с распознанными напарниками. Гражданские пассажиры в состав не входят. Назначенный диспетчером юнит укажите вручную.')
 if studio:button((studio.patrolUnitExtra and 'Скрыть дополнительные поля'or'Дополнительные поля юнита')..'##session-unit-extra',ui)then studio.patrolUnitExtra=not studio.patrolUnitExtra end
 if studio.patrolUnitExtra then
  for _,row in ipairs({{'vehicle','Транспорт · вручную'},{'sector','Полицейский сектор · вручную'},{'post','Пост тюрьмы'}})do
   draft[row[1]]=studio:field(row[2]..'##session-'..row[1],'session:'..row[1],draft[row[1]],512)
  end
  ui.text('{sector} — ваш сектор, {map_square} — квадрат карты; район не подменяет официальный сектор.')
 end
 if studio:button('Шаблоны и дополнительные настройки →##session-settings',ui)then
  if callbacks.openSettings then callbacks.openSettings('radio','session')else studio.radioPage='session'end
 end
 im.Separator();studio:settingsHeading(ui,'Экипаж')
 if studio:button('Управлять контактами##session-contacts',ui)then
  if callbacks.openPatrolContacts then callbacks.openPatrolContacts()else studio.partnerPage='contacts'end
 end
    studio:settingsHeading(ui,'Состав следующего патруля')
    ui.text('Отметьте контакты и укажите IC-имена. Выбор сохраняется. Текущий экипаж меняется только после «Применить новый состав» и подтверждения. В начале/при продолжении выбранные напарники должны быть видны рядом.')
    studio.patrolCrewQuery=studio:field('Поиск напарника##session-crew-search','session:crew-search',studio.patrolCrewQuery or '',256)
    local query=model.casefold(studio.patrolCrewQuery)
    if #studio.lib.partners==0 then ui.text('Сначала добавьте контакт на вкладке «Контакты». Для одиночного патруля оставьте состав пустым.')end
    local known={}
    for _,p in ipairs(studio.lib.partners)do
        known[p.id]=true
        local row,index;for i,r in ipairs(draft.crew)do if r.contact_id==p.id then row=r;index=i;break end end
        if query==''or model.casefold(p.nickname..' '..p.callsign):find(query,1,true)then
            local checked,changed=studio:check(p.nickname..' · '..p.callsign..'##session-crew-'..p.id,row~=nil)
            if changed then
                if checked then
                    if #draft.crew<8 then row={contact_id=p.id,ic_name='',role='Напарник'};draft.crew[#draft.crew+1]=row
                    else studio:notify('Можно выбрать до 8 напарников.','patrol_session',false)end
                else table.remove(draft.crew,index);row=nil end
            end
            if row then
                row.ic_name=studio:field('IC-имя##session-name-'..p.id,'session:name:'..p.id,row.ic_name,512)
                row.role=studio:field('Роль в экипаже##session-role-'..p.id,'session:role:'..p.id,row.role,256)
            end
        end
    end
    for i=#draft.crew,1,-1 do local row=draft.crew[i];if not known[row.contact_id]then
        ui.text('Контакт № '..row.contact_id..' удалён. Уберите его из будущего состава.')
        if studio:button('Убрать удалённый контакт##session-orphan-'..row.contact_id,ui)then table.remove(draft.crew,i)end
    end end

 if host~='assist'then
  im.Separator();require('pa26_copilot_ui').quick(studio,ui,callbacks)
  if studio:button('Спецвызовы в F4##patrol-dispatch',ui)then callbacks.openAssist('dispatch')end
 end
 save(studio,ui,draft)
 if type(view.history)=='table'and #view.history>0 then
  studio:settingsHeading(ui,'Последние патрули')
  for i=#view.history,math.max(1,#view.history-4),-1 do local r=view.history[i]
   ui.text('№ '..r.id..' · '..settings.duration(r.elapsed_ms)..' · '..r.reason..(r.demo and ' · демо'or ''))
  end
 end
end
return M

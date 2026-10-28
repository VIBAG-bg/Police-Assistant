-- Patrol form reuses the studio's auto-save, wrapping, keys and central modal.
local model=require 'pa26_bindings'
local settings=require 'pa26_patrol_settings'
local M={}
function M.offer(studio,action,callbacks)
    local proposal,err=callbacks.patrolOffer(action)
    if proposal then studio.patrolConfirm=proposal else studio:notify(err,'patrol_session',false)end
end
function M.draw(studio,ui,data,callbacks)
    local im=studio.imgui;studio.currentNoticeScope='patrol_session';studio.preferenceContext=true
    local draft=studio.patrolSessionDraft or model.copy(studio.lib.patrol_session)
    local view=data.patrolSession or {};local a=view.active
    studio:settingsHeading(ui,'Сеанс патруля')
    if data.radioState then ui.text('Место: '..(require('pa26_map_grid').location(data.radioState)or 'не определено'))end
    if studio:button('Трафик-стоп и преследование##patrol-vehicle',ui)then studio.partnerPage='vehicle'end
    ui.text(a and('№ '..a.id..' · '..(a.status=='paused'and 'Пауза'or 'На службе')..' · '..view.duration)or 'Патруль ещё не начат')
    if a then
        ui.text('Доклад: '..a.report_status);ui.text('Экипаж: '..(view.crew or ''))
        if a.status=='paused'then ui.text(a.reason)end
        if view.pending then ui.text('Подтверждённое действие ожидает свободную очередь.')end
        if studio:button(a.status=='paused'and 'Продолжить патруль'or 'Пауза патруля',ui)then
            if a.status=='paused'then M.offer(studio,'resume',callbacks)else callbacks.patrolPause()end
        end
        if studio:button('Применить новый состав##patrol-crew',ui)then M.offer(studio,'crew',callbacks)end
        if studio:button('Завершить с докладом##patrol-finish',ui)then M.offer(studio,'finish',callbacks)end
        if studio:button('Завершить без доклада##patrol-discard',ui)then M.offer(studio,'discard',callbacks)end
    elseif view.recoverable then
        ui.text('Сохранён патруль № '..view.recoverable.id..' · '..settings.duration(view.recoverable.elapsed_ms))
        ui.text('Отсчёт и отправки остановлены. Продолжение требует проверки сервера, персонажа и напарников.')
        if draft.restore_offer and studio:button('Восстановить патруль##patrol-restore',ui)then M.offer(studio,'restore',callbacks)end
        if studio:button('Закрыть сохранённый патруль##patrol-discard',ui)then M.offer(studio,'discard',callbacks)end
    elseif studio:button('Начать патруль##patrol-start',ui)then M.offer(studio,'start',callbacks)end
    require('pa26_copilot_ui').quick(studio,ui,callbacks)
    studio:observeStatus('patrol_session',view.message,'patrol_session')
    studio:passiveWarning('patrol-save',view.saveError and('Не удалось сохранить сеанс: '..view.saveError),'patrol_session')
    im.Separator()
    for _,row in ipairs({{'enabled','Включить сеансы патруля'},{'hud','Показывать патруль в HUD'},
        {'restore_offer','Предлагать восстановление после перезапуска PA'},{'pause_on_crew_change','Пауза при выходе или замене ID напарника'},
        {'periodic','Периодические доклады в сеансе'},{'reporter_self','Рацию в экипаже веду я'},{'confirmation','Подтверждать каждый периодический доклад'}})do
        local v,edit=studio:check(row[2]..'##session-'..row[1],draft[row[1]]);if edit then draft[row[1]]=v end
    end
    ui.text('Включённый сеанс заменяет старый таймер полиции/тюрьмы. До начала сеанса периодических докладов нет. Все автодоклады проходят предупреждение и отмену.')
    ui.text('Если рацию ведёт напарник, снимите флажок «Рацию в экипаже веду я»: начало, продолжение, смена состава и завершение сохраняются локально; периодические доклады PA не отправляются. Ручные SOS и мегафон остаются отдельными действиями.')
    local v,edit=studio:choice('Вид службы##session-mode',draft.mode,{{'police','Автомобильный патруль'},{'foot','Пеший патруль'},{'prison','Охрана тюрьмы'}},ui)
    if edit then draft.mode=v end
    for _,row in ipairs({{'station','Станция / подразделение'},{'unit','Юнит / маркировка'},{'vehicle','Транспорт · вручную'},
        {'sector','Полицейский сектор · вручную'},{'post','Пост тюрьмы'}})do
        draft[row[1]]=studio:field(row[2]..'##session-'..row[1],'session:'..row[1],draft[row[1]],512)
    end
    ui.text('Квадрат добавляется к {area} по настройкам карты. {location} явно подставляет район и доступный квадрат; {sector} — отдельный сектор вашего патруля.')
    ui.text('IC-имя офицера и позывной берутся из профиля. Район GTA не считается официальным полицейским сектором. Поля и формулировки проверяет игрок.')
    local seconds=im.new.int(draft.interval_ms/1000)
    if im.InputInt('Интервал докладов, с##session-interval',seconds)then draft.interval_ms=seconds[0]*1000 end
    local distance=im.new.int(draft.bind_distance)
    if im.InputInt('Проверка напарника рядом, м##session-distance',distance)then draft.bind_distance=distance[0]end
    v,edit=studio:choice('Канал сеанса##session-channel',draft.channel,require('pa26_server_commands').radioChoices,ui)
    if edit then draft.channel=v end
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
    studio:settingsHeading(ui,'Реплики и предпросмотр')
    ui.text('Грамматический род: {gender:передал|передала}. Без /r, /f или /d: канал добавляется отдельно. Переменные: {officer}, {callsign}, {crew}, {crew_count}, {crew_roles}, {crew_callsigns}, {unit}, {station}, {vehicle}, {sector}, {post}, {area}, {location}, {map_square}, {direction}, {duration}, {patrol_id}; также теги и поля профиля. Длинный итог может не поместиться в лимит чата — предпросмотр это проверяет.')
    if studio:button('Вставить пример докладов SFPS##patrol-sfps-preset',ui)then
        draft.start_template='{local_tag}{unit}, начинаем патрулирование по городу {city}. Экипаж: {crew}. Район: {area}. Далее доступны.'
        draft.resume_template='{local_tag}{unit}, продолжаем патрулирование по городу {city}. Экипаж: {crew}. Район: {area}. Направление: {direction}.'
        draft.periodic_template=draft.resume_template
        draft.finish_template='{local_tag}{unit}, патрулирование завершено. Экипаж: {crew}. Время на службе: {duration}.'
        for k in pairs(studio.cache)do if k:match('^session:template:')then studio.cache[k]=nil end end
    end
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
    studio.patrolSessionDraft=draft
    studio:autoSettings('patrol_session',{'patrol_session'},draft,'patrolSessionDraft');studio:autosaveHint(ui,'patrol_session');studio:drawNotice(ui)
    if #view.history>0 then
        studio:settingsHeading(ui,'Последние патрули')
        for i=#view.history,math.max(1,#view.history-4),-1 do local r=view.history[i]
            ui.text('№ '..r.id..' · '..settings.duration(r.elapsed_ms)..' · '..r.reason..(r.demo and ' · демо'or ''))
        end
    end
end
return M

local model=require 'pa26_bindings'
local prefs=require 'pa26_patrol_event_settings'
local M={}
function M.summary(studio,ui,data,callbacks)
    local view=data.patrolEvents;if not view then return end
    studio:settingsHeading(ui,'События патруля · за всё время')
    ui.text('Отдельный учёт: подтверждённые вручную факты / переданные клиенту доклады. Эти значения не складываются со счётчиками биндов выше.')
    for _,row in ipairs(prefs.catalog)do
        local id=row[1]
        if view.facts[id]or view.reports[id]then ui.text(studio.lib.patrol_events.events[id].name..': '..(view.facts[id]or 0)..' / '..(view.reports[id]or 0))end
    end
    if studio:button('Открыть журнал событий патруля##stats-patrol-events',ui)then callbacks.openPatrolEvents();studio.patrolEventPage='history'end
end
function M.open(studio,kind,attempt,callbacks)
    local form,err=callbacks.patrolEventForm(kind,attempt)
    if form then
        for k in pairs(studio.cache)do if k:match('^patrol%-event%-form:')then studio.cache[k]=nil end end
        studio.patrolEventForm=form
    else studio:notify(err,'patrol_events',false)end
end
function M.draw(studio,ui,data,callbacks)
    local im=studio.imgui;studio.currentNoticeScope='patrol_events';studio.preferenceContext=true
    local cfg=studio.patrolEventDraft or model.copy(studio.lib.patrol_events);local view=data.patrolEvents or {attempts={},events={},facts={},reports={}}
    studio:settingsHeading(ui,'События патруля')
    ui.text('PA отдельно считает записанные вами события и отправленные доклады. Нажатие команды само по себе не подтверждает её результат.')
    studio.patrolEventPage=studio:choice('События##patrol-event-page',studio.patrolEventPage or 'work',
        {{'work','Записать событие'},{'history','Журнал и счётчики'},{'settings','Настройки'}},ui)
    if studio.patrolEventPage=='work'then
        for i=#view.attempts,math.max(1,#view.attempts-5),-1 do local a=view.attempts[i]
            local row=cfg.events[a.kind]
            ui.text('Проверьте результат: '..a.line..' · '..a.origin)
            if studio:button(row.name..' · проверить##patrol-attempt-'..a.id,ui)then M.open(studio,a.kind,a.id,callbacks)end
        end
        local choices={};for _,row in ipairs(prefs.catalog)do if cfg.events[row[1]].enabled then choices[#choices+1]={row[1],cfg.events[row[1]].name}end end
        local picked,changed=studio:choice('Вид события##patrol-event-kind',studio.patrolEventKind or 'pursuit_vehicle',choices,ui)
        if changed then studio.patrolEventKind=picked end
        if studio:button('Подготовить событие##patrol-event-new',ui)then M.open(studio,picked,nil,callbacks)end
        local form=studio.patrolEventForm
        if form then
            im.Separator();studio:settingsHeading(ui,cfg.events[form.kind].name)
            if form.kind=='force_used'then ui.text('Запишите, какая сила применялась, по какой причине и при каких обстоятельствах. Выстрел или потеря здоровья не создают запись автоматически. Рапорт и медицинскую помощь нужно выполнить отдельно.')end
            if form.target then ui.text('Техническая цель: '..form.target.name..' ['..form.target.id..']')else ui.text('Человек не выбран. Для этого события может потребоваться цель.')end
            if not form.target and data.target and callbacks.patrolEventBindTarget then
                ui.text('PA не определил участника команды. Выбирайте человека для события только в том случае, если он действительно участвовал.')
                if studio:button('Связать с '..data.target.name..' ['..data.target.id..']##patrol-event-bind-target',ui)then
                    local ok,err=callbacks.patrolEventBindTarget(form);if not ok then studio:notify(err,'patrol_events',false)end
                end
            end
            if form.target_manual then ui.text('Человек привязан вами вручную после команды.')end
            ui.text('Введите имя, известное вашему персонажу, или приметы человека. Игровой ник и SA:MP ID не заменяют установленную личность. Если выбран другой человек, заполните новую форму.')
            if form.target and callbacks.identitySubject then
                local subject,source=callbacks.identitySubject(form.target,form.target_stamp)
                if subject then
                    ui.text(source)
                    if studio:button('Подставить известное имя / приметы##patrol-event-identity',ui)then
                        form.subject=subject;studio:setBuffer('patrol-event-form:'..form.id..':subject',subject,1024)
                    end
                end
                if callbacks.openIdentity and studio:button('Открыть IC-сведения о человеке##patrol-event-identity-open',ui)then callbacks.openIdentity()end
            end
            for _,row in ipairs({{'subject','Человек · IC-имя или известные приметы'},{'basis','Основание / статья · вручную'},
                {'destination','Кому / куда передан задержанный'},{'details','Дополнительные сведения'}})do
                form[row[1]]=studio:field(row[2]..'##patrol-event-'..row[1],'patrol-event-form:'..form.id..':'..row[1],form[row[1]],1024)
            end
            local checked,edit=studio:check('Подтверждаю, что событие действительно произошло##patrol-event-ack',form.acknowledged)
            if edit then form.acknowledged=checked end
            ui.text('Вы подтверждаете событие вручную по тому, что произошло в игре. В деморежиме реальные счётчики не увеличиваются.')
            local preview,err=callbacks.patrolEventPreview(form,cfg)
            ui.text(preview and('Доклад: '..preview)or('Для доклада: '..tostring(err)))
            local function prepare(report)
                local p,why=callbacks.patrolEventOffer(form,report)
                if p then studio.patrolEventConfirm=p else studio:notify(why,'patrol_events',false)end
            end
            if studio:button('Записать и передать доклад##patrol-event-report',ui)then prepare(true)end
            if studio:button('Записать без доклада##patrol-event-local',ui)then prepare(false)end
            if studio:button('Закрыть форму##patrol-event-close',ui)then studio.patrolEventForm=nil end
        end
    elseif studio.patrolEventPage=='history'then
        ui.text('Подтверждено вручную / передано клиенту в рацию. Отправленный доклад не доказывает серверный результат.')
        for _,row in ipairs(prefs.catalog)do ui.text(cfg.events[row[1]].name..': '..(view.facts[row[1]]or 0)..' / '..(view.reports[row[1]]or 0))end
        local labels={['local']='без доклада',pending='ожидает отправки',client='передано клиенту',demo='демо',cancelled='доклад отменён'}
        for i=#view.events,math.max(1,#view.events-19),-1 do local e=view.events[i]
            im.Separator();ui.text('№ '..e.id..' · '..e.date..' · '..e.name..' · патруль '..e.patrol_id)
            ui.text(e.subject..' · подтверждено вручную · '..labels[e.report_status]..(e.demo and ' · демо'or ''))
            if e.attempt~=''then ui.text('Попытка: '..e.attempt)end
            if e.report_line~=''then ui.text('Доклад: '..e.report_line)end
        end
    else
        for _,row in ipairs({{'enabled','Включить события патруля'},{'suggest_commands','Предлагать проверить результат после команды'},
            {'require_patrol','Записывать события только в начатом патруле'},{'remind_clear','После доставки напоминать о проверке IC-розыска'},
            {'toast_enabled','Предлагать проверку команды в уведомлении'}})do
            local checked,edit=studio:check(row[2]..'##patrol-event-setting-'..row[1],cfg[row[1]]);if edit then cfg[row[1]]=checked end
        end
        studio:settingsHeading(ui,'Уведомление после команды',
            'Y или кнопка откроет форму события. Запись и доклад появятся после её заполнения и отдельного подтверждения. N или «Позже» скроет уведомление; сама попытка останется в списке до истечения срока. Экстренная связь и отыгровки оружия выполняются первыми.','patrol-event-toast')
        cfg.toast_mode=studio:choice('Управление уведомлением##patrol-event-toast-mode',cfg.toast_mode,
            {{'confirm','Y / N и кнопки'},{'buttons','Только кнопки'}},ui)
        local toastSeconds=im.new.int(cfg.toast_ms/1000)
        if im.InputInt('Сколько показывать уведомление, с##patrol-event-toast-duration',toastSeconds)then cfg.toast_ms=toastSeconds[0]*1000 end
        ui.text('От 1 до 30 секунд, пока уведомление видно. Открытый чат, важное окно или другое уведомление ставят таймер на паузу. {command} — команда; {event} — событие; {origin} — откуда запущено; {target} — ник или ID участника для вашего удобства, не установленное имя персонажа.')
        for _,row in ipairs({{'toast_title','Заголовок уведомления'},{'toast_template','Вопрос после команды'},{'toast_hint','Пояснение в уведомлении'}})do
            cfg[row[1]]=studio:field(row[2]..'##patrol-event-'..row[1],'patrol-events:'..row[1],cfg[row[1]],4096,true,82)
        end
        ui.text('Предпросмотр: '..prefs.noticePreview(cfg.toast_template))
        for _,row in ipairs({{'attempt_ttl_ms','Сколько хранить неподтверждённую попытку, с'},{'duplicate_ms','Защита от одинакового факта, с'}})do
            local n=im.new.int(cfg[row[1]]/1000);if im.InputInt(row[2]..'##patrol-event-'..row[1],n)then cfg[row[1]]=n[0]*1000 end
        end
        cfg.clear_reminder=studio:field('Напоминание после доставки##patrol-event-reminder','patrol-events:reminder',cfg.clear_reminder,2048,true,82)
        studio:settingsHeading(ui,'Напоминания после подтверждённого события',
            'После отдельной записи факта задержания, доставки или применения силы появляется местное напоминание. Команда и выстрел сами его не создают. Готово / Позже только управляют напоминанием. Новая редакция закона о полиции: ст. 19, 25–26; порядок применения силы — MANUAL 260. Прежние ссылки 28–29, 57–58 относятся к архивной редакции. Напоминание PA не подтверждает выполнение помощи или отчёта.','patrol-followup-info')
        for _,row in ipairs({{'followup_enabled','Показывать напоминания после событий'},{'rights_reminder_enabled','После задержания напоминать о разъяснении прав'},
            {'force_reminder_enabled','После применения силы напоминать о помощи и оформлении'}})do
            local checked,edit=studio:check(row[2]..'##patrol-event-setting-'..row[1],cfg[row[1]]);if edit then cfg[row[1]]=checked end
        end
        cfg.followup_title=studio:field('Заголовок напоминания##patrol-followup-title','patrol-events:followup-title',cfg.followup_title,2048)
        cfg.rights_reminder=studio:field('Напоминание о правах##patrol-followup-rights','patrol-events:followup-rights',cfg.rights_reminder,2048,true,100)
        cfg.force_reminder=studio:field('После силы: помощь и оформление##patrol-followup-force','patrol-events:followup-force',cfg.force_reminder,2048,true,120)
        ui.text('Предпросмотр после применения силы · '..cfg.followup_title..'\n'..cfg.force_reminder..'\nЧеловек: [данные из подтверждённого события]')
        for _,row in ipairs({{'followup_ms','Видимое время напоминания, с'},{'followup_ttl_ms','Общий срок напоминания, с'},{'followup_snooze_ms','Напомнить позже через, с'},{'followup_limit','Максимум ожидающих напоминаний'}})do
            local multiplier=row[1]=='followup_limit'and 1 or 1000
            local n=im.new.int(cfg[row[1]]/multiplier);if im.InputInt(row[2]..'##patrol-event-'..row[1],n)then cfg[row[1]]=n[0]*multiplier end
        end
        ui.text('Показ: 1–60 секунд; срок актуальности: 1–1800 секунд; отложить на: 1–300 секунд; очередь: 1–10 напоминаний. Таймер показа идёт, только пока карточка видна. Смена цели, игровой ситуации или настроек отменяет устаревшие напоминания.')
        ui.text('Предпросмотр · '..cfg.followup_title..'\n'..cfg.rights_reminder..'\nЧеловек: [данные из вашей формы события]')
        ui.text('Клавиша событий: '..model.shortcutName(cfg.open_shortcut))
        if studio:button('Назначить##patrol-events-key',ui)then callbacks.capture({kind='feature',group='patrol_events',field='open_shortcut'})end
        if cfg.open_shortcut.key~=0 and studio:button('Снять назначение##patrol-events-clear',ui)then cfg.open_shortcut={key=0,ctrl=false,alt=false,shift=false}end
        ui.text('У каждого события свои текст и условия. Указанная команда лишь предлагает записать событие вручную. PA не определяет её аргументы и результат. Когда требуется доклад, сверяйтесь с правилами сервера.')
        for _,row in ipairs(prefs.catalog)do
            local id=row[1];local r=cfg.events[id];im.Separator();studio:settingsHeading(ui,r.name)
            for _,flag in ipairs({{'enabled','Доступно'},{'suggest','Предлагать после команды'},{'require_target','Нужен выбранный человек'}})do
                local checked,edit=studio:check(flag[2]..'##patrol-event-'..id..'-'..flag[1],r[flag[1]]);if edit then r[flag[1]]=checked end
            end
            for _,field in ipairs({{'name','Название'},{'command','Имя известной серверной команды · без /'}})do
                r[field[1]]=studio:field(field[2]..'##patrol-event-'..id..'-'..field[1],'patrol-events:'..id..':'..field[1],r[field[1]],512)
            end
            local value,edit=studio:choice('Канал##patrol-event-'..id,r.channel,require('pa26_server_commands').radioChoices,ui)
            if edit then r.channel=value end
            r.template=studio:field('Текст доклада##patrol-event-template-'..id,'patrol-events:'..id..':template',r.template,2048,true,82)
            local form=studio.patrolEventForm and model.copy(studio.patrolEventForm)or {};form.kind=id
            local preview,err=callbacks.patrolEventPreview(form,cfg)
            ui.text(preview and('Предпросмотр: '..preview)or('Для предпросмотра: '..tostring(err)))
        end
        ui.text('Грамматический род: {gender:передал|передала}. Переменные: {subject}, {basis}, {destination}, {details}, {unit}, {crew}, {officer}, {area}, {location}, {map_square}, {duration}, {patrol_id}; также поля и теги профиля. Если имя не установлено, в {subject} впишите известные приметы.')
    end
    studio:observeStatus('patrol_events',view.message,'patrol_events')
    studio:passiveWarning('patrol-event-save',view.saveError and('Журнал не сохранён: '..view.saveError),'patrol_events')
    studio.patrolEventDraft=cfg;studio:autoSettings('patrol_events',{'patrol_events'},cfg,'patrolEventDraft')
    studio:autosaveHint(ui,'patrol_events');studio:drawNotice(ui)
end
return M

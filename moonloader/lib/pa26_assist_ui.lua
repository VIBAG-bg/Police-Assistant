local model=require 'pa26_bindings'
local prefs=require 'pa26_assist_settings'
local vehicles=require 'pa26_vehicle_settings'
local training=require 'pa26_training'
local menu=require 'pa26_menu'
local M={}
local departments={{'all','Все'},{'EPD','EPD'},{'FBI','FBI'},{'Alcatraz','Alcatraz'}}
local function note(s,err)s:notify(err or '',s.currentNoticeScope,false)end
local function saved(s,callbacks,scope)
    s:flushAutosave(callbacks,true)
    if s.autosaves and s.autosaves[scope]then note(s,'Исправьте настройки: последние изменения ещё не сохранены.');return false end
    return true
end
local function number(s,ui,d,k,label,divisor)
    local n=s.imgui.new.int(d[k]/(divisor or 1))
    if s.imgui.InputInt(label,n)then d[k]=n[0]*(divisor or 1)end
end
local function key(s,ui,callbacks,group,field,label)
    ui.text(label..': '..model.shortcutName(s.lib[group][field]))
    if s:button('Назначить##assist-key-'..group..'-'..field,ui)then callbacks.capture({kind='feature',group=group,field=field})end
    if s.lib[group][field].key~=0 and s:button('Убрать##assist-key-clear-'..group..'-'..field,ui)then
        local copy=model.copy(s.lib);copy[group][field]={key=0,ctrl=false,alt=false,shift=false}
        local ok,err=callbacks.save(copy)
        if ok and group=='vehicle'and s.vehicleDraft then s.vehicleDraft[field]=model.copy(copy[group][field])end
        if not ok then note(s,err)end
    end
end
M.shortcut=key
function M.offer(s,callbacks,kind)
    local p,err=callbacks.evidenceOffer(s.evidenceLabel or '')
    if p then s.assistConfirm={kind='evidence',proposal=p}else note(s,err)end
end
function M.megaphone(s,ui,data,callbacks)
    local im=s.imgui;local d=s.vehicleDraft or model.copy(s.lib.vehicle);local v=data.vehicle or {};s.vehicleDraft=d
    s.currentNoticeScope='vehicle';s:settingsHeading(ui,'Мегафон')
    d.megaphone_enabled=s:check('Включить мегафон##megaphone-enabled',d.megaphone_enabled)
    ui.text('Выберите реплику, прочитайте готовый текст и нажмите ДА. Пока вы не подтвердили действие, в чат ничего не отправляется.')
    s.megaphonePage=menu.choiceControl(im,ui,'##megaphone-page','',s.megaphonePage or'phrases',
        {{'phrases','Реплики'},{'settings','Настройки'}},s,{buttons=true,font=s.buttonFont})
    local function phrase(i,p)
        if s:button(p.name:gsub('##','# #')..'##assist-say-'..i,ui)then
            s.vehicleDraft=d;s:autoSettings('vehicle',{'vehicle'},d,'vehicleDraft')
            if saved(s,callbacks,'vehicle')then
                local proposal,err=callbacks.vehicleOffer('megaphone_'..i,false)
                if proposal then s.vehicleConfirm=proposal else note(s,err)end
            end
        end
    end
    if s.megaphonePage=='phrases'then
        s:settingsHeading(ui,'Общие объявления')
        ui.text('Эти реплики можно использовать без выбранной машины. Начинать погоню или трафик-стоп не нужно.')
        local count=0;for i,p in ipairs(d.phrases)do if p.enabled and p.target=='none'then phrase(i,p);count=count+1 end end
        if count==0 then ui.text('Добавьте общее объявление во вкладке «Настройки»: выберите адресата «Все окружающие».')end
        im.Separator();s:settingsHeading(ui,'Обращение к выбранной машине')
        if v.selected then
            local values=require('pa26_vehicle').describe(v.selected,d,s.lib.profile.gender)
            ui.text('Выбрана: '..(values and values.model or d.unknown_model)..' ['..v.selected.id..']')
            if s:button('Снять выбор машины##assist-car-clear',ui)then callbacks.vehicleClear()end
        else ui.text('Для адресного требования выберите видимую машину из списка:')end
        for _,c in ipairs(v.candidates or {})do
            local values=require('pa26_vehicle').describe(c,d,s.lib.profile.gender)
            if s:button((values and values.model or d.unknown_model)..' ['..c.id..'] · '..math.floor(c.distance)..' м##assist-car-'..c.id,ui)then
                local ok,err=callbacks.vehicleSelect(c.id);if not ok then note(s,err)end
            end
        end
        for i,p in ipairs(d.phrases)do if p.enabled and p.target~='none'then phrase(i,p)end end
    else
        s:settingsHeading(ui,'Когда доступен мегафон')
        for _,row in ipairs({{'megaphone_require_patrol','Только во время активного патруля'},
            {'megaphone_require_duty','Только в служебном режиме'},{'megaphone_require_radio','Требовать включённую рацию'},
            {'megaphone_wheel','Показывать мегафон в радиальном меню'}})do
            d[row[1]]=s:check(row[2]..'##megaphone-'..row[1],d[row[1]])
        end
        ui.text('Мегафон включается отдельно от транспорта. Для использования вне патруля снимите «Только во время активного патруля». Условие конкретной реплики задаётся ниже. Доступ к /m и результат команды определяет сервер.')
        key(s,ui,callbacks,'vehicle','megaphone_shortcut','Открыть выбор реплик')
        key(s,ui,callbacks,'assist','megaphone_shortcut','Дополнительное сочетание для этого окна')
        ui.text('В радиальном меню с категориями: «Служба → Мегафон». Этот пункт открывает окно и ничего не отправляет. Через F4: «Помощники → Мегафон».')
        im.Separator();s:settingsHeading(ui,'Настройка реплик')
        local choices={};for i,p in ipairs(d.phrases)do choices[#choices+1]={i,'Реплика '..i..' · '..p.name}end
        s.phraseSlot=s:choice('Изменить требование##assist-phrase-slot',s.phraseSlot or 1,choices,ui)
        local i=s.phraseSlot;local p=d.phrases[i];local prefix='assist:phrase:'..i..':'
        p.enabled=s:check('Показывать кнопку требования##assist-phrase-enabled',p.enabled)
        p.name=s:field('Короткое название##assist-phrase-name',prefix..'name',p.name,256)
        p.target=s:choice('Адресат##assist-phrase-target',p.target,{{'vehicle','Выбранная машина'},{'none','Все окружающие'}},ui)
        p.template=s:field('Текст без /команды##assist-phrase-text',prefix..'text',p.template,2048,true,110)
        p.channel=s:choice('Канал##assist-phrase-channel',p.channel,{{'/m','Мегафон /m'},{'/s','Крик /s'}},ui)
        p.condition=s:choice('Когда доступно##assist-phrase-condition',p.condition,vehicles.phraseConditions,ui)
        ui.text('Для всех реплик: {direction}, {station}, {unit}, {crew}, {area}, {location}, {map_square}, {sector}, {callsign} и поля профиля. Для выбранной машины также: {model}, {model_id}, {vehicle_color}, {vehicle_id}, {vehicle_description}, {color_one}, {color_two}. Общий текст не должен содержать переменные чужой машины.')
        local line,err=callbacks.vehiclePreview('megaphone_'..i,d)
        s:settingsHeading(ui,'Предпросмотр');ui.text(line or tostring(err))
        key(s,ui,callbacks,'vehicle','phrase_'..i..'_shortcut','Подтвердить эту реплику по сочетанию')
    end
    s.vehicleDraft=d;s:autoSettings('vehicle',{'vehicle'},d,'vehicleDraft');s:autosaveHint(ui,'vehicle')
    s:drawNotice(ui)
end
function M.evidence(s,ui,data,callbacks)
    local im=s.imgui;local d=s.evidenceDraft or model.copy(s.lib.assist.evidence);local view=data.evidence or {}
    s.currentNoticeScope='evidence';s:settingsHeading(ui,'Фиксация доказательств')
    ui.text('PA может отправить проверенную вами команду времени, затем дождётся снимка, который вы сделаете клавишей F8. Автоматическая съёмка пока не подключена. Журнал PA сам по себе не заменяет снимок, видео или проверку администрации.')
    s.evidenceLabel=s:field('Что фиксируем##evidence-label','assist:evidence:label',s.evidenceLabel or '',384)
    if not view.active and not view.pending then
        if s:button('Подготовить фиксацию##evidence-start',ui)then
            s.evidenceDraft=d;s:autoSettings('evidence',{'assist','evidence'},d,'evidenceDraft')
            if saved(s,callbacks,'evidence')then M.offer(s,callbacks)end
        end
    end
    s:observeStatus('assist',view.message,'assist')
    if view.pending then ui.text('Выполняется подготовка. Повторный запуск заблокирован.')end
    if view.active then
        ui.text(d.prompt)
        s.evidencePath=s:field('Путь к созданному снимку##evidence-file','assist:evidence:path',s.evidencePath or '',2048)
        ui.text(d.file_hint)
        if s:button('Проверить новый файл##evidence-check',ui)then local ok,err=callbacks.evidenceCheck(s.evidencePath);if not ok then note(s,err)end end
    end
    if(view.active or view.pending)and s:button('Отменить фиксацию##evidence-cancel',ui)then callbacks.evidenceCancel()end
    if view.unsaved and s:button('Повторить запись журнала##evidence-retry',ui)then callbacks.evidenceRetry()end
    im.Separator();s:settingsHeading(ui,'Настройки фиксации')
    d.enabled=s:check('Включить помощник фиксации##evidence-enabled',d.enabled)
    local command,commandEdited=s:field('Команда времени без аргументов##evidence-command','assist:evidence:command',d.time_command,128)
    if commandEdited and command~=d.time_command then d.time_command=command;d.time_verified=false;d.time_enabled=false end
    d.time_source=s:field('Где проверена команда: /help или ответ сервера##evidence-source','assist:evidence:source',d.time_source,1024)
    d.time_verified=s:check('Я проверил эту команду на сервере##evidence-verified',d.time_verified)
    d.time_enabled=s:check('Отправлять команду времени после ДА##evidence-time-enabled',d.time_enabled)
    number(s,ui,d,'delay_ms','Пауза перед снимком, мс##evidence-delay')
    number(s,ui,d,'timeout_ms','Ожидание снимка, с##evidence-timeout',1000)
    number(s,ui,d,'confirmation_ms','Срок подтверждения, с##evidence-confirmation',1000)
    d.prompt=s:field('Текст подсказки перед снимком##evidence-prompt','assist:evidence:prompt',d.prompt,1024,true,70)
    d.file_hint=s:field('Подсказка к пути снимка##evidence-file-hint','assist:evidence:file-hint',d.file_hint,1024,true,70)
    ui.text('Предпросмотр: '..(d.time_enabled and d.time_command or 'Команда времени выключена')..' → пауза '..d.delay_ms..' мс → '..d.prompt)
    s.evidenceDraft=d;s:autoSettings('evidence',{'assist','evidence'},d,'evidenceDraft');s:autosaveHint(ui,'evidence')
    key(s,ui,callbacks,'assist','evidence_shortcut','Открыть фиксацию')
    im.Separator();s:settingsHeading(ui,'Последние фиксации')
    for i=#s.lib.assist.history,math.max(1,#s.lib.assist.history-7),-1 do
        local h=s.lib.assist.history[i]
        ui.text(h.date..' · '..h.label..' · '..({verified='Файл проверен',cancelled='Отменено',timeout='Истекло ожидание',demo='Демо'})[h.status])
        if h.path~=''then ui.text(h.path)end
        ui.text(h.details)
    end
    if #s.lib.assist.history>0 and s:button('Очистить журнал фиксаций##evidence-history-clear',ui)then
        s.assistConfirm={kind='clear_evidence',history=model.copy(s.lib.assist.history)}
    end
    s:drawNotice(ui)
end
function M.study(s,ui,data,callbacks)
    local im=s.imgui;local d=s.trainingDraft or model.copy(s.lib.assist.training)
    s.study=s.study or training.new();s.currentNoticeScope='training';s:settingsHeading(ui,'Личное обучение')
    ui.text('Добавьте свои вопросы и ответы, укажите источник и редакцию материала. После ответа вы сами отмечаете, насколько уверенно его помните. Это помощник для подготовки к экзамену.')
    d.enabled=s:check('Включить обучение##study-enabled',d.enabled)
    d.department=s:choice('Ведомство##study-department',d.department,departments,ui)
    number(s,ui,d,'limit','Вопросов за занятие · 1–50##study-limit')
    s.trainingDraft=d;s:autoSettings('training',{'assist','training'},d,'trainingDraft')
    if s:button('Начать занятие##study-start',ui)and saved(s,callbacks,'training')then local ok,err=s.study:start(s.lib.assist.training);if not ok then note(s,err)end end
    local c,err=s.study:current(s.lib.assist.training);s:passiveWarning('training-current',err,'training')
    local session=s.study.session
    if session then
        im.Separator()
        if c then
            s:settingsHeading(ui,'Вопрос '..session.index..' из '..#session.rows);ui.text(c.question)
            ui.text('Источник: '..c.source..' · редакция: '..c.revision)
            if not session.revealed then if s:button('Показать ответ##study-reveal',ui)then s.study:reveal(s.lib.assist.training)end
            else
                s:settingsHeading(ui,'Ответ для сравнения');ui.text(c.answer)
                for _,sp in ipairs({{true,'Знал ответ##study-known'},{false,'Повторить позже##study-repeat'}})do
                    if s:button(sp[2],ui)and saved(s,callbacks,'training')then
                        local cfg,token=s.study:grade(s.lib.assist.training,sp[1])
                        if cfg then
                            local copy=model.copy(s.lib);copy.assist.training=cfg
                            local ok,saveErr=callbacks.save(copy)
                            if ok then s.study:commit(token);s.trainingDraft=nil;d=cfg else note(s,saveErr)end
                        else note(s,token)end
                    end
                end
            end
        else s:settingsHeading(ui,'Занятие завершено');ui.text('Знал: '..session.known..' · повторить: '..session.repeat_count..'. Приоритет следующего занятия — карточки, которые давались труднее.')end
        if s:button('Закончить занятие##study-stop',ui)then s.study:cancel()end
    end
    im.Separator();s:settingsHeading(ui,'Редактор своих карточек')
    if #d.cards<prefs.MAX_CARDS and s:button('Добавить учебную карточку##study-add',ui)then
        local id=d.next_id;d.next_id=id+1
        d.cards[#d.cards+1]={id=id,name='Новая карточка '..id,enabled=false,question='',answer='',source='',revision='',department='all'};s.studyCard=id
    end
    local choices={};for _,card in ipairs(d.cards)do choices[#choices+1]={card.id,card.name}end
    if #choices>0 then
        local exists=false;for _,card in ipairs(d.cards)do if card.id==s.studyCard then exists=true end end
        if not exists then s.studyCard=d.cards[1].id end
        s.studyCard=s:choice('Карточка##study-card',s.studyCard,choices,ui)
        for _,card in ipairs(d.cards)do if card.id==s.studyCard then
            local prefix='assist:study:'..card.id..':'
            card.name=s:field('Название карточки##study-name',prefix..'name',card.name,384)
            card.enabled=s:check('Использовать в занятиях##study-card-enabled',card.enabled)
            card.department=s:choice('Для ведомства##study-card-department',card.department,departments,ui)
            for _,sp in ipairs({{'question','Вопрос',8193,100},{'answer','Ответ',16385,150},{'source','Ссылка или название источника',1025},{'revision','Редакция / дата источника',385}})do
                card[sp[1]]=s:field(sp[2]..'##study-'..sp[1],prefix..sp[1],card[sp[1]],sp[3],sp[4]~=nil,sp[4])
            end
            local p=d.progress[tostring(card.id)]
            ui.text(p and('Ваш прогресс: знал '..p.known..', повторить '..p.repeat_count)or'Ещё не проходили. Изменение вопроса, ответа или источника сбрасывает прогресс этой редакции.')
            if s:button('Удалить карточку##study-delete',ui)then s.assistConfirm={kind='delete_card',id=card.id,name=card.name,revision=prefs.revision(card)}end
        end end
    else ui.text('Карточек пока нет. Добавьте свою и заполните источник.')end
    s.trainingDraft=d;s:autoSettings('training',{'assist','training'},d,'trainingDraft');s:autosaveHint(ui,'training')
    key(s,ui,callbacks,'assist','training_shortcut','Открыть обучение');s:drawNotice(ui)
end
function M.notices(s,ui,data,callbacks)
    local d=s.interactionDraft or model.copy(s.lib.assist.interaction)
    s.currentNoticeScope='interaction';s:settingsHeading(ui,'Карточки взаимодействия')
    ui.text('Эти уведомления видны только вам на HUD и не попадают в игровой чат. Новые тексты и сроки начнут действовать со следующего события.')
    ui.text(s.lib.settings.interaction_notices and 'Показ включён: Настройки → Доступ.'or'Показ выключен: Настройки → Доступ.')
    if s:button('Открыть настройки показа##interaction-settings',ui)then callbacks.openNoticeSettings()end
    for _,r in ipairs({{'started_ms','Начало взаимодействия, с'},{'ended_ms','Завершение, с'},{'disconnected_ms','Выход человека с сервера, с'}})do number(s,ui,d,r[1],r[2]..'##notice-'..r[1],1000)end
    number(s,ui,d,'max_cards','Одновременно карточек · 1–3##notice-count')
    ui.text('{name} — ник человека, {id} — его SA:MP ID. Введите текст без /команд. Эти подписи помогают вам узнать игрока и не считаются сведениями, известными персонажу.')
    for _,r in ipairs(prefs.noticeFields)do
        d[r[1]]=s:field(r[2]..'##notice-'..r[1],'assist:notice:'..r[1],d[r[1]],512,true,60)
    end
    s:settingsHeading(ui,'Предпросмотр выхода человека')
    local function expand(v)return v:gsub('{name}','Player_Name'):gsub('{id}','37')end
    ui.text(expand(d.ended_title));ui.text('Player_Name [37]');ui.text(expand(d.disconnected));ui.text('Срок: '..(d.disconnected_ms/1000)..' с')
    s.interactionDraft=d;s:autoSettings('interaction',{'assist','interaction'},d,'interactionDraft');s:autosaveHint(ui,'interaction');s:drawNotice(ui)
end
function M.draw(s,ui,data,callbacks)
    s.currentUi=ui;s.preferenceContext=true;s.settingTextChanged=false;s.currentNoticeScope='assist'
    local tab=s.assistPage or'patrol'
    if tab~='roleplay'and tab~='commands'then
        tab=menu.choiceControl(s.imgui,ui,'##assist-tabs','',tab,{{'patrol','Патруль'},{'megaphone','Мегафон'},{'evidence','Фиксация'},{'training','Обучение'},{'notices','Уведомления'}},s,{buttons=true,font=s.buttonFont})
        s.assistPage=tab
    end
    if s:button('Настройки чата, переноса RP и команд##assist-chat-settings',ui)and callbacks.openSettings then callbacks.openSettings('chat')end
    if tab=='patrol'then require('pa26_patrol_ui').draw(s,ui,data,callbacks)
    elseif tab=='megaphone'then M.megaphone(s,ui,data,callbacks)
    elseif tab=='evidence'then M.evidence(s,ui,data,callbacks)
    elseif tab=='notices'then M.notices(s,ui,data,callbacks)
    elseif tab=='roleplay'then require('pa26_rp_ui').draw(s,ui,data,callbacks)
    elseif tab=='commands'then require('pa26_server_commands').draw(s,ui,data,callbacks)
    else M.study(s,ui,data,callbacks)end
    s.preferenceContext=nil
end
function M.waiting(s,ui,view,now)
    local p=view.active;if not p then return end
    local im=s.imgui;local io=im.GetIO();local width=math.max(180,math.min(660,io.DisplaySize.x-32))
    local remaining=math.max(0,math.ceil((p.cfg.timeout_ms-((require('pa26_core').elapsed(now,p.waitAt))or p.cfg.timeout_ms))/1000))
    local message='Фиксация · '..p.label..'\n'..p.cfg.prompt..'\nОсталось '..remaining..' с · End / Esc — отменить'
    local font=s.buttonFont or im.GetFont();local layout=menu.labelLayout(font,tonumber(font.FontSize),width-40,message)
    im.SetNextWindowPos(im.ImVec2(io.DisplaySize.x/2,28),im.Cond.Always,im.ImVec2(.5,0))
    im.SetNextWindowSize(im.ImVec2(width,math.min(io.DisplaySize.y-56,layout.height+40)),im.Cond.Always)
    im.Begin('Фиксация##pa26-evidence-progress',nil,im.WindowFlags.NoDecoration+im.WindowFlags.NoInputs+im.WindowFlags.NoSavedSettings)
    ui.push(function()im.End()end);ui.text(message);ui.finish()
end
function M.modal(s)
    local a=s.assistConfirm;if not a then return end
    if a.kind=='evidence'then
        local p=a.proposal;local lines={p.label,'Район: '..p.area}
        for _,line in ipairs(p.lines)do lines[#lines+1]=line end
        lines[#lines+1]=#p.lines==0 and 'Команда времени выключена. В игровой чат ничего не отправится.'or 'После ДА PA отправит команду один раз. Убедитесь в игре, что сервер её выполнил.'
        lines[#lines+1]='Окна PA закроются, пауза '..p.cfg.delay_ms..' мс. '..p.cfg.prompt
        lines[#lines+1]='После этого откройте помощник и укажите путь. Файл должен быть новым, непустым и стабильным. Ожидание: '..(p.cfg.timeout_ms/1000)..' с.'
        lines[#lines+1]=p.demo and 'ДЕМО: команда и снимок не создаются.'or 'Снимок делаете вручную F8. Его содержание PA не оценивает.'
        return {kind='assistant',token=p.token,title='Начать фиксацию?',lines=lines}
    elseif a.kind=='delete_card'then return {kind='assistant',token='delete-study:'..a.id..':'..a.revision,title='Удалить учебную карточку?',lines={a.name,'Вопрос, ответ и личный прогресс этой карточки будут удалены.'}}
    elseif a.kind=='clear_evidence'then return {kind='assistant',token='clear-evidence:'..#a.history,title='Очистить журнал фиксаций?',lines={'Будет удалён локальный журнал: '..#a.history..' записей.','Файлы снимков останутся на диске.'}}end
end
function M.accept(s,callbacks)
    local a=s.assistConfirm;if not a then return nil,'Подтверждение отсутствует.'end
    if a.kind=='evidence'then return callbacks.evidenceAccept(a.proposal)end
    local copy=model.copy(s.lib)
    if a.kind=='delete_card'then
        copy.assist.training=model.copy(s.trainingDraft or s.lib.assist.training);local found
        for i,c in ipairs(copy.assist.training.cards)do if c.id==a.id then
            if prefs.revision(c)~=a.revision then return nil,'Карточка изменилась. Подтвердите удаление заново.'end
            table.remove(copy.assist.training.cards,i);copy.assist.training.progress[tostring(a.id)]=nil;found=true;break
        end end
        if not found then return nil,'Карточка уже удалена.'end
    elseif a.kind=='clear_evidence'then
        if not callbacks.assistEqual(copy.assist.history,a.history)then return nil,'Появились новые записи. Подтвердите очистку заново.'end
        copy.assist.history={}
    else return nil,'Неизвестное действие помощника.'end
    local ok,err=callbacks.save(copy)
    if ok and a.kind=='delete_card'then
        s.trainingDraft=nil;if s.autosaves then s.autosaves.training=nil end
        s:clearPreferenceCache('assist:study:'..tostring(a.id)..':')
    end
    return ok,err
end
return M

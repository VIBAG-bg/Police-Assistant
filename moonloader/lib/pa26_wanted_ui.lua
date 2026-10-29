-- PA-owned wizard; never clicks server dialogs and never sends from rendering.
local catalog=require 'pa26_wanted_catalog'
local prefs=require 'pa26_procedure_settings'
local model=require 'pa26_bindings'
local M={}
local function error(s,why)s:notify(why or 'Не удалось выполнить действие.','procedures',false)end
local function field(s,f,label,key,size,multi)
    f[key]=s:field(label..'##wanted-'..key,'wanted-form:'..f.id..':'..key,f[key]or '',size or 1024,multi,multi and 90 or nil)
end
local function question(s,f,ui,label,key)
    f[key]=s:choice(label..'##wanted-'..key,f[key],{{'unknown','Не знаю'},{'yes','Да'},{'no','Нет'}},ui)
end
function M.settings(s,ui,cfg,cb)
    s:settingsHeading(ui,'Помощник розыска')
    for _,r in ipairs({{'wanted_assistant_enabled','Включить помощник розыска'},{'wanted_enabled','Действия розыска доступны в меню'},{'wanted_intercept','Открывать помощник для /su и /wanted'},
        {'wanted_require_life_ack','Спрашивать о ситуации после последней смерти'},{'allow_ooc','Показывать отдельную OOC-ветку'},
        {'wanted_reminder_enabled','Напоминать о проверке OOC-звёзд'},
        {'wanted_allow_remote','Разрешить /su ID для игрока в любой точке карты'},
        {'wanted_autofill_passport','После подтверждения паспорта подставлять имя из ника'},
        {'wanted_id_as_passport','При автозаполнении использовать ID как номер паспорта'},
        {'wanted_suggest_ooc','Предлагать OOC, если маска мешает установить личность'},
        {'wanted_each_trait','Каждую примету через запятую отыгрывать отдельной /todo'}})do cfg[r[1]]=s:check(r[2]..'##wanted-config-'..r[1],cfg[r[1]])end
    ui.text('Для /su ID игроку достаточно быть подключённым: расстояние, другой город и отсутствие на экране не мешают. Взаимодействие рядом не требуется. Имя и номер подставляются только после распознанного показа паспорта вам либо вашего ответа «паспорт видел». Ник: John_Smith → John Smith; номер: ID. Свои уточнения сохраняются. Без паспорта доступен общий RP по приметам. OOC только предлагается: выбор и отправку подтверждаете вы.')
    cfg.wanted_label=s:field('Название действия в меню##case-label-wanted','case:label:wanted',cfg.wanted_label,512)
    for _,r in ipairs({{'wheel','В радиальном меню'},{'quick','В быстром списке'}})do cfg['wanted_'..r[1]]=s:check(r[2]..'##case-access-wanted_'..r[1],cfg['wanted_'..r[1]])end
    ui.text('Открыть форму: '..model.shortcutName(cfg.wanted_shortcut))
    if s:button('Назначить клавишу##case-key-wanted',ui)then cb.capture({kind='feature',group='procedures',field='wanted_shortcut'})end
    if cfg.wanted_shortcut.key~=0 and s:button('Снять назначение##case-key-clear-wanted',ui)then cfg.wanted_shortcut={key=0,ctrl=false,alt=false,shift=false}end
    cfg.wanted_send_mode=s:choice('После подтверждения##wanted-send-mode',cfg.wanted_send_mode,
        {{'direct','Выдать выбранный пункт через шорткат'},{'menu','Открыть серверный список причин'}},ui)
    ui.text('/su ID раздел подпункт: последние два числа — коды, а не количество звёзд. /su ID открывает список. /wanted без аргументов показывает общий список преступников.')
    for _,r in ipairs({{'wanted_direct_command','Шорткат выдачи'},{'wanted_open_command','Открытие серверного списка'},{'wanted_list_command','Общий список преступников'}})do
        cfg[r[1]]=s:field(r[2]..'##wanted-config-'..r[1],'wanted-config:'..r[1],cfg[r[1]],1024)
    end
    ui.text('В этой версии допустим только подтверждённый синтаксис выше. Старый шаблон wanted_command сохранён в личных данных, но помощник его не отправляет.')
    for _,r in ipairs({{'delay_ms','Пауза между RP-строками, мс'},{'wanted_reminder_delay_ms','Первая проверка OOC, мс'},
        {'wanted_reminder_snooze_ms','Повтор напоминания, мс'},{'wanted_reminder_show_ms','Длительность карточки, мс'}})do
        ui.text(r[2]);local n=s.imgui.new.int(cfg[r[1]])
        s.imgui.PushItemWidth(math.max(1,s.imgui.GetContentRegionAvail().x));ui.push(function()s.imgui.PopItemWidth()end)
        if s.imgui.InputInt('##wanted-time-'..r[1],n)then cfg[r[1]]=n[0]end;ui.finish()
    end
    ui.text('По умолчанию приметы идут связным докладом в /todo. Длинный доклад продолжается с маркером из настроек переноса (обычно ...), а действие после * сохраняется в каждой части. Отдельная реплика на каждую примету включается переключателем выше.')
    ui.text('RP: 1000–10000 мс, с учётом общего интервала PA. Первая проверка: 1000–300000 мс; повтор: 1000–600000 мс; показ: 1000–60000 мс.')
    cfg.wanted_reminder_title=s:field('Заголовок напоминания##wanted-reminder-title','wanted:reminder:title',cfg.wanted_reminder_title,512)
    cfg.wanted_reminder_text=s:field('Текст напоминания##wanted-reminder-text','wanted:reminder:text',cfg.wanted_reminder_text,4096,true,90)
    ui.text('Предпросмотр: '..cfg.wanted_reminder_title..' — '..cfg.wanted_reminder_text)
    s:settingsHeading(ui,'Отыгровки розыска')
    ui.text('Наши редактируемые фразы. Переменные: {device}, {ic_name}, {passport_number}, {appearance}, {game_group}, {game_reason}, {game_stars}, {game_category}, {game_item}, {facts}, {ooc_purpose}, {id}. Имя/номер используются после подтверждения паспорта. Дополнение с номером идёт после основной паспортной отыгровки; общий RP по приметам применяется, если своё описание не введено. Грамматический род: {gender:передал|передала}, выбирается в Профиле. Длинные реплики переносятся общей системой PA.')
    for _,r in ipairs(prefs.rpFields)do if r[1]:match('^wanted_')then
        cfg[r[1]]=s:field(r[2]..'##wanted-rp-'..r[1],'wanted-rp:'..r[1],cfg[r[1]],8192,true,90)
        ui.text('Предпросмотр: '..cb.caseTemplatePreview(cfg[r[1]],s.caseForm))
    end end
end
function M.reasonPicker(s,ui,f,cb,options)
    options=options or{};local pageSize=options.perPage or 4
    local groups={{'all','Все разделы (все статьи)'}};for _,r in ipairs(catalog.groups)do groups[#groups+1]={r.id,r.id..' · '..r.title}end
    f.reason_group=s:choice('Раздел преступления##wanted-group',f.reason_group or'all',groups,ui)
    s.wantedSearch=s:field('Поиск · можно оставить пустым##wanted-search','wanted:search',s.wantedSearch or '',512)
    local query=model.casefold(s.wantedSearch):gsub('ё','е'):match('^%s*(.-)%s*$')
    local rows={}
    for _,r in ipairs(catalog.rows)do
        local text=model.casefold(r.group_title..' '..r.title..' '..r.id..' '..table.concat(r.refs,' ')):gsub('ё','е')
        if query~=''and text:find(query,1,true)or query==''and(f.reason_group=='all'or r.group==f.reason_group) then rows[#rows+1]=r end
    end
    if query~=''then ui.text('Найдено: '..#rows..'. Поиск по всем разделам; выбор причины не отправляет команду.')end
    if options.adaptive then
        local im=s.imgui;local width=math.max(1,im.GetContentRegionAvail().x-28);local font=s.buttonFont or im.GetFont();local size=tonumber(font.FontSize)
        local function height(t)return require('pa26_menu').labelLayout(font,size,width,t).height+26 end
        local reserve=height('Подробности основания и факты')+height('Проверить отыгровку и команду')+height('Назад · сведения')+96
        local rowHeight=52
        for _,r in ipairs(rows)do rowHeight=math.max(rowHeight,height('Выбрано · '..r.id..' · '..r.title..' · '..r.stars..' ур.'))end
        pageSize=math.max(2,math.min(8,math.floor((im.GetContentRegionAvail().y-reserve)/rowHeight)))
    end
    s.wantedMatchedCount=#rows;s.wantedPerPage=pageSize
    s.wantedPage=s.wantedPage or 1
    local signature=f.reason_group..'\0'..query
    if s.wantedPageSignature~=signature then s.wantedPage=1;s.wantedPageSignature=signature end
    local pages=math.max(1,math.ceil(#rows/pageSize));s.wantedPage=math.max(1,math.min(pages,s.wantedPage))
    for n=(s.wantedPage-1)*pageSize+1,math.min(#rows,s.wantedPage*pageSize)do local r=rows[n]
        local label=(f.reason_id==r.id and 'Выбрано · 'or '')..r.id..' · '..r.title..' · '..r.stars..' ур.'
        if s:button(label..'##wanted-reason-'..r.id,ui)then f.reason_id=r.id end
    end
    if #rows==0 then ui.text('Подходящих пунктов нет. Измените запрос или очистите поле поиска.')end
    if pages>1 then
        ui.text('Страница '..s.wantedPage..' / '..pages)
        local width=options.compact and math.max(1,(s.imgui.GetContentRegionAvail().x-10)/2)or nil
        if s:button('Предыдущая##wanted-page-back',ui,width)then s.wantedPage=math.max(1,s.wantedPage-1)end
        if options.compact then s.imgui.SameLine(0,10)end
        if s:button('Следующая##wanted-page-next',ui,width)then s.wantedPage=math.min(pages,s.wantedPage+1)end
    end
    local r=catalog.byId[f.reason_id]
    if r and options.compact then ui.text('Выбран: '..r.id..' · '..r.stars..' ур.')end
    if r and not options.compact then
        s:settingsHeading(ui,'Выбранный пункт: '..r.id..' · '..r.title)
        ui.text(r.group_title..' · '..r.stars..' ур. розыска по серверному меню. Это не перевод IC-лет в звёзды и не расчёт сложения уровней.')
        local refs={};for _,v in ipairs(r.refs)do refs[#refs+1]=v:gsub('UK:','УК ст. '):gsub('AK:','АК ст. ')end
        ui.text('Возможные нормы: '..(#refs>0 and table.concat(refs,', ')or 'прямое соответствие не найдено'))
        ui.text(r.mapping_status..'. '..r.note)
        if cb.openWantedKnowledge and s:button('Открыть карточку в базе##wanted-knowledge',ui)then cb.openWantedKnowledge(r.knowledge_key)end
    end
end
function M.form(s,ui,data,cb,cfg)
    local im=s.imgui
    if s:button('Новая форма##case-new',ui)then
        local f,why=cb.caseBegin(s.caseKind)
        if f then
            if f.kind=='wanted'and catalog.byId[s.wantedSuggestedReason]then f.reason_id=s.wantedSuggestedReason;f.reason_group=f.reason_id:sub(1,2);s.wantedSuggestedReason=nil end
            s.caseForm=f;s.caseStoredForms=s.caseStoredForms or {};s.caseStoredForms[f.kind]=f
        else error(s,why)end
    end
    local f=s.caseForm;if f and cb.caseValid and not cb.caseValid(f)then
        s.wantedAppearance=nil;ui.text('Форма устарела: игрок отключился, ID изменился или игровая сцена недоступна. Создайте новую форму.');return
    end
    if not f then
        ui.text(s.caseKind=='wanted_list'and 'Общий список не требует выбранного человека. ID в /wanted не добавляется.'or 'Введите /su ID подключённого игрока в любой точке карты либо выберите человека рядом и откройте новую форму.')
        return
    end
    im.Separator();ui.text(f.target and('Подозреваемый: '..f.target.name..' [ID: '..f.target.id..']')or 'Общий список преступников')
    ui.text('Отыгровка через: '..(f.inVehicle and 'бортовой компьютер крузера'or 'служебный КПК')..'. Стоять рядом не нужно: /su ID работает на любом расстоянии. PA проверяет, чтобы под этим ID не зашёл другой игрок. После смены машины или игровой сцены подготовьте действие заново.')
    if f.stage=='identity'then
        if cfg.wanted_require_life_ack then f.life_ack=s:check('Основание получено в текущей игровой жизни · не использую сведения до смерти / RK##wanted-life-ack',f.life_ack)end
        if cfg.allow_ooc then f.mode=s:choice('Ветка розыска##wanted-mode',f.mode,{{'ic','IC · по паспорту или приметам'},{'ooc','OOC · только для пеленгации /setmark'}},ui)end
        if f.mode=='ooc'then
            f.ooc_reason=s:choice('Для какой механики нужны звёзды##wanted-ooc-purpose',f.ooc_reason,prefs.oocReasons,ui)
            ui.text(prefs.oocNotes[f.ooc_reason]or '')
            ui.text('Это не IC-обвинение. Маска сама по себе не разрешает OOC-звёзды. Для /pt и Alcatraz они запрещены. После смерти в той же ситуации и для личных целей выдача запрещена.')
            question(s,f,ui,'Номер телефона известен вашему персонажу по RP?','phone_known')
            question(s,f,ui,'Проверили, что телефон сейчас включён?','phone_active')
            question(s,f,ui,'До этих технических звёзд у человека уже был IC-розыск?','prior_ic_stars')
            ui.text('Если IC-розыск уже есть или его состояние неизвестно, не добавляйте технические звёзды через эту ветку. Откройте пеленгацию отдельно; существующие IC-звёзды снимать нельзя.')
            if f.phone_known=='yes'then field(s,f,'IC-номер телефона','phone_number',512);field(s,f,'Откуда известен номер по RP','phone_source',512)end
            f.ooc_ack=s:check('Проверил RP-пеленгацию, телефон включён, сниму звёзды сразу после неё##wanted-ooc-ack',f.ooc_ack)
        else
            question(s,f,ui,'На подозреваемом полная RP-маска (/mask + аксессуар на лице)?','mask')
            ui.text('По п. 14.1–14.3 RP-маска — одновременно серый цвет /mask и аксессуар, закрывающий лицо. Только одно условие — NonRP-маска: выберите «Нет», затем проверьте основание розыска по приметам. Ник и TAB не устанавливают личность по RP.')
            if f.mask=='yes'then question(s,f,ui,'Вы установили личность по лицу или паспорту ДО маски и НЕ теряли человека из виду?','face_before')end
            question(s,f,ui,'Вы видели паспорт этого человека?','passport_seen')
            if cb.caseFillWanted then cb.caseFillWanted(f)end
            if f.passport_seen=='yes'then
                ui.text((f.passport_source=='server'and 'Показ паспорта вам распознан из чата. 'or 'Вы отметили, что видели паспорт. ')..'В отыгровку подставится имя: '..f.ic_name..' · № паспорта: '..(f.passport_number~=''and f.passport_number or 'не указан')..' (по настройкам PA: имя из ника, номер из ID; ручное уточнение сохраняется).')
                f.edit_passport=s:check('Уточнить имя или номер вручную##wanted-edit-passport',f.edit_passport==true)
                if f.edit_passport or not cfg.wanted_autofill_passport then
                    field(s,f,'Имя и фамилия из показанного паспорта','ic_name',512)
                    field(s,f,'Номер паспорта · если известен','passport_number',512)
                end
            elseif f.passport_seen=='no'then
                ui.text('На следующем шаге выберите «Общая» или «С приметами». Во втором случае откроется отдельное окно ввода; ранее записанные в PA приметы будут подставлены.')
                if cb.caseSuggestOoc and cb.caseSuggestOoc(f)then
                    ui.text('RP-маска мешает IC-идентификации. OOC-ветка возможна только для /setmark при известном IC-номере и RP-пеленгации, а не для /pt или ареста. На следующем шаге нужно подтвердить эти условия.')
                    if s:button('Перейти к OOC-звёздам##wanted-use-ooc',ui)then local ok,why=cb.caseChooseOoc(f);if not ok then error(s,why)end end
                end
            end
        end
        local branch,why=cb.caseBranch(f);if not branch then ui.text(why)end
        if s:button('Далее · причина розыска##wanted-next',ui)then local ok,why=cb.caseNext(f);if not ok then error(s,why)end end
    elseif f.stage=='appearance_choice'or f.stage=='appearance_input'then
        s.wantedAppearance={form=f,stage=f.stage}
        ui.text('Выберите отыгровку в отдельном окне: общую либо с введёнными приметами.')
    elseif f.stage=='basis'then
        M.reasonPicker(s,ui,f,cb)
        field(s,f,'Факты ситуации · для заметки и переменной {facts}','facts',2048,true)
        if s:button('Проверить отыгровку и команду##wanted-preview',ui)then local ok,why=cb.caseNext(f);if not ok then error(s,why)end end
        if f.branch=='appearance'then
            ui.text(f.appearance_mode=='detailed'and 'Отыгровка с приметами: '..f.appearance or 'Общая отыгровка по приметам.')
            if s:button('Изменить вариант отыгровки##wanted-change-appearance',ui)then f.stage='appearance_choice'end
        end
        if s:button('Назад · сведения##wanted-back-identity',ui)then f.stage='identity'end
    else
        local p,why=cb.casePreview(f)
        if not p then ui.text(why)else
            if p.gameReason then
                ui.text('Пункт '..p.gameReason.id..' · '..p.gameReason.title..' · '..p.gameReason.stars..' ур.')
                ui.text(p.gameReason.mapping_status..'. '..p.gameReason.note)
            end
            if f.kind=='wanted_list'then ui.text('Общий серверный список: дело, имя, уровень. Номер дела не считается ID игрока; автоматического поиска по ID здесь нет.')end
            for i,line in ipairs(p.lines)do ui.text(i..'. '..line)end
            ui.text('Кнопка ниже отправит только показанные отыгровки. После них появится отдельное ДА/НЕТ перед самой командой. End / Esc отменит остаток; НЕТ не повторяет уже отправленные RP-строки.')
            if s:button('Отыграть ориентировку в чат (затем ДА/НЕТ на выдачу)##wanted-prepare',ui)then
                local offer,why=cb.caseOffer(f)
                if offer then local ok;ok,why=cb.caseAccept(offer);if not ok then error(s,why)end else error(s,why)end
            end
        end
        if f.kind=='wanted'and s:button('Назад · выбор причины##wanted-back-basis',ui)then f.stage='basis'end
    end
end
function M.review(s,ui,data,cb)
    s:settingsHeading(ui,'Проверки OOC-звёзд')
    ui.text('Это локальные проверки результата, они сохраняются после перезапуска. Каждая команда пеленгации и снятия имеет RP и отдельное ДА. Старый ID не используется автоматически; при другом подключении цепочка заблокирована. После отправки /clear подтвердите фактическое снятие в игре.')
    local rows=data.caseForms and data.caseForms.reminders or {}
    if #rows==0 then ui.text('Незавершённых проверок нет.')end
    for _,r in ipairs(rows)do
        s.imgui.Separator();ui.text(r.player_name..' · ID при записи: '..r.player_id)
        ui.text(r.reason..' · выбранный уровень: '..r.stars)
        ui.text(r.context);ui.text('Сервер при записи: '..r.session)
        ui.text(r.status=='issued'and 'Выдачу вы отметили вручную.'or 'Проверьте, были ли звёзды действительно выданы. Команда могла завершиться ошибкой или окно могло быть закрыто.')
        if r.status=='check'and s:button('Звёзды выданы · отметить вручную##wanted-issued-'..r.token,ui)then cb.caseReminder(r.token,'issued')end
        if r.status=='issued'or r.status=='located'then
            s.chainChecks=s.chainChecks or{}
            local label=r.status=='issued'and'Телефон сейчас включён, IC-номер и источник проверены'or'Сейчас только временные OOC-звёзды: других IC-звёзд нет; пеленгация завершена'
            s.chainChecks[r.token]=s:check(label..'##chain-check-'..r.token,s.chainChecks[r.token]==true)
            if cb.caseChain and s:button((r.status=='issued'and'RP + /setmark · предпросмотр'or'RP + /clear · предпросмотр')..'##chain-send-'..r.token,ui)then
                local p,err=cb.caseChain(r.token,r.status=='issued'and'mark'or'clear',s.chainChecks[r.token])
                s.chainChecks[r.token]=false
                if p then s.caseConfirm=p else s:notify(err,'procedures',false)end
            end
        end
        if r.status=='mark_sent'then
            ui.text('Запрос /setmark передан. Это ещё не подтверждение местоположения.')
            if s:button('Результат пеленгации получен в игре##chain-located-'..r.token,ui)then cb.caseReminder(r.token,'located')end
        elseif r.status=='clear_sent'then ui.text('/clear передан. Проверьте серверный результат: напоминание останется до вашей отметки о снятии.')end
        if s:button('Звёзды сняты / не выдавались##wanted-resolved-'..r.token,ui)then cb.caseReminder(r.token,'resolved')end
    end
end
return M

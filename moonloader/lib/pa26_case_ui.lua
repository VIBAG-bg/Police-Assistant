local model=require 'pa26_bindings'
local preferences=require 'pa26_procedure_settings'
local wantedUi=require 'pa26_wanted_ui'
local M={}
function M.select(studio,kind)
    studio.caseStoredForms=studio.caseStoredForms or {}
    if studio.caseForm then studio.caseStoredForms[studio.caseForm.kind]=studio.caseForm end
    studio.caseKind=kind;studio.caseForm=studio.caseStoredForms[kind]
end
local function notify(studio,error)studio:notify(error,'procedures',false)end
function M.draw(studio,ui,data,callbacks)
    local im=studio.imgui;studio.currentNoticeScope='procedures';studio.preferenceContext=true
    studio:settingsHeading(ui,'Розыск, штрафы и пеленгация',
        'Выберите человека, заполните форму и проверьте готовый текст. PA не подбирает сведения и наказание за вас. Команда отправится после отдельного ДА, если вы заранее проверили и настроили её.','case-flow')
    ui.text('Розыск: игровой пункт определяет уровень. Штраф: сумму указываете вы. Подсказки по УК/АК не заменяют проверку фактов.')
    studio.casePage=studio:choice('Процедуры##case-page',studio.casePage or 'form',{{'form','Форма'},{'wanted_settings','Розыск · настройки'},{'ooc','Проверки OOC'},{'settings','Настройки'}},ui)
    local cfg=studio.caseDraft or model.copy(studio.lib.procedures)
    if studio.casePage=='wanted_settings'then wantedUi.settings(studio,ui,cfg,callbacks)
    elseif studio.casePage=='ooc'then wantedUi.review(studio,ui,data,callbacks)
    elseif studio.casePage=='settings'then
        for _,row in ipairs({{'enabled','Включить ручные формы'},{'wanted_enabled','Форма розыска'},{'fine_enabled','Форма штрафа'},
            {'mark_enabled','Форма пеленгации'},{'clear_enabled','Помощь со снятием технических OOC-звёзд после пеленгации'},{'allow_ooc','Отдельные OOC-ветки розыска и метки'},{'fine_unmasked','Для штрафа требовать открытое лицо'}})do
            local v,changed=studio:check(row[2]..'##case-setting-'..row[1],cfg[row[1]]);if changed then cfg[row[1]]=v end
        end
        local delay=im.new.int(cfg.delay_ms)
        if im.InputInt('Пауза между шагами, мс##case-delay',delay)then cfg.delay_ms=delay[0]end
        ui.text('От 1000 до 10000 мс. Между сообщениями также действует общий интервал PA. Перед отправкой процедуры всегда нужно подтверждение.')
        if studio.caseSettingsKind~='fine'and studio.caseSettingsKind~='mark'and studio.caseSettingsKind~='clear'then studio.caseSettingsKind='fine'end
        studio.caseSettingsKind=studio:choice('Настраиваемая процедура##case-settings-kind',studio.caseSettingsKind,
            {{'fine','Штраф'},{'mark','Пеленгация'},{'clear','Снятие технических OOC-звёзд'}},ui)
        for _,kind in ipairs({studio.caseSettingsKind})do
            if kind~='clear'then
            studio:settingsHeading(ui,'Быстрый доступ')
            cfg[kind..'_label']=studio:field('Название действия в меню##case-label-'..kind,'case:label:'..kind,cfg[kind..'_label'],512)
            for _,row in ipairs({{'wheel','В радиальном меню'},{'quick','В быстром списке'}})do
                local key=kind..'_'..row[1];local v,changed=studio:check(row[2]..'##case-access-'..key,cfg[key]);if changed then cfg[key]=v end
            end
            ui.text('Открыть форму: '..model.shortcutName(cfg[kind..'_shortcut']))
            if studio:button('Назначить клавишу##case-key-'..kind,ui)then callbacks.capture({kind='feature',group='procedures',field=kind..'_shortcut'})end
            if cfg[kind..'_shortcut'].key~=0 and studio:button('Снять назначение##case-key-clear-'..kind,ui)then
                cfg[kind..'_shortcut']={key=0,ctrl=false,alt=false,shift=false}
            end
            ui.text('Кнопка меню только открывает форму. Тексты других процедур сохраняются; перед отправкой заново проверьте выбранного человека и сведения.')
            end
            studio:settingsHeading(ui,'Команда · '..preferences.names[kind])
            if kind=='clear'then ui.text('Точный синтаксис /clear проверьте на сервере. Используйте {id}. PA предложит RP и команду только в незавершённой цепочке пеленгации, после проверки отсутствия других IC-звёзд. Отправка не закрывает напоминание о результате.')end
            ui.text(kind=='mark'and 'Команда изначально пуста. Проверьте /setmark в игре: её технические аргументы не следует выводить из IC-номера. Используйте {id} или {phone_number}, если именно они нужны. Если команда без аргументов открывает диалог, выберите цель в нём вручную: PA этот диалог не заполняет.'or 'Начальное значение пустое. Скопируйте полный синтаксис своего сервера после проверки /help. Используйте {id}, {amount}, {basis}; при необходимости {article} и {part}. Здесь не задаются суммы и звёзды по умолчанию.')
            cfg[kind..'_command']=studio:field('Точная команда сервера##case-command-'..kind,'case:command:'..kind,cfg[kind..'_command'],1024)
            ui.text('Предпросмотр команды: '..(cfg[kind..'_command']==''and 'команда пока не задана'or callbacks.caseTemplatePreview(cfg[kind..'_command'],studio.caseForm)))
            cfg[kind..'_source']=studio:field('Где проверен синтаксис##case-source-'..kind,'case:source:'..kind,cfg[kind..'_source'],1024)
            local v,changed=studio:check('Синтаксис и аргументы проверены мной##case-verified-'..kind,cfg[kind..'_verified']);if changed then cfg[kind..'_verified']=v end
        end
        ui.text('Пока проверка не отмечена, PA не отправит команду. Отмечайте её после проверки в игре: нужны точные аргументы, допустимая дистанция, ранг и ответы сервера.')
        studio:settingsHeading(ui,'Редактируемые RP-заготовки',
            'Введите отыгровки, начиная каждую строку с /me или /do. PA подставит данные формы и разделит слишком длинные реплики. Между сообщениями будет пауза, указанная выше. Все нужные поля необходимо заполнить заранее.','case-templates')
        ui.text('Личные примеры, которые нужно сверить с правилами вашего сервера. От 1 до 8 строк /me или /do. Переменные: {id}, {amount}, {basis}, {article}, {part}, {ic_name}, {passport_number}, {appearance}, {phone_number}, {phone_source}. Каждая отправляемая строка проверяется на лимит чата.')
        for _,row in ipairs(preferences.rpFields)do if row[1]:match('^'..studio.caseSettingsKind..'_')then
            cfg[row[1]]=studio:field(row[2]..'##case-rp-'..row[1],'case:rp:'..row[1],cfg[row[1]],8192,true,90)
            ui.text('Предпросмотр: '..callbacks.caseTemplatePreview(cfg[row[1]],studio.caseForm))
        end end
        ui.text('На последнем шаге формы вы увидите все отыгровки и команду с данными выбранного человека. Проверьте их перед подтверждением.')
    else
        local kind,changed=studio:choice('Действие##case-kind',studio.caseKind or 'wanted',{{'wanted','Розыск'},{'wanted_list','Список преступников'},{'fine','Штраф'},{'mark','Пеленгация'}},ui)
        if changed then M.select(studio,kind)else studio.caseKind=kind end
        if kind=='wanted'or kind=='wanted_list'then wantedUi.form(studio,ui,data,callbacks,cfg)
        else
        if kind=='mark'and callbacks.caseRemoteTarget then
            studio.markRemoteId=studio:field('ID подключённого человека · можно в другом городе##mark-account','mark:account',studio.markRemoteId or'',12)
            if studio:button('Открыть пеленгацию для этого ID##mark-account-open',ui)then
                local ok,err=callbacks.caseRemoteTarget(tonumber(studio.markRemoteId));if not ok then notify(studio,err)end
            end
        end
        if studio:button('Новая форма##case-new',ui)then
            local f,err=callbacks.caseBegin(studio.caseKind)
            if f then
                studio.caseForm=f
                studio.caseStoredForms=studio.caseStoredForms or {};studio.caseStoredForms[f.kind]=f
                for key in pairs(studio.cache)do if key:match('^case%-form:')then studio.cache[key]=nil end end
            else notify(studio,err)end
        end
        local f=studio.caseForm
        if f then
            im.Separator();ui.text(preferences.names[f.kind]..' · '..f.target.name..' ['..f.target.id..']')
            ui.text('Шаг '..(f.stage=='identity'and '1 · Личность'or f.stage=='basis'and '2 · Основание и значение'or '3 · Предпросмотр'))
            local function field(label,key,size,multiline)
                f[key]=studio:field(label..'##case-'..key,'case-form:'..f.id..':'..key,f[key],size,multiline,multiline and 90 or nil)
            end
            local function question(label,key)
                local v,changed=studio:choice(label..'##case-'..key,f[key],{{'unknown','Не знаю'},{'yes','Да'},{'no','Нет'}},ui)
                if changed then f[key]=v end
            end
            if f.stage=='identity'then
                if f.kind~='fine'and cfg.allow_ooc then
                    f.mode=studio:choice((f.kind=='mark'and 'Ветка пеленгации'or 'Ветка розыска')..'##case-mode',f.mode,
                        {{'ic','IC · по RP-данным'},{'ooc',f.kind=='mark'and 'OOC · отдельная процедура'or 'OOC · функциональные звёзды'}},ui)
                end
                if f.mode=='ooc'then
                    ui.text('OOC-звёзды разрешены только для RP-пеленгации /setmark: нужен известный по RP номер и включённый телефон. Снимите звёзды сразу после пеленгации. Ник, ID и приметы не заменяют номер (6.9–6.17).')
                    f.ooc_ack=studio:check('Понимаю, что выбираю отдельную OOC-механику##case-ooc-ack',f.ooc_ack)
                end
                if f.kind=='mark'then
                    question('Телефон сейчас включён?', 'phone_active')
                    question('Номер известен вашему персонажу?', 'phone_known')
                    field('Известный IC-номер телефона','phone_number',512,false)
                    field('Откуда персонажу известен номер','phone_source',512,false)
                    ui.text('Для пеленгации нужен известный вашему персонажу телефон. Его нельзя получить из SA:MP ID или номера паспорта. Чтобы сохранить телефон для следующих процедур, запишите его в карточку человека.')
                    if studio:button('IC-сведения и телефон##case-identity-open',ui)then callbacks.openIdentity()end
                else
                    if f.identity_nonce then ui.text('Начальные сведения взяты из карточки, которую вы заполнили вручную. Они не извлечены из ответа сервера.')end
                    if f.kind=='fine'and cfg.fine_unmasked then question('На человеке маска?', 'mask')end
                    question('Вы видели паспорт этого человека?', 'passport_seen')
                    if f.passport_seen=='yes'then
                        field('IC-имя и фамилия из документа','ic_name',512,false)
                        field('Номер паспорта · если известен','passport_number',512,false)
                    elseif f.passport_seen=='no'then
                        if f.kind~='fine'or not cfg.fine_unmasked then question('На человеке маска?', 'mask')end
                        if f.mask=='yes'then question('Вы видели лицо до маски?', 'face_before')end
                        field('Известные вашему персонажу приметы','appearance',2048,true)
                    end
                end
                local branch,why=callbacks.caseBranch(f)
                if not branch then
                    local warning=f.kind~='mark'and f.mode=='ic'and f.mask=='yes'and f.face_before=='no'and f.passport_seen~='yes'
                    if warning then im.PushStyleColor(im.Col.Text,im.ImVec4(1,.36,.39,1));ui.push(function()im.PopStyleColor(1)end)end
                    ui.text(why);if warning then ui.finish()end
                end
                if studio:button('Далее · основание##case-next',ui)then local ok,err=callbacks.caseNext(f);if not ok then notify(studio,err)end end
            elseif f.stage=='basis'then
                if f.kind~='mark'then
                    field('Номер статьи · вручную','article',512,false);field('Часть статьи · вручную','part',256,false)
                    field('Точное основание для команды','basis',1024,false)
                    field(f.kind=='wanted'and 'Количество звёзд · вручную'or 'Сумма штрафа · вручную','amount',128,false)
                    ui.text('Укажите допустимое количество звёзд или сумму самостоятельно, сверившись с правилом. Статья и часть попадут в команду, только если в её шаблоне есть соответствующие переменные.')
                else
                    field('Основание и условия пеленгации','basis',1024,false)
                    ui.text('Команда может установить метку на карте. Проверьте её появление в игре. PA не подтверждает местонахождение человека и не выдаёт сопутствующий розыск автоматически.')
                end
                if studio:button('Проверить полный текст##case-preview',ui)then local ok,err=callbacks.caseNext(f);if not ok then notify(studio,err)end end
                if studio:button('Назад · личность##case-back-identity',ui)then f.stage='identity'end
            else
                local p,err=callbacks.casePreview(f)
                if not p then ui.text(err)
                else
                    local branchName=({passport='по паспортным данным',appearance='по известным приметам',ic='IC-пеленгация',ooc='OOC-процедура'})[p.branch]
                    ui.text('Ветка: '..branchName..(f.kind~='mark'and(' · значение: '..p.values.amount)or '')..' · основание: '..p.values.basis)
                    if f.kind=='mark'and f.mode=='ic'then ui.text('Номер: '..p.values.phone_number..' · источник: '..p.values.phone_source)end
                    for i,line in ipairs(p.lines)do ui.text(i..'. '..line)end
                    if p.warning then ui.text(p.warning)end
                    if p.ready and studio:button('Подтвердить выполнение##case-send',ui)then
                        local offer,why=callbacks.caseOffer(f)
                        if offer then studio.caseConfirm=offer else notify(studio,why)end
                    end
                    if studio:button('Создать отключённый черновик бинда##case-draft',ui)then
                        local ok,why=callbacks.caseDraft(f)
                        if not ok then notify(studio,why)end
                    end
                end
                if studio:button('Назад · основание##case-back-basis',ui)then f.stage='basis'end
            end
        end
        end
        local status=data.caseForms or {};studio:observeStatus('procedures',status.message,'procedures')
        if status.pending then ui.text('Процедура ожидает / выполняется в общей очереди. End или Esc — остановить остаток.')end
    end
    studio.caseDraft=cfg;studio:autoSettings('procedures',{'procedures'},cfg,'caseDraft');studio:autosaveHint(ui,'procedures');studio:drawNotice(ui)
end
return M

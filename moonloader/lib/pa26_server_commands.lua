-- Read-only transcription of the two in-game help screenshots supplied by the user.
-- Names/purposes are confirmed by the screenshots; argument order, ranks and responses are not.
local M={source='Игровая справка 20.10.2026 + скриншоты розыска и уточнения пользователя 23.10.2026'}
M.radioChoices={{'/r','/r · подразделение'},{'/f','/f · организация'},{'/d','/d · департамент'}}
M.commands={
    {'/invite','Принять в организацию'},{'/uninvite','Уволить из организации'},
    {'/fmenu','Информация о фракции'},{'/fmission','Задания фракции'},
    {'/r','Рация подразделения'},{'/rn','Рация подразделения (non-rp)'},
    {'/f','Рация организации'},{'/fn','Рация организации (non-rp)'},
    {'/su','Объявить в розыск'},{'/clear','Снять розыск'},
    {'/cuff','Надеть наручники'},{'/uncuff','Снять наручники'},
    {'/arrest','Посадить в тюрьму'},{'/push','Затолкать игрока в транспорт'},
    {'/m','Мегафон'},{'/find','Посмотреть онлайн фракции'},
    {'/takelic','Забрать лицензию на авто'},{'/skip','Выдать пропуск'},{'/unskip','Забрать пропуск'},
    {'/ud','Показать удостоверение'},{'/frisk','Обыскать игрока'},{'/take','Изъять вещи игрока'},
    {'/ticket','Выписать штраф игроку'},{'/fwarn','Выдать выговор'},{'/unmask','Снять маску с игрока'},
    {'/fwarnoff','Выдать выговор оффлайн'},{'/d','Чат департамента'},{'/taser','Использовать тайзер'},
    {'/division','Выдать дивизион'},{'/undivision','Забрать дивизион'},
    {'/black','Добавить в чёрный список'},{'/unblack','Убрать из чёрного списка'},{'/blackcheck','Проверить на наличие в чёрном списке'},
    {'/pt','Начать погоню'},{'/mark','/mark [текст] — Отправить запрос с текстом'},{'/unpt','Закончить погоню'},
    {'/break','Установить барьер'},{'/hold','Вести игрока за собой'},{'/unhold','Перестать вести игрока за собой'},
    {'/setmark','Приблизительное местонахождение разыскиваемого'},{'/wanted','Общий список преступников · без ID'}}
M.procedureHeads={wanted='/su',fine='/ticket',mark='/setmark'}
function M.find(name)for _,r in ipairs(M.commands)do if r[1]==name then return r end end end
function M.bindingWarnings(binding)
    local out,seen={},{}
    for line in ((binding.script or '')..'\n'):gmatch('(.-)\n')do
        local head=line:match('^%s*(/[%a%d_]+)');head=head and head:lower()
        if head=='/wanted'and line:match('^%s*/[Ww][Aa][Nn][Tt][Ee][Dd]%s+%S')and not seen[head]then
            seen[head]=true;out[#out+1]='/wanted показывает общий список без ID. Для выдачи розыска используйте помощник /su: ID, раздел, подпункт. Личный текст сохранён.'
        elseif (head=='/fine'or head=='/tazer')and not seen[head]then
            seen[head]=true;out[#out+1]='Проверьте '..head..': этой команды нет в предоставленной справке Exsellent. Личный текст не изменён; название и параметры нужно сверить в игре.'
        elseif(head=='/blacklist'or head=='/unblacklist')and not seen[head]then
            seen[head]=true;out[#out+1]='В справке сервера указаны /black и /unblack. Проверьте '..head..'; личный текст сохранён без замены.'
        elseif head=='/su'and not seen[head]then
            seen[head]=true;out[#out+1]='Шорткат /su: ID, номер раздела, номер подпункта. Это не звёзды и не статья УК/АК. Для проверок личности и отдельного итогового ДА/НЕТ используйте помощник розыска; обычный бинд отправляет свой текст.'
        end
    end
    return out
end
function M.audit(lib)
    local out={}
    if lib.taser.command~='/taser'then out[#out+1]='Тайзер: сохранено '..lib.taser.command..', в справке указан /taser. Сохранённое значение можно заменить явно кнопкой ниже.'end
    for _,kind in ipairs({'wanted','fine','mark'})do
        local raw=lib.procedures[kind..'_command'];local head=raw:match('^(/[%a%d_]+)')
        if head and head~=M.procedureHeads[kind]then out[#out+1]='Форма '..({wanted='розыска',fine='штрафа',mark='местонахождения'})[kind]..': '..head..'; в этой справке назначению соответствует '..M.procedureHeads[kind]..'. Проверьте контракт.'end
    end
    for _,b in ipairs(lib.bindings)do
        if b.enabled then
            local seen={}
            for line in(b.script..'\n'):gmatch('(.-)\n')do
                local head=line:match('^%s*(/[%a%d_]+)')
                if(head=='/fine'or head=='/tazer')and not seen[head]then
                    out[#out+1]='Бинд «'..b.name..'»: '..head..' отсутствует в показанном списке. Аргументы и назначение требуют проверки; автозамены нет.';seen[head]=true
                end
            end
            for _,warning in ipairs(M.bindingWarnings(b))do out[#out+1]='Бинд «'..b.name..'»: '..warning end
            if b.command=='su'or b.command=='wanted'then out[#out+1]='Бинд «'..b.name..'»: локальное имя /'..b.command..' занято помощником. Бинд сохранён; назначьте ему своё имя или клавишу.'end
        end
    end
    return out
end
function M.draw(s,ui,data,callbacks,referenceOnly)
    s.currentNoticeScope='commands';s:settingsHeading(ui,'Команды сервера · сверка')
    ui.text(M.source)
    ui.text('Для /su подтверждены ID, раздел и подпункт; /su ID открывает меню, /wanted без ID — общий список. Аргументы остальных команд, ограничения ранга и дальности проверяются отдельно. Отправок из этой страницы нет.')
    ui.text('/find — онлайн фракции; /mark — запрос; /setmark — приблизительное место разыскиваемого, с соблюдением RP-пеленгации. /pt — серверная метка погони; /unpt — её завершение. Наш доклад о погоне сам эти команды не вызывает.')
    s:settingsHeading(ui,'Сохранённые настройки')
    for _,line in ipairs(M.audit(s.lib))do ui.text(line)end
    ui.text('Канал докладов сейчас: '..s.lib.alerts.channel..'. /r — подразделение, /f — организация, /d — департамент. Выбор меняется в настройках связи.')
    if s.lib.taser.command~='/taser'and s:button('Взять имя /taser из справки##server-apply-taser',ui)then
        local model=require 'pa26_bindings';local draft=s.taserDraft or model.copy(s.lib.taser);draft.command='/taser'
        s.taserDraft=draft;s:clearPreferenceCache('taser:mode:command');s:autoSettings('taser',{'taser'},draft,'taserDraft')
        s:notify('Имя команды изменено. Режим тайзера и ответы сервера проверьте отдельно.','commands',false,'info')
    end
    ui.text('Названия процедур: розыск — /su, штраф — /ticket, местонахождение — /setmark. Неизвестные аргументы остаются выключенными до проверки.')
    for _,row in ipairs({{'wanted','Открыть форму розыска'},{'fine','Открыть форму штрафа'},{'mark','Открыть форму местонахождения'}})do
        if s:button(row[2]..'##server-procedure-'..row[1],ui)then callbacks.openProcedures(row[1])end
    end
    s:settingsHeading(ui,'Точный список из справки')
    for _,row in ipairs(M.commands)do ui.text(row[1]..' — '..row[2])end
    if not referenceOnly then require('pa26_manual_actions').draw(s,ui)end
    s:drawNotice(ui)
end
return M

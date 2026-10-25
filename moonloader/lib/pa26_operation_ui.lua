local model=require 'pa26_bindings'
local settings=require 'pa26_operation_settings'
local operations=require 'pa26_operations'
local M={}
local function label(s)return tostring(s):gsub('##','# #')end
local function child(studio,ui,id,width,height,body)
    local im=studio.imgui
    local visible=im.BeginChild(id,im.ImVec2(width,height),true,im.WindowFlags.AlwaysUseWindowPadding)
    ui.push(function()im.EndChild()end)
    if visible then body()end
    ui.finish()
end
function M.draw(studio,ui,data,callbacks)
    local im=studio.imgui;local view=data.operations or {rows={},totals={}}
    studio.currentNoticeScope='operations';studio.preferenceContext=true
    studio:settingsHeading(ui,'История служебных действий','Здесь отдельно видны введённая команда, её отправка и ваша отметка о результате. Ответы Exsellent пока не распознаются автоматически.','operations-source')
    studio.operationPage=studio:choice('Журнал действий##operations-page',studio.operationPage or 'history',{{'history','История'},{'settings','Настройки'}},ui)
    if studio.operationPage=='settings'then
        local cfg=studio.operationDraft or model.copy(studio.lib.operations)
        for _,row in ipairs({{'enabled','Наблюдать служебные команды'},{'manual','Команды, введённые вручную'},
            {'binder','Команды биндов, процедур и быстрых действий'},{'demo','Сохранять демонстрации отдельно'},
            {'capture_chat','Сохранять контекст чата после команды'}})do
            local value,changed=studio:check(row[2]..'##operations-setting-'..row[1],cfg[row[1]])
            if changed then cfg[row[1]]=value end
        end
        for _,row in ipairs({{'timeout_ms','Срок ожидания оценки, с',1000},{'confirm_ms','Время действия подтверждения, с',1000},{'history_limit','Сколько записей хранить',1},
            {'chat_window_ms','Собирать чат после команды, с',1000},{'chat_limit','Строк чата на команду',1}})do
            local value=im.new.int(cfg[row[1]]/row[3])
            if im.InputInt(row[2]..'##operations-setting-'..row[1],value)then cfg[row[1]]=value[0]*row[3]end
        end
        ui.text('Ожидание результата: 1–3600 секунд; время на подтверждение: 1–300 секунд; история: 20–500 записей. Без вашей отметки результат останется неизвестным. Уменьшение истории удалит лишние старые записи — при необходимости сначала экспортируйте их.')
        ui.text('Лимит записей задаёт максимальную длину истории. Сам файл ограничен 1 МБ, поэтому длинные команды и пояснения могут сократить её. Новые записи сохраняются первыми.')
        studio:settingsHeading(ui,'Контекст чата для настройки сервера',
            'По желанию в последнюю реальную запись попадут показанные строки чата за 1–120 с, максимум 1–20 строк. Это соседние сообщения, включая реплики игроков; связи с командой, успеха и паспортных данных PA из них не выводит. Скрытые фильтрами сообщения не сохраняются. Для /help добавьте help в список команд. Экспорт остаётся локальным.','operations-chat-context')
        local raw=studio:field('Наблюдаемые команды · одно имя на строку##operations-commands','operations-commands',table.concat(cfg.commands,'\n'),4097,true,160)
        local commands,err=settings.parseCommands(raw)
        if err then ui.text(err)else cfg.commands=commands end
        ui.text('Впишите имя без /, ID и аргументов, например cuff или ticket. Журнал только наблюдает за вводом: он не меняет и не повторяет команду.')
        ui.text('Деморежим защищает отправки из сценариев PA. Команды, которые вы сами вводите в игровой чат, выполняются как обычно; журнал лишь отмечает попытку.')
        studio.operationDraft=cfg
        if not err then studio:autoSettings('operations',{'operations'},cfg,'operationDraft')end
        studio:autosaveHint(ui,'operations');studio:drawNotice(ui);return
    end
    local totals=view.totals
    ui.text('В сохранённой истории: передач клиенту '..(totals.client or 0)..' · ручных попыток '..(totals.observed or 0)..' · демо '..(totals.preview or 0))
    ui.text('Ваши оценки: успех '..(totals.success or 0)..' · отказ '..(totals.failure or 0)..' · неизвестно '..(totals.unknown or 0)..' · без оценки '..(totals.unresolved or 0))
    ui.text('Это журнал команд с вашими отметками о результате. Его записи не складываются со счётчиками патруля или биндов.')
    if not view.enabled then ui.text('Наблюдение выключено. Историю можно читать и уточнять; новые команды сейчас не добавляются.')end
    local search=studio:field('ПОИСК: команда, текст или человек##operations-search','operations-search','',1024)
    local query=model.casefold(search)
    studio.operationFilter=studio:choice('Показать##operations-filter',studio.operationFilter or 'all',{{'all','Все'},{'unresolved','Без оценки'},{'manual','Мои оценки'},{'demo','Демо'}},ui)
    local rows={};local filter=studio.operationFilter
    for i=#view.rows,1,-1 do
        local r=view.rows[i];local parts={r.command,r.text,r.target and r.target.name or '',r.result_note,r.binding_name}
        for _,m in ipairs(r.chat or {})do parts[#parts+1]=m.text end
        local text=table.concat(parts,' ')
        if (filter=='all'or filter=='demo'and r.demo or filter=='manual'and r.source=='manual'or filter=='unresolved'and not r.demo and r.source=='none')and
            (query==''or model.casefold(text):find(query,1,true))then rows[#rows+1]=r end
    end
    local searchKey=filter..'\0'..query
    if studio.operationSearchKey~=searchKey then studio.operationSearchKey=searchKey;studio.operationListPage=1 end
    local pages=math.max(1,math.ceil(#rows/12));studio.operationListPage=math.min(pages,studio.operationListPage or 1)
    ui.text('Страница '..studio.operationListPage..' / '..pages..' · найдено '..#rows)
    if im.Button('Назад##operations-prev')then studio.operationListPage=math.max(1,studio.operationListPage-1)end
    im.SameLine();if im.Button('Далее##operations-next')then studio.operationListPage=math.min(pages,studio.operationListPage+1)end
    im.SameLine();if im.Button('Экспорт истории##operations-export')then
        local ok,err=callbacks.operationExport();if not ok then studio:notify(err,'operations',false)end
    end
    local chosen
    for _,r in ipairs(rows)do if r.id==studio.operationSelected then chosen=r end end
    local width=im.GetContentRegionAvail().x;local wide=width>=760
    local height=math.max(260,im.GetContentRegionAvail().y-8)
    local listWidth=wide and math.min(400,math.max(240,width*.38))or width
    child(studio,ui,'##operations-list',listWidth,wide and height or math.min(280,height),function()
        if #rows==0 then ui.text('Подходящих действий пока нет. Настройки находятся сверху.')end
        for i=(studio.operationListPage-1)*12+1,math.min(#rows,studio.operationListPage*12)do
            local r=rows[i];local active=studio.operationSelected==r.id
            if active then
                im.PushStyleColor(im.Col.Button,im.ImVec4(.05,.40,.56,.95));ui.push(function()im.PopStyleColor(1)end)
            end
            if studio:button(label('#'..r.id..' · /'..r.command..' · '..r.date)..'##operation-row-'..r.id,ui)then
                studio.operationSelected=r.id;chosen=r
            end
            if active then ui.finish()end
            ui.text(operations.statusNames[r.status]);im.Separator()
        end
    end)
    if wide then im.SameLine()end
    child(studio,ui,'##operations-detail',wide and math.max(1,width-listWidth-12)or width,height,function()
        if not chosen then ui.text('Выберите действие в списке. Здесь будут команда, источник и ручная оценка.');return end
        ui.text('Действие #'..chosen.id..' · '..chosen.date)
        ui.text(operations.transportNames[chosen.transport]..' · '..operations.originNames[chosen.origin])
        ui.text('Цель на момент команды: '..(chosen.target and(chosen.target.name..' ['..chosen.target.id..']')or 'Не установлена. Аргументы ручной команды PA не угадывает.'))
        if chosen.binding_name~=''then ui.text('Сценарий: '..chosen.binding_name)end
        ui.text(chosen.text);im.Separator();ui.text('Результат: '..operations.statusNames[chosen.status])
        if chosen.result_note~=''then ui.text(chosen.result_note)end
        if chosen.resolved_at~=''then ui.text('Оценка изменена: '..chosen.resolved_at)end
        if chosen.chat and #chosen.chat>0 then
            im.Separator();ui.text('Сообщения чата после команды · для самостоятельной проверки')
            for _,m in ipairs(chosen.chat)do ui.text('+'..string.format('%.1f',m.after_ms/1000)..' с · '..m.text)end
            im.Separator()
        end
        if chosen.demo then ui.text('Демонстрацию нельзя отметить как настоящий успех или отказ.');return end
        if studio.operationOwner~=chosen.id then
            studio.operationOwner=chosen.id;studio.cache['operation-result-note']=nil
            studio.operationOutcome=({manual_success='success',manual_failure='failure',manual_unknown='unknown'})[chosen.status]or 'unknown'
        end
        studio.operationOutcome=studio:choice('Какой результат вы установили?##operation-outcome',studio.operationOutcome,{{'success','Успех'},{'failure','Отказ'},{'unknown','Неизвестно'}},ui)
        local explanation=studio:field('По чему вы установили результат?##operation-note','operation-result-note',chosen.source=='manual'and chosen.result_note or '',2049,true,110)
        ui.text('Опишите, что произошло в игре или что ответил сервер. Оценка сохранится как ваша ручная отметка. PA не повторит команду и не отправит доклад.')
        if studio:button('Проверить и сохранить оценку##operation-review',ui)then
            local p,err=callbacks.operationOffer(chosen.id,studio.operationOutcome,explanation)
            if p then studio.operationConfirm=p else studio:notify(err,'operations',false)end
        end
    end)
    studio:observeStatus('operations',view.message,'operations')
    if view.sizeLimited then ui.text('Глубина истории ограничена размером файла. Старые записи с длинными пояснениями уступили место новым.')end
    studio:drawNotice(ui)
end
return M

local model=require 'pa26_bindings'
local core=require 'pa26_core'
local M={}
function M.draw(s,ui,updater,callbacks,author)
    local im=s.imgui;s.currentUi=ui;s.preferenceContext=true
    s:settingsHeading(ui,'Обновления Police Assistant')
    ui.text('Установлена PA '..core.VERSION)
    local job=s.autosaves and s.autosaves.updates
    local cfg=model.copy(job and job.value or s.lib.settings.updates)
    cfg.enabled=s:check('Включить проверку и загрузку обновлений##updates-enabled',cfg.enabled)
    cfg.repository=s:field('GitHub: владелец/репозиторий##updates-repository','updates:repository',cfg.repository,256)
    ui.text('Официальный источник: VIBAG-bg/Police-Assistant. Если поле очистить, запросов к GitHub нет. Используются публичные GitHub Releases и пакет pa26-update.zip; пароли и токены сюда не вводятся.')
    cfg.check_on_start=s:check('Проверять новую версию при входе##updates-on-start',cfg.check_on_start)
    cfg.include_prerelease=s:check('Предлагать также предварительные выпуски##updates-prerelease',cfg.include_prerelease)
    cfg.show_progress_window=s:check('Показывать отдельное окно установки##updates-progress-window',cfg.show_progress_window)
    ui.text('Окно на русском с зелёным прогрессом остаётся после выхода из GTA. Возвращайтесь в игру после «Готово — можно запускать GTA». Его можно свернуть; до результата закрытие окна отключено. При раннем запуске GTA помощник ждёт её закрытия и продолжает установку.')
    local n=im.new.int(cfg.timeout_seconds)
    if im.SliderInt('Ожидание сети, с##updates-timeout',n,1,120)then cfg.timeout_seconds=n[0]end
    s:autoSettings('updates',{'settings','updates'},cfg)
    s:autosaveHint(ui,'updates')
    ui.text('Загрузка запускается только вашей кнопкой. Установка начинается после полного выхода из GTA. Личные JSON/INI, бинды, заметки и журналы не заменяются; перед установкой их актуальные копии сохраняются отдельно вместе с предыдущими файлами PA. Резервные копии автоматически не удаляются.')
    if author then
        s:settingsHeading(ui,'Авторские бинды и настройки')
        ui.text('Отдельные наборы из того же GitHub. Загрузка не заменяет данные: сначала появится окно ДА / НЕТ. Профиль, контакты, заметки и журналы сохраняются. Перед заменой создаётся проверенная копия; после применения перезапустится только PA.')
        if s:button('Обновить бинд-лист с GitHub##author-binds',ui)then author:start('binds')end
        if s:button('Обновить настройки с GitHub##author-settings',ui)then author:start('settings')end
        ui.text(author.status)
    end
    if not updater then ui.text('Помощник обновления недоступен.');return end
    local labels={idle='Готов к проверке',unavailable='Помощник недоступен',checking='Проверка GitHub',available='Новая версия найдена',
        current='Новая подходящая версия не найдена',downloading='Скачивание и проверка пакета',waiting='Пакет готов · ожидается выход из GTA',
        installed='Последнее обновление установлено',rolled_back='Предыдущая версия восстановлена',cancelled='Обновление отменено',error='Обновление остановлено'}
    ui.text('Состояние: '..(labels[updater.phase]or'Проверка состояния'))
    if not updater.job then
        if s:button('Проверить обновления##updates-check',ui)then
            s:flushAutosave(callbacks,true)
            if not(s.autosaves and s.autosaves.updates)then updater:check()end
        end
        if updater.candidate then
            ui.text('Версия: '..updater.candidate.version)
            ui.text('Изменения из GitHub · описание автора выпуска:')
            ui.text((updater.candidate.notes or''):gsub('[%z\1-\8\11\12\14-\31]',' '))
            if s:button('Скачать и установить после выхода##updates-download',ui)then
                s:flushAutosave(callbacks,true)
                if not(s.autosaves and s.autosaves.updates)then updater:download()end
            end
        end
    elseif updater.job.mode=='Prepare'then
        if s:button('Отменить отложенное обновление##updates-cancel',ui)then updater:cancel()end
    end
    if updater.result and updater.result.message then ui.text(require('pa26_updater').message(updater.result.message))end
    if updater.env.platform and s:button('Открыть резервные копии и отчёты##updates-backups',ui)then
        local ok=pcall(updater.env.platform.openBackups,updater.env.platform)
        if not ok then s:notify('Не удалось открыть папку обновлений.','updates',false)end
    end
end
return M

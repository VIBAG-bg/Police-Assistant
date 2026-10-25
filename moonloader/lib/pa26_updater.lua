local core=require 'pa26_core'
local M={};local Updater={};Updater.__index=Updater
function M.defaults()return {enabled=true,repository='VIBAG-bg/Police-Assistant',check_on_start=false,include_prerelease=false,timeout_seconds=30}end
function M.validate(raw)
    local out=M.defaults();if raw==nil then return out end
    if type(raw)~='table'then return nil,'Неверные настройки обновления.'end
    for _,key in ipairs({'enabled','check_on_start','include_prerelease'})do if raw[key]~=nil then
        if type(raw[key])~='boolean'then return nil,'Неверный переключатель обновления.'end;out[key]=raw[key]end end
    local repo=raw.repository or''
    if type(repo)~='string'or #repo>140 or not core.validUtf8(repo)or repo:find('%c')then return nil,'Укажите GitHub: владелец/репозиторий.'end
    repo=repo:match('^%s*(.-)%s*$'):gsub('^https://github%.com/',''):gsub('/$','')
    if repo~=''then
        local owner,name=repo:match('^([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9][A-Za-z0-9_.-]*)$')
        if not owner or #owner>39 or #name>100 or name:sub(-4)=='.git'then return nil,'Укажите владелец/репозиторий без .git, токенов и дополнительных путей.'end
    end
    out.repository=repo;local n=raw.timeout_seconds or out.timeout_seconds
    if not core.finite(n)or n%1~=0 or n<1 or n>120 then return nil,'Ожидание сети: от 1 до 120 секунд.'end;out.timeout_seconds=n
    return out
end
local messages={
    ready='Готов к проверке обновлений.',checking='Проверяется наличие новой версии.',new_version='Новая версия найдена.',
    no_new_version='Новая подходящая версия не найдена.',downloading='Пакет скачивается и проверяется.',
    invalid_game_root='Не удалось определить папку игры.',invalid_repository='Укажите источник обновления в виде владелец/репозиторий.',
    launch_failed='Windows не запустила помощник обновления.',copy_worker='Не удалось подготовить помощник обновления.',
    worker_interrupted='Помощник обновления был остановлен до установки. Игровые и личные файлы не заменялись. Проверьте версию и повторите загрузку.',
    network_error='Не удалось соединиться с GitHub. Действующая версия сохранена.',network_timeout='GitHub не ответил вовремя. Повторите проверку позже.',
    http_403='GitHub ограничил запросы. Повторите позже.',http_404='Репозиторий или опубликованный выпуск не найден. Для этой версии нужны публичные GitHub Releases.',
    update_busy='Обновление уже проверяется или ожидает закрытия игры.',release_changed='Выпуск изменился после проверки. Проверьте обновления заново.',
    archive_hash_mismatch='Пакет загружен не полностью или повреждён. Установка не началась.',payload_hash_mismatch='Файлы пакета не прошли проверку. Установка не началась.',
    incompatible_package='Пакет несовместим с этой версией обновлятора или форматом личных данных. Нужна ручная установка.',
    bootstrap_update_requires_manual_install='Для изменения загрузчика нужна ручная установка. Личные данные не изменены.',
    cef_incompatible='Версия игрового чата отличается от поддерживаемой. Установка остановлена.',
    personal_data_changed='Личные файлы изменились во время установки. PA остановил обновление и сохраняет резервные копии.',
    close_wait_expired='Истекло ожидание закрытия GTA. Проверьте состояние обновления перед новым запуском.',
    downloaded_close_game='Обновление скачано и проверено. Закройте GTA и дождитесь завершения установки перед повторным запуском. Резервная копия актуальных личных файлов будет сделана после выхода.',
    close_game_to_recover='Закройте GTA: помощник восстановит согласованную версию PA из резервной копии.',
    update_installed='Обновление установлено и проверено. Личные файлы сохранены; резервная копия доступна в папке обновлений.',
    update_rolled_back='Обновление отменено; предыдущие файлы PA восстановлены. Личные файлы не заменялись. Резервная копия сохранена.',
    damaged_backup='Резервная копия не прошла проверку. PA остаётся приостановлен; сохранённые файлы и отчёт доступны для восстановления.',
    runtime_changed_during_recovery='После прерывания файлы PA изменились. Автоматический откат остановлен, чтобы не перезаписать эти изменения. Нужна проверка резервной копии.',
}
function M.message(code)return messages[code]or'Операция обновления остановлена. Личные файлы не подменяются. Подробности доступны в папке обновлений; при незавершённой замене PA будет приостановлен до восстановления.'end
local function signature(c)return table.concat({tostring(c.enabled),c.repository,tostring(c.include_prerelease),c.timeout_seconds},'|')end
function M.new(env)return setmetatable({env=env,phase=env.platform and'idle'or'unavailable',started=not env.platform,autoChecked=not env.platform},Updater)end
function Updater:notify(code,info)self.env.notify(M.message(code),info and'info'or'warning')end
function Updater:start(mode,candidate)
    local cfg,why=M.validate(self.env.settings());if not cfg then self.env.notify(why,'warning');return false end
    if self.job then return false end
    if mode~='Status'and(not cfg.enabled or cfg.repository=='')then self.env.notify('Источник обновления не настроен. Укажите репозиторий GitHub в настройках на этой странице.','warning');return false end
    if not self.env.platform then self:notify('invalid_game_root');return false end
    local request={product='police-assistant-2026',moonloader=self.env.platform.ml,repository=cfg.repository,
        include_prerelease=cfg.include_prerelease,timeout_seconds=cfg.timeout_seconds,approved=mode=='Prepare',candidate=candidate}
    local ok,text=pcall(self.env.encode,request);if not ok then self:notify('invalid_request');return false end
    local good,job,err=pcall(self.env.platform.start,self.env.platform,mode,text)
    if not good or not job then self:notify(err or'launch_failed');return false end
    self.job=job;self.job.at=self.env.now();self.job.signature=signature(cfg);self.phase=mode=='Prepare'and'downloading'or'checking';self.lastStatus=nil
    return true
end
function Updater:check()self.candidate=nil;return self:start('Check')end
function Updater:download()
    local cfg=M.validate(self.env.settings())
    if not self.candidate or not cfg or self.candidateSignature~=signature(cfg)then self.env.notify('Проверьте обновления заново перед скачиванием.','warning');return false end
    return self:start('Prepare',self.candidate)
end
function Updater:cancel()
    if not self.job or self.job.mode~='Prepare'then return false end
    local ok,good=pcall(self.env.platform.cancel,self.env.platform,self.job)
    if not ok or not good then self:notify('write_request');return false end
    return true
end
function Updater:tick()
    local now=self.env.now();if self.lastPoll and(core.elapsed(now,self.lastPoll)or 0)<250 then return end;self.lastPoll=now
    if not self.started then self.started=true;self:start('Status');return end
    if not self.job then
        local cfg=M.validate(self.env.settings())
        if not self.autoChecked and cfg and cfg.enabled and cfg.check_on_start and cfg.repository~=''then self.autoChecked=true;self:check()end
        return
    end
    local cfg=M.validate(self.env.settings())
    if self.job.mode~='Status'and cfg and signature(cfg)~=self.job.signature then
        if self.job.mode=='Prepare'then pcall(self.env.platform.cancel,self.env.platform,self.job)end
        self.job=nil;self.candidate=nil;self.phase='idle';self.env.notify('Настройки обновления изменились. Предыдущая заявка отменена.','info');return
    end
    local ok,raw=pcall(self.env.platform.poll,self.env.platform,self.job)
    if ok and type(raw)=='string'and raw~=self.lastStatus then
        local decoded,row=pcall(self.env.decode,raw)
        if decoded and type(row)=='table'and row.product=='police-assistant-2026'and row.moonloader==self.env.platform.ml and
            type(row.phase)=='string'and type(row.message)=='string'then
            self.lastStatus=raw;self.phase=row.phase;self.result=row
            local mode=self.job.mode
            if mode=='Status'and row.active_job==true then
                local good,job,request=pcall(self.env.platform.adopt,self.env.platform,row.job)
                local decoded,old=pcall(self.env.decode,request or'')
                local frozen=decoded and type(old)=='table'and M.validate(old)
                if not good or not job or not frozen then self:notify('invalid_request');self.job=nil;self.phase='error';return end
                self.job=job;job.at=now;job.signature=signature(frozen);mode='Prepare'
            end
            if row.phase=='available'then
                if type(row.details)~='table'or type(row.details.version)~='string'or type(row.details.sha256)~='string'or #row.details.sha256~=64 then self:notify('invalid_request')
                else self.candidate=row.details;self.candidateSignature=self.job.signature;self.env.notify('Доступна новая версия PA '..row.details.version..'. Откройте «Обновления PA», чтобы посмотреть изменения и скачать.','info')end
                self.job=nil
            elseif row.phase=='waiting'then
                local key=self.job.id..':'..row.message
                if self.waitNotice~=key then self.waitNotice=key;self:notify(row.message,true)end
            elseif row.phase=='current'then if mode~='Status'then self.env.notify('Новая подходящая версия не найдена.','info')end;self.job=nil
            elseif row.phase=='idle'then self.job=nil
            elseif row.phase=='error'or row.phase=='installed'or row.phase=='rolled_back'or row.phase=='cancelled'then
                if not(mode=='Status'and row.receipt_seen==true)then
                    if row.phase~='cancelled'then self:notify(row.message,row.phase~='error')else self.env.notify('Отложенное обновление отменено.','info')end
                    if self.env.platform.seen then pcall(self.env.platform.seen,self.env.platform,row.job)end
                end
                self.job=nil
            end
        end
    end
    if self.job then
        local age=core.elapsed(now,self.job.at);local cfg=M.validate(self.env.settings())
        local seconds=cfg and cfg.timeout_seconds or 30
        local deadline=self.job.mode=='Status'and 15000 or self.job.mode=='Check'and(seconds*2000+15000)or(seconds*7000+15000)
        if not age or self.phase~='waiting'and age>deadline then
            if self.job.mode=='Prepare'then pcall(self.env.platform.cancel,self.env.platform,self.job)end
            self:notify('network_timeout');self.job=nil;self.phase='error'
        end
    end
end
function Updater:label()
    return self.phase=='waiting'and'Обновление готово'or self.candidate and('Обновить PA · '..self.candidate.version)or'Обновления PA'
end
return M

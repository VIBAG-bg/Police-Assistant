local core=require 'pa26_core'
local shared=require 'pa26_patrol_settings'
local M={}
-- Editable examples, not claims that each report is mandatory under server rules.
M.catalog={
    {'pursuit_vehicle','Погоня за транспортом','{unit}: 10-57 VICTOR, {subject}. 10-20: {area}.',''},
    {'pursuit_foot','Пешая погоня','{unit}: 10-57 FOXTROT, {subject}. 10-20: {area}.',''},
    {'traffic_stop','Остановка транспорта','{unit}: остановка транспорта, {subject}. 10-20: {area}.',''},
    {'detention','Задержание','{unit}: задержан {subject}. Основание: {basis}.','cuff'},
    {'frisk','Досмотр','{unit}: досмотр {subject} завершён. 10-20: {area}.','frisk'},
    {'handover','Передача задержанного','{unit}: задержанный {subject} передан {destination}.',''},
    {'jail','Доставка в тюрьму','{unit}: {subject} доставлен в тюрьму. Основание: {basis}.','arrest'},
    {'force_used','Применение силы','{unit}: применена сила к {subject}. {details}. 10-20: {area}.',''},
    {'custom','Своё событие','{unit}: {details}. 10-20: {area}.',''},
}
M.variables=shared.copy(shared.variables)
for _,key in ipairs({'subject','basis','destination','details'})do M.variables[key]=true end
function M.defaults()
    local out={enabled=false,suggest_commands=true,require_patrol=true,attempt_ttl_ms=300000,duplicate_ms=5000,
        toast_enabled=true,toast_mode='confirm',toast_ms=10000,toast_title='Проверить результат команды',
        toast_template='Попытка {command}. Результат сервера ещё не подтверждён. Открыть проверку события «{event}»?',
        toast_hint='Предложение само ничего не записывает и не отправляет в рацию.',
        remind_clear=true,clear_reminder='Проверьте, нужно ли снять IC-розыск после заключения по действующей процедуре. PA не снимает звёзды автоматически.',
        followup_enabled=true,rights_reminder_enabled=true,force_reminder_enabled=true,followup_ms=20000,followup_ttl_ms=300000,followup_snooze_ms=30000,followup_limit=4,
        followup_title='Проверка после события',
        rights_reminder='Когда обстановка позволяет, проверьте, разъяснили ли вы человеку причину задержания и его права. Одного нажатия команды для этого недостаточно.',
        force_reminder='Когда безопасно, проверьте состояние пострадавшего и необходимость первой/медицинской помощи. Применение огнестрельного оружия нужно документировать и оформить рапорт; специальные средства при травме — зафиксировать и проверить. PA не устанавливает травму и не подтверждает сдачу рапорта.',
        open_shortcut={key=0,ctrl=false,alt=false,shift=false},events={}}
    for _,row in ipairs(M.catalog)do out.events[row[1]]={enabled=true,name=row[2],template=row[3],channel='/r',
        command=row[4],suggest=row[4]~='',require_target=row[1]~='custom'}end
    return out
end
M.noticeVariables={command=true,event=true,origin=true,target=true}
function M.noticeText(raw,template)
    if type(raw)~='string'or #raw>1024 or not core.validUtf8(raw)or raw:find('[%z\1-\8\11\12\14-\31\127]')or raw:match('^%s*$')then
        return nil,'Нужен непустой текст уведомления до 1024 байт UTF-8.'
    end
    if template then
        local rest=raw:gsub('{([a-z_]+)}',function(k)return M.noticeVariables[k]and ''or '{'end)
        if rest:find('[{}]')then return nil,'Переменные уведомления: {command}, {event}, {origin}, {target}.'end
    end
    return raw
end
function M.noticePreview(template,values)
    values=values or {}
    return template:gsub('{([a-z_]+)}',function(k)return values[k]or '['..k..']'end)
end
function M.template(raw)
    local v=shared.text(raw,768)
    if not v or v==''or v:match('^[/@]')then return nil,'Нужна реплика без команды и перевода строки.'end
    local rest=v:gsub('{([a-z_]+)}',function(k)return M.variables[k]and ''or '{'end)
    if rest:find('[{}]')then return nil,'Неизвестная переменная события.'end
    return v
end
function M.validate(raw)
    local out=M.defaults();if raw==nil then return out end
    if type(raw)~='table'then return nil,'Неверные настройки событий.'end
    for _,k in ipairs({'enabled','suggest_commands','require_patrol','remind_clear','toast_enabled','followup_enabled','rights_reminder_enabled','force_reminder_enabled'})do
        if raw[k]~=nil then if type(raw[k])~='boolean'then return nil,'Неверный переключатель события.'end;out[k]=raw[k]end
    end
    for _,row in ipairs({{'attempt_ttl_ms',1000,1800000},{'duplicate_ms',1000,30000},{'toast_ms',1000,30000},
        {'followup_ms',1000,60000},{'followup_ttl_ms',1000,1800000},{'followup_snooze_ms',1000,300000},{'followup_limit',1,10}})do
        local n=raw[row[1]];if n==nil then n=out[row[1]]end
        if not shared.integer(n,row[2],row[3])then return nil,'Неверный интервал событий.'end;out[row[1]]=n
    end
    if out.followup_ttl_ms<out.followup_ms or out.followup_snooze_ms>out.followup_ttl_ms then return nil,'Срок напоминания не должен быть короче показа и отсрочки.'end
    for _,key in ipairs({'followup_title','rights_reminder','force_reminder'})do
        local value=raw[key];if value==nil then value=out[key]end
        local err;out[key],err=M.noticeText(value,false);if not out[key]then return nil,err end
    end
    if #out.followup_title>120 or out.followup_title:find('[\r\n]')then return nil,'Заголовок напоминания: одна короткая строка до 120 байт UTF-8.'end
    if raw.toast_mode~=nil then out.toast_mode=raw.toast_mode end
    if out.toast_mode~='confirm'and out.toast_mode~='buttons'then return nil,'Выберите Y/N или кнопки уведомления.'end
    for _,key in ipairs({'toast_title','toast_template','toast_hint'})do
        local value=raw[key];if value==nil then value=out[key]end
        local err;out[key],err=M.noticeText(value,key=='toast_template');if not out[key]then return nil,err end
    end
    out.clear_reminder=shared.text(raw.clear_reminder or out.clear_reminder,768);if not out.clear_reminder then return nil,'Неверное напоминание об IC-розыске.'end
    local key=raw.open_shortcut or out.open_shortcut
    if type(key)~='table'or not shared.integer(key.key,0,254)or type(key.ctrl)~='boolean'or type(key.alt)~='boolean'or type(key.shift)~='boolean'then return nil,'Неверная клавиша событий.'end
    out.open_shortcut=shared.copy(key)
    if raw.events~=nil then
        if type(raw.events)~='table'then return nil,'Неверный каталог событий.'end
        for _,row in ipairs(M.catalog)do
            local r=raw.events[row[1]]or out.events[row[1]];local v={}
            if type(r)~='table'then return nil,'Повреждён вид события.'end
            for _,k in ipairs({'enabled','suggest','require_target'})do if type(r[k])~='boolean'then return nil,'Неверное условие события.'end;v[k]=r[k]end
            v.name=shared.text(r.name,120);v.command=shared.text(r.command,32)
            if not v.name or v.name==''or not v.command or(v.command~=''and not v.command:match('^[a-z][a-z0-9_]*$'))or v.command:match('^pa26')then return nil,'Проверьте название события и имя серверной команды без /.'end
            v.channel=r.channel;if v.channel~='/r'and v.channel~='/f'and v.channel~='/d'then return nil,'Канал события: /r, /f или /d.'end
            local err;v.template,err=M.template(r.template);if not v.template then return nil,err end
            out.events[row[1]]=v
        end
    end
    return out
end
return M

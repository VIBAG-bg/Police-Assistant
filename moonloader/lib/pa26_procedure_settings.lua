-- Personal procedure drafts. Server command contracts are empty until verified.
local shared=require 'pa26_patrol_settings'
local core=require 'pa26_core'
local M={}
M.variables={id=true,amount=true,basis=true,article=true,part=true,ic_name=true,passport_number=true,appearance=true,phone_number=true,phone_source=true,
    device=true,game_reason=true,game_group=true,game_stars=true,game_category=true,game_item=true,ooc_purpose=true,facts=true}
M.names={wanted='Розыск',wanted_list='Список преступников',fine='Штраф',mark='Пеленгация'}
M.oocReasons={{'tracking','Только RP-пеленгация через /setmark · 6.9–6.17'}}
M.oocNotes={tracking='Только для /setmark: известный по RP номер, включённый телефон и отыгранная пеленгация. Снять OOC-звёзды сразу после завершения. Для /pt, Alcatraz и других механик OOC-звёзды запрещены (6.9–6.17, редакция 21.10.2026).'}
M.rpFields={{'wanted_passport_rp','Розыск · установленное имя из паспорта'},{'wanted_appearance_rp','Розыск · известные приметы'},
    {'wanted_passport_number_rp','Розыск · дополнение с номером паспорта'},
    {'wanted_generic_appearance_rp','Розыск · общая отыгровка по приметам без ручного описания'},
    {'wanted_traits_rp','Розыск · /todo с введёнными приметами'},
    {'wanted_ooc_rp','Функциональные OOC-звёзды'},{'wanted_car_intro_rp','Розыск в машине · начало'},
    {'wanted_foot_intro_rp','Розыск пешком · начало'},{'wanted_list_rp','Просмотр списка преступников'},{'fine_passport_rp','Штраф · паспортные данные'},
    {'fine_appearance_rp','Штраф · данные без паспорта'},{'mark_ic_rp','Пеленгация · известный IC-номер'},{'mark_ooc_rp','Пеленгация · отдельная OOC-процедура'}}
function M.defaults()
    local out={enabled=false,wanted_enabled=true,fine_enabled=true,mark_enabled=true,allow_ooc=true,fine_unmasked=true,delay_ms=1500,
        wanted_assistant_enabled=true,wanted_intercept=true,wanted_require_life_ack=true,
        wanted_allow_remote=true,wanted_autofill_passport=true,wanted_id_as_passport=true,wanted_suggest_ooc=true,wanted_each_trait=false,
        wanted_passport_number_rp="/do В карточке ориентировки указан номер паспорта: {passport_number}.",
        wanted_generic_appearance_rp="/me {gender:зажал|зажала} кнопку тангенты рации и {gender:передал|передала} диспетчеру приметы подозреваемого.\n/do Диспетчер составил ориентировку на розыск по причине: {game_reason}.",
        wanted_traits_rp="/todo Диспетчер, приметы подозреваемого: {appearance}*зажав кнопку тангенты рации.\n/do В ориентировке диспетчера указана причина: {game_reason}.",
        wanted_send_mode='direct',wanted_direct_command='/su {id} {game_category} {game_item}',wanted_open_command='/su {id}',wanted_list_command='/wanted',
        wanted_reminder_enabled=true,wanted_reminder_delay_ms=15000,wanted_reminder_snooze_ms=60000,wanted_reminder_show_ms=20000,
        wanted_reminder_title='Проверьте OOC-звёзды',
        wanted_reminder_text='Проверьте результат серверного выбора. Если вы выдали OOC-звёзды, снимите их вручную после нужного этапа. PA не подтверждает выдачу и не отправляет /clear.',
        wanted_command='',fine_command='',mark_command='',wanted_verified=false,fine_verified=false,mark_verified=false,
        wanted_source='',fine_source='',mark_source='',
        wanted_passport_rp="/me {gender:сверил|сверила} паспортные данные на имя {ic_name} и {gender:передал|передала} ориентировку диспетчеру.\n/do В базе данных зафиксирован запрос на розыск по причине: {game_reason}.",
        wanted_appearance_rp='/me зажал кнопку тангенты рации и передал диспетчеру известные приметы подозреваемого: {appearance}.',
        wanted_ooc_rp="/me {gender:ввёл|ввела} известный номер {phone_number} в служебный терминал и {gender:запросил|запросила} пеленгацию сигнала.\n/do На экране терминала отображается расчёт сектора по сигналу сотовой вышки.",
        wanted_car_intro_rp="/me {gender:повернулся|повернулась} к бортовому компьютеру крузера, {gender:авторизовался|авторизовалась} в базе и {gender:открыл|открыла} карточку ориентировки.",
        wanted_foot_intro_rp="/me {gender:снял|сняла} служебный КПК с пояса, {gender:разблокировал|разблокировала} терминал и {gender:открыл|открыла} карточку ориентировки.",
        wanted_list_rp='/me открыв {device}, просмотрел список разыскиваемых.',
        fine_passport_rp="/me {gender:сверил|сверила} паспортные данные {ic_name} и {gender:заполнил|заполнила} бланк постановления о штрафе.",
        fine_appearance_rp="/me {gender:уточнил|уточнила} установочные данные нарушителя и {gender:оформил|оформила} бланк постановления о штрафе.",
        mark_ic_rp='/me ввёл известный номер {phone_number} в бортовой терминал и отправил запрос.\n/do На экране терминала отображается запрос на определение местоположения.',
        mark_ooc_rp='/me открыв служебный терминал, отправил запрос на определение местоположения.\n/do Запрос передан; на экране терминала отображается ожидание ответа.'}
    for _,kind in ipairs({'wanted','fine','mark'})do
        out[kind..'_wheel']=true;out[kind..'_quick']=true;out[kind..'_label']=M.names[kind]
        out[kind..'_shortcut']={key=0,ctrl=false,alt=false,shift=false}
    end
    return out
end
local function placeholders(text,genderAllowed)
    local rest=(genderAllowed and core.stripGender(text)or text):gsub('{([a-z_]+)}',function(k)return M.variables[k]and ''or '{'end)
    return not rest:find('[{}]')
end
function M.command(raw,kind,verified)
    local v=shared.text(raw,512)
    if not v then return nil,'Команда должна быть одной строкой.'end
    if v==''then return not verified and ''or nil,'Сначала укажите точную команду из /help.'end
    local head=v:match('^/([a-z][a-z0-9_]*)%s')or v:match('^/([a-z][a-z0-9_]*)$')
    if not head or head:match('^pa26')or kind=='wanted'and head~='su'or kind=='mark'and head~='setmark'or not placeholders(v)then return nil,'Проверьте имя серверной команды и переменные.'end
    if kind=='mark'then
        local args=v:match('^/%S+%s+(.+)$')
        if args and not v:find('{id}',1,true)and not v:find('{phone_number}',1,true)then
            return nil,'Для цели используйте {id} или {phone_number}, без постоянного ID / номера. Если команда открывает диалог без аргументов, оставьте только её имя.'
        end
    elseif not v:find('{id}',1,true)or not v:find('{amount}',1,true)or not v:find('{basis}',1,true)then return nil,'В точном контракте нужны {id}, {amount} и {basis}; не подставляйте постоянный ID или сумму.'end
    return v
end
function M.rp(raw)
    if type(raw)~='string'or #raw>4096 then return nil,'Слишком длинная RP-заготовка.'end
    local count=0
    for line in(raw..'\n'):gmatch('(.-)\n')do
        line=line:gsub('\r$',''):match('^%s*(.-)%s*$')
        if line~=''then
            count=count+1
            if not shared.text(line,768)or not(line:match('^/me%s+')or line:match('^/do%s+')or line:match('^/todo%s+[^*]+%*[^*]+$'))or not placeholders(line,true)then return nil,'RP-строки начинаются с /me, /do либо /todo текст*действие и используют известные переменные.'end
        end
    end
    if count==0 or count>8 then return nil,'В процедуре нужно от 1 до 8 RP-строк.'end
    return raw
end
function M.validate(raw)
    local out=M.defaults();if raw==nil then return out end
    if type(raw)~='table'then return nil,'Неверные настройки процедур.'end
    for _,k in ipairs({'enabled','wanted_enabled','fine_enabled','mark_enabled','allow_ooc','fine_unmasked','wanted_verified','fine_verified','mark_verified',
        'wanted_assistant_enabled','wanted_intercept','wanted_require_life_ack','wanted_reminder_enabled','wanted_allow_remote','wanted_autofill_passport','wanted_id_as_passport','wanted_suggest_ooc','wanted_each_trait'})do
        if raw[k]~=nil then if type(raw[k])~='boolean'then return nil,'Неверный переключатель процедуры.'end;out[k]=raw[k]end
    end
    local n=raw.delay_ms;if n==nil then n=out.delay_ms end
    if not shared.integer(n,1000,10000)then return nil,'Пауза процедуры: от 1000 до 10000 мс.'end;out.delay_ms=n
    if raw.wanted_send_mode~=nil then
        if raw.wanted_send_mode~='direct'and raw.wanted_send_mode~='menu'then return nil,'Выберите способ выдачи розыска.'end
        out.wanted_send_mode=raw.wanted_send_mode
    end
    if raw.wanted_direct_command and raw.wanted_direct_command~='/su {id} {game_category} {game_item}'then return nil,'Шорткат /su принимает ID, номер раздела и номер подпункта; количество звёзд аргументом не является.'end
    for _,key in ipairs({'wanted_open_command','wanted_list_command'})do
        local value=raw[key]or out[key]
        if value~=(key=='wanted_open_command'and '/su {id}'or '/wanted')then
            return nil,'Для этой версии подтверждены только /su {id} и /wanted без дополнительных аргументов.'
        end
        out[key]=value
    end
    for _,spec in ipairs({{'wanted_reminder_delay_ms',1000,300000},{'wanted_reminder_snooze_ms',1000,600000},{'wanted_reminder_show_ms',1000,60000}})do
        local value=raw[spec[1]];if value==nil then value=out[spec[1]]end
        if not shared.integer(value,spec[2],spec[3])then return nil,'Проверьте время напоминания об OOC-звёздах.'end;out[spec[1]]=value
    end
    out.wanted_reminder_title=shared.text(raw.wanted_reminder_title or out.wanted_reminder_title,120)
    local reminder=raw.wanted_reminder_text or out.wanted_reminder_text
    if type(reminder)=='string'then reminder=reminder:gsub('\r\n','\n')end
    if not out.wanted_reminder_title or out.wanted_reminder_title==''or type(reminder)~='string'or #reminder>1400 or
        not core.validUtf8(reminder)or reminder:gsub('\n',''):find('%c')or not reminder:find('%S')then
        return nil,'Укажите заголовок и текст напоминания об OOC-звёздах; допускаются обычные переносы строк.'
    end
    out.wanted_reminder_text=reminder
    for _,kind in ipairs({'wanted','fine','mark'})do
        for _,flag in ipairs({'wheel','quick'})do
            local key=kind..'_'..flag
            if raw[key]~=nil then if type(raw[key])~='boolean'then return nil,'Неверная видимость процедуры.'end;out[key]=raw[key]end
        end
        local label=raw[kind..'_label'];if label==nil then label=out[kind..'_label']end
        out[kind..'_label']=shared.text(label,120)
        if not out[kind..'_label']or out[kind..'_label']==''then return nil,'Укажите короткое название быстрого действия.'end
        local key=raw[kind..'_shortcut'];if key==nil then key=out[kind..'_shortcut']end
        if type(key)~='table'or not shared.integer(key.key,0,254)or type(key.ctrl)~='boolean'or type(key.alt)~='boolean'or type(key.shift)~='boolean'then
            return nil,'Неверная клавиша открытия процедуры.'
        end
        out[kind..'_shortcut']=shared.copy(key)
        local err;out[kind..'_command'],err=M.command(raw[kind..'_command']or out[kind..'_command'],kind,out[kind..'_verified'])
        if not out[kind..'_command']then return nil,err end
        out[kind..'_source']=shared.text(raw[kind..'_source']or '',240)
        if not out[kind..'_source']or out[kind..'_verified']and out[kind..'_source']==''then return nil,'Укажите источник проверки серверной команды.'end
    end
    for _,row in ipairs(M.rpFields)do local k=row[1]
        local err;out[k],err=M.rp(raw[k]or out[k]);if not out[k]then return nil,err end
    end
    return out
end
-- Persistent local follow-ups contain no executable commands or reusable ped IDs.
function M.validateReminders(raw)
    if raw==nil then return {}end
    if type(raw)~='table'or #raw>32 then return nil,'Повреждён список проверки OOC-звёзд.'end
    local out,seen={},{}
    for i,r in ipairs(raw)do
        if type(r)~='table'or not shared.text(r.token,160)or r.token==''or seen[r.token]or
            not shared.integer(r.player_id,0,1003)or not shared.text(r.player_name,120)or r.player_name==''or
            not shared.text(r.session,240)or not shared.text(r.reason,240)or not shared.text(r.context,900)or
            not shared.integer(r.stars,1,6)or not shared.integer(r.created,0,9007199254740991)or
            (r.status~='check'and r.status~='issued')then return nil,'Повреждена запись проверки OOC-звёзд.'end
        seen[r.token]=true;out[i]=shared.copy(r)
    end
    for k in pairs(raw)do if type(k)~='number'or k%1~=0 or k<1 or k>#raw then return nil,'Неверный список проверки OOC-звёзд.'end end
    return out
end
return M

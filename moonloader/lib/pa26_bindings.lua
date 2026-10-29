-- Original data model. No Lua text from a library is ever executed.
local core = require 'pa26_core'
local preferences = require 'pa26_preferences'
local patrolSettings=require 'pa26_patrol_settings'
local eventSettings=require 'pa26_patrol_event_settings'
local identitySettings=require 'pa26_identity'
local procedureSettings=require 'pa26_procedure_settings'
local operationSettings=require 'pa26_operation_settings'
local vehicleSettings=require 'pa26_vehicle_settings'
local assistSettings=require 'pa26_assist_settings'
local rpSettings=require 'pa26_rp_settings'
local chatText=require 'pa26_chat_text'
local mapGrid=require 'pa26_map_grid'
local nearbyModel=require 'pa26_nearby'
local windowLayout=require 'pa26_window_layout'
local manualChat=require 'pa26_manual_chat'
local updateSettings=require 'pa26_updater'
local manualActions=require 'pa26_manual_actions'
local M = {SCHEMA = 1, MAX_BINDS = 128, MAX_NOTES = 128, MAX_PARTNERS = 64, MAX_STEPS = 64}
M.stats = {{'none', 'Без служебного счётчика'}, {'arrest', 'Задержания'}, {'documents', 'Проверки документов'},
    {'frisk', 'Досмотры'}, {'cuff', 'Наручники'}, {'uncuff', 'Снятие наручников'},
    {'license', 'Изъято водительских прав'}, {'fine_player', 'Штрафы игрокам'}, {'fine_vehicle', 'Штрафы автомобилям'},
    {'invite', 'Принято в организацию'}, {'dismiss', 'Уволено'}, {'promote', 'Повышено'}, {'reprimand', 'Выговоры'}}
M.modifierKeys = {[16]=true, [17]=true, [18]=true, [91]=true, [92]=true}
M.variables = {
    {'id', 'ID выбранного человека'}, {'select_id', 'ID выбранного человека'}, {'select_nick', 'Ник выбранного человека'},
    {'select_name', 'Имя выбранного человека из ника'}, {'select_firstname', 'Имя из ника'}, {'select_lastname', 'Фамилия из ника'},
    {'suspect_name', 'Имя выбранного человека'}, {'select_weapon', 'Текущее оружие видимой цели'},
    {'select_vehicle', 'Модель транспорта видимой цели'}, {'select_speed', 'Скорость видимой цели, единицы GTA'},
    {'select_plate', 'Номер транспорта: ручное поле'}, {'my_id', 'Собственный SA:MP ID'}, {'my_nick', 'Собственный ник'},
    {'my_name', 'Имя из профиля или ника'}, {'my_firstname', 'Имя'}, {'my_lastname', 'Фамилия'},
    {'my_weapon', 'Собственное текущее оружие'}, {'my_vehicle', 'Модель собственного транспорта'},
    {'my_speed', 'Скорость движения, единицы GTA'}, {'my_plate', 'Номер: ручное поле профиля'}, {'my_mark', 'Маркировка / позывной экипажа'},
    {'city', 'Город GTA'}, {'area', 'Английское название района'}, {'square', 'Ручной сектор или выбранный в настройках квадрат карты'},
    {'map_square','Квадрат координатной сетки карты'}, {'location','Район и доступный квадрат карты'},
    {'s', 'Секунды'}, {'m', 'Минуты'}, {'h', 'Часы'}, {'D', 'День'}, {'M', 'Месяц'}, {'Y', 'Год'},
    {'greeting', 'Приветствие по времени'}, {'local_tag', 'Префикс локальной волны'}, {'global_tag', 'Префикс общей волны'},
    {'prison_tag', 'Префикс тюремной волны'}, {'department', 'Ведомство'}, {'rank', 'Должность'}, {'accent', 'Акцент'},
    {'team', 'Имена выбранных видимых напарников'}, {'team_id', 'ID напарников рядом'}, {'team_nick', 'Позывные напарников рядом'}, {'team_player_nick','Игровые ники напарников рядом'},
    {'team_name', 'Имена напарников рядом'}, {'team_count', 'Число выбранных видимых напарников'},
    {'closest_id', 'Ближайший допустимый видимый человек'}, {'closest_nick', 'Его ник'}, {'closest_name', 'Имя из ника'},
    {'closest_firstname', 'Имя из ника'}, {'closest_lastname', 'Фамилия из ника'}, {'closest_weapon', 'Текущее оружие'},
    {'closest_vehicle', 'Модель видимого транспорта'}, {'closest_speed', 'Скорость видимой цели, единицы GTA'},
    {'closest_plate', 'Номер: ручной параметр'}, {'param1', 'Первый аргумент'}, {'param2', 'Второй аргумент'},
    {'param3', 'Третий аргумент'}, {'param4', 'Четвёртый аргумент'}, {'param5', 'Пятый аргумент'},
    {'param6', 'Шестой аргумент'}, {'param7', 'Седьмой аргумент'}, {'param8', 'Восьмой аргумент'}, {'params', 'Аргументы вместе'},
}
M.variableNames = {}; for _, v in ipairs(M.variables) do M.variableNames[v[1]] = true end
local manualVariables={my_plate=true,select_plate=true,closest_plate=true,my_mark=true,city=true,square=true,
    local_tag=true,global_tag=true,prison_tag=true,department=true,rank=true,accent=true}
local nameVariables={my_name=true,my_firstname=true,my_lastname=true,select_name=true,select_firstname=true,
    select_lastname=true,suspect_name=true,closest_name=true,closest_firstname=true,closest_lastname=true}
local timeVariables={s=true,m=true,h=true,D=true,M=true,Y=true,greeting=true}
function M.variableInfo(name)
    if not M.variableNames[name] then return nil end
    if name=='location'then return {kind='derived',source='Район GTA + квадрат карты',detail='Готовое местоположение: Doherty, квадрат H-18. Формат редактируется в «Настройки → Карта». В интерьере и за границей сетки остаётся только район; неизвестный квадрат не блокирует доклад.'}end
    if name=='map_square'then return {kind='derived',source='Координаты GTA + настройки сетки',detail='Квадрат карты, например H-18. Сетка настраивается в «Настройки → Карта»; это не подтверждённый официальный сектор SFPS. В интерьере и вне границ сетки значения нет.'}end
    if name=='square'then return {kind='profile',source='Профиль / настройки карты',detail='По умолчанию ручной сектор профиля сохраняется. В «Настройки → Карта» можно явно включить подстановку текущего квадрата карты. Ручное значение при этом не стирается.'}end
    if name=='accent' then return {kind='profile',source='Ручной профиль',detail='Готовый префикс обычной речи. Вручную введённая обычная речь получает его автоматически. В биндах используйте {accent} явно; пустое поле отключает акцент.'} end
    if manualVariables[name] then return {kind='profile',source='Ручной профиль',detail='Введите значение в настройках профиля. Автоматического чтения с сервера сейчас нет.'} end
    if nameVariables[name] then return {kind='derived',source='Профиль / игровой ник',detail='Свои имена берутся из профиля или ника; чужие — из ника. Это не проверенные паспортные данные.'} end
    if timeVariables[name] then return {kind='clock',source='Часы',detail='Часовой пояс выбирается в профиле: ПК, UTC или UTC+3.'} end
    if name:match('^param%d$') or name=='params' then return {kind='argument',source='Аргументы запуска',detail='Значения вводятся в форме запуска или после команды бинда.'} end
    if name:match('^team') then return {kind='team',source='Контакты + видимые игроки',detail='Только добавленные напарники, видимые рядом. Позывные заполняются вручную в контактах.'} end
    if name:match('_speed$') then return {kind='api',source='GTA API',detail='Показание скорости в единицах GTA; калибровка км/ч ещё не подтверждена.'} end
    if name:match('_vehicle$') then return {kind='api',source='GTA API',detail='Пешком или GTA model ID. Название кастомной машины Exsellent пока не определяется.'} end
    if name:match('_weapon$') then return {kind='api',source='GTA API',detail='Оружие собственного персонажа либо доступного видимого игрока. Требуется поддержка функции клиентом.'} end
    if name=='area' then return {kind='api',source='GTA: координаты и зона',detail='Английское имя района; в интерьере — номер интерьера. Это не полицейский сектор.'} end
    if name=='my_id' or name=='my_nick' then return {kind='api',source='SA:MP API',detail='ID или ник собственного подключённого персонажа.'} end
    return {kind='api',source='SA:MP: видимый игрок',detail='ID или ник выбранного либо однозначного ближайшего видимого игрока в допустимой дистанции.'}
end

function M.copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}; for key, v in pairs(value) do out[key] = M.copy(v) end; return out
end
function M.clean(value, limit, multiline)
    if type(value) ~= 'string' or #value > limit or not core.validUtf8(value) then return nil, 'Неверный UTF-8 или превышен размер поля.' end
    local check = multiline and value:gsub('\r\n', '\n'):gsub('\n', '') or value
    if check:find('%c') then return nil, 'Управляющие символы запрещены.' end
    return multiline and value:gsub('\r\n', '\n') or value:match('^%s*(.-)%s*$')
end
function M.accentPrefix(value)
    local prefix,err=M.clean(value or '',240)
    if not prefix then return nil,err end
    local folded=M.casefold(prefix)
    if folded=='без акцента' or folded=='нет акцента' or folded=='нет' or folded=='none' then return '' end
    return prefix
end
function M.applyAccent(text,value)
    if type(text)~='string' then return nil,'Неверный текст речи.' end
    local prefix,err=M.accentPrefix(value)
    if not prefix then return nil,err end
    if prefix=='' or text:match('^%s*[/!]') or text:match('^%s*$') then return text end
    if text:sub(1,#prefix)==prefix then
        local nextChar=text:sub(#prefix+1,#prefix+1)
        if nextChar=='' or nextChar:match('%s') or prefix:sub(-1):match('%p') then return text end
    end
    return prefix..' '..text
end
function M.array(value, max)
    if type(value) ~= 'table' then return false end
    local count = 0
    for key in pairs(value) do
        if not core.finite(key) or key < 1 or key ~= math.floor(key) or key > max then return false end
        count = count + 1
    end
    for i = 1, count do if value[i] == nil then return false end end
    return count <= max
end
function M.validKey(key)
    return core.finite(key) and key == math.floor(key) and (key == 0 or
        (key >= 8 and key <= 254 and key ~= 13 and key ~= 27 and not M.modifierKeys[key]))
end
function M.keyName(key)
    if key == 0 then return 'Не назначено' end
    if key >= 0x70 and key <= 0x87 then return 'F' .. (key - 0x6F) end
    if key >= 0x30 and key <= 0x5A then return string.char(key) end
    local names = {[0x08]='Backspace',[0x09]='Tab',[0x0D]='Enter',[0x20]='Space',[0x21]='PageUp',[0x22]='PageDown',
        [0x23]='End',[0x24]='Home',[0x25]='Left',[0x26]='Up',[0x27]='Right',[0x28]='Down',
        [0x2D]='Insert',[0x2E]='Delete',[0x6B]='Num+', [0x6D]='Num-', [0x6F]='Num/', [0x6A]='Num*'}
    if key >= 0x60 and key <= 0x69 then return 'Num' .. (key - 0x60) end
    return names[key] or ('VK ' .. tostring(key))
end
function M.shortcutName(s)
    if not s or s.key == 0 then return 'Не назначено' end
    return (s.ctrl and 'Ctrl+' or '') .. (s.alt and 'Alt+' or '') .. (s.shift and 'Shift+' or '') .. M.keyName(s.key)
end
function M.shortcut(raw)
    if type(raw) ~= 'table' or not M.validKey(raw.key) then return nil, 'Недопустимая клавиша.' end
    local s = {key=raw.key}
    for _, k in ipairs({'ctrl','alt','shift'}) do if type(raw[k]) ~= 'boolean' then return nil, 'Некорректное сочетание.' end; s[k]=raw[k] end
    if s.key ~= 0 and not s.ctrl and not s.alt and not s.shift and
        (s.key == 0x49 or s.key == 0x4A or s.key == 0x4B or s.key == 0x5A) then
        return nil, 'I/J/K/Z без модификатора оставлены серверу.'
    end
    if s.ctrl and s.alt and s.key == 0x2E then return nil, 'Системное сочетание запрещено.' end
    return s
end
local caseMap
function M.casefold(text)
    if caseMap then return (tostring(text):gsub('[%z\1-\127\194-\244][\128-\191]*',function(c) return caseMap[c] or c:lower() end)) end
    local upper, lower = 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ', 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя'
    local map, list = {}, {}; for c in lower:gmatch('[%z\1-\127\194-\244][\128-\191]*') do list[#list+1]=c end
    local i=0; for c in upper:gmatch('[%z\1-\127\194-\244][\128-\191]*') do i=i+1; map[c]=list[i] end
    caseMap=map
    return (tostring(text):gsub('[%z\1-\127\194-\244][\128-\191]*', function(c) return map[c] or c:lower() end))
end
function M.parseArguments(text)
    local clean,err=M.clean(text,2048); if not clean then return nil,err end
    local args,part={},{}; local quoted,active=false,false; local i=1
    local function flush()
        if active then if #args>=8 then return nil,'Максимум 8 аргументов.' end; args[#args+1]=table.concat(part); part={}; active=false end
        return true
    end
    while i<=#clean do local c=clean:sub(i,i)
        if c=='"' then quoted=not quoted; active=true
        elseif c=='\\' and (clean:sub(i+1,i+1)=='"' or clean:sub(i+1,i+1)=='\\') then part[#part+1]=clean:sub(i+1,i+1); active=true; i=i+1
        elseif c:match('%s') and not quoted then local ok; ok,err=flush(); if not ok then return nil,err end
        else part[#part+1]=c; active=true end
        i=i+1
    end
    if quoted then return nil,'Закройте кавычки аргумента.' end
    local ok; ok,err=flush(); if not ok then return nil,err end
    local out={}; for n,value in ipairs(args) do out['param'..n]=value end; return out
end
function M.find(lib, id)
    for _, bind in ipairs(lib.bindings) do if bind.id == id then return bind end end
end
-- Display order can change; stored IDs keep shortcuts, wheel slots and history stable.
function M.bindingNumber(lib, id)
    for number, bind in ipairs(lib.bindings) do if bind.id == id then return number end end
end
function M.newBinding(id)
    return {id=id,name='Новый сценарий',category='Мои сценарии',enabled=true,quick=false,favorite=false,
        target_required=false,skip_confirmation=false,no_accent=false,wheel_visible=false,wheel_group='auto',wheel_car_visible=false,wheel_car_group='auto',command='',command_alias='',shortcut={key=0,ctrl=false,alt=false,shift=false},stat='none',
        script='Здравствуйте.',parameters={}}
end
-- Native chat input can be prepared before Enter, independently from outgoing
-- RPC filtering. Preserve its observed encoding; wire validation stays CP1251.
function M.manualSpeech(raw,accent,codec,input,settings)
    if type(raw)~='string'then return nil,'Поле чата недоступно.'end
    local prefix=M.accentPrefix(accent)
    if not prefix or prefix=='' or chatText.skipAccent(raw,settings)then return raw end
    local utf=input and raw:find('[\128-\255]')and core.validUtf8(raw)
    local ok,plain=true,raw
    if not utf then ok,plain=pcall(codec.decode,raw)end
    if not ok or not core.validUtf8(plain)then return nil,'Ошибка кодировки чата.'end
    local text,err=M.applyAccent(plain,prefix);if not text then return nil,err end
    local wire;wire,err=core.encodeWire(text,codec);if not wire then return nil,err end
    return utf and text or wire
end
-- Prepare native input while typing, before SA:MP can echo the original text.
-- Track only our own prefix; commands and manually supplied text stay editable.
function M.liveSpeech(raw,accent,codec,ownedPrefix,settings)
    if type(raw)~='string'then return nil,nil,'Поле чата недоступно.'end
    local body=raw
    if ownedPrefix and raw:sub(1,#ownedPrefix)==ownedPrefix then body=raw:sub(#ownedPrefix+1)end
    if chatText.skipAccent(body,settings)then return body,nil end
    local prepared,err=M.manualSpeech(body,accent,codec,true,settings)
    if not prepared then return nil,nil,err end
    local prefix=prepared~=body and prepared:sub(1,#prepared-#body)or nil
    return prepared,prefix
end
M.chatPolicy=chatText.policy
-- Dot commands are converted only at submission. Never shorten or split commands.
function M.submitSpeech(raw,accent,codec,input,settings,ownedPrefix)
    if type(raw)~='string'then return nil,'Поле чата недоступно.'end
    local body=raw
    if ownedPrefix and raw:sub(1,#ownedPrefix)==ownedPrefix then body=raw:sub(#ownedPrefix+1)end
    if (not settings or settings.chat_dot_commands~=false)and body:sub(1,1)=='.'or
        settings and settings.manual_radio_prefix~=false and type(settings.local_tag)=='string'and settings.local_tag~=''and body:match('^ */[rR] ')then
        local utf=input and body:find('[\128-\255]')and core.validUtf8(body)
        local ok,plain=true,body
        if not utf then ok,plain=pcall(codec.decode,body)end
        if not ok or not core.validUtf8(plain)then return nil,'Ошибка кодировки чата.'end
        local command,converted=chatText.dotCommand(plain,settings)
        local radio;command,radio=chatText.radioCommand(command,settings)
        if converted or radio then
            local wire,err=core.encodeWire(command,codec);if not wire then return nil,err end
            return utf and command or wire,nil,converted
        end
    end
    return M.manualSpeech(body,accent,codec,input,settings)
end
function M.alertDefaults()
    local out={enabled=true,on_duty=true,auto_shots=true,include_sd=false,channel='/r',
        shots_template='{local_tag}Shots fired. По мне открыли огонь. Мой 10-20: {area}.',
        sos_template='{local_tag}10-70. Требуется поддержка. 10-20: {area}.',
        cooldown_ms=30000,timeout_ms=15000}
    return preferences.extendAlerts(out,{})
end
M.alertKinds={'sos','shots','code0','code1','code4'}
function M.alertShortcutDefaults()
    return {sos={key=0x31,alt=true,ctrl=false,shift=false},shots={key=0x32,alt=true,ctrl=false,shift=false},
        code0={key=0x33,alt=true,ctrl=false,shift=false},
        code1={key=0,alt=false,ctrl=false,shift=false},code4={key=0,alt=false,ctrl=false,shift=false}}
end
M.featureKeys={{'radio_guard','skip_shortcut','Пропустить автодоклад'}, {'weapon_warning','shortcut','Предупредить об оружии'},
    {'alert_shortcuts','sos','SOS'}, {'alert_shortcuts','shots','Shots fired'}, {'alert_shortcuts','code0','CODE 0'},
    {'alert_shortcuts','code1','CODE 1'}, {'alert_shortcuts','code4','CODE 4'},
    {'patrol_session','toggle_shortcut','Открыть патруль'}, {'patrol_session','pause_shortcut','Пауза / продолжение патруля'},
    {'patrol_session','finish_shortcut','Завершить патруль'}, {'patrol_events','open_shortcut','События патруля'},
    {'procedures','wanted_shortcut','Открыть форму розыска'}, {'procedures','fine_shortcut','Открыть форму штрафа'},
    {'procedures','mark_shortcut','Открыть пеленгацию'},
    {'vehicle','select_shortcut','Трафик-стоп · выбрать машину'}, {'vehicle','pursuit_shortcut','Преследование транспорта'},
    {'vehicle','megaphone_shortcut','Мегафон выбранной машине'}}
for i=1,vehicleSettings.phraseCount do M.featureKeys[#M.featureKeys+1]={'vehicle','phrase_'..i..'_shortcut','Мегафон · требование '..i}end
for _,row in ipairs(assistSettings.keys)do M.featureKeys[#M.featureKeys+1]={'assist',row[1],row[2]}end
function M.validateAlerts(raw)
    local out=M.alertDefaults()
    if raw==nil then return out end -- Optional extension: keep existing schema-3 libraries.
    if type(raw)~='table' then return nil,'Неверные настройки связи.' end
    for _,key in ipairs({'enabled','on_duty','auto_shots','include_sd'}) do
        if type(raw[key])~='boolean' then return nil,'Неверный флаг связи: '..key end;out[key]=raw[key]
    end
    if raw.channel~='/r' and raw.channel~='/f' and raw.channel~='/d' then return nil,'Канал IC: /r, /f или /d.' end;out.channel=raw.channel
    for _,key in ipairs({'shots_template','sos_template'}) do
        local value,err=preferences.template(raw[key],preferences.radioVariables)
        if not value then return nil,err end
        out[key]=value
    end
    for _,spec in ipairs({{'cooldown_ms',1000,120000},{'timeout_ms',1000,30000}}) do
        local n=raw[spec[1]]
        if not core.finite(n) or n~=math.floor(n) or n<spec[2] or n>spec[3] then return nil,'Неверный интервал связи.' end
        out[spec[1]]=n
    end
    return preferences.extendAlerts(out,raw)
end
function M.defaults(cfg)
    local lib = {schema=M.SCHEMA,next_id=7,bindings={},notes={
        {id=1,name='Как пользоваться биндами',body='Создайте сценарий в разделе «Бинды».\n{my_name} в фигурных скобках подставляет имя из профиля.\n@wait(1500) добавляет паузу в миллисекундах.\n@sleep(F11) ждёт отдельного нажатия клавиши.\nБыстрое меню содержит только сценарии с отметкой «В быстром меню».\nДемо выполняет шаги без отправки в игру.',favorite=true},
        {id=2,name='Перед реальным запуском',body='Проверьте итоговый текст, цель и команду вашего сервера.\nID закрепляется на время сценария.\nEnd или Esc останавливают оставшиеся шаги.\nФакт передачи команды клиенту не доказывает её принятие сервером.',favorite=false},
    },next_note_id=3,partners={},next_partner_id=1,wheel={1,2,3,4,5,6},
    profile={name='',gender='male',accent='',department='',rank='',case_number='',local_tag='',global_tag='',prison_tag='',callsign='',my_plate='',select_plate='',closest_plate='',square='',city='',timezone='local'},
    alerts=M.alertDefaults(),weapons=preferences.weaponDefaults(),taser=preferences.taserDefaults(),
    wanted_reminders={},nearby=nearbyModel.defaults(),map_grid=mapGrid.defaults(),rp_text=rpSettings.defaults(),assist=assistSettings.defaults(),vehicle=vehicleSettings.defaults(),operations=operationSettings.defaults(),procedures=procedureSettings.defaults(),identity=identitySettings.defaults(),patrol_session=patrolSettings.defaults(),patrol_events=eventSettings.defaults(),radio_guard=preferences.radioGuardDefaults(),weapon_warning=preferences.weaponWarningDefaults(),alert_shortcuts=M.alertShortcutDefaults(),
    settings={updates=updateSettings.defaults(),window_layout=windowLayout.defaults(),manual_chat=manualChat.defaults(),quick_key=0x7A,tips_key=0x7B,cancel_key=0x23,opacity=.86,compact=false,ask_screenshot_path=false,
        retain_distance=40,retain_grace_ms=1500,keep_target_on_interior_change=true,aim_select_enabled=true,aim_select_control='mouse',aim_select_delay_ms=150,wheel_mode='categories',wheel_profile='compact',wheel_enabled=true,interaction_notices=true,accent_live_input=true,accent_skip_brackets=true,chat_dot_commands=true,manual_radio_prefix=true,cef_chat_support=true,cef_chat_diagnostics=true,cef_layout_indicator=true,cef_chat_weapon_guard=true,cef_chat_weapon_lock=true,cef_chat_grace_ms=350,wheel_names={}},
    filters={},recruitment={min_age=18,min_level=3,min_lawfulness=0,land=true,water=false,air=false,weapon=true,medical=true}}
    local categories={introduce='Общение',documents='Документы',wanted='Проверки',frisk='Досмотр',cuff='Задержание',release='Задержание'}
    lib.settings.manual_actions=manualActions.defaults();lib.settings.wheel_child_limit=0;lib.settings.wheel_system_groups={};lib.settings.wheel_order={};lib.settings.wheel_edit_enabled=true;lib.settings.shutdown_message='Police Assistant полностью отключён до перезахода в игру.'
    local female={introduce='остановившись рядом, достала служебное удостоверение и раскрыла его перед собеседником.',
        documents='оглянувшись по сторонам, обратилась к собеседнику с просьбой предъявить паспорт.',
        wanted='сверив известные сведения, внесла данные в служебный терминал и открыла форму поиска.',
        frisk='надев перчатки, аккуратно проверила одежду и карманы саспекта.',
        cuff='придерживая руку саспекта, достала наручники и аккуратно защёлкнула их на запястьях.',
        release='вставив ключ в замок, расстегнула наручники и убрала их в подсумок на поясе.'}
    for i, action in ipairs(core.actions) do
        local entry=cfg and cfg[action.key] or action
        local bind=M.newBinding(i); bind.name=action.label; bind.category=categories[action.key]; bind.target_required=true
        bind.enabled=entry.enabled~=false; bind.quick=true; bind.wheel_visible=true; bind.wheel_group='auto'; bind.favorite=i<=2; bind.stat=({documents='documents',frisk='frisk',cuff='cuff',release='uncuff'})[action.key] or 'none'
        local lines={}; if entry.me~='' then local phrase=entry.me==action.me and ('{gender:'..entry.me:sub(1,-2)..'|'..female[action.key]:sub(1,-2)..'}.') or entry.me; lines[#lines+1]='/me '..phrase end
        if entry.do_text~='' then lines[#lines+1]='/do '..entry.do_text end
        if entry.command~='' then lines[#lines+1]=entry.command end
        bind.script=table.concat(lines,'\n'); if bind.script=='' then bind.script='Сценарий не настроен.'; bind.enabled=false end
        lib.bindings[#lib.bindings+1]=bind
    end
    require('pa26_wheel_scope').fresh(lib.settings,lib.wheel)
    for _,bind in ipairs(lib.bindings)do bind.wheel_car_visible=bind.wheel_visible end
    if cfg then for _,k in ipairs({'quick_key','tips_key'}) do if lib.settings[k]==cfg.main.menu_key or lib.settings[k]==cfg.main.radial_key then lib.settings[k]=0 end end end
    return lib
end
function M.knowledgeOrigin(raw)
    if type(raw)~='table' or raw.manual_command_contract~=true or
        not ({wanted=true,fine=true})[raw.procedure] or not ({passport=true,appearance=true,ooc=true})[raw.identity] then
        return nil,'Повреждено основание из базы знаний.'
    end
    local out={manual_command_contract=true,procedure=raw.procedure,identity=raw.identity}
    for _,key in ipairs({'catalog_version','article_id','reference','source_url'})do
        local value=M.clean(raw[key],key=='source_url'and 600 or 160)
        if not value then return nil,'Повреждено поле основания '..key end
        out[key]=value
    end
    if not out.source_url:match('^https://forum%.exsellentrp%.com/')then return nil,'Неверная ссылка на источник.'end
    if raw.personal_origin~=nil then
        if not({custom=true,override=true})[raw.personal_origin]then return nil,'Повреждено происхождение личной карточки.'end
        local stamp=M.clean(raw.personal_updated_at,80)
        if not stamp then return nil,'Повреждена дата личной карточки.'end
        out.personal_origin=raw.personal_origin;out.personal_updated_at=stamp
    end
    return out
end
local reservedAliases={}
for _,row in ipairs(require('pa26_server_commands').commands)do reservedAliases[row[1]:sub(2)]=true end
for word in ('me do try todo s b n l ln df bkn gps sms call help id time report admin ask pay heal members giverank setrank rank promotion name login quit q reconnect'):gmatch('%S+')do reservedAliases[word]=true end
function M.reservedAlias(name)return name:match('^pa26')~=nil or reservedAliases[name]==true end
function M.bindingCommands(b)
    local out={}
    if b.command and b.command~=''then out[#out+1]=b.command end
    if b.command_alias and b.command_alias~=''and b.command_alias~=b.command then out[#out+1]=b.command_alias end
    return out
end
function M.validateBinding(raw)
    if type(raw)~='table' or not core.finite(raw.id) or raw.id<1 or raw.id>999999999 or raw.id~=math.floor(raw.id) then return nil,'Некорректный ID сценария.' end
    local b={id=raw.id}; local error
    for _, f in ipairs({'name','category','command','script'}) do
        b[f],error=M.clean(raw[f],f=='script' and 16384 or (f=='command' and 48 or 160),f=='script')
        if not b[f] then return nil,f..': '..error end
    end
    if b.name=='' or b.script:match('^%s*$') then return nil,'Нужны название и текст сценария.' end
    if b.command~='' and not b.command:match('^pa26_[a-z][a-z0-9_]*$') then return nil,'Команда запуска: pa26_имя латиницей, без /.' end
    b.command_alias,error=M.clean(raw.command_alias or '',48,false)
    if not b.command_alias then return nil,'Короткая команда: '..tostring(error)end
    b.command_alias=b.command_alias:gsub('^/',''):lower()
    if b.command_alias~=''then
        if not b.command_alias:match('^[a-z][a-z0-9_]*$')then return nil,'Короткая команда: название латиницей, без пробелов.'end
        if M.reservedAlias(b.command_alias)then return nil,'Имя /'..b.command_alias..' занято сервером или PA. Выберите другое имя.'end
    end
    for _, f in ipairs({'enabled','quick','favorite','target_required'}) do if type(raw[f])~='boolean' then return nil,'Некорректный флаг '..f end; b[f]=raw[f] end
    for _,f in ipairs({'skip_confirmation','no_accent'})do
        if raw[f]~=nil and type(raw[f])~='boolean'then return nil,'Некорректный флаг '..f end
        b[f]=raw[f]==true
    end
    if raw.wheel_visible~=nil and type(raw.wheel_visible)~='boolean' then return nil,'Некорректный флаг радиального меню.' end
    b.wheel_visible=raw.wheel_visible==nil and raw.quick or raw.wheel_visible==true
    local groups={auto=true,citizen=true,documents=true,detention=true,frisk=true,wanted=true,service=true,leadership=true,custom=true}
    b.wheel_group=raw.wheel_group or 'auto'
    if not groups[b.wheel_group] then return nil,'Неизвестная категория радиального меню.' end
    if raw.wheel_car_visible~=nil and type(raw.wheel_car_visible)~='boolean'then return nil,'Видимость бинда в машине: включено или выключено.'end
    b.wheel_car_visible=raw.wheel_car_visible;if b.wheel_car_visible==nil then b.wheel_car_visible=b.wheel_visible end
    b.wheel_car_group=raw.wheel_car_group;if b.wheel_car_group==nil then b.wheel_car_group=b.wheel_group end
    if not groups[b.wheel_car_group]then return nil,'Неизвестная секция бинда в машине.'end
    b.shortcut,error=M.shortcut(raw.shortcut); if not b.shortcut then return nil,error end
    local found=false; for _, s in ipairs(M.stats) do if s[1]==raw.stat then found=true end end
    if not found then return nil,'Неизвестный служебный счётчик.' end; b.stat=raw.stat
    if not M.array(raw.parameters,8) then return nil,'Допустимо до 8 параметров.' end
    b.parameters={}; local names={}
    for _, p in ipairs(raw.parameters) do
        if type(p)~='table' or type(p.name)~='string' or not p.name:match('^[a-z][a-z0-9_]*$') or #p.name>24 or names[p.name] then return nil,'Некорректное или повторное имя параметра.' end
        if p.type~='text' and p.type~='integer' then return nil,'Тип параметра: text или integer.' end
        if type(p.required)~='boolean' then return nil,'Не указан обязательный параметр.' end
        local label=M.clean(p.label,160); local default=M.clean(p.default,240)
        if not label or not default then return nil,'Повреждён параметр.' end
        if p.type=='integer' and default~='' and not default:match('^%-?%d+$') then return nil,'Значение по умолчанию должно быть целым.' end
        names[p.name]=true; b.parameters[#b.parameters+1]={name=p.name,label=label,default=default,type=p.type,required=p.required}
    end
    if raw.knowledge~=nil then
        b.knowledge,error=M.knowledgeOrigin(raw.knowledge);if not b.knowledge then return nil,error end
    end
    return b
end
function M.validate(raw, cfg)
    if type(raw)~='table' or raw.schema~=M.SCHEMA then return nil,'Неизвестная версия библиотеки.' end
    local out=M.defaults(cfg); out.bindings={}; out.notes={}; out.partners={}
    local alertError;out.alerts,alertError=M.validateAlerts(raw.alerts);if not out.alerts then return nil,alertError end
    out.weapons,alertError=preferences.validateWeapons(raw.weapons);if not out.weapons then return nil,alertError end
    out.taser,alertError=preferences.validateTaser(raw.taser);if not out.taser then return nil,alertError end
    out.radio_guard,alertError=preferences.validateRadioGuard(raw.radio_guard);if not out.radio_guard then return nil,alertError end
    out.weapon_warning,alertError=preferences.validateWeaponWarning(raw.weapon_warning);if not out.weapon_warning then return nil,alertError end
    out.patrol_session,alertError=patrolSettings.validate(raw.patrol_session);if not out.patrol_session then return nil,alertError end
    out.patrol_events,alertError=eventSettings.validate(raw.patrol_events);if not out.patrol_events then return nil,alertError end
    out.identity,alertError=identitySettings.validate(raw.identity);if not out.identity then return nil,alertError end
    out.vehicle,alertError=vehicleSettings.validate(raw.vehicle);if not out.vehicle then return nil,alertError end
    out.assist,alertError=assistSettings.validate(raw.assist);if not out.assist then return nil,alertError end
    out.rp_text,alertError=rpSettings.validate(raw.rp_text);if not out.rp_text then return nil,alertError end
    out.map_grid,alertError=mapGrid.validate(raw.map_grid);if not out.map_grid then return nil,alertError end
    out.nearby,alertError=nearbyModel.validate(raw.nearby);if not out.nearby then return nil,alertError end
    out.procedures,alertError=procedureSettings.validate(raw.procedures);if not out.procedures then return nil,alertError end
    out.wanted_reminders,alertError=procedureSettings.validateReminders(raw.wanted_reminders);if not out.wanted_reminders then return nil,alertError end
    out.operations,alertError=operationSettings.validate(raw.operations);if not out.operations then return nil,alertError end
    for _, f in ipairs({'next_id','next_note_id','next_partner_id'}) do
        if not core.finite(raw[f]) or raw[f]<1 or raw[f]>999999999 or raw[f]~=math.floor(raw[f]) then return nil,'Некорректный счётчик ID.' end; out[f]=raw[f]
    end
    if not M.array(raw.bindings,M.MAX_BINDS) or not M.array(raw.notes,M.MAX_NOTES) or not M.array(raw.partners,M.MAX_PARTNERS) then return nil,'Слишком большой или повреждённый список.' end
    local ids,commands,keys={},{},{}
    for _, entry in ipairs(raw.bindings) do
        local b,err=M.validateBinding(entry); if not b then return nil,err end
        if ids[b.id] or b.id>=out.next_id then return nil,'Повторный ID сценария или неверный next_id.' end; ids[b.id]=true
        for _,name in ipairs(M.bindingCommands(b))do
            if commands[name]then return nil,'Повторная команда запуска: /'..name..'.'end
            commands[name]=true
        end
        if b.enabled and b.shortcut.key~=0 then local key=M.shortcutName(b.shortcut); if keys[key] then return nil,'Повторное сочетание: '..key end; keys[key]=true end
        out.bindings[#out.bindings+1]=b
    end
    for _, spec in ipairs({{'notes','next_note_id',8192},{'partners','next_partner_id',512}}) do
        local seen={}
        for _, row in ipairs(raw[spec[1]]) do
            if type(row)~='table' or not core.finite(row.id) or row.id<1 or row.id~=math.floor(row.id) or row.id>=out[spec[2]] or seen[row.id] then return nil,'Повторный или неверный ID записи.' end; seen[row.id]=true
            if spec[1]=='notes' then
                local name=M.clean(row.name,160); local body=M.clean(row.body,spec[3],true)
                if not name or name=='' or not body or type(row.favorite)~='boolean' then return nil,'Повреждённая памятка.' end
                out.notes[#out.notes+1]={id=row.id,name=name,body=body,favorite=row.favorite}
            else
                local nick=M.clean(row.nickname,24); local callsign=M.clean(row.callsign,80)
                if not nick or not nick:match('^[%w_%.%[%]%-]+$') or not callsign then return nil,'Повреждённый контакт напарника.' end
                for _, old in ipairs(out.partners) do if old.nickname:lower()==nick:lower() then return nil,'Напарник уже добавлен.' end end
                out.partners[#out.partners+1]={id=row.id,nickname=nick,callsign=callsign}
            end
        end
    end
    if not M.array(raw.wheel,6) or #raw.wheel~=6 then return nil,'Нужно ровно 6 мест колеса.' end
    out.wheel={}; for i,id in ipairs(raw.wheel) do if id~=0 and not ids[id] then return nil,'В колесе неизвестный сценарий.' end; out.wheel[i]=id
        -- Old direct-slot assignments survive even when their F11 flag is off.
        if id~=0 then for n,b in ipairs(out.bindings) do if b.id==id and raw.bindings[n].wheel_visible==nil then b.wheel_visible=true end end end
    end
    if type(raw.profile)~='table' or type(raw.settings)~='table' then return nil,'Отсутствует профиль или настройки.' end
    for key,default in pairs(out.profile) do local value=M.clean(raw.profile[key],240); if not value then return nil,'Неверное поле профиля: '..key end; out.profile[key]=value end
    if out.profile.gender~='male' and out.profile.gender~='female' then return nil,'Выберите грамматический род.' end
    if out.profile.timezone~='local' and out.profile.timezone~='utc' and out.profile.timezone~='moscow' then return nil,'Неверный часовой пояс.' end
    local global={}; for _,key in ipairs({'quick_key','tips_key','cancel_key'}) do
        local v=raw.settings[key]; if not M.validKey(v) then return nil,'Неверная клавиша окна.' end
        if v~=0 and (global[v] or v==(cfg and cfg.main.menu_key) or v==(cfg and cfg.main.radial_key)) then return nil,'Конфликт клавиш окон.' end
        if v==0x49 or v==0x4A or v==0x4B or v==0x5A then return nil,'I/J/K/Z оставлены серверу.' end
        global[v]=true; out.settings[key]=v
    end
    if not core.finite(raw.settings.opacity) or raw.settings.opacity<.5 or raw.settings.opacity>1 then return nil,'Непрозрачность: 0.5–1.' end; out.settings.opacity=raw.settings.opacity
    for _,p in ipairs({{'retain_distance',20,200},{'retain_grace_ms',500,5000},{'aim_select_delay_ms',0,2000}}) do
        local value=raw.settings[p[1]]
        if value~=nil then
            if not core.finite(value) or value~=math.floor(value) or value<p[2] or value>p[3] then return nil,'Неверное условие сохранения выбранного игрока.' end
            out.settings[p[1]]=value
        end
    end
    for _, k in ipairs({'compact','ask_screenshot_path'}) do if type(raw.settings[k])~='boolean' then return nil,'Неверный флаг настроек.' end; out.settings[k]=raw.settings[k] end
    local modes={categories=true,classic=true}; local profiles={compact=true,extended=true,full=true}
    local mode=raw.settings.wheel_mode or 'categories'; local profile=raw.settings.wheel_profile or 'compact'
    if not modes[mode] or not profiles[profile] then return nil,'Неверный режим или профиль радиального меню.' end
    out.settings.wheel_mode=mode; out.settings.wheel_profile=profile
    local childLimit=raw.settings.wheel_child_limit or 0
    if not core.finite(childLimit)or childLimit%1~=0 or childLimit<0 or childLimit>16 then return nil,'Второе кольцо: авто либо от 1 до 16 действий.'end
    out.settings.wheel_child_limit=childLimit
    out.settings.wheel_system_groups={}
    local systemGroups=raw.settings.wheel_system_groups or{}
    if type(systemGroups)~='table'then return nil,'Неверные секции встроенных действий.'end
    local validSystems={};for _,r in ipairs(require('pa26_wheel').systemRows)do validSystems[r[1]]=true end
    local validGroups={disabled=true,citizen=true,documents=true,detention=true,frisk=true,wanted=true,service=true,leadership=true,custom=true}
    for id,group in pairs(systemGroups)do
        if not validSystems[id]or not validGroups[group]then return nil,'Неизвестное действие или секция колеса.'end
        out.settings.wheel_system_groups[id]=group
    end
    out.settings.wheel_order,alertError=require('pa26_wheel_order').validate(raw.settings.wheel_order)
    if not out.settings.wheel_order then return nil,alertError end
    local editEnabled=raw.settings.wheel_edit_enabled;if editEnabled==nil then editEnabled=true end
    if type(editEnabled)~='boolean'then return nil,'Неверный переключатель перестановки колеса.'end
    out.settings.wheel_edit_enabled=editEnabled
    local shutdownMessage=raw.settings.shutdown_message or 'Police Assistant полностью отключён до перезахода в игру.'
    if type(shutdownMessage)~='string'or #shutdownMessage>1024 or not core.validUtf8(shutdownMessage)or shutdownMessage:find('%c')then return nil,'Неверное локальное уведомление о выключении.'end
    out.settings.shutdown_message=shutdownMessage
    out.settings.manual_actions,alertError=manualActions.validate(raw.settings.manual_actions)
    if not out.settings.manual_actions then return nil,alertError end
    local aimControl=raw.settings.aim_select_control
    if aimControl==nil then aimControl='mouse'end
    if aimControl~='mouse'and aimControl~='game'then return nil,'Выберите управление выбором человека: ПКМ или прицеливание GTA.'end
    out.settings.aim_select_control=aimControl
    local grace=raw.settings.cef_chat_grace_ms or out.settings.cef_chat_grace_ms
    if not core.finite(grace)or grace%1~=0 or grace<50 or grace>1000 then return nil,'Защита открытия чата: 50–1000 мс.'end
    out.settings.cef_chat_grace_ms=grace
    for _,k in ipairs({'wheel_enabled','interaction_notices','keep_target_on_interior_change','accent_live_input','accent_skip_brackets','chat_dot_commands','manual_radio_prefix','cef_chat_support','cef_chat_diagnostics','cef_layout_indicator','cef_chat_weapon_guard','cef_chat_weapon_lock','aim_select_enabled'}) do
        if raw.settings[k]~=nil then
            if type(raw.settings[k])~='boolean' then return nil,'Неверный переключатель: '..k end
            out.settings[k]=raw.settings[k]
        end
    end
    out.settings.updates,alertError=updateSettings.validate(raw.settings.updates);if not out.settings.updates then return nil,alertError end
    out.settings.window_layout,alertError=windowLayout.validate(raw.settings.window_layout);if not out.settings.window_layout then return nil,alertError end
    out.settings.manual_chat,alertError=manualChat.validate(raw.settings.manual_chat);if not out.settings.manual_chat then return nil,alertError end
    out.settings.wheel_names={}
    local names=raw.settings.wheel_names
    if names~=nil and type(names)~='table'then return nil,'Неверные названия категорий колеса.'end
    local groups={citizen=true,documents=true,detention=true,frisk=true,wanted=true,service=true,leadership=true,custom=true}
    for key,value in pairs(names or {})do
        local clean=M.clean(value,160)
        if not groups[key]or not clean or clean:find('[\r\n]')then return nil,'Название категории должно быть однострочным, до 160 байт UTF-8.'end
        if clean~=''then out.settings.wheel_names[key]=clean end
    end
    local carSettings,carError=require('pa26_wheel_scope').validate(raw.settings,out.settings,out.wheel,ids,M.clean,M.array,validSystems)
    if not carSettings then return nil,carError end
    for key,value in pairs(carSettings)do out.settings[key]=value end
    out.alert_shortcuts=M.alertShortcutDefaults()
    if raw.alert_shortcuts~=nil and type(raw.alert_shortcuts)~='table'then return nil,'Неверные клавиши связи.'end
    for key,rawKey in pairs(raw.alert_shortcuts or {})do
        if out.alert_shortcuts[key]==nil then return nil,'Неизвестная клавиша связи.'end
        out.alert_shortcuts[key]=rawKey
    end
    local featureKeys={}
    for _,sp in ipairs(M.featureKeys)do
        local s,err=M.shortcut(out[sp[1]][sp[2]]);if not s then return nil,err end
        local count=1+(s.ctrl and 1 or 0)+(s.alt and 1 or 0)+(s.shift and 1 or 0)
        if s.key~=0 and (count>3 or ((s.key==0x59 or s.key==0x4e) and not s.ctrl and not s.alt and not s.shift))then return nil,'Для напоминаний выберите сочетание до 3 клавиш; Y/N без модификаторов заняты подтверждениями.'end
        local name=M.shortcutName(s)
        local conflict=s.key~=0 and (global[s.key] or (cfg and (s.key==cfg.main.menu_key or s.key==cfg.main.radial_key)) or keys[name] or featureKeys[name])
        if conflict then
            if raw[sp[1]]==nil or raw[sp[1]][sp[2]]==nil then s={key=0,ctrl=false,alt=false,shift=false}
            else return nil,'Клавиша напоминания занята: '..name end
        end
        out[sp[1]][sp[2]]=s;if s.key~=0 then featureKeys[M.shortcutName(s)]=true end
    end
    for _, b in ipairs(out.bindings) do if b.enabled and b.shortcut.key~=0 and
        (global[b.shortcut.key] or b.shortcut.key==(cfg and cfg.main.menu_key) or b.shortcut.key==(cfg and cfg.main.radial_key)) then return nil,'Клавиша занята окном: '..M.shortcutName(b.shortcut) end end
    if not M.array(raw.filters,16) then return nil,'Слишком много фильтров.' end; out.filters={}
    for _, f in ipairs(raw.filters) do local prefix=type(f)=='table' and M.clean(f.prefix,160)
        if not prefix or prefix=='' or type(f.enabled)~='boolean' then return nil,'Фильтру нужен буквальный префикс.' end
        out.filters[#out.filters+1]={prefix=prefix,enabled=f.enabled}
    end
    if type(raw.recruitment)~='table' then return nil,'Нет критериев приёма.' end
    for _, k in ipairs({'min_age','min_level','min_lawfulness'}) do local v=raw.recruitment[k]
        if not core.finite(v) or v<0 or v>999 or v~=math.floor(v) then return nil,'Критерий должен быть целым числом 0–999.' end; out.recruitment[k]=v end
    for _, k in ipairs({'land','water','air','weapon','medical'}) do if type(raw.recruitment[k])~='boolean' then return nil,'Неверный критерий.' end; out.recruitment[k]=raw.recruitment[k] end
    return out
end
function M.recruitmentResult(criteria, candidate)
    local missing={}
    for _, pair in ipairs({{'age','min_age','Возраст'},{'level','min_level','Уровень'},{'lawfulness','min_lawfulness','Законопослушность'}}) do
        local v=candidate[pair[1]]; if not core.finite(v) or v<criteria[pair[2]] then missing[#missing+1]=pair[3] end
    end
    for _, key in ipairs({'land','water','air','weapon','medical'}) do if criteria[key] and candidate[key]~=true then missing[#missing+1]=key end end
    return #missing==0,missing
end
-- Validate only assignment metadata; an unfinished name/text must not prevent
-- choosing a key. Check again on Apply against the latest library and draft.
function M.checkKeyAssignment(lib,cfg,draft,request,raw)
    local shortcut,err=M.shortcut(raw); if not shortcut then return nil,err end
    -- Limit new assignments without invalidating older saved shortcuts.
    local count=(shortcut.key~=0 and 1 or 0)+(shortcut.ctrl and 1 or 0)+(shortcut.alt and 1 or 0)+(shortcut.shift and 1 or 0)
    if count>3 then return nil,'Максимум 3 клавиши: основная и до двух из Ctrl, Alt, Shift.' end
    local fields={quick_key='Быстрое меню',tips_key='Памятки',cancel_key='Остановка сценария'}
    local features={};for _,row in ipairs(M.featureKeys)do features[row[1]]=features[row[1]]or{};features[row[1]][row[2]]=row[3]end
    if type(request)~='table' or (request.kind~='binding' and request.kind~='setting' and request.kind~='feature') then return nil,'Неизвестное назначение.' end
    if request.kind=='feature' and (not features[request.group] or not features[request.group][request.field])then return nil,'Неизвестная клавиша напоминания.'end
    if request.kind=='setting' and not fields[request.field] then return nil,'Неизвестная настройка клавиши.' end
    if request.kind=='binding' and (not draft or draft.id~=request.id) then return nil,'Редактируемый бинд изменился. Повторите назначение.' end
    if request.kind=='setting' and (shortcut.ctrl or shortcut.alt or shortcut.shift) then
        return nil,'Для окна или остановки выберите одну клавишу без Ctrl, Alt и Shift.'
    end
    if shortcut.key==0 then return shortcut end
    if request.kind=='feature' and (shortcut.key==0x59 or shortcut.key==0x4e) and not shortcut.ctrl and not shortcut.alt and not shortcut.shift then return nil,'Y/N без модификаторов заняты подтверждением.'end
    local windows={[cfg.main.menu_key]='Главное меню',[cfg.main.radial_key]='Радиальное меню'}
    for field,name in pairs(fields) do
        local key=lib.settings[field]
        if key~=0 and not (request.kind=='setting' and request.field==field) then windows[key]=name end
    end
    if windows[shortcut.key] then return nil,'Клавиша '..M.keyName(shortcut.key)..' занята: '..windows[shortcut.key]..'.' end
    local function conflicts(binding)
        if not binding or not binding.enabled or binding.shortcut.key==0 then return false end
        if request.kind=='binding' and binding.id==request.id then return false end
        return request.kind=='setting' and binding.shortcut.key==shortcut.key or
            request.kind~='setting' and M.shortcutName(binding.shortcut)==M.shortcutName(shortcut)
    end
    for _,b in ipairs(lib.bindings) do
        if conflicts(b) then return nil,'Сочетание занято биндом «'..b.name..'». Выберите другое.' end
    end
    if draft and conflicts(draft) then return nil,'Сочетание занято текущим черновиком. Выберите другое.' end
    for group,entries in pairs(features)do for field,name in pairs(entries)do
        local current=lib[group] and lib[group][field]
        if current and current.key~=0 and not(request.kind=='feature' and request.group==group and request.field==field)and
            (request.kind=='setting' and current.key==shortcut.key or M.shortcutName(current)==M.shortcutName(shortcut))then return nil,'Сочетание занято: '..name end
    end end
    return shortcut
end
function M.matchesShortcut(shortcut, key, modifiers)
    return shortcut.key~=0 and shortcut.key==key and shortcut.ctrl==modifiers.ctrl and shortcut.alt==modifiers.alt and shortcut.shift==modifiers.shift
end
return M

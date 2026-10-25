-- Original Police Assistant 2026 rules. Lua 5.1 / LuaJIT, no game APIs.
local M = {VERSION = '0.39.0', SCHEMA = 2, WIRE_LIMIT = 127, TEMPLATE_LIMIT = 768}
M.actions = {
    {key = 'introduce', label = 'Представиться', me = 'остановившись рядом, достал служебное удостоверение и раскрыл его перед собеседником.', do_text = 'Удостоверение раскрыто: данные и фотография видны собеседнику.', command = ''},
    {key = 'documents', label = 'Документы', me = 'оглянувшись по сторонам, обратился к собеседнику с просьбой предъявить паспорт.', do_text = 'Готов ли собеседник предъявить документ?', command = ''},
    {key = 'wanted', label = 'Розыск', enabled=false, me = 'сверив известные сведения, внёс данные в служебный терминал и открыл форму поиска.', do_text = 'На экране терминала открыта форма запроса.', command = ''},
    {key = 'frisk', label = 'Досмотр', me = 'надев перчатки, аккуратно проверил одежду и карманы саспекта.', do_text = 'Что удалось обнаружить при досмотре саспекта?', command = '/frisk {id}'},
    {key = 'cuff', label = 'Наручники', me = 'придерживая руку саспекта, достал наручники и аккуратно защёлкнул их на запястьях.', do_text = 'Браслеты наручников зафиксированы и не пережимают запястья.', command = '/cuff {id}'},
    {key = 'release', label = 'Освободить', me = 'вставив ключ в замок, расстегнул наручники и убрал их в подсумок на поясе.', do_text = 'Наручники убраны в подсумок.', command = ''},
}
M.menuKeys = {{'F7', 0x76}, {'F8', 0x77}, {'F9', 0x78}, {'F10', 0x79}}
M.wheelKeys = {{'X', 0x58}, {'C', 0x43}, {'V', 0x56}, {'B', 0x42}}

function M.finite(x)
    return type(x) == 'number' and x == x and x ~= math.huge and x ~= -math.huge
end
function M.validId(id)
    return M.finite(id) and id >= 0 and id <= 1003 and id == math.floor(id)
end
function M.keyAllowed(key, choices)
    for _, choice in ipairs(choices) do if key == choice[2] then return true end end
    return false
end
function M.keyName(key)
    for _, choices in ipairs({M.menuKeys, M.wheelKeys}) do
        for _, choice in ipairs(choices) do if key == choice[2] then return choice[1] end end
    end
    return '?'
end

-- Reject overlong encodings, surrogates, invalid continuation bytes and truncation.
function M.validUtf8(s)
    if type(s) ~= 'string' then return false end
    local i = 1
    while i <= #s do
        local b = s:byte(i)
        local count, low, high = 0, 0x80, 0xBF
        if b < 0x80 then count = 0
        elseif b >= 0xC2 and b <= 0xDF then count = 1
        elseif b >= 0xE0 and b <= 0xEF then
            count = 2
            if b == 0xE0 then low = 0xA0 elseif b == 0xED then high = 0x9F end
        elseif b >= 0xF0 and b <= 0xF4 then
            count = 3
            if b == 0xF0 then low = 0x90 elseif b == 0xF4 then high = 0x8F end
        else return false end
        if i + count > #s then return false end
        for n = 1, count do
            local c = s:byte(i + n)
            if c < (n == 1 and low or 0x80) or c > (n == 1 and high or 0xBF) then return false end
        end
        i = i + count + 1
    end
    return true
end

local function cleanLine(value, limit)
    if type(value) ~= 'string' then return nil, 'Текст должен быть строкой.' end
    if value:find('%c') then return nil, 'Управляющие символы и переносы строк запрещены.' end
    if not M.validUtf8(value) then return nil, 'Текст повреждён: нужен UTF-8.' end
    local line = value:match('^%s*(.-)%s*$')
    if #line > limit then return nil, 'Слишком длинный текст.' end
    return line
end

function M.widgetDefaults()
    return {visible = true, x = 8, y = 170, scale = 1, time_source = 'local'}
end

function M.recoveryDefaults()
    return {enabled=true,delay_ms=3000,max_attempts=3,stable_ms=60000,demo_after_recovery=true}
end
function M.validateRecovery(value)
    if type(value)~='table'or type(value.enabled)~='boolean'or type(value.demo_after_recovery)~='boolean'then
        return nil,'Проверьте переключатели восстановления PA.'
    end
    for _,p in ipairs({{'delay_ms',1000,30000},{'max_attempts',1,5},{'stable_ms',1000,600000}})do
        local n=value[p[1]]
        if not M.finite(n)or n~=math.floor(n)or n<p[2]or n>p[3]then return nil,'Недопустимое значение восстановления: '..p[1]end
    end
    return true
end

function M.validateWidget(w)
    if type(w) ~= 'table' or type(w.visible) ~= 'boolean' then
        return nil, 'Некорректные настройки компактного виджета.'
    end
    for _, key in ipairs({'x', 'y'}) do
        if not M.finite(w[key]) or w[key] < 0 or w[key] > 32768 then
            return nil, 'Положение виджета должно быть в пределах экрана.'
        end
    end
    if not M.finite(w.scale) or w.scale < 0.65 or w.scale > 2 then
        return nil, 'Масштаб виджета должен быть от 0.65 до 2.'
    end
    if w.time_source ~= 'local' and w.time_source ~= 'game' then
        return nil, 'Выберите часы компьютера или игровые часы.'
    end
    return true
end

function M.defaults()
    local cfg = {main = {schema = M.SCHEMA, show_on_connect = true, menu_key = 0x78,
        radial_key = 0x58, max_distance = 8, interval_ms = 1500, demo_mode = true},
        widget = M.widgetDefaults(),recovery=M.recoveryDefaults()}
    for _, a in ipairs(M.actions) do
        cfg[a.key] = {enabled = a.enabled~=false, me = a.me, do_text = a.do_text, command = a.command}
    end
    return cfg
end

function M.validateSettings(cfg)
    if type(cfg) ~= 'table' or type(cfg.main) ~= 'table' then return nil, 'Нет раздела main.' end
    local m = cfg.main
    if m.schema ~= M.SCHEMA then return nil, 'Неизвестная версия настроек.' end
    if type(m.demo_mode) ~= 'boolean' or type(m.show_on_connect) ~= 'boolean' then
        return nil, 'Режимы должны быть true или false.'
    end
    if not M.keyAllowed(m.menu_key, M.menuKeys) or not M.keyAllowed(m.radial_key, M.wheelKeys) then
        return nil, 'Выберите клавиши из списка.'
    end
    if not M.finite(m.max_distance) or m.max_distance < 3 or m.max_distance > 12 then
        return nil, 'Дистанция должна быть от 3 до 12 метров.'
    end
    if not M.finite(m.interval_ms) or m.interval_ms < 1000 or m.interval_ms > 5000 or
        m.interval_ms ~= math.floor(m.interval_ms) then
        return nil, 'Интервал должен быть целым числом от 1000 до 5000 мс.'
    end
    if cfg.recovery~=nil then local ok,err=M.validateRecovery(cfg.recovery);if not ok then return nil,err end end
    if cfg.widget ~= nil then return M.validateWidget(cfg.widget) end
    return true
end

function M.validateAction(entry)
    if type(entry) ~= 'table' then return nil, 'Нет настроек действия.' end
    if entry.enabled ~= nil and type(entry.enabled) ~= 'boolean' then return nil, 'Некорректный флаг enabled.' end
    local out = {enabled = entry.enabled ~= false}
    for _, field in ipairs({'me', 'do_text', 'command'}) do
        local err
        out[field], err = cleanLine(entry[field], field == 'command' and 64 or M.TEMPLATE_LIMIT)
        if not out[field] then return nil, field .. ': ' .. err end
    end
    if out.command ~= '' and not out.command:match('^/[A-Za-z][A-Za-z0-9_]* {id}$') then
        return nil, 'Команда должна иметь вид /command {id}.'
    end
    if out.enabled and out.me == '' and out.do_text == '' and out.command == '' then
        return nil, 'Добавьте текст или отключите действие.'
    end
    return out
end

local function parseBool(v)
    if v == true or v == 'true' then return true end
    if v == false or v == 'false' then return false end
    return nil
end

-- Each damaged field recovers independently. Recovery always starts in demo.
function M.normalizeConfig(raw)
    local cfg, warnings = M.defaults(), {}
    local function warn(s) warnings[#warnings + 1] = s end
    if type(raw) ~= 'table' or type(raw.main) ~= 'table' then
        warn('Повреждён раздел main. Загружены безопасные настройки.')
        return cfg, warnings
    end
    local schema = raw.main.schema == nil and 1 or tonumber(raw.main.schema)
    if schema ~= 1 and schema ~= M.SCHEMA then
        warn('Неизвестная версия INI. Загружены безопасные настройки.')
        return cfg, warnings
    end
    for _, key in ipairs({'demo_mode', 'show_on_connect'}) do
        if raw.main[key] ~= nil then
            local v = parseBool(raw.main[key])
            if v == nil then warn('Некорректный main.' .. key) else cfg.main[key] = v end
        end
    end
    for _, key in ipairs({'menu_key', 'radial_key', 'max_distance', 'interval_ms'}) do
        if raw.main[key] ~= nil then
            local trial = M.defaults()
            trial.main[key] = tonumber(raw.main[key])
            if M.validateSettings(trial) then cfg.main[key] = trial.main[key]
            else warn('Некорректный main.' .. key) end
        end
    end
    for _, a in ipairs(M.actions) do
        if raw[a.key] ~= nil then
            local entry = raw[a.key]
            local candidate
            if type(entry) == 'table' then
                candidate = {me = entry.me, do_text = entry.do_text, command = entry.command,
                    enabled = entry.enabled == nil and true or parseBool(entry.enabled)}
                if entry.enabled ~= nil and candidate.enabled == nil then candidate.enabled = 'invalid' end
            end
            local clean = M.validateAction(candidate)
            if clean then cfg[a.key] = clean
            else
                cfg[a.key] = {enabled = false, me = '', do_text = '', command = ''}
                warn('Действие ' .. a.label .. ' отключено из-за повреждённых настроек.')
            end
        else
            cfg[a.key] = {enabled = false, me = '', do_text = '', command = ''}
            warn('Отсутствует раздел ' .. a.key .. '; действие отключено.')
        end
    end
    if #warnings > 0 then cfg.main.demo_mode = true end
    -- Older schema-2 files have no widget section. Cosmetic recovery must not
    -- alter RP mode or actions; those have already been validated above.
    if raw.widget ~= nil then
        if type(raw.widget) ~= 'table' then
            warn('Повреждён раздел widget; восстановлен виджет по умолчанию.')
        else
            for _, key in ipairs({'visible', 'x', 'y', 'scale', 'time_source'}) do
                local value = raw.widget[key]
                if value ~= nil then
                    if key == 'visible' then value = parseBool(value)
                    elseif key ~= 'time_source' then value = tonumber(value) end
                    local trial = M.widgetDefaults()
                    trial[key] = value
                    if M.validateWidget(trial) then cfg.widget[key] = value
                    else warn('Некорректный widget.' .. key .. '; восстановлено значение по умолчанию.') end
                end
            end
        end
    end
    if raw.recovery~=nil then
        if type(raw.recovery)~='table'then warn('Повреждены настройки восстановления PA; взяты стандартные значения.')
        else
            for key,default in pairs(M.recoveryDefaults())do
                local value=raw.recovery[key]
                if value~=nil then
                    if type(default)=='boolean'then value=parseBool(value)else value=tonumber(value)end
                    local trial=M.recoveryDefaults();trial[key]=value
                    if M.validateRecovery(trial)then cfg.recovery[key]=value
                    else warn('Некорректный recovery.'..key..'; взято стандартное значение.')end
                end
            end
        end
    end
    return cfg, warnings
end

function M.compileAction(entry, id)
    local e, err = M.validateAction(entry)
    if not e then return nil, err end
    if not e.enabled then return nil, 'Это действие отключено.' end
    if not M.validId(id) then return nil, 'Нет допустимого SA:MP ID.' end
    local lines = {}
    if e.me ~= '' then lines[#lines + 1] = '/me ' .. e.me end
    if e.do_text ~= '' then lines[#lines + 1] = '/do ' .. e.do_text end
    if e.command ~= '' then lines[#lines + 1] = (e.command:gsub('{id}', tostring(id))) end
    return lines
end

function M.encodeWire(text, codec)
    if type(text) ~= 'string' or not M.validUtf8(text) or text:find('%c') then return nil, 'Повреждённая строка.' end
    if type(codec) ~= 'table' or type(codec.encode) ~= 'function' or type(codec.decode) ~= 'function' then
        return nil, 'Недоступен преобразователь CP1251.'
    end
    local ok, wire = pcall(codec.encode, text)
    if not ok or type(wire) ~= 'string' or #wire == 0 or #wire > M.WIRE_LIMIT or wire:find('%c') then
        return nil, 'Строка не помещается в лимит чата: 127 байт CP1251.'
    end
    local backOk, back = pcall(codec.decode, wire)
    if not backOk or back ~= text then return nil, 'Текст содержит символы вне CP1251.' end
    return wire
end

function M.prepareAction(entry, id, codec,rpSettings,nickname)
    local lines, err = M.compileAction(entry, id)
    if not lines then return nil, err end
    local out={lines={},wire={},steps={}}
    local rp=require 'pa26_rp_text'
    for i, line in ipairs(lines) do
        local prepared;prepared,err=rp.line(line,codec,rpSettings,nickname)
        if not prepared then return nil,'Строка '..i..': '..err end
        local added;added,err=rp.append(out,prepared);if not added then return nil,err end
    end
    return out
end

function M.targetAllowed(o, maxDistance)
    if type(o) ~= 'table' or not M.finite(maxDistance) or maxDistance < 3 or maxDistance > 12 then return false end
    for _, k in ipairs({'captured', 'exists', 'alive', 'local_alive', 'on_screen', 'streamed',
        'id_match', 'connected', 'line_of_sight'}) do
        if o[k] ~= true then return false end
    end
    return M.validId(o.id) and M.finite(o.distance) and o.distance >= 0 and o.distance <= maxDistance
end

-- Signed/unsigned 32-bit game timer wrap is supported; ordinary clock rollback is rejected.
function M.elapsed(now, before)
    if not M.finite(now) or not M.finite(before) or now ~= math.floor(now) or before ~= math.floor(before) then return nil end
    if now < -2147483648 or now > 4294967295 or before < -2147483648 or before > 4294967295 then return nil end
    local diff = (now - before) % 4294967296
    if diff > 2147483647 then return nil end
    return diff
end

function M.wheelIndex(dx, dy, count, inner, outer)
    if not M.finite(dx) or not M.finite(dy) or not M.finite(count) or count < 1 or
        count > 32 or count ~= math.floor(count) or not M.finite(inner) or not M.finite(outer) or
        inner < 0 or outer <= inner then return nil end
    local d2 = dx * dx + dy * dy
    if not M.finite(d2) or d2 <= inner * inner or d2 > outer * outer then return nil end
    local best, score
    for i = 1, count do
        local a = -math.pi / 2 + (i - 1) * 2 * math.pi / count
        local dot = dx * math.cos(a) + dy * math.sin(a)
        if not score or dot > score then best, score = i, dot end
    end
    return best
end

-- Clockwise from the top divider, matching the user's six-sector reference.
M.wheelSlots = {2, 4, 5, 6, 3, 1}

function M.capturedTargetValid(target)
    return type(target) == 'table' and M.validId(target.id) and M.finite(target.ped) and
        target.ped >= 0 and target.ped <= 2147483647 and target.ped == math.floor(target.ped) and
        type(target.name) == 'string' and #target.name > 0 and #target.name <= 24
end

function M.radialAction(dx, dy, inner, outer)
    if not M.finite(dx) or not M.finite(dy) or not M.finite(inner) or not M.finite(outer) or
        inner <= 0 or outer <= inner then return nil end
    local distance = dx * dx + dy * dy
    if not M.finite(distance) or distance <= inner * inner or distance > outer * outer then return nil end
    local angle = (math.atan2(dy, dx) + math.pi / 2) % (math.pi * 2)
    local slot = math.floor(angle / (math.pi / 3)) + 1
    return M.wheelSlots[math.min(slot, 6)]
end

function M.cameraScore(x, y, width, height)
    if not M.finite(x) or not M.finite(y) or not M.finite(width) or not M.finite(height) or
        width < 300 or height < 300 or width > 32768 or height > 32768 or
        x < 0 or y < 0 or x > width or y > height then return nil end
    local radius = math.min(width, height) * .10
    local dx, dy = x - width / 2, y - height / 2
    local distance = math.sqrt(dx * dx + dy * dy) / radius
    if not M.finite(distance) or distance > 1 then return nil end
    return distance
end

-- GTA's remote-ped area byte may remain zero for a streamed multiplayer actor
-- inside the local interior. Zero is not proof that this actor is outdoors.
-- This is only an area compatibility precheck: streaming, visibility, LOS,
-- identity and distance must still pass before selecting or using the actor.
function M.pedAreaCompatible(localArea,remoteArea)
    local function valid(n)return M.finite(n)and n%1==0 and n>=0 and n<=255 end
    return valid(localArea)and valid(remoteArea)and(remoteArea==0 or localArea==remoteArea)
end
return M

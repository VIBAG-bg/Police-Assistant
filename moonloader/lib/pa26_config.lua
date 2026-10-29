-- Original bounded INI reader and replace-with-backup writer. No executable config.
local core = require 'pa26_core'
local M = {MAX_BYTES = 32768}
M.fs = {
    exists = function(path)
        local f = io.open(path, 'rb')
        if not f then return false end
        f:close()
        return true
    end,
    read = function(path)
        local f, err = io.open(path, 'rb')
        if not f then return nil, err end
        local text = f:read(M.MAX_BYTES + 1)
        f:close()
        return text or ''
    end,
    write = function(path, text)
        local f, err = io.open(path, 'wb')
        if not f then return nil, err end
        local ok, failure = f:write(text)
        if ok then ok, failure = f:flush() end
        local closed, closeErr = f:close()
        if not ok or not closed then return nil, failure or closeErr end
        return true
    end,
    -- Retry only the same operation. Never unlink an occupied destination:
    -- save() owns the verified rollback/backup transaction, not this adapter.
    rename = function(from,to)
        local ok,err,code
        for attempt=1,3 do ok,err,code=os.rename(from,to);if ok then return ok end end
        return nil,err,code
    end,
    remove = function(path)
        local ok,err,code
        for attempt=1,3 do ok,err,code=os.remove(path);if ok then return ok end end
        return nil,err,code
    end,
}

local function call(fs, name, ...)
    local ok, value, err = pcall(fs[name], ...)
    if not ok then return nil, 'Ошибка файловой операции ' .. name end
    return value, err
end

function M.parse(text)
    if type(text) ~= 'string' or #text > M.MAX_BYTES then return nil, 'INI слишком велик.' end
    text = text:gsub('^\239\187\191', ''):gsub('\r\n', '\n')
    if text:find('\0', 1, true) or text:find('\r', 1, true) or not core.validUtf8(text) then
        return nil, 'INI повреждён или имеет неверную кодировку.'
    end
    local raw, section, lineNo = {}, nil, 0
    for line in (text .. '\n'):gmatch('(.-)\n') do
        lineNo = lineNo + 1
        local trimmed = line:match('^%s*(.-)%s*$')
        if trimmed ~= '' and trimmed:sub(1, 1) ~= ';' and trimmed:sub(1, 1) ~= '#' then
            local name = trimmed:match('^%[([A-Za-z][A-Za-z0-9_]*)%]$')
            if name then
                if raw[name] then return nil, 'Повторный раздел INI: ' .. name end
                raw[name], section = {}, name
            else
                local key, value = line:match('^%s*([A-Za-z][A-Za-z0-9_]*)%s*=(.*)$')
                if not section or not key or raw[section][key] ~= nil then
                    return nil, 'Некорректная строка INI: ' .. lineNo
                end
                raw[section][key] = value:match('^%s*(.-)%s*$')
            end
        end
    end
    if not raw.main then return nil, 'В INI отсутствует раздел main.' end
    return raw
end

function M.serialize(cfg)
    local ok, err = core.validateSettings(cfg)
    if not ok then return nil, err end
    local lines = {'; Police Assistant 2026 | UTF-8 | schema 2', '[main]'}
    for _, key in ipairs({'schema', 'show_on_connect', 'menu_key', 'radial_key',
        'max_distance', 'interval_ms', 'demo_mode'}) do
        lines[#lines + 1] = key .. '=' .. tostring(cfg.main[key])
    end
    local widget = cfg.widget or core.widgetDefaults()
    lines[#lines + 1] = '\n[widget]'
    for _, key in ipairs({'visible', 'x', 'y', 'scale', 'time_source'}) do
        lines[#lines + 1] = key .. '=' .. tostring(widget[key])
    end
    lines[#lines+1]='\n[recovery]'
    local recovery=cfg.recovery or core.recoveryDefaults()
    for _,key in ipairs({'enabled','delay_ms','max_attempts','stable_ms','demo_after_recovery'})do
        lines[#lines+1]=key..'='..tostring(recovery[key])
    end
    for _, a in ipairs(core.actions) do
        local entry
        entry, err = core.validateAction(cfg[a.key])
        if not entry then return nil, a.label .. ': ' .. err end
        lines[#lines + 1] = '\n[' .. a.key .. ']'
        for _, key in ipairs({'enabled', 'me', 'do_text', 'command'}) do
            lines[#lines + 1] = key .. '=' .. tostring(entry[key])
        end
    end
    return table.concat(lines, '\n') .. '\n'
end

function M.load(path, fs)
    fs = fs or M.fs
    local warnings = {}
    local text, err = call(fs, 'read', path)
    local raw
    if text then raw, err = M.parse(text) end
    if raw then return core.normalizeConfig(raw) end
    local rollback = call(fs, 'read', path .. '.rollback')
    local backup = rollback or call(fs, 'read', path .. '.bak')
    local backupRaw = backup and M.parse(backup)
    if not backupRaw and rollback then
        backup = call(fs, 'read', path .. '.bak')
        backupRaw = backup and M.parse(backup)
    end
    if backupRaw then
        local cfg, notes = core.normalizeConfig(backupRaw)
        warnings[1] = 'Загружена проверенная резервная копия INI; сохранён записанный в ней режим.'
        for _, note in ipairs(notes) do warnings[#warnings + 1] = note end
        return cfg, warnings
    end
    warnings[1] = text and ('INI не загружен: ' .. tostring(err)) or
        'INI не найден или недоступен. Загружены безопасные настройки.'
    local fallback=core.defaults()
    return fallback, warnings
end

local function finishBackup(path, fs)
    local previous = call(fs, 'read', path .. '.rollback')
    local raw = previous and M.parse(previous)
    local _, notes
    if raw then _, notes = core.normalizeConfig(raw) end
    local destination = path .. (raw and #notes == 0 and '.bak' or '.rejected')
    if call(fs, 'exists', destination) == true and not call(fs, 'remove', destination) then return nil end
    return call(fs, 'rename', path .. '.rollback', destination)
end

function M.save(path, cfg, fs)
    fs = fs or M.fs
    local text, err = M.serialize(cfg)
    if not text then return nil, err end
    local temp, rollback = path .. '.tmp', path .. '.rollback'
    if call(fs, 'exists', rollback) == true then
        local recovered
        if call(fs, 'exists', path) ~= true then recovered = call(fs, 'rename', rollback, path)
        else recovered = finishBackup(path, fs) end
        if not recovered then return nil, 'Не удалось завершить прежнее сохранение; файл .rollback сохранён.' end
    end
    local ok
    ok, err = call(fs, 'write', temp, text)
    if not ok then return nil, 'Запись INI не удалась; прежний файл сохранён.' end
    local check = call(fs, 'read', temp)
    if check ~= text then
        call(fs, 'remove', temp)
        return nil, 'Проверка записанного INI не прошла; прежний файл сохранён.'
    end
    local hadOriginal = call(fs, 'exists', path) == true
    if hadOriginal then
        if not call(fs, 'rename', path, rollback) then
            return nil, 'Не удалось подготовить замену; прежний INI сохранён.'
        end
    end
    if not call(fs, 'rename', temp, path) then
        local restored = not hadOriginal or call(fs, 'rename', rollback, path)
        return nil, restored and 'Замена INI не удалась; прежний файл восстановлен.' or
            'Замена INI не удалась. Прежний файл остался в .rollback.'
    end
    if hadOriginal and not finishBackup(path, fs) then
        return true, 'Новый INI сохранён; предыдущий файл остался в .rollback.'
    end
    return true
end

return M

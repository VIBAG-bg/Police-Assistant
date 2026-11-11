-- One-time author defaults for the 0.46.0 in-game program update.
local core = require 'pa26_core'
local model = require 'pa26_bindings'
local author = require 'pa26_author_presets'
local store = require 'pa26_author_store'
local config = require 'pa26_config'
local users = require 'pa26_user_files'
local jsonStore = require 'pa26_library'
local M = {}

local function map(value)
    if type(value) ~= 'table' then return false end
    for key in pairs(value) do if type(key) ~= 'string' then return false end end
    return true
end

local function useDefaults(current, baseline, official)
    if author.equal(baseline, official) then return model.copy(current) end
    if map(current) and map(baseline) and map(official) then
        local merged = model.copy(current)
        for key, value in pairs(official) do
            merged[key] = useDefaults(current[key], baseline[key], value)
        end
        return merged
    end
    if author.equal(current, baseline) then return model.copy(official) end
    return model.copy(current)
end

local function keepKeys(lib, cfg, current, currentCfg)
    for _, key in ipairs({'quick_key', 'tips_key', 'cancel_key'}) do lib.settings[key] = current.settings[key] end
    for _, spec in ipairs(model.featureKeys) do lib[spec[1]][spec[2]] = model.copy(current[spec[1]][spec[2]]) end
    lib.alert_shortcuts = model.copy(current.alert_shortcuts)
    cfg.main.menu_key, cfg.main.radial_key = currentCfg.main.menu_key, currentCfg.main.radial_key
end

function M.prepare(lib, cfg, json, payload)
    payload = payload or require 'pa26_author_defaults0460'
    local binds, why = author.decode('binds', payload.binds, json)
    if not binds then return nil, why end
    local settings
    settings, why = author.decode('settings', payload.settings, json)
    if not settings then return nil, why end
    local baseline
    baseline, why = author.decode('settings', payload.baseline, json)
    if not baseline then return nil, why end
    local plan
    plan, why = author.prepare('binds', binds, lib, cfg)
    if not plan then return nil, why end
    local current = plan.library
    local official = settings.settings.data
    for _, key in ipairs({'wheel_order', 'wheel_car_order'}) do
        official.settings[key] = require('pa26_author_merge').rebaseOrder(official.settings[key], current)
    end
    local candidate = model.copy(current)
    for key, value in pairs(official) do
        if not author.protected[key] then
            candidate[key] = useDefaults(current[key], baseline.settings.data[key], value)
        end
    end
    -- The previous public preset had 8 foot slots and 6 car slots.
    for key, previous in pairs({wheel_child_limit=8, wheel_car_child_limit=6}) do
        if current.settings[key] == previous then candidate.settings[key] = settings.settings.data.settings[key] end
    end
    candidate.settings.updates = model.copy(current.settings.updates)
    candidate.settings.wheel_car_classic = model.copy(current.settings.wheel_car_classic)
    candidate.assist.history = model.copy(current.assist.history)
    candidate.alerts.on_duty = current.alerts.on_duty
    local expectedLayout = baseline.settings.data.settings.window_layout
    if not author.equal(current.settings.window_layout, expectedLayout) then
        candidate.settings.window_layout = model.copy(current.settings.window_layout)
    end
    local baselineCfg = core.normalizeConfig(baseline.config)
    local officialCfg = core.normalizeConfig(settings.config)
    local nextCfg = useDefaults(cfg, baselineCfg, officialCfg)
    nextCfg.main.demo_mode = cfg.main.demo_mode
    if not author.equal(cfg.widget, baselineCfg.widget) then nextCfg.widget = model.copy(cfg.widget) end
    candidate.settings.applied_author_defaults_0460 = true
    local clean
    clean, why = model.validate(candidate, nextCfg)
    if not clean then
        -- Existing shortcuts have priority over an imported combination.
        keepKeys(candidate, nextCfg, current, cfg)
        clean, why = model.validate(candidate, nextCfg)
    end
    if not clean then return nil, why end
    return {kind='upgrade0460', library=clean, config=nextCfg}
end

function M.apply(workspace, cfg, io, hash, lock, newId)
    if core.VERSION ~= '0.46.1' or workspace.library.settings.applied_author_defaults_0460 then return true end
    if not io then return nil, 'Хранилище авторских наборов недоступно.' end
    local files = workspace.userFiles
    if files.blocked then return nil, files.blocked end
    local fs = io.fs
    local before = store.snapshot(workspace.base, 'upgrade0460', fs)
    for _, key in ipairs({'binds', 'settings'}) do
        local part = before[key] and jsonStore.decode(before[key], workspace.json, function(raw) return users.validate(key, raw, cfg) end)
        if not part or not author.equal(part, files.known[key]) or before[key] ~= files.raw[key] then
            return nil, 'Бинды или настройки изменились на диске либо требуют восстановления.'
        end
    end
    local raw = before.config and config.parse(before.config)
    if not raw then return nil, 'Требуется действующий INI PA.' end
    local diskCfg, warnings = core.normalizeConfig(raw)
    -- A recovery launch may switch the in-memory demo flag for this session.
    diskCfg.main.demo_mode = cfg.main.demo_mode
    if #warnings > 0 or not author.equal(diskCfg, cfg) then return nil, 'INI изменился или требует восстановления.' end
    local prepared, why = M.prepare(workspace.library, cfg, workspace.json)
    if not prepared then return nil, why end
    local id = newId()
    if not id then return nil, 'Не удалось создать номер резервной копии.' end
    local ok, backup = store.apply(workspace.base, prepared, before, workspace.json, fs, hash, lock, id)
    if not ok then return nil, backup end
    return true, backup, prepared
end

return M

-- Installer only. The caller supplies decoded data and writes the verified plan.
local author = require 'pa26_author_presets'
local merge = require 'pa26_author_merge'
local model = require 'pa26_bindings'
local config = require 'pa26_config'
local core = require 'pa26_core'
local users = require 'pa26_user_files'
local binder = require 'pa26_binder'

local function check(value, reason)
    if not value then error(reason or 'Повреждены данные для переноса.', 0) end
    return value
end

local function installed(input)
    local cfg = core.defaults()
    if input.ini then
        local parsed = check(config.parse(input.ini))
        local warnings
        cfg, warnings = core.normalizeConfig(parsed)
        check(#warnings == 0, 'INI содержит повреждённые значения. Восстановите рабочую копию перед переносом.')
    end
    local count = (input.binds and 1 or 0) + (input.settings and 1 or 0) + (input.notes and 1 or 0)
    if count == 3 then
        check(input.ini, 'Для проверки личных клавиш нужен действующий INI.')
        local parts = {}
        for _, kind in ipairs({'binds', 'settings', 'notes'}) do
            parts[kind] = check(users.validate(kind, input[kind], cfg))
        end
        return check(users.combine(parts, cfg)), cfg
    end
    check(count == 0, 'Личная библиотека неполная. Восстановите бинды, настройки и заметки перед переносом.')
    if input.library then
        check(input.ini, 'Для проверки личных клавиш нужен действующий INI.')
        local default = model.defaults(cfg)
        for key in pairs(input.library) do
            check(default[key] ~= nil, 'Неизвестное поле старой библиотеки: '..tostring(key))
        end
        return check(model.validate(input.library, cfg)), cfg
    end
    return model.defaults(cfg), cfg
end

local function matchLegacy(binding, legacy)
    if binding.knowledge and binding.knowledge.personal_origin then return end
    local function find(rows)
        for _, row in ipairs(rows) do
            if row.id == binding.id then
                local command = row.command ~= '' and row.command == binding.command
                if command or row.name == binding.name and row.category == binding.category then return row end
            end
        end
    end
    if binding.author_ref then
        for _, row in ipairs(legacy.author) do
            if binding.author_ref == string.format('A%02d',row.id) then return row end
        end
    else
        return find(legacy.author) or find(legacy.builtins)
    end
end

local function keepPersonalSettings(out, current, legacy, review)
    for key in pairs(author.protected) do out[key] = model.copy(current[key]) end
    out.assist.history = model.copy(current.assist.history)
    out.assist.training.cards = model.copy(current.assist.training.cards)
    out.assist.training.progress = model.copy(current.assist.training.progress)
    out.assist.training.next_id = current.assist.training.next_id
    out.radio_guard.custom = model.copy(current.radio_guard.custom)
    out.radio_guard.next_id = current.radio_guard.next_id
    out.patrol_session.crew = model.copy(current.patrol_session.crew)
    out.patrol_session.unit_number = current.patrol_session.unit_number
    out.vehicle.model_aliases = model.copy(current.vehicle.model_aliases)
    out.vehicle.color_aliases = model.copy(current.vehicle.color_aliases)
    out.map_grid.labels = model.copy(current.map_grid.labels)
    out.settings.updates = model.copy(current.settings.updates)
    out.settings.window_layout.windows = model.copy(current.settings.window_layout.windows)
    out.field.pinned = model.copy(current.field.pinned)
    out.field.coordinates.phone = current.field.coordinates.phone
    out.field.navigation.road_external = current.field.navigation.road_external
    for _, key in ipairs({'lines', 'tag', 'presets'}) do
        out.field.leadership[key] = model.copy(current.field.leadership[key])
    end
    if legacy.saved_briefings then out.field.leadership.briefings = model.copy(current.field.leadership.briefings) end
    local known = {}
    for _, name in ipairs(legacy.manual_heads) do known[name] = true end
    for name, rule in pairs(current.settings.manual_actions.rules) do
        if not known[name] and legacy.saved_manual[name] ~= nil then
            if out.settings.manual_actions.rules[name] then
                review.conflicts[#review.conflicts+1] = '/'..name..': сохранено отдельно созданное правило.'
            end
            out.settings.manual_actions.rules[name] = model.copy(rule)
            review.personalRules[#review.personalRules+1] = '/'..name
        end
    end
    table.sort(review.personalRules)
    for _, command in ipairs(current.operations.commands) do
        local knownCommand = false
        for _, other in ipairs(out.operations.commands) do if other == command then knownCommand = true; break end end
        if not knownCommand then out.operations.commands[#out.operations.commands+1] = command end
    end
end

local function reserveKeys(out, cfg, previous, previousCfg, keys, keyCodes, review)
    local windows = {}
    local function reserve(label, key, fallback)
        if key == 0 then return 0 end
        if keyCodes[key] or windows[key] then
            local nextKey = fallback ~= 0 and not keyCodes[fallback] and not windows[fallback] and fallback or 0
            review.conflicts[#review.conflicts+1] = label..': '..model.keyName(key)..' занята. '..model.keyName(nextKey)..' сохранена для окна.'
            key = nextKey
        end
        if key ~= 0 then windows[key] = true end
        return key
    end
    if keyCodes[cfg.main.menu_key] or keyCodes[cfg.main.radial_key] then
        cfg.main.menu_key = previousCfg.main.menu_key
        cfg.main.radial_key = previousCfg.main.radial_key
        review.conflicts[#review.conflicts+1] = 'Главное меню и колесо сохранили прежние клавиши, чтобы не занять личные сочетания.'
    end
    windows[cfg.main.menu_key], windows[cfg.main.radial_key] = true, true
    for _, key in ipairs({'quick_key', 'tips_key', 'cancel_key'}) do
        out.settings[key] = reserve(key,out.settings[key],previous.settings[key])
    end
    for _, item in ipairs(model.featureKeys) do
        local key = out[item[1]][item[2]]
        if key.key ~= 0 then
            local occupied = windows[key.key] or keys[model.shortcutName(key)]
            if occupied then
                local old = previous[item[1]][item[2]]
                local free = old and old.key ~= 0 and not windows[old.key] and not keys[model.shortcutName(old)]
                local replacement = free and model.copy(old) or {key=0,ctrl=false,alt=false,shift=false}
                review.conflicts[#review.conflicts+1] = item[3]..': '..model.shortcutName(key)..' занято. Назначение: '..model.shortcutName(replacement)..'.'
                out[item[1]][item[2]] = replacement
                key = replacement
            end
            if key.key ~= 0 then keys[model.shortcutName(key)] = true end
        end
    end
    return windows
end

return function(input)
    local legacy = input.legacy
    local prior, priorCfg = installed(input)
    local payload = check(author.validate('binds',input.official_binds))
    local settings = check(author.validate('settings',input.official_settings))
    local out, cfg = model.copy(settings.settings.data), model.copy(settings.config)
    local review = {added={},updated={},personal={},conflicts={},personalRules={}}
    out.bindings, out.notes, out.next_note_id = {}, model.copy(prior.notes), prior.next_note_id
    local oldSettings = input.settings and input.settings.data or input.library
    local rawManual = oldSettings and oldSettings.settings and oldSettings.settings.manual_actions
    legacy.saved_manual = rawManual and rawManual.rules or {}
    local rawLeadership = oldSettings and oldSettings.field and oldSettings.field.leadership
    legacy.saved_briefings = rawLeadership and rawLeadership.briefings
    keepPersonalSettings(out,prior,legacy,review)
    -- This plan is committed only by the one-time manual migration.
    out.settings.help.welcome = true
    cfg.main.demo_mode = priorCfg.main.demo_mode
    if input.ini then cfg.widget = model.copy(priorCfg.widget) end

    local matched, count, candidates = {}, {}, {}
    for _, binding in ipairs(prior.bindings) do
        local stock = matchLegacy(binding,legacy)
        if stock then
            candidates[binding.id] = stock
            count[stock.id] = (count[stock.id] or 0) + 1
        end
    end
    local ids, commands, keys, keyCodes, reserved, savedKeys = {}, {}, {}, {}, {}, {}
    local nextId = math.max(payload.next_id, prior.next_id)
    for _, binding in ipairs(payload.bindings) do reserved[binding.id] = true end
    for _, binding in ipairs(prior.bindings) do
        local stock = candidates[binding.id]
        if stock and count[stock.id] == 1 and reserved[stock.id] then
            matched[stock.id] = {binding=binding,stock=stock}
            ids[binding.id] = true
            if not author.equal(binding.shortcut,stock.shortcut) and binding.shortcut.key ~= 0 then
                savedKeys[stock.id] = model.shortcutName(binding.shortcut)
                keys[savedKeys[stock.id]], keyCodes[binding.shortcut.key] = true, true
            end
        else
            local personal = model.copy(binding)
            personal.author_ref = nil -- Ambiguous provenance must not reclassify it on a later import.
            personal.wheel_group, personal.wheel_visible = 'custom', true
            personal.wheel_car_group = 'custom'
            personal.wheel_extra_groups, personal.wheel_car_extra_groups = {}, {}
            out.bindings[#out.bindings+1] = personal
            review.personal[#review.personal+1] = {id=personal.id,name=personal.name,ambiguous=reserved[personal.id] == true}
            ids[personal.id] = true
            for _, command in ipairs(model.bindingCommands(personal)) do commands[command] = true end
            if personal.shortcut.key ~= 0 then
                keys[model.shortcutName(personal.shortcut)] = true
                keyCodes[personal.shortcut.key] = true
            end
        end
    end
    check(#out.bindings+#payload.bindings <= model.MAX_BINDS,
        'Официальный набор и личные бинды не помещаются вместе. Снимите галочку переноса или освободите место в библиотеке.')
    local windows = reserveKeys(out,cfg,prior,priorCfg,keys,keyCodes,review)
    local mapped = {}
    for _, official in ipairs(payload.bindings) do
        local binding = model.copy(official)
        local original = matched[official.id]
        if original then
            local old = original.binding
            binding.id = old.id
            if old.favorite ~= original.stock.favorite then binding.favorite = old.favorite end
            if not author.equal(old.shortcut,original.stock.shortcut) then binding.shortcut = model.copy(old.shortcut) end
            if savedKeys[official.id] then keys[savedKeys[official.id]] = nil end
            review.updated[#review.updated+1] = {id=old.id,name=binding.name,before=old.script,after=binding.script}
        else
            if ids[binding.id] then
                binding.id = check(merge.freeId(nextId,ids,reserved))
                review.conflicts[#review.conflicts+1] = 'ID '..official.id..' занят личной записью. «'..binding.name..'» получит ID '..binding.id..'.'
            end
            review.added[#review.added+1] = {id=binding.id,name=binding.name,after=binding.script}
        end
        for _, conflict in ipairs(merge.claimAssignments(binding,commands,keys,windows)) do
            review.conflicts[#review.conflicts+1] = '«'..binding.name..'»: '..conflict..' сохранено у прежнего владельца.'
        end
        ids[binding.id], mapped[official.id] = true,binding.id
        nextId = math.max(nextId,binding.id+1)
        out.bindings[#out.bindings+1] = binding
    end
    out.next_id = nextId
    local function classic(slots)
        local result = {}
        for i,id in ipairs(slots) do result[i] = mapped[id] or 0 end
        return result
    end
    out.wheel = classic(payload.wheel)
    out.settings.wheel_car_classic = classic(payload.wheel_car_classic or payload.wheel)
    for _, key in ipairs({'wheel_order','wheel_car_order'}) do
        out.settings[key] = merge.rebaseOrder(out.settings[key],out)
    end
    for _, binding in ipairs(out.bindings) do check(binder.parse(binding.script)) end
    local clean = check(model.validate(out,cfg))
    local parts = users.partition(clean)
    return {binds=parts.binds,settings=parts.settings,notes=not input.notes and parts.notes or nil,
        ini=check(config.serialize(cfg)),review=review}
end

local core = require 'pa26_core'
local M = {}
local Overlay = {}
Overlay.__index = Overlay

function M.defaults()
    return {welcome=false, visible=true, opacity=.74, scale=1}
end

function M.validate(raw)
    local out = M.defaults()
    if raw == nil then return out end
    if type(raw) ~= 'table' then return nil, 'Повреждены настройки инструкций.' end
    for _, key in ipairs({'welcome', 'visible'}) do
        if raw[key] ~= nil then
            if type(raw[key]) ~= 'boolean' then return nil, 'Проверьте переключатели инструкций.' end
            out[key] = raw[key]
        end
    end
    for _, range in ipairs({{'opacity', .25, 1}, {'scale', .75, 1.5}}) do
        local value = raw[range[1]]
        if value ~= nil then
            if not core.finite(value) or value < range[2] or value > range[3] then
                return nil, 'Проверьте прозрачность и масштаб подсказок клавиш.'
            end
            out[range[1]] = value
        end
    end
    if raw.position ~= nil then
        local pos = raw.position
        if type(pos) ~= 'table' or not core.finite(pos.x) or not core.finite(pos.y) or
            pos.x < 0 or pos.x > 1 or pos.y < 0 or pos.y > 1 then
            return nil, 'Неверное положение подсказок клавиш.'
        end
        out.position = {x=pos.x, y=pos.y}
    end
    return out
end

function M.new(settings)
    return setmetatable({firstPending=settings.welcome == true}, Overlay)
end

function Overlay:shortcuts(menu, wheel, assist)
    local old = self.keys
    if old and old.menu == menu and old.wheel == wheel and old.assist == assist.key and
        old.ctrl == assist.ctrl and old.alt == assist.alt and old.shift == assist.shift then return old end
    local binds = require 'pa26_bindings'
    local function name(key, label)
        return key == 0 and 'Не назначена' or label
    end
    self.keys = {menu=menu, wheel=wheel, assist=assist.key, ctrl=assist.ctrl, alt=assist.alt, shift=assist.shift,
        menuLabel=name(menu, binds.keyName(menu)), wheelLabel=name(wheel, binds.keyName(wheel)),
        assistLabel=name(assist.key, binds.shortcutName(assist))}
    return self.keys
end

function M.instructions(keys)
    return {
        'Главное меню · '..keys.menuLabel..'. Здесь находятся настройки, библиотека биндов, памятки и журнал.',
        'Радиальное колесо · '..keys.wheelLabel..'. Выберите нужный раздел и действие. Пешком и за рулём доступны разные наборы.',
        'Помощники · '..keys.assistLabel..'. Откройте патруль, Copilot, работу с транспортом и служебные процедуры.',
        'GPS и карта Esc. Выберите точку или маршрут в инструментах навигации PA. Маршрут отображается на радаре и на карте паузы, если это включено в настройках.',
        'Патруль и Copilot. Начните смену и выберите ситуацию. PA подскажет подходящий доклад и покажет его перед подтверждением.',
        'RP и команды. В библиотеке можно просмотреть, отредактировать и запустить сценарий. Правила ручных команд находятся в «Чат и команды».',
        'Подсказки клавиш, HUD и масштаб настраиваются в «Экран, HUD и карта → HUD». Полная инструкция всегда доступна в боковом меню.',
    }
end

function Overlay:offer(studio, ready)
    if not self.firstPending or not ready or studio:hasModal() or studio.modalVisible then return end
    self.firstPending = false
    studio.helpGuide = {automatic=true}
end

function M.save(studio, draft)
    studio:autoSettings('help', {'settings', 'help'}, draft)
end

function M.draft(studio)
    local pending = studio.autosaves and studio.autosaves.help
    return require('pa26_bindings').copy(pending and pending.value or studio.lib.settings.help)
end

function M.dismiss(studio, disable)
    local guide = studio.helpGuide
    studio.helpGuide = nil
    if not guide or not (disable or guide.automatic and guide.shown) then return end
    local draft = M.draft(studio)
    draft.welcome = false
    M.save(studio, draft)
end

function M.settings(studio, ui, callbacks)
    local im = studio.imgui
    local draft = M.draft(studio)
    studio:settingsHeading(ui, 'Инструкции и подсказки клавиш')
    draft.visible = studio:check('Показывать подсказки клавиш##pa26-help-visible', draft.visible)
    local opacity = im.new.float(draft.opacity)
    if im.SliderFloat('Прозрачность##pa26-help-opacity', opacity, .25, 1) then draft.opacity = opacity[0] end
    local scale = im.new.float(draft.scale)
    if im.SliderFloat('Масштаб##pa26-help-scale', scale, .75, 1.5) then draft.scale = scale[0] end
    if studio:button('Изменить положение##pa26-help-edit', ui) then callbacks.editHelpPosition(draft.position) end
    if studio:button('Сбросить положение##pa26-help-reset', ui) then draft.position = nil; callbacks.editHelpPosition(nil, true) end
    if studio:button('Открыть инструкции##pa26-help-open', ui) then callbacks.openInstructions() end
    draft.welcome = studio:check('Показывать приветствие при следующем запуске##pa26-help-welcome', draft.welcome)
    ui.text('Перетаскивание доступно в режиме изменения положения. В игре подсказки пропускают все нажатия.')
    M.save(studio, draft)
    studio:autosaveHint(ui, 'help')
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function M.geometry(w, h, width, height, position, avoid)
    local margin = math.min(8, w / 4, h / 4)
    width = math.min(width, w - 2 * margin)
    height = math.min(height, h - 2 * margin)
    local freeX, freeY = w - width - 2 * margin, h - height - 2 * margin
    local initial = position == nil
    position = position or {x=1, y=.075}
    local x, y = margin + freeX * clamp(position.x, 0, 1), margin + freeY * clamp(position.y, 0, 1)
    if initial and avoid and x < avoid.x+avoid.w and x+width > avoid.x and
        y < avoid.y+avoid.h and y+height+margin > avoid.y then
        if avoid.y-height >= 2*margin then y = avoid.y-height-margin
        elseif avoid.x-width >= 2*margin then x = avoid.x-width-margin
        elseif avoid.y+avoid.h+height+2*margin <= h then y = avoid.y+avoid.h+margin end
    end
    return x, y, width, height, margin, freeX, freeY
end

function Overlay:visible(cfg, state, editing)
    if not state or not state.session or not state.focused or not state.alive or state.paused or state.blocked or
        state.recording or state.editingHud or state.modal or state.wheel or state.busy then return false end
    if editing then return state.mainWindow and not state.typing end
    return cfg.visible and not state.window
end

function Overlay:draw(im, ui, cfg, keys, studio, avoid)
    local io = im.GetIO()
    local display = io.DisplaySize
    if display.x < 48 or display.y < 48 then return end
    local edit = self.editing
    local vec = im.ImVec2
    local size = im.GetFontSize() * cfg.scale
    local font = im.GetFont()
    local layout = self.layout
    local wantedWidth = math.max(228 * cfg.scale, 14 * size)
    local x, y, w, _, margin, freeX, freeY = M.geometry(display.x, display.y, wantedWidth, 1)
    if not layout or layout.keys ~= keys or layout.w ~= w or layout.size ~= size or layout.font ~= font then
        local menu = require 'pa26_menu'
        local rows = {}
        for _, text in ipairs({'Клавиши PA', keys.wheelLabel..'  Колесо', keys.menuLabel..'  Главное меню',
            keys.assistLabel..'  Помощники', 'Меню → Инструкции'}) do
            for _, line in ipairs(menu.labelLayout(font, size, math.max(1, w-20), text).lines) do
                rows[#rows+1] = line.text
            end
        end
        layout = {keys=keys, w=w, size=size, rows=rows, font=font, lineHeight=size+3}
        self.layout = layout
    end
    local height
    x, y, w, height, margin, freeX, freeY = M.geometry(display.x, display.y, wantedWidth,
        16 + #layout.rows * layout.lineHeight + (edit and 112 or 0), edit and edit.position or cfg.position, not edit and avoid)
    local flags = im.WindowFlags.NoTitleBar + im.WindowFlags.NoResize + im.WindowFlags.NoMove +
        im.WindowFlags.NoSavedSettings
    if not edit then flags = flags + im.WindowFlags.NoInputs + im.WindowFlags.NoFocusOnAppearing +
        im.WindowFlags.NoScrollbar + im.WindowFlags.NoScrollWithMouse end
    im.PushStyleVarFloat(im.StyleVar.WindowRounding, 9)
    ui.push(function() im.PopStyleVar(1) end)
    im.PushStyleColor(im.Col.WindowBg, im.ImVec4(.035, .09, .15, 1))
    ui.push(function() im.PopStyleColor(1) end)
    im.SetNextWindowBgAlpha(cfg.opacity)
    im.SetNextWindowPos(vec(x, y), im.Cond.Always)
    im.SetNextWindowSize(vec(w, height), im.Cond.Always)
    if edit and not edit.shown then
        edit.shown = true
        if im.SetNextWindowFocus then im.SetNextWindowFocus() end
    end
    local expanded = im.Begin('Клавиши PA##pa26-help-overlay', nil, flags)
    ui.push(function() im.End() end)
    if expanded then
        local origin = im.GetCursorScreenPos()
        local list = im.GetWindowDrawList()
        local tint = im.ColorConvertFloat4ToU32(im.ImVec4(.93, .97, 1, 1))
        for index, line in ipairs(layout.rows) do
            if (index+1)*layout.lineHeight <= height then
                list:AddTextFontPtr(layout.font, size, vec(origin.x, origin.y+(index-1)*layout.lineHeight), tint, line)
            end
        end
        if edit then
            im.InvisibleButton('Перетащить##pa26-help-drag', vec(math.max(1, w-18), #layout.rows*layout.lineHeight))
            if im.IsItemActive() and im.IsMouseDragging(0) then
                edit.position = {
                    x=clamp((x-margin+io.MouseDelta.x)/math.max(1, freeX), 0, 1),
                    y=clamp((y-margin+io.MouseDelta.y)/math.max(1, freeY), 0, 1),
                }
            end
            local half = math.max(1, (im.GetContentRegionAvail().x-8)/2)
            local save = studio:button('Сохранить##pa26-help-place', ui, half)
            im.SameLine(0,8)
            local cancel = studio:button('Отмена##pa26-help-cancel', ui, half)
            if save then
                local draft = M.draft(studio)
                draft.position = edit.position
                M.save(studio, draft)
                self.editing = nil
            elseif studio:button('Скрыть подсказки##pa26-help-hide', ui) then
                local draft = M.draft(studio)
                draft.visible = false
                M.save(studio, draft)
                self.editing = nil
            elseif cancel then
                self.editing = nil
            end
        end
    end
    ui.finish()
    ui.finish()
    ui.finish()
end

return M

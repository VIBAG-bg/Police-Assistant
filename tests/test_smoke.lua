-- Explicit legacy personal fixture: the fresh wanted example is disabled.
local support=require 'support.fixture'
local function fixture(options)options=options or{};options.legacyWanted=true;return support(options)end
local core = require 'pa26_core'

local s = fixture()
s.step()
check(s.hasLog('v'..core.VERSION..': игровой цикл запущен.'),table.concat(s.logs,' | '))
check(s.frames[1].condition())
s.step(); check(s.hasLog('v'..core.VERSION..': окно отрисовано.'))
s.page('binds')
s.edits = {['##script'] = '/me новый текст 100% %s %n'}
s.render(); s.click='Запуск##editor-tab'; s.render(); s.click = 'Предпросмотр текущего текста'; s.render(); s.step()
check(s.hasLog('новый текст 100% %s %n'))
eq(#s.sent, 0)
s.commands.pa26() -- demo wheel also works without a native target
s.render();check(s.workspace.studio.pendingNavigation,'Leaving the dirty preview must first ask about saving')
s.click='Отбросить##changes-discard';s.render();s.step()
s.circlesDrawn=0 -- isolate the wheel from the library's vector information icons
s.aimed = false; s.down[0x58] = true; s.step(16, {[0x58] = true})
check(s.colorConversions >= 2, 'radial colors must convert real FFI vectors')
eq(s.circlesDrawn, 4, 'outer edge and ID hub must finish drawing')
eq(s.pathFills,6,'six reference-style sectors must be drawn')
check(s.frames[2].condition(), 'radial drawing failure disabled the interface')
s.down[0x58] = false; s.step(150); s.step(100)
eq(#s.sent, 0); check(s.hasLog('[ДЕМО БИНД]'))
s.commands.pa26demo() -- live now; camera selection works without native weapon targeting
s.down[0x58] = true; s.step(16, {[0x58] = true})
check(s.frames[2].condition()); eq(#s.sent, 0)
s.commands.pa26cancel()

s = fixture({demo = false}); s.liveAction()
eq(#s.sent, 1)
s.step(1499); eq(#s.sent, 1)
s.step(1); eq(#s.sent, 2)
s.step(1500); eq(#s.sent, 3); eq(s.sent[3].line, '/wanted 37')

-- Slow SA:MP startup uses only the owning main coroutine. No hotkeys or
-- chat commands become active before the availability gate has passed.
s = fixture({available = false})
eq(s.waits[1], 100); eq(s.commands.pa26, nil)
s.step(100); eq(s.commands.pa26, nil)
s.available = true; s.step(100)
check(s.commands.pa26 ~= nil); eq(s.waits[#s.waits], 0)
s.step(); check(s.frames[1].condition())
check(s.hasLog('v'..core.VERSION..': игровой цикл запущен.')); eq(#s.sent, 0)

-- A real host API exception stops the script; termination drops commands,
-- rendering subscriptions and the rest of an already-started chat action.
s = fixture({demo = false}); s.liveAction(); eq(#s.sent, 1)
s.failMain()
eq(s.commands.pa26, nil); check(s.frames[1].removed); check(s.frames[2].removed)
s.step(5000); eq(#s.sent, 1)

-- Failed native send remains one attempt with no automatic retry.
s = fixture({demo = false}); s.sendError = true; s.liveAction()
eq(#s.sent, 0); check(s.hasLog('Ошибка отправки'))
s.sendError = false; s.step(5000); eq(#s.sent, 0)

for _, flag in ipairs({'chat', 'dialog', 'cursor', 'console', 'paused', 'localDead',
    'targetDead', 'coordsError'}) do
    s = fixture({demo = false}); s.liveAction(); eq(#s.sent, 1)
    s[flag] = true; s.step(1500); eq(#s.sent, 1)
    s[flag] = false; s.step(5000); eq(#s.sent, 1)
end
for _, flag in ipairs({'streamed', 'clear', 'onScreen', 'localExists', 'targetExists', 'spawned'}) do
    s = fixture({demo = false}); s.liveAction(); s[flag] = false
    s.step(1500); eq(#s.sent, 1)
end
for _, mutation in ipairs({{'name', 'Other_Name'}, {'id', 38}, {'mappedPed', 100}, {'distance', 20}, {'distance', 0/0}}) do
    s = fixture({demo = false}); s.liveAction(); s[mutation[1]] = mutation[2]
    s.step(1500); eq(#s.sent, 1)
end
for _, event in ipairs({'demo', 'focus', 'escape', 'cancel', 'disconnect', 'server', 'device'}) do
    s = fixture({demo = false}); s.liveAction()
    if event == 'demo' then s.commands.pa26demo()
    elseif event == 'focus' then onWindowMessage(0x0008, 0)
    elseif event == 'escape' then onWindowMessage(0x0100, 0x1B); eq(s.consumed, 0)
    elseif event == 'cancel' then s.commands.pa26cancel()
    elseif event == 'disconnect' then s.connected = false
    elseif event == 'device' then onD3DDeviceLost()
    else s.address = 'other' end
    s.step(1500); eq(#s.sent, 1)
end

-- No unsafe lookup for an out-of-range ID, no stale ID display after lost visibility.
s = fixture({demo = false}); s.step(); s.commands.pa26()
s.id = 1004; s.down[0x58] = true; s.step(16, {[0x58] = true})
eq(s.charLookups, 0); check(s.frames[2].condition()); check(s.hasLog('Нет видимой цели'))
s = fixture({demo = false}); s.step(); s.commands.pa26()
s.down[0x58] = true; s.step(16, {[0x58] = true}); check(s.frames[2].condition())
s.clear = false; s.step(); check(not s.frames[2].condition()); eq(#s.sent, 0)
s = fixture({demo = false}); s.step(); s.commands.pa26()
s.down[0x58] = true; s.step(16, {[0x58] = true})
onWindowMessage(0x0008, 0); onWindowMessage(0x0007, 0)
s.down[0x58] = false; s.step(150); eq(#s.sent, 0)
s = fixture({demo = false}); s.liveAction()
s.paused = true; s.render() -- mimgui's condition updater also runs while the game is paused
s.paused = false; s.step(5000); eq(#s.sent, 1)

-- Draft keys do not take effect on failed save; successful save switches them.
s = fixture(); s.step(); s.page('settings');s.saveFail=true;s.click = 'F10##Клавиша окна4'; s.render()
eq(s.saved, nil)
s.click='ОК##warning-ok'; s.render(); s.render()
s.step(16, {[0x78] = true}); check(not s.frames[1].condition())
s.commands.pa26(); s.saveFail = false; s.click = 'Повторить запись##general-retry'; s.render()
eq(s.saved.main.menu_key, 0x79)
s.step(16, {[0x78] = true}); check(s.frames[1].condition())
s.step() -- release the newly assigned key before it can activate
s.step(16, {[0x79] = true}); check(not s.frames[1].condition())

s = fixture(); s.step(); s.io.WantTextInput = true
s.render() -- input capture is sampled in the owning render callback
s.step(16, {[0x78] = true}); check(not s.frames[1].condition()) -- F9 remains available while editing
s.io.WantTextInput = false; s.render()
s.step() -- the next F9 press starts after a release
s.step(16, {[0x78] = true}); check(s.frames[1].condition())

-- A connection can open the window before D3D has rendered anything. Main may
-- continue for many frames, close/reopen the window and lose/regain focus without
-- touching native ImGuiIO or forcing initialization in the wrong coroutine.
s = fixture({render = false})
for _ = 1, 30 do s.step() end
check(not s.initialized); eq(s.ioReads, 0); eq(s.invalidIOReads, 0)
check(not s.hasLog('окно отрисовано.'))
check(s.frames[1].condition())
s.step(16, {[0x78] = true}); check(not s.frames[1].condition())
s.commands.pa26(); check(s.frames[1].condition())
onWindowMessage(0x0008, 0); onWindowMessage(0x0007, 0)
s.commands.pa26(); s.step()
eq(s.ioReads, 0); eq(#s.sent, 0)
s.renderEnabled = true; s.render()
check(s.initialized); check(s.ioReads > 0); eq(s.invalidIOReads, 0)
s.step(); check(s.hasLog('v'..core.VERSION..': окно отрисовано.'))
s.io.WantTextInput = true; s.render()
onWindowMessage(0x0008, 0); onWindowMessage(0x0007, 0)
s.step() -- a held key from before focus loss cannot reopen the menu
s.step(16, {[0x78] = true}); check(s.frames[1].condition())

-- Device loss closes the window and clears the copied input state. A later
-- reopening again waits for the renderer instead of dereferencing its pointers.
s = fixture(); s.step(); s.io.WantTextInput = true; s.render()
onD3DDeviceLost(); s.renderEnabled = false
s.step(16, {[0x78] = true}); check(s.frames[1].condition())
eq(s.invalidIOReads, 0); eq(#s.sent, 0)
s.renderEnabled = true; s.io.WantTextInput = false; s.render()

-- Server shortcuts pass both event orders: mimgui before the script or after.
-- Test the original message, its key-up, an open window, a closed one, a wheel,
-- and an already-started action. This models the input path, not Exsellent CEF.
for _, libraryFirst in ipairs({false, true}) do
    for _, key in ipairs({0x49, 0x4A, 0x4B}) do
        s = fixture(); s.step()
        eq(s.lockRequests, 0); check(not s.controlLocked)
        check(s.keyMessage(key, libraryFirst))
        check(s.inputDisabled()); check(not s.frames[1].condition())
        check(s.keyMessage(key, libraryFirst, 0x0101))
        s.step(); check(s.keyMessage(key, libraryFirst))
        eq(s.consumed, 0)

        s = fixture(); s.step(); s.commands.pa26()
        check(s.keyMessage(key, libraryFirst)); eq(s.lockRequests, 0)

        s = fixture(); s.step(); s.commands.pa26()
        s.down[0x58] = true; s.step(16, {[0x58] = true})
        check(s.frames[2].condition()); eq(s.lockRequests, 0)
        check(s.keyMessage(key, libraryFirst)); check(not s.frames[2].condition())
        s.down[0x58] = false; s.step(150); eq(#s.sent, 0)

        s = fixture({demo = false}); s.liveAction(); eq(#s.sent, 1)
        check(s.keyMessage(key, libraryFirst)); s.step(5000); eq(#s.sent, 1)

        s = fixture(); s.step(); s.io.WantTextInput = true; s.render()
        check(not s.keyMessage(key, libraryFirst))
        check(s.frames[1].condition()); eq(#s.serverKeys, 0)
        s.commands.pa26(); check(s.keyMessage(key, libraryFirst))
    end
end

-- Login takes precedence. Auto-open waits for a live character and clear input,
-- and an early server key cancels the pending popup instead of stealing focus.
s = fixture(); s.spawned = false; s.dialog = true; s.step()
check(not s.frames[1].condition()); check(s.inputDisabled()); eq(s.lockRequests, 0)
s.dialog = false; s.step(); check(not s.frames[1].condition())
s.spawned = true; s.step(); check(s.frames[1].condition())
s = fixture(); s.spawned = false; s.step()
check(s.keyMessage(0x4A, true)); s.spawned = true; s.step()
check(not s.frames[1].condition())
s = fixture(); s.step(); s.dialog = true; s.step()
check(not s.frames[1].condition()); check(s.inputDisabled())
s = fixture({externalLocked = true}); s.step(); s.commands.pa26(); s.step()
check(s.controlLocked); eq(s.lockRequests, 0) -- no global force-unlock of the server

s = fixture(); s.step(); s.page('addons'); s.widgetError = true; s.render()
eq(#s.scopes, 0); check(s.hasLog('Ошибка интерфейса')); eq(#s.sent, 0)
s = fixture(); s.io.DisplaySize.x, s.io.DisplaySize.y = 100, 100; s.step()
eq(#s.scopes, 0)
s = fixture(); s.io.DisplaySize.x, s.io.DisplaySize.y = 640, 480; s.collapsed = true; s.step()
eq(#s.scopes, 0)

s = fixture(); s.step(); onScriptTerminate({})
check(s.commands.pa26 ~= nil)
onScriptTerminate(s.script)
eq(s.commands.pa26, nil); check(s.frames[1].removed); check(s.fontUnsubscribed)
s = fixture({missingApi = true})
check(s.hasLog('Missing API: sampIsChatInputActive'))
s = fixture({missingAvailability = true})
check(s.hasLog('Missing API: isSampAvailable'))
s = fixture({missingLibrary = true})
eq(#s.frames, 0); check(s.hasLog('missing mimgui'))

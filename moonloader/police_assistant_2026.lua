script_name('Police Assistant 2026')
script_author('VIBAG ( Victor Auditore )')
script_version('0.43.4')
script_description('Editable bind library, quick palette, notes and confirmed local journal')
if type(script_properties) == 'function' then script_properties('work-in-pause') end

-- This bootstrap runs before any replaceable PA dependency is loaded.
do
    local ok,platform=pcall(require,'pa26_update_platform')
    if not ok then function main()print('PA update bootstrap missing. Reinstall the complete PA package.')end;return end
    local ready,p=pcall(platform.new,getWorkingDirectory())
    if ready and p and p:gate()then function main()end;return end
end
require('pa26_startup').clear(getWorkingDirectory())
local missing = {}
local function dependency(name)
    local ok, value = pcall(require, name)
    if not ok then
        missing[#missing + 1] = name
        print('[PA26] Cannot load ' .. name .. ': ' .. tostring(value))
        return nil
    end
    return value
end
local core = dependency('pa26_core')
local storage = dependency('pa26_config')
local runtimeModule = dependency('pa26_runtime')
local hudModule = dependency('pa26_hud')
local menuModule = dependency('pa26_menu')
local bindingModel = dependency('pa26_bindings')
local workspaceModule = dependency('pa26_workspace')
local studioModule = dependency('pa26_studio')
local knowledgeModule = dependency('pa26_knowledge')
local knowledgeUiModule = dependency('pa26_knowledge_ui')
local wheelModel = dependency('pa26_wheel')
local alertModule = dependency('pa26_alerts')
local inputModule = dependency('pa26_input')
local preferences = dependency('pa26_preferences')
local patrolModule = dependency('pa26_patrol')
local patrolSessionModule=dependency('pa26_patrol_session')
local patrolEventsModule=dependency('pa26_patrol_events')
local identityModule=dependency('pa26_identity')
local studioClock=0 -- Shared by target scoring and UI; updated only in main.
local sceneServices={rp=dependency('pa26_rp_text'),rpUi=dependency('pa26_rp_ui'),commands=dependency('pa26_server_commands'),model=dependency('pa26_vehicle'),worldModule=dependency('pa26_vehicle_world'),evidenceModule=dependency('pa26_evidence'),filesModule=dependency('pa26_evidence_files'),assistUi=dependency('pa26_assist_ui'),hooks={}}
sceneServices.mapGrid=dependency('pa26_map_grid')
sceneServices.settingsUi=dependency('pa26_settings_ui')
sceneServices.mapAdapterModule=dependency('pa26_map_adapter')
sceneServices.chatModule=dependency('pa26_chat_bridge')
sceneServices.perfModule=dependency('pa26_chat_perf')
sceneServices.manualActionModule=dependency('pa26_manual_actions')
sceneServices.layoutModule=dependency('pa26_keyboard_layout')
sceneServices.targetModule=dependency('pa26_target')
sceneServices.localCommands={}
sceneServices.chatEpoch=0
local caseFormsModule=dependency('pa26_case_forms')
local weaponModule = dependency('pa26_weapons')
local taserModule = dependency('pa26_taser')
local radioGuardModule = dependency('pa26_radio_guard')
local warningModule = dependency('pa26_weapon_warning')
local notificationsModule = dependency('pa26_notifications')
local recoveryModule=dependency('pa26_recovery')
local bit = dependency('bit')
local ffi = dependency('ffi')
local encoding = dependency('encoding')
local imgui = dependency('mimgui')
if #missing > 0 or not core or core.VERSION ~= '0.43.4' then
    function main()
        local reason=#missing>0 and ('Ошибка запуска: отсутствуют библиотеки ('..table.concat(missing, ', ')..'). Проверьте mimgui и encoding в moonloader/lib.')or 'Ошибка запуска: файлы PA относятся к разным версиям. Повторите установку полного пакета.'
        require('pa26_startup').block(getWorkingDirectory(),reason)
        while type(isSampAvailable)=='function'and not isSampAvailable()and type(wait)=='function'do wait(100)end
        require('pa26_startup').announce(reason,encoding)
    end
    return
end

sceneServices.mapAdapter=sceneServices.mapAdapterModule.new(ffi)
local cp1251 = encoding.CP1251
local codec = {
    encode = function(text) return cp1251:encode(text, 'UTF-8') end,
    decode = function(text) return cp1251:decode(text, 'UTF-8') end,
}
do
    local io=require 'pa26_author_io'
    local loaded,adapter=pcall(io.new,getWorkingDirectory());sceneServices.authorIO=loaded and adapter or nil
    local ok,why=require('pa26_author_store').recover(getWorkingDirectory()..'\\config\\police_assistant_2026',
        {encode=encodeJson,decode=decodeJson},sceneServices.authorIO and sceneServices.authorIO.fs or require('pa26_library').fs,io.hash,io.lock)
    if not ok then function main() require('pa26_startup').announce(why,encoding) end;return end
end
local configPath = getWorkingDirectory() .. '\\config\\police_assistant_2026.ini'
local cfg, configWarnings = storage.load(configPath)
cfg.recovery=cfg.recovery or core.recoveryDefaults()
local guardRestart=recoveryModule.consumeMarker(getWorkingDirectory()..'\\config\\police_assistant_2026_restart.flag',storage.fs)
if guardRestart and cfg.recovery.demo_after_recovery then cfg.main.demo_mode=true end
local recovery=recoveryModule.new()
local recoverUi,recoveryDraft,settingsTab
local new = imgui.new
local showWindow = new.bool(false)
local showQuick, showTips = new.bool(false), new.bool(false)
sceneServices.showAssist=new.bool(false)
sceneServices.showWanted=new.bool(false)
sceneServices.showFine=new.bool(false);sceneServices.showMark=new.bool(false);sceneServices.showGround=new.bool(false)
sceneServices.procedureWindows=function()return sceneServices.showFine[0]or sceneServices.showMark[0]or sceneServices.showGround[0]end
sceneServices.hideProcedureWindows=function()sceneServices.showFine[0]=false;sceneServices.showMark[0]=false;sceneServices.showGround[0]=false end
local workspace, studio, keyRecorder, pendingWheelClick
local knowledge,knowledgeUi
local function hasUiModal() return (studio and(studio:hasModal()or studio.modalVisible)) or (knowledgeUi and knowledgeUi:hasModal()) or false end
local function cancelUiModal()
    if studio then studio:cancelModal()end
    if knowledgeUi then knowledgeUi:cancelModal()end
end
local widgetCursor=false
local manualSpeechFailureAt
local manualInputPrefix
local function ownUi() return showWindow[0] or showQuick[0] or showTips[0] or sceneServices.showAssist[0]or sceneServices.showWanted[0]or sceneServices.procedureWindows()or(studio and(studio:hasModal()or studio.modalVisible))or false end
local demoFlag = new.bool(cfg.main.demo_mode)
local onConnectFlag = new.bool(cfg.main.show_on_connect)
local distanceValue = new.float(cfg.main.max_distance)
local intervalValue = new.int(cfg.main.interval_ms)
local draftMenuKey, draftRadialKey = cfg.main.menu_key, cfg.main.radial_key
local buffers, log = {}, {}
local selectedAction, focused, uiFailed = 1, true, false
-- A plain Lua snapshot, never an ImGuiIO pointer. mimgui initializes lazily and
-- switches contexts inside its render callbacks; main must not access GetIO.
local uiTyping = false
local escDismissed = false
local bindingKeyCaptured = false
local uiInputReset = true
local uiRendered = false
local autoOpenForSession
imgui.DisableInput = true
local runtime,alerts,patrol,weapons,taser,radioGuard,weaponWarning,notifications,patrolSession,patrolEvents,identity,caseForms
local registered, subscriptions = {}, {}
local customRegistered, chatEvents, chatHandler, previousChatHandler = {},nil,nil,nil
local quitHandler, joinHandler, previousQuitHandler, previousJoinHandler
local sendChatHandler,previousSendChatHandler
local sendCommandHandler,previousSendCommandHandler
local damageHandler,previousDamageHandler
local bulletHandler,previousBulletHandler
local aimHandler,previousAimHandler
local lifeHooks={}
local ownedChatSendDepth=0
local ownedSendCancelled=false
local shutdown = false
local hud, widgetFrame
local hudFont, hudHeadingFont
local menuHeadingFont, menuBrandFont, menuBodyFont, menuButtonFont, menuSmallFont, menuCompactFont
local wheelLabelFont, wheelIdFont
local uiGlyphRanges -- keep the native range vector alive until the font atlas is built
local menu = menuModule.new()
local metrics = {sent = 0, previews = 0, connections = 0}
local widgetVisible = new.bool(cfg.widget.visible)
local widgetScale = new.float(cfg.widget.scale)

local function pushLog(message)
    log[#log + 1] = message
    if #log > 200 then table.remove(log, 1) end
    print('[PA26] ' .. message)
end

sceneServices.chatPerf=sceneServices.perfModule.new(sceneServices.perfModule.clock(ffi),pushLog)
menu:configureAssets(getWorkingDirectory() .. '\\resource\\pa26', pushLog)

local function report(message,kind)
    runtime:report(message,kind)
end

local function setBuffer(buffer, text)
    assert(type(text) == 'string' and core.validUtf8(text) and #text < ffi.sizeof(buffer))
    ffi.fill(buffer, ffi.sizeof(buffer))
    ffi.copy(buffer, text, #text)
end

local function loadDraft()
    onConnectFlag[0], distanceValue[0], intervalValue[0] =
        cfg.main.show_on_connect, cfg.main.max_distance, cfg.main.interval_ms
    draftMenuKey, draftRadialKey = cfg.main.menu_key, cfg.main.radial_key
    for _, a in ipairs(core.actions) do
        local b = buffers[a.key]
        if not b then
            b = {enabled = new.bool(), me = new.char[1024](),
                do_text = new.char[1024](), command = new.char[128]()}
            buffers[a.key] = b
        end
        b.enabled[0] = cfg[a.key].enabled
        for _, field in ipairs({'me', 'do_text', 'command'}) do setBuffer(b[field], cfg[a.key][field]) end
    end
end
loadDraft()

local function localAlive()
    return type(PLAYER_PED) == 'number' and doesCharExist(PLAYER_PED) == true and
        sampIsLocalPlayerSpawned() == true and isCharDead(PLAYER_PED) == false
end

-- Optional HUD reads use documented APIs and only the local player's ped.
local function optionalRead(name, ...)
    local fn = _G[name]
    if type(fn) ~= 'function' then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function localPedAvailable()
    return type(PLAYER_PED) == 'number' and optionalRead('doesCharExist', PLAYER_PED) == true
end

local function persistWidget(settings)
    -- Preserve saved RP phrases and mode; moving a HUD cannot save draft edits.
    local candidate = {}
    for section, entries in pairs(cfg) do
        candidate[section] = {}
        for key, value in pairs(entries) do candidate[section][key] = value end
    end
    candidate.widget = settings
    local ok, note = storage.save(configPath, candidate)
    if ok then cfg.widget = settings end
    return ok, note
end

hud = hudModule.new(cfg.widget, {
    localId = function()
        if not localPedAvailable() then return nil end
        local found, id = optionalRead('sampGetPlayerIdByCharHandle', PLAYER_PED)
        if found == true and core.validId(id) then return id end
    end,
    nickname = function(id) return optionalRead('sampGetPlayerNickname', id) end,
    ping = function(id) return optionalRead('sampGetPlayerPing', id) end,
    coordinates = function()
        if localPedAvailable() and optionalRead('sampIsLocalPlayerSpawned') == true then
            return optionalRead('getCharCoordinates', PLAYER_PED)
        end
    end,
    interior = function()
        if localPedAvailable() then return optionalRead('getCharActiveInterior', PLAYER_PED) end
    end,
    zone = function(x, y, z) return optionalRead('getNameOfZone', x, y, z) end,
    zoneText = function(key) return optionalRead('getGxtText', key) end,
    decode = codec.decode,
    wallTime = function() return os.time() end,
    localClock = function() return os.date('%d.%m.%Y %H:%M:%S') end,
    localDate = function() return os.date('%d.%m.%Y') end,
    gameClock = function() return optionalRead('getTimeOfDay') end,
    save = persistWidget,
    log = pushLog,
    beginEdit = function()
        if runtime then runtime:cancel('Взаимодействие с виджетом. Действие отменено.') end
    end,
})

sceneServices.mapSample=function()
    local state={connected=hud.connected==true,focused=focused,paused=optionalRead('isPauseMenuActive')==true or optionalRead('isGamePaused')==true}
    if state.connected and localPedAvailable()and optionalRead('sampIsLocalPlayerSpawned')==true then
        state.x,state.y,state.z=optionalRead('getCharCoordinates',PLAYER_PED)
        state.interior=optionalRead('getCharActiveInterior',PLAYER_PED)
        if core.finite(state.interior)and state.interior>0 then state.area='Interior '..state.interior
        elseif core.finite(state.x)and core.finite(state.y)and core.finite(state.z)then
            local key=optionalRead('getNameOfZone',state.x,state.y,state.z)
            state.zoneKey=key
            local raw=type(key)=='string'and key:match('^[A-Za-z0-9_]+$')and optionalRead('getGxtText',key)or nil
            state.area=hudModule.zoneName(key,raw)
        end
    end
    local library=workspace and workspace.library
    local values=sceneServices.mapGrid.values(library and library.map_grid or sceneServices.mapGrid.defaults(),library and library.profile or{},state.x,state.y,state.interior,state.z,state.zoneKey)
    local session=sceneServices.citySession
    if sceneServices.lastCity and(sceneServices.lastCity.session~=session or sceneServices.lastCity.ped~=PLAYER_PED or not state.connected)then sceneServices.lastCity=nil end
    if values.city and state.interior==0 then sceneServices.lastCity={session=session,ped=PLAYER_PED,city=values.city}
    elseif not values.city and state.interior and state.interior>0 and sceneServices.lastCity then values.city=sceneServices.lastCity.city end
    return state,values
end

local function connectionKey()
    if isSampAvailable() ~= true or sampGetGamestate() ~= 3 then return nil end
    local address, port = sampGetCurrentServerAddress()
    if type(address) ~= 'string' or address == '' or not core.finite(port) or
        port < 1 or port > 65535 or port ~= math.floor(port) then return nil end
    return address .. ':' .. tostring(port)
end

local function context()
    local session = connectionKey()
    local chat, dialog, otherCursor = false, false, false
    local cefBusy,console=false,false
    if session then
        chat, dialog = optionalRead('sampIsChatInputActive'), optionalRead('sampIsDialogActive')
        if sceneServices.chatBridge then
            local busy,cefChat,cefDialog=sceneServices.chatBridge:inputBusy(optionalRead('getGameTimer')or 0,workspace and workspace.library.settings.cef_chat_grace_ms)
            cefBusy=busy
            chat=chat~=false or cefChat;dialog=dialog~=false or cefDialog;otherCursor=busy
        end
        -- mimgui owns its cursor while its windows are visible.
        if not ownUi() and not (runtime and runtime.wheel) and not hud.editing and not widgetCursor then
            otherCursor = otherCursor or sampIsCursorActive()~=false
        end
        if type(isSampfuncsConsoleActive) == 'function' and isSampfuncsConsoleActive() ~= false then otherCursor = true;console=true end
    end
    local inputBlocked=chat~=false or dialog~=false or otherCursor~=false
    local life=sceneServices.localLife and sceneServices.localLife:view()
    local incapacitated=life and life.incapacitated and sceneServices.localLife.session==session or false
    local nativeAlive=session~=nil and localAlive()or false
    return {session = session, focused = focused, paused = isGamePaused(),inputBlocked=inputBlocked,
        nativeAlive=nativeAlive,incapacitated=incapacitated,
        blocked = inputBlocked or incapacitated or life and life.transitioning or false,
        menuBlocked=chat~=false or dialog~=false or cefBusy or console,
        window = ownUi(), ownWindow = ownUi(), typing = ownUi() and (uiTyping or (studio and hasUiModal())),
        recording = keyRecorder ~= nil or bindingKeyCaptured, editingHud = hud.editing or hud.drag ~= nil,
        alive = nativeAlive or incapacitated,
        chatActive = chat ~= false, dialogActive = dialog ~= false}
end

context=sceneServices.chatPerf:wrap('context',context)
-- Native scene reads only: visible, loaded nearby peds; no online-ID sweep.
local function bodyPointVisible(cx, cy, cz, x, y, z, inVehicle, ped)
    if isLineOfSightClear(cx, cy, cz, x, y, z, true, true, false, true, false) == true then return true end
    if not inVehicle then return false end
    -- Keep vehicle/body collisions enabled. Only native see-through materials
    -- (e.g. glass) may pass; never ignore an occupant's whole vehicle.
    local hit,colPoint = optionalRead('processLineOfSight', cx, cy, cz, x, y, z,
        true, true, false, true, true, true, false, false)
    if hit==false then return true end
    if hit==true and ped and type(colPoint)=='table'and colPoint.entityType==2 and core.finite(colPoint.entity)and
        type(_G.getVehiclePointerHandle)=='function'and type(_G.storeCarCharIsInNoSave)=='function'then
        local own=optionalRead('storeCarCharIsInNoSave',ped)
        return core.finite(own)and optionalRead('getVehiclePointerHandle',colPoint.entity)==own and
            optionalRead('isLineOfSightClear',cx,cy,cz,x,y,z,true,false,false,true,false)==true
    end
    return false
end

local function visiblePed(ped, maxDistance)
    if not connectionKey() or not localAlive() or not core.finite(ped) or ped < 0 or ped > 2147483647 or
        ped ~= math.floor(ped) or ped == PLAYER_PED or not core.finite(maxDistance) or
        maxDistance < 3 or maxDistance > 200 or doesCharExist(ped) ~= true or
        isCharDead(ped) ~= false or isCharOnScreen(ped) ~= true then return nil end
    local ownInterior=optionalRead('getCharActiveInterior',PLAYER_PED)
    local otherInterior=optionalRead('getCharActiveInterior',ped)
    if not core.pedAreaCompatible(ownInterior,otherInterior)then return nil end
    local inVehicle = optionalRead('isCharInAnyCar', ped)
    if type(inVehicle) ~= 'boolean' then return nil end
    local lx, ly, lz = getCharCoordinates(PLAYER_PED)
    local x, y, z = getCharCoordinates(ped)
    local cx, cy, cz = getActiveCameraCoordinates()
    if not (core.finite(lx) and core.finite(ly) and core.finite(lz) and core.finite(x) and
        core.finite(y) and core.finite(z) and core.finite(cx) and core.finite(cy) and core.finite(cz)) then return nil end
    local dx, dy, dz = lx - x, ly - y, lz - z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if not core.finite(distance) or distance > maxDistance then return nil end
    local visibleOffsets = {}
    local offsets = inVehicle and {.8, .55, .3, .05} or {.8, .2, -.25}
    for _, offset in ipairs(offsets) do
        if bodyPointVisible(cx, cy, cz, x, y, z + offset, inVehicle, ped) then
            visibleOffsets[#visibleOffsets + 1] = offset
        end
    end
    if #visibleOffsets == 0 then return nil end
    return {x = x, y = y, z = z, distance = distance, cx = cx, cy = cy, cz = cz,
        inVehicle = inVehicle, visibleOffsets = visibleOffsets}
end

local function inspectPed(ped, expected, maxDistance, observed)
    -- Identity is read after visibility/range/obstacle checks, never for a hidden/far ped.
    local visual = observed or visiblePed(ped, maxDistance)
    if not visual then return nil end
    local mapped, id = sampGetPlayerIdByCharHandle(ped)
    if mapped ~= true or not core.validId(id) or sampIsPlayerConnected(id) ~= true then return nil end
    if expected and (expected.ped ~= ped or expected.id ~= id) then return nil end
    local streamed, mappedPed = sampGetCharHandleBySampPlayerId(id)
    if streamed ~= true or mappedPed ~= ped then return nil end
    if type(_G.sampIsPlayerNpc) == 'function' and optionalRead('sampIsPlayerNpc', id) ~= false then return nil end
    local nickname = sampGetPlayerNickname(id)
    if type(nickname) ~= 'string' or nickname == '' or #nickname > 24 then return nil end
    if expected and expected.name ~= nickname then return nil end
    return {ped = ped, id = id, name = nickname}
end

local function acquireTarget(maxDistance)
    if not connectionKey() or not localAlive() or type(PLAYER_HANDLE) ~= 'number' then return nil end
    local aimed, ped = optionalRead('getCharPlayerIsTargeting', PLAYER_HANDLE)
    if aimed==true then
        local native=inspectPed(ped,nil,maxDistance)
        if native then return native end
        -- A native lock can be stale or point at a non-player. Continue the visible
        -- camera selection, including friendly officers, with the same checks.
    end
    local width, height = optionalRead('getScreenResolution')
    if not core.finite(width) or not core.finite(height) or width < 300 or height < 300 then
        return nil, 'Размер игрового экрана недоступен.'
    end
    for _, name in ipairs({'getAllChars', 'convert3DCoordsToScreenEx'}) do
        if type(_G[name]) ~= 'function' then return nil, 'Для выбора взглядом недоступна функция: ' .. name end
    end
    local peds = optionalRead('getAllChars')
    if type(peds) ~= 'table' then return nil, 'Список загруженных персонажей недоступен.' end
    local anchorX,anchorY=width*.5,height*.5
    local sample=sceneServices.aimSample;local age=sample and core.elapsed(studioClock,sample.at)
    if sample and age and age<=1500 and sample.session==connectionKey()and sample.ped==PLAYER_PED and
        (sample.mode==53 or sample.mode==55)and optionalRead('isCharInAnyCar',PLAYER_PED)==false and optionalRead('isButtonPressed',0,6)==true then anchorX,anchorY=width*.53,height*.40 end
    local seen, count, best, bestScore, secondScore = {}, 0
    for _, candidate in pairs(peds) do
        count = count + 1
        if count > 2048 then return nil, 'Слишком много персонажей для однозначного выбора.' end
        if core.finite(candidate) and candidate >= 0 and candidate == math.floor(candidate) and not seen[candidate] then
            seen[candidate] = true
            local visual = visiblePed(candidate, maxDistance)
            if visual then
                local score
                -- Accept looking at the torso as well as the upper body.
                for _, offset in ipairs(visual.visibleOffsets) do
                    local projected, wx, wy = optionalRead('convert3DCoordsToScreenEx', visual.x, visual.y, visual.z + offset, true, true)
                    if projected == true and core.finite(wx) and core.finite(wy) then
                        local candidateScore = core.cameraScore(wx, wy, width, height,anchorX,anchorY)
                        if candidateScore ~= nil and (score == nil or candidateScore < score) then score = candidateScore end
                    end
                end
                if score ~= nil then
                    local target = inspectPed(candidate, nil, maxDistance, visual)
                    if target then
                        if bestScore == nil or score < bestScore then
                            secondScore, bestScore, best = bestScore, score, target
                        elseif secondScore == nil or score < secondScore then secondScore = score end
                    end
                end
            end
        end
    end
    if best and secondScore and secondScore - bestScore <= .12 then
        return nil, 'В центре несколько игроков. Наведите камеру точнее и повторите X.'
    end
    return best
end

local function inspectSelected(target, settings)
    -- Only the already selected ID is queried. Unstreaming is not a disconnect.
    local out={connected=optionalRead('sampIsPlayerConnected',target.id)}
    if out.connected~=true then return out end
    out.name=optionalRead('sampGetPlayerNickname',target.id)
    if out.name~=target.name then return out end
    local streamed,ped=optionalRead('sampGetCharHandleBySampPlayerId',target.id)
    if streamed~=true or not core.finite(ped) or ped~=math.floor(ped) or ped<0 or ped>2147483647 or
        ped==PLAYER_PED or optionalRead('doesCharExist',ped)~=true or not localPedAvailable() then return out end
    local localInterior=optionalRead('getCharActiveInterior',PLAYER_PED)
    local remoteInterior=optionalRead('getCharActiveInterior',ped)
    if not core.pedAreaCompatible(localInterior,remoteInterior)then return out end
    local x,y,z=optionalRead('getCharCoordinates',ped)
    local lx,ly,lz=optionalRead('getCharCoordinates',PLAYER_PED)
    if core.finite(x) and core.finite(y) and core.finite(z) and core.finite(lx) and core.finite(ly) and core.finite(lz) then
        out.distance=math.sqrt((x-lx)^2+(y-ly)^2+(z-lz)^2)
    end
    if settings.pursuit and optionalRead('isCharDead',ped)==false then out.tracked={id=target.id,ped=ped,name=target.name}end
    local visual=visiblePed(ped,math.min(200,settings.retain_distance))
    out.visible=visual~=nil
    if visual and visual.distance<=settings.action_distance then
        out.validated=inspectPed(ped,{id=target.id,ped=ped,name=target.name},settings.action_distance,visual)
    end
    return out
end

local function targetEvent(kind,target,reason)
    if studio then studio:forgetKnowledgeIdentity()end
    if knowledgeUi then knowledgeUi:forgetIdentity()end
    if kind=='suspended' then runtime:cancel('Интерьер изменился. Запустите действие заново после перехода.');return end
    if kind=='rebound' then runtime:cancel('Персонаж загружен заново. Выберите действие повторно.'); return end
    runtime:cancel('Выбранный человек изменился.')
    if kind=='changed' and type(reason)=='string' then
        local previousName,previousId=reason:match('^(.*) %[(%d+)%]$')
        if previousId and (not workspace or workspace.library.settings.interaction_notices) then hud:targetNotice('cleared',{name=previousName,id=tonumber(previousId)},'changed',nil,workspace and workspace.library.assist.interaction)end
    end
    if not workspace or workspace.library.settings.interaction_notices then hud:targetNotice(kind,target,reason,nil,workspace and workspace.library.assist.interaction)end
    local label=target.name
    if not core.validUtf8(label) then local ok,value=pcall(codec.decode,label); label=ok and value or 'Игрок' end
    label=label:gsub('{%x%x%x%x%x%x}',''):gsub('%c',' ')..' ['..target.id..']'
    local message
    if kind=='selected' then message='Вы начали взаимодействие с '..label..'.'
    elseif kind=='changed' then message='Выбран другой человек: '..label..'.'
    elseif reason=='disconnected' then message=label..' отключился от сервера. Взаимодействие завершено.'
    else
        local reasons={manual='выбор снят',identity='ID или личность изменились',session='подключение изменилось',
            distance='человек слишком далеко',interior='интерьер изменился',local_unavailable='ваш персонаж недоступен',timer='таймер изменился'}
        message='Взаимодействие с '..label..' завершено: '..(reasons[reason] or 'выбор снят')..'.'
    end
    pushLog(message)
end

local env = {
    now = function() return getGameTimer() end,
    context = context,
    codec = codec,
    rpSettings=function()return workspace and workspace.library.rp_text,hud.data.nickname end,
    rpValid=function(signature)return signature==sceneServices.rp.signature(workspace and workspace.library.rp_text,hud.data.nickname)end,
    log = pushLog,
    feedback=function(message)if sceneServices.userWarning then sceneServices.userWarning(message)end end,
    acquire = acquireTarget,
    validate = function(target, maxDistance)
        if type(target) ~= 'table' then return nil end
        return inspectPed(target.ped, target, maxDistance)
    end,
    send = function(wire)
        -- Last guard immediately before handing one prevalidated line to the client.
        local ctx = context()
        if runtime.demo or not ctx.session or ctx.focused ~= true or ctx.paused ~= false or
            ctx.blocked ~= false or (ctx.window ~= false and ctx.ownWindow~=true) or ctx.alive ~= true or hud.editing or hud.drag then return false end
        -- Library speech already contains the frozen preview accent. Do not apply the live profile twice.
        ownedChatSendDepth=ownedChatSendDepth+1
        ownedSendCancelled=false
        if workspace then workspace.operationLineOverride=nil end
        local sent=pcall(sampSendChat,wire)
        ownedChatSendDepth=ownedChatSendDepth-1
        if not sent or ownedSendCancelled then return false end
        metrics.sent = metrics.sent + 1
        if workspace and workspace.operations and not workspace.executor.queue then
            local ok,text=pcall(codec.decode,wire)
            local target=runtime.queue and runtime.queue.target
            if workspace.operationLineOverride~=nil then
                if text~=workspace.operationLineOverride then target=nil end
                text=workspace.operationLineOverride;ok=type(text)=='string'
            end
            if ok then workspace.operations:observe(text,'legacy',target,'client','Быстрое действие')end
        end
        return true -- no claim of server acceptance; failures are never retried
    end,
}
runtime = runtimeModule.new(env, cfg)
for _, warning in ipairs(configWarnings) do pushLog(warning) end

local defaultWeapons=preferences.weaponDefaults()
local function pedValues(ped)
    local out={}; local weapon=optionalRead('getCurrentCharWeapon',ped)
    if core.finite(weapon) and weapon>=0 and weapon<=46 and weapon==math.floor(weapon) then
        out.weapon=preferences.weaponName(workspace and workspace.library.weapons or defaultWeapons,weapon)
        if ped==PLAYER_PED and taser and taser:activeFor({weapon=weapon})then out.weapon=workspace.library.taser.name end
    end
    local inCar=optionalRead('isCharInAnyCar',ped)
    if inCar==false then out.vehicle='Пешком'
    elseif inCar==true then
        local car=optionalRead('storeCarCharIsInNoSave',ped)
        if core.finite(car) and optionalRead('doesVehicleExist',car)==true then
            local model=optionalRead('getCarModel',car)
            if core.finite(model) then out.vehicle='GTA model '..tostring(model) end
        end
    end
    -- Keep the opcode's units explicit until Exsellent's speed calibration is checked.
    local speed=optionalRead('getCharSpeed',ped)
    if core.finite(speed) and speed>=0 and speed<=1000 then out.speed=string.format('%.1f',speed) end
    return out
end
local function nearbyVisible(distance)
    local peds=optionalRead('getAllChars'); if type(peds)~='table' then return {} end
    local seen,result,count={},{},0
    for _,ped in pairs(peds) do
        count=count+1; if count>2048 then return {} end
        if core.finite(ped) and not seen[ped] then seen[ped]=true
            local visual=visiblePed(ped,distance)
            if visual then local t=inspectPed(ped,nil,distance,visual); if t then t.distance=visual.distance; result[#result+1]=t end end
        end
    end
    return result
end
local function openWorkspace(page,force)
    if studio and ownUi()and not force and(not showWindow[0]or menu.section~=(page or'binds'))and studio:unsavedChanges()then
        return studio:requestNavigation(function()openWorkspace(page,true)end,'открыть другой раздел PA')
    end
    sceneServices.showAssist[0]=false;sceneServices.showWanted[0]=false;sceneServices.hideProcedureWindows()
    showQuick[0],showTips[0]=false,false; showWindow[0]=true; menu.section=page or 'binds'
    uiInputReset=true; uiTyping=false; imgui.DisableInput=false; autoOpenForSession=nil
end
local function hideWorkspaceUi()
    sceneServices.showAssist[0]=false;sceneServices.showWanted[0]=false;sceneServices.hideProcedureWindows()
    if studio then cancelUiModal() end
    showWindow[0],showQuick[0],showTips[0]=false,false,false; uiTyping=false; uiInputReset=true
    imgui.DisableInput=true; autoOpenForSession=nil; hud:stopInteraction(); runtime:cancel('Запуск бинда.')
end
workspace = workspaceModule.new({
    encodeJson=function(v) if type(encodeJson)~='function' then error('MoonLoader encodeJson unavailable') end; return encodeJson(v) end,
    decodeJson=function(v) if type(decodeJson)~='function' then error('MoonLoader decodeJson unavailable') end; return decodeJson(v) end,
    context=context,now=env.now,codec=codec,log=pushLog,demo=function() return runtime.demo end,
    acquire=acquireTarget,validate=env.validate,nearby=nearbyVisible,readPed=pedValues,
    inspectSelected=inspectSelected,targetEvent=targetEvent,
    readLocal=function()
        local values={my_id=hud.data.id and tostring(hud.data.id),my_nick=hud.data.nickname,area=hud.data.district}
        if localPedAvailable() then for key,value in pairs(pedValues(PLAYER_PED)) do values['my_'..key]=value end end
        local mapState,mapValues=sceneServices.mapSample();values.map_square=mapValues.map_square;values.area=mapState.area
        values.city=mapValues.city
        values.location=sceneServices.mapGrid.location({area=values.area,map_square=values.map_square,map_grid=workspace.library.map_grid})
        if workspace.library.map_grid.auto_square then values.square=mapValues.square end
        return values
    end,
    send=env.send,lastSent=function() return runtime.lastSentAt end,markSent=function(now) runtime.lastSentAt=now end,
    planValid=function(plan)
        if plan.manualCommand then return sceneServices.manualActions and sceneServices.manualActions:validPlan(plan)or false end
        if plan.rpSignature and plan.rpSignature~=sceneServices.rp.signature(workspace.library.rp_text,hud.data.nickname)then return false end
        if plan.textSignature and plan.textSignature~=sceneServices.rp.signature(workspace.library.rp_text)then return false end
        if plan.evidenceAction then return sceneServices.evidence and sceneServices.evidence:validPlan(plan)or false end
        if plan.copilotAction then return sceneServices.copilot and sceneServices.copilot:validPlan(plan)or false end
        if plan.vehicleAction then return sceneServices.vehicle and sceneServices.vehicle:validPlan(plan)or false end
        if plan.caseProcedure then return caseForms and caseForms:validPlan(plan)or false end
        if plan.patrolEvent then return patrolEvents and patrolEvents:validPlan(plan)or false end
        if plan.patrolSession then return patrolSession and patrolSession:validPlan(plan)or false end
        if plan.radioGuard and (not radioGuard or not radioGuard:validPlan(plan))then return false end
        if plan.alert then return alerts and alerts:validPlan(plan) or false end
        if plan.automatic then
            if plan.automatic.kind=='weapon_draw'or plan.automatic.kind=='weapon_holster' then return weapons and weapons:validPlan(plan) or false end
            if plan.automatic.kind=='taser_reload' then return taser and taser:validPlan(plan) or false end
            if plan.automatic.kind=='auto_report' then return radioGuard and radioGuard:validPlan(plan) or false end
            if plan.automatic.kind=='weapon_warning' then return weaponWarning and weaponWarning:validPlan(plan) or false end
            return false
        end
        return true
    end,
    executionEvent=function(kind,q,line)
        if kind=='sent_line'and sceneServices.colleagues then sceneServices.colleagues:command(line,studioClock)end
        if sceneServices.evidence then sceneServices.evidence:onExecution(kind,q)end
        if sceneServices.copilot then sceneServices.copilot:onExecution(kind,q,line)end
        if sceneServices.vehicle then sceneServices.vehicle:onExecution(kind,q)end
        if caseForms then caseForms:onExecution(kind,q,line)end
        if patrolEvents then patrolEvents:onExecution(kind,q)end
        if patrolSession then patrolSession:onExecution(kind,q)end
        if alerts then alerts:onExecution(kind,q) end
        if taser then taser:onExecution(kind,q) end
        if weapons then weapons:onExecution(kind,q)end
        if radioGuard then radioGuard:onExecution(kind,q)end
        if weaponWarning then weaponWarning:onExecution(kind,q)end
    end,
    pressed=function(key) return wasKeyPressed(key) end,down=function(key) return isKeyDown(key) end,
    soundAvailable=function() return type(addOneOffSound)=='function' end,
    sound=function(index)
        if not localAlive() or type(addOneOffSound)~='function' then return false end
        local x,y,z=getCharCoordinates(PLAYER_PED); addOneOffSound(x,y,z,({1056,1057,1058})[index]); return true
    end,
    preview=function() metrics.previews=metrics.previews+1 end,hideUi=hideWorkspaceUi,
    openConfirm=function() uiInputReset=true; imgui.DisableInput=false end,
    openReturn=function(page) if page=='quick' then showQuick[0]=true; uiInputReset=true; imgui.DisableInput=false else openWorkspace(page or 'binds') end end,
},cfg,getWorkingDirectory()..'\\config\\police_assistant_2026')
sceneServices.nearby=require('pa26_nearby').new({settings=function()return workspace.library.nearby end,scan=nearbyVisible,
    resolve=function(t,distance)
        local visual=visiblePed(t.ped,distance);if not visual then return nil end
        return inspectPed(t.ped,t,distance,visual)
    end,resolveId=function(id,distance)
        local streamed,ped=optionalRead('sampGetCharHandleBySampPlayerId',id)
        local t=streamed==true and inspectPed(ped,nil,distance)or nil
        return t and t.id==id and t or nil
    end,select=function(t)return workspace:selectTarget(t)end})
-- UI callbacks share the forward-declared game-loop clock.
alerts=alertModule.new({settings=function() return workspace.library.alerts end,codec=codec,log=pushLog,
    shortcuts=function()return workspace.library.alert_shortcuts end,
    offered=function(kind)
        runtime:cancel('Открыто подтверждение доклада.');pendingWheelClick=nil
        local q=workspace.executor.queue
        if kind~='police' and kind~='prison' and q and (q.plan.radioGuard or(q.plan.alert and
            (q.plan.alert.kind=='police' or q.plan.alert.kind=='prison'))) then
            workspace:cancel('Периодический доклад отменён: открыто экстренное подтверждение.')
        end
    end,
    confirm=function(plan,interrupt)
        if interrupt then workspace:cancel('Текущий сценарий остановлен для подтверждённого доклада.') end
        runtime:cancel('Подтверждён доклад в рацию.');hideWorkspaceUi()
        local ok=workspace:request({kind='startPlan',plan=plan,returnTo='quick'})
        return ok,not ok and workspace.status or nil
    end})
local confirmationInput=inputModule.new()
sceneServices.assistInput=inputModule.new()
local function startAutomatic(plan)
    if workspace.pending or runtime.queue or runtime.wheel or alerts.pending or keyRecorder or studio and hasUiModal() then return nil,'Очередь занята.' end
    return workspace.executor:start(plan,runtime.demo,cfg.main.interval_ms)
end
weapons=weaponModule.new({settings=function()return workspace.library.weapons end,codec=codec,log=pushLog,start=startAutomatic})
taser=taserModule.new({settings=function()return workspace.library.taser end,codec=codec,log=pushLog,start=startAutomatic,
    observed=function()return workspace.chatFiltersAvailable or(sceneServices.chatBridge and workspace.library.settings.cef_chat_support and sceneServices.chatBridge.status=='connected')end})
local function notificationUiAvailable()return notifications and not notifications.failed and not hud.failed and not shutdown end
local function cancelNoticePlan(token)
    local q=workspace.executor.queue
    if q and((q.plan.radioGuard and q.plan.radioGuard.token==token)or(q.plan.automatic and q.plan.automatic.token==token))then
        workspace.executor:cancel('Отменено уведомлением. Автоматического повтора нет.')
    end
end
sceneServices.localLife=require('pa26_local_life').new({settings=function()return workspace.library.patrol_session end})
patrolSession=patrolSessionModule.new({clientInstance=patrolSessionModule.clientInstance(ffi),settings=function()return workspace.library.patrol_session end,
    profile=function()return workspace.library.profile end,contacts=function()return workspace.library.partners end,
    codec=codec,log=pushLog,json=workspace.json,path=workspace.base..'_patrol.json',date=function()return os.date('%d.%m.%Y %H:%M:%S')end,
    equal=function(a,b)
        local function same(x,y)
            if type(x)~='table'or type(y)~='table'then return x==y end
            for k,v in pairs(x)do if not same(v,y[k])then return false end end
            for k in pairs(y)do if x[k]==nil then return false end end;return true
        end
        return same(a,b)
    end,
    resolve=function(name,distance)
        for _,r in ipairs(patrolSession.scene and patrolSession.scene.nearby or {})do
            if r.distance<=distance and r.name:lower()==name:lower()then return r end
        end
    end,
    observe=function(id)
        return patrolSession.scene and patrolSession.scene.players[id]
    end,
    start=startAutomatic,cancel=function(token,reason)
        local q=workspace.executor.queue
        if q and q.plan.patrolSession and q.plan.patrolSession.token==token then workspace.executor:cancel(reason or 'Доклад патруля отменён.')end
    end})
-- Native observations are refreshed by main(), never by GUI preparation/clicks.
patrolSession.readScene=function(state,now)
    local settings=workspace.library.patrol_session
    if not state.session or not state.alive then patrolSession.scene={nearby={},players={}};return end
    local scene=patrolSession.scene or {nearby={},players={}}
    local ids,names,nameList={},{},{}
    local wanted=bindingModel.copy(settings.crew)
    for _,row in ipairs(studio.patrolSessionDraft and studio.patrolSessionDraft.crew or{})do wanted[#wanted+1]=row end
    for _,row in ipairs(wanted)do for _,contact in ipairs(workspace.library.partners)do
        if contact.id==row.contact_id then names[contact.nickname:lower()]=true;nameList[#nameList+1]=contact.nickname:lower()end
    end end
    table.sort(nameList);local roster=table.concat(nameList,'\0')
    local age=scene.at and core.elapsed(now,scene.at)
    if scene.session~=state.session or not age or age>=500 or scene.distance~=settings.bind_distance or scene.roster~=roster or scene.enabled~=settings.enabled then
        scene.nearby=#wanted>0 and state.alive and nearbyVisible(settings.bind_distance)or {}
        scene.at=now;scene.session=state.session;scene.distance=settings.bind_distance;scene.roster=roster;scene.enabled=settings.enabled
    end
    -- A verified teammate in this cruiser does not need a camera ray through its roof.
    local known={};for _,row in ipairs(scene.nearby)do known[row.id]=true end
    for _,row in ipairs(state.colleagues and state.colleagues.patrolCrew or{})do
        if names[row.name:lower()]and not known[row.id]and sceneServices.readDriver then
            local live=sceneServices.readDriver(row.id)
            if live and live.name==row.name and core.finite(live.distance)and live.distance<=settings.bind_distance then
                scene.nearby[#scene.nearby+1]=live;known[live.id]=true
            end
        end
    end
    for _,row in ipairs(scene.nearby)do if names[row.name:lower()]then ids[row.id]=true end end
    for _,a in ipairs({patrolSession.data.active or false,patrolSession.intent and patrolSession.intent.record or false,
        patrolSession.queued and patrolSession.queued.record or false})do if a then
        for _,row in ipairs(a.crew)do if core.validId(row.player_id)then ids[row.player_id]=true end end
    end end
    scene.players={}
    for id in pairs(ids)do
        local connected=optionalRead('sampIsPlayerConnected',id)
        local name=connected==true and optionalRead('sampGetPlayerNickname',id)or nil
        if type(name)=='string'then local ok,decoded=pcall(codec.decode,name);name=ok and decoded or nil end
        scene.players[id]={connected=connected==true,name=name}
    end
    patrolSession.scene=scene
end
patrolEvents=patrolEventsModule.new({settings=function()return workspace.library.patrol_events end,
    patrol=function()return patrolSession.data.active end,target=function()return bindingModel.copy(workspace.selectedTarget)end,
    targetStamp=function()return workspace.targets.revision end,
    equal=patrolSession.env.equal,codec=codec,json=workspace.json,path=workspace.base..'_patrol_events.json',
    date=function()return os.date('%d.%m.%Y %H:%M:%S')end,
    validTarget=function(t)
        local selected=workspace.selectedTarget
        if not t or not selected or t.id~=selected.id or t.name~=selected.name or t.ped~=selected.ped then return false end
        local found=workspace.targets:view()
        return found.state=='available'and found.id==t.id and found.name==t.name and found.ped==t.ped
    end,
    start=startAutomatic,cancel=function(token,reason)
        local q=workspace.executor.queue
        if q and q.plan.patrolEvent and q.plan.patrolEvent.token==token then workspace.executor:cancel(reason or 'Доклад события отменён.')end
    end})
sceneServices.wantedAccounts=require('pa26_wanted_accounts').new({
    observe=function(id)return {connected=optionalRead('sampIsPlayerConnected',id),name=optionalRead('sampGetPlayerNickname',id),
        npc=type(_G.sampIsPlayerNpc)=='function'and optionalRead('sampIsPlayerNpc',id)~=false}end,
    generation=function(id)return sceneServices.nearby.generations[id]or 0 end,
    near=function(t)return patrolEvents.env.validTarget(t)end,
    allowRemote=function()return workspace.library.procedures.wanted_allow_remote end})
identity=identityModule.new({settings=function()return workspace.library.identity end,
    resolvePassport=function(name,distance)
        for _,target in ipairs(nearbyVisible(distance))do if target.name==name then return target end end
    end})
caseForms=caseFormsModule.new({gender=function()return workspace.library.profile.gender end,settings=function()return workspace.library.procedures end,codec=codec,equal=patrolSession.env.equal,
    notice=function(text)if studio then studio:notify(text,'procedures',false)end end,
    reminders=function()return workspace.library.wanted_reminders end,wall=function()return os.time()end,
    saveReminders=function(rows)local copy=bindingModel.copy(workspace.library);copy.wanted_reminders=rows;return workspace:save(copy)end,
    target=function()return bindingModel.copy(workspace.selectedTarget),workspace.targets.revision end,
    rpSettings=function()return workspace.library.rp_text,hud.data.nickname end,
    identity=function()return identity:view()end,
    wantedTarget=function()return sceneServices.wantedAccounts:current(workspace.selectedTarget)end,
    wantedIdentity=function(t)return identity:wantedRecord(t)end,
    validWantedTarget=function(t)return sceneServices.wantedAccounts:valid(t)end,
    validTarget=function(t,stamp)return stamp==workspace.targets.revision and patrolEvents.env.validTarget(t)end,
    start=startAutomatic,cancel=function(token,reason)
        local q=workspace.executor.queue
        if q and q.plan.caseProcedure and q.plan.caseProcedure.token==token then workspace.executor:cancel(reason or 'Процедура отменена.')end
    end})
sceneServices.world=sceneServices.worldModule.new(optionalRead,codec,function()return PLAYER_PED end)
sceneServices.vehicle=sceneServices.model.new({settings=function()return workspace.library.vehicle end,codec=codec,scan=sceneServices.world.scan,resolve=sceneServices.world.resolve,ownCar=sceneServices.world.ownCar,selectionStatus=sceneServices.world.status,
    driver=function(id)return sceneServices.readDriver and sceneServices.readDriver(id)end,
    retention=function()local c=sceneServices.copilot;if c and c:inPursuit()then return{distance=workspace.library.vehicle.copilot.pursuit_retain_distance}end end,
    currentTarget=function()return workspace.targets.target,workspace.targets.revision end,
    selectTarget=function(target)
        local ok,err=workspace:selectTarget(target)
        if ok then workspace.selectedTarget=workspace.targets.target;hud.target=workspace.targets:view()end
        return ok,err
    end,
    profile=function()return workspace.library.profile end,reportConfig=function()return workspace.library.patrol_session end,
    service=function()return {unit=workspace.library.patrol_session.unit,station=workspace.library.patrol_session.station,crew=workspace.library.profile.name}end,
    equal=patrolSession.env.equal,patrol=function()return patrolSession.data.active end,start=startAutomatic,
    notice=function(message)studio:notify(message,'vehicle',false)end,
    cancel=function(token,reason)local q=workspace.executor.queue;if q and q.plan.vehicleAction and q.plan.vehicleAction.token==token then workspace.executor:cancel(reason)end end})
sceneServices.colleagues=require('pa26_colleagues').new({read=optionalRead,settings=function()return workspace.library.vehicle.copilot end,
    generation=function(id)return sceneServices.nearby.generations[id]or 0 end,
    partners=function()
        local contacts=bindingModel.copy(workspace.library.partners)
        local roster=studio.patrolSessionDraft and studio.patrolSessionDraft.crew or workspace.library.patrol_session.crew
        for _,p in ipairs(contacts)do for _,r in ipairs(roster or{})do if p.id==r.contact_id then p.ic_name=r.ic_name end end end
        return contacts
    end,profile=function()return workspace.library.profile end,
    crew=function()local a=patrolSession.data.active;return a and #(a.crew or{})>0 or false end})
sceneServices.readDriver=function(id)
    if not core.validId(id)or optionalRead('sampIsPlayerConnected',id)~=true or optionalRead('sampIsPlayerNpc',id)~=false then return end
    local ok,ped=optionalRead('sampGetCharHandleBySampPlayerId',id)
    if ok~=true or not core.finite(ped)or optionalRead('doesCharExist',ped)~=true or optionalRead('isCharDead',ped)~=false then return end
    local back,mapped=optionalRead('sampGetPlayerIdByCharHandle',ped);if back~=true or mapped~=id then return end
    local name=optionalRead('sampGetPlayerNickname',id);if type(name)~='string'or name==''then return end
    if not core.pedAreaCompatible(optionalRead('getCharActiveInterior',PLAYER_PED),optionalRead('getCharActiveInterior',ped))then return end
    local weapon=optionalRead('getCurrentCharWeapon',ped);local x,y,z=optionalRead('getCharCoordinates',ped);local lx,ly,lz=optionalRead('getCharCoordinates',PLAYER_PED)
    local distance=core.finite(x)and core.finite(y)and core.finite(z)and core.finite(lx)and core.finite(ly)and core.finite(lz)and math.sqrt((x-lx)^2+(y-ly)^2+(z-lz)^2)or nil
    return{id=id,ped=ped,name=name,generation=sceneServices.nearby.generations[id]or 0,distance=distance,x=x,y=y,z=z,
        armed=core.finite(weapon)and weapon>=22 and weapon<=38,weapon=weapon}
end
sceneServices.readDriverAccount=function(id)
    if not core.validId(id)or optionalRead('sampIsPlayerConnected',id)~=true or optionalRead('sampIsPlayerNpc',id)~=false then return end
    local name=optionalRead('sampGetPlayerNickname',id);if type(name)~='string'or name==''then return end
    local ok,ped=optionalRead('sampGetCharHandleBySampPlayerId',id)
    if ok==true and core.finite(ped)and optionalRead('doesCharExist',ped)==true and optionalRead('isCharDead',ped)~=false then return end
    local incompatible=ok==true and core.finite(ped)and not core.pedAreaCompatible(optionalRead('getCharActiveInterior',PLAYER_PED),optionalRead('getCharActiveInterior',ped))
    return{id=id,name=name,generation=sceneServices.nearby.generations[id]or 0,incompatible=incompatible}
end
workspace.env.targetRetention=function(target)
    local c=sceneServices.copilot
    if not target or not c or not c.driver or c.driver.id~=target.id or c.driver.name~=target.name or
        c.driver.generation~=(sceneServices.nearby.generations[target.id]or 0)then return end
    return c:retentionFor(c.driver)
end
sceneServices.bulletins=require('pa26_stolen_bulletin').new(function()return workspace.library.vehicle.copilot end)
sceneServices.copilot=require('pa26_copilot').new({vehicle=sceneServices.vehicle,settings=function()return workspace.library.vehicle.copilot end,
    bulletin=function(now)return sceneServices.bulletins:view(now,workspace.library.map_grid)end,
    profile=function()return workspace.library.profile end,codec=codec,equal=patrolSession.env.equal,driver=sceneServices.readDriver,driverAccount=sceneServices.readDriverAccount,taserActive=function(s)return taser:activeFor(s)end,start=startAutomatic,
    notice=function(message)if sceneServices.userWarning then sceneServices.userWarning(message)end end,
    cancel=function(token,reason)local q=workspace.executor.queue;if q and q.plan.copilotAction and q.plan.copilotAction.token==token then workspace.executor:cancel(reason)end end})
sceneServices.copilotUi=require 'pa26_copilot_ui'
sceneServices.refreshFastPt=function(state,now)
    local c=sceneServices.copilot;local request=sceneServices.fastPtRequest;sceneServices.fastPtRequest=nil
    if state.typing or state.paused or not state.focused or state.blocked or not state.alive or not state.session then
        c.fastPtLive=nil;c.fastPtLiveAt=nil;return
    end
    if request and state.session and state.alive and state.focused and not state.paused and not state.blocked and not state.typing then
        local rows={};local limit=workspace.library.vehicle.copilot.fast_pt_distance
        local function add(expected,source)
            local fresh=expected and sceneServices.readDriver(expected.id)
            if fresh and expected.name==fresh.name and(expected.generation==nil or expected.generation==fresh.generation)then fresh.source=source;rows[#rows+1]=fresh end
        end
        if c.phase then add(c.driver,'водитель текущей остановки / погони')end
        add(workspace.selectedTarget,'выбранный человек')
        local car=sceneServices.vehicle.selected
        if car and not car.stale and car.driver_id then
            local driver=sceneServices.readDriver(car.driver_id)
            if driver and car.driver_ped==driver.ped then driver.source='водитель выбранной машины';rows[#rows+1]=driver end
        end
        local colleagues={}
        for _,p in ipairs(workspace.library.partners or{})do colleagues[p.nickname:lower()]=true end
        for name in pairs(sceneServices.colleagues.knownColleagues or{})do colleagues[name]=true end
        for _,p in ipairs((state.colleagues or{}).nearbyOfficers or{})do colleagues[p.name:lower()]=true end
        local skins=require('pa26_copilot_settings').ids(workspace.library.vehicle.copilot.skin_ids,0,65535)or{}
        local fallback=nearbyVisible(limit);table.sort(fallback,function(a,b)return a.distance<b.distance end)
        for _,p in ipairs(fallback)do
            p.generation=sceneServices.nearby.generations[p.id]or 0;p.visible=true;p.fallback=true;p.source='ближайший видимый человек'
            p.colleague=colleagues[p.name:lower()]or skins[optionalRead('getCharModel',p.ped)]or false
            rows[#rows+1]=p
        end
        local target=require('pa26_fast_pt').resolve(rows,state,limit)
        c.fastPtLive=target;c.fastPtLiveAt=now
        local ok,why=c:requestFastPt(rows);if not ok then studio:notify(why,'vehicle',false)end
    end
    local pending=c.intent and c.intent.action=='fast_pt'or c.queued and c.queued.action=='fast_pt'
    for _,p in ipairs(c.offers)do if p.action=='fast_pt'then pending=true end end
    if c.fastPtTarget and pending then
        local fresh=sceneServices.readDriver(c.fastPtTarget.id)
        if fresh and c.fastPtTarget.fallback and not visiblePed(fresh.ped,workspace.library.vehicle.copilot.fast_pt_distance)then fresh=nil end
        c.fastPtLive=fresh;c.fastPtLiveAt=now
    elseif not request then c.fastPtTarget=nil;c.fastPtLive=nil;c.fastPtLiveAt=nil end
end
sceneServices.detentionTimers=require('pa26_detention_timers').new({
    settings=function()return workspace.library.vehicle.copilot end,
    target=function()return sceneServices.wantedAccounts:current(workspace.selectedTarget)end,
    valid=function(t)return sceneServices.wantedAccounts:valid(t)end,
    notice=function(text)studio:notify(text,'vehicle',false)end})
sceneServices.files=sceneServices.filesModule.new()
sceneServices.evidence=sceneServices.evidenceModule.new({settings=function()return workspace.library.assist.evidence end,
    feedback=function(message)if sceneServices.userWarning then sceneServices.userWarning(message)end end,
    codec=codec,equal=patrolSession.env.equal,files=sceneServices.files,date=function()return os.date('%d.%m.%Y %H:%M:%S')end,
    start=startAutomatic,hideUi=hideWorkspaceUi,cancel=function(token,reason)
        local q=workspace.executor.queue;if q and q.plan.evidenceAction and q.plan.evidenceAction.token==token then workspace.executor:cancel(reason)end end,
    record=function(row)
        local copy=bindingModel.copy(workspace.library);local history=copy.assist.history;history[#history+1]=bindingModel.copy(row)
        while #history>48 do table.remove(history,1)end
        return workspace:save(copy)
    end})
local function effectivePatrol()return sceneServices.vehicle:periodic(patrolSession:effectivePatrol(workspace.library.alerts.patrol))end
radioGuard=radioGuardModule.new({settings=function()return workspace.library.radio_guard end,
    patrol=effectivePatrol,codec=codec,log=pushLog,start=startAutomatic,
    cancel=cancelNoticePlan,uiAvailable=notificationUiAvailable})
weaponWarning=warningModule.new({settings=function()return workspace.library.weapon_warning end,
    saveSettings=function(value)
        local candidate=bindingModel.copy(workspace.library);candidate.weapon_warning=value
        local ok,err=workspace:save(candidate)
        if ok then
            if studio.warningDraft then studio.warningDraft.no_accent=value.no_accent end
            local job=studio.autosaves and studio.autosaves.weapon_warning
            if job then job.value.no_accent=value.no_accent end
        end
        return ok,err
    end,
    weaponName=function(id)return taser:activeFor({weapon=id})and workspace.library.taser.name or preferences.weaponName(workspace.library.weapons,id)end,
    taserId=function()return workspace.library.taser.activation~='command'and workspace.library.taser.weapon_id or -1 end,codec=codec,log=pushLog,start=startAutomatic,
    cancel=cancelNoticePlan,uiAvailable=notificationUiAvailable})
notifications=notificationsModule.new({skipShortcut=function()return workspace.library.radio_guard.skip_shortcut end,
    option=function(owner,token,value)
        if owner~='weapon'then return false end
        local ok,err=weaponWarning:setNoAccent(token,value)
        if not ok and err then studio:notify(err,'weapon_warning',false)end
        return ok
    end,
    warnShortcut=function()return workspace.library.weapon_warning.shortcut end,
    lead=function()return workspace.library.radio_guard.lead_ms end,weaponDuration=function()return workspace.library.weapon_warning.toast_ms end,
    skip=function(token)return radioGuard:cancel(token)end,
    action=function(owner,token,yes)if owner=='radio'then
        if yes then return radioGuard:decide(token,true)end;return radioGuard:cancel(token)
    elseif owner=='vehicle'then return sceneServices.copilot:decide(token,yes)
    elseif owner=='weapon'then return weaponWarning:decide(token,yes)
    elseif owner=='patrol'then return patrolEvents:decideNotice(token,yes)
    elseif owner=='wanted'then return caseForms:decideReminder(token,yes)end end,
    shown=function(owner,token)if owner=='radio'then radioGuard:shown(token)
        elseif owner=='weapon'then weaponWarning:shown(token)elseif owner=='patrol'then patrolEvents:shown(token)
        elseif owner=='vehicle'then sceneServices.copilot:shown(token)
        elseif owner=='wanted'then caseForms:shownReminder(token)end end})
patrol=patrolModule.new({settings=effectivePatrol,clockPolicy=function()return workspace.library.radio_guard.count_during_input end,log=pushLog,
    lead=function()return workspace.library.radio_guard.lead_ms end,
    preview=function(key,cfg,remaining)return radioGuard:track(key,radioGuardModule.patrolSpec(cfg),remaining)end,
    ready=function(key)return radioGuard:ready(key)end,
    retire=function(key)radioGuard:retire(key)end,
    drop=function(key)local t=radioGuard.tickets[key];if t then radioGuard:cancel(t.token);radioGuard:retire(key)end end,
    view=function(key)return radioGuard.tickets[key]end,
    pending=function()return alerts.pending end,dispatch=function(kind,confirmation,key)return radioGuard:dispatch(key)end})
studio=studioModule.new(imgui,ffi,workspace.library,function() return studioClock end); workspace.studio=studio
knowledge=knowledgeModule.new({json=workspace.json,now=function()return studioClock end,
    path=getWorkingDirectory()..'\\config\\police_assistant_2026_knowledge.json',
    bundle=getWorkingDirectory()..'\\resource\\pa26\\knowledge-base.json',
    policyPath=getWorkingDirectory()..'\\resource\\pa26\\knowledge-policy.json',
    personalPath=getWorkingDirectory()..'\\config\\police_assistant_2026_knowledge_personal.json'})
knowledgeUi=knowledgeUiModule.new(imgui,ffi,knowledge)
sceneServices.getSanctions=function()
 if not sceneServices.sanctionCatalog or sceneServices.sanctionData~=knowledge.data then
  sceneServices.sanctionData=knowledge.data;sceneServices.sanctionCatalog=require('pa26_sanctions').new(knowledge.data)
 end
 return sceneServices.sanctionCatalog
end
caseForms.env.validSanction=function(f)return sceneServices.getSanctions():valid(f)end
sceneServices.copilot.env.validGroundSource=caseForms.env.validSanction
caseForms.env.validGround=function(p)return sceneServices.copilot:groundContextValid(p,true)end
sceneServices.copilot.env.target=function()return bindingModel.copy(workspace.selectedTarget),workspace.targets.revision end
sceneServices.copilot.env.validTarget=caseForms.env.validTarget
do
    local ok,p=pcall(require('pa26_update_platform').new,getWorkingDirectory())
    sceneServices.updater=require('pa26_updater').new({platform=ok and p or nil,
        settings=function()return workspace.library.settings.updates end,now=function()return studioClock end,
        encode=workspace.json.encode,decode=workspace.json.decode,
        notify=function(message,kind)studio:notify(message,'updates',false,kind)end})
end
do
    local io=sceneServices.authorIO
    sceneServices.authorPresets=require('pa26_author_controller').new({studio=studio,workspace=workspace,json=workspace.json,
        fs=io and io.fs or require('pa26_library').fs,hash=require('pa26_author_io').hash,lock=require('pa26_author_io').lock,io=io,
        now=function()return studioClock end,config=function()local copy=bindingModel.copy(cfg);copy.main.demo_mode=runtime.demo;return copy end,
        busy=function()return workspace.pending~=nil or workspace.executor.queue~=nil or runtime.queue~=nil or (sceneServices.updater.job and sceneServices.updater.job.mode~='Status')end,
        install=function(p)return sceneServices.installAuthorPreset(p)end,reload=function()thisScript():reload()end})
end
studio.warningLog=pushLog
sceneServices.userWarning=function(message)
    if not uiFailed and focused and not context().blocked then studio:notify(message,'system',false)end
end
knowledgeUi.warningSink=function(message,key,manual)
    if manual then studio:notify(message,'knowledge',false)else studio:passiveWarning('knowledge:'..key,message,'knowledge')end
end
knowledgeUi.warningBlocking=function()return studio:hasWarning()end
knowledge.action='load'
local function noticeAvoid()
    local out={}
    for _,r in pairs({hud=not alerts.suppressHud and hud.bounds or nil,alert=alerts.bounds,taser=taser.bounds,copilot=sceneServices.copilot.bounds})do if r then out[#out+1]=r end end
    if not alerts.suppressHud then for _,r in ipairs(hud.noticeBounds or {})do out[#out+1]=r end end
    return out
end
for _,source in ipairs({patrolSession,patrolEvents})do for _,note in ipairs(source.warnings)do pushLog(note)end end
for _,note in ipairs(workspace.warnings)do pushLog(note)end
if workspace.userFiles and workspace.userFiles.blocked~=nil then runtime:setDemo(true)end
env.startBinding=function(index,target)
    local scope=require('pa26_wheel_scope').active(workspace.library,alerts.state);local id=require('pa26_wheel_scope').slots(workspace.library,scope)[index]; local binding=bindingModel.find(workspace.library,id)
    if not binding then report('В этом месте колеса нет сценария.'); return false end
    if target then workspace:selectTarget(target) end
    return workspace:request({kind='prepare',id=id,target=target,start=true,returnTo='quick'})
end
env.wheelScope=function()return require('pa26_wheel_scope').active(workspace.library,alerts.state)end
env.wheelCatalog=function() local state=bindingModel.copy(alerts.state or {});state.patrolSession=patrolSession:view();state.copilot=sceneServices.copilot:view();return wheelModel.build(workspace.library,env.wheelRevision(),true,state) end
env.wheelRevision=function() local state=bindingModel.copy(alerts.state or{});state.copilot=sceneServices.copilot:view();return workspace.libraryRevision*100000000+patrolSession.revision*100+wheelModel.contextRevision(state) end
env.acquire=function(distance)
    local aimed=optionalRead('getCharPlayerIsTargeting',PLAYER_HANDLE)
    local target,reason
    if workspace.selectedTarget and aimed~=true then
        target=env.validate(workspace.selectedTarget,distance)
        reason='Закреплённый человек недоступен. Посмотрите на него или выберите другого.'
    else target,reason=acquireTarget(distance) end
    if target then workspace:selectTarget(target) end
    return target,reason
end
local function studioData()
    studio.buttonFont=menuButtonFont
    studio.headingFont=menuHeadingFont
    return {demo=runtime.demo,journal=workspace.journal,chatFiltersAvailable=workspace.chatFiltersAvailable,
        accentInputAvailable=type(sampGetChatInputText)=='function'and type(sampSetChatInputText)=='function',
        manualChatDraft=sceneServices.manual and sceneServices.manual.draft,
        cefChatStatus=sceneServices.chatBridge and sceneServices.chatBridge.status or 'not_installed',
        cefChatReason=sceneServices.chatBridge and sceneServices.chatBridge.reason,
        nearby=sceneServices.nearby:view(),mapState=sceneServices.mapState,mapAdapterStatus=sceneServices.mapAdapter:message(),
        textFiltersAvailable=workspace.chatFiltersAvailable or(sceneServices.chatBridge and workspace.library.settings.cef_chat_support and sceneServices.chatBridge.status=='connected'),
        target=workspace.selectedTarget,targetState=workspace.targets:view(),queued=workspace.executor.queue,
        localNickname=hud.data.nickname,rpSettings=workspace.library.rp_text,evidence=sceneServices.evidence:view(),vehicle=sceneServices.vehicle:view(),copilot=sceneServices.copilot:view(),detentionTimers=sceneServices.detentionTimers:view(),operations=workspace.operations:view(),radioState=alerts.state,patrol=patrol:view(),patrolSession=patrolSession:view(patrol:view()),patrolEvents=patrolEvents:view(),identity=identity:view(),caseForms=caseForms:view(),taser=taser:view(),codec=codec,autoReport=radioGuard:view()}
end
local function cancelManualActions(reason)
    if sceneServices.manualActions then sceneServices.manualActions:cancel()end
    sceneServices.evidence:cancel(reason)
    sceneServices.vehicle:cancel(reason)
    sceneServices.copilot:cancel(reason)
    workspace.operations:cancelReview()
    if caseForms.intent or caseForms.queued or caseForms.awaitingCommand then caseForms:reset(reason)end
    if patrolSession.intent or patrolSession.queued then patrolSession:cancelQueued(reason)end
    if patrolEvents.intent or patrolEvents.queued then patrolEvents:cancelReport(reason)end
end
local studioCallbacks
studioCallbacks={
    requestShutdown=function()sceneServices.shutdownRequested=true;return true end,
    manualFriskMode=function(token,mode)return sceneServices.manualActions:friskMode(token,mode)end,
    setDemoMode=function(value)if type(value)=='boolean'then sceneServices.requestDemoMode=value end end,
    authorPresetAccept=function()return sceneServices.authorPresets:accept()end,
    selectNearby=function(t,revision)return sceneServices.nearby:request(t,revision)end,
    selectNearbyId=function(id)return sceneServices.nearby:requestId(id)end,
    recheckMap=function()sceneServices.mapAdapter:reset()end,
    setBindingConfirmation=function(id,value)return workspace:setBindingConfirmation(id,value)end,
    openAssist=function(page)
        showWindow[0],showQuick[0],showTips[0]=false,false,false;sceneServices.showAssist[0]=true
        studio.assistPage=page or studio.assistPage or'traffic';uiTyping=false;uiInputReset=true;imgui.DisableInput=false
    end,
    assistEqual=patrolSession.env.equal,
    openNoticeSettings=function()openWorkspace('settings');settingsTab='options'end,
    evidenceOffer=function(label)return sceneServices.evidence:propose(label)end,
    evidenceAccept=function(p)return sceneServices.evidence:accept(p)end,
    evidenceCheck=function(path)return sceneServices.evidence:check(path)end,
    evidenceCancel=function()sceneServices.evidence:cancel('Фиксация отменена пользователем.')end,
    evidenceRetry=function()sceneServices.evidence:retrySave()end,
    evidenceArchiveOffer=function()return sceneServices.evidence:proposeArchive()end,
    evidenceArchiveAccept=function(p)return sceneServices.evidence:archive(p)end,
    evidenceRefresh=function()sceneServices.evidence.scanAt=nil end,
    copilotOffer=function(action)return sceneServices.copilot:propose(action)end,
    fastPt=function()
        sceneServices.fastPtRequest=true;sceneServices.showAssist[0]=false;showQuick[0]=false;showWindow[0]=false;return true
    end,
    copilotEditReport=function(p,values)return sceneServices.copilot:editReport(p,values)end,
    stolenClear=function()sceneServices.bulletins:clear();return true end,
    stolenCorrect=function(fields,revision)return sceneServices.bulletins:correct(fields,studioClock,revision)end,
    copilotWindow=function(answer)
        if answer=='repeat'then return sceneServices.copilot:repeatWindowQuestion()end
        return sceneServices.copilot:windowAnswer(answer,true)
    end,
    openGround=function(p)sceneServices.groundInput=bindingModel.copy(p);return true end,
    groundValid=function(p)return sceneServices.copilot:groundContextValid(p,true)end,
    groundSpeech=function(f)
        local values,why=sceneServices.copilot:values(f.cfg);if not values then return nil,why end
        return require('pa26_copilot').expand(f.cfg.templates.explain_stop,values)
    end,
    groundPreview=function(f)
        if not sceneServices.copilot:groundContextValid(f.request,true)then return nil,'Выбор человека устарел.'end
        f.cfg._ground_target=f.request.groundTarget
        return sceneServices.copilot:prepare(f.request.action,f.cfg)
    end,
    groundOffer=function(f,ground,handoff)
        if ground.sanction_id and not sceneServices.getSanctions():valid(ground)then return nil,'Источник статьи изменился.'end
        f.cfg._ground_target=f.request.groundTarget
        return sceneServices.copilot:proposeGround(f.request,f.cfg,ground,handoff)
    end,
    sanctions=function()return sceneServices.getSanctions()end,
    procedureInput=function(head,args)sceneServices.queueProcedureInput(head,args);return true end,
    trackingRules=function()
        return require('pa26_procedure_input').trackingRules(knowledge.data)
    end,
    trackingOffer=function(f)
        if not caseFormsModule.enabled(workspace.library.procedures,'mark')then return nil,'Включите формы пеленгации в настройках.'end
        local technical,why=caseForms:begin('wanted',f.target);if not technical then return nil,why end
        for _,key in ipairs({'phone_known','phone_number','phone_source','phone_active','prior_ic_stars','life_ack','ooc_ack','reason_id'})do technical[key]=f[key]end
        technical.mode='ooc';technical.ooc_reason='tracking';technical.host='mark';technical.reason_group=technical.reason_id:sub(1,2)
        return caseForms:offer(technical)
    end,
    copilotSelect=function()return sceneServices.vehicle:requestSelection()end,
    copilotPreview=function(action,cfg)
        return sceneServices.copilot:previewTemplate(action,cfg)
    end,
    taserMode=function(active)return taser:confirmMode(active)end,
    vehicleOffer=function(action,nearest)return sceneServices.vehicle:propose(action,nearest)end,
    vehicleAccept=function(p)if p.copilot then return sceneServices.copilot:accept(p)end;return sceneServices.vehicle:accept(p)end,
    vehicleClear=function()sceneServices.vehicle:clearTarget('Выбор машины снят вами.');sceneServices.copilot:reset('Выбор машины снят вами.')end,
    vehicleSelect=function(id)return sceneServices.vehicle:requestSelection(id)end,
    vehiclePreview=function(action,draft)
        local targeted=sceneServices.model.needsTarget(action,draft)
        local c=targeted and(sceneServices.vehicle.selected or sceneServices.vehicle.candidates[1])or nil
        local state,err=sceneServices.vehicle:values(alerts.state or {},c);if not state then return nil,err end
        if targeted then
            if not c then return nil,'Сначала выберите видимую машину.'end
            local values;values,err=sceneServices.model.describe(c,draft);if not values then return nil,err end
            for k,v in pairs(values)do state[k]=v end
        else for key in pairs(require('pa26_vehicle_settings').vehicleFields)do state[key]=nil end end
        local prepared;prepared,err=sceneServices.model.preview(action,draft,state,codec,workspace.library.radio_guard)
        return prepared and prepared.line,err
    end,
    operationOffer=function(id,outcome,note)return workspace.operations:propose(id,outcome,note)end,
    operationAccept=function(p)return workspace.operations:accept(p)end,
    operationExport=function()return workspace.operations:requestExport()end,
    openProcedures=function(kind)
        kind=kind or 'wanted'
        local layout=workspace.library.settings.window_layout
        local separate=(kind=='wanted'or kind=='wanted_list')and layout.wanted_separate or kind=='fine'and layout.fine_separate or kind=='mark'and layout.mark_separate
        if separate then
            hideWorkspaceUi()
            if kind=='fine'then sceneServices.showFine[0]=true;studio.finePage='form'
            elseif kind=='mark'then sceneServices.showMark[0]=true;studio.markPage='form'
            else sceneServices.showWanted[0]=true end
            uiTyping=false;uiInputReset=true;imgui.DisableInput=false
        else openWorkspace('addons');menu.tool='procedures'end
        studio:selectProcedure(kind);studio.casePage='form';studio.wantedBasisDetails=nil;studio.wantedIdentityPage=nil
    end,
    detentionAction=function(action)return sceneServices.detentionTimers:request(action)end,
    caseRemoteTarget=function(id)
        if not core.validId(id)then return nil,'Введите целый ID подключённого человека.'end
        local s=alerts.state or{};sceneServices.caseTargetInput={id=id,session=s.session,at=studioClock,epoch=sceneServices.chatEpoch};return true
    end,
    groundHandoff=function(ground,kind)
        return studio:requestNavigation(function()
            local f,err=caseForms:begin(kind)
            if not f then studio:notify(err,'procedures',false);return end
            f.article=ground.article or'';f.part=ground.part or'';f.basis=ground.basis or'';f.facts=ground.basis or''
            if kind=='wanted'and ground.game then f.reason_id=ground.game;f.reason_group=ground.game:sub(1,2)end
            studioCallbacks.openProcedures(kind);studio.caseForm=f
            studio.caseStoredForms=studio.caseStoredForms or{};studio.caseStoredForms[kind]=f
        end,'открыть новую форму с выбранным основанием')
    end,
    caseBegin=function(kind)return caseForms:begin(kind)end,caseBranch=function(form)return caseForms:branch(form)end,
    caseNext=function(form)return caseForms:next(form)end,casePreview=function(form)return caseForms:preview(form)end,
    caseFillWanted=function(form)return caseForms:fillWanted(form)end,
    caseValid=function(form)return caseForms:validForm(form)end,
    caseAppearance=function(form,mode)return caseForms:chooseAppearance(form,mode)end,
    caseSuggestOoc=function(form)return caseForms:oocSuggested(form)end,caseChooseOoc=function(form)return caseForms:chooseOoc(form)end,
    caseOffer=function(form)return caseForms:offer(form)end,caseAccept=function(p)return caseForms:accept(p)end,
    caseReminder=function(token,action)return caseForms:changeReminder(token,action)end,
    caseChain=function(token,kind,ack)return caseForms:chainOffer(token,kind,ack)end,
    openWantedKnowledge=function(key)
        return studio:requestNavigation(function()openWorkspace('knowledge');knowledgeUi:select(key)end,'открыть карточку причины розыска')
    end,
    caseTemplatePreview=function(template,form)return caseForms:templatePreview(template,form)end,
    caseDraft=function(form)
        if studio.dirty then return nil,'Сначала сохраните или отмените текущий черновик бинда.'end
        if #workspace.library.bindings>=128 then return nil,'Достигнут предел 128 биндов.'end
        local binding,err=caseForms:draft(form,workspace.library.next_id);if not binding then return nil,err end
        local valid;valid,err=bindingModel.validateBinding(binding);if not valid then return nil,err end
        studio:createBinding();studio.draft=binding;studio.selected=binding.id;studio.dirty=true;studio.editorTab='text'
        menu.section='binds';studio:notify('Создан выключенный черновик. При запуске нужно будет заново выбрать человека и заполнить наказание. Перед включением проверьте команду.','binds',nil,'info')
        return true
    end,
    openIdentity=function()openWorkspace('addons');menu.tool='identity'end,
    identityUpdate=function(patch,key,nonce)return identity:update(patch,key,nonce)end,
    identityForget=function(key,nonce)return identity:forget(key,nonce)end,
    identitySubject=function(target,stamp)return identity:subject(target,stamp)end,
    navigateService=function(kind,id)return env.wheelNavigate({kind=kind,id=id,category=kind=='procedure'and 'wanted'or 'service'})end,
    openPatrolEvents=function()return studio:requestNavigation(function()openWorkspace('addons',true);menu.tool='events';studio.partnerPage='events'end,'открыть события патруля')end,
    patrolEventForm=function(kind,attempt)return patrolEvents:form(kind,attempt)end,
    patrolEventBindTarget=function(form)return patrolEvents:bindTarget(form)end,
    patrolEventPreview=function(form,settings)local line,err=patrolEvents:line(form,settings);return line and line.line,err end,
    patrolEventOffer=function(form,report)return patrolEvents:propose(form,report)end,
    patrolEventAccept=function(p)return patrolEvents:accept(p)end,
    openPatrol=function()return studio:requestNavigation(function()openWorkspace('addons',true);menu.tool='patrol';studio.partnerPage='patrol'end,'открыть патруль и экипаж')end,
    patrolTraffic=function(host)
        if host=='assist'then studio.assistPage='traffic'
        elseif host=='partners'then studio.partnerPage='vehicle'
        else menu.tool='vehicle'end
    end,
    patrolOffer=function(action)return patrolSession:propose(action)end,
    patrolAccept=function(p)return patrolSession:accept(p)end,
    patrolPause=function()return patrolSession:pause('Пауза по вашему решению.')end,
    patrolPreview=function(action,draft)
        local a,err=patrolSession:makeRecord(draft,patrolSession.state or {})
        if not a then return nil,err end
        local line;line,err=patrolSession:prepareLine(action,a,patrolSession.state or {},draft)
        return line and line.line,err
    end,
    alert=function(kind) return alerts:request(kind) end,
    skipReport=function()return radioGuard:cancel()end,
    warnWeapon=function()return weaponWarning:request()end,
    save=function(lib,options) if options and options.scope=='window_layout'then return workspace:saveLayout(lib.settings.window_layout)end;return workspace:save(lib) end,saveJournal=function() return workspace:saveJournal() end,
    request=function(request) local ok=workspace:request(request); return ok,not ok and workspace.status or nil end,
    stop=function()cancelManualActions('Остановлено пользователем.');runtime:cancel('Сценарий остановлен.');workspace:cancel('Сценарий остановлен пользователем.')end,
    clearTarget=function() workspace:clearTarget('manual') end,
    openQuick=function() sceneServices.showAssist[0]=false;sceneServices.showWanted[0]=false;sceneServices.hideProcedureWindows();studio.quickWheelCategory=nil; showWindow[0],showTips[0]=false,false; showQuick[0]=true; uiTyping=false; uiInputReset=true; imgui.DisableInput=false end,
    closeQuick=hideWorkspaceUi,
    manualActionDecide=function(token,value)return sceneServices.manualActions:decide(token,value)end,
    openTips=function() sceneServices.showAssist[0]=false;sceneServices.showWanted[0]=false;sceneServices.hideProcedureWindows();showWindow[0],showQuick[0]=false,false; showTips[0]=true; uiTyping=false; uiInputReset=true; imgui.DisableInput=false end,
    capture=function(request)
        request.noticeScope=request.kind=='feature' and request.group or request.kind=='setting' and 'options' or 'binds'
        keyRecorder=request; request.startedAt=nil
        studio:beginKeyCapture(request)
    end,
    captureProgress=function(request,proposal,finished,readerError)
        if not studio.keyCapture or studio.keyCapture.request~=request then return end
        request.startedAt=studioClock
        if not finished then studio:captureProgress(request,proposal,readerError); return end
        local shortcut,err
        if not readerError then shortcut,err=bindingModel.checkKeyAssignment(workspace.library,cfg,studio.draft,request,proposal) end
        studio:captureResult(request,shortcut or proposal,readerError or err)
        if shortcut then keyRecorder=nil end
    end,
    cancelCapture=function() keyRecorder=nil; escDismissed=true end,
    applyCapture=function(request,proposal)
        local shortcut,err=bindingModel.checkKeyAssignment(workspace.library,cfg,studio.draft,request,proposal)
        if not shortcut then return nil,err end
        if request.kind=='binding' then
            studio.draft.shortcut=shortcut; studio.dirty=true; studio.plan=nil
            studio:notify('Сочетание назначено. Сохраните сценарий.','binds',request.id,'info')
            return true
        end
        if request.kind=='feature'then
            local candidate=bindingModel.copy(workspace.library);candidate[request.group][request.field]=shortcut
            local ok,err=workspace:save(candidate)
            if ok then
                local field=({radio_guard='radioGuardDraft',weapon_warning='warningDraft',vehicle='vehicleDraft',patrol_session='patrolSessionDraft',patrol_events='patrolEventDraft',procedures='caseDraft'})[request.group]
                if field and studio[field]then studio[field][request.field]=shortcut end
                local job=studio.autosaves and studio.autosaves[request.group]
                if job then job.value[request.field]=bindingModel.copy(shortcut)end
                studio:notify('Сочетание сохранено.',request.group,false,'info')
            end
            return ok,err
        end
        local candidate=bindingModel.copy(workspace.library); candidate.settings[request.field]=shortcut.key
        local ok; ok,err=workspace:save(candidate)
        if ok then
            if studio.optionDraft then studio.optionDraft[request.field]=shortcut.key end
            local job=studio.autosaves and studio.autosaves.options;if job then job.value[request.field]=shortcut.key end
            studio:notify('Клавиша сохранена.','options',nil,'info')
        end
        return ok,err
    end,
    export=function(kind,id)
        kind=kind or'binds';local ok,err=workspace:export(kind,id)
        studio:notify(err or'Экспорт не выполнен.',kind=='notes'and'hints'or'binds',false,ok and'info'or'warning')
    end,
    import=function(kind)
        kind=kind or'binds';local data,err=workspace:prepareImport(kind);studio.importPreview=data
        studio:notify(err or'',kind=='notes'and'hints'or'binds',false)
    end,
    confirmImport=function(data)
        local ok,err=workspace:import(data);local notes=data.format=='police-assistant.notes'
        studio:notify(err or(ok and(notes and'Заметки добавлены.'or'Бинды добавлены выключенными.')or'Импорт не выполнен.'),notes and'hints'or'binds',false,ok and'info'or'warning')
        return ok,err
    end,
}
for _,name in ipairs({'openAssist','openQuick','openTips'})do
    local original=studioCallbacks[name]
    studioCallbacks[name]=function(...)
        local args={...}
        return studio:requestNavigation(function()original(unpack(args))end,'открыть другое окно PA')
    end
end
local knowledgeCallbacks={codec=codec,nextBindingId=function()return workspace.library.next_id end,
    openCaseGround=function(kind,reference)if not reference then return studioCallbacks.openProcedures(kind)end;return studioCallbacks.groundHandoff({article=reference,basis=reference},kind)end,
    openMark=function()return studioCallbacks.openProcedures('mark')end,
    openOperational=function(topic)
        studioCallbacks.openAssist('traffic');studio.copilotPage=topic=='rights'and'rights'or topic=='traffic'and'work'or'grounds'
    end,
    openWanted=function(reason)
        studio.wantedSuggestedReason=reason
        studioCallbacks.openProcedures('wanted')
        -- Legal hints never revive a previously completed identity/consent form.
        studio.caseForm=nil
        if studio.caseStoredForms then studio.caseStoredForms.wanted=nil end
    end,
    createBinding=function(binding,form)
        if studio.dirty then return nil,'Сначала сохраните или отмените текущий черновик бинда.' end
        if #workspace.library.bindings>=128 then return nil,'Достигнут лимит 128 биндов.' end
        studio:createBinding()
        studio.draft=bindingModel.copy(binding);studio.selected=binding.id;studio.dirty=true;studio.editorTab='text'
        if form and binding.knowledge.identity=='passport'then studio:setBuffer('args:editor'..binding.id..':ic_name',form.ic_name,512)end
        menu.section='binds';studio:notify('Черновик из базы знаний. Проверьте фразы и параметры, затем сохраните.','binds',nil,'info')
        return true
    end}
env.wheelNavigate=function(route,profile,target)
    if route.kind=='copilot'then
        local state=bindingModel.copy(alerts.state or{});state.copilot=sceneServices.copilot:view()
        local catalog=wheelModel.build(workspace.library,env.wheelRevision(),false,state)
        local item=catalog and catalog.bySystem[route.id]
        if not item or item.kind~='copilot'then return false end
        if item.action=='fast_pt'then return studioCallbacks.fastPt()end
        studioCallbacks.openAssist('traffic')
        if item.action=='rights'then studio.copilotPage='rights'
        else sceneServices.copilotUi.offer(studio,studioCallbacks,item.action)end
        return true
    end
    if route.kind=='assist'then
        if route.id~='assist-megaphone'or not workspace.library.vehicle.megaphone_wheel then return false end
        studioCallbacks.openAssist('megaphone');return true
    end
    if route.kind=='procedure'then
        local kind=({['procedure-wanted']='wanted',['procedure-wanted_list']='wanted_list',['procedure-fine']='fine',['procedure-mark']='mark'})[route.id]
        local cfg=workspace.library.procedures
        if not kind or not caseFormsModule.enabled(cfg,kind)then return false end
        local selected=workspace.selectedTarget
        if target and(not selected or target.id~=selected.id or target.name~=selected.name or target.ped~=selected.ped)then
            studio:notify('Выбор человека изменился. Откройте действие заново.','quick',false);return false
        end
        studioCallbacks.openProcedures(kind)
        if not studio.caseForm then
            local f,err=caseForms:begin(kind)
            if f then studio.caseForm=f;studio.caseStoredForms=studio.caseStoredForms or {};studio.caseStoredForms[kind]=f
            else studio:notify(err,'procedures',false)end
        end
        return true
    end
    if route.kind=='patrol'then
        studioCallbacks.openPatrol();local a=patrolSession.data.active
        if route.id=='patrol-pause'and a and a.status=='active'then studioCallbacks.patrolPause()
        elseif route.id=='patrol-resume'or route.id=='patrol-finish'then
            local p,err=patrolSession:propose(route.id=='patrol-resume'and 'resume'or 'finish')
            if p then studio.patrolConfirm=p else studio:notify(err,'patrol_session',false)end
        end
        return true
    end
    if route.kind=='alert' then return alerts:request(route.id) end
    if route.kind=='settings' then
        openWorkspace('binds'); studio:notify('В бинде откройте «Общее», включите «В радиальном меню» и выберите категорию «'..
            wheelModel.categoryName(route.category)..'».','binds',false,'info')
        return true
    end
    studioCallbacks.openQuick(); studio.quickWheelCategory=route.category; studio.quickWheelProfile=profile;studio.quickWheelScope=require('pa26_wheel_scope').active(workspace.library,alerts.state)
    studio.quickQuery=''; studio.cache.quickSearch=nil; studio.quickFavorites=false; studio.quickSelected=nil
    return true
end
env.startWheelBinding=function(item,target)
    if target then workspace:selectTarget(target) end
    local binding=item.binding
    local parameters=#binding.parameters>0 or binding.script:find('{param',1,true)
    if parameters then
        studioCallbacks.openQuick(); studio.quickWheelCategory=item.category
        studio.quickWheelScope=require('pa26_wheel_scope').active(workspace.library,alerts.state);studio.quickWheelProfile=require('pa26_wheel_scope').settings(workspace.library.settings,studio.quickWheelScope).wheel_profile
        studio.quickQuery=''; studio.cache.quickSearch=nil; studio.quickFavorites=false
    end
    local ok=studio:launchBinding(binding,studioCallbacks,'quick')
    if not ok then
        studioCallbacks.openQuick(); studio:notify(studio.status,'quick',false)
    end
    return ok
end

sceneServices.hasManualActivity=function()
    local e,v,c=sceneServices.evidence,sceneServices.vehicle,sceneServices.copilot
    local a=sceneServices.manualActions
    return e.active or e.intent or e.queued or e.archiveRequest or v.intent or v.queued or c.intent or c.queued or
        a and(a.pending or a.approved)or workspace.operations.intent or workspace.operations.offer or
        caseForms.intent or caseForms.queued or caseForms.awaitingCommand or
        patrolSession.intent or patrolSession.queued or patrolEvents.intent or patrolEvents.queued
end
local function closeForInput(reason, keepAutoOpen)
    if not ownUi()and not hasUiModal()and not sceneServices.hasManualActivity()and not runtime.wheel and not runtime.queue and
        not workspace.pending and not workspace.executor.queue and not keyRecorder and not pendingWheelClick and
        not uiTyping and not widgetCursor and not hud.editing and not hud.drag and imgui.DisableInput==true then
        if not keepAutoOpen then autoOpenForSession=nil end
        return
    end
    sceneServices.showAssist[0]=false;sceneServices.showWanted[0]=false;sceneServices.hideProcedureWindows()
    if sceneServices.hasManualActivity()then cancelManualActions(reason)end
    runtime:cancel(reason)
    workspace:cancel(reason)
    showWindow[0],showQuick[0],showTips[0] = false,false,false
    cancelUiModal()
    keyRecorder=nil; pendingWheelClick=nil
    uiTyping = false
    uiInputReset = true
    hud:stopInteraction()
    if widgetFrame then widgetFrame.HideCursor = true end
    imgui.DisableInput = true -- release message capture before mimgui's next updater tick
    if not keepAutoOpen then autoOpenForSession = nil end
end

local function closePanels(force)
    if not force and studio:unsavedChanges()then
        return studio:requestNavigation(function()closePanels(true)end,'закрыть окно PA')
    end
    studio:flushAutosave(studioCallbacks,true)
    knowledge:flush()
    hideWorkspaceUi()
    workspace.pending=nil; workspace.prepared=nil
    cancelUiModal(); keyRecorder=nil; pendingWheelClick=nil
end

local function toggleWindow(force)
    if not force and ownUi()and studio:unsavedChanges()then
        return studio:requestNavigation(function()toggleWindow(true)end,showWindow[0]and'закрыть окно PA'or'открыть главное окно PA')
    end
    sceneServices.showAssist[0]=false;sceneServices.showWanted[0]=false;sceneServices.hideProcedureWindows()
    if (uiFailed or hud.failed)and recoverUi then recoverUi(true);return end
    if showWindow[0] then closePanels(force); return end
    runtime:cancel('Колесо закрыто: открыто окно PA.')
    showQuick[0],showTips[0]=false,false
    showWindow[0] = true
    uiTyping = false
    uiInputReset = true
    hud:stopInteraction()
    autoOpenForSession = nil
    imgui.DisableInput = not showWindow[0]
end

local function setDemo(value)
    if value~=runtime.demo then
        if patrolSession then patrolSession:cancelQueued('Режим изменён. Прежний доклад не повторяется.')end
        workspace:cancel('Режим изменён. Сценарий отменён.')
    end
    runtime:setDemo(value)
    demoFlag[0] = runtime.demo
end

local function readEntry(index)
    local a = core.actions[index]
    local b = buffers[a.key]
    return {enabled = b.enabled[0], me = ffi.string(b.me), do_text = ffi.string(b.do_text),
        command = ffi.string(b.command)}
end

sceneServices.authorPresets.env.callbacks=studioCallbacks
sceneServices.installAuthorPreset=function(p)
    workspace:cancel('Применён авторский набор.');runtime:cancel('Применён авторский набор.')
    if p.kind=='settings' then cfg=p.config;runtime:applyConfig(cfg);workspace.cfg=cfg;workspace.userFiles.cfg=cfg end
    local lib=workspace.userFiles:load();workspace.library=lib;workspace.libraryFresh=false;workspace.libraryRevision=workspace.libraryRevision+1;workspace.commandDirty=true
    studio.autosaves={};studio.dirty=false;studio:setLibrary(lib)
    if p.kind=='settings' then hud.settings=bindingModel.copy(cfg.widget);hud.dirty=false;hud.dirtyAt=nil end
    showWindow[0],showQuick[0],showTips[0],sceneServices.showAssist[0],sceneServices.showWanted[0]=false,false,false,false,false;sceneServices.hideProcedureWindows()
end
local generalSaveFailed=false
local function saveSettings(preferencesOnly)
    generalSaveFailed=true
    local candidate = core.defaults()
    candidate.recovery=bindingModel.copy(recoveryDraft or cfg.recovery)
    candidate.widget = hud:getSettings()
    candidate.main.demo_mode = runtime.demo
    candidate.main.show_on_connect = onConnectFlag[0]
    candidate.main.max_distance = distanceValue[0]
    candidate.main.interval_ms = intervalValue[0]
    candidate.main.menu_key, candidate.main.radial_key = draftMenuKey, draftRadialKey
    local ok, err = core.validateSettings(candidate)
    if not ok then report(err); return end
    local compatible,note=bindingModel.validate(workspace.library,candidate)
    if not compatible then report(note); return end
    for i, a in ipairs(core.actions) do
        local entry
        entry, err = core.validateAction(preferencesOnly and cfg[a.key]or readEntry(i))
        if not entry then report(a.label .. ': ' .. err); return end
        if entry.enabled then
            local plan
            plan, err = core.prepareAction(entry, 1003, codec)
            if not plan then report(a.label .. ': ' .. err); return end
        end
        candidate[a.key] = entry
    end
    runtime:cancel('Действие отменено: сохранение настроек.')
    workspace:cancel('Общие настройки изменились. Запустите сценарий повторно.')
    ok, err = storage.save(configPath, candidate)
    if not ok then report(err); return end
    local saveNote = err
    ok, err = runtime:applyConfig(candidate)
    if not ok then setDemo(true); report('INI записан, но настройки не применены: ' .. tostring(err)); return end
    cfg = candidate
    recoveryDraft=nil
    workspace.cfg=cfg
    hud.dirty, hud.dirtyAt = false, nil
    generalSaveFailed=false
    report(saveNote or 'Настройки сохранены; предыдущий исправный файл — в INI.bak.','info')
end

-- Balance ImGui scopes even if an optional font/widget API fails.
local scopes = {}
local function pushScope(f) scopes[#scopes + 1] = f end
local function endScope()
    local f = table.remove(scopes)
    f()
end
local function text(value)
    imgui.PushTextWrapPos(0)
    pushScope(function() imgui.PopTextWrapPos() end)
    imgui.TextUnformatted(tostring(value)) -- user '%' sequences cannot become native format strings
    endScope()
end
local function recordUiFailure(kind,err)
    local stamp=optionalRead('getGameTimer')or studioClock
    local keepMain,keepQuick,keepTips=showWindow[0],showQuick[0],showTips[0]
    local keepAssist=sceneServices.showAssist[0];local keepWanted=sceneServices.showWanted[0];local keepFine,keepMark,keepGround=sceneServices.showFine[0],sceneServices.showMark[0],sceneServices.showGround[0]
    recovery:trip(stamp,kind,err)
    sceneServices.patrolUiRecovery=sceneServices.patrolUiRecovery or{active=patrolSession.data.active and patrolSession.data.active.status=='active'}
    closeForInput('Ошибка интерфейса. Текущие отправки отменены.')
    if kind~='main'then
        showWindow[0],showQuick[0],showTips[0]=keepMain,keepQuick,keepTips;sceneServices.showAssist[0]=keepAssist;sceneServices.showWanted[0]=keepWanted;sceneServices.showFine[0],sceneServices.showMark[0],sceneServices.showGround[0]=keepFine,keepMark,keepGround
        imgui.DisableInput=not ownUi()
    end
    if cfg.recovery.demo_after_recovery then setDemo(true)end
    caseForms:reset('Интерфейс восстановлен. Проверьте процедуру заново.');patrolEvents:reset('Интерфейс восстановлен. Проверьте действие заново.');sceneServices.vehicle:reset('Интерфейс восстановлен. Перепроверьте машину.');alerts:reset();weapons:reset();taser:reset();weaponWarning:reset();notifications:reset()
    pushLog('Ошибка интерфейса ['..kind..']: '..tostring(err))
    pushLog('Диагностика UI: '..tostring(menu.section)..'; непрозрачность '..tostring(workspace.library.settings.opacity)..
        '; попыток восстановления '..recovery.attempts..'; F9 или /pa26repair — восстановить окна.')
    for key,rect in pairs(menu.windows)do
        pushLog(string.format('Окно %s: x=%s y=%s w=%s h=%s',key,tostring(rect.x),tostring(rect.y),tostring(rect.width),tostring(rect.height)))
    end
    report('Ошибка окна PA. Отправки остановлены; F9 или /pa26repair восстановит интерфейс. Подробности в moonloader.log.')
end
recoverUi=function(manual)
    local now=optionalRead('getGameTimer')or studioClock
    if not recovery:begin(now,cfg.recovery,manual)then return false end
    sceneServices.patrolUiRecovery=sceneServices.patrolUiRecovery or{active=patrolSession.data.active and patrolSession.data.active.status=='active'}
    closeForInput('Восстановление интерфейса. Незавершённые отправки отменены.')
    caseForms:reset('Интерфейс восстановлен. Проверьте процедуру заново.');patrolEvents:reset('Интерфейс восстановлен. Проверьте действие заново.');sceneServices.vehicle:reset('Интерфейс восстановлен. Перепроверьте машину.');alerts:reset();weapons:reset();taser:reset();weaponWarning:reset();notifications:reset()
    if cfg.recovery.demo_after_recovery then setDemo(true)end
    -- Keep drafts and loaded player data; only window/input state is rebuilt.
    menu:resetWindowPositions();uiFailed=false;hud.failed=false;alerts.failed=false;notifications.failed=false
    menu.section='settings';settingsTab='general'
    showWindow[0]=true;showQuick[0]=false;showTips[0]=false;uiTyping=false;uiInputReset=true
    autoOpenForSession=nil;imgui.DisableInput=false
    report('Окна PA восстановлены. Черновики сохранены; прежние действия не повторяются.'..
        (runtime.demo and' Сейчас включён деморежим.'or''),'info')
    return true
end
local function safeDraw(callback)
    scopes = {}
    -- Drawing runs in the renderer-selected context. Balance UI scopes on error.
    local ok, err = pcall(callback)
    if not ok then
        while #scopes > 0 do pcall(endScope) end
        uiFailed=true
        recordUiFailure('main',debug.traceback(tostring(err),2))
    end
end

local fontSubscription = imgui.OnInitialize(function()
    imgui.CaptureKeyboardFromApp(false)
    local ok, err = pcall(function()
        local io = imgui.GetIO()
        local base = getFolderPath(0x14)
        local builder = imgui.ImFontGlyphRangesBuilder()
        builder:AddRanges(io.Fonts:GetGlyphRangesCyrillic())
        -- Cyrillic ranges omit punctuation used by knowledge cards and numeric intervals.
        builder:AddText('‐‑‒–—―…•×−≈≠≤≥→←↑↓↔№«»„“”‘’✓✔▲▼★☆')
        uiGlyphRanges = imgui.ImVector_ImWchar()
        builder:BuildRanges(uiGlyphRanges)
        local ranges = uiGlyphRanges[0].Data
        for _, name in ipairs({'trebucbd.ttf', 'arialbd.ttf', 'segoeuib.ttf'}) do
            local path = base .. '\\' .. name
            if doesFileExist(path) then
                hudFont = io.Fonts:AddFontFromFileTTF(path, 14, nil, ranges)
                hudHeadingFont = io.Fonts:AddFontFromFileTTF(path, 15, nil, ranges)
                if hudFont ~= nil and hudHeadingFont ~= nil then break end
            end
        end
        for _, name in ipairs({'segoeuib.ttf', 'arialbd.ttf'}) do
            local path = base .. '\\' .. name
            if doesFileExist(path) then
                menuHeadingFont = io.Fonts:AddFontFromFileTTF(path, 24, nil, ranges)
                menuBrandFont = io.Fonts:AddFontFromFileTTF(path, 24, nil, ranges)
                menuButtonFont = io.Fonts:AddFontFromFileTTF(path, 18, nil, ranges)
                menuCompactFont = io.Fonts:AddFontFromFileTTF(path, 16, nil, ranges)
                wheelLabelFont = io.Fonts:AddFontFromFileTTF(path, 20, nil, ranges)
                wheelIdFont = io.Fonts:AddFontFromFileTTF(path, 32, nil, ranges)
                if menuHeadingFont ~= nil and menuBrandFont ~= nil then break end
            end
        end
        for _, name in ipairs({'segoeui.ttf', 'arial.ttf'}) do
            local path = base .. '\\' .. name
            if doesFileExist(path) then
                local font = io.Fonts:AddFontFromFileTTF(path, 16, nil, ranges)
                if font ~= nil then
                    io.FontDefault = font -- preserve the existing wheel's font size
                    menuBodyFont = io.Fonts:AddFontFromFileTTF(path, 18, nil, ranges) or font
                    menuSmallFont = io.Fonts:AddFontFromFileTTF(path, 16, nil, ranges) or font
                    return
                end
            end
        end
        pushLog('Шрифт с кириллицей не найден; проверьте Windows Fonts.')
    end)
    if not ok then pushLog('Не удалось загрузить шрифт: ' .. tostring(err)) end
end)
subscriptions[#subscriptions + 1] = fontSubscription

local function mainButton(label, size)
    local font = menuButtonFont
    local available = imgui.GetContentRegionAvail().x
    local visibleLabel = label:match('^(.-)##') or label
    if font ~= nil then
        imgui.PushFont(font)
        pushScope(function() imgui.PopFont() end)
    end
    if menuCompactFont ~= nil and imgui.CalcTextSize(visibleLabel).x + 28 > (size and size.x or available) then
        if font ~= nil then endScope() end
        font = menuCompactFont
        imgui.PushFont(font); pushScope(function() imgui.PopFont() end)
    end
    size = size or imgui.ImVec2(math.max(1, math.min(available, imgui.CalcTextSize(visibleLabel).x + 28)), 44)
    local clicked = menuModule.fittedButton(imgui,{push=pushScope,finish=endScope},label,size)
    if font ~= nil then endScope() end
    return clicked
end

local function chooseKeys(label, choices, value)
    text(label)
    for i, c in ipairs(choices) do
        if i > 1 then imgui.SameLine() end
        if mainButton((value == c[2] and '[ ' or '') .. c[1] ..
            (value == c[2] and ' ]' or '') .. '##' .. label .. i) then value = c[2] end
    end
    return value
end

local function drawActions()
    text('Выберите действие для настройки.')
    imgui.Separator()
    local available = imgui.GetContentRegionAvail().x
    local columns = available >= 580 and 3 or (available >= 380 and 2 or 1)
    local buttonWidth = math.max(80, (available - (columns - 1) * 10) / columns)
    for i, a in ipairs(core.actions) do
        if (i - 1) % columns ~= 0 then imgui.SameLine(0, 10) end
        local active=selectedAction==i
        if active then imgui.PushStyleColor(imgui.Col.Button,imgui.ImVec4(.15,.43,.63,1));pushScope(function()imgui.PopStyleColor(1)end)end
        if mainButton(a.label..'##select'..i,imgui.ImVec2(buttonWidth,44))then selectedAction=i end
        if active then endScope()end
    end
    imgui.Separator()
    local b = buffers[core.actions[selectedAction].key]
    imgui.Checkbox('Действие включено', b.enabled)
    imgui.PushItemWidth(-1)
    pushScope(function() imgui.PopItemWidth() end)
    text('/me — только текст после команды')
    imgui.InputText('##me', b.me, ffi.sizeof(b.me))
    text('/do — только текст после команды')
    imgui.InputText('##do', b.do_text, ffi.sizeof(b.do_text))
    text('Команда сервера: /command {id} либо пусто')
    imgui.InputText('##command', b.command, ffi.sizeof(b.command))
    endScope()
    if mainButton('Проверить текущий текст локально') then
        if runtime:preview(selectedAction, readEntry(selectedAction)) then metrics.previews = metrics.previews + 1 end
    end
    if mainButton('Сохранить все изменения') then saveSettings() end
    if available >= 760 then imgui.SameLine(0, 12) end
    if mainButton('Вернуть сохранённые значения') then loadDraft() end
    text('Предпросмотр использует текст в полях и не переключает режим.')
end

local function drawWidgetSettings()
    local changed=false
    widgetVisible[0] = hud.settings.visible
    if imgui.Checkbox('Показывать компактный виджет', widgetVisible) then hud:setVisible(widgetVisible[0]);changed=true end
    widgetScale[0] = hud.settings.scale
    if imgui.SliderFloat('Размер виджета', widgetScale, 0.65, 2) then hud:change('scale', widgetScale[0]);changed=true end
    if mainButton('Вернуть виджет на исходное место') then hud:resetPosition();changed=true end
    text('Чтобы передвинуть виджет, удерживайте на нём правую кнопку мыши. Если другие окна закрыты, удерживайте Alt, чтобы показать курсор.')
    text('Часы виджета')
    if mainButton((hud.settings.time_source == 'local' and '[ Компьютер ]' or 'Компьютер') .. '##hudclock') then
        hud:change('time_source', 'local'); hud.lastNow = nil;changed=true
    end
    imgui.SameLine()
    if mainButton((hud.settings.time_source == 'game' and '[ Игровые ]' or 'Игровые') .. '##hudclock') then
        hud:change('time_source', 'game'); hud.lastNow = nil;changed=true
    end
    text('Дата берётся с компьютера. Для времени можно выбрать часы компьютера или часы GTA.')
    imgui.Separator()
    return changed
end

settingsTab='profile'
local function settingsHeading(value)
    imgui.Dummy(imgui.ImVec2(0,6))
    if menuButtonFont then imgui.PushFont(menuButtonFont); pushScope(function() imgui.PopFont() end) end
    text(value)
    if menuButtonFont then endScope() end
    imgui.Dummy(imgui.ImVec2(0,4))
end
local function drawSettingsTabs()
    sceneServices.settingsUi.drawTabs(studio,{push=pushScope,finish=endScope,text=text},settingsTab,function(tab)settingsTab=tab end,menuSmallFont or menuButtonFont or imgui.GetFont())
end
local function drawGeneralSettings(part)
    local changed=false
    if part=='controls'then
    settingsHeading('Клавиши и выполнение сценариев')
    if imgui.SliderFloat('Дистанция, м', distanceValue, 3, 12)then changed=true end
    if imgui.SliderInt('Интервал, мс', intervalValue, 1000, 5000)then changed=true end
    settingsHeading('Клавиши основного меню')
    local menuKey,radialKey=chooseKeys('Клавиша окна',core.menuKeys,draftMenuKey),chooseKeys('Клавиша колеса',core.wheelKeys,draftRadialKey)
    if menuKey~=draftMenuKey or radialKey~=draftRadialKey then draftMenuKey,draftRadialKey=menuKey,radialKey;changed=true end
    elseif part=='hud'then
    settingsHeading('Компактный виджет · HUD')
    if drawWidgetSettings()then changed=true end
    elseif part=='mode'then
    settingsHeading('Режим работы')
    text(runtime.demo and'Режим: ДЕМО · без отправки' or'Режим: РЕАЛЬНЫЙ · команды передаются в игру')
    if mainButton('Изменить режим в профиле##mode-profile')then studioCallbacks.openSettings('profile')end
    if imgui.Checkbox('Открывать окно после входа в персонажа', onConnectFlag)then changed=true end
    else
    settingsHeading('Восстановление PA')
    local d=bindingModel.copy(recoveryDraft or cfg.recovery)
    local enabled=new.bool(d.enabled)
    if imgui.Checkbox('Восстанавливать PA после ошибок##recovery-enabled',enabled)then d.enabled=enabled[0];changed=true end
    local demo=new.bool(d.demo_after_recovery)
    if imgui.Checkbox('После восстановления включать деморежим##recovery-demo',demo)then d.demo_after_recovery=demo[0];changed=true end
    for _,p in ipairs({{'delay_ms','Пауза перед восстановлением, с',1000},{'max_attempts','Попыток подряд',1},{'stable_ms','Сбросить счётчик после работы без ошибок, с',1000}})do
        local value=new.int(d[p[1]]/p[3])
        if imgui.InputInt(p[2]..'##recovery-'..p[1],value)then d[p[1]]=value[0]*p[3];changed=true end
    end
    text('Пауза между попытками: 1–30 секунд; число попыток: 1–5. После 1–600 секунд стабильной работы счётчик ошибок обнуляется. Если ошибки повторяются, автоматический перезапуск прекращается.')
    text('Если перестало открываться окно, PA остановит отправки и восстановит интерфейс, сохранив черновики. Если остановился весь скрипт, отдельный модуль попробует загрузить его заново. При полном перезапуске несохранённые черновики теряются. Если закрылась сама GTA, потребуется запустить игру снова.')
    text('/pa26repair восстанавливает окна; /pa26restart запускает остановившийся скрипт. Окна можно двигать за заголовок либо зажатой ПКМ по окну; размер меняется за края. Начальный размер стал шире и подстраивается под экран.')
    if changed then recoveryDraft=d end
    if mainButton('Восстановить окна PA##recovery-now')then recoverUi(true)end
    end
    if changed then saveSettings(true)end
    if generalSaveFailed and mainButton('Повторить запись##general-retry')then saveSettings(true)end
end
local function drawSettingsPage()
    local tab,sub=sceneServices.settingsUi.route(settingsTab)
    settingsTab=tab;if sub then studio.screenSettingsPage=sub end
    sceneServices.settingsUi.draw(studio,{push=pushScope,finish=endScope,text=text},studioData(),studioCallbacks,settingsTab,{menu=menu,general=drawGeneralSettings})
end

local function drawLogPage()
    if mainButton('Очистить журнал') then log = {} end
    for _, line in ipairs(log) do text(line) end
end

studioCallbacks.systemLog=drawLogPage
studioCallbacks.openSettings=function(tab,sub)
    return studio:requestNavigation(function()
        openWorkspace('settings',true);settingsTab=tab or'profile'
        if tab=='chat'and sub then studio.chatSettingsPage=sub end
        if tab=='general'and sub then studio.screenSettingsPage=sub end
    end,'открыть настройки PA')
end

menu.windowConfig=function()
    local pending=studio.autosaves and studio.autosaves.window_layout
    return pending and pending.value or workspace.library.settings.window_layout
end
menu.geometryChanged=function(key,rect)
    local config=menu.windowConfig();if not config.remember or require('pa26_window_layout').same(config.windows[key],rect)then return end
    config=bindingModel.copy(config);config.windows[key]=bindingModel.copy(rect)
    studio:autoSettings('window_layout',{'settings','window_layout'},config)
    local pending=studio.autosaves and studio.autosaves.window_layout;if pending then pending.delay=700 end
end
local function drawMain()
    local io = imgui.GetIO()
    uiTyping = io.WantTextInput == true
    if not core.finite(io.DisplaySize.x) or not core.finite(io.DisplaySize.y) or
        io.DisplaySize.x < 220 or io.DisplaySize.y < 220 then uiTyping = false; return end
    if not menu:prepareWindow(imgui,'main') then return end
    local overHudOk, overHud = pcall(hud.overWidget, hud, imgui)
    if overHudOk then overHud=(overHud and not alerts.suppressHud) or alerts:overWidget(imgui) or taser:overWidget(imgui)or notifications:overWidget(imgui)or sceneServices.copilotUi.over(sceneServices.copilot,imgui)end
    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoSavedSettings +
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse+
        imgui.WindowFlags.NoResize+imgui.WindowFlags.NoMove
    if overHudOk and overHud then flags = flags + imgui.WindowFlags.NoMouseInputs end
    local ui = {push = pushScope, finish = endScope, text = text}
    local baseDepth = #scopes
    if menuBodyFont ~= nil then imgui.PushFont(menuBodyFont); pushScope(function() imgui.PopFont() end) end
    menu.opacity=studio.optionOpacity or workspace.library.settings.opacity
    menu.compact=studio.optionCompact; if menu.compact==nil then menu.compact=workspace.library.settings.compact end
    menu:pushTheme(imgui, ui)
    local expanded = imgui.Begin('Police Assistant 2026##pa26-main', showWindow, flags)
    pushScope(function() imgui.End() end)
    if expanded then
        menu:resizeWindow(imgui,ui,'main')
        local model = {
            connected = hud.connected, nickname = hud.data.nickname or '—', id = hud.data.id or '—',
            ping = hud.data.ping, district = hud.data.district, mapSquare=sceneServices.mapValues and sceneServices.mapValues.map_square, clock = hud.data.clock,
            demo = runtime.demo, sent = metrics.sent, previews = metrics.previews, connections = metrics.connections,
            menuKey = core.keyName(cfg.main.menu_key), wheelKey = core.keyName(cfg.main.radial_key),
            actions = core.actions,
            evidence=sceneServices.evidence:view(),variables=bindingModel.variables,variableInfo=bindingModel.variableInfo,caseNumber=workspace.library.profile.case_number,
            quickKey=bindingModel.keyName(workspace.library.settings.quick_key),tipsKey=bindingModel.keyName(workspace.library.settings.tips_key),assistKey=bindingModel.shortcutName(workspace.library.assist.open_shortcut),
        }
        menu:draw(imgui, ui, model, {
            actions = function() studio:draw('binds',ui,studioData(),studioCallbacks) end,
            updates=function()require('pa26_update_ui').draw(studio,ui,sceneServices.updater,studioCallbacks,sceneServices.authorPresets)end,
            updateLabel=sceneServices.updater:label(),
            openSettings=studioCallbacks.openSettings,
            settings = drawSettingsPage, settingsTabs=drawSettingsTabs,
            settingsTabHeight=function(width)return sceneServices.settingsUi.tabLayout(width,menuSmallFont or menuButtonFont or imgui.GetFont()).total end,
            widget = drawWidgetSettings, log = drawLogPage,
            binds=function() studio:draw('binds',ui,studioData(),studioCallbacks) end,
            hints=function() studio:draw('hints',ui,studioData(),studioCallbacks) end,
            partners=function() studio:draw('partners',ui,studioData(),studioCallbacks) end,
            openPatrol=studioCallbacks.openPatrol,
            patrol=function()studio:draw('patrol',ui,studioData(),studioCallbacks)end,
            patrolEvents=function()studio:draw('patrol_events',ui,studioData(),studioCallbacks)end,
            vehicle=function()studio:draw('vehicle',ui,studioData(),studioCallbacks)end,
            evidence=function()sceneServices.assistUi.evidence(studio,ui,studioData(),studioCallbacks)end,
            training=function()sceneServices.assistUi.study(studio,ui,studioData(),studioCallbacks)end,
            stats=function() studio:draw('stats',ui,studioData(),studioCallbacks) end,
            openAssist=studioCallbacks.openAssist,
            extras=function() studio:draw('recruitment',ui,studioData(),studioCallbacks) end,
            identity=function()studio:draw('identity',ui,studioData(),studioCallbacks)end,
            procedures=function()studio:draw('procedures',ui,studioData(),studioCallbacks)end,
            operations=function()studio:draw('operations',ui,studioData(),studioCallbacks)end,
            knowledge=function()
                knowledgeUi.buttonFont=menuCompactFont;knowledgeUi.headingFont=menuButtonFont
                knowledgeUi:draw(ui,knowledgeCallbacks)
            end,
            selectAction = function(index) selectedAction = index end,
            close = closePanels,
            guardNavigation=function(action,label)return studio:requestNavigation(action,label)end,
            finishWork=function()studio:requestNavigation(function()studio.shutdownConfirm=true end,'отключить Police Assistant')end,
        }, {heading = menuHeadingFont, brand = menuBrandFont, button = menuButtonFont, small = menuSmallFont, compact = menuCompactFont})
        studio:drawModal(ui,studioData(),studioCallbacks)
        knowledgeUi:drawModal(ui)
    end
    endScope()
    while #scopes > baseDepth do endScope() end
    uiTyping = ownUi() and io.WantTextInput == true
    uiRendered = true
    if not ownUi() then imgui.DisableInput = true end
end

local function beforeUiFrame()
    -- mimgui switches to this script's context before this callback. Use the
    -- public ImGui override before NewFrame: buttons/wheel do not own keyboard;
    -- text fields retain input capture for editing.
    if uiInputReset then
        -- Only our ImGuiIO cache, in its selected renderer context. A key-up
        -- missed while DisableInput was true must not repeat on the next open.
        local io = imgui.GetIO()
        ffi.fill(io.KeysDown, ffi.sizeof(io.KeysDown))
        ffi.fill(io.MouseDown, ffi.sizeof(io.MouseDown))
        io.MouseWheel, io.MouseWheelH = 0, 0
        io:ClearInputCharacters()
        uiInputReset = false
    end
    imgui.CaptureKeyboardFromApp(ownUi() and (uiTyping or hasUiModal()))
    local otherUi = not uiFailed and (ownUi() or runtime.wheel ~= nil)
    local ok, wantsMouse = pcall(function()
        hud:prepareInput(imgui, otherUi,widgetCursor)
        local fonts={body=hudFont,heading=hudHeadingFont}
        taser:reserve(imgui,hud,fonts);sceneServices.copilotUi.reserve(sceneServices.copilot,imgui,hud,fonts,hud.equipmentHeight);alerts:measure(imgui,hud,fonts);taser:place(imgui,hud,fonts);sceneServices.copilotUi.place(sceneServices.copilot,imgui,hud,fonts)
        notifications:measure(imgui,fonts,noticeAvoid())
        return hud:wantsMouse(imgui) or ((ownUi() or widgetCursor or hud.editing) and (alerts:overWidget(imgui) or taser:overWidget(imgui)or notifications:overWidget(imgui)or sceneServices.copilotUi.over(sceneServices.copilot,imgui)))
    end)
    if not ok then
        local firstFailure=not hud.failed
        hud.failed = true
        hud:stopInteraction()
        alerts.failed=true;alerts:reset('Ввод карточки связи недоступен.')
        if widgetFrame then widgetFrame.HideCursor = true end
        pushLog('Ввод компактного виджета отключён: ' .. tostring(wantsMouse))
        if firstFailure then recordUiFailure('input',wantsMouse)end
    end
    if ok and wantsMouse then imgui.CaptureMouseFromApp(true)
    elseif not otherUi then imgui.CaptureMouseFromApp(false) end
end

local windowFrame = imgui.OnFrame(function()
    if isGamePaused() then closeForInput('Пауза игры. Действие отменено.'); return false end
    return not shutdown and not uiFailed and focused and showWindow[0] and not isGamePaused()
end, function() safeDraw(beforeUiFrame) end, function() safeDraw(drawMain) end)
windowFrame.LockPlayer, windowFrame.HideCursor = false, false
subscriptions[#subscriptions + 1] = windowFrame

sceneServices.wheelEditInput=function(io,wheel,hit,blocked)
 if workspace.library.settings.wheel_edit_enabled==false then return false end
 local ctrl=io.KeyCtrl==true;local down=imgui.IsMouseDown and imgui.IsMouseDown(0)or io.MouseDown[0]==true
 local previous=wheel.editMouseDown;wheel.editMouseDown=down
 local intent=require('pa26_wheel_edit').update(wheel,hit,{ctrl=ctrl,down=down,clicked=imgui.IsMouseClicked(0),
    released=previous==true and not down,blocked=blocked,now=studioClock},workspace.libraryRevision)
 if intent then intent.scope=wheel.scope;wheel.pendingEdit=intent end
 if ctrl or wheel.editConsumed then wheel.choice=nil;pendingWheelClick=nil;return true end
 return false
end
sceneServices.processWheelEdit=function()
 local w=runtime.wheel;local p=w and w.pendingEdit;if not p then return end;w.pendingEdit=nil
 local age=core.elapsed(studioClock,p.at);local ctx=context()
 if p.revision~=workspace.libraryRevision or not age or age>1500 or not focused or ctx.blocked or ctx.paused or hasUiModal()then return end
 local scope=require('pa26_wheel_scope').active(workspace.library,alerts.state);if p.scope~=scope then return end
 local lib=bindingModel.copy(workspace.library);local source,target=p.source,p.target
 if source.ring=='classic'then
  if require('pa26_wheel_scope').settings(lib.settings,scope).wheel_mode~='classic'or source.index<1 or source.index>6 or target.index<1 or target.index>6 then return end
  local slots=require('pa26_wheel_scope').slots(lib,scope);slots[source.index],slots[target.index]=slots[target.index],slots[source.index]
 else
  if not w.catalog or w.catalog.revision~=env.wheelRevision()or source.category~=target.category then return end
  local group=source.ring=='root'and'root'or source.category;local visible={}
  if source.ring=='root'then for _,cat in ipairs(w.catalog.categories)do visible[#visible+1]=cat.id end
  else local cat=w.catalog.byCategory[group];if not cat then return end
   for _,item in ipairs(cat.items)do visible[#visible+1]=require('pa26_wheel_order').key(item)end
  end
  local key=require('pa26_wheel_scope').key(scope,'order');local values=require('pa26_wheel_order').swap(lib.settings[key][group],visible,source.key,target.key)
  if not values then return end;lib.settings[key][group]=values
 end
 local active=w.catalog and w.nav.active and w.catalog.categories[w.nav.active].id
 local ok,why=workspace:save(lib)
 if not ok then studio:notify('Порядок не сохранён: '..tostring(why),'options',false);return end
 if w.catalog then w.catalog=env.wheelCatalog();w.nav={};for i,c in ipairs(w.catalog.categories)do if c.id==active then w.nav.active=i end end end
 w.choice=nil;w.editConsumed=true
end
local function drawCategoryWheel(io,wheel)
    local layout=wheelModel.layout(io.DisplaySize.x,io.DisplaySize.y,#wheel.catalog.categories)
    if not layout then runtime:cancel('Экран слишком мал для колеса.'); return end
    imgui.SetNextWindowPos(imgui.ImVec2(layout.left,layout.top),imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(layout.width,layout.height),imgui.Cond.Always)
    imgui.Begin('PA26 wheel##pa26',nil,imgui.WindowFlags.NoDecoration+imgui.WindowFlags.NoMove+
        imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoBackground+imgui.WindowFlags.NoScrollWithMouse)
    pushScope(function() imgui.End() end)
    local overWidget=(not alerts.suppressHud and hud:overWidget(imgui)) or hud.drag~=nil or alerts:overWidget(imgui) or taser:overWidget(imgui)or notifications:overWidget(imgui)or sceneServices.copilotUi.over(sceneServices.copilot,imgui)
    local route=wheelModel.hover(wheel.nav,wheel.catalog,layout,io.MousePos.x-layout.cx,io.MousePos.y-layout.cy,
        studioClock,overWidget,wheel.demo,wheel.target)
    if wheel.drag and wheel.drag.ring=='child'then for i,c in ipairs(wheel.catalog.categories)do if c.id==wheel.drag.category then wheel.nav.active=i end end end
    local editing=sceneServices.wheelEditInput(io,wheel,wheelModel.editHit(wheel.catalog,layout,wheel.nav,io.MousePos.x-layout.cx,io.MousePos.y-layout.cy),overWidget)
    if editing then route=nil end
    runtime:setBindingChoice(route,studioClock)
    local nickname=wheel.target and wheel.target.name
    if nickname and not core.validUtf8(nickname) then
        local ok,value=pcall(codec.decode,nickname); nickname=ok and core.validUtf8(value) and value or 'Игрок'
    end
    if nickname then nickname=nickname:gsub('~[^~]*~',''):gsub('%c','') end
    -- Filled arc cells share edges. Disable fill antialiasing for their interior
    -- to avoid dark seams with translucent fills; restore even after draw errors.
    local list=imgui.GetWindowDrawList(); local flags=list.Flags
    if core.finite(flags) then list.Flags=bit.band(flags,bit.bnot(2)); pushScope(function() list.Flags=flags end) end
    wheelModel.draw(imgui,layout,wheel.catalog,wheel.nav,{demo=wheel.demo,target=wheel.target,nickname=nickname,
        key=bindingModel.keyName(cfg.main.radial_key),editEnabled=workspace.library.settings.wheel_edit_enabled~=false},
        {heading=menuHeadingFont,button=wheelLabelFont,body=menuBodyFont,small=menuSmallFont,id=wheelIdFont})
    if core.finite(flags) then endScope() end
    if route and imgui.IsMouseClicked(0) and not overWidget then pendingWheelClick=bindingModel.copy(route) end
    endScope()
end
local function drawWheel()
    local io = imgui.GetIO()
    if not core.finite(io.DisplaySize.x) or not core.finite(io.DisplaySize.y) then
        runtime:cancel('Разрешение экрана недоступно. Колесо закрыто.'); return
    end
    if runtime.wheel and runtime.wheel.catalog then drawCategoryWheel(io,runtime.wheel); return end
    local scale = math.min(1, (io.DisplaySize.x - 32) / 600, (io.DisplaySize.y - 32) / 650)
    if scale < .55 then runtime:cancel('Экран слишком мал для колеса.'); return end
    local width, height = 600 * scale, 650 * scale
    local left, top = (io.DisplaySize.x - width) / 2, (io.DisplaySize.y - height) / 2
    imgui.SetNextWindowPos(imgui.ImVec2(left, top), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(width, height), imgui.Cond.Always)
    imgui.Begin('PA26 wheel##pa26', nil, imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove +
        imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoBackground + imgui.WindowFlags.NoScrollWithMouse)
    pushScope(function() imgui.End() end)
    local wheel = runtime.wheel
    if not wheel then endScope(); return end
    local draw, vec = imgui.GetWindowDrawList(), imgui.ImVec2
    local cx, cy = left + width / 2, top + 325 * scale
    local outer, inner = 218 * scale, 92 * scale
    local overWidget = (not alerts.suppressHud and hud:overWidget(imgui)) or hud.drag ~= nil or alerts:overWidget(imgui) or taser:overWidget(imgui)or notifications:overWidget(imgui)or sceneServices.copilotUi.over(sceneServices.copilot,imgui)
    local ready = wheel.demo or wheel.target ~= nil
    local choice = ready and not overWidget and core.radialAction(io.MousePos.x - cx, io.MousePos.y - cy, inner, outer) or nil
    if choice then local b=bindingModel.find(workspace.library,require('pa26_wheel_scope').slots(workspace.library,wheel.scope)[choice]); if not b or not b.enabled then choice=nil end end
    local editIndex=core.radialAction(io.MousePos.x-cx,io.MousePos.y-cy,inner,outer)
    local editBinding=editIndex and bindingModel.find(workspace.library,require('pa26_wheel_scope').slots(workspace.library,wheel.scope)[editIndex])
    local hit=editIndex and{ring='classic',category='classic',index=editIndex,key=tostring(editIndex),name=editBinding and editBinding.name or'Пустой сектор'}
    if sceneServices.wheelEditInput(io,wheel,hit,overWidget)then choice=nil end
    runtime:setChoice(choice)
    local function color(r, g, b, a) return imgui.ColorConvertFloat4ToU32(imgui.ImVec4(r, g, b, a or 1)) end
    local white, muted = color(1, 1, 1, 1), color(.67, .77, .85, 1)
    draw:AddRectFilled(vec(left, top), vec(left + width, top + height), color(.07, .075, .085, .91), 18 * scale)
    draw:AddRect(vec(left, top), vec(left + width, top + height), color(.31, .37, .43, .50), 18 * scale)
    local function fitted(value, font, size, limit)
        while font:CalcTextSizeA(size, 100000, 0, value).x > limit and #value > 0 do
            local i = #value
            while i > 0 and value:byte(i) >= 128 and value:byte(i) <= 191 do i = i - 1 end
            value = value:sub(1, i - 1)
        end
        return value
    end
    local function centered(value, font, size, x, y, tint, limit)
        font = font or imgui.GetFont(); size = size * scale
        value = fitted(value, font, size, (limit or 560) * scale)
        local measure = font:CalcTextSizeA(size, 100000, 0, value)
        draw:AddTextFontPtr(font, size, vec(x - measure.x / 2, y - measure.y / 2), tint, value)
    end
    local labelFont = wheelLabelFont or menuButtonFont or imgui.GetFont()
    draw:AddTextFontPtr(menuButtonFont or imgui.GetFont(), 18 * scale, vec(left + 24 * scale, top + 20 * scale), white, 'Police Assistant 2026')
    draw:AddTextFontPtr(menuSmallFont or imgui.GetFont(), 16 * scale, vec(left + 24 * scale, top + 50 * scale), muted, 'Радиальное меню по наведению на игрока')
    for slot, index in ipairs(core.wheelSlots) do
        local action = bindingModel.find(workspace.library,require('pa26_wheel_scope').slots(workspace.library,wheel.scope)[index]) or {name='Пусто',enabled=false}
        local beginAngle = -math.pi / 2 + (slot - 1) * math.pi / 3
        local endAngle = beginAngle + math.pi / 3
        local enabled = ready and action.enabled
        local fill = not enabled and color(.13, .15, .18, .82) or
            (choice == index and color(.15, .38, .64, .98) or color(.15, .20, .26, .96))
        -- Each filled sector is convex; the center disc masks its inner portion.
        draw:PathClear(); draw:PathLineTo(vec(cx, cy))
        draw:PathArcTo(vec(cx, cy), outer, beginAngle, endAngle, 20)
        draw:PathLineTo(vec(cx, cy)); draw:PathFillConvex(fill)
    end
    -- Draw dividers after all fills so neighboring sectors cannot cover half
    -- of a divider's stroke or antialiasing.
    for slot, index in ipairs(core.wheelSlots) do
        local action = bindingModel.find(workspace.library,require('pa26_wheel_scope').slots(workspace.library,wheel.scope)[index]) or {name='Пусто',enabled=false}
        local beginAngle = -math.pi / 2 + (slot - 1) * math.pi / 3
        local endAngle = beginAngle + math.pi / 3
        local enabled = ready and action.enabled
        draw:AddLine(vec(cx + math.cos(beginAngle) * inner, cy + math.sin(beginAngle) * inner),
            vec(cx + math.cos(beginAngle) * outer, cy + math.sin(beginAngle) * outer), color(.39, .47, .54, 1), 2.5 * scale)
        local middle, radius = (beginAngle + endAngle) / 2, 156 * scale
        local label = action.name
        centered(label, labelFont, 20, cx + math.cos(middle) * radius,
            cy + math.sin(middle) * radius, enabled and white or muted, 148)
    end
    draw:AddCircle(vec(cx, cy), outer, color(.39, .47, .54, 1), 96, 3 * scale)
    draw:AddCircleFilled(vec(cx, cy), inner, color(.07, .12, .18, .99), 80)
    draw:AddCircle(vec(cx, cy), inner, color(.39, .47, .54, 1), 80, 3 * scale)
    draw:AddCircle(vec(cx, cy), inner - 5 * scale, color(.39, .47, .54, .80), 80, scale)
    local idText = wheel.demo and 'ID 42' or (wheel.target and 'ID ' .. tostring(wheel.target.id) or 'Нет цели')
    local nickname = wheel.demo and 'Демо-игрок' or (wheel.target and wheel.target.name or 'Центр экрана')
    if not core.validUtf8(nickname) then
        local ok, decoded = pcall(codec.decode, nickname)
        nickname = ok and core.validUtf8(decoded) and decoded or 'Игрок'
    end
    nickname = nickname:gsub('~[^~]*~', ''):gsub('%c', '')
    centered(idText, wheelIdFont or menuHeadingFont, 32, cx, cy - 22 * scale, white, 170)
    centered(nickname, menuBodyFont, 18, cx, cy + 18 * scale, muted, 156)
    if choice then local b=bindingModel.find(workspace.library,require('pa26_wheel_scope').slots(workspace.library,wheel.scope)[choice]); if b then centered(b.name,menuSmallFont,14,cx,cy+49*scale,muted,146) end end
    for n,e in ipairs({wheel.nav.editSource or false,wheel.nav.editTarget or false})do if e then
        for slot,index in ipairs(core.wheelSlots)do if index==e.index then local a=-math.pi/2+(slot-1)*math.pi/3
            wheelModel.outline(draw,vec,cx,cy,inner,outer,a,a+math.pi/3,n==1 and color(.25,1,.65,1)or color(1,.8,.25,1),3*scale)
        end end
    end end
    centered(wheel.drag and('Перемещение: «'..wheelModel.shortLabel(wheel.drag.name:gsub('\n',' '))..'»')or'Выбор действия мышью',menuButtonFont,18,cx,top+574*scale,white,550)
    if workspace.library.settings.wheel_edit_enabled~=false then centered('Ctrl + ЛКМ — перетащить сектор и поменять местами',menuSmallFont,12,cx,top+600*scale,muted,550)end
    local hint = not ready and 'Отпустите X, наведите центр камеры на игрока рядом и повторите.' or
        (wheel.demo and 'ДЕМО: отправки нет. X — выбор, Esc — отмена.' or 'X — выбор, Esc — отмена. Цель закреплена.')
    centered(hint, menuSmallFont, 14, cx, top + 618 * scale, muted, 552)
    if choice and imgui.IsMouseClicked(0) and not overWidget then pendingWheelClick=choice end
    endScope()
end

local wheelFrame = imgui.OnFrame(function()
    if isGamePaused() then closeForInput('Пауза игры. Действие отменено.'); return false end
    return not shutdown and not uiFailed and focused and runtime.wheel ~= nil and not isGamePaused()
end, function() safeDraw(beforeUiFrame) end, function() safeDraw(drawWheel) end)
wheelFrame.LockPlayer, wheelFrame.HideCursor = false, false
subscriptions[#subscriptions + 1] = wheelFrame

local function drawWorkspaceWindows()
    local io=imgui.GetIO(); local ui={push=pushScope,finish=endScope,text=text}
    local wasQuick,wasTips=showQuick[0],showTips[0]
    local wasAssist=sceneServices.showAssist[0];local wasWanted=sceneServices.showWanted[0];local wasProcedure=sceneServices.procedureWindows()
    local depth=#scopes
    menu.opacity=studio.optionOpacity or workspace.library.settings.opacity; menu:pushTheme(imgui,ui)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(18,18)); pushScope(function() imgui.PopStyleVar(1) end)
    local function window(title,flag,key,body)
        if not menu:prepareWindow(imgui,key) then return end
        local flags=imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoMove+imgui.WindowFlags.NoResize+imgui.WindowFlags.NoScrollbar+imgui.WindowFlags.NoScrollWithMouse
        if alerts:overWidget(imgui) or taser:overWidget(imgui)or notifications:overWidget(imgui)or sceneServices.copilotUi.over(sceneServices.copilot,imgui)then flags=flags+imgui.WindowFlags.NoMouseInputs end
        local visible=imgui.Begin(title,flag,flags)
        if not flag[0]and studio:unsavedChanges()then
            flag[0]=true
            studio:requestNavigation(function()flag[0]=false;studio:flushAutosave(studioCallbacks,true)end,'закрыть дополнительное окно PA')
        end
        pushScope(function() imgui.End() end)
        if visible then menu:resizeWindow(imgui,ui,key);menuModule.scrollBody(imgui,ui,'workspace-content##'..key,body,key=='wanted'and 12 or 0);studio:drawModal(ui,studioData(),studioCallbacks)end
        endScope()
    end
    if showQuick[0] then window('Police Assistant · Быстрое меню##pa26-quick',showQuick,'quick',function() studio:drawQuick(ui,studioData(),studioCallbacks) end) end
    if showTips[0] then window('Police Assistant · Памятки##pa26-tips',showTips,'tips',function() studio:drawNotes(ui,studioData(),studioCallbacks,true) end) end
    if sceneServices.showAssist[0]then window('Police Assistant · Помощники##pa26-assist',sceneServices.showAssist,'assist',function()sceneServices.assistUi.draw(studio,ui,studioData(),studioCallbacks)end)end
    if sceneServices.showWanted[0]then window('Police Assistant · Розыск##pa26-wanted',sceneServices.showWanted,'wanted',function()require('pa26_wanted_window').draw(studio,ui,studioData(),studioCallbacks)end)end
    if sceneServices.showFine[0]then window('Police Assistant · Штраф (/ticket)##pa26-fine',sceneServices.showFine,'fine',function()require('pa26_fine_window').draw(studio,ui,studioData(),studioCallbacks)end)end
    if sceneServices.showMark[0]then window('Police Assistant · Пеленгация (/setmark)##pa26-mark',sceneServices.showMark,'mark',function()require('pa26_mark_window').draw(studio,ui,studioData(),studioCallbacks)end)end
    if sceneServices.showGround[0]then window(studio.groundForm and studio.groundForm.request.kind=='detention'and'Основание задержания и права##pa26-ground'or'Причина остановки 10-55 и документы##pa26-ground',sceneServices.showGround,'ground',function()require('pa26_ground_window').draw(studio,ui,studioData(),studioCallbacks)end)end
    if(studio:hasModal()or studio.modalVisible or studio.statusInfo~=nil)and not showWindow[0]and not showQuick[0]and not showTips[0]and not sceneServices.showAssist[0]and not sceneServices.showWanted[0]and not sceneServices.procedureWindows()then
        imgui.SetNextWindowPos(imgui.ImVec2(0,0),imgui.Cond.Always);imgui.SetNextWindowSize(imgui.ImVec2(1,1),imgui.Cond.Always)
        imgui.Begin('PA##warning-host',nil,imgui.WindowFlags.NoDecoration+imgui.WindowFlags.NoSavedSettings+imgui.WindowFlags.NoBackground+imgui.WindowFlags.NoInputs)
        pushScope(function()imgui.End()end);studio:drawModal(ui,studioData(),studioCallbacks);endScope()
    end
    local q=workspace.executor.queue
    if q and not ownUi() then
        imgui.SetNextWindowPos(imgui.ImVec2(io.DisplaySize.x/2,28),imgui.Cond.Always,imgui.ImVec2(.5,0))
        imgui.SetNextWindowSize(imgui.ImVec2(math.min(600,io.DisplaySize.x-32),142),imgui.Cond.Always)
        imgui.Begin('Сценарий##pa26-progress',nil,imgui.WindowFlags.NoDecoration+imgui.WindowFlags.NoInputs+imgui.WindowFlags.NoSavedSettings)
        pushScope(function() imgui.End() end)
        text((q.demo and 'ДЕМО · ' or '')..q.plan.binding.name..' · шаг '..q.index..'/'..#q.plan.steps)
        text(workspace.executor.status); text(bindingModel.keyName(workspace.library.settings.cancel_key)..' / Esc — остановить')
        endScope()
    end
    if sceneServices.evidence.active and not ownUi()and not q then sceneServices.assistUi.waiting(studio,ui,sceneServices.evidence:view(),studioClock)end
    while #scopes>depth do endScope() end
    if wasProcedure and not sceneServices.procedureWindows()then studio:flushAutosave(studioCallbacks,true);uiInputReset=true end
    if wasWanted and not sceneServices.showWanted[0]then studio:flushAutosave(studioCallbacks,true)end
    if wasAssist and not sceneServices.showAssist[0]then studio:flushAutosave(studioCallbacks,true)end
    if (wasQuick and not showQuick[0]) or (wasTips and not showTips[0]) or(wasAssist and not sceneServices.showAssist[0])or(wasWanted and not sceneServices.showWanted[0])then uiInputReset=true end
    uiTyping=ownUi() and io.WantTextInput==true
    if not ownUi() and not runtime.wheel then imgui.DisableInput=true end
end
local function safeHudDraw(callback)
    local ok, err = pcall(callback)
    if not ok and not hud.failed then
        hud.failed = true
        hud:stopInteraction()
        alerts.failed=true;alerts:reset('Карточки связи отключены из-за ошибки отрисовки.')
        notifications.failed=true;notifications:reset();radioGuard:reset();weaponWarning:reset()
        if widgetFrame then widgetFrame.HideCursor = true end
        pushLog('Компактный виджет отключён из-за ошибки: ' .. tostring(err))
        recordUiFailure('hud',err)
    end
end

widgetFrame = imgui.OnFrame(function()
    -- No dependency on the settings window, radial wheel or their UI error flag.
    return not shutdown and focused and hud.connected and (hud.settings.visible or alerts:visible() or taser:view().visible or notifications:view().visible or sceneServices.copilot:view().visible) and not hud.failed
end, function() safeHudDraw(beforeUiFrame) end, function()
    safeHudDraw(function()
        local fonts={body=hudFont,heading=hudHeadingFont}
        taser:reserve(imgui,hud,fonts);sceneServices.copilotUi.reserve(sceneServices.copilot,imgui,hud,fonts,hud.equipmentHeight);alerts:measure(imgui,hud,fonts);taser:place(imgui,hud,fonts);sceneServices.copilotUi.place(sceneServices.copilot,imgui,hud,fonts)
        if hud.settings.visible and not alerts.suppressHud then hud:draw(imgui,hudFont,hudHeadingFont) end
        hud:drawNotices(imgui,hudFont,hudHeadingFont)
        alerts:draw(imgui,hud,fonts)
        taser:draw(imgui,hud,fonts)
        sceneServices.copilotUi.drawHud(sceneServices.copilot,imgui)
        notifications:draw(imgui,fonts,noticeAvoid())
    end)
end)
widgetFrame.LockPlayer, widgetFrame.HideCursor = false, true
subscriptions[#subscriptions + 1] = widgetFrame

local workspaceFrame=imgui.OnFrame(function()
    return not shutdown and not uiFailed and focused and not isGamePaused() and (showQuick[0] or showTips[0] or sceneServices.showAssist[0] or sceneServices.showWanted[0] or sceneServices.procedureWindows() or studio:hasModal()or studio.modalVisible or studio.statusInfo~=nil or workspace.executor.queue~=nil or sceneServices.evidence.active~=nil)
end,function() safeDraw(beforeUiFrame) end,function() safeDraw(drawWorkspaceWindows) end)
workspaceFrame.LockPlayer=false; workspaceFrame.HideCursor=true
subscriptions[#subscriptions + 1]=workspaceFrame

sceneServices.mapFrame=imgui.OnFrame(function()
    return not shutdown and focused and hud.connected and workspace.library.map_grid.enabled and not sceneServices.mapAdapter.failed
end,function()
    local ok,err=pcall(function()
        local io=imgui.GetIO();local state=sceneServices.mapState
        if not state then return end
        local settings=workspace.library.map_grid
        local view=sceneServices.mapAdapter:safeView(state,io.DisplaySize.x,io.DisplaySize.y,settings)
        local bulletin=sceneServices.bulletins:view(studioClock,settings)
        if view then sceneServices.mapGrid.draw(imgui,menuSmallFont or hudFont,settings,view,sceneServices.mapGrid.cell(settings,state.x,state.y,state.interior),bulletin and bulletin.targetCell,bulletin and bulletin.targetLabel)end
    end)
    if not ok then
        sceneServices.mapAdapter.failed=true;sceneServices.mapAdapter.status='failed'
        pushLog('Сетка карты отключена: '..tostring(err))
    end
end)
sceneServices.mapFrame.LockPlayer=false;sceneServices.mapFrame.HideCursor=true
subscriptions[#subscriptions+1]=sceneServices.mapFrame


local function cleanup()
    if shutdown then return end
    sceneServices.chatPerf:setEnabled(false)
    pcall(studio.flushAutosave,studio,studioCallbacks,true)
    pcall(knowledge.flush,knowledge)
    pcall(patrolSession.save,patrolSession,true)
    pcall(patrolEvents.save,patrolEvents,true)
    pcall(workspace.operations.interrupt,workspace.operations,'PA завершил работу. Результат команды не установлен.')
    pcall(workspace.operations.save,workspace.operations,true)
    pcall(hud.savePending,hud,optionalRead('getGameTimer')or 0,true)
    shutdown = true
    if sceneServices.chatBridge then pcall(sceneServices.chatBridge.close,sceneServices.chatBridge)end
    pcall(closeForInput,'Скрипт остановлен.')
    if workspace.journal.dirty then pcall(workspace.saveJournal,workspace)end
    pcall(menu.releaseAssets,menu,imgui,false)
    for _,sub in ipairs(subscriptions)do if sub then sub.LockPlayer=false;sub.HideCursor=true;if sub.Unsubscribe then pcall(sub.Unsubscribe,sub)end end end
    pcall(studio.release,studio)
    local availableOk, available = pcall(function()
        return type(isSampAvailable) == 'function' and isSampAvailable() == true
    end)
    if type(sampUnregisterChatCommand) == 'function' and availableOk and available then
        for _, name in ipairs(registered) do pcall(sampUnregisterChatCommand, name) end
        for name in pairs(customRegistered) do pcall(sampUnregisterChatCommand,name) end
    end
    for _,h in ipairs(sceneServices.hooks)do if h.events[h.key]==h.handler then h.events[h.key]=h.previous end end
    sceneServices.hooks={}
    if chatEvents and chatEvents.onServerMessage==chatHandler then chatEvents.onServerMessage=previousChatHandler end
    if chatEvents and chatEvents.onPlayerQuit==quitHandler then chatEvents.onPlayerQuit=previousQuitHandler end
    if chatEvents and chatEvents.onPlayerJoin==joinHandler then chatEvents.onPlayerJoin=previousJoinHandler end
    if chatEvents and chatEvents.onSendChat==sendChatHandler then chatEvents.onSendChat=previousSendChatHandler end
    if chatEvents and chatEvents.onSendCommand==sendCommandHandler then chatEvents.onSendCommand=previousSendCommandHandler end
    if chatEvents and chatEvents.onSendTakeDamage==damageHandler then chatEvents.onSendTakeDamage=previousDamageHandler end
    if chatEvents and chatEvents.onSendBulletSync==bulletHandler then chatEvents.onSendBulletSync=previousBulletHandler end
    if chatEvents and chatEvents.onSendAimSync==aimHandler then chatEvents.onSendAimSync=previousAimHandler end
    for _,hook in ipairs(lifeHooks) do if chatEvents and chatEvents[hook.name]==hook.handler then chatEvents[hook.name]=hook.previous end end
end

sceneServices.performShutdown=function()
    sceneServices.shutdownRequested=nil
    if shutdown then return end
    local ok,why=require('pa26_shutdown').run({
        stop=function()
            cancelManualActions('PA отключается пользователем.');runtime:cancel('PA отключается.');workspace:cancel('PA отключается.')
            workspace.operations:interrupt('PA отключается. Результат незавершённой команды не установлен.')
        end,
        saves={
            {'настройки PA',function()
                studio:flushAutosave(studioCallbacks,true)
                if next(studio.autosaves or{})then return nil,'Закройте сообщение об ошибке и повторите запись изменённых настроек.'end
                return true
            end},
            {'история фиксации',function()
                local e=sceneServices.evidence;if not e.pendingRecord then return true end
                local saved,err=e.env.record(e.pendingRecord);if saved then e.pendingRecord=nil end;return saved,err
            end},
            {'личные карточки базы',function()return knowledge:flush()end},
            {'патруль',function()return patrolSession:save(true)end},
            {'события патруля',function()return patrolEvents:save(true)end},
            {'журнал операций',function()return workspace.operations:save(true)end},
            {'журнал сценариев',function()if workspace.journal.dirty then return workspace:saveJournal()end;return true end},
            {'положение HUD и настройки игры',function()saveSettings(true);return not generalSaveFailed,'Проверьте доступ к INI и корректность настроек.'end},
            {'намерение отключить PA',function()
                if require('pa26_startup').disable(getWorkingDirectory())then return true end
                return nil,'Не удалось подтвердить отключение автоматического восстановления. Проверьте доступ к папке config.'
            end},
        },
        finish=function()
            local message=workspace.library.settings.shutdown_message
            if message and message~=''then report(message,'info')end
            pushLog('Police Assistant отключён пользователем.');cleanup()
        end})
    if ok then sceneServices.shutdownUnload=true else studio:notify(why,'shutdown',false)end
end
sceneServices.manualChatSettings=function()
    local settings=bindingModel.copy(workspace.library.settings)
    settings.local_tag=workspace.library.profile.local_tag
    return settings
end
sceneServices.manual=require('pa26_manual_chat').new({codec=codec,context=function()local s=context();s.blocked=s.inputBlocked;return s end,now=function()return studioClock end,
    epoch=function()return sceneServices.chatEpoch end,interval=function()return cfg.main.interval_ms end,
    settings=function()return workspace.library.settings.manual_chat,workspace.library.rp_text,
        workspace.library.settings.accent_live_input and bindingModel.accentPrefix(workspace.library.profile.accent)or'',
        sceneServices.manualChatSettings(),hud.data.nickname end,
    busy=function()return runtime.queue~=nil or workspace.executor.queue~=nil or workspace.pending~=nil end,
    notice=function(message,result)
        report(message)
        if result and type(result.key)=='string'and result.key:match('^native:')and result.raw~=''and
            type(sampGetChatInputText)=='function'and type(sampSetChatInputText)=='function'then
            local read,current=pcall(sampGetChatInputText)
            if read and current==''then local encoded,wire=pcall(codec.encode,result.raw);if encoded then pcall(sampSetChatInputText,wire)end end
        end
    end,
    send=function(wire)
        local ctx=context()
        if not ctx.session or ctx.focused~=true or ctx.paused~=false or ctx.inputBlocked or ctx.ownWindow or not ctx.alive then return false end
        ownedChatSendDepth=ownedChatSendDepth+1;ownedSendCancelled=false
        local ok=pcall(sampSendChat,wire);ownedChatSendDepth=ownedChatSendDepth-1
        if not ok or ownedSendCancelled then return false end
        metrics.sent=metrics.sent+1;return true
    end})
sceneServices.manualActions=sceneServices.manualActionModule.new({codec=codec,now=function()return studioClock end,
    epoch=function()return sceneServices.chatEpoch end,revision=function()return workspace.libraryRevision end,
    library=function()return workspace.library end,
    state=function()local s=context();s.demo=runtime.demo;s.ped=PLAYER_PED;s.localId=hud.data.id;s.nick=hud.data.nickname;return s end,
    busy=function()return workspace.pending~=nil or workspace.executor.queue~=nil or runtime.queue~=nil or sceneServices.manual.queue~=nil end,
    account=function(head,args)
        if not sceneServices.manualActionModule.targetHeads[head]then return nil end
        local id=tonumber((args or''):match('^(%d+)%s'))or tonumber((args or''):match('^(%d+)$'))
        if not id then return nil end
        return{id=id,name=optionalRead('sampGetPlayerNickname',id),generation=sceneServices.nearby.generations[id]or 0}
    end,
    accountValid=function(a)return not a or optionalRead('sampIsPlayerConnected',a.id)==true and type(a.name)=='string'and
        optionalRead('sampGetPlayerNickname',a.id)==a.name and(sceneServices.nearby.generations[a.id]or 0)==a.generation end,
    guard=function(p)
        if p.head~='cuff'and p.head~='arrest'then return end
        local cp=sceneServices.copilot;local s=cp.state or{};local nearby=sceneServices.colleagues.snapshot
        local pursuing=cp.enteredDangerInPursuit==true and(cp.phase=='Преследование'or cp.phase=='10-66'or cp.phase=='10-57 FOXTROT')
        return require('pa26_colleagues').guard(workspace.library.vehicle.copilot,s.area or hud.data.district,#(nearby.nearbyOfficers or{})+1,pursuing)
    end,
    notice=function(message)studio:notify(message,'commands',false)end,
    showing=function(token)return studio.manualAction and studio.manualAction.token==token end,
    close=function(token)if studio.manualAction and studio.manualAction.token==token then studio.manualAction=nil end end,
    show=function(p)studio.manualAction=p;uiInputReset=true;imgui.DisableInput=false end,
    start=function(plan)return workspace:request({kind='startPlan',plan=plan,returnTo='quick'})end,
    prepare=function(p)
        local model=bindingModel;local binder=require('pa26_binder');local lib=workspace.library
        if p.frisk_mode then lib=model.copy(lib);lib.settings.manual_actions.frisk_mode=p.frisk_mode end
        local cfg=lib.settings.manual_actions;local rule=sceneServices.manualActionModule.rule(lib,p.head)
        local ctx=context();local wire=core.encodeWire(p.raw,codec)
        local noPlan={binding={id=1,name='Ручная /'..p.head,stat='none'},steps={{kind='message',text=p.raw,wire=wire}},lines={p.raw},
            requirements={target=false,closest=false},session=ctx.session,createdAt=studioClock,demo=runtime.demo,has_command=true}
        if p.passThrough then return nil,nil,noPlan end
        local args,why=model.parseArguments(p.args or'');if not args then return nil,why,noPlan end
        local source=rule.prefer_bind and sceneServices.manualActionModule.source(lib,p.head)
        local target
        if p.account then
            local loaded,ped=optionalRead('sampGetCharHandleBySampPlayerId',p.account.id)
            if loaded and ped then target=env.validate({id=p.account.id,ped=ped,name=p.account.name},workspace.cfg.main.max_distance)end
        end
        local function compile(b)
            local req=binder.requirements(b)
            if req.target and not target then return nil,'Игрок из команды сейчас недоступен для персональной отыгровки.'end
            local snapshot,err=workspace:snapshot(b,{target=target});if not snapshot then return nil,err end
            return sceneServices.manualActionModule.plan(lib,p.head,p.raw,model.copy(args),snapshot,b,codec,workspace.library.rp_text)
        end
        local plan,err;if source then plan,err=compile(source)end
        if not plan then local fallback=model.newBinding(1);fallback.name='Ручная /'..p.head;fallback.script=rule.rp;plan,err=compile(fallback)end
        return plan,err,noPlan
    end})
sceneServices.manualText=function(raw,input,owned)
    if type(raw)~='string'then return nil,'Поле чата недоступно.'end
    if owned and raw:sub(1,#owned)==owned then raw=raw:sub(#owned+1)end
    if input and core.validUtf8(raw)then return raw end
    local ok,text=pcall(codec.decode,raw);if not ok or not core.validUtf8(text)then return nil,'Ошибка кодировки ручного чата.'end
    return text
end
sceneServices.offerNativeManual=function(text)
    sceneServices.nativeManualSerial=(sceneServices.nativeManualSerial or 0)+1
    return sceneServices.manual:offer(text,'native:'..tostring(sceneServices.chatEpoch)..':'..sceneServices.nativeManualSerial)
end
sceneServices.checkNativeManual=function(raw,input,owned)
    local text,why=sceneServices.manualText(raw,input,owned);if not text then return nil,why end
    local plan;plan,why=sceneServices.manual:prepare(text)
    return plan,why,text
end
local function prepareNativeChat()
    -- Accent/conversion/splitting are applied by the existing Enter/RPC path.
    -- Never read and rewrite the editing buffer every frame.
    if optionalRead('sampIsChatInputActive')~=true then manualInputPrefix=nil end
end
function onWindowMessage(message, wparam, lparam)
    if shutdown then return end
    -- WM_CHAR/IME text and mouse-selection messages pass straight to the HUD.
    if message~=0x100 and message~=0x101 and message~=0x104 and message~=0x105 and
        message~=0x7 and message~=0x8 and message~=0x1C and message~=0x6 then return end
    local keyboard=message==0x100 or message==0x101 or message==0x104 or message==0x105
    local cefBusy=false
    if keyboard and workspace and sceneServices.chatBridge then
        local settings=workspace.library.settings;local bridge=sceneServices.chatBridge
        if message==0x100 and(wparam==0x75 or wparam==0x54 or wparam==0x0D or wparam==0x1B)then
            local allowed=(wparam==0x75 or wparam==0x54)and settings.cef_chat_support and settings.cef_chat_weapon_guard and bridge.server~=nil and focused and
                not ownUi()and not bridge:busy(studioClock)and optionalRead('sampIsChatInputActive')==false and optionalRead('sampIsDialogActive')==false
            bridge:observeInput(message,wparam,studioClock,allowed)
        end
        cefBusy=bridge:inputBusy(studioClock,settings.cef_chat_grace_ms)
        if settings.cef_chat_support and settings.cef_chat_weapon_guard and sceneServices.chatModule.weaponKey(message,wparam)then
            local held=sceneServices.cefHeldWeaponKeys or{};sceneServices.cefHeldWeaponKeys=held
            if cefBusy or message==0x101 and held[wparam]then
                if type(consumeWindowMessage)=='function'then consumeWindowMessage(true,false)end
                held[wparam]=message==0x100 or nil
            end
        end
    end
    if message==0x100 and sceneServices.manual and sceneServices.manual.queue and(wparam==27 or wparam==workspace.library.settings.cancel_key)then sceneServices.manual:cancel('Отменено пользователем.')end
    if keyboard and not ownUi()and cefBusy and
        (wparam~=0x0D or optionalRead('sampIsChatInputActive')==false)then return end
    confirmationInput:observeMenu(message,wparam,cfg.main.menu_key,lparam)
    if workspace and sceneServices.assistInput and(message==0x100 or message==0x104 or message==0x101 or message==0x105)then
        local shortcut=workspace.library.assist.open_shortcut
        if shortcut and shortcut.key~=0 and wparam==shortcut.key then
            local released=message==0x101 or message==0x105
            local safe=not shutdown and not uiFailed and focused and not uiTyping and not keyRecorder and not hasUiModal()and not context().blocked and optionalRead('isGamePaused')==false and optionalRead('isKeyDown',0x5B)~=true and optionalRead('isKeyDown',0x5C)~=true
            local mods={ctrl=optionalRead('isKeyDown',0x11)==true,alt=optionalRead('isKeyDown',0x12)==true,shift=optionalRead('isKeyDown',0x10)==true}
            if released or safe and mods.ctrl==shortcut.ctrl and mods.alt==shortcut.alt and mods.shift==shortcut.shift then
                sceneServices.assistInput:observeMenu(message,wparam,shortcut.key,lparam)
                if not released then sceneServices.assistConsumed=shortcut.key end
                if sceneServices.assistConsumed==shortcut.key and type(consumeWindowMessage)=='function'then consumeWindowMessage(true,false)end
                if released then sceneServices.assistConsumed=nil end
            end
        end
    end
    if message==0x0100 and wparam==0x0D and optionalRead('sampIsChatInputActive')==true then
        sceneServices.manualSpeechAt=nil;sceneServices.nativeHandledDot=nil;sceneServices.nativeRadioSubmit=nil
        if not shutdown and focused and workspace and hud.connected and not keyRecorder and not hasUiModal()and optionalRead('isGamePaused')==false then sceneServices.manualSpeechAt=studioClock end
    end
    if message==0x0100 and wparam==0x0D and not shutdown and focused and workspace and hud.connected and not keyRecorder and not hasUiModal()and
        optionalRead('sampIsChatInputActive')==true and optionalRead('isGamePaused')==false and type(sampGetChatInputText)=='function'then
        local read,raw=pcall(sampGetChatInputText)
        if read then
            if sceneServices.manual.queue then
                if type(consumeWindowMessage)=='function'then consumeWindowMessage(true,false)end
                report('Предыдущее сообщение ещё отправляется. Новый ввод сохранён.');return
            end
            local plan,why,text=sceneServices.checkNativeManual(raw,true,manualInputPrefix)
            if not plan then
                if type(consumeWindowMessage)=='function'then consumeWindowMessage(true,false)end
                report(why);return
            elseif plan.eligible and #plan.lines>1 then
                if not workspace.chatFiltersAvailable then
                    if type(consumeWindowMessage)=='function'then consumeWindowMessage(true,false)end
                    report('Для переноса нативного чата нужен обработчик SAMP.Lua. Текст сохранён.');return
                end
                sceneServices.nativeManualTicket={text=text,raw=raw,at=studioClock,epoch=sceneServices.chatEpoch}
                return -- Original Enter closes the chat; its outgoing RPC is captured below.
            end
        end
    end
    local prefix=message==0x100 and wparam==0x0D and workspace and workspace.library.settings.accent_live_input and bindingModel.accentPrefix(workspace.library.profile.accent)
    if message==0x0100 and wparam==0x0D and(prefix and prefix~=''or workspace and(workspace.library.settings.chat_dot_commands or workspace.library.settings.manual_radio_prefix))and not shutdown and focused and workspace and hud.connected and not keyRecorder and not hasUiModal()and
        type(sampGetChatInputText)=='function'and type(sampSetChatInputText)=='function'and
        type(sampIsChatInputActive)=='function'and optionalRead('sampIsChatInputActive')==true and optionalRead('isGamePaused')==false then
        local ok,raw=pcall(sampGetChatInputText)
        local prepared,err
        if ok then
            prepared,err=bindingModel.submitSpeech(raw,prefix or'',codec,true,sceneServices.manualChatSettings(),manualInputPrefix)
            if prepared then
                manualInputPrefix=nil
                local utf=raw:find('[\128-\255]')and core.validUtf8(raw)
                local encoded,a,b=pcall(function()return utf and codec.encode(raw)or raw,utf and codec.encode(prepared)or prepared end)
                if encoded then sceneServices.nativeRadioSubmit={raw=a,wire=b,at=studioClock,epoch=sceneServices.chatEpoch,session=connectionKey()}end
            end
        end
        if prepared and prepared~=raw then
            local written,result=pcall(sampSetChatInputText,prepared)
            if not written or result==false then prepared=nil;err='Поле чата не удалось обновить.'end
        end
        if not prepared and(ok or prefix and prefix~='')then
            if type(consumeWindowMessage)=='function'then consumeWindowMessage(true,false)end
            local age=manualSpeechFailureAt and core.elapsed(studioClock,manualSpeechFailureAt)
            if not age or age>=1000 then
                manualSpeechFailureAt=studioClock;report('Сообщение не отправлено: '..tostring(err or'поле ввода недоступно.'))
            end
        else manualSpeechFailureAt=nil
        end
    elseif (message == 0x0100 or message == 0x0104) and
        (wparam == 0x49 or wparam == 0x4A or wparam == 0x4B) then
        if ownUi() and (uiTyping or hasUiModal()) then
            -- The first character after focusing an editor can arrive before
            -- the next ImGui NewFrame. Keep I/J/K in the editor during that gap.
            if type(consumeWindowMessage) == 'function' then consumeWindowMessage(true, false) end
        else
            -- Inventory/server actions receive the original key message.
            closeForInput('Серверная клавиша I/J/K: интерфейс и действие отменены.')
        end
    elseif message == 0x0008 or (message == 0x001C and wparam == 0) or
        (message == 0x0006 and wparam % 65536 == 0) then
        focused = false
        sceneServices.nativePendingCommand=nil;sceneServices.manualSpeechAt=nil;sceneServices.nativeRadioSubmit=nil
        confirmationInput:resetMenu()
        sceneServices.assistInput:resetMenu()
        closeForInput('Фокус игры потерян. Действие отменено.')
    elseif message == 0x0007 or (message == 0x001C and wparam ~= 0) or
        (message == 0x0006 and wparam % 65536 ~= 0) then
        focused = true
    elseif message == 0x0100 and wparam == 0x1B and
        (runtime.wheel or runtime.queue or ownUi() or workspace.executor.queue or workspace.pending) then
        if escDismissed then return end
        if studio:hasWarning()then studio:ackWarning();escDismissed=true
        elseif hasUiModal() then cancelUiModal(); keyRecorder=nil; escDismissed=true
        elseif ownUi() then cancelManualActions('Отменено клавишей Esc.');closePanels();escDismissed=true
        else closeForInput('Отменено клавишей Esc.') end
    end
end

sceneServices.windowHandler=sceneServices.chatPerf:wrap('onWindowMessage',onWindowMessage)
function onWindowMessage(message,wparam,lparam)
    -- No profiler call or CEF work on mouse, selection, character/IME messages.
    if message~=0x100 and message~=0x101 and message~=0x104 and message~=0x105 and message~=0x7 and message~=0x8 and message~=0x1C and message~=0x6 then return end
    return sceneServices.windowHandler(message,wparam,lparam)
end
function onScriptTerminate(script)
    if script == thisScript() then cleanup() end
end

function onD3DDeviceLost()
    closeForInput('Графическое устройство недоступно. Действие отменено.')
    menu:releaseAssets(imgui, true)
end

local requiredApis = {
    'isSampAvailable', 'sampGetGamestate', 'sampGetCurrentServerAddress',
    'sampIsChatInputActive', 'sampIsDialogActive', 'sampIsCursorActive',
    'sampIsLocalPlayerSpawned', 'sampIsPlayerConnected', 'sampGetPlayerNickname',
    'sampGetPlayerIdByCharHandle', 'sampGetCharHandleBySampPlayerId', 'sampRegisterChatCommand',
    'sampSendChat', 'doesCharExist', 'isCharDead', 'isCharOnScreen', 'isCharInAnyCar',
    'getCharPlayerIsTargeting', 'getCharCoordinates', 'getActiveCameraCoordinates',
    'isLineOfSightClear', 'getGameTimer', 'wasKeyPressed', 'isKeyDown', 'isGamePaused',
    'encodeJson','decodeJson',
}

-- This runs directly in MoonLoader's main coroutine. Native UI reads belong to
-- the render callbacks; this function uses only their copied boolean state.
-- Unexpected host errors are reported by MoonLoader and termination cleans up.
local previousSession
sceneServices.queueWantedInput=function(head,args)
    args=tostring(args or '')
    if #args>256 or args:find('[%z\1-\31]')then report('Неверные параметры команды розыска.');return end
    local raw='/'..head..(args~=''and(' '..args)or '')
    local settings=workspace.library.procedures
    local p={head=head,raw=raw,at=optionalRead('getGameTimer'),epoch=sceneServices.chatEpoch,session=connectionKey(),demo=runtime.demo}
    if not settings.wanted_intercept or not caseFormsModule.enabled(settings,'wanted')then
        p.passThrough=true;sceneServices.wantedInput=p;return
    end
    if head=='wanted'then
        if args:match('%S')then report('/wanted открывает общий список без ID. Для выдачи используйте /su ID.');return end
    else
        local id,rest=args:match('^%s*(%d+)%s*(.-)%s*$');id=tonumber(id)
        if not core.validId(id)then report('Использование: /su ID [номер раздела номер подпункта].');return end
        if rest~=''then
            local category,item=rest:match('^(%d+)%s+(%d+)$')
            category,item=tonumber(category),tonumber(item)
            if not category or not item or category<1 or category>13 or item<1 or item>99 then report('После ID нужны номер раздела и номер подпункта. Звёзды не являются аргументом.');return end
            p.reason=string.format('%02d.%02d',category,item)
            if not require('pa26_wanted_catalog').byId[p.reason]then report('Такого подпункта нет в подтверждённом игровом списке.');return end
        end
        -- Account resolution is performed in main(), after the chat closes.
        p.id=id;p.name=optionalRead('sampGetPlayerNickname',id);p.generation=sceneServices.nearby.generations[id]or 0
        if optionalRead('sampIsPlayerConnected',id)~=true or type(p.name)~='string'then report('Игрок с этим ID не подключён.');return end
    end
    sceneServices.wantedInput=p
end
sceneServices.processWantedInput=function(state,now)
    local p=sceneServices.wantedInput;if not p then return end
    local function fresh()
        local age=core.elapsed(now,p.at)
        return age and age<=5000 and p.session==state.session and p.epoch==sceneServices.chatEpoch and p.demo==state.demo
    end
    if not fresh()or not state.alive or not state.focused or state.paused then sceneServices.wantedInput=nil;return end
    if state.blocked or state.typing or state.modal or state.busy then return end
    sceneServices.wantedInput=nil
    if p.passThrough then
        local ok,wire=pcall(codec.encode,p.raw)
        if not ok or not env.send(wire)then report('Команда не отправлена. Повторите её вручную в доступной игровой сцене.')end;return
    end
    studio:requestNavigation(function()
        local age=core.elapsed(optionalRead('getGameTimer'),p.at)
        if not age or age>5000 or connectionKey()~=p.session or sceneServices.chatEpoch~=p.epoch or runtime.demo~=p.demo then
            studio:notify('Команда устарела. Повторите её вручную.','procedures',false);return
        end
        if p.id then
            local t,why=sceneServices.wantedAccounts:select(p.id,p)
            if not t then studio:notify(why,'procedures',false);return end
            if t.name~=p.name or t.generation~=p.generation then studio:notify('ID сменил владельца. Повторите /su для нужного игрока.','procedures',false);return end
            p.target=t
        end
        local kind=p.head=='wanted'and'wanted_list'or'wanted'
        local f,why=caseForms:begin(kind,p.target)
        if not f then studio:notify(why,'procedures',false);return end
        if p.reason then f.reason_id=p.reason end
        if p.ground then
            local h=p.ground
            if not sceneServices.copilot:groundContextValid(h.context,true)then studio:notify('Основание относится к изменившемуся случаю.','procedures',false);return end
            f.article=h.ground.article or'';f.basis=h.ground.basis or'';f.facts=f.basis;f.groundOrigin=bindingModel.copy(h.context)
            if h.ground.game then f.reason_id=h.ground.game end
        end
        studio.caseForm=f;studio.caseStoredForms=studio.caseStoredForms or {};studio.caseStoredForms[f.kind]=f
        caseForms.message=nil
        if studio.statusInfo and studio.statusInfo.key=='procedures'then studio.statusInfo=nil end
        studio.wantedIdentityPage=nil;studio.wantedBasisDetails=nil;studio.wantedPassportEditor=nil;studio.wantedSearch='';studio.cache['wanted:search']=nil
        studioCallbacks.openProcedures(kind)
    end,'открыть помощник розыска')
end
sceneServices.procedureFlow=require('pa26_procedure_flow').new({
 settings=function()return workspace.library.procedures end,codec=codec,now=function()return studioClock end,
 context=function()return alerts.state or{}end,epoch=function()return sceneServices.chatEpoch end,
 generation=function(id)return sceneServices.nearby.generations[id]or 0 end,
 suggest=function(kind)
  return workspace.selectedTarget or sceneServices.copilot.driverLive or(kind=='mark'and sceneServices.wantedAccounts.selected)
 end,
 notice=function(message)studio:notify(message,'procedures',false)end,
 pass=function(raw)
  if sceneServices.manualActions:offer(raw,true)then return end
  local ok,wire=pcall(codec.encode,raw);if not ok or not env.send(wire)then report('Команда не отправлена. Повторите её вручную.')end
 end,
 resolve=function(kind,id,generation)
  if kind=='mark'then return sceneServices.wantedAccounts:select(id,{name=optionalRead('sampGetPlayerNickname',id),generation=generation})end
  local streamed,ped=optionalRead('sampGetCharHandleBySampPlayerId',id)
  local target=streamed==true and inspectPed(ped,nil,cfg.main.max_distance)or nil
  if not target or target.id~=id or(sceneServices.nearby.generations[id]or 0)~=generation then
   return nil,'Для штрафа нужен доступный человек рядом. Пеленгация и /su могут использовать удалённый ID; штраф не получает этого исключения.'
  end
  local old=workspace.selectedTarget
  if not old or old.id~=target.id or old.name~=target.name or old.ped~=target.ped then workspace:selectTarget(target)end
  return target
 end,
 open=function(kind,p,target)
  studio:requestNavigation(function()
   local s=alerts.state or{}
   if s.session~=p.session or s.localId~=p.localId or s.demo~=p.demo or sceneServices.chatEpoch~=p.epoch or
    (core.elapsed(studioClock,p.at)or math.huge)>5000 or target and(sceneServices.nearby.generations[target.id]or 0)~=p.generation then
    studio:notify('Переход устарел. Повторите команду.','procedures',false);return
   end
   studioCallbacks.openProcedures(kind)
   if not target then studio.caseForm=nil;return end
   local f,why=caseForms:begin(kind,target)
   if not f then studio:notify(why,'procedures',false);return end
   if p.amount then f.amount=p.amount end;if p.basis then f.basis=p.basis end
   local inherited=p.ground or(not p.basis and sceneServices.copilot.lastStopReason)
   if kind=='fine'and inherited and sceneServices.copilot:groundContextValid(inherited.context,true)and
    inherited.context.groundTarget.id==target.id and inherited.context.groundTarget.name==target.name then
    local g=inherited.ground
    f.article=g.article or'';f.part='';f.basis=g.basis or'';f.groundOrigin=bindingModel.copy(inherited.context);f.fromStopReason=true
    if g.sanction_id then local row=sceneServices.getSanctions().byId[g.sanction_id]
     if row and row.hash==g.sanction_hash then require('pa26_sanctions').select(f,row,g.sanction_branch)end
    end
   end
   studio.caseForm=f;studio.caseStoredForms=studio.caseStoredForms or{};studio.caseStoredForms[kind]=f
  end,'открыть '..(kind=='fine'and'штраф'or'пеленгацию'))
 end,
})
sceneServices.queueProcedureInput=function(head,args,ground)
 local ok,why=sceneServices.procedureFlow:capture(head,args,ground);if not ok then studio:notify(why,'procedures',false)end
end
sceneServices.processProcedureInput=function(s,now)sceneServices.procedureFlow:tick(s,now)end
sceneServices.processGroundInput=function()
 local c=sceneServices.copilot;local p=sceneServices.groundInput or c.groundRequest
 sceneServices.groundInput=nil;c.groundRequest=nil
 if p then
  if c:groundContextValid(p,true)then
   studio:requestNavigation(function()
    if not c:groundContextValid(p,true)then studio:notify('Случай изменился.','vehicle',false);return end
    hideWorkspaceUi();sceneServices.showGround[0]=true;imgui.DisableInput=false;uiInputReset=true
    local key=table.concat({p.session or'',p.life,p.ped,p.groundTarget.id,p.groundTarget.name,p.groundTarget.generation or 0,
        p.groundCar and p.groundCar.handle or'foot',p.groundCar and p.groundCar.id or''},':')
    if studio.groundDraftKey~=key then studio.groundSpeechDrafts={};studio.groundDraftKey=key end
    studio.groundForm={request=bindingModel.copy(p),cfg=bindingModel.copy(p.cfg),speechDrafts=studio.groundSpeechDrafts};studio.groundPage='form';studio.groundSearch='';studio.groundListPage=1
   end,'выбрать основание для этого человека')
  else studio:notify('Водитель или случай изменились. Повторите выбор причины.','vehicle',false)end
 end
 local h=c.groundHandoff;c.groundHandoff=nil
 if h and c:groundContextValid(h.context,true)then
  local id=h.context.groundTarget.id
  if h.kind=='fine'then sceneServices.queueProcedureInput('ticket',tostring(id),h)
  else
   sceneServices.queueWantedInput('su',tostring(id))
   if sceneServices.wantedInput then sceneServices.wantedInput.ground=h end
  end
 end
end
local function syncBindingCommands()
    if not workspace.commandDirty then return end
    workspace.commandDirty=false
    for name in pairs(customRegistered) do
        if type(sampUnregisterChatCommand)=='function' then pcall(sampUnregisterChatCommand,name) end
        customRegistered[name]=nil;sceneServices.localCommands[name]=nil
    end
    for _,b in ipairs(workspace.library.bindings)do if b.enabled then
      for _,name in ipairs(bindingModel.bindingCommands(b))do if name~='su'and name~='wanted'then
        local id=b.id
        local handler=function(arguments)
            local value=arguments or ''; if not core.validUtf8(value) then local decoded,utf=pcall(codec.decode,value); value=decoded and utf or '' end
            local args,err=bindingModel.parseArguments(value); if not args then report(err); return end
            local current=bindingModel.find(workspace.library,id)
            if current then for i,p in ipairs(current.parameters) do args[p.name]=args['param'..i] or '' end end
            workspace:request({kind='prepare',id=id,args=args,start=true,returnTo='quick'})
        end
        local ok,result=pcall(sampRegisterChatCommand,name,handler)
        if ok and result~=false then customRegistered[name]=true;sceneServices.localCommands[name]=handler
        else local message='Команда /'..name..' занята. Выберите другое имя в редакторе; бинд доступен из меню и по клавише.';pushLog(message);studio:passiveWarning('alias:'..name,message,'binds')end
      end end
    end end
    for name,handler in pairs(sceneServices.manualLocalCommands or{})do if sceneServices.localCommands[name]==handler then sceneServices.localCommands[name]=nil end end
    sceneServices.manualLocalCommands={}
    local manualCfg=workspace.library.settings.manual_actions or sceneServices.manualActionModule.defaults()
    if manualCfg.enabled then for name,row in pairs(manualCfg.rules)do if row.enabled and not sceneServices.localCommands[name]then
        local head=name;local handler=function(args,raw)sceneServices.manualActions:offer(raw or('/'..head..(args~=''and(' '..args)or'')),true)end
        sceneServices.localCommands[name]=handler;sceneServices.manualLocalCommands[name]=handler
    end end end
    sceneServices.chatCommandsRevision=(sceneServices.chatCommandsRevision or 0)+1
end
-- Both chat backends use the same evidence, confirmation and filtering rules.
sceneServices.observeMessage=function(text,source,now)
    if type(text)~='string'or not core.validUtf8(text)then return end
    local visible=text:gsub('{%x%x%x%x%x%x}',''):match('^%s*(.-)%s*$')
    local fresh=not sceneServices.chatBridge or sceneServices.chatBridge:observe(visible,source,now)
    if fresh then
        identity:serverMessage(visible);taser:serverMessage(visible);sceneServices.colleagues:observe(visible)
        if sceneServices.copilot then sceneServices.copilot:observeWindowReply(visible)end
        if sceneServices.bulletins then sceneServices.bulletins:observe(visible,now)end
    end
    for _,filter in ipairs(workspace.library.filters)do if filter.enabled and visible:sub(1,#filter.prefix)==filter.prefix then return false end end
    if fresh then workspace.operations:onChat(text)end
end
sceneServices.observeCommand=function(line)
    if sceneServices.copilot then sceneServices.copilot:observeManualCommand(line,'outgoing')end
    sceneServices.colleagues:command(line,studioClock)
    taser:command(line,workspace.executor.queue and workspace.executor.queue.plan.manualCommand~=nil);patrolEvents:command(line,'Введено вручную · попытка',nil)
    workspace.operations:observe(line,'manual',nil,'observed')
end
-- A Chat RPC cannot be turned into a Command RPC by returning slash text.
-- Cancel it first, then dispatch once from the next safe game frame.
sceneServices.dispatchNativeCommand=function(now)
    local item=sceneServices.nativePendingCommand;if not item then return end
    local age=core.elapsed(now,item.at)
    if not age or age>1000 or item.epoch~=sceneServices.chatEpoch or item.session~=connectionKey()or
        not workspace.library.settings.chat_dot_commands then sceneServices.nativePendingCommand=nil;return end
    if not focused or optionalRead('isGamePaused')~=false or ownUi()or keyRecorder or hasUiModal()then sceneServices.nativePendingCommand=nil;return end
    if context().blocked then return end
    sceneServices.nativePendingCommand=nil
    local name,args=item.wire:match('^/([A-Za-z][A-Za-z0-9_]*)(.*)$')
    local handler=name and sceneServices.localCommands[name:lower()]
    if handler then
        local ok=pcall(handler,(args or''):gsub('^ +',''))
        if not ok then report('Команда PA не выполнена. Повторите её вручную.')end
    elseif name and name:lower():match('^pa26')then report('В PA нет такой команды. Проверьте её название.')
    elseif type(sampSendChat)=='function'then
        local ok=pcall(sampSendChat,item.wire)
        if not ok then report('Не удалось передать команду чату. Повторите её вручную.')end
    end
end
local function connectChatFilters()
    local ok,events=pcall(require,'samp.events')
    workspace.chatFiltersAvailable=ok and type(events)=='table'
    if not workspace.chatFiltersAvailable then return end
    chatEvents=events; previousChatHandler=events.onServerMessage
    previousSendChatHandler=events.onSendChat
    sendChatHandler=function(raw)
        local previous
        if type(previousSendChatHandler)=='function' then previous=previousSendChatHandler(raw); if previous==false then
            if ownedChatSendDepth>0 then ownedSendCancelled=true end;return false end end
        if ownedChatSendDepth>0 then
            if type(previous)=='table'and previous[1]~=raw then
                ownedSendCancelled=true;pushLog('Отправка PA остановлена: другой обработчик изменил подготовленный текст.');return false
            end
            return previous
        end
        local message=type(previous)=='table' and previous[1] or raw
        local age=sceneServices.manualSpeechAt and core.elapsed(studioClock,sceneServices.manualSpeechAt)
        local handled=sceneServices.nativeHandledDot
        if not age and handled and handled.raw==message and handled.epoch==sceneServices.chatEpoch and(core.elapsed(studioClock,handled.at)or math.huge)<=1000 then return false end
        if optionalRead('sampIsChatInputActive')~=true and(not age or age>1000)then return previous end
        local prefix=workspace.library.settings.accent_live_input and bindingModel.accentPrefix(workspace.library.profile.accent)
        if type(message)~='string'or message:match('^%s*/')or message:match('^%s*$')then return previous end
        local settings=sceneServices.manualChatSettings()
        -- Only an actual Enter authorizes converting a fallback Chat RPC.
        settings.chat_dot_commands=settings.chat_dot_commands and age~=nil and age<=1000 and type(raw)=='string'and raw:sub(1,1)=='.'
        local plan,why,text=sceneServices.checkNativeManual(message,false)
        if not plan then report(why);return false end
        if plan.eligible and #plan.lines>1 then sceneServices.offerNativeManual(text);return false end
        local wire,err,converted=bindingModel.submitSpeech(message,prefix or'',codec,false,settings)
        if not wire then
            local notice='[Police Assistant] Сообщение не отправлено: '..(err or 'ошибка кодировки.')
            pushLog(notice)
            if type(sampAddChatMessage)=='function' then local ok,encoded=pcall(codec.encode,notice); if ok then pcall(sampAddChatMessage,encoded,-1) end end
            return false
        end
        if converted then
            sceneServices.manualSpeechAt=nil
            sceneServices.nativeHandledDot={raw=message,at=studioClock,epoch=sceneServices.chatEpoch}
            if sceneServices.nativePendingCommand then report('Предыдущая команда ещё отправляется. Повторите ввод.');return false end
            sceneServices.nativePendingCommand={wire=wire,at=studioClock,epoch=sceneServices.chatEpoch,session=connectionKey()}
            return false
        end
        if wire==message then return previous end
        return {wire}
    end
    events.onSendChat=sendChatHandler
    previousSendCommandHandler=events.onSendCommand
    sendCommandHandler=function(raw)
        local previous
        if type(previousSendCommandHandler)=='function' then
            previous=previousSendCommandHandler(raw)
            if previous==false then
                sceneServices.nativeRadioSubmit=nil
                if ownedChatSendDepth>0 then ownedSendCancelled=true end;return false
            end
        end
        if ownedChatSendDepth>0 and type(previous)=='table'and previous[1]~=raw then
            ownedSendCancelled=true;pushLog('Отправка PA остановлена: другой обработчик изменил подготовленную команду.');return false
        end
        if ownedChatSendDepth==0 then
            local actual=type(previous)=='table'and previous[1]or raw
            if type(actual)=='string'then
                local aliasHead,aliasArgs=actual:match('^/([A-Za-z][A-Za-z0-9_]*)%s*(.-)%s*$')
                aliasHead=aliasHead and aliasHead:lower()
                if aliasHead and customRegistered[aliasHead]and sceneServices.localCommands[aliasHead]then sceneServices.localCommands[aliasHead](aliasArgs);return false end
                local ticket=sceneServices.nativeRadioSubmit
                local age=ticket and core.elapsed(studioClock,ticket.at)
                local manual=ticket and age and age<=1000 and ticket.epoch==sceneServices.chatEpoch and ticket.session==connectionKey()and
                    (raw==ticket.raw or raw==ticket.wire)
                if manual then sceneServices.nativeRadioSubmit=nil end
                -- Some clients invoke the RPC before the window-message hook.
                -- Match the exact active field; other scripts' /r stays exact.
                if not manual and optionalRead('sampIsChatInputActive')==true and type(sampGetChatInputText)=='function'then
                    local read,input=pcall(sampGetChatInputText)
                    if read then
                        if input==raw then manual=true
                        elseif type(input)=='string'and core.validUtf8(input)then
                            local encoded,wire=pcall(codec.encode,input);manual=encoded and wire==raw
                        end
                    end
                end
                local captured=sceneServices.nativeManualTicket
                if captured and captured.epoch==sceneServices.chatEpoch and(core.elapsed(studioClock,captured.at)or math.huge)<=1000 then
                    local plan,why,text=sceneServices.checkNativeManual(actual,false)
                    if not plan then report(why);return false end
                    if plan.eligible and #plan.lines>1 and(text==captured.text or actual==captured.raw)then sceneServices.nativeManualTicket=nil;sceneServices.offerNativeManual(text);return false end
                end
                manual=manual and focused and not shutdown and optionalRead('isGamePaused')==false
                if manual then
                    local decoded,line=pcall(codec.decode,actual)
                    local head,args;if decoded then head,args=line:match('^/([A-Za-z][A-Za-z0-9_]*)%s*(.-)%s*$')end
                    head=head and head:lower()
                    if head and customRegistered[head]and sceneServices.localCommands[head]then sceneServices.localCommands[head](args);return false end
                    if decoded and sceneServices.manualActions:offer(line)then return false end
                    local plan,why,text=sceneServices.checkNativeManual(actual,false)
                    if not plan then report(why);return false end
                    if plan.eligible and #plan.lines>1 then sceneServices.offerNativeManual(text);return false end
                    local prepared,err=bindingModel.submitSpeech(actual,'',codec,false,sceneServices.manualChatSettings())
                    if not prepared then report('Доклад не отправлен: '..tostring(err));return false end
                    if prepared~=actual then actual=prepared;previous={prepared}end
                end
                local ok,line=pcall(codec.decode,actual)
                if ok then sceneServices.observeCommand(line)end
            end
        else
            local actual=type(previous)=='table'and previous[1]or raw
            local ok,line=pcall(codec.decode,actual)
            workspace.operationLineOverride=ok and line or false
            if ok then taser:command(line,workspace.executor.queue and workspace.executor.queue.plan.manualCommand~=nil)end
        end
        return previous
    end
    events.onSendCommand=sendCommandHandler
    previousDamageHandler=events.onSendTakeDamage
    damageHandler=function(id,amount,weapon,bodypart)
        local previous
        if type(previousDamageHandler)=='function' then previous=previousDamageHandler(id,amount,weapon,bodypart);if previous==false then return false end end
        alerts:takeDamage(id,amount,weapon,bodypart)
        if core.finite(amount)and amount>0 then sceneServices.copilot:damage(id,weapon,studioClock);taser:damage(weapon)end
        return previous
    end
    events.onSendTakeDamage=damageHandler
    previousBulletHandler=events.onSendBulletSync
    bulletHandler=function(data)
        local previous
        if type(previousBulletHandler)=='function' then previous=previousBulletHandler(data);if previous==false then return false end end
        local observed=type(previous)=='table' and previous[1] or data
        taser:bullet(observed)
        return previous
    end
    events.onSendBulletSync=bulletHandler
    previousAimHandler=events.onSendAimSync
    aimHandler=function(data)
        local previous
        if type(previousAimHandler)=='function' then previous=previousAimHandler(data);if previous==false then return false end end
        local observed=type(previous)=='table'and previous[1]or data
        weaponWarning:observeAim(observed)
        local ok,mode=pcall(function()return tonumber(observed.camMode)end)
        if ok and core.finite(mode)and mode%1==0 and mode>=0 and mode<=255 then sceneServices.aimSample={mode=mode,at=studioClock,session=connectionKey(),ped=PLAYER_PED}end
        return previous
    end
    events.onSendAimSync=aimHandler
    sceneServices.invalidateLocalScene=function(reason,respawn)
            sceneServices.chatEpoch=sceneServices.chatEpoch+1
            sceneServices.nearby:reset()
            sceneServices.colleagues:reset();sceneServices.bulletins:clear();sceneServices.copilot:reset('Подключение или жизнь изменились.')
            if sceneServices.chatBridge then sceneServices.chatBridge.pending=nil;sceneServices.chatBridge.seen={}end
            alerts:invalidateLife()
            if respawn then patrolSession:interrupt(reason)else patrolSession:cancelQueued(reason)end
            patrolEvents:reset('Жизнь или подключение изменились.')
            identity:clear('Жизнь или подключение изменились. IC-сведения удалены.')
            caseForms:reset('Жизнь или подключение изменились. Процедура отменена.')
            workspace.operations:interrupt('Жизнь или подключение изменились. Результат команды не установлен.')
            patrol:reset();weapons:reset();taser:reset();radioGuard:reset();weaponWarning:reset();notifications:reset()
            runtime:cancel('Персонаж или подключение изменились. Колесо закрыто.')
            workspace:cancel('Персонаж или подключение изменились. Сценарий остановлен.')
            pendingWheelClick=nil
    end
    for _,name in ipairs({'onInitGame','onConnectionClosed','onConnectionLost'})do
        local hook={name=name,previous=events[name]}
        hook.handler=function(...)
            local result;if type(hook.previous)=='function'then result=hook.previous(...);if result==false then return false end end
            sceneServices.localLife:reset();sceneServices.invalidateLocalScene('Подключение изменилось.',false)
            return result
        end
        events[name]=hook.handler;lifeHooks[#lifeHooks+1]=hook
    end
    -- Existing SAMP.Lua mappings were checked in the installed events.lua.
    -- Observe requests; only main() may confirm a changed world scene.
    for _,row in ipairs({{'onSendSpawn','spawn_requested'}, {'onSendDeathNotification','death_reported'},
        {'onRequestSpawnResponse','spawn_approved',1},{'onSetSpawnInfo','spawn_info',4},
        {'onSetPlayerPos','teleport',1},{'onSetPlayerPosFindZ','teleport',1}})do
        local hook={name=row[1],previous=events[row[1]],kind=row[2],index=row[3]}
        hook.handler=function(...)
            local result;if type(hook.previous)=='function'then result=hook.previous(...);if result==false then return false end end
            local args=type(result)=='table'and result or{...}
            sceneServices.localLife:observe(hook.kind,hook.index and args[hook.index]or nil)
            if hook.kind=='spawn_requested'then
                if alerts.pending then alerts:decide(false)end
                sceneServices.nearby:reset()
                closeForInput('Запрошен спавн. Прежние команды не повторяются.')
            end
            return result
        end
        events[hook.name]=hook.handler;lifeHooks[#lifeHooks+1]=hook
    end
    previousQuitHandler,previousJoinHandler=events.onPlayerQuit,events.onPlayerJoin
    quitHandler=function(id,reason)
        workspace.targets:quit(id)
        sceneServices.nearby:invalidate(id)
        sceneServices.colleagues:invalidate(id)
        patrolSession:playerChanged(id)
        identity:playerChanged(id)
        if type(previousQuitHandler)=='function' then return previousQuitHandler(id,reason) end
    end
    joinHandler=function(id,...)
        workspace.targets:join(id)
        sceneServices.nearby:invalidate(id)
        sceneServices.colleagues:invalidate(id)
        patrolSession:playerChanged(id)
        identity:playerChanged(id)
        if type(previousJoinHandler)=='function' then return previousJoinHandler(id,...) end
    end
    events.onPlayerQuit,events.onPlayerJoin=quitHandler,joinHandler
    chatHandler=function(color,raw)
        local previous
        if type(previousChatHandler)=='function' then previous=previousChatHandler(color,raw); if previous==false then return false end end
        if type(previous)=='table'then raw=previous[2]end
        if type(raw)~='string' then return previous end
        local active=false; for _,filter in ipairs(workspace.library.filters) do if filter.enabled then active=true; break end end
        if not active and not workspace.operations:capturesChat()and not workspace.library.identity.passport_chat and workspace.library.taser.activation~='command'and
            not workspace.library.vehicle.copilot.window_offer and not workspace.library.vehicle.copilot.stolen_enabled then return previous end
        local decoded,text=pcall(codec.decode,raw); if not decoded or not core.validUtf8(text) then return previous end
        if sceneServices.observeMessage(text,'native',studioClock)==false then return false end
        return previous
    end
    events.onServerMessage=chatHandler
    for _,name in ipairs({'onVehicleStreamIn','onVehicleStreamOut'})do
        local old=events[name]
        local handler=function(id,...)local result;if type(old)=='function'then result=old(id,...);if result==false then return false end end;sceneServices.vehicle:invalidate(id,name);return result end
        events[name]=handler;sceneServices.hooks[#sceneServices.hooks+1]={events=events,key=name,handler=handler,previous=old}
    end
end
function sceneServices.menuTrace(pressed,source,ctx)
    if pressed then pushLog('Клавиша меню: '..(showWindow[0]and'открыто'or'закрыто')..' ('..tostring(source)..').')
    elseif source=='blocked'then pushLog('Клавиша меню заблокирована: chat='..tostring(ctx.chatActive)..', dialog='..tostring(ctx.dialogActive)..', input='..tostring(ctx.blocked)..'.')end
end
local function updateGame()
    bindingKeyCaptured=keyRecorder~=nil
    local now = getGameTimer()
    studioClock=now
    if sceneServices.patrolUiRecovery then
        local p=sceneServices.patrolUiRecovery;sceneServices.patrolUiRecovery=nil;patrolSession:recoverUi(p.active)
    end
    if sceneServices.chatBridge then sceneServices.chatBridge:tick(now)end
    local ctx = context()
    do
        local ped=localPedAvailable()and PLAYER_PED or nil
        local x,y,z;if ped then x,y,z=optionalRead('getCharCoordinates',ped)end
        local found,id;if ped then found,id=optionalRead('sampGetPlayerIdByCharHandle',ped)end
        local nick=found==true and core.validId(id)and optionalRead('sampGetPlayerNickname',id)or nil
        sceneServices.localLife:tick({session=ctx.session,local_nick=nick or'',ped=ped,alive=ctx.nativeAlive,
            spawned=optionalRead('sampIsLocalPlayerSpawned'),health=ped and optionalRead('getCharHealth',ped),
            interior=ped and optionalRead('getCharActiveInterior',ped),x=x,y=y,z=z},now)
        local life=sceneServices.localLife:view()
        if life.confirmed and sceneServices.invalidateLocalScene then sceneServices.invalidateLocalScene(life.reason,true)end
        ctx.incapacitated=life.incapacitated;ctx.alive=ctx.nativeAlive or life.sceneAlive
        ctx.blocked=ctx.inputBlocked or life.incapacitated or life.transitioning
        ctx.respawnConfirmed=life.confirmed;ctx.respawnEpoch=life.epoch
    end
    sceneServices.citySession=ctx.session
    if sceneServices.weaponSession~=ctx.session or sceneServices.weaponPed~=PLAYER_PED or not ctx.alive or not ctx.focused then
        sceneServices.lastSafeWeapon=nil;sceneServices.cefHeldWeaponKeys={}
        if sceneServices.chatBridge then sceneServices.chatBridge.openGraceAt=nil end
    end
    sceneServices.weaponSession=ctx.session;sceneServices.weaponPed=PLAYER_PED
    if ctx.alive and ctx.focused and not ctx.paused then
        local current=optionalRead('getCurrentCharWeapon',PLAYER_PED)
        local input=ctx.chatActive or sceneServices.chatBridge and sceneServices.chatBridge:inputBusy(now,workspace.library.settings.cef_chat_grace_ms)
        if input and workspace.library.settings.cef_chat_weapon_lock then
            local previous=sceneServices.lastSafeWeapon
            if core.finite(previous)and core.finite(current)and current~=previous and type(setCurrentCharWeapon)=='function'and
                (previous==0 or optionalRead('hasCharGotWeapon',PLAYER_PED,previous)~=false)then optionalRead('setCurrentCharWeapon',PLAYER_PED,previous)end
        elseif not ctx.blocked and core.finite(current)then sceneServices.lastSafeWeapon=current end
    end
    knowledge:tick()
    knowledgeUi:tick(ctx.session,now,showWindow[0]and menu.section=='knowledge')
    sceneServices.authorPresets:tick()
    if sceneServices.authorPresets.applied then
        -- Applying a preset closes the old pages. The acknowledgement must keep
        -- receiving input even while all gameplay controllers wait for reload.
        widgetCursor=false;hud:stopInteraction()
        local interactive=not shutdown and not uiFailed and focused and not ctx.paused and not ctx.blocked and studio:hasWarning()
        workspaceFrame.HideCursor=not interactive
        imgui.DisableInput=not interactive
        return
    end
    studio:flushAutosave(studioCallbacks)
    sceneServices.updater:tick()
    prepareNativeChat()
    hud:refresh(ctx.session, now)
    sceneServices.mapState,sceneServices.mapValues=sceneServices.mapSample()
    local area=sceneServices.mapState.interior
    local previousArea=sceneServices.targetArea
    if previousArea and previousArea.session==ctx.session and previousArea.ped==PLAYER_PED and previousArea.area~=area then
        -- Preserve the person, but never continue an old action or RMB gesture
        -- across a streamed interior boundary. Revalidate before fresh actions.
        if workspace.library.settings.keep_target_on_interior_change then workspace.targets:sceneChanged()
        else workspace:clearTarget('interior')end
        sceneServices.nearby:reset()
            sceneServices.colleagues:reset();sceneServices.bulletins:clear();sceneServices.copilot:reset('Подключение или жизнь изменились.')
        if sceneServices.aimPicker then sceneServices.aimPicker:reset()end
    end
    sceneServices.targetArea=ctx.session and core.finite(area)and{session=ctx.session,ped=PLAYER_PED,area=area}or nil

    sceneServices.nearbyState=bindingModel.copy(ctx)
    sceneServices.nearbyState.ped=localPedAvailable()and PLAYER_PED or nil
    sceneServices.nearbyState.interior=sceneServices.mapState.interior
    sceneServices.nearbyState.demo=runtime.demo
    sceneServices.nearbyState.nearbyOpen=showQuick[0]or showWindow[0]and(menu.section=='binds'or menu.section=='addons')
    sceneServices.nearbyState.modal=hasUiModal()or keyRecorder~=nil or runtime.wheel~=nil or workspace.executor.queue~=nil
    sceneServices.nearbyState.typing=uiTyping
    sceneServices.nearby:tick(sceneServices.nearbyState,now)
    hud.data.district=sceneServices.mapState.area or '—'
    hud.mapSquare=workspace.library.map_grid.enabled and workspace.library.map_grid.hud and sceneServices.mapValues.map_square or nil
    workspace:refreshTarget()
    hud.target=workspace.targets:view()
    if ctx.session ~= previousSession then
        sceneServices.chatEpoch=sceneServices.chatEpoch+1
        if sceneServices.chatBridge then sceneServices.chatBridge.seen={};sceneServices.chatBridge.pending=nil end
        sceneServices.manualSpeechAt=nil
        sceneServices.nativePendingCommand=nil
        closeForInput('Подключение изменилось. Действие отменено.')
        autoOpenForSession = cfg.main.show_on_connect and ctx.session or nil
        previousSession = ctx.session
        if ctx.session then metrics.connections = metrics.connections + 1 end
    end
    -- Server login dialogs and its cursor keep priority during connection.
    if ctx.paused or(ctx.inputBlocked and(not workspace.pending or ctx.chatActive or ctx.dialogActive))then closeForInput('Открыт серверный ввод. Действие отменено.', true) end
    if autoOpenForSession == ctx.session and ctx.session and focused and not ctx.paused and
        not ctx.blocked and ctx.alive and not runtime.wheel and not runtime.queue and not workspace.executor.queue and not workspace.pending then
        showWindow[0] = true
        autoOpenForSession = nil
    end
    runtime:refresh() -- safety checks precede hotkeys and queue advancement
    sceneServices.aimPicker:tick(ctx,now,workspace.library.settings,ownUi()or keyRecorder or hasUiModal()or hud.failed or hud.editing or hud.drag or
        widgetCursor or runtime.wheel or runtime.queue or workspace.pending or workspace.executor.queue)
    hud.target=workspace.targets:view()
    local alertState=bindingModel.copy(ctx)
    alertState.rpText=workspace.library.rp_text;alertState.my_nick=hud.data.nickname;alertState.sendIntervalMs=cfg.main.interval_ms
    alertState.ped=localPedAvailable() and PLAYER_PED or nil;alertState.localId=hud.data.id;alertState.demo=runtime.demo
    alertState.health=alertState.ped and optionalRead('getCharHealth',PLAYER_PED) or nil
    alertState.weapon=alertState.ped and optionalRead('getCurrentCharWeapon',PLAYER_PED) or nil
    alertState.ownUi=ownUi()
    alertState.inVehicle=alertState.ped and optionalRead('isCharInAnyCar',PLAYER_PED)
    if alertState.ped and workspace.library.weapon_warning.enabled and workspace.library.weapon_warning.trigger=='aim' then
        alertState.aimControl=optionalRead('isButtonPressed',0,6)
        local aimed,ped=optionalRead('getCharPlayerIsTargeting',PLAYER_HANDLE)
        if aimed==true and core.finite(ped) and ped~=PLAYER_PED and optionalRead('doesCharExist',ped)==true then
            local found,id=optionalRead('sampGetPlayerIdByCharHandle',ped)
            alertState.aimedAtPlayer=found==true and core.validId(id)
        end
    end
    alertState.onDuty=workspace.library.alerts.on_duty;alertState.radioEnabled=workspace.library.alerts.enabled
    alertState.wheel=runtime.wheel~=nil
    alertState.draggingHud=hud.drag~=nil;alertState.mouseAllowed=ownUi() or hud.editing
    alertState.busy=(workspace.executor.queue and tostring(workspace.executor.queue)) or
        (workspace.pending and tostring(workspace.pending)) or (studio.confirmPlan and tostring(studio.confirmPlan)) or
        (runtime.queue and tostring(runtime.queue)) or nil
    local outgoing=workspace.executor.queue and workspace.executor.queue.plan or workspace.pending and workspace.pending.plan
    alertState.inReport=outgoing and outgoing.alert and outgoing.alert.kind~='police' and outgoing.alert.kind~='prison' or false
    alertState.area=sceneServices.mapState.area
    alertState.gender=workspace.library.profile.gender
    alertState.radioText={split_enabled=workspace.library.radio_guard.split_enabled,continuation=workspace.library.radio_guard.continuation,max_lines=workspace.library.radio_guard.max_lines}
    for _,key in ipairs({'local_tag','prison_tag','global_tag','callsign','city','department','rank'}) do alertState[key]=workspace.library.profile[key] end
    alertState.city=sceneServices.mapValues.city or(workspace.library.profile.city~=''and workspace.library.profile.city or nil)
    alertState.direction=workspace.library.vehicle.direction_enabled and(sceneServices.vehicle.lastDirectionValue or'')or workspace.library.vehicle.manual_direction
    alertState.directionKnown=alertState.direction~=''
    alertState.map_grid=workspace.library.map_grid
    alertState.map_square=sceneServices.mapValues and sceneServices.mapValues.map_square
    alertState.square=sceneServices.mapValues and sceneServices.mapValues.square or nil
    alertState.location=sceneServices.mapGrid.location(alertState)
    alertState.my_name=workspace.library.profile.name~='' and workspace.library.profile.name or
        (hud.data.nickname and hud.data.nickname:gsub('_',' ') or '')
    alertState.post=workspace.library.alerts.patrol.post
    alertState.local_nick=hud.data.nickname or ''
    alertState.accent=workspace.library.profile.accent
    local selected=workspace.selectedTarget
    alertState.targetKey=selected and table.concat({tostring(selected.id),tostring(selected.ped),selected.name or ''},':')or 'unselected'
    alertState.modal=hasUiModal()
    local shortcuts={};for _,row in ipairs(bindingModel.featureKeys)do shortcuts[#shortcuts+1]=workspace.library[row[1]][row[2]]end
    shortcuts[#shortcuts+1]={key=cfg.main.menu_key}
    shortcuts[#shortcuts+1]={key=0x1B};shortcuts[#shortcuts+1]={key=workspace.library.settings.cancel_key}
    local physicalKeys=focused and confirmationInput:read(shortcuts)or nil
    local physicalAbort=confirmationInput:poll({{id='escape-action',shortcut={key=0x1B,ctrl=false,alt=false,shift=false}}},
        focused and not ctx.paused and not ctx.blocked and not keyRecorder,physicalKeys)
    local escapePressed=wasKeyPressed(0x1B)or physicalAbort~=nil
    local physicalCancel=confirmationInput:poll({{id='cancel-action',shortcut={key=workspace.library.settings.cancel_key,ctrl=false,alt=false,shift=false}}},
        focused and not ctx.paused and not ctx.blocked and not keyRecorder and not(ownUi()and(uiTyping or hasUiModal())),physicalKeys)
    local menuAllowed=focused and not ctx.paused and not ctx.menuBlocked and not keyRecorder and not hasUiModal()and not hud.editing and not hud.drag
    local menuPressed,menuSource=confirmationInput:menuPressed(cfg.main.menu_key,menuAllowed,physicalKeys,wasKeyPressed(cfg.main.menu_key))
    -- Function keys close PA even while an editor has native keyboard capture.
    if menuPressed then toggleWindow()end
    sceneServices.menuTrace(menuPressed,menuSource,ctx)
    do
        local shortcut=workspace.library.assist.open_shortcut
        local allowed=shortcut.key~=0 and focused and not ctx.paused and not ctx.blocked and not uiTyping and not keyRecorder and not hasUiModal()and not hud.drag and not hud.editing
        local assistKeys=physicalKeys or{ctrl=isKeyDown(0x11),alt=isKeyDown(0x12),shift=isKeyDown(0x10),super=isKeyDown(0x5B)or isKeyDown(0x5C)}
        if sceneServices.assistInput:menuPressed(shortcut.key,allowed,assistKeys,shortcut.key~=0 and wasKeyPressed(shortcut.key),shortcut)then
            if sceneServices.showAssist[0]then studio:flushAutosave(studioCallbacks,true);closePanels()
            else studioCallbacks.openAssist()end
        end
    end
    local altDown=physicalKeys and physicalKeys.alt
    if not physicalKeys then altDown=isKeyDown(0x12)end
    local cursorAllowed=focused and ctx.session and not ctx.paused and not ctx.blocked and not uiTyping and
        not keyRecorder and not hasUiModal()and not runtime.wheel and not hud.failed
    widgetCursor=cursorAllowed and not ownUi()and altDown or false
    alertState.mouseAllowed=ownUi()or widgetCursor or hud.editing
    alertState.cursorHint='Удерживайте Alt — курсор · '..bindingModel.keyName(cfg.main.menu_key)..' — меню'
    local shortcutRows={};for _,kind in ipairs(bindingModel.alertKinds)do shortcutRows[#shortcutRows+1]={id=kind,shortcut=workspace.library.alert_shortcuts[kind]}end
    local shortcutAlert=confirmationInput:poll(shortcutRows,cursorAllowed and not alerts.pending and alertState.alive==true and not hud.drag,physicalKeys)
    if shortcutAlert then alerts:request(shortcutAlert)end
    local patrolRows={};for _,row in ipairs({{'toggle_shortcut','start'},{'pause_shortcut','pause'},{'finish_shortcut','finish'}})do
        patrolRows[#patrolRows+1]={id='patrol-'..row[2],shortcut=workspace.library.patrol_session[row[1]]}
    end
    patrolRows[#patrolRows+1]={id='patrol-events',shortcut=workspace.library.patrol_events.open_shortcut}
    patrolRows[#patrolRows+1]={id='fast-pt',shortcut=workspace.library.vehicle.fast_pt_shortcut}
    for _,row in ipairs(workspace.library.vehicle.enabled and{{'select_shortcut','vehicle-select'},{'pursuit_shortcut','vehicle-pursuit'}}or {})do
        patrolRows[#patrolRows+1]={id=row[2],shortcut=workspace.library.vehicle[row[1]]}
    end
    patrolRows[#patrolRows+1]={id='assist-megaphone-window',shortcut=workspace.library.vehicle.megaphone_shortcut}
    if workspace.library.vehicle.megaphone_enabled then for i,p in ipairs(workspace.library.vehicle.phrases)do if p.enabled then
        patrolRows[#patrolRows+1]={id='vehicle-phrase-'..i,shortcut=workspace.library.vehicle['phrase_'..i..'_shortcut']}
    end end end
    for _,row in ipairs({{'megaphone_shortcut','megaphone'},{'evidence_shortcut','evidence'},{'training_shortcut','training'}})do
        patrolRows[#patrolRows+1]={id='assist-'..row[2],shortcut=workspace.library.assist[row[1]]}
    end
    local vehicleAnswer=confirmationInput:poll({{id='yes',shortcut={key=0x59,ctrl=false,alt=false,shift=false}},{id='no',shortcut={key=0x4e,ctrl=false,alt=false,shift=false}}},
        focused and not ctx.paused and not ctx.blocked and not uiTyping and not studio:hasWarning()and(studio.vehicleConfirm~=nil or studio.assistConfirm~=nil),physicalKeys)
    if vehicleAnswer then
        if vehicleAnswer=='no'then studio:declineVehicle()
        else local ok,err=studio:acceptModal(nil,studioCallbacks);if ok then studio:cancelModal()else studio:notify(err or'Не удалось выполнить действие.')end end
    end
    local patrolKey=confirmationInput:poll(patrolRows,cursorAllowed and not alerts.pending,physicalKeys)
    if patrolKey then
        if patrolKey=='fast-pt'then sceneServices.fastPtRequest=true;patrolKey=nil end
    end
    if patrolKey then
        if patrolKey:match('^assist%-')then studioCallbacks.openAssist(patrolKey=='assist-megaphone-window'and'megaphone'or patrolKey:sub(8))end
        if patrolKey:match('^vehicle%-')then
            local action=patrolKey=='vehicle-select'and'stop_order'or patrolKey=='vehicle-pursuit'and'pursuit'or'megaphone_'..patrolKey:match('(%d+)$')
            local select=patrolKey=='vehicle-select'or patrolKey=='vehicle-pursuit'and not sceneServices.vehicle.selected
            local revision=sceneServices.vehicle.selectionRevision or 0
            local ok,err=true
            if select then ok,err=sceneServices.vehicle:requestSelection()end
            if ok then sceneServices.vehicleHotkey={action=action,select=select,revision=revision,at=now,session=ctx.session}
            else studio:notify(err,'vehicle',false)end
        end
        if patrolKey=='patrol-events'then studioCallbacks.openPatrolEvents()elseif not patrolKey:match('^vehicle%-')and not patrolKey:match('^assist%-')then studioCallbacks.openPatrol()end
        local a=patrolSession.data.active
        if patrolKey=='patrol-pause'and a and a.status=='active'then studioCallbacks.patrolPause()
        elseif patrolKey=='patrol-pause'and a then local p=patrolSession:propose('resume');studio.patrolConfirm=p
        elseif patrolKey=='patrol-finish'and a then local p=patrolSession:propose('finish');studio.patrolConfirm=p end
    end
    local procedureRows={};for _,kind in ipairs({'wanted','fine','mark'})do
        procedureRows[#procedureRows+1]={id=kind,shortcut=workspace.library.procedures[kind..'_shortcut']}
    end
    local procedureKey=confirmationInput:poll(procedureRows,cursorAllowed and not alerts.pending,physicalKeys)
    if procedureKey then env.wheelNavigate({kind='procedure',id='procedure-'..procedureKey,category='wanted'})end
    alertState=patrolSession:values(alertState,patrolSession.data.active)
    local alertKeys=physicalKeys
    alertState.keyboardAvailable=alertKeys~=nil
    local alertConsumed=alerts:tick(alertState,now,alertKeys or {physical=true,y=true,n=true,mods=true})or shortcutAlert~=nil or patrolKey~=nil or procedureKey~=nil
    -- Timers and automatic single-line RP use the same guarded executor. None
    -- of these features hide a window or interrupt a user scenario implicitly.
    alertState.alertPending=alerts.pending~=nil
    alertState.busy=(workspace.executor.queue and tostring(workspace.executor.queue)) or
        (workspace.pending and tostring(workspace.pending)) or (runtime.queue and tostring(runtime.queue)) or
        (hasUiModal() and 'modal') or nil
    -- Cancel accepted work before controllers dispatch or commit a manual fact.
    if escapePressed and not escDismissed and not uiTyping and not hasUiModal()and not keyRecorder then
        cancelManualActions('Отменено клавишей Esc.')
    end
    if workspace.library.settings.cancel_key~=0 and(wasKeyPressed(workspace.library.settings.cancel_key)or physicalCancel~=nil)and
        not(ownUi()and(uiTyping or hasUiModal()))and not keyRecorder and
        (workspace.executor.queue or runtime.queue or runtime.wheel or workspace.pending or alerts.pending or
            sceneServices.evidence.intent or sceneServices.evidence.queued or sceneServices.evidence.active or
            caseForms.intent or caseForms.queued or caseForms.awaitingCommand or patrolSession.intent or patrolSession.queued or patrolEvents.intent or patrolEvents.queued or workspace.operations.intent)then
        if alerts.pending then alerts:decide(false)end
        closeForInput('Остановлено клавишей отмены.');return
    end
    workspace.operations:tick(alertState,now)
    sceneServices.colleagues:tick(alertState,now);alertState.colleagues=sceneServices.colleagues:view()
    patrolSession.readScene(alertState,now)
    alertState.verifiedCrew=patrolSession.data.active and patrolSession.data.active.crew or nil
    local hour=optionalRead('getTimeOfDay');alertState.gameHour=core.finite(hour)and hour or nil;alertState.moscowTime=core.moscowTime()
    alertState.patrolActive=patrolSession.data.active~=nil
    if sceneServices.patrolWasActive and not alertState.patrolActive then
        patrol:reset()
        local c=sceneServices.copilot
        if not c.phase and not c.intent and not c.queued and not sceneServices.vehicle.phase and not sceneServices.vehicle.intent and not sceneServices.vehicle.queued then
            sceneServices.vehicle:clearTarget('Патруль завершён.');c:reset('Патруль завершён.');c:hideHud()
        end
    end
    sceneServices.patrolWasActive=alertState.patrolActive
    alertState.patrolStatus=patrolSession.data.active and patrolSession.data.active.status or nil
    sceneServices.vehicle:tick(alertState,now)
    sceneServices.refreshFastPt(alertState,now)
    sceneServices.copilot:tick(alertState,now)
    sceneServices.processGroundInput()
    local hot=sceneServices.vehicleHotkey;sceneServices.vehicleHotkey=nil
    if hot and hot.session==ctx.session and(core.elapsed(now,hot.at)or math.huge)<2000 and not hasUiModal()then
        if not hot.select or(sceneServices.vehicle.selectionRevision or 0)>hot.revision then
            if hot.action:match('^megaphone_')then require('pa26_vehicle_ui').offer(studio,studioCallbacks,hot.action,false)
            else
                local p,err=sceneServices.copilot:propose(hot.action)
                if p then sceneServices.copilot.offers={p}else studio:notify(err,'vehicle',false)end
            end
        end
    end
    alertState.taserCombatEnabled=workspace.library.vehicle.copilot.combat_guard;alertState.taserCombatMs=workspace.library.vehicle.copilot.combat_ms;alertState.taserCombatTemplate=workspace.library.vehicle.copilot.combat_warning
    local cv=sceneServices.copilot:view()
    if workspace.library.vehicle.copilot.combat_guard and(cv.combat or cv.car and cv.car.armed or sceneServices.copilot.driverLive and sceneServices.copilot.driverLive.armed)then alertState.taserCombatText=workspace.library.vehicle.copilot.combat_warning end
    local person=workspace.selectedTarget and sceneServices.readDriver(workspace.selectedTarget.id)
    if alertState.taserCombatEnabled and person and person.armed then alertState.taserCombatText=workspace.library.vehicle.copilot.combat_warning end
    local cm=sceneServices.copilot.widgetMail;sceneServices.copilot.widgetMail=nil
    if cm and cm.life==sceneServices.copilot.life and(core.elapsed(now,cm.at)or math.huge)<500 and not hasUiModal()then
        local p,err
        if cm.action=='hide'then sceneServices.copilot:hideHud()
        elseif cm.action=='repeat_pause'then sceneServices.copilot:pauseRepeats()
        else p,err=sceneServices.copilot:propose(cm.action)end
        if p then if p.navigation then sceneServices.groundInput=p else studio.vehicleConfirm=p end;uiInputReset=true elseif err then studio:notify(err,'vehicle',false)end
    end
    alertState.busy=alertState.busy or(workspace.executor.queue and tostring(workspace.executor.queue))
    sceneServices.evidence:tick(alertState,now)
    alertState.busy=alertState.busy or(workspace.executor.queue and tostring(workspace.executor.queue))
    alertState=sceneServices.vehicle:values(alertState)
    sceneServices.wantedAccounts:tick(alertState,workspace.selectedTarget,{studio.caseForm,
        caseForms.intent and caseForms.intent.form or false,caseForms.queued and caseForms.queued.form or false,
        caseForms.awaitingCommand and caseForms.awaitingCommand.form or false,sceneServices.detentionTimers.case or false})
    identity:tick(alertState,workspace.selectedTarget,workspace.targets.revision,now)
    caseForms:tick(alertState,now)
    sceneServices.detentionTimers:tick(alertState,now)
    if sceneServices.caseTargetInput then
        local p=sceneServices.caseTargetInput;sceneServices.caseTargetInput=nil
        local age=core.elapsed(now,p.at)
        if age and age<=5000 and p.session==alertState.session and p.epoch==sceneServices.chatEpoch and not alertState.typing and not alertState.blocked and alertState.alive and alertState.focused then
            local target,err=sceneServices.wantedAccounts:select(p.id)
            local f;if target then f,err=caseForms:begin('mark',target)end
            if f then studio:selectProcedure('mark');studio.caseForm=f;studio.caseStoredForms.mark=f
            else studio:notify(err or'Не удалось выбрать аккаунт.','procedures',false)end
        else studio:notify('Выбор ID устарел. Повторите его в доступной игровой сцене.','procedures',false)end
    end
    if studio.cancelledCaseToken then caseForms:cancelCommandConfirmation(studio.cancelledCaseToken);studio.cancelledCaseToken=nil end
    caseForms:flush()
    if not hasUiModal()then
        local final=caseForms:takeCommandConfirmation()
        if final then
            studioCallbacks.openProcedures(final.form.host or final.kind)
            if final.form.host=='mark'then studio.markReview=true end
            studio.caseConfirm=final
        end
    end
    if caseForms.reviewReminders then
        caseForms.reviewReminders=nil;studioCallbacks.openProcedures('mark');studio.markReview=true
    end
    sceneServices.processWantedInput(alertState,now)
    sceneServices.processProcedureInput(alertState,now)
    alertState.busy=alertState.busy or (workspace.executor.queue and tostring(workspace.executor.queue))
    patrolSession:tick(alertState,now)
    alertState.patrolSuspended=patrolSession.data.active~=nil and patrolSession.suspended==true
    alertState=patrolSession:values(alertState,patrolSession.data.active)
    alerts:updateContext(alertState)
    patrolEvents:tick(alertState,now)
    alertState.busy=alertState.busy or (workspace.executor.queue and tostring(workspace.executor.queue))
    radioGuard:tick(alertState,now)
    taser:tick(alertState,now)
    alertState.taserCombatText=alertState.taserCombatText or taser:combatWarning()
    alertState.taserActive=taser:activeFor(alertState)
    alertState.taserRoleItem={name=workspace.library.taser.name,template=workspace.library.taser.draw_template,
        draw_rp_enabled=workspace.library.taser.draw_rp_enabled~=false and not taser.suppressModeRp,
        holster_enabled=workspace.library.taser.holster_rp_enabled~=false and not taser.suppressModeRp,holster_template=workspace.library.taser.holster_template}
    alertState.reloadPending=alertState.taserActive and(taser:needsReload()or taser.queued)or false
    alertState.busy=alertState.busy or (workspace.executor.queue and tostring(workspace.executor.queue))
    patrol:tick(alertState,now)
    alertState.alertPending=alerts.pending~=nil
    alertState.busy=alertState.busy or (workspace.executor.queue and tostring(workspace.executor.queue))
    weapons:tick(alertState,now)
    alertState.busy=alertState.busy or (workspace.executor.queue and tostring(workspace.executor.queue))
    weaponWarning:tick(alertState,now)
    local candidates=radioGuard:candidates()
    for _,c in ipairs(weaponWarning:candidates())do candidates[#candidates+1]=c end
    for _,c in ipairs(patrolEvents:candidates())do candidates[#candidates+1]=c end
    for _,c in ipairs(caseForms:candidates())do candidates[#candidates+1]=c end
    for _,c in ipairs(sceneServices.copilot:candidates())do candidates[#candidates+1]=c end
    local noticeKeys=physicalKeys
    local noticeConsumed=notifications:tick(candidates,alertState,now,noticeKeys)
    local review,reviewError=patrolEvents:takeNoticeReview()
    if review or reviewError then
        studioCallbacks.openPatrolEvents();studio.patrolEventPage='work'
        if review and not studio.patrolEventForm then
            for key in pairs(studio.cache)do if key:match('^patrol%-event%-form:')then studio.cache[key]=nil end end
            studio.patrolEventForm=review
        else studio:notify(reviewError or 'Текущая форма сохранена. Новая попытка доступна в списке выше.','patrol_events',false,reviewError and'warning'or'info')end
    end
    alertConsumed=alertConsumed or noticeConsumed
    hud.patrol=patrolSession:view(patrol:view()).hud or patrol:view()
    if not workspace.library.settings.wheel_enabled and runtime.wheel then runtime:cancel('Радиальное меню отключено.')end
    local shortcutPressed=false
    local pressedBindingId
    if not alertConsumed and focused and not ctx.blocked and not ownUi() and not workspace.executor.queue and not workspace.pending then
        local mods={ctrl=isKeyDown(0x11),alt=isKeyDown(0x12),shift=isKeyDown(0x10)}
        for _,b in ipairs(workspace.library.bindings) do if b.enabled and b.shortcut.key~=0 and wasKeyPressed(b.shortcut.key) and bindingModel.matchesShortcut(b.shortcut,b.shortcut.key,mods) then shortcutPressed=true; pressedBindingId=b.id; break end end
    end
    local allowWidgetInput = focused and not ctx.paused and not ctx.blocked and hud.connected and not workspace.executor.queue and not workspace.pending and not keyRecorder and not shortcutPressed and not alerts.suppressHud
    local px,py
    if widgetCursor or hud.drag then
        local x, y = optionalRead('getCursorPos')
        px,py=x,y;hud:setPointer(x,y,isKeyDown(0x01),isKeyDown(0x02))
    end
    local b=hud.bounds
    local overHud=b and core.finite(px)and core.finite(py)and px>=b.x and px<=b.x+b.w and py>=b.y and py<=b.y+b.h
    hud:setInteraction(allowWidgetInput and widgetCursor and(hud.drag~=nil or isKeyDown(0x02)and overHud),
        not uiFailed and(ownUi()or widgetCursor or runtime.wheel~=nil))
    if hud.editing or hud.drag then runtime:cancel('Редактирование компактного виджета. Действие отменено.') end
    widgetFrame.HideCursor = not(widgetCursor or hud.editing)
    hud:savePending(now)
    if escapePressed then
        if not uiTyping and not hasUiModal()then weaponWarning:dismiss();radioGuard:cancel()end
        if alerts.pending and not hasUiModal() and not uiTyping then alerts:decide(false) end
        if not escDismissed and studio:hasWarning()then studio:ackWarning();escDismissed=true
        elseif not escDismissed and hasUiModal() then cancelUiModal(); keyRecorder=nil; escDismissed=true
        elseif ownUi() and not escDismissed then closePanels(); escDismissed=true
        elseif not escDismissed then closeForInput('Отменено клавишей Esc.') end
        return
    elseif not isKeyDown(0x1B) and not (ownUi() and studio.guiEscapeDown) then escDismissed=false end
    if keyRecorder and (not studio.keyCapture or studio.keyCapture.request~=keyRecorder) then keyRecorder=nil end
    local recording=keyRecorder~=nil
    if keyRecorder then
        keyRecorder.startedAt=keyRecorder.startedAt or now
        local age=core.elapsed(now,keyRecorder.startedAt)
        if not age or age>10000 or not focused then
            local request=keyRecorder; keyRecorder=nil
            studio:captureTimeout(request)
        end
    end
    if focused and not ctx.paused and not ctx.blocked and not uiFailed and not hud.editing and not hud.drag then
        local typing = ownUi() and (uiTyping or hasUiModal())
        if not alertConsumed and not recording and not typing then
            if workspace.library.settings.quick_key~=0 and not isKeyDown(0x11) and not isKeyDown(0x12) and not isKeyDown(0x10) and wasKeyPressed(workspace.library.settings.quick_key) then
                local visible=showQuick[0]; closePanels(); if not visible then studioCallbacks.openQuick() end
            elseif workspace.library.settings.tips_key~=0 and not isKeyDown(0x11) and not isKeyDown(0x12) and not isKeyDown(0x10) and wasKeyPressed(workspace.library.settings.tips_key) then
                local visible=showTips[0]; closePanels(); if not visible then studioCallbacks.openTips() end
            end
            if not ownUi() and pressedBindingId and not hud.drag then workspace:request({kind='prepare',id=pressedBindingId,start=true,returnTo='quick'}) end
        end
        sceneServices.processWheelEdit()
        if runtime.wheel then
            if pendingWheelClick then local choice=pendingWheelClick; pendingWheelClick=nil; runtime:commitWheel(choice)
            elseif not isKeyDown(cfg.main.radial_key) then runtime:commitWheel() end
        elseif workspace.library.settings.wheel_enabled and not alertConsumed and not ownUi() and not runtime.queue and not workspace.executor.queue and not workspace.pending and not recording and wasKeyPressed(cfg.main.radial_key) then
            uiInputReset = true
            runtime:openWheel()
        end
    end
    runtime:step()
    sceneServices.manual:tick()
    sceneServices.manualActions:tick()
    workspace:tick()
    syncBindingCommands()
    workspaceFrame.HideCursor=not(ownUi()or studio.statusInfo and widgetCursor)
    imgui.DisableInput = shutdown or not focused or ctx.paused or ctx.blocked or
        ((uiFailed or (not ownUi() and runtime.wheel == nil and not(studio.statusInfo and widgetCursor))) and not hud.editing)
end

-- Prepare the local chat before yielding to the game/CEF require('pa26_startup'). The old
updateGame=sceneServices.chatPerf:wrap('updateGame',updateGame)
-- placement after the SA:MP gate was too late after a launcher integrity pass.
sceneServices.readLayout=sceneServices.layoutModule.reader(ffi)
sceneServices.chatBridge=sceneServices.chatModule.new({fs=storage.fs,assetFs=require('pa26_cef_assets').fs,json=workspace.json,
    path=getWorkingDirectory()..'\\..\\cef\\assets\\hud\\',token=function()return sceneServices.chatModule.entropy(ffi)end,
    session=function()local key=connectionKey();return key and(key..'@'..sceneServices.chatEpoch)or nil end,
    settings=function()
        local filters={};for _,filter in ipairs(workspace.library.filters)do if filter.enabled then filters[#filters+1]=filter.prefix end end
        return{enabled=workspace.library.settings.cef_chat_support,accentEnabled=workspace.library.settings.accent_live_input,
            accent=bindingModel.accentPrefix(workspace.library.profile.accent),filters=filters,diagnostics=workspace.library.settings.cef_chat_diagnostics,
            layoutIndicator=workspace.library.settings.cef_layout_indicator,weaponGuard=workspace.library.settings.cef_chat_weapon_guard,
            accent_skip_brackets=workspace.library.settings.accent_skip_brackets,chat_dot_commands=workspace.library.settings.chat_dot_commands,
            manual_radio_prefix=workspace.library.settings.manual_radio_prefix,local_tag=workspace.library.profile.local_tag,
            manual_chat=workspace.library.settings.manual_chat,rp_text=workspace.library.rp_text,nickname=hud.data.nickname}
    end,
    layout=sceneServices.readLayout,
    inputActive=function()return optionalRead('sampIsChatInputActive')~=false or optionalRead('sampIsDialogActive')~=false or optionalRead('sampIsCursorActive')~=false end,
    commandsRevision=function()return sceneServices.chatCommandsRevision or 0 end,
    message=function(text,now)sceneServices.observeMessage(text,'cef',now)end,
    command=sceneServices.observeCommand,manual=function(text,key)return sceneServices.manual:offer(text,key)end,
    manualResult=function(key)return key and sceneServices.manual.seen[key]or sceneServices.manual.result end,log=pushLog})
sceneServices.chatBridge.commands=sceneServices.localCommands
sceneServices.chatBridge.tick=sceneServices.chatPerf:wrap('bridgeTick',sceneServices.chatBridge.tick)
sceneServices.chatBridge.exchange=sceneServices.chatPerf:wrap('bridgeExchange',sceneServices.chatBridge.exchange)
sceneServices.chatBridge:start()

function main()
    for _, name in ipairs(requiredApis) do
        if type(_G[name]) ~= 'function' then
            local reason='Ошибка запуска: клиент не поддерживает '..name..'. Проверьте совместимость MoonLoader и SAMPFUNCS.'
            require('pa26_startup').block(getWorkingDirectory(),reason)
            pushLog(reason)
            cleanup()
            require('pa26_startup').announce(reason,encoding)
            return
        end
    end
    while not isSampAvailable() do
        sceneServices.chatBridge:tick(optionalRead('getGameTimer')or 0)
        wait(100)
    end
    local commands = {
        {'pa26', toggleWindow},
        {'ticket',function(arguments)sceneServices.queueProcedureInput('ticket',arguments)end},
        {'setmark',function(arguments)sceneServices.queueProcedureInput('setmark',arguments)end},
        {'su',function(arguments)sceneServices.queueWantedInput('su',arguments)end},
        {'wanted',function(arguments)sceneServices.queueWantedInput('wanted',arguments)end},
        {'pa26repair',function()recoverUi(true)end},
        {'pa26demo', function() sceneServices.requestDemoMode=not runtime.demo end},
        {'pa26cancel', function() if alerts.pending then alerts:decide(false) end;closeForInput('Отменено командой /pa26cancel.'); workspace:clearTarget('manual') end},
        {'pa26hud', function() hud:setVisible(not hud.settings.visible) end},
        {'pa26hudreset', function() hud:resetPosition() end},
        {'pa26sos',function() alerts:request('sos') end},
        {'pa26shots',function() alerts:request('shots') end},
        {'pa26code0',function() alerts:request('code0') end},
        {'pa26reload',function() taser:requestReload() end},
        {'pa26skip',function() radioGuard:cancel()end},
        {'pa26warn',function() weaponWarning:request()end},
        {'pa26quick',function() closePanels(); studioCallbacks.openQuick() end},
        {'pa26tips',function() closePanels(); studioCallbacks.openTips() end},
        {'pa26run',function(arguments)
            local id,rest=tostring(arguments or ''):match('^%s*(%d+)%s*(.-)%s*$')
            if not id then report('Использование: /pa26run номер_бинда [аргументы]'); return end
            if not core.validUtf8(rest) then local ok,decoded=pcall(codec.decode,rest); rest=ok and decoded or '' end
            local args,err=bindingModel.parseArguments(rest); if not args then report(err); return end
            local b=bindingModel.find(workspace.library,tonumber(id)); if b then for i,p in ipairs(b.parameters) do args[p.name]=args['param'..i] or '' end end
            workspace:request({kind='prepare',id=tonumber(id),args=args,start=true,returnTo='quick'})
        end},
        {'pa26select',function(arguments)
            if tostring(arguments or ''):match('^%s*off%s*$') then workspace:clearTarget('manual'); return end
            local id=tonumber(arguments); if not core.validId(id) then report('Укажите SA:MP ID видимого человека рядом.'); return end
            local streamed,ped=optionalRead('sampGetCharHandleBySampPlayerId',id)
            local target=streamed==true and inspectPed(ped,nil,cfg.main.max_distance) or nil
            if target and target.id==id then workspace:selectTarget(target); return end
            report('Этот человек не виден, слишком далеко или недоступен. Прежний выбор сохранён.')
        end},
        {'pa26export',function() studioCallbacks.export(); openWorkspace('binds') end},
        {'pa26import',function() studioCallbacks.import(); openWorkspace('binds') end},
    }
    for _, item in ipairs(commands) do
        local ok, result = pcall(sampRegisterChatCommand, item[1], item[2])
        if ok and result ~= false then registered[#registered + 1] = item[1];sceneServices.localCommands[item[1]]=item[2]
        else pushLog('Не зарегистрирована команда /' .. item[1] .. '; используйте клавиши.') end
    end
    connectChatFilters(); syncBindingCommands()
    sceneServices.aimPicker=sceneServices.targetModule.aim({
        down=function()
            if workspace.library.settings.aim_select_control=='game'then return optionalRead('isButtonPressed',0,6)end
            return optionalRead('isKeyDown',0x02)
        end,
        acquire=function()
            local aimed,ped=optionalRead('getCharPlayerIsTargeting',PLAYER_HANDLE)
            if aimed==true then
                local native=inspectPed(ped,nil,workspace.library.settings.retain_distance)
                if native then return native end
            end
            -- Friendly teammates may have no native weapon lock. RMB must use
            -- the same visible gaze selection as X instead of silently failing.
            local now=getGameTimer();local age=sceneServices.aimFallbackAt and core.elapsed(now,sceneServices.aimFallbackAt)
            if age and age<250 then return nil end
            sceneServices.aimFallbackAt=now
            return acquireTarget(workspace.library.settings.retain_distance)
        end,
        select=function(target)return workspace:selectTarget(target)end})
    require('pa26_startup').ready(getWorkingDirectory())
    local started, drawReported = false, false
    while true do
        wait(0)
        if sceneServices.shutdownUnload then
            sceneServices.shutdownUnload=nil
            if type(thisScript)=='function'then local found,script=pcall(thisScript)
                if found and script and type(script.unload)=='function'then pcall(script.unload,script)end
            end
            return
        end
        if sceneServices.shutdownRequested then sceneServices.performShutdown()end
        if not shutdown then
        if sceneServices.requestDemoMode~=nil then
            local desired=sceneServices.requestDemoMode;sceneServices.requestDemoMode=nil
            if desired~=runtime.demo then
                local previous=runtime.demo;setDemo(desired);saveSettings(true)
                if generalSaveFailed then setDemo(previous)end
            end
        end
        sceneServices.chatPerf:setEnabled(workspace.library.settings.cef_chat_profile)
        sceneServices.chatPerf:frame()
        updateGame()
        sceneServices.dispatchNativeCommand(studioClock)
        if focused and not isGamePaused()and not context().inputBlocked then sceneServices.chatBridge:dispatch(studioClock)end
        local now=optionalRead('getGameTimer')or studioClock
        if recovery:ready(now,cfg.recovery)and focused and not uiTyping and not hasUiModal()and not isGamePaused()and
            not context().blocked then recoverUi(false)end
        recovery:healthy(now,cfg.recovery)
        if not started then
            pushLog('v'..core.VERSION..': игровой цикл запущен.')
            started = true
        end
        if uiRendered and not drawReported then
            pushLog('v'..core.VERSION..': окно отрисовано.')
            drawReported = true
        end
        end
    end
end

script_name('PA26 Recovery')
script_author('VIBAG ( Victor Auditore )')
script_version('0.40.1')
script_description('Restarts only Police Assistant after a Lua-script termination, with a bounded retry count')
if type(script_properties)=='function'then script_properties('work-in-pause')end

-- Main displays the recovery window; the guard must not reload mixed files.
do
    local good,module=pcall(require,'pa26_update_platform')
    if good then local ok,p=pcall(module.new,getWorkingDirectory())
        if ok and p and p:exists(p.ml..'\\pa26-update.pending')then function main()end;return end
    end
end
local startup=require 'pa26_startup'
local core=require 'pa26_core'
local storage=require 'pa26_config'
local module=require 'pa26_recovery'
local guard=module.new()
local directory=getWorkingDirectory()
local targetPath=directory..'\\police_assistant_2026.lua'
local markerPath=directory..'\\config\\police_assistant_2026_restart.flag'
local configPath=directory..'\\config\\police_assistant_2026.ini'
local settings=core.recoveryDefaults()
local stopping=false
local known=false
local target
local loadedAt
local manual=false
local lastRead
local registered=false
local encodingOk,encoding=pcall(require,'encoding')
if not encodingOk then encoding=nil end
local verifying
local function note(text)startup.announce(text,encoding)end
local function matches(scriptObject)
    if not scriptObject then return false end
    local ok,path=pcall(function()return scriptObject.path end)
    return ok and type(path)=='string'and path:gsub('/','\\'):lower()==targetPath:gsub('/','\\'):lower()
end
local function find()
    if type(script)~='table'or type(script.find)~='function'then return nil end
    local ok,value=pcall(script.find,'Police Assistant 2026')
    if ok and matches(value)then
        local readable,dead=pcall(function()return value.dead end)
        if readable and dead~=true then return value end
    end
end
function onScriptLoad(scriptObject)
    if matches(scriptObject)then target=scriptObject;known=true;loadedAt=getGameTimer()end
end
function onScriptTerminate(scriptObject,quitGame)
    if quitGame==true or scriptObject==thisScript()then
        stopping=true;guard:stop()
        if scriptObject==thisScript()and quitGame~=true and registered and type(sampUnregisterChatCommand)=='function'then
            pcall(sampUnregisterChatCommand,'pa26restart');registered=false
        end
        return
    end
    if not stopping and matches(scriptObject)then
        known=true;target=nil;verifying=nil
        if startup.read(directory)=='blocked'then guard:stop()
        else guard:trip(getGameTimer(),'terminated','Main PA script terminated')end
    end
end
function onQuitGame()stopping=true;guard:stop()end
function main()
    if type(script)~='table'or type(script.find)~='function'or type(script.load)~='function'then
        print('[PA26 Recovery] MoonLoader script management API unavailable.');return
    end
    while not isSampAvailable()do wait(100)end
    target=find();known=target~=nil;loadedAt=getGameTimer()
    registered=sampRegisterChatCommand('pa26restart',function()
        if find()then note('PA работает. Для восстановления окон используйте /pa26repair.');return end
        manual=true
    end)~=false
    while not stopping do
        wait(100)
        local now=getGameTimer()
        if not lastRead or(core.elapsed(now,lastRead)or 1000)>=1000 then
            local ok,cfg,notes=pcall(storage.load,configPath)
            if ok and cfg and #notes==0 then settings=cfg.recovery or core.recoveryDefaults()end
            lastRead=now
        end
        local live=find()
        local startupState=startup.read(directory)
        if live then
            if target~=live then target=live;known=true;loadedAt=now end
            if loadedAt and(core.elapsed(now,loadedAt)or 0)>=settings.stable_ms then guard.attempts=0 end
            if verifying and startupState=='ready'and(core.elapsed(now,verifying)or 0)>=500 then
                note('PA загружен заново. Старые действия не повторяются.'..(settings.demo_after_recovery and' Включён деморежим.'or''));verifying=nil
            end
            -- A queued event from an ordinary script reload must not load a duplicate.
            guard.pending=nil;manual=false
        elseif known and not guard.pending and target then
            target=nil;guard:trip(now,'missing','Main PA script is no longer loaded')
        end
        if startupState=='blocked'and not manual then guard:stop();verifying=nil end
        if not live and(manual or startupState~='blocked'and guard:ready(now,settings))then
            local requested=manual;manual=false
            if guard:begin(now,settings,requested)then
                if settings.demo_after_recovery and not module.writeMarker(markerPath,storage.fs)then
                    note('Не удалось подготовить безопасный перезапуск PA. Повторите /pa26restart.');guard:stop()
                else
                    startup.clear(directory)
                    local ok,value=pcall(script.load,targetPath)
                    if ok and value then
                        target=value;known=true;loadedAt=now;verifying=now
                    else
                        known=true;target=nil;guard:trip(now,'load','Failed to load main PA script')
                        note('PA пока не загрузился. Попытка '..guard.attempts..' из '..settings.max_attempts..'. Проверьте moonloader.log.')
                    end
                end
            end
        end
    end
    if registered and type(sampUnregisterChatCommand)=='function'then pcall(sampUnregisterChatCommand,'pa26restart')end
end

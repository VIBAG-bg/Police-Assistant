local filesModule=require 'pa26_user_files'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local cfg=core.defaults()
local json={encode=function(v)return TEST_JSON_ENCODE(v)end,decode=function(v)return TEST_JSON_DECODE(v)end}
local base='personal'
local original=model.defaults(cfg)
original.profile.name='Private_Officer';original.partners={{id=1,nickname='Private_Partner',callsign='P-17'}};original.next_partner_id=2
original.notes[1].body='Private note';original.bindings[1].name='Мой сохранённый бинд';original.bindings[1].shortcut={key=0x51,ctrl=true,alt=false,shift=false}
local legacy=json.encode(original)
local function fixture(seed)
    local state={data=model.copy(seed or{[base..'_library.json']=legacy}),writes={},changes=0}
    local function change(name,path)
        state.changes=state.changes+1
        if state.off then return false end
        if state.crashAt and state.changes==state.crashAt then state.off=true;return false end
        if state.failAt and state.changes==state.failAt then return false end
        if state.failPath==path then return false end
        state.writes[#state.writes+1]={name=name,path=path};return true
    end
    state.fs={exists=function(p)if state.off then return nil end;return state.data[p]~=nil end,
        read=function(p)if state.off then return nil end;return state.data[p]end,
        write=function(p,text)if not change('write',p)then return nil end;state.data[p]=state.partialAt==state.changes and text:sub(1,math.floor(#text/2))or text;return true end,
        remove=function(p)if not change('remove',p)then return nil end;state.data[p]=nil;return true end,
        rename=function(a,b)if not change('rename',b)or not state.data[a]or state.data[b]then return nil end;state.data[b]=state.data[a];state.data[a]=nil;return true end}
    state.open=function()return filesModule.new(base,json,cfg,state.fs)end
    return state
end
local function read(state,kind)return json.decode(assert(state.data[base..'_'..kind..'.json']))end
local function coherent(state,expected)
    local b,n,s=read(state,'binds'),read(state,'notes'),read(state,'settings')
    eq(b.bindings[1].name,expected.bindings[1].name);eq(b.bindings[1].shortcut.key,expected.bindings[1].shortcut.key)
    eq(n.notes[1].body,expected.notes[1].body);eq(s.data.profile.name,expected.profile.name)
    check(not b.notes and not b.profile and not b.settings and not b.partners)
    check(not n.bindings and not n.profile and not n.settings and not n.partners)
    check(not s.data.bindings and not s.data.notes and not s.data.wheel)
end
local state=fixture();local storage=state.open();local lib,warnings,fresh=storage:load()
check(fresh);eq(#warnings,0);eq(lib.profile.name,original.profile.name);check(storage:save(lib))
coherent(state,original);eq(state.data[base..'_library.json'],legacy,'migration changed the original backup')
local active=model.copy(state.data)
storage=state.open();lib,warnings,fresh=storage:load();check(not fresh);eq(#warnings,0)
local bindsBefore=state.data[base..'_binds.json'];local settingsBefore=state.data[base..'_settings.json']
state.writes={};lib.notes[1].body='Новая заметка';check(storage:save(lib))
eq(state.data[base..'_binds.json'],bindsBefore);eq(state.data[base..'_settings.json'],settingsBefore)
for _,op in ipairs(state.writes)do check(not op.path:find('_binds.json',1,true)and not op.path:find('_settings.json',1,true))end
state.writes={};check(storage:save(lib));eq(#state.writes,0,'unchanged save must not write any file')
lib.bindings[1].name='Новый бинд';local notesBefore=state.data[base..'_notes.json'];check(storage:save(lib));eq(state.data[base..'_notes.json'],notesBefore)

-- Exchange payloads contain exactly the requested kind, including one-item export.
for _,kind in ipairs({'binds','notes'})do
    local payload=assert(filesModule.exchange(lib,kind,1));local field=kind=='binds'and'bindings'or'notes'
    eq(#payload[field],1);check(not payload.profile and not payload.settings and not payload.partners)
    check(kind=='binds'and not payload.notes or kind=='notes'and not payload.bindings)
    check(filesModule.decodeExchange(json.encode(payload),json,kind))
    check(not filesModule.decodeExchange(json.encode(payload),json,kind=='binds'and'notes'or'binds'))
    payload.profile={name='leak'};check(not filesModule.validate(kind,payload))
    local old=assert(filesModule.decodeExchange(legacy,json,kind));check(not old.profile and not old.partners)
end
check(not filesModule.exchange(lib,'all'));check(not filesModule.exchange(lib,'binds',999))
check(not filesModule.decodeExchange(string.rep('[',25),json,'binds'))
check(not filesModule.decodeExchange('{}\0',json,'notes'))

-- Existing backup recovers only its own kind; missing/corrupt files never resurrect
-- the stale monolithic snapshot or silently overwrite a user's notes.
state=fixture(active);state.data[base..'_binds.json.bak']=state.data[base..'_binds.json'];state.data[base..'_binds.json']='broken'
storage=state.open();lib,warnings,fresh=storage:load();eq(lib.bindings[1].name,original.bindings[1].name);check(#warnings>0);check(not storage.blocked)
state=fixture(active);state.data[base..'_notes.json']='broken';storage=state.open();lib,warnings,fresh=storage:load()
check(storage.blocked);check(not fresh);local bad=state.data[base..'_notes.json'];check(not storage:save(lib));eq(state.data[base..'_notes.json'],bad)
state=fixture(active);state.data[base..'_notes.json']=nil;storage=state.open();lib,warnings,fresh=storage:load();check(storage.blocked);check(not storage:save(lib))
state=fixture();state.data[base..'_binds.json']=active[base..'_binds.json'];storage=state.open();lib,warnings,fresh=storage:load();check(storage.blocked)
state=fixture();state.data[base..'_library.json']='broken';storage=state.open();lib,warnings,fresh=storage:load();check(storage.blocked);check(not storage:save(lib))

-- An edit outside PA is not overwritten by a stale in-memory copy.
state=fixture(active);storage=state.open();lib=storage:load();state.data[base..'_binds.json']='external edit';lib.bindings[1].name='Local edit'
check(not storage:save(lib));eq(state.data[base..'_binds.json'],'external edit')
state=fixture(active);storage=state.open();lib=storage:load();state.data[base..'_notes.json']='external note'
lib.bindings[1].name='Local edit';lib.profile.name='Local profile'
check(not storage:save(lib));eq(state.data[base..'_notes.json'],'external note')

-- Inject a process/power loss before each filesystem mutation during both the
-- initial migration and a three-file edit. Restart must recover a complete state.
local changed=model.copy(original);changed.profile.name='Changed_Officer';changed.bindings[1].name='Изменённый бинд';changed.notes[1].body='Изменённая заметка'
local probes=0
local recoverySeeds={};local seenRecovery={}
for _,migration in ipairs({true,false})do
    local baseline=migration and{[base..'_library.json']=legacy}or active
    local probe=fixture(baseline);local writer=probe.open();writer:load();check(writer:save(migration and original or changed))
    local operations=probe.changes
    for failure=1,operations+1 do
        state=fixture(baseline);storage=state.open();storage:load();state.crashAt=failure
        local saved=storage:save(migration and original or changed)
        local decision=state.data[base..'_files_pending.json']
        if decision then
            local tx=TEST_JSON_DECODE(decision);local key=tostring(migration)..':'..tx.phase..':'..tostring(state.data[base..'_binds.json'])
            if not seenRecovery[key]then recoverySeeds[#recoverySeeds+1]=model.copy(state.data);seenRecovery[key]=true end
        end
        state.off=false;state.crashAt=nil
        local restarted=state.open();local recovered,notes,isFresh=restarted:load()
        check(not restarted.blocked,'restart blocked at '..failure..': '..tostring(restarted.blocked))
        if isFresh then check(restarted:save(recovered))end
        if migration then coherent(state,original)
        elseif recovered.profile.name==changed.profile.name then coherent(state,changed)
        else coherent(state,original)end
        eq(state.data[base..'_library.json'],legacy)
        probes=probes+1
    end
end
check(probes>50)

-- A second interruption during recovery itself is also repeatable.
local recoveryProbes=0
for _,seed in ipairs(recoverySeeds)do
    local probe=fixture(seed);local restarted=probe.open();local recovered,_,fresh=restarted:load()
    check(not restarted.blocked);local steps=probe.changes
    for failure=1,steps do
        state=fixture(seed);state.crashAt=failure;local interrupted=state.open();interrupted:load()
        state.off=false;state.crashAt=nil;restarted=state.open();recovered,_,fresh=restarted:load()
        check(not restarted.blocked,'second recovery failed: '..tostring(restarted.blocked))
        if fresh then check(restarted:save(recovered))end
        coherent(state,recovered.profile.name==changed.profile.name and changed or original)
        eq(state.data[base..'_library.json'],legacy);recoveryProbes=recoveryProbes+1
    end
end
check(recoveryProbes>30)

-- Short writes are detected before commit, including both transaction decisions.
local probe=fixture(active);storage=probe.open();storage:load();check(storage:save(changed))
for failure=1,probe.changes do
    state=fixture(active);storage=state.open();storage:load();state.partialAt=failure
    storage:save(changed);state.partialAt=nil
    local restarted=state.open();lib=select(1,restarted:load());check(not restarted.blocked)
    coherent(state,lib.profile.name==changed.profile.name and changed or original)
end

-- Tampered recovery copies/metadata are detected before touching destinations.
check(#recoverySeeds>0)
for _,seed in ipairs(recoverySeeds)do
    state=fixture(seed);local text=state.data[base..'_files_pending.json'];local tx=text and TEST_JSON_DECODE(text)
    if tx then
        local suffix=tx.phase=='committed'and'.pa26-next'or'.pa26-previous';local changedCopy
        for kind,row in pairs(tx.files)do if tx.phase=='committed'or row.had_original then changedCopy=base..'_'..kind..'.json'..suffix;break end end
        if changedCopy then
            state.data[changedCopy]=state.data[changedCopy]..' ';local before=model.copy(state.data)
            storage=state.open();storage:load();check(storage.blocked);check(not storage:save(original))
            for _,kind in ipairs({'binds','notes','settings'})do eq(state.data[base..'_'..kind..'.json'],before[base..'_'..kind..'.json'])end
        end
    end
end
state=fixture(active);state.data[base..'_files_pending.json']=json.encode({format='police-assistant.storage-transaction',schema=1,phase='committed',files={['../../foreign']={had_original=false}}})
storage=state.open();storage:load();check(storage.blocked);coherent(state,original)
local unknown=TEST_JSON_DECODE(legacy);unknown.future_private_data='preserve me'
state=fixture({[base..'_library.json']=json.encode(unknown)});storage=state.open();storage:load();check(storage.blocked)
check(not storage:save(original));eq(TEST_JSON_DECODE(state.data[base..'_library.json']).future_private_data,'preserve me')

-- A transient failure is retryable without restarting or mixing in-memory data.
state=fixture(active);storage=state.open();lib=storage:load();state.failAt=14
local saved=storage:save(changed);if not saved then coherent(state,original);state.failAt=nil;check(storage:save(changed))end
coherent(state,changed)

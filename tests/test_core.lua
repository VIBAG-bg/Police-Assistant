local core = require 'pa26_core'
local cfg = core.defaults()
check(core.validateSettings(cfg))
eq(cfg.main.demo_mode, true)
eq(#core.actions, 6)
local independent = core.defaults()
cfg.cuff.command = '/changed {id}'
eq(independent.cuff.command, '/cuff {id}')
cfg = core.defaults()

for _, bad in ipairs({0/0, math.huge, -math.huge, '8', false, {}, 2.9, 12.1}) do
    local c = core.defaults()
    c.main.max_distance = bad
    check(not core.validateSettings(c))
end
for _, bad in ipairs({999, 5001, 1500.5, 0/0, math.huge}) do
    local c = core.defaults()
    c.main.interval_ms = bad
    check(not core.validateSettings(c))
end
for _, bound in ipairs({3, 12}) do
    local c = core.defaults(); c.main.max_distance = bound; check(core.validateSettings(c))
end
for _, bad in ipairs({'false', 0, {}}) do
    local c = core.defaults(); c.main.demo_mode = bad; check(not core.validateSettings(c))
end
check(not core.validateSettings(nil))
check(not core.validateSettings({main = 'bad'}))

for _, a in ipairs(core.actions) do
    if cfg[a.key].enabled then
        local plan = assert(core.prepareAction(cfg[a.key], 1003, codec))
        for _, wire in ipairs(plan.wire) do check(#wire <= 127) end
    else check(not core.prepareAction(cfg[a.key],1003,codec))end
end
-- A user's explicitly configured legacy command remains editable/supported.
cfg.wanted.enabled=true;cfg.wanted.command='/wanted {id}'
local lines = assert(core.compileAction(cfg.wanted, 0))
eq(lines[3], '/wanted 0')
eq(assert(core.compileAction(cfg.wanted, 1003))[3], '/wanted 1003')
for _, bad in ipairs({-1, 1004, 3.5, 0/0, math.huge, '42', false}) do
    check(not core.compileAction(cfg.wanted, bad))
end
check(not core.compileAction(cfg.wanted, nil))
for _, command in ipairs({'/cuff 17', '/cuff {id} extra', '/cuff {id}\n/kill',
    '/cuff {id}\0', '/123 {id}', '/cuff{id}', '/cuff {ID}', '/cuff {id} {id}'}) do
    check(not core.validateAction({me = 'ok', do_text = '', command = command}))
end
for _, command in ipairs({'', '/cuff {id}', '/a_2 {id}'}) do
    check(core.validateAction({me = 'ok', do_text = '', command = command}))
end
for _, phrase in ipairs({'\nabc', 'abc\n', 'abc\r/other', 'a\0b', 'a\tb', string.char(127),
    string.char(0xC0, 0xAF), string.char(0xED, 0xA0, 0x80), string.char(0xF4, 0x90, 0x80, 0x80),
    string.char(0xD0)}) do
    check(not core.validateAction({me = phrase, do_text = '', command = ''}))
end
eq(assert(core.validateAction({me = '  100% ready {id}  ', do_text = '', command = ''})).me, '100% ready {id}')
check(not core.validateAction({me = false, do_text = '', command = ''}))
check(not core.validateAction({enabled = true, me = '', do_text = '', command = ''}))
check(core.validateAction({enabled = false, me = '', do_text = '', command = ''}))
check(not core.compileAction({enabled = false, me = 'ok', do_text = '', command = ''}, 1))

for _, s in ipairs({'ascii', 'кириллица', '😀', '', 'é'}) do check(core.validUtf8(s)) end
for _, b in ipairs({0x80, 0xC0, 0xC1, 0xF5, 0xFF}) do check(not core.validUtf8(string.char(b))) end
check(core.encodeWire('/me ' .. string.rep('я', 123), codec))
check(not core.encodeWire('/me ' .. string.rep('я', 124), codec))
check(core.encodeWire('/me ' .. string.rep('a', 123), codec))
check(not core.encodeWire('/me ' .. string.rep('a', 124), codec))
check(not core.encodeWire('/me 😀', codec))
check(not core.encodeWire('/me ok', {encode = function() return 'dropped' end, decode = function() return 'wrong' end}))
check(not core.encodeWire('/me ok', {}))
check(not core.encodeWire('/me ok', nil))
check(not core.encodeWire('/me ok', {encode = function() error('bad codec') end, decode = codec.decode}))

local raw = core.defaults()
raw.main.menu_key, raw.main.max_distance, raw.main.demo_mode = '120', '8', 'false'
local normalized, warnings = core.normalizeConfig(raw)
eq(normalized.main.demo_mode, false); eq(#warnings, 0)
raw.main.max_distance = 'nan'
normalized, warnings = core.normalizeConfig(raw)
eq(normalized.main.demo_mode, true); eq(normalized.main.max_distance, 8); check(#warnings > 0)
raw = core.defaults(); raw.main = 'broken'
normalized, warnings = core.normalizeConfig(raw)
eq(normalized.main.demo_mode, true); check(#warnings > 0)
raw = core.defaults(); raw.cuff = nil; raw.main.demo_mode = false
normalized, warnings = core.normalizeConfig(raw)
eq(normalized.cuff.enabled, false); eq(normalized.main.demo_mode, true)
raw = core.defaults(); raw.cuff.enabled = 'false'
normalized, warnings = core.normalizeConfig(raw)
eq(normalized.cuff.enabled, false); eq(#warnings, 0)
raw.cuff.enabled = 'no'
normalized, warnings = core.normalizeConfig(raw)
eq(normalized.cuff.enabled, false); check(#warnings > 0)
raw = core.defaults(); raw.main.schema = 99; raw.main.demo_mode = false
normalized, warnings = core.normalizeConfig(raw)
eq(normalized.main.demo_mode, true); check(#warnings > 0)

local visible = {captured = true, exists = true, alive = true, local_alive = true,
    on_screen = true, streamed = true, id_match = true, connected = true,
    line_of_sight = true, distance = 8, id = 0}
check(core.targetAllowed(visible, 8))
for _, key in ipairs({'captured', 'exists', 'alive', 'local_alive', 'on_screen',
    'streamed', 'id_match', 'connected', 'line_of_sight'}) do
    for _, bad in ipairs({false, 0, 'true', {}}) do
        visible[key] = bad; check(not core.targetAllowed(visible, 8))
    end
    visible[key] = nil; check(not core.targetAllowed(visible, 8)); visible[key] = true
end
for _, bad in ipairs({-1, 8.01, 0/0, math.huge, '1'}) do
    visible.distance = bad; check(not core.targetAllowed(visible, 8))
end
visible.distance = 8
for _, bad in ipairs({0/0, math.huge, '8', 13, 2}) do check(not core.targetAllowed(visible, bad)) end
check(not core.targetAllowed(visible, nil))
visible.id = 1004; check(not core.targetAllowed(visible, 8))

eq(core.elapsed(50, 4294967290), 56)
eq(core.elapsed(-2147483640, 2147483640), 16)
eq(core.elapsed(1500, 1000), 500)
eq(core.elapsed(999, 1000), nil)
eq(core.elapsed(1e100, 0), nil)
eq(core.elapsed(1.5, 0), nil)
for i = 1, 6 do
    local angle = -math.pi / 2 + (i - 1) * 2 * math.pi / 6
    for _, radius in ipairs({38, 80, 195}) do
        eq(core.wheelIndex(math.cos(angle) * radius, math.sin(angle) * radius, 6, 37, 205), i)
    end
end
eq(core.wheelIndex(0, 0, 6, 37, 205), nil)
eq(core.wheelIndex(0, 37, 6, 37, 205), nil)
eq(core.wheelIndex(206, 0, 6, 37, 205), nil)
eq(core.wheelIndex(0/0, 0, 6, 37, 205), nil)
eq(core.wheelIndex(10, 10, 0, 0, 205), nil)

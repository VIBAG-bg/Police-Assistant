local core = require 'pa26_core'
local mod = require 'pa26_runtime'

local function fixture(demo)
    local s = {now = 10000, valid = true, ctx = {session = '127.0.0.1:7777', focused = true,
        paused = false, blocked = false, window = false, alive = true},
        target = {id = 37, ped = 99, name = 'Player_Name'}, sent = {}, logs = {}, attempts = 0}
    local function validate(expected)
        if s.validateError then error('API failure') end
        if not s.valid or expected.id ~= s.target.id or expected.ped ~= s.target.ped or
            expected.name ~= s.target.name then return nil end
        return {id = s.target.id, ped = s.target.ped, name = s.target.name}
    end
    local env = {now = function() if s.timerError then error('timer') end; return s.now end,
        context = function() if s.contextError then error('context') end; return s.ctx end,
        acquire = function() return s.valid and validate(s.target) or nil end,
        validate = validate, codec = codec, log = function(line) s.logs[#s.logs + 1] = line end,
        send = function(line)
            s.attempts = s.attempts + 1
            if s.sendError then error('send') end
            if s.sendFalse then return false end
            s.sent[#s.sent + 1] = {line = line, time = s.now}; return true
        end}
    local cfg = core.defaults(); cfg.main.demo_mode = demo == true
    cfg.wanted.enabled=true;cfg.wanted.command='/wanted {id}' -- explicit personal legacy fixture
    local r = mod.new(env, cfg)
    local function commit(index)
        check(r:openWheel())
        s.now = (s.now + 150) % 4294967296
        r:setChoice(index or 3)
        return r:commitWheel()
    end
    return r, s, commit
end

local r, s, commit = fixture()
check(commit(3)); r:step(); eq(#s.sent, 1)
eq(codec.decode(s.sent[1].line), '/me ' .. r.cfg.wanted.me)
s.now = s.now + 1499; r:step(); eq(#s.sent, 1)
s.now = s.now + 1; r:step(); eq(#s.sent, 2)
s.now = s.now + 1500; r:step(); eq(#s.sent, 3)
eq(codec.decode(s.sent[3].line), '/wanted 37'); eq(r.queue, nil)
check(not commit(3)); eq(#s.sent, 3)
s.now = s.now + 2000; check(commit(3)); r:step(); eq(#s.sent, 4)
check(not r:commitWheel(3)); eq(#s.sent, 4)

-- Every unsafe context cancels both a wheel and a queue, without waiting for the next due message.
for _, change in ipairs({
    {'focused', false}, {'paused', true}, {'blocked', true}, {'window', true},
    {'alive', false}, {'session', false}, {'session', 'other:7777'},
}) do
    r, s, commit = fixture()
    check(commit()); r:step()
    s.ctx[change[1]] = change[2]; s.now = s.now + 10; r:step()
    eq(r.queue, nil); eq(#s.sent, 1)
    r, s = fixture()
    check(r:openWheel())
    s.ctx[change[1]] = change[2]; r:step(); eq(r.wheel, nil)
end

-- Switching to demo during a queue is an immediate, durable cancellation.
r, s, commit = fixture()
check(commit()); r:step(); eq(#s.sent, 1)
check(r:setDemo(true)); eq(r.queue, nil)
s.now = s.now + 5000; r:step(); eq(#s.sent, 1)
check(r:openWheel()); s.now = s.now + 150; r:setChoice(3)
check(r:commitWheel()); r:step(); eq(#s.sent, 1)
check(r:openWheel()); r:setDemo(false); eq(r.wheel, nil)
check(not r:commitWheel(3)); eq(#s.sent, 1)
r, s, commit = fixture(true)
check(commit(3)); r:step(); eq(s.attempts, 0)
local mode = r.demo
check(r:preview(1, {enabled = true, me = 'новый текст 100%', do_text = '', command = ''}))
eq(r.demo, mode); eq(s.attempts, 0)
check(s.logs[#s.logs]:find('новый текст 100%%') ~= nil)

for _, identity in ipairs({'id', 'ped', 'name'}) do
    r, s, commit = fixture(); check(commit()); r:step()
    s.target[identity] = identity == 'name' and 'Other_Name' or 77
    s.now = s.now + 1; r:step(); eq(r.queue, nil); eq(#s.sent, 1)
    r, s = fixture(); check(r:openWheel())
    s.target[identity] = identity == 'name' and 'Other_Name' or 77
    r:step(); eq(r.wheel, nil)
end
r, s, commit = fixture(); check(commit()); s.valid = false
r:step(); eq(s.attempts, 0); eq(r.queue, nil)
r, s = fixture(); s.valid = false; check(r:openWheel()); eq(r.wheel.target,nil)
s.now=s.now+150; r:setChoice(3); eq(r.wheel.choice,nil)
check(not r:commitWheel(3)); eq(s.attempts,0); eq(r.queue,nil)
r, s, commit = fixture(); check(commit()); s.validateError = true
r:step(); eq(s.attempts, 0); eq(r.queue, nil)

for _, failure in ipairs({'sendError', 'sendFalse'}) do
    r, s, commit = fixture(); check(commit()); s[failure] = true
    r:step(); eq(s.attempts, 1); eq(r.queue, nil)
    s.now = s.now + 5000; r:step(); eq(s.attempts, 1) -- no retry
end
for _, failure in ipairs({'timerError', 'contextError'}) do
    r, s, commit = fixture(); check(commit()); s[failure] = true
    r:step(); eq(s.attempts, 0); eq(r.queue, nil)
end

r, s, commit = fixture()
r.cfg.wanted.do_text = 'emoji 😀'
check(not commit()); r:step(); eq(s.attempts, 0) -- entire action is prevalidated
r, s, commit = fixture(); r.cfg.wanted.enabled = false
check(not commit()); eq(s.attempts, 0)

r, s = fixture()
check(r:openWheel()); s.now = s.now + 50; r:setChoice(3)
check(not r:commitWheel()); eq(s.attempts, 0) -- tap
check(r:openWheel()); s.now = s.now + 150; r:setChoice(3); s.now = s.now + 251
check(not r:commitWheel()); eq(s.attempts, 0) -- stale frame
check(r:openWheel()); s.now = s.now + 150; r:setChoice(nil)
check(not r:commitWheel())
check(r:openWheel()); s.now = s.now + 120001; r:step(); check(r.wheel,'holding the wheel must not time out')
r:cancel('test cleanup')
r, s, commit = fixture(); check(commit())
s.now = s.now + 20001; r:step(); eq(s.attempts, 0); eq(r.queue, nil)

r, s, commit = fixture(); check(commit()); r:step()
s.now = s.now - 1; r:step(); eq(r.queue, nil); eq(#s.sent, 1)
r, s, commit = fixture(); s.now = 4294967200
check(commit()); r:step(); eq(#s.sent, 1)
s.now = s.now + 1500; r:step(); eq(#s.sent, 2)
r, s, commit = fixture(); check(commit())
local c = core.defaults(); c.main.demo_mode = false
check(r:applyConfig(c)); eq(r.queue, nil); r:step(); eq(s.attempts, 0)
c.cuff.me = '😀'; check(not r:applyConfig(c)); eq(s.attempts, 0)

-- Uneven frame times cannot burst all remaining lines in a single update.
r, s, commit = fixture(); check(commit())
for _ = 1, 150 do s.now = s.now + 37; r:step() end
eq(#s.sent, 3)
for i = 2, #s.sent do check(s.sent[i].time - s.sent[i - 1].time >= 1500) end
r, s, commit = fixture(); check(commit()); r:step()
s.now = s.now + 10000; r:step(); eq(#s.sent, 2)
r:step(); eq(#s.sent, 2)

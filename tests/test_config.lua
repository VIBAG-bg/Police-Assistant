local core = require 'pa26_core'
local storage = require 'pa26_config'
local cfg = core.defaults()
local text = assert(storage.serialize(cfg))
local packaged, packageNotes = storage.load('moonloader/config/police_assistant_2026.ini')
eq(#packageNotes, 0); eq(packaged.main.demo_mode, false)
eq(assert(storage.serialize(packaged)), text)
local raw = assert(storage.parse('\239\187\191' .. text:gsub('\n', '\r\n')))
local roundtrip, warnings = core.normalizeConfig(raw)
eq(#warnings, 0)
eq(roundtrip.cuff.command, '/cuff {id}')
eq(roundtrip.main.demo_mode, false)
for _, invalid in ipairs({'', 'x=1', '[main]\nx=1\nx=2',
    '[main]\na=1\n[main]\nb=2', '[main]\nnot-a-key', '[main]\nx=a\0b',
    '[main]\nx=\255', string.rep('a', storage.MAX_BYTES + 1)}) do
    check(not storage.parse(invalid))
end
raw = assert(storage.parse('[main]\nschema=2\n[x]\nme=123\ncommand=a=b'))
eq(raw.x.me, '123'); eq(raw.x.command, 'a=b')
check(not storage.serialize({main = {}}))

local function fake(files, fail)
    local fs = {}
    fs.exists = function(path) return files[path] ~= nil end
    fs.read = function(path) return files[path] end
    fs.write = function(path, value)
        if fail == 'write' then return nil end
        files[path] = fail == 'partial' and value:sub(1, 8) or value
        return true
    end
    fs.remove = function(path)
        if fail == 'remove_backup' and path == 'config.bak' then return nil end
        files[path] = nil
        return true
    end
    fs.rename = function(from, to)
        if files[to] or not files[from] then return nil end
        if (fail == 'backup' and from == 'config') or
            ((fail == 'replace' or fail == 'rollback') and from == 'config.tmp') or
            (fail == 'rollback' and from == 'config.rollback') then return nil end
        files[to], files[from] = files[from], nil
        return true
    end
    return fs
end
for _, failure in ipairs({'write', 'partial', 'backup', 'replace'}) do
    local files = {config = 'original', ['config.bak'] = 'older'}
    local ok = storage.save('config', cfg, fake(files, failure))
    check(not ok)
    eq(files.config, 'original', failure .. ' must preserve the original')
    eq(files['config.bak'], 'older', failure .. ' must preserve the backup')
end
local files = {config = 'original'}
check(not storage.save('config', cfg, fake(files, 'rollback')))
eq(files['config.rollback'], 'original')
files = {config = text .. '; previous\n', ['config.bak'] = 'older'}
check(storage.save('config', cfg, fake(files)))
eq(files.config, text); eq(files['config.bak'], text .. '; previous\n'); eq(files['config.tmp'], nil)
files = {config = text .. '; previous\n', ['config.bak'] = 'older'}
local saved, note = storage.save('config', cfg, fake(files, 'remove_backup'))
check(saved); check(note ~= nil); eq(files.config, text)
eq(files['config.rollback'], text .. '; previous\n'); eq(files['config.bak'], 'older')
check(storage.save('config', cfg, fake(files))) -- completes prior backup first
eq(files['config.rollback'], nil)
files = {config = 'broken', ['config.bak'] = text}
check(storage.save('config', cfg, fake(files)))
eq(files['config.bak'], text); eq(files['config.rejected'], 'broken')
files = {}
check(storage.save('config', cfg, fake(files)))
eq(files.config, text)
files = {config = 'broken', ['config.bak'] = text}
local loaded, notes = storage.load('config', fake(files))
eq(loaded.main.demo_mode, true); check(#notes > 0); eq(files.config, 'broken')
files = {['config.rollback'] = text, ['config.tmp'] = 'unfinished'}
loaded, notes = storage.load('config', fake(files))
eq(loaded.main.demo_mode, true); check(#notes > 0)
check(storage.save('config', cfg, fake(files)))
eq(files.config, text); eq(files['config.rollback'], nil)
files = {config = 'broken'}
loaded, notes = storage.load('config', fake(files))
eq(loaded.main.demo_mode, true); check(#notes > 0)
files = {config = text}
loaded, notes = storage.load('config', fake(files))
eq(#notes, 0)
local throwing = fake(files)
throwing.write = function() error('disk failure') end
check(not storage.save('config', cfg, throwing)); eq(files.config, text)

-- Exercise actual Windows/LuaJIT io.write, flush, close and rename operations.
local path = assert(TEST_TEMP_PATH)
check(storage.save(path, cfg))
eq(storage.load(path).cuff.command, '/cuff {id}')
cfg.cuff.me = 'проверил настройки'
check(storage.save(path, cfg))
eq(storage.load(path).cuff.me, cfg.cuff.me)
check(storage.fs.exists(path .. '.bak'))
eq(assert(storage.fs.read(path .. '.bak')), text)

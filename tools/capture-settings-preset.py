"""Read saved game settings, validate, and export only the public author settings.

Never reads binds, notes, logs, or personal knowledge and never writes to the game.
Run with --config pointing to the installed MoonLoader/config directory.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import time
from lupa.luajit21 import LuaRuntime

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--config', type=Path, required=True)
parser.add_argument('--revision', required=True)
args = parser.parse_args()
paths = {'settings': args.config / 'police_assistant_2026_settings.json',
         'config': args.config / 'police_assistant_2026.ini'}
pending = [args.config / ('police_assistant_2026' + tail + suffix)
           for tail in ('_files_pending.json', '_preset_pending.json')
           for suffix in ('', '.bak', '.rollback')]
for attempt in range(3):
    assert not any(p.exists() for p in pending), 'An unfinished personal save needs recovery first.'
    before = {key: path.read_bytes() for key, path in paths.items()}
    time.sleep(.3)
    if before == {key: path.read_bytes() for key, path in paths.items()}:
        break
else:
    raise SystemExit('Settings are being saved; capture again after saving PA.')
lua = LuaRuntime(encoding='utf-8', unpack_returned_tuples=True)
lua.globals().QA_LIB = (root / 'moonloader/lib/?.lua').as_posix()
lua.execute("package.path=QA_LIB..';'..package.path")
def to_lua(value):
    if isinstance(value, dict):
        return lua.table_from({key: to_lua(item) for key, item in value.items()})
    if isinstance(value, list):
        return lua.table_from([to_lua(item) for item in value])
    return value
def plain(value):
    if not hasattr(value, 'items'):
        return value
    result = {key: plain(item) for key, item in value.items()}
    if result and set(result) == set(range(1, len(result) + 1)):
        return [result[i] for i in range(1, len(result) + 1)]
    return result
lua.globals().SOURCE_SETTINGS = to_lua(json.loads(before['settings'].decode('utf-8-sig')))
lua.globals().SOURCE_INI = before['config'].decode('utf-8-sig')
payload = plain(lua.execute("""
local model=require 'pa26_bindings';local files=require 'pa26_user_files'
local core=require 'pa26_core';local author=require 'pa26_author_presets'
local cfg,warnings=core.normalizeConfig(assert(require('pa26_config').parse(SOURCE_INI)))
assert(#warnings==0,table.concat(warnings,', '));assert(core.validateSettings(cfg))
local stock=files.partition(model.defaults(core.defaults()))
local s=assert(files.validate('settings',SOURCE_SETTINGS,cfg))
for key in pairs(author.protected)do s.data[key]=model.copy(stock.settings.data[key])end
s.data.assist.history=model.copy(stock.settings.data.assist.history)
s.data.assist.evidence.screens_dir=stock.settings.data.assist.evidence.screens_dir
s.data.settings.updates=model.copy(stock.settings.data.settings.updates)
-- Fresh installs always use real mode. Applying a preset preserves the recipient's mode.
cfg.main.demo_mode=false
local payload=assert(author.validate('settings',{
 format='police-assistant.author-settings',schema=1,settings=s,config=cfg}))
assert(payload.settings.data.profile.name=='')
assert(#payload.settings.data.partners==0 and #payload.settings.data.wanted_reminders==0)
assert(author.equal(payload.settings.data.assist.history,stock.settings.data.assist.history))
return payload
"""))
assert before == {key: path.read_bytes() for key, path in paths.items()}, 'Source changed during validation.'
assert not any(p.exists() for p in pending), 'A personal save started during validation.'
output = root / 'presets/pa-settings.json'
old = output.read_bytes()
protected = [root / 'presets' / name for name in ('pa-binds.json', 'baseline.json')]
untouched = {path: path.read_bytes() for path in protected}
output.write_text(json.dumps(payload, ensure_ascii=False, indent=2, allow_nan=False) + '\n',
                  encoding='utf-8', newline='\n')
manifest_path = root / 'presets/manifest.json'
manifest = json.loads(manifest_path.read_text('utf-8-sig'))
manifest['settings_revision'] = args.revision
manifest['files']['pa-settings.json'] = {
    'sha256': hashlib.sha256(output.read_bytes()).hexdigest(), 'size': output.stat().st_size}
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
install_path = root / 'INSTALL_MANIFEST.json'
install = json.loads(install_path.read_text('utf-8-sig'))
for row in install['preset_files']:
    row['sha256'] = hashlib.sha256((root / row['path']).read_bytes()).hexdigest()
install_path.write_text(json.dumps(install, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
assert all(path.read_bytes() == content for path, content in untouched.items())
report = {'revision': args.revision, 'captured_at_utc': datetime.now(timezone.utc).isoformat(),
          'source_sha256': {key: hashlib.sha256(value).hexdigest() for key, value in before.items()},
          'previous_sha256': hashlib.sha256(old).hexdigest(),
          'public_sha256': manifest['files']['pa-settings.json']['sha256'],
          'game_written': False, 'binds_changed': False, 'notes_read': False,
          'private_data_excluded': ['profile', 'partners', 'wanted_reminders', 'filters',
                                   'assist.history', 'local screenshot folder', 'update preferences',
                                   'notes', 'personal knowledge'],
          'fresh_demo_mode': False}
(root / 'tests/SETTINGS_CAPTURE_20261031.json').write_text(
    json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Public settings captured and validated; binds, stock notes, and installed game unchanged.')
print('SHA-256: ' + report['public_sha256'])

"""Validate the saved bind document and refresh only the public bind preset.

Settings, notes, profiles and the installed game are never changed.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import time
from lupa.luajit21 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--config', type=Path, required=True)
parser.add_argument('--revision', required=True)
args = parser.parse_args()
source_path = args.config / 'police_assistant_2026_binds.json'
pending = [args.config / ('police_assistant_2026' + suffix + tail)
           for suffix in ('_files_pending.json', '_preset_pending.json')
           for tail in ('', '.bak', '.rollback')]
for attempt in range(3):
    assert not any(p.exists() for p in pending), 'Recover an unfinished save first.'
    source = source_path.read_bytes()
    assert len(source) <= 1048576, 'Bind document is too large.'
    time.sleep(.3)
    if source == source_path.read_bytes():
        break
else:
    raise SystemExit('Binds are being edited; save them and repeat capture.')
lua = LuaRuntime(encoding='utf-8', unpack_returned_tuples=True)
lua.globals().QA_LIB = (ROOT / 'moonloader/lib/?.lua').as_posix()
lua.execute("package.path=QA_LIB..';'..package.path")


def to_lua(value):
    if isinstance(value, dict):
        return lua.table_from({k: to_lua(v) for k, v in value.items()})
    if isinstance(value, list):
        return lua.table_from([to_lua(v) for v in value])
    return value


def plain(value):
    if not hasattr(value, 'items'):
        return value
    result = {k: plain(v) for k, v in value.items()}
    if result and set(result) == set(range(1, len(result) + 1)):
        return [result[i] for i in range(1, len(result) + 1)]
    return result


lua.globals().SOURCE = to_lua(json.loads(source.decode('utf-8-sig')))
payload = plain(lua.execute("""
local p=assert(require('pa26_user_files').validate('binds',SOURCE))
for _,row in ipairs(p.bindings)do assert(require('pa26_binder').parse(row.script))end
return p
"""))
assert source == source_path.read_bytes() and not any(p.exists() for p in pending), 'Save changed during capture.'
protected = {p: p.read_bytes() for p in (ROOT / 'presets/pa-settings.json', ROOT / 'presets/baseline.json')}
output = ROOT / 'presets/pa-binds.json'
previous = output.read_bytes()
output.write_text(json.dumps(payload, ensure_ascii=False, indent=2, allow_nan=False) + '\n', encoding='utf-8', newline='\n')
meta_path = ROOT / 'presets/manifest.json'
meta = json.loads(meta_path.read_text('utf-8-sig'))
meta['binds_revision'] = args.revision
meta['files']['pa-binds.json'] = {'sha256': hashlib.sha256(output.read_bytes()).hexdigest(), 'size': output.stat().st_size}
meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
install_path = ROOT / 'INSTALL_MANIFEST.json'
install = json.loads(install_path.read_text('utf-8-sig'))
for row in install['preset_files']:
    row['sha256'] = hashlib.sha256((ROOT / row['path']).read_bytes()).hexdigest()
install_path.write_text(json.dumps(install, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
assert all(p.read_bytes() == value for p, value in protected.items())
assert source == source_path.read_bytes()
report = {'status': 'validated', 'revision': args.revision, 'utc': datetime.now(timezone.utc).isoformat(),
          'binds': len(payload['bindings']), 'source_sha256': hashlib.sha256(source).hexdigest(),
          'previous_public_sha256': hashlib.sha256(previous).hexdigest(),
          'public_sha256': meta['files']['pa-binds.json']['sha256'],
          'settings_changed': False, 'notes_read': False, 'game_written': False}
(ROOT / 'tests/BINDS_CAPTURE_20261101.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(f"Captured {report['binds']} saved binds; settings, stock notes and installed game unchanged.")
print('SHA-256: ' + report['public_sha256'])

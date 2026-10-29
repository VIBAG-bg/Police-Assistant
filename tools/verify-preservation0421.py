"""Compare 0.42.0 library leaves, allowing only exact stock text upgrades."""
from pathlib import Path
import argparse
import hashlib
import json
from lupa.luajit21 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', type=Path, required=True)
args = parser.parse_args()
baseline = args.baseline.resolve()


def runtime(root):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path=.....'/moonloader/lib/?.lua;'..package.path", root.as_posix())
    return lua


def convert(value):
    if hasattr(value, 'items'):
        return {str(k): convert(v) for k, v in value.items()}
    return value


def leaves(value, path=''):
    if isinstance(value, dict):
        if not value:
            return {path: ('empty',)}
        result = {}
        for key, child in value.items():
            result.update(leaves(child, path + '.' + key if path else key))
        return result
    return {path: (type(value).__name__, value)}


old, new = runtime(baseline), runtime(ROOT)
base = old.execute("local c=require 'pa26_core';local m=require 'pa26_bindings';return assert(m.validate(m.defaults(c.defaults()),c.defaults()))")
stock = leaves(convert(base))
upgrades = {
    'vehicle.description_template', 'vehicle.copilot.templates.stop_order',
    'vehicle.copilot.templates.tire', 'vehicle.copilot.templates.return_car',
    'patrol_session.start_template', 'patrol_session.resume_template',
    'patrol_session.periodic_template', 'patrol_session.finish_template',
}


def transfer(value):
    if hasattr(value, 'items'):
        table = new.table()
        for key, child in value.items():
            table[key] = transfer(child)
        return table
    return value


checked = 0
accepted = set()
for custom in (False, True):
    if custom:
        old.globals().qa_library = base
        old.execute("""
          qa_library.profile.name='Private_Name';qa_library.profile.callsign='PERSONAL';
          qa_library.notes[1].body='PRIVATE NOTE MUST STAY';
          qa_library.partners={{id=1,nickname='Partner_Name',callsign='PERSONAL'}};
          qa_library.next_partner_id=2;
          qa_library.vehicle.copilot.enabled=false;
          qa_library.vehicle.copilot.templates.wanted_rp='/me моя личная отыгровка.';
          qa_library.vehicle.copilot.templates.risk_single='Личное требование.';
          qa_library.vehicle.copilot.templates.stop_order='Моё требование.';
          qa_library.vehicle.copilot.templates.tire='Моё предупреждение.';
          qa_library.vehicle.copilot.templates.return_car='Мой текст возврата.';
          qa_library.vehicle.description_template='Моя машина {model}';
          qa_library.patrol_session.unit='MY-17';
          qa_library.patrol_session.start_template='Личное начало {unit}.';
          qa_library.patrol_session.resume_template='Личное продолжение {unit}.';
          qa_library.patrol_session.periodic_template='Личный доклад {unit}.';
          qa_library.patrol_session.finish_template='Личное завершение {unit}.';
          qa_library.settings.wheel_names={citizen='Своя секция'};
          qa_library.settings.wheel_child_limit=10;
        """)
    result = new.execute("local m=require 'pa26_bindings';local c=require 'pa26_core';return m.validate(...,c.defaults())", transfer(base))
    valid, error = result if isinstance(result, tuple) else (result, None)
    assert valid, error
    before, after = leaves(convert(base)), leaves(convert(valid))
    changed = {k: (v, after.get(k)) for k, v in before.items() if after.get(k) != v}
    for key, (previous, current) in changed.items():
        assert key in upgrades and previous == stock.get(key), (key, previous, current)
        accepted.add(key)
    # Reloading an upgraded library must be idempotent.
    again = new.execute("local m=require 'pa26_bindings';local c=require 'pa26_core';return assert(m.validate(...,c.defaults()))", valid)
    assert leaves(convert(again)) == after, 'Migration must be idempotent'
    checked += len(before)

frozen = 'moonloader/lib/pa26_update_platform.lua'
unchanged = [frozen, 'moonloader/resource/pa26/updater/pa26-update.ps1',
             'cef/assets/hud/pa26-chat-endpoint.js', 'presets/pa-binds.json']
unchanged += [p.relative_to(baseline).as_posix() for p in (baseline / 'tools').glob('*.ps1') if 'build-' not in p.name]
for name in unchanged:
    assert (ROOT / name).read_bytes() == (baseline / name).read_bytes(), name

# Only the requested fresh-install recovery default changes in public settings.
# This does not rewrite an installed user's explicit recovery checkbox.
ini = 'moonloader/config/police_assistant_2026.ini'
assert (ROOT / ini).read_bytes() == (baseline / ini).read_bytes().replace(
    b'demo_after_recovery=true', b'demo_after_recovery=false')
for name in ('pa-settings.json', 'baseline.json'):
    relative = 'presets/' + name
    old_payload = json.loads((baseline / relative).read_text('utf-8-sig'))
    new_payload = json.loads((ROOT / relative).read_text('utf-8-sig'))
    old_payload['config']['recovery']['demo_after_recovery'] = False
    assert new_payload == old_payload, relative
manifest = json.loads((ROOT / 'presets/manifest.json').read_text('utf-8-sig'))
assert manifest['version'] == '0.42.1'
for name, row in manifest['files'].items():
    raw = (ROOT / 'presets' / name).read_bytes()
    assert len(raw) == row['size'] and hashlib.sha256(raw).hexdigest() == row['sha256']

report = {'status': 'passed', 'baseline': '0.42.0', 'legacy_leaf_checks': checked,
          'cases': ['stock', 'custom_profile_notes_contacts_templates_disabled_features_wheel_unit'],
          'accepted_exact_stock_upgrades': sorted(accepted), 'migration_idempotent': True,
          'public_preset_change': 'Only fresh-install demo_after_recovery defaults to false; binds and other preset values unchanged',
          'unchanged_files': sorted(set(unchanged)),
          'loader_sha256': hashlib.sha256((ROOT / frozen).read_bytes()).hexdigest(),
          'game_written': False}
(ROOT / 'tests/PRESERVATION0421.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report))

"""Offline LuaJIT 2.1 tests with real FFI and a real CP1251 codec.
Run: python -m pip install lupa && python tests/run_tests.py
MoonLoader/mimgui/SA:MP are simulated; this does not launch GTA.
"""
from pathlib import Path
import json
import argparse
import hashlib
import os
import sys
import uuid
from lupa.luajit21 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)

def encode_cp1251(value):
    return value.decode("utf-8").encode("cp1251")

def decode_cp1251(value):
    return value.decode("cp1251").encode("utf-8")

def runtime():
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    def to_python(value):
        if isinstance(value, bytes):
            return value.decode('utf-8')
        if hasattr(value, 'items'):
            pairs = list(value.items())
            if pairs and all(isinstance(k, int) for k, _ in pairs) and sorted(k for k, _ in pairs) == list(range(1, len(pairs) + 1)):
                return [to_python(value[i]) for i in range(1, len(pairs) + 1)]
            return {to_python(k): to_python(v) for k, v in pairs}
        return value
    def from_python(value):
        if isinstance(value, str):
            return value.encode('utf-8')
        if isinstance(value, (dict, list)):
            table = lua.table()
            items = value.items() if isinstance(value, dict) else enumerate(value, 1)
            for key, item in items:
                table[from_python(key)] = from_python(item)
            return table
        return value
    lua.globals()[b'TEST_JSON_ENCODE'] = lambda value: json.dumps(to_python(value), ensure_ascii=False, allow_nan=False).encode('utf-8')
    lua.globals()[b'TEST_JSON_DECODE'] = lambda value: from_python(json.loads(value.decode('utf-8')))
    lua.globals()[b'TEST_KNOWLEDGE_JSON'] = (ROOT / 'moonloader/resource/pa26/knowledge-base.json').read_bytes()
    lua.globals()[b'TEST_KNOWLEDGE_POLICY_JSON'] = (ROOT / 'moonloader/resource/pa26/knowledge-policy.json').read_bytes()
    lua.globals()[b"TEST_ENCODE"] = encode_cp1251
    lua.globals()[b"TEST_DECODE"] = decode_cp1251
    lua.execute(b"package.path = 'moonloader/lib/?.lua;tests/?.lua;' .. package.path")
    lua.execute(b"""
        TEST_CHECKS = 0
        function check(condition, message)
            TEST_CHECKS = TEST_CHECKS + 1
            assert(condition, message or ('check ' .. TEST_CHECKS .. '\\n' .. debug.traceback()))
        end
        function eq(a, b, message) check(a == b, message) end
        codec = {
            encode = function(s) return TEST_ENCODE(s) end,
            decode = function(s) return TEST_DECODE(s) end,
        }
    """)
    return lua

syntax_lua = runtime()
files = sorted((ROOT / "moonloader").rglob("*.lua")) + sorted(
    file for file in (ROOT / "tests").rglob("*.lua") if "install-sandbox" not in file.parts and "update-sandbox" not in file.parts
)
for file in files:
    syntax_lua.execute(b"local f,e = loadfile(...); assert(f,e)", file.as_posix().encode("utf-8"))
tested_sources = {file.relative_to(ROOT).as_posix(): hashlib.sha256(file.read_bytes()).hexdigest() for file in files}
sensitive_resources = [*(ROOT / "moonloader/resource/pa26").glob("knowledge*.json"), ROOT / "moonloader/config/police_assistant_2026.ini"]
sensitive_resources.extend((ROOT / 'cef/assets/hud').glob('*.js'))
sensitive_resources.extend((ROOT / 'moonloader/resource/pa26/updater').glob('*.ps1'))
tested_resources = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sensitive_resources}
print(f"LuaJIT syntax: {len(files)} files OK")

results = []
test_names = ['test_core.lua', 'test_config.lua', 'test_runtime.lua', 'test_bindings.lua', 'test_library.lua', 'test_smoke.lua', 'test_hud.lua', 'test_menu.lua', 'test_targeting.lua', 'test_studio.lua', 'test_interaction.lua', 'test_binding_ux.lua', 'test_editor_access.lua', 'test_variables.lua', 'test_settings_tabs.lua', 'test_accent.lua', 'test_draft_lifecycle.lua', 'test_window_layout.lua', 'test_step_editor.lua', 'test_notices.lua', 'test_target_notices.lua', 'test_binder_controls.lua', 'test_binding_dialogs.lua', 'test_shortcut_dialog.lua', 'test_gui_key_capture.lua', 'test_category_wheel.lua', 'test_category_wheel_ui.lua', 'test_alerts.lua', 'test_alerts_ui.lua', 'test_confirmation_input.lua', 'test_service_preferences.lua', 'test_patrol.lua', 'test_weapon_roleplay.lua', 'test_taser.lua', 'test_critical_reports.lua', 'test_service_ui.lua', 'test_radio_guard.lua', 'test_weapon_warning.lua', 'test_service_notifications.lua', 'test_notification_ui.lua', 'test_chat_input.lua', 'test_quick_alert_keys.lua', 'test_autosave.lua', 'test_wheel_labels.lua', 'test_knowledge.lua', 'test_knowledge_forms.lua', 'test_knowledge_ui.lua', 'test_knowledge_updates_ui.lua', 'test_ui_content_regressions.lua', 'test_knowledge_edits.lua', 'test_knowledge_editor_ui.lua', 'test_aim_warning_layout.lua']
test_names.append('test_choice_controls.lua')
test_names.extend(['test_native_chat_live.lua','test_reader_notes_ux.lua'])
test_names.extend(['test_chat_bridge.lua','test_cef_integration.lua'])
test_names.append('test_chat_bridge_startup.lua')
test_names.append('test_keyboard_layout.lua')
test_names.append('test_aim_selection.lua')
test_names.append('test_chat_text.lua')
test_names.extend(['test_feedback.lua','test_helpers_shortcut.lua','test_scroll_bounds.lua','test_vehicle_names.lua','test_general_megaphone.lua','test_general_megaphone_ui.lua'])
test_names.append('test_menu_key.lua')
test_names.append('test_notes_reference_navigation.lua')
test_names.extend(['test_ui_recovery.lua','test_recovery_guard.lua'])
test_names.extend(['test_patrol_session.lua','test_patrol_session_ui.lua','test_patrol_events.lua','test_patrol_event_ui.lua'])
test_names.extend(['test_identity.lua','test_identity_ui.lua'])
test_names.extend(['test_case_forms.lua','test_case_ui.lua'])
test_names.extend(['test_mark_forms.lua','test_mark_ui.lua'])
test_names.extend(['test_patrol_notices.lua','test_patrol_notice_ui.lua'])
test_names.extend(['test_operations.lua','test_operations_ui.lua'])
test_names.append('test_radio_codes.lua')
test_names.append('test_followups.lua')
test_names.append('test_radio_patrol_context.lua')
test_names.append('test_procedure_access.lua')
test_names.append('test_knowledge_departments.lua')
test_names.append('test_force_followup.lua')
test_names.extend(['test_vehicle.lua','test_vehicle_world.lua','test_live_passport.lua','test_command_taser.lua','test_weapon_holster.lua','test_radio_segments.lua','test_live_service_ui.lua'])
test_names.append('test_knowledge_editions.lua')
test_names.extend(['test_assist_settings.lua','test_evidence.lua','test_evidence_files.lua','test_assist_ui.lua','test_megaphone.lua','test_megaphone_ui.lua'])
test_names.append('test_interaction_preferences.lua')
test_names.extend(['test_rp_text.lua','test_rp_integration.lua','test_rp_ui.lua','test_server_commands.lua'])

test_names.extend(['test_russian_text.lua','test_rp_presets_ui.lua'])

test_names.append('test_map_locations.lua')
test_names.extend(['test_nearby.lua','test_vehicle_selection.lua'])
test_names.extend(['test_wanted_forms.lua','test_user_files.lua','test_user_files_ui.lua','test_resume_acceptance.lua'])
test_names.extend(['test_wanted_accounts.lua','test_wanted_remote.lua','test_wanted_passport_memory.lua','test_wanted_todo.lua'])
parser = argparse.ArgumentParser()
test_names.extend(['test_cef_assets.lua','test_hud_close.lua','test_manual_radio.lua'])
test_names.extend(['test_text_segments.lua','test_action_preferences.lua'])
test_names.extend(['test_window_drag.lua','test_passport_formats.lua','test_navigation_guard.lua'])
test_names.extend(['test_map_grid.lua','test_map_adapter.lua','test_map_integration.lua'])
test_names.extend(['test_manual_chat.lua','test_window_persistence.lua','test_wanted_detached.lua','test_manual_live.lua'])
test_names.extend(['test_editor0370.lua','test_manual_channels.lua'])
test_names.extend(['test_interior_selection.lua','test_timing0372.lua'])
test_names.append('test_updater.lua')
test_names.extend(['test_manual_actions.lua','test_wheel_custom.lua'])
test_names.extend(['test_startup040.lua','test_gender040.lua','test_ux040.lua'])
parser.add_argument('--report')
parser.add_argument('--only', nargs='+', choices=test_names)
parser.add_argument('--keep-going', action='store_true', help='Collect failures from every test group; still exit with failure.')
args = parser.parse_args()
for name in args.only or test_names:
    lua = runtime()  # isolated globals and module cache for every test file
    probe = (ROOT / "tests" / (".pa26-check-" + uuid.uuid4().hex + ".ini")).resolve()
    assert probe.parent == (ROOT / "tests").resolve()
    failure = None
    try:
        lua.globals()[b"TEST_TEMP_PATH"] = probe.as_posix().encode("utf-8")
        lua.execute((ROOT / "tests" / name).read_bytes())
    except Exception as exc:
        if not args.keep_going:
            raise
        failure = str(exc)
    finally:
        for suffix in ["", ".tmp", ".bak", ".rollback", ".rejected", ".png"]:
            Path(str(probe) + suffix).unlink(missing_ok=True)
    count = int(lua.globals()[b"TEST_CHECKS"])
    results.append({"test": name, "checks": count, "status": "failed" if failure else "passed", **({"error": failure} if failure else {})})
    print(f"{name}: FAILED\n{failure}" if failure else f"{name}: {count} checks passed")

assert all(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest for name, digest in tested_sources.items()), 'A Lua source changed while the tests were running'
assert all(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest for name, digest in tested_resources.items()), "A knowledge resource changed during testing"
summary = {"resource_sha256": tested_resources, "runtime": "LuaJIT 2.1 (lupa.luajit21)", "syntax_files": len(files), "lua_source_sha256": tested_sources,
           "total_checks": sum(r["checks"] for r in results), "results": results}
if args.report:
    Path(args.report).write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
failed_groups = [r for r in results if r['status'] != 'passed']
print(f"Failed groups: {len(failed_groups)}" if failed_groups else f"Total: {summary['total_checks']} checks passed")
if failed_groups:
    raise SystemExit(1)


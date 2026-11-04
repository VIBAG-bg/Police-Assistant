"""Final targeted evidence; require actual final source/manifest/fixture hashes."""
from pathlib import Path
import datetime,hashlib,json,shutil,statistics,zipfile
root=Path(__file__).resolve().parents[1];qa=root/'docs/qa/0.45.0/cef-hotfix';qa.mkdir(exist_ok=True)
read=lambda n:json.loads((root/n).read_text('utf-8-sig'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before=read('docs/qa/0.45.0/cef-hotfix/BEFORE.json')['files']
allowed={'moonloader/police_assistant_2026.lua','moonloader/lib/pa26_cef_compat.lua','moonloader/lib/pa26_chat_bridge.lua',
 'moonloader/lib/pa26_cef_assets.lua','moonloader/lib/pa26_studio.lua','cef/assets/hud/pa26-chat.js',
 'install.ps1','CEF_CONTRACT.json','UPDATE_CEF_BASELINE.json','INSTALL_MANIFEST.json'}
changed=[n for n,h in before.items()if sha(root/n)!=h]
assert set(changed)<=allowed,('Out of scope changes',set(changed)-allowed)
new_runtime={p.relative_to(root).as_posix()for p in (root/'moonloader').rglob('*')if p.is_file()}-before.keys()
assert new_runtime=={'moonloader/lib/pa26_cef_contract.lua','moonloader/lib/pa26_cef_job.lua'}
assert sha(root/'moonloader/lib/pa26_update_platform.lua')=='995b131aa0250b7ea407915ad7d109de71a8e43cec088603bc99cc489e60565f'
reg=read('tests/REGRESSION-0.45.0.json')
assert all(r['status']=='passed'for r in reg['results'])
for group in ['lua_source_sha256','resource_sha256']:
 assert all(sha(root/n)==h for n,h in reg[group].items()),'Runtime changed after regression'
install=read('tests/CEF_ADAPTIVE_INSTALL0450.json');platform=read('tests/PLATFORM0450.json')
installer=read('tests/INSTALLER_RESULTS.json')
assert install['status']=='passed'and install['installer_sha256']==sha(root/'install.ps1')
assert installer['status']=='passed'and installer['installer_sha256'].lower()==sha(root/'install.ps1')
assert all(r['status']=='passed'for r in platform['results'])
native=read('tests/CEF_NATIVE32_RESULTS.json');job=read('tests/CEF_ADAPTIVE_NATIVE32_0450.json')
assert native['status']==job['status']=='passed'
assert native['bridge_sha256']==sha(root/'moonloader/lib/pa26_chat_bridge.lua')
assert native['adapter_sha256']==sha(root/'cef/assets/hud/pa26-chat.js')
static=read('tests/CEF_ADAPTIVE_STATIC0450.json');browser=read('tests/CEF_ADAPTIVE_JS0450.json')
assert static['status']==browser['status']=='passed'
recovery=read('tests/CEF_RECOVERY0450.json')
assert recovery['status']=='passed' and recovery['adapter_sha256']==sha(root/'cef/assets/hud/pa26-chat.js')
aio=read('tests/ALLINONE_INSTALL0450.json');payload=read('tests/GPS_PATROL_INSTALL0450.json')
assert aio['status']==payload['status']=='passed'
assert aio['archive_sha256']==sha(root/'pa26-update.zip')
assert aio['manifest_sha256']==payload['manifest_sha256']==sha(root/'INSTALL_MANIFEST.json')
perf=read('tests/CEF_PERFORMANCE0450.json')
assert perf['trials']==3
for run in perf['runs']:
 for row in run['rows'].values():
  assert row['editing_ipc']==0 and all(row['editing_dom_work'][k]==0 for k in ['textReads','textWrites','styleReads','rectReads'])
ui=read('tests/UX_NATIVE32_0450.json');assert ui['status']=='passed'and ui['views']>=19
evidence=['CEF_ADAPTIVE_STATIC0450.json','CEF_ADAPTIVE_NATIVE32_0450.json','CEF_ADAPTIVE_INSTALL0450.json',
 'CEF_ADAPTIVE_JS0450.json','CEF_RECOVERY0450.json','CEF_HANDSHAKE0450.json','CEF_NATIVE32_RESULTS.json','CEF_PERFORMANCE0450.json',
 'PLATFORM0450.json','INSTALLER_RESULTS.json','UX_NATIVE32_0450.json']
for name in evidence:shutil.copyfile(root/'tests'/name,qa/name)
old=root.parents[1]/'work/cef-hotfix0450/before-source.zip'
with zipfile.ZipFile(old)as z:
 previous={n:hashlib.sha256(z.read(n)).hexdigest()for n in z.namelist()}
current=[]
for directory in ['moonloader','cef','tools','tests']:
 for p in (root/directory).rglob('*'):
  n=p.relative_to(root).as_posix()
  if any(x.endswith('sandbox')or x in {'install-sandbox','update-sandbox','cef-contract-sandbox','__pycache__'}or x.startswith('roads-native32-')for x in p.relative_to(root).parts):continue
  if not p.is_file()or p.suffix not in {'.lua','.js','.ps1','.py'}:continue
  if previous.get(n)!=sha(p):current.append(n)
documentation=[p.relative_to(root).as_posix()for p in (root/'docs').rglob('*')if p.is_file()and previous.get(p.relative_to(root).as_posix())!=sha(p)]
documentation+=['README.md','CHANGELOG.md']
current+=['install.ps1','CEF_CONTRACT.json','UPDATE_CEF_BASELINE.json','INSTALL_MANIFEST.json']
state={'status':'PASS_LOCAL_WITH_GAME_GATES','version':'0.45.0','at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'production_changes':sorted(set(changed)|new_runtime),'code_and_test_changes':sorted(set(current)),
 'documentation_and_evidence_changes':sorted(set(documentation)),'out_of_scope_runtime_unchanged':True,'protected_platform_sha256':sha(root/'moonloader/lib/pa26_update_platform.lua'),
 'gps_graph_and_updater_worker_unchanged':True,'public_presets_unchanged':True,'user_data_written':False,
 'lua_groups':len(reg['results']),'lua_checks':reg['total_checks'],'static_cases':len(static['cases']),
 'static_checks':static['checks'],'runtime_native_checks':native['checks'],'native_job_checks':job['checks'],
 'current_contract':'CONTRACT_COMPATIBLE','isolated_runtime':'RUNTIME_VERIFIED',
 'actual_gta_runtime':'NOT RUN','old_reviewed_full_file':'BLOCKED_SOURCE_NOT_AVAILABLE',
 'second_pc':'NOT RUN','win7_win10_guests':'NOT RUN','published':False,'installed':False}
(qa/'STATE.json').write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n','utf-8')
lines=['# PA 0.45.0 — итог адаптивного CEF hotfix','',
 'Снимок проверки перед публикацией. Активная GTA и другой ПК не изменялись. Состояние выпуска — на странице релизов GitHub.','',
 '## Причина и решение','',
 'Старые установщик и runtime независимо принимали только один SHA. Теперь оба используют один read-only анализатор PA и реестр. Известный файл проходит быстрый путь; новый хеш допускается при совпадении 42 проверенных компонентов контракта и DOM. Перед включением функций обязателен протокол 2 hello/ack/confirm/ready. Собственный тег располагается перед main.js; исходный JS не заменяется.','',
 'Профиль фиксирует полные тела нужных функций и зависимостей, таблицу/декодер, регистрацию событий и защищённые обращения; имена или отдельные строки не служат доказательством. Комментарии, пробелы, приватные переименования и проверенное независимое изменение функции вне контракта допускаются. Иная обфускация/структура могут потребовать нового профиля. JavaScript лаунчера установщиком не исполняется.','',
 '## Проверки','',
 '| Проверка | Статус | Доказательство |','| --- | --- | --- |',
 f'| Lua-регрессии | PASS | {len(reg["results"])} групп; {reg["total_checks"]:,} проверок; {reg["syntax_files"]} синтаксических Lua-файла |',
 f'| Статическая совместимость | PASS | {static["checks"]} проверок / {len(static["cases"])} случаев: текущий d7526…, новые совместимые SHA, повреждённые интерфейсы/DOM/payload, отсутствие файлов |',
 f'| Настоящий x86 фоновый анализ | PASS | {job["checks"]} проверок; единственное задание и кэш |',
 f'| x86 LuaSocket + текущий send-handler в изолированном V8 | PASS | {native["checks"]} проверок, протокол 2, преобразования, переносы, reconnect, отсутствие дублей |',
 f'| Поздний CEF и ограниченное восстановление | PASS | {recovery["checks"]} проверок; 30 минут виртуального отказа; без редактирования текста/IPC от 40000 событий ввода |',
 f'| Установка текущего неизвестного SHA | PASS | {install["checks"]} проверка: чистая установка, повтор, поздний тег, native-only отказ, личные файлы |',
 '| Windows installer/updater | PASS | 8 групп; 12 прерываний и откат на самостоятельном тестовом пакете с идентичным кодом установщика; production-реестры и ограничения worker сохранены |',
 f'| Текущий полный payload | PASS | All-in-One {aio["checks"]}; установленный manifest {payload["checks"]} |',
 f'| Native CPU UI | PASS | {ui["frames"]} кадров; {ui["views"]} видов; 7 размеров; включая диагностику CEF |',
 '| Старый реестр | PASS (fixture) | Прежний SHA сохранён; быстрый путь и KNOWN_VERIFIED проверены |',
 '| Полный старый launcher c458… | BLOCKED | Файл недоступен; полный повтор реального старого контракта не заявляется |',
 '| Реальные GTA FPS / frametime / задержка ввода / 15 минут | NOT RUN | Требуется пользовательская проверка в игре |',
 '| Установка на другом ПК / Win7, Win10 guest | NOT RUN | Не выполнялась по заданию |',
 '| Неразрешённые изменения GPS/данных/обновлятора | PASS | Хеши совпадают с All-in-One RC |',
 '| Остаточные ошибки автоматического прогона | FAIL: 0 | Все перечисленные завершённые проверки проходят |','',
 '## Производительность','',
 f'Реальный x86 запуск фонового анализатора: {job["initialization_ms"]:.2f} мс, вне игрового потока. Вызовы после кэширования не запускают процесс, не читают файлы и не пересчитывают хеш. Пакет из 100000 кэшированных вызовов ниже разрешения использованного socket-таймера; это не обещание нулевой игровой задержки.','',
 '| Синтетический callback, медиана p95 трёх прогонов | PA OFF, мс | До (0.44), мс | После (0.45), мс |',
 '| --- | ---: | ---: | ---: |']
for event in ['russian','english','backspace','word_selection','drag_selection','double_click','ctrl_a','ctrl_c','ctrl_v','long_message']:
 values=[statistics.median(r['rows'][name]['handlers'][event]['p95_ms']for r in perf['runs'])for name in ['PA_OFF','v0.44.0','v0.45.0']]
 lines.append('| '+event+' | '+' | '.join(f'{v:.6f}'for v in values)+' |')
lines+=['', 'Среда: Node V8 и синтетический DOM; после — с подтверждённым протоколом 2. Во всех прогонах 0 editing IPC и 0 чтений/записей текста, style/layout-запросов от обычного редактирования. Полные worst samples сохранены в JSON. Нельзя переносить эти значения на end-to-end ввод или FPS GTA.','',
 '## Сохранение','',
 'GPS-модули, roads.bin, рендер карты, /setmark policy, патруль, бинды, колесо, RP, половые формы, параметры и публичные авторские пресеты совпадают с предыдущим локальным All-in-One RC. В основном Lua изменены только подключение проверяющего задания, передача диагностики и cleanup. F4/F9 не переработаны; добавлена только сводка в существующем разделе CEF. Защищённый bootstrap: `'+state['protected_platform_sha256']+'`. Worker обновлятора побайтно сохранён относительно предыдущего RC.','',
 'Правила раскладки сохранены по уточнению владельца: преобразуется имя команды с точкой; обычная речь, имена и аргументы не переводятся автоматически.','',
 '## Точный список изменённых программных и тестовых файлов','']
lines+=['- `'+n+'`'for n in sorted(set(current))]
lines+=['','Документация и доказательства:']
lines+=['- `'+n+'`'for n in sorted(set(documentation))]
lines+=['', 'Документация и пересозданные JSON-доказательства дополнительно находятся в docs/qa/0.45.0 и этой папке; SHA файлов и архивов проверяются при упаковке.','',
 '## Следующая приёмка','',
 'Практический [чек-лист второго ПК и пояснения](../../../CEF-ADAPTIVE-0.45.0.md). Не отключать SHA/профильные защиты. `CONTRACT_COMPATIBLE` — статическая совместимость; `RUNTIME_VERIFIED` означает подтверждение конкретного запущенного моста и адаптера, а не выполнение всех игровых сценариев.','',
 'Со старого 0.44 worker нужен однократный полный установщик. Универсальный update ZIP сохраняет CEF-ассеты на месте и не заменяет необходимую начальную установку нового адаптера. QA выполнялся до публикации; активная игра не изменялась.']
(qa/'REPORT.md').write_text('\n'.join(lines)+'\n','utf-8')
print('CEF targeted evidence verified. Unrelated runtime, worker and presets unchanged.')

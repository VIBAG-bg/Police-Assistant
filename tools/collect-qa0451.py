"""Collect finished evidence only; never turn an unrun game check into PASS."""
from pathlib import Path
import datetime,hashlib,json,platform,shutil,statistics
ROOT=Path(__file__).resolve().parents[1];QA=ROOT/'docs/qa/0.45.1'
def read(name):return json.loads((ROOT/name).read_text('utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
reg=read('tests/REGRESSION-0.45.1.json')
assert len(reg['results'])==216 and all(r['status']=='passed'for r in reg['results'])
for name,digest in {**reg['lua_source_sha256'],**reg['resource_sha256']}.items():assert sha(ROOT/name)==digest,name+' changed after regression'
platform_tests=read('tests/PLATFORM0451.json');extra=read('tests/EXTRA0451.json')
assert len(platform_tests['results'])==8 and len(extra['results'])==6
assert all(r['status']=='passed'for r in platform_tests['results']+extra['results'])
install=read('tests/INSTALLER_RESULTS.json')
assert len(install['rollback_after'])==12 and install['manifest_sha256'].lower()==sha(ROOT/'INSTALL_MANIFEST.json')
assert install['installer_sha256'].lower()==sha(ROOT/'install.ps1')
aio=read('tests/ALLINONE_INSTALL0451.json')
assert aio['status']=='passed' and aio['archive_sha256']==sha(ROOT/'pa26-update.zip')
native=read('tests/CEF_NATIVE32_RESULTS.json');assert native['status']=='passed'and native['checks']==113
cpu=read('tests/UX_NATIVE32_0450.json');rp_cpu=read('tests/UX_NATIVE32_0451.json')
assert cpu['status']==rp_cpu['status']=='passed'
base=read('docs/qa/0.45.1/BASELINE.json');preserved=read('docs/qa/0.45.1/PRESERVATION.json')
assert preserved['status']=='PASS'
current=read('docs/qa/0.45.1/CURRENT_CEF.json')
lua_perf=read('tests/LUA_PERFORMANCE0451.json');cef_perf=read('tests/CEF_PERFORMANCE0451.json')
assert all(row['editing_ipc']==0 and all(value==0 for value in row['editing_dom_work'].values())
           for run in cef_perf['runs']for row in run['rows'].values())
copies={
 'tests/REGRESSION-0.45.1.json':'REGRESSION.json','tests/PLATFORM0451.json':'PLATFORM.json',
 'tests/EXTRA0451.json':'EXTRA.json','tests/INSTALLER_RESULTS.json':'INSTALLER.json',
 'tests/ALLINONE_INSTALL0451.json':'ALLINONE.json','tests/CEF_NATIVE32_RESULTS.json':'CEF_NATIVE32.json',
 'tests/UX_NATIVE32_0450.json':'UX_EXISTING_NATIVE32.json','tests/UX_NATIVE32_0451.json':'UX_RP_NATIVE32.json',
 'tests/LUA_PERFORMANCE0451.json':'LUA_PERFORMANCE.json','tests/CEF_PERFORMANCE0451.json':'CEF_PERFORMANCE.json',
 'tests/CEF_ADAPTIVE_STATIC0450.json':'CEF_REVIEWED_REFERENCE_STATIC.json',
 'tests/CEF_ADAPTIVE_INSTALL0450.json':'CEF_REVIEWED_REFERENCE_INSTALL.json',
 'tests/DOWNGRADE0451.json':'DOWNGRADE.json'}
for source,target in copies.items():shutil.copyfile(ROOT/source,QA/target)
state=dict(version='0.45.1',at_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
 status='LOCAL_RC_WITH_EXPLICIT_GAME_AND_CURRENT_CEF_GATES',baseline_head=base['head'],
 lua_groups=len(reg['results']),lua_checks=reg['total_checks'],lua_syntax_files=reg['syntax_files'],lua_regression='PASS',
 installer_updater_fixtures='PASS',platform_fixture_groups=14,rollback_points=12,native_ipc='PASS',
 native_cpu_frames=cpu['frames']+rp_cpu['frames'],native_cpu_ui='PASS',preservation='PASS',
 current_launcher_full_cef='BLOCKED' if not current['allowed']else'NOT RUN',current_cef=current,
 reviewed_d7526_fixture='PASS',game_acceptance='NOT RUN',real_game_input_latency='NOT RUN',
 actual_windows_7='NOT RUN',second_pc_installation='NOT RUN',installed=False,published=False,live_game_written=False,
 environment=dict(python=platform.python_version(),platform=platform.platform(),lua='LuaJIT 2.1 / Lupa',
                  powershell='Windows PowerShell 5.1',native='installed x86 LuaJIT + mimgui CPU + real loopback, no GTA'),
 known_limitations=['Current launcher '+current['sha256']+' fails the preserved functional CEF profile: '+current['reason'],
                   'The original c458 launcher source is unavailable; known-registry fast path is fixture-tested only.',
                   'Real GTA/Exsellent, second PC and native Windows 7 acceptance not run.'])
(QA/'STATE.json').write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n','utf-8')
text='''# Итоговая проверка локального кандидата 0.45.1

Кандидат собран из проверенного исходного архива 0.45.0. Базовый commit: `{head}`. Оригинал ТЗ сохранён дословно; версия — **0.45.1**. Ни публикации, ни установки, ни записи в живую GTA не выполнялось.

## Что реализовано

83 авторских бинда, 34 правила ручных команд, мужские/женские формы, два независимых колеса (8 пеших / 6 автомобильных), дополнительные действия «Ещё», сохранённый личный раздел и следствие в F9. Используются существующие классификатор транспорта и Copilot. Неизвестная модель предлагает два предпросмотра. Опасные этапы подтверждаются отдельно, проверяется прежняя цель и машина; НЕТ / Esc / тайм-аут прекращают остаток.

Тексты, варианты, вопросы, паузы, тайм-ауты и клавиши доступны в прежнем GUI. Номер значка — отдельное поле профиля. Сохранение и предпросмотр проверены. [Уточнения исходного текста](RP-DEVIATIONS.md): четыре замены SA:MP ID на IC-номер значка и одно слишком длинное действие `/todo`, целиком вынесенное в `/me`. Утверждённый текст ручной `/setmark` не менялся; новый A40 приведён к этому же тексту вместо устаревшей фразы старого публичного A40. Задержки и центральное исключение повторов сохранены.

## Матрица результатов

| Проверка | Результат | Область доказательства |
|---|---|---|
| Lua-регрессия | PASS | {groups} групп, {checks:,} проверок; {syntax} файлов синтаксиса |
| 83 бинда / 34 ручных правила | PASS | Обе формы пола, CP1251, пределы сообщений и `/todo`, точные исходные строки с документированными уточнениями |
| Входы команды / F4/F9 / колесо / клавиша | PASS | Реальная подготовка и исполнитель PA в симуляторе; отмена, этапы, неизвестная модель, без повторных отправок |
| Пользовательские данные | PASS | Roundtrip старого формата, личные тексты, избранное, горячие клавиши, названия и порядок колёс, профиль, заметки, геометрия |
| Импорт авторского набора | PASS | Предпросмотр, подтверждение, резервная копия, личные ответвления, конфликты, повторное применение, лимит 128 без удаления данных |
| Защита старого PA | PASS | Настоящие валидаторы 0.45.0 отклоняют оба новых публичных документа schema 2 |
| Установщик / обновлятор | PASS | 8 основных + 6 дополнительных групп на изолированных папках; 12 точек сбоя/отката |
| All-in-One и старый worker 0.44 | PASS | Полный пакет, граф дорог, обрыв и восстановление, безопасный отказ старого worker |
| x86 LuaJIT / IPC | PASS | 113 проверок; настоящий loopback и функция отправки HUD в отдельном V8; чат DOM — тестовый |
| Нативная CPU-отрисовка | PASS | {frames} кадров, 19 прежних + 3 новых представления, 7 разрешений, 2 масштаба шрифта; не GPU и не GTA |
| CEF синтетика | PASS | 578 + 21 + 74 проверок; 40 000 событий редактирования без запросов/DOM-работы, восстановление и отсутствие дублей |
| CEF `d7526…` | PASS | Сохранённые проверенные реальные файлы; статический контракт, установка/переустановка/откат в макете, без изменения original main.js |
| Текущий CEF `f6122…` | BLOCKED | Прежний verifier отклоняет изменившийся функциональный профиль; native-only. Полная CEF-совместимость не заявляется |
| Полный старый клиент `c458…` | BLOCKED | Исходный main.js недоступен; путь известного реестра проверен только макетом |
| GTA / Exsellent, реальная задержка и кадры | NOT RUN | Нужен отдельный игровой прогон |
| Второй компьютер / Windows 7 как ОС | NOT RUN | PS 5.1 и x86 на текущей ОС не доказывают работу на другом ПК / Windows 7 |

Три первых неудачи полного прогона были устаревшими ожиданиями тестов и включением новых системных пунктов в старую раскладку. Исправление сохраняет старую раскладку: новые пункты появляются лишь при явном назначении. Повторный полный прогон чистый. Дополнительный старый тест ожидал замену 6 записей на 83; теперь проверяется сохранение 6 записей плюс 83 новых (89). До запуска All-in-One требуется построенный update.zip; после его подготовки актуальный вариант теста прошёл. Проверки CEF на движущемся live-файле не объявлены успешными: для регрессии отдельно использован архивный `d7526…`, а текущая несовместимость отражена в CURRENT_CEF.json.

## Совместимость и сохранность

CEF-адаптер, мост, обработчик текста, реестр и verifier CEF, навигация, roads.bin, классификатор транспорта, updater worker и защищённый Lua-bootstrap сохранены побайтно. {preserved} проверок сохранности. Изменение install.ps1 ограничено списком собственных PA-модулей. Авторские значения геометрии F4/F9, INI/HUD не менялись. Передача команды клиенту не означает принятия сервером.

Текущий read-only снимок main.js: `{current_sha}`. Результат: `{reason}`, `native-only`, runtime `NOT_RUN`. Успешные 113 IPC-проверок выделенной функции отправки **не** подтверждают полный контракт этого клиента. Это внешний блокер новой чистой CEF-установки, выделенный без переписывания защищённого работающего моста. Обычные нативные функции PA сохраняются. Поддержка этого нового контракта требует отдельного задания и проверки.

Существующие личные бинды автоматически не заменяются. Авторский набор применяется только отдельной кнопкой с просмотром и резервной копией. Старые исполняемые файлы могут не читать новые документы: откат пользовательских данных выполняется из резервной копии. Переход с worker 0.44.0 — однократно полный установщик.

## Измерения — только синтетика

Три парных прогона LuaJIT/Lupa и три Node/V8 с тестовым DOM. Числа ниже — медиана p95 трёх прогонов, включая накладные расходы стенда; это не время появления буквы в GTA.

| Обработчик | 0.45.0, мс | 0.45.1, мс |
|---|---:|---:|
{lua_rows}

В Node/V8 p95 русского ввода: без PA {off:.6f} мс, 0.45.0 {old:.6f} мс, 0.45.1 {new:.6f} мс. Разница на таком стенде сопоставима с шумом измерения. В обоих адаптерах при редактировании — 0 IPC, чтений/записей текста, чтений стилей/геометрии и загрузок endpoint. CEF-файлы одинаковы с baseline. Реальные input latency, FPS и frame spikes остаются NOT RUN; обещание отсутствия игровых фризов по этим цифрам не делается.

## Дальше

Проверить [ручной чек-лист GTA](../../ACCEPTANCE-0.45.1.md). Команды сборки и будущей публикации — [отдельно](../../BUILD-0.45.1.md). До разрешения владельца кандидата не устанавливать и не публиковать. Артефакты и их фактические SHA-256 проверяются `tools/verify-artifacts0451.py`; сами хеши ZIP лежат рядом с архивами в dist/SHA256SUMS.txt.

## Все изменённые и новые файлы

Ниже перечислены файлы исходного пакета относительно замороженного 0.45.0. Временные макеты, журналы и dist не включены. Самоописывающиеся отчёты проверяются внешней суммой архива.

'''
lua_rows=[]
for key in lua_perf['runs'][0]['candidate_0.45.1']:
    prior=statistics.median(r['baseline_0.45.0'][key]['p95_ms']for r in lua_perf['runs'])
    after=statistics.median(r['candidate_0.45.1'][key]['p95_ms']for r in lua_perf['runs'])
    lua_rows.append(f'| {key} | {prior:.6f} | {after:.6f} |')
def typed(name):return statistics.median(r['rows'][name]['handlers']['russian']['p95_ms']for r in cef_perf['runs'])
text=text.format(head=base['head'],groups=state['lua_groups'],checks=state['lua_checks'],syntax=state['lua_syntax_files'],
    frames=state['native_cpu_frames'],preserved=preserved['checks'],current_sha=current['sha256'],reason=current['reason'],
    lua_rows='\n'.join(lua_rows),off=typed('PA_OFF'),old=typed('v0.45.0'),new=typed('v0.45.1'))
roots={'moonloader','cef','presets','docs','tests','tools','.github'}
excluded={'install-sandbox','update-sandbox','cef-contract-sandbox','native0440','home0440','font-upstream','__pycache__','node_modules','installation-backups','dist'}
changes=[];seen=set()
for file in ROOT.rglob('*'):
    if not file.is_file()or file.is_symlink():continue
    rel=file.relative_to(ROOT);name=rel.as_posix()
    if len(rel.parts)>1 and rel.parts[0]not in roots:continue
    if len(rel.parts)==1 and name not in set(n for n in base['files']if'/'not in n)|{'AGENTS.md'}:continue
    if any(part in excluded or part.startswith(('.pa26-','roads-native32-'))for part in rel.parts):continue
    if file.suffix.lower()in {'.dll','.exe','.zip','.log','.bak','.rollback','.pending','.verts','.indices','.rgba'}:continue
    if rel.parts[0]=='tests'and len(rel.parts)==2 and file.suffix not in {'.lua','.py','.js','.ps1'}:continue
    seen.add(name)
    if name in {'docs/qa/0.45.1/FINAL-REVIEW.md','docs/qa/0.45.1/CHANGESET.json'}:continue
    digest=sha(file)
    if digest!=base['files'].get(name):changes.append(dict(path=name,change='modified'if name in base['files']else'new',sha256=digest))
for name in base['files']:
    if not (ROOT/name).exists():changes.append(dict(path=name,change='removed'))
for name in ['docs/qa/0.45.1/FINAL-REVIEW.md','docs/qa/0.45.1/CHANGESET.json']:
    changes.append(dict(path=name,change='new',checksum_scope='outer archive'))
changes.sort(key=lambda row:row['path'])
(QA/'CHANGESET.json').write_text(json.dumps(dict(version='0.45.1',baseline=base['head'],files=changes),ensure_ascii=False,indent=2)+'\n','utf-8')
text+='\n'.join('- `'+r['path']+'` — '+r['change']for r in changes)+'\n'
(QA/'FINAL-REVIEW.md').write_text(text,'utf-8')
print('Collected 0.45.1 evidence:',state['lua_groups'],'groups;',state['native_cpu_frames'],'CPU frames;',len(changes),'changed/new files. Live CEF gate:',state['current_launcher_full_cef'])

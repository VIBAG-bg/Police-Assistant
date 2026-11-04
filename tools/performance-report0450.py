"""Publish measured offline timings with explicit real-game exclusions."""
from pathlib import Path
import json, statistics

ROOT=Path(__file__).resolve().parents[1]
lua=json.loads((ROOT/'tests/LUA_PERFORMANCE0450.json').read_text('utf-8'))
cef=json.loads((ROOT/'tests/CEF_PERFORMANCE0450.json').read_text('utf-8'))
roads=json.loads((ROOT/'tests/ROADS_PERFORMANCE0450.json').read_text('utf-8'))
lines=['# Производительность 0.45.0: границы измерений', '',
 'Это CPU-замеры тестовой среды на текущем Windows-хосте, **не задержка клавиатуры или кадра GTA**. '
 'Три прогретых парных Lua-прогона используют LuaJIT 2.1 + Lupa + существующий fixture. '
 'Три CEF-прогона используют Node V8, настоящий адаптер с подтверждённым протоколом 2 и синтетический DOM с 550 строками истории.', '',
 'Реальные FPS, p50/p95/p99 frame time, кадры >33 мс, end-to-end input latency, '
 'аппаратное A/B в одной GTA-сцене и реальная 15/30-минутная сессия: **NOT RUN**. '
 'Нельзя вычитать эти CPU-числа из игрового пинга или обещать отсутствие микрофризов.', '',
 '## Lua: медиана p95 обработчика по трём прогонам', '',
 '| Обработчик | 0.44.0, мс | 0.45.0, мс |', '| --- | ---: | ---: |']
for name in lua['runs'][0]['baseline_0.44.0']:
    values=[]
    for label in ['baseline_0.44.0','candidate_0.45.0']:
        rows=[run[label][name] for run in lua['runs']]
        values.append(f"{statistics.median(row['p95_ms'] for row in rows):.6f}" if all('p95_ms' in row for row in rows) else 'NOT EXPOSED')
    lines.append('| '+name+' | '+' | '.join(values)+' |')
lines+=['', 'Счёт включает накладные расходы fixture/Lupa и не имитирует фактическую стоимость '
 'игровых API или native route search. Среда Node и Lua прогревалась отдельно; вывод о статистической '
 'эквивалентности игрового FPS из этого не следует.', '', '## CEF: медиана p95 синтетического callback', '',
 '| Событие | PA OFF, мс | 0.44.0, мс | 0.45.0, мс |', '| --- | ---: | ---: | ---: |']
for name in cef['runs'][0]['rows']['PA_OFF']['handlers']:
    values=[f"{statistics.median(run['rows'][label]['handlers'][name]['p95_ms'] for run in cef['runs']):.6f}" for label in ['PA_OFF','v0.44.0','v0.45.0']]
    lines.append('| '+name+' | '+' | '.join(values)+' |')
lines+=['', 'Во всех трёх режимах всех трёх прогонов: **0 чтений/записей текста, '
 '0 getComputedStyle/layout reads и 0 PA IPC-запросов от событий редактирования**. '
 'Статистики и worst sample каждого прогона сохранены в JSON; выбросы Node/GC не скрыты.', '',
 'Текущий send-handler проверен в изолированном V8 с настоящим x86 LuaSocket/IPC: 113 проверок PASS. '
 'Тестовый extractor поддерживает изменившиеся имена декодера; текущий хеш дополнительно проходит общий статический проверяющий профиль и подтверждение адаптера. '
 'Полная игровая приёмка живого CEF, редактора и сервера остаётся NOT RUN. '
 'SHA CEF, неизвестный контракт и следующий шаг: [CEF_CURRENT_CONTRACT](qa/0.45.0/CEF_CURRENT_CONTRACT.json).', '',
 '## Ограничения и повторяемость', '',
 '- `tools/benchmark0450.py --baseline <0.44.0>`: три парных Lua-прогона. '
 'Частота/число samples, median/p95/worst — в [LUA_PERFORMANCE0450](qa/0.45.0/LUA_PERFORMANCE0450.json).',
 '- `tools/benchmark-cef0450.py`: три Node-прогона OFF/baseline/candidate. '
 'Агрегаты — в [CEF_PERFORMANCE0450](qa/0.45.0/CEF_PERFORMANCE0450.json). Тексты чата не записываются.',
 '- `test_soak0450.lua`: 216000 ticks @120Hz, 30 минут **виртуального времени**. '
 'До пяти источников, до 32 записей dedupe, ограниченная частота чтения waypoint, 0 самовольных отправок; '
 'cleanup очищает свои источники/предложения. Это ускоренный replay, не wall-clock soak.',
 '- Рост памяти в настоящем игровом процессе и цена реального pathfinder: NOT RUN. '
 'Проверен размер контейнеров, а не доказано отсутствие всех утечек игрового клиента.',
 '- Диагностика выключена по умолчанию; прежний опциональный профилировщик имеет отдельные '
 'field-бакеты без текста, ID, телефонов, заметок и точных координат. '
 'Игровой порядок измерений: [ACCEPTANCE](ACCEPTANCE-0.45.0.md).', '']
lines+=['## Встроенный граф: подготовка и повторные маршруты','',
 'Три холодных прогона комплектного LGPS v1, фиксированные синтетические точки. Источник открывается один раз; файлы лаунчера не читаются. '
 'По умолчанию максимум 256 коротких шагов за порцию, мягкий CPU-бюджет 1 мс. Это время Lua/Lupa/Windows SHA, не время кадра GTA. '
 'Проверка бюджета не останавливает уже начатый короткий шаг, работу ОС, JIT или GC: абсолютного потолка 1 мс здесь нет.', '',
 '| Прогон / этап | Порций | p95 порции, мс | Худшая порция, мс | Всего CPU/wall вне игры, мс |',
 '| --- | ---: | ---: | ---: | ---: |']
for run in roads['runs']:
 for name,item in run['phases'].items():
  label={'prepare_graph':'подготовка сети','first_route':'первый маршрут','subsequent_route':'следующий маршрут'}[name]
  lines.append(f"| {run['trial']} / {label} | {item['slices']} | {item['slice_p95_ms']:.4f} | {item['worst_slice_ms']:.4f} | {item['total_offline_wall_ms']:.2f} |")
lines+=['', 'Подготовка начинается при включении навигации ещё до выбора цели. Если сеть уже готова, ждать её повторного разбора не нужно. '
 'Число порций не равно миллисекундам игрового ожидания: например, 120 порций по одной за кадр при 60 FPS — около 2 секунд плюс обнаружение/публикация результата. '
 'Реальные первая загрузка, время от постановки waypoint до видимой линии, радар/Esc и FPS ещё NOT RUN. Во время ввода обработчик расчёта возвращается без файловых операций или поиска. '
 'Граф включён в архив без изменения. [Полные результаты](qa/0.45.0/ROADS_PERFORMANCE0450.json).', '']
(ROOT/'docs/PERFORMANCE-0.45.0.md').write_text('\n'.join(lines),'utf-8')
print('Offline performance report written; real GTA metrics remain NOT RUN.')

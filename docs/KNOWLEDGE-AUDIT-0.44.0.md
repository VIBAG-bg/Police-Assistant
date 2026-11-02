# Аудит базы знаний 0.44.0

Проверка выполнена 01.11.2026. Целостность и покрытие отделены от юридической интерпретации и проверки игровых команд. Оригинальные тексты 14 предоставленных файлов и база 0.43.5 не переписаны. Полное машинное свидетельство: [knowledge-audit-0.44.0.json](knowledge-audit-0.44.0.json).

## Покрытие

В базе 94 источника, 1073 статьи, 51 запись команд, 212 правил, 86 радиокодов, 41 основание, 25 сценариев, 31 игровой пункт розыска. Сохранены 23 пробела и четыре неизвестных величины. Все 14 файлов снимков совпали со своими закреплёнными SHA-256. Коллизий идентификаторов статей и осиротевших ссылок на источники нет.

Десять карточек содержат 323 тематических включения. В «Все темы» показываются 230 уникальных строк; несколько тематических включений одной записи не создают дубликат. Типизированные штрафы АК сверены для 43 записей: ветви, диапазоны, условия, единицы и альтернативы сохранены. Звёзды 31 игрового пункта показаны отдельно от юридических ассоциаций.

## Публичная сверка

Все 94 URL имеют отдельный результат чтения. У четырёх источников полностью совпали нормализованные тексты всех индексированных статей; это поиск полного текста предоставленной статьи в публичной странице, а не самостоятельная экспертиза применимости нормы:

| Источник | Сопоставлено записей |
|---|---:|
| УК, тема 111 | 163 |
| АК, тема 113 | 150 |
| Закон о ФБР, тема 97 | 44 |
| Пенитенциарная система, тема 603 | 43 |

89 тем имеют статус `needs_manual_review`. У Конституции, тема 725, совпали 83 из 84 статей; статья 72 требует ручного сопоставления. Доступность страницы и HTTP 200 сами по себе не подтверждают все её нормы. В частности, общие правила 201 и тома Мануала прочитаны публично, но для них не заявлена полная постатейная сверка. Тема 423 недоступна в этом прогоне; её содержимое не выдумано.

## Неустранённые вопросы

- Время рейдов: 4.3 содержит 14:00–22:00, а повтор 10.9 — другое ограничение. Обе формулировки сохранены с предупреждением. Предположение о МСК не превращено в норму.
- `PM_currency_value`: нет установленной стоимости ПМ. В деньги ПМ автоматически не переводится.
- `IC_year_to_game_minutes`: нет подтверждённого пересчёта IC-лет в игровые минуты.
- `article_to_stars`: соответствие статьи пункту `/su` — подсказка, не автоматический перевод наказания в звёзды.
- `official_patrol_grid`: вычисляемые квадраты пользовательской сетки не объявлены официальными территориальными секторами ПД.
- Матрица RP — 51 строка, 50 уникальных команд; `/undivision` повторяется. 21 команда требует RP, 29 не требует. Расхождений классификации с предоставленной таблицей нет. `/wanted` есть в индексе, но отсутствует в этой таблице: отсутствие не означает освобождения от RP. Матрица не подтверждает аргументы, ранг, дальность или успешный ответ сервера.
- Каталог 13 разделов / 31 пункта розыска имеет игровое свидетельство от 23.10.2026. Актуальность на другом сервере или после изменения меню нужно проверять в игре. Снимок не становится бессрочным контрактом.

## Конечный список продолжения

1. Сопоставить Конституцию, статью 72, с полным текущим сообщением темы 725; сохранить версию и причину изменения до обновления исходного текста.
2. Разрешить конфликт рейдов по точной редакции/официальному разъяснению; не выбирать удобное время догадкой.
3. Для каждой темы из таблицы ниже сверить весь применимый текст, приложения и дату редакции. Прочитанная, но не сопоставленная тема остаётся непроверенной.
4. Повторить доступ к 423 только разрешённым публичным способом. При сохранении ограничения получить источник от владельца, не обходить ограничение.
5. В Exsellent отдельно проверить аргументы и ответы используемых команд, звёзды и допустимые процедуры. Не менять нормативные значения по результату одного UI-стенда.

| ID | Статус | Публичный источник |
|---|---|---|
| 346 | needs_manual_review | [Тема 346](https://forum.exsellentrp.com/threads/www-epd-gov-sistema-povysheniya.346/) |
| 302 | needs_manual_review | [Тема 302](https://forum.exsellentrp.com/threads/novovvedeniya-v-pravilakh.302/) |
| 271 | needs_manual_review | [Тема 271](https://forum.exsellentrp.com/threads/sledyashchaya-administratsiya.271/) |
| 269 | needs_manual_review | [Тема 269](https://forum.exsellentrp.com/threads/primery-otygrovok-dlya-sotrudnikov-epd-fbi.269/) |
| 263 | needs_manual_review | [Тема 263](https://forum.exsellentrp.com/threads/ic-ten-kody.263/) |
| 262 | needs_manual_review | [Тема 262](https://forum.exsellentrp.com/threads/ic-stadii-primeneniya-sily-dlya-sotrudnikov-pd-fbi.262/) |
| 261 | needs_manual_review | [Тема 261](https://forum.exsellentrp.com/threads/ic-pravilo-mirandy.261/) |
| 258 | needs_manual_review | [Тема 258](https://forum.exsellentrp.com/threads/ic-polnomochiya-shefa-politsii-i-komissara-epd.258/) |
| 201 | needs_manual_review | [Тема 201](https://forum.exsellentrp.com/threads/yedinyi-reglament-i-pravila-dlya-sotrudnikov-epd-i-fbi.201/) |
| 193 | needs_manual_review | [Тема 193](https://forum.exsellentrp.com/threads/alcatraz-pravila-dlya-sotrudnikov-penitentsiarnoi-sistemy.193/) |
| 266 | needs_manual_review | [Тема 266](https://forum.exsellentrp.com/threads/ic-pravilo-mirandy.266/) |
| 265 | needs_manual_review | [Тема 265](https://forum.exsellentrp.com/threads/ic-stadii-primeneniya-sily-dlya-sotrudnikov-pd-fbi.265/) |
| 264 | needs_manual_review | [Тема 264](https://forum.exsellentrp.com/threads/ic-ten-kody.264/) |
| 202 | needs_manual_review | [Тема 202](https://forum.exsellentrp.com/threads/yedinyi-reglament-i-pravila-dlya-sotrudnikov-epd-i-fbi.202/) |
| 367 | needs_manual_review | [Тема 367](https://forum.exsellentrp.com/threads/fbi-reglament-provedeniya-doprosov.367/) |
| 366 | needs_manual_review | [Тема 366](https://forum.exsellentrp.com/threads/fbi-reglament-raboty-fbi.366/) |
| 340 | needs_manual_review | [Тема 340](https://forum.exsellentrp.com/threads/novovvedeniya-v-pravilakh.340/) |
| 270 | needs_manual_review | [Тема 270](https://forum.exsellentrp.com/threads/primery-otygrovok-dlya-sotrudnikov-epd-fbi.270/) |
| 268 | needs_manual_review | [Тема 268](https://forum.exsellentrp.com/threads/istoriya-direktorov-federal-nogo-byuro-rassledovanii.268/) |
| 267 | needs_manual_review | [Тема 267](https://forum.exsellentrp.com/threads/sledyashchaya-administratsiya.267/) |
| 100 | needs_manual_review | [Тема 100](https://forum.exsellentrp.com/threads/trudovoi-kodeks-respubliki-exsellent.100/) |
| 95 | needs_manual_review | [Тема 95](https://forum.exsellentrp.com/threads/konstitutsiya-respubliki-exsellent.95/) |
| 310 | needs_manual_review | [Тема 310](https://forum.exsellentrp.com/threads/zakon-respubliki-exsellent-ob-osnovakh-sudoproizvodstva.310/) |
| 283 | needs_manual_review | [Тема 283](https://forum.exsellentrp.com/threads/zakon-respubliki-exsellent-o-prokurature.283/) |
| 282 | needs_manual_review | [Тема 282](https://forum.exsellentrp.com/threads/zakon-respubliki-exsellent-o-sudebnoi-sisteme.282/) |
| 174 | needs_manual_review | [Тема 174](https://forum.exsellentrp.com/threads/zakon-o-penitentsiarnoi-sisteme-respubliki-exsellent.174/) |
| 115 | needs_manual_review | [Тема 115](https://forum.exsellentrp.com/threads/zakon-o-ministerstve-zdravookhraneniya-i-sisteme-zdravookhraneniya-respubliki-exsellent.115/) |
| 114 | needs_manual_review | [Тема 114](https://forum.exsellentrp.com/threads/zakon-o-media-i-sredstvakh-massovoi-informatsii-respubliki-exsellent.114/) |
| 99 | needs_manual_review | [Тема 99](https://forum.exsellentrp.com/threads/zakon-o-voinskikh-zvaniyakh-vooruzhennykh-sil-respubliki-exsellent.99/) |
| 98 | needs_manual_review | [Тема 98](https://forum.exsellentrp.com/threads/zakon-o-vooruzhennykh-silakh-respubliki-exsellent.98/) |
| 96 | needs_manual_review | [Тема 96](https://forum.exsellentrp.com/threads/zakon-o-politsii-respubliki-exsellent.96/) |
| 207 | needs_manual_review | [Тема 207](https://forum.exsellentrp.com/threads/exsellent-normativy-vydachi-nakazanii-na-servere.207/) |
| 229 | needs_manual_review | [Тема 229](https://forum.exsellentrp.com/threads/exsellent-chto-takoye-roleplay-nik-i-informatsiya-po-ispol-zovaniyu-rp-komand-na-servere.229/) |
| 210 | needs_manual_review | [Тема 210](https://forum.exsellentrp.com/threads/exsellent-pravila-rp-i-nonrp-dokazatel-stv.210/) |
| 162 | needs_manual_review | [Тема 162](https://forum.exsellentrp.com/threads/ooc-mz-o-yedinyi-ustav.162/) |
| 101 | needs_manual_review | [Тема 101](https://forum.exsellentrp.com/threads/ooc-mi-informatsiya-o-liderakh.101/) |
| 423 | access_blocked | [Тема 423](https://forum.exsellentrp.com/threads/ooc-mi-o-ministerstve-informatsii.423/) |
| 236 | needs_manual_review | [Тема 236](https://forum.exsellentrp.com/threads/ic-yedinyi-ustav-pravitel-stva.236/) |
| 235 | needs_manual_review | [Тема 235](https://forum.exsellentrp.com/threads/ooc-politicheskaya-sistema-partii-vybory-i-zakonodatel-nyi-protsess.235/) |
| 136 | needs_manual_review | [Тема 136](https://forum.exsellentrp.com/threads/ooc-pravila-provedeniya-gosudarstvennogo-perevorota.136/) |
| 409 | needs_manual_review | [Тема 409](https://forum.exsellentrp.com/threads/fbi-reglament-vykhoda-iz-chernogo-spiska.409/) |
| 279 | needs_manual_review | [Тема 279](https://forum.exsellentrp.com/threads/ooc-pravila-prokuratury-respubliki-exsellent.279/) |
| 275 | needs_manual_review | [Тема 275](https://forum.exsellentrp.com/threads/ooc-pravila-sudebnoi-sistemy-respubliki-exsellent.275/) |
| 81 | needs_manual_review | [Тема 81](https://forum.exsellentrp.com/threads/oos-osnovnyye-pravila-ministerstva-oborony.81/) |
| 328 | needs_manual_review | [Тема 328](https://forum.exsellentrp.com/threads/www-epd-gov-backhome-ic.328/) |
| 472 | needs_manual_review | [Тема 472](https://forum.exsellentrp.com/threads/www-epd-gov-manual-rukovodstvo-tom-1-politika-departamenta.472/) |
| 428 | needs_manual_review | [Тема 428](https://forum.exsellentrp.com/threads/lsps-poleznaya-informatsiya.428/) |
| 356 | needs_manual_review | [Тема 356](https://forum.exsellentrp.com/threads/lvps-putevoditel-faq.356/) |
| 341 | needs_manual_review | [Тема 341](https://forum.exsellentrp.com/threads/www-epd-gov-field-training-program.341/) |
| 342 | needs_manual_review | [Тема 342](https://forum.exsellentrp.com/threads/www-epd-gov-sergeant-training-program.342/) |
| 343 | needs_manual_review | [Тема 343](https://forum.exsellentrp.com/threads/www-epd-gov-detective-training-program.343/) |
| 345 | needs_manual_review | [Тема 345](https://forum.exsellentrp.com/threads/www-epd-gov-command-training-program.345/) |
| 496 | needs_manual_review | [Тема 496](https://forum.exsellentrp.com/threads/www-epd-gov-manual-rukovodstvo-tom-2-organizatsiya-i-funktsii.496/) |
| 541 | needs_manual_review | [Тема 541](https://forum.exsellentrp.com/threads/www-epd-gov-manual-rukovodstvo-tom-3-upravleniye-i-uniforma.541/) |
| 344 | needs_manual_review | [Тема 344](https://forum.exsellentrp.com/threads/www-fbi-academy-uchebnaya-programma-natsional-noi-akademii-fbi.344/) |
| 336 | needs_manual_review | [Тема 336](https://forum.exsellentrp.com/threads/www-fbi-academy-reglament-natsional-noi-akademii-fbi.336/) |
| 333 | needs_manual_review | [Тема 333](https://forum.exsellentrp.com/threads/www-fbi-academy-vosstanovleniye-na-sluzhbu.333/) |
| 358 | needs_manual_review | [Тема 358](https://forum.exsellentrp.com/threads/fbi-vnutrennii-reglament-fcisd.358/) |
| 355 | needs_manual_review | [Тема 355](https://forum.exsellentrp.com/threads/fbi-polozheniye-o-fcisd.355/) |
| 445 | needs_manual_review | [Тема 445](https://forum.exsellentrp.com/threads/fbi-national-press-office.445/) |
| 604 | needs_manual_review | [Тема 604](https://forum.exsellentrp.com/threads/zakon-o-politsii-respubliki-exsellent.604/) |
| 555 | needs_manual_review | [Тема 555](https://forum.exsellentrp.com/threads/www-epd-gov-manual-rukovodstvo-tom-4-reglament-protsedur.555/) |
| 660 | needs_manual_review | [Тема 660](https://forum.exsellentrp.com/threads/fbi-reglament-vzaimodeistviya-s-mo.660/) |
| 680 | needs_manual_review | [Тема 680](https://forum.exsellentrp.com/threads/fbi-prikaz-no000001.680/) |
| 1020 | needs_manual_review | [Тема 1020](https://forum.exsellentrp.com/threads/lsps-vnutrennii-ustav-los-santos-police-station.1020/) |
| 1021 | needs_manual_review | [Тема 1021](https://forum.exsellentrp.com/threads/lsps-poleznaya-informatsiya-dlya-sotrudnikov-lsps.1021/) |
| 1028 | needs_manual_review | [Тема 1028](https://forum.exsellentrp.com/threads/lsps-sistema-prokhozhdeniya-akademii.1028/) |
| 1034 | needs_manual_review | [Тема 1034](https://forum.exsellentrp.com/threads/lsps-yedinaya-sistema-povysheniya.1034/) |
| 1036 | needs_manual_review | [Тема 1036](https://forum.exsellentrp.com/threads/lsps-otrabotka-i-snyatiye-distsiplinarnykh-vzyskanii.1036/) |
| 582 | needs_manual_review | [Тема 582](https://forum.exsellentrp.com/threads/www-epd-com-san-fierro-police-station.582/) |
| 584 | needs_manual_review | [Тема 584](https://forum.exsellentrp.com/threads/www-epd-com-sistema-akademii-etapy-prokhozhdeniya.584/) |
| 691 | needs_manual_review | [Тема 691](https://forum.exsellentrp.com/threads/www-epd-com-sistema-povysheniya-i-zayavleniye-na-povysheniye.691/) |
| 690 | needs_manual_review | [Тема 690](https://forum.exsellentrp.com/threads/www-epd-com-f-a-q.690/) |
| 593 | needs_manual_review | [Тема 593](https://forum.exsellentrp.com/threads/www-epd-com-zayavleniye-na-vosstanovleniye-v-dolzhnosti.593/) |
| 776 | needs_manual_review | [Тема 776](https://forum.exsellentrp.com/threads/www-epd-com-zayavleniye-na-perevod-v-sfps.776/) |
| 973 | needs_manual_review | [Тема 973](https://forum.exsellentrp.com/threads/s-w-a-t-normativy-povysheniya-sotrudnikov.973/) |
| 968 | needs_manual_review | [Тема 968](https://forum.exsellentrp.com/threads/s-w-a-t-zayavleniya-na-zachisleniye-v-akademiyu-swat.968/) |
| 969 | needs_manual_review | [Тема 969](https://forum.exsellentrp.com/threads/s-w-a-t-zayavleniya-na-otchisleniye-iz-podrazdeleniya-swat.969/) |
| 971 | needs_manual_review | [Тема 971](https://forum.exsellentrp.com/threads/s-w-a-t-prikazy-nachal-nika-podrazdeleniya.971/) |
| 742 | needs_manual_review | [Тема 742](https://forum.exsellentrp.com/threads/www-epd-gov-formulyar-otcheta-o-primenenii-sily.742/) |
| 746 | needs_manual_review | [Тема 746](https://forum.exsellentrp.com/threads/www-epd-gov-formulyar-otcheta-ob-areste.746/) |
| 679 | needs_manual_review | [Тема 679](https://forum.exsellentrp.com/threads/prikaz-no2-ob-utverzhdenii-yedinogo-formulyara-lichnogo-dela.679/) |
| 609 | needs_manual_review | [Тема 609](https://forum.exsellentrp.com/threads/prikaz-no1-ob-utverzhdenii-vnutrennei-dokumentatsii-exsellent-police-department.609/) |
| 1061 | needs_manual_review | [Тема 1061](https://forum.exsellentrp.com/threads/prikaz-no4-o-naznachenii-komandira-swat.1061/) |
| 999 | needs_manual_review | [Тема 999](https://forum.exsellentrp.com/threads/fbi-prikaz-no000003.999/) |
| 1000 | needs_manual_review | [Тема 1000](https://forum.exsellentrp.com/threads/fbi-prikaz-no000004.1000/) |
| 820 | needs_manual_review | [Тема 820](https://forum.exsellentrp.com/threads/fbi-reglament-uvol-neniya.820/) |
| 698 | needs_manual_review | [Тема 698](https://forum.exsellentrp.com/threads/fbi-prikaz-no000002.698/) |
| 1043 | needs_manual_review | [Тема 1043](https://forum.exsellentrp.com/threads/fbi-prikaz-no000005.1043/) |
| 725 | needs_manual_review | [Тема 725](https://forum.exsellentrp.com/threads/konstitutsiya-respubliki-exsellent.725/) |

Никакое ограничение или несовпадение в этом отчёте не скрыто под общей отметкой «форум проверен». Пользовательские правки остаются личными и не подменяют оригинал источника.

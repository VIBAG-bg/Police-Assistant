-- Additive settings only. Templates are original RP, not quotations of the rules.
local shared=require 'pa26_patrol_settings'
local core=require 'pa26_core'
local dispatch=require 'pa26_dispatch'
local M={}
M.booleans={{'pursuit_retention','Удерживать выбранного водителя до 300 м только в активной погоне'},
 {'repeat_megaphone','Повторно предлагать требования до остановки'}, {'auto_plate','Условный госномер из ID авто · RP-конвенция PA'},{'legacy_tire_enabled','Учитывать отмеченные ниже слоты мегафона как предупреждение об огне'}, {'pursuit_armed','Подозреваемые вооружены · ручная отметка'}, {'enabled','Подсказывать следующий шаг'}, {'hud','Карточка ситуации у HUD'}, {'always_show_on_duty','Карточка на службе в машине'},
 {'stationary_offer','Предложить доклад после остановки'}, {'exit_offer','Реагировать на выход водителя'},
 {'approach_offer','Предложить осмотр салона'}, {'flee_offer','Предложить погоню при отъезде'},
 {'high_risk_offer','Предложить 10-66 после погони'}, {'fast_wanted','Предлагать розыск и /pt отдельным шагом'}, {'taser_offer','Предлагать предупреждение тайзера при пешей погоне'},
 {'adam_driver_mute_radio','Водителю ADAM не показывать автоматические доклады'},
 {'night_flashlight','Фонарик в ночной отыгровке'}, {'window_ooc_hint','Подсказка ответа новичку в /n'},
 {'backup_mark','Добавлять /mark в экстренный доклад'}, {'colleagues_enabled','Радар коллег'},
 {'uniforms_enabled','Учитывать форму ПД как подсказку'}, {'radio_cache','Запоминать коллег из подтверждённых форматов чата'},
 {'ghetto_guard','Напоминать о численности в опасном районе'}, {'combat_guard','Напоминать о тайзере при перестрелке'},
 {'dispatch_enabled','Вызовы и спецситуации'}, {'dispatch_rp_enabled','RP перед докладом о вызове'}, {'robbery_guard','Состав патруля перед выездом'}}
M.numbers={{'pursuit_retain_distance','Погоня: дальность удержания личности, м',20,300},
 {'pursuit_retain_grace_ms','Погоня: ожидание потерянного наблюдения, мс',1000,30000}, {'plate_digits','Минимум цифр условного номера',1,6},{'find_cache_window_ms','Ожидание ответа /find, мс',1000,30000},{'raid_start_hour','Окно рейдов · начало (ваша трактовка МСК)',0,23},{'raid_end_hour','Окно рейдов · конец (ваша трактовка МСК)',0,23},{'scan_ms','Обновление радара, мс',100,5000},{'colleague_radius','Коллеги в радиусе, м',5,100},
 {'stop_distance','Дальность остановки, м',5,50},{'stop_ms','Время неподвижности для 10-55, мс',1000,10000},
 {'risk_stop_ms','Время неподвижности после погони, мс',1000,15000},{'risk_distance','Дальность 10-66, м',5,100},
 {'flee_distance','Отъезд для предложения погони, м',10,150},{'foot_distance','Отход водителя для пешей погони, м',5,50},
 {'toast_ms','Срок предложения, мс',1000,60000},{'warning_cooldown_ms','Интервал предупреждений, мс',1000,60000},
 {'warning_count','Предупреждений по Мануалу',1,10},{'ooc_warning_count','Минимум предупреждений OOC',1,10},
 {'combat_ms','Память о попадании, мс',1000,60000},{'min_officers','Сотрудников для подсказки об опасном районе',2,10},
 {'robbery_min_officers','Порог подсказки: ограбление бизнеса',2,10}}
M.texts={{'plate_prefix','Начало условного номера (например SA-)',32},{'count_legacy_phrases','Слоты с явным предупреждением об огне · номера 1–8',64},{'stop_outcome','Итог остановки',240},{'select_plate','Ручной госномер · заменяет условный',80},
 {'skin_ids','Форма ПД · ID через запятую',512},{'vehicle_models','Служебные машины · модели через запятую',256},
 {'danger_zones','Опасные районы · через запятую',1024},
 {'ghetto_warning','Напоминание об опасном районе',1024}, {'combat_warning','Напоминание о тайзере',1024},
 {'tire_zero','Счётчик: предупреждений ещё нет',512},{'tire_partial','Счётчик: минимум OOC',512},{'tire_done','Счётчик: все предупреждения',512},
 {'lost_vehicle_fallback','Машина не выбрана: текст для «Потерян»',160},
 {'robbery_warning','Предупреждение о составе на ограбление',2048},
 {'dispatch_confirmation_note','Подтверждение RP-вызова',2048}, {'gas_confirmation_note','Подсказка перед требованием на АЗС',2048}}
M.templates={{'call911','Вызов 9-1-1'},{'arrived','Прибытие и опрос граждан'},{'break_report','Перерыв · Код 7'},{'lost','Потерян · Код 4 АДАМ'},{'stop','Доклад 10-55'},{'pursuit','Доклад 10-57 VICTOR'},{'foot','Доклад 10-57 FOXTROT'},
 {'high_risk','Доклад 10-66'},{'combat','CODE 0 · попадание по офицеру'}, {'armed','Вооружённый водитель · без подтверждения стрельбы'},
 {'finish','Завершение ситуации'}, {'approach_day','Подход днём'}, {'approach_night','Подход ночью'},
 {'taser_warning','Предупреждение тайзера при пешей погоне'}, {'window','Вопрос об осмотре'}, {'ooc_hint','Подсказка новичку'}, {'return_car','Вернуться в машину'},
 {'stop_order','Требование остановиться'}, {'tire','Предупреждение в погоне'},
 {'risk_single','10-66 · один человек'}, {'risk_multi','10-66 · несколько человек'},
 {'wanted_rp','Ориентировка перед розыском'}, {'combat_rp','RP перед розыском за нападение'},
 {'backup_risk','Метка помощи при 10-66'}, {'backup_combat','Метка помощи при CODE 0'}}
for _,row in ipairs(dispatch.templates)do M.templates[#M.templates+1]=row end
for _,row in ipairs({{'explain_stop','Назвать причину остановки'},{'documents','Запросить документы'},{'explain_detention','Основание задержания'},
 {'miranda','Полная Миранда · личная произносимая версия'},{'rights_extra','Отдельное разъяснение сроков и обжалования'}})do M.templates[#M.templates+1]=row end
M.booleans[#M.booleans+1]={'detention_timers','Таймеры адвоката и звонка'}
for _,r in ipairs({{'lawyer_response_seconds','Адвокат: ожидание ответа, секунд',1,3600},{'lawyer_arrival_seconds','Адвокат: ожидание прибытия, секунд',1,3600},{'phone_call_seconds','Звонок: длительность, секунд',1,3600}})do M.numbers[#M.numbers+1]=r end
M.texts[#M.texts+1]={'stop_custom','Своя причина остановки',2000};M.texts[#M.texts+1]={'detention_custom','Своё основание задержания',2000}
M.variables={vehicle_type=true,vehicle_type_gen=true,unit=true,station=true,crew=true,model=true,model_id=true,vehicle_id=true,vehicle_color=true,
 vehicle_description=true,vehicle_plate=true,occupants=true,occupants_text=true,driver_id=true,driver_name=true,
 tac=true,armed_text=true,stop_outcome=true,area=true,location=true,map_square=true,sector=true,direction=true,
 my_name=true,my_firstname=true,officers=true,min_officers=true,warnings=true,warning_count=true,ooc_warning_count=true}
local legacyRadio={stop="{local_tag}{unit}, провожу остановку {vehicle_description} в районе {area} ({map_square}), {occupants_text}, Код 4.",pursuit="{local_tag}{unit}, 10-57 VICTOR за {vehicle_description}, {occupants_text}. Направление: {direction}, район: {area} ({map_square}), {tac}, Код 3.{armed_text}",foot="{local_tag}{unit}, подозреваемый покинул {model}, веду пешую погоню 10-57 FOXTROT в районе {area} ({map_square}), направление: {direction}, {tac}, Код 3!",high_risk="{local_tag}{unit}, провожу остановку повышенного риска 10-66 {vehicle_description}, {occupants_text}, район {area} ({map_square}), запрашиваю свободные экипажи по Код 3!",finish="{local_tag}{unit}, заканчиваю проведение остановки {vehicle_description} в районе {area}, {stop_outcome}, продолжаю патрулирование. Код 4."}
M.variables.city=true;M.variables.dispatch_officers=true;M.variables.robbery_min_officers=true
M.variables.stop_ground=true;M.variables.detention_ground=true;M.variables.ground_article=true
function M.defaults()
 local d={pursuit_retention=true,pursuit_retain_distance=300,pursuit_retain_grace_ms=15000,repeat_megaphone=true,auto_plate=true,plate_prefix='SA-',plate_digits=3,legacy_tire_enabled=false,dispatch_enabled=true,dispatch_rp_enabled=true,robbery_guard=true,robbery_min_officers=2,
  lost_vehicle_fallback='преследуемому т/с',
  robbery_warning='ВНИМАНИЕ! Пункты 3.1 / 10.4: на ограбление бизнеса нужен патруль минимум из {robbery_min_officers} сотрудников. Нарушение: Jail–Warn. PA оценивает состав в {dispatch_officers} чел. Подтвердите, что выезжаете с напарником; люди рядом или пассажиры сами по себе не подтверждают состав патруля.',
  dispatch_confirmation_note='Подтверждайте фактически полученный RP-вызов. Место и курс в докладе берутся из текущего положения офицера; проверьте их в предпросмотре. Отыгровка не устанавливает серверную GPS-метку.',
  gas_confirmation_note='Пункт 8.2: требование предъявляют на месте, пока ограбление АЗС продолжается. Предупреждение не разрешает автоматически открывать огонь: основания и ограничения применения силы проверяются отдельно. Пешком выберите доступный канал /s в настройках мегафона, если /m недоступен.',
  radio_templates_version=1,always_show_on_duty=false,pursuit_armed=false,enabled=true,hud=true,stationary_offer=true,exit_offer=true,approach_offer=true,flee_offer=true,high_risk_offer=true,
  fast_wanted=true,taser_offer=true,adam_driver_mute_radio=true,night_flashlight=true,window_ooc_hint=true,backup_mark=false,
  colleagues_enabled=true,uniforms_enabled=true,radio_cache=true,ghetto_guard=true,combat_guard=true,
  find_cache_window_ms=10000,raid_start_hour=14,raid_end_hour=22,scan_ms=500,colleague_radius=50,stop_distance=25,stop_ms=1500,risk_stop_ms=2500,risk_distance=35,flee_distance=25,foot_distance=12,
  toast_ms=30000,warning_cooldown_ms=5000,warning_count=5,ooc_warning_count=1,combat_ms=10000,min_officers=3,
  count_legacy_phrases='1',stationary_delta=.4,tac_channel='TAC 1',stop_outcome='проведена беседа',select_plate='',
  skin_ids='300,301,267,280,281,282,283,284,285,288,295,211,265,266,306,307',vehicle_models='596,597,598,599,490,528,427',
  danger_zones='Ganton,Idlewood,East Los Santos,Jefferson,Glen Park,Willowfield,Las Colinas,Los Flores,East Beach,Playa del Seville,El Corona,Little Mexico',
  ghetto_warning='Правило 9.3 / 10.28: опасный район, сотрудников рядом: {officers} из {min_officers}. Задержание меньшим составом допускается при продолжении погони сюда. Проверьте обстоятельства и действующую редакцию правил.',
  combat_warning='В активной перестрелке тайзер запрещён (п. 5.5 / 10.15); исключения и направление применения проверьте по правилам.',
  tire_zero='Предупреждения: 0/{ooc_warning_count} OOC · 0/{warning_count} Мануал. Счётчик не разрешает огонь.',
  tire_partial='Предупреждения: {warnings}/{ooc_warning_count} OOC · {warnings}/{warning_count} Мануал. Проверьте прочие условия применения силы.',
  tire_done='Предупреждения выполнены: {warnings}/{warning_count}. Место, угрозу и разрешение на огонь проверяет офицер.',
  templates={
   lost="{local_tag}{unit}, по {vehicle_description} объявляю Код 4 АДАМ. Потерян в районе {area} ({map_square}), последний курс — {direction}.",
   break_report="{local_tag}{unit}, {gender:взял|взяла} Код 7 (до 15 минут).",
   arrived="{local_tag}{unit}, {gender:прибыл|прибыла} на место вызова в районе {area} ({map_square}), опрашиваю граждан, Код 4.",
   call911="{local_tag}{unit}, работаю по последнему вызову в 9-1-1, направляюсь на {direction} в район {area} ({map_square}), Код 3.",
   stop="{local_tag}{unit}, провожу остановку {vehicle_description} в {city}, район {area} ({map_square}), направление: {direction}, {occupants_text}, Код 4.",
   pursuit="{local_tag}{unit}, 10-57 VICTOR за {vehicle_description}, {occupants_text}. Двигаюсь на {direction}, {city}, район {area} ({map_square}), {tac}, Код 3.{armed_text}",
   foot="{local_tag}{unit}, подозреваемый покинул {model}, веду пешую погоню 10-57 FOXTROT в {city}, район {area} ({map_square}), двигаюсь на {direction}, {tac}, Код 3!{armed_text}",
   high_risk="{local_tag}{unit}, провожу остановку повышенного риска 10-66 {vehicle_description}, {occupants_text}, нахожусь в {city}, район {area} ({map_square}), запрашиваю свободные экипажи, Код 3!",
   combat='{local_tag}{unit}, CODE 0! По офицеру открыт огонь! Район {area} ({map_square})! Требуется срочная поддержка всех юнитов!',
   armed='{local_tag}{unit}, водитель {vehicle_description} вооружён. Район {area} ({map_square}), запрашиваю поддержку, Код 3!',
   finish="{local_tag}{unit}, заканчиваю проведение остановки {vehicle_description} в районе {area} ({map_square}), {stop_outcome}, продолжаю патрулирование, Код 4.",
   approach_day='подходя к автомобилю, {gender:коснулся|коснулась} ладонью задней левой фары, оставив отпечаток, и {gender:осмотрел|осмотрела} салон.',
   approach_night='достав с пояса тактический фонарик, {gender:коснулся|коснулась} ладонью задней левой фары и {gender:посветил|посветила} лучом в салон автомобиля.',
   taser_warning='Гражданин, остановитесь и держите руки на виду! В случае неподчинения будет применён тайзер!',
   window='{gender:Мог|Могла} ли {my_firstname} увидеть оружие или запрещённые предметы в салоне автомобиля?',
   ooc_hint='Ответьте в /do на мой вопрос (например: /do В салоне оружия нет.)',
   return_car='Водитель {vehicle_type_gen} {model}, цвет: {vehicle_color}, вернитесь на место водителя, заглушите двигатель и держите руки на виду!',
   stop_order='Водитель {vehicle_type_gen} {model}, цвет: {vehicle_color}, остановитесь у обочины и заглушите двигатель!',
   tire='Водитель {vehicle_type_gen} {model}, цвет: {vehicle_color}, остановитесь! При неподчинении будет открыт огонь по колёсам!',
   risk_single='Водитель {model}, заглушите двигатель, вытащите ключи из замка зажигания и выбросьте их в окно!\nМедленно откройте дверь снаружи, выйдите с поднятыми руками спиной к офицерам и поднимите верхнюю одежду!\nСделайте три шага влево от машины и лягте на землю на живот! Выполняйте требования спокойно и без резких движений! В случае угрозы жизни или сопротивления будет применена сила!',
   risk_multi='Водитель {model}, заглушите двигатель, вытащите ключи из замка зажигания и выбросьте их в окно!\nВодитель и пассажиры, выходите из машины строго ПО ОДНОМУ с поднятыми руками спиной к офицерам!\nЛожитесь на живот в метре от дороги в шахматном порядке! Выполняйте требования спокойно и без резких движений! В случае угрозы жизни или сопротивления будет применена сила!',
   wanted_rp='/me {gender:зажал|зажала} кнопку тангенты рации и {gender:передал|передала} диспетчеру приметы автомобиля: {vehicle_description}, гос. номер «{vehicle_plate}».\n/do Диспетчер пробил регистрационные данные автомобиля по базе и объявил водителя в розыск.',
   combat_rp='/me {gender:передал|передала} диспетчеру сведения о подтверждённом вооружённом нападении на офицера и {gender:запросил|запросила} розыск установленного нападавшего.',
   backup_risk='10-66 / CODE 3! Остановка повышенного риска {vehicle_description}, район {area} ({map_square})!',
   backup_combat='CODE 0! Нападение на офицера в районе {area} ({map_square}), нужна срочная помощь!'}}
 for key,text in pairs(dispatch.defaults)do d.templates[key]=text end
 d.stop_ground='none';d.stop_branch='none';d.stop_custom='';d.detention_ground='none';d.detention_custom=''
 d.detention_timers=true;d.lawyer_response_seconds=300;d.lawyer_arrival_seconds=600;d.phone_call_seconds=180
 d.templates.explain_stop='Причина остановки: {stop_ground}. Основание: {ground_article}.'
 d.templates.documents='Предъявите, пожалуйста, документы для проверки. Основание: {stop_ground}.'
 d.templates.explain_detention='Вы задержаны. Основание: {detention_ground}. {ground_article}.'
 d.templates.miranda=require('pa26_operational').miranda
 d.templates.rights_extra='Вы вправе обжаловать задержание. Основание и защитник разъясняются незамедлительно.\nЗвонок предоставляется до ареста, не более трёх минут, в присутствии сотрудника.\nАдвоката вызываем до ареста: ожидаем ответ пять минут, при ответе — прибытие десять минут.'
 return d
end
function M.ids(s,lo,hi)
 if type(s)~='string'then return end;local out,n={},0
 for token in(s..','):gmatch('(.-),')do local v=token:match('^%s*(.-)%s*$');local x=tonumber(v)
  if not x or x%1~=0 or x<lo or x>hi then return end;out[x]=true;n=n+1;if n>256 then return end
 end;return out
end
function M.validate(raw)
 local d=M.defaults();if raw==nil then return d end;if type(raw)~='table'then return nil,'Повреждены настройки Copilot.'end
 for _,r in ipairs(M.booleans)do if raw[r[1]]~=nil then if type(raw[r[1]])~='boolean'then return nil,'Проверьте переключатель Copilot: '..r[2]end;d[r[1]]=raw[r[1]]end end
 for _,r in ipairs(M.numbers)do if raw[r[1]]~=nil then if not shared.integer(raw[r[1]],r[3],r[4])then return nil,'Проверьте значение Copilot: '..r[2]end;d[r[1]]=raw[r[1]]end end
 for _,r in ipairs(M.texts)do if raw[r[1]]~=nil then local t=shared.text(raw[r[1]],r[3]);if not t or(t==''and r[1]~='select_plate'and r[1]~='stop_custom'and r[1]~='detention_custom')then return nil,'Заполните Copilot: '..r[2]end;d[r[1]]=t end end
 local grounds=require 'pa26_operational'
 for _,kind in ipairs({'stop','detention'})do
  local key=kind..'_ground';local value=raw[key]or'none';if not grounds.find(kind,value)then return nil,'Выберите существующее основание.'end;d[key]=value
 end
 d.stop_branch=raw.stop_branch or'none'
 if d.stop_branch~='none'then local found=false;for _,r in ipairs(grounds.stop)do for _,b in ipairs(r.branches or{})do if b[1]==d.stop_branch then found=true end end end;if not found then return nil,'Проверьте ветвь причины остановки.'end end
 if not M.ids(d.count_legacy_phrases,1,8)then return nil,'Номера учитываемых реплик: 1–8, через запятую.'end
 if not M.ids(d.skin_ids,0,65535)or not M.ids(d.vehicle_models,400,65535)then return nil,'ID формы и моделей: целые числа через запятую.'end
 if raw.stationary_delta~=nil then if not core.finite(raw.stationary_delta)or raw.stationary_delta<.05 or raw.stationary_delta>5 then return nil,'Порог неподвижности: 0.05–5 м.'end;d.stationary_delta=raw.stationary_delta end
 d.tac_channel=raw.tac_channel or d.tac_channel;if not({['TAC 1']=true,['TAC 2']=true,['TAC 3']=true})[d.tac_channel]then return nil,'Выберите TAC 1, 2 или 3.'end
 if d.warning_count<d.ooc_warning_count then return nil,'Число предупреждений Мануала должно быть не меньше OOC-минимума.'end
 if raw.templates~=nil then if type(raw.templates)~='table'then return nil,'Повреждены тексты Copilot.'end
  for _,r in ipairs(M.templates)do local t=raw.templates[r[1]]
   if t~=nil then if type(t)~='string'or #t>4096 or not core.validUtf8(t)or t:gsub('\n',''):find('%c')or t==''then return nil,'Проверьте текст Copilot: '..r[2]end
    for k in core.stripGender(t):gmatch('{([^{}]+)}')do if not M.variables[k]and k~='local_tag'then return nil,'Неизвестная переменная Copilot: '..k end end
    if dispatch.rpKeys[r[1]]and not dispatch.validRp(t)then return nil,'В RP вызова нужны отдельные строки /me, /do, /try или /todo.'end
    d.templates[r[1]]=t
   end
  end
 end
 if type(raw.templates)=='table'then
  local old={stop_order='Водитель автомобиля {model}, немедленно остановитесь у обочины и заглушите двигатель!',tire='Водитель автомобиля {model}, немедленно остановитесь у обочины! В случае неподчинения будет открыт огонь по колёсам!',return_car='Водитель автомобиля {model}, немедленно вернитесь в салон, заглушите двигатель и держите руки на виду! При неподчинении будет применена сила!'}
  local stock=M.defaults().templates
  for key,value in pairs(old)do if raw.templates[key]==value then d.templates[key]=stock[key]end end
 end
 if raw.radio_templates_version~=nil and raw.radio_templates_version~=1 then return nil,'Неизвестная версия реплик Copilot.'end
 if raw.radio_templates_version==nil and type(raw.templates)=='table'then
  local stock=M.defaults().templates;for k,old in pairs(legacyRadio)do if raw.templates[k]==old then d.templates[k]=stock[k]end end
 end
 for _,key in ipairs({'robbery_warning','dispatch_confirmation_note','gas_confirmation_note'})do
  local text=core.stripGender(d[key]):gsub('{([a-z_]+)}',function(k)return M.variables[k]and''or'{'end)
  if text:find('[{}]')then return nil,'Неизвестная переменная в подсказке: '..key end
 end
 return d
end
return M

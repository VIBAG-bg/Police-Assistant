-- Editable PA wording, not verbatim law. Plain reports use manual 110's free
-- form, unit + situation + location. No unverified /ml command is issued.
local M={primary={},rows={},templates={}}
local function add(family,id,label,text)
 local r={id,label,id,radioOnly=true,family=family};M.rows[#M.rows+1]=r;M.templates[id]=text;return r
end
M.primary[#M.primary+1]=add('dispatch_search','dispatch_search','Поиск подозреваемого','{local_tag}{unit}, начинаю поиск подозреваемого. Моё 10-20: {area} ({map_square}).')
M.primary[#M.primary+1]=add('dispatch_colleague','dispatch_colleague','Помощь коллеге','{local_tag}{unit}, выезжаю на помощь коллеге. Моё 10-20: {area} ({map_square}).')
for _,r in ipairs({
 {'dispatch_search','search_enroute','Выехал в район поиска','следую в район поиска подозреваемого'},
 {'dispatch_search','search_arrived','Прибыл в район поиска','нахожусь в районе поиска подозреваемого'},
 {'dispatch_search','search_continue','Продолжаю поиск','продолжаю поиск подозреваемого'},
 {'dispatch_search','search_backup','Нужна помощь','запрашиваю помощь экипажей для поиска подозреваемого'},
 {'dispatch_search','search_located','Подозреваемый замечен · подтвердить','подозреваемый замечен, уточняю обстановку'},
 {'dispatch_search','search_finish','Завершил поиск','поиск в текущем районе завершён'},
 {'dispatch_colleague','colleague_arrived','Прибыл к коллеге','нахожусь на месте запроса помощи коллеге'},
 {'dispatch_colleague','colleague_assist','Помогаю на месте','оказываю помощь коллеге на месте'},
 {'dispatch_colleague','colleague_backup','Нужны ещё экипажи','запрашиваю дополнительные экипажи для помощи коллеге'},
 {'dispatch_colleague','colleague_finish','Помощь завершена','помощь коллеге завершена'},
 {'dispatch_gas','gas_assess','Оцениваю обстановку','оцениваю обстановку на АЗС'},
 {'dispatch_gas','gas_secure','Контролирую периметр','контролирую периметр АЗС'},
 {'dispatch_gas','gas_flee','Подозреваемый покидает АЗС','наблюдаю уход подозреваемого от АЗС; уточняю направление'}
})do add(r[1],r[2],r[3],'{local_tag}{unit}, '..r[4]..'. Моё 10-20: {area} ({map_square}).')end
M.source='Мануал Гуерры, том 4, раздел 110; редакция источника 28.10.2026. Личная формулировка PA. /ml, факт прибытия и результаты поиска автоматически не подтверждаются.'
return M

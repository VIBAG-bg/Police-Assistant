-- Radio-only follow-ups use the same proposal, validation and executor as primary reports.
local M={rows={},groups={},templates={}}
M.rows[#M.rows+1]={"dispatch_911_arrived","Прибыл на 9-1-1 · Работаю (Код 6)","dispatch_911_arrived",radioOnly=true}
M.groups["dispatch_911"]=M.groups["dispatch_911"] or {}
M.groups["dispatch_911"][#M.groups["dispatch_911"]+1]=M.rows[#M.rows]
M.templates["dispatch_911_arrived"]="{local_tag}{unit}, экипаж: {crew}, прибыл по вызову 9-1-1 в район {area} ({map_square}). Код 6, проверяю обстановку и опрашиваю граждан."
M.rows[#M.rows+1]={"dispatch_911_clear","Вызов 9-1-1 проверен · 10-99 / Код 4","dispatch_911_clear",radioOnly=true}
M.groups["dispatch_911"]=M.groups["dispatch_911"] or {}
M.groups["dispatch_911"][#M.groups["dispatch_911"]+1]=M.rows[#M.rows]
M.templates["dispatch_911_clear"]="{local_tag}{unit}, вызов 9-1-1 в районе {area} ({map_square}) проверен, нарушений не обнаружено. 10-99, продолжаю патрулирование, Код 4."
M.rows[#M.rows+1]={"dispatch_911_backup","На 9-1-1 нужна поддержка (10-70 / Код 3)","dispatch_911_backup",radioOnly=true}
M.groups["dispatch_911"]=M.groups["dispatch_911"] or {}
M.groups["dispatch_911"][#M.groups["dispatch_911"]+1]=M.rows[#M.rows]
M.templates["dispatch_911_backup"]="{local_tag}{unit}, по вызову 9-1-1 в районе {area} ({map_square}) требуется поддержка. 10-70, запрашиваю свободные экипажи, Код 3."
M.rows[#M.rows+1]={"dispatch_stolen_arrived","В секторе угона · Ищу (Код 6)","dispatch_stolen_arrived",radioOnly=true}
M.groups["dispatch_stolen"]=M.groups["dispatch_stolen"] or {}
M.groups["dispatch_stolen"][#M.groups["dispatch_stolen"]+1]=M.rows[#M.rows]
M.templates["dispatch_stolen_arrived"]="{local_tag}{unit}, экипаж: {crew}, прибыл в сектор поиска угнанного транспорта, 10-20: {area} ({map_square}). Код 6, осматриваю район."
M.rows[#M.rows+1]={"dispatch_stolen_clear","Сектор проверен · ТС не обнаружено","dispatch_stolen_clear",radioOnly=true}
M.groups["dispatch_stolen"]=M.groups["dispatch_stolen"] or {}
M.groups["dispatch_stolen"][#M.groups["dispatch_stolen"]+1]=M.rows[#M.rows]
M.templates["dispatch_stolen_clear"]="{local_tag}{unit}, сектор поиска в районе {area} ({map_square}) проверен, угнанный транспорт не обнаружен. 10-99, Код 4, продолжаю патрулирование."
M.rows[#M.rows+1]={"dispatch_stolen_backup","Угнанное ТС замечено · 10-70","dispatch_stolen_backup",radioOnly=true}
M.groups["dispatch_stolen"]=M.groups["dispatch_stolen"] or {}
M.groups["dispatch_stolen"][#M.groups["dispatch_stolen"]+1]=M.rows[#M.rows]
M.templates["dispatch_stolen_backup"]="{local_tag}{unit}, обнаружен транспорт {stolen_summary} в районе {area} ({map_square}); запрашиваю 10-70, свободные экипажи по Код 3."
M.rows[#M.rows+1]={"dispatch_business_arrived","Прибыл к бизнесу · Периметр (Код 6)","dispatch_business_arrived",radioOnly=true}
M.groups["dispatch_business"]=M.groups["dispatch_business"] or {}
M.groups["dispatch_business"][#M.groups["dispatch_business"]+1]=M.rows[#M.rows]
M.templates["dispatch_business_arrived"]="{local_tag}{unit}, экипаж: {crew}, прибыл к бизнесу по тревоге в районе {area} ({map_square}). Код 6, проверяю объект и периметр."
M.rows[#M.rows+1]={"dispatch_business_clear","Бизнес проверен · 10-99 / Код 4","dispatch_business_clear",radioOnly=true}
M.groups["dispatch_business"]=M.groups["dispatch_business"] or {}
M.groups["dispatch_business"][#M.groups["dispatch_business"]+1]=M.rows[#M.rows]
M.templates["dispatch_business_clear"]="{local_tag}{unit}, тревога бизнеса в районе {area} ({map_square}) проверена, ситуация урегулирована. 10-99, Код 4."
M.rows[#M.rows+1]={"dispatch_business_backup","Бизнес · 211 / 10-70, поддержка","dispatch_business_backup",radioOnly=true}
M.groups["dispatch_business"]=M.groups["dispatch_business"] or {}
M.groups["dispatch_business"][#M.groups["dispatch_business"]+1]=M.rows[#M.rows]
M.templates["dispatch_business_backup"]="{local_tag}{unit}, код 211 у бизнеса в районе {area} ({map_square}), требуется поддержка! Запрашиваю 10-70, свободные экипажи по Код 3."
M.rows[#M.rows+1]={"dispatch_gas_arrived","Прибыл к АЗС · Работаю (Код 6)","dispatch_gas_arrived",radioOnly=true}
M.groups["dispatch_gas"]=M.groups["dispatch_gas"] or {}
M.groups["dispatch_gas"][#M.groups["dispatch_gas"]+1]=M.rows[#M.rows]
M.templates["dispatch_gas_arrived"]="{local_tag}{unit}, экипаж: {crew}, прибыл по тревоге на АЗС в районе {area} ({map_square}). Код 6, контролирую обстановку."
M.rows[#M.rows+1]={"dispatch_gas_clear","АЗС · Ситуация завершена (10-99)","dispatch_gas_clear",radioOnly=true}
M.groups["dispatch_gas"]=M.groups["dispatch_gas"] or {}
M.groups["dispatch_gas"][#M.groups["dispatch_gas"]+1]=M.rows[#M.rows]
M.templates["dispatch_gas_clear"]="{local_tag}{unit}, ситуация на АЗС в районе {area} ({map_square}) урегулирована, 10-99. Продолжаю патрулирование, Код 4."
M.rows[#M.rows+1]={"dispatch_gas_backup","АЗС · Вооружённые / 10-70, Код 3","dispatch_gas_backup",radioOnly=true}
M.groups["dispatch_gas"]=M.groups["dispatch_gas"] or {}
M.groups["dispatch_gas"][#M.groups["dispatch_gas"]+1]=M.rows[#M.rows]
M.templates["dispatch_gas_backup"]="{local_tag}{unit}, вооружённые лица на АЗС в районе {area} ({map_square}), требуется поддержка! 10-70, свободные экипажи по Код 3."
M.rows[#M.rows+1]={"dispatch_bank_arrived","Прибыл к банку · Работаю (Код 6)","dispatch_bank_arrived",radioOnly=true}
M.groups["dispatch_bank"]=M.groups["dispatch_bank"] or {}
M.groups["dispatch_bank"][#M.groups["dispatch_bank"]+1]=M.rows[#M.rows]
M.templates["dispatch_bank_arrived"]="{local_tag}{unit}, экипаж: {crew}, прибыл к банку по тревоге в районе {area} ({map_square}). Код 6, контролирую периметр."
M.rows[#M.rows+1]={"dispatch_bank_clear","Банк · Ситуация завершена (10-99)","dispatch_bank_clear",radioOnly=true}
M.groups["dispatch_bank"]=M.groups["dispatch_bank"] or {}
M.groups["dispatch_bank"][#M.groups["dispatch_bank"]+1]=M.rows[#M.rows]
M.templates["dispatch_bank_clear"]="{local_tag}{unit}, ситуация у банка в районе {area} ({map_square}) урегулирована, 10-99. Код 4."
M.rows[#M.rows+1]={"dispatch_bank_backup","Банк · 211 / 10-70, Код 3","dispatch_bank_backup",radioOnly=true}
M.groups["dispatch_bank"]=M.groups["dispatch_bank"] or {}
M.groups["dispatch_bank"][#M.groups["dispatch_bank"]+1]=M.rows[#M.rows]
M.templates["dispatch_bank_backup"]="{local_tag}{unit}, код 211 в банке, район {area} ({map_square}), запрашиваю 10-70, свободные экипажи по Код 3!"
return M

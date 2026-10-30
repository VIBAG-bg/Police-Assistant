-- Original, editable RP based on the supplied dispatch workflow. Pure data and
-- estimates only: no native observation, routing, incident detection or sends.
local core=require 'pa26_core'
local M={}
M.actions={
 {'dispatch_911','Вызов 9-1-1 · RP + доклад','call_911'},
 {'dispatch_stolen','Поиск угнанного авто · RP + доклад','stolen_car'},
 {'dispatch_business','Ограбление бизнеса · RP + доклад','robbery_business'},
 {'dispatch_gas','Ограбление АЗС · RP + доклад','robbery_gas'},
 {'gas_order','АЗС · Требование грабителям','gas_order'},
 {'dispatch_bank','Ограбление банка · RP + доклад','robbery_bank'}}
local followups=require 'pa26_dispatch_followups'
M.primaryActions={};for i,row in ipairs(M.actions)do M.primaryActions[i]=row end
M.followups=followups.groups
for _,row in ipairs(followups.rows)do M.actions[#M.actions+1]=row end
M.byAction={};M.rpKeys={};M.templates={}
for _,row in ipairs(M.actions)do
 local item={id=row[1],label=row[2],radio=row[3],mega=row[1]=='gas_order',radioOnly=row.radioOnly==true}
 if not item.mega and not item.radioOnly then
  item.rp=row[1]..'_rp';item.foot=row[1]..'_foot_rp'
  M.rpKeys[item.rp]=true;M.rpKeys[item.foot]=true
  M.templates[#M.templates+1]={item.rp,row[2]..' · RP в машине'}
  M.templates[#M.templates+1]={item.foot,row[2]..' · RP пешком'}
 end
 M.byAction[item.id]=item;M.templates[#M.templates+1]={item.radio,item.label..' · текст'}
end
M.aliases={arrive_code6='arrived',break_code7='break_report',lost_code4_adam='lost'}
M.defaults={
 dispatch_911_rp='/me {gender:принял|приняла} входящий вызов 9-1-1 на терминале и {gender:построил|построила} маршрут на GPS-навигаторе.\n/do Координаты вызова 9-1-1 зафиксированы в бортовой системе.',
 dispatch_911_foot_rp='/me {gender:принял|приняла} вызов 9-1-1 на портативной рации и {gender:проверил|проверила} место вызова на служебном КПК.\n/do Сведения о вызове 9-1-1 отображены на экране КПК.',
 call_911='{local_tag}{unit}, работаю по последнему вызову в 9-1-1, направляюсь на {direction} в {city}, район {area} ({map_square}), Код 3.',
 dispatch_stolen_rp='/me {gender:открыл|открыла} на терминале базу ориентировок по угону транспорта и {gender:загрузил|загрузила} сектор поиска в навигатор.\n/do На дисплее отображены приметы разыскиваемого автомобиля и маршрут следования.',
 dispatch_stolen_foot_rp='/me {gender:открыл|открыла} базу ориентировок на служебном КПК и {gender:изучил|изучила} сведения об угнанном автомобиле.\n/do Приметы автомобиля и сектор поиска отображены на КПК.',
 stolen_car='{local_tag}{unit}, {gender:принял|приняла} ориентировку по угону {stolen_summary}, выезжаю на поиск в район {stolen_location}. Моё 10-20: {area} ({map_square}), последний курс {direction}, Код 2.',
 dispatch_business_rp='/me {gender:принял|приняла} сигнал тревожной кнопки бизнеса на бортовой терминал и {gender:вывел|вывела} точку вызова на навигатор.\n/do В системе зафиксировано срабатывание сигнализации коммерческого объекта.',
 dispatch_business_foot_rp='/me {gender:принял|приняла} сообщение об ограблении бизнеса по рации и {gender:открыл|открыла} карточку вызова на служебном КПК.\n/do На КПК отображена информация о тревоге коммерческого объекта.',
 robbery_business='{local_tag}{unit}, реагирую на ограбление бизнеса, экипаж: {crew}, направляюсь в {city}, район {area} ({map_square}), курс {direction}, Код 3!',
 dispatch_gas_rp='/me {gender:получил|получила} сигнал тревоги с автозаправочной станции на терминал и {gender:проложил|проложила} маршрут перехвата.\n/do Бортовая система передала координаты ограбления АЗС.',
 dispatch_gas_foot_rp='/me {gender:принял|приняла} по рации сообщение об ограблении АЗС и {gender:уточнил|уточнила} место вызова на служебном КПК.\n/do Информация об ограблении АЗС доступна на экране КПК.',
 robbery_gas='{local_tag}{unit}, реагирую на ограбление АЗС, экипаж: {crew}, направляюсь в {city}, район {area} ({map_square}), курс {direction}, Код 3!',
 gas_order='Полиция! Всем участникам ограбления АЗС немедленно оставаться на своих местах, бросить оружие и поднять руки! В случае неподчинения будет открыт огонь!',
 dispatch_bank_rp='/me {gender:принял|приняла} экстренный сигнал тревоги из хранилища банка на терминал и {gender:активировал|активировала} протокол повышенной готовности.\n/do Координаты банка и сектор оцепления выведены на экран.',
 dispatch_bank_foot_rp='/me {gender:принял|приняла} экстренный вызов об ограблении банка по рации и {gender:открыл|открыла} сведения об объекте на служебном КПК.\n/do На экране КПК отображены место вызова и сведения для оцепления.',
 robbery_bank='{local_tag}{unit}, сработала сигнализация банка, направляюсь в {city}, район {area} ({map_square}), курс {direction}, запрашиваю свободные юниты по Код 3!'}
for key,text in pairs(followups.templates)do M.defaults[key]=text end
function M.officers(state)
 local c=state and state.colleagues or{};local occupants=c.cruiserOccupants
 if not core.finite(occupants)then occupants=1 end
 local nearby=type(c.nearbyOfficers)=='table'and #c.nearbyOfficers or 0
 return math.max(1,math.min(21,math.floor(occupants)),nearby+1)
end
function M.isRp(key)return M.rpKeys[key]or key=='wanted_rp'or key=='combat_rp'end
function M.validRp(text)
 if type(text)~='string'then return false end
 local count=0
 for line in(text..'\n'):gmatch('(.-)\n')do if line~=''then
  local cmd,body=line:match('^(/%l+)%s+(.+)$')
  if not({['/me']=true,['/do']=true,['/try']=true,['/todo']=true})[cmd]or not body then return false end
  count=count+1
 end end
 return count>0
end
return M

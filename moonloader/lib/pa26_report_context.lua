-- Shared report values from observed crew. A planned roster is never occupancy.
local patrol=require 'pa26_patrol_settings'
local core=require 'pa26_core'
local M={}
local unknown={['']=true,['неизвестно']=true,['не определено']=true,['не определён']=true,['не определен']=true}
function M.directionKnown(values)
 if type(values)~='table'or values.directionKnown~=nil and type(values.directionKnown)~='boolean'then return false end
 local value=values.direction
 if values.directionKnown==false or type(value)~='string'or #value>512 or not core.validUtf8(value)or value:find('[%c{}]')then return false end
 value=value:match('^%s*(.-)%s*$')
 return not unknown[value]and value~='Неизвестно'and value~='Не определено'and value~='Не определён'and value~='Не определен'
end
M.fields={{'unit','Юнит'},{'crew','Экипаж'},{'city','Город'},{'area','Район'},{'map_square','Квадрат'},{'direction','Последний курс'}}
function M.apply(values,override)
    if override==nil then return values end
    if type(override)~='table'then return nil,'Проверьте данные доклада.'end
    for _,r in ipairs(M.fields)do
        local text=override[r[1]]
        if text~=nil then
            if type(text)~='string'or not core.validUtf8(text)or #text>512 or not text:match('%S')or text:find('[%c{}]')then return nil,'Заполните поле «'..r[2]..'» без команд, переносов и переменных.'end
            values[r[1]]=text
            if r[1]=='direction'then values.directionKnown=not unknown[text]end
        end
    end
    return values
end
function M.values(state,profile,cfg)
    state=state or{};profile=profile or{};cfg=cfg or{}
    local out={};local count=patrol.crewCount(state,state.verifiedCrew)
    local name=profile.name~=''and profile.name or state.my_name or state.my_nick
    if not name or name==''then name='Не задано'end
    local names={(name:gsub('_',' '))}
    for _,p in ipairs((state.colleagues or{}).patrolCrew or{})do
        if p.name and #names<count then names[#names+1]=(p.ic_name and p.ic_name~=''and p.ic_name or p.name:gsub('_',' '))end
    end
    out.unit=cfg.unit and cfg.unit~=''and cfg.unit or profile.callsign and profile.callsign~=''and profile.callsign or
        patrol.autoUnit(profile,state,count,cfg.unit_number)
    out.station=cfg.station and cfg.station~=''and cfg.station or(state.colleagues or{}).station or profile.department or'Не задано'
    out.crew=table.concat(names,', ');out.unit_crew_count=tostring(count)
    local grammar=cfg.grammar or patrol.grammarDefaults();local form=count>=2 and'team'or'solo'
    for _,key in ipairs({'start','resume','finish','moving','available'})do
        out['patrol_'..key]=core.expandGender(grammar[key..'_'..form],state.gender or profile.gender)
    end
    return out
end
local function replace(text,needle,value)return(text:gsub(needle:gsub('([^%w])','%%%1'),value))end
local stock
function M.stockTemplate(text)
 if not stock then
  stock={}
  local function collect(value)
   if type(value)=='table'then for _,child in pairs(value)do collect(child)end
   elseif type(value)=='string'then stock[value]=true;for line in(value..'\n'):gmatch('(.-)\n')do if line~=''then stock[line]=true end end end
  end
  for _,name in ipairs({'pa26_copilot_settings','pa26_vehicle_settings','pa26_patrol_settings'})do collect(require(name).defaults())end
  collect(require('pa26_preferences').patrolDefaults())
 end
 return stock[text]==true
end
function M.directionTemplate(text,values,isStock)
    if type(text)~='string'or not text:find('%S')then return nil,'Не задан текст доклада.'end
    if type(values)~='table'then return nil,'Нет данных для подготовки доклада.'end
    if M.directionKnown(values)or not text:find('{direction}',1,true)then return text end
    if isStock==nil then isStock=M.stockTemplate(text)end
    if not isStock then return nil,'Курс не наблюдался. В вашем шаблоне есть {direction}: уточните курс в данных доклада либо измените шаблон. Личный текст сохранён.'end
    -- Omit direction-dependent clauses of stock and unchanged legacy wording.
    for _,clause in ipairs({', {patrol_moving} на {direction}',', двигаюсь на {direction}',
        ', двигаемся на {direction}',', последний курс {direction}',', курс {direction}',
        ', последний курс — {direction}',', направление: {direction}'})do text=replace(text,clause,'')end
    text=replace(text,'{patrol_moving} на {direction}','{patrol_moving}')
    text=replace(text,'направляюсь на {direction} в','направляюсь в')
    text=replace(text,'Двигаюсь на {direction}, ','')
    if text:find('{direction}',1,true)then return nil,'Для этого доклада нужен наблюдавшийся курс. Уточните данные перед отправкой.'end
    return text
end
return M

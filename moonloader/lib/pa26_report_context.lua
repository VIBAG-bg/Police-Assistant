-- Shared report values from observed crew. A planned roster is never occupancy.
local patrol=require 'pa26_patrol_settings'
local core=require 'pa26_core'
local M={}
M.fields={{'unit','Юнит'},{'crew','Экипаж'},{'city','Город'},{'area','Район'},{'map_square','Квадрат'},{'direction','Последний курс'}}
function M.apply(values,override)
    if override==nil then return values end
    if type(override)~='table'then return nil,'Проверьте данные доклада.'end
    for _,r in ipairs(M.fields)do
        local text=override[r[1]]
        if text~=nil then
            if type(text)~='string'or not core.validUtf8(text)or #text>512 or not text:match('%S')or text:find('[%c{}]')then return nil,'Заполните поле «'..r[2]..'» без команд, переносов и переменных.'end
            values[r[1]]=text
            if r[1]=='direction'then values.directionKnown=text~='неизвестно'end
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
function M.directionTemplate(text,values)
    if values.directionKnown~=false and values.direction and values.direction~=''and values.direction~='не определено'then return text end
    -- Omit direction-dependent clauses of stock and unchanged legacy wording.
    for _,clause in ipairs({', {patrol_moving} на {direction}',', двигаюсь на {direction}',
        ', двигаемся на {direction}',', последний курс {direction}',', курс {direction}',
        ', последний курс — {direction}',', направление: {direction}'})do text=replace(text,clause,'')end
    text=replace(text,'{patrol_moving} на {direction}','{patrol_moving}')
    text=replace(text,'направляюсь на {direction} в','направляюсь в')
    text=replace(text,'Двигаюсь на {direction}, ','')
    text=replace(text,'на {direction}','')
    return text
end
return M

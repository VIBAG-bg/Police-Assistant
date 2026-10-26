local shared=require 'pa26_patrol_settings'
local core=require 'pa26_core'
local M={}
M.variables=shared.copy(shared.variables)
M.vehicleFields={model=true,model_id=true,vehicle_id=true,vehicle_color=true,color_one=true,color_two=true,vehicle_description=true}
for _,k in ipairs({'model','model_id','vehicle_id','vehicle_color','color_one','color_two','direction','vehicle_description'})do M.variables[k]=true end
M.actions={{'traffic_stop','Начать трафик-стоп 10-55'},{'pursuit','Начать преследование'},{'megaphone','Обратиться в мегафон'},{'finish','Завершить остановку / погоню'},{'approach','Подойти к остановленной машине'},{'window','Спросить об открытом окне'}}
M.keys={{'select_shortcut','Выбрать машину и подтвердить 10-55'},{'pursuit_shortcut','Подтвердить преследование'},{'megaphone_shortcut','Открыть выбор реплик мегафона'}}
M.phraseCount=8
M.phraseConditions={{'any','Всегда'},{'vehicle','Из служебной машины'},{'foot','Пешком'},{'stop','Во время 10-55'},{'pursuit','Во время погони'}}
for i=1,M.phraseCount do M.keys[#M.keys+1]={'phrase_'..i..'_shortcut','Мегафон · требование '..i}end
function M.defaults()
    local out={enabled=false,require_patrol=true,megaphone_enabled=false,megaphone_require_patrol=false,megaphone_require_duty=true,
        megaphone_require_radio=false,megaphone_wheel=true,radius=40,retain_distance=200,approach_distance=6,front_only=true,occupied_only=true,scan_ms=250,
        selection_mode='auto',selection_ranking='direction',cone_angle=65,height_tolerance=0,
        direction_enabled=true,manual_direction='',motion_ms=300,stationary_distance=.15,max_motion_distance=100,stationary='На месте',
        directions={'Север','Северо-восток','Восток','Юго-восток','Юг','Юго-запад','Запад','Северо-запад'},
        channel='/r',megaphone_channel='/m',confirmation_ms=30000,model_aliases={},color_aliases={},
        pause_patrol_reports=true,pursuit_periodic=true,pursuit_confirmation=true,pursuit_interval_ms=60000,
        traffic_stop_template='{local_tag}{unit}, провожу трафик-стоп 10-55. {vehicle_description}. Экипаж: {crew}. Район: {area}. Далее недоступен.',
        pursuit_template='{local_tag}{unit}, начинаю преследование 10-57 VICTOR. {vehicle_description}. Район: {area}. Направление: {direction}. Экипаж: {crew}.',
        pursuit_periodic_template='{local_tag}{unit}, продолжаю преследование 10-57 VICTOR. {vehicle_description}. Район: {area}. Направление: {direction}.',
        megaphone_template='Водитель автомобиля {model}, говорит {station}. Немедленно остановитесь у обочины и выключите двигатель.',
        finish_template='{local_tag}{unit}, остановка / преследование {model} завершено. Район: {area}. Далее доступен.',
        approach_template='подойдя к машине, коснулся заднего фонаря и, держа руку у кобуры, направился к водителю.',
        window_template='Открыто ли окно со стороны водителя?',
        unknown_model='Модель не определена',unknown_color='Цвет не определён',color_separator=' / ',
        description_template='{model}, цвет: {vehicle_color}'}
    out.phrases={}
    local initial={
        {'Остановиться','Водитель автомобиля {model}, говорит {station}. Остановитесь у обочины и выключите двигатель.'},
        {'Оставаться в машине','Водитель автомобиля {model}, оставайтесь в машине. Держите руки на руле и ожидайте указаний сотрудника {station}.'},
        {'Освободить дорогу','Говорит {station}. Водитель автомобиля {model}, освободите дорогу для служебного транспорта.'},
        {'Уступите дорогу','Говорит {station}. Уступите дорогу служебному транспорту и освободите полосу движения.','none'},
        {'Прижмитесь к обочине','Говорит {station}. Водители, снизьте скорость и прижмитесь к правой обочине. Пропустите служебный транспорт.','none'},
        {'Освободите территорию','Говорит {station}. Освободите территорию и держитесь на безопасном расстоянии. Следуйте указаниям сотрудников.','none'}}
    for i=1,M.phraseCount do
        local p=initial[i]
        out.phrases[i]={enabled=p~=nil,name=p and p[1]or('Требование '..i),template=p and p[2]or'Водитель автомобиля {model}, говорит {station}.',channel='/m',condition='any',target=p and p[3]or'vehicle'}
    end
    for i,row in ipairs(M.keys)do out[row[1]]={key=i<=3 and 0x36+i or 0,ctrl=false,alt=i<=3,shift=false}end
    return out
end
function M.template(value)
    local v=shared.text(value,768)
    if not v or v==''or v:match('^[/@]')then return nil,'Нужна реплика без /команды и перевода строки.'end
    local rest=core.stripGender(v):gsub('{([a-z_]+)}',function(k)return M.variables[k]and ''or '{'end)
    if rest:find('[{}]')then return nil,'Неизвестная переменная транспорта.'end
    return v
end
function M.validate(raw)
    local out=M.defaults();if raw==nil then return out end
    if type(raw)~='table'then return nil,'Повреждены настройки транспорта.'end
    if raw.selection_mode~=nil then out.selection_mode=raw.selection_mode end
    if not({auto=true,vehicle=true,camera=true,screen=true})[out.selection_mode]then return nil,'Проверьте режим выбора машины.'end
    if raw.selection_ranking~=nil then out.selection_ranking=raw.selection_ranking end
    if out.selection_ranking~='direction'and out.selection_ranking~='distance'then return nil,'Проверьте порядок машин в списке.'end
    for _,r in ipairs({{'cone_angle',10,120},{'height_tolerance',0,30}})do
        local n=raw[r[1]];if n==nil then n=out[r[1]]end
        if not shared.integer(n,r[2],r[3])then return nil,'Проверьте настройку выбора: '..r[1]end;out[r[1]]=n
    end
    for _,k in ipairs({'enabled','require_patrol','front_only','occupied_only','direction_enabled','pause_patrol_reports','pursuit_periodic','pursuit_confirmation'})do
        if raw[k]~=nil then if type(raw[k])~='boolean'then return nil,'Неверный переключатель: '..k end;out[k]=raw[k]end
    end
    -- The old transport switch remains authoritative for an old profile.
    out.megaphone_enabled=out.enabled
    for _,k in ipairs({'megaphone_enabled','megaphone_require_patrol','megaphone_require_duty','megaphone_require_radio','megaphone_wheel'})do
        if raw[k]~=nil then if type(raw[k])~='boolean'then return nil,'Неверный переключатель мегафона: '..k end;out[k]=raw[k]end
    end
    for _,row in ipairs({{'radius',5,100},{'retain_distance',30,1000},{'approach_distance',2,15},{'scan_ms',100,2000},{'motion_ms',100,2000},
        {'max_motion_distance',20,500},{'confirmation_ms',1000,60000},{'pursuit_interval_ms',1000,3600000}})do
        local n=raw[row[1]];if n==nil then n=out[row[1]]end
        if not shared.integer(n,row[2],row[3])then return nil,'Неверное значение: '..row[1]end;out[row[1]]=n
    end
    if out.retain_distance<out.radius then return nil,'Дальность удержания должна быть не меньше дальности выбора.'end
    out.stationary_distance=raw.stationary_distance or out.stationary_distance
    if not core.finite(out.stationary_distance)or out.stationary_distance<.05 or out.stationary_distance>5 then return nil,'Порог движения: от 0.05 до 5 м.'end
    out.manual_direction=shared.text(raw.manual_direction or '',120);if not out.manual_direction then return nil,'Неверное ручное направление.'end
    for _,k in ipairs({'channel','megaphone_channel'})do
        out[k]=raw[k]or out[k]
        if k=='channel'and out[k]~='/r'and out[k]~='/f'and out[k]~='/d'or k=='megaphone_channel'and out[k]~='/m'and out[k]~='/s'then return nil,'Выберите предусмотренный канал связи.'end
    end
    for _,k in ipairs({'stationary','unknown_model','unknown_color','color_separator'})do
        out[k]=shared.text(raw[k]or out[k],120)
        if not out[k]or out[k]==''then return nil,'Заполните подпись: '..k end
    end
    for _,k in ipairs({'traffic_stop','pursuit','pursuit_periodic','megaphone','finish','approach','window','description'})do
        local err;out[k..'_template'],err=M.template(raw[k..'_template']or out[k..'_template']);if not out[k..'_template']then return nil,err end
    end
    local description=core.stripGender(out.description_template):gsub('{([a-z_]+)}',function(k)
        return({model=true,model_id=true,vehicle_id=true,vehicle_color=true,color_one=true,color_two=true})[k]and ''or '{'
    end)
    if description:find('[{}]')then return nil,'В описании машины доступны модель, ID и цвета.'end
    if raw.directions~=nil then
        if not shared.array(raw.directions,8)or #raw.directions~=8 then return nil,'Нужны восемь подписей направлений.'end
        for i,v in ipairs(raw.directions)do out.directions[i]=shared.text(v,80);if not out.directions[i]or out.directions[i]==''then return nil,'Заполните направление.'end end
    end
    for _,sp in ipairs({{'model_aliases',400,611},{'color_aliases',0,255}})do
        local map=raw[sp[1]]or {};if type(map)~='table'then return nil,'Неверный словарь транспорта.'end
        for k,v in pairs(map)do
            local n=type(k)=='string'and tonumber(k)
            if not n or tostring(n)~=k or not shared.integer(n,sp[2],sp[3])then return nil,'Неверный ID в словаре.'end
            local label=shared.text(v,120);if not label or label==''or label:find('[{}]')then return nil,'Укажите название без переменных.'end
            out[sp[1]][k]=label
        end
    end
    for _,row in ipairs(M.keys)do local v=raw[row[1]]or out[row[1]]
        if type(v)~='table'or not shared.integer(v.key,0,254)or type(v.ctrl)~='boolean'or type(v.alt)~='boolean'or type(v.shift)~='boolean'then return nil,'Неверная клавиша транспорта.'end
        out[row[1]]=shared.copy(v)
    end
    if raw.phrases~=nil then
        if not shared.array(raw.phrases,M.phraseCount)or #raw.phrases~=M.phraseCount then return nil,'Нужно восемь мест для требований в мегафон.'end
        for i,p in ipairs(raw.phrases)do
            if type(p)~='table'or type(p.enabled)~='boolean'then return nil,'Повреждено требование в мегафон.'end
            -- Only untouched unused legacy slots receive the new general examples.
            if p.target==nil and i>=4 and i<=6 and p.enabled==false and p.name=='Требование '..i and
                p.template=='Водитель автомобиля {model}, говорит {station}.'and p.channel=='/m'and p.condition=='any'then
                p=out.phrases[i]
            end
            local name=shared.text(p.name,120);local body,err=M.template(p.template)
            if not name or name==''or not body then return nil,err or 'Укажите название требования.'end
            if p.channel~='/m'and p.channel~='/s'then return nil,'Мегафон: выберите /m или /s.'end
            local condition=false;for _,c in ipairs(M.phraseConditions)do if c[1]==p.condition then condition=true end end
            if not condition then return nil,'Неизвестное условие требования.'end
            local target=p.target or'vehicle'
            if target~='vehicle'and target~='none'then return nil,'Выберите адресата: машина или общее объявление.'end
            if target=='none'then
                for k in body:gmatch('{([a-z_]+)}')do if M.vehicleFields[k]then return nil,'Общее объявление: уберите {'..k..'} или выберите адресата «Выбранная машина».'end end
            end
            out.phrases[i]={enabled=p.enabled,name=name,template=body,channel=p.channel,condition=p.condition,target=target}
        end
    end
    return out
end
return M

-- Server defaults and editable preferences. No evaluated Lua, command guessing
-- or game reads here. Optional extensions preserve existing personal libraries.
local core=require 'pa26_core'
local M={}
local function copy(t) if type(t)~='table' then return t end;local r={};for k,v in pairs(t)do r[k]=copy(v)end;return r end
local function text(v,max)
    if type(v)~='string' or #v>max or not core.validUtf8(v) or v:find('%c') then return nil end
    return v:match('^%s*(.-)%s*$')
end
M.radioVariables={area=true,local_tag=true,global_tag=true,prison_tag=true,callsign=true,city=true,square=true,map_square=true,location=true,
    my_name=true,department=true,rank=true,post=true,officer=true,crew=true,crew_count=true,crew_roles=true,crew_callsigns=true,
    unit=true,station=true,vehicle=true,sector=true,duration=true,patrol_id=true,direction=true,
    model=true,model_id=true,vehicle_id=true,vehicle_color=true,color_one=true,color_two=true,vehicle_description=true}
function M.template(value,allowed)
    value=text(value,768)
    if not value or value=='' or value:match('^[/@]') then return nil,'Нужен однострочный текст без /команды.' end
    local rest=core.stripGender(value):gsub('{([a-z_]+)}',function(k)return allowed[k] and '' or '{' end)
    if rest:find('[{}]') then return nil,'В тексте есть неизвестная переменная.' end
    return value
end
local function flag(out,raw,key)
    if raw[key]~=nil then if type(raw[key])~='boolean' then return nil,'Неверный переключатель: '..key end;out[key]=raw[key] end
    return true
end
local function integer(out,raw,key,min,max)
    local n=raw[key];if n==nil then return true end
    if not core.finite(n) or n~=math.floor(n) or n<min or n>max then return nil,'Неверное значение: '..key end
    out[key]=n;return true
end
local function channel(value) return value=='/r' or value=='/f' or value=='/d' end
function M.helpCommand(value)
    value=text(value,512)
    if not value then return nil,'Команда помощи должна быть одной строкой.'end
    if value==''then return ''end
    local head=value:match('^/([a-z][a-z0-9_]*)%s')or value:match('^/([a-z][a-z0-9_]*)$')
    local chat={r=true,rn=true,d=true,f=true,fn=true,s=true,b=true,o=true,me=true,['do']=true,todo=true,['try']=true}
    if not head or head:match('^pa26')or chat[head]then return nil,'Укажите отдельную серверную команду помощи, а не реплику или команду PA.'end
    local rest=value:gsub('{([a-z_]+)}',function(key)return M.radioVariables[key]and ''or '{'end)
    if rest:find('[{}]')then return nil,'В команде помощи есть неизвестная переменная.'end
    return value
end
function M.patrolDefaults()
    return {enabled=false,mode='police',confirmation=true,hud=true,post='',
        police_interval_ms=600000,prison_interval_ms=600000,police_channel='/r',prison_channel='/r',
        police_template='{local_tag}Продолжаю патруль. 10-20: {area}.',
        prison_template='{prison_tag}Продолжаю службу в охране тюрьмы. Пост: {post}.'}
end
function M.validatePatrol(raw)
    local out=M.patrolDefaults();if raw==nil then return out end
    if type(raw)~='table' then return nil,'Неверные настройки периодических докладов.' end
    for _,k in ipairs({'enabled','confirmation','hud'}) do local ok,err=flag(out,raw,k);if not ok then return nil,err end end
    out.mode=raw.mode or out.mode;if out.mode~='police' and out.mode~='prison' then return nil,'Выберите патруль полиции или охрану тюрьмы.' end
    out.post=text(raw.post or out.post,240);if not out.post then return nil,'Неверное название поста.' end
    for _,kind in ipairs({'police','prison'}) do
        local ok,err=integer(out,raw,kind..'_interval_ms',1000,3600000);if not ok then return nil,err end
        out[kind..'_channel']=raw[kind..'_channel'] or out[kind..'_channel']
        if not channel(out[kind..'_channel']) then return nil,'Канал доклада: /r, /f или /d.' end
        out[kind..'_template'],err=M.template(raw[kind..'_template'] or out[kind..'_template'],M.radioVariables)
        if not out[kind..'_template'] then return nil,err end
    end
    return out
end
function M.extendAlerts(out,raw)
    for _,spec in ipairs({{'shots_enabled',true},{'sos_enabled',true},{'code0_enabled',true},{'code1_enabled',false},{'code4_enabled',false},{'auto_code0',false}}) do
        out[spec[1]]=spec[2];local ok,err=flag(out,raw,spec[1]);if not ok then return nil,err end
    end
    out.code0_health=25;local ok,err=integer(out,raw,'code0_health',5,50);if not ok then return nil,err end
    out.code0_template,err=M.template(raw.code0_template or '{local_tag}CODE 0. Офицер тяжело ранен, нужна срочная помощь. 10-20: {area}.',M.radioVariables)
    if not out.code0_template then return nil,err end
    for _,row in ipairs({{'code1','{local_tag}CODE 1. Отменяю ранее переданный CODE 0. 10-20: {area}.'},
        {'code4','{local_tag}CODE 4. Помощь больше не требуется. 10-20: {area}.'}})do
        local value=raw[row[1]..'_template'];if value==nil then value=row[2]end
        out[row[1]..'_template'],err=M.template(value,M.radioVariables)
        if not out[row[1]..'_template']then return nil,err end
    end
    for _,kind in ipairs({'shots','sos','code0','code1','code4'}) do
        -- Empty = inherit the legacy channel, so old /r->/d changes keep working.
        local v=raw[kind..'_channel'] or '';if v~='' and not channel(v) then return nil,'Канал связи: общий, /r, /f или /d.' end
        out[kind..'_channel']=v
    end
    out.help_enabled=false;out.help_verified=false;out.help_delay_ms=1500
    for _,key in ipairs({'help_enabled','help_verified'})do local ok;ok,err=flag(out,raw,key);if not ok then return nil,err end end
    ok,err=integer(out,raw,'help_delay_ms',1000,10000);if not ok then return nil,err end
    local command=raw.help_command;if command==nil then command=''end
    out.help_command,err=M.helpCommand(command);if not out.help_command then return nil,err end
    local source=raw.help_source;if source==nil then source=''end
    out.help_source=text(source,240);if not out.help_source then return nil,'Укажите, где проверили команду помощи.'end
    if out.help_enabled and(not out.help_verified or out.help_command==''or out.help_source=='')then
        return nil,'Для команды помощи нужны точное название, источник и ваша отметка проверки на сервере.'
    end
    out.patrol,err=M.validatePatrol(raw.patrol);if not out.patrol then return nil,err end
    return out
end
-- Every real GTA handheld weapon/tool has its own editable alias and one /me.
-- Grenade types on a custom server need an explicit mapping; GTA ID 17 is tear gas.
M.weaponCatalog={
    {1,'Кастет','надев кастет, сжал кулак и оглянулся по сторонам.'},
    {2,'Клюшка для гольфа','перехватив рукоять клюшки, опустил её перед собой и осмотрелся.'},
    {3,'Дубинка','сняв дубинку с поясного крепления, перехватил рукоять и осмотрелся по сторонам.'},
    {4,'Нож','достав нож из ножен, уверенно перехватил рукоять и опустил клинок.'},
    {5,'Бейсбольная бита','взяв бейсбольную биту, поправил хват и оглянулся вокруг.'},
    {6,'Лопата','взял лопату за черенок и опустил её перед собой.'},
    {7,'Бильярдный кий','перехватил кий за рукоять и осмотрелся по сторонам.'},
    {8,'Катана','придерживая ножны, плавно извлёк катану и опустил клинок.'},
    {9,'Бензопила','взяв бензопилу за рукоятки, проверил хват и осмотрелся.'},
    {10,'Dildo 1','взял предмет «{weapon}» в руку и осмотрелся.'},
    {11,'Dildo 2','взял предмет «{weapon}» в руку и осмотрелся.'},
    {12,'Vibrator 1','взял предмет «{weapon}» в руку и осмотрелся.'},
    {13,'Vibrator 2','взял предмет «{weapon}» в руку и осмотрелся.'},
    {14,'Цветы','аккуратно взял букет за стебли и поправил цветы.'},
    {15,'Трость','взял трость за рукоять и опёрся на неё.'},
    {16,'Граната','снял гранату с поясного крепления и осмотрелся, оставив чеку на месте.'},
    {17,'Газовая граната','достав газовую гранату из подсумка, осмотрел её корпус и удержал в руке.'},
    {18,'Коктейль Молотова','взял бутылку с зажигательной смесью и осторожно удержал её в руке.'},
    {22,'Colt 45','оглянувшись по сторонам, аккуратно извлёк {weapon} из кобуры и проверил хват.'},
    {23,'Тайзер','оглянувшись по сторонам, извлёк {weapon} из кобуры и проверил хват.'},
    {24,'Desert Eagle','держа руку у кобуры, осмотрелся и аккуратно извлёк пистолет {weapon}.'},
    {25,'Shotgun','сняв {weapon} с плеча, проверил хват и перевёл оружие в боевое положение.'},
    {26,'Sawn-off Shotgun','достав обрез {weapon}, крепко перехватил рукоять и осмотрелся.'},
    {27,'Combat Shotgun','сняв {weapon} с плеча, проверил хват и перевёл оружие в боевое положение.'},
    {28,'Micro SMG','снял {weapon} с ремня, перехватил рукоять и осмотрелся по сторонам.'},
    {29,'MP5','снял {weapon} с ремня, выключил предохранитель и проверил обстановку вокруг.'},
    {30,'AK-47','сняв {weapon} с плеча, выключил предохранитель и осмотрелся по сторонам.'},
    {31,'M4','сняв {weapon} с плеча, выключил предохранитель и осмотрелся по сторонам.'},
    {32,'Tec-9','взяв {weapon}, проверил хват и направил ствол в безопасную сторону.'},
    {33,'Rifle','сняв {weapon} с плеча, проверил хват и осмотрелся по сторонам.'},
    {34,'Sniper Rifle','сняв {weapon} с плеча, проверил хват и осмотрелся по сторонам.'},
    {35,'Rocket Launcher','взяв {weapon}, устроил гранатомёт на плече и проверил пространство перед собой.'},
    {36,'Heat Seeker','взяв {weapon}, устроил пусковую установку на плече и осмотрелся.'},
    {37,'Flamethrower','взял огнемёт за рукоятки и осмотрел пространство перед собой.'},
    {38,'Minigun','крепко перехватил рукоятки {weapon} и направил стволы в безопасную сторону.'},
    {39,'Заряд C4','достал заряд C4 и осмотрел его корпус.'},
    {40,'Детонатор','достав детонатор, осмотрел его и удержал в ладони.'},
    {41,'Баллончик','взяв баллончик, снял защитный колпачок и осмотрел распылитель.'},
    {42,'Огнетушитель','взял огнетушитель за рукоятку и осмотрел пломбу.'},
    {43,'Камера','взяв камеру, поправил ремень и проверил объектив.'},
    {44,'Прибор ночного видения','взяв прибор ночного видения, проверил его крепления.'},
    {45,'Тепловизор','взяв тепловизор, проверил его крепления.'},
    {46,'Парашют','поправил лямки парашюта и проверил крепления страховочной системы.'},
}
function M.weaponDefaults()
    local out={enabled=false,delay_ms=5000,cooldown_ms=10000,repeat_ms=30000,holster_enabled=true,holster_delay_ms=1500,items={}}
    local common={[3]=true,[16]=true,[17]=true,[22]=true,[23]=true,[24]=true,[25]=true,[29]=true,[31]=true,[34]=true}
    for _,w in ipairs(M.weaponCatalog) do
        local pistol=w[1]>=22 and w[1]<=24;local long=w[1]>=25 and w[1]<=38
        out.items[tostring(w[1])]={enabled=common[w[1]]==true,name=w[2],template=w[3],holster_enabled=pistol or long or w[1]==3,
            holster_template=pistol and 'убедившись в безопасности, убрал {weapon} в кобуру и застегнул фиксатор.'or long and
                'поставил {weapon} на предохранитель и, придерживая ремень, вернул оружие за плечо.'or 'закончив использовать предмет, аккуратно убрал его и осмотрелся по сторонам.'}
    end
    out.items['23'].name='SD Pistol';out.items['23'].template='оглянувшись по сторонам, извлёк {weapon} из кобуры и проверил хват.'
    out.items['31'].name='M4A1';out.items['31'].template='сняв {weapon} с плеча, выключил предохранитель и осмотрелся по сторонам.'
    out.items['3'].holster_template='опустив дубинку, вернул её на поясное крепление и осмотрелся по сторонам.'
    for _,id in ipairs({'35','36','37','38'})do out.items[id].holster_template='опустил {weapon} и, проверив крепления, аккуратно убрал оружие.'end
    return out
end
M.grenadePresets={gas={name='Газовая граната',template='достав газовую гранату из подсумка, осмотрел её корпус и удержал в руке.'},
    smoke={name='Дымовая граната',template='достав дымовую гранату из подсумка, осмотрел её корпус и удержал в руке.'},
    flash={name='Светошумовая граната',template='достав светошумовую гранату из подсумка, осмотрел её корпус и удержал в руке.'}}
function M.validateWeapons(raw)
    local out=M.weaponDefaults();if raw==nil then return out end
    if type(raw)~='table' or type(raw.items)~='table' then return nil,'Неверные настройки оружия.' end
    local ok,err=flag(out,raw,'enabled');if not ok then return nil,err end
    ok,err=flag(out,raw,'holster_enabled');if not ok then return nil,err end
    ok,err=integer(out,raw,'holster_delay_ms',1000,10000);if not ok then return nil,err end
    for _,sp in ipairs({{'delay_ms',1000,30000},{'cooldown_ms',1000,120000},{'repeat_ms',1000,300000}}) do
        ok,err=integer(out,raw,sp[1],sp[2],sp[3]);if not ok then return nil,err end
    end
    for key,value in pairs(raw.items) do
        if not out.items[key] or type(value)~='table' or type(value.enabled)~='boolean' then return nil,'Неизвестное оружие или неверная отметка.' end
        local name=text(value.name,96);local tpl;tpl,err=M.template(value.template,{weapon=true})
        if not name or name=='' or name:find('[{}]') or not tpl then return nil,err or 'Неверное название оружия.' end
        local holster=value.holster_enabled;if holster==nil then holster=out.items[key].holster_enabled end
        local putback;putback,err=M.template(value.holster_template or out.items[key].holster_template,{weapon=true})
        if type(holster)~='boolean'or not putback then return nil,err or 'Неверная отыгровка убирания оружия.'end
        out.items[key]={enabled=value.enabled,name=name,template=tpl,holster_enabled=holster,holster_template=putback}
    end
    return out
end
function M.taserDefaults()
    return {enabled=true,hud=true,weapon_id=24,activation='command',command='/taser',active_reply='',inactive_reply='',reply_timeout_ms=10000,
        name='Taser X26',draw_template='осмотревшись, извлёк {weapon} из кобуры и направил ствол в безопасную сторону.',
        holster_template='убедившись в безопасности, убрал {weapon} в кобуру и застегнул фиксатор.',capacity=2,cooldown_ms=5000,auto_reload=true,
        reload_template='извлёк использованные картриджи, установил новые и проверил крепление тайзера.'}
end
function M.validateTaser(raw)
    local out=M.taserDefaults();if raw==nil then return out end
    if type(raw)~='table' then return nil,'Неверные настройки тайзера.' end
    -- A saved legacy profile keeps its previous weapon mapping until explicitly changed.
    out.activation=raw.activation or 'weapon'
    if out.activation~='weapon'and out.activation~='command'then return nil,'Выберите определение тайзера: оружие или серверная команда.'end
    out.command=text(raw.command or '/tazer',48) -- Older saved profiles had no command field; keep their normalization.
    if not out.command or not out.command:match('^/[a-z][a-z0-9_]*$')or out.command:match('^/pa26')then return nil,'Нужна отдельная серверная команда тайзера без аргументов.'end
    for _,key in ipairs({'active_reply','inactive_reply','name'})do
        out[key]=text(raw[key]or out[key],240);if not out[key]then return nil,'Проверьте текст настройки тайзера.'end
    end
    if out.name==''or out.active_reply~=''and out.active_reply==out.inactive_reply then return nil,'Имя тайзера не должно быть пустым; ответы включения и выключения должны различаться.'end
    for _,key in ipairs({'draw_template','holster_template'})do local err
        out[key],err=M.template(raw[key]or out[key],{weapon=true});if not out[key]then return nil,err end
    end
    local ok,err=integer(out,raw,'reply_timeout_ms',1000,30000);if not ok then return nil,err end
    for _,k in ipairs({'enabled','hud','auto_reload'}) do local ok,err=flag(out,raw,k);if not ok then return nil,err end end
    for _,sp in ipairs({{'weapon_id',22,34},{'capacity',1,10},{'cooldown_ms',1000,15000}}) do local ok,err=integer(out,raw,sp[1],sp[2],sp[3]);if not ok then return nil,err end end
    local err;out.reload_template,err=M.template(raw.reload_template or out.reload_template,{})
    if not out.reload_template then return nil,err end
    return out
end
function M.weaponName(cfg,id)
    if id==0 then return 'Без оружия' end
    local item=cfg and cfg.items and cfg.items[tostring(id)]
    return item and item.name or ('Weapon '..tostring(id))
end
function M.radioGuardDefaults()
    return {lead_ms=30000,toast_ms=10000,split_enabled=true,continuation='...',max_lines=6,skip_shortcut={key=0x4e,alt=true,ctrl=false,shift=false},custom={},next_id=1}
end
function M.validateRadioGuard(raw)
    local out=M.radioGuardDefaults();if raw==nil then return out end
    if type(raw)~='table' then return nil,'Неверные настройки предупреждений связи.' end
    for _,sp in ipairs({{'lead_ms',1000,120000},{'toast_ms',1000,20000}}) do
        local ok,err=integer(out,raw,sp[1],sp[2],sp[3]);if not ok then return nil,err end
    end
    local ok,err=flag(out,raw,'split_enabled');if not ok then return nil,err end
    ok,err=integer(out,raw,'max_lines',1,8);if not ok then return nil,err end
    out.continuation=text(raw.continuation or out.continuation,80);if not out.continuation then return nil,'Неверное начало продолжения доклада.'end
    out.skip_shortcut=copy(raw.skip_shortcut or out.skip_shortcut)
    if type(raw.custom)~='table' then return nil,'Нужен список своих автодокладов.' end
    local count,seen=0,{}
    for key in pairs(raw.custom)do
        if not core.finite(key) or key~=math.floor(key) or key<1 or key>16 then return nil,'Максимум 16 своих автодокладов.'end
        count=count+1
    end
    for i=1,count do
        local r=raw.custom[i]
        if type(r)~='table' or not core.finite(r.id) or r.id<1 or r.id>999999999 or r.id~=math.floor(r.id) or seen[r.id] then return nil,'Неверный ID автодоклада.'end
        seen[r.id]=true
        local name=text(r.name,160);local tpl,err=M.template(r.template,M.radioVariables)
        if not name or name=='' or not tpl or not channel(r.channel) or type(r.enabled)~='boolean' or type(r.confirmation)~='boolean' then return nil,err or 'Проверьте имя, канал и переключатели доклада.'end
        local item={id=r.id,name=name,template=tpl,channel=r.channel,enabled=r.enabled,confirmation=r.confirmation}
        local ok;ok,err=integer(item,r,'interval_ms',1000,3600000)
        if not ok or not item.interval_ms then return nil,err or 'Укажите интервал от 1 до 3600 секунд.'end
        out.custom[#out.custom+1]=item
    end
    local biggest=0;for _,r in ipairs(out.custom)do biggest=math.max(biggest,r.id)end
    local nextId=raw.next_id or biggest+1
    if not core.finite(nextId)or nextId~=math.floor(nextId)or nextId<=biggest or nextId>999999999 then return nil,'Неверный счётчик ID автодокладов.'end
    out.next_id=nextId
    return out
end
function M.weaponWarningDefaults()
    local items={};for _,id in ipairs({22,23,24,25,26,27,28,29,30,31,32,33,34,38})do items[tostring(id)]=true end
    return {enabled=true,mode='toast',trigger='aim',trigger_revision=1,delay_ms=5000,toast_ms=10000,cooldown_ms=30000,remember_ms=120000,
        shortcut={key=0x57,alt=true,ctrl=false,shift=false},channel='/s',no_accent=false,items=items,
        taser_template='Предупреждаю: при невыполнении законных требований будет применён тайзер.',
        firearm_template='Предупреждаю о возможном применении оружия. Прекратите опасные действия!'}
end
function M.validateWeaponWarning(raw)
    local out=M.weaponWarningDefaults();if raw==nil then return out end
    if type(raw)~='table' then return nil,'Неверные настройки предупреждения об оружии.'end
    local ok,err=flag(out,raw,'enabled');if not ok then return nil,err end
    if raw.no_accent~=nil then ok,err=flag(out,raw,'no_accent');if not ok then return nil,err end end
    for _,sp in ipairs({{'delay_ms',1000,30000},{'toast_ms',1000,30000},{'cooldown_ms',1000,120000},{'remember_ms',1000,600000}})do
        ok,err=integer(out,raw,sp[1],sp[2],sp[3]);if not ok then return nil,err end
    end
    out.mode=raw.mode or out.mode;if out.mode~='toast' and out.mode~='confirm' then return nil,'Выберите напоминание или Y/N.'end
    out.trigger=raw.trigger or out.trigger
    -- The old stock reminder appeared just for holding a weapon. Move that
    -- legacy setting to aiming once; explicit choices in this release persist.
    if raw.trigger_revision==nil and out.trigger=='stable' then out.trigger='aim' end
    if raw.trigger_revision~=nil and raw.trigger_revision~=1 then return nil,'Неизвестная версия настройки прицеливания.'end
    if out.trigger~='aim' and out.trigger~='stable' and out.trigger~='draw' then return nil,'Неизвестный момент напоминания.'end
    out.channel=raw.channel or out.channel;if out.channel~='/s' and out.channel~='' then return nil,'Предупреждение: /s либо обычная речь.'end
    out.shortcut=copy(raw.shortcut or out.shortcut)
    for _,key in ipairs({'taser_template','firearm_template'})do out[key],err=M.template(raw[key] or out[key],{weapon=true});if not out[key]then return nil,err end end
    if type(raw.items)~='table' then return nil,'Выберите оружие для напоминаний.'end
    for key,value in pairs(raw.items)do
        if out.items[key]==nil or type(value)~='boolean' then return nil,'Неверная отметка оружия для предупреждения.'end
        out.items[key]=value
    end
    return out
end
M.copy=copy
return M

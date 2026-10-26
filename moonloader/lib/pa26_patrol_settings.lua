-- Optional personal patrol preferences. No game state or source-rule mutations.
local core=require 'pa26_core'
local M={}
function M.copy(v)if type(v)~='table'then return v end;local out={};for k,x in pairs(v)do out[k]=M.copy(x)end;return out end
function M.text(v,max)
    if type(v)~='string'or #v>max or not core.validUtf8(v)or v:find('%c')then return nil end
    return v:match('^%s*(.-)%s*$')
end
function M.array(t,max)
    if type(t)~='table'then return false end;local n=0
    for k in pairs(t)do if type(k)~='number'or k~=math.floor(k)or k<1 or k>max then return false end;n=n+1 end
    return n==#t
end
function M.integer(n,min,max)return core.finite(n)and n==math.floor(n)and n>=min and n<=max end
M.variables={area=true,local_tag=true,prison_tag=true,global_tag=true,callsign=true,city=true,square=true,map_square=true,location=true,
    my_name=true,department=true,rank=true,post=true,officer=true,crew=true,crew_count=true,crew_roles=true,crew_callsigns=true,
    unit=true,station=true,vehicle=true,sector=true,duration=true,patrol_id=true,direction=true}
function M.template(s)
    s=M.text(s,768)
    if not s or s==''or s:match('^[/@]')then return nil,'Нужен текст без команды и перевода строки.'end
    local rest=core.stripGender(s):gsub('{([a-z_]+)}',function(k)return M.variables[k]and ''or '{'end)
    if rest:find('[{}]')then return nil,'Неизвестная переменная патруля.'end
    return s
end
M.actions={'start','resume','finish','crew'}
M.shortcutNames={{'toggle_shortcut','Начать патруль / открыть патруль'},{'pause_shortcut','Пауза / продолжение патруля'},
    {'finish_shortcut','Завершить патруль'}}
function M.defaults()
    local out={enabled=false,hud=true,restore_offer=true,pause_on_crew_change=true,periodic=true,reporter_self=true,
        confirmation=true,interval_ms=600000,channel='/r',mode='police',station='',unit='',vehicle='',sector='',post='',
        bind_distance=60,crew={},
        start_template='{local_tag}{unit}: начинаю патрулирование. Экипаж: {crew}. 10-20: {area}.',
        resume_template='{local_tag}{unit}: продолжаю патрулирование. Экипаж: {crew}. 10-20: {area}.',
        finish_template='{local_tag}{unit}: патрулирование завершено. Время на службе: {duration}.',
        crew_template='{local_tag}{unit}: состав экипажа изменён. Экипаж: {crew}.',
        periodic_template='{local_tag}{unit}: продолжаю службу. Экипаж: {crew}. 10-20: {area}.'}
    for _,row in ipairs(M.shortcutNames)do out[row[1]]={key=0,ctrl=false,alt=false,shift=false}end
    return out
end
function M.validate(raw)
    local out=M.defaults();if raw==nil then return out end
    if type(raw)~='table'then return nil,'Повреждены настройки сеанса патруля.'end
    for _,k in ipairs({'enabled','hud','restore_offer','pause_on_crew_change','periodic','confirmation','reporter_self'})do
        if raw[k]~=nil then if type(raw[k])~='boolean'then return nil,'Неверный переключатель патруля: '..k end;out[k]=raw[k]end
    end
    for _,row in ipairs({{'interval_ms',1000,3600000},{'bind_distance',5,100}})do
        local n=raw[row[1]]or out[row[1]];if not M.integer(n,row[2],row[3])then return nil,'Неверное значение: '..row[1]end;out[row[1]]=n
    end
    out.channel=raw.channel or out.channel;if out.channel~='/r'and out.channel~='/f'and out.channel~='/d'then return nil,'Канал патруля: /r, /f или /d.'end
    out.mode=raw.mode or out.mode;if out.mode~='police'and out.mode~='prison'and out.mode~='foot'then return nil,'Неверный вид службы.'end
    for _,k in ipairs({'station','unit','vehicle','sector','post'})do
        out[k]=M.text(raw[k]or out[k],120);if not out[k]then return nil,'Неверный текст поля: '..k end
    end
    for _,k in ipairs({'start','resume','finish','crew','periodic'})do
        local err;out[k..'_template'],err=M.template(raw[k..'_template']or out[k..'_template']);if not out[k..'_template']then return nil,err end
    end
    for _,row in ipairs(M.shortcutNames)do
        local v=raw[row[1]]or out[row[1]]
        if type(v)~='table'or not M.integer(v.key,0,254)or type(v.ctrl)~='boolean'or type(v.alt)~='boolean'or type(v.shift)~='boolean'then return nil,'Неверная клавиша патруля.'end
        out[row[1]]=M.copy(v)
    end
    if raw.crew~=nil then
        if not M.array(raw.crew,8)then return nil,'В экипаже может быть до 8 напарников.'end
        local ids={};out.crew={}
        for _,r in ipairs(raw.crew)do
            if type(r)~='table'or not M.integer(r.contact_id,1,999999999)or ids[r.contact_id]then return nil,'Неверный контакт экипажа.'end
            local name,role=M.text(r.ic_name or '',120),M.text(r.role or 'Напарник',80)
            if not name or not role or role==''then return nil,'Проверьте имя и роль напарника.'end
            ids[r.contact_id]=true;out.crew[#out.crew+1]={contact_id=r.contact_id,ic_name=name,role=role}
        end
    end
    return out
end
function M.duration(ms)
    local sec=math.floor(math.max(0,ms or 0)/1000)
    return string.format('%02d:%02d:%02d',math.floor(sec/3600),math.floor(sec/60)%60,sec%60)
end
return M

-- Data only. No commands are enabled by upgrading an existing library.
local shared=require 'pa26_patrol_settings'
local core=require 'pa26_core'
local M={MAX_CARDS=96,MAX_HISTORY=48}
M.keys={{'open_shortcut','Открыть окно помощников'},{'megaphone_shortcut','Открыть свои требования в мегафон'},{'evidence_shortcut','Открыть фиксацию доказательств'},{'training_shortcut','Открыть обучение'}}
M.noticeFields={{'started_title','Заголовок начала','Взаимодействие начато'},
    {'ended_title','Заголовок завершения','Взаимодействие завершено'},
    {'started_detail','Выбор человека','Саспект выбран.'},{'other_detail','Другая причина','Выбор снят.'},
    {'manual','Выбор снят вручную','Выбор снят вручную.'},{'identity','Личность изменилась','ID или личность игрока изменились.'},
    {'session','Подключение изменилось','Подключение к серверу изменилось.'},{'distance','Человек далеко','Игрок слишком далеко.'},
    {'local_unavailable','Ваш персонаж недоступен','Ваш персонаж недоступен.'},{'timer','Сброс таймера','Игровой таймер изменился.'},
    {'changed','Выбран другой человек','Выбран другой игрок.'},{'disconnected','Человек вышел с сервера','Игрок вышел с сервера.'}}
function M.noticeDefaults()
    local d={started_ms=10000,ended_ms=15000,disconnected_ms=20000,max_cards=3}
    for _,r in ipairs(M.noticeFields)do d[r[1]]=r[3]end;return d
end
function M.defaults()
    local out={evidence={enabled=false,time_enabled=false,time_command='/time',time_verified=false,time_source='',
        delay_ms=1500,timeout_ms=60000,confirmation_ms=30000,
        prompt='Нажмите F8 в игре, затем откройте помощник и укажите полный путь к созданному снимку.',
        file_hint='Полный путь к новому PNG или JPG. PA проверит файл; нажатие клавиши само по себе не считается сохранённым снимком.'},
        training={enabled=true,limit=10,department='all',next_id=1,cards={},progress={}},history={},interaction=M.noticeDefaults()}
    for _,r in ipairs(M.keys)do out[r[1]]={key=0,ctrl=false,alt=false,shift=false}end
    out.open_shortcut={key=0x73,ctrl=false,alt=false,shift=false}
    return out
end
local function text(v,max,multiline)
    if not multiline then return shared.text(v,max)end
    if type(v)~='string'or #v>max or not core.validUtf8(v)or v:gsub('\n',''):find('%c')then return nil end
    return v:match('^%s*(.-)%s*$')
end
-- A revision key, not a cryptographic signature. Include boundaries to avoid concatenation ambiguity.
function M.revision(c)
    local s=table.concat({c.question,c.answer,c.source,c.revision,c.department},'\0');local a,b=1,0
    for i=1,#s do a=(a+s:byte(i))%65521;b=(b+a)%65521 end
    return tostring(b*65536+a)..':'..#s
end
function M.validate(raw)
    local out=M.defaults();if raw==nil then return out end
    if type(raw)~='table'then return nil,'Повреждены настройки помощников.'end
    if raw.interaction~=nil then
        local d=raw.interaction;if type(d)~='table'then return nil,'Повреждены карточки взаимодействия.'end
        for _,r in ipairs({{'started_ms',1000,120000},{'ended_ms',1000,120000},{'disconnected_ms',1000,120000},{'max_cards',1,3}})do
            if not shared.integer(d[r[1]],r[2],r[3])then return nil,'Неверный срок или количество карточек.'end;out.interaction[r[1]]=d[r[1]]
        end
        for _,r in ipairs(M.noticeFields)do
            local value=text(d[r[1]],240,true)
            if r[1]=='started_detail'and(value=='Собеседник выбран.'or value=='Собседник выбран.')then value='Саспект выбран.'end
            if not value or value==''then return nil,'Заполните текст карточки: '..r[2]end
            local rest=value:gsub('{([a-z_]+)}',function(k)return(k=='name'or k=='id')and ''or '{'end)
            if rest:find('[{}]')then return nil,'В карточках доступны {name} и {id}.'end;out.interaction[r[1]]=value
        end
    end
    local e=raw.evidence or out.evidence
    if type(e)~='table'then return nil,'Повреждены настройки фиксации.'end
    for _,k in ipairs({'enabled','time_enabled','time_verified'})do if type(e[k])~='boolean'then return nil,'Неверный переключатель фиксации.'end;out.evidence[k]=e[k]end
    for _,sp in ipairs({{'delay_ms',0,30000},{'timeout_ms',1000,600000},{'confirmation_ms',1000,60000}})do
        if not shared.integer(e[sp[1]],sp[2],sp[3])then return nil,'Неверное время фиксации: '..sp[1]end;out.evidence[sp[1]]=e[sp[1]]
    end
    for _,sp in ipairs({{'time_command',80},{'time_source',512},{'prompt',600},{'file_hint',600}})do
        local value=text(e[sp[1]],sp[2],sp[1]=='prompt'or sp[1]=='file_hint');if not value or(sp[1]~='time_source'and value=='')then return nil,'Заполните поле фиксации: '..sp[1]end;out.evidence[sp[1]]=value
    end
    if not out.evidence.time_command:match('^/[a-zA-Z][a-zA-Z0-9_]*$')then return nil,'Команда времени должна состоять из /имени без аргументов.'end
    if out.evidence.time_enabled and(not out.evidence.time_verified or out.evidence.time_source=='')then return nil,'Сначала подтвердите команду времени по /help или ответу сервера и укажите источник.'end
    local t=raw.training or out.training
    if type(t)~='table'or type(t.enabled)~='boolean'or not shared.integer(t.limit,1,50)or not shared.integer(t.next_id,1,999999999)or
        not({all=true,EPD=true,FBI=true,Alcatraz=true})[t.department]or not shared.array(t.cards,M.MAX_CARDS)or type(t.progress)~='table'then return nil,'Повреждены учебные карточки.'end
    out.training={enabled=t.enabled,limit=t.limit,department=t.department,next_id=t.next_id,cards={},progress={}}
    local ids={}
    for _,c in ipairs(t.cards)do
        if type(c)~='table'or not shared.integer(c.id,1,t.next_id-1)or ids[c.id]or type(c.enabled)~='boolean'or not({all=true,EPD=true,FBI=true,Alcatraz=true})[c.department]then return nil,'Неверный ID или ведомство учебной карточки.'end
        ids[c.id]=true;local n={id=c.id,enabled=c.enabled,department=c.department}
        for _,sp in ipairs({{'name',160},{'question',4096},{'answer',8192},{'source',512},{'revision',160}})do
            n[sp[1]]=text(c[sp[1]],sp[2],sp[1]=='question'or sp[1]=='answer')
            if not n[sp[1]]or sp[1]=='name'and n[sp[1]]==''or c.enabled and n[sp[1]]==''then return nil,'Заполните название, вопрос, ответ, источник и редакцию активной карточки.'end
        end
        out.training.cards[#out.training.cards+1]=n
        local p=t.progress[tostring(c.id)]
        if p~=nil then
            if type(p)~='table'or type(p.revision)~='string'or not shared.integer(p.known,0,1000000)or not shared.integer(p.repeat_count,0,1000000)then return nil,'Повреждён личный прогресс обучения.'end
            if p.revision==M.revision(n)then out.training.progress[tostring(c.id)]=shared.copy(p)end
        end
    end
    if not shared.array(raw.history or {},M.MAX_HISTORY)then return nil,'Слишком большой журнал фиксации.'end
    for _,h in ipairs(raw.history or {})do
        if type(h)~='table'or type(h.demo)~='boolean'or type(h.verified)~='boolean'or not({verified=true,cancelled=true,timeout=true,demo=true})[h.status]then return nil,'Повреждён журнал фиксации.'end
        local n={demo=h.demo,verified=h.verified,status=h.status}
        if h.verified~=(h.status=='verified')or h.demo and h.verified then return nil,'Неверная отметка снимка.'end
        for _,sp in ipairs({{'date',80},{'label',160},{'path',1024},{'details',512}})do n[sp[1]]=text(h[sp[1]],sp[2]);if not n[sp[1]]then return nil,'Неверный текст журнала фиксации.'end end
        out.history[#out.history+1]=n
    end
    for _,row in ipairs(M.keys)do
        local v=raw[row[1]]or out[row[1]]
        if type(v)~='table'or not shared.integer(v.key,0,254)or type(v.ctrl)~='boolean'or type(v.alt)~='boolean'or type(v.shift)~='boolean'then return nil,'Неверная клавиша помощника.'end
        out[row[1]]=shared.copy(v)
    end
    return out
end
return M

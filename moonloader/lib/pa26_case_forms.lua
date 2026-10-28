-- Manual IC/OOC procedure forms. No sanction calculation or guessed server API.
local core=require 'pa26_core'
local rp=require 'pa26_rp_text'
local model=require 'pa26_bindings'
local shared=require 'pa26_patrol_settings'
local prefs=require 'pa26_procedure_settings'
local catalog=require 'pa26_wanted_catalog'
local M={};local Forms={};Forms.__index=Forms
local function accountKind(kind)return kind=='wanted'or kind=='mark'or kind=='clear'end
function M.enabled(cfg,kind)
    if kind=='wanted'or kind=='wanted_list'then return cfg.wanted_assistant_enabled and cfg.wanted_enabled end
    return cfg.enabled and cfg[kind..'_enabled']
end
local function safe(s)
    return s and s.session and core.finite(s.ped)and s.alive==true and s.focused==true and s.paused==false and
        s.blocked==false and not s.recording and not s.editingHud and not s.draggingHud
end
function M.new(env)return setmetatable({env=env,serial=0,offerSerial=0,consumed=0,life=1,
    runToken=tostring(os.time())..':'..tostring({}),reminders=model.copy(env.reminders and env.reminders()or {}),reminderDue={}},Forms)end
function Forms:begin(kind,explicitWanted)
    local cfg=self.env.settings();local target,stamp=self.env.target()
    if accountKind(kind)and self.env.wantedTarget then target=explicitWanted or self.env.wantedTarget();stamp=nil end
    if not prefs.names[kind]then return nil,'Неизвестная процедура.'end
    if not M.enabled(cfg,kind)then return nil,'Включите эту форму в её настройках.'end
    if not safe(self.state)then return nil,'Закройте игровой ввод и дождитесь доступной игровой сцены.'end
    local valid=accountKind(kind)and self.env.validWantedTarget or self.env.validTarget
    if kind~='wanted_list'and(not target or not valid(target,stamp))then
        return nil,(kind=='wanted'or kind=='mark')and self.env.validWantedTarget and 'Укажите ID подключённого игрока либо выберите человека рядом.'or 'Сначала выберите доступного человека рядом.'
    end
    if (kind=='wanted'or kind=='wanted_list')and type(self.state.inVehicle)~='boolean'then return nil,'Не удалось определить, находитесь ли вы в машине. Создайте форму после обновления сцены.'end
    if kind=='wanted_list'then target=nil;stamp=nil end
    self.serial=self.serial+1
    local r
    if accountKind(kind)and self.env.wantedIdentity then r=self.env.wantedIdentity(target)
    else r=self.env.identity();r=r and r.record
        if r and(not target or r.stamp~=stamp or r.target.id~=target.id or r.target.name~=target.name or r.target.ped~=target.ped)then r=nil end
    end
    local f={id=self.serial,life=self.life,kind=kind,mode='ic',stage='identity',target=model.copy(target),stamp=stamp,
        session=self.state.session,ped=self.state.ped,demo=self.state.demo,localId=self.state.localId,local_nick=self.state.local_nick,
        passport_seen=r and r.passport_seen or 'unknown',mask=r and r.mask or 'unknown',face_before=r and r.face_before or 'unknown',
        ic_name=r and r.ic_name or '',passport_number=r and r.passport_number or '',appearance=r and r.appearance or '',
        phone_known=r and r.phone_known or 'unknown',phone_number=r and r.phone_number or '',phone_source=r and r.phone_source or '',
        identity_nonce=r and r.nonce,identity_version=r and r.version,passport_source=r and r.passport_source,article='',part='',basis='',amount='',ooc_ack=false,
        reason_id='',reason_group='01',facts='',ooc_reason='tracking',life_ack=false,inVehicle=self.state.inVehicle,
        phone_active='unknown',prior_ic_stars='unknown',clear_ic_safe=false}
    if kind=='wanted_list'then f.stage='preview'end
    if kind=='wanted'then
        -- A previous identity note cannot certify uninterrupted sight in this
        -- particular wanted procedure. Ask again under the current mask rule.
        if f.mask=='yes'then f.face_before='unknown'end
        self:fillWanted(f)
    end
    return f
end
function Forms:validForm(f,committed)
    if not f or f.life~=self.life or not committed and f.id<=self.consumed or not safe(self.state)or f.session~=self.state.session or f.ped~=self.state.ped or
        f.demo~=self.state.demo or f.localId~=self.state.localId or f.local_nick~=self.state.local_nick or
        f.kind~='wanted_list'and not (accountKind(f.kind)and self.env.validWantedTarget or self.env.validTarget)(f.target,f.stamp)then return false end
    local cfg=self.env.settings();if not M.enabled(cfg,f.kind)then return false end
    if (f.kind=='wanted'or f.kind=='wanted_list')and f.inVehicle~=self.state.inVehicle then return false end
    if f.identity_nonce then
        local r
        if accountKind(f.kind)and self.env.wantedIdentity then r=self.env.wantedIdentity(f.target)
        else r=self.env.identity();r=r and r.record end
        if not r or r.nonce~=f.identity_nonce or r.version~=f.identity_version then return false end
    end
    return true
end
-- No native API here: GUI changes only the editable draft. Accepted proposals
-- keep a frozen copy and are invalidated by any newer account/passport evidence.
function Forms:fillWanted(f)
    if not f or f.kind~='wanted'then return end
    local cfg=self.env.settings()
    if self.env.wantedIdentity and f.stage=='identity'then
        local r=self.env.wantedIdentity(f.target)
        if r and(r.nonce~=f.identity_nonce or r.version~=f.identity_version)then
            f.identity_nonce=r.nonce;f.identity_version=r.version
            f.passport_seen=r.passport_seen or f.passport_seen;f.passport_source=r.passport_source
            for _,key in ipairs({'ic_name','passport_number','appearance'})do if(f[key]or '')==''and(r[key]or '')~=''then f[key]=r[key]end end
        end
    end
    if f.passport_seen=='yes'and cfg.wanted_autofill_passport and f.target then
        if(f.ic_name or ''):match('^%s*$')then f.ic_name=f.target.name:gsub('_',' ')end
        if cfg.wanted_id_as_passport and(f.passport_number or ''):match('^%s*$')then f.passport_number=tostring(f.target.id)end
    end
end
function Forms:oocSuggested(f)
    local cfg=self.env.settings()
    return f and f.kind=='wanted'and f.mode=='ic'and cfg.allow_ooc and cfg.wanted_suggest_ooc and
        f.mask=='yes'and f.passport_seen=='no'and f.face_before~='yes' or false
end
function Forms:chooseOoc(f)
    if not self:validForm(f)or not self:oocSuggested(f)then return nil,'Предложение OOC устарело. Проверьте сведения заново.'end
    f.mode='ooc';f.ooc_ack=false;return true
end
function Forms:branch(f)
    self:fillWanted(f)
    if not self:validForm(f)then return nil,'Выбор человека, сведения или игровая сцена изменились. Создайте форму заново.'end
    local cfg=self.env.settings()
    if f.kind=='wanted_list'then return 'list'end
    if f.kind=='clear'then
        local r=self:reminder(f.chain_token)
        if not r or r.status~='located'or r.prior_ic_stars~='no'or not f.clear_ic_safe or
            r.player_id~=f.target.id or r.player_name~=f.target.name or r.generation~=f.target.generation or r.session~=tostring(self.state.session)then
            return nil,'Снятие заблокировано: подтвердите результат пеленгации и отсутствие иных IC-звёзд. Старая запись не должна стирать розыск.'
        end
        return 'chain'
    end
    if f.kind=='wanted'and cfg.wanted_require_life_ack and f.life_ack~=true then return nil,'Подтвердите, что основание относится к текущей ситуации после вашей последней смерти.'end
    if f.mode=='ooc'then
        if f.kind=='fine'or not cfg.allow_ooc then return nil,'OOC-ветка отключена.'end
        if f.ooc_ack~=true then return nil,'Подтвердите выбор отдельной OOC-процедуры. Она не устанавливает IC-личность или источник данных.'end
        if f.kind=='wanted'or f.kind=='mark'then
            if f.phone_active~='yes'then return nil,'Проверьте в игре, что телефон включён.'end
            if f.kind=='wanted'and f.prior_ic_stars~='no'then return nil,'До технических звёзд проверьте исходный IC-розыск. При существующих IC-звёздах используйте пеленгацию без технического /su и не снимайте их через эту цепочку.'end
            if f.kind=='wanted'and f.ooc_reason~='tracking'then return nil,'По действующей редакции OOC-звёзды разрешены только для RP-пеленгации через /setmark; /pt и Alcatraz исключены.'end
            if f.phone_known~='yes'or not shared.text(f.phone_number,120)or f.phone_number:match('^%s*$')or
                not shared.text(f.phone_source,120)or f.phone_source:match('^%s*$')then
                return nil,'Для OOC-пеленгации укажите известный по RP номер телефона и источник; ID игрока не является телефоном.'
            end
        end
        return 'ooc'
    end
    if f.mode~='ic'then return nil,'Выберите IC или OOC.'end
    if f.kind=='mark'then
        if f.phone_active~='yes'then return nil,'Проверьте, что известный IC-телефон включён.'end
        if f.phone_known~='yes'then return nil,'Уточните, известен ли номер вашему персонажу. SA:MP ID не является IC-телефоном.'end
        for _,key in ipairs({'phone_number','phone_source'})do
            local value=shared.text(f[key],120)
            if not value or value==''then return nil,key=='phone_number'and 'Укажите известный IC-номер.'or 'Укажите, откуда вашему персонажу известен номер.'end
        end
        return 'ic'
    end
    if f.kind=='fine'and cfg.fine_unmasked and f.mask~='no'then
        return nil,f.mask=='yes'and 'В выбранной политике штрафа нужно открытое лицо. Сначала установите личность / снимите маску по правилам.'or 'Уточните, открыто ли лицо человека.'
    end
    if f.kind=='wanted'then
        if f.mask~='yes'and f.mask~='no'then return nil,'Уточните, есть ли RP-маска: одновременно /mask и визуально скрытое лицо.'end
        if f.mask=='yes'and f.face_before~='yes'then return nil,'Для IC-розыска в RP-маске подтвердите, что личность установлена до маски и человек не пропадал из вида. Один прежний паспорт этого не подтверждает.'end
    end
    if f.passport_seen=='unknown'then return nil,'Сначала ответьте, видели ли вы паспорт.'end
    if f.passport_seen=='yes'then
        if not shared.text(f.ic_name,120)or f.ic_name:match('^%s*$')then return nil,'Укажите IC-имя из документа.'end
        return 'passport'
    end
    if f.passport_seen~='no'then return nil,'Неверный ответ о паспорте.'end
    if f.mask~='yes'and f.mask~='no'then return nil,'Уточните, есть ли на человеке маска.'end
    if f.mask=='yes'and f.face_before~='yes'then
        return nil,f.face_before=='unknown'and 'Видели ли вы лицо до маски?'or 'IC-личность не установлена; розыск по этой ветке может нарушать RP. При допустимой ситуации выберите отдельную OOC-ветку.'
    end
    local appearance=type(f.appearance)=='string'and f.appearance:gsub('%s+',' '):match('^%s*(.-)%s*$')or ''
    if appearance==''and f.kind~='wanted'then return nil,'Опишите известные вашему персонажу приметы.'end
    return 'appearance'
end
function Forms:next(f)
    if f.stage=='identity'then
        local branch,err=self:branch(f);if not branch then return nil,err end
        f.branch=branch
        f.stage=f.kind=='wanted'and branch=='appearance'and 'appearance_choice'or 'basis'
        return true
    end
    if f.stage=='basis'then local preview,err=self:preview(f);if not preview then return nil,err end;f.stage='preview';return true end
    return false,'Форма уже на итоговом шаге.'
end
function Forms:chooseAppearance(f,mode)
    if not self:validForm(f)or f.kind~='wanted'or (f.stage~='appearance_choice'and f.stage~='appearance_input')then
        return nil,'Форма устарела. Откройте розыск заново.'
    end
    local branch,why=self:branch(f);if branch~='appearance'then return nil,why or 'Сведения о личности изменились.'end
    if mode=='general'then f.appearance_mode='general';f.stage='basis';return true end
    if mode=='detailed'then f.appearance_mode='detailed';f.stage='appearance_input';return true end
    if mode=='back'then f.stage='appearance_choice';return true end
    if mode=='apply'then
        local text=type(f.appearance)=='string'and f.appearance:gsub('%s+',' '):match('^%s*(.-)%s*$')or ''
        if text==''or not shared.text(text,768)or text:find('*',1,true)then
            return nil,'Введите приметы через запятую, без звёздочки *. Например: высокий, на вид 25 лет.'
        end
        f.appearance=text;f.appearance_mode='detailed';f.stage='basis';return true
    end
    return nil,'Неизвестный вариант отыгровки.'
end
function Forms:values(f)
    if f.kind=='wanted'or f.kind=='wanted_list'then
        local values={id=f.target and tostring(f.target.id)or '',device=f.inVehicle and 'бортовой компьютер'or 'КПК',
            article='',part='',amount='',basis='',ic_name='',passport_number='',appearance='',phone_number='',phone_source='',facts='',
            game_reason='',game_group='',game_stars='',game_category='',game_item='',ooc_purpose=''}
        if f.kind=='wanted_list'then return values end
        local row=catalog.byId[f.reason_id];if not row then return nil,'Выберите раздел и причину из игрового списка.'end
        values.amount=tostring(row.stars);values.game_stars=values.amount;values.game_reason=row.title;values.game_group=row.group_title
        values.game_category=tostring(tonumber(row.group));values.game_item=tostring(tonumber(row.id:sub(4)))
        values.basis=row.id..' · '..row.group_title..' / '..row.title
        for _,key in ipairs({'ic_name','passport_number','appearance','facts','phone_number','phone_source'})do
            local raw=f[key]or ''
            if key=='appearance'or key=='facts'then raw=type(raw)=='string'and raw:gsub('%s+',' '):match('^%s*(.-)%s*$')or raw end
            values[key]=shared.text(raw,key=='appearance'and 768 or key=='facts'and 900 or 120)
            if not values[key]then return nil,'Проверьте текст поля: '..key end
        end
        if f.passport_seen~='yes'then values.ic_name='';values.passport_number=''end
        if f.appearance_mode=='general'then values.appearance=''end
        if f.mode=='ooc'then values.ooc_purpose=prefs.oocNotes[f.ooc_reason]or ''end
        return values
    end
    local amount=''
    if f.kind~='mark'and f.kind~='clear'then
        amount=shared.text(f.amount,9)
        if not amount or not amount:match('^%d+$')or tonumber(amount)<1 or tonumber(amount)>999999999 then return nil,'Введите целое положительное значение вручную. Проверенной таблицы звёзд/сумм пока нет.'end
        amount=tostring(tonumber(amount))
    end
    local out={id=tostring(f.target.id),amount=amount}
    for _,key in ipairs({'basis','article','part','ic_name','passport_number','phone_number','phone_source'})do
        out[key]=shared.text(f[key]or '',key=='basis'and 240 or 120);if not out[key]then return nil,'Неверный текст: '..key end
    end
    if out.basis==''then return nil,f.kind=='mark'and 'Укажите основание / условия пеленгации.'or 'Укажите точное основание, которое должно уйти в команду.'end
    out.appearance=type(f.appearance)=='string'and f.appearance:gsub('%s+',' '):match('^%s*(.-)%s*$')or ''
    if not shared.text(out.appearance,768)then return nil,'Слишком длинное описание примет.'end
    return out
end
function Forms:preview(f)
    local branch,err=self:branch(f);if not branch then return nil,err end
    local values;values,err=self:values(f);if not values then return nil,err end
    local cfg=self.env.settings();local template=cfg[f.kind..'_'..branch..'_rp']
    if f.kind=='wanted_list'then template=cfg.wanted_list_rp
    elseif f.kind=='wanted'then
        if branch=='appearance'and values.appearance==''then template=cfg.wanted_generic_appearance_rp
        elseif branch=='appearance'and f.appearance_mode=='detailed'then template=cfg.wanted_traits_rp end
        if branch=='passport'and values.passport_number~=''then template=template..'\n'..cfg.wanted_passport_number_rp end
        template=(f.inVehicle and cfg.wanted_car_intro_rp or cfg.wanted_foot_intro_rp)..'\n'..template
    end
    if not template then return nil,'Для этой ветки нет RP-заготовки.'end
    local lines,wire={},{};local rpSignature,textSignature
    local rpSettings,nickname;if self.env.rpSettings then rpSettings,nickname=self.env.rpSettings()end
    local function expand(text)
        local missing
        local line=core.expandGender(text,self.state and self.state.gender or(self.env.gender and self.env.gender())):gsub('{([a-z_]+)}',function(k)
            local v=values[k];if not v or v==''then missing=k;return ''end;return v
        end)
        if missing then return nil,'Заполните поле: '..missing end
        return rp.line(line,self.env.codec,rpSettings,nickname)
    end
    for line in(template..'\n'):gmatch('(.-)\n')do
        line=line:gsub('\r$',''):match('^%s*(.-)%s*$')
        if line~=''then
            local pieces={values.appearance or ''}
            if f.kind=='wanted'and branch=='appearance'and f.appearance_mode=='detailed'and cfg.wanted_each_trait and line:find('{appearance}',1,true)then
                pieces={}
                for trait in (values.appearance..','):gmatch('(.-),')do
                    trait=trait:match('^%s*(.-)%s*$')
                    if trait~=''then pieces[#pieces+1]=trait end
                    if #pieces>24 then return nil,'Слишком много примет. Оставьте не более 24 пунктов.'end
                end
            end
            local appearance=values.appearance
            for _,piece in ipairs(pieces)do
                values.appearance=piece
                local prepared,why=expand(line);if not prepared then return nil,why end
                rpSignature=prepared.rpSignature or rpSignature
                textSignature=prepared.textSignature or textSignature
                for i,v in ipairs(prepared.lines)do lines[#lines+1]=v;wire[#wire+1]=prepared.wires[i]end
            end
            values.appearance=appearance
        end
    end
    local rpCount=#lines;local contract=cfg[f.kind..'_command'];local ready=cfg[f.kind..'_verified']and contract~=''
    if f.kind=='wanted'then
        contract=cfg.wanted_send_mode=='direct'and cfg.wanted_direct_command or cfg.wanted_open_command
        ready=contract==(cfg.wanted_send_mode=='direct'and '/su {id} {game_category} {game_item}'or '/su {id}')
    elseif f.kind=='wanted_list'then contract=cfg.wanted_list_command;ready=contract=='/wanted'end
    if contract~=''then
        local prepared,why=expand(contract);if not prepared then return nil,why end
        for i,v in ipairs(prepared.lines)do lines[#lines+1]=v;wire[#wire+1]=prepared.wires[i]end
    end
    if #lines>32 then return nil,'После переноса слишком много частей для процедуры. Сократите RP-шаблон.'end
    return {lines=lines,wire=wire,rpCount=rpCount,rpSignature=rpSignature,textSignature=textSignature,ready=ready,branch=branch,values=values,
        warning=not ready and 'Аргументы серверной команды не проверены. Доступен только отключённый черновик бинда.'or nil,
        kind=f.kind,form=model.copy(f),cfg=model.copy(cfg),gameReason=f.kind=='wanted'and model.copy(catalog.byId[f.reason_id])or nil}
end
function Forms:draft(f,id)
    if f.kind=='wanted'or f.kind=='wanted_list'then return nil,'Для розыска используйте помощник: он заново проверяет личность и открывает серверный список без аргументов статьи или звёзд.'end
    local preview,err=self:preview(f);if not preview then return nil,err end
    local b=model.newBinding(id);b.name=prefs.names[f.kind]..' · '..(preview.ready and 'ручная форма'or 'непроверенный черновик')
    b.category='Процедуры';b.target_required=true;b.enabled=false
    local template=preview.cfg[f.kind..'_'..preview.branch..'_rp']
    if preview.cfg[f.kind..'_command']~=''then template=template..'\n'..preview.cfg[f.kind..'_command']end
    local used={};local labels={amount=f.kind=='wanted'and 'Количество звёзд · вручную'or 'Сумма штрафа · вручную',
        basis='Точное основание',article='Статья',part='Часть статьи',ic_name='Установленное IC-имя',passport_number='Номер паспорта',appearance='Известные приметы',
        phone_number='Номер для пеленгации',phone_source='IC-источник номера'}
    template=template:gsub('{([a-z_]+)}',function(k)
        if k=='id'then return '{id}'end
        used[k]=true;return '{param:'..k..'}'
    end)
    local steps={}
    for line in(template..'\n'):gmatch('(.-)\n')do
        line=line:gsub('\r$',''):match('^%s*(.-)%s*$')
        if line~=''then
            if #steps>0 then steps[#steps+1]='@wait('..preview.cfg.delay_ms..')'end
            steps[#steps+1]=line
        end
    end
    b.script=table.concat(steps,'\n')
    for _,k in ipairs({'amount','basis','article','part','ic_name','passport_number','appearance','phone_number','phone_source'})do if used[k]then
        b.parameters[#b.parameters+1]={name=k,label=labels[k],type=k=='amount'and 'integer'or 'text',required=true,default=''}
    end end
    if #b.parameters>8 then return nil,'В черновике больше восьми отдельных параметров. Сократите набор переменных в настройках процедуры.'end
    return b,preview
end
function Forms:offer(f)
    if self.intent or self.queued or self.awaitingCommand then return nil,'Другая процедура уже ожидает выполнения.'end
    local preview,err=self:preview(f);if not preview then return nil,err end
    if not preview.ready then return nil,preview.warning end
    if f.kind=='wanted'and f.mode=='ooc'and not self.state.demo and #self.reminders>=32 then
        return nil,'Накопилось 32 незавершённых проверки OOC-звёзд. Сначала разберите их во вкладке «Проверки OOC».'
    end
    self.offerSerial=self.offerSerial+1
    preview.token=self.offerSerial;preview.at=self.now;preview.session=self.state.session;preview.ped=self.state.ped;preview.demo=self.state.demo
    if f.kind=='wanted'or f.kind=='wanted_list'then preview.phase='prepare'end
    return preview
end
function Forms:proposalValid(p,committed)
    local age=p and core.elapsed(self.now,p.at)
    return p and age and age<=(committed and p.phase~='command'and 600000 or 60000)and self:validForm(p.form,committed)and self.env.equal(p.cfg,self.env.settings())or false
end
function Forms:accept(p)
    local final=p and p.phase=='command'
    if self.intent or self.queued or final and(not self.awaitingCommand or self.awaitingCommand.token~=p.token)or
        not self:proposalValid(p,final)then return nil,'Предпросмотр устарел или процедура уже запущена.'end
    if final then self.awaitingCommand=nil end
    self.intent=model.copy(p);return true
end
function Forms:validPlan(plan)
    local p=self.queued
    if not p or not plan.caseProcedure or p.token~=plan.caseProcedure.token or not safe(self.state)or self.state.typing or self.state.modal then return false end
    -- Accepted forms are consumed, but the frozen target/evidence still validate.
    local valid=self:proposalValid(p,true)
    if accountKind(p.kind)and p.form.target and p.form.target.account then
        valid=valid and plan.target==nil and plan.wantedSubject and self.env.equal(plan.wantedSubject,p.form.target)
    end
    return valid and table.concat(plan.wire,'\0')==table.concat(p.planWire or p.wire,'\0')or false
end
function Forms:reset(reason)
    local q=self.queued;self.queued=nil;self.intent=nil;self.awaitingCommand=nil;self.message=reason;self.life=self.life+1
    if q and self.env.cancel then self.env.cancel(q.token,reason)end
end
function Forms:tick(state,now)
    if not core.finite(now)or now~=math.floor(now)then self:reset('Игровой таймер недоступен. Создайте форму заново.');self.state=nil;self.now=nil;return end
    local previous=self.state;local delta=self.now and core.elapsed(now,self.now)
    if previous and(not delta or previous.session~=state.session or previous.ped~=state.ped or previous.demo~=state.demo or
        previous.localId~=state.localId or previous.local_nick~=state.local_nick or previous.alive~=state.alive)then
        self:reset('Игровая сцена изменилась. Создайте форму заново.')
    end
    self.state=model.copy(state);self.now=now
    if self.awaitingCommand and not self:proposalValid(self.awaitingCommand,true)then self:reset('Команда розыска отменена: сцена, цель, сведения или настройки изменились.')end
    if self.queued and not self:proposalValid(self.queued,true)then self:reset('Процедура отменена: данные изменились.')end
    local p=self.intent
    if p then
        if not self:proposalValid(p,p.phase=='command')then self.intent=nil;self.message='Процедура отменена: данные изменились.'
        elseif not state.busy and not state.alertPending and not state.wheel and not state.typing and not state.modal then
            self.intent=nil;self.queued=p
            local b=model.newBinding(999999994);b.name=prefs.names[p.kind]..' · ручная форма';b.category='Процедуры';b.target_required=true;b.stat=p.kind=='fine'and 'fine_player'or 'none';b.script=table.concat(p.lines,'\n')
            local steps,sendLines,sendWire={},{},{}
            local count=p.phase=='prepare'and p.rpCount or #p.lines
            for i=1,count do local line=p.lines[i]
                if i>1 then steps[#steps+1]={kind='wait',ms=p.cfg.delay_ms}end
                steps[#steps+1]={kind='message',text=line,wire=p.wire[i]}
                sendLines[#sendLines+1]=line;sendWire[#sendWire+1]=p.wire[i]
            end
            p.planWire=model.copy(sendWire)
            -- The wanted subject is validated by this controller's frozen
            -- online-account contract, independently of physical interaction.
            local account=accountKind(p.kind)and p.form.target and p.form.target.account==true
            local plan={binding=b,requirements={target=p.kind~='wanted_list'and not account,closest=false},target=not account and model.copy(p.form.target)or nil,
                wantedSubject=account and model.copy(p.form.target)or nil,session=p.session,createdAt=now,demo=p.demo,
                has_command=p.phase~='prepare',steps=steps,lines=sendLines,wire=sendWire,rpSignature=p.rpSignature,textSignature=p.textSignature,
                automatic={kind='case_procedure'},caseProcedure={token=p.token,rpCount=p.rpCount}}
            -- Persist a possible OOC obligation before transmitting /su. A crash
            -- after send must leave a check, even when issuance is unconfirmed.
            if p.kind=='wanted'and p.form.mode=='ooc'and p.phase=='command'and not p.demo and self.env.saveReminders then
                self:recordCommand(p);self:flush()
                if self.remindersDirty then
                    self.queued=nil;self.message='Не удалось сохранить проверку OOC-звёзд. Команда не отправлена; проверьте сохранение перед повтором.'
                    if self.env.notice then self.env.notice(self.message)end;return
                end
            end
            local ok,err=self.env.start(plan)
            self.consumed=math.max(self.consumed,p.form.id)
            if not ok then self.queued=nil;self.message='Процедура не запущена: '..tostring(err)..' Создайте новую форму.'end
        end
    end
end
function Forms:onExecution(kind,q,line)
    local p=self.queued;local mark=q and q.plan and q.plan.caseProcedure
    if not p or not mark or mark.token~=p.token then return end
    if kind=='sent_line'and p.phase~='prepare'and line==p.lines[#p.lines]then self:recordCommand(p)end
    if kind=='completed'then
        self.queued=nil;self.message='Строки переданы клиенту. Результат процедуры должен подтвердить сервер.'
        if p.phase=='prepare'then
            local final=model.copy(p);self.offerSerial=self.offerSerial+1
            final.token=self.offerSerial;final.phase='command';final.at=self.now;final.previousRP={}
            for i=1,p.rpCount do final.previousRP[#final.previousRP+1]=p.lines[i]end
            final.lines={p.lines[#p.lines]};final.wire={p.wire[#p.wire]};final.planWire=nil;final.rpCount=0
            self.awaitingCommand=final;self.message='Отыгровка завершена. Команда ждёт отдельного ДА/НЕТ.';return
        end
        if p.kind=='wanted'or p.kind=='wanted_list'then self.message='Команда передана клиенту. Результат выдачи или открытия списка проверьте на сервере.'end
        self:recordCommand(p)
    elseif kind=='cancelled'then self.queued=nil;self.message='Процедура остановлена. Оставшиеся строки не отправятся; автоматического повтора нет.'end
end
function Forms:recordCommand(p)
    if p.recorded or p.demo then return end
    p.recorded=true
    if p.kind=='wanted'and p.form.mode=='ooc'then
            local created=self.env.wall and self.env.wall()or os.time()
            local token='wanted:'..created..':'..self.life..':'..p.token
            while self:reminder(token)do token=token..':1'end
            self.reminders[#self.reminders+1]={token=token,player_id=p.form.target.id,player_name=p.form.target.name,session=tostring(p.session),
                reason=p.values.basis,context=prefs.oocNotes[p.form.ooc_reason],stars=tonumber(p.values.amount),created=created,status='check',
                generation=p.form.target.generation,phone_number=p.form.phone_number,phone_source=p.form.phone_source,prior_ic_stars=p.form.prior_ic_stars,
                actor_life=self.life,actor_run=self.runToken}
            self.reminderDue[token]=self.now+p.cfg.wanted_reminder_delay_ms;self.remindersDirty=true
    elseif p.form.chain_token then
        local r=self:reminder(p.form.chain_token)
        if r then r.status=p.kind=='clear'and'clear_sent'or'mark_sent';self.remindersDirty=true end
    end
end
function Forms:reminder(token)for _,r in ipairs(self.reminders)do if r.token==token then return r end end end
function Forms:changeReminder(token,action)
    local r=self:reminder(token);if not r then return false end
    if action=='issued'and r.status=='check'then r.status='issued'
    elseif action=='located'and r.status=='mark_sent'then r.status='located'
    elseif action=='resolved'then
        for i,v in ipairs(self.reminders)do if v==r then table.remove(self.reminders,i);break end end;self.reminderDue[token]=nil
    else return false end
    self.remindersDirty=true;return true
end
function Forms:chainOffer(token,kind,ack)
    local r=self:reminder(token)
    if not r or (kind~='mark'and kind~='clear')or ack~=true then return nil,'Сначала проверьте условие этой операции.'end
    if kind=='mark'and r.status~='issued'or kind=='clear'and r.status~='located'then return nil,'Сначала подтвердите предыдущий результат в игре.'end
    local target={account=true,id=r.player_id,name=r.player_name,generation=r.generation}
    if r.actor_life~=self.life or r.actor_run~=self.runToken or r.session~=tostring(self.state and self.state.session)or not r.generation or not self.env.validWantedTarget or not self.env.validWantedTarget(target)then
        return nil,'Запись относится к прежнему подключению или ID. Проверьте человека вручную; автоматическая цепочка для старого аккаунта заблокирована. Напоминание сохранено.'
    end
    local f,err=self:begin(kind,target);if not f then return nil,err end
    f.chain_token=token;f.phone_known='yes';f.phone_number=r.phone_number or'';f.phone_source=r.phone_source or''
    f.phone_active='yes';f.prior_ic_stars=r.prior_ic_stars;f.clear_ic_safe=kind=='clear'and ack
    f.basis='RP-пеленгация по известному IC-телефону';f.stage='preview'
    return self:offer(f)
end
function Forms:flush()
    if not self.remindersDirty or not self.env.saveReminders then return end
    local elapsed=self.lastReminderSave and core.elapsed(self.now,self.lastReminderSave)
    if self.lastReminderSave and elapsed and elapsed<10000 then return end
    self.lastReminderSave=self.now
    local ok,err=self.env.saveReminders(model.copy(self.reminders))
    if ok then self.remindersDirty=false;self.lastReminderSave=nil else self.message='Не удалось сохранить проверку OOC-звёзд: '..tostring(err)end
end
function Forms:candidates()
    local cfg=self.env.settings();local out={}
    if not cfg.wanted_reminder_enabled or not safe(self.state)or self.state.demo then return out end
    self.reminderShownAt=self.reminderShownAt or {}
    for i,r in ipairs(self.reminders)do
        local due=self.reminderDue[r.token]
        if not due then self.reminderDue[r.token]=self.now+cfg.wanted_reminder_delay_ms
        elseif core.elapsed(self.now,due)then
            local shown=self.reminderShownAt[r.token];local age=shown and core.elapsed(self.now,shown)
            if shown and(not age or age>=cfg.wanted_reminder_show_ms)then
                self.reminderShownAt[r.token]=nil;self.reminderDue[r.token]=self.now+cfg.wanted_reminder_snooze_ms
            else
            out[#out+1]={owner='wanted',token=r.token,title=cfg.wanted_reminder_title,
                body=cfg.wanted_reminder_text..'\n'..r.player_name..' [ID при записи: '..r.player_id..']\n'..r.reason..'\n'..r.context,
                status=r.status=='issued'and 'Вы отметили выдачу вручную'or 'Выдача не подтверждена · проверьте серверный результат',
                hint='Открыть — список локальных проверок; Позже — отложить. Команды не отправляются. ID мог измениться.',
                mode='action',full=true,unseen=not shown,priority=12,serial=i,remaining=math.max(0,cfg.wanted_reminder_show_ms-(age or 0)),
                duration=cfg.wanted_reminder_show_ms,yes='Открыть',no='Позже',shortcut={key=0,ctrl=false,alt=false,shift=false}}
            end
        end
    end
    return out
end
function Forms:shownReminder(token)if self:reminder(token)then
    self.reminderPainted=token;self.reminderPaintedAt=self.now;self.reminderShownAt=self.reminderShownAt or {}
    self.reminderShownAt[token]=self.reminderShownAt[token]or self.now
end end
function Forms:decideReminder(token,yes)
    local age=self.reminderPaintedAt and core.elapsed(self.now,self.reminderPaintedAt)
    if type(yes)~='boolean'or self.reminderPainted~=token or not age or age>250 or not self:reminder(token)or not safe(self.state)then return false end
    self.reminderDue[token]=self.now+self.env.settings().wanted_reminder_snooze_ms;self.reminderPainted=nil
    self.reminderShownAt[token]=nil
    if yes then self.reviewReminders=true end;return true
end
function Forms:takeCommandConfirmation()
    local p=self.awaitingCommand
    if not p or p.presented or not self:proposalValid(p,true)or self.state.typing or self.state.modal or self.state.busy then return end
    p.presented=true;return model.copy(p)
end
function Forms:cancelCommandConfirmation(token)
    if self.awaitingCommand and self.awaitingCommand.token==token then self:reset('Команда отменена. Отыгровка уже была отправлена; автоматического повтора нет.');return true end
end
function Forms:view()return {pending=self.intent~=nil or self.queued~=nil or self.awaitingCommand~=nil,message=self.message,reminders=model.copy(self.reminders)}end
function Forms:templatePreview(template,f)
    local values={}
    for key in pairs(prefs.variables)do values[key]=f and f[key]or ''end
    values.id=f and f.target and tostring(f.target.id)or ''
    values.device=f and(f.inVehicle and 'бортовой компьютер'or 'КПК')or 'КПК / бортовой компьютер'
    local row=f and catalog.byId[f.reason_id]
    if row then values.game_reason=row.title;values.game_group=row.group_title;values.game_stars=tostring(row.stars);values.amount=tostring(row.stars)end
    local missing=false
    local text=core.expandGender(template,self.state and self.state.gender or(self.env.gender and self.env.gender())):gsub('{([a-z_]+)}',function(key)
        local v=values[key]
        if not v or v==''then missing=true;return '[не заполнено: '..key..']'end
        return tostring(v):gsub('%s+',' ')
    end)
    return text,missing
end
return M

-- Confirmed IC reports. Only main() advances this state machine; rendering and
-- SAMP.Lua callbacks never send chat or inspect native game state.
local core=require 'pa26_core'
local mapGrid=require 'pa26_map_grid'
local rp=require 'pa26_rp_text'
local model=require 'pa26_bindings'
local hudModel=require 'pa26_hud'
local preferences=require 'pa26_preferences'
local menu=require 'pa26_menu'
local M={KEY_Y=0x59,KEY_N=0x4e,FRAME_MS=250,ARM_MS=120}
-- Exsellent's separate help command is blank/disabled until the user checks it.
-- Its text, evidence note, switch and delay are editable in the radio GUI.
local Controller={};Controller.__index=Controller
M.kinds={shots={name='Доклад: Shots fired',title='Сообщить о стрельбе?',short='Shots fired'},sos={name='SOS: запрос поддержки',title='Запросить поддержку?',short='SOS'},
    code0={name='CODE 0: офицер тяжело ранен',title='CODE 0 · срочная помощь?',short='CODE 0'},
    code1={name='CODE 1: отмена CODE 0',title='Отменить ранее переданный CODE 0?',short='CODE 1'},
    code4={name='CODE 4: помощь не требуется',title='Сообщить, что помощь больше не требуется?',short='CODE 4'},
    police={name='Доклад: патруль полиции',title='Передать доклад патруля?'},prison={name='Доклад: охрана тюрьмы',title='Передать доклад с поста?'}}
local function routine(kind)return kind=='police' or kind=='prison'end
function M.kindEnabled(kind,cfg)
    if not M.kinds[kind] then return false end
    if routine(kind) then return cfg.patrol and cfg.patrol.enabled and cfg.patrol.mode==kind end
    return cfg[kind..'_enabled']~=false
end
local function safe(state,mouse)
    return state and state.session and state.alive==true and state.focused==true and state.paused==false and
        state.blocked==false and state.typing~=true and state.recording~=true and state.draggingHud~=true and
        (mouse or state.editingHud~=true)
end
function M.firearm(weapon,includeSd)
    return core.finite(weapon) and weapon==math.floor(weapon) and
        ((weapon>=22 and weapon<=34 and (weapon~=23 or includeSd==true)) or weapon==38)
end
local function reportValues(state,template,enrich)
    state=mapGrid.reportValues(state,template,enrich)
    local out={}
    for key in pairs(preferences.radioVariables) do
        local used=template:find('{'..key..'}',1,true)
        local value='';if used then value=model.clean(state[key] or '',key:match('^crew')and 4096 or(key=='area'or key=='location')and 1024 or 240)end
        if not value then return nil,'Неверное поле доклада: '..key end
        if used and key=='direction'and value==''then value='неизвестно'end
        local tag=key=='local_tag' or key=='prison_tag' or key=='global_tag'
        if value=='' and not tag and template:find('{'..key..'}',1,true) then return nil,'Заполните поле доклада: '..key end
        if tag and value~='' then value=value..' ' end
        out[key]=value
    end
    return out
end
function M.prepare(kind,state,cfg,codec,now,life)
    if not M.kinds[kind] then return nil,'Неизвестный доклад.' end
    local configError;cfg,configError=model.validateAlerts(cfg);if not cfg then return nil,configError end
    if not cfg.enabled or not cfg.on_duty or not M.kindEnabled(kind,cfg) then return nil,'Этот доклад отключён.' end
    if not state.session or not core.finite(state.ped) or type(state.demo)~='boolean' then return nil,'Персонаж недоступен.' end
    if kind=='code0' and (not core.finite(state.health) or state.health<=0 or state.health>cfg.code0_health) then return nil,'CODE 0 доступен только живому тяжело раненому офицеру: HP ≤ '..cfg.code0_health..'.' end
    local source=routine(kind) and cfg.patrol or cfg
    local template=require('pa26_report_context').directionTemplate(source[kind..'_template'],state);local channel=source[kind..'_channel']
    if not channel or channel=='' then channel=cfg.channel end
    local values,err=reportValues(state,template);if not values then return nil,err end
    local body=core.expandGender(template,state.gender):gsub('{([a-z_]+)}',function(key)return values[key]end):match('^%s*(.-)%s*$')
    local line=channel..' '..body
    local ready;ready,err=rp.line(line,codec,state.rpText,state.my_nick);if not ready then return nil,err end
    local binding=model.newBinding(999999999)
    binding.name=M.kinds[kind].name;binding.category='Связь';binding.script=line
    local plan={binding=binding,requirements={target=false,closest=false},target=nil,closest=nil,
        session=state.session,createdAt=now,demo=state.demo,has_command=true,
        steps=ready.steps,lines=ready.lines,wire=ready.wires,rpSignature=ready.rpSignature,textSignature=ready.textSignature,rpExtraSteps=ready.rpSignature and #ready.lines-1 or 0,
        alert={kind=kind,life=life,ped=state.ped,session=state.session,location={area=state.area,map_square=state.map_square,square=state.square}}}
    if kind=='sos'and cfg.help_enabled then
        -- reportValues above deliberately reads only used values. Prepare the extra
        -- command independently so a required argument cannot become an empty string.
        local extraValues;extraValues,err=reportValues(state,cfg.help_command,false);if not extraValues then return nil,err end
        local extraLine=cfg.help_command:gsub('{([a-z_]+)}',function(key)return extraValues[key]end)
        local extra;extra,err=rp.line(extraLine,codec,state.rpText,state.my_nick);if not extra then return nil,err end
        plan.steps[#plan.steps+1]={kind='wait',ms=cfg.help_delay_ms}
        local added;added,err=rp.append(plan,extra);if not added then return nil,err end
    end
    plan.alert.fingerprint=table.concat({state.session,tostring(state.ped),tostring(life),tostring(state.demo),channel,
        template,table.concat(plan.lines,'\n'),routine(kind) and tostring(cfg.patrol.confirmation) or '',
        kind=='code0' and tostring(cfg.code0_health) or '',kind=='sos'and cfg.help_enabled and tostring(cfg.help_delay_ms)or '',
        kind=='sos'and cfg.help_enabled and cfg.help_source or ''},'\0')
    return plan
end
function M.new(env)
    return setmetatable({env=env,life=1,serial=0,cooldowns={},pending=nil,event=nil,state=nil,failed=false},Controller)
end
function Controller:note(text)
    self.status=text;self.statusAt=self.now
    if self.env.log then pcall(self.env.log,text) end
end
function Controller:reset(reason)
    self.life=self.life+1;self.pending=nil;self.event=nil;self.intent=nil;self.guiKeys=nil;self.armed=false
    self.cooldowns={};self.manual=nil;self.criticalWatch=nil
    if reason then self:note(reason) end
end
function Controller:invalidateLife()
    self:reset();self.state=nil -- spawn/disconnect RPC; wait for a fresh main() snapshot.
end
function Controller:takeDamage(id,amount,weapon,bodypart)
    local state=self.state;local cfg=self.env.settings()
    if self.failed or not cfg.enabled or not cfg.on_duty or not ((cfg.auto_shots and cfg.shots_enabled~=false) or (cfg.auto_code0 and cfg.code0_enabled)) or not state or not state.session or not state.alive or state.inReport or
        not core.validId(id) or id==state.localId or not core.finite(amount) or amount<=0 or amount>1000 or
        not M.firearm(weapon,cfg.include_sd) or not core.finite(bodypart) or bodypart~=math.floor(bodypart) or bodypart<3 or bodypart>9 then return false end
    -- The attacker ID is used solely to exclude self/environment damage. It is
    -- never substituted into IC text, selected as a target, looked up or accused.
    if self.event and self.event.life==self.life then self.event.count=math.min(99,self.event.count+1)
    else self.event={life=self.life,at=self.now,count=1,health=state.health} end
    return true
end
function Controller:request(kind)
    if not M.kinds[kind] then return false end
    self.manual=kind;return true -- Accepted intent; preparation happens in main().
end
function Controller:onCooldown(kind)
    local last=self.cooldowns[kind]
    local elapsed=last and core.elapsed(self.now,last)
    return last and (not elapsed or elapsed<self.env.settings().cooldown_ms)
end
function Controller:offer(kind,automatic,count)
    local cfg=self.env.settings()
    if not cfg.enabled or not cfg.on_duty or not M.kindEnabled(kind,cfg) or not self.state or not self.state.session or
        not self.state.alive or not self.state.focused or self.state.paused then return false end
    if self:onCooldown(kind) then if not automatic then self:note('Подождите перед повторным докладом.') end;return false end
    if self.pending and self.pending.kind==kind then self.pending.hits=math.min(99,self.pending.hits+(count or 0));return true end
    if self.pending and not automatic and (kind=='code1'or kind=='code4')and not routine(self.pending.kind)and
        self.pending.kind~='code1'and self.pending.kind~='code4'then
        self:note('Сначала ответьте на открытое экстренное подтверждение.');return false
    end
    if self.pending and automatic and not (routine(self.pending.kind) or
        (kind=='code0' and self.pending.kind=='shots')) then return false end
    local plan,err=M.prepare(kind,self.state,cfg,self.env.codec,self.now,self.life)
    if not plan then if not automatic then self:note('Доклад не подготовлен: '..tostring(err)) end;return false end
    self.serial=self.serial+1
    self.pending={kind=kind,plan=plan,token=self.serial,offeredAt=self.now,updatedAt=self.now,
        hits=count or 0,busy=self.state.busy,automatic=automatic}
    self.armed=false;self.wasY=nil;self.wasN=nil;self.intent=nil
    if self.env.offered then pcall(self.env.offered,kind) end
    return true
end
function Controller:paint(token,now,keys)
    self.guiKeys={y=keys.y,n=keys.n,mods=keys.mods,at=now}
    if self.pending and self.pending.token==token then
        self.pending.drawnAt=now;self.pending.firstPaintAt=self.pending.firstPaintAt or now
    end
end
function Controller:click(token,yes)
    self.intent={token=token,yes=yes};return true
end
function Controller:keys(input)
    if input and input.physical==true then return input end
    local age=self.guiKeys and core.elapsed(self.now,self.guiKeys.at)
    if self.state.window==true then
        if not age or age>M.FRAME_MS then return {y=true,n=true,mods=true} end -- Fail closed, no stale GUI keys.
        return self.guiKeys
    end
    return input or {}
end
function Controller:decide(yes)
    local p=self.pending;self.pending=nil;self.armed=false;self.intent=nil
    if not p then return false end
    if not yes then
        if p.kind=='shots' or p.kind=='code0' then self.cooldowns[p.kind]=self.now end
        self:note('Доклад отменён.');return true
    end
    p.plan.createdAt=self.now
    local ok,result,err=pcall(self.env.confirm,model.copy(p.plan),p.busy~=nil)
    if ok and result==true then
        self.cooldowns[p.kind]=self.now
        self:note(p.plan.demo and 'Демо: доклад подтверждён, отправок не будет.' or 'Доклад подтверждён; подготовка отправки.')
    else self:note('Доклад не запущен: '..tostring(ok and err or 'ошибка подготовки.')) end
    return true
end
function Controller:tick(state,now,input)
    if self.failed or not core.finite(now) or now~=math.floor(now) then self:reset();return false end
    local delta=self.now and core.elapsed(now,self.now)
    self.now=now
    if self.state and (not delta or self.state.session~=state.session or self.state.ped~=state.ped or self.state.alive~=state.alive or self.state.demo~=state.demo) then self:reset() end
    self.state=state
    local cfg=self.env.settings()
    if not cfg.enabled or not cfg.on_duty or not state.session or not state.alive or not state.focused or state.paused then
        self.pending=nil;self.event=nil;self.manual=nil;self.intent=nil;self.armed=false;self.criticalWatch=nil;return false
    end
    local event=self.event;self.event=nil
    local manual=self.manual;self.manual=nil
    if manual then self:offer(manual,false,0)
    elseif event and event.life==self.life then
        local age=core.elapsed(now,event.at)
        if age and age<=M.FRAME_MS then
            if cfg.auto_code0 and cfg.code0_enabled then self.criticalWatch=event end
            -- Amount includes armour and is not an HP loss. A critical offer
            -- needs a real, fresh health drop after a verified firearm event.
            local critical=cfg.auto_code0 and cfg.code0_enabled and core.finite(event.health) and
                core.finite(state.health) and state.health>0 and state.health<=cfg.code0_health and state.health<event.health
            if critical then self:offer('code0',true,event.count)
            elseif cfg.auto_shots and cfg.shots_enabled~=false then
                if self.pending and self.pending.kind=='shots' then self.pending.hits=math.min(99,self.pending.hits+event.count)
                else self:offer('shots',true,event.count) end
            end
        end
    end
    local watch=self.criticalWatch
    if watch then
        local age=core.elapsed(now,watch.at)
        if not cfg.auto_code0 or not cfg.code0_enabled or watch.life~=self.life or not age or age>1000 then self.criticalWatch=nil
        elseif core.finite(watch.health) and core.finite(state.health) and state.health>0 and state.health<=cfg.code0_health and state.health<watch.health then
            self.criticalWatch=nil
            if not self.pending or self.pending.kind~='code0' then self:offer('code0',true,watch.count)end
        end
    end
    local p=self.pending;if not p then self.intent=nil;return false end
    local age=core.elapsed(now,p.offeredAt)
    if not age or age>=cfg.timeout_ms then
        if p.kind=='shots' or p.kind=='code0' then self.cooldowns[p.kind]=now end
        self.pending=nil;self.intent=nil;self:note('Время подтверждения истекло. Отправок нет.');return false
    end
    local fresh,err=M.prepare(p.kind,state,cfg,self.env.codec,now,self.life)
    if not fresh then self.pending=nil;self.intent=nil;self:note('Доклад отменён: '..tostring(err));return false end
    if fresh.alert.fingerprint~=p.plan.alert.fingerprint or state.busy~=p.busy then
        self.serial=self.serial+1;p.token=self.serial;p.plan=fresh;p.busy=state.busy;p.updatedAt=now;p.drawnAt=nil;p.firstPaintAt=nil
        self.armed=false;self.wasY=nil;self.wasN=nil;self.intent=nil
    end
    local keys=self:keys(input);local painted=p.drawnAt and core.elapsed(now,p.drawnAt)
    if state.keyboardAvailable~=false then p.waitRelease=(keys.y or keys.n) and not self.armed or false end
    local ready=p.firstPaintAt and core.elapsed(now,p.firstPaintAt)
    local keyboard=safe(state,false) and not keys.mods and painted and painted<=M.FRAME_MS and ready and ready>=M.ARM_MS
    local intent=self.intent;self.intent=nil
    if intent and intent.token==p.token and type(intent.yes)=='boolean' and safe(state,true) and
        state.mouseAllowed and painted and painted<=M.FRAME_MS and ready and ready>=M.ARM_MS then return self:decide(intent.yes) end
    local risingY=keys.y==true and self.wasY==false
    local risingN=keys.n==true and self.wasN==false
    self.wasY=keys.y==true;self.wasN=keys.n==true
    if not keyboard then self.armed=false
    elseif not keys.y and not keys.n then self.armed=true
    elseif self.armed and (risingY or risingN) then
        if keys.y and keys.n then self.armed=false
        elseif risingN then return self:decide(false)
        elseif risingY then return self:decide(true) end
    end
    return keys.y==true or keys.n==true -- While a card exists, these keys belong to its confirmation.
end
function Controller:validPlan(plan)
    if not plan.alert then return true end
    local state=self.state;local cfg=self.env.settings()
    if self.failed or not cfg.enabled or not cfg.on_duty or not state or not safe(state,true) or
        plan.alert.life~=self.life or plan.session~=state.session or plan.demo~=state.demo or plan.alert.ped~=state.ped then return false end
    if plan.alert.started then
        state=model.copy(state)
        for _,k in ipairs({'area','map_square','square'})do state[k]=plan.alert.location[k]end
    end
    local fresh=M.prepare(plan.alert.kind,state,cfg,self.env.codec,self.now,self.life)
    return fresh and fresh.alert.fingerprint==plan.alert.fingerprint or false
end
function Controller:updateContext(state)
    local previous=self.state
    if not previous or previous.session~=state.session or previous.ped~=state.ped or previous.demo~=state.demo or previous.alive~=state.alive then
        self:invalidateLife();return false
    end
    -- Patrol reconciliation may change the crew after input was read. The final
    -- executor guard must see that fresh context before handing a line to SA:MP.
    self.state=model.copy(state);return true
end
function Controller:onExecution(kind,q)
    if not q.plan.alert then return end
    if kind=='sent_line'or kind=='preview_line'then q.plan.alert.started=true end
    if kind=='completed' then self:note(q.demo and 'Демо завершено: отправок 0.' or 'Доклад передан клиенту.')
    elseif kind=='cancelled' then self:note('Отправка доклада остановлена.') end
end
function Controller:visible()
    local cfg=self.env.settings();local s=self.state
    return not self.failed and cfg.enabled and cfg.on_duty and s and s.session and s.alive and s.focused and not s.paused
end
local function inside(r,x,y)
    return r and core.finite(x) and core.finite(y) and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h
end
function Controller:measure(im,hud,fonts)
    self.bounds=nil;self.suppressHud=false
    if not self:visible() then hud:setConfirmationHeight(0);self.metrics=nil;return end
    local io=im.GetIO();local r=hud:layout(io.DisplaySize.x,io.DisplaySize.y)
    if not r or io.DisplaySize.x<480 or io.DisplaySize.y<360 then hud:setConfirmationHeight(0);self.metrics=nil;return end
    local s=math.max(.7,math.min(r.scale,1.25));local w=math.min(r.w,420*s)
    w=math.max(240*s,math.min(w,io.DisplaySize.x-24));local pad=12*s;local wrap=w-2*pad
    local body=fonts.body or im.GetFont();local heading=fonts.heading or body
    local m={scale=s,w=w,pad=pad,wrap=wrap,lines={},body=body,heading=heading,shortcuts={},shortcutH=0}
    local bindings=self.env.shortcuts and self.env.shortcuts()or model.alertShortcutDefaults()
    local cfg=self.env.settings();m.quick={}
    for _,kind in ipairs(model.alertKinds)do if M.kindEnabled(kind,cfg)then m.quick[#m.quick+1]=kind end end
    local columns=math.min(3,#m.quick);local bw=columns>0 and(w-(columns+1)*8*s)/columns or w
    for _,kind in ipairs(m.quick)do
        m.shortcuts[kind]=model.shortcutName(bindings[kind])
        m.shortcutH=math.max(m.shortcutH,body:CalcTextSizeA(11*s,100000,bw-8*s,m.shortcuts[kind]).y)
    end
    m.columns=math.max(1,columns);m.rowH=46*s+m.shortcutH
    local rows=math.max(1,math.ceil(#m.quick/m.columns))
    m.cursor=self.state.cursorHint or 'Удерживайте Alt — курсор для кнопок'
    m.cursorLayout=menu.labelLayout(heading,14*s,wrap,m.cursor)
    m.cursorH=m.cursorLayout.height;m.cursorTop=rows*m.rowH
    m.bar=m.cursorTop+m.cursorH+12*s;m.h=m.bar
    local p=self.pending
    if p then
        m.title=M.kinds[p.kind].title
        m.titleH=heading:CalcTextSizeA(16*s,100000,wrap,m.title).y
        m.h=m.bar+8*s+2*pad+m.titleH+8*s
        for _,line in ipairs(p.plan.lines) do
            local height=body:CalcTextSizeA(14*s,100000,wrap-16*s,line).y
            m.lines[#m.lines+1]={text=line,h=height};m.h=m.h+height+16*s
        end
        if p.busy then m.busy='ДА остановит текущий сценарий.';m.busyH=body:CalcTextSizeA(13*s,100000,wrap,m.busy).y;m.h=m.h+m.busyH+6*s end
        m.h=m.h+34*s+24*s+7*s
    elseif self.statusAt and (core.elapsed(self.now,self.statusAt) or 8000)<8000 then
        -- Feedback belongs only to this HUD lane, never to unrelated windows.
        m.feedback=self.status;m.feedbackH=body:CalcTextSizeA(12*s,100000,wrap,m.feedback).y;m.h=m.h+m.feedbackH+12*s
    end
    self.metrics=m;hud:setConfirmationHeight(m.h)
    -- Predict the exact shared HUD lane before underlying windows draw. This
    -- prevents a click through the newly appeared confirmation into their buttons.
    local lane=hud:attachmentLayout(im,fonts)
    if lane then local b=lane.confirmation;self.bounds={x=b.x+(b.w-m.w)/2,y=b.y,w=m.w,h=m.h}
    else
        self.suppressHud=p~=nil -- Temporarily prioritize confirmation when both cannot fit.
        self.bounds={x=math.max(12,io.DisplaySize.x-m.w-16),y=math.max(12,math.min(72,io.DisplaySize.y-m.h-12)),w=m.w,h=m.h}
    end
    if m.h>io.DisplaySize.y-24 or m.w>io.DisplaySize.x-24 then self.bounds=nil end
end
function Controller:overWidget(im)
    if not self:visible() then return false end
    local io=im.GetIO();return inside(self.bounds,io.MousePos.x,io.MousePos.y)
end
function Controller:draw(im,hud,fonts)
    self.buttons={}
    if not self.metrics or not self:visible() then return end
    local io=im.GetIO();local m=self.metrics;local s,pad=m.scale,m.pad
    local box=self.bounds;if not box then return end
    if box.h>io.DisplaySize.y-24 or box.w>io.DisplaySize.x-24 then return end
    self.bounds=box
    local list,vec=im.GetForegroundDrawList(),im.ImVec2
    local function tint(r,g,b,a)return im.ColorConvertFloat4ToU32(im.ImVec4(r,g,b,a or 1))end
    local white,muted=tint(.98,.99,1),tint(.74,.84,.93)
    local mouse=safe(self.state,true) and self.state.mouseAllowed
    local function text(value,font,size,x,y,width,color)
        list:AddTextFontPtr(font,size*s,vec(x,y),color or white,value,nil,width)
    end
    local function button(id,label,x,y,w,h,color)
        local r={x=x,y=y,w=w,h=h};self.buttons[id]=r
        local hover=inside(r,io.MousePos.x,io.MousePos.y)
        list:AddRectFilled(vec(x,y),vec(x+w,y+h),color,8*s)
        if mouse and hover then list:AddRect(vec(x,y),vec(x+w,y+h),tint(.8,.92,1,.65),8*s,im.DrawCornerFlags.All,1*s) end
        local extent=m.heading:CalcTextSizeA(14*s,100000,w-8*s,label)
        text(label,m.heading,14,x+(w-extent.x)/2,y+(h-extent.y)/2,w-8*s)
        return mouse and hover and im.IsMouseClicked(0)
    end
    local x,y,w=box.x,box.y,box.w
    list:AddRectFilled(vec(x,y),vec(x+w,y+m.bar),tint(.035,.12,.20,.85),10*s)
    local cfg=self.env.settings()
    for i,kind in ipairs(m.quick) do
        local row=math.floor((i-1)/m.columns);local column=(i-1)%m.columns
        local count=math.min(m.columns,#m.quick-row*m.columns)
        local bw=(w-(count+1)*8*s)/count
        local bx=x+8*s+column*(bw+8*s);local by=y+row*m.rowH
        local allowed=kind~='code0' or (core.finite(self.state.health) and self.state.health>0 and self.state.health<=cfg.code0_health)
        local clicked=button(kind,M.kinds[kind].short,bx,by+6*s,bw,26*s,
            kind=='code0' and tint(.55,.20,.23,allowed and .94 or .4) or tint(.10,.30,.45,.94))
        if allowed and clicked then self:request(kind) end
        local value=m.shortcuts[kind];local extent=m.body:CalcTextSizeA(11*s,100000,bw-8*s,value)
        text(value,m.body,11,bx+(bw-extent.x)/2,by+36*s,bw-8*s,muted)
    end
    for n,line in ipairs(m.cursorLayout.lines)do
        text(line.text,m.heading,14,x+(w-line.width)/2,y+m.cursorTop+(n-1)*14*s,0,white)
    end
    local p=self.pending
    local keys={y=io.KeysDown[M.KEY_Y]==true,n=io.KeysDown[M.KEY_N]==true,
        mods=io.KeyCtrl==true or io.KeyAlt==true or io.KeyShift==true or io.KeySuper==true}
    self:paint(p and p.token or nil,self.now,keys)
    if not p then
        if m.feedback then text(m.feedback,m.body,12,x+pad,y+m.bar+6*s,m.wrap,muted) end
        return
    end
    y=y+m.bar+8*s
    list:AddRectFilled(vec(x,y),vec(x+w,box.y+box.h),tint(.025,.085,.15,.90),11*s)
    local top=y+pad
    text(m.title,m.heading,16,x+pad,top,m.wrap);top=top+m.titleH+8*s
    for _,row in ipairs(m.lines) do
        list:AddRectFilled(vec(x+pad,top),vec(x+w-pad,top+row.h+10*s),tint(.10,.22,.32,.85),7*s)
        text(row.text,m.body,14,x+pad+8*s,top+5*s,m.wrap-16*s);top=top+row.h+16*s
    end
    if m.busy then text(m.busy,m.body,13,x+pad,top,m.wrap,tint(1,.81,.47));top=top+m.busyH+6*s end
    local keyReady=safe(self.state,false) and self.state.keyboardAvailable~=false and not keys.mods
    local yes=button('yes','Y   ДА',x+pad,top,(m.wrap-8*s)/2,34*s,tint(.12,.43,.27,(keyReady or mouse) and .96 or .52))
    local no=button('no','N   НЕТ',x+pad+(m.wrap+8*s)/2,top,(m.wrap-8*s)/2,34*s,tint(.55,.16,.20,(keyReady or mouse) and .96 or .52))
    if no then self:click(p.token,false) elseif yes then self:click(p.token,true) end
    top=top+40*s
    local remaining=math.max(0,math.ceil((self.env.settings().timeout_ms-(core.elapsed(self.now,p.offeredAt) or 0))/1000))
    local hint=keyReady and (p.waitRelease and 'Отпустите Y / N, затем нажмите снова · '..remaining..' с' or
        'Y / N · '..remaining..' с · отправка только после ДА') or
        (mouse and 'Выбор мышью · '..remaining..' с' or 'Закройте ввод для подтверждения · '..remaining..' с')
    text(hint,m.body,12,x+pad,top,m.wrap,muted)
    local progress=math.max(0,1-(core.elapsed(self.now,p.offeredAt) or 0)/self.env.settings().timeout_ms)
    list:AddRectFilled(vec(x+pad,box.y+box.h-5*s),vec(x+pad+m.wrap*progress,box.y+box.h-3*s),tint(.24,.60,.82),2*s)
end
M.Controller=Controller
return M

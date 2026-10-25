-- Count actual outgoing BULLET_SYNC packets, including misses. Advisory only:
-- never blocks a packet, changes ammo, fires, or claims a server reload succeeded.
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local weapons=require 'pa26_weapons'
local hudModel=require 'pa26_hud'
local M={CAPACITY=require('pa26_preferences').taserDefaults().capacity};local Taser={};Taser.__index=Taser
local function signature(cfg)return table.concat({tostring(cfg.weapon_id),tostring(cfg.cooldown_ms),tostring(cfg.capacity or M.CAPACITY),cfg.reload_template},'\0')end
function M.new(env)return setmetatable({env=env,life=1,shots=0,version=0,events={},queued=false,manual=false},Taser)end
function Taser:reset()
    self.life=self.life+1;self.state=nil;self.now=nil;self.shots=0;self.version=0;self.events={};self.lastShot=nil
    self.queued=false;self.manual=false;self.failedVersion=nil;self.violation=false;self.status=nil
    self.overflow=false
    self.reloadDone=nil
    self.activeCapacity=nil
    self.mode='inactive';self.pendingMode=nil;self.commandMail=nil;self.replyMail=nil;self.manualMode=nil;self.modeSource=nil
end
function Taser:activeFor(state)
    local cfg=self.env.settings();local s=state or self.state
    return cfg.enabled and s and s.weapon==cfg.weapon_id and(cfg.activation~='command'or self.mode=='active')or false
end
function Taser:command(line)
    local cfg=self.env.settings();local s=self.state
    if cfg.activation~='command'or not cfg.enabled or not s or not s.session or not s.alive or s.weapon~=cfg.weapon_id or
        type(line)~='string'or line:match('^%s*(.-)%s*$'):lower()~=cfg.command then return false end
    self.commandMail={at=self.now,session=s.session,ped=s.ped,demo=s.demo};return true
end
function Taser:serverMessage(line)
    local cfg=self.env.settings();local p=self.commandMail or self.pendingMode
    if cfg.activation~='command'or not p or type(line)~='string'then return false end
    line=line:gsub('{%x%x%x%x%x%x}',''):match('^%s*(.-)%s*$')
    if cfg.active_reply~=''and line==cfg.active_reply then self.replyMail={active=true,request=model.copy(p)};return true end
    if cfg.inactive_reply~=''and line==cfg.inactive_reply then self.replyMail={active=false,request=model.copy(p)};return true end
    return false
end
function Taser:confirmMode(active)
    local s=self.state
    if type(active)~='boolean'or not s or not s.session or not s.alive then return nil,'Персонаж недоступен.'end
    self.manualMode={active=active,at=self.now,session=s.session,ped=s.ped,demo=s.demo};return true
end
function Taser:updateMode(state,now,cfg)
    if cfg.activation~='command'then return end
    local p=self.commandMail;self.commandMail=nil
    if p and p.session==state.session and p.ped==state.ped and p.demo==state.demo and state.weapon==cfg.weapon_id then
        self.pendingMode=p;self.mode='unknown';self.modeSource='command_attempt'
    end
    p=self.pendingMode
    if p then local age=core.elapsed(now,p.at);if not age or age>cfg.reply_timeout_ms then self.pendingMode=nil end end
    local event=self.manualMode or self.replyMail;local manual=self.manualMode~=nil;self.manualMode=nil;self.replyMail=nil
    local request=event and(event.request or event);local age=request and core.elapsed(now,request.at)
    if event and request.session==state.session and request.ped==state.ped and request.demo==state.demo and age and age<=cfg.reply_timeout_ms then
        self.mode=event.active and 'active'or 'inactive';self.pendingMode=nil;self.modeSource=manual and 'manual'or 'server'
    end
end
function Taser:bullet(data)
    local cfg=self.env.settings();local s=self.state
    if not cfg.enabled or not s or not s.session or not s.alive or not core.finite(self.now) then return false end
    local ok,id=pcall(function()return tonumber(data.weaponId)end)
    if not ok or id~=cfg.weapon_id or not self:activeFor(s)then return false end
    -- A bounded mailbox records bursts without saving target IDs or coordinates.
    local n=#self.events
    if n<32 then self.events[n+1]={at=self.now,life=self.life} else self.overflow=true end
    return true
end
function Taser:requestReload()
    if self.env.settings().activation=='command'and not self:activeFor()then return nil,'Сначала подтвердите режим тайзера.'end
    self.manual=true;return true
end
function Taser:remaining(at)
    local cfg=self.env.settings();local age=self.lastShot and core.elapsed(at or self.now,self.lastShot)
    return self.lastShot and math.max(0,cfg.cooldown_ms-(age or 0)) or 0
end
function Taser:capacity()return self.activeCapacity or self.env.settings().capacity or M.CAPACITY end
function Taser:needsReload()return self.shots>=self:capacity()end
function Taser:finishReload(at)
    if self.reloadDone and self.reloadDone==self.version and self:remaining(at)==0 then
        self.shots=0;self.failedVersion=nil;self.violation=false;self.reloadDone=nil
        self.activeCapacity=self.env.settings().capacity or M.CAPACITY
    end
end
function Taser:tick(state,now)
    local cfg=self.env.settings();local dt=self.now and core.elapsed(now,self.now)
    if self.state and (not dt or self.state.session~=state.session or self.state.ped~=state.ped or
        self.state.alive~=state.alive or self.state.demo~=state.demo or self.weaponId~=cfg.weapon_id or self.activation~=cfg.activation) then self:reset()end
    self.state=state;self.now=now;self.weaponId=cfg.weapon_id;self.activation=cfg.activation
    self:updateMode(state,now,cfg)
    if not self.activeCapacity or self.shots==0 and not self.queued and not self.reloadDone then self.activeCapacity=cfg.capacity or M.CAPACITY end
    if not cfg.enabled or not state.session or not state.alive then self.events={};self.manual=false;return end
    local events=self.events;self.events={}
    -- A shot received just before the deadline must not gain a new cartridge
    -- merely because the main loop processes its mailbox after that deadline.
    self:finishReload(events[1]and events[1].at or now)
    for _,e in ipairs(events) do
        local age=core.elapsed(now,e.at)
        if e.life==self.life and age then
            local since=self.lastShot and core.elapsed(e.at,self.lastShot)
            self.violation=self.violation or self:needsReload() or (since~=nil and since<cfg.cooldown_ms)
            self.shots=math.min(self:capacity(),self.shots+1);self.version=self.version+1;self.lastShot=now
            self.status=nil
        end
    end
    if self.overflow then self.shots=self:capacity();self.version=self.version+1;self.violation=true;self.overflow=false end
    if self.reloadDone and self.reloadDone~=self.version then
        self.reloadDone=nil;self.failedVersion=self.version;self.status='Выстрел до окончания перезарядки'
    end
    local manual=self.manual
    if self.queued or self.reloadDone or self.shots==0 or (not manual and (not self:needsReload() or not cfg.auto_reload or self.failedVersion==self.version)) then return end
    if not weapons.safe(state)or not self:activeFor(state)or state.busy or state.wheel or state.alertPending then return end
    self.manual=false
    local plan,err=weapons.plan(cfg.reload_template,state,self.env.codec,now,'taser_reload',self.life,signature(cfg),cfg.weapon_id)
    if plan then plan.automatic.shotVersion=self.version;plan.automatic.reloadAuto=not manual end
    local ok
    if plan then ok,err=self.env.start(plan) end
    if ok then self.queued=true;self.status='Перезарядка: /me в очереди'
    else self.failedVersion=self.version;self.status='Перезарядка не выполнена · повторите';if self.env.log then self.env.log('Тайзер: '..tostring(err))end end
end
function Taser:validPlan(plan)
    local a=plan.automatic;if not a or a.kind~='taser_reload' then return true end
    local cfg=self.env.settings();local s=self.state;local age=core.elapsed(self.now,plan.createdAt)
    return cfg.enabled and (not a.reloadAuto or cfg.auto_reload) and weapons.safe(s)and self:activeFor(s)and a.weapon==cfg.weapon_id and
        a.life==self.life and a.shotVersion==self.version and self.shots>0 and plan.session==s.session and
        a.ped==s.ped and plan.demo==s.demo and signature(cfg)==a.signature and age and age<=10000+(plan.rpExtraSteps or 0)*(s.sendIntervalMs or 5000)or false
end
function Taser:onExecution(kind,q)
    local a=q.plan.automatic
    if not a or a.kind~='taser_reload' or a.life~=self.life then return end
    if kind=='completed' then
        self.queued=false
        if a.shotVersion==self.version and (q.demo or q.sent==1) then
            self.reloadDone=self.version;self.failedVersion=nil;self.violation=false
            self.status=q.demo and 'Демо: RP-перезарядка завершена' or 'RP-перезарядка передана клиенту'
            self:finishReload()
        else
            self.failedVersion=self.version;self.status='Перезарядка не подтверждена передачей /me'
        end
    elseif kind=='cancelled' then
        self.queued=false;self.failedVersion=self.version;self.status='Перезарядка прервана · повторите'
    end
end
function Taser:view()
    local cfg=self.env.settings();local s=self.state
    if not cfg.enabled or not cfg.hud or not s or not s.session or not s.alive or not s.focused or s.paused or s.weapon~=cfg.weapon_id then return {visible=false} end
    local remaining=self:remaining();local needs=self:needsReload();local available=self.env.observed and self.env.observed()
    local status
    if not self:activeFor(s)then status=self.mode=='unknown'and 'Режим тайзера не подтверждён · проверьте в настройках'or 'Обычный пистолет · тайзер не включён'
    elseif available==false then status='События выстрелов недоступны'
    elseif self.reloadDone then status=string.format('Перезарядка · подождите %.1f с',remaining/1000)
    elseif self.queued then status='RP-перезарядка выполняется…'
    elseif needs then status=self.failedVersion==self.version and 'Повторите RP-перезарядку' or cfg.auto_reload and 'RP-перезарядка ждёт очередь' or 'Нужна RP-перезарядка'
    elseif remaining>0 then status=string.format('Подождите %.1f с',remaining/1000)
    else status='Можно стрелять' end
    if s.demo then status='ДЕМО · '..status end
    return {visible=true,demo=s.demo,charges=self:capacity()-self.shots,capacity=self:capacity(),pendingCapacity=(cfg.capacity or M.CAPACITY)~=self:capacity()and cfg.capacity or nil,
        remaining=remaining,ready=self:activeFor(s)and available~=false and not needs and not self.queued and remaining==0,
        mode=self.mode or 'inactive',modeSource=self.modeSource,pendingMode=self.pendingMode~=nil,
        status=status,violation=self.violation,needs=needs,queued=self.queued,button=self:activeFor(s)and self.shots>0 and not self.queued and not self.reloadDone and
            (not cfg.auto_reload or self.failedVersion==self.version),progress=1-remaining/cfg.cooldown_ms}
end
function Taser:reserve(im,hud,fonts)
    self.metrics=nil;self.bounds=nil;hud:setEquipmentHeight(0)
    local v=self:view();if not v.visible then return end
    local io=im.GetIO();local r=hud:layout(io.DisplaySize.x,io.DisplaySize.y)
    if not r or io.DisplaySize.x<480 or io.DisplaySize.y<360 then return end
    local scale=math.max(.7,math.min(r.scale,1.25));local w=math.min(r.w,420*scale);local pad=12*scale
    local body=fonts.body or im.GetFont();local heading=fonts.heading or body
    local m={view=v,scale=scale,w=w,pad=pad,body=body,heading=heading,wrap=w-2*pad}
    m.title='Тайзер · '..(v.demo and 'ДЕМО · ' or '')..'RP-заряды '..v.charges..' / '..v.capacity
    if v.pendingCapacity then m.title=m.title..' · после перезарядки: '..v.pendingCapacity end
    m.titleH=heading:CalcTextSizeA(16*scale,100000,m.wrap,m.title).y
    m.statusH=body:CalcTextSizeA(14*scale,100000,m.wrap,v.status).y
    m.h=2*pad+m.titleH+7*scale+m.statusH+13*scale
    if v.violation then m.warning='Нарушен интервал или лимит выстрелов';m.warningH=body:CalcTextSizeA(12*scale,100000,m.wrap,m.warning).y;m.h=m.h+m.warningH+6*scale end
    if v.button then m.h=m.h+36*scale end
    self.metrics=m;hud:setEquipmentHeight(m.h)
end
function Taser:place(im,hud,fonts)
    self.bounds=nil;if not self.metrics or hud.equipmentHeight<=0 then return end
    local lane=hud:attachmentLayout(im,fonts)
    if lane and lane.equipment then local box=lane.equipment;local m=self.metrics
        self.bounds={x=box.x+(box.w-m.w)/2,y=box.y,w=m.w,h=m.h}
    end
end
local function inside(r,x,y)return r and core.finite(x) and core.finite(y) and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h end
function Taser:overWidget(im)local io=im.GetIO();return inside(self.bounds,io.MousePos.x,io.MousePos.y)end
function Taser:draw(im,hud,fonts)
    local m=self.metrics;local box=self.bounds;if not m or not box then return end
    local v=m.view;local s=m.scale;local list=im.GetForegroundDrawList();local vec=im.ImVec2
    local function color(r,g,b,a)return im.ColorConvertFloat4ToU32(im.ImVec4(r,g,b,a or 1))end
    local white=color(.97,.99,1);local tone=v.ready and color(.39,.91,.64) or v.needs and color(1,.53,.55) or color(1,.81,.42)
    list:AddRectFilled(vec(box.x,box.y),vec(box.x+box.w,box.y+box.h),color(.025,.10,.18,.89),10*s)
    local x,y=box.x+m.pad,box.y+m.pad
    local function text(value,font,size,left,top,tint)list:AddTextFontPtr(font,size*s,vec(left,top),tint or white,value,nil,m.wrap)end
    text(m.title,m.heading,16,x,y);y=y+m.titleH+7*s
    text(v.status,m.body,14,x,y,tone);y=y+m.statusH+7*s
    if m.warning then text(m.warning,m.body,12,x,y,color(1,.67,.43));y=y+m.warningH+6*s end
    if v.button then
        local r={x=x,y=y,w=m.wrap,h=30*s};local label='Отыграть перезарядку';local io=im.GetIO()
        list:AddRectFilled(vec(x,y),vec(x+m.wrap,y+30*s),color(.12,.34,.50,.95),7*s)
        local ext=m.heading:CalcTextSizeA(13*s,100000,m.wrap,label)
        text(label,m.heading,13,x+(m.wrap-ext.x)/2,y+(30*s-ext.y)/2)
        if inside(r,io.MousePos.x,io.MousePos.y) and self.state.mouseAllowed and weapons.safe(self.state) and im.IsMouseClicked(0) then self:requestReload()end
    end
    list:AddRectFilled(vec(x,box.y+box.h-6*s),vec(x+m.wrap,box.y+box.h-3*s),color(.12,.23,.33),2*s)
    list:AddRectFilled(vec(x,box.y+box.h-6*s),vec(x+m.wrap*v.progress,box.y+box.h-3*s),tone,2*s)
end
return M

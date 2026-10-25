-- A reminder is not permission to apply force. Only an explicit fresh action
-- prepares speech, and only the existing executor can send it.
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local prefs=require 'pa26_preferences'
local rp=require 'pa26_rp_text'
local M={};local Warning={};Warning.__index=Warning
-- SAMP.Lua's outgoing AimSyncData.camMode uses GTA SA eCamMode values.
-- Observe packets only: never send/force sync, write game memory or read a
-- remote player's camera. A fresh non-aim mode must override a stale target.
M.aimModes={[7]=true,[8]=true,[34]=true,[39]=true,[40]=true,[42]=true,[51]=true,[52]=true,[53]=true,[55]=true,[65]=true}
M.AIM_FRESH_MS=1500
function Warning:observeAim(data)
    local ok,value=pcall(function()return tonumber(data.camMode)end)
    if not ok or not core.finite(value) or value~=math.floor(value) or value<0 or value>255 or not self.now then return end
    self.aimSample={mode=value,at=self.now,session=self.state and self.state.session,ped=self.state and self.state.ped}
end
function Warning:aimStatus(s,now)
    local sample=self.aimSample
    local age=sample and core.elapsed(now,sample.at)
    if sample and sample.session==s.session and sample.ped==s.ped and age and age<=M.AIM_FRESH_MS then
        if not M.aimModes[sample.mode] then return false,'camera' end
        -- Target is a mapped game control, not a hard-coded right mouse key.
        -- It stops the timer on release before the next sync packet arrives.
        if s.aimControl~=nil then return s.aimControl==true,'camera' end
        return s.aimedAtPlayer==true and s.aimControl~=false,'player'
    end
    return s.aimedAtPlayer==true and s.aimControl~=false,'player'
end
function M.safe(s)
    return s and s.session and core.finite(s.ped) and s.alive==true and s.onDuty==true and s.focused==true and
        s.paused==false and s.blocked==false and s.typing~=true and s.recording~=true and s.editingHud~=true and s.draggingHud~=true and not s.alertPending and not s.modal
end
local function scope(s,group)return table.concat({s.session,tostring(s.ped),tostring(s.demo),s.targetKey or 'unselected',group},'\0')end
local function signature(cfg,s,group,name)
    return table.concat({tostring(cfg.enabled),cfg.mode,cfg.trigger,tostring(cfg.delay_ms),cfg.channel,cfg[group..'_template'],
        tostring(s.weapon),name,tostring(cfg.no_accent),cfg.no_accent and''or(s.accent or''),scope(s,group)},'\0')
end
function M.prepare(cfg,state,name,group,codec,now,life)
    local body=cfg[group..'_template']:gsub('{weapon}',function()return name end)
    local err;body,err=model.applyAccent(body,cfg.no_accent and''or(state.accent or''));if not body then return nil,err end
    local line=(cfg.channel~='' and cfg.channel..' ' or '')..body
    local ready;ready,err=rp.line(line,codec,state.rpText,state.my_nick);if not ready then return nil,err end
    local binding=model.newBinding(999999996);binding.name='Предупреждение: '..name;binding.category='Служба';binding.script=line
    return {binding=binding,requirements={target=false,closest=false},session=state.session,createdAt=now,demo=state.demo,
        has_command=cfg.channel~='',steps=ready.steps,lines=ready.lines,wire=ready.wires,rpSignature=ready.rpSignature,textSignature=ready.textSignature,
        automatic={kind='weapon_warning',life=life,ped=state.ped,weapon=state.weapon,
            maxAge=60000+(#ready.steps-1)*5000,signature=signature(cfg,state,group,name),scope=scope(state,group)}}
end
function M.new(env)return setmetatable({env=env,life=1,serial=0,prompted={},spoken={}},Warning)end
function Warning:reset()
    self.life=self.life+1;self.state=nil;self.now=nil;self.pending=nil;self.candidate=nil;self.lastWeapon=nil
    self.prompted={};self.spoken={};self.manual=nil;self.drawWeapon=nil;self.drawAt=nil;self.lastSignature=nil
    self.aimSample=nil;self.aimHold=nil
end
function Warning:request()
    if self.pending then return true end
    self.manual={at=self.now};return true
end
function Warning:drawn(weapon)self.drawWeapon=weapon;self.drawAt=self.now end
function Warning:pruneMemory(cfg)
    for _,entry in ipairs({{self.prompted,cfg.cooldown_ms},{self.spoken,cfg.remember_ms}})do
        for key,at in pairs(entry[1])do local age=core.elapsed(self.now,at);if not age or age>=entry[2]then entry[1][key]=nil end end
    end
end
function Warning:group(s)
    return(s.taserActive==true or s.weapon==(self.env.taserId and self.env.taserId()or 23))and 'taser'or 'firearm'
end
function Warning:dismiss()
    local p=self.pending;if not p then return false end
    self.pending=nil
    if p.phase=='queued' and self.env.cancel then self.env.cancel(p.token)end
    return true
end
function Warning:shown(token)
    local p=self.pending;if p and p.token==token then p.seen=true;p.paintedAt=self.now end
end
function Warning:setNoAccent(token,value)
    local p=self.pending
    if type(value)~='boolean'or not p or p.token~=token or not p.seen or p.phase~='offered'or not M.safe(self.state)then return false end
    local cfg=model.copy(self.env.settings());cfg.no_accent=value
    local plan,err=M.prepare(cfg,self.state,p.name,p.group,self.env.codec,self.now,self.life)
    if not plan then return nil,err end
    if not self.env.saveSettings then return nil,'Сохранение настройки недоступно.'end
    local ok;ok,err=self.env.saveSettings(cfg);if not ok then return nil,err end
    self.serial=self.serial+1;p.token='weapon:'..self.life..':'..self.serial
    plan.automatic.token=p.token;p.plan=plan;p.seen=false;p.paintedAt=nil
    p.remaining=cfg.toast_ms;p.createdAt=self.now;self.lastSignature=plan.automatic.signature
    return true
end
function Warning:offer(force)
    local s=self.state;local cfg=self.env.settings()
    if not cfg.enabled or not M.safe(s) or cfg.items[tostring(s.weapon)]~=true then return false end
    local group=self:group(s);local key=scope(s,group)
    local at=self.spoken[key] or self.prompted[key];local age=at and core.elapsed(self.now,at)
    local limit=self.spoken[key]and cfg.remember_ms or cfg.cooldown_ms
    if not force and at and (not age or age<limit)then return false end
    local name=self.env.weaponName(s.weapon);local plan,err=M.prepare(cfg,s,name,group,self.env.codec,self.now,self.life)
    if not plan then if self.env.log then self.env.log('Предупреждение об оружии: '..tostring(err))end;return false end
    self.serial=self.serial+1
    self.pending={token='weapon:'..self.life..':'..self.serial,plan=plan,group=group,name=name,key=key,
        phase='offered',seen=false,remaining=cfg.toast_ms,createdAt=self.now}
    self.pending.plan.automatic.token=self.pending.token;self.prompted[key]=self.now
    return true
end
function Warning:decide(token,yes)
    local p=self.pending
    if not p or p.token~=token or not p.seen or not M.safe(self.state)or self.state.alertPending then return false end
    if not yes then return self:dismiss()end
    if p.phase~='offered'then return false end
    p.phase='accepted';p.acceptedAt=self.now;return true
end
function Warning:validPlan(plan)
    local a=plan.automatic;if not a or a.kind~='weapon_warning' then return true end
    local p=self.pending;local s=self.state;local cfg=self.env.settings()
    local age=self.now and core.elapsed(self.now,plan.createdAt)
    return p and p.phase=='queued' and p.token==a.token and a.life==self.life and cfg.enabled and M.safe(s) and
        not s.alertPending and cfg.items[tostring(s.weapon)]==true and a.weapon==s.weapon and plan.session==s.session and
        a.ped==s.ped and plan.demo==s.demo and age and age<=(a.maxAge or 60000) and
        signature(cfg,s,self:group(s),self.env.weaponName(s.weapon))==a.signature or false
end
function Warning:tick(state,now)
    local previous=self.state;local dt=self.now and core.elapsed(now,self.now)
    if not core.finite(now) or now~=math.floor(now)then self:reset();return end
    if previous and(not dt or previous.session~=state.session or previous.ped~=state.ped or previous.demo~=state.demo or previous.alive~=state.alive)then self:reset();previous=nil;dt=nil end
    self.state=state;self.now=now;local cfg=self.env.settings();self:pruneMemory(cfg)
    local aiming,source=self:aimStatus(state,now)
    local aimSafe=M.safe(state) and not state.wheel and not state.ownUi and state.inVehicle==false
    local hold=self.aimHold
    if cfg.trigger~='aim' or not cfg.enabled or cfg.items[tostring(state.weapon)]~=true or not aimSafe or not aiming or (dt and dt>1000) then
        self.aimHold=nil
    elseif not hold or hold.weapon~=state.weapon or hold.source~=source then
        self.aimHold={at=now,weapon=state.weapon,source=source,offered=false}
    end
    if self.env.uiAvailable and not self.env.uiAvailable()then self:dismiss();self.candidate=nil;self.lastSignature=nil;return end
    if not cfg.enabled or not state.session or not state.ped or not state.alive or not state.onDuty then self:dismiss();self.candidate=nil;self.lastSignature=nil;self.manual=nil;return end
    local group=self:group(state);local name=self.env.weaponName(state.weapon)
    local sig=signature(cfg,state,group,name)
    if self.lastSignature~=sig then self.candidate={at=now,signature=sig};self.lastSignature=sig end
    local p=self.pending
    if p and p.plan.automatic.signature~=sig then self:dismiss();p=nil end
    if p then
        if (p.phase=='accepted' or p.phase=='queued')and not M.safe(state)then self:dismiss();return end
        if p.phase=='offered' and p.seen and dt and dt<=5000 and M.safe(state)and M.safe(previous)then
            p.remaining=math.max(0,p.remaining-dt);if p.remaining<=0 then self:dismiss();return end
        end
        if p.phase=='accepted' then
            local age=core.elapsed(now,p.acceptedAt)
            if not age or age>20000 then self:dismiss();return end
            if M.safe(state)and not state.busy and not state.wheel and not state.alertPending and not state.reloadPending then
                p.phase='queued';local ok=self.env.start(p.plan)
                if not ok then self:dismiss()end
            end
        end
        return
    end
    if self.manual then
        local age=self.manual.at and core.elapsed(now,self.manual.at)
        if not age or age>2000 then self.manual=nil
        elseif M.safe(state)then self.manual=nil;self.candidate=nil;self:offer(true);return end
    end
    if not M.safe(state)or state.alertPending or cfg.items[tostring(state.weapon)]~=true then self.candidate=nil;self.lastSignature=nil;return end
    if cfg.trigger=='aim' then
        local h=self.aimHold;local age=h and core.elapsed(now,h.at)
        if h and not h.offered and age and age>=cfg.delay_ms then
            -- One decision per continuous hold, even after N or toast timeout.
            h.offered=true;self:offer(false)
        end
        return
    end
    if cfg.trigger=='draw' then
        local age=self.drawAt and core.elapsed(now,self.drawAt)
        if not age or age>5000 then self.drawWeapon=nil end
        if self.drawWeapon==state.weapon then self.drawWeapon=nil;self.candidate=nil;self:offer(false)end
        return
    end
    local c=self.candidate;local age=c and core.elapsed(now,c.at)
    if age and age>=cfg.delay_ms then self.candidate=nil;self:offer(false)end
end
function Warning:onExecution(kind,q)
    local a=q and q.plan and q.plan.automatic;if not a then return end
    if a.kind=='weapon_draw' and(kind=='sent_line' or kind=='preview_line')then self:drawn(a.weapon);return end
    local p=self.pending;if a.kind~='weapon_warning' or not p or a.token~=p.token then return end
    if kind=='sent_line' or kind=='preview_line' then
        self.spoken[p.key]=self.now
        if #q.plan.steps==1 then self.pending=nil end
    elseif kind=='completed'or kind=='cancelled'then self.pending=nil end
end
function Warning:candidates()
    local p=self.pending;if not p then return {}end
    local cfg=self.env.settings();local mode=p.phase~='offered' and 'waiting' or cfg.mode=='confirm' and 'confirm' or 'weapon'
    return {{owner='weapon',token=p.token,title=p.name..' · предупреждение',body=table.concat(p.plan.lines,'\n'),mode=mode,
        accentOption=p.phase=='offered',noAccent=cfg.no_accent==true,
        full=true,unseen=not p.seen,priority=mode=='confirm' and 80 or 50,serial=p.createdAt,remaining=p.remaining,
        status=p.phase~='offered' and 'Предупреждение ждёт свободную очередь' or 'Реплика только после вашего действия',
        hint=p.group=='firearm' and 'Применение силы зависит от ситуации и правил' or 'Перед применением тайзера предупредите',
        yes='Предупредить',no='Позже',shortcut=cfg.shortcut}}
end
return M

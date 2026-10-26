-- Stable logical weapon -> optional draw/holster narrative. No native API reads.
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local rp=require 'pa26_rp_text'
local M={};local Weapons={};Weapons.__index=Weapons
function M.safe(s)return s and s.session and s.ped and s.alive==true and s.focused==true and s.paused==false and
    s.blocked==false and s.typing~=true and s.recording~=true and s.editingHud~=true and s.draggingHud~=true and s.onDuty==true end
local function itemFor(s,cfg)
    local item=cfg.items[tostring(s.weapon)]
    if item and s.taserActive and s.taserRoleItem then
        item=model.copy(item);for k,v in pairs(s.taserRoleItem)do item[k]=v end
        return item,tostring(s.weapon)..':taser'
    end
    return item,s.weapon
end
local function fingerprint(item,cfg)
    return table.concat({item.name,item.template,item.holster_template or '',tostring(item.holster_enabled),
        tostring(cfg.holster_enabled),tostring(cfg.holster_delay_ms),tostring(cfg.delay_ms),tostring(cfg.cooldown_ms),tostring(cfg.repeat_ms)},'\0')
end
local function previousItem(a,state,cfg)
    local item=cfg.items[tostring(a.weapon)]
    if item and type(a.drawKey or a.key)=='string'and state.taserRoleItem then
        item=model.copy(item);for k,v in pairs(state.taserRoleItem)do item[k]=v end
    end
    return item
end
function M.plan(text,state,codec,now,kind,life,signature,weapon)
    local ready,err=rp.prepare('/me',text,codec,state.rpText,state.my_nick);if not ready then return nil,err end
    local binding=model.newBinding(999999998);binding.name=kind=='taser_reload'and 'Тайзер: RP-перезарядка'or 'Оружие: '..tostring(weapon)
    binding.category='Автоматические отыгровки';binding.script='/me '..text
    return {binding=binding,requirements={target=false,closest=false},session=state.session,createdAt=now,demo=state.demo,
        has_command=true,steps=ready.steps,lines=ready.lines,wire=ready.wires,rpSignature=ready.rpSignature,rpExtraSteps=#ready.lines-1,
        automatic={kind=kind,gender=state.gender,life=life,ped=state.ped,weapon=weapon,signature=signature}}
end
function M.new(env)return setmetatable({env=env,life=1,lastWeapon=nil,perWeapon={}},Weapons)end
function Weapons:reset()
    self.life=self.life+1;self.state=nil;self.now=nil;self.lastWeapon=nil;self.lastKey=nil;self.candidate=nil
    self.perWeapon={};self.lastDraw=nil;self.drawn=nil;self.holster=nil
end
function Weapons:onExecution(kind,q)
    local a=q.plan and q.plan.automatic
    if a and a.kind=='weapon_draw'and a.life==self.life and(kind=='sent_line'or kind=='preview_line')then
        self.drawn={weapon=a.weapon,key=a.drawKey,item=model.copy(a.item),signature=a.signature}
    end
end
function Weapons:tick(state,now)
    local cfg=self.env.settings();local dt=self.now and core.elapsed(now,self.now)
    if self.state and(not dt or self.state.session~=state.session or self.state.ped~=state.ped or self.state.demo~=state.demo or self.state.alive~=state.alive)then self:reset()end
    self.now=now;self.state=state
    if not cfg.enabled or not M.safe(state)or not core.finite(state.weapon)or state.weapon~=math.floor(state.weapon)then
        self.lastWeapon=nil;self.lastKey=nil;self.candidate=nil;self.holster=nil;self.drawn=nil;return
    end
    local item,key=itemFor(state,cfg)
    if self.lastKey==nil then self.lastWeapon=state.weapon;self.lastKey=key;return end
    if key~=self.lastKey then
        self.lastWeapon=state.weapon;self.lastKey=key;self.candidate=nil;self.holster=nil
        if item and item.enabled then self.candidate={weapon=state.weapon,key=key,at=now,signature=fingerprint(item,cfg)}end
        if self.drawn and key~=self.drawn.key and cfg.holster_enabled and self.drawn.item.holster_enabled then
            self.holster={drawn=model.copy(self.drawn),at=now}
        end
    end
    if self.drawn and key==self.drawn.key then self.holster=nil end
    local h=self.holster
    if h then
        local age=core.elapsed(now,h.at)
        local live=previousItem(h.drawn,state,cfg)
        if not age or age>cfg.holster_delay_ms+10000 or not cfg.holster_enabled or not live or not live.enabled or not live.holster_enabled or fingerprint(live,cfg)~=h.drawn.signature then self.holster=nil
        elseif age>=cfg.holster_delay_ms and not state.busy and not state.wheel and not state.alertPending and not state.reloadPending then
            local text=core.expandGender(h.drawn.item.holster_template,state.gender):gsub('{weapon}',function()return h.drawn.item.name end)
            local plan,err=M.plan(text,state,self.env.codec,now,'weapon_holster',self.life,h.drawn.signature,h.drawn.weapon)
            if plan then plan.automatic.drawKey=h.drawn.key;plan.automatic.item=model.copy(h.drawn.item)end
            self.holster=nil;self.drawn=nil
            if plan then self.env.start(plan)elseif self.env.log then self.env.log('Убирание оружия: '..tostring(err))end
            return
        end
    end
    local c=self.candidate;if not c then return end
    if not item or not item.enabled or key~=c.key or fingerprint(item,cfg)~=c.signature then self.candidate=nil;return end
    local age=core.elapsed(now,c.at)
    if not age or age>cfg.delay_ms+10000 then self.candidate=nil;return end
    if age<cfg.delay_ms or state.busy or state.wheel or state.alertPending or state.reloadPending then return end
    local last=self.lastDraw and core.elapsed(now,self.lastDraw)
    local repeated=self.perWeapon[c.key]and core.elapsed(now,self.perWeapon[c.key])
    if self.lastDraw and(not last or last<cfg.cooldown_ms)or self.perWeapon[c.key]and(not repeated or repeated<cfg.repeat_ms)then self.candidate=nil;return end
    local text=core.expandGender(item.template,state.gender):gsub('{weapon}',function()return item.name end)
    local plan,err=M.plan(text,state,self.env.codec,now,'weapon_draw',self.life,c.signature,c.weapon)
    if plan then plan.automatic.drawKey=c.key;plan.automatic.item=model.copy(item)end
    self.candidate=nil
    if not plan then if self.env.log then self.env.log('Отыгровка оружия: '..tostring(err))end;return end
    if self.env.start(plan)then self.lastDraw=now;self.perWeapon[c.key]=now end
end
function Weapons:validPlan(plan)
    local a=plan.automatic;if not a or a.kind~='weapon_draw'and a.kind~='weapon_holster'then return true end
    local state=self.state;local cfg=self.env.settings();local age=core.elapsed(self.now,plan.createdAt)
    if not cfg.enabled or not M.safe(state)or a.life~=self.life or plan.session~=state.session or a.ped~=state.ped or a.gender~=state.gender or plan.demo~=state.demo or not age or age>5000+(plan.rpExtraSteps or 0)*(state.sendIntervalMs or 5000)then return false end
    local item,key=itemFor(state,cfg)
    if a.kind=='weapon_holster'then
        local live=previousItem(a,state,cfg)
        return cfg.holster_enabled and key~=a.drawKey and live and live.enabled and live.holster_enabled and fingerprint(live,cfg)==a.signature or false
    end
    return item and item.enabled and key==a.drawKey and fingerprint(item,cfg)==a.signature or false
end
return M

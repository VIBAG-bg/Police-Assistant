-- Local scene continuity, not a health-based death detector. Observes existing
-- SAMP.Lua RPCs; a request/HP/interior alone never proves hospital respawn.
local core=require 'pa26_core';local M={};local Life={};Life.__index=Life
local function point(v)
    local ok,p=pcall(function()return{x=tonumber(v.x),y=tonumber(v.y),z=tonumber(v.z)}end)
    return ok and core.finite(p.x)and core.finite(p.y)and core.finite(p.z)and p or nil
end
local function distance(a,b)
    if not a or not b then return nil end
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)
end
function M.new(env)return setmetatable({env=env,epoch=0,mail={},incapacitated=false},Life)end
function Life:observe(kind,value)
    if #self.mail>=16 then return false end
    if kind=='teleport'or kind=='spawn_info'then value=point(value);if not value then return false end
    elseif kind=='spawn_approved'then if value~=true then return false end
    elseif kind~='spawn_requested'and kind~='death_reported'then return false end
    self.mail[#self.mail+1]={kind=kind,value=value};return true
end
function Life:reset()
    self.mail={};self.session=nil;self.nickname=nil;self.knownScene=false;self.incapacitated=false
    self.spawnRequest=nil;self.spawnApproval=nil;self.spawnPending=nil;self.teleport=nil;self.spawnInfo=nil;self.origin=nil;self.lastPoint=nil
end
function Life:tick(s,now)
    self.confirmed=false
    if core.elapsed(now,now)==nil then self.mail={};return end
    local cfg=self.env.settings();local p=point(s);local nick=s.local_nick
    if self.session and s.session and s.session~=self.session or self.nickname and nick and nick~=''and nick~=self.nickname then self:reset()end
    if s.session then self.session=s.session end
    if nick and nick~=''then self.nickname=nick end
    local low=core.finite(s.health)and s.health<=(cfg.downed_hp or 0)
    if s.alive==true and s.spawned~=false and p and s.session and nick and nick~=''then self.knownScene=true end
    local wasDown=self.incapacitated
    if self.knownScene and s.session==self.session and(low or s.alive~=true)then
        if not self.incapacitated then self.origin=self.lastPoint or p;self.originInterior=s.interior end
        self.incapacitated=true
    end
    local newRequest=false
    for _,e in ipairs(self.mail)do
        if e.kind=='spawn_info'then self.spawnInfo={position=e.value,at=now}
        elseif e.kind=='teleport'then self.teleport={position=e.value,at=now}
        elseif e.kind=='spawn_requested'then
            newRequest=true;self.spawnPending=true
            if self.incapacitated then self.spawnRequest=now end
        elseif e.kind=='spawn_approved'and self.incapacitated then self.spawnApproval=now
        elseif e.kind=='death_reported'and self.knownScene then
            if not self.incapacitated then self.origin=self.lastPoint or p;self.originInterior=s.interior end
            self.incapacitated=true
        end
    end
    self.mail={}
    local function recent(at)local age=at and core.elapsed(now,at);return age and age<=(cfg.respawn_evidence_ms or 10000)end
    if self.incapacitated and s.alive==true and s.spawned==true and not low and p then
        local moved=(distance(p,self.origin)or 0)>=(cfg.respawn_distance or 100)
        local tolerance=cfg.respawn_position_tolerance or 10
        local teleported=self.teleport and recent(self.teleport.at)and(distance(p,self.teleport.position)or math.huge)<=tolerance
        local target=self.spawnInfo and recent(self.spawnInfo.at)and(distance(p,self.spawnInfo.position)or math.huge)<=tolerance
        local newInterior=self.originInterior~=nil and s.interior~=nil and self.originInterior~=s.interior
        local spawnFlow=recent(self.spawnRequest)and(recent(self.spawnApproval)or teleported)
        -- Both a new observed location and independent server/spawn evidence
        -- are required. Reviving in place and ordinary door pickups are safe.
        if (moved or newInterior and teleported and target)and(spawnFlow or teleported and target)then
            self.epoch=self.epoch+1;self.confirmed=true
            self.reason='Подтверждён респавн: новая позиция персонажа и события сервера.'
        end
        if wasDown or self.confirmed then
            self.incapacitated=false;self.spawnRequest=nil;self.spawnApproval=nil;self.teleport=nil;self.origin=nil
        end
    end
    if self.confirmed or self.spawnPending and not newRequest and s.alive==true and s.spawned==true and not low then self.spawnPending=nil end
    if p then self.lastPoint=p end
    self.sceneAlive=s.alive==true or self.incapacitated and self.knownScene and s.session==self.session
end
function Life:view()return{incapacitated=self.incapacitated,transitioning=self.spawnPending==true,sceneAlive=self.sceneAlive==true,epoch=self.epoch,confirmed=self.confirmed,reason=self.reason}end
return M

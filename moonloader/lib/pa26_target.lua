-- Retains one explicitly selected person. Aim selection never sends chat.
local core=require 'pa26_core'
local M={}; local Tracker={}; Tracker.__index=Tracker
local function copy(t) return t and {id=t.id,ped=t.ped,name=t.name} or nil end
local function same(a,b) return a and b and a.id==b.id and a.name==b.name and a.ped==b.ped end
function M.new(env)
    return setmetatable({env=env,target=nil,session=nil,state='none',revision=0},Tracker)
end
function Tracker:event(kind,target,reason)
    if self.env.event then pcall(self.env.event,kind,copy(target),reason) end
end
function Tracker:clear(reason)
    local old=self.target
    self.target=nil; self.state='none'; self.distance=nil; self.lastPoll=nil; self.farAt=nil; self.transition=nil
    if old then self.revision=self.revision+1; self:event('cleared',old,reason or 'manual') end
end
function Tracker:select(target,session)
    if not session or not core.capturedTargetValid(target) then return false end
    if self.session~=session then self:clear('session'); self.session=session end
    if same(self.target,target) then return true end
    local old=self.target
    self.target=copy(target); self.state='available'; self.distance=nil; self.lastPoll=nil; self.farAt=nil; self.transition=nil
    self.revision=self.revision+1
    local kind=old and 'changed' or 'selected'
    if old and old.id==target.id and old.name==target.name then kind='rebound' end
    self:event(kind,self.target,old and (old.name..' ['..old.id..']') or nil)
    return true
end
function Tracker:sceneChanged()
    if not self.target then return end
    self.state='unavailable';self.distance=nil;self.lastPoll=nil;self.farAt=nil;self.transition=true
    self.revision=self.revision+1;self:event('suspended',self.target,'interior')
end
function Tracker:quit(id)
    if self.target and self.target.id==id then self:clear('disconnected') end
end
function Tracker:join(id)
    if self.target and self.target.id==id then self:clear('identity') end
end
function Tracker:refresh(ctx,now,settings)
    if ctx.session~=self.session then self:clear('session'); self.session=ctx.session end
    if not self.target then return end
    if not ctx.session then self:clear('session'); return end
    if ctx.alive~=true then self:clear('local_unavailable'); return end
    if not core.finite(now) then self.state='unavailable'; self.distance=nil; return end
    local elapsed=self.lastPoll and core.elapsed(now,self.lastPoll)
    if self.lastPoll and not elapsed then self:clear('timer'); return end
    if elapsed and elapsed<250 then return end
    self.lastPoll=now
    local ok,observed=pcall(self.env.inspect,copy(self.target),settings)
    if not ok or type(observed)~='table' then self.state='unavailable'; self.distance=nil; self.farAt=nil; return end
    if observed.connected==false then self:clear('disconnected'); return end
    if observed.connected~=true or type(observed.name)~='string' or observed.name=='' then
        self.state='unavailable'; self.distance=nil; self.farAt=nil; return
    end
    if observed.name~=self.target.name then self:clear('identity'); return end
    local distance=observed.distance
    if not core.finite(distance) or distance<0 then distance=nil end
    -- Distance is exposed only when native visibility was positively checked.
    self.distance=observed.visible==true and distance or nil
    local retain=settings.retain_distance or 40
    -- Interior teleports can temporarily expose the old remote coordinates.
    -- Keep only the identity until a visible actor is back in retention range.
    -- All real actions still perform the usual native identity/range/LOS check.
    if self.transition then
        if observed.visible~=true or not distance or distance>retain then
            self.state='unavailable';self.distance=nil;self.farAt=nil;return
        end
        self.transition=nil
    end
    local grace=settings.retain_grace_ms or 1500
    if distance and distance>retain then
        self.state='too_far'; self.farAt=self.farAt or now
        local age=core.elapsed(now,self.farAt)
        if not age then self:clear('timer') elseif age>=grace then self:clear('distance') end
        return
    end
    self.farAt=nil
    if observed.visible==true and distance and distance>settings.action_distance then
        self.state='out_of_range'; return
    end
    local target=observed.validated
    if not core.capturedTargetValid(target) or target.id~=self.target.id or target.name~=self.target.name then
        self.state='unavailable'; return
    end
    if self.target.ped~=target.ped then
        self.target=copy(target); self.revision=self.revision+1; self:event('rebound',self.target)
    end
    self.state='available'
end
function Tracker:view()
    local out=copy(self.target) or {}
    out.state=self.state; out.distance=self.distance; out.revision=self.revision
    local labels={none='Человек не выбран',available='Доступен',out_of_range='Вне дистанции действия',
        too_far='Слишком далеко · выбор будет снят',unavailable='Недоступен · выбор сохранён'}
    out.status=labels[self.state]
    return out
end
local Aim={};Aim.__index=Aim
function M.aim(env)
    return setmetatable({env=env,armed=false},Aim)
end
function Aim:reset()
    self.armed=false;self.started=nil;self.consumed=false
end
function Aim:tick(ctx,now,settings,locked)
    local session=ctx.session
    local elapsed=self.lastNow and core.elapsed(now,self.lastNow)
    if session~=self.session or self.lastNow and not elapsed then self:reset()end
    self.session,self.lastNow=session,core.finite(now)and now or nil
    if settings.aim_select_enabled~=true or not core.finite(now)or not session or
        ctx.alive~=true or ctx.focused~=true or ctx.paused~=false or ctx.blocked~=false or
        ctx.window~=false or locked then self:reset();return false end
    local ok,held=pcall(self.env.down)
    if not ok or type(held)~='boolean'then self:reset();return false end
    if not held then self.armed=true;self.started=nil;self.consumed=false;return false end
    -- A held button after chat/menu/scene changes needs a fresh release.
    if not self.armed or self.consumed then return false end
    self.started=self.started or now
    local age=core.elapsed(now,self.started)
    local delay=settings.aim_select_delay_ms
    if not core.finite(delay)or delay<0 or delay>2000 or not age or age<delay then return false end
    local found,target=pcall(self.env.acquire)
    if not found or not core.capturedTargetValid(target)then return false end
    local selected,result=pcall(self.env.select,target)
    if selected and result==true then self.consumed=true;return true end
    return false
end
return M

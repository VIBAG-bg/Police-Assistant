-- Explicit /su subjects are online accounts, independent of streamed peds.
-- Only read()/tick()/select() call the observation adapter, from main().
local core=require 'pa26_core'
local shared=require 'pa26_patrol_settings'
local M={};local Accounts={};Accounts.__index=Accounts
function M.new(env)return setmetatable({env=env,cache={}},Accounts)end
function Accounts:read(id)
    if not self.state or not self.state.alive or not self.state.session or not core.validId(id)then return end
    local ok,row=pcall(self.env.observe,id)
    if not ok or type(row)~='table'or row.connected~=true or row.npc==true or type(row.name)~='string'or
        #row.name<1 or #row.name>24 or not row.name:match('^[%w_%.]+$')then self.cache[id]=nil;return end
    local generation=self.env.generation(id)
    if not shared.integer(generation,0,9007199254740991)then self.cache[id]=nil;return end
    local value={account=true,id=id,name=row.name,generation=generation}
    self.cache[id]=value;return shared.copy(value)
end
function Accounts:tick(state,localTarget,forms)
    local old=self.state
    if old and(old.session~=state.session or old.ped~=state.ped or old.alive~=state.alive or old.demo~=state.demo or old.localId~=state.localId)then
        self.cache={};self.selected=nil
    end
    self.state={session=state.session,ped=state.ped,alive=state.alive,demo=state.demo,localId=state.localId}
    if not state.session or not state.alive then self.cache={};self.selected=nil;self.near=nil;return end
    self.near=localTarget and self.env.near(localTarget)and shared.copy(localTarget)or nil
    local ids={}
    if localTarget then ids[localTarget.id]=true end
    if self.selected then ids[self.selected.id]=true end
    for _,f in pairs(forms or {})do if f and f.target and core.validId(f.target.id)then ids[f.target.id]=true end end
    self.cache={}
    for id in pairs(ids)do self:read(id)end
    if self.selected and not self:valid(self.selected)then self.selected=nil end
end
function Accounts:valid(target)
    if not target or target.account~=true or not core.validId(target.id)then return false end
    local r=self.cache[target.id]
    if not r or r.name~=target.name or r.generation~=target.generation then return false end
    if self.env.allowRemote()then return true end
    return self.near and self.near.id==target.id and self.near.name==target.name or false
end
function Accounts:select(id,expected)
    local target=self:read(id)
    if not target or not self:valid(target)then return nil,'Игрок не подключён, ID недоступен или удалённый розыск отключён в настройках.'end
    if expected and(target.name~=expected.name or target.generation~=expected.generation)then
        return nil,'ID сменил владельца. Повторите /su для нужного игрока.'
    end
    self.selected=shared.copy(target);return target
end
function Accounts:current(localTarget)
    local target=localTarget and self.cache[localTarget.id]or self.selected
    return self:valid(target)and shared.copy(target)or nil
end
return M

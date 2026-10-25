-- Bounded recovery scheduling. No renderer, network send or native patching.
local core=require 'pa26_core'
local M={};local Recovery={};Recovery.__index=Recovery
function M.new()return setmetatable({attempts=0},Recovery)end
function Recovery:trip(now,kind,message)
    self.pending={at=now,kind=kind,message=tostring(message or'')};self.healthyAt=nil
end
function Recovery:ready(now,settings)
    if not self.pending or not settings.enabled or self.attempts>=settings.max_attempts then return false end
    local age=core.elapsed(now,self.pending.at)
    return age~=nil and age>=settings.delay_ms
end
function Recovery:begin(now,settings,manual)
    if manual then self.attempts=0
    elseif not self:ready(now,settings)then return false end
    self.attempts=self.attempts+1;self.pending=nil;self.healthyAt=now;return true
end
function Recovery:healthy(now,settings)
    local age=self.healthyAt and core.elapsed(now,self.healthyAt)
    if age and age>=settings.stable_ms then self.attempts=0;self.healthyAt=nil end
end
function Recovery:stop()self.pending=nil;self.healthyAt=nil end
function M.writeMarker(path,fs)
    fs=fs or require('pa26_config').fs
    local ok,value=pcall(fs.write,path,'PA26 recovery\n')
    return ok and value==true
end
function M.consumeMarker(path,fs)
    fs=fs or require('pa26_config').fs
    if not fs then return false end
    local ok,value=pcall(fs.read,path)
    if not ok or value~='PA26 recovery\n' then return false end
    -- A failed deletion must keep the restored process in demo as well.
    pcall(fs.remove,path)
    return true
end
return M

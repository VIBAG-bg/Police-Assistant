-- Acknowledged UI warnings: no timeout and no gameplay side effects.
local core=require 'pa26_core'
local M={MAX_PENDING=32};local Feedback={};Feedback.__index=Feedback
function M.new()return setmetatable({queue={},serial=0,passive={}},Feedback)end
function Feedback:push(message,scope,kind)
    if type(message)~='string'or message==''then return false end
    if not core.validUtf8(message)then message='Не удалось прочитать текст предупреждения. Повторите действие; при повторной ошибке проверьте журнал PA.'end
    scope=scope or'general'
    for _,row in ipairs(self.queue)do if row.message==message and row.scope==scope then return false end end
    self.serial=self.serial+1
    local row={message=message,scope=scope,kind=kind or 'warning',token='warning:'..self.serial}
    if #self.queue>=M.MAX_PENDING then
        -- The active warning never changes while the user is reading it.
        -- Keep the latest actionable problem in the last pending slot.
        row.skipped=(self.queue[#self.queue].skipped or 0)+1;self.queue[#self.queue]=row
    else self.queue[#self.queue+1]=row end
    return true
end
function Feedback:peek()return self.queue[1]end
function Feedback:ack()if #self.queue>0 then table.remove(self.queue,1);return true end;return false end
function Feedback:once(key,message,scope)
    if self.passive[key]==message then return false end
    self.passive[key]=message
    if message then return self:push(message,scope)end
    return false
end
function Feedback:clear()self.queue={};self.passive={}end
return M

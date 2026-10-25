-- Radio and megaphone share the same whole-word, two-sided continuation rule.
local core=require 'pa26_core'
local rp=require 'pa26_rp_text'
local M={}
function M.prepare(channel,body,codec,settings,rpSettings,nickname)
    if channel=='/me'or channel=='/do'then return rp.prepare(channel,body,codec,rpSettings,nickname)end
    settings=settings or{}
    if rp.isTextChannel(channel)then
        return rp.prepare(channel,body,codec,rpSettings,nickname,
            {enabled=settings.split_enabled,marker=settings.continuation,max_lines=settings.max_lines})
    end
    -- Unknown commands must remain one indivisible server operation.
    if type(channel)~='string'or type(body)~='string'then return nil,'Неверный канал или текст доклада.'end
    local line=channel..' '..body;local wire,err=core.encodeWire(line,codec);if not wire then return nil,err end
    return {line=line,wire=wire,lines={line},wires={wire},steps={{kind='message',text=line,wire=wire}}}
end
function M.key(plan)
    if type(plan.wires)=='table'then return table.concat(plan.wires,'\0')end
    if type(plan.wire)=='table'then return table.concat(plan.wire,'\0')end
    return plan.wire or ''
end
return M

-- Only an explicit manual submission enters this queue. Never split server args.
local core=require 'pa26_core'
local rp=require 'pa26_rp_text'
local rpPrefs=require 'pa26_rp_settings'
local chat=require 'pa26_chat_text'
local M={};local Queue={};Queue.__index=Queue
function M.defaults()return {enabled=true,max_parts=3,interval_ms=1500}end
function M.validate(raw)
    if raw==nil then return M.defaults()end
    if type(raw)~='table'or type(raw.enabled)~='boolean'or not core.finite(raw.max_parts)or raw.max_parts%1~=0 or raw.max_parts<1 or raw.max_parts>3 or
        not core.finite(raw.interval_ms)or raw.interval_ms%1~=0 or raw.interval_ms<1000 or raw.interval_ms>10000 then return nil,'Ручной чат: 1–3 части, пауза 1000–10000 мс.'end
    return {enabled=raw.enabled,max_parts=raw.max_parts,interval_ms=raw.interval_ms}
end
function M.prepare(text,cfg,rawRp,accent,settings,codec,nickname)
    local options,err=M.validate(cfg);if not options then return nil,err end
    if not options.enabled then return {eligible=false}end
    if type(text)~='string'or #text>8192 or not core.validUtf8(text)or text:find('%c')then return nil,'Сообщение должно быть одной строкой без управляющих символов.'end
    local normalized=chat.dotCommand(text,settings)
    normalized=chat.radioCommand(normalized,settings)
    local channel,body=normalized:match('^(/%a+)%s+(.+)$');if channel then channel=channel:lower()end
    if normalized:match('^%s*[/!]')and not(channel=='/todo'or rp.isTextChannel(channel))then return {eligible=false}end
    if not channel then
        channel='';body=normalized
        if accent and accent~=''and not chat.skipAccent(body,settings)then
            local supplied=body:sub(1,#accent)==accent and(body==accent or body:sub(#accent+1,#accent+1):match('%s')or accent:sub(-1):match('%p'))
            if not supplied then body=accent..' '..body end
        end
    end
    if not body or body:match('^%s*$')then return {eligible=false}end
    local prefs;prefs,err=rpPrefs.validate(rawRp);if not prefs then return nil,err end
    local plan
    if channel=='/todo'then plan,err=rp.todo(normalized,codec,prefs,nickname,{max_lines=options.max_parts})
    else plan,err=rp.prepare(channel,body,codec,prefs,nickname,{max_lines=options.max_parts})end
    if not plan then return nil,'Текст не отправлен: '..tostring(err)..' В ручном чате разрешено не больше '..options.max_parts..' частей.'end
    if #plan.lines>options.max_parts then return nil,'Текст не помещается в три сообщения. Сократите его; отправки не было.'end
    plan.eligible=true;plan.channel=channel;plan.marker=prefs.marker;plan.raw=text
    plan.signature=rp.signature(prefs,nickname)..'\0'..tostring(accent)..'\0'..options.max_parts..'\0'..options.interval_ms..'\0'..table.concat(plan.lines,'\0')
    return plan
end
function M.new(env)return setmetatable({env=env,seen={},order={}},Queue)end
function Queue:prepare(text)
    local cfg,rpSettings,accent,settings,nick=self.env.settings()
    return M.prepare(text,cfg,rpSettings,accent,settings,self.env.codec,nick)
end
function Queue:receipt(key,status,message,raw,sent,total)
    self.result={key=key,status=status,message=message or'',raw=raw or'',sent=sent or 0,total=total or 0}
    if status=='rejected'and raw and raw~=''then self.draft=raw;self.draftKey=key end
    if key then
        if not self.seen[key]then self.order[#self.order+1]=key end
        self.seen[key]=self.result
        while #self.order>32 do
            local old=table.remove(self.order,1)
            if not self.queue or self.queue.key~=old then self.seen[old]=nil else self.order[#self.order+1]=old end
        end
    end
    if self.env.notice and status~='accepted'and status~='completed'then self.env.notice(message,self.result)end
    return self.result
end
function Queue:offer(text,key)
    if key and self.seen[key]then return self.seen[key]end
    if self.queue then return self:receipt(key,'rejected','Дождитесь завершения предыдущего сообщения. Текст сохранён.',text)end
    local plan,err=self:prepare(text)
    if not plan then return self:receipt(key,'rejected',err,text)end
    if not plan.eligible or #plan.lines<2 then return self:receipt(key,'rejected','Для этого текста перенос не нужен. Повторите обычную отправку.',text)end
    local ctx=self.env.context()
    if not ctx.session or ctx.alive~=true or ctx.focused~=true or ctx.paused~=false or ctx.ownWindow or ctx.dialogActive or self.env.busy()then
        return self:receipt(key,'rejected','Сейчас отправить сообщение нельзя. Текст сохранён.',text)
    end
    self.queue={plan=plan,key=key,index=1,at=self.env.now(),session=ctx.session,epoch=self.env.epoch(),sent=0}
    if self.draft==text then self.draftKey=key end
    return self:receipt(key,'accepted','Сообщение принято в очередь.',text,0,#plan.lines)
end
function Queue:cancel(reason)
    local q=self.queue;if not q then return end;self.queue=nil
    local parts={}
    for i=q.index,#q.plan.lines do
        local line=q.plan.lines[i];if q.plan.channel~=''then line=line:sub(#q.plan.channel+2)end
        if q.plan.todoAction then line=line:sub(1,-#q.plan.todoAction-2)end
        local mark=q.plan.marker
        if line:sub(1,#mark+1)==mark..' 'then line=line:sub(#mark+2)end
        if line:sub(-#mark-1)==' '..mark then line=line:sub(1,-#mark-2)end
        parts[#parts+1]=line
    end
    local raw=q.sent==0 and q.plan.raw or(q.plan.channel~=''and q.plan.channel..' 'or'')..table.concat(parts,' ')..(q.plan.todoAction and '*'..q.plan.todoAction or '')
    self.draft=raw;self.draftKey=q.key
    return self:receipt(q.key,'cancelled',reason..' Передано частей: '..q.sent..'/'..#q.plan.lines..'. Остаток сохранён.',raw,q.sent,#q.plan.lines)
end
function Queue:tick()
    local q=self.queue;if not q then return end
    local now=self.env.now();local ctx=self.env.context();local age=core.elapsed(now,q.at)
    if not age or age>60000 or ctx.session~=q.session or self.env.epoch()~=q.epoch or ctx.alive~=true or ctx.focused~=true or ctx.paused~=false or ctx.ownWindow or ctx.dialogActive then return self:cancel('Отправка остановлена: игровая сцена изменилась.')end
    local current=self:prepare(q.plan.raw)
    if not current or current.signature~=q.plan.signature then return self:cancel('Настройки текста изменились. Проверьте остаток сообщения.')end
    if self.env.busy()then return self:cancel('Другое действие PA заняло отправку.')end
    if ctx.blocked or ctx.chatActive then
        if age>15000 then return self:cancel('Чат или другое поле ввода осталось открытым.')end
        return
    end
    local cfg=self.env.settings();local interval=math.max(cfg.interval_ms,self.env.interval())
    if q.last and(core.elapsed(now,q.last)or 0)<interval then return end
    local wire=q.plan.wires[q.index]
    if not wire or #wire>127 or not self.env.send(wire)then return self:cancel('Не удалось передать следующую часть чату.')end
    q.sent=q.sent+1;q.index=q.index+1;q.last=now
    if q.index>#q.plan.lines then self.queue=nil;if self.draftKey==q.key then self.draft=nil;self.draftKey=nil end;return self:receipt(q.key,'completed','Все части переданы клиенту.',nil,q.sent,#q.plan.lines)end
end
return M

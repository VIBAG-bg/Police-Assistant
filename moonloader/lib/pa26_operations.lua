-- Observations and local manual assessments. Never sends or retries a command.
local core=require 'pa26_core'
local shared=require 'pa26_patrol_settings'
local settings=require 'pa26_operation_settings'
local store=require 'pa26_library'
local M={};local Operations={};Operations.__index=Operations
M.statusNames={waiting='Результат не отмечен',timeout='Ответ не установлен за время ожидания',interrupted='Ожидание прервано',
    preview='Демонстрация без отправки',manual_success='Успех отмечен вами',manual_failure='Отказ отмечен вами',manual_unknown='Результат не удалось установить'}
M.transportNames={observed='Наблюдалась попытка команды',client='Передано клиенту',preview='Демо · серверу не отправлялось'}
M.originNames={manual='Введено вручную',binder='Биндер',procedure='Пошаговая процедура',legacy='Быстрое действие'}
local states={};for k in pairs(M.statusNames)do states[k]=true end
local outcomes={success='manual_success',failure='manual_failure',unknown='manual_unknown'}
local function nextRevision(r)r.revision=math.min(999999999,r.revision+1)end
-- Leave room for JSON keys/escaping below the shared store's 1 MiB file limit.
local function rowBytes(r)
    local total=512+2*(#r.text+#r.binding_name+#r.date+#r.resolved_at+#r.result_note+(r.target and #r.target.name or 0))
    for _,m in ipairs(r.chat or {})do total=total+128+2*(#m.text+#m.date)end
    return total
end
local function equal(a,b)
    if type(a)~=type(b)then return false end
    if type(a)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end
    return true
end
local function cleanTarget(t)
    if t==nil then return nil end
    if type(t)~='table'or not core.validId(t.id)then return false end
    local name=shared.text(t.name,160);if not name or name==''then return false end
    return {id=t.id,name=name}
end
local function note(value)
    if type(value)~='string'or #value>2048 or not core.validUtf8(value)or value:find('[%z\1-\8\11\12\14-\31\127]')then return nil end
    return value:match('^%s*(.-)%s*$')
end
local function commandFromText(text)
    if type(text)~='string'or text:find('%c')then return nil end
    local name=text:match('^/([A-Za-z][A-Za-z0-9_]*)%s')or text:match('^/([A-Za-z][A-Za-z0-9_]*)$')
    return name and settings.command(name)
end
function M.defaults()return {schema=1,next_id=1,rows={}}end
function M.validate(raw)
    if type(raw)~='table'or raw.schema~=1 or not shared.integer(raw.next_id,1,999999999)or not shared.array(raw.rows,500)then return nil,'Журнал действий повреждён.'end
    local out=M.defaults();out.next_id=raw.next_id;local ids={}
    for _,r in ipairs(raw.rows)do
        if type(r)~='table'or not shared.integer(r.id,1,raw.next_id-1)or ids[r.id]or
            not shared.integer(r.revision,0,999999999)or not states[r.status]or not M.transportNames[r.transport]or
            not M.originNames[r.origin]or type(r.demo)~='boolean'then return nil,'Неверная запись журнала действий.'end
        local c={id=r.id,revision=r.revision,status=r.status,transport=r.transport,origin=r.origin,demo=r.demo}
        for _,row in ipairs({{'text',2048},{'binding_name',256},{'date',64},{'resolved_at',64}})do
            c[row[1]]=shared.text(r[row[1]],row[2]);if not c[row[1]]then return nil,'Неверный текст записи действия.'end
        end
        c.command=settings.command(r.command);c.result_note=note(r.result_note);c.target=cleanTarget(r.target)
        if not c.command or commandFromText(c.text)~=c.command or c.target==false or not c.result_note or
            r.demo~=(r.transport=='preview')or r.demo~=(r.status=='preview')or
            (r.source~='none'and r.source~='manual')or (r.source=='manual')~=(r.status:match('^manual_')~=nil)then
            return nil,'Несогласованный источник результата действия.'
        end
        c.source=r.source;ids[r.id]=true;out.rows[#out.rows+1]=c
        c.chat={}
        if r.chat~=nil then
            if not shared.array(r.chat,20)then return nil,'Повреждён контекст чата.'end
            for _,m in ipairs(r.chat)do
                if type(m)~='table'or not shared.integer(m.after_ms,0,120000)then return nil,'Неверное время строки чата.'end
                local body=note(m.text);local date=shared.text(m.date,64)
                if not body or body==''or not date or r.demo then return nil,'Неверная строка контекста чата.'end
                c.chat[#c.chat+1]={text=body,date=date,after_ms=m.after_ms}
            end
        end
    end
    return out
end
function M.new(env)
    local data,warnings=M.defaults(),{}
    if env.path and env.json then data,warnings=store.load(env.path,env.json,M.validate,M.defaults)end
    local self=setmetatable({env=env,data=data,warnings=warnings,cfg=settings.validate(env.settings()),pending={},
        seen=setmetatable({},{__mode='k'}),generation=0,sequence=0,now=0,dirty=false},Operations)
    for _,r in ipairs(data.rows)do if r.status=='waiting'then
        r.status='interrupted';nextRevision(r);r.result_note='PA был перезапущен. Результат команды не установлен.';self.dirty=true
    end end
    return self
end
function Operations:date()
    local ok,value=pcall(self.env.date or function()return os.date('%d.%m.%Y %H:%M:%S')end)
    return ok and shared.text(value,64)or ''
end
function Operations:find(id)
    for _,r in ipairs(self.data.rows)do if r.id==id then return r end end
end
function Operations:interrupt(reason)
    for id in pairs(self.pending)do
        local r=self:find(id)
        if r and r.status=='waiting'then r.status='interrupted';nextRevision(r);r.result_note=reason;self.dirty=true end
    end
    self.pending={};self.offer=nil;self.intent=nil;self.chatWindow=nil;self.scene=nil;self.generation=self.generation+1
end
function Operations:trim()
    local bytes=0;for _,r in ipairs(self.data.rows)do bytes=bytes+rowBytes(r)end
    while #self.data.rows>(self.cfg and self.cfg.history_limit or 200)or bytes>900000 do
        if bytes>900000 then self.sizeLimited=true end
        local r=table.remove(self.data.rows,1);bytes=bytes-rowBytes(r);self.pending[r.id]=nil
        if self.offer and self.offer.id==r.id then self.offer=nil end
        if self.intent and self.intent.id==r.id then self.intent=nil end
        if self.chatWindow and self.chatWindow.id==r.id then self.chatWindow=nil end
        self.dirty=true
    end
end
function Operations:observe(text,origin,target,transport,bindingName)
    local cfg=settings.validate(self.env.settings())
    if not cfg or not cfg.enabled or not self.scene or not M.originNames[origin]or
        not M.transportNames[transport]or type(text)~='string'or #text>2048 or not core.validUtf8(text)or text:find('%c')then return end
    if origin=='manual'and not cfg.manual or origin~='manual'and not cfg.binder or transport=='preview'and not cfg.demo then return end
    local command=commandFromText(text);local watched=false
    for _,name in ipairs(cfg.commands)do if name==command then watched=true;break end end
    if not watched then if transport~='preview'then self.chatWindow=nil end;return end
    local t=cleanTarget(target);local binding=shared.text(bindingName or '',256)
    if t==false or not binding or self.data.next_id>=999999999 then return end
    local preview=transport=='preview';local r={id=self.data.next_id,revision=0,command=command,text=text,origin=origin,
        binding_name=binding,target=t,transport=transport,demo=preview,status=preview and 'preview'or 'waiting',
        source='none',result_note='',date=self:date(),resolved_at='',chat={}}
    self.cfg=cfg;self.data.next_id=self.data.next_id+1;self.data.rows[#self.data.rows+1]=r
    if not preview then self.pending[r.id]={at=self.now,timeout=cfg.timeout_ms}end
    self.chatWindow=not preview and cfg.capture_chat and {id=r.id,at=self.now,cfg=shared.copy(cfg)}or nil
    self.dirty=true;self:trim();return r.id
end
function Operations:capturesChat()
    local cfg=settings.validate(self.env.settings());local w=self.chatWindow
    local elapsed=w and core.elapsed(self.now,w.at)
    return cfg and cfg.enabled and cfg.capture_chat and self.scene and w and elapsed and elapsed<=cfg.chat_window_ms and equal(cfg,w.cfg)or false
end
function Operations:onChat(text)
    if not self:capturesChat()then self.chatWindow=nil;return false end
    text=note(text);if not text or text==''then return false end
    local w=self.chatWindow;local r=self:find(w.id);local cfg=w.cfg
    if not r or r.demo or #r.chat>=cfg.chat_limit then self.chatWindow=nil;return false end
    r.chat[#r.chat+1]={text=text,date=self:date(),after_ms=core.elapsed(self.now,w.at)}
    nextRevision(r);self.dirty=true;self:trim()
    if #r.chat>=cfg.chat_limit then self.chatWindow=nil end
    return true
end
function Operations:onExecution(kind,q,line)
    if kind~='sent_line'and kind~='preview_line'then return end
    if type(q)~='table'or type(q.plan)~='table'or type(q.plan.binding)~='table'or not shared.integer(q.index,1,64)then return end
    local seen=self.seen[q]or {};if seen[q.index]then return end
    seen[q.index]=true;self.seen[q]=seen
    local step=q.plan.steps and q.plan.steps[q.index]
    local target=q.plan.target
    if step and step.text~=line then target=nil end -- Another outgoing hook changed the command; its receiver is unknown.
    return self:observe(line,q.plan.caseProcedure and 'procedure'or 'binder',target,
        kind=='preview_line'and 'preview'or 'client',q.plan.binding.name)
end
function Operations:propose(id,outcome,resultNote)
    local r=self:find(id);resultNote=note(resultNote or '')
    if not r or r.demo or not outcomes[outcome]or not resultNote or resultNote==''then return nil,'Выберите реальную запись и кратко опишите, по чему вы установили результат.'end
    if r.revision>=999999999 or self.intent then return nil,'Дождитесь применения предыдущего решения.'end
    local cfg,err=settings.validate(self.env.settings());if not cfg then return nil,err end
    self.sequence=self.sequence+1
    local p={token=self.sequence,id=id,revision=r.revision,outcome=outcome,note=resultNote,row=shared.copy(r),
        generation=self.generation,at=self.now,cfg=cfg}
    self.offer=shared.copy(p);return p
end
function Operations:valid(p)
    if type(p)~='table'then return false end
    local r=self:find(p.id);local cfg=settings.validate(self.env.settings());local age=core.elapsed(self.now,p.at)
    return r and not r.demo and r.revision==p.revision and equal(r,p.row)and p.generation==self.generation and
        age and cfg and age<=cfg.confirm_ms and equal(cfg,p.cfg)
end
function Operations:accept(p)
    if self.intent or not self.offer or not equal(p,self.offer)or not self:valid(p)then return nil,'Запись или условия изменились. Проверьте результат заново.'end
    self.intent=shared.copy(self.offer);self.offer=nil;return true
end
function Operations:cancelReview()self.offer=nil;self.intent=nil end
function Operations:requestExport()self.exportRequested=true;return true end
function Operations:tick(state,now)
    if not core.finite(now)then return end
    local cfg=settings.validate(self.env.settings());local backward=self.lastTick and not core.elapsed(now,self.lastTick)
    self.now=now;self.lastTick=now
    local scene=state.session and state.alive==true and {session=state.session,ped=state.ped,localId=state.localId,demo=state.demo}or nil
    if backward or not equal(scene,self.scene)then self:interrupt('Игровая сцена изменилась. Результат команды не установлен.')end
    if not equal(cfg,self.cfg)then
        self.offer=nil;self.intent=nil;self.chatWindow=nil
        if not cfg or not cfg.enabled then self:interrupt('Наблюдение выключено. Результат команды не установлен.')end
    end
    self.scene=shared.copy(scene);self.cfg=cfg
    if self.chatWindow and not self:capturesChat()then self.chatWindow=nil end
    if self.intent then
        local p=self.intent;self.intent=nil
        if self:valid(p)then
            local r=self:find(p.id);r.status=outcomes[p.outcome];r.source='manual';r.result_note=p.note;r.resolved_at=self:date()
            nextRevision(r);self.pending[r.id]=nil;self.dirty=true
        else self.message='Решение не применено: запись, время или сцена изменились.'end
    end
    for id,p in pairs(self.pending)do
        local elapsed=core.elapsed(now,p.at);local r=self:find(id)
        if not r or r.status~='waiting'then self.pending[id]=nil
        elseif not elapsed or elapsed>=p.timeout then
            r.status='timeout';nextRevision(r);r.result_note='За время ожидания ответ сервера не установлен. Это не означает отказ.'
            self.pending[id]=nil;self.dirty=true
        end
    end
    if self.offer and not self:valid(self.offer)then self.offer=nil end
    if cfg then self:trim()end
    if self.exportRequested then
        self.exportRequested=nil
        local ok,err=self:export()
        self.message=ok and 'История экспортирована в файл _operations_export.json рядом с журналом.'or('Экспорт не выполнен: '..tostring(err))
    end
    if self.dirty and(not self.lastSave or (core.elapsed(now,self.lastSave)or 0)>=5000)then self:save()end
end
function Operations:save(force)
    if not self.dirty and not force then return true end
    if not self.env.path or not self.env.json then return true end
    local ok,err=store.save(self.env.path,self.data,self.env.json,M.validate)
    if ok then self.dirty=false;self.lastSave=self.now;self.saveError=nil
    else self.saveError=err;self.message='Журнал не сохранён: '..tostring(err)end
    return ok,err
end
function Operations:export()
    if not self.env.path or not self.env.json then return nil,'Путь экспорта недоступен.'end
    return store.save(self.env.path:gsub('%.json$','_export.json'),self.data,self.env.json,M.validate)
end
function Operations:view()
    local totals={client=0,observed=0,preview=0,success=0,failure=0,unknown=0,unresolved=0}
    for _,r in ipairs(self.data.rows)do
        totals[r.transport]=totals[r.transport]+1
        local key=({manual_success='success',manual_failure='failure',manual_unknown='unknown'})[r.status]
        if key then totals[key]=totals[key]+1 elseif not r.demo then totals.unresolved=totals.unresolved+1 end
    end
    return {rows=shared.copy(self.data.rows),totals=totals,enabled=self.cfg and self.cfg.enabled==true,
        message=self.message,saveError=self.saveError,sizeLimited=self.sizeLimited,offer=self.offer and shared.copy(self.offer)}
end
return M

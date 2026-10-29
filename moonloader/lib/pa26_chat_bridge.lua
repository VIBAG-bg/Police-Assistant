-- Local CEF IPC. Nonblocking, bounded HTTP on an ephemeral IPv4 loopback port.
-- No CEF memory offsets, DLL hooks, server packets or external service are used.
local core=require 'pa26_core'
local chatText=require 'pa26_chat_text'
local assets=require'pa26_cef_assets'
local M={MARKER=assets.MARKER,MAX_BODY=24576,MAX_CLIENTS=6,TTL=1500,RETRY_MS=2500,ASSET_CHECK_MS=5000}
local Bridge={};Bridge.__index=Bridge
local function call(object,name,...)
    if type(object[name])~='function'then return nil end
    local ok,a,b,c=pcall(object[name],...);if ok then return a,b,c end
end
local function method(object,name,...)
    local ok,a,b,c=pcall(function(...)return object[name](object,...)end,...)
    if ok then return a,b,c end
end
function M.entropy(ffi)
    if ffi.os~='Windows'then return nil end
    local ok,value=pcall(function()
        ffi.cdef('unsigned char __stdcall SystemFunction036(void*, unsigned long);')
        local api=ffi.load('advapi32');local bytes=ffi.new('unsigned char[24]')
        if api.SystemFunction036(bytes,24)==0 then return nil end
        local out={};for i=0,23 do out[#out+1]=string.format('%02x',bytes[i])end;return table.concat(out)
    end)
    return ok and value or nil
end
function M.new(env)
    return setmetatable({env=env,clients={},pages={},state=nil,seen={},status='not_installed',commands={},closed=false},Bridge)
end
function Bridge:diagnose(code)
    local settings=type(self.env.settings)=='function'and self.env.settings()or{}
    if settings.diagnostics==true and type(self.env.log)=='function'then self.env.log('CEF: '..code)end
end
function Bridge:setStatus(status,reason)
    if self.status~=status or self.reason~=reason then
        self.status,self.reason=status,reason
        self:diagnose('status='..status..'; stage='..reason)
    end
end
function Bridge:fail(reason,server)
    if server then method(server,'close')end
    self.server=nil;self:setStatus('unavailable',reason);return false
end
function Bridge:installed()
    if self.env.assetFs then
        local ok,reason=assets.ensure(self.env.path,self.env.assetFs,true)
        if reason=='asset_restored'then self:diagnose('adapter_restored; reload_if_page_already_loaded')end
        return ok,reason
    end
    -- Explicit test/embedded hosts can supply their own small virtual assets.
    local html=call(self.env.fs,'read',self.env.path..'index.html')
    return type(html)=='string'and html:find(M.MARKER,1,true)~=nil and call(self.env.fs,'exists',self.env.path..'pa26-chat.js')==true,'adapter_missing'
end
function Bridge:start()
    if self.server or self.closed then return self.server~=nil end
    if self.env.settings().enabled~=true then self:setStatus('disabled','setting_disabled');return false end
    local installed,reason=self:installed()
    if not installed then self:setStatus('not_installed',reason);return false end
    local token=self.env.token and self.env.token();if type(token)~='string'or #token~=48 or token:find('[^a-f0-9]')then return self:fail('token')end
    local ok,socket=pcall(self.env.socket or require,'socket');if not ok or type(socket)~='table'then return self:fail('socket_module')end
    local server=call(socket,'tcp');if not server then return self:fail('socket_create')end
    if not method(server,'settimeout',0)then return self:fail('socket_timeout',server)end
    if not method(server,'bind','127.0.0.1',0)then return self:fail('socket_bind',server)end
    if not method(server,'listen',6)then return self:fail('socket_listen',server)end
    local address,port=method(server,'getsockname')
    local portType=type(port)
    if portType=='string'and port:match('^%d+$')then port=tonumber(port)end
    if address~='127.0.0.1'or not core.finite(port)or port%1~=0 or port<1 or port>65535 then return self:fail('socket_address',server)end
    self:diagnose('loopback_ready; port_type='..portType)
    self.route='/'..token..'/exchange';self.server=server
    local endpoint='http://127.0.0.1:'..string.format('%d',port)..self.route
    local encoded=call(self.env.json,'encode',endpoint)
    if not encoded then return self:fail('endpoint_encode',server)end
    local script='window.PA26Chat && window.PA26Chat.endpoint('..encoded..');\n'
    local written
    if self.env.assetFs then written=assets.commit(self.env.path..'pa26-chat-endpoint.js',script,self.env.assetFs)
    else written=call(self.env.fs,'write',self.env.path..'pa26-chat-endpoint.js',script)end
    if not written then return self:fail('endpoint_write',server)end
    self.endpointScript=script
    self.waitStarted=nil;self.waitWarned=false;self:setStatus('waiting','endpoint_published');return true
end
function Bridge:busy(now)
    local s=self.state;if not s then return false,false,false end
    local age=core.elapsed(now,s.at)
    -- An expired heartbeat must not leave the UI locked by an old CEF state.
    if not age or age>M.TTL then self:setStatus('waiting','heartbeat_lost');return false,false,false end
    return s.busy,s.chat,s.dialog
end
function Bridge:observeInput(message,key,now,allowed)
    if message~=0x100 then return end
    if key==0x0D or key==0x1B then self.openGraceAt=nil
    elseif allowed and(key==0x75 or key==0x54)then self.openGraceAt=now end
end
function Bridge:inputBusy(now,graceMs)
    local busy,chat,dialog=self:busy(now)
    local age=self.openGraceAt and core.elapsed(now,self.openGraceAt)
    local grace=age~=nil and age<(graceMs or 350)
    if not grace then self.openGraceAt=nil end
    return busy or grace,chat or grace,dialog
end
function M.weaponKey(message,key)
    return(message==0x100 or message==0x101)and(type(key)=='number'and
        (key>=0x30 and key<=0x39 or key>=0x60 and key<=0x69 or key==0x51 or key==0x45))or false
end
function Bridge:observe(text,source,now)
    local fresh={};local match
    for _,row in ipairs(self.seen)do
        local age=core.elapsed(now,row.at)
        if age and age<=2000 then
            if not match and row.text==text and row.source~=source then match=true else fresh[#fresh+1]=row end
        end
    end
    if not match then fresh[#fresh+1]={text=text,source=source,at=now}end
    while #fresh>64 do table.remove(fresh,1)end;self.seen=fresh
    return not match
end
function Bridge:exchange(raw,now)
    local decoded,value=pcall(self.env.json.decode,raw)
    if not decoded or type(value)~='table'or value.schema~=1 or type(value.page)~='string'or #value.page>96 or #value.page<1 or
        type(value.chat)~='boolean'or type(value.dialog)~='boolean'or type(value.busy)~='boolean'or type(value.events)~='table'or #value.events>24 then return nil end
    local last=0
    for _,event in ipairs(value.events)do
        if type(event)~='table'or not core.finite(event.id)or event.id%1~=0 or event.id<=last or event.id>2147483647 or
            type(event.text)~='string'or #event.text>8192 or not core.validUtf8(event.text)or event.text:find('[%z\1-\8\11\12\14-\31]')or
            (event.kind~='message'and event.kind~='command'and event.kind~='local'and event.kind~='manual')or
            (event.kind~='message'and event.text:find('[\r\n]'))then return nil end
        last=event.id
    end
    local page=self.pages[value.page]
    if not page then
        local count,oldest=0
        for name,row in pairs(self.pages)do count=count+1;if not oldest or(core.elapsed(now,row.at)or math.huge)>(core.elapsed(now,self.pages[oldest].at)or math.huge)then oldest=name end end
        if count>=4 then self.pages[oldest]=nil end
        page={ack=0,at=now};self.pages[value.page]=page
    end
    page.at=now
    self.state={at=now,chat=value.chat,dialog=value.dialog,busy=value.busy or value.chat or value.dialog}
    self:setStatus('connected','browser_exchange')
    local settings=self.env.settings()
    local d=value.diagnostics
    if settings.diagnostics==true and type(d)=='table'then
        local valid=type(d.field)=='boolean'and type(d.sendHook)=='boolean'and type(d.accentConfigured)=='boolean'
        for _,key in ipairs({'applied','submitted','rejected'})do if not core.finite(d[key])or d[key]%1~=0 or d[key]<0 or d[key]>1000000 then valid=false end end
        if valid then
            local signature=tostring(d.field)..':'..tostring(d.sendHook)..':'..tostring(d.accentConfigured)
            if signature~=self.browserSignature then
                self.browserSignature=signature
                self:diagnose('browser_ready; field='..tostring(d.field)..'; send_hook='..tostring(d.sendHook)..'; accent_configured='..tostring(d.accentConfigured))
            end
            local counts=d.applied..':'..d.submitted..':'..d.rejected
            local elapsed=self.counterAt and core.elapsed(now,self.counterAt)
            if counts~=self.browserCounts and(not elapsed or elapsed>=5000)then
                self.browserCounts=counts;self.counterAt=now
                self:diagnose('manual_counts; applied='..d.applied..'; submitted='..d.submitted..'; rejected='..d.rejected)
            end
        end
    end
    for _,event in ipairs(value.events)do
        if event.id>page.ack then
            if settings.enabled and(not self.env.session or event.session==self.env.session())then
                if event.kind=='message'then self.env.message(event.text,now)
                elseif event.kind=='command'then self.env.command(event.text)
                elseif event.kind=='manual'then
                    if self.env.manual then page.manualResult=self.env.manual(event.text,value.page..':'..event.id)end
                else
                    local name,args=event.text:match('^/([A-Za-z][A-Za-z0-9_]*)%s*(.-)%s*$')
                    local handler=name and self.commands[name:lower()]
                    if handler then self.pending=self.pending or{};if #self.pending<64 then self.pending[#self.pending+1]={handler=handler,args=args,raw=event.text,at=now,
                        session=self.env.session and self.env.session()or nil}end end
                end
            end
            page.ack=event.id
        end
    end
    local layout
    if settings.enabled==true and settings.layoutIndicator==true and value.chat then
        layout=call(self.env,'layout')
        if type(layout)~='string'or not layout:match('^[A-Z][A-Z][A-Z]?$')then layout=nil end
    end
    local response={schema=1,ack=page.ack,session=self.env.session and self.env.session()or nil,enabled=settings.enabled==true,accentEnabled=settings.accentEnabled==true,
        layoutIndicator=settings.layoutIndicator==true,weaponGuard=settings.weaponGuard~=false,keyboardLayout=layout,chatText=chatText.policy(settings),
        accent=settings.accent or'',filters=settings.filters or{},diagnostics=settings.diagnostics==true,localCommands={}}
    response.manualResult=call(self.env,'manualResult',page.manualResult and page.manualResult.key)or page.manualResult
    for name in pairs(self.commands)do response.localCommands[#response.localCommands+1]=name end;table.sort(response.localCommands)
    return self.env.json.encode(response)
end
local function response(status,body,origin)
    body=body or'';local cors=''
    if origin=='sampcef://assets'or origin=='null'then cors='Access-Control-Allow-Origin: '..origin..'\r\nVary: Origin\r\nAccess-Control-Allow-Methods: POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nAccess-Control-Allow-Private-Network: true\r\nAccess-Control-Max-Age: 600\r\n'end
    return 'HTTP/1.1 '..status..'\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\n'..cors..'Content-Length: '..#body..'\r\n\r\n'..body
end
function Bridge:request(raw,now)
    local boundary=raw:find('\r\n\r\n',1,true);if not boundary then if #raw>4096 then return response('400 Bad Request')end;return nil end
    local head=raw:sub(1,boundary-1);if #head>4096 then return response('400 Bad Request')end
    local method,path=head:match('^(%u+) ([^ ]+) HTTP/1%.[01]\r?\n')
    local headers={}
    for k,v in (head..'\r\n'):gmatch('\r\n([%w%-]+):[ \t]*([^\r\n]*)')do
        k=k:lower();if headers[k]then return response('400 Bad Request')end;headers[k]=v
    end
    local origin=headers.origin
    if path~=self.route or(origin~='sampcef://assets'and origin~='null')then return response('403 Forbidden')end
    if headers['transfer-encoding']then return response('400 Bad Request','',origin)end
    if method=='OPTIONS'then return response('204 No Content','',origin)end
    if method~='POST'then return response('405 Method Not Allowed','',origin)end
    local size=headers['content-length']and headers['content-length']:match('^%d+$')and tonumber(headers['content-length'])
    if not size or size>M.MAX_BODY or size<2 or headers['content-type']~='application/json'then return response('400 Bad Request','',origin)end
    local body=raw:sub(boundary+4);if #body<size then return nil end
    if #body~=size then return response('400 Bad Request','',origin)end
    local ok,result=pcall(self.exchange,self,body,now)
    if not ok or not result then return response('400 Bad Request','',origin)end
    return response('200 OK',result,origin)
end
function Bridge:tick(now)
    if self.closed then return end
    if not self.server then
        local elapsed=self.retryAt and core.elapsed(now,self.retryAt)
        if not self.retryAt or not elapsed or elapsed>=M.RETRY_MS then self.retryAt=now;self:start()end
        if not self.server then return end
    end
    -- A loaded adapter can re-read a repaired endpoint without a browser reload.
    -- Reattaching an HTML tag alone cannot execute it in an already loaded page.
    local elapsed=self.assetAt and core.elapsed(now,self.assetAt)
    -- File verification/repair never runs while a browser input owns the scene.
    -- Check the cheap deadline before constructing settings or touching disk.
    if self.env.assetFs and(not self.assetAt or not elapsed or elapsed>=M.ASSET_CHECK_MS)and
        not self:inputBusy(now)and self.env.settings().enabled==true then
        self.assetAt=now
        local installed,reason=self:installed()
        if self.assetReason~=reason then
            self.assetReason=reason
            if not installed then self:diagnose('asset_check='..tostring(reason))end
        end
        if call(self.env.assetFs,'read',self.env.path..'pa26-chat-endpoint.js')~=self.endpointScript then
            local ok=assets.commit(self.env.path..'pa26-chat-endpoint.js',self.endpointScript,self.env.assetFs)
            if self.endpointWriteFailed~=not ok then
                self.endpointWriteFailed=not ok;self:diagnose(ok and'endpoint_restored'or'endpoint_repair_failed')
            end
        end
    end
    self.waitStarted=self.waitStarted or now
    if not self.state and not self.waitWarned and(core.elapsed(now,self.waitStarted)or 0)>=5000 then
        self.waitWarned=true;self:setStatus('waiting','browser_no_exchange')
    end
    for _=1,2 do
        local client,err=method(self.server,'accept')
        if not client then
            if err~='timeout'then
                for _,row in ipairs(self.clients)do method(row.socket,'close')end;self.clients={}
                -- Keep per-page acknowledgements across a transport restart:
                -- an event accepted before a lost HTTP reply must not run twice.
                self.state=nil;self.pending=nil
                self.retryAt=now;self:fail('socket_accept',self.server)
            end
            break
        end
        local address=method(client,'getpeername')
        if address~='127.0.0.1'or #self.clients>=M.MAX_CLIENTS then method(client,'close')else
            method(client,'settimeout',0);self.clients[#self.clients+1]={socket=client,at=now,raw='',sent=1}
        end
    end
    for i=#self.clients,1,-1 do
        local client=self.clients[i];local age=core.elapsed(now,client.at);local close=not age or age>M.TTL
        if not close and not client.output then
            local text,err,partial=method(client.socket,'receive',8192);text=text or partial
            if text then client.raw=client.raw..text end
            if #client.raw>M.MAX_BODY+4100 then close=true else client.output=self:request(client.raw,now)end
            if err=='closed'and not client.output then close=true end
        end
        if not close and client.output then
            local sent,err,last=method(client.socket,'send',client.output,client.sent)
            client.sent=(sent or last or(client.sent-1))+1
            close=client.sent>#client.output or(err and err~='timeout')or not sent and not last
        end
        if close then method(client.socket,'close');table.remove(self.clients,i)end
    end
end
function Bridge:dispatch(now)
    local pending=self.pending;self.pending=nil
    for _,item in ipairs(pending or{})do
        local age=core.elapsed(now,item.at)
        if age and age<=3000 and self.env.settings().enabled and(not self.env.session or item.session==self.env.session())then
            local ok=pcall(item.handler,item.args,item.raw)
            if not ok and self.env.log then self.env.log('Команда из чата лаунчера не выполнена: ошибка обработчика.')end
        elseif self.env.log then self.env.log('Команда из чата лаунчера отменена: слишком долго было открыто другое окно.')end
    end
end
function Bridge:close()
    self.closed=true;for _,client in ipairs(self.clients)do method(client.socket,'close')end;self.clients={}
    if self.server then method(self.server,'close');self.server=nil end
    self.state=nil;self.pending=nil
end
return M

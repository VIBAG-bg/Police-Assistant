-- Shared preparation for PA speech. Split only text channels, never commands
-- with server-side arguments. Work in real CP1251 bytes, preserve whole words.
local core=require 'pa26_core'
local prefs=require 'pa26_rp_settings'
local M={}
local channels={};for _,channel in ipairs(prefs.channels)do channels[channel]=true end
local keys={'enabled','speech_enabled','display_limit','body_limit','margin','me_extra','do_extra','fallback_nickname','max_lines','todo_action_limit','marker'}
function M.isTextChannel(channel)return channel=='/me'or channel=='/do'or channel=='/try'or channels[channel]==true end
function M.nicknameLength(name,cfg)
    if type(name)~='string'or name==''or not core.validUtf8(name)or name:find('%c')then return cfg.fallback_nickname end
    local n=0;for _ in name:gmatch('[%z\1-\127\194-\244][\128-\191]*')do n=n+1 end;return n
end
function M.signature(raw,nickname)
    local cfg=prefs.validate(raw);if not cfg then return 'invalid-rp-settings'end
    local parts={};for _,key in ipairs(keys)do parts[#parts+1]=tostring(cfg[key])end
    for _,channel in ipairs(prefs.channels)do parts[#parts+1]=channel..'='..tostring(cfg.channels[channel])end
    parts[#parts+1]=tostring(M.nicknameLength(nickname,cfg));return table.concat(parts,'\0')
end
local function encode(text,codec)
    if type(codec)~='table'or type(codec.encode)~='function'or type(codec.decode)~='function'then return nil,'Недоступен преобразователь CP1251.'end
    local ok,wire=pcall(codec.encode,text)
    if not ok or type(wire)~='string'or wire:find('%c')then return nil,'Текст не поддерживается кодировкой игрового чата.'end
    local back,value=pcall(codec.decode,wire)
    if not back or value~=text then return nil,'Текст содержит символы вне CP1251.'end
    return wire
end
function M.prepare(channel,body,codec,raw,nickname,options)
    local cfg,err=prefs.validate(raw);if not cfg then return nil,err end
    if not M.isTextChannel(channel)then return nil,'Этот канал нельзя разделять на несколько реплик.'end
    if type(body)~='string'or body==''or not core.validUtf8(body)or body:find('%c')then return nil,'Реплика должна быть непустой строкой без управляющих символов.'end
    local encoded;encoded,err=encode(body,codec);if not encoded then return nil,err end
    options=options or{}
    local roleplay=channel=='/me'or channel=='/do'or channel=='/try'
    local enabled=roleplay and cfg.enabled or not roleplay and cfg.speech_enabled and cfg.channels[channel]
    if not roleplay and options.enabled==false then enabled=false end
    local marker=options.marker~=nil and options.marker or cfg.marker
    local markerWire;markerWire,err=encode(marker,codec);if not markerWire then return nil,err end
    local maximum=math.min(cfg.max_lines,options.max_lines or cfg.max_lines)
    if not core.finite(maximum)or maximum<1 or maximum~=math.floor(maximum)then return nil,'Неверное число частей реплики.'end
    local prefix=channel==''and''or channel..' '
    local budget=math.min(cfg.body_limit,core.WIRE_LIMIT-#prefix)
    local nick=M.nicknameLength(nickname,cfg)
    if roleplay then budget=math.min(budget,cfg.display_limit-cfg.margin-nick-(channel=='/me'and cfg.me_extra or cfg.do_extra))end
    local lines,wires,steps={},{},{}
    local function add(text)
        if #lines>=maximum then return nil,'Реплика превышает выбранное число частей. Сократите текст или измените предел в настройках.'end
        local line=prefix..text;local wire,why=core.encodeWire(line,codec);if not wire then return nil,why end
        lines[#lines+1]=line;wires[#wires+1]=wire;steps[#steps+1]={kind='message',text=line,wire=wire};return true
    end
    -- Body already includes the chosen accent. Both continuation markers and
    -- every space consume the same budget. A short line remains byte-identical.
    if not enabled or #encoded<=cfg.body_limit then
        local ok;ok,err=add(body);if not ok then return nil,err end
    else
        if budget<2*#markerWire+8 then return nil,'После ника и маркеров не хватает места. Проверьте запас и лимиты.'end
        local words={};for word in body:gmatch('%S+')do words[#words+1]=word end
        if #words==0 then return nil,'Реплика пуста.'end
        local index=1
        while index<=#words do
            local lead=(#lines==0 or marker=='')and''or marker..' '
            local rest=table.concat(words,' ',index)
            local bytes;bytes,err=encode(lead..rest,codec);if not bytes then return nil,err end
            if #bytes<=budget then local ok;ok,err=add(lead..rest);if not ok then return nil,err end;break end
            local current=''
            while index<=#words do
                local candidate=current==''and words[index]or current..' '..words[index]
                local tail=marker==''and''or' '..marker
                local size;size,err=encode(lead..candidate..tail,codec);if not size then return nil,err end
                if #size>budget then break end
                current=candidate;index=index+1
            end
            if current==''then return nil,'Одно слово не помещается вместе с маркерами. Сократите его; PA не обрезает слова.'end
            local ok;ok,err=add(lead..current..(marker==''and''or' '..marker));if not ok then return nil,err end
        end
    end
    return {line=table.concat(lines,'\n'),wire=wires[1],lines=lines,wires=wires,steps=steps,
        rpSignature=roleplay and M.signature(cfg,nickname)or nil,textSignature=not roleplay and M.signature(cfg)or nil,
        body_budget=budget,split_threshold=cfg.body_limit,nickname_bytes=nick}
end
-- /todo repeats its action after * for every speech chunk. A generic split
-- would turn the continuation into a different server command, so keep it here.
function M.todo(line,codec,raw,nickname,options)
    local cfg,err=prefs.validate(raw);if not cfg then return nil,err end
    local speech,action;if type(line)=='string'then speech,action=line:match('^/[Tt][Oo][Dd][Oo]%s+([^*]+)%*([^*]+)$')end
    if not speech or not action then return nil,'Для /todo нужен текст*действие, с одной звёздочкой-разделителем.'end
    speech=speech:match('^%s*(.-)%s*$');action=action:match('^%s*(.-)%s*$')
    if speech==''or action==''then return nil,'Текст и действие /todo не могут быть пустыми.'end
    local actionWire;actionWire,err=encode(action,codec);if not actionWire then return nil,err end
    if #actionWire>cfg.todo_action_limit then return nil,'Действие после * в /todo длиннее '..cfg.todo_action_limit..' символов. Сократите действие; текст не отправлен.'end
    local maximum=math.min(cfg.max_lines,options and options.max_lines or cfg.max_lines)
    if not core.finite(maximum)or maximum<1 or maximum%1~=0 then return nil,'Неверный предел частей /todo.'end
    local budget=math.min(cfg.body_limit,core.WIRE_LIMIT-7-#actionWire)
    if budget<8 then return nil,'Действие /todo слишком длинное: сократите его в настройках.'end
    local words={};for word in speech:gmatch('%S+')do words[#words+1]=word end
    local lines,wires,steps={},{},{}
    local function add(text)
        if #lines>=maximum then return nil,'Слишком много частей /todo. Сократите приметы или шаблон.'end
        local textLine='/todo '..text..'*'..action
        local wire,why=core.encodeWire(textLine,codec);if not wire then return nil,why end
        lines[#lines+1]=textLine;wires[#wires+1]=wire;steps[#steps+1]={kind='message',text=textLine,wire=wire};return true
    end
    local speechWire;speechWire,err=encode(speech,codec);if not speechWire then return nil,err end
    if #speechWire<=budget then
        local ok;ok,err=add(speech);if not ok then return nil,err end
    else
        if not cfg.enabled then return nil,'Перенос RP отключён, а /todo не помещается в чат.'end
        local marker=cfg.marker;local markerWire;markerWire,err=encode(marker,codec);if not markerWire then return nil,err end
        if budget<2*#markerWire+8 then return nil,'После действия и маркеров /todo не хватает места. Сократите действие или маркер.'end
        local index=1
        while index<=#words do
            local lead=#lines==0 and ''or marker..' '
            local rest=table.concat(words,' ',index)
            local wire;wire,err=encode(lead..rest,codec);if not wire then return nil,err end
            if #wire<=budget then
                local ok;ok,err=add(lead..rest);if not ok then return nil,err end;break
            end
            local current=''
            while index<=#words do
                local candidate=current==''and words[index]or current..' '..words[index]
                local bytes;bytes,err=encode(lead..candidate..' '..marker,codec);if not bytes then return nil,err end
                if #bytes>budget then break end
                current=candidate;index=index+1
            end
            if current==''then return nil,'Одно слово не помещается в /todo вместе с маркерами. Сократите его; PA не обрезает слова.'end
            local ok;ok,err=add(lead..current..' '..marker);if not ok then return nil,err end
        end
    end
    return {line=table.concat(lines,'\n'),wire=wires[1],lines=lines,wires=wires,steps=steps,rpSignature=M.signature(cfg,nickname),todoAction=action,body_budget=budget}
end
function M.line(line,codec,raw,nickname)
    if type(line)=='string'and line:match('^/[Tt][Oo][Dd][Oo]%s')then return M.todo(line,codec,raw,nickname)end
    local channel,body;if type(line)=='string'then channel,body=line:match('^(/%a+)(.*)$')end
    if channel and M.isTextChannel(channel:lower())and(body==''or body:match('^%s'))then
        body=body:match('^%s*(.-)%s*$');return M.prepare(channel:lower(),body,codec,raw,nickname)
    end
    if type(line)=='string'and line:sub(1,1)~='/'then return M.prepare('',line,codec,raw,nickname)end
    local wire,err=core.encodeWire(line,codec);if not wire then return nil,err end
    return {line=line,wire=wire,lines={line},wires={wire},steps={{kind='message',text=line,wire=wire}}}
end
function M.append(plan,prepared)
    if prepared.textSignature then
        if plan.textSignature and plan.textSignature~=prepared.textSignature then return nil,'Настройки речи изменились во время подготовки.'end
        plan.textSignature=prepared.textSignature
    end
    if prepared.rpSignature then
        if plan.rpSignature and plan.rpSignature~=prepared.rpSignature then return nil,'Настройки переноса изменились во время подготовки.'end
        plan.rpSignature=prepared.rpSignature
        plan.rpExtraSteps=(plan.rpExtraSteps or 0)+#prepared.lines-1
    end
    plan.lines=plan.lines or{};plan.wire=plan.wire or{};plan.steps=plan.steps or{}
    for i,line in ipairs(prepared.lines)do plan.lines[#plan.lines+1]=line;plan.wire[#plan.wire+1]=prepared.wires[i];plan.steps[#plan.steps+1]=prepared.steps[i]end
    if #plan.steps>64 then return nil,'После переноса получилось больше 64 шагов. Сократите сценарий.'end
    return true
end
return M

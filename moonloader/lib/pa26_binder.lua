-- Small declarative language. Parsing never calls load/loadstring or game APIs.
local core=require 'pa26_core'
local rp=require 'pa26_rp_text'
local model=require 'pa26_bindings'
local M={}
local selected={id=true,suspect_name=true}; for _,v in ipairs(model.variables) do if v[1]:match('^select_') then selected[v[1]]=true end end
local function split(text)
    local result={}; for value in (text..'|'):gmatch('(.-)|') do result[#result+1]=value end; return result
end
local function decodeText(value)
    local out,i={},1
    while i<=#value do
        local char=value:sub(i,i)
        if char=='\\' then
            local nextChar=value:sub(i+1,i+1)
            if nextChar=='n' then out[#out+1]='\n'; i=i+2
            elseif nextChar=='\\' then out[#out+1]='\\'; i=i+2
            else return nil,'В @text допускаются только \\n и \\\\.' end
        else out[#out+1]=char; i=i+1 end
    end
    return table.concat(out)
end
local function parse(script,grouped)
    local text,err=model.clean(script,16384,true); if not text then return nil,err end
    local steps={}
    local function add(step)
        steps[#steps+1]=step
        return #steps<=model.MAX_STEPS
    end
    for line in (text..'\n'):gmatch('(.-)\n') do
        line=line:match('^%s*(.-)%s*$')
        if line~='' and line:sub(1,2)~='--' then
            local step
            if line:sub(1,1)=='@' and not line:match('^@random%(') then
                local name,value=line:match('^@([a-z]+)%((.*)%)$')
                if name=='text' then
                    local decoded,note=decodeText(value)
                    if not decoded then return nil,note end
                    if grouped then step={kind='message',template=decoded}
                    else
                        for message in (decoded..'\n'):gmatch('(.-)\n') do
                            message=message:match('^%s*(.-)%s*$')
                            if message~='' and not add({kind='message',template=message}) then return nil,'Максимум 64 шага в одном сценарии.' end
                        end
                    end
                elseif line=='@cancel' then step={kind='cancel'}
                elseif line=='@screen' then step={kind='screen'}
                elseif name=='wait' and value:match('^%d+$') and tonumber(value)<=60000 then step={kind='wait',ms=tonumber(value)}
                elseif name=='sleep' then
                    local key=tonumber(value)
                    if not key then for k=8,254 do if model.keyName(k):lower()==value:lower() then key=k; break end end end
                    if not model.validKey(key) or key==0 then return nil,'Ожидание: укажите клавишу, например @sleep(F6).' end
                    step={kind='key',key=key}
                elseif name=='check' and (value=='true' or value=='false' or value=='target') then step={kind='check',target=value~='false'}
                elseif name=='select' then step={kind='select',value=value}
                elseif name=='speak' and value:match('^[1-3]$') then step={kind='sound',sound=tonumber(value)}
                else return nil,'Неизвестный или неверный шаг: '..line end
            else step={kind='message',template=line} end
            if step and not add(step) then return nil,'Максимум 64 шага в одном сценарии.' end
        end
    end
    if #steps==0 then return nil,'Сценарий пуст.' end
    return steps
end
function M.parse(script) return parse(script,false) end
function M.parseEditor(script) return parse(script,true) end
function M.parameterValues(binding,args)
    args=args or {}; if type(args)~='table' then return nil,'Некорректные аргументы.' end
    local values={}; local joined={}
    for i=1,8 do
        local text=args['param'..i] or args[i] or ''
        local clean,err=model.clean(text,240); if not clean then return nil,'Аргумент '..i..': '..err end
        values['param'..i]=clean; if clean~='' then joined[#joined+1]=clean end
    end
    values.params=table.concat(joined,' ')
    for _,def in ipairs(binding.parameters) do
        local raw=args[def.name]; if raw==nil or raw=='' then raw=def.default end
        local value,err=model.clean(raw,240); if not value then return nil,err end
        if def.required and value=='' then return nil,'Заполните параметр «'..def.label..'».' end
        if def.type=='integer' and value~='' and not value:match('^%-?%d+$') then return nil,'Параметр «'..def.label..'» должен быть целым числом.' end
        values['param:'..def.name]=value
    end
    return values
end
function M.requirements(binding,parsed)
    local result={target=false,nearby=false,closest=false,target_sources={},closest_sources={}}
    local seen={target={},closest={}}
    local function requirePerson(kind,source)
        result[kind]=true
        if not seen[kind][source] then
            seen[kind][source]=true; local sources=result[kind..'_sources']; sources[#sources+1]=source
        end
    end
    if binding.target_required then requirePerson('target','включена галочка «Требовать выбранного игрока»') end
    -- Only executable steps count. Comments do not acquire people or block a text bind.
    for _,step in ipairs(parsed or M.parse(binding.script) or {}) do
        local template=step.kind=='message' and step.template or step.kind=='select' and step.value
        if template then for token in template:gmatch('{([^{}]+)}') do
            if selected[token] then requirePerson('target','{'..token..'}') end
            if model.variableNames[token] and token:match('^team') then result.nearby=true end
            if model.variableNames[token] and token:match('^closest_') then
                requirePerson('closest','{'..token..'}'); result.nearby=true
            end
        end end
        if step.kind=='check' and step.target then requirePerson('target','@check(target)') end
        if step.kind=='select' then requirePerson('target','@select(...)') end
    end
    return result
end
function M.requirementError(requirements,kind)
    local sources=table.concat(requirements[kind..'_sources'] or {},', ')
    if kind=='closest' then
        return 'Нет однозначного видимого ближайшего игрока'..(sources~='' and (' для '..sources) or '')..'.'
    end
    return 'Нужен выбранный видимый игрок'..(sources~='' and (': '..sources) or '')..'.'
end
function M.requirementHints(requirements)
    local lines={}
    if requirements.target then lines[#lines+1]='Выбранный игрок нужен: '..table.concat(requirements.target_sources,', ')..'.' end
    if requirements.closest then
        lines[#lines+1]='Ближайший игрок нужен: '..table.concat(requirements.closest_sources,', ')..'.'
        lines[#lines+1]='Эти переменные требуют игрока рядом независимо от галочки.'
        for _,source in ipairs(requirements.closest_sources) do
            if source=='{closest_weapon}' then lines[#lines+1]='Для своего оружия используйте {my_weapon}.'; break end
        end
    end
    if not requirements.target and not requirements.closest then lines[#lines+1]='Можно запускать без другого игрока.' end
    return lines
end
local function substitute(template,ctx,params,random)
    local failure
    template=template:gsub('@random%(([^()]*)%)',function(options)
        local list=split(options); if #list<2 or #list>32 then failure='В @random нужно 2–32 варианта.'; return '' end
        local index=random and random(#list) or 1
        if not core.finite(index) or index<1 or index>#list or index~=math.floor(index) then failure='Ошибка выбора варианта.'; return '' end
        return list[index]
    end)
    template=template:gsub('{gender:([^{}|]*)|([^{}]*)}',function(male,female) return ctx.gender=='female' and female or male end)
    local result=template:gsub('{([^{}]+)}',function(token)
        local value=params[token]; if value==nil then value=ctx.values[token] end
        if value==nil then failure='Нет значения {'..token..'}. Заполните профиль, параметры или выберите допустимую цель.'; return '' end
        if value=='' and (token:match('^param%d$') or token=='params') then failure='Заполните {'..token..'}.'; return '' end
        if type(value)~='string' and type(value)~='number' then failure='Неверное значение {'..token..'}.'; return '' end
        local clean=model.clean(tostring(value),1024); if not clean then failure='Недопустимое значение {'..token..'}.'; return '' end
        return clean
    end)
    if failure then return nil,failure end
    if result:find('{',1,true) or result:find('}',1,true) or result:find('@random',1,true) then return nil,'Проверьте скобки переменной или @random.' end
    return result
end
local function variants(template)
    local result={template}
    for round=1,9 do
        local nextList,found={},false
        for _,text in ipairs(result) do local first,last,options=text:find('@random%(([^()]*)%)')
            if first then
                if round>8 then return nil,'Максимум 8 @random в строке.' end
                found=true; local list=split(options); if #list<2 or #list>32 then return nil,'В @random нужно 2–32 варианта.' end
                for _,option in ipairs(list) do nextList[#nextList+1]=text:sub(1,first-1)..option..text:sub(last+1); if #nextList>256 then return nil,'Слишком много сочетаний случайных вариантов.' end end
            else nextList[#nextList+1]=text end
        end
        result=nextList; if not found then return result end
    end
    return nil,'Слишком много случайных вариантов.'
end
function M.compile(binding,ctx,args,codec,random,capabilities)
    local b,err=model.validateBinding(binding); if not b then return nil,err end
    if not b.enabled then return nil,'Этот сценарий выключен.' end
    if type(ctx)~='table' or type(ctx.values)~='table' then return nil,'Контекст не подготовлен.' end
    if b.no_accent then ctx=model.copy(ctx);ctx.values.accent=''end
    local parsed; parsed,err=M.parse(b.script); if not parsed then return nil,err end
    local requirements=M.requirements(b,parsed)
    if requirements.target and not core.capturedTargetValid(ctx.target) then return nil,M.requirementError(requirements,'target') end
    if requirements.closest and not core.capturedTargetValid(ctx.closest) then return nil,M.requirementError(requirements,'closest') end
    local params; params,err=M.parameterValues(b,args); if not params then return nil,err end
    local plan={binding=model.copy(b),target=model.copy(ctx.target),closest=model.copy(ctx.closest),
        steps={},lines={},wire={},requirements=requirements,has_command=false,session=ctx.session,createdAt=ctx.now,demo=ctx.demo}
    local duration=0
    for i,step in ipairs(parsed) do
        local prepared=model.copy(step)
        if step.kind=='message' then
            local options; options,err=variants(step.template); if not options then return nil,err end
            for _,option in ipairs(options) do local variant; variant,err=substitute(option,ctx,params)
                if not variant then return nil,'Шаг '..i..': '..err end
                local tested,why=rp.line(variant,codec,capabilities and capabilities.rpSettings,ctx.values.my_nick)
                if not tested then return nil,'Шаг '..i..': '..tostring(why)end
            end
            local line; line,err=substitute(step.template,ctx,params,random)
            if not line then return nil,'Шаг '..i..': '..err end
            if line:sub(1,1)=='/' then
                local command=line:match('^/([A-Za-z][A-Za-z0-9_]*)')
                if not command or command:lower():match('^pa26') then return nil,'Неверная команда или рекурсивный запуск помощника.' end
                if command:lower()~='me' and command:lower()~='do' then plan.has_command=true end
            end
            local ready;ready,err=rp.line(line,codec,capabilities and capabilities.rpSettings,ctx.values.my_nick)
            if not ready then return nil,'Шаг '..i..': '..err end
            local added;added,err=rp.append(plan,ready);if not added then return nil,err end;prepared=nil
        elseif step.kind=='select' then
            local value; value,err=substitute(step.value,ctx,params,random)
            if not value then return nil,err end
            if not ctx.target or (value~=tostring(ctx.target.id) and value~=ctx.target.name) then return nil,'@select допускает только заранее выбранного человека.' end
            prepared={kind='check',target=true}
        elseif step.kind=='screen' and not (capabilities and capabilities.screen) then return nil,'@screen пока недоступен: поддерживаемый API скриншотов не подключён.'
        elseif step.kind=='sound' and not (capabilities and capabilities.sound) then return nil,'Локальный звук не поддерживается этим клиентом.'
        end
        if step.kind=='key' and capabilities and capabilities.reservedKeys and capabilities.reservedKeys[step.key] then return nil,'Клавиша ожидания занята отменой или основным меню.' end
        if step.kind=='wait' then duration=duration+step.ms end
        if prepared then plan.steps[#plan.steps+1]=prepared end
    end
    if duration>300000 then return nil,'Сумма пауз не должна превышать 5 минут.' end
    return plan
end
function M.toScript(steps)
    local lines={}
    for _,step in ipairs(steps) do
        if step.kind=='message' then
            local template=step.template:gsub('\r\n','\n')
            local first=template:match('^%s*(.*)')
            if template=='' or template:find('\n',1,true) or first:sub(1,2)=='--' or
                (first:sub(1,1)=='@' and not first:match('^@random%(')) then
                lines[#lines+1]='@text('..template:gsub('\\','\\\\'):gsub('\n','\\n')..')'
            else lines[#lines+1]=template end
        elseif step.kind=='wait' then lines[#lines+1]='@wait('..step.ms..')'
        elseif step.kind=='key' then lines[#lines+1]='@sleep('..model.keyName(step.key)..')'
        elseif step.kind=='sound' then lines[#lines+1]='@speak('..step.sound..')'
        elseif step.kind=='select' then lines[#lines+1]='@select('..step.value..')'
        elseif step.kind=='screen' then lines[#lines+1]='@screen'
        elseif step.kind=='cancel' then lines[#lines+1]='@cancel'
        elseif step.kind=='check' then lines[#lines+1]=step.target and '@check(target)' or '@check(false)' end
    end
    return table.concat(lines,'\n')
end
return M

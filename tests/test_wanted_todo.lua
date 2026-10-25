local rp=require 'pa26_rp_text';local prefs=require 'pa26_procedure_settings'
local cfg=prefs.defaults();check(prefs.validate(cfg));check(prefs.rp(cfg.wanted_traits_rp))
local action='обращаясь по рации к диспетчеру.'
for _,text in ipairs({'высокий','на вид 25 лет',string.rep('синяя куртка и чёрные брюки ',12)})do
    local p=assert(rp.line('/todo Приметы подозреваемого: '..text..'*'..action,codec,nil,'Officer_Name'))
    check(#p.lines>=1);local restored={}
    for i,line in ipairs(p.lines)do
        check(line:match('^/todo '));check(line:sub(-#action-1)=='*'..action);check(#p.wires[i]<=127)
        eq(codec.decode(p.wires[i]),line);check(p.rpSignature)
        local speech=assert(line:match('^/todo (.-)%*'))
        if #p.lines>1 then
            if i>1 then check(speech:sub(1,4)=='... ');speech=speech:sub(5)end
            if i<#p.lines then check(speech:sub(-4)==' ...');speech=speech:sub(1,-5)end
        end
        restored[#restored+1]=speech
    end
    eq(table.concat(restored,' '),'Приметы подозреваемого: '..text:match('^%s*(.-)%s*$'))
end
for _,bad in ipairs({'/todo no star','/todo one*two*three','/todo *action','/todo speech*','/todo speech*action\n/su 37 1 1','/todo '..string.rep('я',200)..'*'..action})do check(not rp.line(bad,codec))end
local settings=require('pa26_rp_settings').defaults();settings.enabled=false
check(not rp.line('/todo '..string.rep('высокий ',25)..'*'..action,codec,settings))
-- Unrelated server commands are never split as if they were /todo speech.
local command=assert(rp.line('/su 37 8 1',codec));eq(#command.lines,1);eq(command.lines[1],'/su 37 8 1')

-- A custom marker changes both ends and remains part of the wire budget.
local custom=require('pa26_rp_settings').defaults();custom.marker='>>';custom.body_limit=60
local continued=assert(rp.line('/todo '..string.rep('высокий в синей куртке ',8)..'*докладывая.',codec,custom))
for i,line in ipairs(continued.lines)do
    local speech=line:match('^/todo (.-)%*')
    if i>1 then check(speech:sub(1,3)=='>> ')end
    if i<#continued.lines then check(speech:sub(-3)==' >>')end
    check(#continued.wires[i]<=127)
end
custom.max_lines=1;check(not rp.line('/todo '..string.rep('длинные приметы ',30)..'*докладывая.',codec,custom))
check(not rp.line('/todo текст*'..string.rep('действие ',20),codec))

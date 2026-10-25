local rp=require 'pa26_rp_text'
local settings=require 'pa26_rp_settings'
local model=require 'pa26_bindings'
local binder=require 'pa26_binder'
local cfg=settings.defaults()
eq(cfg.body_limit,90)
local old=model.copy(cfg);old.revision=nil;old.body_limit=99;old.speech_enabled=nil;old.channels=nil
eq(assert(settings.validate(old)).body_limit,90)
old.body_limit=83;eq(assert(settings.validate(old)).body_limit,83)
old.revision=2;old.body_limit=99;eq(assert(settings.validate(old)).body_limit,99)
local bad=model.copy(cfg);bad.speech_enabled='yes';check(not settings.validate(bad))
bad=model.copy(cfg);bad.channels['/ticket']=true;check(not settings.validate(bad))

local function verify(channel,body,options)
    local p,err=rp.prepare(channel,body,codec,cfg,'Victor_Auditore',options);check(p,err)
    local parts={};local prefix=channel==''and''or channel..' '
    for i,line in ipairs(p.lines)do
        eq(codec.decode(p.wires[i]),line);check(#p.wires[i]<=127)
        local text=line:sub(#prefix+1)
        check(#codec.encode(text)<=90,'Accent, spaces and both continuation markers share the 90-character budget')
        if #p.lines>1 then
            if i>1 then eq(text:sub(1,4),'... ');text=text:sub(5)end
            if i<#p.lines then eq(text:sub(-4),' ...');text=text:sub(1,-5)end
        end
        parts[#parts+1]=text
    end
    eq(table.concat(parts,' '),body:gsub('%s+',' '):match('^%s*(.-)%s*$'),'Every source word survives once, in the same order')
    return p
end
for _,channel in ipairs({'','/s','/m','/r','/rn','/f','/fn','/d','/b','/me','/do'})do
    eq(#verify(channel,string.rep('я',90)).lines,1)
    local body=string.rep('Саспект остановитесь ',8):match('^(.-)%s*$')
    check(#verify(channel,body).lines>1)
    local accent=assert(model.applyAccent(string.rep('требование ',15):match('^(.-)%s*$'),'[Армянский акцент]:'))
    check(#verify(channel,accent).lines>1)
    check(not rp.prepare(channel,string.rep('я',91),codec,cfg,'Victor_Auditore'),'Oversized words are never cut')
end
local accent=assert(model.accentPrefix('[Русский акцент]:'))
local exact=accent..' '..string.rep('я',90-#codec.encode(accent)-1)
eq(#codec.encode(exact),90);eq(#verify('/s',exact).lines,1);check(#verify('/s',exact..' ещё').lines>1)
local boundary=string.rep('я',82)..' слово ещё одно'
local p=verify('/s',boundary);eq(p.lines[1],'/s '..string.rep('я',82)..' ...')
eq(p.lines[2],'/s ... слово ещё одно','An overflowing word moves whole, not character by character')
for _,channel in ipairs({'/ticket','/su','/cuff','/unpt','/setmark','/taser','/r1','/radio','/message'})do
    local line=channel..' '..string.rep('x ',48)
    local prepared=assert(rp.line(line,codec,cfg,'Victor_Auditore'));eq(#prepared.lines,1);eq(prepared.lines[1],line)
    check(not rp.line(channel..' '..string.rep('x ',70),codec,cfg,'Victor_Auditore'))
end
for _,text in ipairs({'Текст\nИнъекция','Текст\tтаб','Текст\0ноль','Текст 🙂'})do check(not rp.prepare('/s',text,codec,cfg,'Victor_Auditore'))end
local off=model.copy(cfg);off.channels['/s']=false
eq(#assert(rp.prepare('/s',string.rep('слово ',20),codec,off)).lines,1)
off.speech_enabled=false;eq(#assert(rp.prepare('',string.rep('слово ',20),codec,off)).lines,1)
local one=model.copy(cfg);one.max_lines=1;check(not rp.prepare('/s',string.rep('слово ',40),codec,one))
local b=model.newBinding(7);b.script='/s {accent} '..string.rep('Остановитесь ',15)
local ctx={values={accent='[Русский акцент]:',my_nick='Victor_Auditore'},session='test',now=1000,demo=false}
p=assert(binder.compile(b,ctx,{},codec,nil,{rpSettings=cfg}));check(#p.lines>1)
check(p.lines[1]:find('[Русский акцент]:',1,true))
b.no_accent=true;local quiet=assert(binder.compile(b,ctx,{},codec,nil,{rpSettings=cfg}))
for _,line in ipairs(quiet.lines)do check(not line:find('акцент',1,true))end
eq(ctx.values.accent,'[Русский акцент]:','A per-bind exception never mutates the shared profile')
b.script='/s Первая.\n/s @random(Вторая|Текст 🙂)'
check(not binder.compile(b,ctx,{},codec,function()return 1 end,{rpSettings=cfg}),'Even an unused invalid branch rejects before any send')

-- A multi-part warning stays valid through every queued line.
local prefs=require 'pa26_preferences';local module=require 'pa26_weapon_warning'
local current=prefs.weaponWarningDefaults();current.trigger='stable';current.firearm_template=string.rep('Остановитесь и опустите оружие. ',6)
local state={session='test',ped=1,demo=false,alive=true,onDuty=true,focused=true,paused=false,blocked=false,
    typing=false,recording=false,weapon=31,targetKey='none',accent='[Русский акцент]:',rpText=cfg,my_nick='Victor_Auditore'}
local now=1000;local captured;local saveFails=false
local warning=module.new({settings=function()return current end,weaponName=function()return'M4'end,taserId=function()return-1 end,
    codec=codec,start=function(plan)captured=plan;return true end,
    saveSettings=function(value)if saveFails then return nil,'LOCAL TEST WRITE FAILURE'end;current=value;return true end})
warning:tick(state,now);check(warning:offer(true));local token=warning.pending.token
warning:shown(token);check(warning:setNoAccent(token,true));check(current.no_accent)
check(warning.pending.token~=token);check(not warning:decide(token,true));eq(captured,nil)
for _,line in ipairs(warning.pending.plan.lines)do check(not line:find('акцент',1,true))end
token=warning.pending.token;warning:shown(token);saveFails=true
check(not warning:setNoAccent(token,false));check(current.no_accent);eq(warning.pending.token,token)
saveFails=false;check(warning:setNoAccent(token,false));check(not current.no_accent)
token=warning.pending.token;warning:shown(token);check(warning:decide(token,true))
now=now+16;warning:tick(state,now);check(captured);check(#captured.steps>1)
for i=1,#captured.steps do
    check(warning:validPlan(captured),'An earlier part must not invalidate a later one')
    warning:onExecution('sent_line',{plan=captured,index=i});check(warning.pending)
    now=now+1500;warning:tick(state,now)
end
warning:onExecution('completed',{plan=captured});eq(warning.pending,nil)

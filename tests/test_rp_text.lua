local rp=require 'pa26_rp_text'
local prefs=require 'pa26_rp_settings'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local cfg=prefs.defaults();local nick='Victor_Auditore'
local example='оглянувшись вокруг, нырнул на максимально доступную глубину, после чего сделал глубокий вдох череза'
eq(#codec.encode(example),99)
local function verify(body,channel,cfg,name)
    local p,err=rp.prepare(channel,body,codec,cfg,name);check(p,err)
    local pieces={}
    for i,line in ipairs(p.lines)do
        check(#p.wires[i]<=core.WIRE_LIMIT);eq(codec.decode(p.wires[i]),line);eq(line:sub(1,#channel+1),channel..' ')
        local text=line:sub(#channel+2)
        if #p.lines>1 then
            check(#codec.encode(text)<=p.body_budget)
            if i>1 then eq(text:sub(1,#cfg.marker+1),cfg.marker..' ');text=text:sub(#cfg.marker+2)end
            if i<#p.lines then eq(text:sub(-#cfg.marker-1),' '..cfg.marker);text=text:sub(1,-#cfg.marker-2)end
        end
        pieces[#pieces+1]=text
    end
    eq(table.concat(pieces,' '):match('^%s*(.-)%s*$'):gsub('%s+',' '),body:match('^%s*(.-)%s*$'):gsub('%s+',' '),'Every source word must survive once and in order')
    return p
end
for _,channel in ipairs({'/me','/do'})do
    for _,name in ipairs({nick,string.rep('N',24),string.rep('N',32)})do
        for _,size in ipairs({1,89,90})do eq(#verify(string.rep('я',size),channel,cfg,name).lines,1,'Only > 90 can split by default')end
        check(#verify(example,channel,cfg,name).lines>1)
        local p=verify(example..' ещё',channel,cfg,name);check(#p.lines>=2)
    end
end
local p=verify(example..' ещё','/me',cfg,nick);eq(p.body_budget,90);eq(p.split_threshold,90)
p=verify(example..' ещё','/do',cfg,nick);eq(p.body_budget,90)
check(not rp.prepare('/me',string.rep('А',100),codec,cfg,nick),'An oversized single word must reject, never truncate')
for _,bad in ipairs({'','a\nb','a\tb','a\0b','🙂'})do check(not rp.prepare('/me',bad,codec,cfg,nick))end
local one=model.copy(cfg);one.max_lines=1;check(not rp.prepare('/me',example..' ещё',codec,one,nick))
one.enabled=false;eq(#verify(example..' ещё','/me',one,nick).lines,1)
check(not rp.prepare('/me',string.rep('a ',80),codec,one,nick),'Turning splitting off does not bypass the wire limit')
local marker=model.copy(cfg);marker.marker='…';verify(string.rep('осмотрелся ',24),'/me',marker,nick)
local bulk=model.copy(cfg);bulk.max_lines=16
for _,channel in ipairs({'/me','/do'})do for _,len in ipairs({5,15,24,32})do for _,count in ipairs({1,10,20,40})do
    verify(string.rep('сверил данные №2  ',count),channel,bulk,string.rep('N',len))
end end end
for _,pair in ipairs({{'body_limit',0/0},{'margin',-1},{'max_lines',17},{'fallback_nickname',65},{'marker','a b'}})do
    local c=model.copy(cfg);c[pair[1]]=pair[2];check(not prefs.validate(c))
end
local same=model.copy(cfg);same.preview_text='Другая проверка.';eq(rp.signature(cfg,nick),rp.signature(same,nick),'Editing the demo text must not cancel a real queue')
same.margin=7;check(rp.signature(cfg,nick)~=rp.signature(same,nick))
local plain=assert(rp.line('/r Доклад.',codec,cfg,nick));check(not plain.rpSignature);check(plain.textSignature);eq(#plain.lines,1)
check(not rp.line('/me',codec,cfg,nick));eq(assert(rp.line('/ME коротко',codec,cfg,nick)).line,'/me коротко')
eq(assert(rp.line('/message текст',codec,cfg,nick)).line,'/message текст')
local flaky={encode=function()error('codec failure')end,decode=codec.decode};check(not rp.prepare('/me',example..' ещё',flaky,cfg,nick))

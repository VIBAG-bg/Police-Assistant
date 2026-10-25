local core=require 'pa26_core'
local model=require 'pa26_bindings'
local binder=require 'pa26_binder'
local prefs=require 'pa26_preferences'
local rp=require 'pa26_rp_text'
local lib=model.defaults(core.defaults())
check(model.validate(lib,core.defaults()))
local function style(line)
    local channel,body=line:match('^(/%a+) (.+)$')
    if channel~='/me'and channel~='/do'then return end
    check(body:sub(-1)=='.'or channel=='/do'and body:sub(-1)=='?',line)
    local letter=body:match('^[%z\1-\127\194-\244][\128-\191]*')
    if channel=='/me'then eq(letter,model.casefold(letter),'Start /me in lower case')
    else check(letter~=model.casefold(letter),'Start /do with a capital letter')end
    local p,err=rp.line(line,codec,lib.rp_text,'Victor_Auditore');check(p,err)
    for i,w in ipairs(p.wires)do eq(codec.decode(w),p.lines[i]);check(#w<=127)end
end
local values={id='37',my_nick='Victor_Auditore',ic_name='Джон Смит',appearance='серая куртка',phone_number='123456'}
for _,gender in ipairs({'male','female'})do
    for _,b in ipairs(lib.bindings)do
        if b.enabled then
        local plan,err=binder.compile(b,{values=values,gender=gender,target={id=37,ped=99,name='Other_Name'},session='mock',now=1000,demo=true},{},codec)
        check(plan,err);for _,line in ipairs(plan.lines)do style(line)end
        end
    end
end
for _,w in pairs(lib.weapons.items)do
    style('/me '..w.template:gsub('{weapon}',function()return w.name end))
    style('/me '..w.holster_template:gsub('{weapon}',function()return w.name end))
end
for _,v in pairs(prefs.grenadePresets)do style('/me '..v.template)end
for _,field in ipairs({'draw_template','holster_template','reload_template'})do style('/me '..lib.taser[field]:gsub('{weapon}',function()return lib.taser.name end))end
style('/me '..lib.vehicle.approach_template);style('/do '..lib.vehicle.window_template)
for key,value in pairs(lib.procedures)do if key:match('_rp$')then
    for line in(value..'\n'):gmatch('(.-)\n')do style((line:gsub('{([a-z_]+)}',function(k)return values[k]or 'данные'end)))end
end end
local raw='/me '..string.rep('я',90);eq(assert(rp.line(raw,codec,lib.rp_text,'Victor_Auditore')).line,raw,'Never add punctuation or split a user body of 90 characters')
local rawDo='/do вопрос пользователя?';eq(assert(rp.line(rawDo,codec,lib.rp_text,'Victor_Auditore')).line,rawDo)
local fixture=require 'support.fixture';local s=fixture();s.step();s.page('knowledge');s.render()
local glyphs=s.fontGlyphText or ''
for _,mark in ipairs({'‐','‑','‒','–','—','−','№','→','≤','≥','…'})do check(glyphs:find(mark,1,true),'Missing font atlas glyph request: '..mark)end
eq(#s.sent,0);eq(#s.localChat,0);check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(s.invalidIOReads,0);eq(#s.scopes,0)
onScriptTerminate(s.script)

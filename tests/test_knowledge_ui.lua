local support=require 'support.fixture'
local function fixture(options)options=options or{};options.legacyWanted=true;return support(options)end
local viewModule=require 'pa26_knowledge_ui'
local M=require 'pa26_knowledge'
local core=require 'pa26_core'
local function contains(s,text)
    for _,line in ipairs(s.drawnText)do if line:find(text,1,true)then return true end end
    return false
end
local s=fixture();s.step();s.page('knowledge');eq(s.knowledgeUi.knowledge.data.catalog_version,TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON).catalog_version);check(contains(s,'Найдено:'))
check(not contains(s,'База недоступна'));eq(#s.sent,0)
-- Native close button is icon-only and closing does not cancel an independent bind.
local icon=false;for _,b in ipairs(s.buttonCalls)do if b.label=='##main-close'then icon=true end;check(b.label~='×##main-close')end
check(icon);s.click='##main-close';s.render();check(not s.frames[1].condition());check(s.frames[3].condition())
s.commands.pa26();s.step();s.page('knowledge')
s.edits={['##kb-search']='УБИЛ'};s.render();s.edits={};s.render();check(contains(s,'Убийство'),table.concat(s.logs,'\n'))
local row=M.new();row:activate(assert(M.validate(TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON))))
local actual=row.byKey['offenses:UK:39'];local label='УК ст. 39 · Убийство\n'..M.status(actual)..'##kb-row-'..actual.key
s.click=label;s.render();s.render();eq(s.click,nil);check(contains(s,'Закон не устанавливает перевод IC-лет'));eq(#s.sent,0)
s.click='В избранное##kb-favorite';s.render();s.step(800)
local p=s.files['moonloader\\config\\police_assistant_2026_knowledge_personal.json'];check(p)
eq(TEST_JSON_DECODE(p).favorites[1],actual.key)
s.edits={['##kb-offenses:UK:39-note']='Личная заметка'};s.render();s.edits={};s.step(600)
p=s.files['moonloader\\config\\police_assistant_2026_knowledge_personal.json'];eq(TEST_JSON_DECODE(p).notes[actual.key],'Личная заметка')
eq(#s.sent,0);check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)
for _,size in ipairs({{760,600},{1000,780},{1600,1000},{2560,1440}})do
    s=fixture();s.step();s.resizeWindows={['Police Assistant 2026##pa26-main']={x=size[1],y=size[2]}};s.page('knowledge');s.render()
    check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);eq(#s.sent,0)
end
for _,size in ipairs({{400,200},{720,300},{1600,900}})do
    local r=viewModule.layout(size[1],size[2]);check(r)
    if r.wide then check(r.left>=260);check(r.right>=370);eq(r.left+r.right+r.gap,r.width)end
end
eq(viewModule.layout(0/0,100),nil)
s=fixture({knowledge=false});s.step();s.page('knowledge');check(contains(s,'База недоступна'));check(not s.hasLog('Ошибка интерфейса'))
s.page('binds');check(s.frames[1].condition());eq(#s.sent,0)
-- Y/N, window closure and catalogue browsing must never interrupt ordinary
-- manual chat or send a command out of a knowledge card.
s=fixture({demo=false});s.liveAction();eq(#s.sent,1);s.commands.pa26();s.page('knowledge');s.step(1500)
eq(#s.sent,2);s.step(1500);eq(#s.sent,3)
check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)

local fixture=require 'support.fixture'
local menu=require 'pa26_menu'
local knowledge=require 'pa26_knowledge'
local model=require 'pa26_bindings'
local function has(s,text) return table.concat(s.drawnText,'\n'):find(text,1,true)~=nil end
-- The close icon never creates a tooltip, even from a small header area.
local s=fixture();s.step();s.page('knowledge');require('support.knowledge_reader').all(s)
s.hover='##main-close';s.tooltipCalls={};s.drawnText={};s.render()
eq(#s.tooltipCalls,0);check(not has(s,'Закрыть окно ·'));eq(#s.scopes,0)
-- A real click on every reader tab must leave Data immediately; query/selection survive.
for _,label in ipairs({'Всё','Избранное','Недавние'})do
    s.click='Всё##kb-mode';s.render()
    s.edits={['##kb-search']='Миранда'};s.render();s.edits={}
    s.click='Данные##kb-mode';s.drawnText={};s.render();check(has(s,'Проверить файл импорта'))
    s.click=label..'##kb-mode';s.drawnText={};s.render();eq(s.click,nil)
    check(has(s,'ПОИСК: слово')or has(s,'Поиск'));check(not has(s,'Проверить файл импорта'));eq(#s.scopes,0)
end
-- Explicit line breaks and wrapped words are individually centred and fit the button.
s=fixture();s.step();s.page('knowledge');require('support.knowledge_reader').all(s)
local function paintLabel(text,width,height)
    s.drawnLabels={};s.buttonCalls={}
    local im=s.imgui or require 'mimgui'
    s.rendererContext=true
    local stack={};local ui={push=function(fn)stack[#stack+1]=fn end,finish=function()table.remove(stack)()end}
    menu.fittedButton(im,ui,text..'##test-centering',im.ImVec2(width,height))
    s.rendererContext=false
    local b=s.buttonCalls[#s.buttonCalls];check(b)
    local top,lastY
    for _,line in ipairs(s.drawnLabels)do
        check(math.abs((line.x+line.measure.x/2)-(b.x+b.width/2))<.01,'each line must share the horizontal centre')
        check(line.x>=b.x+13.9);check(line.x+line.measure.x<=b.x+b.width-13.9)
        check(line.y>=b.y+7.9);check(line.y+line.size<=b.y+b.height-7.9)
        if lastY then eq(line.y-lastY,line.size)else top=line.y end
        lastY=line.y
    end
    eq(#stack,0);eq(#s.scopes,0);return s.drawnLabels
end
for _,width in ipairs({110,260,530})do
    local labels=paintLabel('Длинное русское название карточки\nКороткая подпись',width,64)
    check(#labels>=2)
    paintLabel('ОченьДлинноеНеразрывноеРусскоеНазвание',width,38)
end
-- The general-settings RP button uses fill width (-1). Treating that as a
-- literal text width previously produced a column of individual letters.
for _,width in ipairs({-1,-12,0})do
    local labels=paintLabel('Перенос /me и /do',width,36)
    local b=s.buttonCalls[#s.buttonCalls];check(b.width>100);check(b.height<=60);eq(#labels,1)
end
for _,size in ipairs({{760,600},{1600,1000},{2560,1440}})do
    s=fixture();s.step();s.resizeWindows={['Police Assistant 2026##pa26-main']={x=size[1],y=size[2]}}
    require('support.ui_routes').chat(s,'split');s.render()
    local found
    for _,button in ipairs(s.buttonCalls)do if button.label=='Изменить порог и маркер продолжения##manual-chat-rp-settings'then found=button end end
    check(found,'chat settings button must render');check(found.width>=100);check(found.height<=60,'settings label must not become a vertical column')
    check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)
end
-- A 34px icon must not dictate tooltip width or contaminate the next main window.
for _,size in ipairs({{760,600},{1600,1000},{2560,1440}})do
    s=fixture();s.step();s.resizeWindows={['Police Assistant 2026##pa26-main']={x=size[1],y=size[2]}}
    s.page('binds');s.hover='##bind-up1';s.tooltipCalls={};s.render()
    local t=s.tooltipCalls[#s.tooltipCalls];check(t and t.constraints)
    eq(t.constraints.min.x,t.constraints.max.x);check(t.constraints.min.x>=360)
    eq(t.padding.x,14);eq(t.padding.y,12);eq(s.nextConstraints,nil)
    s.hover=nil;s.render();check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)
end
-- Preserve the supplied forum recommendation; the new MANUAL requirement is a separate source update.
local raw=TEST_JSON_DECODE(TEST_KNOWLEDGE_JSON);local k=knowledge.new();k:activate(assert(knowledge.validate(raw)))
local rights=k.byKey['drafts:rights'];check(rights);eq(rights.item.origin,'forum_recommendation')
eq(knowledge.status(rights),'Архивная редакция')
local quote=rights.item.source_recommended_text
check(quote:find('Вы задержаны по подозрению в [кратко указать причину].',1,true))
check(quote:find('или иными незаконными методами запрещено.',1,true))
local speech={}
for _,step in ipairs(rights.item.steps)do
    if step.type=='speech'then
        speech[#speech+1]=step.text
        check(#codec.encode(step.text:gsub('{param:reason}','нападении на сотрудника полиции'))<=127)
    end
end
eq(table.concat(speech,' '):gsub('{param:reason}','[кратко указать причину]'),quote)
local detail=k:detail(rights);local fields={};for _,line in ipairs(detail)do fields[line.label]=(fields[line.label]or'')..line.text end
eq(fields['Текст из темы форума'],quote)
check(fields['Когда и как разъяснять права']:find('После стабилизации ситуации',1,true))
check(fields['Правовое основание']:find('ст. 20 ч. 2',1,true))
check(fields['Как применяется название «Миранда»']:find('не закрепляет классический американский текст',1,true))
check(not fields['Происхождение']);eq(raw.semantic_review.full_catalog_review_complete,false)
local broken=model.copy(raw);broken.drafts[1].application_conditions={42};eq(knowledge.validate(broken),nil)
s=fixture();s.step();s.page('knowledge');require('support.knowledge_reader').all(s)
s.combo='##kb-choice-Раздел';s.click='RP-тексты##kb-choice-Разделdrafts';s.render();s.combo=nil
s.edits={['##kb-search']='Миранда'};s.render();s.edits={}
s.click=rights.title..'\n'..knowledge.status(rights)..'##kb-row-'..rights.key;s.render();s.render()
eq(s.click,nil);check(has(s,quote));check(has(s,'Вариант для бинда'));eq(#s.sent,0);eq(#s.scopes,0)
check(not s.hasLog('Ошибка интерфейса'))

local fixture=require 'support.fixture';local important=require 'pa26_knowledge_important';local knowledge=require 'pa26_knowledge';local model=require 'pa26_bindings'
eq(knowledge.personalDefaults().view.top_tab,'important')
local p=knowledge.personalDefaults();p.view.top_tab='bad';check(not knowledge.validatePersonal(p))
local s=fixture({important=true});s.step();s.page('knowledge');local v=s.knowledgeUi;local d=v.knowledge.important
check(d);eq(#d.cards,10);eq(d.radioCount,54);eq(d.required,21);eq(d.free,29)
local function rows(card,tab)return important.filter(d,'',card,tab)end
eq(#rows('radio','decimal'),31);eq(#rows('radio','three'),11);eq(#rows('radio','situational'),12)
eq(#rows('catalog','all'),31);eq(#rows('commands','all'),50)
local by={};for _,r in ipairs(rows('commands','all'))do by[r.id]=r end
check(by['/rang'].text:find('Не требует',1,true));check(by['/ud'].text:find('Не требует',1,true));check(not by['/skip'].text:find('Не требует',1,true));check(by['/setskin']);check(by['/uninviteoff']);eq(by['/pull'],nil)
for _,q in ipairs({'10-46','390W','тайзер','миранда','/cuff','43'})do check(#important.filter(d,q)>0,q)end
for _,r in ipairs(d.rows)do check(not r.text:find('http',1,true));check(r.search);check(r.key)end
local fines={};for _,r in ipairs(rows('fines','all'))do fines[r.id]=r end
check(fines['AK:43'].text:find('от 10 до 20 ПМ',1,true));check(fines['AK:47'].text:find('от 30 до 50 ПМ',1,true))
local titles={};for _,r in ipairs(rows('catalog','all'))do titles[r.id]=r.title end
check(titles['05.01']:find('взятки',1,true));check(titles['11.03']:find('Похищение',1,true));check(titles['12.01']:find('6 зв.',1,true))
for _,c in ipairs(d.cards)do
 v.importantView={query='',page=1,expanded={}};s.click='Открыть памятку##important-open-'..c.id;s.render();s.render()
 eq(v.importantView.card,c.id);for _,section in ipairs(c.sections)do v.importantView.tab=section.id;v.importantView.cache=nil;s.render()end
 check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(#s.sent,0)
end
v:switchTop('registry');s.render();s.step();eq(v.knowledge.personal.view.top_tab,'registry')
v:switchTop('important');s.render();s.step();eq(v.knowledge.personal.view.top_tab,'important')
v:select('articles:AK:43');eq(v.knowledge.personal.view.top_tab,'registry');eq(v.selected,'articles:AK:43')
-- Unsaved card drafts guard switching into the new dashboard.
v.editor={dirty=true};v:switchTop('important');check(v.confirm and v.confirm.kind=='unsaved_card');eq(v.knowledge.personal.view.top_tab,'registry')
v.editor=nil;v.confirm=nil
local ui=require 'pa26_knowledge_important_ui';eq(ui.columns(240,24),1);eq(ui.columns(1150,16),3)
for _,size in ipairs({{640,480},{800,600},{1024,768},{1152,864},{1366,768},{1920,1080},{2560,1440}})do
 local t=fixture({important=true});t.step();t.io.DisplaySize.x=size[1];t.io.DisplaySize.y=size[2];t.page('knowledge');t.render()
 check(not t.hasLog('Ошибка интерфейса'),table.concat(t.logs,'\n'));eq(#t.scopes,0);eq(#t.sent,0)
end

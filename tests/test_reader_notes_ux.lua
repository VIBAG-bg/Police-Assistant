local fixture=require 'support.fixture';local view=require 'pa26_knowledge_ui';local data=require 'pa26_knowledge';local core=require 'pa26_core'
local bit=require 'bit'
local clock=0;local k=data.new({now=function()return clock end});local v=view.new(nil,nil,k)
v:tick('session',clock,true);eq(v.group,'all');v.group='commands'
clock=700000;v:tick('session',clock,true);eq(v.group,'commands','open reader must never consume its timeout')
v:tick('session',clock,false);clock=clock+599999;v:tick('session',clock,false);eq(v.group,'commands')
v:tick('session',clock,true);eq(v.group,'commands','return before deadline keeps selection')
clock=clock+900000;v:tick('session',clock,true);eq(v.group,'commands')
v:tick('session',clock,false);clock=clock+600000;v:tick('session',clock,false);eq(v.group,'all')
v.group='radio';v:tick('session',clock,true);v:tick('session',clock,false);clock=clock+600001
v.editor={draft={text='Не потерять'}};v:tick('session',clock,false);eq(v.group,'radio');eq(v.editor.draft.text,'Не потерять')
v:tick('session',clock,true);v.editor=nil;eq(v.group,'radio')
k.personal.view.reset_enabled=false;v:tick('session',clock,false);clock=clock+900000;v:tick('session',clock,false);eq(v.group,'radio')
v:tick('other',clock,false);eq(v.group,'all','new session resets even with optional timer disabled')
local old=data.personalDefaults();old.view=nil;eq(assert(data.validatePersonal(old)).view.reset_minutes,10)
old.view={reset_enabled=true,reset_minutes=0};check(not data.validatePersonal(old))
local function healthy(s)check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(#s.sent,0)end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,label);healthy(s)end
local s=fixture({alerts=true});s.step();s.page('knowledge');require('support.knowledge_reader').filters(s)
local combos={};local original=s.imgui.BeginCombo
s.imgui.BeginCombo=function(id,preview)combos[id]=preview;return original(id,preview)end
s.drawnText={};s.childCalls={};s.render()
eq(combos['##kb-choice-Раздел'],'Все разделы');eq(combos['##kb-choice-Ведомство'],nil);eq(combos['##kb-choice-Статус'],'Все статусы')
local text=table.concat(s.drawnText,'\n');check(not text:find('Нажмите ниже',1,true));check(not text:find('Поиск в списке',1,true))
local pinned,items
for _,c in ipairs(s.childCalls)do
    if c.name=='##kb-list'then pinned=c end
    if c.name=='##kb-list-items'then items=c end
end
check(pinned and items);check(bit.band(pinned.flags,s.imgui.WindowFlags.NoScrollWithMouse)~=0);eq(items.parent,'##kb-list')
local sizes,faces={},{};local renderText=s.imgui.TextUnformatted
s.imgui.TextUnformatted=function(text)sizes[text]=s.imgui.GetFontSize();faces[text]=tostring(s.imgui.GetFont());return renderText(text)end
s.render();local searchFace=faces['ПОИСК: слово, номер статьи или команда']or faces['Поиск'];check(searchFace);eq(faces['Раздел'],searchFace);eq(faces['Раздел'],faces['Ведомство']);eq(faces['Раздел'],faces['Статус'])
s.combo='##kb-choice-Раздел';click(s,'Команды##kb-choice-Разделcommands');s.combo=nil;s.render();eq(combos['##kb-choice-Раздел'],'Команды')
click(s,'Данные##kb-mode');s.toggle='Сбрасывать раздел после выхода из базы##kb-reset-enabled';s.intEdits={['Минуты после выхода##kb-reset-minutes']=7};s.render();s.step()
local personal=decodeJson(s.files['moonloader\\config\\police_assistant_2026_knowledge_personal.json'])
check(not personal.view.reset_enabled);eq(personal.view.reset_minutes,7)
-- Contacts appear in both the sidebar and footer.
s.drawnText={};s.render();text=table.concat(s.drawnText,'\n')
for _,contact in ipairs({'Telegram: victor_bg','Discord: victor_bag','GitHub: VIBAG-bg'})do
    local first=text:find(contact,1,true);check(first);check(text:find(contact,first+#contact,true))
end
s.page('hints');local favorite=s.workspace.library.notes[1].favorite
click(s,'##note-favorite1');eq(s.workspace.library.notes[1].favorite,not favorite)
click(s,'##note-favorite1');eq(s.workspace.library.notes[1].favorite,favorite)
click(s,'Редактировать##note');s.edits={['Название##note']='Новый черновик'};s.render();s.edits={}
click(s,'##note-favorite1');click(s,'Сохранить памятку');eq(s.workspace.library.notes[1].name,'Новый черновик')
healthy(s);onScriptTerminate(s.script)
-- Hover borders explicitly keep rounded corners; Alt hint remains readable.
s=fixture({alerts=true});s.step();s.down[0x12]=true;s.step()
local b=s.alerts.buttons.code0;check(b)
s.io.MousePos.x=b.x+b.w/2;s.io.MousePos.y=b.y+b.h/2
local found=false;local rect=s.drawList.AddRect
s.drawList.AddRect=function(self,a,b,color,radius,flags,thickness)
    if flags==15 and radius>0 then found=true end
    return rect(self,a,b,color,radius,flags,thickness)
end
s.step();check(found);check(s.alerts.metrics.cursor:find('Удерживайте Alt',1,true));healthy(s);onScriptTerminate(s.script)

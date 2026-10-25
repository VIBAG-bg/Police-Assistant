local fixture=require 'support.fixture'
local bit=require 'bit'
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'))
    eq(#s.scopes,0);eq(s.invalidIOReads,0);eq(#s.sent,0)
end
local function has(s,text)return table.concat(s.drawnText,'\n'):find(text,1,true)~=nil end
local function click(s,label)
    s.ackInfo()
    s.click=label;s.render();eq(s.click,nil,label)
    s.drawnText={};s.buttonCalls={};s.childCalls={};s.render();healthy(s)
end
local function footer(s,long,short)
    s.buttonCalls={};s.render()
    for _,b in ipairs(s.buttonCalls)do
        if b.label==long..'##footer'or b.label==short..'##footer'then click(s,b.label);return b.label end
    end
    error('missing reference shortcut: '..long)
end
-- Footer shortcuts reach the selected guide. Switching back and forth keeps a
-- real edited note intact, including after navigating directly through section 05.
local s=fixture();s.step();s.page('hints')
click(s,'Добавить новую памятку')
local id=s.workspace.library.notes[#s.workspace.library.notes].id
s.edits={['Название##note']='Не потерять черновик',['Текст##note']='Моя строка.\nЕщё одна строка.'};s.render();s.edits={}
click(s,'Подсказки##reference-guide');check(has(s,'/pa26'))
local pages={
    {'Список команд','Команды','/pa26'},
    {'Список клавиш','Клавиши','Главное меню'},
    {'Список функций','Функции','RP-отыгровки с редактируемыми фразами'},
    {'Список переменных','Переменные','{my_name}'},
}
for _,page in ipairs(pages)do
    local label=footer(s,page[1],page[2]);check(has(s,page[3]))
    local active
    for _,b in ipairs(s.buttonCalls)do if b.label==label then active=b end end
    check(active and active.color and active.color.g>.4)
    click(s,'Памятки##reference-notes');check(has(s,'Название'));check(has(s,'Текст'))
    click(s,'Подсказки##reference-guide');check(has(s,page[3]),'the previously selected guide must survive')
end
s.page('hints');healthy(s)
click(s,'Сохранить памятку')
local note;for _,n in ipairs(s.workspace.library.notes)do if n.id==id then note=n end end
check(note);eq(note.name,'Не потерять черновик');eq(note.body,'Моя строка.\nЕщё одна строка.')
local saved=s.savedLibrary()
eq(saved.notes[#saved.notes].name,note.name);eq(saved.notes[#saved.notes].body,note.body)
-- A footer link from another section still opens section 05. Its return button
-- is outside the scrolling reference content, including in a narrow F9 window.
for _,width in ipairs({760,1180,1600})do
    s.resizeWindows={['Police Assistant 2026##pa26-main']={x=width,y=760}}
    s.page('home');footer(s,'Список переменных','Переменные')
    local back,other,content
    for _,b in ipairs(s.buttonCalls)do
        if b.label=='Памятки##reference-notes'then back=b end
        if b.label=='Подсказки##reference-guide'then other=b end
    end
    for _,c in ipairs(s.childCalls)do
        if c.name=='content##pa26'then content=c end
    end
    check(back and other and content);eq(back.parent,nil);eq(back.window,'Police Assistant 2026##pa26-main')
    check(back.width<160);eq(back.height,other.height)
    check(other.color.g>back.color.g,'selected half must be visible')
    check(bit.band(content.flags,s.imgui.WindowFlags.NoScrollWithMouse)==0)
    click(s,'Памятки##reference-notes')
    check(has(s,'Не потерять черновик'))
end
onScriptTerminate(s.script)
-- The compact switch shares a wide header; a narrow header puts it in the
-- upper-right corner below the title, without covering title or close icon.
local menu=require 'pa26_menu'
local font={FontSize=16,CalcTextSizeA=function(_,size,_,_,text)
    local n=0;for _ in text:gmatch('[%z\1-\127\194-\244][\128-\191]*')do n=n+1 end
    return {x=n*size*.5,y=size}
end}
for _,width in ipairs({640,760,1180,1600,2560})do
    local layout=menu.layout(width,900);local box=menu.referenceSwitchLayout(layout,font,252)
    check(box.x>=layout.x and box.x+box.w<=layout.x+layout.w+.01)
    check(box.w<=272);check(box.h<=40)
    if box.bodyOffset==0 then
        check(box.x>=layout.x+20+252+20);check(box.x+box.w<=layout.x+layout.w-60)
    else
        eq(box.y,layout.bodyY);eq(box.bodyOffset,box.h+8)
    end
end
-- Search captions use a bold face without changing their native input IDs.
s=fixture();s.step()
local fonts={};local renderText=s.imgui.TextUnformatted
s.imgui.TextUnformatted=function(text)fonts[text]=tostring(s.imgui.GetFont());return renderText(text)end
for _,page in ipairs({'knowledge','hints','binds','stats'})do s.page(page);healthy(s)end
for _,title in ipairs({'ПОИСК: слово, номер статьи или команда','ПОИСК: памятки','ПОИСК: бинды','ПОИСК: журнал'})do
    check(fonts[title],title)
end
eq(fonts['ПОИСК: слово, номер статьи или команда'],fonts['Раздел'])
s.page('hints');s.edits={['Поиск памяток##tips']='несуществующая памятка'};s.buttonCalls={};s.render();s.edits={}
for _,b in ipairs(s.buttonCalls)do check(b.label~='Как пользоваться биндами##note1')end
healthy(s)
onScriptTerminate(s.script)
-- The cursor hint is plain bold text on the outer widget. Every wrapped line is
-- centred from its measured width; no filled inner rectangle lies behind it.
for _,display in ipairs({{640,480,1},{1280,720,1},{2560,1440,2}})do
    s=fixture({alerts=true,widgetScale=display[3]});s.io.DisplaySize.x,s.io.DisplaySize.y=display[1],display[2];s.step()
    local fills={};local fill=s.drawList.AddRectFilled
    s.drawList.AddRectFilled=function(self,a,b,color,radius)
        fills[#fills+1]={x=a.x,y=a.y,w=b.x-a.x,h=b.y-a.y};return fill(self,a,b,color,radius)
    end
    s.drawnLabels={};s.render()
    local m,r=s.alerts.metrics,s.alerts.bounds;check(m and r)
    local n=0
    for _,paint in ipairs(s.drawnLabels)do
        for _,line in ipairs(m.cursorLayout.lines)do if paint.text==line.text then
            n=n+1;eq(paint.size,14*m.scale)
            check(math.abs(paint.x+paint.measure.x/2-r.x-r.w/2)<.02)
            check(paint.x>=r.x+m.pad-.02 and paint.x+paint.measure.x<=r.x+r.w-m.pad+.02)
        end end
    end
    eq(n,#m.cursorLayout.lines)
    local top=r.y+m.cursorTop
    for _,rect in ipairs(fills)do
        check(not(rect.x>=r.x and rect.x+rect.w<=r.x+r.w+.02 and rect.y>=top-1 and rect.y+rect.h<=top+m.cursorH+1),'extra background behind the hint')
    end
    check(top+m.cursorH<=r.y+m.bar-10*m.scale)
    healthy(s);onScriptTerminate(s.script)
end

local fixture=require 'support.fixture'
local menuModule=require 'pa26_menu'
local studioModule=require 'pa26_studio'
local bit=require 'bit'
local main='Police Assistant 2026##pa26-main'
local quick='Police Assistant · Быстрое меню##pa26-quick'
local tips='Police Assistant · Памятки##pa26-tips'
local path='moonloader\\config\\police_assistant_2026_library.json'
local function open(s,page)
    if not s.frames[1].condition() then s.commands.pa26() end
    s.page(page)
end
local function bounded(s,name)
    local w=s.windows[name]; check(w)
    check(w.width>0 and w.height>0); check(w.x>=16 and w.y>=16)
    check(w.x+w.width<=s.io.DisplaySize.x-16.01+.02)
    check(w.y+w.height<=s.io.DisplaySize.y-16.01+.02)
end
local function resize(s,name,w,h)
    s.resizeWindows={[name]={x=w,y=h}}; s.render(); bounded(s,name)
end

for _,display in ipairs({{640,480},{800,600},{1280,720},{1920,1080},{2560,1440}}) do
    for _,key in ipairs({'main','quick','tips'}) do
        local r=menuModule.windowBounds(display[1],display[2],key); check(r)
        check(r.minW<=r.width and r.width<=r.maxW); check(r.minH<=r.height and r.height<=r.maxH)
        check(r.maxW<=display[1]-32 and r.maxH<=display[2]-32)
    end
end
eq(menuModule.windowBounds(0/0,720,'main'),nil); eq(menuModule.windowBounds(100,100,'main'),nil)
for _,width in ipairs({1,320,608,729,730,820,1200,2000}) do
    for _,ratio in ipairs({-.5,0,.46,.75,2,0/0}) do
        local r=studioModule.bindingPanels(width,400,ratio); check(r)
        if r.wide then
            check(r.left>=260 and r.right>=360); check(math.abs(r.left+r.gap+r.right-width)<.001)
        end
    end
end

-- The native user size survives rendering and closing/reopening all three windows.
local s=fixture(); s.step(); local before=s.savedBytes()
check(bit.band(s.windows[main].flags,s.imgui.WindowFlags.NoResize)~=0) -- bounded PA edge handles
resize(s,main,980,630); eq(s.windows[main].width,980); eq(s.windows[main].height,630)
s.render(); eq(s.windows[main].width,980)
s.commands.pa26(); s.step(); s.commands.pa26(); s.step(); eq(s.windows[main].width,980)
s.commands.pa26quick(); s.step(); resize(s,quick,480,540)
onWindowMessage(0x0100,0x1B); s.commands.pa26quick(); s.step(); eq(s.windows[quick].width,480)
s.commands.pa26tips(); s.step(); resize(s,tips,560,550)
onWindowMessage(0x0100,0x1B); s.commands.pa26tips(); s.step(); eq(s.windows[tips].width,560)
s.io.DisplaySize.x,s.io.DisplaySize.y=640,480; s.render(); bounded(s,tips)
eq(s.savedBytes(),before,'window sizing must not rewrite the library or discard any draft')
check(not s.hasLog('Ошибка интерфейса')); onScriptTerminate(s.script)

-- Backends lacking native edge support still have working edge and corner handles.
s=fixture(); s.io.BackendFlags=0; s.io.DisplaySize.x=1920;s.step()
local initial=s.windows[main].width
s.activeItem='##resize-main-right'; s.io.MouseDelta.x=30; s.render()
s.activeItem=nil;s.io.MouseDelta.x=0;s.render()
eq(s.windows[main].width,initial+30); eq(s.cursorShape,s.imgui.MouseCursor.ResizeEW)
s.activeItem='##resize-main-tl'; s.io.MouseDelta.x=30; s.io.MouseDelta.y=40; s.render()
s.activeItem=nil;s.io.MouseDelta.x,s.io.MouseDelta.y=0,0;s.render()
bounded(s,main); eq(s.cursorShape,s.imgui.MouseCursor.ResizeNWSE)
s.activeItem=nil; s.io.MouseDelta.x,s.io.MouseDelta.y=0,0
local seen={}
for _,b in ipairs(s.buttonCalls) do if b.label:find('##resize%-main%-') then seen[b.label]=true end end
local count=0; for _ in pairs(seen) do count=count+1 end; eq(count,8)
check(not s.hasLog('Ошибка интерфейса')); onScriptTerminate(s.script)

-- Complete long labels use wrapped text and measured row heights; only the parent scrolls.
s=fixture(); s.step(); open(s,'binds'); s.click='+ Новый сценарий ( Добавить бинд )'; s.render()
local name='Полная проверка документов и служебного удостоверения гражданина'
s.edits={['Название##bind']=name,['##script']='Короткая тестовая реплика.'}; s.render()
s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
s.childCalls={}; s.drawnLabels={}; s.render()
local row,titleButton;local paints={}
for _,c in ipairs(s.childCalls) do
    if c.name=='bindingrow##7' then row=c end
    if c.name=='bindrows##studio' then check(bit.band(c.flags,s.imgui.WindowFlags.NoScrollbar)==0) end
end
for _,b in ipairs(s.buttonCalls)do if b.label=='007  '..name..'##bind7'then titleButton=b end end
for _,label in ipairs(s.drawnLabels) do if label.item=='007  '..name..'##bind7' then paints[#paints+1]=label end end
check(row and titleButton);check(#paints>1,'long title must occupy complete readable lines')
local words={}
for _,paint in ipairs(paints)do
    words[#words+1]=paint.text
    check(math.abs(paint.x+paint.measure.x/2-titleButton.x-titleButton.width/2)<.01)
    check(paint.y>=titleButton.y and paint.y+paint.size<=titleButton.y+titleButton.height)
end
eq(table.concat(words,' '):gsub('%s+',' '),('007  '..name):gsub('%s+',' '))
check(row.height>=#paints*paints[1].size+16+24+10+18,'card includes full title, spacing and metadata')
check(bit.band(row.flags,s.imgui.WindowFlags.NoScrollbar)~=0)
check(bit.band(row.flags,s.imgui.WindowFlags.NoScrollWithMouse)~=0)
local original=s.savedBytes()
local function panelWidths()
    local a,b
    for _,c in ipairs(s.childCalls) do if c.name=='bindlist##studio' then a=c.width elseif c.name=='bindeditor##studio' then b=c.width end end
    return a,b
end
local left=panelWidths()
s.activeItem='##bind-panel-divider'; s.io.MouseDelta.x=40; s.childCalls={}; s.render()
local nextLeft,right=panelWidths(); check(nextLeft>left); check(right>=360)
eq(s.savedBytes(),original); s.activeItem=nil; s.io.MouseDelta.x=0

-- An unsaved edit survives resizing across the list/editor breakpoint and back.
s.edits={['##script']='Несохранённый текст при изменении размера.'}; s.render()
resize(s,main,760,600)
s.drawnText={}; s.render(); check(table.concat(s.drawnText,'\n'):find('Редактор сценария',1,true) or table.concat(s.drawnText,'\n'):find('Изменения ещё не сохранены',1,true))
s.click='К списку биндов##bind-back'; s.render(); s.render()
s.click='007  '..name..'##bind7'; s.render(); s.render()
s.click='Сохранить сценарий'; s.render();s.ackInfo(); s.step()
local lib=s.savedLibrary(); eq(lib.bindings[7].script,'Несохранённый текст при изменении размера.')
s.io.DisplaySize.x,s.io.DisplaySize.y=1920,1080; resize(s,main,1400,900)
check(not s.hasLog('Ошибка интерфейса')); eq(#s.scopes,0); onScriptTerminate(s.script)

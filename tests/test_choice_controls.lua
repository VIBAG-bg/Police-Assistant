local fixture=require 'support.fixture'
local menu=require 'pa26_menu'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local function healthy(s)
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'))
    eq(#s.scopes,0);eq(s.invalidIOReads,0);eq(#s.sent,0)
end
local function click(s,label)
    s.click=label;s.render();eq(s.click,nil,'Choice not visible: '..label);healthy(s)
end
local function has(s,text)return table.concat(s.drawnText,'\n'):find(text,1,true)~=nil end
local s=fixture({demo=false,alerts=true,notifications=true});s.step();s.page('settings')
click(s,'Оружие##settings-tab-weapons')
local combos={};local begin=s.imgui.BeginCombo
s.imgui.BeginCombo=function(id,preview)combos[#combos+1]={id=id,preview=preview};return begin(id,preview)end
s.render()
local buttons={}
for _,b in ipairs(s.buttonCalls)do buttons[b.label]=b end
check(buttons['Отыгрывание оружия##Снаряжение##weapons-pagedraw'])
check(buttons['Тайзер##Снаряжение##weapons-pagetaser'])
check(buttons['Предупреждения##Снаряжение##weapons-pagewarning'])
for _,c in ipairs(combos)do check(c.id~='##Снаряжение##weapons-page')end
click(s,'Предупреждения##Снаряжение##weapons-pagewarning')
check(has(s,'Предупреждения · текст и показ'))
click(s,'Оружие в руках##Когда напоминать##warning-triggerstable')
click(s,'ДА / НЕТ##Показ##warning-modeconfirm')
s.step();eq(s.workspace.library.weapon_warning.trigger,'stable');eq(s.workspace.library.weapon_warning.mode,'confirm')
local saved=s.savedLibrary()
eq(saved.weapon_warning.trigger,'stable');eq(saved.weapon_warning.mode,'confirm')
click(s,'Тайзер##Снаряжение##weapons-pagetaser');check(has(s,'Тайзер · выстрелы, таймер и перезарядка'))
click(s,'Отыгрывание оружия##Снаряжение##weapons-pagedraw')
-- Large catalogues show the selected value in the dropdown itself, with no search.
s.drawnText={};combos={};s.render();check(not has(s,'Нажмите ниже, чтобы открыть список (43).'))
local preview
for _,c in ipairs(combos)do if c.id=='##Изменить оружие##weapon-edit'then preview=c.preview end end
check(preview and preview:find('GTA ID',1,true))
s.combo='##Изменить оружие##weapon-edit'
local input=s.imgui.InputText
s.imgui.InputText=function(id,...)check(id~='##Изменить оружие##weapon-edit-search');return input(id,...)end
click(s,'SD Pistol · GTA ID 23##Изменить оружие##weapon-edit23')
eq(s.workspace.studio.weaponEdit,'23')
s.combo=nil;s.render();combos={};s.combo='##Изменить оружие##weapon-edit';s.render()
for _,c in ipairs(combos)do if c.id=='##Изменить оружие##weapon-edit'then eq(c.preview,'SD Pistol · GTA ID 23')end end
s.combo=nil
-- Navigation in another section also works without discovering a dropdown.
click(s,'Связь##settings-tab-radio')
click(s,'Патруль##Настройки связи##radio-pagepatrol');check(has(s,'Патруль полиции и охрана тюрьмы'))
click(s,'Автодоклады##Настройки связи##radio-pageautomatic');check(has(s,'Предупреждения и свои автодоклады'))
click(s,'Экстренные##Настройки связи##radio-pageemergency');check(has(s,'Shots fired · SOS · радиокоды'))
-- Layout uses the same UTF-8 wrapping as its rendered labels. No narrow columns.
local font={FontSize=16,CalcTextSizeA=function(_,size,_,wrap,text)
    local n=0;for _ in text:gmatch('[%z\1-\127\194-\244][\128-\191]*')do n=n+1 end
    return {x=n*size*.5,y=size}
end}
local choices={{'draw','Полная подпись','Отыгрывание оружия'},{'taser','Полная подпись','Тайзер'},{'warning','Полная подпись','Предупреждения'}}
for _,width in ipairs({180,220,300,420,600,900})do
    local layout=menu.choiceLayout(font,16,width,choices,{buttons=true});check(layout)
    check(layout.width*layout.columns+8*(layout.columns-1)<=width+.01)
    for i,v in ipairs(choices)do
        local text=menu.labelLayout(font,16,layout.width-28,v[3]);check(#text.lines<=2)
        check(text.height+16<=layout.heights[math.ceil(i/layout.columns)])
    end
end
eq(menu.choiceLayout(font,16,500,choices,{list=true}),nil)
local six={{1,'Один'},{2,'Два'},{3,'Три'},{4,'Четыре'},{5,'Пять'},{6,'Шесть'}}
local balanced=menu.choiceLayout(font,16,500,six,{})
eq(balanced.columns,3);eq(balanced.rows,2)
-- Merely browsing controls never starts a bind or transmits a game message.
healthy(s);onScriptTerminate(s.script)

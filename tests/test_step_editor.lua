local fixture=require 'support.fixture'
local binder=require 'pa26_binder'
local model=require 'pa26_bindings'
local ffi=require 'ffi'
local bit=require 'bit'
local path='moonloader\\config\\police_assistant_2026_library.json'

-- Text blocks retain editor boundaries, while execution checks every outgoing line.
local block='Первая строка.\n\nВторая {my_id}.\nC:\\Temp\\file (x)\nLiteral \\n'
local source=binder.toScript({{kind='message',template=block},{kind='wait',ms=1500},{kind='message',template='Последняя.'}})
local edited,err=binder.parseEditor(source); check(edited,err); eq(#edited,3); eq(edited[1].template,block)
local executable=binder.parse(source); eq(#executable,6); eq(executable[2].template,'Вторая {my_id}.')
eq(executable[3].template,'C:\\Temp\\file (x)'); eq(executable[4].template,'Literal \\n')
eq(executable[5].kind,'wait')
local b=model.newBinding(7); b.script=source
local ctx={session='test',now=10000,demo=true,values={my_id='42',accent='[Русский акцент]:'}}
local plan; plan,err=binder.compile(b,ctx,{},codec); check(plan,err); eq(#plan.lines,5)
eq(plan.lines[1],'Первая строка.'); eq(plan.lines[2],'Вторая 42.')
for _,value in ipairs(plan.lines) do check(not value:find('\n',1,true)); check(#codec.encode(value)<=127) end
local literal=binder.toScript({{kind='message',template='@wait(1000)'},{kind='message',template='-- Speech, not a comment.'}})
edited=binder.parseEditor(literal); executable=binder.parse(literal)
eq(#edited,2); eq(#executable,2); eq(executable[1].kind,'message'); eq(executable[1].template,'@wait(1000)')
eq(executable[2].template,'-- Speech, not a comment.')
check(not binder.parse('@text(bad\\q)')); check(not binder.parse('@text(trailing\\)'))
edited=binder.parseEditor('@text()'); eq(#edited,1); eq(edited[1].template,''); check(not binder.parse('@text()'))
b.script=binder.toScript({{kind='message',template=string.rep('x\n',64)}}); check(binder.compile(b,ctx,{},codec))
b.script=binder.toScript({{kind='message',template=string.rep('x\n',65)}}); check(not binder.compile(b,ctx,{},codec))
b.script=binder.toScript({{kind='message',template='Допустимо.\n'..string.rep('я',128)}})
check(not binder.compile(b,ctx,{},codec),'an oversized later line rejects the entire block before sending')
b.script=binder.toScript({{kind='message',template='/me действие\nРечь.'}})
plan=binder.compile(b,ctx,{},codec); eq(plan.lines[1],'/me действие'); eq(plan.lines[2],'Речь.')

local s=fixture(); s.step(); s.page('binds'); s.click='+ Новый сценарий ( Добавить бинд )'; s.render()
s.edits={['Название##bind']='Многострочные шаги',['##script']='Первая.\n@wait(1500)\nПоследняя.'}; s.render()
s.click='Шаги##mode'; s.render()
local function fresh()
    s.multilineCalls={}; s.childCalls={}; s.buttonCalls={}; s.drawnText={}; s.render()
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'))
end
local function messages()
    local result={}; for _,field in ipairs(s.multilineCalls) do
        local uid=field.label:match('^##textstep(%d+)$'); if uid then result[tonumber(uid)]=field.text end
    end; return result
end
local function countSteps()
    local total=0; for _,child in ipairs(s.childCalls) do if child.name:match('^step##') then total=total+1 end end; return total
end
local function save()
    s.click='Сохранить сценарий'; fresh();s.ackInfo(); s.step(); return s.savedLibrary().bindings[7].script
end
local function variable(name,uid,cursor)
    s.focusInput={label='##textstep'..uid,cursor=cursor,first=cursor,last=cursor}; fresh()
    s.edits={['Найти переменную##search']=name}; fresh(); s.combo='##Вставка##variable'; fresh()
    local info; for _,entry in ipairs(model.variables) do if entry[1]==name then info=entry[2] end end
    s.click='{'..name..'} · '..info..'##Вставка##variable'..name; fresh(); s.combo=nil
    s.click='Вставить {'..name..'}##insert'; fresh(); fresh()
end

-- Enter in the first reply must neither split it nor stop drawing later controls.
s.edits={['##textstep1']='Первая.\nНовая строка.\n'}; fresh(); fresh()
eq(countSteps(),3); eq(messages()[1],'Первая.\nНовая строка.\n'); eq(messages()[3],'Последняя.')
for _,field in ipairs(s.multilineCalls) do
    check(field.height>=96 and field.height<=180); eq(field.size,16385); eq(field.flags,s.imgui.InputTextFlags.CallbackAlways)
end
for _,child in ipairs(s.childCalls) do if child.name:match('^step##') then
    check(bit.band(child.flags,s.imgui.WindowFlags.NoScrollbar)~=0)
    check(bit.band(child.flags,s.imgui.WindowFlags.NoScrollWithMouse)~=0)
    check(child.height>=150,'card must have space for heading, input and toolbar')
end end
variable('my_id',1,#'Первая.\n')
eq(messages()[1],'Первая.\n{my_id}Новая строка.\n',tostring(messages()[1])..' | '..table.concat(s.drawnText,' | ')); eq(countSteps(),3)
s.edits={['##textstep1']='Первая.\n{my_id}Новая строка.\nТретья.'}; fresh(); fresh(); eq(countSteps(),3)
source=save(); edited=binder.parseEditor(source); eq(#edited,3); eq(edited[1].template,messages()[1])
executable=binder.parse(source); eq(#executable,5)

-- Moving/deleting uses stable field identities; the remaining buffer never changes owner.
s.click='Ниже##step1'; fresh(); fresh(); eq(countSteps(),3)
eq(messages()[1],edited[1].template); eq(messages()[3],'Последняя.')
s.intEdits={['##wait2']=2500}; fresh(); source=save(); executable=binder.parse(source); eq(executable[1].ms,2500)
s.click='Удалить##step2'; fresh(); fresh(); eq(countSteps(),2)
eq(messages()[1],edited[1].template); eq(messages()[3],'Последняя.')
variable('area',3,#'Последняя'); eq(messages()[3],'Последняя{area}.')
s.click='Удалить##step1'; fresh(); fresh(); eq(countSteps(),1); eq(messages()[3],'Последняя{area}.')
s.click='+ Реплика##addstep'; fresh(); fresh(); eq(countSteps(),2)
eq(messages()[4],'Новая реплика.'); eq(messages()[3],'Последняя{area}.')
source=save(); edited=binder.parseEditor(source); eq(#edited,2); eq(edited[1].template,'Последняя{area}.')

-- An empty reply stays a visible editor step instead of exposing another row's stale buffer.
s.edits={['##textstep4']=''}; fresh(); fresh(); eq(countSteps(),2); eq(messages()[4],'')
s.edits={['##textstep4']=string.rep('Длинная строка.\n',20)}; fresh(); fresh()
eq(countSteps(),2); check(#messages()[4]>400)
for _,field in ipairs(s.multilineCalls) do if field.label=='##textstep4' then eq(field.height,180) end end
source=save(); eq(#binder.parseEditor(source),2); eq(#binder.parse(source),21)
local first=messages()[3]
s.click='Удалить##step3'; fresh(); fresh(); eq(countSteps(),1)
s.click='Удалить##step4'; fresh(); fresh(); eq(countSteps(),0)
s.click='+ Реплика##addstep'; fresh(); fresh(); eq(countSteps(),1); eq(messages()[5],'Новая реплика.')
check(messages()[5]~=first)

-- Save, change mode, select a different bind, then reload: one saved block remains one card.
s.edits={['##textstep5']='A.\nB.\nC.'}; fresh(); source=save(); eq(#binder.parseEditor(source),1)
s.click='Текст##mode'; fresh(); s.click='Шаги##mode'; fresh(); eq(countSteps(),1)
s.click='001  Представиться##bind1'; fresh()
s.click='007  Многострочные шаги##bind7'; fresh(); fresh(); eq(countSteps(),1); eq(messages()[1],'A.\nB.\nC.')
s.click='Действия с биндами##bind-tools';s.render();s.click='Дублировать##bind'; fresh(); fresh(); eq(countSteps(),1); eq(messages()[1],'A.\nB.\nC.')
check(not s.hasLog('Ошибка интерфейса')); eq(#s.sent,0); eq(#s.scopes,0)
onScriptTerminate(s.script)

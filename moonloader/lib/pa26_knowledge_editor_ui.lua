-- The catalogue's personal editor. File operations are queued to the game loop.
local model=require 'pa26_bindings'
local edits=require 'pa26_knowledge_edits'
local data=require 'pa26_knowledge'
local core=require 'pa26_core'
local M={}
local function clearBuffers(v,prefix)
    for key in pairs(v.buffers)do if key:sub(1,#prefix)==prefix then v.buffers[key]=nil end end
end
local function checkBox(v,label,value)
    local b=v.im.new.bool(value==true);local changed=v.im.Checkbox(label,b)
    return b[0]==true,changed
end
local function split(value)
    local out={};for line in value:gmatch('[^\r\n]+')do line=line:match('^%s*(.-)%s*$');if line~=''then out[#out+1]=line end end
    return out
end
function M.after(v,action)
    v.editor=nil;v.review=nil;clearBuffers(v,'edit-');v.editorError=nil
    if not action then return end
    if action.kind=='select'then v:select(action.key)
    elseif action.kind=='mode'then v:switchMode(action.mode)
    elseif action.kind=='new'then M.open(v,nil,action.group)end
end
function M.leave(v,action)
    if v.editor and v.editor.saving then return end
    if v.editor and v.editor.dirty then v.confirm={kind='unsaved_card',after=action};return end
    M.after(v,action)
end
function M.open(v,key,group)
    local row=key and v.knowledge.byKey[key]
    if key and not row then return end
    if row and(row.edit.status=='conflict'or row.edit.status=='collision')then M.review(v,key);return end
    group=group or row.group
    local item=row and model.copy(row.item)or edits.newItem(group)
    if not item then return end
    clearBuffers(v,'edit-');v.review=nil;v.sourceOnly=false
    v.editor={key=key,group=group,draft=item,original=model.copy(item),expected=key and v.knowledge:editSnapshot(key,group)or nil}
    v.showCard=true;v.maintenance=false
end
function M.review(v,key)
    local row=v.knowledge.byKey[key]
    if not row or row.edit.status~='conflict'then return end
    v.editor=nil;v.review={key=key,choices={},expected=v.knowledge:editSnapshot(key,row.group),sourceAck=false};v.showCard=true
end
function M.save(v,after)
    local e=v.editor;if not e or e.saving then return end
    e.saving=true;e.error=nil;e.afterSave=after
    v.knowledge.editAction={kind='save',key=e.key,group=e.group,item=model.copy(e.draft),expected=e.expected}
end
function M.result(v)
    local r=v.knowledge.editResult
    if not r then return end
    v.knowledge.editResult=nil
    if r.request.kind=='save'then
        local e=v.editor
        if e then
            e.saving=false
            if not r.ok then e.error=r.error;v:warning('save-result',r.error,true);return end
            local after=e.afterSave;M.after(v);v.selected=r.key;v.showCard=true
            if after then M.after(v,after)end
        end
    elseif r.request.kind=='resolve'then
        if not r.ok then if v.review then v.review.error=r.error;v.review.saving=false end;v:warning('review-result',r.error,true);return end
        v.review=nil
    elseif r.request.kind=='reset'and r.ok then
        if v.editor and v.editor.key==r.key then M.after(v)end
        if v.selected==r.key and not v.knowledge.byKey[r.key]then v.selected=nil;v.showCard=false end
    end
    local messages={save='Карточка сохранена.',reset='Личная версия удалена. Исходная база сохранена.',resolve='Сравнение завершено.',
        export='Мои карточки экспортированы. Путь указан ниже в «Данных».',preview_import='Файл личных карточек прочитан.',import='Личные карточки импортированы.'}
    v.editNotice={text=r.ok and messages[r.request.kind]or(r.error or'Действие не выполнено.'),started=v.knowledge.now(),error=not r.ok}
    if not r.ok then v:warning('action-result',v.editNotice.text,true)end
end
local function textField(v,ui,e,field,size,multi,hint)
    local current=e.draft[field]
    if current==nil then current=''end
    local value,changed=v:field(ui,edits.labels[field]or field,'edit-'..field,current,size or 12001,multi)
    if changed then e.draft[field]=value end
    if hint then v:muted(ui,hint)end
end
local function listField(v,ui,e,field)
    local value,changed=v:field(ui,edits.labels[field]or field,'edit-'..field,table.concat(e.draft[field]or{},'\n'),12001,70)
    if changed then e.draft[field]=split(value)end
    v:muted(ui,'Каждое слово или фраза — с новой строки.')
end
local function numberField(v,ui,key,label,value)
    local text,changed=v:field(ui,label,key,value==nil and''or tostring(value),80)
    if changed then if text==''then return nil,true end;return tonumber(text)or text,true end
    return value,false
end
local function sanctions(v,ui,e)
    local list=e.draft.sanctions or{}
    if v:button(ui,(e.showSanctions and'Свернуть санкции'or'Изменить санкции')..'##kb-edit-sanctions')then e.showSanctions=not e.showSanctions end
    if not e.showSanctions then v:muted(ui,'Санкций в карточке: '..#list);return end
    v:muted(ui,'Это личные значения из выбранной нормы. ПМ и IC сроки не переводятся автоматически в игровые деньги или звёзды.','warning')
    local remove
    for n,s in ipairs(list)do
        v.im.Separator();v:heading(ui,'Санкция '..n)
        local key='edit-sanction-'..n
        local value,changed=v:choice(ui,'Вид##'..key,s.kind,{{'fine','Штраф'},{'imprisonment','Лишение свободы'}})
        if changed then s.kind=value end
        value,changed=v:choice(ui,'Единица##'..key,s.unit or'none',{{'none','Не указана'},{'PM','ПМ'},{'IC_years','IC лет'},{'days','Дни'},{'hours','Часы'}})
        if changed then if value=='none'then s.unit=nil else s.unit=value end end
        value,changed=numberField(v,ui,key..'-min','Минимум (можно оставить пустым)',s.min);if changed then s.min=value end
        value,changed=numberField(v,ui,key..'-max','Максимум (можно оставить пустым)',s.max);if changed then s.max=value end
        value,changed=v:field(ui,'Условие этой санкции',key..'-condition',s.condition or'',2001,60);if changed then s.condition=value end
        value,changed=v:field(ui,'Альтернатива по статье (если есть)',key..'-alternative',s.alternative or'',2001,60);if changed then s.alternative=value end
        value,changed=checkBox(v,'Возможен пожизненный срок##'..key,s.life_alternative);if changed then s.life_alternative=value end
        if v:button(ui,'Убрать санкцию '..n..'##kb-edit-remove')then remove=n end
    end
    if remove then table.remove(list,remove);clearBuffers(v,'edit-sanction-')end
    if #list<30 and v:button(ui,'Добавить санкцию##kb-edit-add-sanction')then list[#list+1]={kind='fine',unit='PM'}end
    e.draft.sanctions=list
end
local stepTypes={{'speech','Реплика'},{'me','Действие /me'},{'do','Описание /do'},{'manual_field','Параметр перед запуском'},
    {'manual_continue','Продолжить вручную'},{'command','Команда'}}
local function steps(v,ui,e)
    local list=e.draft.steps or{}
    if v:button(ui,(e.showSteps and'Свернуть шаги'or'Изменить реплики и шаги')..'##kb-edit-steps')then e.showSteps=not e.showSteps end
    if not e.showSteps then v:muted(ui,'Шагов: '..#list);return end
    local change
    for n,s in ipairs(list)do
        v.im.Separator();v:heading(ui,'Шаг '..n)
        local key='edit-step-'..n
        local value,changed=v:choice(ui,'Тип шага##'..key,s.type,stepTypes)
        if changed then
            local old=(s.type=='manual_field'or s.type=='manual_continue')and'label'or'text'
            local new=(value=='manual_field'or value=='manual_continue')and'label'or'text'
            if old~=new then s[new]=s[old]or'';s[old]=nil;v.buffers[key..'-text']=nil end
            s.type=value;if value~='manual_field'then s.key=nil end
        end
        if s.type=='manual_field'then
            value,changed=v:field(ui,'Имя параметра',key..'-key',s.key or'',101);if changed then s.key=value end
        end
        local field=(s.type=='manual_field'or s.type=='manual_continue')and'label'or'text'
        value,changed=v:field(ui,'Текст шага',key..'-text',s[field]or'',2001,90);if changed then s[field]=value end
        local width=math.max(1,(v.im.GetContentRegionAvail().x-16)/3)
        for i,a in ipairs({{-1,'Выше'},{1,'Ниже'},{0,'Удалить'}})do
            if i>1 then v.im.SameLine(0,8)end
            if v:button(ui,a[2]..'##kb-step-'..n,width,30)then change={index=n,offset=a[1]}end
        end
    end
    if change then
        local n=change.index;local to=n+change.offset
        if change.offset==0 then table.remove(list,n)
        elseif to>=1 and to<=#list then list[n],list[to]=list[to],list[n]end
        clearBuffers(v,'edit-step-')
    end
    if #list<100 and v:button(ui,'Добавить шаг##kb-edit-add-step')then list[#list+1]={type='speech',text=''}end
    e.draft.steps=list
end
local function departmentNotes(v,ui,e)
    if v:button(ui,(e.showDepartments and'Свернуть пояснения для ведомств'or'Пояснения для EPD, FBI и Alcatraz')..'##kb-edit-departments')then e.showDepartments=not e.showDepartments end
    if not e.showDepartments then return end
    v:muted(ui,'Общее правило остаётся в поле «Текст». Здесь укажите только различия: фильтр ведомства покажет нужное пояснение. Пустое поле убирает личное пояснение для этого ведомства.')
    local notes=e.draft.department_notes or{}
    for _,department in ipairs({'EPD','FBI','Alcatraz'})do
        local index
        for n,note in ipairs(notes)do if note.department==department then index=n;break end end
        local value,changed=v:field(ui,'Для '..department,'edit-department-'..department,index and notes[index].text or'',8001,100)
        if changed then
            if value==''then if index then table.remove(notes,index)end
            elseif index then notes[index].text=value
            else notes[#notes+1]={department=department,text=value,sources={}}end
            e.draft.department_notes=notes
        end
    end
end
function M.draw(v,ui)
    local e=v.editor;if not e then return false end
    v:heading(ui,e.key and'Моя версия карточки'or'Новая карточка')
    v:muted(ui,'Правки хранятся отдельно. Они не меняют опубликованные данные сервера.','warning')
    if not e.key then
        local groups={};for _,g in ipairs(data.groups)do if g[1]~='sources'and g[1]~='patrol'then groups[#groups+1]=g end end
        local group,changed=v:choice(ui,'Раздел карточки',e.group,groups)
        if changed then M.leave(v,{kind='new',group=group});return true end
    end
    if e.saving then v:muted(ui,'Сохраняем карточку…');return true end
    textField(v,ui,e,'title',901)
    textField(v,ui,e,'reference',901)
    listField(v,ui,e,'aliases')
    textField(v,ui,e,'local_text',12001,100)
    textField(v,ui,e,'local_source_url',601,nil,'Необязательная личная ссылка. Официальные ссылки исходника остаются отдельными.')
    for _,field in ipairs(edits.fields(e.group))do
        if field=='sanctions'then sanctions(v,ui,e)
        elseif field=='department_notes'then departmentNotes(v,ui,e)
        elseif field=='steps'then steps(v,ui,e)
        elseif field=='rp_required'then local value,changed=checkBox(v,'Отыгровка перед командой##kb-edit-rp',e.draft.rp_required);if changed then e.draft.rp_required=value end
        elseif field=='requirement'then
            local value,changed=v:choice(ui,'Обязательность',e.draft.requirement or'informational',{{'mandatory','Обязательно'},{'conditional','При указанных условиях'},{'optional','По желанию'},{'informational','Справка'}})
            if changed then e.draft.requirement=value end
        elseif field=='departments'or field=='commands'then listField(v,ui,e,field)
        elseif field~='title'and field~='reference'and field~='aliases'and field~='local_text'and field~='local_source_url'then
            local multiline;if field~='command'then multiline=100 end
            textField(v,ui,e,field,field=='command'and 101 or 12001,multiline)
        end
    end
    e.dirty=not edits.equal(e.draft,e.original)
    if e.error then if not v:warning('editor-error',e.error)then v:muted(ui,e.error,'warning')end else v:warning('editor-error',nil)end
    v.im.Separator()
    if v:button(ui,'Сохранить карточку##kb-edit-save')then M.save(v)end
    if v:button(ui,'Отмена##kb-edit-cancel')then M.leave(v)end
    return true
end
local function display(value,field)
    if value==nil or value==''then return '(не указано)'end
    if type(value)=='boolean'then return value and'Да'or'Нет'end
    if type(value)~='table'then return tostring(value)end
    local out={}
    for _,row in ipairs(value)do
        if type(row)=='table'then
            out[#out+1]=field=='sanctions'and data.sanction(row)or field=='department_notes'and(row.department..': '..row.text)or tostring(row.text or row.label or row.type or'')
        else out[#out+1]=tostring(row)end
    end
    return #out>0 and table.concat(out,'\n')or'(пусто)'
end
function M.drawReview(v,ui)
    local r=v.review;if not r then return false end
    local k=v.knowledge;local row=k.byKey[r.key]
    if not row or row.edit.status~='conflict'then v.review=nil;return false end
    local change=row.edit;local entry=change.entry
    v:heading(ui,'Сравнение с обновлённой базой')
    v:muted(ui,'Личная версия сохранена. Выберите, какие изменения оставить.')
    if change.sourceChanged then
        v:muted(ui,'Изменился связанный источник. Откройте тему и проверьте смысл, даже если нужное поле выглядит прежним.','warning')
        for _,s in ipairs(k:sourceLines(row))do ui.text(s.title);v:field(ui,'Ссылка','review-source-'..s.title,s.url,701,nil,true)end
        r.sourceAck=checkBox(v,'Я сверил обновлённый источник##kb-review-ack',r.sourceAck)
    end
    for _,field in ipairs(change.fields)do
        v.im.Separator();v:heading(ui,edits.labels[field]or field)
        v:muted(ui,'Раньше в базе');ui.text(display(entry.base_item[field],field))
        v:muted(ui,'Теперь в базе');ui.text(display(row.item[field],field))
        v:muted(ui,'Моя версия');ui.text(display(entry.patch[field],field))
        local value,changed=v:choice(ui,'Оставить##'..field,r.choices[field]or'choose',{{'choose','Выберите вариант'},{'mine','Мою версию'},{'source','Новую версию базы'}})
        if changed then r.choices[field]=value end
    end
    if r.error then
        if not v:warning('review-error',r.error)then v:muted(ui,r.error,'warning')end
        if v:button(ui,'Открыть сравнение заново##kb-review-restart')then M.review(v,r.key);return true end
    end
    if not r.saving and v:button(ui,'Применить выбор##kb-review-save')then
        k.editAction={kind='resolve',key=r.key,choices=model.copy(r.choices),ackSource=r.sourceAck,expected=r.expected};r.saving=true;r.error=nil
    end
    if v:button(ui,'Вернуться к карточке##kb-review-cancel')then v.review=nil end
    return true
end
function M.confirmation(c)
    if c.kind~='unsaved_card'and c.kind~='reset_card'and c.kind~='import_edits'then return nil end
    return {title=c.kind=='unsaved_card'and'Сохранить изменения карточки?'or c.kind=='reset_card'and'Удалить мою версию?'or'Импортировать личные карточки?',
        lines={c.kind=='unsaved_card'and'У карточки есть несохранённые изменения.'or c.kind=='reset_card'and
            'Будет удалена только выбранная личная версия. Исходная база сохранится.'or'Текущий набор личных карточек будет заменён. Его резервная копия сохранится. Заметки и игровые значения останутся.'},
        buttons=c.kind=='unsaved_card'and{'Сохранить','Не сохранять'}or{'ДА','НЕТ'},extraFooter=c.kind=='unsaved_card'and 52 or 0}
end
function M.modal(v,ui,c,layout,spec)
    if c.kind~='unsaved_card'and c.kind~='reset_card'and c.kind~='import_edits'then return false end
    local im=v.im
    require('pa26_menu').confirmationBody(im,ui,layout,spec)
    local width=math.max(1,(im.GetContentRegionAvail().x-10)/2)
    im.PushStyleColor(im.Col.Button,im.ImVec4(.13,.47,.32,.9));ui.push(function()im.PopStyleColor(1)end)
    local yes=v:button(ui,c.kind=='unsaved_card'and'Сохранить##kb-dirty'or'ДА##kb-confirm',width);ui.finish();im.SameLine(0,10)
    im.PushStyleColor(im.Col.Button,im.ImVec4(.65,.17,.22,.9));ui.push(function()im.PopStyleColor(1)end)
    local no=v:button(ui,c.kind=='unsaved_card'and'Не сохранять##kb-dirty'or'НЕТ##kb-confirm',width);ui.finish()
    local stay=c.kind=='unsaved_card'and v:button(ui,'Продолжить редактирование##kb-dirty')
    if yes then
        if c.kind=='unsaved_card'then M.save(v,c.after)
        elseif c.kind=='reset_card'then v.knowledge.editAction={kind='reset',key=c.key}
        else v.knowledge.editAction={kind='import'}end
        return true,true
    elseif no then if c.kind=='unsaved_card'then M.after(v,c.after)end;return true,true
    elseif stay then return true,true end
    return true,false
end
function M.maintenance(v,ui)
    local k=v.knowledge
    v.im.Separator();v:heading(ui,'Мои карточки и правки')
    local changed,created=edits.summary(k.edits.state)
    ui.text('Изменено: '..changed..' · Создано: '..created..' · Сохранено отдельно: '..#k.detachedEdits)
    if k.edits.blocked then v:muted(ui,'Файл личных карточек повреждён. Обычное сохранение остановлено; исходные файлы сохранены.','warning')end
    for _,warning in ipairs(k.edits.warnings or{})do v:muted(ui,warning,'warning')end
    if v:button(ui,'Экспортировать мои карточки##kb-edit-export')then k.editAction={kind='export'}end
    v:field(ui,'Файл экспорта: выделите и Ctrl+C','edit-export-path',k.edits.path:gsub('_edits%.json$','_edits_export.json'),701,nil,true)
    v:field(ui,'Сюда положить файл для импорта','edit-import-path',k.edits.path:gsub('_edits%.json$','_edits_import.json'),701,nil,true)
    if v:button(ui,'Проверить файл личных карточек##kb-edit-import')then k.editAction={kind='preview_import'}end
    if k.editCandidate then
        local a,b=edits.summary(k.editCandidate);ui.text('В файле: '..a..' правок и '..b..' новых карточек.')
        if v:button(ui,'Импортировать мои карточки##kb-edit-apply')then v.confirm={kind='import_edits'}end
    end
    local detached={};for _,d in ipairs(k.detachedEdits)do detached[d.key]=d end
    local keys={};for key in pairs(k.edits.state.entries)do
        local row=k.byKey[key]
        if not row or row.edit.status=='conflict'or row.edit.status=='collision'then keys[#keys+1]=key end
    end;table.sort(keys)
    local pages=math.max(1,math.ceil(#keys/20));v.editManagePage=math.max(1,math.min(v.editManagePage or 1,pages))
    if pages>1 then
        ui.text('Требуют внимания: '..#keys..' · '..v.editManagePage..'/'..pages)
        local w=math.max(1,(v.im.GetContentRegionAvail().x-10)/2)
        if v:button(ui,'← Назад##kb-edits-page',w)then v.editManagePage=math.max(1,v.editManagePage-1)end;v.im.SameLine(0,10)
        if v:button(ui,'Далее →##kb-edits-page',w)then v.editManagePage=math.min(pages,v.editManagePage+1)end
    end
    for n=(v.editManagePage-1)*20+1,math.min(#keys,v.editManagePage*20)do
        local key=keys[n]
        local e=k.edits.state.entries[key];local row=k.byKey[key]
        if row and row.edit.status=='conflict'then
            if v:button(ui,'Сравнить: '..row.title:gsub('##','# #')..'##kb-review-'..key)then v.maintenance=false;M.review(v,key)end
        elseif not row or row.edit.status=='collision'then
            local item=e.item or e.base_item
            v:muted(ui,'Сохранена отдельно: '..tostring(item.title or item.reference or e.id)..'. Исходник недоступен либо совпал идентификатор.','warning')
            if detached[key]and detached[key].error then v:muted(ui,detached[key].error,'warning')end
            if v:button(ui,'Удалить личную запись##kb-detached-'..key)then v.confirm={kind='reset_card',key=key}end
        end
    end
end
return M

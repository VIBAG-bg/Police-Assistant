-- Native mimgui catalogue. All file work is queued to the owning main loop.
local dataModule=require 'pa26_knowledge'
local menu=require 'pa26_menu'
local core=require 'pa26_core'
local editorUi=require 'pa26_knowledge_editor_ui'
local model=require 'pa26_bindings'
local importantUi=require 'pa26_knowledge_important_ui'
local M={};local View={};View.__index=View
local function safe(s) return tostring(s or ''):gsub('##','# #') end
function M.layout(w,h,ratio)
    if not core.finite(w) or not core.finite(h) then return nil end
    if w<720 then return {wide=false,width=math.max(1,w),height=math.max(1,h)} end
    local left=math.max(260,math.min(w-382,w*(ratio or .38)))
    return {wide=true,width=w,height=math.max(1,h),left=left,right=w-left-12,gap=12}
end
function M.new(im,ffi,knowledge)
    return setmetatable({im=im,ffi=ffi,knowledge=knowledge,buffers={},query='',group='all',
        department='all',status='all',page=1,ratio=.38,showCard=false},View)
end
function View:hasModal() return self.confirm~=nil end
function View:warning(key,message,manual)
    if type(self.warningSink)=='function'then self.warningSink(message,key,manual);return true end
    return false
end
function View:cancelModal() self.confirm=nil;self.modalToken=nil end
function View:resetSection()
    if self.importantView then self.importantView.card=nil;self.importantView.tab=nil;self.importantView.page=1;self.importantView.cache=nil end
    self.group='all';self.status='all';self.page=1
end
-- Main-loop clock; changing a filter never edits a card or replaces its draft.
function View:tick(session,now,visible)
    if not core.finite(now)then return end
    if not self.sessionReady or self.session~=session then
        self.sessionReady=true;self.session=session;self:resetSection();self.awayAt=not visible and now or nil;return
    end
    local view=self.knowledge.personal.view
    local age=self.awayAt and core.elapsed(now,self.awayAt)
    if view and view.reset_enabled and age and age>=view.reset_minutes*60000 and not self.editor and not self.review and not self.confirm then
        self:resetSection();self.awayAt=now
    end
    if visible then self.awayAt=nil
    elseif not self.awayAt or not age then self.awayAt=now end
end
function View:forgetIdentity()
    if self.form then
        self.form.ic_name='';self.form.face_known=false
        if self.selected then self.buffers[self.selected..'-ic-name']=nil end
        self.formError='Выбор человека изменился. Проверьте IC сведения заново.'
    end
end
function View:field(ui,label,key,value,size,multi,readOnly)
    local im=self.im;local b=self.buffers[key]
    if not b then b=im.new.char[size](value or '');self.buffers[key]=b end
    if label~=''and not menu.searchHeading(im,ui,label,self.headingFont)then ui.text(label)end
    im.PushItemWidth(-1);ui.push(function()im.PopItemWidth()end)
    local flags=readOnly and im.InputTextFlags.ReadOnly or 0
    local changed
    if multi then changed=im.InputTextMultiline('##kb-'..key,b,size,im.ImVec2(-1,multi),flags)
    else changed=im.InputText('##kb-'..key,b,size,flags) end
    ui.finish();return self.ffi.string(b),changed
end
function View:button(ui,title,width,height)
    local clicked=menu.fittedButton(self.im,ui,title,self.im.ImVec2(width or math.max(1,self.im.GetContentRegionAvail().x),height or 38),self.buttonFont)
    return clicked
end
function View:muted(ui,text,tone)
    local im=self.im
    local tint=tone=='warning' and im.ImVec4(1,.74,.36,1) or tone=='good' and im.ImVec4(.43,.87,.75,1) or im.ImVec4(.68,.79,.89,1)
    im.PushStyleColor(im.Col.Text,tint);ui.push(function()im.PopStyleColor(1)end);ui.text(text);ui.finish()
end
function View:heading(ui,text)
    local im=self.im
    if self.headingFont then im.PushFont(self.headingFont);ui.push(function()im.PopFont()end)end
    ui.text(text);if self.headingFont then ui.finish()end
end
function View:choice(ui,label,value,choices)
    local im=self.im;local title=label:match('^(.-)##')or label
    if label=='Раздел'or label=='Ведомство'or label=='Статус'then self:heading(ui,title)else ui.text(title)end
    if label=='Ведомство'then
        return menu.choiceControl(im,ui,'##kb-choice-'..label,'',value,choices,self,{buttons=true,font=self.buttonFont,fold=model.casefold})
    end
    local name='Выберите вариант';for _,v in ipairs(choices)do if v[1]==value then name=v[2];break end end
    local out=value
    im.PushItemWidth(-1);ui.push(function()im.PopItemWidth()end)
    if im.BeginCombo('##kb-choice-'..label,safe(name))then
        ui.push(function()im.EndCombo()end)
        for _,v in ipairs(choices)do
            if im.Selectable(safe(v[2])..'##kb-choice-'..label..v[1],v[1]==value)then out=v[1]end
        end
        ui.finish()
    end
    ui.finish();return out,out~=value
end
local function child(self,ui,id,w,h,fn,flags,padding)
    local im=self.im
    padding=padding==nil and 12 or padding
    im.PushStyleVarVec2(im.StyleVar.WindowPadding,im.ImVec2(padding,padding));ui.push(function()im.PopStyleVar(1)end)
    local visible=im.BeginChild(id,im.ImVec2(w,h),true,im.WindowFlags.AlwaysUseWindowPadding+(flags or 0))
    ui.push(function()im.EndChild()end);if visible then fn()end;ui.finish();ui.finish()
end
function View:select(key)
    if self.editor or self.review then editorUi.leave(self,{kind='select',key=key});return end
    if self.knowledge.personal.view.top_tab~='registry'then self.knowledge.personal.view.top_tab='registry';self.knowledge:changed()end
    if key~=self.selected then self.buffers={};self.form=nil;self.formError=nil;self.mappingError=nil end
    self.selected=key;self.showCard=true;self.sourceOnly=false;self.knowledge:opened(key)
end
function View:switchMode(mode)
    if self.editor or self.review then editorUi.leave(self,{kind='mode',mode=mode});return end
    if mode=='data' then self.maintenance=true;return end
    self.maintenance=false
    local favorite,recent=mode=='favorites',mode=='recent'
    if favorite~=self.favorite or recent~=self.recent then self.page=1 end
    self.favorite,self.recent=favorite,recent
end
function View:drawHome(ui)
    local k=self.knowledge;local im=self.im
    local current=(k.personal.view.catalog_mode or'current')=='current'
    local width=math.max(1,(im.GetContentRegionAvail().x-8)/2)
    if self:button(ui,(current and'Актуальное'or'Все записи')..'##kb-current-mode',width,30)then
        k.personal.view.catalog_mode=current and'all'or'current';k:changed();self.page=1
    end
    im.SameLine(0,8)
    local choices={{'all','Все темы'}};for _,row in ipairs(require('pa26_operational').topics)do choices[#choices+1]=row end
    local topic=self.topic or'all';local label='Все темы';for _,r in ipairs(choices)do if r[1]==topic then label=r[2]end end
    im.PushItemWidth(-1);ui.push(function()im.PopItemWidth()end)
    if im.BeginCombo('##kb-topic',label)then
        ui.push(function()im.EndCombo()end)
        for _,r in ipairs(choices)do if im.Selectable(r[2]..'##kb-topic-'..r[1],r[1]==topic)then self.topic=r[1];self.page=1;self.selected=nil;self.showCard=false end end
        ui.finish()
    end
    ui.finish()
end
function View:drawList(ui,rows)
    local im=self.im
    local pages=math.max(1,math.ceil(#rows/20));self.page=math.max(1,math.min(self.page,pages))
    ui.text('Найдено: '..#rows..' · '..self.page..'/'..pages)
    local w=math.max(1,(im.GetContentRegionAvail().x-10)/2)
    if self:button(ui,'← Назад##kb-page',w,32)then self.page=math.max(1,self.page-1)end
    im.SameLine(0,10)
    if self:button(ui,'Далее →##kb-page',w,32)then self.page=math.min(pages,self.page+1)end
    im.Separator()
    local signature=table.concat({tostring(self.page),self.group,self.department,self.status,self.query,tostring(self.favorite),tostring(self.recent),tostring(self.knowledge.revision)},'\0')
    child(self,ui,'##kb-list-items',0,math.max(1,im.GetContentRegionAvail().y),function()
    if self.listSignature~=signature then im.SetScrollY(0);self.listSignature=signature end
    if #rows==0 then self:muted(ui,'Ничего не найдено. Измените поиск или фильтры.');return end
    local first=(self.page-1)*20+1
    for n=first,math.min(#rows,first+19)do
        local r=rows[n];local selected=self.selected==r.key
        if selected then im.PushStyleColor(im.Col.Button,im.ImVec4(.09,.43,.62,.92));ui.push(function()im.PopStyleColor(1)end)end
        local ref=r.item.reference
        if not ref or not ref:find('%S')then ref=r.item.command or(r.group=='radio'and r.edit.status~='custom'and r.item.id or'')end
        local title=r.title==ref and ref or (ref~='' and ref..' · '..r.title or r.title)
        local label=safe(title)..'\n'..dataModule.status(r)..(self.knowledge:isFavorite(r.key)and' · Избранное'or'')..'##kb-row-'..r.key
        if self:button(ui,label,nil,64)then self:select(r.key)end
        if selected then ui.finish()end
    end
    end,0,4)
end
function View:drawPersonal(ui,row)
    local im=self.im;local k=self.knowledge
    im.Separator();self:heading(ui,'Моя заметка')
    local note,changed=self:field(ui,'',row.key..'-note',k.personal.notes[row.key]or'',4001,90)
    if changed then k:note(row.key,note)end
    self:muted(ui,'Личные правки сохраняются автоматически и остаются при обновлении базы.')
    if row.group=='offenses' or row.group=='articles'then
        self:heading(ui,'Мои игровые значения')
        self:muted(ui,'Введены вручную. Они не становятся подтверждённой нормой сервера.','warning')
        local values=k.personal.mappings[row.key]or{stars='',fine='',minutes=''}
        local copy={stars=values.stars,fine=values.fine,minutes=values.minutes};local any=false
        for _,entry in ipairs({{'stars','Звёзды'},{'fine','Сумма штрафа'},{'minutes','Минуты'}})do
            local value,changed=self:field(ui,entry[2],row.key..'-'..entry[1],values[entry[1]],17)
            copy[entry[1]]=value;any=any or changed
        end
        if any then local _,err=k:mapping(row.key,copy);self.mappingError=err end
        if self.mappingError then if not self:warning('mapping-error',self.mappingError)then self:muted(ui,self.mappingError,'warning')end else self:warning('mapping-error',nil)end
    end
end
function View:drawForm(ui,row,callbacks)
    local im=self.im;local f=self.form
    if not f then return end
    if f.kind=='wanted'then
        ui.text('Розыск готовится в отдельном помощнике: сведения о личности, игровой пункт, отыгровка и итоговое ДА/НЕТ. Статья УК/АК и звёзды не дописываются в шорткат /su.')
        if callbacks.openWanted and self:button(ui,'Перейти в помощник розыска##kb-open-wanted')then self.form=nil;callbacks.openWanted()end
        if self:button(ui,'Отмена##kb-form')then self.form=nil;self.formError=nil end
        return
    end
    im.Separator();self:heading(ui,f.kind=='wanted'and'Подготовка розыска' or 'Подготовка штрафа')
    self:muted(ui,'Создаётся редактируемый бинд. Команда отсюда не отправляется.','warning')
    f.identity=self:choice(ui,'Источник личности',f.identity,f.kind=='wanted'and{
        {'passport','Я видел паспорт'},{'appearance','Я установил приметы / лицо'},{'ooc','OOC-розыск (отдельный режим)'}}or{
        {'passport','Я видел паспорт'},{'appearance','Я установил приметы / лицо'}})
    local mask=im.new.bool(f.masked);if im.Checkbox('Сейчас есть маска##kb-mask',mask)then f.masked=mask[0]end
    if f.identity=='passport'then f.ic_name=self:field(ui,'IC имя из паспорта',row.key..'-ic-name',f.ic_name,121)
    elseif f.identity=='appearance'then
        local face=im.new.bool(f.face_known);if im.Checkbox('Лицо было установлено до маски##kb-face',face)then f.face_known=face[0]end
        if f.masked and not f.face_known then self:muted(ui,'Личность по лицу не установлена. IC выдача здесь не подготовится.','warning')end
    else
        self:muted(ui,'OOC-сведения не доказывают IC личность. Применяйте этот режим только в допустимой ситуации.','warning')
        local ack=im.new.bool(f.ooc_ack);if im.Checkbox('Осознанно выбираю OOC-розыск##kb-ooc',ack)then f.ooc_ack=ack[0]end
    end
    f.part=self:field(ui,'Часть / пункт (если нужно)',row.key..'-part',f.part,33)
    f.reason=self:field(ui,'Краткое основание (дополнение к статье)',row.key..'-reason',f.reason,181)
    local name=f.kind=='wanted'and'stars'or'fine'
    f[name]=self:field(ui,f.kind=='wanted'and'Звёзды — вручную'or'Сумма — вручную',row.key..'-amount',f[name],17)
    self:muted(ui,'Ваша команда: {select_id} — цель; {param1} — звёзды / сумма; {param2} — выбранная статья и основание. Порядок параметров укажите после проверки в игре.')
    f.command=self:field(ui,'Шаблон проверенной вами команды',row.key..'-command',f.command,401,80)
    local reason=(row.item.reference or row.title)..(f.part~=''and(' ч. '..f.part)or'')..(f.reason~=''and(' · '..f.reason)or'')
    ui.text('Основание: '..reason)
    if self:button(ui,'Создать черновик в биндере##kb-compose')then
        local binding,err=self.knowledge:compose(row,f,callbacks.nextBindingId(),callbacks.codec)
        if binding then local ok;ok,err=callbacks.createBinding(binding,f);if ok then self.form=nil end end
        self.formError=err
        if err then self:warning('compose-result',err,true)end
    end
    if self:button(ui,'Отмена##kb-form')then self.form=nil;self.formError=nil end
    if self.formError then if not self:warning('form-error',self.formError)then self:muted(ui,self.formError,'warning')end else self:warning('form-error',nil)end
end
function View:drawCard(ui,callbacks)
    if editorUi.drawReview(self,ui)or editorUi.draw(self,ui)then return end
    local im=self.im;local k=self.knowledge;local row=k.byKey[self.selected]
    if not row then self:heading(ui,'Выберите запись слева');self:muted(ui,'Справка работает без выбранного человека и без доступа к форуму.');return end
    local original=k.baseByKey[row.key]
    if self.sourceOnly and original then
        local sourceRow=model.copy(row);sourceRow.item=original;sourceRow.title=original.title or original.reference or original.command or original.id
        sourceRow.edit={status='source'};row=sourceRow
    end
    local heading=row.item.reference
    if not heading or not heading:find('%S')then heading=row.item.command end
    if not heading or not heading:find('%S')then heading=row.title end
    self:heading(ui,heading)
    if heading~=row.title then ui.text(row.title)end
    self:muted(ui,dataModule.status(row),dataModule.tone(row))
    if self:button(ui,(k:isFavorite(row.key)and'Убрать из избранного'or'В избранное')..'##kb-favorite')then k:favorite(row.key)end
    local actual=k.byKey[self.selected]
    if actual.edit.status=='conflict'then
        if self:button(ui,'Сравнить с обновлённой базой##kb-review')then editorUi.review(self,actual.key);return end
    elseif actual.edit.status~='collision'then
        if self:button(ui,'Редактировать карточку##kb-edit')then editorUi.open(self,actual.key);return end
    end
    if original and actual.edit.status=='override'then
        if self:button(ui,(self.sourceOnly and'Вернуться к моей версии'or'Посмотреть исходник')..'##kb-source')then self.sourceOnly=not self.sourceOnly;self.form=nil;self.formError=nil end
    end
    if actual.edit.entry then
        if self:button(ui,(actual.edit.status=='custom'and'Удалить мою карточку'or'Убрать мою правку')..'##kb-edit-reset')then self.confirm={kind='reset_card',key=actual.key}end
    end
    if row.item.operation_id then
        local card=row.item;ui.text(card.brief)
        local choices={};for line in(card.order..'\n'):gmatch('(.-)\n')do if line~=''then choices[#choices+1]={tostring(#choices+1),line}end end
        self.operationSteps=self.operationSteps or{}
        self.operationSteps[row.key]=self:choice(ui,'Текущий шаг · отметка для себя',self.operationSteps[row.key]or'1',choices)
        if callbacks.openOperational and self:button(ui,'Открыть действия, основания и предпросмотр##kb-operation')then callbacks.openOperational(card.topic)end
        if im.CollapsingHeader('Порядок и исключения##kb-operation-details')then ui.text(card.order);self:muted(ui,'Исключения и ограничения','warning');ui.text(card.exceptions)end
    else
        for _,line in ipairs(k:detail(row,self.department))do
            im.Dummy(im.ImVec2(0,4));self:muted(ui,line.label);ui.text(line.text)
        end
    end
    if callbacks.openWanted and not self.sourceOnly then
        local gameId=row.item.id:match('^game_wanted_(%d%d_%d%d)$')
        if gameId then gameId=gameId:gsub('_','.')
            if self:button(ui,'Открыть помощник с этим пунктом##kb-wanted-reason')then callbacks.openWanted(gameId)end
        end
        for _,id in ipairs(row.item.game_reasons or require('pa26_wanted_catalog').related(row.item.id))do
            if self:button(ui,'Розыск · пункт '..id..'##kb-wanted-'..id)then callbacks.openWanted(id)end
        end
    end
    if row.group=='articles'and k.byKey['offenses:'..row.item.id]then
        if self:button(ui,'Открыть разобранную карточку##kb-offense')then self:select('offenses:'..row.item.id);return end
    end
    if not self.sourceOnly and not k:isArchived(row)and(row.group=='offenses' or row.group=='articles')and actual.edit.status~='conflict'and actual.edit.status~='collision'then
        if row.group=='articles'then self:muted(ui,'Это только указатель. Перед процедурой самостоятельно проверьте состав и санкцию в источнике.','warning')end
        local w=math.max(1,(im.GetContentRegionAvail().x-10)/2)
        for n,entry in ipairs({{'wanted','Розыск'},{'fine','Штраф'}})do
            if n>1 then im.SameLine(0,10)end
            if self:button(ui,entry[2]..'##kb-action',w)then
                if callbacks.openCaseGround then callbacks.openCaseGround(entry[1],row.item.reference or row.title)
                elseif entry[1]=='wanted'and callbacks.openWanted then callbacks.openWanted()
                else
                local values=k.personal.mappings[row.key]or{}
                self.form={kind=entry[1],identity='passport',ic_name='',part='',reason='',stars=values.stars or '',fine=values.fine or '',command='',masked=false,face_known=false,ooc_ack=false}
                for key in pairs(self.buffers)do if key:match('%-ic%-name$')or key:match('%-part$')or key:match('%-reason$')or key:match('%-amount$')or key:match('%-command$')then self.buffers[key]=nil end end
                self.formError=nil
                end
            end
        end
    end
    if not self.sourceOnly then self:drawForm(ui,row,callbacks)end
    local links=k:sourceLines(row,self.department)
    if #links>0 then im.Separator();self:heading(ui,'Источники')end
    for n,s in ipairs(links)do
        ui.text(s.title);self:muted(ui,s.locator..' · Проверено '..s.date)
        self:field(ui,'Ссылка: выделите и Ctrl+C',row.key..'-source-'..n,s.url,701,nil,true)
    end
    self:drawPersonal(ui,row)
end
function View:drawMaintenance(ui)
    local im=self.im;local k=self.knowledge
    if self:button(ui,'Создать личную карточку##kb-new-compact')then editorUi.leave(self,{kind='new',group='rules'});self.maintenance=false end
    self:heading(ui,'Просмотр базы')
    local view=k.personal.view or{reset_enabled=true,reset_minutes=10}
    local enabled=im.new.bool(view.reset_enabled)
    local changed=im.Checkbox('Сбрасывать раздел после выхода из базы##kb-reset-enabled',enabled)
    local minutes=im.new.int(view.reset_minutes)
    if im.InputInt('Минуты после выхода##kb-reset-minutes',minutes)then changed=true end
    if changed then k:viewSettings(enabled[0],math.max(1,math.min(1440,minutes[0])))end
    self:muted(ui,'По умолчанию через 10 минут после закрытия F9 или перехода из базы выбираются «Все разделы» и «Все статусы». Пока база открыта, таймер не идёт. Возврат до истечения срока сохраняет выбор; следующий выход запускает отсчёт заново. Интервал можно изменить или отключить. Новый вход в игру сбрасывает раздел. Черновик карточки не прерывается.')
    im.Separator()
    local department,changed=self:choice(ui,'Приоритет ведомства',k.personal.department,{{'EPD','EPD'},{'FBI','FBI'},{'Alcatraz','Alcatraz'}})
    if changed then k:department(department)end
    self:muted(ui,'Свежая база поставляется в пакете обновления PA из GitHub. Существующая активная база сохраняется до вашего отдельного подтверждения ниже.')
    if self:button(ui,'Посмотреть базу из обновления PA##kb-bundle')then k.action='preview_bundle'end
    self:muted(ui,'Сначала покажем версию базы, входящей в установленную сборку PA. Применение требует отдельного ДА; личные карточки, заметки и значения сохраняются.')
    self:muted(ui,'Для импорта положите готовый JSON в config/police_assistant_2026_knowledge_import.json.')
    if self:button(ui,'Проверить файл импорта##kb-import')then k.action='preview_import' end
    if k.candidate then
        if k.candidateSource=='bundle'then self:heading(ui,'База из установленной сборки PA')end
        ui.text('Кандидат: '..k.candidate.catalog_version..' · '..#k.candidate.offenses..' карточек · '..#k.candidate.articles..' статей')
        if self:button(ui,'Применить базу##kb-apply')then self.confirm={kind='apply_import',version=k.candidate.catalog_version} end
    end
    if self:button(ui,'Вернуть предыдущую базу##kb-rollback')then self.confirm={kind='rollback'} end
    if self:button(ui,'Повторно прочитать файлы##kb-reload')then k.action='load' end
    if k.operationError then if not self:warning('operation-error',k.operationError)then self:muted(ui,k.operationError,'warning')end else self:warning('operation-error',nil)end
    editorUi.maintenance(self,ui)
end
function View:switchTop(tab)
    if self.knowledge.personal.view.top_tab==tab then return end
    if tab~='important'and tab~='registry'then return end
    if self.editor or self.review then editorUi.leave(self,{kind='top',tab=tab});return end
    if self.knowledge.personal.view.top_tab~=tab then self.knowledge.personal.view.top_tab=tab;self.knowledge:changed()end
end
function View:draw(ui,callbacks)
    if not self.knowledge.loaded or not self.knowledge.data then return self:drawRegistry(ui,callbacks)end
    editorUi.result(self)
    local im=self.im;local selected=self.knowledge.personal.view.top_tab or'important'
    local width=math.max(1,(im.GetContentRegionAvail().x-10)/2)
    for n,row in ipairs({{'important','ВАЖНОЕ'},{'registry','РЕЕСТР'}})do
        if n>1 then im.SameLine(0,10)end
        if selected==row[1]then im.PushStyleColor(im.Col.Button,im.ImVec4(.09,.43,.62,.95));ui.push(function()im.PopStyleColor(1)end)end
        if self:button(ui,row[2]..'##kb-top-'..row[1],width,38)then self:switchTop(row[1])end
        if selected==row[1]then ui.finish()end
    end
    if self.knowledge.personal.view.top_tab=='registry'then return self:drawRegistry(ui,callbacks)end
    if self.knowledge.personalError or self.knowledge.personalWarning then self:warning('personal',self.knowledge.personalError or self.knowledge.personalWarning)end
    importantUi.draw(self,ui,callbacks)
end
function View:drawRegistry(ui,callbacks)
    local im=self.im;local k=self.knowledge
    editorUi.result(self)
    if not k.loaded then ui.text('База подготавливается…');return end
    if not k.data then
        if not self:warning('load',k.error or'База недоступна.')then self:muted(ui,k.error or'База недоступна.','warning')else ui.text('База недоступна. Повторите чтение.')end
        if self:button(ui,'Повторить чтение базы##kb-reload')then k.action='load' end
        return
    end
    self:warning('load',nil)
    if self.revision~=k.revision then
        self.revision=k.revision;self.sourceOnly=false
        if not self.editor then self.buffers={}else self.editor.error='Данные обновлены. При сохранении PA проверит, что исходник вашей карточки не изменился.'end
        self.form=nil;self.formError=nil;self.page=1
        if not k.byKey[self.selected]then self.selected=nil;self.showCard=false end
    end
    self.compactView=im.GetContentRegionAvail().y<420
    if not self.compactView then self:muted(ui,k.personal.department..' в приоритете · '..k.data.catalog_version)end
    if self.editNotice then
        if self.editNotice.error and self:warning('edit-notice',self.editNotice.text)then
        elseif (core.elapsed(k.now(),self.editNotice.started)or 0)<7000 then self:muted(ui,self.editNotice.text,self.editNotice.error and'warning'or'good')
        else self.editNotice=nil end
    end
    local available=im.GetContentRegionAvail().x
    local tools={{'all','Всё'},{'favorites','Избранное'},{'recent','Недавние'},{'data','Данные'}}
    local mode=self.maintenance and 'data' or self.favorite and 'favorites' or self.recent and 'recent' or 'all'
    for n,v in ipairs(tools)do
        if n>1 then im.SameLine(0,8)end
        if mode==v[1]then im.PushStyleColor(im.Col.Button,im.ImVec4(.09,.43,.62,.92));ui.push(function()im.PopStyleColor(1)end)end
        if self:button(ui,v[2]..'##kb-mode',math.max(1,(available-24)/4),32)then
            self:switchMode(v[1])
        end
        if mode==v[1]then ui.finish()end
    end
    if self.maintenance then
        child(self,ui,'##kb-maintenance',0,math.max(1,im.GetContentRegionAvail().y),function()self:drawMaintenance(ui)end)
        return
    end
    self:drawHome(ui)
    if not self.compactView and self:button(ui,'Создать карточку##kb-new')then
        local group=self.group
        if group=='all'or group=='sources'or group=='patrol'then group='rules'end
        editorUi.leave(self,{kind='new',group=group})
    end
    if self.compactView then
        self:heading(ui,'Поиск')
        if self:button(ui,'Фильтры##kb-filters-compact',85,30)then self.showFilters=not self.showFilters end
        im.SameLine(0,8)
    end
    local query,queryChanged=self:field(ui,self.compactView and''or'Поиск: слово, номер статьи или команда','search',self.query,1025)
    self.query=query
    local changed=queryChanged
    local changedFilters=not self.compactView and self:button(ui,(self.showFilters and'Скрыть' or'Показать')..' фильтры и статусы##kb-filters-toggle')
    if changedFilters then self.showFilters=not self.showFilters end
    if self.showFilters then
    local filterColumns=im.GetContentRegionAvail().x>=700 and 3 or 1
    if filterColumns>1 then im.Columns(filterColumns,'##kb-filters',false);ui.push(function()im.Columns(1)end)end
    local groups={{'all','Все разделы'}};for _,g in ipairs(dataModule.groups)do groups[#groups+1]=g end
    local group,gc=self:choice(ui,'Раздел',self.group,groups);self.group=group;changed=changed or gc;im.NextColumn()
    local dep,dc=self:choice(ui,'Ведомство',self.department,{{'all','Все'},{'EPD','EPD'},{'FBI','FBI'},{'Alcatraz','Alcatraz'}})
    self.department=dep;changed=changed or dc;im.NextColumn()
    local choices={{'all','Все статусы'},{'summary','Разобранные'},{'index','Указатели'},{'conflict','Уточнения'},
        {'personal','Мои карточки и правки'},{'personal_conflict','Мои: нужно сравнение'}}
    if self.group=='commands'then choices[#choices+1]={'rp_required','RP нужно'};choices[#choices+1]={'rp_free','RP не нужно'}end
    if gc then self.status='all' end
    local status,sc=self:choice(ui,'Статус',self.status,choices)
    self.status=status;changed=changed or sc;im.NextColumn();if filterColumns>1 then ui.finish()end
    end
    if changed then self.page=1 end
    if k.personalError or k.personalWarning then
        self:muted(ui,k.personalError or k.personalWarning,'warning')
        if self:button(ui,'Повторить сохранение личных данных##kb-retry')then k.personalError=nil;k:flush()end
    end
    local home=self.query==''and self.group=='all'and not self.favorite and not self.recent and(self.topic==nil or self.topic=='all')and k.personal.view.catalog_mode=='current'
    local rows=k:search(self.query,{group=self.group,department=self.department,status=self.status,favorite=self.favorite,recent=self.recent,mode=k.personal.view.catalog_mode,topic=self.topic,home=home})
    if changed and self.selected and not self.editor and not self.review and not self.form then
        local found=false;for _,row in ipairs(rows)do if row.key==self.selected then found=true;break end end
        if not found then self.selected=nil;self.showCard=false;self.sourceOnly=false end
    end
    local panes=M.layout(im.GetContentRegionAvail().x,im.GetContentRegionAvail().y,self.ratio)
    if not panes then return end
    if not panes.wide then
        if self.showCard then
            if self:button(ui,'← К результатам##kb-back')then self.showCard=false end
            child(self,ui,'##kb-card',0,math.max(1,im.GetContentRegionAvail().y),function()self:drawCard(ui,callbacks)end)
        else child(self,ui,'##kb-list',0,panes.height,function()self:drawList(ui,rows)end,im.WindowFlags.NoScrollbar+im.WindowFlags.NoScrollWithMouse)end
        return
    end
    local p=im.GetCursorScreenPos()
    im.SetCursorScreenPos(im.ImVec2(p.x+panes.left,p.y));im.InvisibleButton('##kb-divider',im.ImVec2(panes.gap,panes.height))
    local active,hover=im.IsItemActive(),im.IsItemHovered()
    if active or hover then im.SetMouseCursor(im.MouseCursor.ResizeEW)end
    if active and core.finite(im.GetIO().MouseDelta.x)then
        panes.left=math.max(260,math.min(panes.width-382,panes.left+im.GetIO().MouseDelta.x));panes.right=panes.width-panes.left-12;self.ratio=panes.left/panes.width
    end
    im.SetCursorScreenPos(p)
    child(self,ui,'##kb-list',panes.left,panes.height,function()self:drawList(ui,rows)end,im.WindowFlags.NoScrollbar+im.WindowFlags.NoScrollWithMouse)
    im.SameLine(0,12);child(self,ui,'##kb-card',panes.right,panes.height,function()self:drawCard(ui,callbacks)end)
end
function View:drawModal(ui)
    if self.warningBlocking and self.warningBlocking()then self.modalToken=nil;self.modalVisible=false;return end
    local im=self.im;local c=self.confirm
    if not c and not self.modalVisible then return end
    local id='Обновление базы##pa26-knowledge-confirm'
    if c and self.modalToken~=c then self.modalToken=c;self.modalPagination={};self.modalPosition=nil;self.rightDrag=nil;im.OpenPopup(id)end
    local spec=c and editorUi.confirmation(c) or nil
    spec=spec or {title=c and c.kind=='rollback'and'Вернуть предыдущую базу?'or'Применить новую базу?',
        lines={c and c.version or'Будет восстановлена резервная копия локальных данных.',
            'Личные заметки и значения сохранятся. Открытая форма будет сброшена после смены версии.'},buttons={'ДА','НЕТ'}}
    spec.titleFont=self.headingFont;spec.buttonFont=self.buttonFont;spec.pageState=self.modalPagination
    local layout=menu.confirmationLayout(im,spec)
    local io=im.GetIO();local p=self.modalPosition or{x=(io.DisplaySize.x-layout.width)/2,y=(io.DisplaySize.y-layout.height)/2}
    im.SetNextWindowPos(im.ImVec2(math.max(16,math.min(p.x,io.DisplaySize.x-layout.width-16)),math.max(16,math.min(p.y,io.DisplaySize.y-layout.height-16))),im.Cond.Always)
    im.SetNextWindowSize(im.ImVec2(layout.width,layout.height),im.Cond.Always)
    im.PushStyleVarVec2(im.StyleVar.WindowPadding,im.ImVec2(28,24));ui.push(function()im.PopStyleVar(1)end)
    im.PushStyleVarFloat(im.StyleVar.WindowRounding,14);ui.push(function()im.PopStyleVar(1)end)
    im.PushStyleVarVec2(im.StyleVar.ItemSpacing,im.ImVec2(10,10));ui.push(function()im.PopStyleVar(1)end)
    im.PushStyleColor(im.Col.PopupBg,im.ImVec4(.035,.09,.15,.90));ui.push(function()im.PopStyleColor(1)end)
    im.PushStyleColor(im.Col.ModalWindowDimBg,im.ImVec4(.01,.03,.06,.28));ui.push(function()im.PopStyleColor(1)end)
    local flags=im.WindowFlags.NoTitleBar+im.WindowFlags.NoResize+im.WindowFlags.NoSavedSettings+im.WindowFlags.NoMove+
        im.WindowFlags.NoScrollbar+im.WindowFlags.NoScrollWithMouse
    local shown=im.BeginPopupModal(id,nil,flags)
    if shown then
        self.modalVisible=true;ui.push(function()im.EndPopup()end)
        self.modalPosition=menu.rightDragRect(im,self,'knowledge-confirmation')or self.modalPosition
        if not c then im.CloseCurrentPopup();self.modalVisible=false
        else
            local handled,closed=editorUi.modal(self,ui,c,layout,spec)
            if handled then
                if closed then self:cancelModal();im.CloseCurrentPopup();self.modalVisible=false end
            else
            menu.confirmationBody(im,ui,layout,spec)
            local w=math.max(1,(im.GetContentRegionAvail().x-10)/2)
            im.PushStyleColor(im.Col.Button,im.ImVec4(.13,.47,.32,.9));ui.push(function()im.PopStyleColor(1)end)
            local yes=self:button(ui,'ДА##kb-confirm',w);ui.finish();im.SameLine(0,10)
            im.PushStyleColor(im.Col.Button,im.ImVec4(.65,.17,.22,.9));ui.push(function()im.PopStyleColor(1)end)
            local no=self:button(ui,'НЕТ##kb-confirm',w);ui.finish()
            if yes then self.knowledge.action=c.kind;self:cancelModal();im.CloseCurrentPopup();self.modalVisible=false
            elseif no then self:cancelModal();im.CloseCurrentPopup();self.modalVisible=false end
            end
        end
        ui.finish()
    else self.modalVisible=false end
    for _=1,5 do ui.finish()end
end
return M

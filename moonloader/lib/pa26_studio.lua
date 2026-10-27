-- Original mimgui binder workspace. Game reads and execution are queued to main().
local model=require 'pa26_bindings'
local binder=require 'pa26_binder'
local core=require 'pa26_core'
local menuModule=require 'pa26_menu'
local wheelModel=require 'pa26_wheel'
local preferences=require 'pa26_preferences'
local alertModule=require 'pa26_alerts'
local patrolUi=require 'pa26_patrol_ui'
local vehicleUi=require 'pa26_vehicle_ui'
local eventUi=require 'pa26_patrol_event_ui'
local identityUi=require 'pa26_identity_ui'
local caseUi=require 'pa26_case_ui'
local operationUi=require 'pa26_operation_ui'
local feedbackModule=require 'pa26_feedback'
local M={};M.optionKeys={'quick_key','tips_key','cancel_key','opacity','compact','retain_distance','retain_grace_ms','keep_target_on_interior_change','aim_select_enabled','aim_select_control','aim_select_delay_ms','wheel_mode','wheel_profile','wheel_enabled','interaction_notices','wheel_names','wheel_child_limit','wheel_system_groups','ask_screenshot_path'}; local Studio={}; Studio.__index=Studio
local function label(value) return tostring(value):gsub('##','# #') end
local captureModifiers={[16]=true,[17]=true,[18]=true,[91]=true,[92]=true,
    [160]=true,[161]=true,[162]=true,[163]=true,[164]=true,[165]=true}
-- ImGui receives keyboard input even when mimgui consumes it before MoonLoader.
-- This reader is independent of game APIs. Ignore keys held when recording opens,
-- collect modifiers during the chord, then finish only when the chord is released.
function M.captureInput(state,keys,mods)
    local previous=state.previous; local fresh={}; local changed=false
    for key=8,254 do
        if key~=27 and not captureModifiers[key] then
            local down=keys[key]==true
            if previous and down and not previous[key] then fresh[#fresh+1]=key end
            if previous and down~=(previous[key]==true) then changed=true end
        end
    end
    local oldMods=state.mods or {}
    for _,name in ipairs({'ctrl','alt','shift','super'}) do
        if (mods[name]==true)~=(oldMods[name]==true) then changed=true end
    end
    state.previous={}; for key=8,254 do state.previous[key]=keys[key]==true end
    state.mods={ctrl=mods.ctrl==true,alt=mods.alt==true,shift=mods.shift==true,super=mods.super==true}
    if not previous then
        if mods.ctrl or mods.alt or mods.shift then return {proposal={key=0,ctrl=mods.ctrl,alt=mods.alt,shift=mods.shift}} end
        return
    end
    if not state.active and #fresh>0 then
        state.active={key=fresh[1],ctrl=false,alt=false,shift=false}; state.held={}; state.issue=nil
    end
    local active=state.active
    if active then
        for _,key in ipairs(fresh) do
            state.held[key]=true
            if key~=active.key then state.issue='Используйте одну основную клавишу и Ctrl, Alt или Shift.' end
        end
        for _,name in ipairs({'ctrl','alt','shift'}) do active[name]=active[name] or mods[name]==true end
        if mods.super then state.issue='Клавиша Windows оставлена системе. Используйте Ctrl, Alt или Shift.' end
        if active.ctrl and active.alt and active.shift then state.issue='Максимум 3 клавиши: основная и до двух из Ctrl, Alt, Shift.' end
        local held=mods.ctrl or mods.alt or mods.shift or mods.super
        for key in pairs(state.held) do held=held or keys[key]==true end
        if not held then
            local result={proposal=model.copy(active),finished=true,error=state.issue}
            state.active=nil; state.held=nil; state.issue=nil
            return result
        end
        if changed then return {proposal=model.copy(active),error=state.issue} end
    elseif changed then
        return {proposal={key=0,ctrl=mods.ctrl==true,alt=mods.alt==true,shift=mods.shift==true}}
    end
end
function M.keycapParts(proposal)
    local parts={}
    if not proposal then return parts end
    for _,name in ipairs({'ctrl','alt','shift'}) do if proposal[name] then parts[#parts+1]=({ctrl='Ctrl',alt='Alt',shift='Shift'})[name] end end
    if proposal.key and proposal.key~=0 then parts[#parts+1]=model.keyName(proposal.key) end
    return parts
end
function M.keycapLayout(parts,width,font,size)
    local total,widths=0,{}
    for i,text in ipairs(parts) do
        widths[i]=math.max(54,font:CalcTextSizeA(size,100000,0,text).x+28)
        total=total+widths[i]+(i>1 and 28 or 0)
    end
    local scale=math.min(1,math.max(1,width-40)/math.max(1,total))
    for i,value in ipairs(widths) do widths[i]=value*scale end
    return {widths=widths,total=total*scale,gap=28*scale,height=58*scale,fontSize=size*scale}
end
local function boundary(text,pos)
    if not core.finite(pos) or pos<0 or pos>#text or pos~=math.floor(pos) then return false end
    local byte=text:byte(pos+1); return not byte or byte<128 or byte>=192
end
-- Cursor and selection offsets from ImGui are UTF-8 byte offsets, not character counts.
function M.insertText(text,cursor,first,last,token,capacity)
    if not core.validUtf8(text) or not core.validUtf8(token) or not boundary(text,cursor) or
        not boundary(text,first) or not boundary(text,last) then return nil,'Позиция курсора изменилась. Поставьте его в нужный текст ещё раз.' end
    if first>last then first,last=last,first end
    if first==last then first,last=cursor,cursor end
    local result=text:sub(1,first)..token..text:sub(last+1)
    if not core.finite(capacity) or #result>=capacity then return nil,'В текстовом поле недостаточно места для переменной.' end
    return result,first+#token,first,last
end
function M.new(imgui,ffi,lib,now)
    return setmetatable({imgui=imgui,ffi=ffi,lib=lib,cache={},selected=lib.bindings[1] and lib.bindings[1].id,
        note=lib.notes[1] and lib.notes[1].id,editor='text',editorTab='text',tab='library',status='',args={},query='',quickQuery='',
        statsScope='all',noteMode=false,partner=nil,stepCache={},dirty=false,notices={},feedback=feedbackModule.new(),now=now or function() return os.clock()*1000 end},Studio)
end
local function equal(a,b)
    if type(a)~='table'or type(b)~='table'then return a==b end
    for k,v in pairs(a)do if not equal(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end
    return true
end
local function atPath(lib,path)
    local value=lib;for _,key in ipairs(path)do value=value[key]end;return value
end
function Studio:autoSettings(scope,path,value,clearField)
    self.autosaves=self.autosaves or{}
    if #path==1 and path[1]=='alerts'then value=model.copy(value);value.patrol=model.copy(self.lib.alerts.patrol)end
    local previous=self.autosaves[scope]
    if equal(value,atPath(self.lib,path))then self.autosaves[scope]=nil;return end
    local last=self.savedSettings and self.savedSettings[scope]
    if last and equal(value,last.value)and equal(atPath(self.lib,path),last.stored)then return end
    if previous and equal(value,previous.value)then return end
    self.autosaves[scope]={value=model.copy(value),path=path,at=self.now(),delay=self.settingTextChanged and 600 or 0,
        clearField=clearField,owner=clearField and self[clearField]}
end
function Studio:flushAutosave(callbacks,force)
    for scope,job in pairs(self.autosaves or{})do
        local age=core.elapsed(self.now(),job.at)
        local confirmingDelete=scope=='filters'and self.remove and self.remove.kind=='filter'
        if not job.failed and not confirmingDelete and(force or age and age>=job.delay)then
            local copy=model.copy(self.lib);local parent=copy
            for i=1,#job.path-1 do parent=parent[job.path[i]]end
            local value=model.copy(job.value)
            if #job.path==1 and job.path[1]=='settings'then
                local owned=value;value=model.copy(copy.settings)
                for _,key in ipairs(M.optionKeys)do value[key]=model.copy(owned[key])end
            end
            if #job.path==1 and job.path[1]=='alerts'then value.patrol=model.copy(copy.alerts.patrol)end
            parent[job.path[#job.path]]=value
            local ok,err=callbacks.save(copy,{scope=scope})
            if ok then
                self.savedSettings=self.savedSettings or{};self.savedSettings[scope]={value=model.copy(job.value),stored=model.copy(atPath(self.lib,job.path))}
                self.autosaves[scope]=nil
                if job.clearField and self[job.clearField]==job.owner then self[job.clearField]=nil end
                -- Successful background saves stay silent; explicit actions use an acknowledged window.
            else job.failed=true;self:notify('Не сохранено: '..tostring(err)..' Исправьте значение или повторите запись.',scope,false)end
        end
    end
end
function Studio:autosaveHint(ui,scope)
    local job=self.autosaves and self.autosaves[scope]
    ui.text('Переключатели срабатывают сразу. Текст сохраняется сам, когда вы ненадолго прекращаете печатать.')
    if job and job.failed and self:button('Повторить запись##autosave-'..scope,ui)then job.failed=false;job.at=self.now();job.delay=0 end
end
function Studio:notify(message,scope,bindingId,kind)
    message=message or ''; self.status=message
    scope=scope or self.currentNoticeScope or 'binds'
    if message=='' then self.notices[scope]=nil; return end
    if bindingId==nil and scope=='binds' then bindingId=self.draft and self.draft.id or self.selected end
    self.notices[scope]={message=message,createdAt=self.now(),bindingId=bindingId,kind=kind or'warning'}
    local added=self.feedback:push(message,scope,kind)
    if kind~='info'and added and self.warningLog then pcall(self.warningLog,message)end
end
function Studio:hasWarning()return self.feedback:peek()~=nil end
function Studio:ackWarning()
    local acknowledged=self.feedback:ack();self.modalToken=nil;self.modalVisible=false;self.modalError=nil
    return acknowledged
end
function Studio:passiveWarning(key,message,scope)
    if self.feedback:once(key,message,scope)and self.warningLog then pcall(self.warningLog,message)end
end
-- No transient footer notifications. Status events share the acknowledged window.
function Studio:drawNotice(ui)end
function Studio:observeStatus(key,message,scope)
    self.observedStatus=self.observedStatus or {}
    if self.observedStatus[key]==message then return end
    self.observedStatus[key]=message
    if message and message~=''then self.statusInfo={key=key,message=message}end
end
-- Live progress has its own nonmodal window. It must not block the action
-- whose progress it reports or turn a target selection into a confirmation.
function Studio:drawStatusInfo(ui)
    local info=self.statusInfo;if not info or self:hasModal()then return end
    local im=self.imgui
    local spec={title='Состояние PA',lines={info.message},font=self.buttonFont,titleFont=self.headingFont,pageState=info}
    local layout=menuModule.confirmationLayout(im,spec);local io=im.GetIO()
    im.SetNextWindowSize(im.ImVec2(layout.width,layout.height),im.Cond.Always)
    im.SetNextWindowPos(im.ImVec2((io.DisplaySize.x-layout.width)/2,math.max(16,io.DisplaySize.y-layout.height-24)),im.Cond.FirstUseEver)
    local visible=im.Begin('Состояние PA##pa26-status-info',nil,im.WindowFlags.NoSavedSettings+im.WindowFlags.NoCollapse+
        im.WindowFlags.NoResize+im.WindowFlags.NoFocusOnAppearing+im.WindowFlags.NoScrollbar+im.WindowFlags.NoScrollWithMouse)
    ui.push(function()im.End()end)
    if visible then
        menuModule.confirmationBody(im,ui,layout,spec)
        if self:button('ОК##status-info-ok',ui)then self.statusInfo=nil end
    end
    ui.finish()
end
function Studio:clearSteps()
    self.stepDraft=nil; self.stepSource=nil; self.stepError=nil; self.stepOrder={}
    for key in pairs(self.cache) do if key:match('^step:') then self.cache[key]=nil end end
end
function Studio:buffer(key,value,size)
    if not self.cache[key] then
        local buffer=self.imgui.new.char[size or 1024](); self.ffi.copy(buffer,value or '',math.min(#(value or ''),(size or 1024)-1)); self.cache[key]=buffer
    end
    return self.cache[key]
end
function Studio:setBuffer(key,value,size)
    local buffer=self:buffer(key,'',size); self.ffi.fill(buffer,self.ffi.sizeof(buffer)); self.ffi.copy(buffer,value,math.min(#value,self.ffi.sizeof(buffer)-1)); return buffer
end
function Studio:clearTextFocus()
    self.textCursor=nil; self.pendingInsert=nil; self.editField=nil
end
function Studio:forgetKnowledgeIdentity()
    for key in pairs(self.cache)do if type(key)=='string'and key:match('^args:.*:ic_name$')then self.cache[key]=nil end end
end
function Studio:release()
    self:clearTextFocus()
    if self.editCallback then self.editCallback:free(); self.editCallback=nil end
end
function Studio:inputCallback(data)
    local field=self.editField;if not field then return end
    local view=self.textViews and self.textViews[field.key]
    if view then view.cursor=data.CursorPos;view.first=data.SelectionStart;view.last=data.SelectionEnd end
    if not field.body or not self.draft then return end
    if data.BufTextLen<0 or data.BufTextLen>=data.BufSize then return end
    local text=self.ffi.string(data.Buf,data.BufTextLen)
    local pending=self.pendingInsert
    if pending and pending.key==field.key and pending.binding_id==self.draft.id then
        self.pendingInsert=nil
        if text~=pending.text then self:notify('Текст изменился. Повторите вставку в нужной позиции.')
        else
            local result,pos,first,last=M.insertText(text,pending.cursor,pending.first,pending.last,pending.token,math.min(field.capacity,data.BufSize))
            if not result then self:notify(pos)
            else
                data.CursorPos=pending.cursor; data.SelectionStart=pending.first; data.SelectionEnd=pending.last
                if last>first then data:DeleteChars(first,last-first) end
                data:InsertChars(first,pending.token)
                data.CursorPos=pos; data.SelectionStart=pos; data.SelectionEnd=pos
                local ordinal=self.stepOrder and self.stepOrder[tonumber(field.key:match('%d+$'))]
                -- The inserted token itself is the result; keep editor focus and selection.
                text=self.ffi.string(data.Buf,data.BufTextLen)
            end
        end
    end
    if boundary(text,data.CursorPos) and boundary(text,data.SelectionStart) and boundary(text,data.SelectionEnd) then
        self.textCursor={key=field.key,binding_id=self.draft.id,text=text,cursor=data.CursorPos,first=data.SelectionStart,last=data.SelectionEnd}
    end
end
function Studio:insertVariable()
    if not self.draft or not model.variableNames[self.variable] then self:notify('Выберите переменную из списка.'); return false end
    local cursor=self.textCursor
    if not cursor or cursor.binding_id~=self.draft.id or (self.editor=='text')~=(cursor.key=='script') then
        if self.editor~='text' then self:notify('Поставьте курсор в нужную реплику перед вставкой.'); return false end
        cursor={key='script',binding_id=self.draft.id,text=self.draft.script,cursor=#self.draft.script,first=#self.draft.script,last=#self.draft.script}
    end
    self.pendingInsert=model.copy(cursor); self.pendingInsert.token='{'..self.variable..'}'
    return true
end
function Studio:field(label,key,value,size,multiline,height)
    local imgui=self.imgui; local buffer=self:buffer(key,value,size)
    local visible=label:match('^(.-)##') or label
    if visible~=''and not menuModule.searchHeading(imgui,self.currentUi,visible,self.buttonFont)then self.currentUi.text(visible)end
    local inputLabel=visible~='' and ('##'..label) or label
    imgui.PushItemWidth(-1); self.currentUi.push(function() imgui.PopItemWidth() end)
    local changed,flags,callback=false,0,nil
    local body=multiline and self.draft and (key=='script' or key:match('^step:%d+$'))
    if multiline then
        if not self.editCallback then self.editCallback=self.ffi.cast('ImGuiInputTextCallback',function(data)
            local ok=pcall(self.inputCallback,self,data)
            if not ok then self.pendingInsert=nil; self:notify('Вставка недоступна. Поставьте курсор в поле ещё раз.') end
            return 0
        end) end
        flags=imgui.InputTextFlags.CallbackAlways; callback=self.editCallback
        self.editField={key=key,capacity=self.ffi.sizeof(buffer),body=body}
    end
    if multiline then changed=require('pa26_text_editor').draw(self,self.currentUi,inputLabel,key,buffer,height or 180,flags,callback)
    else changed=imgui.InputText(inputLabel,buffer,self.ffi.sizeof(buffer)) end
    self.editField=nil
    self.currentUi.finish()
    if changed and self.preferenceContext then self.settingTextChanged=true end
    return self.ffi.string(buffer),changed
end
function Studio:check(label,value)
    local flag=self.imgui.new.bool(value); local changed=self.imgui.Checkbox(label,flag); return flag[0],changed
end
function Studio:choice(label,value,choices,ui)
    local options={font=self.buttonFont,headingFont=self.buttonFont,fold=model.casefold}
    if label:find('##weapons-page',1,true)or label:find('##radio-page',1,true)then
        options.buttons=true;options.description=true
    elseif label:find('##variable',1,true)or label:find('##weapon-edit',1,true)or
        label:find('##guard-report',1,true)or label:match('##wheel%d+$')then
        options.list=true
    elseif label:find('##bind-wheel-group',1,true)then options.buttons=true end
    return menuModule.choiceControl(self.imgui,ui,'##'..label,label:match('^(.-)##')or label,value,choices,self,options)
end
function Studio:button(label,ui,width)
    return menuModule.fittedButton(self.imgui,ui,label,
        self.imgui.ImVec2(width or math.max(1,self.imgui.GetContentRegionAvail().x),42),self.buttonFont)
end
local function child(self,ui,label,width,height,body,flags,padding,border)
    local im=self.imgui
    if padding then im.PushStyleVarVec2(im.StyleVar.WindowPadding,im.ImVec2(padding,padding)); ui.push(function() im.PopStyleVar(1) end) end
    local visible=im.BeginChild(label,im.ImVec2(width,height),border~=false,(flags or 0)+im.WindowFlags.AlwaysUseWindowPadding)
    ui.push(function() im.EndChild() end); if visible then body() end; ui.finish()
    if padding then ui.finish() end
end
function Studio:resetBinding(id)
    self.selected=id; self.draft=nil; self.dirty=false; self.plan=nil
    self.pendingSelection=nil; self.pendingEditorTab=nil; self.cache={}; self.stepCache={}
    self:clearTextFocus()
    self:clearSteps()
end
function Studio:setLibrary(lib)
    local wasStored=model.find(self.lib,self.selected)
    self.lib=lib
    local stored=model.find(lib,self.selected)
    -- Saving another page must keep a new/duplicated bind that is not stored yet.
    if self.dirty and self.draft and self.draft.id==self.selected and not wasStored then
        -- An import may consume the provisional ID; preserve both records.
        if stored and self.savingDraftId~=self.draft.id then
            self.selected=lib.next_id; self.draft.id=self.selected; self.plan=nil
            self:clearTextFocus()
        end
    elseif not stored or (self.dirty and not self.draft) then
        self:resetBinding(stored and self.selected or (lib.bindings[1] and lib.bindings[1].id))
    end
    if self.pendingSelection and not model.find(lib,self.pendingSelection) then
        self.pendingSelection=nil; self.pendingEditorTab=nil
    end
end
function Studio:select(id)
    if self.selected==id and self.draft then return end
    if self.dirty and self.selected~=id then self.pendingSelection=id; return end
    self.selected=id; local b=model.find(self.lib,id); self.draft=b and model.copy(b) or nil
    self.cache={}; self.stepCache={}; self.dirty=false; self.plan=nil
    self:clearTextFocus()
    self:clearSteps()
end
function Studio:tooltip(ui,value)
    menuModule.tooltip(self.imgui,ui,value)
end
function Studio:rowTitle(ui,title,selected,width,height)
    local im=self.imgui
    im.PushStyleVarFloat(im.StyleVar.FrameRounding,12); ui.push(function() im.PopStyleVar(1) end)
    im.PushStyleVarVec2(im.StyleVar.ButtonTextAlign,im.ImVec2(0,.5)); ui.push(function() im.PopStyleVar(1) end)
    im.PushStyleColor(im.Col.Button,im.ImVec4(.10,.32,.48,selected and .84 or 0)); ui.push(function() im.PopStyleColor(1) end)
    im.PushStyleColor(im.Col.ButtonHovered,im.ImVec4(.13,.35,.50,.78)); ui.push(function() im.PopStyleColor(1) end)
    im.PushStyleColor(im.Col.ButtonActive,im.ImVec4(.13,.42,.59,.94)); ui.push(function() im.PopStyleColor(1) end)
    if self.buttonFont then im.PushFont(self.buttonFont); ui.push(function() im.PopFont() end) end
    local font,fontSize=im.GetFont(),im.GetFontSize()
    local visible=title:match('^(.-)##') or title
    local layout=menuModule.labelLayout(font,fontSize,math.max(1,width-28),visible)
    im.PushStyleColor(im.Col.Text,im.ImVec4(1,1,1,0)); ui.push(function() im.PopStyleColor(1) end)
    local clicked=im.Button(title,im.ImVec2(width,height)); ui.finish()
    local first=im.GetItemRectMin()
    menuModule.drawCenteredLabel(im,font,fontSize,first,width,height,layout)
    if self.buttonFont then ui.finish() end
    for _=1,5 do ui.finish() end
    return clicked
end
function Studio:iconButton(ui,id,kind,height,enabled)
    local im=self.imgui
    enabled=enabled~=false
    im.PushStyleVarFloat(im.StyleVar.FrameRounding,11); ui.push(function() im.PopStyleVar(1) end)
    im.PushStyleColor(im.Col.Button,kind=='play' and im.ImVec4(.10,.40,.58,.84) or im.ImVec4(.10,.21,.31,.66)); ui.push(function() im.PopStyleColor(1) end)
    local clicked=im.Button('##'..id,im.ImVec2(34,height or 34))
    ui.finish(); ui.finish()
    local first,last=im.GetItemRectMin(),im.GetItemRectMax()
    local x,y=(first.x+last.x)/2,(first.y+last.y)/2
    local list=im.GetWindowDrawList(); local tint=im.ColorConvertFloat4ToU32(im.ImVec4(.93,.97,1,enabled and 1 or .28))
    if kind=='play' then list:AddTriangleFilled(im.ImVec2(x-4,y-7),im.ImVec2(x+7,y),im.ImVec2(x-4,y+7),tint)
    elseif kind=='up' or kind=='down' then
        local direction=kind=='up' and -1 or 1
        list:AddLine(im.ImVec2(x-5,y-2*direction),im.ImVec2(x,y+3*direction),tint,1.8)
        list:AddLine(im.ImVec2(x,y+3*direction),im.ImVec2(x+5,y-2*direction),tint,1.8)
    else
        list:AddCircle(im.ImVec2(x,y),9,tint,24,1.5)
        list:AddCircleFilled(im.ImVec2(x,y-4),1.2,tint,12)
        list:AddLine(im.ImVec2(x,y-1),im.ImVec2(x,y+5),tint,1.6)
    end
    return clicked and enabled
end
function Studio:launchBinding(binding,callbacks,returnTo)
    if not binding.enabled then self:notify('Сценарий выключен. Включите его в настройках.'); return false end
    if self.dirty and self.selected==binding.id then self:notify('Сохраните изменения перед запуском этого сценария.'); return false end
    if #binding.parameters>0 or binding.script:find('{param',1,true) then
        if returnTo=='quick' then self.quickSelected=binding.id
        else self:select(binding.id); self.bindPane='editor'; if self.pendingSelection then self.pendingEditorTab='run' else self.editorTab='run' end end
        return true -- The argument form itself explains the next step.
    end
    return callbacks.request({kind='prepare',binding=model.copy(binding),args={},start=true,returnTo=returnTo})
end
function Studio:bindingRow(ui,data,callbacks,binding,number,quick)
    local im=self.imgui
    local access='Клавиша: '..model.shortcutName(binding.shortcut)
    if binding.quick then access=access..' · Меню: '..model.keyName(self.lib.settings.quick_key) end
    local width=math.max(1,im.GetContentRegionAvail().x-24)
    local titleWidth=math.max(1,width-80)
    local title=quick and label(binding.name)..'##quick'..binding.id or string.format('%03d',number)..'  '..(binding.enabled and '' or '(выкл.) ')..label(binding.name)..'##bind'..binding.id
    if self.buttonFont then im.PushFont(self.buttonFont); ui.push(function() im.PopFont() end) end
    local titleLayout=menuModule.labelLayout(im.GetFont(),im.GetFontSize(),math.max(1,titleWidth-28),title:match('^(.-)##'))
    local titleHeight=math.max(quick and 34 or 44,titleLayout.height+16)
    if self.buttonFont then ui.finish() end
    local accessExtent=im.GetFont():CalcTextSizeA(im.GetFontSize(),100000,width,access)
    local height=24+titleHeight+10+accessExtent.y+4
    local selected=quick and self.quickSelected==binding.id or not quick and self.selected==binding.id
    if selected then im.PushStyleColor(im.Col.ChildBg,im.ImVec4(.08,.21,.34,.76)); ui.push(function() im.PopStyleColor(1) end) end
    child(self,ui,(quick and 'quickrow##' or 'bindingrow##')..binding.id,0,height,function()
        local origin=im.GetCursorScreenPos()
        local actualTitleWidth=math.max(1,im.GetContentRegionAvail().x-80)
        if self:rowTitle(ui,title,selected,actualTitleWidth,titleHeight) then
            if quick then self:launchBinding(binding,callbacks,'quick') else self:select(binding.id); self.bindPane='editor' end
        end
        self:tooltip(ui,binding.name..(quick and '\nНажмите для запуска.' or '\nНажмите для редактирования.'))
        im.SetCursorScreenPos(im.ImVec2(origin.x+actualTitleWidth+6,origin.y+(titleHeight-34)/2))
        if self:iconButton(ui,(quick and 'quick-run' or 'bind-run')..binding.id,'play') then self:launchBinding(binding,callbacks,quick and 'quick' or 'binds') end
        self:tooltip(ui,data.demo and 'Запустить в демо: отправок в игру нет.' or 'Открыть предпросмотр. Перед отправкой вы увидите весь текст и команды.')
        if quick then
            im.SetCursorScreenPos(im.ImVec2(origin.x+actualTitleWidth+46,origin.y+(titleHeight-34)/2))
            if self:iconButton(ui,'quick-info'..binding.id,'info') then
                self.infoBinding=binding.id; self.infoReturn='quick'; self.infoPending=true
            end
            self:tooltip(ui,'Информация: клавиша, быстрое меню и требования к игроку.')
        else
            local x,y=origin.x+actualTitleWidth+46,origin.y+(titleHeight-44)/2
            im.SetCursorScreenPos(im.ImVec2(x,y))
            if self:iconButton(ui,'bind-up'..binding.id,'up',20,number>1) then self.reorderRequest={id=binding.id,offset=-1} end
            self:tooltip(ui,number>1 and ('Поднять «'..binding.name..'» на одну позицию в библиотеке.') or 'Уже первый бинд в библиотеке.')
            im.SetCursorScreenPos(im.ImVec2(x,y+24))
            if self:iconButton(ui,'bind-down'..binding.id,'down',20,number<#self.lib.bindings) then self.reorderRequest={id=binding.id,offset=1} end
            self:tooltip(ui,number<#self.lib.bindings and ('Опустить «'..binding.name..'» на одну позицию в библиотеке.') or 'Уже последний бинд в библиотеке.')
        end
        im.SetCursorScreenPos(im.ImVec2(origin.x,origin.y+titleHeight+10))
        ui.text(access)
    end,im.WindowFlags.NoScrollbar+im.WindowFlags.NoScrollWithMouse,12)
    if selected then ui.finish() end
end
function Studio:drawBindingInfo(ui,data,callbacks)
    if self.draft then for _,warning in ipairs(require('pa26_server_commands').bindingWarnings(self.draft))do ui.text(warning)end end
    local im=self.imgui
    if not self.infoBinding then return end
    if self.infoPending then self.infoPosition=nil;self.infoDrag={};im.OpenPopup('pa26-binding-info'); self.infoPending=nil end
    local display=im.GetIO().DisplaySize
    if self.infoPosition then
        local p=self.infoPosition
        im.SetNextWindowPos(im.ImVec2(math.max(16,math.min(p.x,display.x-p.width-16)),math.max(16,math.min(p.y,display.y-p.height-16))),im.Cond.Always)
    end
    im.SetNextWindowSize(im.ImVec2(math.max(1,math.min(480,display.x-32)),math.max(1,math.min(400,display.y-32))),im.Cond.Always)
    if im.BeginPopup('pa26-binding-info',im.WindowFlags.NoSavedSettings) then
        ui.push(function() im.EndPopup() end)
        self.infoDrag=self.infoDrag or{};self.infoPosition=menuModule.rightDragRect(im,self.infoDrag,'binding-info')or self.infoPosition
        local b=model.find(self.lib,self.infoBinding)
        if b then
            ui.text(b.name); im.Separator()
            if self.dirty and self.selected==b.id then ui.text('В редакторе есть несохранённые изменения.') end
            ui.text('Категория: '..b.category)
            ui.text('Клавиша запуска: '..model.shortcutName(b.shortcut))
            ui.text(b.quick and ('Быстрое меню: '..model.keyName(self.lib.settings.quick_key)) or 'В быстрое меню не добавлен.')
            ui.text('Команда: /pa26run '..b.id)
            if b.command~='' then ui.text('Личная команда: /'..b.command) end
            self:drawRequirements(ui,b)
            ui.text(data.demo and 'Режим: ДЕМО, без отправки.' or 'Режим: реальная отправка после проверок.')
            if self:button(data.demo and 'Запустить в демо##info' or 'Подготовить запуск##info',ui) then
                if self:launchBinding(b,callbacks,self.infoReturn) then im.CloseCurrentPopup() end
            end
        else ui.text('Сценарий удалён.') end
        ui.finish()
    end
end
function Studio:saveDraft(callbacks)
    if self.stepError then self:notify(self.stepError,'binds'); return false end
    if not self.draft then self:notify('Нет редактируемого сценария. Выберите бинд или создайте новый.'); return false end
    local draft,err=model.validateBinding(self.draft)
    if not draft then self:notify(err); return false end
    local candidate=model.copy(self.lib); local found=false
    for i,b in ipairs(candidate.bindings) do if b.id==draft.id then candidate.bindings[i]=model.copy(draft); found=true end end
    if not found then candidate.bindings[#candidate.bindings+1]=model.copy(draft); candidate.next_id=math.max(candidate.next_id,draft.id+1) end
    self.savingDraftId=draft.id
    local ok; ok,err=callbacks.save(candidate)
    self.savingDraftId=nil
    self:notify(err or (ok and 'Сценарий сохранён.' or 'Сохранение не выполнено.'),nil,nil,ok and'info'or'warning')
    if ok then self.lib=candidate; self.selected=draft.id; self.draft=draft; self.dirty=false; self.plan=nil end
    return ok
end
function Studio:unsavedChanges()
    local labels={}
    if self.dirty and self.draft then labels[#labels+1]='Бинд: '..self.draft.name end
    local d=self.noteDraft
    if d then
        local stored;for _,n in ipairs(self.lib.notes)do if n.id==d.id then stored=n end end
        if not stored or stored.name~=d.name or stored.body~=d.body then labels[#labels+1]='Памятка: '..d.name end
    end
    return #labels>0,labels
end
function Studio:requestNavigation(action,label)
    local dirty=self:unsavedChanges()
    if not dirty then action();return true end
    self.navigationSerial=(self.navigationSerial or 0)+1
    self.pendingNavigation={action=action,label=label or'перейти дальше',serial=self.navigationSerial}
    return false
end
function Studio:resolveNavigation(save,callbacks)
    local pending=self.pendingNavigation;if not pending then return nil,'Переход уже отменён.'end
    local candidate=model.copy(self.lib);local binding
    if save then
        if self.dirty and self.draft then
            if self.stepError then return nil,self.stepError end
            local err;binding,err=model.validateBinding(self.draft);if not binding then return nil,err end
            local found=false
            for i,b in ipairs(candidate.bindings)do if b.id==binding.id then candidate.bindings[i]=model.copy(binding);found=true end end
            if not found then candidate.bindings[#candidate.bindings+1]=model.copy(binding);candidate.next_id=math.max(candidate.next_id,binding.id+1)end
        end
        if self.noteDraft then
            local found=false
            for _,n in ipairs(candidate.notes)do if n.id==self.noteDraft.id then n.name=self.noteDraft.name;n.body=self.noteDraft.body;found=true end end
            if not found then return nil,'Памятка удалена. Скопируйте текст или отмените изменения перед переходом.'end
        end
        self.savingDraftId=binding and binding.id
        local worked,ok,err=pcall(callbacks.save,candidate);self.savingDraftId=nil
        if not worked then return nil,'Ошибка сохранения: '..tostring(ok)end
        if not ok then return nil,err or'Не удалось сохранить изменения. Черновики остаются в редакторе.'end
        self.lib=candidate
    end
    if self.dirty then
        local stored=binding or model.find(self.lib,self.selected)
        self.draft=stored and model.copy(stored)or nil;self.dirty=false;self.plan=nil;self.stepError=nil;self.stepCache={}
    end
    self.noteDraft=nil;self.noteMode=false;self.cache={};self:clearTextFocus()
    self.pendingNavigation=nil;pending.action();return true
end
function Studio:drawRequirements(ui,binding)
    local cached=self.requirementCache
    if not cached or cached.script~=binding.script or cached.target_required~=binding.target_required then
        cached={script=binding.script,target_required=binding.target_required,lines=binder.requirementHints(binder.requirements(binding))}
        self.requirementCache=cached
    end
    for _,line in ipairs(cached.lines) do ui.text(line) end
end
function Studio:arguments(binding,ui,prefix)
    local args={}; local im=self.imgui
    for i=1,8 do local name='param'..i
        if binding.script:find('{'..name..'}',1,true) or (i<=3 and binding.script:find('{params}',1,true)) then
            local value=self:field('Аргумент '..i..'##'..prefix,'args:'..prefix..':'..name,'',512); args[name]=value
        end
    end
    for _,p in ipairs(binding.parameters) do
            local value=self:field(label(p.label~='' and p.label or p.name)..(p.required and ' *' or '')..'##'..prefix..p.name,'args:'..prefix..':'..p.name,p.default,512); args[p.name]=value
    end
    return args
end
function Studio:drawSteps(ui)
    local draft=self.draft; local im=self.imgui
    if not self.stepDraft or self.stepSource~=draft.script then
        self:clearSteps()
        local steps,err=binder.parseEditor(draft.script)
        if not steps then ui.text(err); if self:button('Открыть текст для исправления',ui) then self.editor='text' end; return end
        self.stepDraft=steps; self.stepSource=draft.script; self.nextStepId=1
        for _,step in ipairs(steps) do step.uid=self.nextStepId; self.nextStepId=self.nextStepId+1 end
    end
    local steps=self.stepDraft; local changed,mutation
    self.stepOrder={}
    for ordinal,step in ipairs(steps) do self.stepOrder[step.uid]=ordinal end
    ui.text('Enter добавляет строку. Длинный текст прокручивается по горизонтали полосой внизу поля. Выделение и курсор сохраняются; ниже доступен полный текст с переносом.')
    for i,step in ipairs(steps) do
        local uid=step.uid; local width=math.max(1,im.GetContentRegionAvail().x-24)
        local font,size=im.GetFont(),im.GetFontSize()
        local title='Шаг '..i..' · '..({message='Текст',wait='Пауза',key='Ожидание клавиши',check='Проверка',sound='Звук',cancel='Завершение',screen='Скриншот',select='Выбор'})[step.kind]
        local titleH=font:CalcTextSizeA(size,100000,width,title).y
        local bodyH,fieldH,previewH
        if step.kind=='message' then
            local lines=select(2,step.template:gsub('\n',''))+1
            fieldH=math.max(96,math.min(180,lines*size+24)); bodyH=fieldH
            local tooWide=false
            for line in (step.template..'\n'):gmatch('(.-)\n')do
                if font:CalcTextSizeA(size,100000,0,line).x>math.max(1,width-24)then tooWide=true;break end
            end
            if tooWide then
                previewH=math.max(size+8,math.min(160,font:CalcTextSizeA(size,100000,math.max(1,width-24),step.template).y+12))
                bodyH=bodyH+20+size+previewH
            end
        elseif step.kind=='wait' then bodyH=size+10+38
        else bodyH=font:CalcTextSizeA(size,100000,width,binder.toScript({step})).y end
        local toolbarWidth=math.max(1,(width-16)/3)
        local toolbarH=math.max(36,font:CalcTextSizeA(size,100000,math.max(1,toolbarWidth-28),'Удалить').y+16)
        local cardH=24+titleH+10+bodyH+10+toolbarH+6
        child(self,ui,'step##'..uid,0,cardH,function()
            ui.text(title)
            if step.kind=='message' then
                local value,edit=self:field('##textstep'..uid,'step:'..uid,step.template,16385,true,fieldH)
                if edit then step.template=value; changed=true end
                if previewH then
                    ui.text('Полный текст · визуальный перенос')
                    child(self,ui,'step-preview##'..uid,0,previewH,function()ui.text(step.template)end,0,4,false)
                end
            elseif step.kind=='wait' then
                ui.text('Пауза, миллисекунды')
                im.PushItemWidth(-1); ui.push(function() im.PopItemWidth() end)
                local value=im.new.int(step.ms)
                if im.InputInt('##wait'..uid,value) then step.ms=math.max(0,math.min(60000,value[0])); changed=true end
                ui.finish()
            else ui.text(binder.toScript({step})) end
            for index,entry in ipairs({{'Выше','up'},{'Ниже','down'},{'Удалить','delete'}}) do
                if index>1 then im.SameLine(0,8) end
                if menuModule.fittedButton(im,ui,entry[1]..'##step'..uid,im.ImVec2(toolbarWidth,toolbarH)) then
                    mutation={kind=entry[2],index=i}
                end
            end
        end,im.WindowFlags.NoScrollbar+im.WindowFlags.NoScrollWithMouse,12)
    end
    if #steps<64 and not mutation then
        if im.Button('+ Реплика##addstep') then mutation={kind='add',step={kind='message',template='Новая реплика.'}} end
        im.SameLine(); if im.Button('+ Пауза##addpause') then mutation={kind='add',step={kind='wait',ms=1500}} end
        if im.Button('+ Ожидание F11##addkey') then mutation={kind='add',step={kind='key',key=0x7A}} end
    end
    if mutation then
        local i=mutation.index
        if mutation.kind=='delete' then
            self.cache['step:'..steps[i].uid]=nil; table.remove(steps,i); changed=true
        elseif mutation.kind=='up' and i>1 then steps[i],steps[i-1]=steps[i-1],steps[i]; changed=true
        elseif mutation.kind=='down' and i<#steps then steps[i],steps[i+1]=steps[i+1],steps[i]; changed=true
        elseif mutation.kind=='add' then
            mutation.step.uid=self.nextStepId; self.nextStepId=self.nextStepId+1
            steps[#steps+1]=mutation.step; changed=true
        end
        if changed then self:clearTextFocus() end
    end
    if changed then
        local script,err=model.clean(binder.toScript(steps),16384,true)
        self.dirty=true; self.plan=nil; self.stepError=err
        if script then draft.script=script; self.stepSource=script; self:setBuffer('script',script,16385) end
    end
    if self.stepError then ui.text(self.stepError) end
end
function Studio:drawEditorBody(ui,data,callbacks)
    if not self.draft then self:select(self.selected) end
    local b=self.draft; if not b then ui.text('Добавьте первый сценарий.'); self:drawNotice(ui); return end
    local im=self.imgui
    if data.target then ui.text('Закреплённая цель: '..data.target.name..' ['..data.target.id..']') end
    local changed,value
    value,changed=self:field('Название##bind','name',b.name,256); if changed then b.name=value; self.dirty=true; self.plan=nil end
    local available,used=im.GetContentRegionAvail().x,0
    for _,tab in ipairs({{'general','Общее'},{'text','Текст'},{'parameters','Параметры'},{'run','Запуск'}}) do
        local title=tab[2]; local width=math.min(available,im.CalcTextSize(title).x+24)
        if used>0 and used+10+width<=available then im.SameLine(0,10); used=used+10 else used=0 end
        local active=self.editorTab==tab[1]
        if active then im.PushStyleColor(im.Col.Button,im.ImVec4(.15,.43,.63,1)); ui.push(function() im.PopStyleColor(1) end) end
        if im.Button(tab[2]..'##editor-tab',im.ImVec2(width,38)) then self.editorTab=tab[1] end; used=used+width
        if active then ui.finish() end
    end
    im.Separator()
    if self.editorTab=='general' then
    for _,f in ipairs({{'category','Категория',256},{'command','Команда запуска (pa26_имя)',64},{'command_alias','Короткая команда (название)',64}}) do
        value,changed=self:field(f[2]..'##bind',f[1],b[f[1]],f[3]); if changed then b[f[1]]=value; self.dirty=true; self.plan=nil end
    end
    ui.text('Вводите без /: pa26_name в первое поле или name во второе, можно заполнить оба. В чате запуск будет /pa26_name или /name. Используйте латиницу без пробелов. Серверные и занятые имена не заменяются.')
    for _,f in ipairs({{'enabled','Включён'},{'quick','В быстром меню'},{'wheel_visible','В радиальном меню'},{'favorite','Избранное'},{'target_required','Требовать выбранного игрока'},
        {'skip_confirmation','Без предупреждения'},{'no_accent','Без акцента'}}) do
        value,changed=self:check(f[2]..'##bind',b[f[1]]); if changed then b[f[1]]=value; self.dirty=true; self.plan=nil end
        if f[1]=='skip_confirmation'then self:tooltip(ui,'Запускать этот бинд без окна ДА / НЕТ. Проверки цели, параметров и доступности игры остаются включены. Сохраните сценарий, чтобы запомнить выбор.')end
        if f[1]=='no_accent'then self:tooltip(ui,'Подставлять пустое значение вместо {accent} в этом сценарии. Для предупреждения об оружии такая же настройка есть рядом с его текстом.')end
    end
    b.wheel_group,changed=self:choice('Категория колеса##bind-wheel-group',b.wheel_group or 'auto',
        wheelModel.categoryChoices(self.lib.settings.wheel_names),ui)
    if changed then self.dirty=true; self.plan=nil end
    ui.text('Клавиша: '..model.shortcutName(b.shortcut))
    if im.Button('Записать сочетание##bindkey') then callbacks.capture({kind='binding',id=b.id}) end
    im.SameLine(); if im.Button('Убрать##bindkey') then b.shortcut={key=0,ctrl=false,alt=false,shift=false}; self.dirty=true end
    b.stat,changed=self:choice('Служебный результат##stat',b.stat,model.stats,ui); if changed then self.dirty=true end
    end
    if self.editorTab=='text' then
    local modeWidth=math.max(1,(im.GetContentRegionAvail().x-10)/2)
    if self:rowTitle(ui,'Текст##mode',self.editor=='text',modeWidth,38)then self.editor='text';self:clearTextFocus()end
    im.SameLine(0,10)
    if self:rowTitle(ui,'Шаги##mode',self.editor=='steps',modeWidth,38)then self.editor='steps';self:clearTextFocus()end
    if self.editor=='text' then
        value,changed=self:field('##script','script',b.script,16385,true,230); if changed then b.script=value; self.dirty=true; self.plan=nil; self:clearSteps() end
    else self:drawSteps(ui) end
    self.variable=self.variable or 'my_name'
    local variableSearch=self:field('Найти переменную##search','variableSearch','',256)
    local variableChoices={}; local needle=model.casefold(variableSearch)
    local chosenVisible=false
    for _,v in ipairs(model.variables) do if needle=='' or model.casefold(v[1]..' '..v[2]):find(needle,1,true) then
        variableChoices[#variableChoices+1]={v[1],'{'..v[1]..'} · '..v[2]}; if v[1]==self.variable then chosenVisible=true end
    end end
    if #variableChoices>0 and not chosenVisible then self.variable=variableChoices[1][1] end
    self.variable=self:choice('Вставка##variable',self.variable,variableChoices,ui)
    if #variableChoices==0 then ui.text('Переменные не найдены. Измените поиск.')
    else
        local info=model.variableInfo(self.variable); ui.text('Источник: '..info.source..'. '..info.detail)
        ui.text(self.editor=='text' and 'Вставка в курсор; выделенный текст заменяется.' or 'Текст вставится в последнюю выбранную реплику. Если что-то выделено, вставка заменит выделение.')
        if im.Button('Вставить {'..self.variable..'}##insert') then self:insertVariable() end
    end
    ui.text('{gender:предъявил|предъявила} · @random(Добрый день|Здравствуйте)')
    end
    if self.editorTab=='parameters' then
    im.Separator()
    ui.text('Именованные параметры: {param:имя}')
    for i,p in ipairs(b.parameters) do
        value,changed=self:field('Имя##param'..i,'paramname'..i,p.name,32); if changed then p.name=value; self.dirty=true end
        value,changed=self:field('Подпись##param'..i,'paramlabel'..i,p.label,256); if changed then p.label=value; self.dirty=true end
        value,changed=self:field('По умолчанию##param'..i,'paramdefault'..i,p.default,512); if changed then p.default=value; self.dirty=true end
        p.type,changed=self:choice('Тип##param'..i,p.type,{{'text','Текст'},{'integer','Целое число'}},ui); if changed then self.dirty=true end
        p.required,changed=self:check('Обязательный##param'..i,p.required); if changed then self.dirty=true end
        if im.Button('Удалить параметр##'..i) then table.remove(b.parameters,i); self.dirty=true; self.cache={}; break end
    end
    if #b.parameters<8 and im.Button('+ Параметр##newparam') then local n=#b.parameters+1; b.parameters[n]={name='arg'..n,label='Параметр '..n,default='',type='text',required=true}; self.dirty=true end
    end
    if self.editorTab=='run' then
    im.Separator()
    ui.text('Команда этого сценария: /pa26run '..b.id)
    local args=self:arguments(b,ui,'editor'..b.id)
    if self:button('Предпросмотр текущего текста',ui) then
        if self.stepError then self:notify(self.stepError) else callbacks.request({kind='preview',binding=model.copy(b),args=args,returnTo='binds'}) end
    end
    if self:button(data.demo and 'Выполнить в демо' or 'Подготовить запуск',ui) then
        if self.stepError then self:notify(self.stepError) else callbacks.request({kind='prepare',binding=model.copy(b),args=args,returnTo='binds',start=true}) end
    end
    if self.plan and self.plan.binding.id==b.id then ui.text('Итоговый текст'); for _,line in ipairs(self.plan.lines) do ui.text(line) end end
    end
    im.Separator()
    self:drawRequirements(ui,b)
    self:drawNotice(ui)
end
function Studio:drawEditor(ui,data,callbacks)
    if not self.draft then self:select(self.selected)end
    if not self.draft then ui.text('Добавьте первый сценарий.');return end
    local im=self.imgui
    -- Header belongs to the outer pane. Only the body below it can scroll.
    if self:button('Сохранить сценарий',ui)then self:saveDraft(callbacks)end
    ui.text(self.dirty and 'Изменения ещё не сохранены'or 'Редактор сценария · Все изменения сохранены')
    ui.text(string.format('Сценарий %03d',model.bindingNumber(self.lib,self.draft.id)or(#self.lib.bindings+1)))
    im.Separator()
    child(self,ui,'bind-editor-body##studio',0,math.max(1,im.GetContentRegionAvail().y),function()
        self:drawEditorBody(ui,data,callbacks)
    end)
end
function M.bindingPanels(width,height,ratio)
    if not core.finite(width) or not core.finite(height) or width<1 or height<1 then return nil end
    local wide=width>=730
    if not wide then return {wide=false,width=width,height=height} end
    ratio=core.finite(ratio) and ratio or .46
    local left=math.max(260,math.min(width-372,width*ratio))
    return {wide=true,width=width,height=height,left=left,gap=12,right=width-left-12}
end
function Studio:createBinding()
    if self.dirty then self:notify('Сначала сохраните или отмените изменения.')
    elseif #self.lib.bindings>=128 then self:notify('Достигнут лимит 128 сценариев.')
    else
        self.selected=self.lib.next_id; self.draft=model.newBinding(self.selected)
        self.cache={}; self.dirty=true; self.plan=nil; self.bindPane='editor'
        self:clearTextFocus(); self:clearSteps()
    end
end
function Studio:duplicateBinding()
    if self.dirty then self:notify('Сначала сохраните изменения.'); return end
    local old=model.find(self.lib,self.selected)
    if not old then return end
    if #self.lib.bindings>=128 then self:notify('Достигнут лимит 128 сценариев.'); return end
    local b=model.copy(old); b.id=self.lib.next_id; b.name=b.name..' (копия)'; b.command='';b.command_alias=''
    b.shortcut={key=0,ctrl=false,alt=false,shift=false}
    self.selected=b.id; self.draft=b; self.cache={}; self.dirty=true; self.plan=nil; self.bindPane='editor'
    self:clearTextFocus(); self:clearSteps()
end
function Studio:moveBinding(offset,callbacks,id)
    id=id or self.selected
    local copy=model.copy(self.lib)
    for i,b in ipairs(copy.bindings) do if b.id==id then
        local n=i+offset
        if n>=1 and n<=#copy.bindings then
            copy.bindings[i],copy.bindings[n]=copy.bindings[n],copy.bindings[i]
            local ok,err=callbacks.save(copy); self:notify(err or '')
            if ok then self.lib=copy end
        end
        return
    end end
end
-- The card list is the only scrolling part of the left pane. Reserve the
-- complete measured toolbar before giving its remaining height to the cards.
function Studio:drawBindingList(ui,data,callbacks,search)
    local im=self.imgui; local gap=10
    local width=math.max(1,(im.GetContentRegionAvail().x-gap)/2)
    local rows={{'Дублировать##bind','Удалить##bind'},
        {'Экспорт всех биндов','Импорт биндов'},
        {'Экспорт выбранного бинда','Файлы обмена##bind-files'}}
    local font=self.buttonFont or im.GetFont(); local size=tonumber(font.FontSize)
    local heights,total={},10
    for i,row in ipairs(rows) do
        heights[i]=42
        for _,name in ipairs(row) do
            local visible=name:match('^(.-)##') or name
            heights[i]=math.max(heights[i],font:CalcTextSizeA(size,100000,math.max(1,width-28),visible).y+16)
        end
        total=total+heights[i]+gap
    end
    local height=math.max(1,im.GetContentRegionAvail().y-total)
    local origin=im.GetCursorScreenPos()
    child(self,ui,'bindrows##studio',0,height,function()
        for number,b in ipairs(self.lib.bindings) do
            if search=='' or model.casefold(b.name..' '..b.category..' '..b.command..' '..(b.command_alias or '')):find(search,1,true) then
                self:bindingRow(ui,data,callbacks,b,number,false)
            end
        end
    end,0,0,false)
    local reorder=self.reorderRequest; self.reorderRequest=nil
    if reorder then self:moveBinding(reorder.offset,callbacks,reorder.id) end
    local clicked={}
    local y=origin.y+height+10
    for i,row in ipairs(rows) do
        im.SetCursorScreenPos(im.ImVec2(origin.x,y))
        for column,name in ipairs(row) do
            if column==2 then im.SameLine(0,gap) end
            if menuModule.fittedButton(im,ui,name,im.ImVec2(width,heights[i]),self.buttonFont) then clicked[name]=true end
        end
        y=y+heights[i]+gap
    end
    if clicked['Дублировать##bind'] then self:duplicateBinding() end
    if clicked['Удалить##bind'] and self.selected then self.remove={kind='binding',id=self.selected} end
    if clicked['Экспорт всех биндов']then callbacks.export('binds')end
    if clicked['Импорт биндов']then callbacks.import('binds')end
    if clicked['Экспорт выбранного бинда']then
        if self.selected then callbacks.export('binds',self.selected)else self:notify('Выберите сохранённый бинд.')end
    end
    if clicked['Файлы обмена##bind-files']then
        self:notify('Бинды: config/police_assistant_2026_binds.json. Для обмена: police_assistant_2026_binds_exchange.json в той же папке. Экспортируется сохранённый текст; несохранённые правки сначала сохраните. Профиль, заметки, контакты и настройки в экспорт не входят. Для импорта замените файл обмена полученным JSON и нажмите «Импорт биндов».','binds',false,'info')
    end
end
function Studio:drawBindings(ui,data,callbacks)
    local im=self.imgui
    if self.pendingSelection and not self.draft then
        self.pendingSelection=nil; self.pendingEditorTab=nil; self.dirty=false
        self:clearTextFocus(); self:notify('Нет редактируемого сценария. Выберите бинд или создайте новый.')
    end
    local wide=im.GetContentRegionAvail().x>=730
    local headerWidth=math.max(1,(im.GetContentRegionAvail().x-10)/2)
    if self:button('+ Новый сценарий ( Добавить бинд )',ui,headerWidth) then self:createBinding() end
    im.SameLine(0,10)
    if self:button('Быстрое меню',ui,headerWidth) then callbacks.openQuick() end
    if not wide and self.bindPane=='editor' then
        if self:button('К списку биндов##bind-back',ui) then self.bindPane='list' end
        local height=math.max(1,im.GetContentRegionAvail().y)
        child(self,ui,'bindeditor##studio',0,height,function() self:drawEditor(ui,data,callbacks) end)
        return
    end
    local query=self:field('Поиск##library','search',self.query,256); self.query=query
    local search=model.casefold(query)
    if wide then ui.text('Выберите бинд слева, чтобы изменить его. Границу между списком и редактором можно перетаскивать.') end
    local panes=M.bindingPanels(im.GetContentRegionAvail().x,math.max(1,im.GetContentRegionAvail().y),self.bindRatio)
    local left,height=panes.wide and panes.left or panes.width,panes.height
    if panes.wide then
        local cursor=im.GetCursorScreenPos()
        im.SetCursorScreenPos(im.ImVec2(cursor.x+left,cursor.y))
        im.InvisibleButton('##bind-panel-divider',im.ImVec2(panes.gap,height))
        local active=im.IsItemActive()
        local hovered=im.IsItemHovered()
        if active or hovered then im.SetMouseCursor(im.MouseCursor.ResizeEW) end
        if active and core.finite(im.GetIO().MouseDelta.x) then
            left=math.max(260,math.min(panes.width-372,left+im.GetIO().MouseDelta.x))
            self.bindRatio=left/panes.width; panes.right=panes.width-left-panes.gap
        end
        im.GetWindowDrawList():AddLine(im.ImVec2(cursor.x+left+panes.gap/2,cursor.y+6),
            im.ImVec2(cursor.x+left+panes.gap/2,cursor.y+math.max(6,height-6)),
            im.ColorConvertFloat4ToU32(im.ImVec4(.30,.56,.73,(active or hovered) and .9 or .3)),2)
        im.SetCursorScreenPos(cursor)
    end
    child(self,ui,'bindlist##studio',left,height,function()
        self:drawBindingList(ui,data,callbacks,search)
    end,im.WindowFlags.NoScrollbar+im.WindowFlags.NoScrollWithMouse)
    if panes.wide then
        im.SameLine(0,panes.gap)
        child(self,ui,'bindeditor##studio',panes.right,height,function() self:drawEditor(ui,data,callbacks) end)
    end
end
function Studio:queueStatus(ui,data,callbacks)
    local q=data.queued
    if q then
        ui.text('Выполняется: '..q.plan.binding.name..' · шаг '..q.index..'/'..#q.plan.steps)
        if self:button('Остановить сценарий##running',ui) then callbacks.stop() end
    end
end
function Studio:drawQuick(ui,data,callbacks)
    self.currentUi=ui
    self.currentNoticeScope='quick'
    require('pa26_nearby').draw(self,ui,data,callbacks)
    local im=self.imgui
    self:queueStatus(ui,data,callbacks)
    if data.target then
        ui.text('Выбран: '..data.target.name..' ['..data.target.id..'] · '..(data.targetState and data.targetState.status or ''))
        if self:button('Снять выбор##target',ui) then callbacks.clearTarget() end
        if callbacks.openIdentity and self:button('IC-сведения о человеке##target-identity',ui)then callbacks.openIdentity()end
    end
    if self.confirmPlan then
        ui.text('Подготовленный сценарий ожидает подтверждения.')
        return
    end
    if self.quickWheelCategory then
        ui.text('Колесо → '..wheelModel.categoryName(self.quickWheelCategory,self.lib.settings.wheel_names))
        if self:button('Все бинды быстрого меню##quick-wheel-clear',ui) then self.quickWheelCategory=nil; self.quickSelected=nil end
    end
    local query=self:field('Найти сценарий##quick','quickSearch',self.quickQuery,256); self.quickQuery=query
    self.quickFavorites=self:check('Только избранные##quick',self.quickFavorites or false)
    ui.text(data.demo and 'ДЕМО · отправки в игру нет' or 'Реальный режим · команды проверяет сервер')
    local search=model.casefold(query); local count=0
    if self.quickWheelCategory then
        local state=model.copy(data.radioState or {});state.patrolSession=data.patrolSession
        local catalog=wheelModel.build(self.lib,0,true,state)
        local category=catalog and catalog.byCategory[self.quickWheelCategory]
        for _,item in ipairs(category and category.items or {})do
            if item.kind=='alert'or item.kind=='patrol'or item.kind=='assist'then
                local name=item.name:gsub('\n',' ')
                if search==''or model.casefold(name):find(search,1,true)then
                    count=count+1
                    if self:button(name..'##quick-system-'..item.id,ui)then
                        if item.disabled then self:notify(item.reason,'quick',false)else callbacks.navigateService(item.kind,item.id)end
                    end
                end
            end
        end
    end
    for _,item in ipairs(wheelModel.procedureItems(self.lib))do
        local included=self.quickWheelCategory and item.wheel_visible and item.category==self.quickWheelCategory or not self.quickWheelCategory and item.quick
        if included and(search==''or model.casefold(item.name):find(search,1,true))then
            count=count+1
            if self:button(item.name..'##quick-system-'..item.id,ui)then callbacks.navigateService(item.kind,item.id)end
        end
    end
    for number,b in ipairs(self.lib.bindings) do
        local included=self.quickWheelCategory and b.wheel_visible and wheelModel.groupFor(b,self.quickWheelProfile)==self.quickWheelCategory or
            not self.quickWheelCategory and b.quick
        if b.enabled and included and (not self.quickFavorites or b.favorite) and (search=='' or model.casefold(b.name..' '..b.category):find(search,1,true)) then
        count=count+1
        self:bindingRow(ui,data,callbacks,b,number,true)
        if self.quickSelected==b.id then
            local args=self:arguments(b,ui,'quick'..b.id)
            if im.Button(data.demo and 'Запустить в демо##run'..b.id or 'Запустить##run'..b.id) then callbacks.request({kind='prepare',binding=model.copy(b),args=args,start=true,returnTo='quick'}) end
        end
    end end
    if count==0 then ui.text(self.quickWheelCategory and 'В этой категории пока нет доступных действий. Проверьте флажок «В радиальном меню» у бинда.' or
        'Отметьте нужные сценарии «В быстром меню» в редакторе.') end
    self:drawNotice(ui)
    self:drawBindingInfo(ui,data,callbacks)
end
function Studio:drawNotes(ui,data,callbacks,floating)
    self.currentUi=ui
    self.currentNoticeScope='hints'
    local im=self.imgui
    if floating then self:queueStatus(ui,data,callbacks) end
    if not floating then
        if self:button('Экспорт всех заметок##notes-export',ui)then callbacks.export('notes')end
        if self:button('Импорт заметок##notes-import',ui)then callbacks.import('notes')end
        ui.text('Заметки хранятся отдельно: police_assistant_2026_notes.json. Файл обмена в config: police_assistant_2026_notes_exchange.json. Он содержит только сохранённые заметки. Для обмена одной заметкой выберите её и нажмите «Экспорт выбранной заметки».')
    end
    local query=self:field('Поиск памяток##tips','noteSearch','',256); local search=model.casefold(query)
    for _,note in ipairs(self.lib.notes) do if search=='' or model.casefold(note.name..' '..note.body):find(search,1,true) then
        local origin=im.GetCursorScreenPos();local width=math.max(1,im.GetContentRegionAvail().x-46)
        local font=self.buttonFont or im.GetFont();local size=tonumber(font.FontSize)
        local height=math.max(42,menuModule.labelLayout(font,size,math.max(1,width-28),note.name).height+16)
        im.PushStyleVarFloat(im.StyleVar.FrameRounding,12);ui.push(function()im.PopStyleVar(1)end)
        im.PushStyleColor(im.Col.Button,self.note==note.id and im.ImVec4(.09,.43,.62,.92)or im.ImVec4(.09,.23,.34,.86));ui.push(function()im.PopStyleColor(1)end)
        local clicked=menuModule.fittedButton(im,ui,label(note.name)..'##note'..note.id,im.ImVec2(width,height),font)
        ui.finish();ui.finish()
        if clicked then
            local id=note.id
            self:requestNavigation(function()self.note=id;self.noteMode=false;self.noteDraft=nil;self.cache['noteName']=nil;self.cache['noteBody']=nil end,'открыть другую памятку')
        end
        im.SetCursorScreenPos(im.ImVec2(origin.x+width+8,origin.y+(height-38)/2))
        if menuModule.starButton(im,ui,'note-favorite'..note.id,note.favorite,38)then
            local copy=model.copy(self.lib);for _,n in ipairs(copy.notes)do if n.id==note.id then n.favorite=not note.favorite end end
            local editCache=self.noteMode and self.cache
            local ok,err=callbacks.save(copy);if ok then self.lib=copy;if editCache then self.cache=editCache end else self:notify(err or'Не удалось сохранить избранное.')end
        end
        self:tooltip(ui,note.favorite and'Убрать памятку из избранного' or'Добавить памятку в избранное')
        im.SetCursorScreenPos(im.ImVec2(origin.x,origin.y+height+8))
    end end
    local selected; for _,n in ipairs(self.lib.notes) do if n.id==self.note then selected=n end end
    im.Separator()
    if selected then
        if self.noteMode then
            local draft=self.noteDraft
            if not draft or draft.id~=selected.id then draft={id=selected.id,name=selected.name,body=selected.body};self.noteDraft=draft end
            local name=self:field('Название##note','noteName',draft.name,256)
            local body=self:field('Текст##note','noteBody',draft.body,8193,true,260)
            draft.name=name;draft.body=body
            if self:button('Сохранить памятку',ui) then local copy=model.copy(self.lib); for _,n in ipairs(copy.notes) do if n.id==selected.id then n.name=name; n.body=body end end
                local ok,err=callbacks.save(copy); self:notify(err or (ok and 'Памятка сохранена.' or 'Не сохранено.'),nil,nil,ok and'info'or'warning'); if ok then self.lib=copy; self.noteMode=false;self.noteDraft=nil end end
            if im.Button('Отмена##note') then self.noteMode=false;self.noteDraft=nil; self.cache['noteName']=nil; self.cache['noteBody']=nil end
        else
            ui.text(selected.name); child(self,ui,'notebody##studio',0,math.max(120,im.GetContentRegionAvail().y-130),function() ui.text(selected.body) end)
            if im.Button('Редактировать##note') then self.noteMode=true end
            im.SameLine(); if im.Button('Удалить##note') then self.remove={kind='note',id=selected.id} end
            if not floating and self:button('Экспорт выбранной заметки##notes-export-one',ui)then callbacks.export('notes',selected.id)end
        end
    end
    if self:button('Добавить новую памятку',ui) then
        if self.noteMode then self:notify('Сначала сохраните или отмените редактирование памятки.'); return end
        local copy=model.copy(self.lib); local id=copy.next_note_id; copy.next_note_id=id+1; copy.notes[#copy.notes+1]={id=id,name='Новая памятка',body='Введите текст.',favorite=false}
        local ok,err=callbacks.save(copy); self:notify(err or ''); if ok then self.lib=copy; self.note=id; self.noteMode=true; self.cache['noteName']=nil; self.cache['noteBody']=nil end
    end
    if not floating and self:button('Открыть отдельное окно памяток',ui) then callbacks.openTips() end
    self:drawNotice(ui)
end
function Studio:drawPartners(ui,data,callbacks)
    ui.text('Здесь хранится постоянный список напарников по нику. Состав текущего экипажа выбирается в «Патруль и экипаж».')
    if self:button('Перейти к текущему патрулю и экипажу →##partners-patrol',ui)then callbacks.openPatrol()end
    self.partnerPage=self:choice('Напарники и служба##partners-page',self.partnerPage or 'contacts',{{'contacts','Контакты'},{'patrol','Патруль'},{'events','События'},{'vehicle','Транспорт'}},ui)
    if self.partnerPage=='vehicle'then vehicleUi.draw(self,ui,data,callbacks);return end
    if self.partnerPage=='patrol'then patrolUi.draw(self,ui,data,callbacks);return end
    if self.partnerPage=='events'then eventUi.draw(self,ui,data,callbacks);return end
    local im=self.imgui; local chosen
    for _,p in ipairs(self.lib.partners) do if im.Selectable(p.nickname..' · '..(p.callsign~='' and p.callsign or 'без позывного')..'##partner'..p.id,self.partner==p.id) then self.partner=p.id; self.cache['partnerNick']=nil; self.cache['partnerCall']=nil end; if p.id==self.partner then chosen=p end end
    im.Separator(); ui.text('Контакт хранится по нику; ID может меняться после переподключения.')
    local nick=self:field('Игровой ник##partner','partnerNick',chosen and chosen.nickname or '',64)
    local callsign=self:field('Позывной##partner','partnerCall',chosen and chosen.callsign or '',128)
    if self:button(chosen and 'Сохранить контакт' or 'Добавить контакт',ui) then local copy=model.copy(self.lib)
        if chosen then for _,p in ipairs(copy.partners) do if p.id==chosen.id then p.nickname=nick; p.callsign=callsign end end
        else copy.partners[#copy.partners+1]={id=copy.next_partner_id,nickname=nick,callsign=callsign}; copy.next_partner_id=copy.next_partner_id+1 end
        local ok,err=callbacks.save(copy); self:notify(err or ''); if ok then self.lib=copy; self.cache['partnerNick']=nil; self.cache['partnerCall']=nil; self.partner=nil end
    end
    if chosen and self:button('Удалить контакт',ui) then self.remove={kind='partner',id=chosen.id} end
    if chosen and self:button('Новый контакт',ui) then self.partner=nil; self.cache['partnerNick']=nil; self.cache['partnerCall']=nil end
    ui.text('Переменные team используют только выбранных напарников, которых ваш персонаж видит рядом в момент подготовки бинда.')
    self:drawNotice(ui)
end
function Studio:drawStats(ui,data,callbacks)
    self.statsPage=self:choice('История работы##stats-page',self.statsPage or'summary',{{'summary','Сводка и журнал биндов'},{'operations','Команды и ответы сервера'},{'system_log','Системный лог PA'}},ui)
    if self.statsPage=='operations'then return operationUi.draw(self,ui,data,callbacks)end
    if self.statsPage=='system_log'then if callbacks.systemLog then callbacks.systemLog()end;return end
    return self:drawStatsSummary(ui,data,callbacks)
end
function Studio:drawStatsSummary(ui,data,callbacks)
    local im=self.imgui; local j=data.journal
    self.statsScope=self:choice('Период##stats',self.statsScope,{{'all','За всё время'},{'today','Сегодня'},{'session','Текущий запуск'}},ui)
    local counts=self.statsScope=='today' and (j.data.days[os.date('%Y-%m-%d')] or {}) or self.statsScope=='session' and j.results or j.data.counters
    ui.text('Служебные результаты · подтверждено пользователем')
    local columns=im.GetContentRegionAvail().x>=520
    if columns then im.Columns(2,'service-stats##studio',false); ui.push(function() im.Columns(1) end) end
    for _,s in ipairs(model.stats) do if s[1]~='none' then ui.text(s[2]..': '..tostring(counts[s[1]] or 0)); if columns then im.NextColumn() end end end
    if columns then ui.finish() end
    eventUi.summary(self,ui,data,callbacks)
    im.Separator(); ui.text('Сценариев за запуск: '..j.session.runs..' · демо: '..j.session.demo..' · строк передано: '..j.session.sent..' · отменено: '..j.session.cancelled)
    local query=self:field('Поиск в журнале##stats','journalQuery','',256); local search=model.casefold(query)
    child(self,ui,'journal##studio',0,300,function()
        for i=#j.data.events,1,-1 do local e=j.data.events[i]
            if search=='' or model.casefold(e.name..' '..e.target..' '..e.reason):find(search,1,true) then
                ui.text(e.date..' · '..e.name..(e.demo and ' · ДЕМО' or '')..' · '..(e.status=='completed' and 'завершено' or 'отменено'))
                ui.text(e.target..' · строк передано: '..e.sent..(e.confirmed and ' · результат подтверждён' or ''))
                if e.knowledge then
                    local identity=({passport='Паспорт',appearance='Приметы',ooc='OOC'})[e.knowledge.identity]or e.knowledge.identity
                    ui.text((e.knowledge.personal_origin and'Из личной карточки: 'or'Шаблон из базы: ')..e.knowledge.reference..' · '..e.knowledge.catalog_version..' · '..identity)
                end
                if e.reason~='' then ui.text(e.reason) end
                if not e.demo and not e.confirmed and e.sent>0 and e.stat~='none' and im.Button('Подтвердить служебный результат##event'..e.id) then self.confirmResult=e.id end
                im.Separator()
            end
        end
    end)
    if self:button('Очистить журнал',ui) then self.reset='log' end
    if self:button('Обнулить служебную статистику',ui) then self.reset='stats' end
    self:drawNotice(ui)
end
function Studio:settingsHeading(ui,title,help,helpId)
    local im=self.imgui
    im.Dummy(im.ImVec2(0,6))
    if self.buttonFont then im.PushFont(self.buttonFont); ui.push(function() im.PopFont() end) end
    if help then
        local pos=im.GetCursorScreenPos();local width=im.GetContentRegionAvail().x
        im.SetCursorScreenPos(im.ImVec2(pos.x+math.max(0,width-34),pos.y))
        self:iconButton(ui,'settings-info-'..helpId,'info',26);self:tooltip(ui,help)
        im.SetCursorScreenPos(pos)
        im.PushTextWrapPos(im.GetCursorPosX()+math.max(1,width-46));ui.push(function()im.PopTextWrapPos()end)
        im.TextUnformatted(title);ui.finish()
    else ui.text(title)end
    if self.buttonFont then ui.finish() end
    im.Dummy(im.ImVec2(0,4))
end
function Studio:profileGroup(ui,copy,title,fields)
    local im=self.imgui
    self:settingsHeading(ui,title)
    local width=im.GetContentRegionAvail().x; local columns=width>=620 and 2 or 1
    if columns==2 then
        im.Columns(2,'profile-group-'..fields[1][1],false); ui.push(function() im.Columns(1) end)
        im.SetColumnWidth(0,width*.5)
    end
    for _,f in ipairs(fields) do
        copy.profile[f[1]]=self:field(f[2]..'##profile','profile:'..f[1],copy.profile[f[1]],512)
        if columns==2 then im.NextColumn() end
    end
    if columns==2 then ui.finish() end
    im.Dummy(im.ImVec2(0,8)); im.Separator()
end
function Studio:drawAlerts(ui,data,callbacks)
    ui.text('В репликах доступно {gender:передал|передала}; род выбирается в Профиле.')
    local im=self.imgui
    self.radioPage=self:choice('Настройки связи##radio-page',self.radioPage or 'emergency',
        {{'emergency','Shots fired · SOS · радиокоды','Экстренные','Здесь можно сообщить о стрельбе или ранении, запросить поддержку и отменить запрос. Перед отправкой PA попросит подтверждение.'},
            {'patrol','Патруль полиции и охрана тюрьмы','Патруль','Выберите режим службы, интервал и текст периодического доклада.'},
            {'automatic','Предупреждения и свои автодоклады','Автодоклады','Настройте напоминания об автодокладах или добавьте своё расписание.'}},ui)
    if self.radioPage=='automatic'then self.currentNoticeScope='radio_guard';self:drawRadioGuard(ui,data,callbacks);return end
    if self.radioPage=='patrol' then self.currentNoticeScope='patrol';self:drawPatrol(ui,data,callbacks);return end
    self.currentNoticeScope='alerts'
    self:settingsHeading(ui,'Связь · отдельные доклады')
    self:settingsHeading(ui,'Быстрый вызов с клавиатуры')
    for _,kind in ipairs(model.alertKinds)do
        local label=alertModule.kinds[kind].short
        ui.text(label..': '..model.shortcutName(self.lib.alert_shortcuts[kind]))
        if self:button('Назначить '..label..'##alert-key-'..kind,ui)then callbacks.capture({kind='feature',group='alert_shortcuts',field=kind})end
        if self:button('Отключить сочетание##alert-key-clear-'..kind,ui)then
            local copy=model.copy(self.lib);copy.alert_shortcuts[kind]={key=0,ctrl=false,alt=false,shift=false};local ok,err=callbacks.save(copy);if not ok then self:notify(err)end
        end
    end
    ui.text('Сочетание откроет подтверждение. Чтобы нажать кнопки мышью, удерживайте Alt.')
    local draft=self.alertDraft or model.copy(self.lib.alerts)
    local changed=false
    for _,spec in ipairs({{'enabled','Включить связь: доклады и SOS'},{'on_duty','На службе · автофункции PA'},
        {'shots_enabled','Включить Shots fired'},{'sos_enabled','Включить SOS'},{'code0_enabled','Включить CODE 0'},
        {'code1_enabled','Включить CODE 1 · отмена CODE 0'},{'code4_enabled','Включить CODE 4 · помощь не нужна'},
        {'auto_shots','Предлагать Shots fired при попадании'},{'auto_code0','Предлагать CODE 0 при критическом ранении'},
        {'include_sd','Учитывать SD Pistol в Shots fired (Exsellent: тайзер)'}}) do
        local value,edit=self:check(spec[2]..'##alerts-'..spec[1],draft[spec[1]])
        if edit then draft[spec[1]]=value;changed=true end
    end
    local channel,edit=self:choice('IC-канал##alerts-channel',draft.channel,require('pa26_server_commands').radioChoices,ui)
    if edit then draft.channel=channel;changed=true end
    for _,spec in ipairs({{'shots','Доклад о стрельбе'},{'sos','Запрос поддержки'},{'code0','Критическое ранение'},
        {'code1','CODE 1 · отмена ранее переданного CODE 0'},{'code4','CODE 4 · помощь больше не требуется'}}) do
        self:settingsHeading(ui,spec[2])
        local key=spec[1]..'_channel';local value,edit=self:choice('Канал##alerts-'..key,draft[key],
            {{'','Общий канал'},{'/r','/r · подразделение'},{'/f','/f · организация'},{'/d','/d · департамент'}},ui)
        if edit then draft[key]=value;changed=true end
        key=spec[1]..'_template';value=self:field('Текст##alerts-template-'..key,'alert:'..key,draft[key],2048,true,88)
        if value~=draft[key] then draft[key]=value;changed=true end
        self:radioPreview(ui,data,draft,spec[1])
        if spec[1]=='sos'then
            self:settingsHeading(ui,'Дополнительная серверная команда помощи',
                'Команду помощи нужно сначала проверить в игровом /help. Затем впишите её ниже и укажите, где проверили. При запросе SOS PA покажет её вместе с докладом и отправит после рации с заданной паузой. Без вашего ДА отправки не будет.','sos-help-command')
            for _,row in ipairs({{'help_enabled','Добавлять команду помощи к SOS'},{'help_verified','Я проверил название и параметры на сервере'}})do
                local value,edit=self:check(row[2]..'##alerts-'..row[1],draft[row[1]])
                if edit then draft[row[1]]=value;changed=true end
            end
            for _,row in ipairs({{'help_command','Команда помощи из /help'},{'help_source','Где и когда проверено'}})do
                local value=self:field(row[2]..'##alerts-'..row[1],'alert:'..row[1],draft[row[1]],1024)
                if value~=draft[row[1]]then draft[row[1]]=value;changed=true end
            end
            local delay=im.new.int(draft.help_delay_ms)
            if im.InputInt('Пауза до команды помощи, мс##alerts-help-delay',delay)then draft.help_delay_ms=delay[0];changed=true end
            ui.text('Допустимая пауза — 1000–10000 мс. Можно использовать переменные доклада, перечисленные ниже. Отметьте проверку только после того, как сами убедитесь, что команда работает.')
        end
    end
    ui.text('Подстановки: {area}, {location}, {local_tag}, {prison_tag}, {global_tag}, {callsign}, {city}, {square}, {map_square}, {my_name}, {department}, {rank}, {post}.')
    ui.text('Квадрат рядом с районом и формат места настраиваются в «Настройки → Карта». В докладах {area} дополняется квадратом, если в шаблоне ещё нет явного {square}, {map_square} или {location}. В биндах {area} остаётся районом.')
    self:settingsHeading(ui,'Поля начатого патруля',
        'Данные патруля: {officer} — ваше игровое имя; {unit} — обозначение экипажа; {station} — станция; {vehicle} — машина; {sector} — сектор; {crew} — имена напарников; {crew_count} — число участников; {crew_roles} — состав с ролями; {crew_callsigns} — позывные; {duration} — время патруля; {patrol_id} — номер патруля в PA. Эти значения доступны после начала патруля. Если состав изменится, старый доклад потребуется проверить заново.','radio-patrol-variables')
    ui.text('Shots fired — сообщение о попадании по вашему персонажу. SOS — отдельный запрос поддержки (10-70). ДА отправляет выбранный доклад; НЕТ или истечение времени отменяет его.')
    ui.text('CODE 0 — сообщение о тяжёлом ранении. PA предложит его после попадания из огнестрельного оружия, если здоровье действительно уменьшилось. Урон по броне, падение и тайзер не вызывают это предложение.')
    ui.text('CODE 1 отменяет ранее переданный CODE 0, а CODE 4 сообщает, что помощь больше не нужна. Вы отправляете их вручную и каждый раз подтверждаете текст. Эти доклады не завершают патруль и не снимают розыск.')
    if not data.chatFiltersAvailable then ui.text('События урона недоступны: работают ручные кнопки связи.') end
    local cooldown=im.new.int(draft.cooldown_ms/1000)
    if im.SliderInt('Повторный доклад, с##alerts-cooldown',cooldown,1,120) then draft.cooldown_ms=cooldown[0]*1000;changed=true end
    local timeout=im.new.int(draft.timeout_ms/1000)
    if im.SliderInt('Время подтверждения, с##alerts-timeout',timeout,1,30) then draft.timeout_ms=timeout[0]*1000;changed=true end
    local health=im.new.int(draft.code0_health)
    if im.SliderInt('Критический HP ≤##alerts-health',health,5,50) then draft.code0_health=health[0];changed=true end
    if changed then self.alertDraft=draft end
    self:autoSettings('alerts',{'alerts'},draft,'alertDraft')
    self:autosaveHint(ui,'alerts')
    if self:button('Открыть Shots fired##alerts-shots',ui) then callbacks.alert('shots') end
    if self:button('Открыть SOS##alerts-sos',ui) then callbacks.alert('sos') end
    if self:button('Открыть CODE 0##alerts-code0',ui) then callbacks.alert('code0') end
    if self:button('Открыть CODE 1##alerts-code1',ui) then callbacks.alert('code1') end
    if self:button('Открыть CODE 4##alerts-code4',ui) then callbacks.alert('code4') end
    ui.text('Предпросмотр использует сохранённые настройки. Отметку «На службе» нужно включить самостоятельно: PA не определяет вашу фракцию и должность.')
    self:drawNotice(ui)
end
function Studio:clearPreferenceCache(prefix)
    for key in pairs(self.cache) do if key:sub(1,#prefix)==prefix then self.cache[key]=nil end end
end
function Studio:radioPreview(ui,data,draft,kind)
    if not data.codec then return end
    local state=model.copy(data.radioState or {})
    state.session=state.session or 'preview';state.ped=state.ped or 0;state.demo=true
    if kind=='police'or kind=='prison'or not state.post or state.post==''then state.post=draft.patrol.post end
    state.health=draft.code0_health
    local plan,err=alertModule.prepare(kind,state,draft,data.codec,self.now(),0)
    if plan then
        for i,line in ipairs(plan.lines)do ui.text('Предпросмотр '..i..' · '..#plan.wire[i]..' / '..core.WIRE_LIMIT..' байт');ui.text(line)end
        if #plan.lines>1 then ui.text('Длинный текст будет передан частями; общий интервал отправки PA сохраняется.')end
        if kind=='sos'and draft.help_enabled then ui.text('До дополнительной команды помощи: '..draft.help_delay_ms..' мс; общий интервал отправки PA также действует.')end
    else ui.text('Проверьте доклад: '..tostring(err))end
end
function Studio:drawRadioGuard(ui,data,callbacks)
    local im=self.imgui;local d=self.radioGuardDraft or model.copy(self.lib.radio_guard);local changed=false
    self:settingsHeading(ui,'Предупреждения перед автодокладами')
    ui.text('Все автодоклады используют общую очередь. Время предупреждения и полной карточки задаётся ниже, от 1 секунды. Если интервал доклада короче предупреждения, оно сокращается до интервала; отмена остаётся доступной.')
    local value=im.new.int(d.lead_ms/1000)
    if im.SliderInt('Предупредить заранее, с##guard-lead',value,1,120)then d.lead_ms=value[0]*1000;changed=true end
    value=im.new.int(d.toast_ms/1000)
    if im.SliderInt('Полное уведомление, с##guard-toast',value,1,20)then d.toast_ms=value[0]*1000;changed=true end
    ui.text('Пропустить ближайший: '..model.shortcutName(d.skip_shortcut)..' · /pa26skip')
    if self:button('Назначить сочетание отмены##guard-key',ui)then callbacks.capture({kind='feature',group='radio_guard',field='skip_shortcut'})end
    im.SameLine();if self:button('Убрать##guard-key',ui)then d.skip_shortcut={key=0,ctrl=false,alt=false,shift=false};changed=true end
    ui.text('Пока вы печатаете или игра неактивна, таймер стоит на паузе. После возвращения PA предупредит снова. Экстренные подтверждения Y/N идут первыми. Отмена пропускает один доклад; выключение расписания останавливает следующие.')
    self:settingsHeading(ui,'Длинные доклады')
    local split,splitChanged=self:check('Делить длинные доклады на строки##guard-split',d.split_enabled)
    if splitChanged then d.split_enabled=split;changed=true end
    local maxLines=im.new.int(d.max_lines);if im.InputInt('Максимум строк в докладе##guard-max-lines',maxLines)then d.max_lines=maxLines[0];changed=true end
    local continuation=self:field('Начало продолжения##guard-continuation','guard:continuation',d.continuation,256)
    if continuation~=d.continuation then d.continuation=continuation;changed=true end
    ui.text('Длинный доклад делится по словам так, чтобы части помещались в чат. В предпросмотре видны все части. Между отправками действует общий интервал; остаток можно отменить.')
    self:settingsHeading(ui,'Свои автодоклады')
    if self:button('+ Новый автодоклад##guard-new',ui)and #d.custom<16 then
        local id=d.next_id;d.next_id=id+1
        d.custom[#d.custom+1]={id=id,name='Новый автодоклад',enabled=false,confirmation=false,interval_ms=600000,channel='/r',
            template='{local_tag}Продолжаю службу. 10-20: {area}.'}
        self.autoReportId=tostring(id);changed=true
    end
    if #d.custom==0 then ui.text('Укажите текст, канал и периодичность. Новый доклад начнёт работать только после включения его переключателя.')
    else
        local choices={};local found
        for i,r in ipairs(d.custom)do choices[#choices+1]={tostring(r.id),string.format('%02d',i)..' · '..r.name};if tostring(r.id)==self.autoReportId then found=r end end
        self.autoReportId=self:choice('Доклад##guard-report',found and self.autoReportId or choices[1][1],choices,ui)
        local r;for _,row in ipairs(d.custom)do if tostring(row.id)==self.autoReportId then r=row;break end end
        local prefix='auto:'..r.id..':'
        local name=self:field('Название##guard-name',prefix..'name',r.name,256);if name~=r.name then r.name=name;changed=true end
        local v,edit=self:check('Включить расписание##guard-enabled',r.enabled);if edit then r.enabled=v;changed=true end
        v,edit=self:check('Каждый раз подтверждать Y / N##guard-confirmation',r.confirmation);if edit then r.confirmation=v;changed=true end
        value=im.new.int(r.interval_ms/1000);if im.InputInt('Интервал, с##guard-interval',value)then r.interval_ms=value[0]*1000;changed=true end
        ui.text('От 1 до 3600 секунд. Для короткого интервала предупреждение сокращается до его длительности. Предпросмотр и отмена сохраняются; общая очередь может задержать отправку.')
        v,edit=self:choice('Канал##guard-channel',r.channel,require('pa26_server_commands').radioChoices,ui);if edit then r.channel=v;changed=true end
        v=self:field('Текст доклада##guard-template',prefix..'template',r.template,2048,true,88);if v~=r.template then r.template=v;changed=true end
        ui.text('{area}, {location}, {my_name}, {callsign}, {department}, {rank}, {local_tag}, {prison_tag}, {global_tag}, {city}, {square}, {map_square}, {post}. Пост задаётся в периодических докладах; личные поля — в профиле.')
        if data.radioState and data.codec then
            local p,err=require('pa26_radio_guard').prepare(r,data.radioState,data.codec,self.now(),0)
            if p then for i,line in ipairs(p.lines)do ui.text('Предпросмотр '..i..': '..line..' · '..#p.wire[i]..' / 127 байт')end
            else ui.text('Проверьте доклад: '..tostring(err))end
        end
        if self:button('Удалить##guard-delete',ui)then self.radioGuardDraft=d;self.customRemove={id=r.id,name=r.name,owner=d}end
    end
    if changed then self.radioGuardDraft=d end
    self:autoSettings('radio_guard',{'radio_guard'},d,'radioGuardDraft')
    self:autosaveHint(ui,'radio_guard')
    if data.autoReport and data.autoReport.visible then
        ui.text('Предстоит: '..data.autoReport.name)
        if self:button('Пропустить ближайший доклад##guard-skip',ui)then callbacks.skipReport()end
    end
    ui.text('Для автодокладов включите связь и отметку «На службе». В деморежиме PA показывает уведомления и готовые строки, ничего не отправляя в игру.')
    self:drawNotice(ui)
end
function Studio:drawWeaponWarning(ui,data,callbacks)
    local im=self.imgui;local d=self.warningDraft or model.copy(self.lib.weapon_warning);local changed=false
    self:settingsHeading(ui,'Предупреждение перед применением оружия',
        'Если удерживать прицел в течение заданного времени, PA предложит предупредить об оружии. Наводиться на человека необязательно. Когда режим камеры недоступен, PA проверяет наведение на игрока. Текст отправится только после вашей кнопки или сочетания. Все условия можно изменить ниже.','weapon-warning')
    local v,edit=self:check('Показывать напоминание об оружии##warning-enabled',d.enabled);if edit then d.enabled=v;changed=true end
    v,edit=self:choice('Показ##warning-mode',d.mode,{{'toast','Уведомление с кнопкой и сочетанием','Уведомление'},{'confirm','Карточка Y / N','ДА / НЕТ'}},ui);if edit then d.mode=v;changed=true end
    v,edit=self:choice('Когда напоминать##warning-trigger',d.trigger,{{'aim','При непрерывном прицеливании','В прицеле'},{'stable','После выбора оружия','Оружие в руках'},{'draw','После отыгровки доставания','После отыгровки'}},ui);if edit then d.trigger=v;changed=true end
    for _,sp in ipairs({{'delay_ms',d.trigger=='aim' and 'Непрерывно в прицеле, с' or 'Оружие в руках, с',1,30},{'toast_ms','Напоминание видно, с',1,30},
        {'cooldown_ms','Между напоминаниями, с',1,120},{'remember_ms','Помнить предупреждение, с',1,600}})do
        local p=im.new.int(d[sp[1]]/1000);if im.SliderInt(sp[2]..'##warning-'..sp[1],p,sp[3],sp[4])then d[sp[1]]=p[0]*1000;changed=true end
    end
    v,edit=self:choice('Речь##warning-channel',d.channel,{{'/s','Крик · /s'},{'','Обычная речь'}},ui);if edit then d.channel=v;changed=true end
    v,edit=self:check('Без акцента##warning-no-accent',d.no_accent);if edit then d.no_accent=v;changed=true end
    self:settingsHeading(ui,'Что говорить')
    ui.text('Введите обе реплики без команды /s. Переменная {weapon} подставит название выбранного оружия.')
    for _,sp in ipairs({{'taser','Тайзер'},{'firearm','Огнестрельное оружие'}})do
        local key=sp[1]..'_template';v=self:field('Предупреждение: '..sp[2]..'##warning-'..key,'warning:'..key,d[key],2048,true,76)
        if v~=d[key]then d[key]=v;changed=true end
        local preview=model.applyAccent(core.expandGender(d[key],self.lib.profile.gender),d.no_accent and''or self.lib.profile.accent)
        require('pa26_rp_ui').preview(self,ui,data,(d.channel~=''and d.channel..' 'or '')..(preview or d[key]),'Предпросмотр')
    end
    ui.text('Сочетание: '..model.shortcutName(d.shortcut)..' · /pa26warn открывает напоминание, не произносит реплику.')
    if self:button('Назначить сочетание предупреждения##warning-key',ui)then callbacks.capture({kind='feature',group='weapon_warning',field='shortcut'})end
    im.SameLine();if self:button('Убрать##warning-key',ui)then d.shortcut={key=0,ctrl=false,alt=false,shift=false};changed=true end
    local ids={};for key in pairs(d.items)do ids[#ids+1]=tonumber(key)end;table.sort(ids)
    for _,id in ipairs(ids)do
        local key=tostring(id);v,edit=self:check(preferences.weaponName(self.lib.weapons,id)..'##warning-weapon-'..key,d.items[key])
        if edit then d.items[key]=v;changed=true end
    end
    ui.text('Текст отправится после нажатия кнопки, сочетания или ДА. НЕТ и истечение времени отменяют предупреждение. Если очередь занята, PA подождёт. Смена оружия или цели, а также открытый чат отменяют устаревшее подтверждение.')
    ui.text('Отсчёт идёт, пока вы удерживаете прицел; смотреть на человека необязательно. Если режим камеры недоступен, нужно навести оружие на игрока. Отпускание прицела, открытие меню или смена оружия запускают отсчёт заново. На одно удержание появляется одно напоминание. Уже показанное напоминание можно подтвердить и после отпускания прицела.')
    ui.text('Напоминание работает при включённой отметке «На службе». Допустимость применения оружия зависит от ситуации и правил сервера.')
    if changed then self.warningDraft=d end
    self:autoSettings('weapon_warning',{'weapon_warning'},d,'warningDraft')
    self:autosaveHint(ui,'weapon_warning')
    if self:button('Показать напоминание##warning-test',ui)then callbacks.warnWeapon()end
    self:drawNotice(ui)
end
function Studio:drawPatrol(ui,data,callbacks)
    if self:button('Открыть сеанс патруля и экипаж##patrol-session-open',ui)then callbacks.openPatrol()end
    local im=self.imgui;local draft=self.patrolDraft or model.copy(self.lib.alerts.patrol);local changed=false
    self:settingsHeading(ui,'Периодические доклады')
    for _,spec in ipairs({{'enabled','Включить периодические доклады'},{'confirmation','Подтверждать каждый доклад Y / N'},{'hud','Показывать время до доклада в HUD'}}) do
        local value,edit=self:check(spec[2]..'##patrol-'..spec[1],draft[spec[1]]);if edit then draft[spec[1]]=value;changed=true end
    end
    local mode,edit=self:choice('Служба##patrol-mode',draft.mode,{{'police','Патруль полиции'},{'prison','Охрана тюрьмы'}},ui)
    if edit then draft.mode=mode;changed=true end
    ui.text('Включите этот режим и отметку «На службе» в настройках связи. Если убрать подтверждение, PA будет автоматически отправлять один доклад за выбранный интервал.')
    ui.text('Пауза игры, открытый чат, серверные окна и потеря фокуса приостанавливают таймер. Текущий сценарий и экстренные доклады отправляются первыми.')
    for _,kind in ipairs({'police','prison'}) do
        self:settingsHeading(ui,kind=='police' and 'Патруль полиции' or 'Охрана тюрьмы')
        local key=kind..'_interval_ms';local seconds=im.new.int(draft[key]/1000)
        if im.InputInt('Интервал, с##patrol-'..kind,seconds) then draft[key]=seconds[0]*1000;changed=true end
        ui.text('От 1 до 3600 секунд. После смены режима или интервала отсчёт начинается заново.')
        key=kind..'_channel';local value,edit=self:choice('Канал##patrol-'..kind,draft[key],require('pa26_server_commands').radioChoices,ui)
        if edit then draft[key]=value;changed=true end
        key=kind..'_template';value=self:field('Текст доклада##patrol-'..kind,'patrol:'..key,draft[key],2048)
        if value~=draft[key] then draft[key]=value;changed=true end
    end
    local post=self:field('Пост тюрьмы · вручную##patrol-post','patrol:post',draft.post,512)
    if post~=draft.post then draft.post=post;changed=true end
    ui.text('В докладе охраны {post} означает ваш пост, а {prison_tag} — префикс из профиля. Пост и фракцию нужно указать самостоятельно: PA не определяет их по месту нахождения.')
    local radio=model.copy(self.lib.alerts);radio.patrol=draft
    self:radioPreview(ui,data,radio,draft.mode)
    if changed then self.patrolDraft=draft end
    self:autoSettings('patrol',{'alerts','patrol'},draft,'patrolDraft')
    self:autosaveHint(ui,'patrol')
    self:drawNotice(ui)
end
function Studio:drawWeapons(ui,data,callbacks)
    ui.text('В текстах доступно {gender:достал|достала}; род выбирается в Профиле. Предпросмотр показывает готовую реплику.')
    self.weaponPage=self:choice('Снаряжение##weapons-page',self.weaponPage or 'draw',
        {{'draw','Отыгрывание оружия · одиночные /me','Отыгрывание оружия','Выберите оружие, отредактируйте его название и отыгровки. Задержки ниже помогут избежать лишних повторов.'},
            {'taser','Тайзер · выстрелы, таймер и перезарядка','Тайзер','Заряды, отсчёт после выстрела и редактируемая RP-перезарядка.'},
            {'warning','Предупреждения · текст и показ','Предупреждения','Настройте предупреждения для тайзера и огнестрельного оружия: текст, время прицеливания и способ подтверждения.'}},ui)
    if self.weaponPage=='warning'then self.currentNoticeScope='weapon_warning';self:drawWeaponWarning(ui,data,callbacks);return end
    if self.weaponPage=='taser' then self.currentNoticeScope='taser';self:drawTaser(ui,data,callbacks);return end
    self.currentNoticeScope='weapons'
    local im=self.imgui;local draft=self.weaponDraft or model.copy(self.lib.weapons);local changed=false
    self:settingsHeading(ui,'Автоматические отыгровки оружия')
    local value,edit=self:check('Включить отыгровку доставания##weapons-enabled',draft.enabled)
    if edit then draft.enabled=value;changed=true end
    for _,spec in ipairs({{'delay_ms','Оружие в руках, с',1,30},{'cooldown_ms','Между отыгровками, с',1,120},{'repeat_ms','Повтор одного оружия, с',1,300}}) do
        local seconds=im.new.int(draft[spec[1]]/1000)
        if im.SliderInt(spec[2]..'##weapons-'..spec[1],seconds,spec[3],spec[4]) then draft[spec[1]]=seconds[0]*1000;changed=true end
    end
    local holster,holsterChanged=self:check('Отыгрывать убирание оружия##weapons-holster',draft.holster_enabled)
    if holsterChanged then draft.holster_enabled=holster;changed=true end
    local holsterDelay=im.new.int(draft.holster_delay_ms);if im.InputInt('Убирание после смены, мс##weapons-holster-delay',holsterDelay)then draft.holster_delay_ms=holsterDelay[0];changed=true end
    ui.text('Реплика об убирании появляется, только если PA уже отыграл доставание этого оружия. Если сразу взять его снова, реплика отменится. Для гранат убирание по умолчанию выключено.')
    ui.text('После смены оружия PA ждёт заданное время. Если вы снова смените оружие или очередь занята, устаревшая реплика отменится. Оружие, которое уже было в руках при запуске PA, не отыгрывается.')
    ui.text('Для автоматических /me включите отметку «На службе» в настройках связи.')
    local choices={};local checked=0
    for _,row in ipairs(preferences.weaponCatalog) do local key=tostring(row[1]);local item=draft.items[key]
        choices[#choices+1]={key,item.name..' · GTA ID '..key};if item.enabled then checked=checked+1 end
    end
    ui.text('Выбрано оружий: '..checked..' / '..#choices)
    self.weaponEdit=self:choice('Изменить оружие##weapon-edit',self.weaponEdit or '23',choices,ui)
    local key=self.weaponEdit;local item=draft.items[key]
    if key=='16' or key=='17' then
        local preset,edit=self:choice('Назначить проверенный тип гранаты##grenade-preset','current',
            {{'current','Сохранить текущие название и текст'},{'gas','Газовая граната'},{'smoke','Дымовая граната'},{'flash','Светошумовая граната'}},ui)
        if edit and preferences.grenadePresets[preset] then
            local p=preferences.grenadePresets[preset];item.name=p.name;item.template=p.template
            self.cache['weapon:name:'..key]=nil;self.cache['weapon:text:'..key]=nil;changed=true
        end
    end
    value,edit=self:check('Отыгрывать это оружие##weapon-picked',item.enabled);if edit then item.enabled=value;changed=true end
    value=self:field('Название для переменных и /me##weapon-name','weapon:name:'..key,item.name,256)
    if value~=item.name then item.name=value;changed=true end
    value=self:field('Одна реплика /me · без /me в начале##weapon-text','weapon:text:'..key,item.template,2048,true,96)
    if value~=item.template then item.template=value;changed=true end
    local h,he=self:check('Отыгрывать убирание этого оружия##weapon-holster',item.holster_enabled);if he then item.holster_enabled=h;changed=true end
    local ht=self:field('Одна /me при убирании · без /me##weapon-holster-text','weapon:holster:'..key,item.holster_template,2048,true,72)
    if ht~=item.holster_template then item.holster_template=ht;changed=true end
    require('pa26_rp_ui').preview(self,ui,data,'/me '..item.holster_template:gsub('{weapon}',function()return item.name end),'Убирание')
    local expanded=item.template:gsub('{weapon}',function()return item.name end)
    require('pa26_rp_ui').preview(self,ui,data,'/me '..expanded)
    if self:button('Настроить перенос /me и /do##weapon-rp-settings',ui)then if callbacks.openSettings then callbacks.openSettings('chat','split')else callbacks.openAssist('roleplay')end end
    ui.text('В справке сервера указан /taser, который применяется с Deagle в руках. Прежнее имя /tazer сохранено в старых профилях. Оружие с ID 23 — обычный SD Pistol, а ID 17 — газовая граната. Меняйте эти назначения только после проверки предметов на сервере.')
    child(self,ui,'weapon-checklist##preferences',0,220,function()
        for _,row in ipairs(preferences.weaponCatalog) do local key=tostring(row[1]);local item=draft.items[key]
            local value,edit=self:check('ID '..key..'##weapon-check-'..key,item.enabled)
            im.SameLine();ui.text(item.name)
            if edit then item.enabled=value;changed=true end
        end
    end)
    if changed then self.weaponDraft=draft end
    self:autoSettings('weapons',{'weapons'},draft,'weaponDraft')
    self:autosaveHint(ui,'weapons')
    self:drawNotice(ui)
end
function Studio:drawTaser(ui,data,callbacks)
    local im=self.imgui;local draft=self.taserDraft or model.copy(self.lib.taser);local changed=false
    self:settingsHeading(ui,'Тайзер · серверный режим и учёт выстрелов')
    local activation,activationChanged=self:choice('Определение тайзера##taser-activation',draft.activation,{{'command','Команда сервера · Deagle'},{'weapon','Отдельный GTA ID · другой профиль'}},ui)
    if activationChanged then draft.activation=activation;changed=true end
    if self:button('Применить профиль Exsellent: /taser + Deagle##taser-exsellent',ui)then draft.activation='command';draft.command='/taser';draft.weapon_id=24;changed=true end
    for _,row in ipairs({{'command','Команда включения / выключения'},{'name','Название тайзера'},{'active_reply','Точный ответ: тайзер включён'},{'inactive_reply','Точный ответ: тайзер выключен'},
        {'draw_template','/me: достать тайзер · без /me'},{'holster_template','/me: убрать тайзер · без /me'}})do
        local value=self:field(row[2]..'##taser-mode-'..row[1],'taser:mode:'..row[1],draft[row[1]],2048,true,64)
        if value~=draft[row[1]]then draft[row[1]]=value;changed=true end
    end
    local reply=im.new.int(draft.reply_timeout_ms);if im.InputInt('Ожидание ответа сервера, мс##taser-reply-timeout',reply)then draft.reply_timeout_ms=reply[0];changed=true end
    ui.text('Команда сама по себе ещё не подтверждает включение тайзера. Пока ответы сервера неизвестны, оставьте поля ниже пустыми и отмечайте режим вручную. Обычные выстрелы Deagle не учитываются как выстрелы тайзера. Переключение режима не восстанавливает заряды.')
    require('pa26_rp_ui').preview(self,ui,data,'/me '..draft.draw_template:gsub('{weapon}',function()return draft.name end),'Доставание')
    require('pa26_rp_ui').preview(self,ui,data,'/me '..draft.holster_template:gsub('{weapon}',function()return draft.name end),'Убирание')
    ui.text('В игровой справке указан /taser. Если у вас сохранено другое имя, замените его вручную после проверки.')
    if draft.command~='/taser'and self:button('Взять /taser из справки##taser-server-name',ui)then draft.command='/taser';self:clearPreferenceCache('taser:mode:command');changed=true end
    if draft.activation=='command'then
        if self:button('Подтверждаю: тайзер включён##taser-mode-on',ui)and callbacks.taserMode then callbacks.taserMode(true)end
        if self:button('Подтверждаю: обычный Deagle##taser-mode-off',ui)and callbacks.taserMode then callbacks.taserMode(false)end
        ui.text('Текущий режим: '..((data.taser or {}).mode or 'не подтверждён'))
    end
    for _,spec in ipairs({{'enabled','Включить учёт тайзера'},{'hud','Виджет тайзера рядом с HUD'},{'auto_reload','Автоматическая RP-перезарядка'}}) do
        local value,edit=self:check(spec[2]..'##taser-'..spec[1],draft[spec[1]]);if edit then draft[spec[1]]=value;changed=true end
    end
    local seconds=im.new.int(draft.cooldown_ms/1000)
    if im.SliderInt('Между выстрелами, с##taser-cooldown',seconds,1,15) then draft.cooldown_ms=seconds[0]*1000;changed=true end
    local id=im.new.int(draft.weapon_id)
    if im.InputInt('GTA ID оружия · Deagle: 24##taser-id',id) then draft.weapon_id=id[0];changed=true end
    local capacity=im.new.int(draft.capacity)
    if im.InputInt('RP-выстрелов до перезарядки##taser-capacity',capacity)then draft.capacity=capacity[0];changed=true end
    self:settingsHeading(ui,'Лимит RP-выстрелов',
        'Для профиля EPD по прочитанным правилам оставьте 2 заряда. Значения 1–10 предназначены для других профилей и не меняют патроны GTA. Если вы уже стреляли, новая ёмкость начнёт действовать после отыгровки перезарядки.','taser-capacity-info')
    local value=self:field('Одна /me для перезарядки · без /me##taser-reload','taser:reload',draft.reload_template,2048,true,96)
    if value~=draft.reload_template then draft.reload_template=value;changed=true end
    require('pa26_rp_ui').preview(self,ui,data,'/me '..draft.reload_template)
    ui.text('Счётчик учитывает ваши выстрелы, включая промахи. Он отражает заряды по выбранному RP-профилю, а не патроны GTA. Смена оружия его не обнуляет.')
    ui.text('Когда заряды закончатся, PA дождётся свободной очереди и отправит отыгровку перезарядки. Готовность вернётся после отправки всех её частей и заданной паузы. Если отправка не удалась, повтор нужно запустить вручную.')
    ui.text('Для автоматической перезарядки включите «На службе». Повторить её вручную можно командой /pa26reload или кнопкой на виджете.')
    ui.text('PA не блокирует выстрелы и не меняет патроны. Перед применением тайзера учитывайте требование о предупреждении, допустимую дистанцию и ограничения сервера.')
    if not data.chatFiltersAvailable then ui.text('SAMP.Lua недоступна: автоматический подсчёт выстрелов не работает.')end
    if changed then self.taserDraft=draft end
    self:autoSettings('taser',{'taser'},draft,'taserDraft')
    self:autosaveHint(ui,'taser')
    self:drawNotice(ui)
end
function Studio:drawProfile(ui,data,callbacks,part)
    part=part or 'all'
    local copy=model.copy(self.lib);local im=self.imgui;copy.profile=self.profileDraft or model.copy(copy.profile)
    if part=='profile'or part=='all'then
    ui.text('Данные персонажа и службы. Изменения сохраняются автоматически.')
    self:profileGroup(ui,copy,'Персонаж и служба',{{'name','RP-имя'},{'department','Ведомство'},{'rank','Должность'},{'case_number','Личное дело'}})
    self:profileGroup(ui,copy,'Экипаж и рация',{{'callsign','Позывной экипажа'},{'local_tag','Префикс локальной волны'},
        {'global_tag','Префикс общей волны'},{'prison_tag','Префикс тюремной волны'}})
    self:profileGroup(ui,copy,'Место и транспорт · ручные значения',{{'city','Город (вручную)'},{'square','Сектор патруля (вручную)'},
        {'my_plate','Свой номер авто (вручную)'},{'select_plate','Номер выбранной машины (вручную)'},{'closest_plate','Номер ближайшей машины (вручную)'}})
    copy.profile.gender=self:choice('Грамматический род',copy.profile.gender,{{'male','Мужской'},{'female','Женский'}},ui)
    copy.profile.timezone=self:choice('Часы в биндах',copy.profile.timezone,{{'local','Компьютер'},{'utc','UTC'},{'moscow','Москва (UTC+3)'}},ui)
    local grid=model.copy((self.autosaves and self.autosaves.map_grid and self.autosaves.map_grid.value)or self.lib.map_grid)
    local auto,changed=self:check('Автозаполнение {square} квадратом карты##profile-auto-square',grid.auto_square)
    if changed then grid.auto_square=auto;if self.mapDraft then self.mapDraft.auto_square=auto end;self:autoSettings('map_grid',{'map_grid'},grid)end
    ui.text('Ручной сектор сохраняется. Полная настройка сетки — Экран, HUD и карта → Карта.')
    if self:button('Настроить акцент, перевод .команд и чат →##profile-chat',ui)and callbacks.openSettings then callbacks.openSettings('chat','accent')end
    end
    if part=='chat_accent'or part=='all'then
    local radio,radioChanged=self:check('Добавлять префикс локальной волны в мой /r##manual-radio-prefix',copy.settings.manual_radio_prefix)
    if radioChanged then self:autoSettings('manual_radio',{'settings','manual_radio_prefix'},radio)end
    ui.text('При отправке вашего /r PA добавляет префикс из «Профиль → Префикс локальной волны». После перевода .к действует то же правило. Пустое поле или выключатель оставляют доклад без изменений. /rn, /f, /d и другие команды не затрагиваются. Акцент в рацию не добавляется.')
    local radioExample=require('pa26_chat_text').radioCommand('/r Запрашиваю помощь.',{manual_radio_prefix=radio,local_tag=copy.profile.local_tag})
    ui.text('Предпросмотр: '..radioExample)
    if data.codec then local wire,err=require('pa26_core').encodeWire(radioExample,data.codec);if not wire then ui.text('Пример не помещается в чат: '..tostring(err))end end
    ui.text('Готовый префикс не дублируется. Длинный доклад продолжится по словам, если автоперенос включён. Перед отправкой проверяются все части и предел 127 байт вместе с /r и префиксом. Бинды и готовые доклады PA используют свои шаблоны: для них по-прежнему есть {local_tag}.')
    self:autosaveHint(ui,'manual_radio')
    self:settingsHeading(ui,'Акцент и команды с точкой')
    copy.profile.accent=self:field('Акцент##profile','profile:accent',copy.profile.accent,512)
    ui.text('Префикс обычной речи, например: [Русский акцент]:. Пустое поле отключает акцент.')
    ui.text('Акцент добавляется только к обычному сообщению, которое вы сами вводите в игровой чат. Команды с / или !, /me, /do, рация и автоматические реплики PA не меняются. В собственном бинде можно явно поставить {accent}.')
    local live,changed=self:check('Добавлять акцент в мой обычный чат##accent-live',copy.settings.accent_live_input)
    if changed then
        if live and model.accentPrefix(copy.profile.accent)==''then copy.profile.accent='[Русский акцент]:';self:setBuffer('profile:accent',copy.profile.accent,512)end
        self:autoSettings('accent_chat',{'settings','accent_live_input'},live)
    end
    local preview=live and model.applyAccent('Привет.',copy.profile.accent)or'Привет.'
    ui.text('Предпросмотр: '..tostring(preview or'Проверьте текст акцента.'))
    ui.text('Выключатель отключает акцент и при вводе, и при отправке. Текст префикса сохраняется. При включённом автопереносе длинная речь продолжается с многоточиями, а акцент остаётся только в первой части. Если подготовить все части нельзя, ввод сохраняется.')
    local brackets,bracketsChanged=self:check('Без акцента после ( и ) в начале сообщения##accent-brackets',copy.settings.accent_skip_brackets)
    if bracketsChanged then self:autoSettings('accent_chat',{'settings','accent_skip_brackets'},brackets)end
    ui.text('Если сообщение начинается с ( или ), PA оставит его без акцента. Пробелы перед скобкой тоже учитываются. Скобки внутри обычной фразы ничего не меняют.')
    ui.text('Предпросмотр: '..tostring(brackets and') Привет.'or(live and model.applyAccent(') Привет.',copy.profile.accent)or') Привет.')))
    local dot,dotChanged=self:check('Команды с точкой на русской раскладке##chat-dot-commands',copy.settings.chat_dot_commands)
    if dotChanged then self:autoSettings('accent_chat',{'settings','chat_dot_commands'},dot)end
    ui.text('Поставьте одну точку в самом начале поля и сразу напишите команду. При отправке PA заменит точку на / и переведёт только имя команды по клавишам русской раскладки. Аргументы сохранятся. Работает и с выключенным акцентом. Для CEF-чата также нужна включённая поддержка чата лаунчера ниже.')
    ui.text(dot and'Предпросмотр: .к Запрашиваю помощь. → /r Запрашиваю помощь.; .ыефеы → /stats.'or'Предпросмотр: .к Запрашиваю помощь. — перевод команд выключен.')
    ui.text('Пробел перед точкой, .5, .., многоточия и точки внутри текста не создают команду. Начальная точка отключает акцент, пока эта настройка включена. Неизвестную команду проверяет сервер. Чтобы написать .слово как обычный текст, поставьте перед точкой пробел или выключите перевод.')
    end
    if part=='chat_cef'or part=='all'then
    local cef,cefChanged=self:check('Поддержка чата лаунчера##cef-chat',copy.settings.cef_chat_support)
    if cefChanged then self:autoSettings('cef_chat',{'settings','cef_chat_support'},cef)end
    ui.text('При запуске проверяет подключение PA к CEF-чату и восстанавливает свой тег в HUD, если лаунчер его убрал. Проверка выполняется до ожидания SA-MP. Если страница чата уже успела загрузиться без PA, потребуется новый запуск игры. Серверные main.js и DLL не меняются.')
    ui.text('Связывает CEF-чат с командами PA, фильтрами и распознаванием служебных сообщений. Во время ввода игровые сочетания и отправка сценариев блокируются так же, как в стандартном чате.')
    local layout,layoutChanged=self:check('Язык ввода рядом с полем чата##cef-layout',copy.settings.cef_layout_indicator)
    if layoutChanged then self:autoSettings('cef_chat',{'settings','cef_layout_indicator'},layout)end
    ui.text('Показывает текущую раскладку клавиатуры справа от поля CEF-чата: RU, EN, BG, UK и другие. Обновляется при смене языка. При закрытом чате или потере связи значок скрывается. Это отдельный индикатор, он не меняет текст и RP-акцент.')
    ui.text(({
        disabled='Поддержка чата лаунчера выключена.',connected='Чат лаунчера: связь установлена.',waiting='Чат лаунчера: ожидается связь с игровым окном.',
        unavailable='Чат лаунчера: адаптер установлен, но локальная связь недоступна.',
        not_installed='Чат лаунчера: адаптер не установлен. Для стандартного чата SA-MP он не нужен.'
    })[data.cefChatStatus or'not_installed'])
    if self:button((self.showCefDiagnostics and 'Скрыть диагностику чата' or 'Диагностика чата')..'##cef-diagnostics-toggle',ui)then self.showCefDiagnostics=not self.showCefDiagnostics end
    if self.showCefDiagnostics then
    local cefReason=({setting_disabled='Для подключения включите поддержку чата лаунчера.',asset_missing='Файл HUD пока недоступен. PA повторит проверку автоматически.',
        asset_too_large='Размер HUD превышает допустимый. Нужна новая проверка совместимости.',adapter_file_missing='Не найден скрипт адаптера PA. Повторите установку PA.',
        asset_contract='Структура HUD изменилась. Нужна проверка совместимости; файл оставлен как есть.',asset_tag_conflict='Подключение PA в HUD неоднозначно. Нужна проверка установки.',
        asset_backup='Не удалось сохранить копию HUD перед восстановлением подключения.',asset_changed='Лаунчер обновил HUD во время проверки. PA повторит попытку.',
        asset_write='Не удалось подготовить файл подключения.',asset_replace='Не удалось обновить подключение PA. Проверьте доступ к папке HUD.',asset_verify='Файл подключения изменился после записи. PA повторит проверку.',adapter_missing='Не найдено подключение адаптера в HUD.',token='Не удалось подготовить защищённое локальное соединение.',
        socket_module='Не загрузилась установленная сетевая библиотека LuaSocket.',socket_create='Не удалось создать локальное соединение.',
        socket_timeout='Не удалось включить неблокирующий режим.',socket_bind='Не удалось открыть локальный адрес.',
        socket_listen='Не удалось начать ожидание игрового окна.',socket_accept='Локальное соединение прервалось. PA повторит подключение автоматически.',socket_address='Сетевая библиотека вернула неподходящий адрес или порт.',
        endpoint_encode='Не удалось подготовить адрес для игрового окна.',endpoint_write='Не удалось записать адрес для игрового окна.',
        endpoint_published='Адрес готов. Ожидается первое обращение чата.',browser_no_exchange='Чат пока не обратился к PA. Если он загрузился до восстановления подключения, перезапустите игру. Подробности: moonloader.log.',
        heartbeat_lost='Обмен с чатом прервался. Ожидается восстановление связи.'})[data.cefChatReason]
    if cefReason then ui.text(cefReason)end
    local cefLog,cefLogChanged=self:check('Диагностика чата##cef-chat-diagnostics',copy.settings.cef_chat_diagnostics)
    if cefLogChanged then self:autoSettings('cef_chat',{'settings','cef_chat_diagnostics'},cefLog)end
    ui.text('Записывает этап подключения и причины сбоев в moonloader.log. Текст переписки, сам акцент и секретный адрес не записываются. Счётчики означают подготовку и передачу сообщения чату, а не принятие сервером.')
    self:autosaveHint(ui,'cef_chat')
    self:autosaveHint(ui,'accent_chat')
    if not data.chatFiltersAvailable and not data.accentInputAvailable then ui.text('Перехват обычного чата недоступен в этом клиенте.') end
    end
    end
    self.profileDraft=copy.profile
    self:autoSettings('profile',{'profile'},copy.profile,'profileDraft');self:autosaveHint(ui,'profile')
    self:drawNotice(ui)
end
function Studio:drawOptions(ui,data,callbacks,part)
    part=part or 'all'
    local copy=model.copy(self.lib);local im=self.imgui;local d=self.optionDraft or model.copy(copy.settings)
    if part~='appearance'then
    self:settingsHeading(ui,'Клавиши отдельных окон')
    for _,f in ipairs({{'quick_key','Быстрое меню'},{'tips_key','Памятки'},{'cancel_key','Остановить'}})do
        ui.text(f[2]..': '..model.keyName(d[f[1]]))
        if im.Button('Назначить##'..f[1])then callbacks.capture({kind='setting',field=f[1]})end
        im.SameLine();if im.Button('Отключить##'..f[1])then d[f[1]]=0 end
    end
    self:settingsHeading(ui,'Окно помощников')
    require('pa26_assist_ui').shortcut(self,ui,callbacks,'assist','open_shortcut','Открыть / закрыть помощников')
    ui.text('По умолчанию F4. Клавишу можно переназначить или убрать; она не срабатывает при наборе текста, открытом чате и подтверждениях.')
    end
    if part~='controls'then
    self:settingsHeading(ui,'Оформление окон')
    local alpha=im.new.float(d.opacity);if im.SliderFloat('Непрозрачность',alpha,.5,1)then d.opacity=alpha[0]end
    d.compact=self:check('Компактные отступы',d.compact)
    end
    if part~='appearance'then
    im.Separator();self:settingsHeading(ui,'Выбранный человек')
    d.aim_select_enabled=self:check('Выбирать человека при удержании ПКМ##aim-select',d.aim_select_enabled)
    d.aim_select_control=self:choice('Кнопка выбора##aim-select-control',d.aim_select_control,{{'mouse','Всегда правая кнопка мыши','ПКМ'},{'game','Кнопка прицеливания из управления GTA','Прицеливание GTA'}},ui)
    ui.text('При стандартном управлении оба варианта используют ПКМ. «Всегда правая кнопка мыши» не зависит от переназначения клавиш GTA. Второй вариант следует настройке прицеливания в самой игре.')
    local aimDelay=im.new.int(d.aim_select_delay_ms);if im.SliderInt('Удержание перед выбором, мс',aimDelay,0,2000)then d.aim_select_delay_ms=aimDelay[0]end
    ui.text('Наведитесь на человека и удерживайте ПКМ до его игрового выделения. PA запомнит его без X и без оружия, в том числе на мотоцикле. За одно удержание выбирается один человек; отпустите кнопку перед новым выбором. Реплики и команды от этого не отправляются.')
    ui.text('При варианте «Прицеливание GTA» используется кнопка, назначенная в управлении игры. Меню, чат, диалоги и выполняющийся сценарий блокируют новый выбор. После их закрытия отпустите кнопку и нажмите снова.')
    d.keep_target_on_interior_change=self:check('Сохранять выбранного человека при смене интерьера##keep-target-interior',d.keep_target_on_interior_change)
    ui.text('При входе и выходе человек остаётся выбранным. Пока он не загрузился рядом, действия недоступны. Незавершённый сценарий отменяется; новый запускайте после перехода. Выход с сервера, смерть и смена личности по-прежнему снимают выбор.')
    local distance=im.new.int(d.retain_distance);if im.SliderInt('Дальность выбора и сохранения, м',distance,20,200)then d.retain_distance=distance[0]end
    local grace=im.new.int(d.retain_grace_ms);if im.SliderInt('Перерыв стрима, мс',grace,500,5000)then d.retain_grace_ms=grace[0]end
    ui.text('Выбранный человек остаётся закреплён, пока он в игре и достаточно близко. У каждой серверной команды могут быть свои ограничения по расстоянию.')
    require('pa26_nearby').settings(self,ui)
    im.Separator();self:settingsHeading(ui,'Радиальное меню')
    for _,spec in ipairs({{'wheel_enabled','Включить радиальное меню'},{'interaction_notices','Карточки взаимодействия с игроками'}})do d[spec[1]]=self:check(spec[2]..'##feature-'..spec[1],d[spec[1]])end
    if self:button('Тексты и сроки карточек##interaction-edit',ui)then callbacks.openAssist('notices')end
    d.wheel_mode=self:choice('Способ выбора##wheel-mode',d.wheel_mode,{{'categories','Категории и внешняя дуга','По категориям'},{'classic','Шесть прямых действий','Прямые действия'}},ui)
    if d.wheel_mode=='categories'then
        d.wheel_profile=self:choice('Количество категорий##wheel-profile',d.wheel_profile,{{'compact','4 крупные категории','4'},{'extended','6 категорий','6'},{'full','8 категорий','8'}},ui)
        ui.text('Чтобы открыть колесо, удерживайте назначенную клавишу. Добавить бинд: откройте его в библиотеке, перейдите в «Общее», включите «В радиальном меню» и выберите категорию.')
        self:settingsHeading(ui,'Названия категорий колеса','Ниже показаны категории для выбранного числа секций. При переключении между 4, 6 и 8 секциями скрытые названия сохраняются. Бинды остаются в своих категориях.','wheel-names')
        ui.text('Можно менять только названия: привязка биндов к категориям останется прежней. Пустое поле вернёт стандартное название.')
        d.wheel_names=d.wheel_names or{}
        local ids=wheelModel.profiles[d.wheel_profile]or wheelModel.profiles.compact
        for n,id in ipairs(ids)do
            -- IDs, not visible positions, own the names across 4/6/8 profiles.
            local name,edited=self:field('Категория '..n..'##wheel-name-'..id,'wheel-name:'..id,
                d.wheel_names[id]or wheelModel.categoryName(id),256)
            if edited then d.wheel_names[id]=name~=''and name or nil end
        end
        ui.text('Названия скрытых категорий сохраняются. Верните 6 или 8 секций — поля появятся с вашими названиями.')
        local customCount,changed=self:check('Своё число действий второго кольца##wheel-child-custom',(d.wheel_child_limit or 0)>0)
        if changed then d.wheel_child_limit=customCount and 10 or 0 end
        if customCount then local v=im.new.int(d.wheel_child_limit);if im.SliderInt('Действий перед кнопкой поиска##wheel-child-limit',v,1,16)then d.wheel_child_limit=v[0]end end
        ui.text('Авто сохраняет прежний размер. При своём числе, например 10, показываются до 10 действий, а при переполнении — дополнительная кнопка «Ещё и поиск».')
        self:settingsHeading(ui,'Куда поместить встроенные действия')
        d.wheel_system_groups=d.wheel_system_groups or{}
        local choices=wheelModel.categoryChoices(d.wheel_names);choices[1]={'auto','Стандартная секция'}
        for _,row in ipairs(wheelModel.systemRows)do
            local value,edited=self:choice(row[2]..'##wheel-system-'..row[1],d.wheel_system_groups[row[1]]or'auto',choices,ui)
            if edited then d.wheel_system_groups[row[1]]=value~='auto'and value or nil end
        end
        ui.text('В профиле с 4/6 секциями скрытые категории объединяются, как у биндов. При возврате к 8 назначения сохраняются.')
    else
        ui.text('Места прямого меню')
        local choices={{0,'Пусто'}};for _,binding in ipairs(copy.bindings)do choices[#choices+1]={binding.id,binding.name}end
        local positions={'Верх справа','Справа','Низ справа','Низ слева','Слева','Верх слева'}
        for slot,index in ipairs(core.wheelSlots)do local value,changed=self:choice(positions[slot]..'##wheel'..slot,copy.wheel[index],choices,ui)
            if changed then copy.wheel[index]=value;callbacks.save(copy)end end
    end
    end
    self.optionDraft=d;self:autoSettings('options',{'settings'},d,'optionDraft');self:autosaveHint(ui,'options');self:drawNotice(ui)
end

function Studio:drawExtras(ui,data,callbacks,recruitmentOnly)
    local copy=model.copy(self.lib); local im=self.imgui
    ui.text('Проверка кандидата · значения вводятся вручную')
    self.candidate=self.candidate or {age=18,level=1,lawfulness=0,land=false,water=false,air=false,weapon=false,medical=false}
    self.criteriaDraft=self.criteriaDraft or model.copy(copy.recruitment)
    local labels={min_age='Минимальный возраст',min_level='Минимальный уровень',min_lawfulness='Минимальная законопослушность'}
    for _,k in ipairs({'min_age','min_level','min_lawfulness'}) do local v=im.new.int(self.criteriaDraft[k]); if im.InputInt(labels[k],v) then self.criteriaDraft[k]=math.max(0,math.min(999,v[0])); self.criteriaDirty=true end end
    for _,pair in ipairs({{'land','Наземный транспорт'},{'water','Водный транспорт'},{'air','Воздушный транспорт'},{'weapon','Оружие'},{'medical','Медосмотр'}}) do
        local v,changed=self:check('Требуется: '..pair[2],self.criteriaDraft[pair[1]]); if changed then self.criteriaDraft[pair[1]]=v; self.criteriaDirty=true end
        self.candidate[pair[1]]=self:check('У кандидата: '..pair[2],self.candidate[pair[1]])
    end
    for _,pair in ipairs({{'age','Возраст кандидата'},{'level','Уровень кандидата'},{'lawfulness','Законопослушность кандидата'}}) do local v=im.new.int(self.candidate[pair[1]]); if im.InputInt(pair[2],v) then self.candidate[pair[1]]=math.max(0,math.min(999,v[0])) end end
    local accepted,missing=model.recruitmentResult(self.criteriaDraft,self.candidate); ui.text(accepted and 'Введённые данные соответствуют критериям.' or 'Не выполнены критерии: '..table.concat(missing,', '))
    self:autoSettings('extras',{'recruitment'},self.criteriaDraft,'criteriaDraft')
    if not recruitmentOnly then self:drawFilters(ui,data,callbacks)end
    im.Separator(); ui.text('Объявление или повторяемую реплику можно создать как обычный бинд с нужной командой сервера.')
    ui.text('Стробоскопы и поиск преступников требуют подтверждённых возможностей сервера; скрытые данные не читаются.')
    self:drawNotice(ui)
end

function Studio:drawFilters(ui,data,callbacks)
    local copy=model.copy(self.lib);local im=self.imgui
    im.Separator(); ui.text('Фильтры серверного чата · буквальные префиксы')
    ui.text(data.textFiltersAvailable and 'Фильтры подключены к игровому чату. Каждый префикс можно включить отдельно.' or 'Фильтры ожидают подключение SAMP.Lua или адаптера чата лаунчера.')
    self.filtersDraft=self.filtersDraft or model.copy(copy.filters)
    for i,filter in ipairs(self.filtersDraft) do
        filter.enabled=self:check('Скрывать##filter'..i,filter.enabled)
        local prefix,edited=self:field('Префикс##filter'..i,'filter'..i,filter.prefix,256)
        if edited then filter.prefix=prefix end
        if im.Button('Удалить##filter'..i) then self.remove={kind='filter',id=i,prefix=self.lib.filters[i]and self.lib.filters[i].prefix or filter.prefix} end
    end
    self:autoSettings('filters',{'filters'},self.filtersDraft,'filtersDraft')
    local prefix=self:field('Новый префикс##newfilter','newfilter','',256)
    if im.Button('Добавить выключенный фильтр') and #self.filtersDraft<16 then
        copy.filters=model.copy(self.filtersDraft);copy.filters[#copy.filters+1]={prefix=prefix,enabled=false}
        local ok,err=callbacks.save(copy);self:notify(err or '')
        if ok then self.filtersDraft=nil;if self.autosaves then self.autosaves.filters=nil end;self.cache['newfilter']=nil end
    end
    self:drawNotice(ui)
end
function Studio:hasModal()
    return self:hasWarning()or self.authorPresetConfirm~=nil or self.manualAction~=nil or self.wantedAppearance~=nil or self.rpPresetConfirm~=nil or self.assistConfirm~=nil or self.vehicleConfirm~=nil or self.operationConfirm~=nil or self.caseConfirm~=nil or self.patrolEventConfirm~=nil or self.patrolConfirm~=nil or self.remove~=nil or self.reset~=nil or self.importPreview~=nil or self.confirmPlan~=nil or self.confirmResult~=nil or
        self.pendingSelection~=nil or self.pendingNavigation~=nil or self.keyCapture~=nil or self.customRemove~=nil
end
function Studio:cancelModal()
    local pending=self:hasModal()
    if self.caseConfirm and self.caseConfirm.phase=='command'then self.cancelledCaseToken=self.caseConfirm.token end
    self.feedback:clear()
    if self.wantedAppearance then self.wantedAppearance.form.stage='identity' end
    self.wantedAppearance=nil
    self.manualAction=nil
    self.authorPresetConfirm=nil
    self.rpPresetConfirm=nil
    self.assistConfirm=nil;self.operationConfirm=nil
    self.vehicleConfirm=nil;self.caseConfirm=nil;self.patrolEventConfirm=nil;self.patrolConfirm=nil; self.remove=nil; self.reset=nil; self.importPreview=nil; self.confirmPlan=nil; self.confirmResult=nil
    self.pendingSelection=nil; self.pendingNavigation=nil; self.pendingEditorTab=nil; self.keyCapture=nil
    self.customRemove=nil
    self.modalToken=nil; self.modalError=nil
    return pending
end
function Studio:beginKeyCapture(request)
    local fields={quick_key='Быстрое меню',tips_key='Памятки',cancel_key='Остановка сценария'}
    local current,name='Не назначено',fields[request.field]
    if request.kind=='binding' and self.draft and self.draft.id==request.id then
        current=model.shortcutName(self.draft.shortcut); name=self.draft.name
    elseif request.kind=='setting' then current=model.keyName(self.lib.settings[request.field])
    elseif request.kind=='feature'then
        local field=({radio_guard='radioGuardDraft',weapon_warning='warningDraft',vehicle='vehicleDraft',patrol_session='patrolSessionDraft',patrol_events='patrolEventDraft',procedures='caseDraft'})[request.group]
        local draft=field and self[field]
        current=model.shortcutName((draft or self.lib[request.group])[request.field])
        for _,row in ipairs(model.featureKeys)do if row[1]==request.group and row[2]==request.field then name=row[3]end end
    end
    self.keyCapture={request=request,current=current,name=name or 'Клавиша',stage='listening',reader={}}
end
function Studio:pollKeyCapture(io,callbacks)
    local c=self.keyCapture
    if not c or c.stage=='ready' or c.stage=='timeout' then return end
    local mods={ctrl=io.KeyCtrl or io.KeysDown[17],alt=io.KeyAlt or io.KeysDown[18],
        shift=io.KeyShift or io.KeysDown[16],super=io.KeySuper or io.KeysDown[91] or io.KeysDown[92]}
    local input=M.captureInput(c.reader,io.KeysDown,mods)
    if input then callbacks.captureProgress(c.request,input.proposal,input.finished==true,input.error) end
end
function Studio:captureProgress(request,proposal,error)
    local c=self.keyCapture; if not c or c.request~=request then return false end
    c.proposal=model.copy(proposal); c.error=error; c.valid=false
    c.stage=proposal.key~=0 and 'holding' or 'listening'; self.modalError=nil
    return true
end
function Studio:captureResult(request,proposal,error)
    local capture=self.keyCapture; if not capture or capture.request~=request then return false end
    capture.proposal=model.copy(proposal); capture.error=error; capture.valid=not error
    capture.stage=error and 'error' or 'ready'; self.modalError=nil
    return true
end
function Studio:captureTimeout(request)
    local capture=self.keyCapture; if not capture or capture.request~=request then return end
    capture.stage='timeout'; capture.valid=false
    capture.error='Время ожидания истекло. Нажмите в центре окна, чтобы записать заново.'
end
function Studio:resolveSelection(save,callbacks)
    local id,tab=self.pendingSelection,self.pendingEditorTab
    if not id or not model.find(self.lib,id) then return nil,'Бинд для перехода недоступен. Отмените диалог и выберите его заново.' end
    if save and not self:saveDraft(callbacks) then return nil,self.status end
    self.pendingSelection=nil; self.pendingEditorTab=nil; self.dirty=false
    self:select(id)
    if tab then self.editorTab=tab end
    return true
end
function Studio:selectProcedure(kind)caseUi.select(self,kind)end
function Studio:modalIntent(data)
    local warning=self.feedback:peek()
    if warning then
        local lines={warning.message}
        if warning.skipped then lines[#lines+1]='Несколько повторных предупреждений объединены. Проверьте журнал PA при необходимости.'end
        return{kind='warning',token=warning.token,title=warning.kind=='info'and 'Уведомление'or 'Предупреждение',lines=lines}
    end
    if self.authorPresetConfirm then return require('pa26_author_controller').modal(self)end
    if self.manualAction then return{kind='manual_action',token='manual-command:'..self.manualAction.token,title='Отыграть действие перед командой?',lines=self.manualAction.lines}end
    if self.pendingNavigation then
        local _,lines=self:unsavedChanges()
        lines[#lines+1]='После сохранения: '..self.pendingNavigation.label..'.'
        lines[#lines+1]='«Сохранить» запишет правки и продолжит переход. «Отбросить» удалит несохранённые правки. «Остаться» вернёт вас к редактированию.'
        return {kind='changes',token='navigation:'..self.pendingNavigation.serial,title='Сохранить изменения перед выходом?',lines=lines}
    end
    if self.wantedAppearance then
        local a=self.wantedAppearance
        return {kind=a.stage=='appearance_choice'and 'wanted_appearance_choice'or 'wanted_appearance_input',
            token='wanted-appearance:'..a.form.id..':'..a.stage,
            title=a.stage=='appearance_choice'and 'Как передать ориентировку диспетчеру?'or 'Введите приметы подозреваемого',
            lines=a.stage=='appearance_choice'and {'Паспорт не проверялся, лицо подозреваемого не скрыто RP-маской.',
                'Для '..a.form.target.name..' [ID: '..a.form.target.id..']. Пока ничего не отправляется.',
                'Общая — готовая отыгровка без ручного ввода. С приметами — ввод в следующем окне.'}or
                {'Пример: высокий, на вид 25 лет, в синей куртке. Сам пример в чат не отправляется.',
                'Перечислите приметы через запятую без символа *. PA продолжит длинный текст связными /todo с «...» и тем же действием после *.'}}
    end
    if self.rpPresetConfirm then return require('pa26_rp_presets').modal(self)end
    if self.assistConfirm then return require('pa26_assist_ui').modal(self)end
    if self.operationConfirm then
        local p=self.operationConfirm
        return {kind='operation_result',token='operation:'..p.token,title='Сохранить вашу оценку результата?',lines={
            'Действие #'..p.row.id..' · '..p.row.date,p.row.text,
            'Цель на момент команды: '..(p.row.target and(p.row.target.name..' ['..p.row.target.id..']')or 'Не установлена'),
            'Было: '..require('pa26_operations').statusNames[p.row.status],
            'Станет: '..require('pa26_operations').statusNames[({success='manual_success',failure='manual_failure',unknown='manual_unknown'})[p.outcome]],
            'Ваше пояснение: '..p.note,
            'Вы отмечаете результат вручную по тому, что произошло в игре.',
            'ДА изменит только выбранную запись журнала. PA не повторит команду и не отправит доклад в рацию.'}}
    end
    if self.caseConfirm then
        if self.caseConfirm.phase=='command'then
            local p=self.caseConfirm;local direct=p.kind=='wanted'and p.cfg.wanted_send_mode=='direct'
            local lines={p.form.target and('Подозреваемый: '..p.form.target.name..' [ID: '..p.form.target.id..']')or 'Общий список преступников'}
            if p.gameReason then
                lines[#lines+1]='Пункт '..p.gameReason.id..' · '..p.gameReason.group_title..' / '..p.gameReason.title
                lines[#lines+1]='По серверному списку: '..p.gameReason.stars..' ур. розыска. Итоговый уровень и отказ при максимуме определяет сервер.'
                lines[#lines+1]=p.gameReason.mapping_status..'. '..p.gameReason.note
            end
            if p.form.mode=='ooc'and p.kind=='wanted'then lines[#lines+1]=require('pa26_procedure_settings').oocNotes[p.form.ooc_reason]end
            lines[#lines+1]='Отыгровка уже завершена. После ДА будет отправлена только эта команда:'
            for _,line in ipairs(p.lines)do lines[#lines+1]=line end
            lines[#lines+1]=direct and 'Команда может сразу выдать розыск без серверного окна. НЕТ отменит команду; уже отправленные отыгровки не повторятся.'or 'Команда откроет серверный список; дальнейший выбор в нём вы делаете вручную. НЕТ отменит открытие.'
            lines[#lines+1]=p.demo and 'ДЕМО · отправки на сервер нет.'or 'Реальный режим · проверьте цель, основание и последствия.'
            return {kind='case_procedure',token='case-final:'..p.token,title=direct and 'Выдать выбранный розыск?'or 'Открыть серверный список?',lines=lines}
        end
        local p=self.caseConfirm;local lines={p.form.target.name..' ['..p.form.target.id..'] · '..p.form.mode:upper(),
            'Основание: '..p.values.basis}
        if p.kind=='mark'then
            if p.form.mode=='ic'then lines[#lines+1]='IC-номер: '..p.values.phone_number..' · источник: '..p.values.phone_source end
            lines[#lines+1]='Метка и результат команды зависят от сервера. PA не добавляет розыск вместе с пеленгацией.'
        else lines[#lines+1]='Значение введено вручную: '..p.values.amount end
        for _,line in ipairs(p.lines)do lines[#lines+1]=line end
        lines[#lines+1]='Сначала отправятся отыгровки, затем команда. End или Esc остановит оставшиеся шаги. Результат проверьте в игре.'
        lines[#lines+1]=p.demo and 'Демо: серверных отправок нет.'or 'Реальный режим: после ДА строки поступят в общую очередь.'
        return {kind='case_procedure',token='case:'..p.token,title=p.kind=='wanted'and 'Выполнить процедуру розыска?'or p.kind=='mark'and 'Выполнить пеленгацию?'or 'Выполнить процедуру штрафа?',lines=lines}
    end
    if self.patrolEventConfirm then
        local p=self.patrolEventConfirm
        return {kind='patrol_event',token=p.token,title=p.report and 'Записать факт и передать доклад?'or 'Записать подтверждённый факт?',
            lines={p.cfg.events[p.form.kind].name,
                p.form.target and('Техническая цель: '..p.form.target.name..' ['..p.form.target.id..']')or 'Без технической цели',
                'Человек / приметы: '..p.form.subject,
                p.form.basis~=''and('Основание: '..p.form.basis)or '',
                p.line or 'В рацию ничего не отправится.',
                'Источник: ваше ручное подтверждение. Это не ответ сервера.',
                p.demo and 'Демо: реальная статистика и сервер не изменятся.'or 'Один факт будет записан в журнале патруля. Передача доклада учитывается отдельно.'}}
    end
    if self.vehicleConfirm then
        local p=self.vehicleConfirm
        local lines={p.target and p.description or'Общее объявление для окружающих.',
            p.target and('Машина ['..p.target.id..'] · GTA модель '..p.target.model_id)or('Реплика: '..(p.label or'Мегафон')),'Y — ДА · N — НЕТ'}
        for _,line in ipairs(p.prepared.lines)do lines[#lines+1]=line end
        lines[#lines+1]=p.demo and 'Демо: отправок на сервер нет.'or 'После ДА PA отправит показанные строки по очереди. Результат команды нужно проверить в игре.'
        return {kind='vehicle',token=p.token,title=p.target and'Выполнить действие с выбранной машиной?'or'Передать общее объявление?',lines=lines}
    end
    if self.patrolConfirm then
        local p=self.patrolConfirm
        return {kind='patrol',token='patrol:'..p.token,title=p.no_report and 'Изменить сеанс без доклада в рацию?'or p.action=='discard'and 'Завершить без доклада?'or 'Передать доклад патруля?',
            lines={p.line or(p.no_report and 'Рацию ведёт напарник. PA изменит только состояние вашего патруля, без сообщений в чат.'or 'Сеанс будет закрыт локально. В рацию ничего не отправится.'),
                'Патруль № '..p.record.id..' · '..p.record.officer,
                'Экипаж: '..#p.record.crew..' напарников · режим: '..(p.demo and 'демо'or 'реальные команды'),
                p.no_report and 'После ДА изменится локальный сеанс и таймер. Радиодоклада от PA не будет.'or p.action=='finish'and 'Таймер остановится после передачи строки клиенту. При ошибке сеанс встанет на паузу.'or
                p.action=='discard'and 'Длительность сохранится в истории. Продолжить этот сеанс уже не получится.'or
                'После ДА действие встанет в очередь. Его результат проверьте в игре: отправка команды ещё не означает успешное выполнение.'}}
    end
    if self.keyCapture then
        local c=self.keyCapture
        local lines={c.name,'Текущее назначение: '..c.current}
        if c.request.kind~='setting' then lines[#lines+1]='Одна клавиша или Ctrl / Alt / Shift + клавиша. Всего до 3.'
        else lines[#lines+1]='Для этой настройки выберите одну клавишу.' end
        if c.stage=='ready' then
            lines[#lines+1]=c.request.kind=='setting' and 'Кнопка «Назначить» сохранит клавишу в настройках.' or
                c.request.kind=='feature' and 'Кнопка «Назначить» сохранит сочетание в настройках.' or
                'Кнопка «Назначить» применит сочетание к черновику. Затем сохраните сценарий.'
        end
        if c.stage=='ready' then lines[#lines+1]='Выбрано: '..model.shortcutName(c.proposal) end
        lines[#lines+1]='Esc — отмена. Нажмите в центре, чтобы записать заново.'
        if c.error then lines[#lines+1]=c.error end
        return {kind='capture',token='capture:'..tostring(c),height=420,title='Назначение клавиши',lines=lines}
    end
    if self.customRemove then return {kind='delete_custom_report',token='delete-auto:'..self.customRemove.id,
        title='Удалить автодоклад?',height=270,lines={self.customRemove.name,'Удалить этот доклад и его расписание? Другие несохранённые изменения останутся в черновике.'}}end
    if self.pendingSelection and self.draft then
        local target=model.find(self.lib,self.pendingSelection)
        return {kind='changes',token='changes:'..self.draft.id..':'..self.pendingSelection,height=312,title='Сохранить изменения бинда?',
            lines={self.draft.name,'Переход к: '..(target and target.name or 'недоступный бинд'),
                'Перед выходом сохраните бинд, отмените изменения или вернитесь к редактированию.'}}
    end
    if self.remove then
        local r=self.remove; local names={binding='сценарий',note='памятку',partner='контакт',filter='фильтр чата'}
        local key=({binding='bindings',note='notes',partner='partners',filter='filters'})[r.kind]
        if not key then return nil end
        local item
        if r.kind=='filter' then item=self.lib.filters[r.id]
        elseif r.kind=='binding' and self.draft and self.draft.id==r.id then item=self.draft end
        if not item then for _,entry in ipairs(self.lib[key]) do if entry.id==r.id then item=entry; break end end end
        return {kind='delete',token='delete:'..r.kind..':'..r.id,title='Удалить '..names[r.kind]..'?',
            lines={item and (item.name or item.nickname or item.prefix) or ('Запись '..r.id),
                'Вы уверены, что хотите удалить эту запись?'},height=258}
    end
    if self.reset then
        return {kind='reset',token='reset:'..self.reset,height=258,
            title=self.reset=='log' and 'Очистить журнал?' or 'Обнулить статистику?',
            lines={self.reset=='log' and 'Будут удалены записи журнала. Служебные счётчики сохранятся.' or
                'Будут обнулены служебные счётчики. Журнал останется доступным.'}}
    end
    if self.confirmResult then
        local name='Запись '..self.confirmResult
        for _,e in ipairs(data.journal.data.events) do if e.id==self.confirmResult then name=e.name; break end end
        return {kind='result',token='result:'..self.confirmResult,height=290,title='Подтвердить служебный результат?',
            lines={name,'Отмечайте результат после выполнения действия в игре. Служебный счётчик увеличится на один.'}}
    end
    if self.importPreview then
        local v=self.importPreview
        local notes=v.format=='police-assistant.notes';local rows=notes and v.notes or v.bindings
        local lines={notes and('Заметок: '..#rows)or('Биндов: '..#rows),
            notes and'Заметки добавятся отдельными записями. Бинды, контакты, профиль и настройки сохранятся.'or
                'Бинды добавятся выключенными, без клавиш и команд запуска, с обязательным подтверждением. Заметки, контакты, профиль и настройки сохранятся.'}
        for _,row in ipairs(rows)do lines[#lines+1]=row.name end
        return {kind='import',token='import:'..tostring(v),height=320,title=notes and'Добавить заметки из файла?'or'Добавить бинды из файла?',lines=lines}
    end
    if self.confirmPlan then
        local plan=self.confirmPlan
        local lines={plan.binding.name,plan.target and ('Получатель: '..plan.target.name..' ['..plan.target.id..']') or 'Без цели',
            data.demo and 'ДЕМО · отправки в игру нет' or 'После подтверждения начнётся отправка в игровой чат.'}
        for _,warning in ipairs(require('pa26_server_commands').bindingWarnings(plan.binding))do lines[#lines+1]=warning end
        for _,line in ipairs(plan.lines) do lines[#lines+1]=line end
        return {kind='plan',token='plan:'..tostring(plan),height=440,title='Запустить сценарий?',lines=lines}
    end
end
function Studio:acceptModal(data,callbacks)
    if self:hasWarning()then return nil,'Сначала закройте предупреждение кнопкой «ОК».'end
    if self.authorPresetConfirm then return callbacks.authorPresetAccept()end
    if self.rpPresetConfirm then return require('pa26_rp_presets').accept(self,callbacks)end
    if self.assistConfirm then return require('pa26_assist_ui').accept(self,callbacks)end
    if self.operationConfirm then return callbacks.operationAccept(self.operationConfirm)end
    if self.caseConfirm then return callbacks.caseAccept(self.caseConfirm)end
    if self.patrolEventConfirm then return callbacks.patrolEventAccept(self.patrolEventConfirm)end
    if self.vehicleConfirm then return callbacks.vehicleAccept(self.vehicleConfirm)end
    if self.patrolConfirm then return callbacks.patrolAccept(self.patrolConfirm)end
    if self.customRemove then
        local r=self.customRemove;local copy=model.copy(self.lib);local draft=self.radioGuardDraft or r.owner
        if not draft then return nil,'Запись изменилась. Повторите удаление.'end
        for i=#copy.radio_guard.custom,1,-1 do if copy.radio_guard.custom[i].id==r.id then table.remove(copy.radio_guard.custom,i)end end
        local ok,err=callbacks.save(copy);if not ok then return nil,err end
        if self.autosaves then self.autosaves.radio_guard=nil end
        for i=#draft.custom,1,-1 do if draft.custom[i].id==r.id then table.remove(draft.custom,i)end end
        self.radioGuardDraft=draft;self.autoReportId=nil;self:clearPreferenceCache('auto:'..r.id..':');return true
    end
    if self.remove then
        local r=self.remove; local copy=model.copy(self.lib)
        local key=({binding='bindings',note='notes',partner='partners',filter='filters'})[r.kind]
        if not key then return nil,'Запись недоступна.' end
        if r.kind=='filter' then
            if not copy.filters[r.id] or copy.filters[r.id].prefix~=r.prefix then return nil,'Список фильтров изменился. Повторите выбор.' end
            table.remove(copy.filters,r.id)
        else
            for i=#copy[key],1,-1 do if copy[key][i].id==r.id then table.remove(copy[key],i) end end
        end
        if r.kind=='binding' then for i,id in ipairs(copy.wheel) do if id==r.id then copy.wheel[i]=0 end end end
        local ok,err=callbacks.save(copy)
        if not ok then return nil,err end
        self:setLibrary(copy)
        if r.kind=='filter'then
            self.filtersDraft=nil;self:clearPreferenceCache('filter');if self.autosaves then self.autosaves.filters=nil end
        end
        if r.kind=='binding' and self.draft and self.draft.id==r.id then self:resetBinding(copy.bindings[1] and copy.bindings[1].id) end
        return true
    end
    if self.reset or self.confirmResult then
        local journal=data.journal
        local previous,results,dirty=model.copy(journal.data),model.copy(journal.results),journal.dirty
        if self.confirmResult then
            local ok,err=journal:confirm(self.confirmResult); if not ok then return nil,err end
        elseif self.reset=='log' then journal:clearLog() else journal:resetStats() end
        local ok,err=callbacks.saveJournal()
        if not ok then journal.data=previous; journal.results=results; journal.dirty=dirty end
        return ok,err
    end
    if self.importPreview then return callbacks.confirmImport(self.importPreview) end
    if self.confirmPlan then return callbacks.request({kind='startPlan',plan=self.confirmPlan}) end
    return nil,'Подтверждение больше не требуется.'
end
function Studio:drawCaptureSurface(ui,callbacks)
    local im=self.imgui; local capture=self.keyCapture
    if not capture then return end
    local width=math.max(1,im.GetContentRegionAvail().x)
    im.PushStyleColor(im.Col.Button,im.ImVec4(.06,.16,.25,.94)); ui.push(function() im.PopStyleColor(1) end)
    im.PushStyleColor(im.Col.ButtonHovered,im.ImVec4(.08,.22,.34,.97)); ui.push(function() im.PopStyleColor(1) end)
    local retry=im.Button('##capture-surface',im.ImVec2(width,126))
    ui.finish(); ui.finish()
    local first,last=im.GetItemRectMin(),im.GetItemRectMax()
    local draw=im.GetWindowDrawList(); local vec=im.ImVec2
    local font=self.headingFont or im.GetFont(); local size=self.headingFont and 24 or im.GetFontSize()
    local function tint(r,g,b,a) return im.ColorConvertFloat4ToU32(im.ImVec4(r,g,b,a)) end
    local function centered(text,fontSize,y,color)
        local measured=font:CalcTextSizeA(fontSize,100000,0,text)
        draw:AddTextFontPtr(font,fontSize,vec(first.x+(width-measured.x)/2,y),color,text)
    end
    local parts=M.keycapParts(capture.proposal)
    if capture.stage=='timeout' then centered('Записать заново',size,first.y+37,tint(1,1,1,1))
    elseif #parts>3 then centered('Слишком много клавиш',size,first.y+37,tint(1,.75,.75,1))
    elseif #parts==0 then centered('Нажмите клавишу',size,first.y+37,tint(1,1,1,1))
    else
        local layout=M.keycapLayout(parts,width,font,size)
        local x,y=first.x+(width-layout.total)/2,first.y+20+(58-layout.height)/2
        for i,text in ipairs(parts) do
            local w=layout.widths[i]; local h=layout.height
            draw:AddRectFilled(vec(x,y+3),vec(x+w,y+h+3),tint(.02,.06,.10,.8),10)
            draw:AddRectFilled(vec(x,y),vec(x+w,y+h),tint(.13,.31,.45,.99),10)
            draw:AddRect(vec(x,y),vec(x+w,y+h),tint(.40,.64,.81,.84),10,15,1.2)
            local extent=font:CalcTextSizeA(layout.fontSize,100000,0,text)
            draw:AddTextFontPtr(font,layout.fontSize,vec(x+(w-extent.x)/2,y+(h-extent.y)/2),tint(1,1,1,1),text)
            x=x+w
            if i<#parts then
                local extent=font:CalcTextSizeA(layout.fontSize,100000,0,'+')
                draw:AddTextFontPtr(font,layout.fontSize,vec(x+(layout.gap-extent.x)/2,y+(h-extent.y)/2),tint(.65,.78,.88,1),'+')
                x=x+layout.gap
            end
        end
    end
    local hint
    if capture.stage=='holding' then hint='Отпустите клавиши'
    elseif capture.stage=='ready' then hint='Сочетание записано · нажмите «Назначить»'
    elseif capture.stage=='error' or capture.stage=='timeout' then hint='Нажмите здесь, чтобы попробовать снова'
    elseif #parts>0 then hint='Добавьте основную клавишу'
    else hint=capture.request.kind~='setting' and 'или сочетание до 3 клавиш' or 'одна клавиша' end
    centered(hint,14,first.y+98,tint(.68,.81,.91,1))
    if retry then callbacks.capture(capture.request) end
end
-- Call at the parent window's root, after all scrolling children are ended.
-- ImGui owns mouse blocking; hasModal() also blocks our game hotkeys.
function Studio:drawModal(ui,data,callbacks)
    self:drawStatusInfo(ui)
    local im=self.imgui; local io=im.GetIO()
    local escape=io.KeysDown[27]==true
    if escape and not self.guiEscapeDown and self:hasModal() then
        if self:hasWarning()then self:ackWarning()else
            if self.manualAction then callbacks.stop()end
            self:cancelModal();callbacks.cancelCapture()end
    end
    self.guiEscapeDown=escape
    if not self:hasWarning()then self:pollKeyCapture(io,callbacks)end
    local intent=self:modalIntent(data)
    local id='Подтверждение##pa26-confirm'
    if not intent and not self.modalVisible then return end
    if intent and intent.token~=self.modalToken then
        self.modalToken=intent.token; self.modalError=nil;self.modalPagination={};self.modalPosition=nil;self.rightDrag=nil; im.OpenPopup(id)
    end
    local spec={title=intent and intent.title or '',lines=model.copy(intent and intent.lines or{}),
        titleFont=self.buttonFont,buttonFont=self.buttonFont,pageState=self.modalPagination,columns=intent and(intent.kind=='warning'or intent.kind=='manual_action')and 1 or intent and intent.kind=='changes' and 3 or 2,
        extraHeight=intent and intent.kind=='capture' and 136 or intent and intent.kind=='wanted_appearance_input'and 90 or 0,
        extraAfterLines=intent and intent.kind=='wanted_appearance_input',
        buttons=intent and intent.kind=='warning'and{'ОК'}or intent and intent.kind=='changes' and {'Сохранить','Отбросить','Остаться'} or
            intent and intent.kind=='capture' and {'Назначить','Отмена'}or
            intent and intent.kind=='manual_action'and {'ДА — отыграть RP и выполнить','НЕТ — выполнить сразу без RP','Отменить всё (Esc) — не отправлять'}or
            intent and intent.kind=='case_procedure'and self.caseConfirm.phase=='command'and {self.caseConfirm.kind=='wanted_list'and 'ДА — открыть /wanted'or(self.caseConfirm.cfg.wanted_send_mode=='direct'and 'ДА — выдать розыск'or 'ДА — открыть список'),self.caseConfirm.kind=='wanted_list'and 'НЕТ — отменить'or 'НЕТ — не выдавать розыск'}or
            intent and intent.kind=='wanted_appearance_choice'and {'Общая (без ввода)','С приметами'}or
            intent and intent.kind=='wanted_appearance_input'and {'Далее · к выбору статьи','Назад'}or{'ДА','НЕТ'}}
    local confirmationBinding=intent and intent.kind=='plan'and self.confirmPlan and model.find(self.lib,self.confirmPlan.binding.id)
    if confirmationBinding then spec.checkboxLabel='Больше не показывать предупреждение для этого действия.'end
    if self.modalError then spec.lines[#spec.lines+1]='Не выполнено: '..self.modalError end
    local layout=menuModule.confirmationLayout(im,spec)
    local position=self.modalPosition or{x=(io.DisplaySize.x-layout.width)/2,y=(io.DisplaySize.y-layout.height)/2}
    position.x=math.max(16,math.min(position.x,io.DisplaySize.x-layout.width-16))
    position.y=math.max(16,math.min(position.y,io.DisplaySize.y-layout.height-16))
    im.SetNextWindowPos(im.ImVec2(position.x,position.y),im.Cond.Always)
    im.SetNextWindowSize(im.ImVec2(layout.width,layout.height),im.Cond.Always)
    local depth=0
    local function style(index,value,vector)
        if vector then im.PushStyleVarVec2(index,value) else im.PushStyleVarFloat(index,value) end
        ui.push(function() im.PopStyleVar(1) end); depth=depth+1
    end
    local function color(index,value)
        im.PushStyleColor(index,value); ui.push(function() im.PopStyleColor(1) end); depth=depth+1
    end
    style(im.StyleVar.WindowRounding,14); style(im.StyleVar.FrameRounding,10)
    style(im.StyleVar.WindowBorderSize,0)
    style(im.StyleVar.WindowPadding,im.ImVec2(28,24),true)
    style(im.StyleVar.ItemSpacing,im.ImVec2(10,10),true)
    color(im.Col.PopupBg,im.ImVec4(.035,.09,.15,.88))
    color(im.Col.ModalWindowDimBg,im.ImVec4(.01,.03,.06,.28))
    local flags=im.WindowFlags.NoTitleBar+im.WindowFlags.NoResize+im.WindowFlags.NoMove+
        im.WindowFlags.NoSavedSettings+im.WindowFlags.NoCollapse+im.WindowFlags.NoScrollbar+im.WindowFlags.NoScrollWithMouse
    local visible=im.BeginPopupModal(id,nil,flags)
    if visible then
        self.modalVisible=true; ui.push(function() im.EndPopup() end)
        self.modalPosition=menuModule.rightDragRect(im,self,'confirmation')or self.modalPosition
        if not intent then im.CloseCurrentPopup(); self.modalVisible=false
        else
            menuModule.confirmationBody(im,ui,layout,spec,intent.kind=='capture' and function()self:drawCaptureSurface(ui,callbacks)end or
                intent.kind=='wanted_appearance_input'and function()
                    local f=self.wantedAppearance.form
                    f.appearance=self:field('Приметы##wanted-appearance-modal','wanted-appearance-input:'..f.id,f.appearance or '',2048)
                end or nil)
            local function answer(text,base,hover,active,width)
                im.PushStyleColor(im.Col.Button,base); ui.push(function() im.PopStyleColor(1) end)
                im.PushStyleColor(im.Col.ButtonHovered,hover); ui.push(function() im.PopStyleColor(1) end)
                im.PushStyleColor(im.Col.ButtonActive,active); ui.push(function() im.PopStyleColor(1) end)
                local clicked=self:button(text,ui,width)
                ui.finish(); ui.finish(); ui.finish(); return clicked
            end
            local function green(text,width) return answer(text,im.ImVec4(.10,.51,.29,.97),im.ImVec4(.14,.64,.37,1),im.ImVec4(.08,.43,.24,1),width) end
            local function red(text,width) return answer(text,im.ImVec4(.64,.17,.23,.97),im.ImVec4(.78,.23,.29,1),im.ImVec4(.54,.12,.17,1),width) end
            local function neutral(text,width) return answer(text,im.ImVec4(.12,.28,.40,.94),im.ImVec4(.18,.39,.53,1),im.ImVec4(.08,.22,.32,1),width) end
            local function close() self:cancelModal(); im.CloseCurrentPopup(); self.modalVisible=false end
            local function execute(fn)
                local worked,ok,err=pcall(fn)
                if worked and ok then self:cancelModal(); im.CloseCurrentPopup(); self.modalVisible=false
                else self.modalError=tostring(worked and (err or 'Не удалось сохранить изменения.') or ok);self:notify(self.modalError)end
            end
            if intent.kind=='warning'then
                local available=im.GetContentRegionAvail().x;local width=math.min(180,available)
                local cursor=im.GetCursorPosX();im.SetCursorPosX(cursor+(available-width)/2)
                if neutral('ОК##warning-ok',width)then self:ackWarning();im.CloseCurrentPopup()end
            elseif intent.kind=='changes' then
                local width=math.max(1,(im.GetContentRegionAvail().x-20)/3)
                local save=green('Сохранить##changes-save',width); im.SameLine(0,10)
                local discard=red('Отбросить##changes-discard',width); im.SameLine(0,10)
                local stay=neutral('Остаться##changes-stay',width)
                if stay then close()
                elseif save then execute(function()if self.pendingNavigation then return self:resolveNavigation(true,callbacks)end;return self:resolveSelection(true,callbacks)end)
                elseif discard then execute(function()if self.pendingNavigation then return self:resolveNavigation(false,callbacks)end;return self:resolveSelection(false,callbacks)end)end
            elseif intent.kind=='wanted_appearance_choice'or intent.kind=='wanted_appearance_input'then
                local a=self.wantedAppearance;local width=math.max(1,(im.GetContentRegionAvail().x-10)/2)
                local first=neutral((intent.kind=='wanted_appearance_choice'and 'Общая (без ввода)'or 'Далее · к выбору статьи')..'##wanted-appearance-first',width)
                im.SameLine(0,10)
                local second=neutral((intent.kind=='wanted_appearance_choice'and 'С приметами'or 'Назад')..'##wanted-appearance-second',width)
                if first or second then
                    local mode=intent.kind=='wanted_appearance_choice'and(first and 'general'or 'detailed')or(first and 'apply'or 'back')
                    local ok,why=callbacks.caseAppearance(a.form,mode)
                    if ok then
                        self.wantedAppearance=nil;self.modalToken=nil;im.CloseCurrentPopup();self.modalVisible=false
                    else self.modalError=why end
                end
            elseif intent.kind=='manual_action'then
                local width=math.max(1,im.GetContentRegionAvail().x)
                local yes=green(spec.buttons[1]..'##confirm-yes',width)
                local no=neutral(spec.buttons[2]..'##confirm-no',width)
                local cancel=red(spec.buttons[3]..'##confirm-cancel',width)
                if cancel then close();callbacks.stop()
                elseif yes or no then execute(function()return callbacks.manualActionDecide(self.manualAction.token,yes==true)end)end
            elseif intent.kind=='capture' then
                local capture=self.keyCapture
                local width=math.max(1,(im.GetContentRegionAvail().x-10)/2)
                local apply
                if capture.valid then apply=green('Назначить##capture-apply',width)
                else
                    local muted=im.ImVec4(.09,.14,.19,.48)
                    answer('Назначить##capture-apply',muted,muted,muted,width)
                    self:tooltip(ui,capture.error or 'Сначала нажмите свободную клавишу или сочетание.')
                end
                im.SameLine(0,10)
                local cancel=red('Отмена##capture-cancel',width)
                if cancel then close()
                elseif apply then execute(function() return callbacks.applyCapture(capture.request,capture.proposal) end) end
            else
                if confirmationBinding then
                    local value,changed=self:check('##bind-skip-confirmation',confirmationBinding.skip_confirmation==true)
                    im.SameLine(0,8);ui.text(spec.checkboxLabel)
                    if changed then
                        local ok,err=callbacks.setBindingConfirmation(confirmationBinding.id,value)
                        if not ok then self.modalError=tostring(err or'Не удалось сохранить настройку.')end
                    end
                end
                local width=math.max(1,(im.GetContentRegionAvail().x-10)/2)
                local yes=green((spec.buttons[1]or'ДА')..'##confirm-yes',width); im.SameLine(0,10)
                local no=red((spec.buttons[2]or'НЕТ')..'##confirm-no',width)
                if intent.kind=='manual_action'then
                    if no or yes then execute(function()return callbacks.manualActionDecide(self.manualAction.token,yes==true)end)end
                elseif no then close() elseif yes then execute(function() return self:acceptModal(data,callbacks) end) end
            end
        end
        ui.finish()
    else self.modalVisible=false end
    for _=1,depth do ui.finish() end
end
function Studio:draw(page,ui,data,callbacks)
    self.currentUi=ui
    self.settingTextChanged=false;self.preferenceContext=page=='profile'or page=='options'or page=='alerts'or page=='weapons'or page=='extras'or page=='map'
    self.currentNoticeScope=page
    self:queueStatus(ui,data,callbacks)
    if page=='binds'or page=='identity'or page=='procedures'then require('pa26_nearby').draw(self,ui,data,callbacks)end
    if page=='binds' then self:drawBindings(ui,data,callbacks)
    elseif page=='hints' then self:drawNotes(ui,data,callbacks,false)
    elseif page=='partners' then self:drawPartners(ui,data,callbacks)
    elseif page=='stats' then self:drawStats(ui,data,callbacks)
    elseif page=='profile' then self:drawProfile(ui,data,callbacks,'profile')
    elseif page=='options' then self:drawOptions(ui,data,callbacks)
    elseif page=='alerts' then self:drawAlerts(ui,data,callbacks)
    elseif page=='weapons' then self:drawWeapons(ui,data,callbacks)
    elseif page=='extras' then self:drawExtras(ui,data,callbacks)
    elseif page=='recruitment'then self:drawExtras(ui,data,callbacks,true)
    elseif page=='patrol'then patrolUi.draw(self,ui,data,callbacks)
    elseif page=='patrol_events'then eventUi.draw(self,ui,data,callbacks)
    elseif page=='vehicle'then vehicleUi.draw(self,ui,data,callbacks)
    elseif page=='map'then require('pa26_map_ui').draw(self,ui,data,callbacks)
    elseif page=='identity'then identityUi.draw(self,ui,data,callbacks)
    elseif page=='procedures'then caseUi.draw(self,ui,data,callbacks)
    elseif page=='operations'then operationUi.draw(self,ui,data,callbacks)end
end
return M

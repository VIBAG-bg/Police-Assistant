local model=require 'pa26_bindings'
local M={}
function M.draw(s,ui,data,cb,menu)
    local im=s.imgui;s.currentUi=ui;s.preferenceContext=true
    local layout=model.copy((s.autosaves and s.autosaves.window_layout and s.autosaves.window_layout.value)or s.lib.settings.window_layout)
    s:settingsHeading(ui,'Размер и положение окон')
    layout.remember=s:check('Сохранять выставленный размер и положение после перезахода##window-remember',layout.remember)
    layout.wanted_separate=s:check('Открывать розыск в отдельном окне##wanted-detached',layout.wanted_separate)
    ui.text('Начальный размер: '..layout.initial_percent..'% ширины и высоты экрана. После изменения мышью сохраняется именно ваш размер. При другом разрешении он пересчитывается пропорционально и остаётся в пределах экрана.')
    local percent=im.new.int(layout.initial_percent)
    im.PushItemWidth(math.max(1,im.GetContentRegionAvail().x));ui.push(function()im.PopItemWidth()end)
    if im.SliderInt('##window-initial-percent',percent,50,95)then layout.initial_percent=percent[0]end;ui.finish()
    if s:button('Применить начальный размер к главному окну##window-apply',ui)then
        layout.windows.main=nil;menu.windows.main=nil;menu.resetWindows=menu.resetWindows or{};menu.resetWindows.main=true
    end
    if s:button('Сбросить размеры и положения всех окон##window-reset',ui)then
        layout.windows={};menu.windows={};menu:resetWindowPositions()
    end
    s:autoSettings('window_layout',{'settings','window_layout'},layout)
    s:settingsHeading(ui,'Перенос ручного чата')
    local cfg=model.copy((s.autosaves and s.autosaves.manual_chat and s.autosaves.manual_chat.value)or s.lib.settings.manual_chat)
    cfg.enabled=s:check('Переносить длинный текст после Enter##manual-chat-enabled',cfg.enabled)
    ui.text('Обычная речь, /me, /do, /try, /todo и включённые каналы рации/OOC (в том числе /n). Целые слова, ... на стыках, акцент только в первой части обычной речи. Команды с аргументами не разделяются. Порог берётся из настроек переноса RP: сейчас '..s.lib.rp_text.body_limit..' символов. До первой отправки проверяются все части.')
    for _,row in ipairs({{'max_parts','Максимум частей (1–3)',1,3},{'interval_ms','Пауза между частями, мс',1000,10000}})do
        ui.text(row[2]);local n=im.new.int(cfg[row[1]])
        im.PushItemWidth(math.max(1,im.GetContentRegionAvail().x));ui.push(function()im.PopItemWidth()end)
        if im.SliderInt('##manual-chat-'..row[1],n,row[3],row[4])then cfg[row[1]]=n[0]end;ui.finish()
    end
    ui.text('Если текст не помещается, отправки не будет и ввод сохранится. Enter разрешает реальную отправку ручного текста. При разрыве связи или остановке остаток возвращается в черновик; уже отправленные части повторно не отправляются.')
    if s:button('Изменить порог и маркер продолжения##manual-chat-rp-settings',ui)then cb.openAssist('roleplay')end
    if data.manualChatDraft and data.manualChatDraft~=''then
        if s.manualDraftShown~=data.manualChatDraft then s.cache['manual:recovery']=nil;s.manualDraftShown=data.manualChatDraft end
        s:field('Сохранённый остаток · можно выделить и скопировать##manual-recovery','manual:recovery',data.manualChatDraft,8192,true,90)
    end
    s:autoSettings('manual_chat',{'settings','manual_chat'},cfg)
    s:autosaveHint(ui,'window_layout');s:autosaveHint(ui,'manual_chat')
end
return M

-- Presentation-only settings routes. Persistent keys and execution stay unchanged.
local menu=require 'pa26_menu'
local model=require 'pa26_bindings'
local themes=require 'pa26_theme'
local M={}
M.tabs={{'profile','1. Профиль'},{'chat','2. Чат и команды'},
    {'options','3. Управление и колесо'},{'radio','4. Рация и тревоги'},
    {'weapons','5. Оружие и тайзер'},{'general','6. Экран, HUD и карта'}}
local sectionNames={profile='Профиль',chat='Чат и команды',options='Управление и колесо',
    radio='Рация и тревоги',weapons='Оружие и тайзер',general='Экран, HUD и карта'}
local pageNames={accent='Акцент и .команды',split='Автоперенос и /todo',commands='Ручные команды',filters='Фильтры и CEF',
    emergency='Связь',session='Смена патруля',patrol='Таймер патруля',automatic='Автодоклады',
    windows='Окна и режим',hud='HUD',map='Карта',recovery='Восстановление'}
M.searchIndex={
    {'name','RP-имя и личное дело','profile',nil,'ник персонаж имя номер личное дело'},
    {'rank','Ведомство, звание и значок','profile',nil,'отдел должность ранг жетон номер значка'},
    {'duty-profiles','Быстрые профили службы','profile',nil,'пресет профиль сменить подразделение'},
    {'unit','Позывной и префиксы рации','profile',nil,'экипаж позывные тег local_tag global_tag prison_tag'},
    {'gender','Грамматический род','profile',nil,'пол мужской женский гендер'},
    {'timezone','Часовой пояс','profile',nil,'utc москва часы время'},
    {'plates','Город, сектор и номера транспорта','profile',nil,'госномер авто транспорт сектор'},
    {'accent','Акцент обычной речи','chat','accent','русский акцент префикс обыкновенный текст'},
    {'dots','Команды с точкой','chat','accent','перевод раскладка .к .ыефеы .команды'},
    {'radio-prefix','Префикс ручной рации','chat','accent','/r теги локальная волна'},
    {'split','Автоперенос ручного чата','chat','split','длинное сообщение разделить enter части'},
    {'todo','Лимит /todo и перенос RP','chat','split','отыгровки длина лимит символов'},
    {'continuation','Маркер продолжения и пауза между частями','chat','split','многоточие скорость интервал'},
    {'manual-rp','RP перед ручными командами','chat','commands','отыгровка действия /cuff /su /setmark'},
    {'command-reference','Справка серверных команд','chat','commands','команда зачем /ud /pt'},
    {'filters','Фильтры чата','chat','filters','скрыть префикс сообщения'},
    {'cef','CEF · чат лаунчера','chat','filters','cef мост лаунчер игровой чат'},
    {'cef-protection','Защита клавиш и индикатор раскладки CEF','chat','filters','cef оружие чат задержка язык'},
    {'cef-diagnostics','Диагностика подключения CEF','chat','filters','cef журнал производительность совместимость'},
    {'window-keys','Клавиши окон и отмены','options',nil,'f9 f4 быстрое меню клавиатура хоткей'},
    {'aim','Выбор человека ПКМ','options',nil,'прицел правой кнопкой мыши интерьеры удержание'},
    {'nearby','Люди рядом','options',nil,'радиус расстояние список люди вокруг'},
    {'wheel','Радиальное колесо X','options',nil,'колесо wheel категория перестановка'},
    {'two-wheels','Два колеса · пешком и в машине','options',nil,'колесо машина транспорт два'},
    {'wheel-actions','Встроенные действия и категории колеса','options',nil,'колесо назначение секция группы'},
    {'dutystate','На службе и канал рации','radio','emergency','связь канал доклад'},
    {'sos','SOS, Shots fired и CODE 0','radio','emergency','sos тревога помощь ранен код 0'},
    {'code','CODE 1 и CODE 4','radio','emergency','отмена тревоги помощь безопасность'},
    {'session','Смена патруля и восстановление','radio','session','начало экипаж автоюнит lincoln adam'},
    {'patrol-templates','Шаблоны патрульных докладов','radio','session','патруль фразы продолжение доклады'},
    {'patrol-timer','Таймер патруля и напоминания','radio','patrol','интервал таймер старый патруль'},
    {'automatic','Свои автодоклады и предупреждения','radio','automatic','f6 расписание автоматические доклады'},
    {'weapons','Отыгровки оружия','weapons',nil,'достать убрать пистолет оружие задержка'},
    {'taser','Тайзер и лимит выстрелов','weapons',nil,'тайзер tazer taser дегл заряды выстрелы'},
    {'weapon-warning','Предупреждения об оружии','weapons',nil,'предупреждение напоминание оружие'},
    {'theme','Тема оформления','general','windows','цвет темы палитра полиция swat fbi алькатрас'},
    {'opacity','Непрозрачность и компактные отступы','general','windows','прозрачность плотность масштаб'},
    {'icons','Иконки интерфейса','general','windows','font awesome значки колесо'},
    {'size','Размеры и положения окон','general','windows','сброс окно геометрия разрешение'},
    {'mode','Реальный и демонстрационный режим','general','windows','демо включение режим'},
    {'hud','Виджет HUD','general','hud','hud оверлей виджет положение часы'},
    {'key-hints','Подсказки клавиш','general','hud','горячие клавиши оверлей инструкции'},
    {'map','Квадраты карты и радар','general','map','esc карта сетка сектор координаты'},
    {'map-labels','Цвет и подписи клеток','general','map','карта размер альфа линии'},
    {'recovery','Восстановление интерфейса','general','recovery','восстановить сбой окна повтор'},
}
local searchable={}
local function fold(s)return model.casefold(s):gsub('ё','е'):gsub('%s+',' '):match('^%s*(.-)%s*$')end
for _,row in ipairs(M.searchIndex)do
    local path=sectionNames[row[3]]..(row[4]and' → '..pageNames[row[4]]or'')
    searchable[#searchable+1]={id=row[1],label=row[2],tab=row[3],page=row[4],path=path,
        title=fold(row[2]),words=fold(row[2]..' '..row[5])}
end
function M.search(query)
    local needle=fold(query or '')
    if needle==''then return {}end
    local matches={}
    for i,entry in ipairs(searchable)do
        local found=true
        for token in needle:gmatch('%S+')do
            if not entry.words:find(token,1,true)then found=false;break end
        end
        if found then
            local at=entry.title:find(needle,1,true)
            matches[#matches+1]={index=i,rank=at==1 and 0 or at and 1 or 2,entry=entry}
        end
    end
    table.sort(matches,function(a,b)return a.rank<b.rank or a.rank==b.rank and a.index<b.index end)
    local result={}
    for i=1,math.min(8,#matches)do result[i]=matches[i].entry end
    return result
end
function M.route(tab)
    if tab=='display'then return 'general','windows'end
    if tab=='map'then return 'general','map'end
    for _,row in ipairs(M.tabs)do if row[1]==tab then return tab end end
    return 'profile'
end
function M.tabLayout(width,font)
    local available=math.max(1,width-16)
    local columns=available>=1100 and 6 or 3
    local w=math.max(1,math.floor((available-(columns-1)*8)/columns))
    local height=38
    for _,row in ipairs(M.tabs)do
        height=math.max(height,menu.labelLayout(font,tonumber(font.FontSize),math.max(1,w-28),row[2]).height+16)
    end
    local rows=math.ceil(#M.tabs/columns)
    local tabsHeight=rows*height+(rows-1)*8
    return {width=w,height=height,columns=columns,tabsHeight=tabsHeight,total=16+tabsHeight+math.max(46,tonumber(font.FontSize)+30)}
end
local searchKey='settings:quick-search'
local function searchInput(s,ui)
    local im=s.imgui
    local buffer=s:buffer(searchKey,s.settingsSearch or '',256)
    local width=im.GetContentRegionAvail().x
    im.PushItemWidth(math.max(1,width-42));ui.push(function()im.PopItemWidth()end)
    if im.InputTextWithHint then im.InputTextWithHint('##settings-search','Найти настройку...',buffer,256)
    else im.InputText('Найти настройку...##settings-search',buffer,256)end
    ui.finish()
    s.settingsSearch=s.ffi.string(buffer)
    if s.settingsSearch~=''then
        im.SameLine(0,6)
        if menu.fittedButton(im,ui,'×##settings-search-clear',im.ImVec2(36,30))then
            s:setBuffer(searchKey,'',256);s.settingsSearch=''
        end
    end
end
function M.drawTabs(s,ui,active,select,font)
    local im=s.imgui;local layout=M.tabLayout(im.GetContentRegionAvail().x+16,font or im.GetFont())
    active=M.route(active)
    local origin=im.GetCursorPos()
    for index,row in ipairs(M.tabs)do
        local column=(index-1)%layout.columns;local rowIndex=math.floor((index-1)/layout.columns)
        im.SetCursorPos(im.ImVec2(origin.x+column*(layout.width+8),origin.y+rowIndex*(layout.height+8)))
        local p=ui.theme or themes.get(s.lib.settings.theme)
        if active==row[1]then im.PushStyleColor(im.Col.Button,themes.vec(im,p.btnPrimary));ui.push(function()im.PopStyleColor(1)end)end
        if menu.fittedButton(im,ui,row[2]..'##settings-tab-'..row[1],im.ImVec2(layout.width,layout.height),font)then select(row[1])end
        if active==row[1]then ui.finish()end
    end
    im.SetCursorPos(im.ImVec2(origin.x,origin.y+layout.tabsHeight+8))
    searchInput(s,ui)
end
local function choose(s,ui,key,value,items)
    return menu.choiceControl(s.imgui,ui,'##'..key,'',value,items,s,{buttons=true,font=s.buttonFont})
end
function M.chat(s,ui,data,callbacks,ctx)
    s.chatSettingsPage=choose(s,ui,'chat-settings-page',s.chatSettingsPage or'accent',
        {{'accent','Акцент, .команды и рация'},{'split','Автоперенос и /todo'},
            {'commands','RP перед ручными командами'},{'filters','Фильтры и чат лаунчера (CEF)'}})
    if s.chatSettingsPage=='accent'then s:drawProfile(ui,data,callbacks,'chat_accent')
    elseif s.chatSettingsPage=='split'then
        require('pa26_interface_settings').draw(s,ui,data,callbacks,ctx.menu,'chat')
        require('pa26_rp_ui').draw(s,ui,data,callbacks)
    elseif s.chatSettingsPage=='commands'then
        require('pa26_manual_actions').draw(s,ui)
        if s:button((s.showServerReference and'Скрыть справку и сверку команд'or'Справка и сверка серверных команд')..'##chat-server-reference',ui)then s.showServerReference=not s.showServerReference end
        if s.showServerReference then require('pa26_server_commands').draw(s,ui,data,callbacks,true)end
    else
        s:drawFilters(ui,data,callbacks)
        s:drawProfile(ui,data,callbacks,'chat_cef')
    end
end
function M.draw(s,ui,data,callbacks,tab,ctx)
    local query=s.settingsSearch or ''
    if query:find('%S')then
        if s.settingsSearchKey~=query then
            s.settingsSearchKey=query;s.settingsSearchMatches=M.search(query)
            if s.imgui.SetScrollY then s.imgui.SetScrollY(0)end
        end
        if #s.settingsSearchMatches==0 then ui.text('Настройки не найдены.')end
        for _,entry in ipairs(s.settingsSearchMatches)do
            if s:button(entry.path..' · '..entry.label..'##settings-result-'..entry.id,ui)then
                s:setBuffer(searchKey,'',256);s.settingsSearch=''
                if callbacks.openSettings then callbacks.openSettings(entry.tab,entry.page)end
                if s.imgui.SetScrollY then s.imgui.SetScrollY(0)end
                return
            end
        end
        return
    end
    local page,sub=M.route(tab)
    if sub then s.screenSettingsPage=sub end
    s.currentUi=ui;s.preferenceContext=true;s.settingTextChanged=false;s.currentNoticeScope='settings'
    if page=='profile'then s:drawProfile(ui,data,callbacks,'profile')
    elseif page=='chat'then M.chat(s,ui,data,callbacks,ctx)
    elseif page=='options'then
        ctx.general('controls')
        s:drawOptions(ui,data,callbacks,'controls')
    elseif page=='radio'then s:drawAlerts(ui,data,callbacks)
    elseif page=='weapons'then s:drawWeapons(ui,data,callbacks)
    else
        s.screenSettingsPage=choose(s,ui,'screen-settings-page',s.screenSettingsPage or'windows',
            {{'windows','Окна и режим'},{'hud','HUD'},{'map','Карта'},{'recovery','Восстановление'}})
        if s.screenSettingsPage=='windows'then
            ctx.general('mode')
            require('pa26_interface_settings').draw(s,ui,data,callbacks,ctx.menu,'windows')
            s:drawOptions(ui,data,callbacks,'appearance')
        elseif s.screenSettingsPage=='hud'then
            ctx.general('hud')
            if callbacks.openInstructions then require('pa26_help').settings(s,ui,callbacks)end
        elseif s.screenSettingsPage=='map'then require('pa26_map_ui').draw(s,ui,data,callbacks)
        else ctx.general('recovery')end
    end
    s.preferenceContext=nil
end

local actionSections={
    {'emergency','Экстренные и связь',{'sos','shots','code0','pa-share-coordinates','pa-call911','copilot-call911','copilot-arrived'}},
    {'patrol','Патруль и смена',{'patrol-open','patrol-pause','patrol-resume','patrol-finish','pa-patrol-busy','copilot-patrol_continue'}},
    {'procedures','Розыск, штрафы и процедуры',{'procedure-wanted','procedure-wanted_list','procedure-fine','procedure-mark','pa-fast-wanted','pa-bulletins','pa-vehicle-bulletins','pa-custody-timers','copilot-fast_wanted','copilot-fast_pt','copilot-pursuit_mark'}},
    {'traffic','Трафик, мегафон и Copilot',{}},
}
local actionSectionById={}
for i,section in ipairs(actionSections)do
    for _,id in ipairs(section[3])do actionSectionById[id]=i end
end
function M.groupWheelActions(rows)
    local groups={}
    for i,section in ipairs(actionSections)do groups[i]={id=section[1],title=section[2],rows={}}end
    for _,row in ipairs(rows)do
        local group=groups[actionSectionById[row[1]] or 4]
        group.rows[#group.rows+1]=row
    end
    return groups
end
local wheelActionGroups
function M.drawWheelActions(s,ui,wheel,scope,settings)
    wheelActionGroups=wheelActionGroups or M.groupWheelActions(wheel.systemRows)
    local im=s.imgui
    s.wheelActionsOpen=s.wheelActionsOpen or {}
    local choices=wheel.systemCategoryChoices(settings.wheel_names)
    for _,group in ipairs(wheelActionGroups)do
        local key=scope..'-'..group.id
        local marker=s.wheelActionsOpen[key] and '− 'or '+ '
        if s:button(marker..group.title..'##wheel-system-group-'..key,ui)then s.wheelActionsOpen[key]=not s.wheelActionsOpen[key]end
        if s.wheelActionsOpen[key]then
            local two=im.GetContentRegionAvail().x>=620
            if two then im.Columns(2,'wheel-actions-'..key,false);ui.push(function()im.Columns(1)end)end
            for _,row in ipairs(group.rows)do
                local value,edited=s:choice(row[2]..'##wheel-system-'..row[1],settings.wheel_system_groups[row[1]] or 'auto',choices,ui)
                if edited then settings.wheel_system_groups[row[1]]=value~='auto'and value or nil end
                if two then im.NextColumn()end
            end
            if two then ui.finish()end
        end
    end
end
return M

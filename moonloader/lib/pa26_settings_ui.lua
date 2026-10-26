-- Presentation-only settings routes. Persistent keys and execution stay unchanged.
local menu=require 'pa26_menu'
local M={}
M.tabs={{'profile','1. Профиль'},{'chat','2. Чат и команды'},
    {'options','3. Управление и колесо'},{'radio','4. Рация и тревоги'},
    {'weapons','5. Оружие и тайзер'},{'general','6. Экран, HUD и карта'}}
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
    return {width=w,height=height,columns=columns,total=16+rows*height+(rows-1)*8}
end
function M.drawTabs(s,ui,active,select,font)
    local im=s.imgui;local layout=M.tabLayout(im.GetContentRegionAvail().x+16,font or im.GetFont())
    active=M.route(active)
    local origin=im.GetCursorPos()
    for index,row in ipairs(M.tabs)do
        local column=(index-1)%layout.columns;local rowIndex=math.floor((index-1)/layout.columns)
        im.SetCursorPos(im.ImVec2(origin.x+column*(layout.width+8),origin.y+rowIndex*(layout.height+8)))
        if active==row[1]then im.PushStyleColor(im.Col.Button,im.ImVec4(.08,.48,.66,.96));ui.push(function()im.PopStyleColor(1)end)end
        if menu.fittedButton(im,ui,row[2]..'##settings-tab-'..row[1],im.ImVec2(layout.width,layout.height),font)then select(row[1])end
        if active==row[1]then ui.finish()end
    end
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
        elseif s.screenSettingsPage=='hud'then ctx.general('hud')
        elseif s.screenSettingsPage=='map'then require('pa26_map_ui').draw(s,ui,data,callbacks)
        else ctx.general('recovery')end
    end
    s.preferenceContext=nil
end
return M

-- Exercise visible controls rather than mutating private navigation state.
local M={}
function M.click(s,label)
    s.click=label;s.render();eq(s.click,nil,'Missing control: '..label)
    check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'))
    eq(#s.scopes,0);eq(s.invalidIOReads,0)
end
function M.settings(s,key)
    s.page('settings')
    local names={profile='1. Профиль',chat='2. Чат и команды',options='3. Управление и колесо',
        radio='4. Рация и тревоги',weapons='5. Оружие и тайзер',general='6. Экран, HUD и карта'}
    M.click(s,assert(names[key])..'##settings-tab-'..key)
end
function M.id(s,suffix)
    s.buttonCalls={};s.render()
    local found
    for _,b in ipairs(s.buttonCalls)do if b.label:sub(-#suffix)==suffix then found=b.label end end
    M.click(s,assert(found,'Missing visible button '..suffix))
end
function M.chat(s,key)
    M.settings(s,'chat')
    local names={accent='Акцент, .команды и рация',split='Автоперенос и /todo',commands='RP перед ручными командами',filters='Фильтры и чат лаунчера (CEF)'}
    M.click(s,assert(names[key])..'##chat-settings-page'..key)
end
function M.screen(s,key)
    M.settings(s,'general')
    local names={windows='Окна и режим',hud='HUD',map='Карта',recovery='Восстановление'}
    M.click(s,assert(names[key])..'##screen-settings-page'..key)
end
function M.operations(s)
    s.page('stats');M.click(s,'Команды и ответы сервера##История работы##stats-pageoperations')
end
return M

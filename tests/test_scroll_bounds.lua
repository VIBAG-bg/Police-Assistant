local fixture=require 'support.fixture';local bit=require 'bit'
for _,display in ipairs({{640,480},{1280,720},{2560,1440}})do
    local s=fixture({demo=false});s.step();s.io.DisplaySize.x,s.io.DisplaySize.y=display[1],display[2]
    for _,row in ipairs({{'pa26quick','quick','Police Assistant · Быстрое меню##pa26-quick'},
        {'pa26tips','tips','Police Assistant · Памятки##pa26-tips'},
        {'helpers','assist','Police Assistant · Помощники##pa26-assist'}})do
        if row[1]=='helpers'then onWindowMessage(0x100,0x73,0);onWindowMessage(0x101,0x73,0);s.step()else s.commands[row[1]]();s.step()end
        local window=s.windows[row[3]];check(window,row[3]);check(bit.band(window.flags,s.imgui.WindowFlags.NoScrollbar)~=0)
        check(bit.band(window.flags,s.imgui.WindowFlags.NoScrollWithMouse)~=0,'resize handles must never create a scroll range')
        local body
        for _,child in ipairs(s.childCalls)do if child.name=='workspace-content##'..row[2]then body=child end end
        check(body);eq(body.window,row[3]);check(bit.band(body.flags,s.imgui.WindowFlags.NoScrollWithMouse)==0,'content retains native bounded scrolling')
        for _,button in ipairs(s.buttonCalls)do if button.window==row[3]and button.label:match('^##resize%-')then check(button.parent~='workspace-content##'..row[2])end end
        eq(#s.scopes,0);check(not s.hasLog('Ошибка интерфейса'))
    end
    eq(#s.sent,0);onScriptTerminate(s.script)
end

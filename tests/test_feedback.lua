local module=require 'pa26_feedback'
local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local bit=require 'bit'
local q=module.new()
check(not q:push(''));check(q:push('Нужна рация.','vehicle'));check(not q:push('Нужна рация.','vehicle'))
local first=q:peek();for i=1,100 do q:push('Ошибка '..i,'scope')end
eq(#q.queue,module.MAX_PENDING);eq(q:peek(),first);check(q:ack());eq(q:peek().message,'Ошибка 1')
q:clear();check(not q:peek());check(q:once('state','Ошибка.','x'));q:ack();check(not q:once('state','Ошибка.','x'))
q:once('state',nil,'x');check(q:once('state','Ошибка.','x'));q:clear();check(q:push('\255','x'));check(require('pa26_core').validUtf8(q:peek().message))
local function findButton(s,id)
    for i=#s.buttonCalls,1,-1 do if s.buttonCalls[i].label==id then return s.buttonCalls[i]end end
end
local s=fixture({demo=false});s.step();s.commands.pa26();s.step()
onWindowMessage(0x100,0x73,0);onWindowMessage(0x101,0x73,0);s.step()
check(s.windows['Police Assistant · Помощники##pa26-assist'])
require('support.ui_routes').id(s,'##assist-tabsmegaphone')
local phrase=s.workspace.library.vehicle.phrases[1]
s.click=phrase.name..'##assist-say-1';s.render();check(s.workspace.studio:hasWarning());eq(#s.sent,0)
local warning=s.workspace.studio.feedback:peek();check(warning.message:find('Мегафон недоступен',1,true))
check(findButton(s,'ОК##warning-ok'));check(not findButton(s,'ДА##confirm-yes'));check(not findButton(s,'НЕТ##confirm-no'))
local popup=s.windows['Подтверждение##pa26-confirm'];check(popup)
eq(popup.x+popup.width/2,s.io.DisplaySize.x/2);eq(popup.y+popup.height/2,s.io.DisplaySize.y/2)
check(bit.band(popup.flags,s.imgui.WindowFlags.NoScrollbar)~=0);check(bit.band(popup.flags,s.imgui.WindowFlags.NoScrollWithMouse)~=0)
s.step(10000);check(s.workspace.studio:hasWarning(),'warning does not disappear before acknowledgement')
local text=s.workspace.studio.feedback:peek().message;s.workspace.studio:notify(text,'vehicle',false);eq(#s.workspace.studio.feedback.queue,1)
s.click='ОК##warning-ok';s.render();check(not s.workspace.studio:hasWarning());eq(#s.sent,0)
s.click=phrase.name..'##assist-say-1';s.render();check(s.workspace.studio:hasWarning(),'an explicit retry may show the reason again')
s.down[27]=true;onWindowMessage(0x100,27,0);s.step();check(not s.workspace.studio:hasWarning());s.down[27]=false;s.step()
-- An acknowledged error preserves the underlying decision and user draft.
local studio=s.workspace.studio;studio.pendingSelection=1;studio.dirty=true
studio.draft=model.copy(s.workspace.library.bindings[2]);studio.draft.script='Не потерять текст.'
studio:notify('Не получилось сохранить.','binds');s.render();check(studio:hasWarning());eq(studio.pendingSelection,1)
local ok=studio:acceptModal(nil,{});check(not ok,'warning cannot confirm the hidden action')
s.down[0x59]=true;s.step();eq(studio.pendingSelection,1);eq(#s.sent,0)
s.down[0x59]=false;s.click='ОК##warning-ok';s.render();s.render();eq(studio.pendingSelection,1);eq(studio.draft.script,'Не потерять текст.')
check(findButton(s,'Сохранить##changes-save'));studio:cancelModal();studio.dirty=false
-- Explicit success is acknowledged too; popup works with every PA window closed.
s.down[27]=true;onWindowMessage(0x100,27,0);s.step();s.down[27]=false;onWindowMessage(0x101,27,0);s.step()
studio:notify('Сохранено.','profile',false,'info');check(studio:hasWarning());s.render();s.click='ОК##warning-ok';s.render();check(not studio:hasWarning())
studio:notify('Самостоятельное предупреждение.','system',false);s.step();check(findButton(s,'ОК##warning-ok'));check(s.windows['PA##warning-host'])
s.click='ОК##warning-ok';s.render();eq(#s.sent,0);eq(#s.scopes,0);check(not s.hasLog('Ошибка интерфейса'))
onScriptTerminate(s.script)
-- Very long text uses the existing page layout, never inner scrolling.
for _,display in ipairs({{640,480},{1280,720},{2560,1440}})do
    s=fixture({demo=false});s.step();s.io.DisplaySize.x,s.io.DisplaySize.y=display[1],display[2]
    s.workspace.studio:notify(string.rep('Полный текст предупреждения без обрезки. ',400),'system',false);s.render()
    popup=s.windows['Подтверждение##pa26-confirm'];check(popup);check(popup.width<=display[1]-32);check(popup.height<=display[2]-32)
    check(findButton(s,'ОК##warning-ok'));check(findButton(s,'Далее##confirmation-page'))
    eq(#s.scopes,0);eq(#s.sent,0);onScriptTerminate(s.script)
end

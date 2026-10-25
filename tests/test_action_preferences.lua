local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local binder=require 'pa26_binder'
local path='moonloader\\config\\police_assistant_2026_library.json'
local lib=model.defaults(core.defaults());local b=model.newBinding(7);b.name='Проверка подтверждений';b.script='/r Проверка.'
lib.bindings[#lib.bindings+1]=b;lib.next_id=8
local legacy=model.copy(b);legacy.skip_confirmation=nil;legacy.no_accent=nil
local clean=assert(model.validateBinding(legacy));eq(clean.skip_confirmation,false);eq(clean.no_accent,false)
for _,key in ipairs({'skip_confirmation','no_accent'})do local bad=model.copy(b);bad[key]='true';check(not model.validateBinding(bad))end
local s=fixture({demo=false,library=lib});s.step()
local function render()s.render();check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0)end
local function launch()s.commands.pa26run('7');s.step();s.step(150);render()end
launch();check(s.workspace.studio.confirmPlan);eq(#s.sent,0)
s.libraryWriteFail=true;s.toggle='##bind-skip-confirmation';render()
check(not model.find(s.workspace.library,7).skip_confirmation);check(s.workspace.studio.confirmPlan);eq(#s.sent,0)
s.libraryWriteFail=false;s.workspace.studio.modalError=nil
s.toggle='##bind-skip-confirmation';render()
check(model.find(s.workspace.library,7).skip_confirmation)
check(model.find(s.savedLibrary(),7).skip_confirmation)
check(s.workspace.studio.confirmPlan,'Saving the checkbox preserves the current question; it never means YES')
eq(#s.sent,0)
s.click='НЕТ##confirm-no';render();s.step();eq(#s.sent,0)
launch();check(not s.workspace.studio.confirmPlan);check(#s.sent==1)
eq(s.sent[1].line,'/r Проверка.')
check(s.workspace:setBindingConfirmation(7,false))
launch();check(s.workspace.studio.confirmPlan);eq(#s.sent,1)
s.click='НЕТ##confirm-no';render();s.step()

-- Sync the modal choice into a dirty editor without saving unrelated fields.
s.commands.pa26();s.step();s.page('binds');s.workspace.studio:select(7);s.workspace.studio.bindPane='editor';s.workspace.studio.editorTab='text';render()
s.edits={['##script']='/r Несохранённый текст.'};render();check(s.workspace.studio.dirty)
local source=s.workspace.studio.draft.script
check(s.workspace:setBindingConfirmation(7,true));eq(s.workspace.studio.draft.script,source)
check(s.workspace.studio.dirty);check(s.workspace.studio.draft.skip_confirmation)
eq(model.find(s.workspace.library,7).script,'/r Проверка.')

-- Small windows retain the entire UTF-8 buffer and provide a wrapped view.
s.workspace.studio.editor='steps'
for _,display in ipairs({{640,480},{800,600},{1280,720}})do
    s.io.DisplaySize.x,s.io.DisplaySize.y=display[1],display[2]
    local long=string.rep('Очень длинная реплика саспекту. ',100):match('^(.-)%s*$')
    render();s.edits={['##textstep1']=long};render();render()
    local draft=s.workspace.studio.draft;local steps=assert(binder.parseEditor(draft.script))
    eq(#steps,1);eq(steps[1].template,long)
    local full=false;for _,child in ipairs(s.childCalls)do if child.name=='step-preview##1'then full=true end end
    check(full,'The complete text is available with visual wrapping, without adding executable newlines')
end
local savedBindingLibrary=s.savedLibrary()
onScriptTerminate(s.script)
-- The small checkbox on the real warning surface persists the same preference
-- as settings, refreshes the preview/token, and never sends on its own.
local seed=model.defaults(core.defaults());seed.profile.accent='[Армянский акцент]:'
seed.weapon_warning.trigger='stable';seed.weapon_warning.mode='confirm'
seed.weapon_warning.firearm_template=string.rep('Саспект, остановитесь и опустите оружие. ',5):match('^(.-)%s*$')
s=fixture({demo=false,alerts=true,notifications=true,categoryWheel=true,library=seed});s.step()
if s.frames[1].condition()then s.commands.pa26();s.step()end
s.weapon=31;s.step();for _=1,5 do s.step(1000)end
check(s.weaponWarning.pending);check(s.notifications.buttons.accent);eq(#s.sent,0)
local token=s.weaponWarning.pending.token
s.notifications.intent={kind='accent',token=token,value=true,at=s.now};s.step(16)
check(s.workspace.library.weapon_warning.no_accent);check(s.savedLibrary().weapon_warning.no_accent)
eq(s.workspace.library.profile.accent,seed.profile.accent);eq(#s.sent,0)
check(s.weaponWarning.pending.token~=token)
token=s.weaponWarning.pending.token;s.weaponWarning:shown(token);check(s.weaponWarning:decide(token,true))
for _=1,12 do s.step(1500)end
check(#s.sent>1,'All parts of a long warning must reach the shared executor')
for _,row in ipairs(s.sent)do
    check(row.line:match('^/s '));check(#codec.encode(row.line:sub(4))<=90);check(not row.line:find('акцент',1,true))
end
check(not s.workspace.executor.queue);check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)
onScriptTerminate(s.script)
s=fixture({demo=false,library=savedBindingLibrary});s.step()
check(model.find(s.workspace.library,7).skip_confirmation,'The preference survives reloading')
-- Missing required arguments remain a hard stop even without a dialog.
local candidate=model.copy(s.workspace.library);local required=model.find(candidate,7)
required.parameters={{name='reason',label='Причина',type='text',required=true,default=''}};required.script='/r {param:reason}'
check(s.workspace:save(candidate));s.commands.pa26run('7');s.step();s.step(150)
eq(#s.sent,0);check(not s.workspace.executor.queue)
onScriptTerminate(s.script)

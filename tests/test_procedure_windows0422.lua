local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local function setup(demo)
 local lib=model.defaults(core.defaults());lib.procedures.enabled=true;lib.procedures.mark_command='/setmark {id}';lib.procedures.mark_verified=true;lib.procedures.mark_source='User confirmed'
 local s=fixture({productionWindows=true,demo=demo==true,library=lib,alerts=true,categoryWheel=true});s.step()
 if s.frames[1].condition()then s.commands.pa26();s.step()end;return s
end
local function click(s,label)s.click=label;s.render();eq(s.click,nil,'Missing: '..label);check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)end
for _,demo in ipairs({false,true})do
 local s=setup(demo);s.commands.ticket('37 150 Красный сигнал');s.step();s.step()
 check(s.windows['Police Assistant · Штраф (/ticket)##pa26-fine']);check(not s.frames[1].condition());eq(#s.sent,0)
 local f=s.workspace.studio.caseForm;check(f);eq(f.kind,'fine');eq(f.target.id,37);eq(f.amount,'150');eq(f.basis,'Красный сигнал')
 f.passport_seen='yes';f.ic_name='Driver Name';f.mask='no';s.render()
 click(s,'Далее · основание##fine-next-identity');eq(f.stage,'basis')
 click(s,'Проверить текст##fine-preview');eq(f.stage,'preview')
 click(s,'Отыграть · затем подтвердить команду##procedure-send-fine')
 check(s.workspace.studio.caseConfirm)
 -- Exactly one RP phase; a separate server-command confirmation follows.
 click(s,'ДА##confirm-yes')
 for _=1,24 do s.step(1600);if s.workspace.studio.caseConfirm then break end end
 check(s.workspace.studio.caseConfirm);eq(s.workspace.studio.caseConfirm.phase,'command')
 for _,line in ipairs(s.sent)do check(not line.line:match('^/ticket '))end
 click(s,'ДА — выписать штраф##confirm-yes');s.step();s.step(1800)
 if demo then eq(#s.sent,0)else eq(s.sent[#s.sent].line,'/ticket 37 150 Красный сигнал')end
 check(not s.frames[1].condition())
 onScriptTerminate(s.script)
end
local s=setup(false);s.streamed=false;s.distance=5000;s.commands.setmark('37');s.step();s.step()
check(s.windows['Police Assistant · Пеленгация (/setmark)##pa26-mark']);check(not s.frames[1].condition());eq(#s.sent,0)
local f=s.workspace.studio.caseForm;eq(f.kind,'mark');eq(f.target.id,37)
s.edits={['##Известный IC-номер телефона##procedure-phone_number']='555123',['##Уточнить источник номера##procedure-phone_source']='Мой IC-источник'};f.phone_known='yes';f.phone_active='yes';s.render();s.edits={};s.render();eq(f.phone_source,'Мой IC-источник')
click(s,'Далее · исходный розыск##mark-next-phone');f.prior_ic_stars='unknown';s.render();eq(f.stage,'basis')
f.prior_ic_stars='yes';s.render();click(s,'Подготовить RP и команду##mark-preview');eq(f.stage,'preview')
eq(#s.sent,0);check(not s.hasLog('Ошибка интерфейса'));onScriptTerminate(s.script)
s=setup(false);s.distance=5000;s.streamed=false;s.commands.ticket('37');s.step();s.step();eq(#s.sent,0);check(not s.workspace.studio.caseForm);onScriptTerminate(s.script)

-- Both incoming chat backends use one mailbox and never repeat a CEF event.
s=setup(false);local bridge=s.chatBridge
local event={id=1,kind='local',text='/ticket 37 150 Проверенное основание',session=bridge.env.session()}
local payload=encodeJson({schema=1,page='procedures-cef',chat=false,dialog=false,busy=false,events={event}})
check(bridge:exchange(payload,s.now),'CEF exchange rejected');s.step();s.step();local first=s.workspace.studio.caseForm;check(first);eq(first.kind,'fine')
check(bridge:exchange(payload,s.now));s.step();eq(s.workspace.studio.caseForm,first);eq(#s.sent,0);onScriptTerminate(s.script)

-- OOC tracking reuses the persisted existing chain; no automatic /clear or /pt.
s=setup(false);s.commands.setmark('37');s.step();s.step();f=s.workspace.studio.caseForm
s.edits={['##Известный IC-номер телефона##procedure-phone_number']='555123',['##Уточнить источник номера##procedure-phone_source']='Материалы дела'}
f.phone_known='yes';f.phone_active='yes';s.render();s.edits={};click(s,'Далее · исходный розыск##mark-next-phone')
f.prior_ic_stars='no';f.reason_id='08.02';f.life_ack=true;f.ooc_ack=true;s.render()
click(s,'Подготовить RP и команду##mark-preview');check(s.workspace.studio.caseConfirm);eq(s.workspace.studio.caseConfirm.form.host,'mark')
click(s,'ДА##confirm-yes')
for _=1,24 do s.step(1600);if s.workspace.studio.caseConfirm then break end end
check(s.workspace.studio.caseConfirm);click(s,'ДА — выдать розыск##confirm-yes');s.step();s.step(1800)
local reminders=s.caseForms:view().reminders;eq(#reminders,1);eq(reminders[1].status,'check');eq(s.sent[#s.sent].line,'/su 37 8 2')
for _,row in ipairs(s.sent)do check(not row.line:match('^/clear '));check(not row.line:match('^/pt '));check(not row.line:match('^/setmark '))end
s.commands.setmark('37');s.step();s.step();local token=reminders[1].token
check(s.caseForms:changeReminder(token,'issued'));s.render()
check(not s.caseForms:chainOffer(token,'clear',true),'A sent /su does not prove tracking has completed')
local plan=assert(s.caseForms:chainOffer(token,'mark',true));check(plan.form.chain_token==token)
check(not s.caseForms:chainOffer(token,'clear',true));eq(#s.caseForms:view().reminders,1)
check(not s.hasLog('Ошибка интерфейса'));eq(s.invalidIOReads,0);onScriptTerminate(s.script)

-- Separate settings use the same delayed, atomic library saves as the main UI.
s=setup(false);s.commands.ticket('37');s.step();s.step()
s.workspace.studio.finePage='settings';s.render()
s.intEdits={['##procedure-pm']=100};s.render();s.intEdits={};s.step(50)
eq(s.workspace.library.procedures.pm_rate,100);eq(s.savedLibrary().procedures.pm_rate,100)
local own='/me {gender:оформил|оформила} постановление на имя {ic_name}.'
s.edits={['##Штраф · паспортные данные##procedure-rp-fine_passport_rp']=own};s.render();s.edits={}
local pending=s.workspace.studio.autosaves.procedures
check(pending,'Changed RP text must schedule a save');eq(pending.delay,600)
check(s.workspace.library.procedures.fine_passport_rp~=own)
s.step(400);check(s.workspace.library.procedures.fine_passport_rp~=own)
s.step(250);eq(s.workspace.library.procedures.fine_passport_rp,own);eq(s.savedLibrary().procedures.fine_passport_rp,own)
eq(#s.sent,0);check(not s.hasLog('Ошибка интерфейса'));eq(s.invalidIOReads,0);onScriptTerminate(s.script)

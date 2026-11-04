local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local function click(s,label)s.click=label;s.render();eq(s.click,nil,label);check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0)end
for _,wh in ipairs({{1152,864},{1366,768},{1920,1080},{2560,1440}})do
 local lib=model.defaults(core.defaults());lib.profile.gender='female'
 local s=fixture({library=lib,demo=false,productionWindows=true,copilot=true});s.io.DisplaySize.x=wh[1];s.io.DisplaySize.y=wh[2]
 s.step();if not s.frames[1].condition()then s.commands.pa26();s.step()end
 s.page('addons');click(s,'Навигация и инструменты##toolfield')
 local studio=s.workspace.studio
 for _,page in ipairs({'navigation','coordinates','cruiser','pinned','leadership'})do studio.fieldPage=page;s.render();check(not s.hasLog('Ошибка интерфейса'),page..' '..table.concat(s.logs,'\n'));eq(#s.scopes,0)end
 studio.fieldPage='coordinates';s.render();s.edits={['##Телефон получателя /sms##coord-phone']='123456'};s.render();s.edits={};s.step(700)
 eq(s.workspace.library.field.coordinates.phone,'123456');eq(s.savedLibrary().field.coordinates.phone,'123456')
 eq(#s.sent,0);s.ackInfo()
 -- Esc ownership: consume the whole first physical key cycle, not the next one.
 onWindowMessage(0x100,0x1b,0);check(not s.frames[1].condition());local before=s.consumed
 onWindowMessage(0x100,0x1b,0);check(s.consumed>before);onWindowMessage(0x101,0x1b,0);before=s.consumed
 onWindowMessage(0x100,0x1b,0);eq(s.consumed,before,'Next distinct Esc belongs to GTA');onWindowMessage(0x101,0x1b,0)
 s.physicalDown={[0x73]=true};s.step();s.physicalDown={};s.step();check(s.frames[4].condition())
 onWindowMessage(0x100,0x1b,0);check(not s.frames[4].condition());onWindowMessage(0x101,0x1b,0)
 s.chat=true;before=s.consumed;onWindowMessage(0x100,0x1b,0);eq(s.consumed,before);onWindowMessage(0x101,0x1b,0);s.chat=false
 eq(#s.sent,0);onScriptTerminate(s.script)
end
local setup=require 'support.copilot_fixture'
for _,gender in ipairs({'male','female'})do for _,id in ipairs({411,522,481,4000,593})do
 local cp,v,s=setup();s.state.gender=gender;s.profile.gender=gender;s.car.model_id=id;s.car.distance=3;s.state.inVehicle=false;s.tick();check(v:selectNearest(true));s.tick()
 cp.phase='10-55';v.phase='10-55'
 local p=assert(cp:propose('approach'));local text=table.concat(p.prepared.lines,' ')
 if id~=411 then for _,word in ipairs({'салон','двер','окно','багажник'})do check(not text:find(word,1,true),text)end end
 if id~=411 then check(not cp:propose('window_question'));check(not cp:propose('window_knock'))end
 s.cfg.copilot.templates.approach_bike_day='{gender:осмотрел|осмотрела} мой текст.';s.tick()
 if id==522 then p=assert(cp:propose('approach'));check(table.concat(p.prepared.lines,' '):find('мой текст',1,true))end
end end
-- Every known stock RP line is rendered via the shared gateway. Custom text survives unchanged.
local custom='/me мой личный текст: достал пропуск.'
eq(core.expandGender(custom,'female'),custom)
eq(core.expandGender('/me ввёл ориентировку подозреваемого в навигационный комплекс крузера и запросил пеленг сигнала со спутника.','female'),
 '/me ввела ориентировку подозреваемого в навигационный комплекс крузера и запросила пеленг сигнала со спутника.')
eq(core.expandGender('{gender:вышел|вышла}','unknown'),'вышел')

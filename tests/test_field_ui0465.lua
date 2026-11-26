local fixture=require 'support.fixture'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local lib=model.defaults(core.defaults())
lib.field.enabled=true
lib.field.leadership.enabled=true
lib.field.leadership.briefings={{name='Инструктаж',tag='',department='EPD',lines={'Первая строка.','Вторая строка.'}}}
local s=fixture({library=lib,demo=false,productionWindows=true})
local studio=s.workspace.studio

local function click(label)
 s.click=label;s.render()
 eq(s.click,nil,label)
 check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'))
 eq(#s.scopes,0)
end
local function hasButton(label)
 for _,button in ipairs(s.buttonCalls)do if button.label:find(label,1,true)then return true end end
 return false
end
local function saved()return s.savedLibrary().field end

s.step()
if not s.frames[1].condition()then s.commands.pa26();s.step()end
s.page('addons');click('Инструменты службы##toolfield')
local sliders={observe_ms=630,arrival=36,ttl_ms=200123,offer_ms=1001,channel_limit=115,delay_ms=2700}
local seen={}
s.imgui.SliderInt=function(label,value)
 local key=label:match('^##field%-(.+)$')
 if not sliders[key]then return false end
 eq(value[0]%1,0);value[0]=sliders[key];seen[key]=true;return true
end
local sliderFloat=s.imgui.SliderFloat
s.imgui.SliderFloat=function(label,...)
 check(not sliders[label:match('^##field%-(.+)$')],'Integer field must use SliderInt: '..label)
 return sliderFloat(label,...)
end
studio.fieldPage='cruiser';s.buttonCalls={};s.render()
eq(studio.fieldPage,'coordinates')
check(not hasButton('Помощь водителю'))
check(not hasButton('##field-save'))
s.step(700)
eq(saved().navigation.observe_ms,630);eq(saved().navigation.arrival,36)
eq(saved().coordinates.ttl_ms,200123);eq(saved().coordinates.offer_ms,1001)

studio.fieldPage='leadership';studio.leaderPage='news';s.render();s.step(700)
eq(saved().leadership.channel_limit,115);eq(saved().leadership.delay_ms,2700)
for key in pairs(sliders)do check(seen[key],key)end

studio.leaderPage='briefing';studio.briefingIndex=1;studio.briefingLine=1
local input='##Строки инструктажа##briefing-body'
local function edit(text)
 s.edits={[input]=text};s.render();eq(s.edits[input],nil)
end
edit(' \n\n')
s.drawnText={};s.buttonCalls={};s.step(700)
check(table.concat(s.drawnText,'\n'):find('Добавьте хотя бы одну непустую строку',1,true))
check(not hasButton('##briefing-preview'),'An empty editor must not offer to send its old saved text')
eq(saved().leadership.briefings[1].lines[1],'Первая строка.')
check(not studio.feedback:peek(),'Empty draft must not produce an autosave error')
s.multilineCalls={};s.render()
local stillEmpty=false
for _,inputCall in ipairs(s.multilineCalls)do
 if inputCall.label==input then stillEmpty=inputCall.text==' \n\n' end
end
check(stillEmpty,'The editor stays empty while the old text remains saved')

edit('Новая первая.\n\nНовая вторая.')
s.step(700)
eq(#saved().leadership.briefings[1].lines,2)
eq(saved().leadership.briefings[1].lines[1],'Новая первая.')
eq(saved().leadership.briefings[1].lines[2],'Новая вторая.')

click('Предпросмотр выбранной строки##briefing-preview')
check(not studio.assistConfirm,'Rendering leaves template context preparation to the game loop')
s.step()
check(studio.assistConfirm,'Briefing preview opens after saving')
click('НЕТ##confirm-no')
eq(studio.briefingLine,1);eq(#s.sent,0)
click('Предпросмотр выбранной строки##briefing-preview')
s.step()
click('ДА##confirm-yes')
for _=1,5 do s.step(700)end
eq(#s.sent,1);eq(s.sent[1].line,'Новая первая.')
if not s.frames[1].condition()then s.commands.pa26();s.step()end
s.render()
eq(studio.briefingLine,2,'A completed send advances the live editor')
studio.briefingLine=1;s.render()
eq(studio.briefingLine,1,'A completion token is applied only once')
onScriptTerminate(s.script)

local wheel=require 'pa26_wheel'
lib.vehicle.enabled=true;lib.vehicle.copilot.enabled=true
local function catalog(pinned)
 return wheel.build(lib,1,true,{inVehicle=true,onDuty=true,copilot={car={},pinned=pinned}})
end
local wanted=catalog('fast_wanted')
eq(wanted.bySystem['copilot-fast_wanted'].name,'Розыск по авто 8.1 · без /pt')
eq(wanted.bySystem['copilot-pursuit_mark'].name,'Розыск · без /pt')
eq(catalog('pursuit_mark').bySystem['copilot-pursuit_mark'].name,'Только /pt')

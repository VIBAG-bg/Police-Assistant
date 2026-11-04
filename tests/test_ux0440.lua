local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core'
local equal=require('pa26_author_presets').equal;local icons=require 'pa26_icons';local menu=require 'pa26_menu'
eq(menu.sections[4].key,'partners');eq(menu.sections[4].label,'Патруль');eq(menu.sections[4].short,'Патруль')
eq(icons.semantic('Быстрый /pt рядом · ДА/НЕТ##copilot-fast-pt'),'crosshairs')
eq(icons.semantic('ДА##confirm-yes'),'check');eq(icons.semantic('НЕТ##confirm-no'),'xmark')
icons.clear();check(not icons.get('house'));icons.setEnabled(false);check(not icons.get('house'));icons.setEnabled(true)
-- Existing settings need no migration; the single optional presentation flag defaults on.
local raw=model.defaults(core.defaults());raw.settings.ui_icons=nil;raw.profile.name='Private Name'
raw.settings.wheel_names.citizen='Моё колесо';raw.notes[1].body='Личная заметка';raw.patrol_session.start_template='Мой доклад {unit}.'
local cleaned=assert(model.validate(raw,core.defaults()));check(cleaned.settings.ui_icons)
eq(cleaned.profile.name,raw.profile.name);check(equal(cleaned.notes,raw.notes));check(equal(cleaned.bindings,raw.bindings))
eq(cleaned.patrol_session.start_template,raw.patrol_session.start_template);eq(cleaned.settings.wheel_names.citizen,'Моё колесо')
cleaned.settings.ui_icons=false;check(not assert(model.validate(cleaned,core.defaults())).settings.ui_icons)
local s=fixture({important=true,copilot=true,alerts=true,productionWindows=true});s.step();if not s.frames[1].condition()then s.commands.pa26();s.step()end;s.page('partners');s.render()
local studio=s.workspace.studio;eq(studio.partnerPage,'patrol');eq(#s.sent,0)
local function click(text)s.click=text;s.render();eq(s.click,nil,text);check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,' | '));eq(#s.scopes,0)end
check(studio.patrolSessionDraft);eq(studio.patrolSessionDraft.start_template,s.workspace.library.patrol_session.start_template)
s.edits={['##Юнит вручную · пусто = автоматически##session-unit']='2-L-77'};s.render();s.edits={};s.step(650)
click('Шаблоны и дополнительные настройки →##session-settings');eq(studio.radioPage,'session')
s.render();check(studio.patrolSessionDraft);eq(#s.sent,0)
-- Deep links override the default without wiping the shared session draft.
s.page('partners');studio.partnerPage='contacts';s.render()
eq(studio.partnerPage,'contacts');eq(studio.patrolSessionDraft.unit,'2-L-77');eq(#s.sent,0)
-- Expanding dispatch families is pure navigation, not an RP or server action.
s.physicalDown={[0x73]=true};s.step();s.physicalDown={};s.step();studio.assistPage='traffic';s.render()
for _,r in ipairs(require('pa26_copilot_ui').dispatchFamilies)do
 local before=#s.sent
 studio.dispatchIncident=r[1];s.render();eq(studio.dispatchIncident,r[1]);eq(#s.sent,before)
 check(not studio.vehicleConfirm)
end
onScriptTerminate(s.script)
-- All-topics rendering keeps specific membership and never duplicates an identity.
local f=fixture({important=true});f.step();local d=f.knowledgeUi.knowledge.important
local important=require 'pa26_knowledge_important'
for _,card in ipairs(d.cards)do
 local seen,unique={},0
 for _,section in ipairs(card.sections)do
  local rows=important.filter(d,'',card.id,section.id);eq(#rows,#section.rows)
  for _,r in ipairs(rows)do if not seen[r.key]then unique=unique+1;seen[r.key]=true end end
 end
 eq(#important.filter(d,'',card.id,'*'),unique)
 local seenDisplay={};for _,r in ipairs(important.filter(d,'',card.id,'*'))do
  check(not seenDisplay[r.key]);seenDisplay[r.key]=true;check(r.sectionTitle);check(r.provenance)
  check(not r.text:find('\226\128\139',1,true),'Invisible source decoration cannot become a missing glyph')
 end
end
for _,r in ipairs(important.filter(d,'','fines','all'))do check(r.kind=='fine');check(#r.sanctions>0)end
local view=require 'pa26_knowledge_important_ui'
local layout={blocks={{top=0,height=100},{top=100,height=80},{top=180,height=120}},total=300}
local a,b=view.visible(layout,110,170);eq(a,2);eq(b,2)
a,b=view.visible(layout,400,500);eq(a,4);eq(b,3)
a,b=view.visible(layout,-100,80);eq(a,1);eq(b,1)
-- A stranger cannot become an automatic /pt target. Wanted evidence is identity-bound.
local pt=require 'pa26_fast_pt';local t={id=20,ped=25,name='Known_Name',distance=4,generation=1,visible=true,fallback=true}
check(not pt.resolve({t},{ped=1},50));t.wanted_verified=true;t.wanted_name=t.name;t.wanted_generation=1;t.wanted_level=2
check(pt.resolve({t},{ped=1},50));t.generation=2;check(not pt.resolve({t},{ped=1},50));t.generation=1;t.wanted_name='Other_Name';check(not pt.resolve({t},{ped=1},50))
t.fallback=false;check(pt.resolve({t},{ped=1},50),'Explicit target remains usable through the normal guard')
onScriptTerminate(f.script)

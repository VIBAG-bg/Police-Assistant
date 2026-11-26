local theme=require 'pa26_theme'
local icons=require 'pa26_icons'
local settings=require 'pa26_settings_ui'
local model=require 'pa26_bindings'
local core=require 'pa26_core'
local users=require 'pa26_user_files'
local same=require('pa26_author_presets').equal
local roles=[[
 windowBg childBg cardBg sidebarBg headerBg footerBg border popupBg separator
 frameBg frameHovered frameActive scrollbarBg scrollbarGrab scrollbarGrabHovered scrollbarGrabActive
 sliderGrab sliderGrabActive checkMark btnPrimary btnPrimaryHover btnPrimaryActive btnSecondary btnSecondaryHover
 btnSecondaryActive btnDanger btnDangerHover btnDangerActive hudBg hudHeader hudBorder hudBadge wheelRoot
 wheelRootActive wheelRootPending wheelChild wheelChildSelected wheelCenter wheelAccent toastBg toastBodyBg
 statusSafe statusWarn statusAlert statusMuted
]]
local function luminance(c)
 local function ramp(v)return v<=.04045 and v/12.92 or ((v+.055)/1.055)^2.4 end
 return .2126*ramp(c[1])+.7152*ramp(c[2])+.0722*ramp(c[3])
end
for _,row in ipairs(theme.choices)do
 local id=row[1];check(theme.valid(id));local p=theme.get(id)
 for key in roles:gmatch('%S+')do
  for i=1,4 do check(p[key][i]>=0 and p[key][i]<=1,id..' '..key)end
 end
 for _,key in ipairs({'btnPrimary','btnSecondary','btnDanger','btnPrimaryHover','btnPrimaryActive'})do
  check((luminance(p.text)+.05)/(luminance(p[key])+.05)>=4.5,id..' '..key..' label contrast')
 end
 for _,key in ipairs({'statusSafe','statusWarn','statusAlert','statusMuted'})do eq(p[key],theme.get('police')[key])end
 eq(icons.color(p,'normal'),p.wheelAccent);eq(icons.color(p,'safe'),p.statusSafe);eq(icons.color(p,'danger'),p.statusAlert)
 check(not pcall(function()p.windowBg=nil end))
 check(not pcall(function()p.windowBg[1]=0 end))
end
check(not theme.valid('wrong'));eq(theme.get('wrong'),theme.get('police'));eq(theme.get(nil),theme.get('police'))
eq(icons.semantic('Патруль LSPS##home-duty-preset-3'),nil)

local cfg=core.defaults()
local old=model.defaults(cfg);old.profile_presets=nil;old.settings.theme=nil
local clean=assert(model.validate(old,cfg));eq(#clean.profile_presets,0);eq(clean.settings.theme,'police')
clean.settings.theme='fbi'
clean.profile.name='Personal Officer';clean.profile.gender='female';clean.profile.accent='[Акцент]:'
clean.profile.department='FBI';clean.profile.rank='Agent';clean.profile.callsign='1-A-1'
clean.profile.local_tag='[FBI] ';clean.profile.global_tag='[G] ';clean.profile.prison_tag='[P] ';clean.profile.badge_number='134'
check(model.addDutyPreset(clean,'Дежурный FBI'))
check(not model.addDutyPreset(clean,'дежурный fbi'))
clean.profile.department='LSPD';clean.profile.rank='Officer';clean.profile.callsign='1-L-1'
clean.profile.local_tag='L';clean.profile.global_tag='G';clean.profile.prison_tag='P';clean.profile.badge_number='321'
check(model.addDutyPreset(clean,'Патруль LSPS'))
local copied=assert(model.validate(clean,cfg))
local parts=users.partition(copied)
parts.settings=assert(users.validate('settings',parts.settings,cfg))
local roundtrip=assert(users.combine(parts,cfg))
eq(roundtrip.settings.theme,'fbi');check(same(roundtrip.profile_presets,copied.profile_presets))
local before=model.copy(roundtrip)
local preset=roundtrip.profile_presets[1]
check(model.applyDutyPreset(roundtrip,preset.id));check(model.dutyPresetMatches(roundtrip.profile,preset))
for k,v in pairs(before.profile)do if preset[k]==nil or k=='name'then eq(roundtrip.profile[k],v,k)end end
before.profile=roundtrip.profile
check(same(before,roundtrip),'Only seven fields may change on apply')
local invalid=model.copy(roundtrip);invalid.settings.theme='removed';eq(assert(model.validate(invalid,cfg)).settings.theme,'police')
invalid=model.copy(roundtrip);invalid.profile_presets[2].id=invalid.profile_presets[1].id
check(not model.validate(invalid,cfg))
invalid=model.copy(roundtrip)
for i=3,8 do check(model.addDutyPreset(invalid,'Профиль '..i))end
check(not model.addDutyPreset(invalid,'Лишний'))
check(not model.applyDutyPreset(roundtrip,800))

for _,row in ipairs({
 {'ТАЙЗЕР','weapons',nil,'taser'},{'колесо','options',nil,'wheel'},
 {'тема','general','windows','theme'},{'CEF','chat','filters','cef'},
 {'акцент','chat','accent','accent'},{'HUD','general','hud','hud'},
 {'свои автодоклады','radio','automatic','automatic'},{'  квадраты   карты  ','general','map','map'},
})do
 local r=assert(settings.search(row[1])[1]);eq(r.tab,row[2]);eq(r.page,row[3]);eq(r.id,row[4])
end
eq(#settings.search('   '),0);eq(#settings.search('нет такой настройки 234443'),0)
local seen={}
local wheel=require 'pa26_wheel'
for index,section in ipairs(settings.groupWheelActions(wheel.systemRows))do
 for _,row in ipairs(section.rows)do check(not seen[row[1]],row[1]);seen[row[1]]=index end
end
for _,row in ipairs(wheel.systemRows)do check(seen[row[1]],row[1])end
eq(seen.code0,1);eq(seen['patrol-open'],2);eq(seen['procedure-wanted'],3);eq(seen['assist-megaphone'],4)

local journal=require 'pa26_journal'
local day='2026-11-26'
local j=journal.new(nil,function()return day end)
local function event(stat,sent)
 return j:record({plan={binding={name='Демо',stat=stat}},demo=false,sent=sent},'completed')
end
check(j:confirm(event('cuff',2).id));event('none',3)
local today=j:today();eq(today.runs,2);eq(today.sent,5);eq(today.cuffs,1)
local reopened=journal.new(j.data,function()return day end)
eq(reopened:today().runs,2)
day='2026-11-27';eq(j:today().runs,0)
check(j:confirm(event('documents',1).id));eq(j:today().documents,1)
j:clearLog();eq(j:today().runs,1);eq(j:today().sent,1)

local previewNow,previewRevision,contextReads=100,1,0
local field=require('pa26_field_services').new({
 gameNow=function()return previewNow end,revision=function()return previewRevision end,
 templateContext=function()contextReads=contextReads+1;return {gender='female',values={callsign='1-L-1'}}end,
})
eq(field:previewText('/gnews Обычный текст.'),'/gnews Обычный текст.')
field:refreshPreview();eq(contextReads,0)
local template='/gnews {callsign} {gender:начал|начала}'
eq(field:previewText(template),nil);eq(contextReads,0)
field:refreshPreview();eq(contextReads,1)
eq(field:previewText(template),'/gnews 1-L-1 начала');eq(contextReads,1)
field:refreshPreview();eq(contextReads,1)
previewNow=800
eq(field:previewText(template),'/gnews 1-L-1 начала');eq(contextReads,1)
field:refreshPreview();eq(contextReads,2)
previewRevision=2
eq(field:previewText(template),nil);eq(contextReads,2)
field:refreshPreview()
eq(field:previewText(template),'/gnews 1-L-1 начала');eq(contextReads,3)

local updateUi=require 'pa26_update_ui'
local clicked,pending
local performed={}
local update={phase='available',candidate={version='0.47.1'},env={platform={
 openBackups=function()performed[#performed+1]='backups'end,
}}}
for _,name in ipairs({'check','download','cancel'})do update[name]=function()performed[#performed+1]=name end end
local author={status='Готово',start=function(_,kind)performed[#performed+1]=kind end}
local renderer={lib=roundtrip,imgui={new={int=function(n)return {n}end},SliderInt=function()return false end},
 settingsHeading=function()end,check=function(_,_,v)return v end,field=function(_,_,_,v)return v end,
 autoSettings=function()end,autosaveHint=function()end,flushAutosave=function()end,
 button=function(_,label)return label:find(clicked,1,true)~=nil end}
for _,row in ipairs({{'##updates-check','check'},{'##updates-download','download'},
 {'##author-binds','binds'},{'##author-settings','settings'},{'##updates-backups','backups'},
 {'##updates-cancel','cancel',{mode='Prepare'}}})do
 clicked,pending=row[1],nil;update.job=row[3]
 local before=#performed
 updateUi.draw(renderer,{text=function()end},update,{afterUi=function(run)pending=run;return true end},author)
 check(pending);eq(#performed,before,'Worker must not run inside render')
 pending();eq(performed[#performed],row[2])
end

local fixture=require 'support.fixture'
local routes=require 'support.ui_routes'
local s=fixture({library=copied,productionWindows=true})
local studio=s.workspace.studio
s.step()
if not s.frames[1].condition()then s.commands.pa26();s.step()end
s.page('settings')
local function search(text)
 local label='Найти настройку...##settings-search'
 s.edits={[label]=text};s.render();eq(s.edits[label],nil,text)
end
for _,row in ipairs({
 {'тема','theme','screenSettingsPage','windows'},
 {'cef','cef','chatSettingsPage','filters'},
 {'акцент','accent','chatSettingsPage','accent'},
 {'hud','hud','screenSettingsPage','hud'},
 {'смена патруля','session','radioPage','session'},
})do
 search(row[1]);routes.id(s,'##settings-result-'..row[2])
 eq(studio[row[3]],row[4]);eq(studio.settingsSearch,'')
end
search('колесо');routes.click(s,'×##settings-search-clear');eq(studio.settingsSearch,'')
routes.screen(s,'windows')
s.combo='##Тема оформления##ui-theme'
routes.click(s,'Алькатрас · Сталь и янтарь##Тема оформления##ui-themealcatraz')
s.combo=nil;s.step(700)
eq(s.savedLibrary().settings.theme,'alcatraz')

s.page('home')
routes.id(s,'##home-duty-preset-1')
eq(s.workspace.library.profile.department,'LSPD','The renderer only queues the apply')
s.step(700)
eq(s.savedLibrary().profile.department,'FBI')
eq(s.savedLibrary().profile.name,'Personal Officer');eq(s.savedLibrary().profile.gender,'female')
eq(s.savedLibrary().profile.accent,'[Акцент]:')
check(same(s.savedLibrary().bindings,copied.bindings));check(same(s.savedLibrary().notes,copied.notes))
s.ackInfo()
routes.settings(s,'profile')
local name='##Название профиля##duty-preset-name'
s.edits={[name]='Дежурство 3'};s.render();eq(s.edits[name],nil)
routes.id(s,'##duty-preset-save');s.step(700);eq(#s.savedLibrary().profile_presets,3)
s.ackInfo()
routes.id(s,'##duty-preset-delete-3')
routes.click(s,'ДА##confirm-yes');s.step(700);eq(#s.savedLibrary().profile_presets,2)
s.ackInfo()

local functions={}
routes.screen(s,'recovery')
for _,name in ipairs({'isGamePaused','getGameTimer','isSampAvailable','sampGetGamestate','sampGetCurrentServerAddress',
 'sampGetPlayerNickname','sampIsPlayerConnected','sampIsChatInputActive','sampIsDialogActive','getCharCoordinates'})do
 functions[name]=_G[name]
 _G[name]=function()error('Read on render: '..name)end
end
s.click='Восстановить окна PA##recovery-now'
s.render()
eq(s.click,nil)
for name,value in pairs(functions)do _G[name]=value end
check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0)
check(not s.hasLog('Окна PA восстановлены'))
s.step()
check(s.hasLog('Окна PA восстановлены'))
onScriptTerminate(s.script)

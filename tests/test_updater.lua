local module=require 'pa26_updater';local model=require 'pa26_bindings';local core=require 'pa26_core'
local cfg=module.defaults();eq(cfg.repository,'VIBAG-bg/Police-Assistant');check(not cfg.check_on_start)
check(cfg.show_progress_window)
check(assert(module.validate({repository='Owner/Repo'})).show_progress_window,'old settings get a visible progress window')
check(not assert(module.validate({repository='Owner/Repo',show_progress_window=false})).show_progress_window)
check(not module.validate({repository='Owner/Repo',show_progress_window='yes'}))
eq(assert(module.validate({repository='https://github.com/Owner/Repo/'})).repository,'Owner/Repo')
for _,repo in ipairs({'owner/repo.git','https://evil.test/x','a/b/c','a/b?token=x','a/b#x','a/b\n','a;evil/b','/a/b','a/b@v1'})do check(not module.validate({repository=repo}),repo)end
for _,n in ipairs({0,121,1.5,0/0,math.huge})do check(not module.validate({timeout_seconds=n}))end
local lib=model.defaults(core.defaults());lib.settings.updates=nil
local loaded=assert(model.validate(lib,core.defaults()));eq(loaded.settings.updates.repository,'VIBAG-bg/Police-Assistant')
loaded.settings.updates={enabled=true,repository='Owner/Repo',check_on_start=true,include_prerelease=false,timeout_seconds=1}
local users=require 'pa26_user_files';local parts=users.partition(loaded)
eq(assert(users.combine(TEST_JSON_DECODE(TEST_JSON_ENCODE(parts)),core.defaults())).settings.updates.timeout_seconds,1)
local function setup()
    local s={cfg=module.defaults(),now=1000,started={},notices={},reply=nil}
    local p={ml='C:\\Game\\MoonLoader'}
    function p:start(mode,json)local job={mode=mode,id=string.rep('a',32),root='test'};s.started[#s.started+1]={mode=mode,data=TEST_JSON_DECODE(json)};return job end
    function p:poll()return s.reply end
    function p:cancel()s.cancelled=true;return true end
    function p:seen(job)s.seen=job end
    s.u=module.new({platform=p,settings=function()return s.cfg end,now=function()return s.now end,encode=TEST_JSON_ENCODE,decode=TEST_JSON_DECODE,
        notify=function(message,kind)s.notices[#s.notices+1]={message=message,kind=kind}end})
    function s.tick(phase,message,details)
        s.now=s.now+300
        if phase then s.reply=TEST_JSON_ENCODE({product='police-assistant-2026',moonloader=p.ml,phase=phase,message=message or phase,details=details})end
        s.u:tick()
    end
    return s
end
local s=setup();s.cfg.repository='';s.tick();eq(#s.started,1);eq(s.started[1].mode,'Status')
s.tick('idle','ready');for _=1,10 do s.tick()end;eq(#s.started,1,'empty source must never check the network')
check(not s.u:check());eq(#s.started,1);check(s.notices[#s.notices].message:find('не настроен',1,true))
s.cfg.repository='Owner/Repo';check(s.u:check());check(not s.u:check());eq(#s.started,2)
local candidate={version='0.39.0',sha256=string.rep('a',64),asset_id=7,notes='Описание автора'}
s.tick('available','new_version',candidate);eq(s.u.candidate.version,'0.39.0');eq(#s.started,2)
check(s.u:download());eq(s.started[3].mode,'Prepare');check(s.started[3].data.approved);check(s.started[3].data.show_progress_window)
s.tick('waiting','downloaded_close_game');local notices=#s.notices
for _=1,10 do s.tick()end;eq(#s.notices,notices,'same status must not open a modal every frame')
check(s.u:cancel());check(s.cancelled);s.tick('cancelled','cancelled');check(not s.u.job)
s=setup();s.cfg.repository='Owner/Repo';s.cfg.check_on_start=true;s.tick();s.tick('idle','ready');s.tick()
eq(#s.started,2);eq(s.started[2].mode,'Check');s.tick('current','no_new_version');for _=1,10 do s.tick()end;eq(#s.started,2)
s=setup();s.cfg.repository='Owner/Repo';s.u.started=true;s.u:check();s.tick('available','new_version',candidate)
s.cfg.repository='Other/Repo';check(not s.u:download());eq(#s.started,1,'old repository candidate cannot install')
s.cfg.repository='Owner/Repo';check(s.u:download());s.cfg.enabled=false;s.tick();check(s.cancelled);check(not s.u.job)
s=setup();s.cfg.repository='Owner/Repo';s.u.started=true;s.u:check();s.reply='broken';s.now=1000000;s.u:tick();check(not s.u.job);eq(s.u.phase,'error')
s=setup();s.cfg.repository='Owner/Repo';s.tick()
local adopted={mode='Prepare',id=string.rep('b',32),root='adopted'}
s.u.env.platform.adopt=function()return adopted,TEST_JSON_ENCODE({repository='Owner/Repo',include_prerelease=false,timeout_seconds=30})end
s.reply=TEST_JSON_ENCODE({product='police-assistant-2026',moonloader=s.u.env.platform.ml,phase='waiting',message='downloaded_close_game',active_job=true,job=adopted.id})
s.tick();eq(s.u.job.root,'adopted');eq(#s.started,1,'reload must adopt, not launch a second download')
local notices=#s.notices;s.tick('waiting','downloaded_close_game');eq(#s.notices,notices,'adoption cannot repeat waiting popup')
check(s.u:cancel());check(s.cancelled)
-- Real sidebar route and settings persistence, without a process/network mock
-- accidentally creating a real update request from the test fixture.
local fixture=require 'support.fixture';s=fixture({demo=true});s.step();s.page('binds')
local button
for _,b in ipairs(s.buttonCalls)do if b.label=='Обновления PA##pa26-updates'then button=b end end
check(button);eq(button.parent,'sidebar##pa26')
s.click='Обновления PA##pa26-updates';s.render();check(s.click==nil)
s.edits={['GitHub: владелец/репозиторий##updates-repository']='Owner/Repo'};s.render();s.edits={};s.step(650)
eq(s.savedLibrary().settings.updates.repository,'Owner/Repo')
s.toggle='Показывать отдельное окно установки##updates-progress-window';s.render();s.step(650)
check(not s.savedLibrary().settings.updates.show_progress_window,'window preference is editable and persists')
local studio=s.workspace.studio
local general=model.copy(s.workspace.library.settings);general.opacity=.75
studio:autoSettings('settings',{'settings'},general)
local changed=model.copy(s.workspace.library.settings.updates);changed.repository='Other/Repo'
studio:autoSettings('updates',{'settings','updates'},changed);s.step(650)
eq(s.savedLibrary().settings.updates.repository,'Other/Repo','whole settings autosave must preserve the latest updater settings')
check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,' | '));eq(#s.scopes,0);onScriptTerminate(s.script)

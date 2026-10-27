local screens=require 'pa26_screens';local Evidence=require 'pa26_evidence';local prefs=require 'pa26_assist_settings'
local equal=require('pa26_author_presets').equal
eq(screens.index('sa-mp-999.png'),999);eq(screens.index('sa-mp-000.jpg'),0);check(not screens.index('../sa-mp-999.png'));check(not screens.index('holiday.png'))
local rows={};for i=0,989 do rows[#rows+1]={name=string.format('sa-mp-%03d.png',i),path='C:/fake/'..i,created=i,written=i}end
local scan=screens.summarize('C:/fake',rows);check(scan.nearLimit);check(not scan.full);eq(scan.maxIndex,989);eq(scan.count,990)
rows[#rows+1]={name='sa-mp-999.png',path='C:/fake/last',created=1000,written=1000};scan=screens.summarize('C:/fake',rows);check(scan.full);eq(scan.latestFile,'C:/fake/last')
local cfg=prefs.defaults().evidence;cfg.enabled=true;cfg.time_enabled=true;cfg.time_verified=true;cfg.time_source='server';cfg.auto_scan=true
local now,stamp,records,plans,archived=1000,1000000,{}, {},0
local found
local files={clock=function()return stamp end,scanScreens=function()return found end,
 verify=function(path,since)if found and found.latestCreated>=since then return{path=path,key='stable',size=100,created=found.latestCreated,written=found.latestWritten}end;return nil,'old'end,
 archiveScreens=function(dir)archived=archived+1;return{moved=1,skipped=0,archiveDir=dir..'/PA_Archive_test'}end}
local e=Evidence.new({settings=function()return cfg end,files=files,equal=equal,codec=codec,start=function(p)plans[#plans+1]=p;return true end,
 date=function()return'2026-10-27'end,record=function(r)records[#records+1]=r;return true end})
local s={session='s',ped=1,alive=true,focused=true,paused=false,blocked=false,demo=false}
local function tick(dt)now=now+(dt or 500);e:tick(s,now)end
tick();local p=assert(e:propose('test'));check(e:accept(p));tick();eq(#plans,1);stamp=2000000;e:onExecution('completed',{plan=plans[1]})
found={dir='C:/fake',count=1,maxIndex=0,nearLimit=false,latestFile='C:/fake/sa-mp-000.png',latestCreated=1999999,latestWritten=2000001}
tick();check(e.active,'A previous screenshot cannot satisfy the new session')
found.latestCreated=2000001;tick();check(e.active);tick();check(not e.active);eq(records[1].status,'verified');eq(records[1].path,found.latestFile)
local a=assert(e:proposeArchive());eq(archived,0);check(e:archive(a));eq(archived,0,'No file moves from render callback');tick();eq(archived,1)
e.scan=found;s.demo=true;tick();a=assert(e:proposeArchive());check(e:archive(a));tick();eq(archived,1,'Demo never moves files')
e.scan=found;a=assert(e:proposeArchive());s.session='new';tick();check(not e:archive(a));eq(archived,1)

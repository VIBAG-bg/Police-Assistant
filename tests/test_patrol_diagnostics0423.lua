local module=require 'pa26_patrol';local prefs=require 'pa26_preferences';local model=require 'pa26_bindings'
local cfg=prefs.patrolDefaults();cfg.enabled=true;cfg.police_interval_ms=300000
local state={session='test',ped=1,demo=false,onDuty=true,radioEnabled=true,alive=true,focused=true,paused=false,blocked=false,typing=false}
local logs={};local accepted=false;local why='Не задана переменная {unit}: проверьте обозначение экипажа.'
local c=module.new{settings=function()return cfg end,dispatch=function()return accepted,why end,log=function(t)logs[#logs+1]=t end}
local now=1000;c:tick(state,now)
for _=1,300 do now=now+1000;c:tick(state,now)end
eq(#logs,1);check(c:view().status:find('Проверьте настройки доклада ('..why..')',1,true));check(logs[1]:find(why,1,true))
check(logs[1]:find('интервал=300000 мс',1,true));check(logs[1]:find('канал=/r',1,true))
for _=1,20 do now=now+16;c:tick(state,now)end;eq(#logs,1,'Do not log the same failure each frame')
cfg.police_template='Исправленный текст';c:tick(state,now+1);eq(c.error,nil)
accepted=true;for _=1,301 do now=now+1000;c:tick(state,now)end;eq(c.error,nil);check(not c:view().status:find('Проверьте',1,true))
local phase='invalid';why='Неверный канал доклада: нужен /r.'
c=module.new{settings=function()return cfg end,preview=function()return phase,why end,lead=function()return 300000 end,log=function(t)logs[#logs+1]=t end}
c:tick(state,now);eq(c.error,why);check(logs[#logs]:find(why,1,true))
phase='confirm';c:tick(state,now+1000);eq(c.error,nil);eq(c:view().phase,'confirmation')
phase='cancelled';c:tick(state,now+2000);eq(c.error,nil,'User cancellation is not a settings fault')
c:problem('Строка 1\nСтрока 2',cfg,'test');check(not c:view().status:find('\n',1,true));check(logs[#logs]:find('Строка 1\nСтрока 2',1,true))
c:reset();eq(c.error,nil)

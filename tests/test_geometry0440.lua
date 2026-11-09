local geo=require 'pa26_geometry';local menu=require 'pa26_menu';local model=require 'pa26_bindings';local core=require 'pa26_core'
local sizes={{640,480},{800,600},{1152,864},{1366,768},{1920,1080},{2560,1440},{3440,1440},{800,1100}}
local function bounded(r,w,h)
 check(r and geo.finite(r.width)and geo.finite(r.height));check(r.x>=16 and r.y>=16)
 check(r.x+r.width<=w-16.0001+.001 and r.y+r.height<=h-16.0001+.001)
end
for _,sz in ipairs(sizes)do for key in pairs(geo.windows)do
 for _,scale in ipairs({.8,1,1.25,1.5,2})do
  local w,h=sz[1],sz[2];local r=geo.rect(w,h,key,nil,nil,'author',scale);bounded(r,w,h)
  local unchanged=geo.rect(w,h,key,{width=r.width,height=r.height,x=r.x,y=r.y,displayW=w,displayH=h})
  eq(unchanged.width,r.width);eq(unchanged.height,r.height);eq(unchanged.x,r.x);eq(unchanged.y,r.y)
  for _,bad in ipairs({0/0,math.huge,-1,0,1,40000})do
   local invalid={width=bad,height=bad,x=0,y=0,displayW=w,displayH=h}
   local recovered=geo.rect(w,h,key,invalid,nil,'author',scale);bounded(recovered,w,h)
   eq(recovered.width,r.width);eq(recovered.height,r.height)
  end
 end
end end
local main=geo.rect(2560,1440,'main');eq(main.width,2251);eq(main.height,1339);eq(main.x,16);eq(main.y,31)
check(geo.rect(1920,1080,'assist').width==828);check(geo.rect(1366,768,'assist').width==720)
eq(geo.rect(2560,1440,'assist').height,830)
local savedF4={width=680,height=650,x=50,y=90,displayW=1366,displayH=768}
eq(geo.rect(1366,768,'assist',savedF4).width,680);eq(geo.rect(1366,768,'assist',savedF4).height,650)
eq(geo.rect(1920,1080,'main',nil,70,'percent').width,1344)
local custom={width=680,height=839,x=792,y=285,displayW=2560,displayH=1440}
local kept=geo.rect(2560,1440,'assist',custom);eq(kept.width,680);eq(kept.height,839);eq(kept.x,792)
local m=menu.new();m.windows.assist=model.copy(custom);m.windows.main={width=0,height=0,x=0,y=0}
m.windowConfig=function()return {remember=true,windows={main={width=1100,height=620,x=80,y=50,displayW=1280,displayH=720}}}end
m:recoverWindowPositions();eq(m.windows.assist.width,680);eq(m.windows.main.width,1100);check(m.forceWindows.main)
for _,sz in ipairs(sizes)do bounded(geo.rect(sz[1],sz[2],'main',m.windows.main),sz[1],sz[2])end
local hudModule=require 'pa26_hud';local hud=hudModule.new(core.widgetDefaults(),{})
local original=hud:getSettings();local a=hud:layout(2560,1440);eq(a.x,2278);eq(a.y,409);eq(a.scale,1)
local b=hud:layout(1920,1080);check(b.x+b.w<=1920);check(1920-b.x-b.w<12);eq(b.y,306.75)
hud:layout(1366,768);hud:layout(2560,1440);eq(hud.settings.x,original.x);eq(hud.settings.scale,original.scale)
-- Legacy files are interpreted in their own viewport, not on a 2K screen.
local cfg=core.defaults();cfg.widget={visible=true,x=80,y=140,scale=1.1,time_source='local'}
local text=assert(require('pa26_config').serialize(cfg));local normalized=core.normalizeConfig(assert(require('pa26_config').parse(text)))
eq(normalized.widget.x,80);eq(normalized.widget.reference_width,nil)
hud=hudModule.new(normalized.widget,{});a=hud:layout(1366,768);eq(a.x,80);eq(a.y,140);eq(a.scale,1.1)
check(hud.dirty);eq(hud.settings.reference_width,1366)
for _,sz in ipairs(sizes)do local r=hud:layout(sz[1],sz[2]);check(r and r.x>=0 and r.y>=0);check(r.x+r.w<=sz[1]+.001 and r.y+r.h<=sz[2]+.001)end
hud:layout(1920,1080);hud:change('x',333);hud:change('y',222);a=hud:layout(1920,1080);eq(a.x,333);eq(a.y,222)
local persisted=assert(require('pa26_config').serialize({main=core.defaults().main,widget=hud:getSettings(),recovery=core.recoveryDefaults(),
 introduce=core.defaults().introduce,documents=core.defaults().documents,wanted=core.defaults().wanted,frisk=core.defaults().frisk,cuff=core.defaults().cuff,release=core.defaults().release}))
local reloaded=core.normalizeConfig(assert(require('pa26_config').parse(persisted)))
local restored=hudModule.new(reloaded.widget,{}):layout(1920,1080);eq(restored.x,333);eq(restored.y,222)
local same=require('pa26_window_layout').same
check(not same({width=0/0},{}));check(not same({},{}))
local broken=core.defaults();broken.widget.x=-1;broken.widget.y=0/0
local clean=core.normalizeConfig(broken);eq(clean.widget.reference_width,2560);eq(clean.widget.x,2278)
local good=hud:getSettings();check(not hud:recoverGeometry());eq(hud.settings.x,good.x)
hud.settings.x=0/0;check(hud:recoverGeometry());eq(hud.settings.reference_width,2560)
local recovered=hud:layout(1366,768);check(recovered.x+recovered.w<=1366);check(math.abs(recovered.y-409*768/1440)<.01)
-- Recovery neither resets operation settings nor starts/resends any game action.
local fixture=require 'support.fixture';local seed=model.defaults(core.defaults());seed.settings.window_layout.windows.main={width=1100,height=620,x=80,y=50,displayW=1280,displayH=720}
local s=fixture({productionWindows=true,library=seed});s.step();local before=model.copy(s.workspace.library.bindings)
s.commands.pa26repair();s.step();local win=s.windows['Police Assistant 2026##pa26-main'];eq(win.width,1100);eq(win.height,620)
eq(#s.sent,0);eq(#s.workspace.library.bindings,#before);check(not s.hasLog('Ошибка интерфейса'));eq(#s.scopes,0);onScriptTerminate(s.script)

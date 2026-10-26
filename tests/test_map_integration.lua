local fixture=require 'support.fixture';local model=require 'pa26_bindings';local core=require 'pa26_core';local binder=require 'pa26_binder'
local path='moonloader\\config\\police_assistant_2026_library.json'
local lib=model.defaults(core.defaults());lib.profile.square='Ручной сектор';lib.bindings[1].script='Личный бинд.'
local s=fixture({demo=false,library=lib});s.step()
local function healthy()check(not s.hasLog('Ошибка интерфейса'),table.concat(s.logs,'\n'));eq(#s.scopes,0);eq(s.invalidIOReads,0)end
local function click(label)s.click=label;s.render();eq(s.click,nil,'Missing control '..label);healthy()end
local b=model.newBinding(10);b.script='Район {area}; квадрат {map_square}; сектор {square}.'
local snap=assert(s.workspace:snapshot(b,{}));eq(snap.values.map_square,'M-13');eq(snap.values.square,'Ручной сектор')
local plan=assert(binder.compile(b,snap,{},codec));check(plan.lines[1]:find('M-13',1,true));eq(#s.sent,0)
require('support.ui_routes').screen(s,'map')
check(table.concat(s.drawnText,'\n'):find('Квадраты карты',1,true))
local before=model.copy(s.workspace.library.bindings)
s.toggle='Автозаполнение {square}##map-auto-square';s.render();s.step(700);healthy()
check(s.workspace.library.map_grid.auto_square);eq(s.workspace.library.profile.square,'Ручной сектор')
snap=assert(s.workspace:snapshot(b,{}));eq(snap.values.square,'M-13')
local persisted=s.savedLibrary();check(persisted.map_grid.auto_square);eq(persisted.profile.square,'Ручной сектор');eq(persisted.bindings[1].script,before[1].script)
local oldCoords=getCharCoordinates
getCharCoordinates=function(ped)if ped==1 then return 250,0,0 end;return oldCoords(ped)end
s.step(100);snap=assert(s.workspace:snapshot(b,{}));eq(snap.values.map_square,'M-14');eq(snap.values.square,'M-14')
getCharActiveInterior=function()return 1 end;s.step(100);snap=assert(s.workspace:snapshot(b,{}));check(not snap.values.map_square);check(not snap.values.square)
local only=model.newBinding(11);only.script='{map_square}'
local p,err=binder.compile(only,snap,{},codec);check(not p);check(err:find('map_square',1,true),err)
getCharActiveInterior=function()return 0 end;getCharCoordinates=function()return 4000,0,0 end;s.step(100)
snap=assert(s.workspace:snapshot(b,{}));check(not snap.values.map_square)
getCharCoordinates=oldCoords;s.step(100)
s.toggle='Автозаполнение {square}##map-auto-square';s.render();s.step(700);snap=assert(s.workspace:snapshot(b,{}));eq(snap.values.square,'Ручной сектор')
-- Bad row text remains a draft and cannot poison the live model or the renderer.
s.edits={['##Буквы строк с севера на юг##map-rows']='АБ'};s.render();s.edits={};s.step(800);healthy()
eq(s.workspace.library.map_grid.row_labels,'ABCDEFGHIJKLMNOPQRSTUVWX')
s.workspace.studio.mapGridDraft=nil;s.workspace.studio.cache['map-rows']=nil
-- Moving across cells must not cancel a radio occurrence that does not use the new variable.
local guard=require 'pa26_radio_guard';local prefs=require 'pa26_preferences'
local st={session='test',ped=1,alive=true,onDuty=true,radioEnabled=true,focused=true,paused=false,blocked=false,map_square='A-1'}
local now=1000;local c=guard.new({settings=function()return prefs.radioGuardDefaults()end,codec=codec})
c:tick(st,now);local spec={name='Патруль',template='Патруль продолжается.',channel='/r',interval_ms=60000,confirmation=true}
local phase,_,ticket=c:track('unused-square',spec,30000);eq(phase,'pending')
st.map_square='B-2';c:tick(st,now+100);phase=c:track('unused-square',spec,29900);eq(phase,'pending');eq(ticket.phase,'pending')
spec={name='Квадрат',template='Квадрат {map_square}.',channel='/r',interval_ms=60000,confirmation=true}
phase,_,ticket=c:track('used-square',spec,30000);eq(phase,'pending');st.map_square='C-3';c:tick(st,now+200);phase=c:track('used-square',spec,29800);eq(phase,'pending');check(table.concat(ticket.plan.lines,'\n'):find('C-3',1,true));check(not ticket.paintedWire)
eq(#s.sent,0,'Opening/configuring the grid must never send game text');healthy();onScriptTerminate(s.script)

local setup=require 'support.copilot_fixture'
local cp,v,s=setup()
for _,value in ipairs({'неизвестно','не определено',''})do
 local prepared,why=require('pa26_copilot').expand(require('pa26_copilot_settings').defaults().templates.patrol_continue,
  {direction=value,unit='1-L-1',crew='Офицер',patrol_resume='продолжаю патруль',city='Сан-Фиерро',area='Doherty',map_square='J-6',patrol_moving='двигаюсь',patrol_available='доступен',local_tag=''})
 check(prepared,why);check(not prepared:find('на неизвестно',1,true));check(not prepared:find('на не определено',1,true))
end
local p=assert(cp:prepare('patrol_continue'));check(not table.concat(p.lines,' '):find('на неизвестно',1,true))
local custom='Мой доклад, двигаюсь на {direction}. Код 4.';s.cfg.copilot.templates.patrol_continue=custom
local plan,why=cp:prepare('patrol_continue');eq(plan,nil);check(why:find('{direction}',1,true));eq(s.cfg.copilot.templates.patrol_continue,custom)
v.lastDirectionValue='Север';plan=assert(cp:prepare('patrol_continue'));check(table.concat(plan.lines,' '):find('на Север',1,true));eq(s.cfg.copilot.templates.patrol_continue,custom)
-- Last observed movement survives a stop and getting out; no orientation guess.
s.own.x=10;s.tick();local direction=v.lastDirectionValue;check(direction and direction~='')
for _=1,8 do s.tick()end;eq(v.lastDirectionValue,direction)
s.state.inVehicle=false;s.tick();eq(v.lastDirectionValue,direction)
for _,row in ipairs(require('pa26_dispatch').actions)do if not row.mega then
 local prepared,err=cp:prepare(row[1]);if prepared then check(not table.concat(prepared.lines,' '):find('на неизвестно',1,true))else check(type(err)=='string')end
end end

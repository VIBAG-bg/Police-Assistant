-- Optional services share the existing settings document and atomic storage.
local core=require 'pa26_core';local M={}
function M.defaults()return {
 enabled=false,share_shortcut={key=0,ctrl=false,alt=false,shift=false},
 -- Retain saved road settings for older installs. Only marker display uses this group now.
 navigation={enabled=false,observe_waypoint=false,overlay=false,native_path=false,keep_waypoint=false,road_external='',road_work=256,road_budget_ms=1,road_snap=300,hud=true,radar=true,pause_map=true,
  observe_ms=250,recalculate_ms=1500,movement=20,missing_grace_ms=750,retry_ms=5000,arrival=15,max_segments=256,line_width=3,opacity=.9},
 coordinates={enabled=false,observe=false,ttl_ms=300000,offer_ms=20000,arrival_clear=false,channel='/fn',phone='',
  rn_verified=true,fn_verified=true,ln_verified=false,sms_verified=false,shortcut={key=0,ctrl=false,alt=false,shift=false}},
 cruiser={enabled=false,cruise=false,signals=false,auto_hazard=false,target_speed=60,speed_step=5,
  shortcut={key=0,ctrl=false,alt=false,shift=false},left_key=0,right_key=0,hazard_key=0},
 pinned={enabled=false,note_id=0,x=.72,y=.14,width=.25,height=.35,opacity=.88,font_scale=1},
 leadership={enabled=false,verified=false,source='',command='/gnews',tag='',channel_limit=127,delay_ms=1500,
  lines={'','',''},presets={},briefings=require('pa26_field_briefings').defaults()}
}end
local limits={road_work={16,1024},road_budget_ms={.25,3},road_snap={25,600},observe_ms={200,2000},recalculate_ms={1500,60000},movement={5,200},missing_grace_ms={200,5000},retry_ms={1000,60000},
 arrival={1,100},max_segments={16,256},line_width={1,8},opacity={.1,1},ttl_ms={1000,1800000},offer_ms={1000,60000},
 target_speed={5,250},speed_step={1,20},note_id={0,999999998},x={0,1},y={0,1},width={.15,.9},height={.12,.85},font_scale={.7,2},
 channel_limit={16,127},delay_ms={1000,10000},left_key={0,254},right_key={0,254},hazard_key={0,254}}
local function text(s,n)return type(s)=='string'and #s<=n and core.validUtf8(s)and not s:find('%c')end
local function shortcut(s)
 return type(s)=='table'and core.finite(s.key)and s.key%1==0 and s.key>=0 and s.key<=254 and type(s.ctrl)=='boolean'and type(s.alt)=='boolean'and type(s.shift)=='boolean'
end
function M.validate(raw)
 local d=M.defaults();if type(raw)~='table'then return d end
 if type(raw.enabled)=='boolean'then d.enabled=raw.enabled end
 if shortcut(raw.share_shortcut)then for k,v in pairs(raw.share_shortcut)do if d.share_shortcut[k]~=nil then d.share_shortcut[k]=v end end end
 for group,defaults in pairs(d)do if group~='share_shortcut'and type(defaults)=='table'and type(raw[group])=='table'then
  for k,v in pairs(defaults)do local x=raw[group][k]
   if type(v)=='boolean'and type(x)=='boolean'then defaults[k]=x
   elseif type(v)=='number'and core.finite(x)then local bound=limits[k];if bound and x>=bound[1]and x<=bound[2]then defaults[k]=x end
   elseif type(v)=='string'and text(x,(k=='source'or k=='road_external')and 1024 or 160)then defaults[k]=x
   elseif k=='shortcut'and shortcut(x)then defaults[k]={key=x.key,ctrl=x.ctrl,alt=x.alt,shift=x.shift}end
  end
 end end
 if not({['/rn']=true,['/fn']=true,['/ln']=true,['/sms']=true})[d.coordinates.channel]then d.coordinates.channel='/fn'end
 if not d.coordinates.phone:match('^%d*$')then d.coordinates.phone=''end
 if not d.leadership.command:match('^/gnews$')then d.leadership.command='/gnews';d.leadership.verified=false end
 local rawLeader=type(raw.leadership)=='table'and raw.leadership or{}
 for i=1,3 do local x=type(rawLeader.lines)=='table'and rawLeader.lines[i];if text(x,4096)then d.leadership.lines[i]=x end end
 for _,name in ipairs({'presets','briefings'})do
  local rows=rawLeader[name]
  if rows~=nil and(type(rows)~='table'or #rows>32)then return nil,'Не удалось сохранить '..name..': допустимо не больше 32 записей. Данные не заменены.'end
  if type(rows)=='table'then d.leadership[name]={};for i=1,#rows do local r=rows[i]
   if type(r)=='table'and text(r.name,160)and r.name~=''and text(r.tag or'',160)then
    local row={name=r.name,tag=r.tag or'',lines={},department=r.department or'EPD',favorite=r.favorite==true}
    if not({EPD=true,FBI=true,Alcatraz=true})[row.department]then row.department='EPD'end
    local valid=type(r.lines)=='table'and #r.lines>=1 and #r.lines<=64
    if valid then for _,line in ipairs(r.lines)do if not text(line,4096)then valid=false;break end;row.lines[#row.lines+1]=line end end
    if valid then d.leadership[name][#d.leadership[name]+1]=row else return nil,'Проверьте строки записи «'..r.name..'». Сохранение отменено.'end
   else return nil,'У записи нужен непустой заголовок, тег и корректный текст. Сохранение отменено.'end
  end end
 end
 return d
end
return M

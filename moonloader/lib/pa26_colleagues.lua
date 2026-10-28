-- All native reads are called by tick() in main. Uniforms are hints, not IC identity.
local core=require 'pa26_core';local copy=require('pa26_patrol_settings').copy
local M={};local C={};C.__index=C
M.pdSkins={
 [300]={role='cadet',station='LSPS',label='Кадет LSPS'},[301]={role='cadet',station='SFPS',label='Кадет SFPS'},[267]={role='cadet',station='LVPS',label='Кадет LVPS'},
 [280]={role='officer',station='LSPS',label='Офицер LSPS'},[281]={role='officer',station='SFPS',label='Офицер SFPS'},[282]={role='officer',station='LVPS',label='Офицер LVPS'},
 [283]={role='supervisor',station='EPD',label='Старший офицер'},[284]={role='officer',station='EPD',label='Мотобат / Патруль'},[285]={role='swat',station='SWAT',label='Боец SWAT'},
 [288]={role='supervisor',station='EPD',label='Командование'},[295]={role='detective',station='EPD',label='Детектив / Штаб'},
 [211]={role='officer',station='EPD',label='Сотрудница ПД'},[265]={role='officer',station='EPD',label='Офицер ПД'},[266]={role='officer',station='EPD',label='Офицер ПД'},[306]={role='officer',station='EPD',label='Офицер ПД'},[307]={role='officer',station='EPD',label='Офицер ПД'}}
M.pdVehicles={[596]=true,[597]=true,[598]=true,[599]=true,[490]=true,[528]=true,[427]=true}
function M.role(inVehicle,isDriver,passengers)
 if not inVehicle then return nil,nil,0 end
 local n=1+math.max(0,math.min(20,tonumber(passengers)or 0))
 return n>=2 and'ADAM'or'LINCOLN',n>=2 and(isDriver and'driver'or'navigator')or'solo',n
end
function M.callsign(profile,skin,occupants,crew)
 profile=profile or{};if type(profile.callsign)=='string'and profile.callsign~=''then return profile.callsign end
 if skin==285 then return'DAVID-1'end
 local dept=profile.department or'';local station=dept:find('LSPS',1,true)and'1'or dept:find('LVPS',1,true)and'3'or dept:find('SFPS',1,true)and'2'or nil
 local info=M.pdSkins[skin];station=station or((dept==''or dept=='EPD')and'1')or(info and({LSPS='1',SFPS='2',LVPS='3'})[info.station])or'1'
 return station..(((occupants or 1)>=2 or crew==true)and'-A-1'or'-L-1')
end
function M.new(env)return setmetatable({env=env,knownColleagues={},findNames={},snapshot={nearbyOfficers={},nearbyCruisers=0}},C)end
function C:reset()self.knownColleagues={};self.findNames={};self.findAt=nil;self.scanAt=nil;self.snapshot={nearbyOfficers={},nearbyCruisers=0}end
function C:command(line,now)if type(line)=='string'and line:lower():match('^/find%s*$')then self.findAt=now end end
function C:observe(line)
 local cfg=self.env.settings();if not cfg.radio_cache or type(line)~='string'or #line>1024 then return end
 line=line:gsub('{%x%x%x%x%x%x}','')
 local radio=line:match('^%[R%]')or line:match('^%[F%]')or line:match('^%[Рация%]')or line:match('^%[Фракция%]')
 local nick=line:match('([A-Za-z][A-Za-z_]+)%[%d+%]')or line:match('([A-Za-z][A-Za-z_]+)%(%d+%)')or line:match('([A-Za-z][A-Za-z_]+):')
 if nick and #nick<=24 then
  if radio then local n=0;for _ in pairs(self.knownColleagues)do n=n+1 end;if n<1004 then self.knownColleagues[nick:lower()]=true end
  elseif line:match('^%- ')and line:find('[Телефон:',1,true)then
   self.findNames[nick:lower()]=true;local age=self.findAt and core.elapsed(self.now,self.findAt)
   if age and age<=cfg.find_cache_window_ms then self.knownColleagues[nick:lower()]=true end
  end
 end
end
function C:ownSnapshot(s)
 local r=self.env.read;local car=s.inVehicle and r('storeCarCharIsInNoSave',s.ped)or nil
 if car and r('doesVehicleExist',car)~=true then car=nil end
 local mode,role,occupants=M.role(car~=nil,car and r('getDriverOfCar',car)==s.ped,car and r('getNumberOfPassengers',car))
 local skin=r('getCharModel',s.ped);local profile=self.env.profile()or{}
 local dept=profile.department;local station=type(dept)=='string'and dept~=''and dept~='EPD'and dept or'LSPS'
 return{nearbyOfficers={},nearbyCruisers=0,ownCruiserRole=role,unitMode=mode,cruiserOccupants=occupants,skin=skin,
  autoCallsign=M.callsign(profile,skin,occupants,self.env.crew and self.env.crew()),station=station}
end
function C:tick(s,now)
 self.now=now
 if s.session~=self.session or s.ped~=self.ped then self:reset();self.session=s.session;self.ped=s.ped end
 local cfg=self.env.settings();if not s.session or not s.alive or not s.onDuty then self.snapshot={nearbyOfficers={},nearbyCruisers=0};return end
 local age=self.scanAt and core.elapsed(now,self.scanAt);if age and age<cfg.scan_ms then return end;self.scanAt=now
 local own=self:ownSnapshot(s);if not cfg.colleagues_enabled then self.snapshot=own;return end
 local r=self.env.read;local x,y,z=r('getCharCoordinates',s.ped);if not core.finite(x)or not core.finite(y)or not core.finite(z)then self.snapshot={nearbyOfficers={},nearbyCruisers=0};return end
 local skins=require('pa26_copilot_settings').ids(cfg.skin_ids,0,65535)or{};local vehicles=require('pa26_copilot_settings').ids(cfg.vehicle_models,400,65535)or{}
 local buddies={};for _,p in ipairs(self.env.partners()or{})do local nick=p.name or p.nickname or p.nick;if type(nick)=='string'then buddies[nick:lower()]=true end end
 local function near(px,py,pz)return core.finite(px)and core.finite(py)and core.finite(pz)and math.sqrt((px-x)^2+(py-y)^2+(pz-z)^2)or math.huge end
 local seen,rows={},{};local count=0;local recognized={[s.ped]=true}
 local localArea=r('getCharActiveInterior',s.ped)
 for _,ped in pairs(r('getAllChars')or{})do count=count+1;if count>2048 then break end
  if core.finite(ped)and ped~=s.ped and not seen[ped]then seen[ped]=true
   if r('doesCharExist',ped)==true and r('isCharDead',ped)==false and core.pedAreaCompatible(localArea,r('getCharActiveInterior',ped))then
    local px,py,pz=r('getCharCoordinates',ped);local distance=near(px,py,pz)
    if distance<=cfg.colleague_radius then local ok,id=r('sampGetPlayerIdByCharHandle',ped);local back,handle=r('sampGetCharHandleBySampPlayerId',id)
     if ok==true and core.validId(id)and back==true and handle==ped and r('sampIsPlayerConnected',id)==true and r('sampIsPlayerNpc',id)==false then
      local nick=r('sampGetPlayerNickname',id);local skin=r('getCharModel',ped)
      if type(nick)=='string'and #nick<=24 and(cfg.uniforms_enabled and skins[skin]or cfg.radio_cache and self.knownColleagues[nick:lower()]or buddies[nick:lower()])then
       recognized[ped]=true
       rows[#rows+1]={id=id,name=nick,skin=skin,role_label=M.pdSkins[skin]and M.pdSkins[skin].label or'Коллега из чата / контактов',distance=distance}
      end
     end
    end
   end
  end
 end
 table.sort(rows,function(a,b)return a.distance<b.distance end)
 local n=0;seen={};count=0
 for _,car in pairs(r('getAllVehicles')or{})do count=count+1;if count>2048 then break end
  if core.finite(car)and not seen[car]then seen[car]=true
   if r('doesVehicleExist',car)==true then
    local px,py,pz=r('getCarCoordinates',car);local driver=r('getDriverOfCar',car)
    if(vehicles[r('getCarModel',car)]or recognized[driver])and near(px,py,pz)<=cfg.colleague_radius and core.finite(driver)and r('doesCharExist',driver)==true then n=n+1 end
   end
  end
 end
 own.nearbyOfficers=rows;own.nearbyCruisers=n;self.snapshot=own
end
function C:view()return copy(self.snapshot)end
function M.guard(cfg,zone,officers,pursuit)
 if not cfg.ghetto_guard or pursuit or officers>=cfg.min_officers then return end
 for part in(cfg.danger_zones..','):gmatch('(.-),')do if part:match('^%s*(.-)%s*$')==zone then return cfg.ghetto_warning:gsub('{officers}',tostring(officers)):gsub('{min_officers}',tostring(cfg.min_officers))end end
end
return M

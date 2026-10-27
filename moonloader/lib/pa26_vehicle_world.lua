-- Native reads live here; called from main(), never a render/RPC callback.
local core=require 'pa26_core'
local names=require 'pa26_vehicle_names'
local M={}
function M.angle(origin,forward,candidate,cone,maxHeight)
    if not(origin and forward and candidate)or not core.finite(cone)or not core.finite(maxHeight)or cone<0 or cone>180 or maxHeight<0 then return nil end
    for _,r in ipairs({{origin,'x'},{origin,'y'},{origin,'z'},{candidate,'x'},{candidate,'y'},{candidate,'z'},{forward,'x'},{forward,'y'}})do if not core.finite(r[1][r[2]])then return nil end end
    if maxHeight>0 and math.abs(candidate.z-origin.z)>maxHeight then return nil end
    local dx,dy=candidate.x-origin.x,candidate.y-origin.y
    local length=math.sqrt(dx*dx+dy*dy);local norm=math.sqrt(forward.x^2+forward.y^2)
    if norm<.0001 then return nil end
    if length<.0001 then return 0 end
    local dot=math.max(-1,math.min(1,(dx*forward.x+dy*forward.y)/(length*norm)))
    local angle=math.deg(math.acos(dot))
    return angle<=cone+.000001 and angle or nil
end
function M.new(read,codec,ped)
    local api={}
    local function location()
        local p=ped();if read('doesCharExist',p)~=true then return end
        local x,y,z=read('getCharCoordinates',p)
        if not core.finite(x)or not core.finite(y)or not core.finite(z)then return end
        local car=read('isCharInAnyCar',p)==true and read('storeCarCharIsInNoSave',p)or nil
        return x,y,z,car
    end
    local function vehicle(handle,visible,maximum,origin)
        if not core.finite(handle)or read('doesVehicleExist',handle)~=true then return end
        local lx,ly,lz,own
        if origin then lx,ly,lz,own=origin.x,origin.y,origin.z,origin.car else lx,ly,lz,own=location()end
        if not lx or handle==own then return end
        local ok,id=read('sampGetVehicleIdByCarHandle',handle)
        if ok~=true or not core.finite(id)or id<1 or id>=2000 or id~=math.floor(id)then return end
        local mapped,roundtrip=read('sampGetCarHandleBySampVehicleId',id)
        if mapped~=true or roundtrip~=handle then return end
        local x,y,z=read('getCarCoordinates',handle)
        local model=read('getCarModel',handle)
        if not core.finite(x)or not core.finite(y)or not core.finite(z)or not core.finite(model)or model~=math.floor(model)or model<400 or model>65535 then return end
        local distance=math.sqrt((x-lx)^2+(y-ly)^2+(z-lz)^2)
        if distance>maximum then return end
        if visible then
            if read('isCarOnScreen',handle)~=true then return end
            -- Ignore the vehicle itself in the line test, while buildings block it.
            if read('isLineOfSightClear',lx,ly,lz+1,x,y,z+1,true,false,false,true,false,false,false)~=true then return end
        end
        local a,b=read('getCarColours',handle)
        -- A GXT label may encode a modded font, rather than CP1251 or UTF-8.
        -- Mapping a verified model ID avoids corrupt names in UI and game text.
        local label=names[model]
        local driver=read('getDriverOfCar',handle);local driverKnown=core.finite(driver);local driverId,driverName
        if core.finite(driver)and read('doesCharExist',driver)==true then
            local mapped,pid=read('sampGetPlayerIdByCharHandle',driver)
            local back,ped=read('sampGetCharHandleBySampPlayerId',pid)
            if mapped==true and core.validId(pid)and back==true and ped==driver and read('sampIsPlayerConnected',pid)==true and read('sampIsPlayerNpc',pid)==false then driverId=pid;driverName=read('sampGetPlayerNickname',pid)end
        else driver=nil end
        local passengers=read('getNumberOfPassengers',handle)
        if not core.finite(passengers)then passengers=0 end;passengers=math.max(0,math.min(20,math.floor(passengers)))
        local weapon=driver and read('getCurrentCharWeapon',driver)
        return {id=id,handle=handle,model_id=model,model_name=label,color1=a,color2=b,x=x,y=y,z=z,distance=distance,
            driver_known=driverKnown,driver_ped=driver,driver_id=driverId,driver_name=driverName,passengers=passengers,occupants=(driver and 1 or 0)+passengers,
            armed=core.finite(weapon)and weapon>=22 and weapon<=38 and weapon~=40}
    end
    function api.scan(cfg)
        local lx,ly,lz,own=location();if not lx then api.lastStatus='Координаты недоступны.';return {}end
        local origin={x=lx,y=ly,z=lz,car=own}
        local mode=cfg.selection_mode or 'auto';local forward,basis
        if (mode=='auto'or mode=='vehicle')and own then
            local x,y=read('getOffsetFromCarInWorldCoords',own,0,1,0)
            local ox,oy=read('getCarCoordinates',own)
            if core.finite(x)and core.finite(y)and core.finite(ox)and core.finite(oy)and (x-ox)^2+(y-oy)^2>.0001 then forward={x=x-ox,y=y-oy};basis='транспорт'end
        end
        if not forward and(mode=='camera'or mode=='auto')then
            local cx,cy=read('getActiveCameraCoordinates');local tx,ty=read('getActiveCameraPointAt')
            if core.finite(cx)and core.finite(cy)and core.finite(tx)and core.finite(ty)and (tx-cx)^2+(ty-cy)^2>.0001 then forward={x=tx-cx,y=ty-cy};basis='камера'end
        end
        if not forward and(mode=='vehicle'or mode=='camera')then api.lastStatus=mode=='vehicle'and'Направление машины недоступно. Сядьте в машину или выберите другой режим.'or'Направление камеры недоступно. Выберите режим «Экран».';return {}end
        api.lastStatus=forward and('Направление выбора: '..basis)or mode=='screen'and'Выбор по видимости на экране.'or'Направление недоступно; используется видимость на экране.'
        local all=read('getAllVehicles');if type(all)~='table'then return {}end
        local out,seen={},{};local count=0
        for _,handle in pairs(all)do
            count=count+1;if count>2048 then break end
            if core.finite(handle)and not seen[handle]then seen[handle]=true
                local c=vehicle(handle,cfg.front_only,cfg.radius,origin)
                if c then
                    local maxHeight=cfg.height_tolerance or 8
                    local angle=forward and M.angle(origin,forward,c,cfg.cone_angle or 65,maxHeight)or nil
                    local eligible=(not forward or angle~=nil)and(maxHeight==0 or math.abs(c.z-lz)<=maxHeight)
                    local driver=cfg.occupied_only and read('getDriverOfCar',handle)or nil
                    if eligible and(not cfg.occupied_only or core.finite(driver)and read('doesCharExist',driver)==true)then c.angle=angle;c.selection_basis=basis or 'экран';out[#out+1]=c end
                end
            end
        end
        return out
    end
    function api.status()return api.lastStatus end
    function api.resolve(selected,cfg)return vehicle(selected.handle,false,cfg.retain_distance)end
    function api.ownCar()
        local _,_,_,handle=location();if not handle or read('doesVehicleExist',handle)~=true then return end
        local x,y,z=read('getCarCoordinates',handle)
        if core.finite(x)and core.finite(y)and core.finite(z)then return {handle=handle,x=x,y=y,z=z}end
    end
    return api
end
return M

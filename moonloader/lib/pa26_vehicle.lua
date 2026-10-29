-- Streamed, visible vehicle only. Vehicle identity is independent of a player ID.
local core=require 'pa26_core'
local mapGrid=require 'pa26_map_grid'
local model=require 'pa26_bindings'
local settings=require 'pa26_vehicle_settings'
local radio=require 'pa26_radio_text'
local M={};local Vehicle={};Vehicle.__index=Vehicle
local function same(a,b)return a and b and a.id==b.id and a.handle==b.handle and a.model_id==b.model_id and a.generation==b.generation end
local function sceneSafe(s)return s and s.session and s.alive and s.focused and not s.paused and not s.blocked end
function M.selectable(c,cfg)return c and(not cfg.occupied_only or core.validId(c.driver_id)and core.finite(c.driver_ped))end
local function safe(s)return sceneSafe(s)and s.onDuty and s.radioEnabled end
local function megaphone(action)return action=='megaphone'or tostring(action):match('^megaphone_%d+$')~=nil end
function M.needsTarget(action,cfg)
    local slot=tonumber(tostring(action):match('^megaphone_(%d+)$'))
    return not(slot and cfg.phrases[slot]and cfg.phrases[slot].target=='none')
end
local function allowed(action,cfg,s)
    if not megaphone(action)then return cfg.enabled and safe(s)end
    return cfg.megaphone_enabled and sceneSafe(s)and(not cfg.megaphone_require_duty or s.onDuty)and(not cfg.megaphone_require_radio or s.radioEnabled)
end
local function needsPatrol(action,cfg)return megaphone(action)and cfg.megaphone_require_patrol or not megaphone(action)and cfg.require_patrol end
function M.compass(dx,dy,names)
    if not core.finite(dx)or not core.finite(dy)or dx==0 and dy==0 then return end
    local angle=math.deg(math.atan2(dx,dy))%360
    return names[(math.floor((angle+22.5)/45)%8)+1]
end
function M.colors(c,cfg)
    local palette=require 'pa26_vehicle_palette'
    local function color(id)return cfg.color_aliases[tostring(id)]or palette[tostring(id)]or cfg.unknown_color end
    local a,b=color(c.color1),color(c.color2)
    return a==b and a or a..cfg.color_separator..b,a,b
end
-- A user-selected RP convention, not a server registration lookup.
function M.plate(c,cfg)
    cfg=cfg or {};c=c or {}
    if type(cfg.select_plate)=='string'and cfg.select_plate:match('%S')then return cfg.select_plate end
    if cfg.auto_plate~=false and core.finite(c.id)and c.id%1==0 and c.id>=0 and c.id<=65535 then
        local digits=cfg.plate_digits or 3;local prefix=cfg.plate_prefix or'SA-'
        if not core.finite(digits)or digits%1~=0 or digits<1 or digits>6 or type(prefix)~='string'or #prefix>32 or not core.validUtf8(prefix)or prefix:find('%c')then return 'проверьте настройки номера'end
        return prefix..string.format('%0'..tostring(digits)..'d',c.id)
    end
    return 'не указан'
end
function M.describe(c,cfg,gender)
    local name=cfg.model_aliases[tostring(c.model_id)]or c.model_name or cfg.unknown_model
    local color,a,b=M.colors(c,cfg)
    local kind,gen=require('pa26_vehicle_types').names(c.model_id,cfg.type_names)
    local values={vehicle_type=kind,vehicle_type_gen=gen,model=name,model_id=tostring(c.model_id),vehicle_id=tostring(c.id),vehicle_color=color,color_one=a,color_two=b}
    local cp=cfg.copilot or{}
    values.occupants=tostring(c.occupants or 1);values.occupants_text=({[0]='салон пуст',[1]='внутри один',[2]='внутри двое',[3]='внутри трое',[4]='внутри четверо'})[c.occupants or 1]or('внутри '..tostring(c.occupants)..' чел.')
    values.driver_id=c.driver_id and tostring(c.driver_id)or'';values.driver_name=c.driver_name and c.driver_name:gsub('_',' ')or'Водитель'
    values.vehicle_plate=M.plate(c,cp)
    values.tac=cp.tac_channel or'TAC 1';values.stop_outcome=cp.stop_outcome or'проведена беседа';values.armed_text=(c.armed or cp.pursuit_armed)and' Подозреваемые вооружены!'or''
    local missing
    local description=core.expandGender(cfg.description_template,gender):gsub('{([a-z_]+)}',function(k)if not values[k]then missing=k;return ''end;return values[k]end)
    if missing then return nil,'Описание машины: используйте {vehicle_type}, {vehicle_type_gen}, {model}, {model_id}, {vehicle_id}, {vehicle_color}, {color_one}, {color_two}.'end
    values.vehicle_description=description;return values
end
function M.new(env)return setmetatable({env=env,life=1,targetLife=1,serial=0,candidates={},generations={}},Vehicle)end
function Vehicle:cancel(reason)
    local p=self.queued;self.queued=nil;self.intent=nil
    if p and self.env.cancel then self.env.cancel(p.token,reason)end
    self.message=reason
end
function Vehicle:reset(reason)
    self:cancel(reason);self.life=self.life+1;self.selected=nil;self.candidates={};self.phase=nil;self.motion=nil;self.own=nil;self.scanAt=nil
    self.selectionRequest=nil;self.retainedByStream=nil
    self.syncedDriver=nil;self.syncedRevision=nil;self.driverSelectionRevision=nil
end
function Vehicle:clearTarget(reason,streamLost)
    self.retainedByStream=streamLost==true
    self.targetLife=self.targetLife+1
    local p=self.queued or self.intent
    if p and p.target then self:cancel(reason)end
    self.selected=nil;self.candidates={};self.phase=nil;self.scanAt=nil
    self.syncedDriver=nil;self.syncedRevision=nil;self.driverSelectionRevision=nil
    if not p or p.target then self.message=reason end
end
function Vehicle:invalidate(id,kind)
    if not core.finite(id)then return end
    self.generations[id]=(self.generations[id]or 0)+1
    if self.selected and self.selected.id==id then self:clearTarget('Выбранная машина выгружена или её ID выдан заново.',kind=='onVehicleStreamOut')end
    self.scanAt=nil
end
function Vehicle:decorate(c)
    if not c or not core.finite(c.id)or not core.finite(c.handle)or not core.finite(c.model_id)then return end
    c=model.copy(c);c.generation=self.generations[c.id]or 0;return c
end
function Vehicle:direction(s,now,cfg)
    local car=self.env.ownCar and self.env.ownCar()
    self.own=car;self.directionValue=cfg.stationary
    if not cfg.direction_enabled or not car then self.motion=nil;return end
    local old=self.motion;local age=old and core.elapsed(now,old.at)
    if old and old.handle==car.handle and age and age>=cfg.motion_ms and age<=5000 then
        local dx,dy=car.x-old.x,car.y-old.y;local distance=math.sqrt(dx*dx+dy*dy)
        if distance>=cfg.stationary_distance and distance<=cfg.max_motion_distance then
            self.directionValue=M.compass(dx,dy,cfg.directions)or cfg.stationary
        end
    elseif old and old.handle==car.handle and age and age<cfg.motion_ms then
        self.directionValue=old.direction or cfg.stationary;return
    end
    self.motion={handle=car.handle,x=car.x,y=car.y,at=now,direction=self.directionValue}
end
function Vehicle:values(state,c)
    local out=model.copy(state or self.state or {});local cfg=self.env.settings()
    c=c or self.selected
    for k,v in pairs(self.env.service and self.env.service()or {})do if out[k]==nil or out[k]==''then out[k]=v end end
    out.direction=cfg.direction_enabled and(self.directionValue or cfg.stationary)or cfg.manual_direction
    local profile=self.env.profile and self.env.profile()or{};local nearby=out.colleagues or{}
    if not out.unit or out.unit==''then out.unit=nearby.unitAuto or(profile.callsign~=''and profile.callsign)or nearby.autoCallsign or'1-L-1'end
    if not out.station or out.station==''then out.station=nearby.station or'LSPS'end
    if not out.crew or out.crew==''then out.crew=profile.name~=''and profile.name or out.my_name or'Офицер'end
    if not out.city or out.city==''then out.city=profile.city and profile.city~=''and profile.city or'не определён'end
    if c then local values,err=M.describe(c,cfg,out.gender);if not values then return nil,err end;for k,v in pairs(values)do out[k]=v end end
    return out
end
function Vehicle:periodic(base)
    local cfg=self.env.settings();if not cfg.enabled or not self.phase then return base end
    local out=model.copy(base)
    out.session_key=(base.session_key or '')..':vehicle:'..self.phase..':'..tostring(self.selected and self.selected.id or '')
    if self.phase=='10-55'then if cfg.pause_patrol_reports then out.enabled=false end;return out end
    if self.phase=='Преследование'then
        out.enabled=base.enabled and cfg.pursuit_periodic and self.selected~=nil
        out.confirmation=cfg.pursuit_confirmation
        for _,kind in ipairs({'police','prison'})do
            out[kind..'_template']=cfg.pursuit_periodic_template;out[kind..'_channel']=cfg.channel;out[kind..'_interval_ms']=cfg.pursuit_interval_ms
        end
    end
    return out
end
function M.preview(action,cfg,values,codec,split)
    local slot=tonumber(tostring(action):match('^megaphone_(%d+)$'))
    local phrase=slot and cfg.phrases and cfg.phrases[slot]
    if slot and(not phrase or not phrase.enabled)then return nil,'Требование выключено или удалено.'end
    local body=phrase and phrase.template or cfg[action..'_template'];if not body then return nil,'Неизвестное действие транспорта.'end
    values=mapGrid.reportValues(values,body,not megaphone(action)and action~='approach'and action~='window')
    local missing;body=core.expandGender(body,values.gender):gsub('{([a-z_]+)}',function(k)
        local v=values[k];local tag=k=='local_tag'or k=='global_tag'or k=='prison_tag'or k=='armed_text'
        if v==nil and not tag or v==''and not tag then missing=k;return ''end
        return tag and k~='armed_text'and v and v~=''and tostring(v)..' 'or tostring(v or '')
    end)
    if missing then return nil,'Заполните поле: '..missing end
    local channel=phrase and phrase.channel or action=='megaphone'and cfg.megaphone_channel or action=='approach'and '/me'or action=='window'and '/do'or cfg.channel
    return radio.prepare(channel,body,codec,split,values.rpText,values.my_nick)
end
function Vehicle:phraseAllowed(action,cfg)
    local slot=tonumber(tostring(action):match('^megaphone_(%d+)$'))
    if not slot then return true end
    local p=cfg.phrases and cfg.phrases[slot]
    if not p or not p.enabled then return false end
    return p.condition=='any'or p.condition=='vehicle'and self.own~=nil or p.condition=='foot'and self.own==nil or
        p.condition=='stop'and self.phase=='10-55'or p.condition=='pursuit'and self.phase=='Преследование'
end
function Vehicle:proposalValid(p)
    local cfg=self.env.settings();local s=self.state;local age=p and core.elapsed(self.now,p.at)
    if not p or not allowed(p.action,cfg,s)or p.life~=self.life or p.session~=s.session or p.ped~=s.ped or p.demo~=s.demo or
        not age or age>cfg.confirmation_ms or not self.env.equal(cfg,p.cfg)then return false end
    local a=self.env.patrol and self.env.patrol()
    if needsPatrol(p.action,cfg)and(not a or a.status~='active'or a.id~=p.patrol_id)then return false end
    if not self:phraseAllowed(p.action,cfg)then return false end
    if not p.started then
        local values=self:values(s,p.target);if not values then return false end
        local fresh=M.preview(p.action,cfg,values,self.env.codec,s.radioText)
        if not fresh or radio.key(fresh)~=radio.key(p.prepared)then return false end
    end
    if not M.needsTarget(p.action,cfg)then return p.target==nil end
    if p.targetLife~=self.targetLife or not same(self.selected,p.target)then return false end
    if self.selected.color1~=p.target.color1 or self.selected.color2~=p.target.color2 then return false end
    if(p.action=='approach'or p.action=='window')and(self.own or self.selected.distance>cfg.approach_distance)then return false end
    return self.selected.distance<=cfg.retain_distance
end
function Vehicle:refreshCandidates(cfg)
    self.scanAt=self.now;self.candidates={}
    local ok,rows=pcall(self.env.scan,cfg)
    if ok and type(rows)=='table'then
        for _,c in ipairs(rows)do local v=self:decorate(c)
            if v and M.selectable(v,cfg)and core.finite(v.distance)and v.distance>=0 then self.candidates[#self.candidates+1]=v end
        end
    end
    local nearEmpty,nearOccupied=math.huge,math.huge
    for _,c in ipairs(self.candidates)do
        if(c.occupants or 0)>0 then nearOccupied=math.min(nearOccupied,c.distance)else nearEmpty=math.min(nearEmpty,c.distance)end
    end
    local immediateEmpty=nearEmpty<8 and nearOccupied>25
    local function tier(c)
        if not cfg.occupied_priority then return 0 end
        if immediateEmpty and(c.occupants or 0)==0 and c.distance<8 then return 0 end
        return(c.occupants or 0)>0 and(immediateEmpty and 1 or 0)or 2
    end
    table.sort(self.candidates,function(a,b)
        local ta,tb=tier(a),tier(b);if ta~=tb then return ta<tb end
        local closeA,closeB=a.distance<=12,b.distance<=12
        if closeA~=closeB then return closeA end
        if closeA and a.distance~=b.distance then return a.distance<b.distance end
        local aa,ab=core.finite(a.angle)and a.angle or 181,core.finite(b.angle)and b.angle or 181
        if cfg.selection_ranking=='direction'and aa~=ab then return aa<ab end
        if a.distance==b.distance then return a.id<b.id end;return a.distance<b.distance
    end)
end
function Vehicle:requestSelection(id)
    local cfg=self.env.settings()
    if not(cfg.enabled or cfg.megaphone_enabled)or not sceneSafe(self.state)then return nil,'Включите транспорт или мегафон; игра должна быть доступна.'end
    self.selectionRequest={id=id,life=self.life,session=self.state.session,at=self.now};return true
end
function Vehicle:syncDriverTarget(cfg)
    if not cfg.sync_driver_target or not self.env.driver or not self.env.currentTarget or not self.env.selectTarget then
        self.syncedDriver=nil;self.syncedRevision=nil;return
    end
    local explicit=(self.selectionRevision or 0)~=(self.driverSelectionRevision or 0)
    self.driverSelectionRevision=self.selectionRevision or 0
    local car=self.selected;if not car then return end
    local target,revision=self.env.currentTarget();local old=self.syncedDriver
    -- Retaining an already captured driver is separate from candidate scanning.
    -- A parked car cannot become a new target, but an exited driver is still
    -- the same person throughout the active stop/pursuit.
    local exited=self.phase~=nil and car.driver_known==true and car.driver_id==nil and old~=nil
    local id=exited and old.id or car.driver_id;if not core.validId(id)then return end
    local automatic=target and old and target.id==old.id and target.ped==old.ped and target.name==old.name and revision==self.syncedRevision
    if not(explicit or not target and(not old or self.phase~=nil)or automatic)then return end
    local driver=self.env.driver(id)
    if not core.capturedTargetValid(driver)then return end
    if exited then
        if driver.ped~=old.ped or driver.name~=old.name or old.generation~=nil and driver.generation~=old.generation then return end
    elseif car.driver_ped and driver.ped~=car.driver_ped or car.driver_name and driver.name~=car.driver_name then return end
    if target and target.id==driver.id and target.ped==driver.ped and target.name==driver.name then
        if explicit or automatic then self.syncedDriver=model.copy(driver);self.syncedRevision=revision end
        return
    end
    if self.env.selectTarget(driver)then
        self.syncedDriver=model.copy(driver)
        local _,fresh=self.env.currentTarget();self.syncedRevision=fresh
    end
end
function Vehicle:selectNearest(fresh)
    if fresh and #self.candidates==0 then self:refreshCandidates(self.env.settings())end
    local cfg=self.env.settings();local c
    for _,row in ipairs(self.candidates)do if M.selectable(row,cfg)then c=row;break end end
    if not c then return nil,cfg.occupied_only and'Рядом нет видимой машины с игроком за рулём. Повернитесь к ней или измените дальность.'or'Рядом нет видимой машины. Повернитесь к нужному автомобилю или измените дальность выбора.'end
    if not same(self.selected,c)then self:clearTarget('Выбрана другая машина.')end
    self.selected=model.copy(c);self.selectionRevision=(self.selectionRevision or 0)+1;return true
end
function Vehicle:selectCandidate(id)
    local cfg=self.env.settings()
    if not(cfg.enabled or cfg.megaphone_enabled)or not sceneSafe(self.state)then return nil,'Включите транспорт или мегафон; игра должна быть доступна.'end
    for _,c in ipairs(self.candidates)do if c.id==id and M.selectable(c,cfg)then
        if not same(self.selected,c)then self:clearTarget('Выбрана другая машина.')end
        self.selected=model.copy(c);self.selectionRevision=(self.selectionRevision or 0)+1;return true
    end end
    return nil,'Машина больше не входит в список рядом.'
end
function Vehicle:propose(action,nearest)
    local cfg=self.env.settings();local s=self.state
    if not allowed(action,cfg,s)then
        if megaphone(action)then return nil,'Мегафон недоступен. Включите его в «Помощники → Мегафон» и проверьте выбранные условия службы и рации.'end
        return nil,'Включите транспорт, служебный режим и рацию.'
    end
    local a=self.env.patrol and self.env.patrol()
    if needsPatrol(action,cfg)and(not a or a.status~='active')then return nil,'Сначала начните патруль или измените условие доступа в настройках этой функции.'end
    if self.intent or self.queued then return nil,'Дождитесь текущего действия или отмените его.'end
    if not self:phraseAllowed(action,cfg)then return nil,'Требование выключено или его условие сейчас не выполнено.'end
    local targeted=M.needsTarget(action,cfg)
    if nearest and targeted then local ok,err=self:selectNearest();if not ok then return nil,err end end
    local c=targeted and self.selected or nil;if targeted and not c then return nil,'Сначала выберите машину или используйте общее объявление.'end
    if(action=='approach'or action=='window')and(self.own or c.distance>cfg.approach_distance)then return nil,'Для этого действия выйдите из машины и подойдите к выбранному автомобилю.'end
    local values,err=self:values(s,c);if not values then return nil,err end
    if not targeted then for key in pairs(settings.vehicleFields)do values[key]=nil end end
    local prepared;prepared,err=M.preview(action,cfg,values,self.env.codec,s.radioText)
    if not prepared then return nil,err end
    self.serial=self.serial+1
    local p={token='vehicle:'..self.life..':'..self.serial,action=action,life=self.life,session=s.session,ped=s.ped,demo=s.demo,
        at=self.now,target=c and model.copy(c)or nil,targetLife=targeted and self.targetLife or nil,cfg=model.copy(cfg),patrol_id=a and a.id or 0,prepared=prepared,description=values.vehicle_description}
    local slot=tonumber(tostring(action):match('^megaphone_(%d+)$'));if slot then p.label=cfg.phrases[slot].name end
    return p
end
function Vehicle:accept(p)
    if self.intent or self.queued then return nil,'Действие транспорта уже ожидает отправки.'end
    if not self:proposalValid(p)then return nil,'Условия, настройки или игровая сцена изменились. Подготовьте подтверждение заново.'end
    self.intent=model.copy(p);return true
end
function Vehicle:validPlan(plan)
    local p=self.queued
    return p and plan.vehicleAction and plan.vehicleAction.token==p.token and self:proposalValid(p)and
        not self.state.typing and not self.state.modal and radio.key(plan)==table.concat(p.prepared.wires,'\0')or false
end
function Vehicle:onExecution(kind,q)
    local p=self.queued;if not p or not q.plan.vehicleAction or q.plan.vehicleAction.token~=p.token then return end
    if kind=='sent_line'or kind=='preview_line'then p.started=true end
    if kind=='completed'then
        self.queued=nil
        if p.action=='finish'then self.phase=nil elseif p.action=='traffic_stop'then self.phase='10-55'elseif p.action=='pursuit'then self.phase='Преследование'end
        self.message=q.demo and 'Демо завершено · отправок нет.'or 'Все строки переданы клиенту. Ответ сервера определяет результат.'
    elseif kind=='cancelled'then self.queued=nil;self.message='Действие прервано; оставшиеся строки отменены без повтора.'end
end
function Vehicle:tick(state,now)
    if state.incapacitated then
        self.state=model.copy(state);self.now=now;self:cancel('Персонаж ранен. Ситуация транспорта сохранена.');return
    end
    local previous=self.state
    if previous and previous.incapacitated and previous.session==state.session and previous.local_nick==state.local_nick then
        previous=model.copy(previous);previous.ped=state.ped;previous.alive=state.alive
    end
    local age=self.now and core.elapsed(now,self.now)
    if previous and(not age or previous.session~=state.session or previous.ped~=state.ped or previous.alive~=state.alive or previous.demo~=state.demo)then self:reset('Игровая сцена изменилась.')end
    self.state=model.copy(state);self.now=now;local cfg=self.env.settings()
    if not state.session or not state.alive or not state.focused or state.paused or state.blocked then
        self:cancel('Игра или ввод недоступны. Действие транспорта отменено.');self.motion=nil;self.directionValue=cfg.stationary;return
    end
    self:direction(state,now,cfg)
    if not cfg.enabled and not cfg.megaphone_enabled then if self.selected or self.intent or self.queued then self:reset('Транспорт и мегафон отключены.')end;return end
    local scanAge=self.scanAt and core.elapsed(now,self.scanAt)
    if self.selectionRequest or not scanAge or scanAge>=cfg.scan_ms then
        self:refreshCandidates(cfg)
        if self.selected then
            local tracking=cfg
            if self.env.retention then local p=self.env.retention();if p then tracking=model.copy(cfg);tracking.retain_distance=p.distance end end
            local current=self:decorate(self.env.resolve(self.selected,tracking))
            if not same(current,self.selected)or current.distance>tracking.retain_distance then self:clearTarget('Выбранная машина недоступна или слишком далеко.',current==nil)
            else self.selected=current end
        end
    end
    local selection=self.selectionRequest;self.selectionRequest=nil
    if selection and selection.life==self.life and selection.session==state.session and(core.elapsed(now,selection.at)or math.huge)<2000 then
        local ok,err
        if selection.id then ok,err=self:selectCandidate(selection.id)else ok,err=self:selectNearest(true)end
        if not ok then self.message=err;if self.env.notice then self.env.notice(err)end end
    end
    self:syncDriverTarget(cfg)
    local p=self.intent
    if p then
        if not self:proposalValid(p)then self:cancel('Подтверждение транспорта устарело.')
        elseif not state.busy and not state.modal and not state.typing and not state.recording and not state.wheel and not state.alertPending then
            self.intent=nil
            local b=model.newBinding(999999993);b.name=(megaphone(p.action)and'Мегафон · 'or'Транспорт · ')..(p.label or p.action);b.category='Патруль';b.script=p.prepared.line
            local plan={binding=b,requirements={target=false,closest=false},session=p.session,createdAt=now,demo=p.demo,has_command=true,
                steps=model.copy(p.prepared.steps),lines=model.copy(p.prepared.lines),wire=model.copy(p.prepared.wires),rpSignature=p.prepared.rpSignature,textSignature=p.prepared.textSignature,
                automatic={kind='vehicle_action'},vehicleAction={token=p.token}}
            self.queued=p;local ok,err=self.env.start(plan)
            if not ok then self.queued=nil;self.message='Не запущено: '..tostring(err)end
        end
    end
end
function Vehicle:view()
    local candidates={};for i=1,math.min(8,#self.candidates)do candidates[i]=model.copy(self.candidates[i])end
    return {selected=model.copy(self.selected),nearest=model.copy(self.candidates[1]),candidates=candidates,phase=self.phase,direction=self.directionValue,
        selection_status=self.env.selectionStatus and self.env.selectionStatus()or nil,message=self.message,pending=self.intent~=nil or self.queued~=nil}
end
M.same=same
return M

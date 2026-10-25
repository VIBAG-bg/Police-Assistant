-- Cached binding catalogue, geometry and hover state for the two-level wheel.
-- No game APIs, network or chat sends; drawing only uses the supplied ImGui context.
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local binder=require 'pa26_binder'
local M={HOVER_MS=110}
local tau=2*math.pi
local definitions={
    citizen={id='citizen',name='Гражданин'},documents={id='documents',name='Документы'},
    detention={id='detention',name='Задержание'},frisk={id='frisk',name='Досмотр'},
    wanted={id='wanted',name='Розыск и штрафы',label='Розыск\nи штрафы'},
    service={id='service',name='Служба'},leadership={id='leadership',name='Руководство'},custom={id='custom',name='Свои бинды'},
}
M.profiles={compact={'citizen','detention','wanted','service'},
    extended={'citizen','detention','wanted','service','leadership','custom'},
    full={'citizen','documents','detention','frisk','wanted','service','leadership','custom'}}
local aliases={['гражданин']='citizen',['общение']='citizen',['документы']='documents',
    ['задержание']='detention',['наручники']='detention',['миранда']='detention',['арест']='detention',
    ['досмотр']='frisk',['обыск']='frisk',['проверки']='wanted',['розыск']='wanted',['штрафы']='wanted',['розыск и штрафы']='wanted',
    ['служба']='service',['патруль']='service',['связь']='service',['рация']='service',['sos']='service',
    ['руководство']='leadership',['кадры']='leadership',['свои бинды']='custom'}
function M.groupFor(binding,profile)
    local group=binding.wheel_group
    if not group or group=='auto' then group=aliases[model.casefold(binding.category):match('^%s*(.-)%s*$')] or 'custom' end
    if profile~='full' then if group=='documents' then group='citizen' elseif group=='frisk' then group='detention' end end
    if profile=='compact' and (group=='leadership' or group=='custom') then group='service' end
    return definitions[group] and group or 'service'
end
function M.categoryName(id,names)
    local name=type(names)=='table'and names[id]
    return type(name)=='string'and name:find('%S')and name or definitions[id]and definitions[id].name or 'Категория'
end
function M.categoryChoices(names)
    local out={{'auto','По категории бинда'}}
    for _,id in ipairs(M.profiles.full)do out[#out+1]={id,M.categoryName(id,names)}end
    return out
end
function M.procedureItems(lib)
    local cfg=lib.procedures;local out={}
    if not cfg then return out end
    for _,kind in ipairs({'wanted','fine','mark'})do if require('pa26_case_forms').enabled(cfg,kind)then
        out[#out+1]={kind='procedure',id='procedure-'..kind,procedure=kind,category='wanted',name=cfg[kind..'_label'],
            wheel_visible=cfg[kind..'_wheel'],quick=cfg[kind..'_quick'],needsTarget=false}
    end end
    if cfg.wanted_assistant_enabled and cfg.wanted_enabled then
        out[#out+1]={kind='procedure',id='procedure-wanted_list',procedure='wanted_list',category='wanted',name='Список преступников',wheel_visible=cfg.wanted_wheel,quick=cfg.wanted_quick,needsTarget=false}
    end
    return out
end
function M.build(lib,revision,includeAlerts,serviceState)
    if lib.settings.wheel_mode=='classic' then return nil end
    local profile=lib.settings.wheel_profile or 'compact'
    local ids=M.profiles[profile] or M.profiles.compact
    local out={profile=profile,revision=revision or 0,categories={},byId={},byCategory={},bySystem={}}
    for _,id in ipairs(ids) do
        local d=definitions[id];local custom=lib.settings.wheel_names and lib.settings.wheel_names[id]
        local name=M.categoryName(id,lib.settings.wheel_names)
        local cat={id=id,name=name,label=custom and custom:find('%S')and name or d.label or name,items={}}
        out.categories[#out.categories+1]=cat; out.byCategory[id]=cat
    end
    if includeAlerts and lib.alerts and lib.alerts.enabled and lib.alerts.on_duty then
        for _,spec in ipairs({{'sos','SOS\nподдержка'},{'shots','Доклад о\nстрельбе'},{'code0','CODE 0\nранение'}}) do
            if lib.alerts[spec[1]..'_enabled']~=false then
            local item={kind='alert',id=spec[1],category='service',name=spec[2],needsTarget=false}
            if item.id=='code0' then
                item.disabled=not (serviceState and core.finite(serviceState.health) and serviceState.health>0 and serviceState.health<=lib.alerts.code0_health)
                item.reason='CODE 0: нужен живой офицер с HP ≤ '..lib.alerts.code0_health..'.'
            end
            out.bySystem[item.id]=item;out.byCategory.service.items[#out.byCategory.service.items+1]=item
            end
        end
    end
    if includeAlerts and lib.vehicle and lib.vehicle.megaphone_wheel then
        local item={kind='assist',id='assist-megaphone',category='service',name='Мегафон',needsTarget=false}
        out.bySystem[item.id]=item;out.byCategory.service.items[#out.byCategory.service.items+1]=item
    end
    if includeAlerts and lib.patrol_session and lib.patrol_session.enabled then
        local view=serviceState and serviceState.patrolSession or {};local a=view.active
        local rows={{'patrol-open',a and 'Патруль\nи экипаж'or 'Начать\nпатруль'}}
        if a then rows[#rows+1]={a.status=='paused'and 'patrol-resume'or 'patrol-pause',a.status=='paused'and 'Продолжить\nпатруль'or 'Пауза\nпатруля'};rows[#rows+1]={'patrol-finish','Завершить\nпатруль'}end
        for _,row in ipairs(rows)do
            local item={kind='patrol',id=row[1],category='service',name=row[2],needsTarget=false}
            out.bySystem[item.id]=item;out.byCategory.service.items[#out.byCategory.service.items+1]=item
        end
    end
    if includeAlerts then for _,item in ipairs(M.procedureItems(lib))do if item.wheel_visible then
        out.bySystem[item.id]=item;out.byCategory.wanted.items[#out.byCategory.wanted.items+1]=item
    end end end
    for _,b in ipairs(lib.bindings) do if b.wheel_visible then
        local req=binder.requirements(b)
        local item={id=b.id,name=b.name,binding=model.copy(b),needsTarget=req.target,category=M.groupFor(b,profile)}
        out.byId[b.id]=item; local cat=out.byCategory[item.category]
        cat.items[#cat.items+1]=item
    end end
    return out
end
function M.entries(cat)
    if #cat.items==0 then return {{kind='settings',category=cat.id,name='Добавить\nдействия'}} end
    local out={}; local limit=#cat.items<=6 and #cat.items or 5
    for i=1,limit do local e=cat.items[i]; out[i]={kind=e.kind or 'binding',id=e.id,category=cat.id,name=e.name} end
    if #cat.items>6 then out[#out+1]={kind='more',category=cat.id,name='Ещё '..(#cat.items-5)..'\nи поиск'} end
    return out
end
function M.available(catalog,route,demo,target)
    if not route then return false end
    local cat=catalog.byCategory[route.category]
    if route.kind=='more' then return cat~=nil and #cat.items>6 end
    if route.kind=='settings' then return cat~=nil and #cat.items==0 end
    if route.kind=='alert'or route.kind=='patrol'or route.kind=='procedure'or route.kind=='assist'then
        local item=catalog.bySystem and catalog.bySystem[route.id]
        if type(item)~='table'or item.kind~=route.kind or item.category~=route.category then return false,'Действие недоступно.' end
        return not item.disabled,item.disabled and item.reason or nil
    end
    local item=route.kind=='binding' and catalog.byId[route.id]
    if not item or item.category~=route.category then return false,'Действие недоступно.' end
    if not item.binding.enabled then return false,'Бинд выключен.' end
    if item.needsTarget and not demo and not target then return false,'Выберите человека для этого действия.' end
    return true
end
function M.sameRoute(a,b)
    return type(a)=='table' and type(b)=='table' and a.kind==b.kind and a.id==b.id and a.category==b.category
end
function M.layout(width,height,count)
    if not core.finite(width) or not core.finite(height) or not M.profiles.compact or
        (count~=4 and count~=6 and count~=8) then return nil end
    local scale=math.min(1,(width-32)/740,(height-32)/760)
    if scale<.55 then return nil end
    local w,h=740*scale,760*scale
    local x,y=(width-w)/2,(height-h)/2
    return {scale=scale,width=w,height=h,left=x,top=y,cx=x+370*scale,cy=y+355*scale,
        inner=82*scale,rootOuter=176*scale,childInner=188*scale,outer=306*scale,count=count,step=tau/count}
end
local function angle(dx,dy) return math.atan2(dy,dx) end
local function relative(a,center) return (a-center+math.pi)%tau-math.pi end
function M.rootAt(layout,dx,dy)
    local r=math.sqrt(dx*dx+dy*dy)
    if r<layout.inner or r>layout.rootOuter then return nil end
    local offset=(angle(dx,dy)+math.pi/2)%tau
    local within=offset%layout.step
    if within<.014 or within>layout.step-.014 then return nil end
    return math.floor(offset/layout.step)+1
end
function M.arc(layout,index,count)
    local center=-math.pi/2+(index-.5)*layout.step
    local span=math.min(144,math.max(48,count*24))*math.pi/180
    return {center=center,first=center-span/2,last=center+span/2,span=span,step=span/count}
end
function M.hover(nav,catalog,layout,dx,dy,now,blocked,demo,target)
    nav.choice=nil; nav.reason=nil
    if blocked or not core.finite(dx) or not core.finite(dy) or not core.finite(now) then nav.candidate=nil; return nil end
    local r=math.sqrt(dx*dx+dy*dy)
    if r<layout.inner then nav.active=nil; nav.candidate=nil; return nil end
    if r>layout.outer then nav.candidate=nil; return nil end
    local root=M.rootAt(layout,dx,dy)
    if root then
        if nav.active and root~=nav.active then
            local center=-math.pi/2+(nav.active-.5)*layout.step
            if math.abs(relative(angle(dx,dy),center))<layout.step/2+.055 then root=nav.active end
        end
        if root==nav.active then nav.candidate=nil
        elseif root~=nav.candidate then nav.candidate=root; nav.since=now
        else local elapsed=core.elapsed(now,nav.since)
            if not elapsed then nav.since=now
            elseif elapsed>=M.HOVER_MS then nav.active=root; nav.candidate=nil end
        end
        return nil -- Root categories never commit a binding.
    end
    nav.candidate=nil -- Opening a category requires continuous hover inside its visible sector.
    if r<layout.childInner or not nav.active then return nil end -- Stable bridge between rings.
    local cat=catalog.categories[nav.active]; if not cat then return nil end
    local entries=M.entries(cat); local arc=M.arc(layout,nav.active,#entries)
    local d=relative(angle(dx,dy),arc.center)
    if d< -arc.span/2 or d>=arc.span/2 then return nil end
    local pos=(d+arc.span/2)/arc.step
    if math.min(pos%1,1-pos%1)<.045 then return nil end -- Quiet angular gaps.
    local entry=entries[math.floor(pos)+1]
    local enabled,reason=M.available(catalog,entry,demo,target)
    nav.reason=reason
    if enabled then nav.choice=model.copy(entry) end
    return nav.choice
end
local function cornersFit(x,y,w,h,inner,outer,middle,span)
    for _,dx in ipairs({-w/2,w/2}) do for _,dy in ipairs({-h/2,h/2}) do
        local px,py=x+dx,y+dy; local r=math.sqrt(px*px+py*py)
        if r<inner+5 or r>outer-5 or math.abs(relative(angle(px,py),middle))>span/2-.024 then return false end
    end end
    return true
end
-- Fit native text to its actual wedge. Long action names also appear below the wheel.
local labelCache,labelCacheCount={},0
function M.fitLabel(font,text,size,wrap,inner,outer,middle,span)
    local key=table.concat({tostring(font),text,size,wrap,inner,outer,middle,span},'|')
    local cached=labelCache[key]
    if cached then return cached.size,cached.extent,cached.text,cached.wrap end
    local r=(inner+outer)/2; local x,y=math.cos(middle)*r,math.sin(middle)*r
    local originalSize=size
    while #text>0 do
        for candidate=originalSize,11,-1 do
            local wordWidth=0
            for word in text:gmatch('%S+') do wordWidth=math.max(wordWidth,font:CalcTextSizeA(candidate,100000,0,word).x) end
            for candidateWrap=wrap,math.max(36,wrap-60),-20 do
            if candidateWrap>=wordWidth then
            local extent=font:CalcTextSizeA(candidate,100000,candidateWrap,text)
            if cornersFit(x,y,extent.x,extent.y,inner,outer,middle,span) then
                cached={size=candidate,extent={x=extent.x,y=extent.y},text=text,wrap=candidateWrap}
                if labelCacheCount>=256 then labelCache={};labelCacheCount=0 end
                labelCache[key]=cached;labelCacheCount=labelCacheCount+1
                return candidate,cached.extent,text,candidateWrap
            end
            end
        end end
        local chars={};for c in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do if c~='…' then chars[#chars+1]=c end end
        if #chars<=1 then break end
        text=table.concat(chars,'',1,math.max(1,#chars-4))..'…'
    end
    return 11,{x=0,y=0},'',wrap
end
function M.shortLabel(text)
    local chars={}; for c in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do chars[#chars+1]=c end
    if #chars<=42 then return text end
    local short=table.concat(chars,'',1,39):gsub('%s+%S*$','')
    return short..'…'
end
function M.draw(im,layout,catalog,nav,info,fonts)
    local list,vec=im.GetWindowDrawList(),im.ImVec2
    local scale=layout.scale
    local function color(r,g,b,a) return im.ColorConvertFloat4ToU32(im.ImVec4(r,g,b,a)) end
    local white,muted=color(1,1,1,1),color(.70,.83,.93,1)
    local function centered(text,font,size,x,y,wrap,tint)
        font=font or im.GetFont(); size=size*scale; wrap=(wrap or 680)*scale
        local extent=font:CalcTextSizeA(size,100000,wrap,text)
        list:AddTextFontPtr(font,size,vec(x-extent.x/2,y-extent.y/2),tint or white,text,nil,wrap)
    end
    local function sector(inner,outer,first,last,fill)
        local gap=.014; first=first+gap; last=last-gap
        local segments=math.max(5,math.ceil((last-first)*22))
        for i=0,segments-1 do
            local a=first+(last-first)*i/segments; local b=first+(last-first)*(i+1)/segments
            list:PathClear()
            list:PathLineTo(vec(layout.cx+math.cos(a)*inner,layout.cy+math.sin(a)*inner))
            list:PathLineTo(vec(layout.cx+math.cos(a)*outer,layout.cy+math.sin(a)*outer))
            list:PathLineTo(vec(layout.cx+math.cos(b)*outer,layout.cy+math.sin(b)*outer))
            list:PathLineTo(vec(layout.cx+math.cos(b)*inner,layout.cy+math.sin(b)*inner))
            list:PathFillConvex(fill)
        end
    end
    local body=fonts.button or im.GetFont()
    for i,cat in ipairs(catalog.categories) do
        local first=-math.pi/2+(i-1)*layout.step; local last=first+layout.step
        local active=nav.active==i; local pending=nav.candidate==i
        sector(layout.inner,layout.rootOuter,first,last,
            active and color(.12,.42,.64,.84) or pending and color(.12,.31,.47,.78) or color(.035,.14,.23,.65))
        local middle=(first+last)/2; local radius=(layout.inner+layout.rootOuter)/2
        local size,extent,text,wrap=M.fitLabel(body,cat.label,18,layout.count==4 and 118 or layout.count==6 and 96 or 76,
            82,176,middle,layout.step)
        list:AddTextFontPtr(body,size*scale,vec(layout.cx+math.cos(middle)*radius-extent.x*scale/2,
            layout.cy+math.sin(middle)*radius-extent.y*scale/2),white,text,nil,wrap*scale)
    end
    local active=nav.active and catalog.categories[nav.active]
    if active then
        local entries=M.entries(active); local arc=M.arc(layout,nav.active,#entries)
        for i,entry in ipairs(entries) do
            local first=arc.first+(i-1)*arc.step; local last=first+arc.step; local middle=(first+last)/2
            local available=M.available(catalog,entry,info.demo,info.target)
            local selected=M.sameRoute(nav.choice,entry)
            sector(layout.childInner,layout.outer,first,last,selected and color(.16,.48,.72,.90) or
                available and color(.045,.19,.30,.70) or color(.075,.12,.17,.52))
            local label=M.shortLabel(entry.name)
            local size,extent,text,wrap=M.fitLabel(body,label,17,120,188,306,middle,arc.step)
            local radius=(layout.childInner+layout.outer)/2
            list:AddTextFontPtr(body,size*scale,vec(layout.cx+math.cos(middle)*radius-extent.x*scale/2,
                layout.cy+math.sin(middle)*radius-extent.y*scale/2),available and white or muted,text,nil,wrap*scale)
        end
    end
    list:AddCircleFilled(vec(layout.cx,layout.cy),layout.inner-3*scale,color(.035,.10,.16,.84),80)
    list:AddCircle(vec(layout.cx,layout.cy),layout.inner-3*scale,color(.29,.57,.75,.23),80,1.2*scale)
    centered('Police Assistant',fonts.heading,20,layout.cx,layout.top+24*scale,600)
    centered(info.demo and 'ID 42' or info.target and ('ID '..info.target.id) or 'Нет цели',fonts.id,26,layout.cx,layout.cy-17*scale,146)
    centered(info.demo and 'Демо-игрок' or info.nickname or 'Свои действия',fonts.body,14,layout.cx,layout.cy+20*scale,138,muted)
    local status=nav.reason or nav.choice and (nav.choice.kind=='binding' and catalog.byId[nav.choice.id].name or nav.choice.name) or
        active and (active.name..' · '..#active.items..' действий') or 'Наведите на категорию'
    centered(status,fonts.body,16,layout.cx,layout.top+684*scale,650)
    centered('К центру — назад · '..info.key..' отпустить или кликнуть — выбрать · Esc — отмена',fonts.small,14,
        layout.cx,layout.top+723*scale,700,muted)
end
return M

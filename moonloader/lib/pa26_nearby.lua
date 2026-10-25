-- Cached presentation only. Native scans/revalidation/selection run from main().
local core=require 'pa26_core'
local M={};local Nearby={};Nearby.__index=Nearby
local function copy(v)if type(v)~='table'then return v end;local r={};for k,x in pairs(v)do r[k]=copy(x)end;return r end
function M.defaults()return {enabled=true,distance=20,max_people=8,interval_ms=500}end
function M.validate(raw)
    local out=M.defaults();if raw==nil then return out end
    if type(raw)~='table'or type(raw.enabled)~='boolean'then return nil,'Проверьте включение списка людей рядом.'end
    out.enabled=raw.enabled
    for _,r in ipairs({{'distance',3,60},{'max_people',2,16},{'interval_ms',200,2000}})do
        local n=raw[r[1]];if not core.finite(n)or n~=math.floor(n)or n<r[2]or n>r[3]then return nil,'Проверьте настройку списка людей: '..r[1]end
        out[r[1]]=n
    end
    return out
end
local function safe(s)return s and s.session and s.ped and s.alive==true and s.focused==true and s.paused==false and not s.blocked and s.nearbyOpen==true and not s.modal end
local function same(a,b)return a and b and a.id==b.id and a.ped==b.ped and a.name==b.name and a.generation==b.generation end
function M.new(env)return setmetatable({env=env,rows={},generations={},serial=0},Nearby)end
function Nearby:reset()self.rows={};self.intent=nil;self.at=nil;self.serial=self.serial+1 end
function Nearby:invalidate(id)
    if not core.validId(id)then return end
    self.generations[id]=(self.generations[id]or 0)+1
    if self.intent and self.intent.target.id==id then self.intent=nil end
    for i=#self.rows,1,-1 do if self.rows[i].id==id then table.remove(self.rows,i)end end
    self.at=nil
end
function Nearby:request(target,revision)
    if revision~=self.serial or not safe(self.state)then return nil,'Список изменился. Выберите человека заново.'end
    for _,r in ipairs(self.rows)do if same(r,target)then
        self.intent={target=copy(r),revision=revision,session=self.state.session,ped=self.state.ped,interior=self.state.interior}
        self.message='Проверяю выбранного человека…';return true
    end end
    return nil,'Человека больше нет в текущем списке.'
end
function Nearby:requestId(id)
    if not core.validId(id)then return nil,'Укажите числовой SA:MP ID игрока.'end
    if not safe(self.state)then return nil,'Сначала закройте чат и другие подтверждения, затем повторите выбор.'end
    local locked
    for _,row in ipairs(self.rows)do if row.id==id then locked=copy(row);break end end
    self.intent={id=id,target=locked,generation=self.generations[id]or 0,revision=self.serial,
        session=self.state.session,ped=self.state.ped,interior=self.state.interior}
    return true
end
function Nearby:tick(state,now)
    local cfg=self.env.settings();local previous=self.state
    local changed=not previous or state.session~=previous.session or state.ped~=previous.ped or state.interior~=previous.interior or state.demo~=previous.demo
    local age=self.at and core.elapsed(now,self.at)
    if changed or self.at and not age then self:reset()end
    self.state=copy(state)
    if not cfg.enabled or not safe(state)then self:reset();return end
    local signature=table.concat({cfg.distance,cfg.max_people,cfg.interval_ms},':')
    if self.signature~=signature then self:reset();self.signature=signature end
    local pending=self.intent;self.intent=nil
    if pending then
        local t=pending.target
        local id=pending.id or t.id
        local generation=pending.id and pending.generation or t.generation
        if pending.revision==self.serial and pending.session==state.session and pending.ped==state.ped and pending.interior==state.interior and generation==(self.generations[id]or 0)then
            local ok,fresh
            if pending.id then ok,fresh=pcall(self.env.resolveId,id,cfg.distance)
            else ok,fresh=pcall(self.env.resolve,t,cfg.distance)end
            if ok and core.capturedTargetValid(fresh)and fresh.id==id and(not t or fresh.ped==t.ped and fresh.name==t.name)then
                local selected,result=pcall(self.env.select,fresh)
                self.message=selected and result==true and 'Человек выбран. Команды не отправлялись.'or 'Выбор сейчас недоступен.'
            else self.message='Человек ушёл, закрыт препятствием или его данные изменились. Повторите выбор.'end
        else self.message='Игровая сцена изменилась. Повторите выбор.'end
    end
    age=self.at and core.elapsed(now,self.at)
    if age and age<cfg.interval_ms then return end
    self.at=now
    local ok,all=pcall(self.env.scan,cfg.distance);local rows,seen={},{}
    if ok and type(all)=='table'then for i,t in ipairs(all)do
        if i>2048 then break end
        if core.capturedTargetValid(t)and core.validUtf8(t.name)and not t.name:find('%c')and core.finite(t.distance)and t.distance>=0 and t.distance<=cfg.distance and not seen[t.id]then
            local r=copy(t);r.generation=self.generations[t.id]or 0;rows[#rows+1]=r;seen[t.id]=true
        end
    end else self.message='Список видимых людей пока недоступен.'end
    table.sort(rows,function(a,b)if a.distance==b.distance then return a.id<b.id end;return a.distance<b.distance end)
    self.total=#rows;while #rows>cfg.max_people do table.remove(rows)end
    local identical=#rows==#self.rows
    if identical then for i,r in ipairs(rows)do if not same(r,self.rows[i])then identical=false;break end end end
    if not identical then self.serial=self.serial+1 end
    self.rows=rows
end
function Nearby:view()return {rows=copy(self.rows),revision=self.serial,total=self.total or 0,message=self.message,enabled=self.env.settings().enabled}end
function M.buttonId(r)
    local name=r.name:gsub('.',function(c)return string.format('%02x',c:byte())end)
    return 'nearby-'..r.id..'-'..r.ped..'-'..(r.generation or 0)..'-'..name
end
function M.draw(s,ui,data,callbacks)
    local view=data.nearby;if not view or not view.enabled then return end
    local im=s.imgui;local rows=view.rows
    s:settingsHeading(ui,'Люди рядом')
    local typed=s:field('Выбрать игрока по ID##nearby-id','nearby-id','',16)
    if s:button('Выбрать по ID##nearby-select-id',ui)then
        local id=typed:match('^%s*(%d+)%s*$')
        local ok,err=callbacks.selectNearbyId(id and tonumber(id)or nil)
        if not ok then s:notify(err,'nearby',false)end
    end
    s:observeStatus('nearby',view.message,'nearby')
    if #rows==0 then ui.text('Рядом нет доступных видимых игроков. Введите ID или поверните камеру к человеку.');return end
    local width=math.max(1,im.GetContentRegionAvail().x)
    local columns=math.max(1,math.min(3,math.floor((width+8)/228)))
    local pageSize=columns*(im.GetContentRegionAvail().y<300 and 1 or 2)
    local pages=math.ceil(#rows/pageSize);s.nearbyPage=math.max(1,math.min(s.nearbyPage or 1,pages))
    local first=(s.nearbyPage-1)*pageSize+1;local bw=(width-(columns-1)*8)/columns
    local labels,heights={},{};local font=s.buttonFont or im.GetFont();local size=tonumber(font.FontSize)
    for i=first,math.min(#rows,first+pageSize-1)do
        local r=rows[i];labels[i]=r.name:gsub('##','# #')..' ['..r.id..']\n'..string.format('%.1f м',r.distance)..'###'..M.buttonId(r)
        local row=math.floor((i-first)/columns)
        local layout=require('pa26_menu').labelLayout(font,size,math.max(1,bw-28),labels[i]:match('^(.-)##'))
        heights[row]=math.max(heights[row]or 60,layout.height+20)
    end
    for i=first,math.min(#rows,first+pageSize-1)do
        local r=rows[i];if (i-first)%columns~=0 then im.SameLine(0,8)end
        local selected=data.target and data.target.id==r.id and data.target.ped==r.ped and data.target.name==r.name
        if s:rowTitle(ui,labels[i],selected,bw,heights[math.floor((i-first)/columns)])then
            local ok,err=callbacks.selectNearby(r,view.revision);if not ok then s:notify(err)end
        end
    end
    if pages>1 then
        ui.text('Страница '..s.nearbyPage..' / '..pages)
        if s:button('Назад##nearby-page',ui,(width-8)/2)then s.nearbyPage=math.max(1,s.nearbyPage-1)end
        im.SameLine(0,8);if s:button('Далее##nearby-page',ui,(width-8)/2)then s.nearbyPage=math.min(pages,s.nearbyPage+1)end
    end
    ui.text('Выбираются любые видимые игроки рядом, включая офицеров. Нажатие не отправляет команд и не меняет ранг.')
    im.Separator()
end
function M.settings(s,ui)
    local im=s.imgui;local d=s.nearbyDraft or copy(s.lib.nearby)
    s:settingsHeading(ui,'Кнопки людей рядом')
    d.enabled=s:check('Показывать видимых людей рядом##nearby-enabled',d.enabled)
    for _,r in ipairs({{'distance','Дальность списка, м',3,60},{'max_people','Максимум людей в списке',2,16},{'interval_ms','Обновление списка, мс',200,2000}})do
        ui.text(r[2]);im.PushItemWidth(-1);ui.push(function()im.PopItemWidth()end)
        local n=im.new.int(d[r[1]]);if im.SliderInt('##nearby-'..r[1],n,r[3],r[4])then d[r[1]]=n[0]end;ui.finish()
    end
    ui.text('Список использует только видимых игроков. Перед выбором PA повторно проверяет ник, ID, персонажа, расстояние и препятствия. Дальность серверных действий этим списком не увеличивается. Список доступен в биндах, быстром меню и карточке человека.')
    s.nearbyDraft=d;s:autoSettings('nearby',{'nearby'},d,'nearbyDraft');s:autosaveHint(ui,'nearby')
end
return M

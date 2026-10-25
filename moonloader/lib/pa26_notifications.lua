-- Shared bottom-centre toast surface. No game APIs or chat sends in this file.
local core=require 'pa26_core'
local model=require 'pa26_bindings'
local M={};local Notices={};Notices.__index=Notices
local function safe(s)return s and s.focused==true and s.paused==false and s.blocked==false and s.typing~=true and
    s.recording~=true and s.editingHud~=true and s.draggingHud~=true and not s.alertPending and not s.modal end
local function inside(r,x,y)return r and core.finite(x)and core.finite(y)and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h end
local function overlaps(a,b)return a and b and a.x<b.x+b.w and a.x+a.w>b.x and a.y<b.y+b.h and a.y+a.h>b.y end
function M.new(env)return setmetatable({env=env,buttons={},lastKeys={}},Notices)end
function Notices:reset()self.active=nil;self.bounds=nil;self.buttons={};self.intent=nil;self.armed=nil;self.mouseArmed=nil;self.skipArmed=false;self.lastKeys={};self.paintedToken=nil;self.seenAt=nil end
local function pressed(shortcut,keys,last)
    return shortcut and shortcut.key~=0 and keys.keys and keys.keys[shortcut.key]==true and last[shortcut.key]~=true and
        not keys.super and keys.ctrl==shortcut.ctrl and keys.alt==shortcut.alt and keys.shift==shortcut.shift
end
function Notices:tick(candidates,state,now,keys)
    local dt=self.now and core.elapsed(now,self.now);self.now=now;self.state=state
    if not core.finite(now)or(dt==nil and self.lastNow)then self:reset()end;self.lastNow=now
    table.sort(candidates,function(a,b)
        if a.priority~=b.priority then return a.priority>b.priority end
        if a.unseen~=b.unseen then return a.unseen end
        if a.remaining~=b.remaining then return a.remaining<b.remaining end
        return a.serial<b.serial
    end)
    local selected=candidates[1]
    if self.active and(self.active.full or self.active.owner=='radio')then
        -- Keep a scheduled occurrence visible through its compact phase. Equal
        -- priority schedules wait their turn instead of hiding each other's
        -- warning repeatedly and starving every deadline.
        for _,c in ipairs(candidates)do if c.token==self.active.token and(c.full or c.owner=='radio')and(not selected or c.priority>=selected.priority)then selected=c;break end end
    end
    if not selected or not safe(state)then
        self.active=selected;self.bounds=nil;self.buttons={};self.armed=nil;self.mouseArmed=nil;self.skipArmed=false;self.intent=nil
        self.lastKeys=keys and keys.keys or {};return false
    end
    if not self.active or self.active.token~=selected.token then self.armed=nil;self.mouseArmed=nil;self.seenAt=nil;self.paintedToken=nil end
    self.active=selected
    local consumed=false
    if self.intent then
        local intent=self.intent;self.intent=nil
        local age=intent.at and core.elapsed(now,intent.at)
        if age and age<=250 and intent.token==selected.token and self.paintedToken==selected.token then
            if intent.kind=='accent'then
                if selected.accentOption and self.env.option then self.env.option(selected.owner,selected.token,intent.value)end
            else self.env.action(selected.owner,selected.token,intent.yes)end
            consumed=true
        end
    end
    if not keys or not keys.physical then self.armed=nil;self.skipArmed=false;self.lastKeys={};return consumed end
    local skip=self.env.skipShortcut();local warn=self.env.warnShortcut()
    local released=not keys.y and not keys.n and(not keys.keys or not keys.keys[skip.key])and(not keys.keys or not keys.keys[warn.key])
    local paintedAge=self.paintedAt and core.elapsed(now,self.paintedAt)
    local visibleAge=self.seenAt and core.elapsed(now,self.seenAt)
    local fresh=self.paintedToken==selected.token and paintedAge and paintedAge<=math.max(250,dt or 0)+50
    if released then self.skipArmed=true;if fresh and visibleAge and visibleAge>=120 then self.armed=selected.token end end
    if self.skipArmed and pressed(skip,keys,self.lastKeys)then
        self.skipArmed=false;self.armed=nil;self.env.skip(selected.owner=='radio' and selected.token or nil);consumed=true
    elseif self.armed==selected.token and fresh then
        local yes,no=false,false
        if selected.mode=='confirm' and not keys.mods then
            yes=keys.y and not keys.n and not self.lastKeys[0x59]
            no=keys.n and not keys.y and not self.lastKeys[0x4e]
        elseif selected.owner=='weapon'and selected.mode=='weapon' then yes=pressed(warn,keys,self.lastKeys)end
        if yes or no then self.env.action(selected.owner,selected.token,yes);self.armed=nil;consumed=true end
    end
    self.lastKeys=model.copy(keys.keys or {});return consumed
end
function Notices:view()return self.active and safe(self.state)and not self.failed and {visible=true,token=self.active.token}or {visible=false}end
function Notices:measure(im,fonts,avoid)
    self.bounds=nil;self.buttons={};local c=self.active
    if not self:view().visible then return nil end
    local io=im.GetIO();local width,height=io.DisplaySize.x,io.DisplaySize.y
    if not core.finite(width)or not core.finite(height)or width<320 or height<240 then return nil end
    local s=math.max(.85,math.min(1,height/720));local w=math.min(600*s,width-24);local pad=16*s;local wrap=w-2*pad
    local body=fonts.body or im.GetFont();local heading=fonts.heading or body
    local function extent(font,size,text)return font:CalcTextSizeA(size*s,100000,wrap,text)end
    local title=c.full and c.title or c.title..' · предстоящий доклад'
    local titleH=extent(heading,16,title).y;local statusH=extent(body,13,c.status).y
    local bodyH=c.full and extent(body,14,c.body).y or 0
    local hint=(self.state.demo and 'ДЕМО · без отправки · 'or '')..(c.hint or '')
    local hintH=extent(body,12,hint).y
    local key=model.shortcutName(c.shortcut)
    local keys=c.mode=='confirm'and 'Y — ДА · N — НЕТ' or c.owner=='radio'and(key..' — пропустить')or(key..' — предупредить')
    local cursor=self.state.cursorHint or 'Alt — курсор для кнопок'
    if c.shortcut.key==0 and c.mode~='confirm'then keys=cursor else keys=keys..' · '..cursor end
    local keyH=extent(body,12,keys).y
    local h=pad*2+titleH+statusH+hintH+keyH+bodyH+36*s+(c.full and 34 or 26)*s
    if c.accentOption then h=h+26*s end
    if h>height-24 then return nil end
    local r={x=(width-w)/2,y=height-h-24,w=w,h=h}
    for _=1,4 do
        local changed=false
        for _,other in ipairs(avoid or {})do if overlaps(r,other)then
            local y=other.y-r.h-12
            if y>=12 then r.y=y;changed=true
            else
                local left=other.x-r.w-12;local right=other.x+other.w+12
                if left>=12 then r.x=left;changed=true elseif right+r.w<=width-12 then r.x=right;changed=true
                else self.bounds=nil;return nil end
            end
        end end
        if not changed then break end
    end
    for _,other in ipairs(avoid or {})do if overlaps(r,other)then return nil end end
    self.bounds=r;self.measurement={s=s,pad=pad,wrap=wrap,body=body,heading=heading,title=title,titleH=titleH,bodyH=bodyH,statusH=statusH,
        hint=hint,hintH=hintH,keys=keys,keyH=keyH};return r
end
function Notices:overWidget(im)
    local io=im.GetIO();return self:view().visible and inside(self.bounds,io.MousePos.x,io.MousePos.y)or false
end
function Notices:draw(im,fonts,avoid)
    local r=self:measure(im,fonts,avoid);if not r then return end
    local c=self.active;local m=self.measurement;local s=m.s;local io=im.GetIO();local list=im.GetForegroundDrawList();local vec=im.ImVec2
    local function tint(a,b,d,alpha)return im.ColorConvertFloat4ToU32(im.ImVec4(a,b,d,alpha or 1))end
    local white,muted=tint(.98,.99,1),tint(.72,.84,.94)
    local function text(value,font,size,x,y,color)list:AddTextFontPtr(font,size*s,vec(x,y),color or white,value,nil,m.wrap)end
    list:AddRectFilled(vec(r.x,r.y),vec(r.x+r.w,r.y+r.h),tint(.035,.13,.22,.91),13*s)
    local x,y=r.x+m.pad,r.y+m.pad
    text(m.title,m.heading,16,x,y);y=y+m.titleH+6*s
    text(c.status,m.body,13,x,y,tint(.58,.83,1));y=y+m.statusH+8*s
    if c.full then
        list:AddRectFilled(vec(x-4*s,y-3*s),vec(x+m.wrap+4*s,y+m.bodyH+5*s),tint(.10,.24,.35,.9),7*s)
        text(c.body,m.body,14,x,y);y=y+m.bodyH+12*s
    end
    text(m.hint,m.body,12,x,y,muted);y=y+m.hintH+8*s
    local mouse=safe(self.state)and self.state.mouseAllowed
    local clicked=mouse and im.IsMouseClicked(0)
    local mouseDown=io.MouseDown and io.MouseDown[0]==true
    local visibleAge=self.seenAt and core.elapsed(self.now,self.seenAt)
    if mouse and not clicked and not mouseDown and visibleAge and visibleAge>=120 then self.mouseArmed=c.token end
    local mouseReady=mouse and self.mouseArmed==c.token and visibleAge and visibleAge>=120
    local function button(id,label,bx,bw,green)
        local b={x=bx,y=y,w=bw,h=34*s};self.buttons[id]=b
        local hover=inside(b,io.MousePos.x,io.MousePos.y)
        list:AddRectFilled(vec(b.x,b.y),vec(b.x+b.w,b.y+b.h),green and tint(.12,.43,.28,.98)or tint(.51,.16,.22,.98),8*s)
        local extent=m.heading:CalcTextSizeA(14*s,100000,bw-8*s,label)
        list:AddTextFontPtr(m.heading,14*s,vec(b.x+(bw-extent.x)/2,b.y+(b.h-extent.y)/2),white,label,nil,bw-8*s)
        return mouseReady and hover and clicked
    end
    local yes,no=false,false
    if c.accentOption then
        local box={x=x,y=y,w=16*s,h=16*s};local hit={x=x,y=y-2*s,w=m.wrap,h=22*s}
        self.buttons.accent=hit
        list:AddRectFilled(vec(box.x,box.y),vec(box.x+box.w,box.y+box.h),tint(.16,.30,.42),3*s)
        if c.noAccent then
            list:AddLine(vec(x+3*s,y+8*s),vec(x+7*s,y+12*s),white,2*s)
            list:AddLine(vec(x+7*s,y+12*s),vec(x+13*s,y+4*s),white,2*s)
        end
        text('Без акцента',m.body,13,x+24*s,y)
        if mouseReady and inside(hit,io.MousePos.x,io.MousePos.y)and clicked then
            self.intent={kind='accent',token=c.token,value=not c.noAccent,at=self.now}
        end
        y=y+26*s
    end
    if c.mode=='radio'or c.mode=='waiting'then no=button('no','Отменить',x,m.wrap,false)
    else
        local bw=(m.wrap-8*s)/2
        yes=button('yes',c.mode=='confirm'and 'Y   ДА' or c.yes,x,bw,true)
        no=button('no',c.mode=='confirm'and 'N   НЕТ' or c.no,x+bw+8*s,bw,false)
    end
    y=y+42*s;text(m.keys,m.body,12,x,y,muted)
    local remaining=math.max(0,c.remaining or 0);local total=c.duration or(c.owner=='radio'and self.env.lead()or self.env.weaponDuration())
    local progress=math.max(0,math.min(1,remaining/math.max(1,total)))
    list:AddRectFilled(vec(x,r.y+r.h-6*s),vec(x+m.wrap,r.y+r.h-3*s),tint(.16,.29,.40),2*s)
    list:AddRectFilled(vec(x,r.y+r.h-6*s),vec(x+m.wrap*progress,r.y+r.h-3*s),tint(.26,.65,.86),2*s)
    self.paintedToken=c.token;self.paintedAt=self.now;self.seenAt=self.seenAt or self.now
    self.env.shown(c.owner,c.token)
    if clicked then self.mouseArmed=nil end
    if yes or no then self.intent={token=c.token,yes=yes,at=self.now}end
end
M.safe=safe;M.overlaps=overlaps
return M

-- Original main-menu shell inspired by the user's visual reference.
-- Optional generated artwork is local to this menu and never owns input.
local core = require 'pa26_core'
local bit = require 'bit'
local M = {}
local Menu = {}
Menu.__index = Menu
M.sections = {
    {key='home',label='Главная',short='Главная'},
    {key='binds',label='Библиотека биндов',short='Бинды'},
    {key='addons',label='Помощники службы',short='Помощники'},
    {key='partners',label='Напарники',short='Напарники'},
    {key='hints',label='Памятки и справка',short='Памятки'},
    {key='knowledge',label='База знаний',short='База знаний'},
    {key='stats',label='Журнал и статистика',short='Журнал'},
    {key='settings',label='Настройки',short='Настройки'},
}

M.credit = 'by VIBAG ( Victor Auditore )'
M.contacts={'Telegram: victor_bg','Discord: victor_bag','GitHub: VIBAG-bg'}
M.contactText=table.concat(M.contacts,' · ')

function M.new()
    return setmetatable({section = 'home', guide = 'commands', tool = 'patrol', assets = {}, windows = {}}, Menu)
end
function Menu:navigate(section,guide,tool)
    local title=section;for _,row in ipairs(M.sections)do if row.key==section then title=row.label end end
    local function apply()self.section=section;self.referenceOpen=guide~=nil;if guide then self.guide=guide end;if tool then self.tool=tool end end
    if self.guardNavigation and section~=self.section then return self.guardNavigation(apply,'открыть раздел «'..title..'»')end
    apply();return true
end

local function clamp(value,low,high) return math.max(low,math.min(high,value)) end
function M.windowBounds(width,height,key,percent)
    if not core.finite(width) or not core.finite(height) or width<220 or height<220 then return nil end
    percent=percent or 70
    local defaults=({main={width*percent/100,height*percent/100,760,480},wanted={width*.7,math.max(720,height*.86),420,400},quick={780,700,360,320},tips={960,760,420,360},assist={680,560,420,380}})[key]
    if not defaults then return nil end
    local maxW,maxH=width-32,height-32
    local minW,minH=math.min(defaults[3],maxW),math.min(defaults[4],maxH)
    return {width=clamp(defaults[1],minW,maxW),height=clamp(defaults[2],minH,maxH),
        minW=minW,minH=minH,maxW=maxW,maxH=maxH}
end
function Menu:prepareWindow(imgui,key)
    local io=imgui.GetIO(); local bounds=M.windowBounds(io.DisplaySize.x,io.DisplaySize.y,key)
    if not bounds then return false end
    local config=self.windowConfig and self.windowConfig()
    local saved=self.windows[key];local restored=false
    if not saved and config and config.remember then saved=config.windows[key];self.windows[key]=saved;restored=saved~=nil end
    self.pendingWindows=self.pendingWindows or{};self.resetWindows=self.resetWindows or{}
    local pending=self.pendingWindows[key];self.pendingWindows[key]=nil
    local reset=self.resetWindows[key];self.resetWindows[key]=nil
    local desired=pending or saved;if reset then desired=nil end
    local rect=M.windowRect(io.DisplaySize.x,io.DisplaySize.y,key,desired,config and config.initial_percent)
    imgui.SetNextWindowSizeConstraints(imgui.ImVec2(bounds.minW,bounds.minH),imgui.ImVec2(bounds.maxW,bounds.maxH))
    local force=restored or not saved or pending or reset or(saved.displayW~=io.DisplaySize.x or saved.displayH~=io.DisplaySize.y)
    local condition=force and imgui.Cond.Always or imgui.Cond.FirstUseEver
    -- Position and size must be fixed BEFORE Begin calculates native clip rects.
    imgui.SetNextWindowPos(imgui.ImVec2(rect.x,rect.y),condition)
    imgui.SetNextWindowSize(imgui.ImVec2(rect.width,rect.height),condition)
    return true
end
function M.windowRect(width,height,key,saved,percent)
    local b=M.windowBounds(width,height,key,percent);if not b then return nil end
    saved=saved or{}
    if core.finite(saved.displayW)and core.finite(saved.displayH)and saved.displayW>=220 and saved.displayH>=220 then
        local copy={};for k,v in pairs(saved)do copy[k]=v end
        for _,k in ipairs({'width','x'})do if core.finite(copy[k])then copy[k]=copy[k]*width/saved.displayW end end
        for _,k in ipairs({'height','y'})do if core.finite(copy[k])then copy[k]=copy[k]*height/saved.displayH end end
        saved=copy
    end
    local w=clamp(core.finite(saved.width)and saved.width or b.width,b.minW,b.maxW)
    local h=clamp(core.finite(saved.height)and saved.height or b.height,b.minH,b.maxH)
    return {width=w,height=h,x=clamp(core.finite(saved.x)and saved.x or(width-w)/2,16,width-w-16),
        y=clamp(core.finite(saved.y)and saved.y or(height-h)/2,16,height-h-16)}
end
function Menu:resetWindowPositions()
    self.pendingWindows={};self.resetWindows={main=true,quick=true,tips=true,assist=true,wanted=true}
end
function Menu:nativeEdges(imgui)
    local io=imgui.GetIO()
    return io.ConfigWindowsResizeFromEdges==true and bit.band(tonumber(io.BackendFlags),2)~=0
end
function Menu:resizeWindow(imgui,ui,key)
    local io=imgui.GetIO(); local bounds=M.windowBounds(io.DisplaySize.x,io.DisplaySize.y,key)
    if not bounds then return end
    local size,pos=imgui.GetWindowSize(),imgui.GetWindowPos()
    local width,height=clamp(size.x,bounds.minW,bounds.maxW),clamp(size.y,bounds.minH,bounds.maxH)
    local x,y=pos.x,pos.y
    assert(core.finite(size.x)and core.finite(size.y)and core.finite(x)and core.finite(y),'Недоступны координаты окна PA.')
    self.windows[key]={width=size.x,height=size.y,x=x,y=y,displayW=io.DisplaySize.x,displayH=io.DisplaySize.y}
    -- All edge mutations are queued for the next Begin, including native backends.
    -- SetWindowPos/Size after Begin leaves stale clip rectangles during dragging.
    do
        local cursor=imgui.GetCursorScreenPos(); local e=7
        local handles={{'left',0,e,e,height-2*e,-1,0},{'right',width-e,e,e,height-2*e,1,0},
            {'top',e,0,width-2*e,e,0,-1},{'bottom',e,height-e,width-2*e,e,0,1},
            {'tl',0,0,e,e,-1,-1},{'tr',width-e,0,e,e,1,-1},
            {'bl',0,height-e,e,e,-1,1},{'br',width-e,height-e,e,e,1,1}}
        for _,h in ipairs(handles) do
            imgui.SetCursorScreenPos(imgui.ImVec2(x+h[2],y+h[3]))
            imgui.InvisibleButton('##resize-'..key..'-'..h[1],imgui.ImVec2(h[4],h[5]))
            local active=imgui.IsItemActive(); local hovered=imgui.IsItemHovered()
            if active or hovered then
                local diagonal=h[6]~=0 and h[7]~=0
                local shape=diagonal and (h[6]==h[7] and imgui.MouseCursor.ResizeNWSE or imgui.MouseCursor.ResizeNESW)
                    or (h[6]~=0 and imgui.MouseCursor.ResizeEW or imgui.MouseCursor.ResizeNS)
                imgui.SetMouseCursor(shape)
                local a,b=imgui.GetItemRectMin(),imgui.GetItemRectMax()
                imgui.GetWindowDrawList():AddRectFilled(a,b,imgui.ColorConvertFloat4ToU32(imgui.ImVec4(.23,.60,.85,.5)),3)
            end
            if active and core.finite(io.MouseDelta.x) and core.finite(io.MouseDelta.y) then
                local newW=clamp(width+h[6]*io.MouseDelta.x,bounds.minW,bounds.maxW)
                local newH=clamp(height+h[7]*io.MouseDelta.y,bounds.minH,bounds.maxH)
                if h[6]<0 then x=x+width-newW end
                if h[7]<0 then y=y+height-newH end
                width,height=newW,newH
            end
        end
        imgui.SetCursorScreenPos(cursor)
    end
    x=clamp(x,16,io.DisplaySize.x-width-16); y=clamp(y,16,io.DisplaySize.y-height-16)
    if width~=size.x or height~=size.y or x~=pos.x or y~=pos.y then
        self.pendingWindows=self.pendingWindows or{}
        self.pendingWindows[key]={width=width,height=height,x=x,y=y}
    end
    if self.geometryChanged and not(io.MouseDown and(io.MouseDown[0]or io.MouseDown[1]))and not self.pendingWindows[key]then self.geometryChanged(key,self.windows[key])end
    if key~='main'then self:dragWindow(imgui,ui,key,8,1,math.max(1,width-48),26)end
    local moved=M.rightDragRect(imgui,self,key)
    if moved then self.pendingWindows=self.pendingWindows or{};self.pendingWindows[key]=moved end
end
-- Apply returned coordinates BEFORE the next Begin, so native clip rectangles
-- move with the window. The right button never becomes a left-button click.
function M.rightDragRect(im,owner,key)
    local io=im.GetIO();local down=io.MouseDown and io.MouseDown[1]==true
    if not down then owner.rightDrag=nil;return end
    local pos,size=im.GetWindowPos(),im.GetWindowSize();local mouse=io.MousePos
    if not mouse or not core.finite(mouse.x)or not core.finite(mouse.y)or
        not core.finite(size.x)or not core.finite(size.y)or not core.finite(pos.x)or not core.finite(pos.y)then owner.rightDrag=nil;return end
    local flags=im.HoveredFlags and im.HoveredFlags.ChildWindows or 0
    if not owner.rightDrag and type(im.IsMouseClicked)=='function'and im.IsMouseClicked(1)and
        not(io.MouseDown[0]==true)and type(im.IsWindowHovered)=='function'and im.IsWindowHovered(flags)then
        owner.rightDrag={key=key,dx=mouse.x-pos.x,dy=mouse.y-pos.y}
    end
    local drag=owner.rightDrag;if not drag or drag.key~=key then return end
    local x=clamp(mouse.x-drag.dx,16,math.max(16,io.DisplaySize.x-size.x-16))
    local y=clamp(mouse.y-drag.dy,16,math.max(16,io.DisplaySize.y-size.y-16))
    return {x=x,y=y,width=size.x,height=size.y}
end
function Menu:dragWindow(imgui,ui,key,x,y,width,height)
    local cursor=imgui.GetCursorScreenPos();local pos,size=imgui.GetWindowPos(),imgui.GetWindowSize()
    imgui.SetCursorScreenPos(imgui.ImVec2(pos.x+x,pos.y+y))
    imgui.InvisibleButton('##move-'..key,imgui.ImVec2(width,height))
    local io=imgui.GetIO()
    if imgui.IsItemActive()and core.finite(io.MouseDelta.x)and core.finite(io.MouseDelta.y)then
        self.pendingWindows=self.pendingWindows or{}
        self.pendingWindows[key]=M.windowRect(io.DisplaySize.x,io.DisplaySize.y,key,
            {x=pos.x+io.MouseDelta.x,y=pos.y+io.MouseDelta.y,width=size.x,height=size.y})
    end
    imgui.SetCursorScreenPos(cursor)
end

-- Cache measured UTF-8 lines; every line is centred within the same clickable area.
local labelCache,labelOrder={},{}
function M.labelLayout(font,fontSize,width,text)
    width=math.max(1,width)
    local key=tostring(font)..'|'..fontSize..'|'..width..'|'..text
    if labelCache[key] then return labelCache[key] end
    local lines={}
    local function measure(value) return font:CalcTextSizeA(fontSize,100000,0,value).x end
    local function add(value) lines[#lines+1]={text=value,width=measure(value)} end
    for paragraph in (text:gsub('\r','')..'\n'):gmatch('(.-)\n') do
        if measure(paragraph)<=width then add(paragraph)
        else
            local line=''
            for word in paragraph:gmatch('%S+') do
                local joined=line=='' and word or line..' '..word
                if measure(joined)<=width then line=joined
                else
                    if line~='' then add(line);line='' end
                    if measure(word)<=width then line=word
                    else
                        for glyph in word:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
                            if line~='' and measure(line..glyph)>width then add(line);line='' end
                            line=line..glyph
                        end
                    end
                end
            end
            if line~='' then add(line) end
        end
    end
    local result={lines=lines,height=#lines*fontSize}
    if #labelOrder>=256 then labelCache[table.remove(labelOrder,1)]=nil end
    labelOrder[#labelOrder+1]=key;labelCache[key]=result
    return result
end
function M.drawCenteredLabel(imgui,font,fontSize,first,width,height,layout)
    local top=first.y+(height-layout.height)/2
    local tint=imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1,1,1,1))
    for n,line in ipairs(layout.lines) do
        imgui.GetWindowDrawList():AddTextFontPtr(font,fontSize,
            imgui.ImVec2(first.x+(width-line.width)/2,top+(n-1)*fontSize),tint,line.text,nil,0)
    end
end
function M.tooltip(imgui,ui,value)
    if not imgui.IsItemHovered() then return end
    local display=imgui.GetIO().DisplaySize
    local width=math.max(32,math.min(388,display.x-32))
    imgui.SetNextWindowSizeConstraints(imgui.ImVec2(width,1),imgui.ImVec2(width,math.max(1,display.y-32)))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding,imgui.ImVec2(14,12));ui.push(function()imgui.PopStyleVar(1)end)
    imgui.BeginTooltip();ui.push(function()imgui.EndTooltip()end)
    imgui.PushTextWrapPos(imgui.GetCursorPosX()+width-28);ui.push(function()imgui.PopTextWrapPos()end)
    imgui.TextUnformatted(value)
    ui.finish();ui.finish();ui.finish()
end
M.searchTitles={['Поиск']='ПОИСК: бинды',['Поиск памяток']='ПОИСК: памятки',
    ['Найти сценарий']='ПОИСК: сценарий',['Найти переменную']='ПОИСК: переменная',
    ['Поиск в журнале']='ПОИСК: журнал',['Поиск в списке']='ПОИСК: в списке',
    ['Поиск: слово, номер статьи или команда']='ПОИСК: слово, номер статьи или команда'}
function M.searchHeading(im,ui,label,font)
    local title=M.searchTitles[label];if not title then return false end
    if font then im.PushFont(font);ui.push(function()im.PopFont()end)end
    ui.text(title)
    if font then ui.finish()end
    return true
end

-- Full text, generous padding, then answers. Expand before wrapping further.
-- Exceptionally large previews use pages at screen limits, never a scrollbar.
function M.confirmationLayout(im,spec)
    local display=im.GetIO().DisplaySize
    local bodyFont=im.GetFont();local bodySize=im.GetFontSize()
    local titleFont=spec.titleFont or bodyFont;local titleSize=tonumber(titleFont.FontSize)
    local buttonFont=spec.buttonFont or bodyFont;local buttonSize=tonumber(buttonFont.FontSize)
    local titleWidth=titleFont:CalcTextSizeA(titleSize,100000,0,spec.title or '').x
    local maxWidth=math.max(1,math.min(960,display.x-32));local maxHeight=math.max(1,display.y-32)
    local width=math.min(math.max(400,math.min(600,titleWidth+80)),maxWidth)
    local title,body,footer,height,inner
    repeat
        inner=math.max(1,width-56)
        title=M.labelLayout(titleFont,titleSize,inner,spec.title or '')
        body=spec.extraHeight or 0
        for _,line in ipairs(spec.lines or{})do if line then body=body+M.labelLayout(bodyFont,bodySize,inner,line).height+10 end end
        body=math.max(1,body-10)
        local cols=spec.columns or 2;local buttonWidth=math.max(1,(inner-(cols-1)*10)/cols)
        footer=42
        for _,label in ipairs(spec.buttons or{})do footer=math.max(footer,M.labelLayout(buttonFont,buttonSize,math.max(1,buttonWidth-28),label).height+16)end
        local rows=math.max(1,math.ceil(#(spec.buttons or{})/cols))
        footer=footer*rows+(rows-1)*10+(spec.extraFooter or 0)
        if spec.checkboxLabel then
            footer=footer+math.max(bodySize+8,M.labelLayout(bodyFont,bodySize,math.max(1,inner-32),spec.checkboxLabel).height)+10
        end
        height=48+title.height+10+body+20+footer
        if height<=maxHeight or width>=maxWidth then break end
        width=math.min(maxWidth,width+80)
    until false
    local pages
    if height>maxHeight then
        local rows={}
        for _,line in ipairs(spec.lines or{})do if line then
            if #rows>0 then rows[#rows+1]='' end
            for _,row in ipairs(M.labelLayout(bodyFont,bodySize,inner,line).lines)do rows[#rows+1]=row.text end
        end end
        local capacity=math.max(1,math.floor((maxHeight-48-title.height-10-20-footer-50-(spec.extraHeight or 0))/bodySize))
        if #rows==0 then rows[1]=''end
        pages={};for first=1,#rows,capacity do
            local text={};for n=first,math.min(first+capacity-1,#rows)do text[#text+1]=rows[n]end
            pages[#pages+1]=table.concat(text,'\n')
        end
        local page=math.max(1,math.min(#pages,spec.pageState and spec.pageState.page or 1))
        body=M.labelLayout(bodyFont,bodySize,inner,pages[page]).height+(spec.extraHeight or 0)
        height=math.min(maxHeight,48+title.height+10+body+20+footer+50)
    end
    return {width=width,height=height,body=body,footer=footer,title=title,pages=pages,
        titleFont=titleFont,titleSize=titleSize,overflow=pages~=nil}
end
function M.confirmationBody(im,ui,layout,spec,extra)
    im.PushFont(layout.titleFont);ui.push(function()im.PopFont()end)
    ui.text(spec.title);ui.finish()
    if extra and not spec.extraAfterLines then extra()end
    if layout.pages then
        local state=spec.pageState or{};local count=#layout.pages
        state.page=math.max(1,math.min(count,state.page or 1));ui.text(layout.pages[state.page])
        local width=math.max(1,(im.GetContentRegionAvail().x-20)/3)
        if im.Button('Назад##confirmation-page',im.ImVec2(width,30))then state.page=math.max(1,state.page-1)end
        im.SameLine(0,10);im.Button(state.page..' / '..count..'##confirmation-pages',im.ImVec2(width,30))
        im.SameLine(0,10)
        if im.Button('Далее##confirmation-page',im.ImVec2(width,30))then state.page=math.min(count,state.page+1)end
    else for _,line in ipairs(spec.lines or{})do if line then ui.text(line)end end end
    if extra and spec.extraAfterLines then extra()end
    im.Dummy(im.ImVec2(0,0))
end

-- Native Button clips single-line text. Draw the complete label ourselves.
function M.fittedButton(imgui,ui,label,size,font)
    if font then imgui.PushFont(font); ui.push(function() imgui.PopFont() end) end
    local current=imgui.GetFont(); local fontSize=imgui.GetFontSize()
    local visible=label:match('^(.-)##') or label
    -- Resolve ImGui's automatic/fill size before measuring or centering text.
    local available=(size.x<0 or size.y<0)and imgui.GetContentRegionAvail()
    local width=size.x
    if width<0 then width=math.max(4,available.x+width)
    elseif width==0 then width=current:CalcTextSizeA(fontSize,100000,0,visible).x+28 end
    local requestedHeight=size.y<0 and math.max(4,available.y+size.y)or size.y
    local wrap=math.max(1,width-28)
    local layout=M.labelLayout(current,fontSize,wrap,visible)
    local height=math.max(requestedHeight,layout.height+16)
    imgui.PushStyleColor(imgui.Col.Text,imgui.ImVec4(1,1,1,0)); ui.push(function() imgui.PopStyleColor(1) end)
    local clicked=imgui.Button(label,imgui.ImVec2(width,height)); ui.finish()
    local first=imgui.GetItemRectMin()
    M.drawCenteredLabel(imgui,current,fontSize,first,width,height,layout)
    if font then ui.finish() end
    return clicked
end

-- Small sets are visible choices. Large catalogues keep an explicit, searchable
-- picker. IDs/values are independent of short captions and remain unchanged.
function M.choiceLayout(font,size,width,choices,options)
    options=options or {};width=math.max(1,width)
    local n=#choices
    if n==0 or options.list or (n>6 and not options.buttons) then return nil end
    local maximum=math.min(n,math.max(1,math.floor((width+8)/100)))
    -- Prefer balanced rows (3+3 rather than 5+1); keep all options equally sized.
    for wantedRows=1,(options.buttons and 4 or 2) do
        local columns=math.ceil(n/wantedRows)
        if columns<=maximum then
        local cell=math.max(1,(width-8*(columns-1))/columns)
        local rows=math.ceil(n/columns);local heights={};local fits=true
        for i,v in ipairs(choices)do
            local caption=tostring(v[3] or v[2])
            local lines=M.labelLayout(font,size,math.max(1,cell-28),caption)
            if #lines.lines>2 then fits=false end
            local row=math.ceil(i/columns)
            heights[row]=math.max(heights[row]or 36,lines.height+16)
        end
        if fits and(rows<=(options.buttons and 4 or 2))then
            return {columns=columns,width=cell,heights=heights,rows=rows}
        end
        end
    end
end

function M.choiceControl(im,ui,id,label,value,choices,state,options)
    options=options or {};state=state or{}
    if label~=''then ui.text(label)end
    local current
    for _,v in ipairs(choices)do if v[1]==value then current=v;break end end
    if #choices==0 then ui.text('Нет доступных вариантов.');return value,false end
    local font=options.font or im.GetFont();local size=tonumber(font.FontSize)
    local layout=M.choiceLayout(font,size,im.GetContentRegionAvail().x,choices,options)
    local out=value
    local function clean(s)return tostring(s):gsub('##','# #')end
    if layout then
        for i,v in ipairs(choices)do
            if (i-1)%layout.columns~=0 then im.SameLine(0,8)end
            local selected=v[1]==value
            im.PushStyleColor(im.Col.Button,im.ImVec4(selected and .08 or .10,selected and .45 or .23,selected and .63 or .34,selected and .98 or .88));ui.push(function()im.PopStyleColor(1)end)
            if M.fittedButton(im,ui,clean(v[3]or v[2])..id..tostring(v[1]),
                im.ImVec2(layout.width,layout.heights[math.ceil(i/layout.columns)]),font)then out=v[1]end
            ui.finish()
        end
        -- Use the newly chosen value immediately; its page is drawn this frame.
        for _,v in ipairs(choices)do if v[1]==out then current=v;break end end
        if current and(options.description or current[3]and current[3]~=current[2])then
            im.Dummy(im.ImVec2(0,4))
            local heading=options.headingFont or font
            im.PushFont(heading);ui.push(function()im.PopFont()end)
            ui.text(tostring(current[2]));ui.finish()
            if current[4]then ui.text(current[4])end
        end
    else
        im.PushItemWidth(-1);ui.push(function()im.PopItemWidth()end)
        local open=im.BeginCombo(id,current and clean(current[2])or'Выберите вариант')
        if open then
            ui.push(function()im.EndCombo()end)
            for _,v in ipairs(choices)do
                if im.Selectable(clean(v[2])..id..tostring(v[1]),v[1]==value)then out=v[1]end
            end
            ui.finish()
        end
        ui.finish()
    end
    return out,out~=value
end

function Menu:configureAssets(directory, logger)
    self.assetDirectory, self.assetLogger = directory, logger
    self.assets = {
        banner = {file = 'banner-bmw-lamborghini.png', width = 1983, height = 793},
        sidebar = {file = 'sidebar-police-assistant.png', width = 1254, height = 1254},
    }
end

local function assetNote(self, asset, reason)
    if self.assetLogger then
        pcall(self.assetLogger, 'Изображение ' .. asset.file .. ' недоступно: ' .. tostring(reason))
    end
end

local function pngSize(path)
    local opened, file = pcall(io.open, path, 'rb')
    if not opened or not file then return nil, 'файл не найден или не читается' end
    local ok, header, length = pcall(function() return file:read(24), file:seek('end') end)
    pcall(file.close, file)
    if not ok or type(header) ~= 'string' or #header ~= 24 or
        header:sub(1, 8) ~= '\137PNG\r\n\26\n' or header:sub(13, 16) ~= 'IHDR' then
        return nil, 'нужен корректный PNG'
    end
    if type(length) ~= 'number' or length > 16 * 1024 * 1024 then return nil, 'слишком большой файл' end
    local function numberAt(offset)
        local a, b, c, d = header:byte(offset, offset + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    local width, height = numberAt(17), numberAt(21)
    if width < 1 or height < 1 or width > 4096 or height > 4096 or width * height > 8388608 then
        return nil, 'размер изображения вне допустимых границ'
    end
    return {width = width, height = height}
end

-- Called only from drawing, after mimgui has selected its initialized renderer.
-- A missing/bad image is attempted once per device lifecycle, never every frame.
function Menu:loadAsset(imgui, key)
    local asset = self.assets[key]
    if not asset or not self.assetDirectory then return nil end
    if asset.renderFailed then return nil end
    if asset.attempted then return asset.texture end
    asset.attempted = true
    local path = self.assetDirectory .. '\\' .. asset.file
    local size, reason = pngSize(path)
    if not size then assetNote(self, asset, reason); return nil end
    asset.width, asset.height = size.width, size.height
    local ok, texture = pcall(imgui.CreateTextureFromFile, path)
    if not ok or texture == nil then
        assetNote(self, asset, ok and 'не удалось создать текстуру' or texture)
        return nil
    end
    asset.texture = texture
    return texture
end

function Menu:assetHeight(key, width)
    local asset = self.assets[key]
    return asset and width * asset.height / asset.width or 142
end

function Menu:drawAsset(imgui, key, width, maxHeight)
    local texture = self:loadAsset(imgui, key)
    if texture == nil or width <= 0 or maxHeight <= 0 then return false end
    local asset = self.assets[key]
    local scale = math.min(width / asset.width, maxHeight / asset.height)
    local drawWidth, drawHeight = asset.width * scale, asset.height * scale
    local cursor = imgui.GetCursorPosX()
    imgui.SetCursorPosX(cursor + (width - drawWidth) / 2)
    local ok, reason = pcall(function()
        local position = imgui.GetCursorScreenPos()
        local corner = imgui.ImVec2(position.x + drawWidth, position.y + drawHeight)
        local draw = imgui.GetWindowDrawList()
        local rounding = math.min(9, drawWidth / 8, drawHeight / 8)
        if type(draw.AddImageRounded) == 'function' then
            draw:AddImageRounded(texture, position, corner, imgui.ImVec2(0, 0), imgui.ImVec2(1, 1),
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 1)), rounding)
            local border = imgui.ImVec4(.19, .37, .53, .8)
            draw:AddRect(position, corner,
                imgui.ColorConvertFloat4ToU32(border), rounding)
            imgui.Dummy(imgui.ImVec2(drawWidth, drawHeight))
        else
            imgui.Image(texture, imgui.ImVec2(drawWidth, drawHeight))
        end
    end)
    imgui.SetCursorPosX(cursor)
    if not ok then
        -- AddImageRounded may already have queued this pointer for EndFrame.
        -- Keep ownership until device loss/shutdown instead of freeing mid-frame.
        asset.renderFailed = true
        assetNote(self, asset, reason)
    end
    return ok
end

function Menu:releaseAssets(imgui, retry)
    for _, asset in pairs(self.assets) do
        local texture = asset.texture
        asset.texture = nil -- prevent a second release, including during cleanup
        if texture ~= nil then pcall(imgui.ReleaseTexture, texture) end
        asset.attempted = not retry
        if retry then asset.renderFailed = false end
    end
end

local function color(imgui, r, g, b, a) return imgui.ImVec4(r, g, b, a or 1) end

function Menu:pushTheme(imgui, ui)
    local colors = {
        {imgui.Col.WindowBg, .045, .075, .115, self.opacity or .86},
        {imgui.Col.ChildBg, .070, .112, .173, .35},
        {imgui.Col.Text, 1, 1, 1, 1},
        {imgui.Col.TextDisabled, .73, .81, .88, 1},
        {imgui.Col.Border, .24, .38, .50, .42},
        {imgui.Col.FrameBg, .09, .15, .22, .85},
        {imgui.Col.FrameBgHovered, .12, .23, .34, 1},
        {imgui.Col.FrameBgActive, .13, .29, .44, 1},
        {imgui.Col.Button, .13, .31, .47, .82},
        {imgui.Col.ButtonHovered, .20, .43, .62, .93},
        {imgui.Col.ButtonActive, .13, .40, .59, .95},
        {imgui.Col.Header, .11, .35, .56, 1},
        {imgui.Col.HeaderHovered, .13, .43, .66, 1},
        {imgui.Col.HeaderActive, .10, .40, .64, 1},
        {imgui.Col.CheckMark, .23, .76, .92, 1},
    }
    if imgui.Col.TitleBg then colors[#colors+1]={imgui.Col.TitleBg,.07,.19,.30,1} end
    if imgui.Col.TitleBgActive then colors[#colors+1]={imgui.Col.TitleBgActive,.09,.29,.46,1} end
    for _, c in ipairs(colors) do
        imgui.PushStyleColor(c[1], color(imgui, c[2], c[3], c[4], c[5]))
        ui.push(function() imgui.PopStyleColor(1) end)
    end
    for _, entry in ipairs({{imgui.StyleVar.WindowRounding, 18}, {imgui.StyleVar.FrameRounding, 10},
        {imgui.StyleVar.ChildRounding, 14}, {imgui.StyleVar.WindowBorderSize, 1}}) do
        imgui.PushStyleVarFloat(entry[1], entry[2])
        ui.push(function() imgui.PopStyleVar(1) end)
    end
    for _, entry in ipairs({{imgui.StyleVar.WindowPadding, 0, 0},
        {imgui.StyleVar.FramePadding, 14, self.compact and 6 or 10}, {imgui.StyleVar.ItemSpacing, 12, self.compact and 6 or 10},
        {imgui.StyleVar.ButtonTextAlign, .5, .5}}) do
        imgui.PushStyleVarVec2(entry[1], imgui.ImVec2(entry[2], entry[3]))
        ui.push(function() imgui.PopStyleVar(1) end)
    end
end

local function child(imgui, ui, name, width, height, body, transparent, flags, padding)
    padding = padding == nil and 16 or padding
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(padding, padding))
    ui.push(function() imgui.PopStyleVar(1) end)
    if transparent then
        imgui.PushStyleColor(imgui.Col.ChildBg, color(imgui, 0, 0, 0, 0))
        ui.push(function() imgui.PopStyleColor(1) end)
    end
    -- Dear ImGui 1.72 otherwise ignores padding for a child without a border.
    local visible = imgui.BeginChild(name, imgui.ImVec2(width, height), not transparent,
        (flags or 0) + imgui.WindowFlags.AlwaysUseWindowPadding)
    ui.push(function() imgui.EndChild() end)
    if visible then body() end
    ui.finish()
    if transparent then ui.finish() end
    ui.finish()
end

-- Floating window chrome must not contribute to a scrolling body's extent.
function M.scrollBody(imgui,ui,name,body)
    child(imgui,ui,name,0,0,body,true,0,0)
end

local function withFont(imgui, ui, font, body)
    if font ~= nil then imgui.PushFont(font); ui.push(function() imgui.PopFont() end) end
    body()
    if font ~= nil then ui.finish() end
end

local function muted(imgui, ui, value)
    imgui.PushStyleColor(imgui.Col.Text, color(imgui, .74, .82, .90, 1))
    ui.push(function() imgui.PopStyleColor(1) end)
    ui.text(value)
    ui.finish()
end

local function heading(imgui, ui, value, font)
    withFont(imgui, ui, font, function() ui.text(value) end)
end

local function button(imgui, ui, label, size, font)
    return M.fittedButton(imgui,ui,label,size,font)
end

function M.referenceSwitchLayout(layout,font,titleWidth)
    local size=tonumber(font.FontSize)
    local textWidth=math.max(font:CalcTextSizeA(size,100000,0,'Памятки').x,
        font:CalcTextSizeA(size,100000,0,'Подсказки').x)
    local width=math.min(layout.w,math.max(236,(textWidth+28)*2+8))
    local height=math.max(32,size+16)+6
    local x=layout.x+layout.w-60-width
    local inline=x>=layout.x+20+titleWidth+20
    if not inline then x=layout.x+layout.w-width end
    return {x=x,y=inline and layout.headerY+(layout.headerH-height)/2 or layout.bodyY,
        w=width,h=height,bodyOffset=inline and 0 or height+8}
end

function Menu:referenceSwitch(imgui,ui,box,font)
    local vec=imgui.ImVec2
    imgui.SetCursorPos(vec(box.x,box.y))
    local origin=imgui.GetCursorScreenPos()
    imgui.GetWindowDrawList():AddRectFilled(origin,vec(origin.x+box.w,origin.y+box.h),
        imgui.ColorConvertFloat4ToU32(color(imgui,.04,.12,.19,.90)),box.h/2)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding,(box.h-6)/2)
    ui.push(function()imgui.PopStyleVar(1)end)
    local width=(box.w-8)/2
    for index,entry in ipairs({{'Памятки',false,'notes'},{'Подсказки',true,'guide'}})do
        local active=(self.referenceOpen==true)==entry[2]
        imgui.PushStyleColor(imgui.Col.Button,active and color(imgui,.09,.43,.62,.96)or color(imgui,0,0,0,0))
        ui.push(function()imgui.PopStyleColor(1)end)
        imgui.SetCursorPos(vec(box.x+3+(index-1)*(width+2),box.y+3))
        if button(imgui,ui,entry[1]..'##reference-'..entry[3],vec(width,box.h-6),font)then
            self.referenceOpen=entry[2]
        end
        ui.finish()
    end
    ui.finish()
end

-- A real vector icon; independent of fonts and multiplication-letter glyphs.
function M.closeButton(imgui,ui,id,size)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding,12)
    ui.push(function()imgui.PopStyleVar(1)end)
    local clicked=imgui.Button('##'..id,imgui.ImVec2(size,size));ui.finish()
    local a,b=imgui.GetItemRectMin(),imgui.GetItemRectMax()
    local x,y=(a.x+b.x)/2,(a.y+b.y)/2
    local radius=size*.155
    local draw=imgui.GetWindowDrawList()
    local tint=imgui.ColorConvertFloat4ToU32(imgui.ImVec4(.86,.94,1,1))
    draw:AddLine(imgui.ImVec2(x-radius,y-radius),imgui.ImVec2(x+radius,y+radius),tint,2)
    draw:AddLine(imgui.ImVec2(x+radius,y-radius),imgui.ImVec2(x-radius,y+radius),tint,2)
    return clicked
end

function M.starButton(im,ui,id,selected,size)
    size=size or 38
    im.PushStyleVarFloat(im.StyleVar.FrameRounding,11);ui.push(function()im.PopStyleVar(1)end)
    im.PushStyleColor(im.Col.Button,selected and im.ImVec4(.32,.25,.09,.86)or im.ImVec4(.09,.21,.31,.84));ui.push(function()im.PopStyleColor(1)end)
    local clicked=im.Button('##'..id,im.ImVec2(size,size));ui.finish();ui.finish()
    local a,b=im.GetItemRectMin(),im.GetItemRectMax();local x,y=(a.x+b.x)/2,(a.y+b.y)/2
    local points={};local radius=size*.28;local draw=im.GetWindowDrawList()
    local tint=im.ColorConvertFloat4ToU32(selected and im.ImVec4(1,.79,.19,1)or im.ImVec4(.78,.73,.52,.95))
    for n=0,9 do local angle=-math.pi/2+n*math.pi/5;local r=n%2==0 and radius or radius*.46
        points[n+1]=im.ImVec2(x+math.cos(angle)*r,y+math.sin(angle)*r)
    end
    for n=1,10 do local first,last=points[n],points[n%10+1]
        if selected then draw:AddTriangleFilled(im.ImVec2(x,y),first,last,tint)
        else draw:AddLine(first,last,tint,1.6)end
    end
    return clicked
end
local function selectorRow(imgui, items, active, prefix, onSelect,ui)
    local available, used = imgui.GetContentRegionAvail().x, 0
    for _, entry in ipairs(items) do
        local label = entry[2]
        local width = math.min(available, imgui.CalcTextSize(label).x + 32)
        if used > 0 and used + 12 + width <= available then
            imgui.SameLine(0, 12)
            used = used + 12
        else used = 0 end
        local selected=active==entry[1]
        if selected then
            imgui.PushStyleColor(imgui.Col.Button,imgui.ImVec4(.15,.43,.63,1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered,imgui.ImVec4(.18,.50,.70,1))
            imgui.PushStyleColor(imgui.Col.ButtonActive,imgui.ImVec4(.12,.37,.56,1))
        end
        local clicked
        if ui then clicked=M.fittedButton(imgui,ui,label..'##'..prefix..entry[1],imgui.ImVec2(width,44))
        else clicked=imgui.Button(label..'##'..prefix..entry[1],imgui.ImVec2(width,44))end
        if clicked then onSelect(entry[1])end
        if selected then imgui.PopStyleColor(3)end
        used = used + width
    end
end

local function rows(imgui, ui, data)
    imgui.Columns(2, 'rows##pa26', false)
    ui.push(function() imgui.Columns(1) end)
    imgui.SetColumnWidth(0, math.max(110, math.min(210, imgui.GetWindowSize().x * .38)))
    for _, row in ipairs(data) do
        muted(imgui, ui, row[1]); imgui.NextColumn()
        ui.text(tostring(row[2] or '—')); imgui.NextColumn()
    end
    ui.finish()
end

function Menu:guidePage(imgui, ui, model)
    local items = {{'commands', 'Команды'}, {'keys', 'Клавиши'}, {'features', 'Функции'}, {'variables', 'Переменные'}}
    selectorRow(imgui, items, self.guide, 'guide', function(key) self.guide = key end)
    imgui.Separator()
    if self.guide == 'commands' then
        rows(imgui, ui, {
            {'/pa26', 'Открыть или закрыть главное меню'},
            {'/pa26demo', 'Переключить демонстрационный режим'},
            {'/pa26cancel', 'Отменить колесо и оставшиеся строки'},
            {'/pa26hud', 'Показать или скрыть компактный виджет'},
            {'/pa26hudreset', 'Вернуть виджет на исходное место'},
            {'/pa26quick', 'Отдельное быстрое меню биндов'}, {'/pa26tips', 'Отдельное окно памяток'},
            {'/pa26run N', 'Запустить бинд с номером N и аргументами'}, {'/pa26select ID', 'Выбрать конкретного видимого человека'},
        })
        heading(imgui,ui,'Сервер: названия из игровой справки',imgui.GetFont())
        muted(imgui,ui,'Получены от пользователя 20.10.2026. Аргументы и ограничения на скриншотах не показаны.')
        rows(imgui,ui,require('pa26_server_commands').commands)
    elseif self.guide == 'keys' then
        rows(imgui, ui, {{model.menuKey, 'Главное меню'}, {model.wheelKey .. ' (удерживать)', 'Радиальное меню'},
            {'Alt', 'Курсор для редактирования виджета'}, {'ПКМ на виджете', 'Перемещение'},
            {'ЛКМ на крестике', 'Скрыть виджет'}, {'Esc', 'Закрыть меню и отменить действие'}})
        if model.quickKey then rows(imgui,ui,{{model.quickKey,'Быстрое меню'},{model.tipsKey,'Памятки'},{'End','Остановить сценарий (по умолчанию)'}}) end
    elseif self.guide == 'variables' then
        local variables={}; for _,v in ipairs(model.variables or {{'id','ID видимого игрока'}}) do
            local info=model.variableInfo and model.variableInfo(v[1])
            variables[#variables+1]={'{'..v[1]..'}',v[2]..(info and (' · '..info.source..'. '..info.detail) or '')}
        end
        rows(imgui,ui,variables)
        muted(imgui,ui,'Вставки работают в тексте пользовательских биндов. Источник номера авто и сектора — ручной профиль.')
    else
        ui.text('RP-отыгровки с редактируемыми фразами')
        ui.text('Радиальное меню по удержанию клавиши')
        ui.text('Компактный виджет: ник, ID, пинг, район и часы')
        ui.text('Локальный предпросмотр без отправки в чат')
        ui.text('Сохранение настроек и журнал действий')
    end
end

function Menu:homePage(imgui, ui, model, callbacks, fonts)
    local available = imgui.GetContentRegionAvail().x
    self:loadAsset(imgui, 'banner')
    local heroHeight = self:assetHeight('banner', available)
    if not self:drawAsset(imgui, 'banner', available, heroHeight) then
        child(imgui, ui, 'photo-slot##pa26', available, 142, function()
            heading(imgui, ui, 'Exsellent RP / Police Assistant', fonts.heading)
            ui.text('San Andreas Police Department • FBI')
            ui.text('Department of Corrections')
            muted(imgui, ui, 'Изображение недоступно; инструменты остаются доступны.')
        end)
    end
    imgui.Dummy(imgui.ImVec2(0, 8))
    child(imgui, ui, 'profile##pa26', available, 264, function()
        heading(imgui, ui, 'Личное дело', fonts.heading)
        imgui.Separator()
        rows(imgui, ui, {{'Номер личного дела', model.caseNumber~='' and model.caseNumber or 'Не заполнено'}, {'Игровой ник', model.nickname},
            {'SA:MP ID', model.id}, {'Доступ к программе', 'Локальная версия'},
            {'Режим работы', model.demo and 'Демонстрационный' or 'Реальные команды'},
            {'Подключение', model.connected and 'На сервере' or 'Ожидание подключения'}})
    end)
    imgui.Dummy(imgui.ImVec2(0, 8))
    if callbacks.openPatrol and button(imgui,ui,'Патруль и экипаж##home-patrol',imgui.ImVec2(available,40),fonts.button)then callbacks.openPatrol()end
    local pairedButtons = available >= 650
    local buttonWidth = pairedButtons and (available - 12) / 2 or available
    if button(imgui, ui, 'Библиотека биндов##home', imgui.ImVec2(buttonWidth, 46), fonts.button) then
        self:navigate('binds',nil,'actions')
    end
    if pairedButtons then imgui.SameLine(0, 12) end
    if button(imgui, ui, 'Завершить работу##home', imgui.ImVec2(buttonWidth, 46), fonts.button) then callbacks.finishWork() end
    withFont(imgui, ui, fonts.small, function() muted(imgui, ui, 'Остановить текущую отыгровку и закрыть меню.') end)
end

function Menu:statsPage(imgui, ui, model, fonts)
    heading(imgui, ui, 'Статистика текущего запуска', fonts.heading)
    muted(imgui, ui, 'Локальные показатели помощника')
    imgui.Separator()
    rows(imgui, ui, {{'Строк передано в чат', model.sent or 0}, {'Локальных предпросмотров', model.previews or 0},
        {'Подключений за запуск', model.connections or 0}, {'Пинг', model.ping and tostring(model.ping) .. ' мс' or '—'},
        {'Текущий район', model.district}, {'Квадрат карты', model.mapSquare or '—'}, {'Дата и время', model.clock}})
    imgui.Dummy(imgui.ImVec2(0, 10))
    heading(imgui, ui, 'Служебная статистика', fonts.heading)
    rows(imgui, ui, {{'Задержания', '—'}, {'Проверки документов', '—'}, {'Обыски', '—'}})
    muted(imgui, ui, 'Учёт служебных событий добавим отдельным модулем.')
end

function Menu:bindsPage(imgui, ui, model, callbacks, fonts)
    heading(imgui, ui, 'Основные клавиши', fonts.heading)
    rows(imgui, ui, {{model.menuKey, 'Главное меню'}, {model.wheelKey, 'Радиальное меню'}, {'Esc', 'Отмена действия'}})
    if imgui.Button('Изменить клавиши##binds') then self:navigate('settings')end
    imgui.Separator()
    heading(imgui, ui, 'RP-сценарии', fonts.heading)
    for index, action in ipairs(model.actions or {}) do
        local width = math.max(140, imgui.GetContentRegionAvail().x)
        if button(imgui, ui, action.label .. '##edit-action' .. index, imgui.ImVec2(width, 44), fonts.button) then
            callbacks.selectAction(index)
            self:navigate('addons',nil,'actions')
        end
    end
    muted(imgui, ui, 'Сценарии вызываются из колеса; отдельные клавиши для каждого пока не назначены.')
end

function Menu:addonsPage(imgui,ui,model,callbacks,fonts)
    heading(imgui,ui,'Помощники службы',fonts.heading)
    muted(imgui,ui,'Выберите задачу текущей смены. Общие параметры находятся в «Настройках».')
    if callbacks.openAssist and button(imgui,ui,'Открыть быстрое окно помощников ('..(model.assistKey or'F4')..')##assist-open',imgui.ImVec2(-1,42),fonts.button)then callbacks.openAssist()end
    local tools={{'patrol','Патруль и экипаж'},{'events','События патруля'},{'identity','Человек и личность'},
        {'vehicle','Машина и мегафон'},{'procedures','Розыск, штрафы, /setmark'},{'evidence','Фиксация (F8)'},{'training','Обучение'},{'extras','Собеседование'}}
    selectorRow(imgui,tools,self.tool,'tool',function(key)self.tool=key end,ui)
    imgui.Separator()
    local route=({patrol='patrol',events='patrolEvents',identity='identity',vehicle='vehicle',procedures='procedures',
        evidence='evidence',training='training',extras='extras',actions='actions',widget='widget',log='log',operations='operations'})[self.tool]
    if route and callbacks[route]then callbacks[route]()
    elseif self.tool=='wheel'then
        ui.text('Настройка колеса теперь находится в «Настройки → Управление и колесо».')
        if callbacks.openSettings and button(imgui,ui,'Открыть настройки колеса##wheel-settings',imgui.ImVec2(-1,42),fonts.button)then callbacks.openSettings('options')end
    end
end

-- Geometry is independent of rendering and keeps the footer outside the scroll.
function M.layout(w, h,footerTextHeight)
    if not core.finite(w) or not core.finite(h) or w < 440 or h < 300 then return nil end
    local margin = w < 800 and 10 or 16
    local gap = w < 800 and 12 or 16
    local side = w < 800 and 184 or (w < 1060 and 224 or 280)
    local rightX = margin + side + gap
    local rightW = w - rightX - margin
    local columns = rightW >= 800 and 4 or 2
    local rows=4/columns
    local footerH=14+rows*40+(rows-1)*12+8+(footerTextHeight or(columns==4 and 32 or 46))+12
    local bodyY = margin + 60 + gap
    local footerY = h - margin - footerH
    return {margin = margin, gap = gap, side = side, x = rightX, w = rightW,
        headerY = margin, headerH = 60, bodyY = bodyY,
        bodyH = math.max(1, footerY - gap - bodyY), footerY = footerY,
        footerH = footerH, columns = columns, panelH = h - margin * 2}
end

function Menu:draw(imgui, ui, model, callbacks, fonts)
    self.guardNavigation=callbacks.guardNavigation
    local size, pos = imgui.GetWindowSize(), imgui.GetWindowPos()
    local w, h = size.x, size.y
    local layout = M.layout(w, h)
    if not layout then
        ui.text('Police Assistant')
        ui.text(M.credit)
        muted(imgui, ui, 'Увеличьте разрешение для полного меню.')
        if imgui.Button('Открыть RP-инструменты##compact') then self:navigate('addons')end
        callbacks.actions()
        return
    end
    local smallFont=fonts.small or imgui.GetFont();local smallSize=tonumber(smallFont.FontSize)
    local creditH=M.labelLayout(smallFont,smallSize,layout.w-32,M.credit).height
    local contactH=M.labelLayout(smallFont,smallSize,layout.w-32,M.contactText).height
    local footerTextH=creditH+4+contactH
    layout=M.layout(w,h,footerTextH)
    local side = layout.side
    local list, vec = imgui.GetWindowDrawList(), imgui.ImVec2
    local function packed(r, g, b, a) return imgui.ColorConvertFloat4ToU32(color(imgui, r, g, b, a)) end
    local function panel(x, y, width, height, fill)
        local first, last = vec(pos.x + x, pos.y + y), vec(pos.x + x + width, pos.y + y + height)
        list:AddRectFilled(first, last, fill, 14)
        list:AddRect(first, last, packed(.28, .45, .58, .25), 14)
    end
    panel(layout.margin, layout.margin, side, layout.panelH, packed(.09, .25, .40, .84))
    panel(layout.x, layout.headerY, layout.w, layout.headerH, packed(.09, .23, .35, .55))
    panel(layout.x, layout.footerY, layout.w, layout.footerH, packed(.09, .16, .24, .35))
    local pageTitle = 'Главная'
    for _, section in ipairs(M.sections) do if section.key == self.section then pageTitle = section.label end end
    local titleFont = fonts.heading or imgui.GetFont()
    local referenceBox
    if self.section=='hints'and callbacks.hints then
        referenceBox=M.referenceSwitchLayout(layout,fonts.compact or fonts.button or imgui.GetFont(),
            titleFont:CalcTextSizeA(24,100000,0,pageTitle).x)
    end
    local dragWidth=referenceBox and referenceBox.bodyOffset==0 and(referenceBox.x-layout.x-16)or(layout.w-68)
    self:dragWindow(imgui,ui,'main',layout.x+8,layout.headerY+6,math.max(1,dragWidth),layout.headerH-12)
    if self.section=='updates'then pageTitle='Обновления PA'end
    list:AddTextFontPtr(titleFont, 24, vec(pos.x + layout.x + 20, pos.y + layout.headerY + 18), packed(1, 1, 1, 1), pageTitle)
    imgui.SetCursorPos(vec(layout.x + layout.w - 48, layout.headerY + 11))
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, vec(6, 6))
    ui.push(function() imgui.PopStyleVar(1) end)
    ui.menuKey=model.menuKey
    local closeClicked = M.closeButton(imgui,ui,'main-close',38)
    ui.finish()
    if closeClicked then callbacks.close(); return end

    if referenceBox then
        local font=fonts.compact or fonts.button or imgui.GetFont()
        self:referenceSwitch(imgui,ui,referenceBox,font)
    end

    imgui.SetCursorPos(vec(layout.margin, layout.margin))
    child(imgui, ui, 'sidebar##pa26', side, layout.panelH, function()
        local artworkWidth = imgui.GetContentRegionAvail().x
        local artworkHeight = math.min(artworkWidth, math.max(72, layout.panelH - 620))
        if layout.panelH < 510 or not self:drawAsset(imgui, 'sidebar', artworkWidth, artworkHeight) then
            heading(imgui, ui, 'Police Assistant', fonts.brand)
        end
        withFont(imgui, ui, fonts.small, function() ui.text('2026 / Помощник полиции') end)
        imgui.Dummy(vec(0, 6))
        if callbacks.updates then
            withFont(imgui,ui,fonts.compact or fonts.small,function()
                if imgui.Button((callbacks.updateLabel or 'Обновления PA')..'##pa26-updates',vec(math.max(1,imgui.GetContentRegionAvail().x),36))then self:navigate('updates')end
            end)
            imgui.Dummy(vec(0,6))
        end
        local sidebarTextH=0
        for _,line in ipairs(M.contacts)do sidebarTextH=sidebarTextH+M.labelLayout(smallFont,smallSize,artworkWidth,line).height end
        local spacing=self.compact and 6 or 10
        local navHeight = math.max(1, imgui.GetContentRegionAvail().y - (3*smallSize+sidebarTextH+9*spacing+10+math.max(0,42-smallSize)))
        child(imgui, ui, 'navigation##pa26', 0, navHeight, function()
            imgui.PushStyleVarVec2(imgui.StyleVar.ButtonTextAlign, vec(0, .5))
            ui.push(function() imgui.PopStyleVar(1) end)
            withFont(imgui, ui, side < 244 and fonts.compact or fonts.button, function()
                for index, section in ipairs(M.sections) do
                    local selected = self.section == section.key
                    if selected then
                        imgui.PushStyleColor(imgui.Col.Button, color(imgui, .09, .50, .70, .94))
                        ui.push(function() imgui.PopStyleColor(1) end)
                    end
                    local label = side < 244 and section.short or section.label
                    if imgui.Button(string.format('%02d', index) .. '  ' .. label .. '##nav' .. section.key,
                        vec(math.max(1, imgui.GetContentRegionAvail().x), 44)) then self:navigate(section.key)end
                    if selected then ui.finish() end
                end
            end)
            ui.finish()
        end, true, 0, 0)
        imgui.Dummy(vec(0, 4))
        withFont(imgui, ui, fonts.small, function()
            imgui.PushStyleColor(imgui.Col.Button,model.demo and color(imgui,.52,.33,.09,.96)or color(imgui,.08,.32,.35,.96));ui.push(function()imgui.PopStyleColor(1)end)
            if M.fittedButton(imgui,ui,(model.demo and 'ДЕМО · без отправки'or'Реальный режим')..'##sidebar-demo',vec(-1,42),fonts.small)and callbacks.toggleDemo then callbacks.toggleDemo()end
            ui.finish()
            muted(imgui, ui, model.connected and 'Соединение активно' or 'Ожидание сервера')
            imgui.Dummy(vec(0,6));ui.text('Для связи')
            for _,line in ipairs(M.contacts)do ui.text(line)end
        end)
    end, true, imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

    local contentY,contentH=layout.bodyY,layout.bodyH
    if self.section=='settings' and callbacks.settingsTabs then
        imgui.SetCursorPos(vec(layout.x,layout.bodyY))
        local tabsHeight=callbacks.settingsTabHeight and callbacks.settingsTabHeight(layout.w) or 54
        child(imgui,ui,'settings-tabs##pa26',layout.w,tabsHeight,function() callbacks.settingsTabs() end,true,
            imgui.WindowFlags.NoScrollbar+imgui.WindowFlags.NoScrollWithMouse,8)
        contentY=contentY+tabsHeight+8; contentH=math.max(1,contentH-tabsHeight-8)
    elseif self.section=='hints' and referenceBox then
        contentY=contentY+referenceBox.bodyOffset;contentH=math.max(1,contentH-referenceBox.bodyOffset)
    end
    local contentFlags=0
    if self.section=='binds' or self.section=='knowledge' or (self.section=='addons' and self.tool=='actions') then
        contentFlags=imgui.WindowFlags.NoScrollbar+imgui.WindowFlags.NoScrollWithMouse
    end
    imgui.SetCursorPos(vec(layout.x, contentY))
    child(imgui, ui, 'content##pa26', layout.w, contentH, function()
        if self.section=='updates'and callbacks.updates then callbacks.updates()
        elseif self.section == 'home' then self:homePage(imgui, ui, model, callbacks, fonts)
        elseif self.section == 'settings' then callbacks.settings()
        elseif self.section == 'stats' then if callbacks.stats then callbacks.stats() else self:statsPage(imgui, ui, model, fonts) end
        elseif self.section == 'binds' then if callbacks.binds then callbacks.binds() else self:bindsPage(imgui, ui, model, callbacks, fonts) end
        elseif self.section == 'hints' then
            if callbacks.hints and not self.referenceOpen then callbacks.hints()
            else self:guidePage(imgui, ui, model)end
        elseif self.section == 'partners' then
            if callbacks.partners then callbacks.partners() else
            heading(imgui, ui, 'Список напарников', fonts.heading)
            imgui.Separator()
            ui.text('Напарников пока нет')
            muted(imgui, ui, 'Здесь появится список и карточки напарников.') end
        elseif self.section == 'addons' then self:addonsPage(imgui, ui, model, callbacks, fonts)
        elseif self.section == 'knowledge' and callbacks.knowledge then callbacks.knowledge() end
    end, true, contentFlags)

    imgui.SetCursorPos(vec(layout.x + 16, layout.footerY + 14))
    local links = {{'commands', 'Список команд'}, {'keys', 'Список клавиш'},
        {'features', 'Список функций'}, {'variables', 'Список переменных'}}
    local columns = layout.columns
    local buttonWidth = (layout.w - 32 - 12 * (columns - 1)) / columns
    local shortLabels = {'Команды', 'Клавиши', 'Функции', 'Переменные'}
    for index, link in ipairs(links) do
        if (index - 1) % columns ~= 0 then imgui.SameLine(0, 12) end
        local label = layout.w < 650 and shortLabels[index] or link[2]
        local active=self.section=='hints'and self.referenceOpen and self.guide==link[1]
        if active then imgui.PushStyleColor(imgui.Col.Button,color(imgui,.09,.43,.62,.94));ui.push(function()imgui.PopStyleColor(1)end)end
        if button(imgui, ui, label .. '##footer', vec(buttonWidth, 40), fonts.compact or fonts.button) then
            self:navigate('hints',link[1])
        end
        if active then ui.finish()end
        if index % columns == 0 and index < #links then imgui.SetCursorPosX(layout.x + 16) end
    end
    imgui.SetCursorPos(vec(layout.x + 16, layout.footerY + layout.footerH - footerTextH - 12))
    withFont(imgui, ui, fonts.small, function()
        imgui.PushTextWrapPos(imgui.GetCursorPosX()+layout.w-32);ui.push(function()imgui.PopTextWrapPos()end)
        imgui.TextUnformatted(M.credit)
        imgui.SetCursorPos(vec(layout.x+16,layout.footerY+layout.footerH-footerTextH-12+creditH+4))
        imgui.TextUnformatted(M.contactText)
        ui.finish()
    end)
end

return M

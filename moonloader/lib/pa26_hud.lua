-- Original compact HUD. All game reads are injected; renderer reads stay in draw.
local core = require 'pa26_core'
local M = {WIDTH = 272, HEIGHT = 174, HEADER = 24}

-- Administrative rectangles from this client's GTA SA data/info.zon.
-- These are coordinate facts, not police jurisdictions or server sectors.
local cityBounds={
    {'Лос-Сантос',44.6147,-2892.97,2997.06,-768.027},
    {'Лас-Вентурас',869.461,596.349,2997.06,2993.87},
    {'Боун-Каунти',-480.539,596.349,869.461,2993.87},
    {'Тьерра-Робада',-2997.47,1659.68,-480.539,2993.87},
    {'Тьерра-Робада',-1213.91,596.349,-480.539,1659.68},
    {'Сан-Фиерро',-2997.47,-1115.58,-1213.91,1659.68},
    {'Ред-Каунти',-1213.91,-768.027,2997.06,596.349},
    {'Флинт-Каунти',-1213.91,-2892.97,44.6147,-768.027},
    {'Уэтстоун',-2997.47,-2892.97,-1213.91,-1115.58}}
function M.cityName(x,y,z,zoneKey)
    if not core.finite(x)or not core.finite(y)or z~=nil and not core.finite(z)then return nil end
    local key=type(zoneKey)=='string'and zoneKey:upper():gsub('%d+[A-Z]?$','')or''
    -- Airport/Foster Valley subzones extend beyond the broad SF rectangle.
    if(key=='SFAIR'or key=='SILLY')and x>=-3000 and x<=-900 and y>=-1300 and y<=600 then return'Сан-Фиерро'end
    for _,r in ipairs(cityBounds)do if x>=r[2]and x<r[4]and y>=r[3]and y<r[5]then return r[1]end end
end

-- Zone keys are native GTA labels, not text encoded for the game's font atlas.
-- English place names are facts verified against this client's zone/GXT data.
-- Prefer these names even when a localized GXT happens to look like valid UTF-8.
local districtNames = {
    ALDEA = "Aldea Malvada",
    ANGPI = "Angel Pine",
    ARCO = "Arco del Oeste",
    BACKO = "Back o Beyond",
    BARRA = "Las Barrancas",
    BATTP = "Battery Point",
    BAYV = "Palisades",
    BEACO = "Beacon Hill",
    BFC = "Blackfield Chapel",
    BFLD = "Blackfield",
    BIGE = "'The Big Ear'",
    BINT = "Blackfield Intersection",
    BLUAC = "Blueberry Acres",
    BLUEB = "Blueberry",
    BLUF = "Verdant Bluffs",
    BONE = "Bone County",
    BRUJA = "Las Brujas",
    BYTUN = "Bayside Tunnel",
    CALI = "Caligula's Palace",
    CALT = "Calton Heights",
    CAM = "The Camel's Toe",
    CARSO = "Fort Carson",
    CHC = "Las Colinas",
    CHINA = "Chinatown",
    CITYS = "City Hall",
    CIVI = "Santa Flora",
    COM = "Commerce",
    CONF = "Conference Centre",
    CRANB = "Cranberry Station",
    CREE = "Creek",
    CREEK = "Shady Creeks",
    CUNTC = "Avispa Country Club",
    DAM = "Sherman Dam",
    DILLI = "Dillimore",
    DOH = "Doherty",
    DRAG = "The Four Dragons Casino",
    EASB = "Easter Basin",
    EBAY = "Easter Bay Chemicals",
    EBE = "East Beach",
    ELCA = "El Castillo del Diablo",
    ELCO = "El Corona",
    ELQUE = "El Quebrados",
    ELS = "East Los Santos",
    ESPE = "Esplanade East",
    ESPN = "Esplanade North",
    ETUNN = "Easter Tunnel",
    FALLO = "Fallow Bridge",
    FARM = "The Farm",
    FERN = "Fern Ridge",
    FINA = "Financial",
    FISH = "Fisher's Lagoon",
    FLINTC = "Flint County",
    FLINTI = "Flint Intersection",
    FLINTR = "Flint Range",
    FLINW = "Flint Water",
    FRED = "Frederick Bridge",
    GAN = "Ganton",
    GANTB = "Gant Bridge",
    GARC = "Garcia",
    GARV = "Garver Bridge",
    GGC = "Greenglass College",
    GLN = "Glen Park",
    HANKY = "Hankypanky Point",
    HASH = "Hashbury",
    HAUL = "Fallen Tree",
    HBARNS = "Hampton Barns",
    HGP = "Harry Gold Parkway",
    HIGH = "The High Roller",
    HILLP = "Missionary Hill",
    ISLE = "The Emerald Isle",
    IWD = "Idlewood",
    JEF = "Jefferson",
    JTE = "Julius Thruway East",
    JTN = "Julius Thruway North",
    JTS = "Julius Thruway South",
    JTW = "Julius Thruway West",
    JUNIHI = "Juniper Hill",
    JUNIHO = "Juniper Hollow",
    KACC = "K.A.C.C. Military Fuels",
    KINC = "Kincaid Bridge",
    LA = "Los Santos",
    LAIR = "Los Santos International",
    LDM = "Last Dime Motel",
    LDOC = "Ocean Docks",
    LDS = "Linden Side",
    LDT = "Downtown Los Santos",
    LEAFY = "Leafy Hollow",
    LFL = "Los Flores",
    LIND = "Willowfield",
    LINDEN = "Linden Station",
    LMEX = "Little Mexico",
    LOT = "Come-A-Lot",
    LSINL = "Los Santos Inlet",
    LST = "Linden Station",
    LVA = "LVA Freight depot",
    MAKO = "The Mako Span",
    MAR = "Marina",
    MARKST = "Market Station",
    MART = "Martin Bridge",
    MEAD = "Verdant Meadows",
    MKT = "Market",
    MONINT = "Montgomery Intersection",
    MONT = "Montgomery",
    MTCHI = "Mount Chiliad",
    MUL = "Mulholland",
    MULINT = "Mulholland Intersection",
    NROCK = "North Rock",
    OCEAF = "Ocean Flats",
    OCTAN = "Octane Springs",
    OVS = "Old Venturas Strip",
    PALMS = "Green Palms",
    PALO = "Palomino Creek",
    PANOP = "The Panopticon",
    PARA = "Paradiso",
    PAYAS = "Las Payasadas",
    PER1 = "Pershing Square",
    PILL = "Pilgrim",
    PINK = "The Pink Swan",
    PINT = "Pilson Intersection",
    PIRA = "Pirates in Men's Pants",
    PLS = "Playa del Seville",
    PROBE = "Lil' Probe Inn",
    PRP = "Prickle Pine",
    QUARY = "Hunter Quarry",
    RED = "Red County",
    REDE = "Redsands East",
    REDW = "Redsands West",
    REST = "Restricted Area",
    RIE = "Randolph Industrial Estate",
    RIH = "Richman",
    RING = "The Clown's Pocket",
    ROBAD = "Tierra Robada",
    ROBINT = "Robada Intersection",
    ROCE = "Roca Escalante",
    ROD = "Rodeo",
    ROY = "Royale Casino",
    RSE = "Rockshore East",
    RSW = "Rockshore West",
    SANAND = "San Andreas",
    SANB = "San Fierro Bay",
    SAN_AND = "San Andreas",
    SASO = "San Andreas Sound",
    SF = "San Fierro",
    SFAIR = "Easter Bay Airport",
    SFDWT = "Downtown",
    SHACA = "Shady Cabin",
    SHERR = "Sherman Reservoir",
    SILLY = "Foster Valley",
    SMB = "Santa Maria Beach",
    SPIN = "Spinybed",
    SRY = "Sobell Rail Yards",
    STAR = "Starfish Casino",
    STRIP = "The Strip",
    SUN = "Temple",
    SUNMA = "Bayside Marina",
    SUNNN = "Bayside",
    THEA = "King's",
    TOM = "Regular Tom",
    TOPFA = "Hilltop Farm",
    UNITY = "Unity Station",
    VAIR = "Las Venturas Airport",
    VALLE = "Valle Ocultado",
    VE = "Las Venturas",
    VERO = "Verona Beach",
    VIN = "Vinewood",
    VISA = "The Visage",
    WESTP = "Queens",
    WHET = "Whetstone",
    WWE = "Whitewood Estates",
    YBELL = "Yellow Bell Golf Course",
    YELLOW = "Yellow Bell Station",
}

function M.zoneName(key, rawText)
    if type(key) ~= 'string' or #key > 16 or not key:match('^[A-Za-z0-9_]+$') then return 'San Andreas' end
    key = key:upper()
    if districtNames[key] then return districtNames[key] end
    if key == 'NULL' or key == 'NONE' then return 'San Andreas' end
    if type(rawText) == 'string' and #rawText <= 128 then
        local value = rawText:gsub('~[^~]*~', ''):match('^%s*(.-)%s*$')
        if value ~= '' and not value:find('[^ -~]') and value:find('[A-Za-z]') then return value end
    end
    return key -- bounded readable label for an unknown/custom zone, never guessed CP1251
end

local Hud = {}
Hud.__index = Hud

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function invoke(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function clean(value, decode, limit)
    if type(value) ~= 'string' or value == '' or #value > (limit or 256) then return nil end
    if not core.validUtf8(value) then value = invoke(decode, value) end
    if type(value) ~= 'string' or not core.validUtf8(value) then return nil end
    value = value:gsub('~[^~]*~', ''):gsub('%c', ' '):match('^%s*(.-)%s*$')
    return value ~= '' and value or nil
end

function M.new(settings, env)
    settings = settings or core.widgetDefaults()
    assert(core.validateWidget(settings))
    return setmetatable({settings = copy(settings), env = env, connected = false,
        editing = false, interactive = false, failed = false, dirty = false,
        data = {identity = '— | Ping: —', district = '—', clock = '—'},
        lastNow = nil, lastWall = nil, session = nil, drag = nil,
        bounds = nil, lastMouseDown = false, notices={}, noticeNow=0, confirmationHeight=0,equipmentHeight=0}, Hud)
end

function Hud:expireNotices(now)
    self.noticeNow=core.finite(now) and now or self.noticeNow
    for i=#self.notices,1,-1 do
        local age=core.elapsed(self.noticeNow,self.notices[i].startedAt)
        if not age or age>=self.notices[i].duration then table.remove(self.notices,i) end
    end
end
function Hud:targetNotice(kind,target,reason,now,preferences)
    if kind=='rebound' or not target or not core.validId(target.id) then return false end
    self:expireNotices(now)
    local name=clean(target.name,self.env.decode,96) or 'Игрок'
    name=name:gsub('{%x%x%x%x%x%x}','')
    -- A termination replaces this person's earlier green card immediately.
    for i=#self.notices,1,-1 do
        local note=self.notices[i]
        if note.id==target.id and note.name==name then table.remove(self.notices,i) end
    end
    local positive=kind=='selected' or kind=='changed'
    local p=preferences or require('pa26_assist_settings').noticeDefaults()
    local duration=positive and p.started_ms or reason=='disconnected'and p.disconnected_ms or p.ended_ms
    local function expand(value)return value:gsub('{([a-z_]+)}',function(k)return k=='name'and name or k=='id'and tostring(target.id)or ''end)end
    local detail=type(p[reason])=='string'and p[reason]or p.other_detail
    table.insert(self.notices,1,{id=target.id,name=name,positive=positive,
        title=expand(positive and p.started_title or p.ended_title),
        detail=expand(positive and p.started_detail or detail),
        duration=duration,startedAt=self.noticeNow})
    while #self.notices>p.max_cards do table.remove(self.notices) end
    return true
end
function Hud:setConfirmationHeight(height)
    if not core.finite(height) or height<0 or height>2000 then return false end
    self.confirmationHeight=height; return true
end
function Hud:setEquipmentHeight(height)
    if not core.finite(height) or height<0 or height>2000 then return false end
    self.equipmentHeight=height;return true
end
-- One shared attachment lane: an active SOS confirmation gets the first slot,
-- followed by notices. At screen edges the whole lane moves above or beside HUD.
function M.overlayLayout(r,width,height,heights,reserve,equipment)
    if not r or not core.finite(width) or not core.finite(height) or width<1 or height<1 then return nil end
    for _,key in ipairs({'x','y','w','h','scale'}) do if not core.finite(r[key]) then return nil end end
    if r.w<=0 or r.w>width-8 or r.h<=0 or r.scale<=0 then return nil end
    reserve=reserve or 0
    if not core.finite(reserve) or reserve<0 then return nil end
    equipment=equipment or 0;if not core.finite(equipment) or equipment<0 then return nil end
    local gap=10*r.scale; local total=reserve+equipment+(reserve>0 and equipment>0 and gap or 0)
    for _,h in ipairs(heights) do
        if not core.finite(h) or h<=0 then return nil end
        if total>0 then total=total+gap end; total=total+h
    end
    if total<=0 or total>height-8 then return nil end
    local candidates={{r.x,r.y+r.h+gap},{r.x,r.y-total-gap},
        {r.x-r.w-gap,r.y},{r.x+r.w+gap,r.y}}
    for _,point in ipairs(candidates) do
        local x,y=math.max(4,math.min(point[1],width-r.w-4)),math.max(4,math.min(point[2],height-total-4))
        local overlap=x<r.x+r.w and x+r.w>r.x and y<r.y+r.h and y+total>r.y
        if x>=4 and x+r.w<=width-4 and not overlap then
            local out={notices={}}; local nextY=y
            if reserve>0 then out.confirmation={x=x,y=y,w=r.w,h=reserve}; nextY=nextY+reserve+gap end
            if equipment>0 then out.equipment={x=x,y=nextY,w=r.w,h=equipment};nextY=nextY+equipment+gap end
            for _,h in ipairs(heights) do out.notices[#out.notices+1]={x=x,y=nextY,w=r.w,h=h}; nextY=nextY+h+gap end
            return out
        end
    end
end
function Hud:attachmentLayout(im,fonts)
    local io=im.GetIO();local r=self:layout(io.DisplaySize.x,io.DisplaySize.y);if not r then return nil end
    local pad=12*r.scale;local wrap=r.w-2*pad;local heights={}
    local body=fonts.body or im.GetFont();local heading=fonts.heading or body
    for _,note in ipairs(self.settings.visible and self.notices or {}) do
        local age=core.elapsed(self.noticeNow,note.startedAt)
        if age and age<note.duration then heights[#heights+1]=2*pad+
            heading:CalcTextSizeA(15*r.scale,100000,wrap,note.title).y+
            heading:CalcTextSizeA(16*r.scale,100000,wrap,note.name..' ['..note.id..']').y+
            body:CalcTextSizeA(14*r.scale,100000,wrap,note.detail).y+14*r.scale end
    end
    local lane=M.overlayLayout(r,io.DisplaySize.x,io.DisplaySize.y,heights,self.confirmationHeight,self.equipmentHeight)
    while not lane and #heights>0 do table.remove(heights);lane=M.overlayLayout(r,io.DisplaySize.x,io.DisplaySize.y,heights,self.confirmationHeight,self.equipmentHeight)end
    if not lane and self.equipmentHeight>0 and self.confirmationHeight>0 then
        lane=M.overlayLayout(r,io.DisplaySize.x,io.DisplaySize.y,{},self.confirmationHeight,0)
    end
    self.equipmentBounds=lane and lane.equipment or nil
    return lane
end

function Hud:getSettings() return copy(self.settings) end

function Hud:change(key, value)
    local nextSettings = self:getSettings()
    nextSettings[key] = value
    if not core.validateWidget(nextSettings) then return false end
    if self.settings[key] ~= value then
        self.settings = nextSettings
        self.dirty, self.dirtyAt = true, nil
    end
    return true
end

function Hud:setVisible(value)
    if not self:change('visible', value) then return end
    self.failed = false
    self:stopInteraction()
    if not self.settings.visible then self.bounds=nil end
end

function Hud:resetPosition()
    local defaults = core.widgetDefaults()
    self:change('x', defaults.x)
    self:change('y', defaults.y)
    self:change('scale', defaults.scale)
    self:setVisible(true)
end

function Hud:stopInteraction()
    self.drag = nil
    self.editing, self.interactive, self.lastMouseDown = false, false, false
end

function Hud:setInteraction(editing, otherUi)
    self.editing = editing == true and self.settings.visible and not self.failed
    self.interactive = (self.editing or otherUi == true) and self.settings.visible and not self.failed
    if not self.interactive then self.drag = nil end
end

function Hud:setPointer(x, y, left, right)
    self.pointer = {x = x, y = y, left = left == true, right = right == true}
end

function Hud:prepareInput(imgui, otherUi, explicitCursor)
    if not(self.editing or explicitCursor) or otherUi or not self.pointer then return end
    -- ImGui input is disabled while the HUD is passive. Feed a fresh snapshot
    -- only in explicit Alt editing, so an earlier disabled mouse-up cannot stick.
    local io, p = imgui.GetIO(), self.pointer
    if core.finite(p.x) and core.finite(p.y) then io.MousePos = imgui.ImVec2(p.x, p.y) end
    io.MouseDown[0], io.MouseDown[1] = p.left, p.right
end

function Hud:savePending(now,force)
    if not self.dirty then return end
    if self.drag and not force then self.dirtyAt = now; return end
    if self.dirtyAt == nil then self.dirtyAt = now end
    local elapsed = core.elapsed(now, self.dirtyAt)
    if elapsed == nil then self.dirtyAt = now; return end
    -- One save after release/debounce; no disk writes during a drag or every frame.
    if elapsed < 700 and not force then return end
    self.dirty, self.dirtyAt = false, nil
    local ok, note = invoke(self.env.save, self:getSettings())
    if ok ~= true then
        invoke(self.env.log, 'Положение виджета изменено только до перезапуска: ' .. tostring(note or 'INI недоступен'))
    end
end

function Hud:refresh(session, now)
    self:expireNotices(now)
    self.connected = session ~= nil
    if session ~= self.session then
        self.session, self.lastNow = session, nil
        self.data = {identity = '— | Ping: —', district = '—', clock = '—'}
        self.notices={}
        self:stopInteraction()
    end
    local wall = invoke(self.env.wallTime)
    local elapsed = self.lastNow ~= nil and core.elapsed(now, self.lastNow) or nil
    if self.lastNow ~= nil and elapsed ~= nil and elapsed < 500 and wall == self.lastWall then return end
    self.lastNow, self.lastWall = now, wall
    local clock = invoke(self.env.localClock)
    if type(clock) == 'string' then self.data.clock = clock else self.data.clock = '—' end
    if self.settings.time_source == 'game' then
        local hours, minutes = invoke(self.env.gameClock)
        local date = invoke(self.env.localDate)
        if core.finite(hours) and core.finite(minutes) and hours == math.floor(hours) and
            minutes == math.floor(minutes) and hours >= 0 and hours <= 23 and minutes >= 0 and
            minutes <= 59 and type(date) == 'string' then
            self.data.clock = string.format('%s %02d:%02d', date, hours, minutes)
        else self.data.clock = 'Игровое время: —' end
    end
    if not self.connected then return end
    local id = invoke(self.env.localId)
    local nick = core.validId(id) and clean(invoke(self.env.nickname, id), self.env.decode, 96) or nil
    local ping = core.validId(id) and invoke(self.env.ping, id) or nil
    if not core.finite(ping) or ping < 0 or ping > 999999 or ping ~= math.floor(ping) then ping = nil end
    self.data.nickname, self.data.id, self.data.ping = nick, core.validId(id) and id or nil, ping
    self.data.identity = (nick or '—') .. '[' .. (core.validId(id) and tostring(id) or '—') ..
        '] | Ping: ' .. (ping ~= nil and tostring(ping) or '—')
    local x, y, z = invoke(self.env.coordinates)
    self.data.district = '—'
    if core.finite(x) and core.finite(y) and core.finite(z) then
        local interior = invoke(self.env.interior)
        if core.finite(interior) and interior > 0 and interior == math.floor(interior) then
            self.data.district = 'Interior ' .. tostring(interior)
        else
            local key = invoke(self.env.zone, x, y, z)
            if type(key) == 'string' and #key <= 16 and key:match('^[A-Za-z0-9_]+$') then
                self.data.district = districtNames[key:upper()] or M.zoneName(key, invoke(self.env.zoneText, key))
            else self.data.district = 'San Andreas' end
        end
    end
end

function Hud:preparePatrolStatus(font)
    local status=self.patrol and self.patrol.visible and self.patrol.status or''
    if self.patrolStatusText==status and self.patrolStatusFont==font then return end
    self.patrolStatusText=status;self.patrolStatusFont=font
    local rows=require('pa26_menu').labelLayout(font,13,254,status).lines
    local visible={};for i=1,math.min(#rows,12)do visible[i]=rows[i].text end
    if #rows>12 then visible[12]='Продолжение — в журнале PA.'end
    self.patrolStatusRows=visible;self.patrolExtraHeight=math.max(0,(#visible-1)*16)
end
function Hud:layout(width, height)
    if not core.finite(width) or not core.finite(height) or width <= 0 or height <= 0 then return nil end
    local baseHeight=M.HEIGHT+(self.mapSquare and 28 or 0)+(self.patrol and self.patrol.visible and((self.patrol.crew and 80 or 58)+(self.patrolExtraHeight or 0))or 0)
    local scale = math.min(self.settings.scale, (width - 4) / M.WIDTH, (height - 4) / baseHeight)
    if scale < 0.45 then return nil end
    local w, h = M.WIDTH * scale, baseHeight * scale
    local x = math.max(0, math.min(self.settings.x, width - w))
    local y = math.max(0, math.min(self.settings.y, height - h))
    return {x = x, y = y, w = w, h = h, scale = scale}
end

local function contains(rect, x, y)
    return rect ~= nil and core.finite(x) and core.finite(y) and
        x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

function Hud:wantsMouse(imgui)
    if not self.interactive or not self.connected or not self.settings.visible or self.failed then return false end
    if self.editing or self.drag ~= nil then return true end
    local io = imgui.GetIO() -- only called in the renderer-selected before-frame context
    return contains(self:layout(io.DisplaySize.x, io.DisplaySize.y), io.MousePos.x, io.MousePos.y)
end

function Hud:overWidget(imgui)
    if not self.interactive or not self.settings.visible or self.failed then return false end
    local io = imgui.GetIO()
    return contains(self:layout(io.DisplaySize.x, io.DisplaySize.y), io.MousePos.x, io.MousePos.y)
end

local function dropLastCharacter(value)
    local i = #value
    while i > 0 and value:byte(i) >= 0x80 and value:byte(i) <= 0xBF do i = i - 1 end
    return value:sub(1, i - 1)
end

local function fitted(font, value, size, maxWidth)
    local width = font:CalcTextSizeA(size, 100000, 0, value).x
    if width <= maxWidth then return value, width end
    while #value > 0 do
        value = dropLastCharacter(value)
        local candidate = value .. '…'
        width = font:CalcTextSizeA(size, 100000, 0, candidate).x
        if width <= maxWidth then return candidate, width end
    end
    return '', 0
end

function Hud:draw(imgui, bodyFont, headingFont)
    -- Other overlays share this render callback and may remain visible on their
    -- own. They must never resurrect the compact panel after its X was pressed.
    if not self.settings.visible or self.failed or not self.connected then
        self.bounds=nil;self:stopInteraction();return
    end
    local io = imgui.GetIO()
    self:preparePatrolStatus(bodyFont or imgui.GetFont())
    local r = self:layout(io.DisplaySize.x, io.DisplaySize.y)
    self.bounds = r
    if not r then self.drag = nil; return end
    local mx, my = io.MousePos.x, io.MousePos.y
    if self.interactive and not self.lastMouseDown and imgui.IsMouseClicked(1) and contains(r, mx, my) then
        self.drag = {dx = mx - r.x, dy = my - r.y}
        invoke(self.env.beginEdit)
    end
    self.lastMouseDown = io.MouseDown[1] == true
    if self.drag then
        if not self.interactive or not self.lastMouseDown then self.drag = nil
        else
            self:change('x', math.max(0, math.min(mx - self.drag.dx, io.DisplaySize.x - r.w)))
            self:change('y', math.max(0, math.min(my - self.drag.dy, io.DisplaySize.y - r.h)))
            r = self:layout(io.DisplaySize.x, io.DisplaySize.y)
        end
    end
    local s, x, y, w, h = r.scale, r.x, r.y, r.w, r.h
    local closeRect = {x = x + w - 21 * s, y = y + 4 * s, w = 17 * s, h = 17 * s}
    local overClose = self.interactive and contains(closeRect, mx, my)
    if overClose and imgui.IsMouseClicked(0) and not self.drag then
        invoke(self.env.beginEdit)
        self:setVisible(false)
        return
    end
    local list = imgui.GetForegroundDrawList()
    local vec = imgui.ImVec2
    local function color(a, b, c, d) return imgui.ColorConvertFloat4ToU32(imgui.ImVec4(a, b, c, d)) end
    local white, shadow = color(1, 1, 1, 1), color(0, 0, 0, 0.70)
    list:AddRectFilled(vec(x + 1 * s, y + 2 * s), vec(x + w + 1 * s, y + h + 2 * s),
        color(0, 0, 0, 0.32), 6 * s)
    list:AddRectFilled(vec(x, y), vec(x + w, y + h), color(0.035, 0.085, 0.145, 0.79), 8 * s)
    local topCorners = imgui.DrawCornerFlags.TopLeft + imgui.DrawCornerFlags.TopRight
    list:AddRectFilled(vec(x, y), vec(x + w, y + M.HEADER * s),
        color(0.25, 0.62, 0.86, 0.96), 6 * s, topCorners)
    list:AddRect(vec(x, y), vec(x + w, y + h), color(0.28, 0.56, 0.78, 0.16), 8 * s)
    local mapOffset=self.mapSquare and 28 or 0
    for _, offset in ipairs({24, 58, 88+mapOffset, 140+mapOffset}) do
        list:AddLine(vec(x + 2 * s, y + offset * s), vec(x + w - 2 * s, y + offset * s),
            color(0.45, 0.65, 0.83, 0.18), math.max(1, s))
    end
    bodyFont, headingFont = bodyFont or imgui.GetFont(), headingFont or bodyFont or imgui.GetFont()
    local function line(value, font, size, top, centered, maxWidth)
        local fittedValue, textWidth = fitted(font, value, size * s, maxWidth * s)
        local left = centered and x + (w - textWidth) / 2 or x + 9 * s
        list:AddTextFontPtr(font, size * s, vec(left + s, y + top * s + s), shadow, fittedValue)
        list:AddTextFontPtr(font, size * s, vec(left, y + top * s), white, fittedValue)
    end
    line('Police Assistant', headingFont, 15, 3, true, 222)
    line(self.data.identity, bodyFont, 14, 35, true, 254)
    line('Район: ' .. self.data.district, bodyFont, 14, 66, false, 254)
    if self.mapSquare then
        local label='Квадрат карты: '
        local labelW=bodyFont:CalcTextSizeA(14*s,100000,0,label).x
        local value,valueW=fitted(headingFont,self.mapSquare,17*s,math.max(0,242*s-labelW))
        local badgeW=math.min(254*s,labelW+valueW+12*s)
        list:AddRectFilled(vec(x+9*s,y+84*s),vec(x+9*s+badgeW,y+110*s),color(.12,.36,.54,.70),4*s)
        list:AddTextFontPtr(bodyFont,14*s,vec(x+15*s,y+89*s),color(.70,.89,1,1),label)
        list:AddTextFontPtr(headingFont,17*s,vec(x+15*s+labelW,y+87*s),white,value)
    end
    local target=self.target or {state='none',status='Человек не выбран'}
    if target.id then
        local nickname=clean(target.name,self.env.decode,96) or 'Игрок'
        local prefix,suffix='Игрок: ',' ['..target.id..']'
        local reserved=bodyFont:CalcTextSizeA(14*s,100000,0,prefix..suffix).x
        nickname=fitted(bodyFont,nickname,14*s,math.max(0,254*s-reserved))
        line(prefix..nickname..suffix,bodyFont,14,96+mapOffset,false,254)
    else line('Игрок: —',bodyFont,14,96+mapOffset,false,254) end
    local stateText=target.status or 'Человек не выбран'
    if core.finite(target.distance) then stateText=stateText..string.format(' · %.1f м',target.distance) end
    line(stateText,bodyFont,14,118+mapOffset,false,254)
    line(self.data.clock, bodyFont, 14, 150+mapOffset, true, 254)
    if self.patrol and self.patrol.visible then
        list:AddLine(vec(x+9*s,y+(174+mapOffset)*s),vec(x+w-9*s,y+(174+mapOffset)*s),color(.40,.62,.78,.25),s)
        line(self.patrol.label..(self.patrol.crew and ''or ' · рация'),headingFont,14,180+mapOffset,false,254)
        for n,text in ipairs(self.patrolStatusRows or{self.patrol.status})do line(text,bodyFont,13,201+mapOffset+(n-1)*16,false,254)end
        local extra=self.patrolExtraHeight or 0
        if self.patrol.crew then line(self.patrol.crew,bodyFont,13,222+mapOffset+extra,false,254)end
        local barY=(self.patrol.crew and 247 or 225)+mapOffset+extra
        list:AddRectFilled(vec(x+9*s,y+barY*s),vec(x+w-9*s,y+(barY+3)*s),color(.12,.24,.34,.8),2*s)
        list:AddRectFilled(vec(x+9*s,y+barY*s),vec(x+9*s+(w-18*s)*self.patrol.progress,y+(barY+3)*s),color(.24,.62,.86,.95),2*s)
    end
    if overClose then
        list:AddRectFilled(vec(closeRect.x, closeRect.y), vec(closeRect.x + closeRect.w, closeRect.y + closeRect.h),
            color(1, 1, 1, 0.16), 3 * s)
    end
    local cx, cy = x + w - 12 * s, y + 12 * s
    local crossColor = color(1, 1, 1, overClose and 1 or 0.80)
    list:AddLine(vec(cx - 3 * s, cy - 3 * s), vec(cx + 3 * s, cy + 3 * s), crossColor, math.max(1, s))
    list:AddLine(vec(cx - 3 * s, cy + 3 * s), vec(cx + 3 * s, cy - 3 * s), crossColor, math.max(1, s))
end

function Hud:drawNotices(imgui,bodyFont,headingFont)
    self.noticeBounds={}; self.confirmationBounds=nil;self.equipmentBounds=nil
    if (not self.settings.visible and self.confirmationHeight<=0 and self.equipmentHeight<=0) or self.failed then return end
    local io=imgui.GetIO(); local r=self:layout(io.DisplaySize.x,io.DisplaySize.y)
    if not r then return end
    bodyFont=bodyFont or imgui.GetFont(); headingFont=headingFont or bodyFont
    local s=r.scale; local pad=12*s; local wrap=r.w-2*pad
    local rows,heights={},{}
    for _,note in ipairs(self.settings.visible and self.notices or {}) do
        local age=core.elapsed(self.noticeNow,note.startedAt)
        if age and age<note.duration then
            local who=note.name..' ['..note.id..']'
            local titleH=headingFont:CalcTextSizeA(15*s,100000,wrap,note.title).y
            local nameH=headingFont:CalcTextSizeA(16*s,100000,wrap,who).y
            local detailH=bodyFont:CalcTextSizeA(14*s,100000,wrap,note.detail).y
            rows[#rows+1]={note=note,age=age,who=who,titleH=titleH,nameH=nameH,detailH=detailH}
            heights[#heights+1]=2*pad+titleH+nameH+detailH+14*s
        end
    end
    local layout=self:attachmentLayout(imgui,{body=bodyFont,heading=headingFont})
    if not layout then return end
    while #rows>#layout.notices do table.remove(rows)end
    self.noticeBounds=layout.notices; self.confirmationBounds=layout.confirmation;self.equipmentBounds=layout.equipment
    local list=imgui.GetForegroundDrawList(); local vec=imgui.ImVec2
    for i,row in ipairs(rows) do
        local note=row.note; local box=layout.notices[i]
        local alpha=math.min(1,(note.duration-row.age)/400)
        local function tint(a,b,c,d) return imgui.ColorConvertFloat4ToU32(imgui.ImVec4(a,b,c,(d or 1)*alpha)) end
        local accent=note.positive and tint(.28,.88,.52) or tint(1,.35,.38)
        list:AddRectFilled(vec(box.x,box.y),vec(box.x+box.w,box.y+box.h),tint(.035,.085,.145,.87),9*s)
        local top=box.y+pad
        list:AddTextFontPtr(headingFont,15*s,vec(box.x+pad,top),tint(.96,.98,1),note.title,nil,wrap)
        top=top+row.titleH+4*s
        list:AddTextFontPtr(headingFont,16*s,vec(box.x+pad,top),accent,row.who,nil,wrap)
        top=top+row.nameH+4*s
        list:AddTextFontPtr(bodyFont,14*s,vec(box.x+pad,top),tint(.79,.87,.94),note.detail,nil,wrap)
        local progress=math.max(0,1-row.age/note.duration)
        list:AddRectFilled(vec(box.x+pad,box.y+box.h-5*s),vec(box.x+pad+wrap*progress,box.y+box.h-3*s),accent,2*s)
    end
end

return M

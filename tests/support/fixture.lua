-- The real script is executed with native LuaJIT FFI and strict, canonical API mocks.
local ffi = require 'ffi'
local core = require 'pa26_core'

-- Native-style IO fields plus a strict renderer boundary. mimgui creates its
-- context lazily on the first active draw, not when OnFrame is registered.
ffi.cdef [[
    typedef struct { float x, y; } Pa26TestVec2;
    typedef struct { float x, y, z, w; } Pa26TestVec4;
    typedef struct { int reserved; } Pa26TestFontAtlas;
    typedef struct { float FontSize; } Pa26TestFont;
    typedef struct { unsigned short* Data; } Pa26TestRanges;
    typedef struct {
        Pa26TestVec2 DisplaySize, MousePos;
        bool MouseDown[5];
        bool KeysDown[512];
        bool KeyCtrl, KeyAlt, KeyShift, KeySuper;
        float MouseWheel, MouseWheelH;
        bool queuedCharacters;
        bool WantTextInput;
        bool WantCaptureKeyboard;
        bool ConfigWindowsResizeFromEdges;
        int BackendFlags;
        Pa26TestVec2 MouseDelta;
        Pa26TestFontAtlas* Fonts;
        void* FontDefault;
    } Pa26TestIO;
    typedef struct ImGuiInputTextCallbackData {
        int EventFlag, Flags;
        void* UserData;
        unsigned short EventChar;
        int EventKey;
        char* Buf;
        int BufTextLen, BufSize;
        bool BufDirty;
        int CursorPos, SelectionStart, SelectionEnd;
    } ImGuiInputTextCallbackData;
    typedef int (*ImGuiInputTextCallback)(ImGuiInputTextCallbackData* data);
]]
local function callbackText(data,text)
    check(#text<data.BufSize); ffi.fill(data.Buf,data.BufSize); ffi.copy(data.Buf,text,#text)
    data.BufTextLen=#text; data.BufDirty=true
end
ffi.metatype('ImGuiInputTextCallbackData',{__index={
    DeleteChars=function(data,pos,count)
        local text=ffi.string(data.Buf,data.BufTextLen)
        check(pos>=0 and count>=0 and pos+count<=#text)
        callbackText(data,text:sub(1,pos)..text:sub(pos+count+1))
        data.CursorPos=pos; data.SelectionStart=pos; data.SelectionEnd=pos
    end,
    InsertChars=function(data,pos,token)
        local text=ffi.string(data.Buf,data.BufTextLen)
        check(pos>=0 and pos<=#text)
        callbackText(data,text:sub(1,pos)..token..text:sub(pos+1))
        data.CursorPos=pos+#token; data.SelectionStart=data.CursorPos; data.SelectionEnd=data.CursorPos
    end,
}})
ffi.metatype('Pa26TestIO', {__index={
    ClearInputCharacters=function(io) io.queuedCharacters=false end,
}})
local fontPool = {}
local ranges = ffi.new('unsigned short[3]', {0x20, 0x4ff, 0})
ffi.metatype('Pa26TestFont', {__index = {
    CalcTextSizeA = function(_, size, _, wrap, value)
        check(core.validUtf8(value))
        local lines,x,width=1,0,0
        for glyph in value:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
            if glyph=='\n' then width=math.max(width,x); x=0; lines=lines+1
            else
                if wrap>0 and x>0 and x+size*.5>wrap then width=math.max(width,x); x=0; lines=lines+1 end
                x=x+size*.5
            end
        end
        return {x=math.max(width,x),y=lines*size}
    end,
}})
ffi.metatype('Pa26TestFontAtlas', {__index = {
    GetGlyphRangesCyrillic = function() return ranges end,
    AddFontFromFileTTF = function(_, path, size)
        check(size == 14 or size == 15 or size == 16 or size == 18 or size == 20 or size == 24 or size == 32)
        local font = ffi.new('Pa26TestFont[1]')
        font[0].FontSize=size
        fontPool[#fontPool + 1] = font
        return ffi.cast('Pa26TestFont*', font)
    end,
}})

local function fixture(options)
    options = options or {}
    local s = {now = 10000, connected = true, chat = false, dialog = false, cursor = false,
        console = false, paused = false, spawned = true, localExists = true, localDead = false,
        aimed = true, targetExists = true, targetDead = false, onScreen = true, streamed = true,
        clear = true, vehicle = false, id = 37, name = 'Player_Name', mappedPed = 99, distance = 5,
        sent = {}, logs = {}, commands = {}, frames = {}, scopes = {}, consumed = 0,
        drawnText = {}, charLookups = 0, tab = 'Действия', press = {}, down = {}, address = '127.0.0.1',
        available = options.available ~= false, waits = {}, renderEnabled = options.render ~= false,health=100,weapon=0,
        rendererContext = false, initialized = false, invalidIOReads = 0, ioReads = 0,
        controlLocked = options.externalLocked == true, ownedLock = false, lockRequests = 0,
        serverKeys = {}, messageConsumed = false, inputActive = false,
        colorConversions = 0, circlesDrawn = 0}
    s.files={}; s.localChat={}; s.events={onSendChat=options.sendChatHandler,onSendTakeDamage=options.damageHandler,
        onSendSpawn=options.spawnHandler,onSendBulletSync=options.bulletHandler,onSendCommand=options.sendCommandHandler,onSendAimSync=options.aimHandler,
        onServerMessage=options.serverMessageHandler}
    -- Historical UI tests inspect the persisted model through all three real
    -- documents. No virtual monolithic file is provided to the running script.
    s.savedLibrary=function()
        local base='moonloader\\config\\police_assistant_2026'
        if not s.files[base..'_settings.json']then return TEST_JSON_DECODE(assert(s.files[base..'_library.json']))end
        local value=TEST_JSON_DECODE(assert(s.files[base..'_settings.json'])).data
        local binds=TEST_JSON_DECODE(assert(s.files[base..'_binds.json']))
        local notes=TEST_JSON_DECODE(assert(s.files[base..'_notes.json']))
        value.bindings=binds.bindings;value.next_id=binds.next_id;value.wheel=binds.wheel
        value.notes=notes.notes;value.next_note_id=notes.next_note_id
        return value
    end
    s.savedBytes=function()
        local out={};local base='moonloader\\config\\police_assistant_2026'
        for _,kind in ipairs({'binds','notes','settings'})do out[#out+1]=s.files[base..'_'..kind..'.json']or'<missing>'end
        return table.concat(out,'\0')
    end
    if options.library then s.files['moonloader\\config\\police_assistant_2026_library.json']=TEST_JSON_ENCODE(options.library) end
    if options.journal then s.files['moonloader\\config\\police_assistant_2026_journal.json']=TEST_JSON_ENCODE(options.journal) end
    if options.operations then s.files['moonloader\\config\\police_assistant_2026_operations.json']=TEST_JSON_ENCODE(options.operations) end
    s.wrapValues={}; s.buttonCalls={}; s.floatStyles={}; s.triangleIcons=0
    s.windows={}; s.windowStack={}; s.drawnLabels={}; s.fontStack={}; s.paddingStack={}; s.padding={x=14,y=14}
    s.colorValues={}; s.styleColors={}; s.colorStack={}; s.childNames={}; s.modalCalls={}
    local function blockedByModal() return s.modalOpen and not s.inModal end
    package.loaded['samp.events']=nil
    package.preload['samp.events']=function()
        if options.sampEvents==false then error('SAMP.Lua unavailable') end
        return s.events
    end
    local memoryFs={
        exists=function(path) return s.files[path]~=nil end,
        read=function(path) return s.files[path] end,
        write=function(path,text) if s.libraryWriteFail then return nil,'injected library failure' end; s.files[path]=text; return true end,
        rename=function(a,b) if not s.files[a] or s.files[b] then return nil end; s.files[b]=s.files[a]; s.files[a]=nil; return true end,
        remove=function(path) s.files[path]=nil; return true end,
    }
    if TEST_KNOWLEDGE_JSON and options.knowledge~=false then
        s.files['moonloader\\resource\\pa26\\knowledge-base.json']=TEST_KNOWLEDGE_JSON
    end
    if TEST_KNOWLEDGE_POLICY_JSON then s.files['moonloader\\resource\\pa26\\knowledge-policy.json']=TEST_KNOWLEDGE_POLICY_JSON end
    local config = core.defaults()
    config.main.demo_mode = options.demo ~= false
    if options.widgetScale then config.widget.scale=options.widgetScale end
    local function log(line) s.logs[#s.logs + 1] = tostring(line) end
    print = log
    local new = {bool = function(v) return ffi.new('bool[1]', v == true) end,
        int = function(v) return ffi.new('int[1]', v or 0) end,
        float = function(v) return ffi.new('float[1]', v or 0) end}
    new.char = setmetatable({}, {__index = function(_, size) return ffi.typeof('char[' .. size .. ']') end})
    s.fonts = ffi.new('Pa26TestFontAtlas[1]')
    s.io = ffi.new('Pa26TestIO', {DisplaySize = {1280, 720}, MousePos = {727, 410},
        WantTextInput = false, Fonts = s.fonts,ConfigWindowsResizeFromEdges=true,BackendFlags=2})
    local function beginScope(name) s.scopes[#s.scopes + 1] = name end
    local function endScope(name)
        eq(s.scopes[#s.scopes], name, 'ImGui scope mismatch: ' .. name)
        table.remove(s.scopes)
    end
    local imgui = {new = new, Cond = {Always = 1, Appearing = 2, FirstUseEver = 4},
        DisableInput = false,
        WindowFlags = {NoDecoration = 1, NoMove = 2, NoSavedSettings = 4, NoBackground = 8},
        ImVec2 = function(x, y) return {x = x, y = y} end,
        ImVec4 = function(x, y, z, w) return ffi.new('Pa26TestVec4', x, y, z, w) end,
        GetIO = function()
            if not s.rendererContext then
                s.invalidIOReads = s.invalidIOReads + 1
                error('mimgui.GetIO called without renderer context', 2)
            end
            s.ioReads = s.ioReads + 1
            return s.io
        end,
        GetColorU32 = function(index)
            check(type(index) == 'number', 'GetColorU32 expects a style index, not ImVec4')
            return 0
        end,
        ColorConvertFloat4ToU32 = function(color)
            check(ffi.istype('Pa26TestVec4', color), 'color conversion requires ImVec4')
            for _, channel in ipairs({color.x, color.y, color.z, color.w}) do
                check(channel >= 0 and channel <= 1, 'color channel outside range')
            end
            s.colorConversions = s.colorConversions + 1
            local function channel(v) return math.floor(v*255+.5) end
            local packed=channel(color.x)+channel(color.y)*256+channel(color.z)*65536+channel(color.w)*16777216
            s.colorValues[packed]={r=color.x,g=color.y,b=color.z,a=color.w}
            return packed
        end,
        OnInitialize = function(f)
            s.fontInit = f
            return {Unsubscribe = function() s.fontUnsubscribed = true end}
        end,
        CaptureKeyboardFromApp = function(value)
            check(s.rendererContext, 'capture override requires renderer context')
            check(type(value) == 'boolean')
            s.nextCapture = value
        end,
        OnFrame = function(condition, before, draw)
            local frame = {condition = condition, before = draw and before or nil,
                draw = draw or before, LockPlayer = false, HideCursor = false}
            frame.Unsubscribe = function() frame.removed = true end
            s.frames[#s.frames + 1] = frame
            return frame
        end,
        SetNextWindowPos = function(pos,cond,pivot) s.nextWindowPos={pos=pos,cond=cond,pivot=pivot} end,
        SetNextWindowSize = function(size,cond)
            check(size.x > 0 and size.y > 0)
            check(size.x <= s.io.DisplaySize.x and size.y <= s.io.DisplaySize.y)
            s.nextWindowSize={size=size,cond=cond}
        end,
        Begin = function(name, _, flags)
            local window=s.windows[name]; local fresh=not window
            window=window or {width=1040,height=700,x=10,y=10}; window.flags=flags; window.name=name
            if s.nextWindowSize and (s.nextWindowSize.cond==1 or fresh) then
                window.width,window.height=s.nextWindowSize.size.x,s.nextWindowSize.size.y
            end
            if s.resizeWindows and s.resizeWindows[name] then
                window.width,window.height=s.resizeWindows[name].x,s.resizeWindows[name].y; s.resizeWindows[name]=nil
            end
            if s.nextConstraints then
                window.width=math.max(s.nextConstraints.min.x,math.min(s.nextConstraints.max.x,window.width))
                window.height=math.max(s.nextConstraints.min.y,math.min(s.nextConstraints.max.y,window.height))
            end
            if s.nextWindowPos and (s.nextWindowPos.cond==1 or fresh) then
                local pivot=s.nextWindowPos.pivot or {x=0,y=0}
                window.x=s.nextWindowPos.pos.x-window.width*pivot.x; window.y=s.nextWindowPos.pos.y-window.height*pivot.y
            end
            s.nextWindowSize=nil; s.nextWindowPos=nil; s.nextConstraints=nil
            s.windowStack[#s.windowStack+1]={area=s.area,window=s.currentWindow}
            s.currentWindow=window; s.windows[name]=window; s.area={x=window.width,y=window.height}
            s.mainFlags=flags; beginScope('window'); return not s.collapsed
        end,
        End = function()
            endScope('window'); local previous=table.remove(s.windowStack)
            s.area=previous.area; s.currentWindow=previous.window
        end,
        PushTextWrapPos = function(value) s.wrapValues[#s.wrapValues+1]=value; beginScope('wrap') end,
        PopTextWrapPos = function() endScope('wrap') end,
        TextUnformatted = function(value) s.drawnText[#s.drawnText + 1] = value end,
        BeginTabBar = function() beginScope('tabs'); return true end,
        EndTabBar = function() endScope('tabs') end,
        BeginTabItem = function(name)
            if s.tab == name then beginScope('tab'); return true end
            return false
        end,
        EndTabItem = function() endScope('tab') end,
        PushItemWidth = function() beginScope('width') end,
        PopItemWidth = function() endScope('width') end,
        InputText = function(label, buffer, size, flags, callback)
            eq(size, ffi.sizeof(buffer))
            if blockedByModal() then return false end
            if s.widgetError then error('injected widget failure') end
            s.lastItemLabel=label
            local changed=false
            local editKey=s.edits and (s.edits[label] and label or label:sub(1,2)=='##' and s.edits[label:sub(3)] and label:sub(3))
            if editKey then
                local value = s.edits[editKey]
                check(#value < size)
                ffi.fill(buffer, size); ffi.copy(buffer, value, #value)
                s.edits[editKey]=nil
                changed=true; if callback then s.activeInputLabel=label end
            end
            local focus=s.focusInput and s.focusInput.label==label and s.focusInput or nil
            if s.focusNext or focus then s.activeInputLabel=label; s.focusNext=false end
            if callback and s.activeInputLabel==label then
                eq(flags,256); check(ffi.istype('ImGuiInputTextCallback',callback))
                local text=ffi.string(buffer)
                s.nativeCarets=s.nativeCarets or {}
                local caret=focus or (not changed and s.nativeCarets[label]) or {cursor=#text,first=#text,last=#text}
                local data=ffi.new('ImGuiInputTextCallbackData[1]')
                data[0].EventFlag=256; data[0].Flags=flags; data[0].Buf=buffer
                data[0].BufTextLen=#text; data[0].BufSize=size
                data[0].CursorPos=caret.cursor; data[0].SelectionStart=caret.first or caret.cursor; data[0].SelectionEnd=caret.last or caret.cursor
                eq(callback(data),0)
                s.nativeCarets[label]={cursor=data[0].CursorPos,first=data[0].SelectionStart,last=data[0].SelectionEnd}
                if data[0].BufDirty then changed=true end
                if focus then s.focusInput=nil end
            end
            return changed
        end,
        Checkbox = function(label, buffer)
            if blockedByModal() then return false end
            if s.toggle == label then s.toggle = nil; buffer[0] = not buffer[0]; return true end
            return false
        end,
        Button = function(label,size)
            s.lastItemLabel=label
            s.buttonCalls[#s.buttonCalls+1]={label=label,width=size and size.x or 0,height=size and size.y or 0,
                parent=s.childNames[#s.childNames],window=s.currentWindow and s.currentWindow.name,
                color=s.styleColors[s.imgui.Col.Button],x=s.cursorX or 14,y=s.cursorY or 24}
            s.lastButtonSize=size
            if blockedByModal() then return false end
            if s.click == label then s.click = nil; s.activeInputLabel=nil; return true end
            return false
        end,
        SliderFloat = function() return false end, SliderInt = function() return false end,
        SameLine = function() end, Separator = function() end, SetCursorPos = function() end,
        SetWindowFontScale = function(scale) check(scale > 0) end,
        GetWindowDrawList = function() return {
            AddCircle = function(_, _, radius, color, segments, thickness)
                check(type(color) == 'number' and color >= 0 and color <= 0xFFFFFFFF)
                check(radius > 0 and segments > 0 and thickness > 0)
                s.circlesDrawn = s.circlesDrawn + 1
            end,
            AddCircleFilled = function(_, _, radius, color, segments)
                check(type(color) == 'number' and color >= 0 and color <= 0xFFFFFFFF)
                check(radius > 0 and segments > 0)
                s.circlesDrawn = s.circlesDrawn + 1
            end,
        } end,
    }

    local function renderer() check(s.rendererContext, 'UI call outside rendering') end
    s.imgui = imgui
    imgui.WindowFlags = {NoTitleBar=1,NoResize=2,NoMove=4,NoScrollbar=8,NoScrollWithMouse=16,
        NoCollapse=32,NoBackground=128,NoSavedSettings=256,NoMouseInputs=512,NoInputs=1024,NoDecoration=43,AlwaysUseWindowPadding=65536,NoFocusOnAppearing=4096}
    imgui.Col, imgui.StyleVar = {}, {}
    for i, key in ipairs({'WindowBg','ChildBg','Text','TextDisabled','Border','FrameBg','FrameBgHovered',
        'FrameBgActive','Button','ButtonHovered','ButtonActive','Header','HeaderHovered','HeaderActive','CheckMark',
        'PopupBg','ModalWindowDimBg'}) do imgui.Col[key]=i end
    for i, key in ipairs({'WindowRounding','FrameRounding','ChildRounding','WindowBorderSize','WindowPadding','FramePadding','ItemSpacing','ButtonTextAlign'}) do imgui.StyleVar[key]=i end
    imgui.DrawCornerFlags = {TopLeft=1,TopRight=2,All=15}
    imgui.ImVec2 = function(x,y) return ffi.new('Pa26TestVec2', x,y) end
    imgui.ImFontGlyphRangesBuilder = function() return {
        AddRanges = function(_, value) check(type(value)=='cdata') end,
        AddText = function(_, value) check(core.validUtf8(value));s.fontGlyphText=(s.fontGlyphText or '')..value end,
        BuildRanges = function(_, value) value[0].Data=ranges end,
    } end
    imgui.ImVector_ImWchar = function() return ffi.new('Pa26TestRanges[1]') end
    imgui.PushFont = function(font) renderer(); s.fontStack[#s.fontStack+1]=font; beginScope('font') end
    imgui.PopFont = function() endScope('font'); table.remove(s.fontStack) end
    imgui.GetFont = function() renderer(); return s.fontStack[#s.fontStack] or ffi.cast('Pa26TestFont*',s.io.FontDefault~=nil and s.io.FontDefault or fontPool[#fontPool]) end
    imgui.GetFontSize = function() return tonumber(imgui.GetFont().FontSize) end
    imgui.PushStyleColor = function(index, value)
        renderer(); check(type(index)=='number'); check(ffi.istype('Pa26TestVec4',value)); beginScope('color')
        s.colorStack[#s.colorStack+1]={index=index,previous=s.styleColors[index]}
        s.styleColors[index]={r=value.x,g=value.y,b=value.z,a=value.w}
    end
    imgui.PopStyleColor = function(count) for _=1,(count or 1) do
        endScope('color'); local previous=table.remove(s.colorStack); s.styleColors[previous.index]=previous.previous
    end end
    imgui.PushStyleVarFloat = function(index, value) renderer(); check(type(index)=='number' and type(value)=='number'); s.floatStyles[#s.floatStyles+1]={index=index,value=value}; beginScope('style') end
    s.styleKinds={}
    local pushFloat=imgui.PushStyleVarFloat
    imgui.PushStyleVarFloat=function(index,value) pushFloat(index,value); s.styleKinds[#s.styleKinds+1]=false end
    imgui.PushStyleVarVec2 = function(index, value)
        renderer(); check(type(index)=='number' and ffi.istype('Pa26TestVec2',value)); beginScope('style')
        local padding=index==imgui.StyleVar.WindowPadding; s.styleKinds[#s.styleKinds+1]=padding
        if padding then s.paddingStack[#s.paddingStack+1]=s.padding; s.padding={x=value.x,y=value.y} end
    end
    imgui.PopStyleVar = function(count) for _=1,(count or 1) do
        endScope('style'); if table.remove(s.styleKinds) then s.padding=table.remove(s.paddingStack) end
    end end
    s.childAreas, s.childCalls = {}, {}
    s.area = {x=1040,y=700}
    imgui.SetNextWindowSizeConstraints=function(first,last)
        renderer(); check(first.x>0 and first.y>0 and last.x>=first.x and last.y>=first.y)
        s.nextConstraints={min=first,max=last}
    end
    imgui.SetWindowSizeVec2=function(size)
        renderer(); s.currentWindow.width,s.currentWindow.height=size.x,size.y; s.area={x=size.x,y=size.y}
    end
    imgui.SetWindowPosVec2=function(pos) renderer(); s.currentWindow.x,s.currentWindow.y=pos.x,pos.y end
    imgui.BeginChild = function(name,size,border,flags)
        renderer(); check(type(name)=='string' and type(flags)=='number'); beginScope('child')
        s.childCalls[#s.childCalls+1]={name=name,border=border,flags=flags,width=size.x,height=size.y,padding=s.padding,
            parent=s.childNames[#s.childNames],window=s.currentWindow and s.currentWindow.name}
        s.childNames[#s.childNames+1]=name
        s.childAreas[#s.childAreas+1]=s.area
        s.area={x=size.x>0 and size.x or s.area.x-s.padding.x*2,y=size.y>0 and size.y or s.area.y-s.padding.y*2}
        return not s.hideChild
    end
    imgui.EndChild = function() endScope('child'); s.area=table.remove(s.childAreas); table.remove(s.childNames) end
    imgui.GetContentRegionAvail = function() renderer(); return imgui.ImVec2(math.max(1,s.area.x-s.padding.x*2),math.max(1,s.area.y-s.padding.y*2)) end
    imgui.GetWindowSize = function() renderer(); return imgui.ImVec2(s.area.x,s.area.y) end
    imgui.GetWindowPos = function() renderer(); return imgui.ImVec2(s.currentWindow and s.currentWindow.x or 10,s.currentWindow and s.currentWindow.y or 10) end
    imgui.GetCursorPos = function() renderer(); return imgui.ImVec2(0,0) end
    imgui.GetCursorPosX = function() renderer(); return s.cursorX or 14 end
    imgui.SetCursorPosX = function(value) renderer(); s.cursorX=value end
    imgui.GetCursorScreenPos = function() renderer(); return imgui.ImVec2(s.cursorX or 14,s.cursorY or 24) end
    imgui.SetCursorScreenPos = function(pos) renderer(); s.cursorX,s.cursorY=pos.x,pos.y end
    imgui.GetItemRectMin = function() renderer(); return imgui.ImVec2(s.cursorX or 14,s.cursorY or 24) end
    imgui.GetItemRectMax = function() renderer(); check(s.lastButtonSize~=nil); return imgui.ImVec2((s.cursorX or 14)+s.lastButtonSize.x,(s.cursorY or 24)+s.lastButtonSize.y) end
    imgui.CalcTextSize = function(value) renderer(); return imgui.ImVec2(select(2,value:gsub('[^\128-\191]',''))*8,18) end
    imgui.Dummy = function(size) renderer(); check(core.finite(size.x) and core.finite(size.y)) end
    imgui.Columns = function(count)
        renderer(); if count==1 then endScope('columns') else check(count>=2 and count<=32 and count==math.floor(count)); beginScope('columns') end
    end
    imgui.SetColumnWidth = function(_,width) check(width>0) end
    imgui.NextColumn = function() renderer() end
    imgui.CollapsingHeader=function(label)
        renderer();s.openHeaders=s.openHeaders or{}
        if s.click==label then s.click=nil;s.openHeaders[label]=not s.openHeaders[label]end
        return s.openHeaders[label]==true
    end
    imgui.SetScrollY=function(value)renderer();check(value==0);s.scrollResets=(s.scrollResets or 0)+1 end
    imgui.CaptureMouseFromApp = function(value) renderer(); check(type(value)=='boolean'); s.captureMouse=value end
    imgui.InputTextFlags={CallbackAlways=256,ReadOnly=16384}
    imgui.SetKeyboardFocusHere=function(offset) renderer(); check(offset==nil or offset==0); s.focusNext=true end
    s.multilineCalls={}
    imgui.InputTextMultiline=function(label,buffer,size,dimensions,flags,callback)
        renderer(); check(dimensions.y>0)
        local changed=imgui.InputText(label,buffer,size,flags,callback)
        s.multilineCalls[#s.multilineCalls+1]={label=label,size=size,height=dimensions.y,flags=flags,text=ffi.string(buffer)}
        return changed
    end
    imgui.InputInt=function(label,value)
        renderer()
        if blockedByModal() then return false end
        if s.intEdits and s.intEdits[label]~=nil then value[0]=s.intEdits[label]; s.intEdits[label]=nil; return true end
        return false
    end
    imgui.SliderFloat=function(label,value,minimum,maximum)
        renderer();if blockedByModal()then return false end
        if s.floatEdits and s.floatEdits[label]~=nil then
            value[0]=math.max(minimum,math.min(maximum,s.floatEdits[label]));s.floatEdits[label]=nil;return true
        end
        return false
    end
    imgui.Selectable=function(label) renderer(); s.lastItemLabel=label; if blockedByModal() then return false end; if s.click==label then s.click=nil; s.activeInputLabel=nil; return true end; return false end
    imgui.IsItemHovered=function() renderer(); return s.hover==s.lastItemLabel end
    imgui.IsItemActive=function() renderer(); return s.activeItem==s.lastItemLabel end
    imgui.InvisibleButton=function(label,size) return imgui.Button(label,size) end
    imgui.MouseCursor={ResizeNS=3,ResizeEW=4,ResizeNESW=5,ResizeNWSE=6}
    imgui.SetMouseCursor=function(shape) renderer(); check(type(shape)=='number'); s.cursorShape=shape end
    s.tooltipCalls={};s.tooltipCursors={}
    imgui.BeginTooltip=function()
        renderer();beginScope('tooltip')
        s.tooltipCursors[#s.tooltipCursors+1]={x=s.cursorX,y=s.cursorY}
        s.cursorX,s.cursorY=s.padding.x,s.padding.y
        s.tooltipCalls[#s.tooltipCalls+1]={constraints=s.nextConstraints,padding={x=s.padding.x,y=s.padding.y}}
        s.nextConstraints=nil
    end
    imgui.EndTooltip=function()
        local cursor=assert(table.remove(s.tooltipCursors));s.cursorX,s.cursorY=cursor.x,cursor.y
        endScope('tooltip')
    end
    imgui.OpenPopup=function(id)
        renderer();s.popup=id
        if id=='Подтверждение##pa26-confirm'or id=='Обновление базы##pa26-knowledge-confirm'then s.modalOpen=true end
    end
    imgui.BeginPopup=function(id) renderer(); if s.popup==id then beginScope('popup'); return true end; return false end
    imgui.BeginPopupModal=function(id,_,flags)
        renderer()
        if s.popup~=id then s.nextWindowPos=nil; s.nextWindowSize=nil; return false end
        local parent=s.currentWindow and s.currentWindow.name
        eq(#s.childNames,0,'modal must be drawn at the parent root, outside scrolling panes')
        imgui.Begin(id,nil,flags); endScope('window'); beginScope('popup'); s.inModal=true
        local w=s.currentWindow
        s.modalCalls[#s.modalCalls+1]={parent=parent,x=w.x,y=w.y,width=w.width,height=w.height,flags=flags,
            background=s.styleColors[imgui.Col.PopupBg]}
        return true
    end
    imgui.EndPopup=function()
        endScope('popup')
        if s.inModal then
            local previous=table.remove(s.windowStack); s.area=previous.area; s.currentWindow=previous.window; s.inModal=false
        end
    end
    imgui.CloseCurrentPopup=function() renderer(); s.popup=nil; s.modalOpen=false end
    imgui.BeginCombo=function(label) renderer(); if blockedByModal() then return false end; if s.combo==label then beginScope('combo'); return true end; return false end
    imgui.EndCombo=function() endScope('combo') end
    imgui.IsMouseClicked = function(button) renderer(); return s.mouseClicks and s.mouseClicks[button]==true or false end
    s.textures, s.textureLoads, s.textureReleases, s.imageDraws = {},0,0,{}
    imgui.CreateTextureFromFile = function(path)
        renderer(); s.textureLoads=s.textureLoads+1
        if s.textureFail then return nil end
        local tex=ffi.cast('void*',s.textureLoads)
        s.textures[tostring(tex)]=true
        return tex
    end
    imgui.ReleaseTexture = function(tex)
        check(s.textures[tostring(tex)]==true,'double release or invalid texture')
        s.textures[tostring(tex)]=false; s.textureReleases=s.textureReleases+1
    end
    local list = imgui.GetWindowDrawList()
    list.Flags=3
    local function vector(v) check(ffi.istype('Pa26TestVec2',v)); check(core.finite(v.x) and core.finite(v.y)) end
    local function packed(c) check(type(c)=='number' and c>=0 and c<=0xFFFFFFFF) end
    list.AddRectFilled = function(_,a,b,c) renderer(); vector(a); vector(b); packed(c) end
    list.AddRect = function(_,a,b,c) renderer(); vector(a); vector(b); packed(c); if s.rectError and #s.imageDraws>0 then error('injected image border error') end end
    list.AddLine = function(_,a,b,c) renderer(); vector(a); vector(b); packed(c) end
    list.AddTriangleFilled = function(_,a,b,c,tint) renderer(); vector(a); vector(b); vector(c); packed(tint); s.triangleIcons=s.triangleIcons+1 end
    list.AddRectFilledMultiColor = function(_,a,b,c,d,e,f) renderer(); vector(a); vector(b); packed(c); packed(d); packed(e); packed(f) end
    list.AddText = function(_,p,c,value) renderer(); vector(p); packed(c); check(core.validUtf8(value)) end
    list.AddTextFontPtr = function(_,font,size,p,c,value,_,wrap)
        renderer(); vector(p); packed(c); check(core.validUtf8(value)); s.drawnText[#s.drawnText+1]=value
        s.drawnLabels[#s.drawnLabels+1]={text=value,wrap=wrap or 0,size=size,width=s.area.x,height=s.area.y,
            x=p.x,y=p.y,color=s.colorValues[c],measure=font:CalcTextSizeA(size,100000,wrap or 0,value),
            item=s.lastItemLabel,parent=s.childNames[#s.childNames]}
    end
    list.AddImageRounded = function(_,tex,a,b,uv0,uv1,c,rounding)
        renderer(); check(s.textures[tostring(tex)]==true); vector(a); vector(b); vector(uv0); vector(uv1); packed(c)
        s.imageDraws[#s.imageDraws+1]={w=b.x-a.x,h=b.y-a.y,tex=tex}
    end
    s.pathFills=0
    list.PathClear=function() renderer(); s.pathPoints=0 end
    list.PathLineTo=function(_,point) renderer(); vector(point); s.pathPoints=(s.pathPoints or 0)+1 end
    list.PathArcTo=function(_,point,radius,first,last,segments)
        renderer(); vector(point); check(radius>0 and core.finite(first) and core.finite(last))
        check(last>first and last-first<=math.pi); check(segments>=3)
        s.pathPoints=(s.pathPoints or 0)+segments+1
    end
    list.PathFillConvex=function(_,tint)
        renderer(); packed(tint); check((s.pathPoints or 0)>=3)
        if s.pathDrawError then error('injected wheel drawing failure') end
        s.pathFills=s.pathFills+1; s.pathPoints=0
    end
    imgui.Image = function(tex,size) renderer(); check(s.textures[tostring(tex)]==true); vector(size) end
    imgui.GetWindowDrawList = function() renderer(); return list end
    s.drawList=list
    imgui.GetForegroundDrawList = function()
        if s.hudDrawError then error('injected HUD rendering failure') end
        return imgui.GetWindowDrawList()
    end

    package.loaded.mimgui, package.loaded.encoding, package.loaded.pa26_config = nil, nil, nil
    package.loaded.pa26_library,package.loaded.pa26_workspace,package.loaded.pa26_user_files=nil,nil,nil
    package.loaded.pa26_patrol_session,package.loaded.pa26_patrol_events=nil,nil
    package.loaded.pa26_operations=nil
    package.loaded.pa26_knowledge,package.loaded.pa26_knowledge_ui=nil,nil
    package.loaded.pa26_knowledge_edits,package.loaded.pa26_knowledge_editor_ui=nil,nil
    package.preload.mimgui = function()
        if options.missingLibrary then error('missing mimgui') end
        return imgui
    end
    local enc = {default = 'DO_NOT_CHANGE', CP1251 = {
        encode = function(_, value, from) eq(from, 'UTF-8'); return codec.encode(value) end,
        decode = function(_, value, to) eq(to, 'UTF-8'); return codec.decode(value) end,
    }}
    package.preload.encoding = function() return enc end
    package.preload.pa26_config = function() return {
        fs=memoryFs,
        load = function() return config, {} end,
        save = function(_, value)
            if s.saveFail then return nil, 'injected disk failure' end
            s.saved = value
            return true
        end,
    } end
    package.preload.pa26_library=function() local value=dofile('moonloader/lib/pa26_library.lua'); value.fs=memoryFs; return value end
    package.preload.pa26_knowledge_ui=function()
        local value=dofile('moonloader/lib/pa26_knowledge_ui.lua');local original=value.new
        value.new=function(...)local v=original(...);s.knowledgeUi=v;return v end
        return value
    end
    package.loaded.pa26_chat_bridge=nil
    package.preload.pa26_chat_bridge=function()
        local value=dofile('moonloader/lib/pa26_chat_bridge.lua')
        local original=value.new
        value.new=function(env)
            -- Never touch the real launcher from a simulated game host.
            env.assetFs=options.cefAssets or {read=function()return nil end}
            local instance=original(env);s.chatBridge=instance;return instance
        end
        return value
    end
    package.loaded.pa26_input=nil
    package.preload.pa26_input=function()
        local value=dofile('moonloader/lib/pa26_input.lua')
        return {new=function()return value.new(function(key)
            local physical=s.physicalDown or s.guiDown or s.down
            return (physical[key]==true or not s.physicalDown and not s.guiDown and s.press[key]==true)and -32768 or 0
        end)end}
    end
    encodeJson=function(value) return TEST_JSON_ENCODE(value) end
    decodeJson=function(value) return TEST_JSON_DECODE(value) end
    script_name, script_author, script_version, script_description = function() end, function() end, function() end, function() end
    script_properties = function(property) eq(property, 'work-in-pause'); s.workInPause = true end
    isSampAvailable = function() return s.available end
    if options.missingAvailability then isSampAvailable = nil end
    sampGetGamestate = function()
        if s.stateError then error('injected game state API failure') end
        return s.connected and 3 or 5
    end
    sampGetCurrentServerAddress = function() return s.address, 7777 end
    sampRegisterChatCommand = function(name, callback) s.commands[name] = callback; return true end
    sampUnregisterChatCommand = function(name) s.commands[name] = nil end
    getWorkingDirectory = function() return 'moonloader' end
    -- Runtime health is isolated just like the fixture's other filesystem data.
    package.loaded.pa26_startup={
        clear=function()s.startupState=nil end,
        block=function(_,message)s.startupState='blocked';s.startupMessage=message;return true end,
        ready=function()s.startupState='ready';return true end,
        read=function()return s.startupState,s.startupMessage end,
        announce=function(message)s.logs[#s.logs+1]=message;return true end,
    }

    doesFileExist = function() return true end
    getFolderPath = function() return 'C:/Windows/Fonts' end
    getCursorPos = function() return s.mx or s.io.MousePos.x, s.my or s.io.MousePos.y end
    convertWindowScreenCoordsToGameScreenCoords = function(x,y) return x*640/s.io.DisplaySize.x,y*448/s.io.DisplaySize.y end
    sampGetPlayerPing = function() return s.ping or 40 end
    getCharActiveInterior=function(ped)
        if ped==PLAYER_PED then return s.localInterior or 0 end
        local actor=s.actors and s.actors[ped]
        return actor and actor.interior or s.remoteInterior or 0
    end
    getNameOfZone = function() return s.zoneKey or 'EBE' end
    getGxtText = function() return 'East Beach' end
    getTimeOfDay = function() return 15,30 end
    getGameTimer = function() return s.now end
    getCharHealth=function(ped)check(not s.rendererContext,'health API read in renderer');eq(ped,PLAYER_PED);if s.healthError then error('health unavailable')end;return s.health end
    getCurrentCharWeapon=function(ped)check(not s.rendererContext,'weapon API read in renderer');return ped==PLAYER_PED and s.weapon or 24 end
    sampIsChatInputActive = function() return s.chat end
    sampGetChatInputText=function()check(not s.rendererContext,'chat read in renderer');if s.chatReadError then error('chat input unavailable')end;return s.chatText or ''end
    sampSetChatInputText=function(value)check(not s.rendererContext,'chat write in renderer');if s.chatWriteError then return false end;s.chatText=value;s.chatWrites=(s.chatWrites or 0)+1 end
    if options.chatInputBackend==false then sampGetChatInputText=nil;sampSetChatInputText=nil end
    if options.missingApi then sampIsChatInputActive = nil end
    -- Do not create isSampChatInputActive: the old typo must fail this test.
    isSampChatInputActive = nil
    sampIsDialogActive = function() return s.dialog end
    sampIsCursorActive = function() return s.cursor end
    isSampfuncsConsoleActive = function() return s.console end
    isGamePaused = function() return s.paused end
    sampIsLocalPlayerSpawned = function() return s.spawned end
    PLAYER_HANDLE, PLAYER_PED = 0, 1
    doesCharExist = function(ped)
        if ped==1 then return s.localExists end
        local a=s.actors and s.actors[ped]
        if a then return a.exists~=false end
        return ped==99 and s.targetExists or false
    end
    isCharDead = function(ped) if ped == 1 then return s.localDead end; local a=s.actors and s.actors[ped]; return a and a.dead==true or s.targetDead end
    isCharInAnyCar = function(ped) local a=s.actors and s.actors[ped]; return a and a.vehicle==true or s.vehicle end
    isCharOnScreen = function(ped) local a=s.actors and s.actors[ped]; if a then return a.onScreen~=false end; return s.onScreen end
    local function actorById(id)
        for ped,a in pairs(s.actors or {}) do if a.id==id then return a,ped end end
    end
    sampIsPlayerConnected = function(id)
        if s.identityError then error('injected player identity failure') end
        if s.targetConnected==false then return false end
        local a=actorById(id); return not a or a.connected~=false
    end
    sampIsPlayerNpc = function(id) local a=actorById(id); return a and a.npc==true or s.npc==true end
    getCharPlayerIsTargeting = function() return s.aimed, s.aimedPed or 99 end
    isButtonPressed=function(pad,key)
        check(not s.rendererContext,'game aim control read in renderer');eq(pad,0);eq(key,6)
        return s.aimControl==true
    end
    if options.aimControlApi==false then isButtonPressed=nil end
    s.identityReads,s.remoteIdentityReads=0,0
    sampGetPlayerIdByCharHandle = function(ped)
        s.identityReads=s.identityReads+1
        if ped~=1 then s.remoteIdentityReads=s.remoteIdentityReads+1 end
        local a=s.actors and s.actors[ped]
        if a then return a.mapped~=false,a.id end
        if ped==1 or ped==99 then return true,s.id end
        return false,-1
    end
    sampGetCharHandleBySampPlayerId = function(id)
        check(core.validId(id), 'invalid ID must not reach SA:MP')
        s.charLookups = s.charLookups + 1
        local a,ped=actorById(id)
        if a then return a.streamed~=false,a.mappedPed or ped end
        return s.streamed, s.mappedPed
    end
    sampGetPlayerNickname = function(id) local a=actorById(id); return a and a.name or s.name end
    getCharCoordinates = function(ped)
        if s.coordsError then error('injected coordinate API failure') end
        if ped == 1 then return 0, 0, 0 end
        local a=s.actors and s.actors[ped]
        if a then return a.x,a.y,a.z end
        return 0, s.distance, 0
    end
    getActiveCameraCoordinates = function() return 0, 0, 1 end
    getScreenResolution=function() return s.io.DisplaySize.x,s.io.DisplaySize.y end
    s.poolReads=0
    getAllChars=function()
        s.poolReads=s.poolReads+1
        if s.poolError then error('injected ped-pool failure') end
        if s.invalidPool then return false end
        return s.pool or {1,99}
    end
    convert3DCoordsToScreenEx=function(x,y,z,checkMin,checkMax)
        check(checkMin==true and checkMax==true)
        if s.projectionError then error('injected projection failure') end
        for _,a in pairs(s.actors or {}) do
            if a.x==x and a.y==y and z>=a.z-.26 and z<=a.z+.81 then return a.projected~=false,a.sx,a.sy end
        end
        if s.torsoOnly and math.abs(z-.8)<.01 then return true,100,100 end
        return s.projected~=false,s.sx or s.io.DisplaySize.x/2,s.sy or s.io.DisplaySize.y/2
    end
    isLineOfSightClear = function(_, _, _, _, _, z, buildings, vehicles, actors, objects)
        check(buildings == true and actors == false and objects == true)
        if vehicles==false then return s.worldClear~=false end
        check(vehicles==true)
        if s.glass or (s.upperBlocked and math.abs(z-.8)<.01) then return false end
        return s.clear
    end
    getVehiclePointerHandle=function(pointer)return pointer end
    storeCarCharIsInNoSave=function(ped)return ped==PLAYER_PED and(s.ownCarHandle or 51)or(s.targetCarHandle or 50)end
    s.transparentReads=0
    processLineOfSight = function(_, _, _, _, _, _, buildings, vehicles, actors, objects, particles, seeThrough, ignoreObjects, shootThrough)
        check(buildings==true and vehicles==true and actors==false and objects==true and particles==true)
        check(seeThrough==true and ignoreObjects==false and shootThrough==false)
        s.transparentReads=s.transparentReads+1
        if s.traceError then error('injected transparent-surface trace error') end
        if s.traceNil then return nil end
        if s.collision then return true,{entityType=2,entity=s.collision}end
        return not s.clear
    end
    sampSendChat = function(value)
        if s.sendError then error('injected send failure') end
        local event=value:sub(1,1)=='/' and s.events.onSendCommand or s.events.onSendChat
        if type(event)=='function' then
            local replacement=event(value)
            if replacement==false then return end
            if type(replacement)=='table' then value=replacement[1] end
        end
        s.sent[#s.sent + 1] = {line = codec.decode(value), time = s.now}
    end
    sampAddChatMessage=function(value,color) check(color==-1); s.localChat[#s.localChat+1]=codec.decode(value) end
    local function keyboardConsumed()
        return options.consumeKeyboard==true and s.inputActive and not imgui.DisableInput and s.io.WantCaptureKeyboard
    end
    wasKeyPressed = function(key) return not keyboardConsumed() and s.press[key] == true end
    isKeyDown = function(key) return not keyboardConsumed() and s.down[key] == true end
    consumeWindowMessage = function(game, scripts)
        eq(game, true); eq(scripts, false)
        s.consumed = s.consumed + 1; s.messageConsumed = true
    end
    local scriptObject = {}
    thisScript = function() return scriptObject end
    wait = function(delay)
        check(delay == 0 or delay == 100)
        s.waits[#s.waits + 1] = delay
        coroutine.yield()
    end
    onWindowMessage, onScriptTerminate = nil, nil
    -- Historical wheel cases exercise the retained six-action mode explicitly.
    -- New hierarchical cases opt into production defaults with categoryWheel=true.
    local model=require 'pa26_bindings'; local seed=model.copy(options.library or model.defaults(config))
    -- Existing UI regressions exercise a configured large window and inline
    -- procedures. New geometry/detached cases opt into unmodified production
    -- defaults, just as categoryWheel does for the newer wheel controller.
    if not options.productionWindows then
        seed.settings.window_layout=require('pa26_window_layout').defaults()
        seed.settings.window_layout.initial_percent=95
        seed.settings.window_layout.remember=false
        seed.settings.window_layout.wanted_separate=false
    end
    if not options.categoryWheel then seed.settings.wheel_mode='classic' end
    if options.nearby==false then seed.nearby.enabled=false end
    if options.legacyWanted then
        local b=model.find(seed,3);b.enabled=true;b.script='/me '..core.defaults().wanted.me..'\n/do '..core.defaults().wanted.do_text..'\n/wanted {id}'
    end
    seed.alerts=seed.alerts or model.alertDefaults();seed.alerts.enabled=options.alerts==true
    if options.notifications~=true then seed.weapon_warning.enabled=false end
    s.files['moonloader\\config\\police_assistant_2026_library.json']=TEST_JSON_ENCODE(seed)
    -- Historical scenarios disable this new, independent overlay. Dedicated
    -- alerts scenarios opt into the actual production defaults and expose state.
    local alertsModule=require 'pa26_alerts';local originalAlertsNew=alertsModule.new
    alertsModule.new=function(...) local a=originalAlertsNew(...);s.alerts=a;return a end
    local taserModule=require 'pa26_taser';local originalTaserNew=taserModule.new
    taserModule.new=function(...)local a=originalTaserNew(...);s.taser=a;return a end
    local caseModule=require 'pa26_case_forms';local originalCaseNew=caseModule.new
    caseModule.new=function(...)local a=originalCaseNew(...);s.caseForms=a;return a end
    local identityModule=require 'pa26_identity';local originalIdentityNew=identityModule.new
    identityModule.new=function(...)local a=originalIdentityNew(...);s.identity=a;return a end
    local vehicleModule=require 'pa26_vehicle';local originalVehicleNew=vehicleModule.new
    vehicleModule.new=function(...)local a=originalVehicleNew(...);s.vehicleController=a;return a end
    local eventsModule=require 'pa26_patrol_events';local originalEventsNew=eventsModule.new
    eventsModule.new=function(...)local a=originalEventsNew(...);s.patrolEvents=a;return a end
    local sessionModule=require 'pa26_patrol_session';local originalSessionNew=sessionModule.new
    sessionModule.new=function(...)local a=originalSessionNew(...);s.patrolSession=a;return a end
    local patrolModule=require 'pa26_patrol';local originalPatrolNew=patrolModule.new
    patrolModule.new=function(...)local a=originalPatrolNew(...);s.patrol=a;return a end
    local weaponsModule=require 'pa26_weapons';local originalWeaponsNew=weaponsModule.new
    weaponsModule.new=function(...)local a=originalWeaponsNew(...);s.weapons=a;return a end
    local guardModule=require 'pa26_radio_guard';local originalGuardNew=guardModule.new
    guardModule.new=function(...)local a=originalGuardNew(...);s.radioGuard=a;return a end
    local warningModule=require 'pa26_weapon_warning';local originalWarningNew=warningModule.new
    warningModule.new=function(...)local a=originalWarningNew(...);s.weaponWarning=a;return a end
    local noticesModule=require 'pa26_notifications';local originalNoticesNew=noticesModule.new
    noticesModule.new=function(...)local a=originalNoticesNew(...);s.notifications=a;return a end
    local hudModule=require 'pa26_hud';local originalHudNew=hudModule.new
    hudModule.new=function(...)local a=originalHudNew(...);s.hud=a;return a end
    local workspaceModule=require 'pa26_workspace';local originalWorkspaceNew=workspaceModule.new
    workspaceModule.new=function(...)local a=originalWorkspaceNew(...);s.workspace=a;return a end
    local runtimeModule=require 'pa26_runtime'; local originalRuntimeNew=runtimeModule.new
    if options.categoryWheel then runtimeModule.new=function(...) local r=originalRuntimeNew(...);s.runtime=r;return r end end
    local evidenceModule=require 'pa26_evidence';local originalEvidenceNew=evidenceModule.new
    evidenceModule.new=function(...)local a=originalEvidenceNew(...);s.evidence=a;return a end
    local filesModule=require 'pa26_evidence_files';local originalFilesNew=filesModule.new
    filesModule.new=function()if options.evidenceFiles then return options.evidenceFiles(s)end;return{clock=function()return 1000000000 end,verify=function()return nil,'Fixture: no screenshot'end,scanScreens=function()return nil,'Fixture: no screenshot directory'end}end
    local cm=require 'pa26_copilot';local originalCopilot=cm.new
    cm.new=function(env)local c=originalCopilot(env);s.copilot=c;return c end
    local colleagues=require 'pa26_colleagues';local originalColleagues=colleagues.new
    colleagues.new=function(env)
        local get=env.settings
        if not options.copilot then env.settings=function()local c=require('pa26_bindings').copy(get());c.colleagues_enabled=false;return c end end
        local c=originalColleagues(env);s.colleagues=c;return c
    end
    local author=require 'pa26_author_controller';local originalAuthor=author.new
    author.new=function(env)
        if options.authorPresetIO then
            env.io=options.authorPresetIO;env.fs=memoryFs
            env.hash=function(text)local h=1;for i=1,#text do h=(h*31+text:byte(i))%2147483647 end;return string.format('%08x',h)..string.rep('0',56)end
            env.lock=function()return function()end end
            env.reload=function()s.reloads=(s.reloads or 0)+1 end
        end
        local c=originalAuthor(env);s.authorPresets=c;return c
    end
    dofile('moonloader/police_assistant_2026.lua')
    cm.new=originalCopilot;colleagues.new=originalColleagues
    author.new=originalAuthor
    evidenceModule.new=originalEvidenceNew;filesModule.new=originalFilesNew
    runtimeModule.new=originalRuntimeNew
    alertsModule.new=originalAlertsNew
    vehicleModule.new=originalVehicleNew
    caseModule.new=originalCaseNew;identityModule.new=originalIdentityNew;eventsModule.new=originalEventsNew;sessionModule.new=originalSessionNew;taserModule.new=originalTaserNew;patrolModule.new=originalPatrolNew;weaponsModule.new=originalWeaponsNew
    guardModule.new=originalGuardNew;warningModule.new=originalWarningNew;noticesModule.new=originalNoticesNew
    hudModule.new=originalHudNew;workspaceModule.new=originalWorkspaceNew
    check(s.workInPause)
    eq(enc.default, 'DO_NOT_CHANGE')
    local co = coroutine.create(main)
    check(coroutine.resume(co))
    function s.render()
        if not s.renderEnabled then return end
        local activeFrames, wantsLock = {}, false
        for _, f in ipairs(s.frames) do
            if not f.removed and f.condition() then
                activeFrames[#activeFrames + 1] = f
                wantsLock = wantsLock or f.LockPlayer == true
            end
        end
        s.inputActive = #activeFrames > 0
        -- mimgui's updater locks only when an active subscription requests it;
        -- it releases its own previous lock, leaving a server-owned lock alone.
        if wantsLock then
            s.controlLocked, s.ownedLock = true, true
            s.lockRequests = s.lockRequests + 1
        elseif s.ownedLock then s.controlLocked, s.ownedLock = false, false end
        if #activeFrames > 0 then
            s.rendererContext = true
            if not s.initialized then
                if s.fontInit then s.fontInit() end
                s.initialized = true
            end
            for _, f in ipairs(activeFrames) do if f.before then f.before() end end
            -- WindowMessage writes ImGuiIO before consumption. The game can see
            -- no keys while the GUI still sees the physical chord.
            local physical=s.guiDown
            for key=8,254 do s.io.KeysDown[key]=physical and physical[key]==true or
                (not physical and (s.down[key]==true or s.press[key]==true)) end
            s.io.KeyCtrl=s.io.KeysDown[17] or s.io.KeysDown[162] or s.io.KeysDown[163]
            s.io.KeyAlt=s.io.KeysDown[18] or s.io.KeysDown[164] or s.io.KeysDown[165]
            s.io.KeyShift=s.io.KeysDown[16] or s.io.KeysDown[160] or s.io.KeysDown[161]
            s.io.KeySuper=s.io.KeysDown[91] or s.io.KeysDown[92]
            -- Capture override is consumed by NewFrame. Without it a focused
            -- window may take keyboard events, even when no text is edited.
            s.io.WantCaptureKeyboard = s.nextCapture == nil or s.nextCapture
            s.nextCapture = nil
            local firstImage = #s.imageDraws + 1
            for _, f in ipairs(activeFrames) do f.draw() end
            for i=firstImage,#s.imageDraws do
                check(s.textures[tostring(s.imageDraws[i].tex)] == true,
                    'texture freed before renderer EndFrame')
            end
            s.rendererContext = false
        end
        eq(#s.scopes, 0)
        eq(s.invalidIOReads, 0)
    end
    function s.step(dt, press)
        s.now = s.now + (dt or 16)
        s.press = press or {}
        if coroutine.status(co) ~= 'dead' then
            local ok, failure = coroutine.resume(co)
            check(ok, tostring(failure))
        end
        s.render()
        s.press = {}
    end
    function s.page(key)
        s.render() -- floating windows may have been the last rendered surface
        for i,entry in ipairs(require('pa26_menu').sections) do
            if entry.key==key then
                local window=s.windows['Police Assistant 2026##pa26-main']
                local layout=require('pa26_menu').layout(window and window.width or s.area.x,window and window.height or s.area.y)
                local label=layout and layout.side<244 and entry.short or entry.label
                s.click=string.format('%02d',i)..'  '..label..'##nav'..key; s.render(); return
            end
        end
        error('unknown test page')
    end
    function s.ackInfo()
        local count=0
        while s.workspace.studio.feedback:peek()and s.workspace.studio.feedback:peek().kind=='info'do
            count=count+1;assert(count<=32,'informational window loop')
            local click=s.click;s.click=nil;s.render();s.click='ОК##warning-ok';s.render();s.click=click
        end
    end
    function s.liveAction()
        s.step()
        s.commands.pa26() -- close connection window
        local scale=math.min(1,(s.io.DisplaySize.x-32)/600,(s.io.DisplaySize.y-32)/650)
        s.io.MousePos.x,s.io.MousePos.y=s.io.DisplaySize.x/2-156*scale,s.io.DisplaySize.y/2
        s.down[0x58] = true
        s.step(16, {[0x58] = true})
        check(s.frames[2].condition())
        s.down[0x58] = false
        s.step(150)
        s.step(100)
        s.click='ДА##confirm-yes'; s.render()
        s.step(16); s.step(100)
    end
    function s.hasLog(fragment)
        for _, line in ipairs(s.logs) do if line:find(fragment, 1, true) then return true end end
        return false
    end
    function s.keyMessage(key, libraryFirst, message)
        message = message or 0x0100
        s.messageConsumed = false
        if options.consumeKeyboard then
            s.guiDown=s.guiDown or {}
            s.guiDown[key]=message==0x0100 or message==0x0104
        end
        local function library()
            if s.inputActive and not imgui.DisableInput and s.io.WantCaptureKeyboard then
                s.messageConsumed = true
            end
        end
        if libraryFirst then library() end
        if not (options.consumeKeyboard and libraryFirst and s.messageConsumed) then onWindowMessage(message, key) end
        if not libraryFirst then library() end
        if not s.messageConsumed and not s.controlLocked then
            s.serverKeys[#s.serverKeys + 1] = key
        end
        return not s.messageConsumed and not s.controlLocked
    end
    function s.inputDisabled() return imgui.DisableInput end
    function s.failMain()
        s.stateError = true
        local ok, failure = coroutine.resume(co)
        check(not ok)
        check(tostring(failure):find('injected game state API failure', 1, true) ~= nil)
        eq(coroutine.status(co), 'dead')
        -- MoonLoader invokes this event when it terminates an errored script.
        onScriptTerminate(s.script)
        s.stateError = false
    end
    s.script = scriptObject
    return s
end

return fixture

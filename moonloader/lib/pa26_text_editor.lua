-- A real horizontal viewport around multiline inputs. ImGui's internal
-- cursor scrolling is disabled, so selection cannot reset the visible origin.
local core=require 'pa26_core'
local M={}
function M.caretX(text,cursor,font,size)
    cursor=core.finite(cursor)and math.max(0,math.min(#text,math.floor(cursor)))or 0
    local head=text:sub(1,cursor):match('([^\n]*)$')or ''
    return font:CalcTextSizeA(size,1000000,0,head).x+12
end
function M.follow(scroll,caret,visible,maximum)
    if caret<scroll+12 then scroll=caret-12
    elseif caret>scroll+visible-28 then scroll=caret-visible+28 end
    return math.max(0,math.min(maximum,scroll))
end
function M.draw(s,ui,label,key,buffer,height,flags,callback)
    local im=s.imgui
    -- Offline presentation doubles may not implement scrolling. The installed
    -- mimgui exports both operations and always takes the viewport path.
    if im.GetScrollX==nil or im.SetScrollX==nil then
        if s.pendingInsert and s.pendingInsert.key==key then im.SetKeyboardFocusHere()end
        return im.InputTextMultiline(label,buffer,s.ffi.sizeof(buffer),im.ImVec2(-1,height),flags,callback)
    end
    s.textViews=s.textViews or {}
    local owner=s.draft and s.draft.id or false
    local v=s.textViews[key]
    if not v or v.owner~=owner then v={owner=owner};s.textViews[key]=v end
    local text=s.ffi.string(buffer);local font,size=im.GetFont(),im.GetFontSize()
    if v.text~=text or v.font~=font or v.size~=size then
        local widest=0
        for line in(text..'\n'):gmatch('(.-)\n')do widest=math.max(widest,font:CalcTextSizeA(size,1000000,0,line).x)end
        v.text,v.font,v.size,v.widest=text,font,size,widest
    end
    local width=math.max(1,im.GetContentRegionAvail().x)
    local content=math.max(width,v.widest+48)
    local windowFlags=im.WindowFlags.HorizontalScrollbar+im.WindowFlags.AlwaysHorizontalScrollbar+im.WindowFlags.NoScrollWithMouse
    im.PushStyleVarVec2(im.StyleVar.WindowPadding,im.ImVec2(0,0));ui.push(function()im.PopStyleVar(1)end)
    im.SetNextWindowContentSize(im.ImVec2(content,0))
    local visible=im.BeginChild('text-viewport##'..key,im.ImVec2(width,height),false,windowFlags)
    ui.push(function()im.EndChild()end)
    local changed=false
    if visible then
        local scroll=im.GetScrollX();local pos=im.GetWindowPos()
        local oldCursor=v.cursor
        if s.pendingInsert and s.pendingInsert.key==key then im.SetKeyboardFocusHere()end
        changed=im.InputTextMultiline(label,buffer,s.ffi.sizeof(buffer),im.ImVec2(content,math.max(24,im.GetContentRegionAvail().y)),
            flags+(im.InputTextFlags.NoHorizontalScroll or 0),callback)
        v.active=im.IsItemActive();v.maximum=im.GetScrollMaxX()
        if v.active then
            local io=im.GetIO();local nextScroll=scroll;local maximum=math.max(0,content-width)
            local navigation=false
            for _,name in ipairs({'Home','End','LeftArrow','RightArrow','UpArrow','DownArrow'})do
                local vk=io.KeyMap[im.lib['ImGuiKey_'..name]]
                if vk>=0 and vk<512 and io.KeysDown[vk]then navigation=true;break end
            end
            if io.MouseDown[0]then
                -- Move only at the visible edges; preserve the drag's anchor.
                if io.MousePos.y>=pos.y and io.MousePos.y<=pos.y+height-18 then
                    local speed=math.min(32,math.max(1,io.DeltaTime*620))
                    if io.MousePos.x>pos.x+width-12 then nextScroll=scroll+speed
                    elseif io.MousePos.x<pos.x+12 then nextScroll=scroll-speed end
                end
            elseif v.cursor and (v.cursor~=oldCursor or changed or navigation or v.mouseDown and v.first==v.last)then
                nextScroll=M.follow(scroll,M.caretX(s.ffi.string(buffer),v.cursor,font,size),width,maximum)
            end
            nextScroll=math.max(0,math.min(maximum,nextScroll))
            if math.abs(nextScroll-scroll)>.1 then im.SetScrollX(nextScroll)end
            v.mouseDown=io.MouseDown[0]
        end
        v.scroll=im.GetScrollX();v.viewport=width;v.content=content
    end
    ui.finish();ui.finish()
    return changed
end
return M

-- Original PA map geometry. A coordinate grid, not an official police-sector map.
-- No game reads, FFI, network calls, commands or persistent side effects.
local core=require 'pa26_core'
local M={MAX_LABELS=512}
local defaultLocation='{area}, квадрат {map_square}'
local reportDefaults={enabled=true,report_area=true,location_template=defaultLocation}
local lastLocation,lastLocationValid
local function validLocation(t)
    if type(t)~='string'or #t>240 then return false end
    if t==lastLocation then return lastLocationValid end
    local valid=core.validUtf8(t)and not t:find('%c')and not t:match('^%s*[/@]')and
        select(2,t:gsub('{area}',''))==1 and select(2,t:gsub('{map_square}',''))==1 and
        not t:gsub('{area}',''):gsub('{map_square}',''):find('[{}]')
    -- One immutable, <=240-byte format only; position and map flags stay fresh.
    lastLocation,lastLocationValid=t,valid;return valid
end
local function reportSettings(values)
    if type(values)~='table'then return nil,'Нет данных о месте для доклада.'end
    local s=values.map_grid;if s==nil then return reportDefaults end
    if type(s)~='table'or s.enabled~=nil and type(s.enabled)~='boolean'or
        s.report_area~=nil and type(s.report_area)~='boolean'then return nil,'Повреждены настройки места в докладе.'end
    if s.location_template~=nil and not validLocation(s.location_template)then return nil,'Проверьте формат места: нужны {area} и {map_square}.'end
    return s
end
local function reportTemplate(template)
    if type(template)~='string'or not template:find('%S')then return nil,'Не задан текст доклада.'end
    return true
end
local function copy(t)local n={};for k,v in pairs(t)do n[k]=v end;return n end
local function integer(x,a,b)return core.finite(x)and x==math.floor(x)and x>=a and x<=b end
function M.defaults()
    return {enabled=true,radar=true,pause_map=true,hud=true,labels=true,axis_labels=true,highlight=true,auto_square=false,auto_city=true,
        report_area=true,location_template=defaultLocation,
        west=-3000,north=3000,cell_size=250,columns=24,row_labels='ABCDEFGHIJKLMNOPQRSTUVWX',column_start=1,separator='-',
        font_size=12,line_width=1,line_alpha=.32,label_alpha=.88,min_label_px=50,theme='white'}
end
function M.validate(raw)
    local out=M.defaults();if raw==nil then return out end
    if type(raw)~='table'then return nil,'Повреждены настройки квадратов карты.'end
    if raw.auto_city~=nil then if type(raw.auto_city)~='boolean'then return nil,'Неверный переключатель города.'end;out.auto_city=raw.auto_city end
    for _,k in ipairs({'enabled','radar','pause_map','hud','labels','axis_labels','highlight','auto_square'})do
        if type(raw[k])~='boolean'then return nil,'Неверный переключатель карты: '..k end;out[k]=raw[k]
    end
    if raw.report_area~=nil then
        if type(raw.report_area)~='boolean'then return nil,'Неверный переключатель квадрата в докладах.'end
        out.report_area=raw.report_area
    end
    if raw.location_template~=nil then out.location_template=raw.location_template end
    local t=out.location_template
    if not validLocation(t)then
        return nil,'Формат места: одна строка до 240 байт с {area} и {map_square}, без команды.'
    end
    for _,r in ipairs({{'west',-10000,10000},{'north',-10000,10000},{'cell_size',50,2000},{'columns',1,48},{'column_start',0,99},
        {'font_size',9,24},{'line_width',1,3},{'min_label_px',25,150}})do
        if not integer(raw[r[1]],r[2],r[3])then return nil,'Проверьте значение карты: '..r[1]end;out[r[1]]=raw[r[1]]
    end
    for _,k in ipairs({'line_alpha','label_alpha'})do
        if not core.finite(raw[k])or raw[k]<.05 or raw[k]>1 then return nil,'Прозрачность карты должна быть от 0.05 до 1.'end;out[k]=raw[k]
    end
    if type(raw.row_labels)~='string'or #raw.row_labels<1 or #raw.row_labels>26 or raw.row_labels:find('[^A-Z]')then
        return nil,'Метки строк: от 1 до 26 разных заглавных латинских букв.'
    end
    local seen={};for c in raw.row_labels:gmatch('.')do if seen[c]then return nil,'Метки строк не должны повторяться.'end;seen[c]=true end
    if raw.separator~='-'and raw.separator~=''then return nil,'Разделитель квадрата: дефис или без разделителя.'end
    if not({white=true,blue=true,gold=true})[raw.theme]then return nil,'Неизвестный цвет сетки.'end
    out.row_labels=raw.row_labels;out.separator=raw.separator;out.theme=raw.theme
    return out
end
function M.bounds(s)return s.west,s.north-#s.row_labels*s.cell_size,s.west+s.columns*s.cell_size,s.north end
function M.cell(s,x,y,interior)
    if not s or not s.enabled or not core.finite(x)or not core.finite(y)or not integer(interior,0,0)then return nil end
    local west,south,east,north=M.bounds(s)
    if x<west or x>east or y<south or y>north then return nil end
    -- Interior boundaries belong to the east/south cell; the outer edge belongs to the last cell.
    local col=math.min(s.columns,math.floor((x-west)/s.cell_size)+1)
    local row=math.min(#s.row_labels,math.floor((north-y)/s.cell_size)+1)
    local label=s.row_labels:sub(row,row)..s.separator..tostring(col+s.column_start-1)
    return {row=row,col=col,label=label,west=west+(col-1)*s.cell_size,east=west+col*s.cell_size,
        north=north-(row-1)*s.cell_size,south=north-row*s.cell_size}
end
function M.values(s,profile,x,y,interior,z,zoneKey)
    local c=M.cell(s,x,y,interior)
    local square=profile and profile.square or ''
    if s and s.enabled and s.auto_square then square=c and c.label or nil end
    local city=profile and profile.city or''
    if s and s.auto_city~=false or city==''then
        city=interior==0 and require('pa26_hud').cityName(x,y,z,zoneKey)or nil
    end
    return {map_square=c and c.label or nil,square=square,cell=c,city=city}
end
-- {area} stays a district in binds. Only report renderers opt into enrichment;
-- saved wording is never rewritten. Explicit square tokens avoid duplication.
function M.location(values)
    local s,err=reportSettings(values);if not s then return nil,err end
    local area=values.area
    if area==nil or area==''then return nil end
    if type(area)~='string'then return nil,'Неверное поле доклада: район.'end
    local square=values.map_square
    if square~=nil and type(square)~='string'then return nil,'Неверное поле доклада: квадрат карты.'end
    if not s.enabled or type(square)~='string'or square==''then return area end
    return ((s.location_template or defaultLocation):gsub('{([a-z_]+)}',function(k)
        return k=='area'and area or k=='map_square'and square or '{'..k..'}'
    end))
end
function M.reportValues(values,template,enrich)
    local checked,err=reportTemplate(template);if not checked then return nil,err end
    local s;s,err=reportSettings(values);if not s then return nil,err end
    local location;location,err=M.location(values);if err then return nil,err end
    local out=copy(values);out.location=location
    if enrich~=false and s.report_area~=false and template:find('{area}',1,true)and
        not template:find('{map_square}',1,true)and not template:find('{square}',1,true)and not template:find('{location}',1,true)then
        out.area=out.location
    end
    return out
end
function M.reportPolicy(values,template)
    local checked,err=reportTemplate(template);if not checked then return nil,err end
    local s;s,err=reportSettings(values);if not s then return nil,err end
    if template:find('{location}',1,true)or s.report_area~=false and template:find('{area}',1,true)and
        not template:find('{map_square}',1,true)and not template:find('{square}',1,true)then
        return table.concat({tostring(s.enabled),tostring(s.report_area),s.location_template or defaultLocation},'\0')
    end
    return ''
end
function M.project(v,x,y)
    local px=v.ox+v.a*x+v.b*y;local py=v.oy+v.c*x+v.d*y
    if not core.finite(px)or not core.finite(py)or math.abs(px)>1e8 or math.abs(py)>1e8 then return nil end
    return px,py
end
function M.inside(v,x,y,pad)
    pad=pad or 0
    if not core.finite(x)or not core.finite(y)or x<v.left+pad or x>v.right-pad or y<v.top+pad or y>v.bottom-pad then return false end
    if v.ellipse then
        local e=v.ellipse;if e.rx<=pad or e.ry<=pad then return false end
        return ((x-e.cx)/(e.rx-pad))^2+((y-e.cy)/(e.ry-pad))^2<=1
    end
    return true
end
function M.clip(v,x1,y1,x2,y2)
    if not(core.finite(x1)and core.finite(y1)and core.finite(x2)and core.finite(y2))then return nil end
    local dx,dy=x2-x1,y2-y1;local lo,hi=0,1
    for _,r in ipairs({{-dx,x1-v.left},{dx,v.right-x1},{-dy,y1-v.top},{dy,v.bottom-y1}})do
        if math.abs(r[1])<1e-12 then if r[2]<0 then return nil end
        else local t=r[2]/r[1];if r[1]<0 then lo=math.max(lo,t)else hi=math.min(hi,t)end end
        if lo>hi then return nil end
    end
    if v.ellipse then
        local e=v.ellipse;local xx,yy=(x1-e.cx)/e.rx,(y1-e.cy)/e.ry
        local vx,vy=dx/e.rx,dy/e.ry;local a=vx*vx+vy*vy;local b=2*(xx*vx+yy*vy);local c=xx*xx+yy*yy-1
        if a<1e-18 then if c>0 then return nil end
        else local disc=b*b-4*a*c;if disc<0 then return nil end
            local root=math.sqrt(math.max(0,disc));lo=math.max(lo,(-b-root)/(2*a));hi=math.min(hi,(-b+root)/(2*a))
        end
    end
    if lo>hi or (dx*dx+dy*dy)*(hi-lo)^2<.05 then return nil end
    return x1+lo*dx,y1+lo*dy,x1+hi*dx,y1+hi*dy
end
function M.validView(v)
    if type(v)~='table'then return false end
    for _,k in ipairs({'a','b','c','d','ox','oy','left','right','top','bottom'})do if not core.finite(v[k])or math.abs(v[k])>1e8 then return false end end
    if v.right<=v.left or v.bottom<=v.top or math.abs(v.a*v.d-v.b*v.c)<1e-16 then return false end
    if v.ellipse then
        for _,k in ipairs({'cx','cy','rx','ry'})do if not core.finite(v.ellipse[k])then return false end end
        if v.ellipse.rx<=1 or v.ellipse.ry<=1 then return false end
    end
    return true
end
function M.geometry(s,v,current,targetCell,targetLabel)
    local out={lines={},labels={}};if not s.enabled or not M.validView(v)then return out end
    local west,south,east,north=M.bounds(s)
    local function line(wx1,wy1,wx2,wy2,active,target)
        local x1,y1=M.project(v,wx1,wy1);local x2,y2=M.project(v,wx2,wy2)
        if x1 and x2 then local a,b,c,d=M.clip(v,x1,y1,x2,y2);if a then out.lines[#out.lines+1]={a,b,c,d,active=active,target=target}end end
    end
    for col=0,s.columns do line(west+col*s.cell_size,north,west+col*s.cell_size,south)end
    for row=0,#s.row_labels do line(west,north-row*s.cell_size,east,north-row*s.cell_size)end
    if current and s.highlight then
        line(current.west,current.north,current.east,current.north,true);line(current.east,current.north,current.east,current.south,true)
        line(current.east,current.south,current.west,current.south,true);line(current.west,current.south,current.west,current.north,true)
    end
    if targetCell and core.finite(targetCell.west)and core.finite(targetCell.north)and core.finite(targetCell.east)and core.finite(targetCell.south)then
        line(targetCell.west,targetCell.north,targetCell.east,targetCell.north,false,true);line(targetCell.east,targetCell.north,targetCell.east,targetCell.south,false,true)
        line(targetCell.east,targetCell.south,targetCell.west,targetCell.south,false,true);line(targetCell.west,targetCell.south,targetCell.west,targetCell.north,false,true)
    else targetCell=nil end
    local function label(value,wx,wy,active,offsetx,offsety,target)
        if #out.labels>=M.MAX_LABELS then return end
        local x,y=M.project(v,wx,wy);if not x then return end;x=x+(offsetx or 0);y=y+(offsety or 0)
        local chars=0;for _ in value:gmatch('[%z\1-\127\194-\244][\128-\191]*')do chars=chars+1 end
        local hw=chars*s.font_size*.4;local hh=s.font_size*.55
        if M.inside(v,x-hw,y-hh,2)and M.inside(v,x+hw,y+hh,2)and M.inside(v,x+hw,y-hh,2)and M.inside(v,x-hw,y+hh,2)then
            out.labels[#out.labels+1]={text=value,x=x,y=y,active=active,target=target}
        end
    end
    local cellpx=s.cell_size*math.min(math.sqrt(v.a*v.a+v.c*v.c),math.sqrt(v.b*v.b+v.d*v.d))
    if s.labels then
        -- Add the current cell first so the label budget can never hide it.
        if current then label(current.label,(current.west+current.east)/2,(current.north+current.south)/2,true)end
        if targetCell then label(targetLabel or('УГОН: '..targetCell.label),(targetCell.west+targetCell.east)/2,(targetCell.north+targetCell.south)/2,false,0,-s.font_size*1.4,true)end
        if cellpx>=math.max(s.min_label_px,s.font_size*3.7)then
            for row=1,#s.row_labels do for col=1,s.columns do
                if not current or row~=current.row or col~=current.col then
                    label(s.row_labels:sub(row,row)..s.separator..tostring(col+s.column_start-1),west+(col-.5)*s.cell_size,north-(row-.5)*s.cell_size)
                end
            end end
        end
    end
    if s.axis_labels and v.kind=='map'then
        local stride=math.max(1,math.ceil(s.font_size*1.8/math.max(1,cellpx)))
        for col=1,s.columns,stride do label(tostring(col+s.column_start-1),west+(col-.5)*s.cell_size,north,false,0,s.font_size)end
        for row=1,#s.row_labels,stride do label(s.row_labels:sub(row,row),west,north-(row-.5)*s.cell_size,false,s.font_size,0)end
    end
    return out
end
function M.draw(im,font,s,view,current,targetCell,targetLabel)
    local g=M.geometry(s,view,current,targetCell,targetLabel);local list=im.GetBackgroundDrawList();font=font or im.GetFont()
    local rgb=({white={1,1,1},blue={.4,.73,1},gold={1,.73,.35}})[s.theme]
    local function color(alpha,active)return im.ColorConvertFloat4ToU32(im.ImVec4(active and .4 or rgb[1],active and .86 or rgb[2],active and .65 or rgb[3],alpha))end
    local lc,tc,hc=color(s.line_alpha),color(s.label_alpha),color(math.max(s.label_alpha,.8),true)
    local targetColor=im.ColorConvertFloat4ToU32(im.ImVec4(1,.59,.17,math.max(s.label_alpha,.8)))
    local shadow=im.ColorConvertFloat4ToU32(im.ImVec4(0,0,0,s.label_alpha*.9))
    for _,l in ipairs(g.lines)do list:AddLine(im.ImVec2(l[1],l[2]),im.ImVec2(l[3],l[4]),l.target and targetColor or l.active and hc or lc,(l.active or l.target)and s.line_width+1 or s.line_width)end
    for _,t in ipairs(g.labels)do
        local dim=font:CalcTextSizeA(s.font_size,100000,0,t.text);local x,y=t.x-dim.x/2,t.y-dim.y/2
        if M.inside(view,x,y,1)and M.inside(view,x+dim.x,y+dim.y,1)then
            list:AddTextFontPtr(font,s.font_size,im.ImVec2(x+1,y+1),shadow,t.text)
            list:AddTextFontPtr(font,s.font_size,im.ImVec2(x,y),t.target and targetColor or t.active and hc or tc,t.text)
        end
    end
    return #g.lines,#g.labels
end
return M

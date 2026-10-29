-- Independent dashboard view. No file access, native gameplay calls or chat sends.
local menu=require 'pa26_menu'
local important=require 'pa26_knowledge_important'
local M={}
local function action(v,cb,a)
 if a.kind=='wanted'and cb.openWanted then cb.openWanted(a.value)
 elseif a.kind=='fine'and cb.openCaseGround then cb.openCaseGround('fine',a.value)
 elseif a.kind=='mark'and cb.openMark then cb.openMark()
 elseif a.kind=='operational'and cb.openOperational then cb.openOperational(a.value)end
end
function M.columns(width,font)return math.max(1,math.min(3,math.floor((width+12)/(260*math.max(1,(font or 16)/16)+12))))end
function M.tileHeight(v,c,width)
 local im=v.im;local font=im.GetFont();local size=im.GetFontSize and im.GetFontSize()or 16
 local function h(text,heading)local f=heading and v.headingFont or font;local fs=f.FontSize or size;return menu.labelLayout(f,fs,math.max(30,width-32),text).height end
 local total=h('10. '..c.title,true)+h(c.subtitle,false)+88
 for _,line in ipairs(c.highlights)do total=total+h('• '..line,false)+7 end
 return math.ceil(total)
end
local function child(v,ui,id,w,h,fn)
 local im=v.im
 im.PushStyleVarVec2(im.StyleVar.WindowPadding,im.ImVec2(12,12));ui.push(function()im.PopStyleVar(1)end)
 local visible=im.BeginChild(id,im.ImVec2(w,h),true,im.WindowFlags.AlwaysUseWindowPadding)
 ui.push(function()im.EndChild()end);if visible then fn()end;ui.finish();ui.finish()
end
function M.draw(v,ui,cb)
 local data=v.knowledge.important;local im=v.im
 if not data then ui.text('Памятки подготавливаются…');return end
 v.importantView=v.importantView or{query='',page=1,expanded={}}
 local s=v.importantView
 local compact=im.GetContentRegionAvail().y<240
 local function toolbar()
  local value,changed=v:field(ui,compact and'Поиск' or'Быстрый поиск: код, команда, нарушение или статья','important-search',s.query,1025)
  if changed then s.query=value;s.page=1;s.cache=nil end
  if s.card and v:button(ui,'Назад к 10 карточкам##important-back')then s.card=nil;s.tab=nil;s.page=1;s.cache=nil end
 end
 if not compact then toolbar()end
 menu.scrollBody(im,ui,'##important-content',function()
  if compact then toolbar()end
  if s.card then
   local choices={}for _,c in ipairs(data.cards)do choices[#choices+1]={c.id,c.title}end
   local id,change=v:choice(ui,'Карточка##important-card',s.card,choices)
   if change then s.card=id;s.tab=data.byId[id].sections[1].id;s.page=1;s.cache=nil end
   local c=data.byId[s.card];v:heading(ui,c.title)
   choices={}for _,section in ipairs(c.sections)do choices[#choices+1]={section.id,section.title}end
   s.tab=s.tab or c.sections[1].id
   local tab,tch=v:choice(ui,'Тема##important-section',s.tab,choices)
   if tch then s.tab=tab;s.page=1;s.cache=nil end
   for i,a in ipairs(c.actions)do if v:button(ui,a.label..'##important-action-'..c.id..'-'..i)then action(v,cb,a)end end
  end
  if not s.card and s.query:match('^%s*$')then
   v:muted(ui,'10 памяток для службы. Выберите нужную; полная база и источники находятся в РЕЕСТРЕ.')
   local width=im.GetContentRegionAvail().x;local count=M.columns(width,im.GetFontSize and im.GetFontSize()or 16)
   local gap=12;local tile=(width-gap*(count-1))/count
   for first=1,#data.cards,count do
    local height=0;for n=first,math.min(#data.cards,first+count-1)do height=math.max(height,M.tileHeight(v,data.cards[n],tile))end
    for n=first,math.min(#data.cards,first+count-1)do
     if n>first then im.SameLine(0,gap)end
     local c=data.cards[n]
     child(v,ui,'##important-tile-'..c.id,tile,height,function()
      local p=im.GetCursorScreenPos();local draw=im.GetWindowDrawList()
      draw:AddRectFilled(im.ImVec2(p.x-6,p.y),im.ImVec2(p.x-3,p.y+math.max(25,height-30)),im.ColorConvertFloat4ToU32(im.ImVec4(.18,.70,.78,.85)),2)
      v:heading(ui,string.format('%02d. ',n)..c.title);v:muted(ui,c.subtitle)
      for _,line in ipairs(c.highlights)do ui.text('• '..line)end
      if v:button(ui,'Открыть памятку##important-open-'..c.id)then s.card=c.id;s.tab=c.sections[1].id;s.page=1;s.cache=nil end
     end)
    end
   end
   return
  end
  local key=tostring(data.revision)..'|'..tostring(s.card)..'|'..tostring(s.tab)..'|'..s.query
  if s.cacheKey~=key or not s.cache then s.cache=important.filter(data,s.query,s.card,s.tab);s.cacheKey=key end
  local rows=s.cache;local per=12;local pages=math.max(1,math.ceil(#rows/per));s.page=math.min(s.page,pages)
  v:muted(ui,'Найдено: '..#rows..' · Страница '..s.page..' / '..pages)
  for i=(s.page-1)*per+1,math.min(#rows,s.page*per)do local row=rows[i]
   if not s.card then v:muted(ui,data.byId[row.card].title)end
   local expanded=s.expanded[row.key];if expanded==nil then expanded=#row.text<480 end
   if v:button(ui,row.title..'##important-row-'..row.key)then
    if not s.card then s.card=row.card;s.tab=row.section;s.page=1;s.cache=nil end
    s.expanded[row.key]=not expanded
   end
   if row.note then v:muted(ui,row.note,'warning')end
   if expanded then ui.text(row.text)else ui.text(row.summary and row.summary~=''and row.summary or'Нажмите на заголовок, чтобы раскрыть порядок и условия.')end
   if row.action and v:button(ui,(row.action.kind=='wanted'and'Выбрать в /su'or'Выбрать в форме штрафа')..'##important-use-'..row.key)then action(v,cb,row.action)end
   im.Separator()
  end
  if #rows==0 then ui.text('Совпадений нет. Попробуйте название, номер статьи или команду.')end
  if s.page>1 and v:button(ui,'Предыдущие##important-prev')then s.page=s.page-1 end
  if s.page<pages and v:button(ui,'Следующие##important-next')then s.page=s.page+1 end
 end)
end
return M

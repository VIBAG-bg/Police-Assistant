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
 local visible=im.BeginChild(id,im.ImVec2(w,h),true,im.WindowFlags.AlwaysUseWindowPadding+(im.WindowFlags.NoScrollbar or 0)+(im.WindowFlags.NoScrollWithMouse or 0))
 ui.push(function()im.EndChild()end);if visible then fn()end;ui.finish();ui.finish()
end
local icons=require 'pa26_icons'
local tones={body={.90,.94,.97,1},heading={.88,.95,.98,1},meta={.64,.74,.82,1},
 info={.46,.60,.91,1},warning={.89,.69,.35,1},safe={.33,.79,.58,1}}
-- Fixed presentation blocks: each is measured only on width/font/filter revision.
-- Prefix offsets permit binary culling; all text is immediately scroll-readable.
function M.prepare(v,rows,width,global)
 local im=v.im;local body=im.GetFont();local fs=im.GetFontSize();local heading=v.buttonFont or body
 local hs=(heading.FontSize or fs)/(body.FontSize or fs)*fs;local blocks={};local total=0;local lastGroup
 for _,r in ipairs(rows)do
  local b={row=r,top=total,lines={},height=12}
  local function line(text,tone,bold,gap)
   if not text or text==''then return end
   local font=bold and heading or body;local size=bold and hs or fs
   local layout=menu.labelLayout(font,size,math.max(1,width-24),text)
   b.lines[#b.lines+1]={text=text,tone=tone or'body',font=font,size=size,y=b.height}
   b.height=b.height+layout.height+(gap or 8)
  end
  local group=(global and v.knowledge.important.byId[r.card].title..' · 'or'')..r.sectionTitle
  if group~=lastGroup then line(group,'info',true,12);lastGroup=group end
  line(r.title,'heading',true,10)
  if r.kind=='command'then line(r.rp_required and'RP требуется'or'Без отдельного RP','info',false)
  elseif r.kind=='wanted'then line('Игровое наблюдение: '..r.stars..' зв. · '..r.observed_on,'info',false);line('Связь со статьями: рекомендация PA, не равенство нормы и звёзд.','warning',false)end
  line(r.text)
  for i,branch in ipairs(r.sanctions or{})do
   line('Санкция '..i..' · '..(branch.condition or'Условие в тексте статьи'),'info',true)
   if branch.min~=nil then line(tostring(branch.min)..(branch.max~=nil and('–'..tostring(branch.max))or'')..' '..(branch.unit or'единица не указана'),'info')end
   line(branch.alternative or branch.source_excerpt)
  end
  if r.note then line(r.note,'warning')end
  if r.edit_status then line('Личная редакция: '..r.edit_status..' · сравнение доступно в РЕЕСТРЕ.','warning')end
  local refs={};local seen={}
  for _,ref in ipairs(r.provenance or{})do
   local text=(ref.title or ref.source_id)..(ref.locator and(' · '..ref.locator)or'')..(ref.date and(' · снимок '..ref.date)or'')
   if not seen[text]then refs[#refs+1]=text;seen[text]=true end
  end
  line(#refs>0 and('Источник: '..table.concat(refs,'; '))or'Основание: пояснение PA / отдельно предоставленные наблюдения. Проверяйте по РЕЕСТРУ.','meta')
  if r.action then
   b.actionY=b.height;b.actionLabel=(r.action.kind=='wanted'and'Выбрать в /su'or'Выбрать в форме штрафа')..'##important-use-'..r.key
   b.actionH=math.max(38,menu.labelLayout(heading,hs,math.max(1,width-54),b.actionLabel:match('^(.-)##')).height+16)
   b.height=b.height+b.actionH+10
  end
  b.height=b.height+16;total=total+b.height;blocks[#blocks+1]=b
 end
 return {blocks=blocks,total=total,width=width}
end
function M.visible(layout,top,bottom)
 local rows=layout.blocks;local lo,hi=1,#rows
 while lo<=hi do local mid=math.floor((lo+hi)/2);local b=rows[mid]
  if b.top+b.height<top then lo=mid+1 else hi=mid-1 end
 end
 local first=lo;while lo<=#rows and rows[lo].top<=bottom do lo=lo+1 end
 return first,lo-1
end
function M.renderRows(v,ui,cb,layout)
 local im=v.im;local origin=im.GetCursorScreenPos();local w=layout.width
 im.PushStyleVarVec2(im.StyleVar.ItemSpacing,im.ImVec2(0,0));ui.push(function()im.PopStyleVar(1)end)
 local wp=im.GetWindowPos and im.GetWindowPos()or{x=0,y=0}
 local ws=im.GetWindowSize and im.GetWindowSize()or{x=w,y=100000}
 local first,last=M.visible(layout,wp.y-origin.y-40,wp.y+ws.y-origin.y+40)
 local function skip(h)if h>0 then im.Dummy(im.ImVec2(1,h))end end
 if first>#layout.blocks then skip(layout.total);ui.finish();return end
 skip(layout.blocks[first].top)
 for n=first,last do local b=layout.blocks[n];local pos=im.GetCursorScreenPos();local list=im.GetWindowDrawList()
  for _,line in ipairs(b.lines)do local t=tones[line.tone]or tones.body
   list:AddTextFontPtr(line.font,line.size,im.ImVec2(pos.x+12,pos.y+line.y),im.ColorConvertFloat4ToU32(im.ImVec4(t[1],t[2],t[3],t[4])),line.text,nil,math.max(1,w-24))
  end
  if b.actionY then
   im.SetCursorScreenPos(im.ImVec2(pos.x,pos.y+b.actionY))
   if v:button(ui,b.actionLabel,w,b.actionH)then action(v,cb,b.row.action)end
   im.SetCursorScreenPos(pos)
  end
  list:AddLine(im.ImVec2(pos.x+12,pos.y+b.height-5),im.ImVec2(pos.x+w-12,pos.y+b.height-5),im.ColorConvertFloat4ToU32(im.ImVec4(.24,.38,.50,.45)),1)
  skip(b.height)
 end
 local lastBlock=layout.blocks[last];skip(layout.total-(lastBlock and lastBlock.top+lastBlock.height or 0))
 ui.finish()
end
function M.draw(v,ui,cb)
 local data=v.knowledge.important;local im=v.im
 if not data then ui.text('Памятки подготавливаются…');return end
 v.importantView=v.importantView or{query=''};local s=v.importantView
 local function invalidate()s.cache=nil;s.layout=nil;s.scrollReset=true end
 menu.scrollBody(im,ui,'##important-content',function()
  local value,changed=v:field(ui,'Найти код, команду, нарушение или статью','important-search',s.query,1025)
  if changed then s.query=value;invalidate()end
  if s.card then
   if v:button(ui,'Назад к 10 карточкам##important-back')then s.card=nil;s.tab=nil;invalidate()end
  end
  if s.card then
   local c=data.byId[s.card]
   v:heading(ui,c.title);v:muted(ui,c.subtitle)
   v:muted(ui,'По предоставленным снимкам 28.10.2026. Текущую редакцию и полные ссылки проверяйте в РЕЕСТРЕ.')
   local choices={{'*','Все темы'}};for _,section in ipairs(c.sections)do choices[#choices+1]={section.id,section.title}end
   local tab,tch=menu.choiceControl(im,ui,'##important-section','',s.tab or'*',choices,s,{buttons=true,font=v.buttonFont})
   if tch then s.tab=tab;invalidate()end
   for i,a in ipairs(c.actions)do if v:button(ui,a.label..'##important-action-'..c.id..'-'..i)then action(v,cb,a)end end
  end
  if not s.card and not s.query:match('%S')then
   v:muted(ui,'10 памяток для службы. Сначала выберите задачу. Полная база, личные правки и источники — в РЕЕСТРЕ.')
   local width=im.GetContentRegionAvail().x;local count=M.columns(width,im.GetFontSize());local gap=12;local tile=(width-gap*(count-1))/count
   for first=1,#data.cards,count do
    local height=0;for n=first,math.min(#data.cards,first+count-1)do height=math.max(height,M.tileHeight(v,data.cards[n],tile)+36)end
    for n=first,math.min(#data.cards,first+count-1)do
     if n>first then im.SameLine(0,gap)end
     local c=data.cards[n]
     child(v,ui,'##important-tile-'..c.id,tile,height,function()
      local p=im.GetCursorScreenPos();local draw=im.GetWindowDrawList()
      draw:AddRectFilled(im.ImVec2(p.x-6,p.y),im.ImVec2(p.x-3,p.y+height-30),im.ColorConvertFloat4ToU32(im.ImVec4(.18,.70,.78,.85)),2)
      icons.heading(im,ui,string.format('%02d. ',n)..c.title,icons.cards[c.id],'info');v:muted(ui,c.subtitle)
      for _,line in ipairs(c.highlights)do ui.text('• '..line)end
      v:muted(ui,c.hasIssues and'Есть уточнения · проверьте условия'or'По предоставленным источникам',c.hasIssues and'warning'or nil)
      if v:button(ui,'Открыть памятку##important-open-'..c.id)then s.card=c.id;s.tab='*';invalidate()end
     end)
    end
   end
   return
  end
  local key=tostring(data.revision)..'|'..tostring(s.card)..'|'..tostring(s.tab)..'|'..s.query
  if s.cacheKey~=key or not s.cache then s.cache=important.filter(data,s.query,s.card,s.tab);s.cacheKey=key;s.layout=nil end
  local width=math.max(1,im.GetContentRegionAvail().x);local font=im.GetFont();local size=im.GetFontSize()
  if not s.layout or s.width~=width or s.font~=font or s.fontSize~=size then
   s.layout=M.prepare(v,s.cache,width,not s.card);s.width=width;s.font=font;s.fontSize=size
  end
  v:muted(ui,'Найдено: '..#s.cache..' · полный текст')
  if #s.cache==0 then
   ui.text('По запросу ничего не найдено. Попробуйте название, номер статьи или команду.')
   if v:button(ui,'Очистить поиск##important-clear')then s.query='';v.buffers['important-search']=nil;invalidate()end
  else M.renderRows(v,ui,cb,s.layout)end
 end)
end
return M

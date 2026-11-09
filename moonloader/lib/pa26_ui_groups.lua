-- Presentation-only rows. Original labels/IDs and intent callbacks are retained.
local menu=require 'pa26_menu'
local M={}
function M.buttons(s,ui,rows,choose,compact)
 local im=s.imgui;local width=math.max(1,im.GetContentRegionAvail().x)
 local columns=width>=(compact and 420 or 580) and #rows>1 and 2 or 1
 local gap=compact and 8 or 12;local cell=(width-gap*(columns-1))/columns
 local font=s.buttonFont or im.GetFont();local size=font.FontSize or im.GetFontSize()
 for first=1,#rows,columns do
  local height=compact and 30 or 42
  for n=first,math.min(#rows,first+columns-1)do
   local text=rows[n][2]:match('^(.-)##')or rows[n][2]
   height=math.max(height,menu.labelLayout(font,size,math.max(1,cell-54),text).height+16)
  end
  for n=first,math.min(#rows,first+columns-1)do
   if n>first then im.SameLine(0,gap)end
   local row=rows[n]
   if menu.fittedButton(im,ui,row[2],im.ImVec2(cell,height),s.buttonFont)then choose(row[1],row)end
   if row[3]then menu.tooltip(im,ui,row[3])end
  end
 end
end
return M

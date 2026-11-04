-- Projection of a bounded immutable world polyline, using the existing map geometry.
local grid=require 'pa26_map_grid';local core=require 'pa26_core';local M={}
function M.simplify(points,maximum)
 if type(points)~='table'or #points>2000 then return{}end
 maximum=math.max(2,math.min(257,math.floor(maximum or 257)));local out={}
 for _,p in ipairs(points)do if not require('pa26_navigation').point(p)then return{}end end
 if #points<2 then return points end
 -- Best-first Douglas-Peucker: preserve corners before straight stretches,
 -- stop at a world tolerance or the hard draw budget. No native calls here.
 local keep={[1]=true,[#points]=true};local count=2;local heap={}
 local function push(a,b)
  if b-a<2 then return end
  local first,last=points[a],points[b];local dx,dy=last.x-first.x,last.y-first.y;local length=dx*dx+dy*dy
  local far,err
  for i=a+1,b-1 do local p=points[i];local t=length>0 and math.max(0,math.min(1,((p.x-first.x)*dx+(p.y-first.y)*dy)/length))or 0
   local x,y=p.x-first.x-t*dx,p.y-first.y-t*dy;local d=x*x+y*y
   if not err or d>err then far,err=i,d end
  end
  if not far or err<=4 then return end
  local item={a=a,b=b,i=far,error=err};local index=#heap+1
  while index>1 do local parent=math.floor(index/2);if heap[parent].error>=err then break end;heap[index]=heap[parent];index=parent end;heap[index]=item
 end
 local function pop()
  local top,last=heap[1],table.remove(heap);if #heap>0 then local i=1
   while i*2<=#heap do local child=i*2;if child<#heap and heap[child+1].error>heap[child].error then child=child+1 end
    if heap[child].error<=last.error then break end;heap[i]=heap[child];i=child
   end;heap[i]=last
  end;return top
 end
 push(1,#points)
 while #heap>0 and count<maximum do local r=pop();keep[r.i]=true;count=count+1;push(r.a,r.i);push(r.i,r.b)end
 for i,p in ipairs(points)do if keep[i]then out[#out+1]={x=p.x,y=p.y,z=p.z or 0}end end
 return out
end
function M.geometry(points,view,maximum)
 if not grid.validView(view)then return{}end
 local out={};for i=2,math.min(#(points or{}),257)do
  local a,b=points[i-1],points[i];local x,y=grid.project(view,a.x,a.y);local xx,yy=grid.project(view,b.x,b.y)
  local a1,b1,a2,b2=grid.clip(view,x,y,xx,yy)
  if a1 then out[#out+1]={a1,b1,a2,b2};if #out>=math.min(maximum or 256,256)then break end end
 end;return out
end
local viewFields={'a','b','c','d','ox','oy','left','right','top','bottom'}
local empty={}
function M.draw(im,points,view,cfg,target,cache)
 points=points or empty
 cache=cache or{};local same=cache.points==points and cache.maximum==cfg.max_segments and cache.ellipse==not not view.ellipse
 if same then for _,k in ipairs(viewFields)do if cache[k]~=view[k]then same=false;break end end end
 if same and view.ellipse then for _,k in ipairs({'cx','cy','rx','ry'})do if cache['ellipse_'..k]~=view.ellipse[k]then same=false;break end end end
 if not same then
  cache.lines=M.geometry(points,view,cfg.max_segments);cache.points=points;cache.maximum=cfg.max_segments;cache.ellipse=not not view.ellipse
  for _,k in ipairs(viewFields)do cache[k]=view[k]end
  if view.ellipse then for _,k in ipairs({'cx','cy','rx','ry'})do cache['ellipse_'..k]=view.ellipse[k]end end
 end
 local lines=cache.lines;local list=im.GetBackgroundDrawList()
 local line=im.ColorConvertFloat4ToU32(im.ImVec4(1,.65,.12,cfg.opacity));local shadow=im.ColorConvertFloat4ToU32(im.ImVec4(0,0,0,cfg.opacity))
 for _,p in ipairs(lines)do list:AddLine(im.ImVec2(p[1],p[2]),im.ImVec2(p[3],p[4]),shadow,cfg.line_width+2);list:AddLine(im.ImVec2(p[1],p[2]),im.ImVec2(p[3],p[4]),line,cfg.line_width)end
 if target and(target.kind=='mark'or target.kind=='bulletin'or target.marker_missing and cfg.keep_waypoint)then
  local x,y=grid.project(view,target.x,target.y)
  if x and grid.inside(view,x,y,8)then
   list:AddCircle(im.ImVec2(x,y),6,shadow,12,4);list:AddCircle(im.ImVec2(x,y),6,line,12,2)
  end
 end
 return #lines
end
return M

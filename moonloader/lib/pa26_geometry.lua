-- Sanitized author layout, captured 2026-11-01 at 2560x1440. No profile/RP data.
-- Preferred dimensions are separate from resize limits: a valid user size wins.
local M={referenceW=2560,referenceH=1440}
M.windows={
 main={width=2251,height=1339,x=16,y=31},
 -- Keep the author layout centre with a compact operational console.
 assist={width=1104,height=830,x=580,y=289.5},
 wanted={width=1792,height=900,x=444,y=335.5},
 tips={width=960,height=760,x=800,y=340},
 quick={width=780,height=700,x=890,y=370},
 ground={width=780,height=1152,x=890,y=144},
 fine={width=1120,height=1000,x=720,y=220},
 mark={width=1040,height=1000,x=760,y=220},
}
M.widget={x=2278,y=409,scale=1,reference_width=2560,reference_height=1440,responsive=true}
local limits={main={760,480,1080,640},assist={420,380,720,540},wanted={420,400,860,640},
 fine={420,360,760,640},mark={420,360,740,620},ground={420,360,740,680},quick={360,320,700,620},tips={420,360,820,640}}
local function finite(n)return type(n)=='number'and n==n and n~=math.huge and n~=-math.huge end
local function clamp(n,a,b)return math.max(a,math.min(b,n))end
M.finite=finite
function M.bounds(w,h,key,percent,style,scale)
 if not finite(w)or not finite(h)or w<220 or h<220 or w>32768 or h>32768 then return end
 local ref,l=M.windows[key],limits[key];if not ref then return end
 scale=finite(scale)and clamp(scale,.65,2)or 1
 local maxW,maxH=w-32,h-32;local minW,minH=math.min(l[1],maxW),math.min(l[2],maxH)
 local pw,ph=ref.width*w/M.referenceW,ref.height*h/M.referenceH
 -- These content floors keep controls readable, without prohibiting a smaller
 -- explicitly saved window. On a small display the content genuinely scrolls.
 pw=math.max(pw,math.min(l[3]*scale,maxW));ph=math.max(ph,math.min(l[4]*scale,maxH))
 if key=='main'and style=='percent'then
  percent=finite(percent)and clamp(percent,50,95)or 70;pw,ph=w*percent/100,h*percent/100
 end
 return {width=clamp(pw,minW,maxW),height=clamp(ph,minH,maxH),minW=minW,minH=minH,maxW=maxW,maxH=maxH}
end
function M.valid(row,key)
 if type(row)~='table'or not limits[key]then return false end
 for _,k in ipairs({'width','height','x','y'})do
  local minimum=(k=='x'or k=='y')and-32768 or 0
  if not finite(row[k])or row[k]<minimum or row[k]>32768 then return false end
 end
 local rw,rh=row.displayW,row.displayH
 if rw~=nil or rh~=nil then
  if not finite(rw)or not finite(rh)or rw<220 or rh<220 or rw>32768 or rh>32768 then return false end
 end
 local l=limits[key]
 return row.width>=math.min(l[1],rw and rw-32 or l[1])and row.height>=math.min(l[2],rh and rh-32 or l[2])
end
function M.rect(w,h,key,saved,percent,style,scale)
 local b=M.bounds(w,h,key,percent,style,scale);if not b then return end
 local ww,hh,x,y=b.width,b.height
 if M.valid(saved,key)then
  local sx,sy=saved.displayW and w/saved.displayW or 1,saved.displayH and h/saved.displayH or 1
  ww,hh=clamp(saved.width*sx,b.minW,b.maxW),clamp(saved.height*sy,b.minH,b.maxH)
  x,y=saved.x*sx,saved.y*sy
 else
  local ref=M.windows[key]
  if key=='main'and style=='percent'then x,y=(w-ww)/2,(h-hh)/2
  else
   -- Preserve the reference centre when a content floor changes dimensions.
   x=(ref.x+ref.width/2)*w/M.referenceW-ww/2
   y=(ref.y+ref.height/2)*h/M.referenceH-hh/2
  end
 end
 return {width=ww,height=hh,x=clamp(x,16,w-ww-16),y=clamp(y,16,h-hh-16)}
end
return M

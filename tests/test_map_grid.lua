local grid=require 'pa26_map_grid';local core=require 'pa26_core';local model=require 'pa26_bindings'
local s=grid.defaults();check(grid.validate(s));eq(grid.cell(s,-3000,3000,0).label,'A-1');eq(grid.cell(s,3000,-3000,0).label,'X-24')
eq(grid.cell(s,0,0,0).label,'M-13');eq(grid.cell(s,-2750,3000,0).label,'A-2');eq(grid.cell(s,-3000,2750,0).label,'B-1')
for row=1,24 do for col=1,24 do
    local x,y=-3000+(col-.5)*250,3000-(row-.5)*250
    local c=grid.cell(s,x,y,0);eq(c.row,row);eq(c.col,col);eq(c.label,string.char(64+row)..'-'..col)
    check(x>=c.west and x<=c.east and y>=c.south and y<=c.north)
    for _,d in ipairs({-124.999,0,124.999})do eq(grid.cell(s,x+d,y,0).label,c.label);eq(grid.cell(s,x,y+d,0).label,c.label)end
end end
for i=1,23 do
    local x=-3000+i*250;eq(grid.cell(s,x,2875,0).col,i+1);eq(grid.cell(s,x-.001,2875,0).col,i)
    local y=3000-i*250;eq(grid.cell(s,-2875,y,0).row,i+1);eq(grid.cell(s,-2875,y+.001,0).row,i)
end
for _,p in ipairs({{-3000.001,0},{3000.001,0},{0,-3000.001},{0,3000.001},{0/0,1},{1,math.huge}})do check(not grid.cell(s,p[1],p[2],0))end
for _,interior in ipairs({1,-1,.5,math.huge})do check(not grid.cell(s,0,0,interior))end
check(not grid.cell(s,0,0,nil))
eq(grid.values(s,{square='Пост 2'},0,0,0).square,'Пост 2');eq(grid.values(s,{},0,0,0).map_square,'M-13')
s.auto_square=true;eq(grid.values(s,{square='Пост 2'},0,0,0).square,'M-13');check(not grid.values(s,{square='Пост 2'},0,0,1).square)
s.enabled=false;check(not grid.values(s,{square='Пост 2'},0,0,0).map_square);eq(grid.values(s,{square='Пост 2'},0,0,0).square,'Пост 2')
s=grid.defaults();s.row_labels='Z';s.columns=1;s.west=100;s.north=500;s.cell_size=500;s.column_start=0;s.separator=''
check(grid.validate(s));eq(grid.cell(s,100,500,0).label,'Z0');eq(grid.cell(s,600,0,0).label,'Z0')
for _,bad in ipairs({{row_labels='AA'},{row_labels='АБ'},{row_labels=''},{columns=0},{columns=49},{cell_size=0},{west=0/0},{north=math.huge},
    {separator='?'},{theme='invalid'},{font_size=30},{line_alpha=0},{label_alpha=2},{auto_square='true'}})do
    local c=grid.defaults();for k,v in pairs(bad)do c[k]=v end;check(not grid.validate(c))
end
local lib=model.defaults(core.defaults());lib.profile.square='Север';lib.bindings[1].script='Моя личная отыгровка.'
lib.map_grid=nil;local upgraded=assert(model.validate(lib,core.defaults()));eq(upgraded.profile.square,'Север');eq(upgraded.bindings[1].script,'Моя личная отыгровка.')
check(upgraded.map_grid.enabled);check(not upgraded.map_grid.auto_square)
upgraded.map_grid.cell_size=500;local persisted=assert(model.validate(TEST_JSON_DECODE(TEST_JSON_ENCODE(upgraded)),core.defaults()));eq(persisted.map_grid.cell_size,500)
local v={kind='map',a=.1,b=0,c=0,d=-.1,ox=400,oy=300,left=0,top=0,right=800,bottom=600}
s=grid.defaults();local g=grid.geometry(s,v,grid.cell(s,0,0,0));eq(#g.lines,54);check(#g.labels>1)
for _,l in ipairs(g.lines)do check(grid.inside(v,l[1],l[2]));check(grid.inside(v,l[3],l[4]))end
for i=0,15 do
    local angle=i*math.pi/8;local c,k=math.cos(angle),math.sin(angle)
    local r={kind='radar',a=.2*c,b=.2*k,c=.2*k,d=-.2*c,ox=200,oy=150,left=50,top=30,right=350,bottom=270,
        ellipse={cx=200,cy=150,rx=150,ry=120}}
    g=grid.geometry(s,r,grid.cell(s,0,0,0));check(#g.lines>0)
    for _,l in ipairs(g.lines)do
        for n=1,3,2 do check(((l[n]-200)/150)^2+((l[n+1]-150)/120)^2<=1.0000001,'Line escapes circular radar')end
    end
    for _,t in ipairs(g.labels)do check(grid.inside(r,t.x,t.y,2))end
end
local circle={left=0,right=200,top=0,bottom=200,ellipse={cx=100,cy=100,rx=100,ry=100}}
local x1,y1,x2,y2=grid.clip(circle,-100,100,300,100);check(math.abs(x1)<1e-6);eq(y1,100);check(math.abs(x2-200)<1e-6);eq(y2,100)
check(not grid.clip(circle,-100,-10,300,-10));check(not grid.clip(circle,100,100,100,100))
local huge=model.copy(v);huge.right=16384;huge.bottom=16384;huge.ox=8192;huge.oy=8192;huge.a=2;huge.d=-2
s.columns=48;s.row_labels='ABCDEFGHIJKLMNOPQRSTUVWXYZ';s.cell_size=100;s.min_label_px=25
g=grid.geometry(s,huge,grid.cell(s,0,0,0));check(#g.labels<=grid.MAX_LABELS)
v.a=0;v.d=0;eq(#grid.geometry(s,v).lines,0)
-- Explicit output variable compiles through the actual binder and radio preparer.
local b=model.newBinding(7);b.script='/r Квадрат {map_square}.'
local plan=assert(require('pa26_binder').compile(b,{session='test',createdAt=1000,demo=true,values={map_square='H-18'}},{},codec))
check(plan.lines[1]:find('H-18',1,true))
local spec={name='Квадрат',template='Квадрат {map_square}.',channel='/r',confirmation=true,interval_ms=60000}
plan=assert(require('pa26_radio_guard').prepare(spec,{session='test',ped=1,demo=true,map_square='H-18'},codec,1000,1))
eq(plan.lines[1],'/r Квадрат H-18.')
check(not require('pa26_radio_guard').prepare(spec,{session='test',ped=1},codec,1000,1))

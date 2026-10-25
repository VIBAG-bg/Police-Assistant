local menu=require'pa26_menu'
for _,display in ipairs({{640,480},{800,600},{1280,720},{1366,768},{1920,1080},{2560,1440},{3840,2160}})do
    for _,key in ipairs({'main','quick','tips','assist'})do
        local r=assert(menu.windowRect(display[1],display[2],key))
        check(r.x>=16 and r.y>=16 and r.x+r.width<=display[1]-16 and r.y+r.height<=display[2]-16)
        check(r.width>=r.height or display[1]<display[2],'Default proportions should be horizontal')
    end
end
local wide=menu.windowBounds(1920,1080,'main');eq(wide.width,1344);eq(wide.height,756)
check(wide.width>1180 and wide.width/wide.height>1.5)
local pos={x=100,y=100};local size={x=400,y=300}
local io={DisplaySize={x=1280,y=720},MousePos={x=200,y=150},MouseDown={[0]=false,[1]=true}}
local clicked,hovered=true,true
local im={GetIO=function()return io end,GetWindowPos=function()return pos end,GetWindowSize=function()return size end,
    IsMouseClicked=function(button)eq(button,1);return clicked end,IsWindowHovered=function()return hovered end}
local owner={};local r=assert(menu.rightDragRect(im,owner,'assist'));eq(r.x,100);eq(r.y,100)
clicked=false;hovered=false;io.MousePos={x=320,y=230};r=assert(menu.rightDragRect(im,owner,'assist'))
eq(r.x,220);eq(r.y,180);eq(menu.rightDragRect(im,owner,'tips'),nil,'Another window cannot steal a held drag')
io.MousePos={x=99999,y=99999};r=assert(menu.rightDragRect(im,owner,'assist'));eq(r.x,864);eq(r.y,404)
io.MousePos={x=-9999,y=-9999};r=assert(menu.rightDragRect(im,owner,'assist'));eq(r.x,16);eq(r.y,16)
io.MouseDown[1]=false;eq(menu.rightDragRect(im,owner,'assist'),nil);eq(owner.rightDrag,nil)
io.MouseDown[1]=true;eq(menu.rightDragRect(im,owner,'assist'),nil,'A held button before opening cannot start a drag')
clicked=true;hovered=false;eq(menu.rightDragRect(im,owner,'assist'),nil,'Occluded windows cannot start a drag')
hovered=true;io.MouseDown[0]=true;eq(menu.rightDragRect(im,owner,'assist'),nil,'Left resize/click and right drag cannot begin together')
io.MouseDown[0]=false;io.MousePos.x=0/0;eq(menu.rightDragRect(im,owner,'assist'),nil)

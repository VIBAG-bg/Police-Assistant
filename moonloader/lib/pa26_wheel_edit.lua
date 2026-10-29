-- Renderer creates a bounded intent; only main validates and persists it.
local M={}
function M.update(wheel,hit,input,revision)
 wheel.nav=wheel.nav or{}
 if input.ctrl then wheel.editConsumed=true;wheel.choice=nil end
 if input.blocked or not input.ctrl then wheel.drag=nil;wheel.nav.editSource=nil;wheel.nav.editTarget=nil;return end
 if input.clicked and hit then
  wheel.drag={ring=hit.ring,category=hit.category,key=hit.key,index=hit.index,name=hit.name,revision=revision,at=input.now}
 end
 local d=wheel.drag
 if not d then return end
 wheel.editConsumed=true;wheel.choice=nil;wheel.nav.choice=nil
 local compatible=hit and hit.ring==d.ring and hit.category==d.category
 wheel.nav.editSource=d;wheel.nav.editTarget=compatible and hit or nil
 if input.released then
  wheel.drag=nil;wheel.nav.editSource=nil;wheel.nav.editTarget=nil
  if compatible and hit.key~=d.key and revision==d.revision then return{source=d,target=hit,revision=revision,at=input.now}end
 end
end
return M

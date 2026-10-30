-- Selection consumes prepared observations; emission uses the normal executor.
local core=require 'pa26_core';local model=require 'pa26_bindings';local M={}
function M.same(a,b)return a and b and a.id==b.id and a.name==b.name and a.ped==b.ped and a.generation==b.generation end
function M.valid(t,state,radius)
 return t and core.validId(t.id)and type(t.name)=='string'and core.validUtf8(t.name)and not t.name:find('[%c{}]')and t.ped~=state.ped and
  core.finite(t.ped)and t.ped>0 and core.finite(t.distance)and t.distance>=0 and t.distance<=math.min(50,radius)and core.finite(t.generation)and t.generation>=0 and t.generation%1==0
end
function M.resolve(rows,state,radius)
 for i,r in ipairs(rows or{})do if i>2051 then break end;if M.valid(r,state,radius)and(not r.fallback or r.visible and not r.colleague)then return model.copy(r)end end
end
function M.install(C)
 function C:requestFastPt(rows)
  local cfg=self.env.settings()
  if not cfg.fast_pt_enabled then return nil,'Быстрый /pt выключен в настройках Copilot.'end
  local t=M.resolve(rows,self.state,cfg.fast_pt_distance)
  if not t then return nil,'Нет подходящей видимой цели в пределах '..cfg.fast_pt_distance..' м. Подойдите ближе или используйте /pt ID вручную.'end
  self.fastPtTarget=t
  local p,why=self:propose('fast_pt');if not p then return nil,why end
  self.offers={p};return true
 end
 function C:validFastPt(p)
  local target=self.fastPtLive
  return self.env.settings().fast_pt_enabled and M.same(p.ptTarget,target)and M.valid(target,self.state,self.env.settings().fast_pt_distance)and
   self.fastPtLiveAt and(core.elapsed(self.now,self.fastPtLiveAt)or math.huge)<=250
 end
end
return M

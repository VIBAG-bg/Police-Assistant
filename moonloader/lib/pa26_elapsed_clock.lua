-- Patrol-only monotonic clock. Allocated once; read by updateGame, never ImGui.
local core=require 'pa26_core'
local M={}
function M.windows(ffi)
 if not ffi or ffi.os~='Windows'then return nil end
 local ok,read=pcall(function()
  pcall(ffi.cdef,'int __stdcall QueryUnbiasedInterruptTime(uint64_t*);')
  local api=ffi.load('kernel32');local value=ffi.new('uint64_t[1]')
  if api.QueryUnbiasedInterruptTime(value)==0 then return end
  -- Windows 7+: monotonic working time; sleep/hibernation are excluded.
  return function()if api.QueryUnbiasedInterruptTime(value)~=0 then
   local n=tonumber(value[0]);if core.finite(n)then return math.floor(n/10000)end
  end end
 end)
 return ok and read or nil -- No CPU-time fallback; unavailable clocks use the old safe policy.
end
function M.delta(now,old,wall,oldWall,previous,state,cfg)
 local dt=old and core.elapsed(now,old)
 if not previous or not state or not previous.focused or not state.focused or
  previous.focusEpoch~=state.focusEpoch then return nil end
 local map=previous.paused==true or state.paused==true
 if map then
  if cfg.count_map_time==false or not core.finite(wall)or not core.finite(oldWall)then return nil end
  dt=wall-oldWall
  if dt<0 or dt>(cfg.map_max_gap_ms or 3600000)then return nil end
 elseif core.finite(wall)and core.finite(oldWall)then dt=wall-oldWall end
 if not core.finite(dt)or dt<0 or not map and dt>5000 then return nil end
 return dt
end
return M

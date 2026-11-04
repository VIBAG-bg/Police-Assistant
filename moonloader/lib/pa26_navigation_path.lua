-- No unverified CPathFind address is callable in this release. A native adapter
-- must supply independently verified ABI/signatures and a tested lock backend.
local M={MAX_NODES=2000,verified=false}
function M.status()return false,'Дорожный GPS заблокирован: ABI и работа поверх Esc-карты не проверены в GTA.'end
function M.new(backend)
 local out={verified=false,reason=select(2,M.status())}
 if not backend or backend.buildVerified~=true or backend.abiVerified~=true or backend.gameAcceptance~=true then return out end
 if type(backend.lock)~='function'or type(backend.unlock)~='function'or type(backend.stale)~='function'or type(backend.find)~='function'then return out end
 if backend.stale()then out.reason='Остался gps.lock: native-режим выключен до проверки.';return out end
 out.verified=true
 function out:find(a,b)
  if not self.first then if backend.lock()~=true then self.verified=false;return end end
  local ok,points,distance=pcall(backend.find,a,b,M.MAX_NODES)
  if not ok then self.verified=false;return end
  local valid=type(points)=='table'and #points>=2 and #points<=M.MAX_NODES and require('pa26_core').finite(distance)and distance>0 and distance<100000
  if valid then for _,p in ipairs(points)do if not require('pa26_navigation').point(p)then valid=false;break end end end
  if not valid then self.verified=false;self.reason='Нативный маршрут не прошёл проверку; gps.lock сохранён.';return end
  if not self.first then if backend.unlock()~=true then self.verified=false;return end;self.first=true end
  return points,distance
 end
 return out
end
return M

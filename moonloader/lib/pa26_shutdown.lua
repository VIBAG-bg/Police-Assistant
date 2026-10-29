-- No GUI or native calls. A failed save leaves PA loaded and permits a retry.
local M={}
function M.run(env)
 local ok,err=pcall(env.stop)
 if not ok then return nil,'Не удалось остановить текущие действия: '..tostring(err)end
 for _,step in ipairs(env.saves)do
  local called,result,why=pcall(step[2])
  if not called or result~=true then return nil,'Не сохранено: '..step[1]..'. PA остаётся включённым. '..tostring(called and why or result or'Повторите запись.')end
 end
 local cleaned,why=pcall(env.finish)
 if not cleaned then return nil,'Данные записаны, но отключение требует проверки: '..tostring(why)end
 return true
end
return M

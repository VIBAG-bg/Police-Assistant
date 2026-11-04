-- Advisory only: never rewrites a user's saved words or guesses target gender.
local core=require 'pa26_core';local M={}
local verbs={'достал','предъявил','показал','ввёл','отправил','проверил','открыл','закрыл','надел','снял','запросил','подошёл','осмотрел','задержал','посадил','изъял','передал','взял','обратился','представился','произнёс','заполнил','получил','уточнил','зачитал','поставил','защёлкнул'}
function M.inspect(text)
 if type(text)~='string'then return{}end
 local out={};for line in(text..'\n'):gmatch('(.-)\n')do if line:match('^/me%s')then
  local plain=core.stripGender(line)
  for _,verb in ipairs(verbs)do
   local first=plain:find(verb,1,true)
   if first then local tail=plain:sub(first+#verb,first+#verb+1)
    if tail==''or tail:match('^[%s%p]')then out[#out+1]=verb end
   end
  end
 end end;return out
end
M.fallback='Если род не задан в старом шаблоне, используется мужская форма. Род офицера выбирается явно в профиле; род цели не угадывается.'
return M

-- Parsing only. Resolving accounts, scene checks and sending belong to main().
local core=require 'pa26_core';local M={}
function M.parse(head,args)
 if head~='ticket'and head~='setmark'then return nil,'Неизвестная команда процедуры.'end
 if type(args)~='string'or #args>1024 or not core.validUtf8(args)or args:find('%c')then return nil,'Проверьте параметры: одна строка без управляющих символов.'end
 args=args:match('^%s*(.-)%s*$')
 local p={head=head,kind=head=='ticket'and'fine'or'mark',raw='/'..head..(args~=''and(' '..args)or'')}
 if args==''then return p end
 local id,rest=args:match('^(%d+)%s*(.-)$');id=tonumber(id)
 if not core.validId(id)then return nil,'Укажите целый ID подключённого игрока.'end
 p.id=id
 if rest~=''then
  if head=='setmark'then return nil,'Использование: /setmark [ID]. IC-телефон указывается внутри помощника.'end
  local amount,reason=rest:match('^(%d+)%s+(.+)$')
  if not amount or #amount>9 or tonumber(amount)<1 or tonumber(amount)>999999999 or not reason:match('%S')then
   return nil,'Использование: /ticket [ID] либо /ticket ID сумма причина.'
  end
  p.amount=tostring(tonumber(amount));p.basis=reason
 end
 return p
end
-- Current source records are chunks, rather than one record per numbered rule.
-- Keep each complete source paragraph, including notes, without mixing editions.
function M.trackingRules(data)
 local found={}
 for _,row in ipairs(type(data)=='table'and data.rules or{})do
  if type(row)=='table'and type(row.id)=='string'and row.id:match('^reg%-current:')and type(row.text)=='string'then
   local active
   for line in (row.text:gsub('\r\n','\n')..'\n'):gmatch('(.-)\n')do
    local n=tonumber(line:match('^%s*6%.(%d+)%.%s'))
    if n then
     active=n>=9 and n<=17 and not found[n]and n or nil
     if active then found[active]=line end
    elseif line:match('^%s*%d+%.%d+%.')or line:match('^%s*Спойлер:')or line:match('^%s*Раздел ')then active=nil
    elseif active and line:match('%S')then found[active]=found[active]..'\n'..line end
   end
  end
 end
 local out={};for n=9,17 do if found[n]then out[#out+1]=found[n]end end;return out
end
return M

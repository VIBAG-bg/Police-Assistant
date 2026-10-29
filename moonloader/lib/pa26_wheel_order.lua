-- Stable IDs only; hidden/contextual entries keep their stored positions.
local core=require 'pa26_core';local M={}
local groups={root=true,citizen=true,documents=true,detention=true,frisk=true,wanted=true,service=true,leadership=true,custom=true}
function M.key(item)return type(item.id)=='number'and('b:'..item.id)or('s:'..tostring(item.id))end
function M.validate(raw)
 if raw==nil then return{}end
 if type(raw)~='table'then return nil,'Неверный порядок секторов колеса.'end
 local out={}
 for group,rows in pairs(raw)do
  if not groups[group]or type(rows)~='table'then return nil,'Неизвестная группа порядка колеса.'end
  local n,seen=0,{};out[group]={}
  for i,key in pairs(rows)do
   if not core.finite(i)or i%1~=0 or i<1 or i>256 or type(key)~='string'or #key>80 or seen[key]or
     (group=='root'and(not groups[key]or key=='root')or group~='root'and not(key:match('^b:%d+$')or key:match('^s:[%w_-]+$')))then return nil,'Повреждён порядок секторов колеса.'end
   seen[key]=true;n=n+1;out[group][i]=key
  end
  if n~=#rows or group=='root'and n>8 then return nil,'Неверная длина порядка колеса.'end
  for i=1,n do if rows[i]==nil then return nil,'Пропуск в порядке колеса.'end end
 end
 return out
end
function M.sort(items,keys,keyOf)
 local rank={};for i,k in ipairs(keys or{})do rank[k]=i end
 local position={};for i,item in ipairs(items)do position[item]=i end
 table.sort(items,function(a,b)local x,y=rank[keyOf(a)]or 100000,rank[keyOf(b)]or 100000;return x==y and position[a]<position[b]or x<y end)
end
function M.swap(existing,visible,source,target)
 local a,b;for i,k in ipairs(visible)do if k==source then a=i end;if k==target then b=i end end
 if not a or not b or a==b then return nil,'Выберите другой сектор того же кольца.'end
 local reordered,active={},{};for i,k in ipairs(visible)do reordered[i]=k;active[k]=true end
 reordered[a],reordered[b]=reordered[b],reordered[a]
 local out,index={},1
 for _,k in ipairs(existing or{})do if active[k]then out[#out+1]=reordered[index];index=index+1 else out[#out+1]=k end end
 while index<=#reordered do out[#out+1]=reordered[index];index=index+1 end
 return out
end
return M

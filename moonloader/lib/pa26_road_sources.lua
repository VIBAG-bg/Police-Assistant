-- Only four explicitly permitted read-only locations; never scan directories.
local M={HASH='c1d347286ccb0349940800570078c6872bef31c12ac6d6f77a4b1cf8b857d7db',SIZE=589664}
function M.absolute(path)
 if type(path)~='string'or #path>1024 or path:find('[%z\r\n]')then return nil end
 path=path:gsub('/','\\')
 if not path:match('^%a:\\')or path:sub(3):find(':',1,true)then return nil end
 local parts={};for part in path:sub(4):gmatch('[^\\]+')do
  if part=='.'or part=='..'or part:find('[<>"|?*]')or part:match('[%. ]$')then return nil end
  parts[#parts+1]=part
 end
 if #parts==0 then return nil end
 return path:sub(1,3)..table.concat(parts,'\\')
end
function M.candidates(script,ml,custom)
 script=M.absolute(script);ml=M.absolute(ml)
 if not script or not ml or not ml:lower():match('\\moonloader$')or
  script:lower()~=(ml..'\\police_assistant_2026.lua'):lower()then return nil,'Не удалось подтвердить папку установленного PA.'end
 local root=ml:match('^(.*)\\[^\\]+$');local out={};local seen={}
 local function add(path,id,label,pinned)
  local normalized=M.absolute(path);if normalized and not seen[normalized:lower()]then
   seen[normalized:lower()]=true;out[#out+1]={path=normalized,id=id,label=label,sha256=pinned and M.HASH or nil,size=pinned and M.SIZE or nil}
  end
 end
 add(ml..'\\resource\\pa26\\roads.bin','bundled','Встроенный граф PA',true)
 if custom and custom~=''then
  if not M.absolute(custom)then return nil,'Для дополнительного графа выберите полный путь к обычному файлу.'end
  add(custom,'custom','Выбранный дополнительный граф')
 end
 add(root..'\\exsellent\\gps\\roads.bin','launcher','Резервный граф Exsellent')
 add(root..'\\legacy\\gps\\roads.bin','legacy','Резервный граф Legacy')
 return out
end
function M.new(env)
 local cached,key,errorText;local open=env.open or require('pa26_road_file').open
 return {open=function(_,index,custom)
  if key~=custom or not cached then
   key=custom;cached,errorText=M.candidates(env.script(),env.moonloader(),custom)
  end
  if not cached then return nil,{label='Папка PA',id='invalid'},errorText end
  local row=cached[index];if not row then return nil,nil,'Других разрешённых источников нет.'end
  local handle,why=open(row.path)
  return handle,row,why
 end}
end
return M

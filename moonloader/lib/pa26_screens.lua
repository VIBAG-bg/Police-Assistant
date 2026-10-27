-- Windows screenshots adapter. Scanning/moving is invoked by Evidence:tick only.
local core=require 'pa26_core';local M={}
function M.index(name)
 if type(name)~='string'then return end
 local n,ext=name:lower():match('^sa%-mp%-(%d+)%.([a-z]+)$')
 if n and #n<=7 and(ext=='png'or ext=='jpg'or ext=='jpeg')then return tonumber(n)end
end
function M.summarize(dir,rows)
 local out={dir=dir,count=0,maxIndex=-1,latestWritten=0,files={}}
 for _,f in ipairs(rows)do
  local ext=f.name:lower():match('%.([a-z]+)$')
  if not f.directory and(ext=='png'or ext=='jpg'or ext=='jpeg')then
   out.count=out.count+1;local i=M.index(f.name);if i and i>out.maxIndex then out.maxIndex=i end
   out.files[#out.files+1]=f
   if f.written>out.latestWritten or f.written==out.latestWritten and(not out.latestFile or f.path>out.latestFile)then
    out.latestWritten=f.written;out.latestFile=f.path;out.latestCreated=f.created
   end
  end
 end
 out.nearLimit=out.count>=900 or out.maxIndex>=990;out.full=out.maxIndex>=999;return out
end
function M.new(api)
 local ffi=require 'ffi';if ffi.os~='Windows'then
  api.defaultScreensDir=function()return nil,'Каталог снимков доступен в Windows.'end
  api.scanScreens=function()return nil,'Каталог снимков доступен в Windows.'end
  api.archiveScreens=function()return nil,'Архив доступен в Windows.'end;return api
 end
 pcall(ffi.cdef,[[
  typedef struct{unsigned long low,high;} PA41_TIME;
  typedef struct{unsigned long attrs;PA41_TIME created,accessed,written;unsigned long sizeHigh,sizeLow,res0,res1;wchar_t name[260];wchar_t alternate[14];} PA41_FIND;
  void* __stdcall FindFirstFileW(const wchar_t*,PA41_FIND*);
  int __stdcall FindNextFileW(void*,PA41_FIND*);int __stdcall FindClose(void*);
  int __stdcall CreateDirectoryW(const wchar_t*,void*);unsigned long __stdcall GetFileAttributesW(const wchar_t*);
  int __stdcall MoveFileExW(const wchar_t*,const wchar_t*,unsigned long);unsigned long __stdcall GetLastError(void);
  int __stdcall SHGetFolderPathW(void*,int,void*,unsigned long,wchar_t*);
  int __stdcall WideCharToMultiByte(unsigned int,unsigned long,const wchar_t*,int,char*,int,const char*,int*);
 ]])
 local k=ffi.load('kernel32');local shell=ffi.load('shell32');local bit=require 'bit'
 local function wide(s)
  if type(s)~='string'or #s>1000 or not core.validUtf8(s)or not s:match('^%a:[/\\]')or s:find('[%c*?<>|\"]')or s:find(':',3,true)then return nil end
  s=s:gsub('/','\\'):gsub('\\+$','')
  for part in s:sub(4):gmatch('[^\\]+')do
   local stem=part:upper():match('^[^.]+')or''
   if part=='.'or part=='..'or part:match('[ .]$')or({CON=true,PRN=true,AUX=true,NUL=true})[stem]or stem:match('^COM[1-9]$')or stem:match('^LPT[1-9]$')then return nil end
  end
  local n=k.MultiByteToWideChar(65001,8,s,#s,nil,0);if n<=0 then return nil end
  local w=ffi.new('wchar_t[?]',n+1);if k.MultiByteToWideChar(65001,8,s,#s,w,n)~=n then return nil end;return w,s
 end
 local function utf8(w)
  local n=k.WideCharToMultiByte(65001,0,w,-1,nil,0,nil,nil);if n<=1 then return''end
  local b=ffi.new('char[?]',n);k.WideCharToMultiByte(65001,0,w,-1,b,n,nil,nil);return ffi.string(b,n-1)
 end
 local function plain(path)
  local w,s=wide(path);if not w then return nil end
  local current=s
  while #current>3 do local cw=wide(current);if not cw then return nil end;local a=k.GetFileAttributesW(cw)
   if a~=0xffffffff and bit.band(a,0x400)~=0 then return nil end;current=current:match('^(.*)\\[^\\]+$')or''
  end;return w,s
 end
 local function stamp(t)return tonumber(t.high)*4294967296+tonumber(t.low)end
 function api.defaultScreensDir()
  local out=ffi.new('wchar_t[260]')
  -- CSIDL_PERSONAL follows Documents redirection (including OneDrive), unlike USERPROFILE.
  if shell.SHGetFolderPathW(nil,5,nil,0,out)~=0 then return nil,'Не найден каталог «Документы». Укажите папку вручную.'end
  return utf8(out)..'\\GTA San Andreas User Files\\SAMP\\screens'
 end
 function api.scanScreens(custom)
  local path=custom;if not path or path==''then local why;path,why=api.defaultScreensDir();if not path then return nil,why end end
  local _,dir=plain(path);if not dir then return nil,'Выберите обычную локальную папку без ссылок, переходов и служебных имён.'end
  local attrs=k.GetFileAttributesW((wide(dir)));if attrs==0xffffffff or bit.band(attrs,0x10)==0 then return nil,'Папка снимков пока не найдена. Сделайте F8 или укажите её вручную.'end
  local pattern=wide(dir..'\\_');if not pattern then return nil,'Слишком длинный путь.'end
  pattern[ffi.sizeof(pattern)/2-2]=42 -- final underscore -> *, keep NUL
  local data=ffi.new('PA41_FIND[1]');local h=k.FindFirstFileW(pattern,data)
  if h==ffi.cast('void*',-1)then if k.GetLastError()==2 then return M.summarize(dir,{})end;return nil,'Не удалось прочитать папку снимков.'end
  local rows,limit={},false;local n=0
  repeat
   n=n+1;if n>10000 then limit=true;break end
   local d=data[0];local name=utf8(d.name)
   if name~='.'and name~='..'and bit.band(d.attrs,0x400)==0 then rows[#rows+1]={name=name,path=dir..'\\'..name,directory=bit.band(d.attrs,0x10)~=0,
    created=stamp(d.created),written=stamp(d.written),size=tonumber(d.sizeHigh)*4294967296+tonumber(d.sizeLow)}end
  until k.FindNextFileW(h,data)==0
  local last=k.GetLastError();k.FindClose(h)
  if limit then return nil,'Слишком много файлов: больше 10000. Выберите отдельную папку снимков.'end
  if last~=18 and last~=0 then return nil,'Чтение папки прервано. Попробуйте снова.'end
  return M.summarize(dir,rows)
 end
 function api.archiveScreens(path,dateTag)
  if type(dateTag)~='string'or not dateTag:match('^%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d$')then return nil,'Неверная дата архива.'end
  local scan,err=api.scanScreens(path);if not scan then return nil,err end
  local dir;for i=0,99 do local candidate=scan.dir..'\\PA_Archive_'..dateTag..(i==0 and''or'_'..i)
   local w=plain(candidate);if not w then return nil,'Путь архива содержит перенаправление.'end
   if k.CreateDirectoryW(w,nil)~=0 then dir=candidate;break end
   if k.GetLastError()~=183 then return nil,'Не удалось создать папку архива. Проверьте доступ к каталогу.'end
  end
  if not dir then return nil,'Не найдено свободное имя архива. Существующие папки сохранены.'end
  local moved,skipped,eligible=0,0,0;local cutoff=api.clock()-10000000 -- leave files written during the last second
  for _,f in ipairs(scan.files)do if M.index(f.name)~=nil then
   eligible=eligible+1
   local from=plain(f.path);local to=plain(dir..'\\'..f.name)
   -- A complete stable file only. Never overwrite, delete, recurse or copy across drives.
   local verified=from and to and f.written<=cutoff and api.verify(f.path,0)
   if verified and verified.written==f.written and verified.size==f.size and k.MoveFileExW(from,to,0)~=0 then moved=moved+1 else skipped=skipped+1 end
  end end
  return {moved=moved,skipped=skipped,eligible=eligible,archiveDir=dir}
 end
 return api
end
return M

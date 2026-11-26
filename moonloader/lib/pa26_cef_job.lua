-- Initialization-only child process. Hidden, bounded lifetime/output, no
-- launcher execution or HUD writes. Optional lookup uses the official HTTPS registry.
local M={}
local jobFiles={'verify.ps1','result.tmp','result.json'}
local function validNonce(name)return #name==48 and not name:find('[^0-9a-f]')end

function M.new(ml,json,options)
 local ffi=require 'ffi';local bit=require 'bit';local platform=assert(require('pa26_update_platform').new(ml))
 local code=require 'pa26_cef_contract';local kernel=ffi.load('kernel32')
 pcall(ffi.cdef,[[
 typedef struct {unsigned long cb;wchar_t *reserved,*desktop,*title;unsigned long x,y,w,h,cx,cy,fill,flags;unsigned short show,reserved2;unsigned char* bytes;void *inHandle,*outHandle,*errHandle;} PaCefStartup;
 typedef struct {void *process,*thread;unsigned long pid,tid;} PaCefProcess;
 int __stdcall CreateProcessW(const wchar_t*,wchar_t*,void*,void*,int,unsigned long,void*,const wchar_t*,PaCefStartup*,PaCefProcess*);
 unsigned long __stdcall WaitForSingleObject(void*,unsigned long);
 int __stdcall TerminateProcess(void*,unsigned int);
 typedef struct {unsigned long low,high;} PaCefFileTime;
 typedef struct {
  unsigned long attributes;
  PaCefFileTime created,accessed,written;
  unsigned long sizeHigh,sizeLow,reserved0,reserved1;
  wchar_t name[260],alternate[14];
 } PaCefFindDataW;
 void* __stdcall PaCefFindFirstFileW(const wchar_t*,PaCefFindDataW*) __asm__("FindFirstFileW");
 int __stdcall PaCefFindNextFileW(void*,PaCefFindDataW*) __asm__("FindNextFileW");
 int __stdcall FindClose(void*);
 int __stdcall DeleteFileW(const wchar_t*);
 int __stdcall RemoveDirectoryW(const wchar_t*);
 ]])
 local function wide(s)
  local n=kernel.MultiByteToWideChar(65001,8,s,#s,nil,0);assert(n>0,'path_encoding')
  local w=ffi.new('wchar_t[?]',n+1);assert(kernel.MultiByteToWideChar(65001,8,s,#s,w,n)==n);return w
 end
 local function utf8(w)
  local n=kernel.WideCharToMultiByte(65001,0,w,-1,nil,0,nil,nil)
  if n<=0 then return ''end
  local out=ffi.new('char[?]',n)
  if kernel.WideCharToMultiByte(65001,0,w,-1,out,n,nil,nil)~=n then return ''end
  return ffi.string(out,n-1)
 end
 local base=(options.cacheRoot or platform.base:match('^(.*)\\updates$')):gsub('/','\\'):gsub('\\+$','')
 assert(base:match('^%a:\\[^\\]')and not base:find('[%c*?<>|"]')and not base:find(':',3,true)
  and not base:match('[ .]$'),'invalid_cache_path')
 local baseParent=base:match('^(.*\\)[^\\]+$')
 local checksRoot=base..'\\cef-checks'
 local jobPrefix=checksRoot..'\\'
 local function plainDirectory(attributes)
  return attributes~=0xffffffff and bit.band(attributes,0x410)==0x10
 end
 local function plainPath(path)
  local current=path:sub(1,3)
  for part in path:sub(4):gmatch('[^\\]+')do
   if part:match('[ .]$')then return false end
   current=current..part
   if not plainDirectory(kernel.GetFileAttributesW(wide(current)))then return false end
   current=current..'\\'
  end
  return true
 end
 local function removeJobDir(dir)
  if type(dir)~='string' or dir:sub(1,#jobPrefix)~=jobPrefix or not validNonce(dir:sub(#jobPrefix+1))then return end
  if not plainPath(dir)then return end
  for _,file in ipairs(jobFiles)do
   local path=wide(dir..'\\'..file)
   local attributes=kernel.GetFileAttributesW(path)
   if attributes~=0xffffffff and bit.band(attributes,0x410)==0 then pcall(kernel.DeleteFileW,path)end
  end
  pcall(kernel.RemoveDirectoryW,wide(dir))
 end
 local function pruneJobs()
  local data=ffi.new('PaCefFindDataW[1]')
  local search=kernel.PaCefFindFirstFileW(wide(jobPrefix..'*'),data)
  if search==ffi.cast('void*',-1)then return end
  -- Leave recent work from another PA instance alone. The verifier has a 30 s deadline.
  local staleBefore=(os.time()+11644473600-300)*10000000
  for i=1,64 do
   local entry=data[0]
   if plainDirectory(entry.attributes) and tonumber(entry.written.high)*4294967296+tonumber(entry.written.low)<staleBefore then
    local name=utf8(entry.name)
    if validNonce(name)then pcall(removeJobDir,jobPrefix..name)end
   end
   if i==64 or kernel.PaCefFindNextFileW(search,data)==0 then break end
  end
  kernel.FindClose(search)
 end
 local function b64(s)
  local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  local out={};for i=1,#s,3 do local a,b,c=s:byte(i,i+2);local n=a*65536+(b or 0)*256+(c or 0)
   out[#out+1]=alphabet:sub(math.floor(n/262144)%64+1,math.floor(n/262144)%64+1)..alphabet:sub(math.floor(n/4096)%64+1,math.floor(n/4096)%64+1)..(b and alphabet:sub(math.floor(n/64)%64+1,math.floor(n/64)%64+1)or'=')..(c and alphabet:sub(n%64+1,n%64+1)or'=')
  end;return table.concat(out)
 end
 local function quoted(s)return "[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"..b64(s).."'))"end
 local self={}
 function self.start()
  local nonce=assert(require('pa26_chat_bridge').entropy(ffi),'entropy')
  assert(validNonce(nonce)and plainPath(baseParent),'invalid_cache_root')
  assert(platform:mkdir(base));assert(platform:mkdir(checksRoot))
  pcall(pruneJobs)
  local root=jobPrefix..nonce
  local hud=options.hudRoot or platform.ml..'\\..\\cef\\assets\\hud'
  local script='$ErrorActionPreference="Stop"\n$env:PSModulePath=Join-Path $PSHOME Modules\n'..code.verifier..'\n$registry=('..quoted(code.registry)..' | ConvertFrom-Json)\n'..
   '$r=Get-PaCefContract ('..quoted(hud)..') $registry'..(options.onlineProfiles and' -OnlineProfiles'or'')..'\n$r.nonce="'..nonce..'"\n'..
   '$json=$r|ConvertTo-Json -Depth 8 -Compress\n[IO.File]::WriteAllText(('..quoted(root..'\\result.tmp')..'),$json,(New-Object Text.UTF8Encoding($false)))\n'..
   '[IO.File]::Move(('..quoted(root..'\\result.tmp')..'),('..quoted(root..'\\result.json')..'))\n'
  local system=ffi.new('wchar_t[260]');assert(kernel.GetSystemDirectoryW(system,260)>0)
  local exe=utf8(system)..'\\WindowsPowerShell\\v1.0\\powershell.exe'
  local args=wide('"'..exe..'" -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File '..require('pa26_update_platform').quote(root..'\\verify.ps1'))
  local startup=ffi.new('PaCefStartup[1]');startup[0].cb=ffi.sizeof('PaCefStartup');local process=ffi.new('PaCefProcess[1]')
  assert(kernel.CreateDirectoryW(wide(root),nil)~=0,'job_directory')
  if not platform:write(root..'\\verify.ps1',script)then
   pcall(removeJobDir,root)
   return nil,'write_request'
  end
  if kernel.CreateProcessW(wide(exe),args,nil,nil,0,0x08000000,nil,nil,startup,process)==0 then
   pcall(removeJobDir,root)
   return nil,'process'
  end
  kernel.CloseHandle(process[0].thread)
  return {root=root,nonce=nonce,handle=process[0].process}
 end
 function self.poll(job)
  if kernel.WaitForSingleObject(job.handle,0)==258 then return nil end
  local raw=platform:read(job.root..'\\result.json',32768);if not raw then return nil,'result_missing'end
  local good,value=pcall(json.decode,raw)
  if not good or type(value)~='table'or value.nonce~=job.nonce then return nil,'invalid_result'end
  value.nonce=nil;return value
 end
 function self.close(job,terminate)
  if job.handle then
   local status=kernel.WaitForSingleObject(job.handle,0)
   if terminate and status==258 then
    kernel.TerminateProcess(job.handle,1)
    status=kernel.WaitForSingleObject(job.handle,500)
   end
   kernel.CloseHandle(job.handle);job.handle=nil
   if status==0 then pcall(removeJobDir,job.root)end
  end
 end
 return self
end
return M

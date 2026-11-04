-- Initialization-only child process. Hidden, bounded lifetime/output, no
-- network, no launcher execution and no installation writes to the HUD.
local M={}
function M.new(ml,json,options)
 local ffi=require 'ffi';local platform=assert(require('pa26_update_platform').new(ml))
 local code=require 'pa26_cef_contract';local kernel=ffi.load('kernel32')
 pcall(ffi.cdef,[[
 typedef struct {unsigned long cb;wchar_t *reserved,*desktop,*title;unsigned long x,y,w,h,cx,cy,fill,flags;unsigned short show,reserved2;unsigned char* bytes;void *inHandle,*outHandle,*errHandle;} PaCefStartup;
 typedef struct {void *process,*thread;unsigned long pid,tid;} PaCefProcess;
 int __stdcall CreateProcessW(const wchar_t*,wchar_t*,void*,void*,int,unsigned long,void*,const wchar_t*,PaCefStartup*,PaCefProcess*);
 unsigned long __stdcall WaitForSingleObject(void*,unsigned long);
 int __stdcall TerminateProcess(void*,unsigned int);
 ]])
 local function wide(s)
  local n=kernel.MultiByteToWideChar(65001,8,s,#s,nil,0);assert(n>0,'path_encoding')
  local w=ffi.new('wchar_t[?]',n+1);assert(kernel.MultiByteToWideChar(65001,8,s,#s,w,n)==n);return w
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
  local base=options.cacheRoot or platform.base:match('^(.*)\\updates$')
  assert(platform:mkdir(base));base=base..'\\cef-checks';assert(platform:mkdir(base))
  local root=base..'\\'..nonce;assert(platform:mkdir(root))
  local hud=options.hudRoot or platform.ml..'\\..\\cef\\assets\\hud'
  local script='$ErrorActionPreference="Stop"\n$env:PSModulePath=Join-Path $PSHOME Modules\n'..code.verifier..'\n$registry=('..quoted(code.registry)..' | ConvertFrom-Json)\n'..
   '$r=Get-PaCefContract ('..quoted(hud)..') $registry\n$r.nonce="'..nonce..'"\n'..
   '$json=$r|ConvertTo-Json -Depth 8 -Compress\n[IO.File]::WriteAllText(('..quoted(root..'\\result.tmp')..'),$json,(New-Object Text.UTF8Encoding($false)))\n'..
   '[IO.File]::Move(('..quoted(root..'\\result.tmp')..'),('..quoted(root..'\\result.json')..'))\n'
  assert(platform:write(root..'\\verify.ps1',script))
  local system=ffi.new('wchar_t[260]');assert(kernel.GetSystemDirectoryW(system,260)>0)
  local n=kernel.WideCharToMultiByte(65001,0,system,-1,nil,0,nil,nil);local utf=ffi.new('char[?]',n);kernel.WideCharToMultiByte(65001,0,system,-1,utf,n,nil,nil)
  local exe=ffi.string(utf)..'\\WindowsPowerShell\\v1.0\\powershell.exe'
  local args=wide('"'..exe..'" -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File '..require('pa26_update_platform').quote(root..'\\verify.ps1'))
  local startup=ffi.new('PaCefStartup[1]');startup[0].cb=ffi.sizeof('PaCefStartup');local process=ffi.new('PaCefProcess[1]')
  assert(kernel.CreateProcessW(wide(exe),args,nil,nil,0,0x08000000,nil,nil,startup,process)~=0,'process')
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
   if terminate and kernel.WaitForSingleObject(job.handle,0)==258 then kernel.TerminateProcess(job.handle,1)end
   kernel.CloseHandle(job.handle);job.handle=nil
  end
 end
 return self
end
return M

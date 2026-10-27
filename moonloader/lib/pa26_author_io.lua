-- Data-only downloads use an independent job. The program updater is unchanged.
local M={};local ffi=require 'ffi'
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function b64(s)
 local out={};for i=1,#s,3 do local a,b,c=s:byte(i,i+2);local n=a*65536+(b or 0)*256+(c or 0)
  out[#out+1]=alphabet:sub(math.floor(n/262144)%64+1,math.floor(n/262144)%64+1)..alphabet:sub(math.floor(n/4096)%64+1,math.floor(n/4096)%64+1)..(b and alphabet:sub(math.floor(n/64)%64+1,math.floor(n/64)%64+1)or'=')..(c and alphabet:sub(n%64+1,n%64+1)or'=')
 end;return table.concat(out)
end
local function native()
 pcall(ffi.cdef,[[
 int __stdcall MoveFileExW(const wchar_t*,const wchar_t*,unsigned long);
 int __stdcall DeleteFileW(const wchar_t*);
 int __stdcall CryptAcquireContextA(uintptr_t*,const char*,const char*,unsigned long,unsigned long);
 int __stdcall CryptCreateHash(uintptr_t,unsigned int,uintptr_t,unsigned long,uintptr_t*);
 int __stdcall CryptHashData(uintptr_t,const unsigned char*,unsigned long,unsigned long);
 int __stdcall CryptGetHashParam(uintptr_t,unsigned long,unsigned char*,unsigned long*,unsigned long);
 int __stdcall CryptDestroyHash(uintptr_t);int __stdcall CryptReleaseContext(uintptr_t,unsigned long);
 ]])
 return ffi.load('kernel32'),ffi.load('advapi32')
end
local function wide(s)
 local k=ffi.load('kernel32');local cp=65001;local n=k.MultiByteToWideChar(cp,8,s,#s,nil,0)
 if n==0 then cp=0;n=k.MultiByteToWideChar(cp,0,s,#s,nil,0)end
 if n==0 then return nil end;local w=ffi.new('wchar_t[?]',n+1);k.MultiByteToWideChar(cp,cp==65001 and 8 or 0,s,#s,w,n);return w
end
function M.hash(text)
 if type(text)~='string'then return nil end
 local _,a=native();local provider,hash=ffi.new('uintptr_t[1]'),ffi.new('uintptr_t[1]')
 if a.CryptAcquireContextA(provider,nil,nil,24,0xF0000000)==0 then return nil end
 local ok=a.CryptCreateHash(provider[0],0x800c,0,0,hash)~=0
 local data,n=ffi.new('unsigned char[32]'),ffi.new('unsigned long[1]',32)
 if ok then ok=a.CryptHashData(hash[0],text,#text,0)~=0 and a.CryptGetHashParam(hash[0],2,data,n,0)~=0;a.CryptDestroyHash(hash[0])end
 a.CryptReleaseContext(provider[0],0);if not ok or n[0]~=32 then return nil end
 local out={};for i=0,31 do out[#out+1]=string.format('%02x',data[i])end;return table.concat(out)
end
function M.lock(path)
 local k=native();local w=wide(path);if not w then return nil end
 local h=k.CreateFileW(w,0xC0000000,0,nil,4,0x04000100,nil)
 if h==ffi.cast('void*',-1)then return nil end
 return function()k.CloseHandle(h)end
end
function M.new(ml)
 local p,err=require('pa26_update_platform').new(ml);if not p then return nil,err end
 local self={platform=p};local k=native()
 local function canonical(path)
  local w=wide(path);if not w then error('path_encoding')end
  local n=k.WideCharToMultiByte(65001,0,w,-1,nil,0,nil,nil);local out=ffi.new('char[?]',n);k.WideCharToMultiByte(65001,0,w,-1,out,n,nil,nil);return ffi.string(out,n-1)
 end
 local function plain(path)
  local full=canonical(path);local node=full
  while node and #node>3 do local attr=k.GetFileAttributesW(wide(node));if attr~=0xffffffff and require('bit').band(attr,0x400)~=0 then return false end;node=node:match('^(.*)\\[^\\]+$')end
  return true
 end
 self.fs={exists=function(path)return p:exists(canonical(path))end,
  read=function(path)if not plain(path)then return nil end;return p:read(canonical(path),1048576)end,
  write=function(path,text)if not plain(path)then return nil end;return p:write(canonical(path),text)end,
  rename=function(a,b)if not plain(a)or not plain(b)then return nil end;return k.MoveFileExW(wide(a),wide(b),8)~=0 end,
  remove=function(path)if not plain(path)then return nil end;return k.DeleteFileW(wide(path))~=0 end}

 function self:start(kind,repository,timeout)
  if kind~='binds'and kind~='settings'then return nil,'Неверный вид набора.'end
  if not repository:match('^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$')then return nil,'Неверный репозиторий.'end
  timeout=math.max(1,math.min(120,math.floor(timeout or 30)))
  local g=ffi.new('PaUpdateGuid[1]');if ffi.load('ole32').CoCreateGuid(g)~=0 then return nil,'Не удалось создать задание.'end
  local raw=ffi.cast('unsigned char*',g);local id='';for i=0,15 do id=id..string.format('%02x',raw[i])end
  local base=p.base:match('^(.*)\\updates$');if not base then return nil,'Неверная папка загрузки.'end
  local cache=base..'\\presets';local jobs=cache..'\\jobs';local job=jobs..'\\'..id
  for _,path in ipairs({base,cache,jobs,job})do local ok,why=p:mkdir(path);if not ok then return nil,why end end
  local code=([[
$ErrorActionPreference='Stop'
$ml=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s'))
$job=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s'))
$kind='%s';$repo='%s';$id='%s'
. (Join-Path $ml 'resource/pa26/updater/pa26-update.ps1') -Mode Library
try {
 $release=Get-PaRemote ('https://api.github.com/repos/'+$repo+'/releases/latest') 'api' 1048576 %d | ConvertFrom-Json
 if($release.draft -or $release.prerelease -or $release.tag_name -cnotmatch '^v[0-9]+\.[0-9]+\.[0-9]+$'){throw 'preset_release_invalid'}
 $name=if($kind -eq 'binds'){'pa-binds.json'}else{'pa-settings.json'}
 $asset=@($release.assets|Where-Object name -CEQ $name)
 if($asset.Count -ne 1 -or $asset[0].size -lt 1 -or $asset[0].size -gt 1048576 -or $asset[0].digest -cnotmatch '^sha256:[a-f0-9]{64}$'){throw 'preset_asset_missing'}
 $url='https://github.com/'+$repo+'/releases/download/'+$release.tag_name+'/'+$name
 if($asset[0].browser_download_url -cne $url){throw 'preset_origin_mismatch'}
 $file=Join-Path $job 'payload.json'
 Get-PaRemote $url 'asset' 1048576 %d $file
 $hash=Get-PaHash $file
 if(('sha256:'+$hash) -cne $asset[0].digest -or (Get-Item -LiteralPath $file).Length -ne $asset[0].size){throw 'preset_hash_mismatch'}
 Write-PaJson (Join-Path $job 'result.json') @{product='pa-author-preset';job=$id;kind=$kind;ok=$true;version=$release.tag_name;sha256=$hash;size=$asset[0].size}
}catch{Write-PaJson (Join-Path $job 'result.json') @{product='pa-author-preset';job=$id;kind=$kind;ok=$false;error=$_.Exception.Message}}
]]):format(b64(p.ml),b64(job),kind,repository,id,timeout,timeout)
  local utf16=code:gsub('.',function(c)return c..'\0'end)
  local system=ffi.new('wchar_t[260]');if k.GetSystemDirectoryW(system,260)==0 then return nil,'Windows PowerShell не найден.'end
  local n=0;while system[n]~=0 do n=n+1 end
  local suffix='\\WindowsPowerShell\\v1.0\\powershell.exe';local path=ffi.new('wchar_t[?]',n+#suffix+1);ffi.copy(path,system,n*2)
  for i=1,#suffix do path[n+i-1]=suffix:byte(i)end
  local args=wide('-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand '..b64(utf16))
  local launched=ffi.load('shell32').ShellExecuteW(nil,wide('open'),path,args,nil,0)
  if tonumber(ffi.cast('intptr_t',launched))<=32 then return nil,'Windows не запустила загрузку.'end
  return {id=id,root=job,kind=kind}
 end
 function self:poll(job,json)
  local raw=p:read(job.root..'\\result.json',16384);if not raw then return end
  local ok,r=pcall(json.decode,raw)
  if not ok or type(r)~='table'or r.product~='pa-author-preset'or r.job~=job.id or r.kind~=job.kind then return nil,'Неверный ответ загрузки.'end
  if r.ok~=true then return nil,'Не удалось загрузить набор. Код: '..tostring(r.error)end
  local text=p:read(job.root..'\\payload.json',1048576)
  if not text or #text~=r.size or M.hash(text)~=r.sha256 then return nil,'Загруженный файл не прошёл проверку SHA-256.'end
  return text,nil,r.version
 end
 return self
end
return M

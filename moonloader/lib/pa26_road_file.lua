-- Windows 7+ Unicode sequential reader. No writes, DLL injection or game memory.
local M={}
function M.open(path)
 if not require('pa26_road_sources').absolute(path)then return nil,'Недопустимый путь.'end
 local ffi=require 'ffi'
 pcall(ffi.cdef,[[
 int __stdcall MultiByteToWideChar(unsigned int,unsigned long,const char*,int,wchar_t*,int);
 void* __stdcall CreateFileW(const wchar_t*,unsigned long,unsigned long,void*,unsigned long,unsigned long,void*);
 int __stdcall ReadFile(void*,void*,unsigned long,unsigned long*,void*);
 int __stdcall CloseHandle(void*);
 ]])
 local k=ffi.load('kernel32');local n=k.MultiByteToWideChar(65001,8,path,#path,nil,0)
 if n<=0 then return nil,'Путь не читается в Unicode.'end
 local wide=ffi.new('wchar_t[?]',n+1);if k.MultiByteToWideChar(65001,8,path,#path,wide,n)~=n then return nil,'Не удалось прочитать путь.'end
 local h=k.CreateFileW(wide,0x80000000,5,nil,3,0x08000080,nil)
 if h==ffi.cast('void*',-1)then return nil,'Файл отсутствует или недоступен.'end
 local f={handle=h,buffer=ffi.new('uint8_t[16384]'),count=ffi.new('unsigned long[1]')}
 function f:read(size)
  assert(self.handle and type(size)=='number'and size>=1 and size<=16384 and size%1==0,'invalid graph read')
  if k.ReadFile(self.handle,self.buffer,size,self.count,nil)==0 then error('Ошибка чтения дорожного файла')end
  if self.count[0]==0 then return nil end
  return ffi.string(self.buffer,self.count[0])
 end
 function f:close()if self.handle then k.CloseHandle(self.handle);self.handle=nil end end
 return f
end
return M

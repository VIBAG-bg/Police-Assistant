-- Documented Windows file APIs only; no GTA/SAMP offsets or screenshot injection.
local M={}
function M.new()
    local ffi=require 'ffi'
    if ffi.os~='Windows'then return {clock=function()end,verify=function()return nil,'Проверка файлов доступна только в Windows.'end}end
    pcall(ffi.cdef,[[
        typedef struct { unsigned long low, high; } PA25_FILETIME;
        typedef struct { unsigned long attributes; PA25_FILETIME created, accessed, written; unsigned long sizeHigh, sizeLow; } PA25_FILEDATA;
        int __stdcall MultiByteToWideChar(unsigned int,unsigned long,const char*,int,unsigned short*,int);
        void __stdcall GetSystemTimeAsFileTime(PA25_FILETIME*);
        int __stdcall GetFileAttributesExW(const unsigned short*,int,void*);
        void* __stdcall CreateFileW(const unsigned short*,unsigned long,unsigned long,void*,unsigned long,unsigned long,void*);
        int __stdcall ReadFile(void*,void*,unsigned long,unsigned long*,void*);
        int __stdcall SetFilePointerEx(void*,long long,long long*,unsigned long);
        int __stdcall CloseHandle(void*);
    ]])
    local k=ffi.load('kernel32')
    local function stamp(t)return tonumber(t.high)*4294967296+tonumber(t.low)end
    local function wide(path)
        if type(path)~='string'or #path>1024 or path:find('%c')or not(path:match('^[A-Za-z]:[\\/]'))or path:find(':',3,true)then return nil end
        if path:find('..',1,true)then return nil end
        local n=k.MultiByteToWideChar(65001,8,path,#path,nil,0);if n<=0 then return nil end
        local w=ffi.new('unsigned short[?]',n+1);if k.MultiByteToWideChar(65001,8,path,#path,w,n)~=n then return nil end;return w
    end
    local function attributes(w)
        local a=ffi.new('PA25_FILEDATA[1]');if k.GetFileAttributesExW(w,0,a)==0 then return end
        return {created=stamp(a[0].created),written=stamp(a[0].written),size=tonumber(a[0].sizeHigh)*4294967296+tonumber(a[0].sizeLow),attributes=tonumber(a[0].attributes)}
    end
    return {clock=function()local t=ffi.new('PA25_FILETIME[1]');k.GetSystemTimeAsFileTime(t);return stamp(t[0])end,
        verify=function(path,since)
            local ext=type(path)=='string'and path:lower():match('%.([a-z]+)$')
            if ext~='png'and ext~='jpg'and ext~='jpeg'then return nil,'Укажите PNG или JPG, созданный после начала фиксации.'end
            local w=wide(path);if not w then return nil,'Нужен полный локальный путь без переходов .. и служебных символов.'end
            local a=attributes(w)
            if not a or a.attributes%32>=16 or a.size<32 or a.size>134217728 then return nil,'Файл не найден, пуст, ещё записывается или больше 128 МБ.'end
            if type(since)~='number'or a.created<since or a.written<since then return nil,'Этот файл появился раньше начала фиксации. Сделайте новый снимок.'end
            local h=k.CreateFileW(w,2147483648,7,nil,3,128,nil)
            if h==nil or h==ffi.cast('void*',-1)then return nil,'Не удалось прочитать снимок.'end
            local buf=ffi.new('unsigned char[32]');local read=ffi.new('unsigned long[1]')
            local ok=k.ReadFile(h,buf,32,read,nil);local count=tonumber(read[0]);local header=ffi.string(buf,count)
            local tailSize=ext=='png'and 12 or 2
            local seek=k.SetFilePointerEx(h,-tailSize,nil,2);local tail=ffi.new('unsigned char[12]')
            local tailOk=seek~=0 and k.ReadFile(h,tail,tailSize,read,nil)~=0 and read[0]==tailSize
            k.CloseHandle(h)
            if ok==0 or count<32 or not tailOk then return nil,'Снимок ещё не готов.'end
            local ending=ffi.string(tail,tailSize)
            if ext=='png'and(a.size<67 or header:sub(1,16)~='\137PNG\r\n\26\n\0\0\0\13IHDR'or ending~='\0\0\0\0IEND\174\66\96\130')or
                ext~='png'and(header:byte(1)~=255 or header:byte(2)~=216 or header:byte(3)~=255 or ending~='\255\217')then return nil,'Формат или окончание снимка не подтверждены. Дождитесь записи нового PNG/JPG.'end
            local after=attributes(w)
            if not after or after.size~=a.size or after.written~=a.written then return nil,'Снимок ещё записывается. Повторите проверку.'end
            a.path=path;a.key=path..':'..a.size..':'..string.format('%.0f',a.created)..':'..string.format('%.0f',a.written)
            return a
        end}
end
return M

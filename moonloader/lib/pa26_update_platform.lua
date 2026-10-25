-- Protocol-1 bootstrap. Automatic packages must keep this file byte-identical.
-- No game chat, shell interpolation, credentials or network calls here.
local M={PROTOCOL=1}
local function absolute(path)return type(path)=='string'and path:match('^%a:[/\\]')and not path:find('[%z\r\n]')end
M.absolute=absolute
local function quote(s)return '"'..s:gsub('(\\*)"','%1%1\\"'):gsub('(\\+)$','%1%1')..'"'end
M.quote=quote
function M.new(ml)
    if not absolute(ml)or not ml:gsub('/','\\'):lower():match('\\moonloader$')then return nil,'invalid_game_root'end
    ml=ml:gsub('/','\\')
    local ffi=require 'ffi'
    local bit=require 'bit'
    pcall(ffi.cdef,[[
        int __stdcall MultiByteToWideChar(unsigned int,unsigned long,const char*,int,wchar_t*,int);
        int __stdcall WideCharToMultiByte(unsigned int,unsigned long,const wchar_t*,int,char*,int,const char*,int*);
        int __stdcall SHGetFolderPathW(void*,int,void*,unsigned long,wchar_t*);
        unsigned int __stdcall GetSystemDirectoryW(wchar_t*,unsigned int);
        unsigned int __stdcall GetWindowsDirectoryW(wchar_t*,unsigned int);
        unsigned long __stdcall GetFileAttributesW(const wchar_t*);
        int __stdcall CreateDirectoryW(const wchar_t*,void*);
        void* __stdcall CreateFileW(const wchar_t*,unsigned long,unsigned long,void*,unsigned long,unsigned long,void*);
        int __stdcall ReadFile(void*,void*,unsigned long,unsigned long*,void*);
        int __stdcall GetFileSizeEx(void*,long long*);
        int __stdcall WriteFile(void*,const void*,unsigned long,unsigned long*,void*);
        int __stdcall CloseHandle(void*);int __stdcall CopyFileW(const wchar_t*,const wchar_t*,int);
        int __stdcall FlushFileBuffers(void*);
        typedef struct {unsigned long a;unsigned short b,c;unsigned char d[8];} PaUpdateGuid;
        long __stdcall CoCreateGuid(PaUpdateGuid*);
        void* __stdcall ShellExecuteW(void*,const wchar_t*,const wchar_t*,const wchar_t*,const wchar_t*,int);
        int __stdcall MessageBoxW(void*,const wchar_t*,const wchar_t*,unsigned int);
    ]])
    local kernel=ffi.load('kernel32');local shell=ffi.load('shell32');local ole=ffi.load('ole32');local user=ffi.load('user32')
    local function wide(s,cp)
        cp=cp or 65001;local flags=cp==65001 and 8 or 0
        local n=kernel.MultiByteToWideChar(cp,flags,s,#s,nil,0);assert(n>0,'path_encoding')
        local out=ffi.new('wchar_t[?]',n+1);assert(kernel.MultiByteToWideChar(cp,flags,s,#s,out,n)==n);return out
    end
    local function utf8(w)
        local n=kernel.WideCharToMultiByte(65001,0,w,-1,nil,0,nil,nil);assert(n>0)
        local out=ffi.new('char[?]',n);kernel.WideCharToMultiByte(65001,0,w,-1,out,n,nil,nil);return ffi.string(out,n-1)
    end
    -- MoonLoader can return a system-codepage path; convert it once.
    local ok=pcall(function()wide(ml)end)
    if not ok then ml=utf8(wide(ml,0))end
    local app=ffi.new('wchar_t[260]');assert(shell.SHGetFolderPathW(nil,0x1c,nil,0,app)==0,'local_appdata')
    local system=ffi.new('wchar_t[260]');assert(kernel.GetSystemDirectoryW(system,260)>0,'system_directory')
    local windows=ffi.new('wchar_t[260]');assert(kernel.GetWindowsDirectoryW(windows,260)>0,'windows_directory')
    local powershell=utf8(system)..'\\WindowsPowerShell\\v1.0\\powershell.exe'
    local explorer=utf8(windows)..'\\explorer.exe'
    local base=utf8(app)..'\\PoliceAssistant2026\\updates';local jobs=base..'\\jobs'
    local self={ml=ml,base=base,jobs=jobs}
    function self:exists(path)return kernel.GetFileAttributesW(wide(path))~=0xffffffff end
    function self:mkdir(path)
        if self:exists(path)then
            local attr=kernel.GetFileAttributesW(wide(path));if bit.band(attr,0x400)~=0 or bit.band(attr,0x10)==0 then return nil,'reparse_path'end
            return true
        end
        if kernel.CreateDirectoryW(wide(path),nil)==0 then return nil,'create_directory'end;return true
    end
    function self:read(path,limit)
        local h=kernel.CreateFileW(wide(path),0x80000000,7,nil,3,0x80,nil)
        if h==ffi.cast('void*',-1)then return nil end
        local size=ffi.new('long long[1]')
        if kernel.GetFileSizeEx(h,size)==0 or size[0]<0 or size[0]>limit then kernel.CloseHandle(h);return nil,'read_status'end
        local n=tonumber(size[0]);local b=ffi.new('char[?]',n+1);local count=ffi.new('unsigned long[1]')
        local success=kernel.ReadFile(h,b,n+1,count,nil)~=0;kernel.CloseHandle(h)
        if not success or count[0]~=n then return nil,'read_status'end;return ffi.string(b,count[0])
    end
    function self:write(path,text)
        local h=kernel.CreateFileW(wide(path),0x40000000,0,nil,2,0x80000080,nil)
        if h==ffi.cast('void*',-1)then return nil,'write_request'end
        local count=ffi.new('unsigned long[1]');local success=kernel.WriteFile(h,text,#text,count,nil)~=0 and count[0]==#text
        if success then success=kernel.FlushFileBuffers(h)~=0 end;kernel.CloseHandle(h)
        return success or nil,'write_request'
    end
    function self:launch(mode,job)
        if not({Check=true,Prepare=true,Status=true,Recover=true})[mode]or not job:match('^[0-9a-f]+$')or #job~=32 then return nil,'invalid_request'end
        local root=jobs..'\\'..job;local script=root..'\\pa26-update.ps1'
        local args='-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File '..quote(script)..' -Mode '..mode..' -MoonLoader '..quote(ml)..' -JobRoot '..quote(root)
        local result=shell.ShellExecuteW(nil,wide('open'),wide(powershell),wide(args),nil,0)
        if tonumber(ffi.cast('intptr_t',result))<=32 then return nil,'launch_failed'end;return true
    end
    function self:start(mode,json)
        local parent=base:match('^(.*)\\updates$');assert(self:mkdir(parent));assert(self:mkdir(base));assert(self:mkdir(jobs))
        local guid=ffi.new('PaUpdateGuid[1]');assert(ole.CoCreateGuid(guid)==0,'job_id')
        local bytes=ffi.cast('unsigned char*',guid);local parts={};for i=0,15 do parts[#parts+1]=string.format('%02x',bytes[i])end
        local job=table.concat(parts);local root=jobs..'\\'..job;assert(self:mkdir(root))
        local worker=ml..'\\resource\\pa26\\updater\\pa26-update.ps1'
        if kernel.CopyFileW(wide(worker),wide(root..'\\pa26-update.ps1'),1)==0 then return nil,'copy_worker'end
        if json then local good,why=self:write(root..'\\request.json',json);if not good then return nil,why end end
        local launched,why=self:launch(mode,job);if not launched then return nil,why end
        return {id=job,mode=mode,root=root}
    end
    function self:poll(job)return self:read(job.root..'\\status.json',1048576)end
    function self:adopt(job)
        if type(job)~='string'or #job~=32 or not job:match('^[0-9a-f]+$')then return nil end
        local root=jobs..'\\'..job
        return {id=job,root=root,mode='Prepare'},self:read(root..'\\request.json',1048576)
    end
    function self:cancel(job)return self:write(job.root..'\\cancel','cancel')end
    function self:seen(job)
        if type(job)=='string'and #job==32 and job:match('^[0-9a-f]+$')then return self:write(jobs..'\\'..job..'\\receipt.seen','seen')end
    end
    function self:openBackups()shell.ShellExecuteW(nil,wide('open'),wide(explorer),wide(quote(base..'\\games')),nil,1)end
    function self:gate()
        local marker=ml..'\\pa26-update.pending';if not self:exists(marker)then return false end
        local pending=self:read(marker,128)or''
        if pending:match('^[0-9a-f]+$')and #pending==32 then pcall(self.launch,self,'Recover',pending)end
        user.MessageBoxW(nil,wide('PA: обновление было прервано или ещё не завершено.\nЗакройте GTA и дождитесь восстановления. Личные файлы не заменяются.\nДо завершения PA приостановлен, чтобы не загружать разные версии модулей.'),wide('Обновление Police Assistant'),0x30)
        return true
    end
    return self
end
return M

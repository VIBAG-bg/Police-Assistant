local ffi=require 'ffi'
if ffi.os~='Windows'then check(true);return end
local files=require('pa26_evidence_files').new()
local path=TEST_TEMP_PATH..'.png';local since=files.clock();check(type(since)=='number')
local bytes=('89504e470d0a1a0a0000000d4948445200000001000000010804000000b51c0c020000000b4944415478da6364f80f00010501012718e3660000000049454e44ae426082'):gsub('..',function(c)return string.char(tonumber(c,16))end)
local f=assert(io.open(path,'wb'));f:write(bytes);f:close()
local a,err=files.verify(path,since);check(a,err);eq(a.size,#bytes);eq(a.path,path)
check(not files.verify(path,files.clock()+10000000),'An older file cannot be approved')
check(not files.verify(path..':stream',since));check(not files.verify('relative.png',since));check(not files.verify('C:\\x\\..\\fake.png',since))
f=assert(io.open(path,'wb'));f:write(bytes:sub(1,40));f:close();check(not files.verify(path,since),'A partial PNG must not pass')
f=assert(io.open(path,'wb'));f:write(string.rep('x',80));f:close();check(not files.verify(path,since))
os.remove(path)

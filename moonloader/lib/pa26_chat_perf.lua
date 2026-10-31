-- Opt-in aggregate timing only. No arguments, chat text, identities or paths.
local M={};local P={};P.__index=P
local buckets={.05,.1,.25,.5,1,2,4,8,16,33,50,100,250,1000,math.huge}
local allowed={frame=true,context=true,updateGame=true,onWindowMessage=true,bridgeTick=true,bridgeExchange=true}
function M.clock(ffi)
 local ok,read=pcall(function()
  if ffi.os~='Windows'then return end
  ffi.cdef('int __stdcall QueryPerformanceCounter(int64_t*); int __stdcall QueryPerformanceFrequency(int64_t*);')
  local api=ffi.load('kernel32');local count,frequency=ffi.new('int64_t[1]'),ffi.new('int64_t[1]')
  if api.QueryPerformanceFrequency(frequency)==0 or tonumber(frequency[0])<=0 then return end
  local scale=1000/tonumber(frequency[0])
  return function()api.QueryPerformanceCounter(count);return tonumber(count[0])*scale end
 end)
 return ok and read or function()return os.clock()*1000 end
end
function M.new(clock,log)return setmetatable({clock=clock,log=log,enabled=false,rows={}},P)end
function P:record(name,ms)
 if not self.enabled or not allowed[name]or type(ms)~='number'or ms~=ms or ms<0 or ms==math.huge then return end
 local r=self.rows[name];if not r then r={n=0,sum=0,max=0,h={}};self.rows[name]=r end
 r.n=r.n+1;r.sum=r.sum+ms;r.max=math.max(r.max,ms)
 for i,limit in ipairs(buckets)do if ms<=limit then r.h[i]=(r.h[i]or 0)+1;break end end
end
function P:flush()
 for name,r in pairs(self.rows)do
  local sum,p95=0,0
  for i,limit in ipairs(buckets)do sum=sum+(r.h[i]or 0);if sum>=r.n*.95 then p95=limit;break end end
  if self.log then self.log(string.format('CEF PERF %s: n=%d avg_ms=%.4f p95_le_ms=%s max_ms=%.4f',name,r.n,r.sum/r.n,tostring(p95),r.max))end
 end
 self.rows={}
end
function P:setEnabled(value)
 value=value==true;if value==self.enabled then return end
 if self.enabled then self:flush()end
 self.enabled=value;self.lastFrame=nil;self.reportAt=nil;self.rows={}
end
function P:frame()
 if not self.enabled then return end
 local now=self.clock();if self.lastFrame then self:record('frame',now-self.lastFrame)end;self.lastFrame=now
 self.reportAt=self.reportAt or now
 if now-self.reportAt>=30000 then self:flush();self.reportAt=now end
end
function P:wrap(name,fn)
 assert(allowed[name])
 return function(...)
  if not self.enabled then return fn(...)end
  local start=self.clock();local a,b,c=fn(...);self:record(name,self.clock()-start);return a,b,c
 end
end
return M

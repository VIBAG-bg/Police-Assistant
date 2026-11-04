-- One shared PA-owned verifier, run once outside the game thread. No launcher
-- JavaScript is executed by it. Decisions are cached until PA is restarted.
local core=require 'pa26_core'
local M={max_bytes=4194304,reviewed='c458636ad5201c00aaf1e21e80bbf7fa74670734fcd0f66c812d495c893bd410'}
function M.controller(env)
 local self={env=env,report={state='UNAVAILABLE',allowed=false,reason='analysis_pending',runtime='NOT_RUN',capabilities={}}}
 function self:check(now)
  if self.done then return self.report end
  if not self.job then
   local ok,job=pcall(self.env.start)
   if not ok or not job then self.done=true;self.report.reason='analysis_start_failed';return self.report end
   self.job=job;self.started=now
  end
  local age=core.elapsed(now,self.started)
  if not age or age>30000 then
   if self.env.close then pcall(self.env.close,self.job,true)end
   self.done=true;self.report.reason='analysis_timeout';return self.report
  end
  if self.polled and(core.elapsed(now,self.polled)or 0)<500 then return self.report end
  self.polled=now
  local ok,value,err=pcall(self.env.poll,self.job)
  if not ok or err then self.done=true;self.report.reason='analysis_failed'
  elseif value then
   local valid=value.schema==2 and type(value.known)=='boolean'and type(value.allowed)=='boolean'and type(value.reason)=='string'and #value.reason<=160
   valid=valid and(value.state=='CONTRACT_COMPATIBLE'or value.state=='INCOMPATIBLE'or value.state=='UNAVAILABLE')
   if value.allowed then valid=valid and value.state=='CONTRACT_COMPATIBLE'and type(value.sha256)=='string'and #value.sha256==64 and not value.sha256:find('[^a-f0-9]')and type(value.fingerprint)=='string'and #value.fingerprint<=120 and type(value.capabilities)=='table'
    for _,name in ipairs({'dom','outgoing','incoming','payloads','lifecycle','focus','ipc','adapter_order'})do valid=valid and value.capabilities[name]==true end
   end
   self.done=true
   if valid then self.report=value else self.report.reason='analysis_invalid_reply'end
  end
  if self.done and self.env.close then pcall(self.env.close,self.job,false)end
  return self.report
 end
 function self:close()if self.job and self.env.close then pcall(self.env.close,self.job,true)end;self.done=true end
 return self
end
function M.runtime(ml,json,options)
 local ok,worker=pcall(require('pa26_cef_job').new,ml,json,options or{})
 if not ok or not worker then return M.controller({start=function()return nil end})end
 return M.controller(worker)
end
return M

"""Individual offline handler timings. Includes Lupa/fixture overhead, not GTA FPS."""
from pathlib import Path
import argparse,datetime,json,os,statistics,time
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);args=p.parse_args()
def measure(root):
 os.chdir(root)
 ns={'__file__':str(root/'tests/run_tests.py')}
 source=(root/'tests/run_tests.py').read_text('utf-8').split('syntax_lua = runtime()')[0]
 exec(compile(source,str(root/'tests/run_tests.py'),'exec'),ns);lua=ns['runtime']()
 lua.execute(b"""
 local f=require 'support.fixture'; B=f({demo=false,render=false});B.step()
 if B.frames[1].condition()then B.commands.pa26();B.step()end
 B.chatBridge.server={accept=function()return nil,'timeout'end,close=function()end}
 B.chatBridge.state={at=B.now,busy=true,chat=true,dialog=false};B.step()
 local function find(fn,key,seen)
  seen=seen or{};if type(fn)~='function'or seen[fn]then return end;seen[fn]=true
  for i=1,100 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==key then return v end end
  for i=1,100 do local n,v=debug.getupvalue(fn,i);if not n then break end;if type(v)=='function'then local found=find(v,key,seen);if found then return found end end end
 end
 UPDATE=find(main,'updateGame');CONTEXT=find(main,'context')
 PAYLOAD='{"schema":1,"page":"perf","chat":true,"dialog":false,"busy":true,"events":[]}'
 """)
 out={}
 cases=[('onWindowMessage.mouse','onWindowMessage(0x200,0,0)',6000),('onWindowMessage.char','onWindowMessage(0x102,65,0)',6000),
  ('onWindowMessage.key','onWindowMessage(0x100,65,0)',6000),('Bridge.tick','B.chatBridge:tick(B.now)',2000),
  ('Bridge.exchange','B.chatBridge:exchange(PAYLOAD,B.now)',500),('context','CONTEXT()',800),('updateGame','UPDATE()',800)]
 for name,code,count in cases:
  if name=='context'and not lua.globals()[b'CONTEXT']or name=='updateGame'and not lua.globals()[b'UPDATE']:
   out[name]={'status':'not_exposed'};continue
  fn=lua.eval(('function()'+code+' end').encode())
  for _ in range(80):fn()
  samples=[]
  for _ in range(count):
   start=time.perf_counter_ns();fn();samples.append((time.perf_counter_ns()-start)/1_000_000)
  samples.sort();out[name]={'samples':count,'median_ms':statistics.median(samples),'p95_ms':samples[int(count*.95)],'worst_handler_ms':max(samples)}
 lua.execute(b'onScriptTerminate(B.script)');return out
report={'measured_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'environment':'LuaJIT 2.1 + existing offline fixture + Lupa calls',
 'game_started':False,'actual_input_latency_measured':False,'actual_frame_time_spikes_measured':False,'chat_contents_recorded':False,
 'rows':{'v0.43.2':measure(args.baseline.resolve()),'v0.44.0':measure(ROOT)}}
os.chdir(ROOT);(ROOT/'tests/LUA_PERFORMANCE0440.json').write_text(json.dumps(report,indent=2)+'\n','utf-8')
print(json.dumps(report))

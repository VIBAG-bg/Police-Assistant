"""Bounded bundled-graph preparation/search measurements, never GTA frame latency."""
from pathlib import Path
import hashlib,json,statistics,time
from lupa.luajit21 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
road=ROOT/'moonloader/resource/pa26/roads.bin'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before=sha(road)
assert road.stat().st_size==589664 and before=='c1d347286ccb0349940800570078c6872bef31c12ac6d6f77a4b1cf8b857d7db'
runs=[]
for trial in range(3):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.globals().MODULES=(ROOT/'moonloader/lib/?.lua').as_posix()
    lua.globals().ROAD=road.as_posix()
    lua.globals().ML=(ROOT/'moonloader').as_posix()
    lua.execute(r"""
      package.path=MODULES..';'..package.path
      OPENS=0
      local resolver=require('pa26_road_sources').new({script=function()return ML..'/police_assistant_2026.lua'end,
       moonloader=function()return ML end,open=function(path)
        assert(path:gsub('\\','/')==ROAD,'Standalone test must only read the packaged graph')
        OPENS=OPENS+1;return io.open(ROAD,'rb')
       end})
      G=require('pa26_navigation_roads').new({hash=require('pa26_author_io').hash,openCandidate=function(i,c)return resolver:open(i,c)end})
      C={road_work=256,road_budget_ms=1}
      G:prepare('')
    """)
    tick=lua.eval('function()G:tick(C,true);return G.phase,G.lastOps end')
    def measure(done):
        samples=[];maximum=0;worst_stage='';worst=-1;start=time.perf_counter()
        for frame in range(10000):
            at=time.perf_counter_ns();phase,ops=tick();elapsed=(time.perf_counter_ns()-at)/1e6;samples.append(elapsed)
            if elapsed>worst:worst=elapsed;worst_stage=lua.eval('G.status')
            maximum=max(maximum,ops)
            if done():break
        assert done() and maximum<=256
        samples.sort()
        return {'slices':len(samples),'max_work_units_per_slice':maximum,
                'total_offline_wall_ms':(time.perf_counter()-start)*1000,
                'slice_p50_ms':statistics.median(samples),'slice_p95_ms':samples[int(len(samples)*.95)],
                'slice_p99_ms':samples[int(len(samples)*.99)],'worst_slice_ms':max(samples),'worst_stage':worst_stage}
    prep=measure(lambda:lua.eval("G.phase~='loading'"))
    assert lua.eval("G.phase=='ready' and G:view().sourceId=='bundled'")
    phases={'prepare_graph':prep}
    for name,start,end in [('first_route',(1500,-1700),(-2000,200)),('subsequent_route',(-2000,200),(1500,-1700))]:
        lua.execute(f'J=G:begin({{x={start[0]},y={start[1]}}},{{x={end[0]},y={end[1]}}},300)')
        item=measure(lambda:lua.eval('J.done==true'))
        done,count,distance,why=lua.eval('function()local d,p,l,w=G:poll(J);return d,p and #p,l,w end')()
        assert done and count and distance>0,(count,distance,why)
        item.update(route_nodes=count,road_distance=distance)
        phases[name]=item;lua.execute('G:cancel(J)')
    assert lua.eval('OPENS')==1,'Do not reparse/read the graph for subsequent destinations'
    lua.execute('G:reset();assert(not G.handle and not G.graph and not G.job)')
    runs.append({'trial':trial+1,'file_opens':1,'phases':phases})
assert sha(road)==before
modules=['pa26_navigation_roads.lua','pa26_road_sources.lua','pa26_road_file.lua','pa26_sha256.lua']
result={'version':'0.45.0','status':'passed','environment':'LuaJIT 2.1 + Lupa; packaged LGPS v1; synthetic world endpoints; no launcher files',
        'roads_sha256':before,'backend_sha256':sha(ROOT/'moonloader/lib/pa26_navigation_roads.lua'),
        'source_sha256':{n:sha(ROOT/'moonloader/lib'/n)for n in modules},
        'trials':3,'runs':runs,'game_started':False,'game_written':False,'road_data_included_in_package':True,
        'gta_frame_times_measured':False,'actual_input_latency_measured':False,'waypoint_to_visible_route_ms':'NOT RUN',
        'time_scope':'Offline CPU/wall handler timings; slices run consecutively and are not real GTA frames'}
(ROOT/'tests/ROADS_PERFORMANCE0450.json').write_text(json.dumps(result,indent=2)+'\n','utf-8')
print(json.dumps({'status':'passed','trials':runs,'game_latency':'NOT RUN'},ensure_ascii=False))

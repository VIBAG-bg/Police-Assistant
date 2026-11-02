"""Render captured real ImGui CPU meshes/atlas to PNG; not a GTA screenshot."""
from pathlib import Path
import argparse,json,numpy as np
from PIL import Image
parser=argparse.ArgumentParser();parser.add_argument('capture',type=Path);parser.add_argument('output',type=Path);args=parser.parse_args()
root=args.capture;out=args.output;out.mkdir(parents=True,exist_ok=True)
for path in sorted(root.glob('*.json')):
 meta=json.loads(path.read_text());w,h=meta['width'],meta['height'];aw,ah=meta['atlas']['w'],meta['atlas']['h']
 atlas=np.frombuffer((root/'atlas.rgba').read_bytes(),dtype=np.uint8).reshape(ah,aw,4).astype(np.float32)/255
 textures={str(t['id']):np.asarray(Image.open(t['path']).convert('RGBA'),dtype=np.float32)/255 for t in meta.get('textures',[])}
 canvas=np.empty((h,w,3),np.float32);canvas[:]=[.018,.035,.055]
 for item in meta['lists']:
  dtype=np.dtype([('x','<f4'),('y','<f4'),('u','<f4'),('v','<f4'),('col','<u4')])
  v=np.frombuffer((root/(item['file']+'.verts')).read_bytes(),dtype=dtype)
  indices=np.frombuffer((root/(item['file']+'.indices')).read_bytes(),dtype='<u2');offset=0
  for cmd in item['commands']:
   texture=textures.get(cmd.get('texture'),atlas);th,tw=texture.shape[:2]
   clip=cmd['clip'];end=offset+cmd['count']
   for ids in indices[offset:end].reshape(-1,3):
    a,b,c=v[ids];x0=max(0,int(clip[0]),int(np.floor(min(a['x'],b['x'],c['x']))));x1=min(w,int(np.ceil(clip[2])),int(np.ceil(max(a['x'],b['x'],c['x']))))
    y0=max(0,int(clip[1]),int(np.floor(min(a['y'],b['y'],c['y']))));y1=min(h,int(np.ceil(clip[3])),int(np.ceil(max(a['y'],b['y'],c['y']))))
    if x1<=x0 or y1<=y0:continue
    den=(b['y']-c['y'])*(a['x']-c['x'])+(c['x']-b['x'])*(a['y']-c['y'])
    if abs(den)<1e-7:continue
    yy,xx=np.mgrid[y0:y1,x0:x1];xx=xx+.5;yy=yy+.5
    wa=((b['y']-c['y'])*(xx-c['x'])+(c['x']-b['x'])*(yy-c['y']))/den
    wb=((c['y']-a['y'])*(xx-c['x'])+(a['x']-c['x'])*(yy-c['y']))/den;wc=1-wa-wb
    mask=(wa>=-1e-6)&(wb>=-1e-6)&(wc>=-1e-6)
    if not mask.any():continue
    wa,wb,wc=wa[mask],wb[mask],wc[mask]
    u=np.clip(((wa*a['u']+wb*b['u']+wc*c['u'])*tw).astype(int),0,tw-1)
    tv=np.clip(((wa*a['v']+wb*b['v']+wc*c['v'])*th).astype(int),0,th-1)
    colors=np.array([[int(q['col'])>>s&255 for s in [0,8,16,24]]for q in [a,b,c]],np.float32)/255
    rgba=(wa[:,None]*colors[0]+wb[:,None]*colors[1]+wc[:,None]*colors[2])*texture[tv,u]
    dest=canvas[y0:y1,x0:x1];alpha=rgba[:,3,None];dest[mask]=rgba[:,:3]*alpha+dest[mask]*(1-alpha)
   offset=end
 Image.fromarray(np.clip(canvas*255,0,255).astype('uint8')).save(out/(path.stem+'.png'))
 print(path.stem,flush=True)

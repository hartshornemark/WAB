"""Recover Boeing top-view curves via LibreDWG JSON; produce a clean overlay SVG.
Run dwgread -O JSON -o /tmp/max9.json against the supplied original first.
PYTHONPATH must include ezdxf. No station datum is inferred from CAD insertion coordinates.
"""
from pathlib import Path
import json, hashlib
from xml.etree import ElementTree as ET
import json,ezdxf
from ezdxf.math import BSpline
from ezdxf.path import make_path
from xml.etree import ElementTree as ET
from pathlib import Path
O=json.load(open('/tmp/max9.json',encoding='latin1'))['OBJECTS']; lookup={o['handle'][2]:o for o in O}; b=next(o for o in O if o.get('object')=='BLOCK_HEADER' and o.get('name')=='737-9 TOP VIEW'); es=[lookup[h[-1]] for h in b['entities']]
d=ezdxf.new();m=d.modelspace(); paths=[]
for e in es:
 typ=e.get('entity');pts=[]
 if typ=='LWPOLYLINE':
  bulges=e.get('bulges',[]); ent=m.add_lwpolyline([(p[0],p[1],bulges[i] if i<len(bulges) else 0) for i,p in enumerate(e['points'])],format='xyb',close=bool(e['flag']&512)); pts=list(make_path(ent).flattening(.15))
 elif typ=='LINE':pts=[e['start'],e['end']]
 elif typ=='SPLINE':
  c=e['ctrl_pts']; s=BSpline([(p['x'],p['y'],p['z']) for p in c],order=e['degree']+1,knots=e['knots'],weights=[p['w'] for p in c]);pts=list(s.flattening(.15))
 if pts: paths.append((e['handle'][2],[(p[0],p[1]) for p in pts]))

nose=min(x for _,p in paths for x,y in p)
tail=max(x for _,p in paths for x,y in p)
centre=(366.296991260884+512.474791260884)/2
scale=240/(tail-nose)
svg=ET.Element('svg',xmlns='http://www.w3.org/2000/svg',viewBox='0 0 248 50',width='1984',height='400',role='img')
ET.SubElement(svg,'title').text='Boeing 737 MAX 9 fuselage — tail left, nose right'
ET.SubElement(svg,'desc').text='Derived from Boeing 737-9_3VIEW.dwg, 2020. Original top-view curves retained; wings omitted and tail surfaces cropped. Boeing identifies the source as airport-planning geometry accurate within plus or minus six inches. CAD coordinates do not establish the weight-and-balance datum.'
g=ET.SubElement(svg,'g',fill='none',stroke='#858b92',**{'stroke-width':'0.16','stroke-linejoin':'round','stroke-linecap':'round'})
for h,p in paths:
 ET.SubElement(g,'path',id=f'boeing-{h}',d='M'+' L'.join(f'{244-(x-nose)*scale:.5f},{25+(y-centre)*scale:.5f}' for x,y in p))
out=Path('output/aircraft-calibration/737-max9/737-max9-fuselage.svg');out.write_bytes(ET.tostring(svg,encoding='utf-8',xml_declaration=True))
meta={'aircraftType':'7M9','series':'900','source':'Boeing 737-9_3VIEW.dwg','noseX':244,'centreY':25,'span':240,'cadNoseX':nose,'cadTailX':tail,'cadDrawingUnits':'inches, verified against dimension annotations (header units disagree)','cadLengthInches':tail-nose,'lengthMetres':(tail-nose)*.0254,'noseArmMetres':3.302,'noseStationInches':130,'datumStatus':'User-provided 130 inches forward of nose; MAX 9-specific Weight and Balance Manual confirmation pending','sha256':hashlib.sha256(out.read_bytes()).hexdigest()}
Path('output/aircraft-calibration/737-max9/calibration-draft.json').write_text(json.dumps(meta,indent=2)+'\n')
print(json.dumps(meta,indent=2))

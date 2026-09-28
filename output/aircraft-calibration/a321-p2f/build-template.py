"""Extract the supplied Airbus A321 DXF plan in its original millimetre scale.

No aircraft geometry is invented. Curves are flattened to <=1 mm tolerance;
only the fuselage band is retained. The same plan serves both deck overlays.
"""
from pathlib import Path
from xml.etree.ElementTree import Element, SubElement, tostring
import json, hashlib
import ezdxf
from ezdxf import bbox
from ezdxf.path import make_path

HERE = Path(__file__).parent
SOURCE = Path('/Users/mahartshorne/Documents/Other Stuff/Weight and Balance Project/Load Control/Aircraft SVG/Airbus/Airbus_A321_WTF.dxf')
document = ezdxf.readfile(SOURCE)
# The source sheet labels its units as mm. The separate side/front views are
# outside this plan-view region; these anchors are measured from its geometry.
NOSE_Y = -15897.09375
TAIL_Y = 28732.20703125
CENTRE_X = 56812.8125
LENGTH_MM = TAIL_Y - NOSE_Y
SCALE = 240 / LENGTH_MM
root = Element('svg', xmlns='http://www.w3.org/2000/svg', viewBox='0 0 248 50', width='1488', height='300', role='img')
SubElement(root,'title').text = 'Airbus A321 fuselage plan — tail left, nose right'
SubElement(root,'desc').text = 'Original geometry from Airbus_A321_WTF.dxf. General A321 outline shared by Main Deck and Lower Deck views; conversion-specific cargo doors are not defined by this source.'
group = SubElement(root,'g', fill='none', stroke='#858b92', **{'stroke-width':'0.09','stroke-linecap':'round','stroke-linejoin':'round'})
count = 0
for entity in document.modelspace():
    bounds = bbox.extents([entity])
    if not bounds.has_data or bounds.extmin.x < 39000 or bounds.extmax.y > 41000:
        continue
    if bounds.extmax.x < CENTRE_X-25/SCALE or bounds.extmin.x > CENTRE_X+25/SCALE:
        continue
    points = list(make_path(entity).flattening(1))
    if len(points)<2: continue
    coords = [(244-(p.y-NOSE_Y)*SCALE,25-(p.x-CENTRE_X)*SCALE) for p in points]
    SubElement(group,'path',d='M '+' L '.join(f'{x:.5f},{y:.5f}' for x,y in coords))
    count += 1
content=tostring(root,encoding='utf-8',xml_declaration=True)
(HERE/'a321-p2f-fuselage.svg').write_bytes(content)
Path('src/assets/aircraft-layouts/a321-p2f-fuselage.svg').write_bytes(content)
metadata={'source':str(SOURCE),'sourceSha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'cadUnits':'mm (source sheet annotation)','noseY':NOSE_Y,'tailY':TAIL_Y,'centreX':CENTRE_X,'lengthMetres':LENGTH_MM/1000,'noseX':244,'tailX':4,'scalePerMetre':SCALE*1000,'paths':count,'sha256':hashlib.sha256(content).hexdigest(),'byteSize':len(content)}
(HERE/'geometry.json').write_text(json.dumps(metadata,indent=2)+'\n')
print(json.dumps(metadata,indent=2))

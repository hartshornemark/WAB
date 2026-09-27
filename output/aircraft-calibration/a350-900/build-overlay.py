"""Build the A350-900 application overlay from the supplied Airbus DWG SVG conversion."""
from pathlib import Path
from xml.etree import ElementTree as ET
import re

HERE = Path(__file__).parent
SOURCE = HERE / 'a350-source.svg'
OUTPUT = HERE / 'a350-900-fuselage.svg'
APP_OUTPUT = Path('src/assets/aircraft-layouts/a359-900-fuselage.svg')
NS = '{http://www.w3.org/2000/svg}'
ET.register_namespace('', 'http://www.w3.org/2000/svg')
source = ET.parse(SOURCE).getroot()

# Final coordinates after the drawing's Y inversion and a 90-degree turn:
# final_x = -cad_y, final_y = -cad_x. The window retains the fuselage and
# enough wing/tail root detail to orient the holds without shrinking the body.
VIEW = (10000.0, -118500.0, 69000.0, 18500.0)
x0, y0, width, height = VIEW
x1, y1 = x0 + width, y0 + height
number = r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?'
token_re = re.compile(rf'[MLAZ]|{number}')

def path_points(data: str):
    tokens = token_re.findall(data)
    index = 0
    command = None
    points = []
    while index < len(tokens):
        if tokens[index].isalpha():
            command = tokens[index]
            index += 1
            if command == 'Z':
                continue
        if command in {'M', 'L'}:
            if index + 1 >= len(tokens): break
            points.append((float(tokens[index]), float(tokens[index + 1])))
            index += 2
        elif command == 'A':
            if index + 6 >= len(tokens): break
            rx, ry = float(tokens[index]), float(tokens[index + 1])
            px, py = float(tokens[index + 5]), float(tokens[index + 6])
            points.extend(((px, py), (px-rx, py-ry), (px+rx, py+ry)))
            index += 7
        else:
            index += 1
    return points

def geometry_points(element):
    if element.tag == NS + 'path':
        return path_points(element.get('d', ''))
    if element.tag == NS + 'line':
        return [(float(element.get('x1', 0)), float(element.get('y1', 0))),
                (float(element.get('x2', 0)), float(element.get('y2', 0)))]
    return []

def intersects(points):
    if not points:
        return False
    transformed = [(-py, -px) for px, py in points]
    min_x = min(p[0] for p in transformed)
    max_x = max(p[0] for p in transformed)
    min_y = min(p[1] for p in transformed)
    max_y = max(p[1] for p in transformed)
    return max_x >= x0 and min_x <= x1 and max_y >= y0 and min_y <= y1

root = ET.Element(NS+'svg', {
    'role':'img', 'aria-labelledby':'a359-title a359-desc',
    'viewBox':f'{x0:g} {y0:g} {width:g} {height:g}', 'width':'1492', 'height':'400',
})
ET.SubElement(root, NS+'title', {'id':'a359-title'}).text = 'Airbus A350-900 fuselage — tail left, nose right'
ET.SubElement(root, NS+'desc', {'id':'a359-desc'}).text = (
    'Derived from the supplied Airbus A350-900 DWG. Original plan-view vector '
    'geometry is retained and cropped around the fuselage for hold and cabin overlays.'
)
rotated = ET.SubElement(root, NS+'g', {'transform':'rotate(-90) scale(1,-1)', 'fill':'none',
    'stroke':'#858b92', 'stroke-width':'44', 'stroke-linejoin':'round', 'stroke-linecap':'round'})
main = next(child for child in source if child.tag == NS+'g')
kept = 0
for element in main.iter():
    points = geometry_points(element)
    if not intersects(points):
        continue
    attrs = {key: value for key, value in element.attrib.items() if key in {'d','x1','y1','x2','y2'}}
    ET.SubElement(rotated, element.tag, attrs)
    kept += 1
ET.indent(root, space='  ')
contents = ET.tostring(root, encoding='utf-8', xml_declaration=True)
OUTPUT.write_bytes(contents)
APP_OUTPUT.write_bytes(contents)
print(f'kept={kept} bytes={len(contents)} output={OUTPUT}')

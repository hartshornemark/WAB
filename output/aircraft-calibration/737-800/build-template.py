"""Build the application fuselage overlay from the supplied 737-800 DXF."""
from pathlib import Path
import hashlib
import json
from xml.etree import ElementTree as ET

import ezdxf
from ezdxf import bbox
from ezdxf.path import make_path

SOURCE = Path("/Users/mahartshorne/Downloads/737-800.dxf")
HERE = Path(__file__).parent
OUTPUT = HERE / "737-800-fuselage.svg"

document = ezdxf.readfile(SOURCE)
model = document.modelspace()

# The source contains side, front and top views. The top view occupies x >= -68
# and y < 100. The application viewBox then crops wings and dimensions around
# the fuselage centre line while retaining doors, windows and fuselage details.
entities = []
excluded_top_view_details = {"1F9", "43D4", "594A", "594B", "594D", "596D", "596F"}
for entity in model:
    if entity.dxftype() not in {"LINE", "POLYLINE", "LWPOLYLINE", "ARC", "CIRCLE", "SPLINE", "ELLIPSE"}:
        continue
    if entity.dxf.handle in excluded_top_view_details:
        continue
    bounds = bbox.extents([entity], fast=True)
    if not bounds.has_data or bounds.center.x <= -100 or bounds.center.y >= 100:
        continue
    # Between the tail and nose, keep only geometry that belongs to the
    # fuselage band. This removes the mirrored wing, engine and pylon detail
    # that crosses the top-view centreline in the source drawing.
    if 350 < bounds.center.x < 1100 and (
        bounds.extmin.y < -410 or bounds.extmax.y > -240
    ):
        continue
    entities.append(entity)

nose = min(bbox.extents([entity], fast=True).extmin.x for entity in entities)
tail = max(bbox.extents([entity], fast=True).extmax.x for entity in entities)
length = 1554.0
# The two forward-most fuselage curves meet at this drawing centreline. The
# earlier extraction used an unrelated construction line at -399.319794,
# which placed the aircraft below the hold and seat overlays.
centre = -325.321994
scale = 240 / length

svg = ET.Element(
    "svg",
    xmlns="http://www.w3.org/2000/svg",
    viewBox="0 0 248 50",
    width="1984",
    height="400",
    role="img",
)
ET.SubElement(svg, "title").text = "Boeing 737-800 fuselage — tail left, nose right"
ET.SubElement(svg, "desc").text = (
    "Derived from the supplied 737-800.dxf. Original top-view vector geometry "
    "is retained; wings and dimensions are removed for the version 4 application overlay."
)
group = ET.SubElement(
    svg,
    "g",
    fill="none",
    stroke="#858b92",
    **{"stroke-width": "0.16", "stroke-linejoin": "round", "stroke-linecap": "round"},
)

path_count = 0
for entity in entities:
    try:
        points = list(make_path(entity).flattening(0.12))
    except (AttributeError, TypeError, ValueError):
        continue
    if len(points) < 2:
        continue
    data = "M" + " L".join(
        f"{244 - (point.x - nose) * scale:.5f},{25 + (point.y - centre) * scale:.5f}"
        for point in points
    )
    ET.SubElement(group, "path", id=f"boeing-{entity.dxf.handle}", d=data)
    path_count += 1

OUTPUT.write_bytes(ET.tostring(svg, encoding="utf-8", xml_declaration=True))
metadata = {
    "aircraftType": "738",
    "series": "800",
    "source": SOURCE.name,
    "noseX": 244,
    "centreY": 25,
    "span": 240,
    "cadNoseX": nose,
    "cadTailX": tail,
    "cadDrawingUnits": "inches, confirmed by the 129 FT 6 IN length annotation",
    "cadLengthInches": length,
    "lengthMetres": length * 0.0254,
    "noseArmMetres": 3.302,
    "noseStationInches": 130,
    "datumStatus": "Uses the same 130-inch forward-of-nose calibration framework as the 737 MAX 9 template.",
    "pathCount": path_count,
    "sha256": hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
}
(HERE / "calibration-draft.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
print(json.dumps(metadata, indent=2))

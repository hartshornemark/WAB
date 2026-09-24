"""Build a dimensioned vector proof from the original plan-view geometry.

No image-canvas dimensions or manually positioned hold coordinates are used.
D2/D4 values were read from ZZ / 319 / 100 on 2026-09-21.
"""
from pathlib import Path
from xml.etree import ElementTree as ET
from copy import deepcopy
import json
import math
import re

BASE = Path(__file__).resolve().parent
NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)
source = ET.parse(BASE / "a319-vector-clean.svg").getroot()
solids = source.find(f"{{{NS}}}g[@id='Solids']")
lines = source.find(f"{{{NS}}}g[@id='_x34_-view']")

# Endpoints come from the plan-view outline, not from the SVG page bounds.
outline = lines[7]
coords = list(map(float, re.findall(r"[-+]?\d*\.?\d+", outline.attrib["points"])))
points = list(zip(coords[::2], coords[1::2]))
NOSE = min(x for x, y in points)  # 16.449
TAIL = max(x for x, y in points)  # 402.798
CENTRE = (340.833 + 386.667) / 2
SPAN = TAIL - NOSE
assert math.isclose(SPAN, 386.349)
# EASA.A.064, Issue 62, A319 section 15 (PDF page 153): datum 2.540 m ahead of nose.
NOSE_ARM = 2.540
DATUM_SOURCE = "https://www.easa.europa.eu/en/downloads/16507/en#page=153"

holds = [
    dict(id="1", start=9.858, end=13.107, maxWeightKg=2268, volumeM3=8.560),
    dict(id="4", start=19.608, end=24.028, maxWeightKg=3021, volumeM3=11.940),
    dict(id="5", start=24.028, end=27.270, maxWeightKg=1497, volumeM3=7.220),
]
doors = [
    dict(id="1", start=9.971, end=11.608, side="R"),
    dict(id="4", start=22.187, end=24.004, side="R"),
    dict(id="5", start=25.287, end=26.240, side="R"),
]

def el(tag, attrs=None, text=None):
    obj = ET.Element(f"{{{NS}}}{tag}", {k:str(v) for k,v in (attrs or {}).items()})
    obj.text = text
    return obj

def build(length):
    # One rigid rotation: tail to the left, nose to the right, centreline retained.
    transform = f"matrix(-1 0 0 -1 {NOSE + TAIL:.3f} {2 * CENTRE:.3f})"
    x_at = lambda arm: TAIL - (arm - NOSE_ARM) * SPAN / length
    assert math.isclose(x_at(NOSE_ARM), TAIL)
    assert math.isclose(x_at(NOSE_ARM + length), NOSE)
    svg = el("svg", {
        "viewBox": "5 279.25 409.247 169", "width": "1637", "height": "676",
        "role": "img", "aria-labelledby": "diagram-title diagram-description",
    })
    svg.append(el("title", {"id":"diagram-title"}, "A319 holds and cargo doors — tail left, nose right"))
    svg.append(el("desc", {"id":"diagram-description"},
        f"Balance arm at the nose is {NOSE_ARM:.3f} m; datum is {NOSE_ARM:.3f} m ahead of the nose. "
        f"Aircraft length reference {length:.2f} m. Hold lengths use D2 values; widths are schematic. "
        "Doors 1, 4 and 5 use the saved D4 values verified on 2026-09-21."))
    svg.append(el("rect", {"x":5,"y":279.25,"width":409.247,"height":169,"fill":"white"}))
    aircraft = el("g", {"id":"aircraft", "transform":transform})
    # Extract only the top view, excluding other views and drawing dimensions.
    aircraft.append(deepcopy(solids[1]))
    for index in [*range(7,17),26,27,43]:
        obj = deepcopy(lines[index])
        if index == 26:
            obj.set("d", "M286.792,340.833H87.307 M286.792,386.667H87.307")
        aircraft.append(obj)
    svg.append(aircraft)
    overlays = el("g", {"font-family":"Arial, Helvetica, sans-serif", "fill":"#17335F"})
    geometry=[]
    hold_height = 42
    # The strip aligns with the longitudinal extents of the holds. Labels remain
    # centred over their own holds and are legible in the default detail view.
    strip_left = x_at(max(h['end'] for h in holds))
    strip_right = x_at(min(h['start'] for h in holds))
    information = el("g", {"id":"hold-information", "fill":"#111111"})
    information.append(el("rect", {"x":f"{strip_left:.5f}","y":331.25,
        "width":f"{strip_right-strip_left:.5f}","height":6.8,"rx":3.4,"fill":"#D5D5D5"}))
    for hold in holds:
        left, right = x_at(hold['end']), x_at(hold['start'])
        width = right - left
        assert math.isclose(width, (hold['end'] - hold['start']) * SPAN / length)
        group = el("g", {"id":f"hold-{hold['id']}"})
        group.append(el("title", text=f"Hold {hold['id']}: Max Weight {hold['maxWeightKg']} Kg; Volume {hold['volumeM3']:.2f} m³; balance arms {hold['start']:.3f}–{hold['end']:.3f} m"))
        # Width across the aircraft is illustrative, with clearance inside the
        # fuselage. The rectangle's horizontal bounds still use the D2 arms.
        group.append(el("rect", {"x":f"{left:.5f}", "y":CENTRE-hold_height/2,
            "width":f"{width:.5f}", "height":hold_height, "rx":6.2,
            "fill":"none","stroke":"#939393","stroke-width":0.5}))
        mid=(left+right)/2
        information.append(el("text", {"id":f"hold-information-{hold['id']}","x":f"{mid:.5f}","y":335.6,
            "text-anchor":"middle","font-size":2.5,"font-weight":700},
            f"HOLD {hold['id']} MAX {hold['maxWeightKg']} Kg/{hold['volumeM3']:.2f} m³"))
        overlays.append(group)
        geometry.append(dict(**hold,x=left,width=width,y=CENTRE-hold_height/2,height=hold_height))
    overlays.append(information)
    display_doors = [dict(door) for door in doors]
    for door in display_doors:
        hold = next(h for h in holds if h['id'] == door['id'])
        overlaps_hold = max(door['start'],hold['start']) < min(door['end'],hold['end'])
        if not NOSE_ARM <= door['start'] < door['end'] <= NOSE_ARM + length or not overlaps_hold:
            continue  # Never substitute an invented position for an invalid source range.
        left, right = x_at(door['end']), x_at(door['start'])
        y=388.9 # Close to the lower fuselage, with clear space around the end ticks.
        group = el("g", {"id":f"door-{door['id']}"})
        group.append(el("title", text=f"Door {door['id']}: balance arms {door['start']:.3f}–{door['end']:.3f} m, right side"))
        group.append(el("path", {"d":f"M{left:.5f} {y} H{right:.5f} M{left:.5f} {y-1.4} V{y+1.4} M{right:.5f} {y-1.4} V{y+1.4}",
            "fill":"none","stroke":"#245F9F","stroke-width":0.6}))
        group.append(el("text", {"x":f"{(left+right)/2:.5f}","y":393.8,
            "text-anchor":"middle","font-size":2.5,"font-weight":700,"fill":"#245F9F"},"DOOR"))
        overlays.append(group)
    svg.append(overlays)
    return ET.tostring(svg, encoding="unicode"), geometry

default, geometry = build(33.84)
alternative, _ = build(33.54)
preview, _ = build(33.84)
preview_alternative, _ = build(33.54)
(BASE / "a319-vector-hold-door-overlay.svg").write_text(default)
(BASE / "a319-vector-hold-door-overlay-3354.svg").write_text(alternative)
(BASE / "a319-vector-hold-door-preview.svg").write_text(preview)
(BASE / "a319-vector-hold-door-preview-3354.svg").write_text(preview_alternative)
for filename, content in [("a319-vector-hold-door-detail.svg",preview),
                          ("a319-vector-hold-door-detail-3354.svg",preview_alternative)]:
    detail=ET.fromstring(content)
    # The close-up shows the fuselage edges and doors only. Keep the original
    # vector paths and calibration intact; clip out wings and internal tail lines.
    defs=el('defs')
    clip=el('clipPath', {'id':'fuselage-edge-detail','clipPathUnits':'userSpaceOnUse'})
    for y in (340.55, 380.0):
        clip.append(el('rect', {'x':102,'y':y,'width':236,'height':6.95}))
    defs.append(clip)
    detail.insert(0,defs)
    aircraft=detail.find(f"{{{NS}}}g[@id='aircraft']")
    position=list(detail).index(aircraft)
    detail.remove(aircraft)
    clipped=el('g', {'clip-path':'url(#fuselage-edge-detail)'})
    clipped.append(aircraft)
    detail.insert(position,clipped)
    detail.set('viewBox','102 327.25 236 72')
    detail.set('width','1888')
    detail.set('height','576')
    (BASE / filename).write_text(ET.tostring(detail, encoding='unicode'))
(BASE / "a319-vector-coordinate-register.json").write_text(json.dumps({
    "source":"a319-vector-clean.svg", "orientation":"tail left / nose right",
    "sourceNoseX":NOSE,"sourceTailX":TAIL,"fuselageCentreY":CENTRE,
    "assumedLengthMetres":33.84,"alternativeLengthMetres":33.54,
    "noseBalanceArmMetres":NOSE_ARM,"datumSource":DATUM_SOURCE,
    "formula":"x = 402.798 - (balanceArmMetres - 2.540) * 386.349 / overallLengthMetres",
    "holdWidth":"schematic; 42 vector units, centred on the fuselage",
    "holds":geometry,"doors":doors,
    "unplottedDoors":[],
    "doorDataVerified":"D4 screen, ZZ / 319 / 100, 2026-09-21",
    "visualPreview":{"door5":{"start":25.287,"end":26.240,"provisional":False},
                     "file":"a319-vector-hold-door-preview.svg", "detailFile":"a319-vector-hold-door-detail.svg"},
}, indent=2))

html='''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>A319 — Holds and Doors</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f5f7fc;color:#17335f;font:15px Arial,Helvetica,sans-serif}
main{max-width:1800px;margin:24px auto;padding:0 24px}header{display:flex;align-items:center;justify-content:space-between;gap:18px;flex-wrap:wrap}
h1{font-size:23px;margin:0 0 7px}header p{margin:0;color:#586d8c}fieldset{display:flex;gap:18px;border:1px solid #d9e2f0;border-radius:8px;padding:10px 14px;margin:0}legend{font-size:12px;color:#586d8c}label{white-space:nowrap;cursor:pointer}input{accent-color:#2f6cc5}
.controls{display:flex;gap:12px;flex-wrap:wrap}
figure{margin:24px 0 16px;background:white;border:1px solid #d9e2f0;border-radius:12px;overflow:hidden}img{width:100%;height:auto;display:block}
.note{padding:14px 18px;border-left:4px solid #d89b28;background:#fff6e6;border-radius:4px;line-height:1.5}footer{font-size:13px;color:#586d8c;margin-top:12px;line-height:1.5}
.datum{margin-top:16px;color:#586d8c;font-size:13px;line-height:1.5}.datum a{color:#2f6cc5}
</style></head><body><main>
<header><div><h1>A319 · Holds &amp; Doors</h1><p>Tail left · Nose right · Balance arm at nose = 2.540 m</p></div>
<div class="controls"><fieldset><legend>View</legend><label><input type="radio" name="view" value="detail" checked> Hold detail</label><label><input type="radio" name="view" value="full"> Full aircraft</label></fieldset>
<fieldset><legend>Length reference for comparison</legend><label><input type="radio" name="length" value="3384" checked> 33.84 m</label><label><input type="radio" name="length" value="3354"> 33.54 m</label></fieldset></div></header>
<div class="datum">Distance behind nose = Balance Arm − 2.540 m. Datum: <a href="https://www.easa.europa.eu/en/downloads/16507/en#page=153" target="_blank" rel="noopener">EASA A.064 · A319 §15</a>.</div>
<figure><img id="plan" src="a319-vector-hold-door-detail.svg?v=holdsaved4" alt="A319 holds with wide grey outlines and a grey information strip showing each hold name, Max Weight in Kg and Volume in cubic metres. All three door markers use saved D4 measurements."></figure>

<footer>Hold labels show Name, Max Weight (Kg) and Volume (m³). All holds and doors follow the saved D2/D4 values for ZZ / 319 / 100. Hold widths are schematic.</footer>
<script>document.querySelectorAll('.controls input').forEach(input=>input.addEventListener('change',()=>{const view=document.querySelector('input[name="view"]:checked').value;const length=document.querySelector('input[name="length"]:checked').value;document.getElementById('plan').src='a319-vector-hold-door-'+(view==='detail'?'detail':'preview')+(length==='3354'?'-3354':'')+'.svg?v=holdsaved4';}));</script>
</main></body></html>'''
(BASE / "a319-vector-hold-door-overlay.html").write_text(html)
print(json.dumps({"noseX":NOSE,"tailX":TAIL,"centreY":CENTRE,"scale":SPAN/33.84,"holds":geometry},indent=2))

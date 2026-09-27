from pathlib import Path
from PIL import Image, ImageDraw
import math

SCALE = 4
SIZE = (1200, 300)
INK = (79, 89, 102, 255)


def pt(value):
    if isinstance(value, tuple):
        return tuple(int(round(v * SCALE)) for v in value)
    return int(round(value * SCALE))


def canvas():
    image = Image.new("RGBA", (SIZE[0] * SCALE, SIZE[1] * SCALE), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def line(draw, points, width=3, fill=INK, joint="curve"):
    draw.line([pt(p) for p in points], fill=fill, width=pt(width), joint=joint)


def polygon(draw, points, width=3):
    scaled = [pt(p) for p in points]
    draw.polygon(scaled, fill=(255, 255, 255, 0))
    draw.line(scaled + [scaled[0]], fill=INK, width=pt(width), joint="curve")


def rounded(draw, box, radius, width=3):
    draw.rounded_rectangle(pt(box), radius=pt(radius), outline=INK, width=pt(width))


def ellipse(draw, box, width=3):
    draw.ellipse(pt(box), outline=INK, width=pt(width))


def finish(image, path):
    image.resize(SIZE, Image.Resampling.LANCZOS).save(path)


def airbus(path, *, length, windows):
    image, draw = canvas()
    nose = 92
    tail = nose + length
    top, bottom = 116, 211
    # Fuselage and tail cone.
    upper = [(nose, 175), (104, 153), (129, 134), (168, 122), (228, top), (tail - 170, top), (tail - 112, 111), (tail - 50, 119), (tail, 143)]
    lower = [(tail, 143), (tail - 30, 169), (tail - 92, 190), (tail - 176, 207), (tail - 260, bottom), (228, bottom), (168, 207), (128, 197), (104, 184), (nose, 175)]
    line(draw, upper + lower, 4)
    # Vertical and horizontal stabilisers.
    polygon(draw, [(tail - 185, 116), (tail - 109, 23), (tail - 65, 27), (tail - 98, 119)], 4)
    # The horizontal stabiliser remains inside the tail cone in side view.  An
    # earlier long diamond projected past the fuselage and made the Airbus tail
    # look forked on the small carrier cards.
    polygon(draw, [(tail - 166, 120), (tail - 61, 116), (tail - 34, 124), (tail - 137, 137)], 3)
    # Wing and fairing.
    polygon(draw, [(nose + length * .52, 151), (nose + length * .70, 174), (nose + length * .58, 184), (nose + length * .43, 165)], 3)
    polygon(draw, [(nose + length * .47, 173), (nose + length * .60, 176), (nose + length * .67, 190), (nose + length * .50, 187)], 3)
    # Visible engine and pylon.
    ex = nose + length * .48
    rounded(draw, (ex - 42, 181, ex + 48, 231), 16, 4)
    line(draw, [(ex + 37, 183), (ex + 74, 166), (ex + 86, 167)], 3)
    line(draw, [(ex - 32, 228), (ex + 33, 228)], 2)
    # Cockpit windows.
    polygon(draw, [(121, 154), (139, 143), (157, 144), (149, 157), (127, 159)], 3)
    line(draw, [(139, 144), (137, 158)], 2)
    # Doors.
    for x in (184, tail - 156):
        rounded(draw, (x, 137, x + 20, 190), 3, 3)
    rounded(draw, (nose + length * .38, 177, nose + length * .38 + 30, 207), 4, 3)
    rounded(draw, (nose + length * .76, 177, nose + length * .76 + 30, 207), 4, 3)
    # Passenger windows.
    start, end = 218, tail - 185
    pitch = (end - start) / max(windows - 1, 1)
    for i in range(windows):
        x = start + pitch * i
        if abs(x - (nose + length * .48)) < 26:
            continue
        rounded(draw, (x, 151, x + 8, 161), 3, 2)
    # Nose gear and main gear.
    line(draw, [(189, 211), (189, 234)], 3)
    ellipse(draw, (179, 230, 199, 249), 3)
    line(draw, [(nose + length * .56, 208), (nose + length * .56, 236)], 3)
    ellipse(draw, (nose + length * .56 - 12, 231, nose + length * .56 + 12, 254), 3)
    line(draw, [(72, 255), (tail - 30, 255)], 3)
    finish(image, path)


def dash8(path):
    image, draw = canvas()
    nose, tail = 94, 1070
    top, bottom = 116, 207
    upper = [(nose, 173), (105, 151), (132, 134), (176, 122), (236, top), (890, top), (956, 111), (1024, 124), (tail, 151)]
    lower = [(tail, 151), (1047, 176), (996, 193), (914, 205), (230, bottom), (169, 204), (127, 194), (103, 182), (nose, 173)]
    line(draw, upper + lower, 4)
    # Tall fin and high T-tail.
    polygon(draw, [(917, 116), (976, 29), (1023, 31), (994, 122)], 4)
    # A slim, convex T-tail reads clearly when reduced to card size.
    polygon(draw, [(856, 43), (1057, 46), (1087, 55), (891, 59)], 3)
    # High wing and engine nacelle.
    polygon(draw, [(480, 122), (685, 124), (753, 143), (507, 143)], 3)
    rounded(draw, (486, 128, 603, 176), 15, 4)
    line(draw, [(512, 176), (535, 190), (587, 190), (606, 175)], 3)
    # Propeller hub and blades.
    hubx, huby = 476, 151
    ellipse(draw, (hubx - 7, huby - 7, hubx + 7, huby + 7), 3)
    for angle in (12, 102, 192, 282):
        a = math.radians(angle)
        b = math.radians(angle + 9)
        inner = 9
        outer = 73
        polygon(draw, [
            (hubx + math.cos(a) * inner, huby + math.sin(a) * inner),
            (hubx + math.cos(a) * outer, huby + math.sin(a) * outer),
            (hubx + math.cos(b) * (outer - 8), huby + math.sin(b) * (outer - 8)),
            (hubx + math.cos(b) * inner, huby + math.sin(b) * inner),
        ], 2)
    # Cockpit, doors and windows.
    polygon(draw, [(120, 152), (139, 139), (165, 141), (153, 158), (126, 159)], 3)
    line(draw, [(140, 141), (138, 158)], 2)
    for x in (182, 885):
        rounded(draw, (x, 135, x + 24, 190), 3, 3)
    for x in range(224, 872, 25):
        if 450 <= x <= 505:
            continue
        rounded(draw, (x, 149, x + 9, 160), 3, 2)
    # Hold doors.
    rounded(draw, (247, 177, 282, 205), 4, 3)
    rounded(draw, (792, 177, 827, 205), 4, 3)
    # Landing gear and ground line.
    line(draw, [(194, 207), (194, 234)], 3)
    ellipse(draw, (184, 230, 204, 249), 3)
    line(draw, [(552, 189), (552, 235)], 3)
    ellipse(draw, (539, 230, 565, 255), 3)
    line(draw, [(72, 256), (tail - 15, 256)], 3)
    finish(image, path)


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    target = root / "public" / "aircraft-profiles"
    target.mkdir(parents=True, exist_ok=True)
    airbus(target / "a319-100.png", length=880, windows=25)
    airbus(target / "a320-200.png", length=960, windows=29)
    dash8(target / "dh3-300.png")

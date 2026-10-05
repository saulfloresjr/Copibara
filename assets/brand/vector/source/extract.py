"""Copibara flat mark (assets/brand/taskbar-icon-1.png) — measure every layer (logo-to-vector skill).

Two-tone source: near-black ink on opaque white, very little anti-aliasing. Every layer is a compact
closed shape selected by colour + seed and contoured on ONE field (luminance) at its mid level, so the
silhouette and its cut-outs share the same edge definition:
  body_silhouette  ears + head + arms + the band wrapping the card's bottom (ink, outer contour)
  eye_left/right   sleepy closed-eye crescents (white cut-outs)
  nose             (white cut-out)
  clipboard_card   (white cut-out; the paws bite into its sides)
  line_1..3        text lines on the card (ink)
"""
import json
from trace import Raster
from bezier import find_corners

r = Raster("ref.png")
INK = lambda x, y: r.LUM(x, y) < 128
PAPER = lambda x, y: r.LUM(x, y) >= 128
DARK = lambda x, y: 255 - r.LUM(x, y)      # contour field for ink shapes
LIGHT = lambda x, y: r.LUM(x, y)           # contour field for white cut-outs (same 50% iso-line)
LEVEL = 127.5

shapes = {}
def take(name, test, seed, field):
    assert test(*seed), f"seed for {name} is not on the shape: {seed}"
    m, px = r.component(test, seed)
    pts = r.outline(m, field, LEVEL)
    cs = find_corners(pts, 50, 14)
    shapes[name] = dict(outline=pts, bbox=r.bbox(px), n=len(px), mask=m, corners=cs)
    print(f"{name:16s} px {len(px):7d} bbox {r.bbox(px)} outline {len(pts):5d} corners {len(cs)}")

def first(xs, y, test):
    return next(x for x in xs if test(x, y))

# body: the big ink component (seed in the middle of the head)
take("body_silhouette", INK, (627, 420), DARK)
body = shapes["body_silhouette"]["mask"]

# white cut-outs inside the body: find white pixels enclosed by ink along known rows
inside = lambda x, y: PAPER(x, y)
# eyes: the white strokes on the eye row, left and right of centre
eye_row = next(y for y in range(380, 620) if any(PAPER(x, y) and body[r.i(x - 40, y)] and body[r.i(x + 40, y)] for x in range(420, 520)))
take("eye_left", inside, (first(range(420, 560), eye_row + 6, PAPER), eye_row + 6), LIGHT)
take("eye_right", inside, (first(range(700, 840), eye_row + 6, PAPER), eye_row + 6), LIGHT)
# nose: white on the centre column below the eyes
ny = next(y for y in range(eye_row + 30, 760) if PAPER(627, y))
take("nose", inside, (627, ny + 8), LIGHT)
# card: white on the centre column further down
cy = next(y for y in range(ny + 120, 1000) if PAPER(627, y))
take("clipboard_card", inside, (627, cy + 10), LIGHT)
card = shapes["clipboard_card"]["mask"]

# lines: ink components inside the card's bounding box, top to bottom
cx0, cy0, cx1, cy1 = shapes["clipboard_card"]["bbox"]
taken = set(); n = 0
for y in range(cy0 + 5, cy1 - 5):
    x = 627
    if INK(x, y) and (x, y) not in taken:
        n += 1
        m, px = r.component(INK, (x, y)); taken.update(px)
        take(f"line_{n}", INK, (x, y), DARK)
        if n == 3: break

json.dump(dict(size=[r.W, r.H],
               shapes={k: dict(outline=v["outline"], bbox=v["bbox"], corners=v["corners"]) for k, v in shapes.items()}),
          open("geometry.json", "w"))

palette = {"body_silhouette": (255, 0, 255), "eye_left": (0, 200, 255), "eye_right": (0, 200, 255),
           "nose": (0, 220, 0), "clipboard_card": (255, 140, 0), "line_1": (255, 0, 0), "line_2": (255, 0, 0), "line_3": (255, 0, 0)}
img = r.overlay([(v["outline"], palette[k], True) for k, v in shapes.items()], scale=1)
from PIL import ImageDraw
d = ImageDraw.Draw(img)
for k, v in shapes.items():
    for c in v["corners"]:
        x, y = v["outline"][c]; d.ellipse([x - 7, y - 7, x + 7, y + 7], outline=(0, 160, 0), width=3)
img.crop((260, 170, 995, 1040)).save("debug_overlay.png")
print("ink colour", r.mean_color([(x, y) for x in range(600, 660) for y in range(300, 340)]))

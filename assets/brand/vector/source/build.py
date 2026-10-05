"""Build the Copibara flat-mark SVGs from geometry.json (logo-to-vector skill).

Models (what the original draws, rather than its pixels):
  * real points where two ARCS meet (ear/head, arm notch, band join, paw bites) are restored at the
    intersection of circles fitted to the edges on either side (trace.sharpen extends straight lines,
    which overshoots by up to 5.5 px on these arc-to-arc notches and lost two of them)
  * the text lines are exact capsules (stadiums) from their measured extents
  * the nose is convex: the simplest fit with zero inflections
  * corners come from the RAW outline and are passed through explicitly (never re-detected after edits)

reference-aligned.svg  faithful: source viewBox (1254), measured geometry, white paper
copibara-mark-*.svg    master (layered, true transparency), flat, light, dark, small, favicon.svg
"""
import json, math, os
from bezier import fit_closed_simplest, fit_open_simplest, find_corners, to_path, deviation, inflections

g = json.load(open("geometry.json")); W0 = g["size"][0]
SH = {k: [tuple(p) for p in v["outline"]] for k, v in g["shapes"].items()}
os.makedirs("out", exist_ok=True)
INK = "#212121"                                   # sampled interior (no brief colour)
DEV = 1.0                                         # skill: 1.6 px @2000 px, scaled to this 1254 px source
REPORT = {}

# ---------------------------------------------------------------- corner modelling (arc-to-arc)
def fit_circle(ps):
    """Kåsa least-squares circle; returns (cx, cy, r) or None for a near-straight run."""
    n = len(ps); mx = sum(p[0] for p in ps) / n; my = sum(p[1] for p in ps) / n
    u = [(p[0] - mx, p[1] - my) for p in ps]
    suu = sum(a * a for a, _ in u); svv = sum(b * b for _, b in u); suv = sum(a * b for a, b in u)
    suuu = sum(a ** 3 for a, _ in u); svvv = sum(b ** 3 for _, b in u)
    suvv = sum(a * b * b for a, b in u); svuu = sum(b * a * a for a, b in u)
    det = suu * svv - suv * suv
    if abs(det) < 1e-9: return None
    uc = (0.5 * (suuu + suvv) * svv - 0.5 * (svvv + svuu) * suv) / det
    vc = (0.5 * (svvv + svuu) * suu - 0.5 * (suuu + suvv) * suv) / det
    r = math.sqrt(uc * uc + vc * vc + (suu + svv) / n)
    return (uc + mx, vc + my, r) if r < 4000 else None

def fit_line(ps):
    n = len(ps); mx = sum(p[0] for p in ps) / n; my = sum(p[1] for p in ps) / n
    sxx = sum((p[0] - mx) ** 2 for p in ps); syy = sum((p[1] - my) ** 2 for p in ps); sxy = sum((p[0] - mx) * (p[1] - my) for p in ps)
    a = 0.5 * math.atan2(2 * sxy, sxx - syy); return (mx, my), (math.cos(a), math.sin(a))

def meet(A, B, near):
    """Intersection of two edge models (circle or line) closest to `near`."""
    pts = []
    if A[0] == "c" and B[0] == "c":
        (x0, y0, r0), (x1, y1, r1) = A[1], B[1]; d = math.hypot(x1 - x0, y1 - y0)
        if d == 0 or d > r0 + r1 or d < abs(r0 - r1): return None
        a = (r0 * r0 - r1 * r1 + d * d) / (2 * d); h = math.sqrt(max(0, r0 * r0 - a * a))
        xm, ym = x0 + a * (x1 - x0) / d, y0 + a * (y1 - y0) / d
        pts = [(xm + h * (y1 - y0) / d, ym - h * (x1 - x0) / d), (xm - h * (y1 - y0) / d, ym + h * (x1 - x0) / d)]
    else:
        if A[0] == "l": A, B = B, A
        if A[0] == "c" and B[0] == "l":                       # circle x line
            (cx, cy, r), ((px, py), (dx, dy)) = A[1], B[1]
            fx, fy = px - cx, py - cy; b = fx * dx + fy * dy; c = fx * fx + fy * fy - r * r; disc = b * b - c
            if disc < 0: return None
            for t in (-b + math.sqrt(disc), -b - math.sqrt(disc)): pts.append((px + dx * t, py + dy * t))
        else:                                                  # line x line
            (p1, d1), (p2, d2) = A[1], B[1]; den = d1[0] * d2[1] - d1[1] * d2[0]
            if abs(den) < 1e-9: return None
            t = ((p2[0] - p1[0]) * d2[1] - (p2[1] - p1[1]) * d2[0]) / den; pts = [(p1[0] + d1[0] * t, p1[1] + d1[1] * t)]
    return min(pts, key=lambda q: math.hypot(q[0] - near[0], q[1] - near[1])) if pts else None

def model(ps):
    c = fit_circle(ps); return ("c", c) if c else ("l", fit_line(ps))

def restore_points(pts, corners, inner, span, max_move=8.0):
    """Replace the rounded samples around each corner by the apex where the two edge models meet.
    Returns (new polyline, new corner indices)."""
    n = len(pts); drop = set(); apex = {}
    for c in corners:
        side_a = [pts[(c - k) % n] for k in range(inner, span)]
        side_b = [pts[(c + k) % n] for k in range(inner, span)]
        X = meet(model(side_a), model(side_b), pts[c])
        if X and math.hypot(X[0] - pts[c][0], X[1] - pts[c][1]) <= max_move:
            apex[c] = X; drop.update((c + m) % n for m in range(-inner + 1, inner) if m)
    out, idx = [], []
    for i in range(n):
        if i in drop: continue
        if i in corners: idx.append(len(out)); out.append(apex.get(i, pts[i]))
        else: out.append(pts[i])
    return out, idx

def corners_of(name, pts):
    if name == "body_silhouette": return find_corners(pts, 50, 14)
    if name == "clipboard_card": return find_corners(pts, 30, 6)
    return []
CORNER_MODEL = {"body_silhouette": (4, 18), "clipboard_card": (3, 10)}   # (inner, span) in 2-px samples

# ---------------------------------------------------------------- capsules and convex shapes
K = 0.5522847498
def capsule(pts):
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys); r = (y1 - y0) / 2; yc = (y0 + y1) / 2
    a, b = x0 + r, x1 - r
    line = lambda p, q: (p, (p[0] + (q[0] - p[0]) / 3, p[1] + (q[1] - p[1]) / 3), (p[0] + 2 * (q[0] - p[0]) / 3, p[1] + 2 * (q[1] - p[1]) / 3), q)
    return [line((a, y0), (b, y0)),
            ((b, y0), (b + K * r, y0), (x1, yc - K * r), (x1, yc)),
            ((x1, yc), (x1, yc + K * r), (b + K * r, y1), (b, y1)),
            line((b, y1), (a, y1)),
            ((a, y1), (a - K * r, y1), (x0, yc + K * r), (x0, yc)),
            ((x0, yc), (x0, yc - K * r), (a - K * r, y0), (a, y0))]

def smooth_fit(pts, rep, expect_infl, dev_cap=1.25):
    """Corner-free shapes (nose: convex, 0 inflections; eye crescent: 2). The MOST ACCURATE fit with
    exactly the design's inflection count — not the simplest one. The ring starts at the middle of its
    top edge, so the closing seam lands on gentle curvature instead of a tight cap."""
    from bezier import fit_closed, taubin, ERR_STEPS
    cx = sum(p[0] for p in pts) / len(pts); top_y = min(p[1] for p in pts)
    top = min(range(len(pts)), key=lambda i: abs(pts[i][0] - cx) + 3 * (pts[i][1] - top_y))
    ring = pts[top:] + pts[:top]
    best = None
    for iters in (6, 12, 20, 40):
        clean = taubin(ring, iters, closed=True)
        for e in ERR_STEPS:
            segs = fit_closed(clean, e, corners=[])
            if inflections(segs) != expect_infl: continue
            mx, rms = deviation(ring, segs)
            if mx <= dev_cap and (best is None or rms < best[0]): best = (rms, mx, segs, iters, e)
    if best is None: return fit_closed_simplest(ring, dev_limit=dev_cap, corners=[])
    rep.append(dict(model=f"smooth, {expect_infl} inflections", taubin_iters=best[3], err=best[4], segments=len(best[2]),
                    dev_max=round(best[1], 2), dev_rms=round(best[0], 2)))
    return best[2]

convex_fit = lambda pts, rep: smooth_fit(pts, rep, 0)

# ---------------------------------------------------------------- fitting one layer
def fit_layer(name, pts, dev=DEV, store=None):
    rep = []
    if name.startswith("line_"): segs = capsule(pts); rep.append(dict(model="capsule", segments=6))
    elif name == "nose": segs = smooth_fit(pts, rep, 0, dev_cap=max(1.25, dev))
    elif name.startswith("eye_"): segs = smooth_fit(pts, rep, 2, dev_cap=max(1.25, dev))
    else:
        inner, span = CORNER_MODEL[name]
        p2, cs = restore_points(pts, corners_of(name, pts), inner, span)
        segs = fit_closed_simplest(p2, dev_limit=dev, corners=cs, report=rep)
    if store is not None: store[name] = rep
    return segs

ALIGNED = {k: fit_layer(k, v, store=REPORT) for k, v in SH.items()}

# ---------------------------------------------------------------- symmetry (normalization, recorded)
cp = sorted((SH["clipboard_card"][i] for i in corners_of("clipboard_card", SH["clipboard_card"])), key=lambda p: p[1])
axis = sum((a[0] + b[0]) / 2 for a, b in zip(cp[0::2], cp[1::2])) / (len(cp) // 2)
mir = lambda pts: [(2 * axis - x, y) for x, y in pts]
mseg = lambda c: tuple((2 * axis - x, y) for x, y in reversed(c))
def mean_near(a, b): return sum(min(math.hypot(p[0] - q[0], p[1] - q[1]) for q in b[::2]) for p in a[::3]) / len(a[::3])
asym = {"eyes": mean_near(SH["eye_left"], mir(SH["eye_right"])), "nose": mean_near(SH["nose"], mir(SH["nose"])),
        "body": mean_near(SH["body_silhouette"], mir(SH["body_silhouette"])), "card": mean_near(SH["clipboard_card"], mir(SH["clipboard_card"]))}
SYMMETRIZE = max(asym.values()) <= 2.0
print("axis", round(axis, 2), "asymmetry px", {k: round(v, 2) for k, v in asym.items()}, "-> symmetrize", SYMMETRIZE)

def left_half(pts):
    """Open polyline: the left half of a closed contour, from the top axis crossing to the bottom one."""
    n = len(pts); cross = [i for i in range(n) if (pts[i][0] - axis) * (pts[(i + 1) % n][0] - axis) <= 0]
    a, b = cross[0], cross[-1]
    arcs = [[pts[(a + 1 + m) % n] for m in range((b - a) % n)], [pts[(b + 1 + m) % n] for m in range((a - b) % n)]]
    half = min(arcs, key=lambda arc: sum(p[0] for p in arc) / len(arc))
    if half[0][1] > half[-1][1]: half = half[::-1]                       # top -> bottom
    half = [(min(x, axis), y) for x, y in half]; half[0] = (axis, half[0][1]); half[-1] = (axis, half[-1][1])
    return half

def mirror_layer(name, pts, dev, store):
    """Exactly symmetric: model + fit the left half, horizontal at both axis crossings, mirror the cubics."""
    rep = []; half = left_half(pts)
    if name == "nose":
        full = half + mir(half[::-1]); segs = convex_fit(full, rep)      # nose: convex model on the symmetrized ring
        store[name] = rep; return segs
    inner, span = CORNER_MODEL[name]
    cs = [i for i in corners_of(name, half + mir(half[::-1])) if 2 < i < len(half) - 3]
    # restore apexes on the half (corner model needs both sides; the half's corners are interior)
    p2, cs2 = restore_points(half, cs, inner, span)
    cuts = [0] + cs2 + [len(p2) - 1]; segs = []
    for a, b in zip(cuts, cuts[1:]):
        if b - a >= 1: segs += fit_open_simplest(p2[a:b + 1], dev, report=rep)
    p0, c1, c2, p3 = segs[0]; segs[0] = (p0, (c1[0], p0[1]), c2, p3)
    p0, c1, c2, p3 = segs[-1]; segs[-1] = (p0, c1, (c2[0], p3[1]), p3)
    store[name] = rep
    return segs + [mseg(c) for c in reversed(segs)]

def build_set(src, dev, store):
    out = {}
    if SYMMETRIZE:
        for k in ("body_silhouette", "clipboard_card", "nose"): out[k] = mirror_layer(k, src[k], dev, store)
        out["eye_left"] = fit_layer("eye_left", src["eye_left"], dev, store)
        out["eye_right"] = [mseg(c) for c in reversed(out["eye_left"])]
        for k in ("line_1", "line_2", "line_3"): out[k] = fit_layer(k, src[k], dev, store)
    else:
        out = {k: fit_layer(k, v, dev, store) for k, v in src.items()}
    return out

REPORT_MASTER = {}
MASTER_SRC = build_set(SH, DEV, REPORT_MASTER)

def scaled(pts, s):
    cx = sum(p[0] for p in pts) / len(pts); cy = sum(p[1] for p in pts) / len(pts)
    return [(cx + (x - cx) * s, cy + (y - cy) * s) for x, y in pts]
SMALL_IN = dict(SH); SMALL_IN["eye_left"] = scaled(SH["eye_left"], 1.3); SMALL_IN["nose"] = scaled(SH["nose"], 1.15)
SMALL_SRC = build_set(SMALL_IN, 2.2, {})

MOVE = {k: round(deviation(SH[k], MASTER_SRC[k])[1], 2) for k in SH}
print("master vs measured, rms px:", MOVE)

# ---------------------------------------------------------------- canvas + SVG writers
xs = [p[0] for p in SH["body_silhouette"]]; ys = [p[1] for p in SH["body_silhouette"]]
by0, by1 = min(ys), max(ys); cxm = axis if SYMMETRIZE else (min(xs) + max(xs)) / 2
V = 1024; S = 0.90 * V / (by1 - by0); TX = V / 2 - cxm * S; TY = V / 2 - (by0 + by1) / 2 * S
tr = lambda segs: [tuple((p[0] * S + TX, p[1] * S + TY) for p in c) for c in segs]
CUT = ("eye_left", "eye_right", "nose", "clipboard_card"); LINES = ("line_1", "line_2", "line_3")

def layered(paths, ink, w, bg=None, note=""):
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {w}" width="{w}" height="{w}">',
         f'<!-- Copibara flat mark{note}. Bézier rebuild of assets/brand/taskbar-icon-1.png (logo-to-vector). -->',
         f'<defs><mask id="cutouts" maskUnits="userSpaceOnUse" x="0" y="0" width="{w}" height="{w}"><rect width="{w}" height="{w}" fill="#fff"/>']
    o += [f'<path id="{k}" d="{to_path(paths[k])}" fill="#000"/>' for k in CUT]
    o += [f'<path id="{k}" d="{to_path(paths[k])}" fill="#fff"/>' for k in LINES]
    o.append('</mask></defs>')
    if bg: o.append(f'<rect id="paper" width="{w}" height="{w}" fill="{bg}"/>')
    o.append(f'<g id="mark"><path id="body_silhouette" d="{to_path(paths["body_silhouette"])}" fill="{ink}" mask="url(#cutouts)"/></g></svg>')
    return "\n".join(o)

def single(paths, fill, note, tile=None, inset=1.0, w=V, style=None):
    d = " ".join(to_path(paths[k]) for k in ("body_silhouette",) + CUT + LINES)
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {w}" width="{w}" height="{w}">', f'<!-- Copibara flat mark · {note} -->']
    if style: o.append(f"<style>{style}</style>")
    if tile: o.append(f'<rect width="{w}" height="{w}" rx="{w * 0.2237:.1f}" fill="{tile}"/>')
    t = "" if inset == 1.0 else f' transform="translate({w * (1 - inset) / 2:.2f} {w * (1 - inset) / 2:.2f}) scale({inset})"'
    attr = 'class="m"' if style else f'fill="{fill}"'
    o.append(f'<path id="copibara_mark" {attr} fill-rule="evenodd"{t} d="{d}"/></svg>'); return "\n".join(o)

M = {k: tr(v) for k, v in MASTER_SRC.items()}; SM = {k: tr(v) for k, v in SMALL_SRC.items()}
open("out/reference-aligned.svg", "w").write(layered(ALIGNED, INK, W0, bg="#FFFFFF", note=" · reference-aligned (1254 px source grid)"))
open("out/copibara-mark-master.svg", "w").write(layered(M, INK, V, note=" · master"))
open("out/copibara-mark-flat.svg", "w").write(single(M, "#000000", "flat: one even-odd path, single colour (template images, mask-icon)"))
open("out/copibara-mark-light.svg", "w").write(single(M, INK, "light: ink mark on a light tile", tile="#F6F1EA", inset=0.74))
open("out/copibara-mark-dark.svg", "w").write(single(M, "#FFFFFF", "dark: white mark on a dark tile", tile="#1C1C1E", inset=0.74))
open("out/copibara-mark-small.svg", "w").write(single(SM, INK, "small (16-32 px): eyes x1.3, nose x1.15, coarser curves"))
open("out/favicon.svg", "w").write(single(SM, INK, "favicon: small geometry; ink in light mode, white in dark mode",
                                          style=".m{fill:#212121}@media (prefers-color-scheme:dark){.m{fill:#fff}}"))

cols = {"body_silhouette": "#9AA0AA", "eye_left": "#1E88E5", "eye_right": "#1E88E5", "nose": "#43A047",
        "clipboard_card": "#F57C00", "line_1": "#E53935", "line_2": "#E53935", "line_3": "#E53935"}
wf = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {V} {V}" width="{V}" height="{V}"><rect width="{V}" height="{V}" fill="#fff"/>']
for k, c in cols.items(): wf.append(f'<path id="{k}" d="{to_path(M[k])}" fill="none" stroke="{c}" stroke-width="3"/>')
for k, segs in M.items(): wf += [f'<circle cx="{s[0][0]:.1f}" cy="{s[0][1]:.1f}" r="4" fill="{cols[k]}"/>' for s in segs]
open("out/layers-wireframe.svg", "w").write("\n".join(wf + ["</svg>"]))

json.dump(dict(aligned=REPORT, master=REPORT_MASTER), open("out/fit-report.json", "w"), indent=1)
json.dump({
    "source": "assets/brand/taskbar-icon-1.png (1254 px, opaque, ink #212121 on white) — the mark the menu bar icon was made from",
    "reference_aligned": {"grid": "1254 px source, untransformed", "background": "white paper (the source is opaque)",
                          "models": "arc-to-arc corners restored at circle intersections; text lines as exact capsules; nose convex"},
    "master": {"canvas": "1024 viewBox (exported 4096)", "placement": "mark height = 90% of canvas, centred on the mirror axis",
               "transparency": "eyes, nose and card are true cut-outs (the source paints them white)",
               "symmetry": (f"mirror-symmetric about x={axis:.1f}: body, card and nose built from their left halves and mirrored; right eye = mirrored left eye; "
                            f"text lines unchanged (they are left-aligned). Source asymmetry (mean px): " + ", ".join(f"{k} {v:.2f}" for k, v in asym.items()) +
                            "; within the 2 px tolerance.") if SYMMETRIZE else "not applied",
               "master_vs_source_rms_px": MOVE, "colour": INK + " sampled from the source"},
    "small": {"use": "16-32 px (favicon, tiny UI)", "changes": "eyes scaled 1.30x and nose 1.15x about their centroids; curve tolerance 2.2 px"},
    "light_dark": "master geometry on a 22.37% rounded tile, mark at 74% of the tile",
}, open("out/normalization.json", "w"), indent=1)
print("segments:", {k: len(v) for k, v in M.items()})

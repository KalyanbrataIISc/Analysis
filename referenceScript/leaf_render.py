"""Leaf-game frames rebuilt from the game logs.

Shared by ``leaf_gameplay_video.py`` (one video per block) and ``leaf_trial_diagrams.py``
(explanatory figures). Geometry, colours, HUD and timing rules follow the game source in the
sibling ``CogLab-Games`` repository (Assets/Games/Leaf/Scripts: LeafGameController*.cs,
LeafLaneLayout.cs, LeafVisualRenderer.cs) and ``Documentation/Games/Leaf.md``.

Inputs per block (``data/<date>/gameData``):
    p<P>_b<B>_leaves_trialdata.csv    trial timing, directions, cue, reveal, response, points
    p<P>_b<B>_leaves_ssvepframes.csv  CPU end-of-frame time of every trial frame (incl. drops)
    p<P>_b<B>_leaves_nftrace.csv      NF level / green zone every 12 frames

Exact from the logs: pre-SSVEP and trial timing, cue (which group flashes red), directions, NF
fill level and green zone, reveal frame and kind, response / miss, feedback text, HUD values,
dropped frames (held frames). NOT logged, so assumed (see SETTINGS): leaf start positions (the
game draws them from an unseeded RNG; each trial is re-laid out with the game's own lane /
invariant-grid algorithm from ``layout_seed``), the screen / safe area, and the red-flash rate.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image, ImageDraw, ImageFont

PROJECT_ROOT = Path(__file__).resolve().parent.parent
GAME_REPO = PROJECT_ROOT.parent / "CogLab-Games"
BACKGROUND_PNG = GAME_REPO / "Assets" / "Resources" / "LeafGame" / "BackgroundTexture.png"

# =================================== SETTINGS ===================================
SCREEN_W, SCREEN_H = 3200, 2136   # tablet (Xiaomi 25097RP43I, stimframes metadata 2026-11-02);
                                  # safe area assumed to be the full screen
REFRESH_HZ = 120                  # display rate (also logged per trial in ssvepframes)
GAME = dict(                      # prefab defaults unless the logs show otherwise
    pre_flash_hz=4,               # red cue flash; not logged, game default
    pre_border_lum=0.5,           # steady pre-SSVEP border grey
    ssvep_mean_lum=0.5,           # border grey when the SSVEP flicker is not drawn
    iti_sec=5,
    nf_green_hold_sec=1, nf_green_threshold=0.9,
    leaves_per_flock=8, leaf_size_px=150, leaf_width_mult=0.42, leaf_border_mult=0.2,
    leaf_speed_px_s=200, lane_margin_px=6, leaf_arc_points=10,
    reference_short_side=1080, min_scale=0.25, max_scale=4,
    autofit_min_fraction=0.35, autofit_step_fraction=0.05, max_field_shrink_px=400, min_repeats=1,
    cue_w_px=520, cue_h_px=90, cue_corner_px=20, cue_corner_segments=8, cue_bottom_px=24,
    cue_font_px=32, cue_outline_px=2,            # cueFontSize 64 x cueCharacterSize 0.5
    feedback_font_px=96,
    c1_rgb=(0, 191, 255), c2_rgb=(255, 140, 0), green_rgb=(179, 255, 179), flash_rgb=(255, 0, 0),
    success_rgb=(0, 255, 0), failure_rgb=(255, 0, 0),
    cue_words=("Moving", "Pointing"),            # left half (C2 colour), right half (C1 colour)
    # HUD (IMGUI); sizes at a 1080-px short side (x UiScale)
    hud_tile_w=166, hud_tile_h=72, hud_gap=10, hud_right_pad=14, hud_top=12,
    hud_label_px=17, hud_value_px=31, hud_button_px=26,
    hud_panel_rgba=(10, 30, 42, 224), hud_label_rgb=(179, 214, 204),
    exit_bg_rgba=(47, 38, 45, 245), exit_text_rgb=(230, 128, 128), hud_corner_px=15,
)
# ================================================================================

DIRS = ("up", "down", "left", "right")
DIR_VEC = np.array([[0, -1], [0, 1], [-1, 0], [1, 0]], float)   # y-down screen coordinates


# ------------------------------------------------------------------ geometry
@dataclass
class Dims:
    L: float; W: float; B: float; OL: float; OW: float; margin: float; speed: float; max_radius: float


def leaf_dims(s: float) -> Dims:
    g = GAME
    L = g["leaf_size_px"] * s
    W = g["leaf_size_px"] * g["leaf_width_mult"] * s
    B = g["leaf_size_px"] * g["leaf_border_mult"] * s
    OL, OW = L + 2 * B, W + 2 * B
    return Dims(L, W, B, OL, OW, g["lane_margin_px"] * s, g["leaf_speed_px_s"] * s / REFRESH_HZ,
                0.5 * math.hypot(OL, OW))


def all_combos():
    """The 24 (C1 point, C1 move, C2 point, C2 move) combinations, 0=up 1=down 2=left 3=right."""
    out = []
    for p1 in range(4):
        for m1 in range(4):
            if m1 == p1:
                continue
            r = [d for d in range(4) if d not in (p1, m1)]
            out += [(p1, m1, r[0], r[1]), (p1, m1, r[1], r[0])]
    return out


def choose_field(sw, sh, required, max_shrink, min_repeats):
    """LeafLaneLayout.ChooseField: largest w x h near the viewport with gcd(w, h) >= required."""
    max_shrink = min(max_shrink, min(sw - 1, sh - 1))
    if max_shrink < 0 or required * min_repeats > min(sw, sh):
        return None
    w = np.arange(sw, sw - max_shrink - 1, -1)
    h = np.arange(sh, sh - max_shrink - 1, -1)
    G = np.gcd.outer(w, h)
    Wm, Hm = np.meshgrid(w, h, indexing="ij")
    valid = (G >= required) & (Wm // G >= min_repeats) & (Hm // G >= min_repeats)
    if not valid.any():
        return None
    area = np.where(valid, Wm.astype(np.int64) * Hm, -1)
    iw, ih = np.unravel_index(np.argmax(area), area.shape)   # first max in the C# loop order
    bw, bh = int(w[iw]), int(h[ih])
    return ((sw - bw) // 2, (sh - bh) // 2, bw, bh), math.gcd(bw, bh)


def _extents(p, d):
    return (d.OL, d.OW) if p >= 2 else (d.OW, d.OL)


def _count_slots(half, spacing):
    return max(1, math.floor(2 * half / spacing) + 1)


def _place_along(n, lanes, along_size, min_spacing, rnd):
    lc = len(lanes)
    if lc < 1:
        return None
    counts = [0] * lc
    for i in range(n):
        counts[i % lc] += 1
    if any(c > math.floor(along_size / min_spacing) for c in counts):
        return None
    offsets = [rnd() * along_size for _ in range(lc)]
    placed = [0] * lc
    along, cross = np.zeros(n), np.zeros(n)
    for i in range(n):
        l = i % lc
        along[i] = (offsets[l] + placed[l] * along_size / counts[l]) % along_size
        placed[l] += 1
        cross[i] = lanes[l]
    return along, cross


def _place_invariant(n, lanes, along_size, modulus, half, centre, own, other, spacing, rnd):
    lc = len(lanes)
    windows = max(1, round(along_size / modulus))
    slots = _count_slots(half, spacing)
    if lc * windows * slots < n:
        return None
    step = spacing if slots > 1 else 0
    slack = max(0, 2 * half - (slots - 1) * step)
    counts = [0] * lc
    for i in range(n):
        counts[i % lc] += 1
    jitter = [rnd() * slack for _ in range(lc)]
    total = windows * slots
    along, cross = np.zeros(n), np.zeros(n)
    k = 0
    for lane in range(lc):
        for j in range(counts[lane]):
            idx = (j * total // counts[lane] + lane) % total
            win, slot = idx % windows, idx // windows
            inv = centre - half + jitter[lane] + slot * step
            phase = (own * (inv - other * lanes[lane])) % modulus
            along[k] = (phase + win * modulus) % along_size
            cross[k] = lanes[lane]
            k += 1
    return along, cross


def lane_layout(n, field, d: Dims, combo, rnd):
    """LeafLaneLayout.Create. Returns (positions[2n,2], velocities[2n,2], flock[2n]) or None."""
    p1, m1, p2, m2 = combo
    e1, e2 = _extents(p1, d), _extents(p2, d)
    v1, v2 = DIR_VEC[m1], DIR_VEC[m2]
    fx, fy, fw, fh = field
    m = d.margin
    x, y = np.zeros(2 * n), np.zeros(2 * n)
    if (v1[0] != 0) == (v2[0] != 0):                       # same axis: alternating lanes
        on_x = v1[0] != 0
        cross_size, along_size = (fh, fw) if on_x else (fw, fh)
        ce = max(e1[1], e2[1]) if on_x else max(e1[0], e2[0])
        a1, a2 = (e1[0], e2[0]) if on_x else (e1[1], e2[1])
        lane_count = math.floor(cross_size / (ce + m))
        if lane_count < 2:
            return None
        c = [(i + 0.5) * (cross_size / lane_count) for i in range(lane_count)]
        r1 = _place_along(n, c[0::2], along_size, a1 + m, rnd)
        r2 = _place_along(n, c[1::2], along_size, a2 + m, rnd) if r1 is not None else None
        if r2 is None:
            return None
        (A1, C1), (A2, C2) = r1, r2
        if on_x:
            x[:n], y[:n], x[n:], y[n:] = fx + A1, fy + C1, fx + A2, fy + C2
        else:
            x[:n], y[:n], x[n:], y[n:] = fx + C1, fy + A1, fx + C2, fy + A2
    else:                                                  # perpendicular: invariant grid
        f1x = v1[0] != 0
        eA, eB, vA, vB = (e1, e2, v1, v2) if f1x else (e2, e1, v2, v1)
        sA, sB = vA[0], vB[1]
        g = math.gcd(round(fw), round(fh))
        c_req = (eA[0] + eB[0]) / 2 + (eA[1] + eB[1]) / 2 + 2 * m
        if g <= 2 * c_req:
            return None
        hA = hB = (g / 2 - c_req) / 2
        max_a = max(1, math.floor(fh / (eA[1] + m)))
        max_b = max(1, math.floor(fw / (eB[0] + m)))
        slots_a = max(1, round(fw / g)) * _count_slots(hA, eA[0] + m)
        slots_b = max(1, round(fh / g)) * _count_slots(hB, eB[1] + m)
        na = min(max_a, max(1, -(-n // slots_a)))
        nb = min(max_b, max(1, -(-n // slots_b)))
        lanes_a = [(i + 0.5) * (fh / na) for i in range(na)]
        lanes_b = [(i + 0.5) * (fw / nb) for i in range(nb)]
        ra = _place_invariant(n, lanes_a, fw, g, hA, 0, sA, sB, eA[0] + m, rnd)
        rb = _place_invariant(n, lanes_b, fh, g, hB, g / 2, sB, sA, eB[1] + m, rnd) if ra is not None else None
        if rb is None:
            return None
        (alA, crA), (alB, crB) = ra, rb
        if f1x:
            x[:n], y[:n], x[n:], y[n:] = fx + alA, fy + crA, fx + crB, fy + alB
        else:
            x[n:], y[n:], x[:n], y[:n] = fx + alA, fy + crA, fx + crB, fy + alB
    vel = np.vstack([np.tile(v1 * d.speed, (n, 1)), np.tile(v2 * d.speed, (n, 1))])
    return np.column_stack([x, y]), vel, np.r_[np.zeros(n, int), np.ones(n, int)]


@dataclass
class Geometry:
    s: float; u: float; d: Dims; field: tuple; gcd: int; k: float; out_w: int; out_h: int


def screen_geometry(out_scale=0.5) -> Geometry:
    """activePixelScale (auto-fit), field rectangle and UiScale as LeafGameController computes them."""
    g = GAME
    requested = min(max(min(SCREEN_W, SCREEN_H) / g["reference_short_side"], g["min_scale"]), g["max_scale"])
    minimum = max(g["min_scale"], requested * g["autofit_min_fraction"])
    step = max(0.01, requested * g["autofit_step_fraction"])
    combos = all_combos()
    scale = requested
    while scale >= minimum - 1e-4:
        s = max(minimum, scale)
        d = leaf_dims(s)
        required = math.ceil(2 * (d.OL + d.OW + 2 * d.margin)) + 1
        res = choose_field(SCREEN_W, SCREEN_H, required, round(g["max_field_shrink_px"] * s), g["min_repeats"])
        if res and all(lane_layout(g["leaves_per_flock"], res[0], d, c, lambda: 0.5) for c in combos):
            u = min(max(min(SCREEN_W, SCREEN_H) / 1080, 0.15), 4)
            return Geometry(s, u, d, res[0], res[1], out_scale,
                            2 * round(SCREEN_W * out_scale / 2), 2 * round(SCREEN_H * out_scale / 2))
        scale -= step
    raise RuntimeError("Display auto-fit failed")


def leaf_shape(pointing, length, width, arc_points=GAME["leaf_arc_points"]):
    """LeafVisualRenderer.CreateLeafShape: polygon in y-down coordinates centred on the leaf."""
    n = min(max(arc_points, 5), 64)
    stem_rear, body_rear, tip = -length * 0.5, -length * 0.30, length * 0.5
    hw = width * 0.5
    stem_half = min(hw * 0.32, max(0.75, width * 0.055))
    pts = [(stem_rear, -stem_half), (body_rear, -stem_half)]
    for i in range(1, n + 1):
        t = i / n
        env = max(0.0, math.sin(math.pi * t)) ** 0.72
        org = min(1.0, 0.90 + 0.06 * math.sin(math.pi * t) + 0.04 * math.sin(2 * math.pi * t))
        pts.append((body_rear + (tip - body_rear) * t, -(stem_half * (1 - t) + (hw - stem_half) * env * org)))
    for i in range(n - 1, 0, -1):
        t = i / n
        env = max(0.0, math.sin(math.pi * t)) ** 0.72
        org = min(1.0, 0.94 + 0.08 * math.sin(math.pi * t) - 0.05 * math.sin(2 * math.pi * t))
        pts.append((body_rear + (tip - body_rear) * t, stem_half * (1 - t) + (hw - stem_half) * env * org))
    pts += [(body_rear, stem_half), (stem_rear, stem_half)]
    a = math.radians((-90, 90, 180, 0)[pointing])
    R = np.array([[math.cos(a), -math.sin(a)], [math.sin(a), math.cos(a)]])
    return np.array(pts) @ R.T


# ------------------------------------------------------------------ raster helpers
SS = 4  # supersampling for anti-aliased shapes and text


def poly_mask(points, h, w):
    """Coverage of a polygon in local pixel coordinates (pixel (r, c) covers [c, c+1) x [r, r+1))."""
    img = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(img).polygon([(float(x) * SS, float(y) * SS) for x, y in points], fill=255)
    return np.asarray(img.reduce(SS), np.float32) / 255


def rounded_rect_mask(w, h, r):
    wi, hi = math.ceil(w), math.ceil(h)
    img = Image.new("L", (wi * SS, hi * SS), 0)
    ImageDraw.Draw(img).rounded_rectangle([0, 0, w * SS - 1, h * SS - 1], radius=r * SS, fill=255)
    return np.asarray(img.reduce(SS), np.float32) / 255


def blend(F, M, r0, c0, rgb):
    """Paint a flat colour (0-1) with coverage M whose top-left pixel lands at row r0, col c0."""
    h, w = M.shape
    H, W = F.shape[:2]
    r1, r2, c1, c2 = max(0, r0), min(H, r0 + h), max(0, c0), min(W, c0 + w)
    if r1 >= r2 or c1 >= c2:
        return
    a = M[r1 - r0:r2 - r0, c1 - c0:c2 - c0, None]
    reg = F[r1:r2, c1:c2]
    reg *= 1 - a
    reg += a * np.asarray(rgb, np.float32)


def blend_rgba(F, I, A, r0, c0):
    h, w = A.shape
    H, W = F.shape[:2]
    r1, r2, c1, c2 = max(0, r0), min(H, r0 + h), max(0, c0), min(W, c0 + w)
    if r1 >= r2 or c1 >= c2:
        return
    a = A[r1 - r0:r2 - r0, c1 - c0:c2 - c0, None]
    F[r1:r2, c1:c2] = F[r1:r2, c1:c2] * (1 - a) + I[r1 - r0:r2 - r0, c1 - c0:c2 - c0] * a


def _font_path(bold):
    names = ("arialbd.ttf", "Arial Bold.ttf") if bold else ("arial.ttf", "Arial.ttf")
    for d in (Path("C:/Windows/Fonts"), Path("/System/Library/Fonts/Supplemental"), Path("/Library/Fonts"),
              Path("/usr/share/fonts/truetype/msttcorefonts")):
        for n in names:
            if (d / n).is_file():
                return str(d / n)
    import matplotlib
    return str(Path(matplotlib.get_data_path()) / "fonts" / "ttf" / ("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"))


@dataclass
class Text:
    rgb: np.ndarray; a: np.ndarray; ax: float; ay: float


@lru_cache(maxsize=None)
def text_image(s, px, bold=False, rgb=(255, 255, 255), outline_rgb=(0, 0, 0), outline_px=0.0):
    """Arial (Unity's LegacyRuntime font) text with Unity's Outline effect; anchor = block centre."""
    font = ImageFont.truetype(_font_path(bold), max(1, round(px * SS)))
    spacing = round(0.12 * px * SS)
    l, t, r, b = ImageDraw.Draw(Image.new("L", (1, 1))).multiline_textbbox(
        (0, 0), s, font=font, anchor="mm", align="center", spacing=spacing)
    pad = (math.ceil(outline_px) + 3) * SS
    wc = math.ceil((2 * max(r, -l) + 2 * pad) / SS) * SS
    hc = math.ceil((2 * max(b, -t) + 2 * pad) / SS) * SS
    img = Image.new("L", (wc, hc), 0)
    ImageDraw.Draw(img).multiline_text((wc / 2, hc / 2), s, font=font, fill=255, anchor="mm",
                                       align="center", spacing=spacing)
    a = np.asarray(img.reduce(SS), np.float32) / 255
    H, W = a.shape
    col = np.empty((H, W, 3), np.float32)
    if outline_px > 0:
        dpx = max(1, round(outline_px))
        ao = np.zeros_like(a)
        for sx in (-dpx, dpx):
            for sy in (-dpx, dpx):
                ao = np.maximum(ao, np.roll(a, (sy, sx), axis=(0, 1)))
        at = 1 - (1 - a) * (1 - ao)
        col[:] = (np.asarray(rgb, np.float32) / 255 * a[..., None]
                  + np.asarray(outline_rgb, np.float32) / 255 * (ao * (1 - a))[..., None]) / np.maximum(at, 1e-6)[..., None]
    else:
        at = a
        col[:] = np.asarray(rgb, np.float32) / 255
    rr, cc = np.nonzero(at > 0.004)
    r1, r2 = max(0, rr.min() - 1), min(H, rr.max() + 2)
    c1, c2 = max(0, cc.min() - 1), min(W, cc.max() + 2)
    return Text(col[r1:r2, c1:c2], at[r1:r2, c1:c2], W / 2 - c1, H / 2 - r1)


def draw_text(F, T: Text, cx, cy):
    blend_rgba(F, T.rgb, T.a, round(cy - T.ay), round(cx - T.ax))


# ------------------------------------------------------------------ static assets
class Assets:
    """Background, double cue, static HUD layer and leaf sprites for one screen geometry."""

    def __init__(self, geo: Geometry):
        g, k, s, u = GAME, geo.k, geo.s, geo.u
        self.geo = geo
        bg = Image.open(BACKGROUND_PNG).convert("RGB").resize((geo.out_w, geo.out_h), Image.BILINEAR)
        self.bg = np.asarray(bg, np.float32) / 255           # sprite stretched over the full screen
        # double cue (bottom of the full-screen safe area)
        cw, ch = g["cue_w_px"] * s, g["cue_h_px"] * s
        rad = min(g["cue_corner_px"] * s, cw * 0.25, ch * 0.5)
        self.cue_cy = (SCREEN_H - (g["cue_bottom_px"] * s + ch / 2)) * k
        self.cue_cx = SCREEN_W / 2 * k
        bw, bh = math.ceil(cw * k) + 4, math.ceil(ch * k) + 4
        self.cue_masks = []
        for left in (True, False):
            P = self._half_cue(cw, ch, rad, g["cue_corner_segments"], left) * k
            P[:, 1] = -P[:, 1]
            self.cue_masks.append(poly_mask(P + [bw / 2, bh / 2], bh, bw))
        self.cue_r0, self.cue_c0 = round(self.cue_cy - bh / 2), round(self.cue_cx - bw / 2)
        self.cue_rgb = [np.array(g["c2_rgb"]) / 255, np.array(g["c1_rgb"]) / 255]
        self.cue_words = [text_image(w, g["cue_font_px"] * s * k, False, (0, 0, 0), (255, 255, 255),
                                     g["cue_outline_px"] * s * k) for w in g["cue_words"]]
        self.cue_word_x = [self.cue_cx - cw * 0.25 * k, self.cue_cx + cw * 0.25 * k]
        # HUD (IMGUI, top-left coordinates)
        tile_w = min(max(g["hud_tile_w"] * u, 112 * u), SCREEN_W * 0.20)
        tile_h, gap = g["hud_tile_h"] * u, g["hud_gap"] * u
        x0, y0 = SCREEN_W - 3 * tile_w - 2 * gap - g["hud_right_pad"] * u, g["hud_top"] * u
        L = np.zeros((geo.out_h, geo.out_w, 3), np.float32)
        LA = np.zeros((geo.out_h, geo.out_w), np.float32)
        tile = rounded_rect_mask(tile_w * k, tile_h * k, g["hud_corner_px"] * k)
        self.hud_value_x = []
        for i, label in enumerate(("TIME", "SCORE", "REACHED COLOR")):
            xt = x0 + i * (tile_w + gap)
            self._paint(L, LA, tile * g["hud_panel_rgba"][3] / 255, round(y0 * k), round(xt * k),
                        np.array(g["hud_panel_rgba"][:3]) / 255)
            T = text_image(label, round(g["hud_label_px"] * u) * k, True, g["hud_label_rgb"])
            self._paint_text(L, LA, T, (xt + tile_w / 2) * k, (y0 + 4 + 11 * u) * k)
            self.hud_value_x.append((xt + tile_w / 2) * k)
        self.hud_value_y = (y0 + 23 * u + (tile_h - 25 * u) / 2) * k
        self.hud_value_px = round(g["hud_value_px"] * u) * k
        bwid, bhei, bx, by = max(150, 190 * u), max(44, 56 * u), 14 * u, 12 * u
        btn = rounded_rect_mask(bwid * k, bhei * k, g["hud_corner_px"] * k)
        self._paint(L, LA, btn * g["exit_bg_rgba"][3] / 255, round(by * k), round(bx * k),
                    np.array(g["exit_bg_rgba"][:3]) / 255)
        self._paint_text(L, LA, text_image("Exit to menu", round(g["hud_button_px"] * u) * k, True, g["exit_text_rgb"]),
                         (bx + bwid / 2) * k, (by + bhei / 2) * k)
        rr, cc = np.nonzero(LA > 0)
        self.hud_rows, self.hud_cols = slice(rr.min(), rr.max() + 1), slice(cc.min(), cc.max() + 1)
        self.hud_rgb, self.hud_a = L[self.hud_rows, self.hud_cols], LA[self.hud_rows, self.hud_cols, None]
        self.feedback_px = round(g["feedback_font_px"] * s) * k
        self.feedback_outline = max(1, round(g["feedback_font_px"] * s) * 0.03) * k
        self._sprites = {}

    @staticmethod
    def _half_cue(w, h, r, segs, left):
        hy = h / 2
        outer = -w / 2 if left else w / 2

        def arc(c, a0, a1):
            a = np.radians(np.linspace(a0, a1, segs + 1))
            return np.column_stack([c[0] + r * np.cos(a), c[1] + r * np.sin(a)])
        if left:
            return np.vstack([[0, hy], arc((outer + r, hy - r), 90, 180), arc((outer + r, -hy + r), 180, 270), [0, -hy]])
        return np.vstack([[0, -hy], arc((outer - r, -hy + r), 270, 360), arc((outer - r, hy - r), 0, 90), [0, hy]])

    @staticmethod
    def _paint(L, LA, M, r0, c0, rgb):
        h, w = M.shape
        a0 = LA[r0:r0 + h, c0:c0 + w]
        an = M + a0 * (1 - M)
        L[r0:r0 + h, c0:c0 + w] = ((rgb * M[..., None]) + L[r0:r0 + h, c0:c0 + w] * (a0 * (1 - M))[..., None]) \
            / np.maximum(an, 1e-6)[..., None]
        LA[r0:r0 + h, c0:c0 + w] = an

    def _paint_text(self, L, LA, T, cx, cy):
        h, w = T.a.shape
        r0, c0 = round(cy - T.ay), round(cx - T.ax)
        a0 = LA[r0:r0 + h, c0:c0 + w]
        an = T.a + a0 * (1 - T.a)
        L[r0:r0 + h, c0:c0 + w] = (T.rgb * T.a[..., None] + L[r0:r0 + h, c0:c0 + w] * (a0 * (1 - T.a))[..., None]) \
            / np.maximum(an, 1e-6)[..., None]
        LA[r0:r0 + h, c0:c0 + w] = an

    def sprites(self, pointing, n_phase=4):
        """Outer / inner coverage masks of one leaf direction at n_phase^2 sub-pixel offsets."""
        if pointing not in self._sprites:
            d, k = self.geo.d, self.geo.k
            Po, Pi = leaf_shape(pointing, d.OL, d.OW) * k, leaf_shape(pointing, d.L, d.W) * k
            o = math.ceil(np.abs(Po).max()) + 2
            sz = 2 * o + 1
            outer, inner = {}, {}
            for py in range(n_phase):
                for px in range(n_phase):
                    off = np.array([o + px / n_phase, o + py / n_phase])
                    outer[py, px] = poly_mask(Po + off, sz, sz)
                    inner[py, px] = poly_mask(Pi + off, sz, sz)
            self._sprites[pointing] = (o, n_phase, outer, inner)
        return self._sprites[pointing]

    def draw_cue(self, F):
        for m, rgb in zip(self.cue_masks, self.cue_rgb):
            blend(F, m, self.cue_r0, self.cue_c0, rgb)
        for T, x in zip(self.cue_words, self.cue_word_x):
            draw_text(F, T, x, self.cue_cy)

    def draw_hud(self, F, t, score, reached):
        reg = F[self.hud_rows, self.hud_cols]
        reg *= 1 - self.hud_a
        reg += self.hud_rgb * self.hud_a
        sec = max(0, math.floor(t))
        for v, x in zip((f"{sec // 60:02d}:{sec % 60:02d}", str(score), str(reached)), self.hud_value_x):
            draw_text(F, text_image(v, self.hud_value_px, True), x, self.hud_value_y)


# ------------------------------------------------------------------ one block
@dataclass
class Trial:
    frame_end: np.ndarray; level: np.ndarray; green: np.ndarray; reveal: int; lum: np.ndarray
    P: int; cue_onset: float; cue: int; combo: tuple; trial_end: float; feedback: str; correct: bool
    layout: tuple = None


def load_block(game_dir: Path, stem: str):
    """Trial table and per-trial frame data of one block (stem = p<P>_b<B>_leaves)."""
    g = GAME
    T = pd.read_csv(game_dir / f"{stem}_trialdata.csv")
    S = pd.read_csv(game_dir / f"{stem}_ssvepframes.csv")
    N = pd.read_csv(game_dir / f"{stem}_nftrace.csv")
    if T.TrialNumber.duplicated().any():
        raise ValueError(f"{stem}: repeated TrialNumber (several runs appended)")
    trials = []
    for _, r in T.iterrows():
        s = S[S.TrialNumber == r.TrialNumber].sort_values("FrameNumber")
        n = N[N.TrialNumber == r.TrialNumber].sort_values("FrameNumber")
        if s.FrameNumber.iloc[0] != 1 or (np.diff(s.FrameNumber) != 1).any():
            raise ValueError(f"{stem} trial {r.TrialNumber}: gap in ssvepframes")
        fe = s.FrameEndTime.to_numpy(float).copy()
        bad = np.isnan(fe)
        if bad.any():   # rare missing end times: predicted display time + median offset
            ed = s.EstimatedDisplayTime.to_numpy(float)
            fe[bad] = ed[bad] + np.median(fe[~bad] - ed[~bad])
        K = len(fe)
        frames = np.arange(1, K + 1)
        nf = n.FrameNumber.to_numpy()
        level = np.interp(frames, np.r_[nf, K + 1], np.r_[n.NFLevel, n.NFLevel.iloc[-1]])
        green = level >= g["nf_green_threshold"]
        pre = n.ColorsRevealed.to_numpy() == 0
        for f, hold, ing in zip(nf[pre], n.GreenHoldSec.to_numpy()[pre], n.InGreenZone.to_numpy()[pre]):
            if ing:     # known green run from the hold counter
                green[max(0, f - round(hold * REFRESH_HZ)):f] = True
            else:
                green[f - 1] = False
        idx = np.nonzero(fe >= r.ColorOnsetTime - 0.5 / REFRESH_HZ)[0]
        reveal = int(idx[0]) + 1 if idx.size else K               # 1-based reveal frame
        if r.NfSuccess == 1:   # NF reveal: the last hold frames were green
            green[max(0, reveal - round(g["nf_green_hold_sec"] * REFRESH_HZ)):reveal] = True
        verdict = "Missed" if r.ResponseTimeout == 1 else ("Correct" if r.Accuracy == 1 else "Incorrect")
        trials.append(Trial(
            frame_end=fe, level=level, green=green, reveal=reveal,
            lum=s[["BorderLuminanceC1", "BorderLuminanceC2"]].to_numpy(float),
            P=round(r.PreSsvepSec * REFRESH_HZ), cue_onset=r.CueOnsetTime, cue=int(r.Cue == "c2"),
            combo=tuple(DIRS.index(r[c]) for c in ("C1PointDir", "C1MoveDir", "C2PointDir", "C2MoveDir")),
            trial_end=r.TrialEnd, feedback=f"{verdict}\n+{int(r.Points)} points", correct=r.Accuracy == 1))
    return T, trials


def find_blocks(day_dir: Path):
    """[(participant, block, stem)] of every Leaf block of a day, sorted by name."""
    out = []
    for f in sorted((day_dir / "gameData").glob("*_leaves_trialdata.csv")):
        if f.name.startswith("."):          # macOS ._* / .DS_Store
            continue
        parts = f.name.split("_")
        if len(parts) == 4 and parts[0].startswith("p") and parts[1].startswith("b"):
            out.append((parts[0][1:], parts[1][1:], f"{parts[0]}_{parts[1]}_leaves"))
    return out


class LeafRenderer:
    """Frame at any game time t (s since the session's T0, as the HUD TIME) of one block."""

    def __init__(self, game_dir: Path, stem: str, assets: Assets, layout_seed=1, draw_ssvep=False):
        self.A, self.geo = assets, assets.geo
        self.T, self.trials = load_block(game_dir, stem)
        self.draw_ssvep = draw_ssvep
        block = int(stem.split("_")[1][1:])
        rng = np.random.default_rng(layout_seed + block)
        for tr in self.trials:
            tr.layout = lane_layout(GAME["leaves_per_flock"], self.geo.field, self.geo.d, tr.combo, rng.random)
            if tr.layout is None:
                raise RuntimeError("layout infeasible")
        self.cue_onsets = np.array([tr.cue_onset for tr in self.trials])
        self.t_start = self.trials[0].cue_onset - GAME["iti_sec"]      # lead-in ITI after "Begin block"
        self.t_end = self.trials[-1].trial_end + GAME["iti_sec"]

    def phase(self, t):
        """('iti'|'pre'|'trial'|'feedback', trial, frame index, Advance() count) at time t."""
        i = np.searchsorted(self.cue_onsets, t, side="right") - 1
        if i < 0:
            return "iti", None, 0, 0
        tr = self.trials[i]
        if t < tr.frame_end[0]:
            p = min(tr.P, math.floor((t - tr.cue_onset) * REFRESH_HZ) + 1)
            return "pre", tr, p, p
        if t < tr.frame_end[-1]:
            kf = int(np.searchsorted(tr.frame_end, t, side="right"))
            return "trial", tr, kf, tr.P + kf
        if t < tr.trial_end:
            return "feedback", tr, 0, 0
        return "iti", tr, 0, 0

    def leaf_positions(self, tr, adv):
        """Screen positions after `adv` Advance() calls (motion with wrap), plus flock index."""
        pos0, vel, flock = tr.layout
        fx, fy, fw, fh = self.geo.field
        fmin, fsz = np.array([fx, fy], float), np.array([fw, fh], float)
        return fmin + np.mod(pos0 - fmin + adv * vel, fsz), flock

    def frame(self, t):
        g, A, k, d = GAME, self.A, self.geo.k, self.geo.d
        F = A.bg.copy()
        ph, tr, idx, adv = self.phase(t)
        if ph in ("pre", "trial"):
            grey = lambda v: (v, v, v)
            if ph == "pre":
                flash = flash_on((idx - 1) / REFRESH_HZ, (tr.P - 1) / REFRESH_HZ, g["pre_flash_hz"])
                fills = [(0, 0, 0)] * 2
                borders = [grey(g["pre_border_lum"])] * 2
                if flash:
                    borders[tr.cue] = tuple(c / 255 for c in g["flash_rgb"])
            else:
                if idx >= tr.reveal:
                    fills = [tuple(c / 255 for c in g["c1_rgb"]), tuple(c / 255 for c in g["c2_rgb"])]
                elif tr.green[idx - 1]:
                    fills = [tuple(c / 255 for c in g["green_rgb"])] * 2
                else:
                    fills = [grey(tr.level[idx - 1])] * 2
                if self.draw_ssvep:
                    borders = [grey(tr.lum[idx - 1, 0]), grey(tr.lum[idx - 1, 1])]
                else:
                    borders = [grey(g["ssvep_mean_lum"])] * 2
            self._draw_leaves(F, tr, adv, fills, borders)
            A.draw_cue(F)
        elif ph == "feedback":
            A.draw_cue(F)
            col = g["success_rgb"] if tr.correct else g["failure_rgb"]
            draw_text(F, text_image(tr.feedback, A.feedback_px, False, col, (0, 0, 0), A.feedback_outline),
                      self.geo.out_w / 2, self.geo.out_h / 2)
        T = self.T
        done = T.TrialEnd.to_numpy() <= t
        score = int(T.TotalPoints.to_numpy()[done][-1]) if done.any() else 0
        reached = int(((T.NfSuccess == 1) & (T.ColorOnsetTime <= t)).sum())
        A.draw_hud(F, t, score, reached)
        return np.clip(F, 0, 1)

    def _draw_leaves(self, F, tr, adv, fills, borders):
        d, k = self.geo.d, self.geo.k
        fx, fy, fw, fh = self.geo.field
        pos, flock = self.leaf_positions(tr, adv)
        dirs = (tr.combo[0], tr.combo[2])
        copies = []
        for p in pos:      # RenderLeaves: wrap copies near the field edges
            dx = fw if p[0] - d.max_radius < fx else (-fw if p[0] + d.max_radius > fx + fw else 0)
            dy = fh if p[1] - d.max_radius < fy else (-fh if p[1] + d.max_radius > fy + fh else 0)
            c = [p]
            if dx:
                c.append(p + (dx, 0))
            if dy:
                c.append(p + (0, dy))
            if dx and dy:
                c.append(p + (dx, dy))
            copies.append(c)
        for layer in (0, 1):                    # all borders first, then all fills (sorting order)
            for j, cs in enumerate(copies):
                fl = flock[j]
                o, nph, outer, inner = self.A.sprites(dirs[fl])
                masks = outer if layer == 0 else inner
                rgb = borders[fl] if layer == 0 else fills[fl]
                for p in cs:
                    q = p * k
                    fq = np.floor(q)
                    pxi = min(nph - 1, int((q[0] - fq[0]) * nph))
                    pyi = min(nph - 1, int((q[1] - fq[1]) * nph))
                    blend(F, masks[pyi, pxi], int(fq[1]) - o, int(fq[0]) - o, rgb)


def flash_on(t_sec, last_frame_sec, hz):
    """LeafGameController.PreSsvepFlashOn: square wave; only whole red halves ending by the last frame."""
    cyc = t_sec * hz
    i = math.floor(cyc)
    return hz > 0 and t_sec >= 0 and cyc - i < 0.5 and (i + 0.5) / hz <= last_frame_sec + 1e-9


def to_uint8(F):
    return (F * 255 + 0.5).astype(np.uint8)

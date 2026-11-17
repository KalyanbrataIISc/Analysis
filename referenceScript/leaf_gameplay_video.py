"""Rebuild the gameplay video of every Leaf block of one recording day from the game logs.

    python referenceScript/leaf_gameplay_video.py                    # all Leaf blocks of DAY
    python referenceScript/leaf_gameplay_video.py --blocks 2 3       # some blocks
    python referenceScript/leaf_gameplay_video.py --max-sec 30       # quick test

Output: video/<date>_leaf_p<P>_b<B>_gameplay.mp4 (H.264, needs ffmpeg on PATH). Each video starts
with a short title card listing what is exact and what is assumed, then the lead-in ITI before
trial 1, and ends after the last ITI. Video time follows game time (HUD TIME = s since T0).
What is taken from the logs and what is assumed: see leaf_render.py.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import leaf_render as lr  # noqa: E402

# =================================== SETTINGS ===================================
DAY = "2026-11-16"          # recording day (data/<DAY>)
OUT_FPS = 60                # video frame rate (game ran at 120 Hz; every 2nd game frame is shown)
OUT_SCALE = 0.5             # video pixels per screen pixel (3200x2136 -> 1600x1068)
CRF = 18                    # H.264 quality (lower = better / larger)
TITLE_CARD_SEC = 4          # title card length (0 = none)
DRAW_SSVEP = False          # True: draw the logged sinusoidal border flicker (aliases at 60 fps)
LAYOUT_SEED = 1             # RNG seed for the re-drawn leaf start positions
# ================================================================================


def title_card(r: lr.LeafRenderer, date, participant, block):
    T, g, geo = r.T, lr.GAME, r.geo
    lines = [
        f"Leaf game  |  {date}  |  participant {participant}  |  block {block}",
        f"{len(T)} trials, {int((T.NfSuccess == 1).sum())} NF reveals, accuracy {100 * T.Accuracy.mean():.0f}%, "
        f"{int(T.TotalPoints.iloc[-1])} points",
        "",
        "Rebuilt from the game logs, not a screen recording.",
        "From the logs: trial timing, cue, directions, NF fill level, reveal, response, feedback, HUD.",
        "Assumed (not logged): leaf start positions (re-drawn with the game's layout code),",
        f"screen {lr.SCREEN_W}x{lr.SCREEN_H} with full safe area, red cue flash {g['pre_flash_hz']:g} Hz.",
    ]
    if not r.draw_ssvep:
        lines.append("SSVEP border flicker not drawn: borders shown at the mean grey.")
    F = np.empty((geo.out_h, geo.out_w, 3), np.float32)
    F[:] = np.array([7, 34, 50], np.float32) / 255
    lr.draw_text(F, lr.text_image("\n".join(lines), round(34 * geo.u) * geo.k), geo.out_w / 2, geo.out_h / 2)
    return np.clip(F, 0, 1)


def render(job):
    day_dir, out_dir, participant, block, stem, max_sec = job
    geo = lr.screen_geometry(OUT_SCALE)
    r = lr.LeafRenderer(day_dir / "gameData", stem, lr.Assets(geo), LAYOUT_SEED, DRAW_SSVEP)
    t_end = min(r.t_end, r.t_start + max_sec)
    times = r.t_start + np.arange(int((t_end - r.t_start) * OUT_FPS) + 1) / OUT_FPS
    out = out_dir / f"{day_dir.name}_leaf_p{participant}_b{block}_gameplay.mp4"
    cmd = [shutil.which("ffmpeg"), "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
           "-s", f"{geo.out_w}x{geo.out_h}", "-r", str(OUT_FPS), "-i", "-", "-c:v", "libx264", "-preset", "medium",
           "-crf", str(CRF), "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(out)]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    t0 = time.time()
    card = lr.to_uint8(title_card(r, day_dir.name, participant, block)).tobytes()
    for _ in range(round(TITLE_CARD_SEC * OUT_FPS)):
        proc.stdin.write(card)
    for i, t in enumerate(times):
        proc.stdin.write(lr.to_uint8(r.frame(t)).tobytes())
        if (i + 1) % 3600 == 0:
            print(f"  {stem}: {i + 1}/{len(times)} frames ({time.time() - t0:.0f} s)", flush=True)
    proc.stdin.close()
    if proc.wait() != 0:
        raise RuntimeError(f"ffmpeg failed for {out}")
    return f"{out.name}: {len(times)} frames ({len(times) / OUT_FPS:.0f} s of gameplay) in {time.time() - t0:.0f} s"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--day", default=DAY)
    ap.add_argument("--blocks", nargs="*", type=int, help="block numbers (default: all Leaf blocks of the day)")
    ap.add_argument("--max-sec", type=float, default=float("inf"), help="render at most this much gameplay")
    ap.add_argument("--jobs", type=int, default=5, help="blocks rendered in parallel")
    a = ap.parse_args()
    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg not found on PATH")
    day_dir = lr.PROJECT_ROOT / "data" / a.day
    out_dir = lr.PROJECT_ROOT / "video"
    out_dir.mkdir(exist_ok=True)
    blocks = [b for b in lr.find_blocks(day_dir) if not a.blocks or int(b[1]) in a.blocks]
    geo = lr.screen_geometry(OUT_SCALE)
    print(f"Screen {lr.SCREEN_W}x{lr.SCREEN_H}, activePixelScale {geo.s:.4f}, field {geo.field} (gcd {geo.gcd}); "
          f"blocks: {[b[1] for b in blocks]}", flush=True)
    jobs = [(day_dir, out_dir, p, b, stem, a.max_sec) for p, b, stem in blocks]
    with ProcessPoolExecutor(max_workers=max(1, min(a.jobs, len(jobs)))) as ex:
        for msg in ex.map(render, jobs):
            print(msg, flush=True)


if __name__ == "__main__":
    main()

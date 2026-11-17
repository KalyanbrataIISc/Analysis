"""Explanatory figures of the Leaf game, drawn from frames rebuilt by leaf_render.py.

    python referenceScript/leaf_trial_diagrams.py

Writes to referenceScript/results/:
    <date>_leaf_trial_structure.png   one trial in time: frames at key moments, phases, what each
                                      element shows, markers and the logged NF level
    <date>_leaf_game_components.png   one screen with every component labelled, leaf anatomy and
                                      leaf states through a trial
Dark theme, to match the game.
"""
from __future__ import annotations

import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
from matplotlib.patches import ConnectionPatch, Polygon, Rectangle  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
import leaf_render as lr  # noqa: E402

# =================================== SETTINGS ===================================
DAY, STEM, TRIAL = "2026-11-16", "p2_b2_leaves", 2     # NF reveal + correct response
STILL_TIMES = [22.5, 24.94, 25.07, 26.5, 28.9, 31.3, 32.5, 33.9, 36.0]   # game time (s) of the frames
STILL_CAPTIONS = ["ITI: field empty", "Pre-SSVEP: cued group\nflashes red", "Pre-SSVEP: flash off",
                  "SSVEP on: fill = NF level", "Fill brightens with NF", "NF ≥ 0.9: green,\nhold 1 s",
                  "Reveal: true colours", "Feedback 1 s", "ITI 5 s"]
NF_GAIN_PER_S = 1.0         # NfRatePerUnitPerSec on this day (checked from the trace; code default 3)
OUT_DIR = Path(__file__).resolve().parent / "results"
# ================================================================================

BG, PANEL, FG, MUTED, GRID = "#0b1a24", "#13293a", "#e8eef2", "#9fb3c0", "#2a4356"
C1, C2, GREEN, RED = "#00bfff", "#ff8c00", "#b3ffb3", "#ff3030"
plt.rcParams.update({"figure.facecolor": BG, "axes.facecolor": PANEL, "savefig.facecolor": BG,
                     "text.color": FG, "axes.labelcolor": FG, "xtick.color": MUTED, "ytick.color": MUTED,
                     "axes.edgecolor": GRID, "font.family": "Arial", "font.size": 11})


def trial_structure(r: lr.LeafRenderer, out: Path):
    T = r.T
    row, prev, nxt = (T[T.TrialNumber == TRIAL + d].iloc[0] for d in (0, -1, 1))
    t0 = row.TrialStart
    ev = dict(iti=prev.TrialEnd - t0, cue=row.CueOnsetTime - t0, green=row.FirstGreenTime - t0,
              reveal=row.ColorOnsetTime - t0, resp=row.ColorOnsetTime + row.ReactionTime - t0,
              stop=row.TrialEnd - t0, next=nxt.CueOnsetTime - t0)
    fig = plt.figure(figsize=(24, 13.5), dpi=100)
    fig.suptitle(f"Leaf game: one trial  ({DAY}, block {STEM.split('_')[1][1:]}, trial {TRIAL})", fontsize=20,
                 fontweight="bold", y=0.985)
    p1, m1, p2, m2 = row.C1PointDir, row.C1MoveDir, row.C2PointDir, row.C2MoveDir
    fig.text(0.5, 0.945, f"Cue: {'C1 (blue, POINTING rule)' if row.Cue == 'c1' else 'C2 (orange, MOVING rule)'}   |   "
             f"C1 points {p1}, moves {m1}   |   C2 points {p2}, moves {m2}   |   correct answer: {row.CorrectResponse}"
             f"   |   C1 {row.FrequencyC1Hz:g} Hz, C2 {row.FrequencyC2Hz:g} Hz (marker {row.TrialStartMarker})",
             ha="center", fontsize=13, color=MUTED)
    xl = (ev["iti"] - 0.3, ev["next"] + 0.3)

    # frames
    n = len(STILL_TIMES)
    w, gap = 0.102, (0.97 - len(STILL_TIMES) * 0.102) / (len(STILL_TIMES) - 1)
    h = w * 24 / 13.5 * r.geo.out_h / r.geo.out_w
    thumbs = []
    for i, (t, cap) in enumerate(zip(STILL_TIMES, STILL_CAPTIONS)):
        ax = fig.add_axes([0.015 + i * (w + gap), 0.725, w, h])
        ax.imshow(lr.to_uint8(r.frame(t)))
        ax.set_xticks([]); ax.set_yticks([])
        for s in ax.spines.values():
            s.set_edgecolor(GRID)
        ax.set_title(f"{cap}\nt = {t - t0:+.2f} s", fontsize=11, color=FG, pad=4)
        thumbs.append(ax)

    # lanes
    axT = fig.add_axes([0.075, 0.30, 0.91, 0.33])
    axT.set_xlim(xl); axT.set_ylim(6, 0)
    axT.set_yticks(np.arange(6) + 0.5, ["Phase", "Leaf borders", "Leaf fills", "Double cue", "HUD", "Markers"], fontsize=12)
    axT.tick_params(axis="x", labelbottom=False, length=0); axT.tick_params(axis="y", length=0)

    def box(y, a, b, c, txt="", tc=FG, fs=11):
        axT.add_patch(Rectangle((a, y + 0.12), b - a, 0.76, fc=c, ec=PANEL, lw=1.5))
        if txt:
            axT.text((a + b) / 2, y + 0.5, txt, ha="center", va="center", fontsize=fs, color=tc)

    box(0, ev["iti"], ev["cue"], "#33475a", f"ITI  {ev['cue'] - ev['iti']:.1f} s")
    box(0, ev["cue"], 0, "#8c2f39", f"Pre-SSVEP\n{-ev['cue']:.1f} s")
    box(0, 0, ev["reveal"], "#2f5d8c", f"SSVEP + NF   {ev['reveal']:.2f} s   (≤ 15 s, else timeout reveal)")
    box(0, ev["reveal"], ev["resp"], "#8a6a1f", f"Response\n{ev['resp'] - ev['reveal']:.2f} s (≤ 4 s)")
    box(0, ev["resp"], ev["stop"], "#2f6b3a", f"Feedback\n{ev['stop'] - ev['resp']:.1f} s")
    box(0, ev["stop"], ev["next"], "#33475a", f"ITI  {ev['next'] - ev['stop']:.1f} s")
    # borders: grey + 4 red flashes, then SSVEP flicker until the response
    box(1, ev["cue"], 0, "#808080")
    for k in range(4):
        axT.add_patch(Rectangle((ev["cue"] + k * 0.25, 1.12), 0.125, 0.76, fc=RED, ec="none"))
    axT.text(ev["cue"] - 0.15, 1.5, "grey 0.5 + red 4 Hz\n(cued group only)", ha="right", va="center", fontsize=11)
    xs = np.linspace(0, ev["resp"], 2000)
    axT.add_patch(Rectangle((0, 1.12), ev["resp"], 0.76, fc="#1d3446", ec="none"))
    axT.plot(xs, 1.5 - 0.3 * np.sin(2 * np.pi * row.FrequencyC1Hz * xs), color="#9a9a9a", lw=0.6)
    axT.text(ev["reveal"] / 2, 1.5, f" SSVEP grey flicker: C1 {row.FrequencyC1Hz:g} Hz, C2 {row.FrequencyC2Hz:g} Hz (not drawn in the videos) ",
             ha="center", va="center", fontsize=11, bbox=dict(fc=PANEL, ec="none", pad=1))
    # fills from the logged NF trace
    nf = r.trials[TRIAL - 1]
    box(2, ev["cue"], 0, "#000000", "black")
    fe = nf.frame_end - t0
    for kf in range(0, nf.reveal - 1, 6):
        c = GREEN if nf.green[kf] else str(min(1.0, nf.level[kf]))
        a, b = fe[kf], fe[min(kf + 6, nf.reveal - 1)]
        axT.add_patch(Rectangle((a, 2.12), b - a, 0.76, fc=c, ec="none"))
    axT.text(1.0, 2.5, "grey = NF level", ha="center", va="center", fontsize=11)
    axT.text((ev["green"] + ev["reveal"]) / 2, 2.5, "green", ha="center", va="center", fontsize=11, color="k")
    half = (ev["resp"] - ev["reveal"]) / 2
    axT.add_patch(Rectangle((ev["reveal"], 2.12), half, 0.76, fc=C1, ec="none"))
    axT.add_patch(Rectangle((ev["reveal"] + half, 2.12), half, 0.76, fc=C2, ec="none"))
    axT.text(ev["resp"] + 0.12, 2.5, f"leaves removed;\n\"{nf.feedback.splitlines()[0]}  {nf.feedback.splitlines()[1]}\"",
             va="center", fontsize=11)
    box(3, ev["cue"], ev["stop"], "#5a4a2a", "Moving | Pointing box (colour → rule; not the target), cue onset to end of feedback")
    box(4, ev["iti"], ev["next"], "#24384a", "TIME (s since session start), SCORE (added at trial end), REACHED COLOR (+1 at NF reveal), Exit to menu")
    for x, lab in ((0, f"{row.TrialStartMarker} trialstart"), (ev["reveal"], "50 success (NF reveal)"),
                   (ev["resp"], "40 response"), (ev["stop"], "30 trialstop")):
        axT.axvline(x, color=FG, lw=1, alpha=0.45)
        axT.text(x + 0.06, 5.5, lab, va="center", fontsize=11, fontweight="bold",
                 bbox=dict(fc=PANEL, ec="none", pad=1))
    axT.axvline(ev["cue"], color=MUTED, lw=1, ls=":")
    axT.axvline(ev["green"], color=GREEN, lw=1, ls=":")

    # NF trace
    axN = fig.add_axes([0.075, 0.075, 0.91, 0.2], sharex=axT)
    tn = r.T  # noqa: F841
    import pandas as pd
    N = pd.read_csv(lr.PROJECT_ROOT / "data" / DAY / "gameData" / f"{STEM}_nftrace.csv")
    N = N[N.TrialNumber == TRIAL]
    tt = N.SampleTime - t0
    axN.axvspan(ev["green"], ev["reveal"], color=GREEN, alpha=0.25, lw=0)
    axN.axhline(0, color=GRID, lw=1)
    axN.axhline(0.9, color=GREEN, lw=1.2, ls="--")
    axN.text(xl[1] - 0.1, 0.93, "green threshold 0.9", ha="right", va="bottom", color=GREEN, fontsize=11)
    axN.plot(tt, N.NFValueClipped, color="#8aa0ae", lw=1.2, label="NF input (clipped to ±1)")
    axN.plot(tt, N.NFLevel, color=C1, lw=2.4, label=f"NF level = fill grey  (+ input × {NF_GAIN_PER_S:g}/s each frame, clamped 0-1)")
    axN.text((ev["green"] + ev["reveal"]) / 2, 0.45, f"green from {ev['green']:.2f} s\n1 s hold → reveal",
             ha="center", fontsize=11)
    for x in (0, ev["reveal"], ev["resp"], ev["stop"]):
        axN.axvline(x, color=FG, lw=1, alpha=0.3)
    axN.set_ylim(-0.3, 1.08); axN.set_ylabel("NF")
    axN.set_xlabel("Time relative to SSVEP onset / trialstart marker (s)", fontsize=12)
    axN.legend(loc="upper left", frameon=False, fontsize=11)
    axN.grid(axis="x", color=GRID, lw=0.5)

    for ax, t in zip(thumbs, STILL_TIMES):
        fig.add_artist(ConnectionPatch(xyA=(0.5, 0), coordsA=ax.transAxes, xyB=(t - t0, 0), coordsB=axT.transData,
                                       color=MUTED, lw=1, ls=":"))
        axT.plot(t - t0, 0.04, "o", color=FG, ms=6, clip_on=False, zorder=5)
    fig.text(0.5, 0.008, "Frames rebuilt from the game logs; leaf start positions re-drawn (not logged); "
             "the SSVEP flicker appears only in the border row of this diagram.", ha="center", fontsize=10, color=MUTED)
    fig.savefig(out, dpi=100)
    plt.close(fig)


def leaf_patch(ax, pointing, x, y, border, fill, scale=1.0):
    Po = lr.leaf_shape(pointing, 210 * scale, 123 * scale)
    Pi = lr.leaf_shape(pointing, 150 * scale, 63 * scale)
    ax.add_patch(Polygon(Po + [x, y], closed=True, fc=border, ec="none"))
    ax.add_patch(Polygon(Pi + [x, y], closed=True, fc=fill, ec="none"))


def components(r: lr.LeafRenderer, out: Path, t=32.5):
    k = r.geo.k
    fig = plt.figure(figsize=(24, 10.8), dpi=100)
    ax = fig.add_axes([0.005, 0.02, 0.64, 0.92])
    ax.imshow(lr.to_uint8(r.frame(t)))
    ax.set_xlim(-10, r.geo.out_w + 10); ax.set_ylim(r.geo.out_h + 10, -10); ax.axis("off")
    ax.set_title("Screen (rebuilt frame, 3200 × 2136 tablet shown at half size), just after the reveal",
                 fontsize=15, color=FG)
    fx, fy, fw, fh = r.geo.field
    ax.add_patch(Rectangle((fx * k, fy * k), fw * k, fh * k, fill=False, ec="#ffe14d", ls="--", lw=2))
    # pick a C1 and a C2 leaf near the middle to point at
    _, tr, _, adv = r.phase(t)
    pos, flock = r.leaf_positions(tr, adv)
    mid = np.array([r.geo.out_w * 0.5, r.geo.out_h * 0.55]) / k
    leaf = {}
    for f in (0, 1):
        idx = np.nonzero(flock == f)[0]
        leaf[f] = pos[idx[np.argmin(np.linalg.norm(pos[idx] - mid, axis=1))]] * k
    style = dict(fontsize=12, color="#111", bbox=dict(boxstyle="round,pad=0.35", fc="#fff6c2", ec="#111"),
                 arrowprops=dict(arrowstyle="-|>", color="#ffe14d", lw=2, shrinkA=0, shrinkB=2))
    A = r.A

    def call(xy, txt, xytext, ha="center"):
        ax.annotate(txt, xy=xy, xytext=xytext, ha=ha, va="center", **style)

    call((185, 40), "Exit to menu (two taps)", (360, 40))
    call((A.hud_value_x[0] - 60, 55), "TIME: s since session start", (640, 55))
    call((A.hud_value_x[1], 80), "SCORE: total points\n(100 = NF reveal + correct,\n10 = timeout + correct)", (1000, 230))
    call((A.hud_value_x[2], 80), "REACHED COLOR:\nNF-earned reveals", (1420, 230))
    call(tuple(leaf[0]), "C1 group (8 leaves), blue after reveal\nrule: POINTING", (leaf[0][0] - 330, leaf[0][1] - 90), "center")
    call(tuple(leaf[1]), "C2 group (8 leaves), orange after reveal\nrule: MOVING", (leaf[1][0] + 260, leaf[1][1] + 110), "center")
    call((A.cue_c0 + 4, A.cue_cy), "Double cue: colour → rule\n(not the target)", (250, A.cue_cy))
    call((r.geo.out_w - 4, (fy + fh) * k - 30), "Leaf field 3200 × 1600 px\n(leaves wrap at its edges)", (1380, (fy + fh) * k - 110), "center")

    # one leaf
    axL = fig.add_axes([0.66, 0.50, 0.33, 0.42]); axL.set_facecolor(BG); axL.set_aspect("equal"); axL.axis("off")
    axL.set_title("One leaf", fontsize=15, color=FG)
    leaf_patch(axL, 3, 0, 0, "#808080", C1)
    axL.annotate("", xy=(0, -160), xytext=(0, -95), arrowprops=dict(arrowstyle="-|>", color=FG, lw=2.5))
    axL.text(20, -140, "moving direction (here: up)", fontsize=12, va="center")
    lab = dict(fontsize=12, arrowprops=dict(arrowstyle="-", color=MUTED, lw=1))
    axL.annotate("tip = pointing direction\n(here: right)", xy=(105, 0), xytext=(160, -45), va="center", **lab)
    axL.annotate("stem", xy=(-100, 0), xytext=(-190, 50), ha="right", va="center", **lab)
    axL.annotate("border (outer ring): grey; red during the\ncue flash; SSVEP flicker during the trial",
                 xy=(35, 52), xytext=(140, 130), ha="left", va="center", **lab)
    axL.annotate("fill: black → NF grey\n→ green → true colour", xy=(-25, -8), xytext=(-150, -110),
                 ha="right", va="center", **lab)
    axL.set_xlim(-420, 470); axL.set_ylim(200, -190)

    # states
    axS = fig.add_axes([0.66, 0.21, 0.33, 0.26]); axS.set_facecolor(BG); axS.set_aspect("equal"); axS.axis("off")
    axS.set_title("Leaf states through a trial", fontsize=15, color=FG)
    states = [("#ff0000", "#000000", "pre-SSVEP\ncue flash"), ("#808080", "#000000", "pre-SSVEP\nflash off"),
              ("#808080", "0.3", "NF low"), ("#808080", "0.75", "NF high"), ("#808080", GREEN, "NF ≥ 0.9\ngreen"),
              ("#808080", C1, "revealed\nC1 = Pointing"), ("#808080", C2, "revealed\nC2 = Moving")]
    for i, (b, f, lab) in enumerate(states):
        leaf_patch(axS, 0, i * 170, 0, b, f, 0.95)
        axS.text(i * 170, 130, lab, ha="center", va="top", fontsize=11)
    axS.set_xlim(-100, 6 * 170 + 100); axS.set_ylim(220, -120)

    fig.text(0.665, 0.035,
             "Task: the red flash marks the target group. Watch it while the borders flicker;\n"
             "NF (SSVEP at that group's frequency) brightens the fills. 1 s in green reveals the\n"
             "colours (else they are revealed at 15 s). Then report with an arrow key / swipe (4 s):\n"
             "blue → its POINTING direction, orange → its MOVING direction.\n"
             f"This trial: target C1 (blue), points up → correct answer: up.",
             fontsize=12, va="bottom", bbox=dict(boxstyle="round,pad=0.6", fc=PANEL, ec=GRID))
    fig.savefig(out, dpi=100)
    plt.close(fig)


def main():
    OUT_DIR.mkdir(exist_ok=True)
    geo = lr.screen_geometry(0.5)
    r = lr.LeafRenderer(lr.PROJECT_ROOT / "data" / DAY / "gameData", STEM, lr.Assets(geo))
    trial_structure(r, OUT_DIR / f"{DAY}_leaf_trial_structure.png")
    components(r, OUT_DIR / f"{DAY}_leaf_game_components.png")
    print("wrote", *sorted(p.name for p in OUT_DIR.glob(f"{DAY}_leaf_*.png")))


if __name__ == "__main__":
    main()

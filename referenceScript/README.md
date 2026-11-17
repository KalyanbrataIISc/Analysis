# referenceScript — game illustrations (Python)

Rebuilds what the participant saw from the game logs, for videos and explanatory figures. Not
data analysis (that stays in MATLAB, `scripts/`).

| File | Does |
|---|---|
| `leaf_render.py` | Leaf-game frame renderer shared by the two scripts below. Ports the game's field auto-fit, lane layout, leaf shape, double cue and HUD from `CogLab-Games/Assets/Games/Leaf/Scripts`, and drives them from `trialdata`, `ssvepframes` and `nftrace` |
| `leaf_gameplay_video.py` | One MP4 per Leaf block of a day → `video/<date>_leaf_p<P>_b<B>_gameplay.mp4` |
| `leaf_trial_diagrams.py` | `results/<date>_leaf_trial_structure.png` (one trial in time) and `results/<date>_leaf_game_components.png` (labelled screen, leaf anatomy, leaf states) |

Run from the project root (Windows: Anaconda Python; needs numpy, pandas, Pillow, matplotlib, and
ffmpeg on PATH; reads the sibling `CogLab-Games` repository for the background image):

```
C:\ProgramData\anaconda3\python.exe referenceScript\leaf_gameplay_video.py            # all Leaf blocks of DAY
C:\ProgramData\anaconda3\python.exe referenceScript\leaf_gameplay_video.py --blocks 2 --max-sec 30
C:\ProgramData\anaconda3\python.exe referenceScript\leaf_trial_diagrams.py
```

Settings sit at the top of each file (SETTINGS block).

**Exact from the logs:** pre-SSVEP and trial timing (per-frame end times, so dropped frames show as
held frames), cue and red-flash target, directions, NF fill level and green zone, reveal frame and
kind (NF / timeout), response or miss, feedback text, HUD values.

**Assumed (not logged by the game):** leaf start positions (re-drawn with the game's own layout
code from a fixed seed, so lanes, spacing, motion and wrap are the game's), screen 3200×2136 with
the full screen as safe area (the tablet), red flash rate 4 Hz (default). The SSVEP border flicker
is not drawn in the videos by default (`DRAW_SSVEP`); borders stay at the mean grey.

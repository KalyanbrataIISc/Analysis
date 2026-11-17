# SSVEP / CCA neurofeedback analysis

Analysis of EEG recorded while participants play SSVEP neurofeedback games (Leaf, Paddle, Breakout, …).
Files are named by **recording date (YYYY-MM-DD)**, so data and plots for one session sort together.

## Layout

| Folder | Contents |
|---|---|
| `scripts/leaf/` | **Current analysis.** Self-contained MATLAB scripts for one day of Leaf-game blocks |
| `matlab/` | Real-time acquisition/experiment scripts (`RT_acquisition_CCA.m`, `RT_experiment_CCA.m`); the dynamic CCA in `scripts/` follows these |
| `notebooks/` | Earlier Python analysis notebooks, one per session/question (e.g. `2026-11-04_leaf_dynamics.ipynb`) |
| `src/` | Python modules imported by the notebooks (`cca.py`, `classical_cca.py`, `emg32_cca.py`, `epoch_cca_spectra.py`, `leaf_block_timing.py`) |
| `data/<date>/` | Raw recordings (git-ignored): `eeg_*` folders from BciCore and `gameData/` logs |
| `data/ssvep_stim_frames/` | Stimulus frame-timing logs |
| `plots/<date>_<analysis>/` | Figures, per-trial tables and results written by the scripts and notebooks (committed) |
| `Documentation/Games/` | Per-game reference: paradigm, trial timing, neurofeedback, event markers, output-file columns, caveats |
| `Documentation/FingerDecoding-CodeWalkthrough/` | Code walkthrough and 8-channel validation checklist for the FingerDecoding game |
| `docs/` | Slides and diagrams |
| `Toolbox/` | Third-party MATLAB toolboxes: Chronux 2.12 (used), EEGLAB, FieldTrip, NoiseTools |

## MATLAB analysis (current)

Both scripts live in `scripts/leaf/`, take one day folder as input, and share the same loading,
block pairing, preprocessing (1–45 Hz band-pass, 50 Hz notch, common-average reference) and
dynamic CCA (1 s window, 100 ms hop, power-iteration CCA as in `matlab/RT_acquisition_CCA.m`).

To run: open the script, set `cfg.dataDir` at the top of the USER SETTINGS block to the day folder
(default `data/2026-11-16`) and run it. Every tunable setting is in that block. Paths are resolved
from the script's own location, so the working directory does not matter.

| Script | Output folder | Plots |
|---|---|---|
| `leaf_ssvep_analysis.m` | `plots/<date>_leaf_matlab/` | 1 session spectrum · 2 CCA-projected spectrum · 3 reveal-locked CCA score (target vs non-target) · 4 reveal-locked SSVEP power · 5 RT by block · 6 time-to-reveal by block |
| `leaf_rt_congruency_cca_analysis.m` | `plots/<date>_leaf_rt_congruency_matlab/` | 1 RT congruent vs incongruent (rule repetition), by rule × session half · 2 RT vs max pre-reveal CCA score difference · 3 RT vs max pre-reveal SSVEP power difference |

Each run writes PNG + FIG figures, `trials.csv` (one row per trial) and `results.mat` (`cfg` and results).

### Expected input

```
data/<date>/
  eeg_*/            one per block: *_signals.csv (ch*_uv columns + marker), *_config.txt (sampling rate)
  gameData/         p<P>_b<B>_leaves_trialdata.csv, one per Leaf block (other games' logs are ignored)
```

EEG folders are matched to game blocks by their trial-start marker sequences, so folder names and
order do not matter, and EEG folders from other games on the same day are skipped.
Leaf event codes: trial start 31–34 (20/21 legacy), colour reveal 50, response 40, stop 30.

## Sessions

| Date | Analysis | Notes |
|---|---|---|
| 2026-09-22 | notebook `raw_eeg_first_look` | First recordings, before CCA |
| 2026-10-06 | notebooks `rolling_cca`, `rolling_classical_cca`, `cca_epoch_spectra`, `emg32_cca_*` | Paddle + Leaf |
| 2026-10-14 | notebook `ssvep_stim_frame_timing` | Stimulus frame timing |
| 2026-10-30 | notebook `cca_epoch_spectra` | Paddle v2 + Leaf |
| 2026-11-02 | notebooks `open_pins`, `with_cap_*`, `shorted_noisefloor_1927` | Hardware / noise-floor checks |
| 2026-11-04 | notebooks `leaf_overview`, `leaf_dynamics`; `plots/2026-11-04_leaf_matlab` | Participant 7, Leaf, 4 blocks |
| 2026-11-11 | `leaf_ssvep_analysis.m` | Participant 1, Leaf, 2 blocks |
| 2026-11-16 | `leaf_ssvep_analysis.m`, `leaf_rt_congruency_cca_analysis.m` | Participant 2: Leaf (5 blocks), Breakout (2), Paddle-MultiDir (1) |

From 2026-11-11 on, EEG folders are named `eeg_<game>_p<P>_s<S>_<yyyymmdd_HHMMSS>`.

## Notes

- Notebooks that import from `src/` have a first cell that adds `../src` to `sys.path`; run them from `notebooks/`.
- `src/emg32_cca.py` expects the EMG32 firmware source at `EMG32/` in this folder (not currently present).
- Only Chronux is needed by the MATLAB scripts (`Toolbox/chronux_2_12/chronux_2_12/spectral_analysis`, added to the path automatically).

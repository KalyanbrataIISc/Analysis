# SSVEP / CCA neurofeedback analysis

Files are named by **recording date (YYYY-MM-DD)**, so notebooks, data and plots for one session sort together.

| Folder | Contents |
|---|---|
| `Analysis_MATLAB/` | MATLAB analysis scripts (current analysis) |
| `notebooks/` | Earlier Python analysis notebooks, one per session/question (e.g. `2026-11-04_leaf_dynamics.ipynb`) |
| `src/` | Shared Python modules imported by notebooks (`cca.py`, `classical_cca.py`, `emg32_cca.py`, `leaf_block_timing.py`, `epoch_cca_spectra.py`) |
| `scripts/` | Generators that (re)build notebooks: `build_<notebook name>.py`, plus figure helpers |
| `data/<date>/` | Raw recordings: `eeg_<timestamp>/` folders and `gameData/` logs |
| `data/ssvep_stim_frames/` | Stimulus frame-timing logs |
| `plots/<date>_<analysis>/` | Exported figures, audits and HTML reports written by the notebooks |
| `matlab/` | Real-time acquisition/experiment scripts (`RT_*.m`) |
| `docs/` | Slides and diagrams |
| `Toolbox/` | MATLAB toolboxes |
| `_archive/` | Superseded or duplicate files kept for reference (zip of 2026-11-02 data, old shims) |

## Sessions

| Date | Notebooks | Notes |
|---|---|---|
| 2026-09-22 | `raw_eeg_first_look` | First recordings, before CCA |
| 2026-10-06 | `rolling_cca`, `rolling_classical_cca`, `cca_epoch_spectra`, `emg32_cca_*` | Paddle + Leaf games |
| 2026-10-14 | `ssvep_stim_frame_timing` | Stimulus frame timing |
| 2026-10-30 | `cca_epoch_spectra` | Paddle v2 + Leaf |
| 2026-11-02 | `open_pins`, `with_cap_1831`, `with_cap_1858-1906`, `with_cap_combined`, `shorted_noisefloor_1927` | Hardware / noise-floor checks |
| 2026-11-04 | `leaf_overview`, `leaf_dynamics` | Participant 7, Leaf, 4 blocks |

## MATLAB analysis (current)
`Analysis_MATLAB/leaf_ssvep_analysis.m` does the whole Leaf-day analysis in one file: preprocessing, session spectra, dynamic CCA (1 s window, 100 ms updates, as in `RT_acquisition_CCA.m`), reveal-locked CCA score and SSVEP power (target vs non-target), and RT / time-to-reveal by block. Set `cfg.dataDir` at the top to the day's folder and run; every tunable setting is in the USER SETTINGS block. Output goes to `plots/<date>_leaf_matlab/`.

## Notes
- Notebooks that import from `src/` have a first cell that adds `../src` to `sys.path`.
- Regenerate a notebook from the project root, e.g. `python scripts/build_2026-11-04_leaf_dynamics.py --execute`.
- `src/emg32_cca.py` expects the EMG32 firmware source at `EMG32/` in this folder (not currently present).
- `_reorganisation_log.csv` maps every old path to its new one (2026-11-10 reorganisation).

# CLAUDE.md

SSVEP / CCA neurofeedback EEG analysis. See `README.md` for the folder layout and session list.

## Where the work happens

- **Current analysis is MATLAB, in `scripts/leaf/`.** Python notebooks in `notebooks/` (+ `src/`) are earlier work; don't extend them unless asked.
- `matlab/RT_acquisition_CCA.m` / `RT_experiment_CCA.m` are the real-time scripts the game runs with. The offline dynamic CCA must stay faithful to them (window, hop, power-iteration CCA, preprocessing).
- `Documentation/Games/<Game>.md` is the reference for each game's markers, timing and log columns. Check it before interpreting codes or CSV columns (Leaf: start 31–34 / legacy 20–21, reveal 50, response 40, stop 30; cue C1 = Pointing, C2 = Moving).

## Script conventions (`scripts/leaf/*.m`)

- Each script is **self-contained**: one top-level script followed by local functions. There is no shared helper file, so `load_game_runs`, `read_signals`, `marker_events`, `segment_trials`, `match_game_run`, `preprocess`, `dynamic_cca`, `mask_updates`, `save_fig`, `list_dir`, … are duplicated. **When changing one of these, make the same change in both scripts.**
- All tunables live in the `USER SETTINGS` block as `cfg.*` fields, with a short comment each. Add new options there, not as literals in the body.
- Paths are built from the script location (`projectRoot = fileparts(fileparts(here))`); never hard-code absolute paths. Output goes to `plots/<date>_<analysis>_matlab/`.
- Use `list_dir` instead of `dir` for file listings: it drops macOS `._*` / `.DS_Store` files (files copied from a Mac carry these) and sorts by name so results match across Windows/macOS/Linux.
- EEG folders are paired to game blocks by trial-start marker sequence, not by name; unpaired folders (other games) are skipped with a warning.
- Figures are numbered (`1_…`, `2_…`) and saved as PNG + FIG; each run also writes `trials.csv` and `results.mat` (v7.3).
- The only toolbox dependency is Chronux (`Toolbox/chronux_2_12/...`). Don't edit anything under `Toolbox/`.

## Data and outputs

- `data/` is git-ignored (raw recordings). Day folders are `data/YYYY-MM-DD/` with `eeg_*` folders (BciCore: `*_signals.csv`, `*_config.txt`, …) and `gameData/`. From 2026-11-11, EEG folders are `eeg_<game>_p<P>_s<S>_<timestamp>`.
- `plots/` **is** committed, including regenerated figures and `results.mat`.
- Name new analysis outputs and notebooks by recording date first (`YYYY-MM-DD_<topic>`).

## Environment

The project is worked on from both Windows and macOS; scripts must run unchanged on both (use `fullfile`, never `\` or `/` literals in paths).

- **Windows:** MATLAB R2026a is on PATH: `matlab -batch "run('scripts/leaf/leaf_ssvep_analysis.m')"` from the project root.
- **macOS (Apple Silicon):** MATLAB is *not* on PATH. Call the app binary directly, and use R2026a (R2023a is also installed; don't pick it up by accident):
  `/Applications/MATLAB_R2026a.app/bin/matlab -batch "run('scripts/leaf/leaf_ssvep_analysis.m')"` from the project root.
- A full day takes a while; run in the background, and say when a change was not executed.
- macOS litters the tree with `.DS_Store` and, on copied drives, `._*` files. Never commit them (including the ones under `Toolbox/`), and keep using `list_dir` so they never reach the analysis.
- `src/__pycache__/` is currently tracked by git; ignore it.

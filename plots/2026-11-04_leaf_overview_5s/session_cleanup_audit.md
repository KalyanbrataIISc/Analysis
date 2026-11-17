# Session cleanup audit - 4 November 2026

The four official Leaf recordings match all 24 start markers in behavioral blocks:
1. eeg_20261104_162610 -> p7_b1
2. eeg_20261104_163332 -> p7_b2
3. eeg_20261104_164709 -> p7_b3
4. eeg_20261104_165657 -> p7_b4

Extras inspected before user removal:
- eeg_20261104_161939: 93,957 samples, 375.828 s; 24 trials. Marker runs: 20x12, 21x12, 39x24, 40x14, 41x12, 42x12, 30x24. Matches Paddle MultiDir defaults; game identification inferred from marker protocol, without matching behavioral log.
- eeg_20261104_164051: 72,215 samples, 288.860 s; no nonzero signal or feature markers and no matching behavioral block. Non-task EEG, not empty EEG.

Neither extra was empty. The user deleted them before notebook creation. This notebook never deletes or changes recordings. Header-only raw CSVs are normal PROC ONLY placeholders and are retained.

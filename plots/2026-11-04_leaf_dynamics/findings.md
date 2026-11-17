# Leaf Game findings - 4 November 2026

Four blocks pooled; 96 trials; 72 reveals and 24 administrative timeouts.
- C1: RMST15=9.10 s; first-green-to-reveal median=0.99 s among reveals; 7 trials reached green but timed out.
- C2: RMST15=8.83 s; first-green-to-reveal median=0.99 s among reveals; 5 trials reached green but timed out.

Key interpretation:
- Early task-minus-ITI change favors 17 Hz independent of attendance: physical frequency asymmetry 0.0238, exploratory 95% interval [0.0066, 0.0418]. Instruction-following contrast -0.0042 [-0.0389, 0.0323] remains uncertain.
- Optimized target peaks largely disappear on the next non-overlapping second. Treat these fitted peaks as descriptive, not independent validation of a stable response.
- Reveal-aligned score increases contain both attended enhancement and distractor suppression. The stopping rule selects these trials, so this does not independently establish learning.
- Of 24 timeouts, 12 never reached green and 12 reached green without a reveal before the deadline.
- Recorded border modulation matches logged 17/19 Hz on scheduled phase time (median regression R squared approximately 1); frame-end software timing gives median R squared approximately 0.99. No physical photodiode measurement is available.

Exploratory balanced contrasts:
- wait15_s, C2 minus C1: -0.267 [95% trial-bootstrap interval -1.903, 1.343], n=96
- wait15_s, attend19 minus attend17: 1.320 [95% trial-bootstrap interval -0.251, 2.955], n=96
- early_score_diff, C2 minus C1: 0.012 [95% trial-bootstrap interval -0.012, 0.036], n=96
- early_power_db, C2 minus C1: 0.029 [95% trial-bootstrap interval -1.126, 1.191], n=96
- early_power_db_previous, C2 minus C1: 0.409 [95% trial-bootstrap interval -1.401, 2.115], n=96
- early_score_diff, attend19 minus attend17: -0.037 [95% trial-bootstrap interval -0.061, -0.014], n=96
- pre_minus_earlier_power_db, balanced paired change: 2.261 [95% trial-bootstrap interval 1.279, 3.314], n=56
- pre_minus_earlier_power_db_previous, balanced paired change: 1.505 [95% trial-bootstrap interval 0.018, 2.961], n=56
- pre_minus_earlier_score_diff, balanced paired change: 0.056 [95% trial-bootstrap interval 0.041, 0.071], n=56
- pre_minus_earlier_score_att, balanced paired change: 0.034 [95% trial-bootstrap interval 0.020, 0.050], n=56
- pre_minus_earlier_score_dist, balanced paired change: -0.022 [95% trial-bootstrap interval -0.035, -0.008], n=56

Trial-level early measure vs restricted waiting time (within-cell centered):
- early_power_db: descriptive Spearman r=-0.101.
- early_power_db_previous: descriptive Spearman r=-0.044.
- early_score_diff: descriptive Spearman r=-0.241.

Instruction versus physical frequency decomposition:
- early_score_diff, instruction contrast in physical 17-minus-19 coordinates: -0.0123 [-0.0365, 0.0150].
- early_score_diff, physical 17-minus-19 frequency asymmetry: 0.0183 [0.0063, 0.0307].
- early_minus_baseline_score_diff, instruction contrast in physical 17-minus-19 coordinates: -0.0042 [-0.0389, 0.0323].
- early_minus_baseline_score_diff, physical 17-minus-19 frequency asymmetry: 0.0238 [0.0066, 0.0418].
- early_power_db, instruction contrast in physical 17-minus-19 coordinates: 0.3123 [-0.8342, 1.4419].
- early_power_db, physical 17-minus-19 frequency asymmetry: 0.5866 [0.0407, 1.1653].
- early_minus_baseline_power_db, instruction contrast in physical 17-minus-19 coordinates: 0.3650 [-1.5799, 2.2162].
- early_minus_baseline_power_db, physical 17-minus-19 frequency asymmetry: 1.3106 [0.3716, 2.2480].

Projection peak prominence, mean over trial spectra:
- preceding_window, U17: 0.29 dB relative to local non-target bins.
- preceding_window, U19: 0.23 dB relative to local non-target bins.
- same_window, U17: 6.23 dB relative to local non-target bins.
- same_window, U19: 5.84 dB relative to local non-target bins.

Pre-reveal growth is partly selected by the integration-and-hold rule, not independent evidence of learning. Intervals crossing zero leave effects uncertain. Preceding-window evaluation, fixed-cohort results and block plots are sensitivity checks, not confirmatory replications.
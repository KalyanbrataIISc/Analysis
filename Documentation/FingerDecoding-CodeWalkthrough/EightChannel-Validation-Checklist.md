# Testing an eight-channel EEG finger-decoding board

Reference: Ding et al., *EEG-based brain-computer interface enables real-time robotic hand control at individual finger level*, Nature Communications 16:5401 (2025), DOI https://doi.org/10.1038/s41467-025-61064-x. Supplied PDF: `/Users/swikriti/Downloads/s41467-025-61064-x.pdf`.

This is a proposed validation plan, not completed results. Paper-supported methods are marked P; board-specific engineering/adaptation tests are marked B. No code, model or firmware was changed.

## Scope and interpretation

The paper acquired 128-channel Biosemi EEG at 1024 Hz, used CAR, downsampling to 100 Hz, fourth-order 4–40 Hz Butterworth filtering and z-scored 1-second windows, with 125 ms control updates (Methods, p.16). Offline trials were 5 seconds with 2-second ITI; online trials were 3 seconds with feedback in seconds 1–3 and 2-second ITI (pp.14–15). ME/MI models were trained separately. Its metrics include trial-majority accuracy and per-class precision/recall.

EEGNet-8,2 means the architecture's F1=8 and D=2, not eight recording channels; input channel count is a separate parameter in the original EEGNet implementation: https://raw.githubusercontent.com/vlawhern/arl-eegmodels/master/EEGModels.py . The board's generated model currently has 8 inputs, 250 samples, F1=16, D=2, F2=64 and two classes. Its OWN filter uses 1–40 Hz at 250 Hz; its default hop is 100 ms. This is an adaptation, not exact replication of the paper. The paper examines reduced/channel-region inputs but does not validate this exact eight-electrode board/montage/model.

Distinguish three claims:

1. Hardware acquires and transmits eight usable EEG channels.
2. The deployed board runs its trained model correctly and in real time.
3. The system decodes the participant's cued finger above chance from EEG on unseen data.

The first two do not establish the third.

## Mandatory tests and evidence

### 1. Electrode identity and eight-input mapping (P+B)

Document the eight scalp electrode names/10–20 locations, reference/ground, physical board channels and their exact trained-model row order. Firmware selects physical channels 9–16 (zero-based 8–15), which are not automatically sensorimotor electrodes. Confirm the montage covers the intended motor regions; the paper's regional analyses support sensorimotor contribution (Results pp.4 and supplementary analyses discussed p.17). Verify all eight channels are genuine, active inputs with no copies, zeros or silent substitutions. Perturb/test each input on a bench fixture and confirm its software/model row responds. Output: mapping table and channel-level traces.

### 2. Acquisition quality and stability (B)

Use shorted-input noise measurements and known-signal bench tests to check gain/scaling, sample rate, channel order, clipping/rails, line interference, noise and crosstalk. Measure live dropout/flatline rates and hardware health. Report sampling-rate drift, raw sequence gaps, ring drops, bad SPI frames and changes in missed-DRDY counts. Zero network sequence gaps alone does not establish zero acquisition failures. Set application-specific acceptance thresholds before testing; the paper provides no universal electrical acceptance thresholds for this board.

### 3. Confirm actual inference is running (B)

Archive the flashed firmware role/version, model hash and training provenance. Verify EEGNET_ENABLED and appropriate stage/rate rather than assuming the presence of weights or an active Wi-Fi connection proves inference. Capture genuine ML frames with changing newest-sample sequence, class, confidence and measured forward latency. Simulation must be excluded. The checked-out source is ROLE_CUSTOM/Stage6 with EEGNet disabled by default; the flashed firmware must be independently identified. Output: boot/build metadata and continuous ML log synchronized with raw samples.

### 4. Training–deployment preprocessing agreement (P+B)

Match channels, order, reference, units, sampling rate, window length, filter type/order/cutoffs, causal state, normalization, padding and class labels. Decide whether to replicate the paper's 100 Hz/4–40 Hz pipeline or retain/retrain for the board's 250 Hz/1–40 Hz OWN pipeline. Do not feed a model a different transform because both outputs are called EEG. Compare intermediate PC and board preprocessing values for identical replay data; include startup/warm-up, gaps and reconnects. Output: preprocessing specification plus numerical comparison.

### 5. Numerical model parity (B)

For the same eight-channel preprocessed windows, compare original checkpoint/evaluation-mode logits and probabilities with exported/folded/fused PC implementation and board results. Test many held-out real windows, not only zeros/synthetic signals; compare intermediate layers if needed. Report max/mean error, prediction agreement and near-tie cases. Define floating-point tolerances before acceptance based on the engine's approximation and class margins. Confirm batchnorm folding, tensor layout, padding, pooling and dense flatten order. Output: parity report and model/export hashes. Matching labels alone is weaker evidence than matching logits/probabilities.

### 6. Timing and sustained throughput (P+B)

Measure raw sample sequence and marker onsets: 10, separate first cue, one finger marker per trial, 60 for every trial including last, then separate 11. No flash/prediction triggers. Measure offline 5-second trials and online 3-second trials with 2-second ITI. Confirm 300 ms boundary guards actually preserve markers. The paper uses 125 ms outputs; the board/game uses 100 ms—report that difference or configure a deliberate matched protocol. Measure forward latency separately from queue wait, wireless transport, Unity receipt and display latency; report median/p95/max, jitter, dropped inference windows and results under sustained load. For a 100 ms hop, the complete pipeline must keep up without backlog; a fast single forward pass is insufficient. Use photodiode/independent equipment for claims about physical display onset. Output: per-trial timing, end-to-end latency distribution and stress-test logs.

### 7. Cue/window alignment and session state (P+B)

Relate each prediction's source sample sequence to cue onset. The online design starts feedback after 1 second; verify eligible one-second windows for the intended protocol rather than gating by packet arrival alone. Board inference is currently free-running and its windows/filters do not reset with Unity trials. Verify suppression of stale predictions, no previous-trial carryover, no feedback during ITI, and correct behaviour on abort/reconnect. Filter state can legitimately continue; specify the chosen policy. Output: predictions with window-end sequence, cue/start/end sample indices and trial ID.

### 8. Held-out eight-channel offline decoding (P+B)

Use balanced randomized Thumb/Pinky trials for the present binary model; test other class sets only with a corresponding trained model. Analyze ME and MI separately. Train/fine-tune with the exact deployed eight inputs, not an unchanged 128-channel checkpoint. Use trial/run/session-grouped train/validation/test splits; all overlapping windows from one trial belong in the same split. Never tune on final test data. Prefer separate-session testing for session transfer and model claims. Paper reports five-fold CV, but window leakage prevention is an explicit proposed requirement here. Output: held-out trial confusion matrix, accuracy, balanced accuracy, per-class precision/recall/F1, confidence interval and counts.

### 9. Genuine prospective online decoding (P+B)

Lock the model before a new test run. Use live EEG, randomized cues and actual decoded output; exclude simulation. Record every eligible prediction and compute the paper-style final trial class from majority vote within a predefined feedback interval, with tie/missing-data policy specified in advance. Report both unsmoothed and displayed/smoothed outcomes, failure rate and per-run/per-subject variability. Do not treat correlated 100 ms updates as independent trials for significance. Binary balanced chance is 50%; ternary balanced chance is 33.3%. Use a predeclared trial-level permutation/binomial analysis as appropriate and report confidence intervals; account for block/session dependence. Choose sample size for the intended effect and interval precision, not merely to obtain a nominal p-value. Output: locked-model prospective trial results.

### 10. Eight-channel ablation and comparison (P+B)

Train and evaluate the selected eight-channel layout on identical held-out trials against larger available layouts (e.g. 16/32/128 where available), other eight-channel layouts and reduced subsets. Keep selection/model tuning inside training folds. Compare with a suitable classical baseline such as CSP/FBCSP-LDA. The paper found strong sensorimotor contributions and reduced contralateral-hand-knob input could perform worse than whole-scalp input; channel placement matters, not just count. Output: paired held-out performance and uncertainty. This establishes whether eight channels are adequate for the specified task/participant rather than merely supported by the software shape.

### 11. Artifact, cue-leakage and negative controls (B)

ME can include muscle/movement contamination; MI should have no intended movement. Record EMG or another independent movement measure if possible, plus eye/jaw/head-motion checks. Test passive viewing of the same visual cues without ME/MI to examine cue-evoked confounding; examine whether accuracy depends on obvious artifacts. Include shuffled-label/permutation and no-informative-input controls. A forced-choice binary model still outputs a class on noise, shorted electrodes or rest—do not expect an absence of predictions. The correct negative-control question is whether output systematically follows true instructions above chance when informative motor EEG is absent. Output: control-condition performance, artifact analysis and movement monitoring.

### 12. Physiological corroboration (P+B)

Inspect trial-aligned alpha (8–13 Hz) and beta (13–30 Hz) power changes/ERD over the chosen sensorimotor electrodes, with a prespecified reference/baseline and separately for ME/MI. The paper's physiological analyses support motor-region contributions; ERD alone does not prove discrimination between individual fingers. Compare channel saliency/ablation with electrode identity where feasible. Output: ERD/time-frequency figures and channel relevance. EEG spectral presence or alpha peaks alone are not proof of finger decoding.

### 13. Fine-tuning benefit without test contamination (P+B)

The paper trained ME/MI separately and fine-tuned on same-day earlier runs while freezing early layers (Methods p.16). For an eight-channel deployment, compare base and fine-tuned models on the same untouched later/session test trials. Freeze/tune layers deliberately for your architecture; do not assume layer numbers transfer across exporters. Retain model hashes and train/test membership. Output: paired improvement and uncertainty; online adaptation data must not be counted as its own test.

### 14. Smoothing stability versus response delay (P+B)

Compare the same raw prediction stream with smoothing disabled/enabled, and optionally prospectively counterbalance feedback conditions. Record switch rate, time to follow a genuine sustained change, class recall and trial accuracy. Use all probabilities for multiclass probability smoothing; one-hot label votes are a different algorithm. Binary winning softmax reconstructs the other probability only when valid. Reset Unity history per trial. Confirm exactly one smoothing stage; raw board outputs may be smoothed in Unity, while already-smoothed MATLAB outputs should pass through. The paper's Eq.1 supplies the recursive probability framework, but our alpha=.90 is a project setting rather than a claimed paper requirement. Output: raw/smoothed comparison with lag and accuracy.

### 15. Reproducibility, recording and adverse-state behaviour (B)

Repeat on a separate day/fit and additional participants before a general claim. Save raw EEG, task plan, settings, firmware/model hashes, montage, predictions/probabilities or logits, confidence, source sequence, event timing and health. Verify complete final trial-stop/run-end markers, exports and no missing files needed for scoring. Test cable/Wi-Fi interruption, reconnect, app pause, saturation/flat inputs and low resource conditions. Do not let stale/fabricated predictions appear valid. Output: reproducible analysis package and operational test report.

## Decision rule and claim wording

Predefine engineering tolerances and statistical endpoints before final testing. There is no universal percentage in this paper that proves an eight-channel board is working. The paper's 80.56% binary MI and 60.61% ternary MI are group results from its different setup; its >70% offline threshold selected online participants, not a board electrical/deployment acceptance threshold.

A defensible limited statement is:

> The board acquired eight specified EEG channels, its deployed model matched the reference implementation within predefined numerical tolerances, sustained the configured real-time update schedule, and achieved [accuracy with confidence interval] on [number] held-out prospective trials for [ME or MI, finger set, participant/session]. Performance exceeded the predefined chance/null criterion, with artifact controls and complete marker/data logging.

Without prospective accuracy and artifact controls, say “eight-channel acquisition and on-board inference demonstrated,” not “EEG finger decoding validated.” Without board/PC parity, successful UI feedback does not establish correct model deployment. Without multi-participant testing, limit claims to tested participants/tasks.

Current project evidence confirms raw acquisition, recent no-gap recordings and approximately correct trial/ITI timing with separate run markers. Numerical model parity, prospective eight-channel decoding accuracy, input montage verification and artifact controls remain to be demonstrated.

# Finger Decoding

Reference for analysing data produced by the **Finger Decoding** game. Every statement here was checked against the source as of this commit. Where the code and the existing docs disagree, the code is treated as correct (see section 14).

Shared infrastructure (MonotonicClock, BciCore server and EEG loggers, UsbBiosemiLink, calibration screen, launcher settings) is described in [00-Shared-Infrastructure.md](00-Shared-Infrastructure.md). This document only states how Finger Decoding uses those pieces.

Deeper walkthroughs that already exist:

- `Assets/Games/FingerDecoding/README.md`: operator README. Partly stale; see section 14.
- `Documentation/FingerDecoding-CodeWalkthrough/Guide.md`: EMG32 board, EEGNet and Unity execution walkthrough. Its line references to Unity files are stale.
- `Documentation/FingerDecoding-CodeWalkthrough/EightChannel-Validation-Checklist.md`: a proposed validation plan for an 8-channel board. It is a plan, not results.

---

## 1. Overview & paradigm

**What the participant sees.** The screen is a uniform grey background (sRGB 80,80,80). A white, continuous right-hand silhouette (no wrist, thumb on the left, ring finger visible but never cued) is centred on screen. At trial onset one of the selected fingers (Thumb, Index, Middle or Pinky) is filled in **cue blue `#1738E8`**. Depending on the cue pattern, the blue fill either flashes on and off or shows once. Between trials and during run lead-in or hold periods the screen is completely blank grey, with no hand. During trials a small **Abort** button is visible in the top-right corner (`Assets/Games/FingerDecoding/Scripts/FingerCanvasView.cs:50-51`, `:150-151`).

**What the participant does.** There is no button, touch or keyboard response.

- `motorTask = ME` (motor execution): the participant moves the cued finger.
- `motorTask = MI` (motor imagery): the participant imagines moving it.

The task only changes the trigger codes and the accepted prediction-ID range (ME uses 21-24, MI uses 31-34). It does not change any visuals or instructions. **The game shows no instruction screen.**

**Modes.**

| Mode | Trial length (default) | Feedback |
|---|---|---|
| `Offline` | 5 s | None. The prediction marker never appears. Predictions are still received and logged as `prediction_received` when the source is not Simulation. |
| `Online` | 3 s | From `feedbackDelay` = max(`onlineFeedbackStart`, first cue on-period) after onset (default 1 s), a circle appears directly above the **decoded** fingertip. It is green (`#1EDC5D`) when decoded == cued and red (`#F23440`) otherwise. It updates at most every `predictionUpdateInterval` (≥0.1 s). |

**BCI purpose.** The game provides cue-locked EEG epochs for individual-finger ME/MI decoding (paradigm modelled on Ding et al. 2025, Nat. Commun. 16:5401), and in online mode it gives closed-loop feedback from an external decoder. Unity does **no** EEG preprocessing or inference. It only receives decoded finger IDs (`Assets/Games/FingerDecoding/Scripts/FingerPredictions.cs:20`).

**Success rule.** A displayed prediction is "correct" when `decoded finger == cued finger` (`FingerExperimentController.cs:331`, `FingerCsvLogger.cs:55`). The game computes no score and no trial-level accuracy. Trial-level summaries are counts of correct presented updates (`trialdata.csv`). The cue (from `plan.csv`) is the ground-truth label. A green circle only means agreement with the instruction.

---

## 2. Code map

| Item | Value | Source |
|---|---|---|
| Game ID | `finger-decoding` | `Assets/Games/FingerDecoding/Prefabs/FingerDecoding.prefab:91` |
| Display name | `Finger Decoding` | `FingerDecoding.prefab:92` |
| Launcher colour | (0.0902, 0.2196, 0.9098) = `#1738E8` | `FingerDecoding.prefab:93` |
| PlayerPrefs key | `CogLab.Games.finger-decoding.v1` | `Assets/CogLab/Framework/GameModule.cs:29` |
| Launcher module class | `CogLab.FingerDecoding.FingerGameModule` | `Scripts/FingerGameModule.cs` |
| Settings / session controller | `CogLab.FingerDecoding.FingerExperimentController` (disabled template on prefab root) | `FingerDecoding.prefab:36-78` |
| Runtime assembly | `CogLab.Games.FingerDecoding` (refs CogLab.Framework, CogLab.Shared, BciCore, Unity.ugui, Unity.TextMeshPro, Unity.InputSystem) | `CogLab.Games.FingerDecoding.asmdef` |
| Editor assembly | `CogLab.Games.FingerDecoding.Editor` (Editor only) | `Editor/CogLab.Games.FingerDecoding.Editor.asmdef` |
| Prefab | `Assets/Games/FingerDecoding/Prefabs/FingerDecoding.prefab`. It is instanced under `Games` in `Assets/CogLab/App/Scenes/CogLab.unity` with **no field overrides** (only name and transform). | `CogLab.unity:206-262` |

Files (paths relative to `Assets/Games/FingerDecoding/`):

| File | Role |
|---|---|
| `Scripts/FingerProtocol.cs` | Enums (`Finger`, `MotorTask`, `ExperimentMode`, `CuePattern`, `AcquisitionMethod`, `PredictionSource`, `ClassCount`), finger↔ID mapping, Fisher-Yates balanced run, cue-visibility function. |
| `Scripts/FingerExperimentController.cs` | All settings, session/run/trial state machine, event logging calls, abort/export. Implements `IGameSession`. |
| `Scripts/FingerCanvasView.cs` | Builds the uGUI canvas: hand, cue masks, prediction marker, Abort button, in-game researcher settings screen, run-pause screen. |
| `Scripts/FingerPredictions.cs` | Decoded-ID receiver. Handles UDP (background thread), BciCore `OnMlResult` (explicit IDs) and EMG32 class 0/1 mapping. Bounded queue of 4096 entries. |
| `Scripts/FingerFeedbackSmoother.cs` | Exponential evidence accumulator used for online display. |
| `Scripts/FingerAcquisition.cs` | Starts BciCore server or UsbBiosemi link and sends numeric markers. |
| `Scripts/FingerCsvLogger.cs` | Writes `events.csv`, `trace.csv`, `trialdata.csv` and `session.csv`. |
| `Scripts/FingerGameModule.cs` | `GameModule` subclass. Delegates validation and runs `NormalizeMarkerSettings` after saved settings load. |
| `Scripts/FingerDeviceCheck.cs` | Opt-in on-device simulation self-test. Compiled only with `DEVELOPMENT_BUILD` or in the Editor. |
| `Editor/FingerExperimentInspector.cs` | Inspector with class-preset buttons and a "Use these Finger settings in launcher" button that writes PlayerPrefs. |
| `Editor/FingerVerification.cs`, `FingerBoundaryVerification.cs`, `FingerSmoothingVerification.cs`, `FingerLoggingVerification.cs` | Editor regression checks: protocol, marker order and spacing, smoothing, logging, health echo labels, USB link. |
| `Editor/FingerLauncherIntegration.cs`, `Editor/FingerProjectSetup.cs` | Scene integration and Android build menus. Builds always use `BuildOptions.Development`. |
| `Tools/send_prediction.py`, `Tools/emg32_to_udp.py` | UDP senders for decoded IDs. |
| `Tools/check_session.py` | Sanity checker for `events.csv`. |
| `Resources/FingerDecoding/*.png`, `geometry.json` | Sprites (2000×2600 hand, border and 4 masks; 256×256 circle) and fingertip geometry. |
| `Scenes/FingerExperiment.unity`, `Scenes/FingerFeedbackDemo.unity` | Standalone scenes. The demo sets `visualDemonstration=1` and writes no logs. |

---

## 3. Session flow / state machine

`Phase` enum: `Settings, Calibration, RunLeadIn, Trial, Iti, RunEndHold, BetweenRuns, Aborting, Exporting, Complete, Failed` (`FingerExperimentController.cs:73`).

```
Launcher "Play Finger Decoding"
  GameModule.Launch: copy template JSON -> runtime controller, ConfigureSharedLaunch(participant, block, eegLoggingMode)
  Start(): landscape-only autorotate, build canvas, show in-game Settings screen         [Settings]
       |
  "Begin / next run" -> BeginExperiment(): ValidateSettings, freeze session vars, build sequences,
       |               create FingerPredictions; if source != Simulation create FingerAcquisition
       |-- BciCore:   BciServer.StartServer(...) + shared calibration screen                 [Calibration]
       |              Proceed (only if BciServer.State == Connected) -> ExitCalibrationMode -> StartSession
       |              Back -> Exit()  (export EEG, return to launcher)
       |-- UsbBiosemi: if link not connected -> status "Waiting for USB bridge"; press Begin again
       |-- Simulation: no acquisition -> StartSession immediately
  StartSession(): create task folder, session.csv keys, settings.json, plan.csv; BeginRun
  BeginRun:  marker 10 "run_start", blank                                                    [RunLeadIn]
     +markerGap (0.3 s) -> BeginTrial: cue marker 21-24 / 31-34 "cue_on", hand + blue cue   [Trial]
     +duration -> marker 60 "trial_end", "iti_onset", blank                                  [Iti]
     +ITI -> "iti_end"; next trial ... ; after last trial's ITI: marker 11 "run_end"          [RunEndHold]
     +markerGap -> more runs?  pauseBetweenRuns && runPauseDuration>0 -> "run_pause_on"       [BetweenRuns]
                                   countdown or tap -> "run_pause_end" -> BeginRun
                              no pause -> BeginRun
                   last run -> "session_complete" -> Finish(export) -> settings screen        [Complete]
```

Transitions are evaluated once per Unity frame in `Update()` → `AdvanceSession(now)` (`FingerExperimentController.cs:258-290`). `now` is `MonotonicClock.Now`, read once at the start of `Update`.

| Item | Behaviour | Source |
|---|---|---|
| Calibration (BciCore only) | Shared `BciCalibration.Open` (EEG/FFT telemetry). Proceed is silently ignored until `BciServer.State == Connected`. EEG logging is active from server start, so the EEG file includes the calibration period. | `:228-229`, `FingerAcquisition.cs:18-25` |
| "EEG / FFT checker" button | Preflight only. Starts BciServer with `EegLoggingMode.Disabled`, opens calibration, and either button returns to Settings. Writes no task files. | `:183-203` |
| Instructions | None. | — |
| Normal completion | `Complete()` logs `session_complete` (code 0), then `Finish(exit=false)`. Cleanup disposes the receiver, acquisition (stopping BciServer) and logger, then converts EEG (`ConvertCurrentSessionToCsvAsync`) if BciCore and logging is not Disabled. Stays on the settings screen with the CSV path. "Back to games" returns to the launcher. | `:347-371` |
| Abort (Abort button, Escape, "Back to games", calibration Back) | `Exit()`. If a session is running, `AbortWithSeparatedMarkers` blanks the screen immediately. If in a trial, it waits until `lastHardwareTriggerAt + markerGap` and logs `trial_aborted` (60). It then waits `markerGap`, logs `run_aborted` (11) if the run is active, waits `markerGap` again, logs `session_aborted` (0), then `Finish(exit=true)` returns to the launcher. Outside a session `Exit()` finishes and returns directly. | `:386-417` |
| Escape key | Checked every frame **in every phase**, including Settings, where it returns to the launcher. | `:262` |
| Fatal: acquisition lost | While `sessionStarted`, `!acquisition.Ready` or `acquisition.Error != null` triggers `Fail(...)`. | `:268` |
| Fatal: prediction receiver error | `predictions.Error != null` (UDP socket error) triggers `Fail`. | `:269` |
| Fatal: app paused/backgrounded | `OnApplicationPause(true)` during a session triggers `Fail`. | `:418` |
| `Fail()` | Logs **only** `session_aborted` (code 0, no hardware marker) and flushes. Then `Finish(exit=false, failed=true)`. **No 60/11 markers and no `trialdata.csv` row for the interrupted trial.** | `:349-350` |
| Restart | After Complete/Failed, Begin starts a new session with a new task folder and a new BciServer start and calibration. | `:209` |
| Orientation | Landscape autorotate during the game. Restored in `OnDestroy`. | `:172-174`, `:419-425` |

Settings are frozen into private session variables at Begin (`:216-224`). The configuration UI is locked until export finishes.

---

## 4. Trial structure & timing

### Timeline (defaults, one run)

```
t (s, relative)    event (code)              screen
-0.3               run_start (10)            blank grey             <- RunLeadIn, markerGap=0.3
 0.0               cue_on (21..24|31..34)    hand + blue finger      <- trial onset = frame time
 0.5               cue_off (0)               plain hand              (Flash 0.5/0.5)
 1.0               cue_flash_on (0)          blue                    online feedback may start here
 ...               prediction_received/presented (0)                 online only, >=0.1 s apart
 D                 trial_end (60), iti_onset (0)  blank              D = 5 (offline) or 3 (online)
 D+2               iti_end (0) + next cue_on (same frame)
 ... last trial:   iti_end (0) + run_end (11) at D+2                 <- full ITI between last 60 and 11
 +0.3              (RunEndHold over) run_pause_on (0) -> 20 s countdown screen (tap skips)
 +20               run_pause_end (0), run_start (10) of next run
```

Online SinglePulse example: 0-1 s blue finger, 1-3 s plain hand with feedback circle, 3 s marker 60 and blank.

### Timing parameters

| Parameter | Field | Effective default | Used as |
|---|---|---|---|
| Trial duration | `offlineTrialDuration` / `onlineTrialDuration` | 5 s / 3 s | `endDeadline = onset + duration` (`:254`) |
| ITI | `itiDuration` | 2 s | `itiDeadline = trial_end frame time + ITI` (`:298`) |
| Run lead-in / end hold / abort guard | `markerSeparationSeconds` | 0.3 s (forced ≥0.3, ITI forced ≥ it) | `boundaryDeadline = now + markerGap` (`:250`, `:280`) |
| Run pause | `pauseBetweenRuns`, `runPauseDuration` | true, 20 s | Countdown. A tap anywhere resumes early (`:285-292`). Not shown after the final run. |
| Cue flash | `cuePattern=Flash`, `cueOnDuration`, `cueOffDuration` | 0.5 / 0.5 s | `visible = (elapsed mod (on+off)) < on` (`FingerProtocol.cs:33-37`) |
| Single pulse | `cuePattern=SinglePulse`, `singlePulseDuration` | 1 s | `visible = elapsed < on` |
| Online feedback start | `onlineFeedbackStart` | 1 s | `feedbackDelay = max(onlineFeedbackStart, flashOn)` in Online, 0 otherwise (`:222`) |
| Prediction update interval | `predictionUpdateInterval` | 0.1 s | Minimum spacing of presentation ticks. Validation rejects values <0.1, and `Math.Max(.1, …)` is applied as well (`:221`). |

### What ends a trial

Only the deadline: the first frame with `now >= endDeadline` (`:295-299`) ends the trial, or an abort/fail. There are no response or timeout rules. The end check runs **before** cue-edge and prediction processing in that frame.

### Seconds vs frames

All timing is in seconds on `MonotonicClock`, polled once per rendered frame. Every transition therefore lands on the first frame at or after its deadline, a lateness of up to about one frame period. Each phase's deadline is computed from the **actual** frame time of the previous transition, with no catch-up, so lateness accumulates across a run. ITI is measured from the actual `trial_end` frame time. The next `cue_on` is at the first frame ≥ `itiDeadline`. Finger does not set the display rate. It inherits the launcher's `DisplayRateManager.ApplyPresentation(120, 1)` (`Assets/CogLab/App/CogLabAppController.cs:99`). A tablet device check measured offline trials 5.0003-5.0099 s, online 3.0016-3.0050 s and ITI 2.0017-2.0080 s (`Documentation/android-device-check.json`).

### Feedback within a trial (online)

See section 7. Feedback is cleared at trial end (`ShowIti` → `Clear()`). Cue flash edges do not clear it (`SetCue` touches masks only, `FingerCanvasView.cs:153`).

---

## 5. Trial planning / randomisation

- **Classes**: the selected fingers from `includeThumb/Index/Middle/Pinky`, in fixed order Thumb, Index, Middle, Pinky (`:115-120`). Validation requires exactly `numberOfClasses` (2/3/4) selected fingers. The ring finger is never available.
- **Presets** (`ApplyClassPreset`, `:121-126`; in-game settings and Inspector only): 2 classes = Thumb+Pinky; 3 = Thumb+Index+Pinky; 4 = all. The preset keeps trials-per-finger (`trialsPerRun / oldClassCount`) and recomputes `trialsPerRun`. Cycling `Number Of Classes` in the **launcher** tab does *not* run the preset, so the include flags must be set by hand there.
- **Balancing** (`FingerProtocol.BalancedRun`, `FingerProtocol.cs:23-32`): each run contains `trialsPerRun / k` occurrences of each selected finger (k = class count). The list `[f0,f1,…,f0,f1,…]` is Fisher-Yates shuffled with `random.Next(i+1)`. Runs are independent. There are no constraints on repeats, so the same finger can occur consecutively. `trialsPerRun % k != 0` is rejected.
- **Default plan**: 8 runs × 20 trials, 4 classes → 5 per finger per run, 160 trials. Limits: ≤1000 runs, ≤10000 trials/run, ≤100000 total.
- **Seeding** (`:223-224`): `seed = useFixedRandomSeed ? randomSeed : Environment.TickCount`. A single `System.Random(seed)` generates all runs in order. Default is a fixed seed of 21021, so every session with default settings has the **same** sequence. The seed actually used is written in `plan.csv`, `events.csv` and `trialdata.csv` (`random_seed`). In `settings.json`, `randomSeed` holds the field value, which is not the seed used when `useFixedRandomSeed=false`.
- **Reproducibility**: `System.Random` with the same seed, finger set and run/trial counts reproduces `plan.csv` exactly (Editor check `FingerVerification.cs:17-20`). `plan.csv` is written before the first trial and is authoritative.

---

## 6. Stimulus

**Canvas**: Screen Space Overlay, sorting order 100. `CanvasScaler` uses ScaleWithScreenSize with reference 1920×1080 and match 0.5 (`FingerCanvasView.cs:29-32`). Full-screen grey `Image` (80,80,80).

**Geometry** (reference-canvas units; values for a 16:9 screen, where the canvas is 1920×1080):

| Element | Formula | 16:9 value |
|---|---|---|
| Hand container | anchors x 0.10-0.90, y 0.105-0.895 of canvas (`:41`) | 1536 × 853.2 |
| Artwork rect | `AspectRatioFitter.FitInParent`, aspect 1000/1300 (`:43-44`) | height-limited: 656.3 × 853.2 |
| Rendered scale | `localScale = handScale × 0.5` (`:143`); default handScale 0.8 → **0.4** | 262.5 × 341.3 (≈31.6% of screen height), centred |
| Art space | 1000 × 1300 units, origin top-left (`geometry.json`) | 1 art unit ≈ 0.2625 ref px |
| Fingertips (art units) | Thumb (162,682), Index (389,325), Middle (538,250), Pinky (833,479) (`:16`) | — |
| Prediction circle | centre anchor `(tip.x/1000, 1 − (tip.y − 76)/1300)`, diameter `0.116 × artwork width` (= 116 art units; radius 58 + 18 gap → bottom edge 18 units above the tip) (`:155-161`) | ≈30.5 ref px diameter after scale |

Layers, bottom to top: white `RightHand` sprite → four `<Finger>Mask` images (tinted cue blue, only the cued one enabled) → dark `HandBorder` sprite → `PredictionMarker` circle. Masks are clipped to the silhouette in the artwork.

**Colours** (authored as sRGB `Color32`; project colour space is Linear, `ProjectSettings.asset:50`. uGUI displays these sRGB values, subject to texture compression of the sprites):

| Use | sRGB | Hex |
|---|---|---|
| Background | 80,80,80 | `#505050` |
| Cue | 23,56,232 | `#1738E8` |
| Correct feedback | 30,220,93 | `#1EDC5D` |
| Incorrect feedback | 242,52,64 | `#F23440` |
| Abort button | 45,55,68 | `#2D3744` |

**Motion**: none. **SSVEP / flicker**: not applicable. The cue on/off alternation (default 1 Hz, 50% duty) is frame-quantised, with phase origin = the `cue_on` frame time (`onset`). It is not an SSVEP stimulus and is not vsync-locked. `FrameStimulusCsvLogger` and `PresentationClock` are not used.

**Visual demonstration** (`visualDemonstration=true`): every 4 s the cue moves to the next finger, with a correct marker for 2 s and then an incorrect marker on the next finger. There is no logging (`FingerExperimentController.cs:263-267`).

---

## 7. Neurofeedback

The shared SSVEP NF pair (`NfSourceType`, NF index/channel, USB 24-byte NF records) is **not used**. `UsbBiosemiLink` still receives NF records and echoes `R <sampleCount>` control lines, but Finger never calls `TryRead`/`TryReadPair` (`FingerAcquisition.cs:28-30`). Feedback instead comes from decoded **finger IDs**:

| `predictionSource` | Transport | Accepted content | `source_timestamp` logged | `receivedAt` clock point |
|---|---|---|---|---|
| `Simulation` | none | Every tick: predicted = **cued finger**, confidence 0.85 (`:317-321`, `:336`). Online only. | `""` | the tick's frame time |
| `Udp` | UDP port `predictionUdpPort` (5020), bound to Any or Loopback | One datagram ≤256 bytes: `id[,confidence[,source_stamp]]`. id must be 21-24 or 31-34, confidence finite in [0,1], at most 3 fields (`FingerPredictions.cs:70-80`, `:89`) | the 3rd field, verbatim | `MonotonicClock.Now` on the receive thread |
| `BciCoreMl` | `BciServer.OnMlResult` (requires BciCore) | `PredClass` must already be the finger ID. Confidence is **not** validated (`:49`) | `Seq` as bare integer | main-thread dispatch (frame-quantised) |
| `Emg32EegNet` | `BciServer.OnMlResult` | `PredClass` 0/1 mapped to `emg32ClassZeroFinger`/`emg32ClassOneFinger` → ME/MI ID; confidence in [0,1] (`:50-62`) | `seq=<newest board sample seq>;latency_ms=<forward ms>` | main-thread dispatch (frame-quantised) |

Invalid packets increment `RejectedPackets`, as does overflow beyond 4096 queued items. **This counter is never logged.**

**Per-trial processing** (`TickTrial`, `FingerExperimentController.cs:293-332`):

1. At `cue_on` the queue is cleared and the smoother reset (`:253-255`).
2. Every frame, all queued predictions are drained. A prediction is dropped silently, without a log row, if `receivedAt < onset`, `receivedAt ≥ endDeadline`, its ID is outside the current ME/MI range, or its finger is not selected. Otherwise a `prediction_received` row is written, and if `receivedAt ≥ onset + feedbackDelay` it becomes the single `pending` prediction (the newest wins).
3. Online only: at the first frame with `now ≥ nextPrediction` (initially `onset + feedbackDelay`), `scheduled = nextPrediction` and `nextPrediction = now + interval`, scheduled from the actual frame, not the plan. Missed ticks are not replayed. The pending prediction is consumed (Simulation synthesises one). If none is pending, nothing changes and the previous circle stays.
4. If smoothing is enabled the smoother runs (below). The display is then set: circle above `decoded`, green if `decoded == cue`, else red. A `prediction_presented` row is written.

**Smoothing** (`FingerFeedbackSmoother.cs:11-29`). It is active when `enableFeedbackSmoothing && !(externalPredictionsAlreadySmoothed && source ∈ {Udp, BciCoreMl})` (`:219`). With the defaults (true/true) this means Simulation and Emg32EegNet are smoothed, and Udp and BciCoreMl are passed through. `binary = (source ∈ {Emg32EegNet, Simulation} || externalConfidenceIsBinarySoftmax) && k == 2 && 0.5 ≤ c ≤ 1`.

```
for each selected finger f:
    e_f = binary ? (f == predicted ? c : 1 − c) : (f == predicted ? 1 : 0)
    h_f = α · h_f + e_f                       (α = smoothingAlpha, default 0.90)
winner = argmax_f h_f  (ties -> earliest in Thumb,Index,Middle,Pinky order)
displayed confidence = h_winner / Σ_f h_f
```

The history `h` is reset at every `cue_on`. It is only updated on ticks that consume a fresh prediction, so there is no decay on empty ticks. There is no clipping beyond these rules, and no thresholds: every consumed prediction updates the display.

**Stall handling**: none. With no new predictions the last circle stays until trial end. There is no stall timeout. (Shared "USB NF stall timeout" does not bind to Finger.)

---

## 8. Responses & scoring

- **Participant inputs**: none. Operator inputs are the Abort button, Escape (Input System `Keyboard.current.escapeKey`), a tap on the run-pause screen, and the settings buttons.
- **Correctness** (`FingerCsvLogger.cs:55`): `prediction_correctness = 1` if `cued_finger == predicted_finger`, `0` if they differ, empty if either is missing. In `prediction_received` rows it refers to the **raw** decoded finger. In `prediction_presented` rows it refers to the **displayed** (possibly smoothed) finger.
- **Per-trial summary** (`trialdata.csv`): `presented_prediction_count` and `correct_prediction_count` are counted over `prediction_presented` rows since `cue_on`. `last_*` columns refer to the last **presented** prediction. In Offline mode nothing is presented, so these columns are empty or 0 even if predictions were received.
- **RT**: not applicable. There is no response.
- **Decoder latency available**: `prediction_timestamp − cue_onset_timestamp` (both `MonotonicClock`; arrival in Unity, not decoder window time). For Emg32EegNet the `source_timestamp` contains `seq` (newest EEG sample of the 250-sample window), which allows mapping to the EEG sample index (section 13).

---

## 9. Event markers / triggers

Hardware markers are sent only when `code > 0` and `acquisition != null`, i.e. never for Simulation (`FingerExperimentController.cs:337-344`). All events, including code-0 events, are rows in `events.csv`.

| Code | `event` | Exact moment | Condition | Hardware? |
|---|---|---|---|---|
| 10 | `run_start` | Frame of `BeginRun` (session start, after a run pause, or after RunEndHold when there is no pause) | every run | yes |
| 21/22/23/24 (ME) · 31/32/33/34 (MI) | `cue_on` | Frame the trial starts (first frame ≥ lead-in or ITI deadline). Thumb/Index/Middle/Pinky = +0/+1/+2/+3 (`FingerProtocol.cs:16`) | every trial | yes |
| 0 | `cue_off`, `cue_flash_on` | Frame a cue edge is detected. `scheduled_timestamp` = theoretical edge (`CueEdge`, `:334-335`) | Flash: every edge; SinglePulse: one `cue_off` | no |
| 0 | `prediction_received` | Row written when the prediction is drained (`event_timestamp` = write time; `prediction_timestamp` = arrival) | valid prediction inside the trial | no |
| 0 | `prediction_presented` | Presentation tick frame | Online | no |
| 60 | `trial_end` | First frame ≥ `endDeadline` | every completed trial | yes |
| 0 | `iti_onset` | Same frame as `trial_end` | | no |
| 0 | `iti_end` | First frame ≥ `itiDeadline`, immediately followed by the next `cue_on` or by `run_end` in the same frame | | no |
| 11 | `run_end` | Same frame as the final trial's `iti_end` (a full ITI after the last 60) | | yes |
| 0 | `run_pause_on` / `run_pause_end` | Pause start (after RunEndHold) / countdown expiry or tap | `pauseBetweenRuns && runPauseDuration > 0`, not after the last run | no |
| 0 | `session_complete` | After the last RunEndHold | | no |
| 60 | `trial_aborted` | Abort during Trial, ≥`markerGap` after the previous hardware marker | operator abort | yes |
| 11 | `run_aborted` | `markerGap` after abort start (or after `trial_aborted`) | abort while run active (RunLeadIn/Trial/Iti) | yes |
| 0 | `session_aborted` | End of abort sequence, or on `Fail()` | | no |

**Transport**

- **BciCore**: `BciServer.LogTriggerSent("finger_<code>", code)` adds a health row `trigger_sent:finger_<code>` (seq 0, marker = code), then `BciServer.SendMarker(code)` sends a TCP CMD frame to the board (`FingerAcquisition.cs:36`). `trigger_delivered` = return value of `SendMarker`: written to the socket, **not** confirmed latched.
- **UsbBiosemi**: `UsbBiosemiLink.Send` writes the ASCII line `"<code>\n"` to the localhost TCP bridge (`usbBiosemiPort`, default 5010) with a 100 ms write timeout. `trigger_delivered = (Error == null)` after the send. A reset code 0 is sent on every new connection.

**Board latch**: the board stamps the latched marker on the RAW/PROC sample `marker` column for about 200 ms and has a single latch, not a FIFO (Guide.md §11). Finger therefore guarantees ≥`markerSeparationSeconds` (≥0.3 s) between 10→cue, last 60→11 (full ITI), 11→next 10 (RunEndHold), and 60/cue→abort markers. **Not guaranteed**: cue→60 is separated only by the trial duration (validated ≥0.1 s).

**Health-log echo labels**: Finger sets `BciServer.SeparateMarkerEchoesInHealthLog = true` while its BciCore acquisition exists and restores the previous value on dispose (`FingerAcquisition.cs:20-23`, `:40`). In `*_health.csv`:

- Board marker echoes are logged as `marker = 1000 + code` with `event = marker_echo:<code>` (e.g. 1021). Echo of 0 is 1000.
- Health frames carrying a latched marker are logged with `marker = 0` and `event = latched_marker:<code>`.
- Sent triggers keep `marker = code` with `event = trigger_sent:finger_<code>`.

RAW/PROC sample markers are unchanged (`Packages/org.iisc.bcicore.server/Runtime/Api/BciServer.cs:369-390`).

**Validation rules (expected marker sequence for a complete session)**: `[10, (cue, 60) × trialsPerRun, 11] × numberOfRuns`. Consecutive hardware markers are ≥0.3 s apart, except cue→60 when the trial is <0.3 s. Editor check `FingerBoundaryVerification.cs:72-79` asserts exactly this order and spacing.

**Legacy vs shuffled modes**: not applicable (single scheme). The ME/MI ranges are the only variant.

---

## 10. Output files

### 10.1 Task folder

Path: `<root>/p<P>_b<S>_fingerdecoding_<yyyyMMdd_HHmmss_fff UTC>_<32-hex GUID>/` (`FingerCsvLogger.cs:22-25`)

- `<root>` = `fingerDataFolderName` if it is an absolute path, otherwise `Application.persistentDataPath/<fingerDataFolderName>`. The default is `FingerDecodingData` (`FingerExperimentController.cs:237`). On Android this is `/storage/emulated/0/Android/data/<package>/files/FingerDecodingData/`.
- `<P>` is the launcher participant number and `<S>` the launcher "Block number". Characters other than letters, digits, `-` and `_` become `_`. An empty value becomes `000`.
- The folder is created at `StartSession`, i.e. after Proceed in calibration. Files are opened with `FileMode.CreateNew` and UTF-8 without BOM. A new folder is created every session, so nothing is ever appended or overwritten. There is no schema-version column and no header-mismatch handling.
- Flushing: `events.csv` and `trace.csv` are flushed at each `trial_end`, on `Fail` and on dispose. A hard crash can lose the rows written since the last trial end. `session.csv` is flushed per row.

Number formatting: times and confidences use `F9` (9 decimals, invariant culture). `NaN` is written as an **empty field**. Quoted fields: `event` and `source_timestamp` in events/trace, all `session.csv` values, and `participant`/`session` in plan.csv.

#### `events.csv` (every event) and `trace.csv` (only `prediction_received` and `prediction_presented` rows, identical columns)

Header (`FingerCsvLogger.cs:18`). Columns are filled differently by `Event()` (task events, `FingerExperimentController.cs:337-344`) and `Record()` (prediction rows, `:345-346`).

| # | Column | Meaning | Event() rows | Record() rows |
|---|---|---|---|---|
| 0 | `event` | Event name (quoted) | see §9 | `prediction_received` / `prediction_presented` |
| 1 | `run_number` | 1-based run | `run+1`. `run_pause_on/end` already carry the **next** run number | `run+1` |
| 2 | `trial_number` | 1-based trial within run | `trial+1`. `run_start` = 1; `run_end`/`run_pause_*`/`session_complete` = last trial index | `trial+1` |
| 3 | `experimental_mode` | `Offline`/`Online` | | |
| 4 | `motor_task` | `ME`/`MI` | | |
| 5 | `cued_finger` | `Thumb/Index/Middle/Pinky` | empty for `run_*` and `run_pause_*`. Otherwise the current or **previous** trial's cue (`iti_*`, `session_*`) | current cue |
| 6 | `predicted_finger` | finger | last **presented** prediction of the current trial (empty after `cue_on` until the first presentation). Run events can carry the previous trial's value | raw (received) or displayed (presented) finger |
| 7 | `prediction_correctness` | 1/0/empty | cue vs col 6. Empty if either is missing | cue vs col 6 |
| 8 | `prediction_confidence` | [0,1] | last presented confidence | raw confidence (received). Presented: smoothed `h_w/Σh` if smoothing is on, else raw. Empty if none supplied |
| 9 | `cue_onset_timestamp` | s, MonotonicClock | `onset` (frame time of `cue_on`). Empty for run events | `onset` |
| 10 | `prediction_timestamp` | s, MonotonicClock | arrival time of the last presented prediction | `receivedAt` (arrival). For Simulation = tick frame time |
| 11 | `trial_end_timestamp` | s, MonotonicClock | frame time, only for `trial_end` / `trial_aborted` | empty |
| 12 | `trigger_code` | int | code (0 for software events) | 0 |
| 13 | `event_timestamp` | s, MonotonicClock | `now` of the frame (start of `Update`) | `MonotonicClock.Now` **at write time** (slightly later than the frame start) |
| 14 | `scheduled_timestamp` | s, MonotonicClock | planned time: `run_start`/`cue_on`/`iti_onset`/`run_pause_on` = now; cue edges = theoretical edge; `trial_end` = `endDeadline`; `iti_end`/`run_end` = `itiDeadline`; `run_pause_end` = `runPauseDeadline` (even when tapped early); `session_complete` = stale last `itiDeadline`; aborts = empty | received: empty; presented: tick deadline `nextPrediction` |
| 15 | `presented_timestamp` | s, MonotonicClock | = `event_timestamp` (frame in which the visual change was submitted) | received: empty; presented: tick frame `now` |
| 16 | `source_timestamp` | string | `""` | upstream stamp (see §7) |
| 17 | `utc_timestamp` | ISO-8601 UTC (`O`) | `DateTime.UtcNow` at write | same |
| 18 | `trigger_delivered` | 0/1 | 1 only if code>0 and send succeeded | 0 |
| 19 | `simulation` | 0/1 | 1 if `predictionSource == Simulation` | |
| 20 | `random_seed` | int | seed actually used | |

#### `trialdata.csv` (one row per `trial_end` or `trial_aborted`; `FingerCsvLogger.cs:29`, `:63-70`)

| Column | Meaning / units / clock |
|---|---|
| `run_number`, `trial_number` | 1-based. Join keys to `plan.csv` (`run`,`trial`) and `events.csv` |
| `experimental_mode`, `motor_task`, `cued_finger` | as above |
| `trial_start` | `cue_onset_timestamp` (s, MonotonicClock) |
| `trial_end` | frame time of `trial_end`/`trial_aborted` (s, MonotonicClock). For aborts this is the marker time, which comes after the screen already blanked |
| `trial_duration` | `trial_end − trial_start` (s). Frame-quantised, ≥ configured duration for completed trials |
| `trial_start_marker` | cue ID (21-24/31-34). Written even when not delivered (Simulation) |
| `end_reason` | `completed` / `aborted` |
| `last_predicted_finger`, `last_prediction_correctness`, `last_prediction_confidence` | last **presented** prediction (empty in Offline) |
| `presented_prediction_count`, `correct_prediction_count` | counts of `prediction_presented` rows since `cue_on` |
| `simulation`, `random_seed` | as above |

Trials interrupted by `Fail()` (disconnect, app pause, UDP error) produce **no** row.

#### `plan.csv` (written at StartSession; `FingerExperimentController.cs:244-245`)

`run,trial,finger,cue_id,seed,participant,session`: one row per planned trial (1-based), finger name, cue ID, seed, and quoted participant/session strings.

#### `session.csv` (`Key,Value`, all quoted)

Keys in order: `Participant`, `Session`, `CreatedUtc`, `TaskDirectory`, `TimestampClock` (fixed text), `ExperimentalMode`, `MotorTask`, `PredictionSource`, `AcquisitionMethod`, `EegLoggingMode`, `EegDirectory` (= `BciServer.CurrentSessionDir` at StartSession for BciCore, else empty). At close: `CompletedTrials`, `AbortedTrials`, `LastEvent`, `ClosedUtc` (`FingerCsvLogger.cs:31-35`, `:73-79`; `FingerExperimentController.cs:239-242`).

#### `settings.json`

`JsonUtility.ToJson(controller, prettyPrint)` of the runtime controller at StartSession, containing all serialized public fields by **code field name** (e.g. `fingerDataFolderName`). It does not contain participant/session, the EEG logging mode, the actual seed, or launcher Common values beyond what was bound into fields.

### 10.2 EEG logs (BciCore acquisition only, logging not Disabled)

Written by the shared BciCore server. Formats and columns are in [00-Shared-Infrastructure.md](00-Shared-Infrastructure.md). How Finger uses them:

- Folder: `persistentDataPath/BciCoreLogs/eeg_finger-decoding_p<P>_s<S>_<local yyyyMMdd_HHmmss>/`. The game name is set by the launcher's `BciServer.SetSessionIdentity(..., "finger-decoding")` (`CogLabAppController.cs:701`). A new folder is opened on each board connection/HELLO.
- Files: `<stem>_raw.csv`, `<stem>_signals.csv`, `<stem>_features.csv`, `<stem>_health.csv`, `<stem>_config.txt`. In `BinaryThenCsv` mode, `.bin` files are written and converted at `Finish`.
- `raw.csv`/`signals.csv`: `seq, raw1..N | ch1_uv..chN_uv, marker`. The `marker` column carries the **original** codes 10/11/21-34/60 for about 200 ms per marker.
- `health.csv`: `wall_sec, board_ms, seq, …, marker, event`, with Finger's echo labelling (§9). `wall_sec` is **integer local seconds-of-day**, so it is only useful for coarse matching.
- The recording starts at board connection, so it includes the calibration screen before `run_start`. The link from task to EEG is `session.csv:EegDirectory`.
- UsbBiosemi: EEG is recorded by the external acquisition software, not by the app.

### 10.3 Other

- `PlayerPrefs` `CogLab.Games.finger-decoding.v1` holds the template settings JSON. `SetPredictionSource` writes it immediately when Prediction Source is cycled in-game (`:372-383`).
- Device check (development builds, only if `finger-device-check.request` exists in `persistentDataPath`): `FingerDecodingData/DeviceChecks/<ts>/report.json`, simulation task folders, and `finger-device-check.request.result.json`.
- No `stimframes` file and no NF trace file.

---

## 11. Settings reference

**Effective default** = prefab YAML value (`FingerDecoding.prefab:48-78`). Fields missing from the YAML use the C# initializer. Saved PlayerPrefs override both. "UI name" is the nicified field name shown in the in-game settings screen and the launcher Finger tab.

| UI name | Field | Effective default | Code initializer (if different) | Unit | Meaning / validation |
|---|---|---|---|---|---|
| Motor Task | `motorTask` | `ME` (0) | | enum ME/MI | Selects ID range 21-24 vs 31-34 |
| Experimental Mode | `experimentalMode` | `Offline` (0) | | enum | Offline: no feedback; Online: feedback |
| Number Of Classes | `numberOfClasses` | `Four` (4) | | 2/3/4 | Must equal the number of included fingers |
| Include Thumb / Index / Middle / Pinky | `includeThumb`… | true ×4 | | bool | Selected classes |
| Number Of Runs | `numberOfRuns` | 8 | | count | ≥1 (Min 1) |
| Trials Per Run | `trialsPerRun` | 20 | | count | ≥2, divisible by class count |
| Pause Between Runs | `pauseBetweenRuns` | true | | bool | |
| Run Pause Duration | `runPauseDuration` | 20 (not in prefab) | 20 | s | ≥0. 0 disables the pause |
| Hand Scale | `handScale` | 0.8 (not in prefab) | 0.8 | factor | Rendered scale = ×0.5. Launcher Range 0.5-1.2; controller accepts (0, 1.5] |
| Offline Trial Duration | `offlineTrialDuration` | 5 | | s | ≥0.1 |
| Online Trial Duration | `onlineTrialDuration` | 3 | | s | ≥0.1 |
| Iti Duration | `itiDuration` | 2 | | s | ≥ `markerSeparationSeconds`. If less, it is reset to max(2, sep) on load and Begin |
| Marker Separation Seconds | `markerSeparationSeconds` | 0.3 (not in prefab) | 0.3 | s | Raised to 0.3 if lower |
| Cue Pattern | `cuePattern` | `Flash` (0) | | enum Flash/SinglePulse | |
| Cue On Duration / Cue Off Duration | `cueOnDuration`, `cueOffDuration` | 0.5 / 0.5 | | s | ≥0.01 |
| Single Pulse Duration | `singlePulseDuration` | 1 | | s | ≥0.01 and ≤ trial duration |
| Online Feedback Start | `onlineFeedbackStart` | 1 | | s | < online trial duration (checked in both modes) |
| Prediction Update Interval | `predictionUpdateInterval` | 0.1 | | s | ≥0.1 and ≤ trial duration |
| Enable Feedback Smoothing | `enableFeedbackSmoothing` | true (not in prefab) | true | bool | |
| External Predictions Already Smoothed | `externalPredictionsAlreadySmoothed` | true (not in prefab) | true | bool | Bypasses smoothing for Udp/BciCoreMl |
| Smoothing Alpha | `smoothingAlpha` | 0.90 (not in prefab) | 0.90 | — | [0,1); launcher Range 0-0.99 |
| External Confidence Is Binary Softmax | `externalConfidenceIsBinarySoftmax` | false (not in prefab) | false | bool | 2-class Udp/BciCoreMl evidence mode |
| Acquisition Method | `acquisitionMethod` | `BciCore` (0) | | enum BciCore/UsbBiosemi | Ignored when source = Simulation |
| Prediction Source | `predictionSource` | **`Simulation` (0)** | **`Emg32EegNet`** | enum Simulation/Udp/BciCoreMl/Emg32EegNet | Simulation = no acquisition, no EEG, always-correct predictions |
| Usb Biosemi Port | `usbBiosemiPort` | 5010 | | TCP port | **Common tab "USB Biosemi port"** |
| Prediction Udp Port | `predictionUdpPort` | 5020 | | UDP port | Not 5005/5006 |
| Udp Loopback Only | `udpLoopbackOnly` | false | | bool | Bind 127.0.0.1 instead of Any |
| Emg32 Class Zero Finger / Class One Finger | `emg32ClassZeroFinger`, `emg32ClassOneFinger` | Thumb / Pinky (not in prefab) | same | enum | EMG32 class→finger map. In Online, both must be selected, distinct, and k = 2 |
| Use Fixed Random Seed | `useFixedRandomSeed` | true | | bool | **Common tab "Use fixed random seed"** |
| Random Seed | `randomSeed` | 21021 | | int | Finger tab only. Not bound to Common "Fixed random seed" |
| Finger Data Folder Name | `fingerDataFolderName` (YAML key `dataFolderName`, migrated by `FormerlySerializedAs`) | `FingerDecodingData` | | path | Relative to persistentDataPath, or absolute. Not bound to Common "Data folder" |
| Visual Demonstration | `visualDemonstration` | false | | bool | Hidden from the in-game settings screen. Visible in the launcher tab |

Obsolete keys still in the prefab YAML, ignored by the code: `enableOfflineFeedback`, `simulationPattern`, `manualPredictedFinger` (`FingerDecoding.prefab:67,73,74`).

**Launcher interaction.**

- The Common tab binds only `usbBiosemiPort` (key `usbPort`) and `useFixedRandomSeed` (key `fixedSeedEnabled`) (`Assets/CogLab/App/SharedSettingsCatalog.cs:38,45`). These fields are hidden from the Finger tab. A saved explicit Common value overwrites Finger's field on later launches.
- Not affected: display rate, VSync, frequencies, connection/stall timeouts, UDP trigger port, data folder, frame logging, NF trace interval, fixed seed value and keyboard (no matching field names).
- The launcher passes participant number, block number (logged as "Session") and `eegLoggingMode` (default `DirectCsv`) via `ConfigureSharedLaunch` (`FingerExperimentController.cs:113-114`).
- The launcher tab enforces `[Min]`/`[Range]` (`CogLabAppController.cs:656-658`) and `FingerGameModule.ValidateSettings` before launch.
- Edits made on the **in-game** settings screen affect only that runtime copy and are not persisted, **except** Prediction Source.

---

## 12. Timing & clock semantics

- **Clock**: every `*_timestamp` column except `utc_timestamp` and `source_timestamp` is `MonotonicClock.Now = Stopwatch.GetTimestamp()/Stopwatch.Frequency` in seconds (`Assets/CogLab/Shared/Timing/MonotonicClock.cs:7`). The origin is arbitrary (on Android effectively time since boot). It is shared across games, not reset per session, and has sub-microsecond resolution. It is **not** shared with the EEG board, and no EEG file contains it.
- **What the times mean**: `event_timestamp`/`presented_timestamp` for task events is the CPU time at the start of the `Update()` in which Unity changed the UI or sent the marker. The visible change happens at a later vsync, typically 1-2 frames later plus panel latency. Photon onset is not measured. `scheduled_timestamp` is the deadline the frame was waiting for, so `event − scheduled` is the frame-quantisation lateness (0 for events scheduled at `now`).
- **Marker vs screen**: for code>0 events the marker is sent synchronously inside the same `Update` before rendering. Marker transmission (TCP to board over Wi-Fi, or localhost bridge) and the board's latching on its next sample add unmeasured latency. The visual change follows at the next present.
- **Prediction rows**: `prediction_timestamp` is Unity arrival. For BciCore sources this is the main-thread dispatch time, so it is quantised to frames. For UDP it is the socket receive time. `event_timestamp` of `prediction_received` is the write time (drain frame). Decoder-side timing is only in `source_timestamp`.
- **Dropped frames**: not detected or logged. The only evidence is gaps between consecutive frame-timed events (e.g. `event_timestamp − scheduled_timestamp` of cue edges and ticks). Missed presentation ticks are silently skipped.
- **Precision limits**: transitions have about 1 frame (8.3 ms at 120 Hz) of quantisation and cumulative lateness within a run. `trial_duration` is ≥ nominal by up to about 1 frame (+ jitter). The 9-decimal formatting is not real precision.
- **UTC**: `utc_timestamp` is `DateTime.UtcNow` at row write. It is for coarse cross-referencing only (EEG `wall_sec` is local time-of-day, in integer seconds).

---

## 13. Analysis guide

**Keys and joins**

- Trial key = (`run_number`, `trial_number`), consistent across `plan.csv` (`run`,`trial`), `trialdata.csv` and `events.csv`/`trace.csv`.
- Session key = the task folder name. `session.csv:EegDirectory` points to the EEG folder.
- Use `simulation==0` and `trigger_delivered==1` to select real data.

**Align EEG to task events (BciCore)**

1. In `<stem>_raw.csv` (or `_signals.csv`), find rising edges: rows where `marker != 0` and `marker != previous row's marker`. Each code is held for about 200 ms (≈50 samples at 250 Hz), so count transitions, not rows.
2. Extract the ordered list of `events.csv` rows with `trigger_code > 0` and `trigger_delivered == 1`.
3. Match the two sequences in order, requiring identical code sequences (pattern `10, (cue,60)…, 11` per run; aborts may end with `60, 11` or `11`). Mismatched counts mean lost or merged markers. Investigate before analysing.
4. Map any task time `t` to an EEG sample: use the nearest preceding matched marker `m` and compute `sample ≈ seq_m + (t − event_timestamp_m) · Fs`, with Fs from `<stem>_config.txt` (250 Hz typical). For better accuracy, fit `seq = a + b·t` by least squares over all matched markers in a run. `b` also estimates the clock-rate ratio, and the residuals expose marker-latency jitter.
5. Health rows `trigger_sent:finger_<code>` (seq 0) and `marker_echo:<code>` (marker `1000+code`) confirm sending and echo but are **not** sample-accurate. The echo header seq is not a sample index (Guide.md §10).
6. Emg32EegNet predictions: `source_timestamp` contains `seq=<n>`, the newest sample of the classifier window. Treat the window as `[n−249, n]` (250 samples, 25-sample hop). Verify that this seq space matches `raw.csv` `seq` on your firmware before relying on it.

**Epoching**

| Purpose | Anchor | Window |
|---|---|---|
| Offline ME/MI decoding | `cue_on` marker sample | 0 to +5 s (+ `trial_end` 60 marker as check) |
| Online decoding / feedback period | `cue_on` | feedback window `[feedbackDelay, duration)` = 1-3 s default |
| Baseline | `iti_onset`/60 → next cue (2 s blank) | e.g. −1 to 0 s before cue. **The first trial of a run has only a 0.3 s blank lead-in after marker 10**; the run-pause screen precedes it |
| ERD | cue-locked 8-13 Hz / 13-30 Hz power | relative to an ITI baseline |

Cue-flash edges (`cue_off`/`cue_flash_on`) are visual events at about 1 Hz and can evoke VEPs. Use their `event_timestamp`s to model or exclude them.

**Performance metrics**

- Label per trial: `cued_finger` (or `plan.csv:finger`). Chance = 1/k for balanced k classes.
- Displayed accuracy per trial: `correct_prediction_count / presented_prediction_count` (online). Last-update correctness: `last_prediction_correctness`.
- Raw-decoder accuracy (recommended; independent of Unity smoothing): use `trace.csv` rows `event=="prediction_received"` with `prediction_timestamp ≥ cue_onset_timestamp + feedbackDelay` and `< trial_end`. Take a majority vote per trial (predefine the tie rule) and build a confusion matrix of cued vs voted finger. Report per class and balanced accuracy. Do not treat 100 ms updates as independent samples; test at trial level.
- Confusion of displayed vs raw: compare `prediction_presented.predicted_finger` with the raw prediction consumed at the same tick. That is the last `prediction_received` with `prediction_timestamp` equal to the presented row's `prediction_timestamp`.
- Decoder throughput: count `prediction_received` per trial / feedback-window length. Expect about 10/s for a 100 ms hop.

**Sanity checks to run on a dataset**

1. `plan.csv` balance: each run has `trialsPerRun/k` of each finger, and the seed matches `random_seed`.
2. `trialdata.csv` row count = planned trials for a complete session (`session.csv:CompletedTrials`). `end_reason` is all `completed`. `trial_duration − nominal` lies in [0, ~2 frames].
3. Consecutive `trial_start − previous trial_end` ≈ ITI (+ ≤1 frame).
4. Hardware marker sequence in `events.csv` follows `[10,(cue,60)×N,11]×R`, all `trigger_delivered==1`, with consecutive marker gaps ≥0.3 s except cue→60.
5. EEG marker edges are equal in count and order to delivered markers. Fit residuals of `seq` vs `event_timestamp` are small, a few samples at most.
6. Offline sessions contain no `prediction_presented` rows. Online sessions have presented ticks ≥`interval` apart (`check_session.py` reports this range), and no prediction rows outside `[cue_onset, trial_end)`.
7. `simulation==0` for real data. `session.csv:PredictionSource` and `settings.json` match the intended protocol, especially Prediction Source, smoothing flags and the EMG32 mapping.
8. `session.csv:LastEvent` is `session_complete`. `session_aborted` indicates an abort or failure: check for a missing final trial row and missing 60/11 markers.
9. For each prediction source, check confidence range and NaN fraction. BciCoreMl confidence is not validated.

Tool: `python3 Assets/Games/FingerDecoding/Tools/check_session.py <folder>/events.csv` checks balance, durations, presentation intervals and correctness labels.

---

## 14. Known caveats / doc discrepancies

**Effective defaults / settings**

1. **Prediction Source default**: the prefab stores `predictionSource: 0` = `Simulation` (`FingerDecoding.prefab:69`), while the code initializer is `Emg32EegNet` (`FingerExperimentController.cs:54`). The README's "New configurations default to Emg32EegNet" is false for the launcher. Fresh installs and "Reset all" give Simulation. Always check `session.csv:PredictionSource` and `simulation`.
2. The prefab is stale. It lacks `runPauseDuration`, `handScale`, `markerSeparationSeconds`, the four smoothing fields and the EMG32 mapping, which therefore take C# initializers. It still contains removed keys (`enableOfflineFeedback`, `simulationPattern`, `manualPredictedFinger`).
3. `dataFolderName` → `fingerDataFolderName` is migrated only for Unity YAML (`FormerlySerializedAs`). Old PlayerPrefs JSON with `dataFolderName` is ignored by `JsonUtility`, so a previously customised folder silently reverts to `FingerDecodingData`.
4. Common "Use fixed random seed" binds to Finger but Common "Fixed random seed" does not (Finger's field is `randomSeed`, alias `fixedRandomSeed`).
5. Hand scale limits disagree: launcher `[Range(.5,1.2)]`, controller check (0,1.5], README "0 and 1.5". The rendered scale is also halved (`×0.5`).
6. README says prediction intervals below 0.1 are "clamped". Validation actually rejects them, and the clamp is redundant.
7. `ConfigureSharedLaunch` substitutes `"000"` for a blank session, while the field initializer is `"001"` (`:104`, `:114`). The launcher blocks blanks anyway.
8. Validation of the EMG32 two-class mapping and the BciCore requirement applies only in **Online** mode. Offline + Emg32EegNet + UsbBiosemi passes, but the BciServer never starts and no predictions arrive.
9. `onlineFeedbackStart < onlineTrialDuration` is enforced even in Offline mode.
10. Cycling Number Of Classes in the launcher tab does not apply the class preset (only the in-game screen and Inspector do).

**Logging / markers**

11. `Fail()` paths (acquisition lost, app paused, UDP socket error) write only `session_aborted` (code 0). There is **no 60 or 11 marker** and **no `trialdata.csv` row** for the interrupted trial. README implies clean partial files.
12. `Fail()` is guarded only against `Phase.Exporting`, not `Phase.Aborting`. A disconnect during the abort coroutine can start a second `Finish`, and the abort's remaining events are then dropped because the logger is null.
13. `RejectedPackets` (invalid UDP/EMG32 packets, queue overflow) is never logged. Predictions with the wrong ME/MI range, an unselected finger, arrival outside `[onset, endDeadline)`, arrival during ITI or lead-in, or arrival in the trial's final frame are dropped **without any row**.
14. `BciCoreMl` confidence is not validated and its `source_timestamp` is a bare seq number. `Emg32EegNet` uses `seq=…;latency_ms=…`. UDP stamps are arbitrary.
15. Run-level events carry stale prediction columns from the previous trial. `iti_*`/`session_*` rows carry the previous cue. `run_pause_*` rows already have the next run number.
16. `scheduled_timestamp` quirks: `run_pause_end` = planned deadline even when tapped early (scheduled > event). `session_complete` = the last trial's `itiDeadline` (meaningless).
17. `trial_aborted`'s `trial_end` time is when the marker was sent (up to `markerGap` after the abort), not when the screen blanked.
18. Cue→60 spacing equals the trial duration, which validation allows down to 0.1 s. Below 0.3 s the board latch can overwrite the cue marker.
19. `trigger_delivered` means "written to socket", not "latched by the board". Confirm with RAW marker edges.
20. Health `trigger_sent` rows use the name `finger_<code>` for every code, including 10/11/60. `wall_sec` has 1 s resolution in local time.
21. `events.csv`/`trace.csv` are flushed only at trial end, on failure and on dispose.
22. `settings.json:randomSeed` is not the used seed when `useFixedRandomSeed=false`. Use the `random_seed` column.

**Docs**

23. `Assets/Games/FingerDecoding/Documentation/Examples/*.csv` were produced by an older version: `run_start` and the first `cue_on` share a timestamp (no 0.3 s lead-in), and predictions are presented 0.1 s after onset (no 1 s feedback delay). They are not representative of current output.
24. Guide.md line references to Unity sources are stale (e.g. "FingerExperimentController.cs, line 150" for `Start`, which is now line 169). Its `GameModule.cs, line 41` is now `Launch` at line 78.
25. README says Escape "stops a trial or ITI". It also exits from the settings screen to the launcher at any time. README says "ITI completely blank" (true), but the Abort button is also hidden during ITI, lead-in and holds (only Escape works there).
26. README numbering skips item 7. README `check_session.py <csv-path>` expects `events.csv` specifically.
27. `FingerDeviceCheck` is compiled only for development builds, but both Finger build menus use `BuildOptions.Development`, so it is present in those APKs (it runs only if the request file exists).
28. The EMG32 path is documented as not physically validated (README; Guide.md §2: checked-out firmware has EEGNet disabled). Treat Emg32EegNet data as requiring the validation in EightChannel-Validation-Checklist.md.

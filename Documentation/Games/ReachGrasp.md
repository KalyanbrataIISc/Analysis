# Reach & Grasp — Cup vs Spoon

Data-collection task (no classifier, no neurofeedback). Verified against the code at commit `af3b034`.
Shared clocks, BciCore server, EEG file formats and trigger transports are described in
[00-Shared-Infrastructure.md](00-Shared-Infrastructure.md). This page covers only how Reach & Grasp uses them.

Path abbreviations used in citations:

| Short | Full path |
| --- | --- |
| `Ctrl` | `Assets/Games/ReachGrasp/Scripts/ReachGraspGameController.cs` |
| `Log` | `Assets/Games/ReachGrasp/Scripts/ReachGraspSessionLog.cs` |
| `Design` | `Assets/Games/ReachGrasp/Scripts/ReachGraspDesign.cs` |
| `View` | `Assets/Games/ReachGrasp/Scripts/ReachGraspView.cs` |
| `Prefab` | `Assets/Games/ReachGrasp/Prefabs/ReachGraspGame.prefab` |

---

## 1. Overview & paradigm

- **What the participant sees.** A dark screen. Each trial shows a sequence of static photographs of a right hand
  with a **cup** or a **spoon**: *Hold* (hand holding object on table), *Lift* (object lifted), *Place* (hand holding
  object on table again — same picture as Hold), *Rest* (resting-hand picture). A heading names object and phase
  (e.g. `CUP - HOLD`, `SPOON - LIFT`, `REST`). After the cues a white `+` fixation cross is shown for the
  inter-trial interval (ITI) with the caption `Relax` (`Ctrl:428-435`).
- **What the participant does.**
  - `MotorExecution` (ME, default): perform the pictured movement with the right hand on a real cup/spoon.
  - `MotorImagery` (MI): imagine the pictured movement, keep the hand still (instruction text `Ctrl:421-424`).
- **Mode.** `OneCycle` (default): Hold 1.5 s → Lift 1 s → Place 1.5 s → Rest 1 s. `TwoCycles`: Hold 0.5 → Lift 1 →
  Place 0.5 → Rest 0.5, repeated twice. Both default to 5 s of cues per trial (`Design:24-46`).
- **Purpose.** Collect EEG for two-class (cup vs spoon) grasp decoding under ME or MI, with phase-locked event
  markers. Ported from Roshni's MATLAB `CupSpoon` protocol and images (`Assets/Games/ReachGrasp/Art/PROVENANCE.md`).
- **Correct-response / success rule.** None. There is no response, no accuracy, no feedback, no classifier
  (`Summary.classificationEnabled=false`, `Ctrl:108`; `timing-readme.txt`, `Log:27-28`). A trial "succeeds" only in
  the technical sense: `EndReason=completed` and `TimingValid=True` (Section 8).

## 2. Code map

| File | Class / type | Role |
| --- | --- | --- |
| `Scripts/ReachGraspGameController.cs` | `ReachGraspGameController : MonoBehaviour, IGameSession` | Settings, state machine, scheduling, acquisition, markers, export, summary UI text |
| `Scripts/ReachGraspDesign.cs` | `ReachGraspDesign` (static), enums `MovementCondition`, `MovementCycle`, `ObjectCue`, `MovementPhase`, `RecordingSource`, struct `PhaseDefinition` | Pure design: phase table, balanced object sequence, marker code formula |
| `Scripts/ReachGraspSessionLog.cs` | `ReachGraspSessionLog` | Task directory, `events.csv`, `trialdata.csv`, `cueframes.csv`, `settings.json`, `session.json`, `timing-readme.txt` |
| `Scripts/ReachGraspView.cs` | `ReachGraspView` | IMGUI drawing (background, text, cue image, fixation, Stop/advance buttons) |
| `Scripts/ReachGraspGameModule.cs` | `ReachGraspGameModule : GameModule` | **Launcher module class**; delegates `ValidateSettings` to the disabled controller template |
| `Editor/ReachGraspInstaller.cs` | `ReachGraspInstaller` | Menu `CogLab/Reach & Grasp/Register game`: texture import settings, prefab creation, scene registration |
| `Tests/Editor/ReachGraspTests.cs` | `ReachGraspTests` | EditMode tests (phase tables, marker codes, balancing, seed reproducibility, prefab defaults, export checks) |
| `Art/*.png` | — | 5 cue images (see Section 6) |
| `Art/LiberationSans*`, `Art/Shaders/*`, `Art/CollectionFont.asset`, `Resources/TMP Settings.asset` | — | TextMeshPro assets; **not referenced by any current script** (Section 14) |

| Item | Value | Source |
| --- | --- | --- |
| Runtime assembly | `CogLab.Games.ReachGrasp` (refs `CogLab.Framework`, `CogLab.Shared`, `BciCore`, `Unity.InputSystem`) | `Assets/Games/ReachGrasp/CogLab.Games.ReachGrasp.asmdef` |
| Editor / test assemblies | `CogLab.Games.ReachGrasp.Editor`, `CogLab.Games.ReachGrasp.Tests` | `Editor/*.asmdef`, `Tests/Editor/*.asmdef` |
| Namespace | `ReachGraspGame` | all scripts |
| Prefab | `Assets/Games/ReachGrasp/Prefabs/ReachGraspGame.prefab` (controller **disabled**, module enabled) | `Prefab:43,103` |
| Game ID | `reach-grasp` | `Prefab:109` |
| Display name | `Reach & Grasp` | `Prefab:110` |
| Launcher colour | (0.63, 0.39, 0.18) | `Prefab:111` |
| PlayerPrefs key | `CogLab.Games.reach-grasp.v1` | `Assets/CogLab/Framework/GameModule.cs:29` |
| Scene registration | Instance under `Games` in `Assets/CogLab/App/Scenes/CogLab.unity` | `Editor/ReachGraspInstaller.cs:47-57` |

Launch path: launcher `Launch()` → `BciServer.SetSessionIdentity(participant, session, "reach-grasp")`
(`Assets/CogLab/App/CogLabAppController.cs:688-710`) → `GameModule.Launch` copies the template's settings (JSON, minus
texture references, which are copied by reference) into a fresh runtime controller and calls
`ConfigureSharedLaunch(participant, session, eegLoggingMode, callback)` before `Start` (`GameModule.cs:78-120`,
`Ctrl:114-115`).

## 3. Session flow / state machine

`enum Stage { Calibration, Connecting, Instructions, RunReady, Task, Iti, Break, Exporting, Summary, Error }` (`Ctrl:18`).
`Error` is declared but **never assigned**; failures go through `Exporting` → `Summary`.

```
                 BciCore source                         UsbBiosemi source
 Start() ──► Calibration (shared raw/FFT GUI)     Start() ──► Connecting (wait ≤ acquisitionTimeoutSec)
              │ Proceed (guarded)  │ Back / Stop&Export         │ connected, or requireEegConnection=false
              ▼                    ▼                            ▼         timeout ─► Fail(connection_timeout)
          Instructions ◄──────────────────────────────────── Instructions
              │ Continue / Space / Enter
              ▼
          RunReady (run = 1)  ──Start run──►  [run_start 10]  ──► Task ─► Iti ─► Task ─► ... (2×trialsPerObjectPerRun trials)
              ▲                                                                 │ last trial of run: [run_end 11]
              │ Continue (enabled after betweenRunBreakSec), run++              ▼
              └──────────────────────────────────────────────────────────── Break
                                                    after last run: StopAndExport("completed")
 any StopAndExport / Fail ──► [task_abort 60 if in Task] [run_end 11 if run open] [experiment_end 15]
                              ──► stop BciServer ──► Exporting (EEG bin→csv if BinaryThenCsv; CSV verification)
                              ──► Summary ("Back to games" if export ok, else "Retry export")
```

### Transitions in detail

| From | Trigger | To / effect | Source |
| --- | --- | --- | --- |
| `Start()` | settings invalid or exception | `Fail("setup_error: …")` | `Ctrl:151,177` |
| `Start()` (BciCore) | always | starts `BciServer` (ports 5005/5006, logging per launcher policy), subscribes `OnHello`/`OnMarker`, opens `BciCalibration` with readiness guard | `Ctrl:161-171` |
| `Start()` (UsbBiosemi) | always | `new UsbBiosemiLink(biosemiBridgePort, resetCode 0)`, deadline = now + `acquisitionTimeoutSec` | `Ctrl:174` |
| Calibration | *Proceed to Game* pressed and `CalibrationBlockReason()` is null | destroy calibration, `ExitCalibrationMode`, → Instructions | `Ctrl:224-228` |
| Calibration | *Proceed* while blocked | stays; Proceed button disabled and shows `Waiting for EEG`; footer explains reason | `Ctrl:216-223`, `CalibrationScreen.cs:1679-1770` |
| Calibration | *Back* | `StopAndExport("calibration_back")`, automatically returns to launcher after a successful export | `Ctrl:203-207,250-254` |
| Calibration | *Stop & Export* | `StopAndExport("calibration_stop")` → Summary | `Ctrl:170` |
| Connecting | `usb.IsConnected` or `!requireEegConnection` | → Instructions | `Ctrl:264-266` |
| Connecting | now ≥ deadline | `Fail("connection_timeout: Biosemi bridge was not connected.")` | `Ctrl:267` |
| Instructions | Continue / Space / Enter | → RunReady, `run=1` | `Ctrl:309` |
| RunReady | Start run / Space / Enter | if EEG required and not ready → `Fail("acquisition_not_ready")` (**aborts the session**); else build run sequence, emit `run_start`, start trial 1 | `Ctrl:310-315` |
| Task | phase deadlines (Section 4) | next phase, or → Iti with `task_end`+`iti_onset` | `Ctrl:275-291` |
| Iti | now ≥ itiEnd | write trial row; next trial, or `run_end` → Break, or after last run `StopAndExport("completed")` | `Ctrl:293-303` |
| Break | Continue / Space / Enter, only when now ≥ breakEnd | `run++`, → RunReady (a second tap "Start run" is needed) | `Ctrl:316` |
| Exporting | export task finished | → Summary; `exportComplete = (exportError=="")` | `Ctrl:241-257` |
| Summary | *Back to games* / Space / Enter (export ok) | dispose log, return to launcher | `Ctrl:317,399-402` |
| Summary | *Retry export* (button only) | → Exporting again | `Ctrl:392-393,448-450` |

### Fatal / abort conditions (all call `Fail(reason)` → `StopAndExport(reason)`; reason becomes `endReason`)

| Reason string | Condition | Checked in stages | Source |
| --- | --- | --- | --- |
| `setup_error: <msg>` | invalid settings / exception in `Start` | Start | `Ctrl:177` |
| `connection_timeout: …` | USB bridge not connected within `acquisitionTimeoutSec` (15 s) | Connecting | `Ctrl:267` |
| `acquisition_disconnected` | `requireEegConnection` and not `Connected` (BciCore: `BciServer.State != Connected`; USB: `!usb.IsConnected`) | RunReady, Task, Iti, Break | `Ctrl:269-270,192` |
| `eeg_data_stalled` | BciCore, `requireEegConnection`, `BciServer.SecondsSinceLastEegSample > eegDataStallTimeoutSec` (3 s) | RunReady, Task, Iti, Break | `Ctrl:271-272` |
| `bridge_error: <msg>` | USB link reports an error (disconnect or failed marker write) | any except Summary/Error | `Ctrl:273-274` |
| `acquisition_not_ready` | Start run pressed while not connected / no samples / stalled | RunReady (on Advance) | `Ctrl:312` |
| `timing_overrun: a complete cue phase was missed.` | at a phase boundary, `now` is already past the **end** of the next phase | Task | `Ctrl:282` |
| `application_paused` | `OnApplicationPause(true)` | Task, Iti only | `Ctrl:404` |
| `runtime_error: <msg>` | exception in `Tick` | any | `Ctrl:232` |
| `operator_stop` | Escape key, or touch *Stop & export* tapped twice within 4 s | any except Exporting/Summary | `Ctrl:148,260`, `View:81-91` |
| `calibration_stop`, `calibration_back` | calibration-screen buttons | Calibration | `Ctrl:170,206` |
| `application_quit` | `OnApplicationQuit` while not exporting/summary | any | `Ctrl:405` |
| `runtime_destroyed` | object destroyed without export (no markers, no EEG export; trial row and session.json written) | any | `Ctrl:406-413` |
| `completed` | all runs finished | Iti | `Ctrl:299` |

Instructions stage has **no** connection/stall check (`Ctrl:269-272` list RunReady/Task/Iti/Break only).

### Escape / exit behaviour

- Keyboard (only when `keyboardAdvanceEnabled`, `Ctrl:258-262`): **Escape** → `StopAndExport("operator_stop")` in any
  stage except Summary/Error (Exporting returns earlier, so Escape is ignored there). **Space/Enter** → `Advance()`.
  With `keyboardAdvanceEnabled=false`, Escape also does nothing.
- Touch: *Stop & export* (bottom-left, red) is visible in every stage except Exporting and Summary, including during
  trials; first tap changes label to *Confirm stop & export* for 4 s (`View:81-91`).
- Only one UI action is queued per frame (`pendingAction ??= action`, `Ctrl:209`).
- After any stop, the session goes to Summary; the operator returns to the launcher with *Back to games* only after a
  successful export (except `calibration_back`, which returns automatically). If export keeps failing, the only
  way out of Summary is a successful *Retry export*.
- On return the launcher restores 120 Hz / VSync 1, `runInBackground` and sleep timeout
  (`CogLabAppController.cs:717-729`).

### Export (`Ctrl:349-391`)

1. `StopAndExport`: close calibration; if a trial is active: emit `task_abort` (code = `taskEndCode`, only if in
   Task) and write its trial row; `EndRun()` (emits `run_end` if a run is open); emit `experiment_end`; capture EEG
   directory; **`BciServer.StopServer()` immediately**; dispose markers; unsubscribe; → Exporting; flush; save
   `session.json`.
2. `ExportEegAsync`: if BciCore and `BinaryThenCsv`, convert every directory in `eegDirectories` with
   `BinToCsvConverter.ConvertSessionAsync(path, propagateErrors:true)`; then `VerifySavedCsvFiles` on a worker thread.
3. `VerifySavedCsvFiles`: counts lines of every `*.csv` under the task directory and the EEG directories.
   Throws (→ `exportError`, Retry offered) if `trialdata.csv` data rows ≠ trials started (when > 0), or if BciCore
   logging is enabled, no `*_signals.csv`/`*_raw.csv` has ≥ 1 data row, and (samples were received, or trials were
   started with EEG required).
4. Results are saved in `session.json.csvFiles`.

## 4. Trial structure & timing

### Phase table (`Design:24-46`, built once in `Start`, `Ctrl:117,152`)

Onsets are cumulative sums of durations; `TaskDuration = last.Onset + last.Duration`.

| Mode | # | Phase | Cycle | Default duration (s) | Planned onset (s) | Setting |
| --- | --- | --- | --- | --- | --- | --- |
| OneCycle | 1 | Hold | 1 | 1.5 | 0 | `oneCycleHoldSec` |
| | 2 | Lift | 1 | 1.0 | 1.5 | `oneCycleLiftSec` |
| | 3 | Place | 1 | 1.5 | 2.5 | `oneCyclePlaceSec` |
| | 4 | Rest | 1 | 1.0 | 4.0 | `oneCycleRestSec` |
| TwoCycles | 1–4 | Hold, Lift, Place, Rest | 1 | 0.5, 1.0, 0.5, 0.5 | 0, 0.5, 1.5, 2.0 | `twoCycle*Sec` |
| | 5–8 | Hold, Lift, Place, Rest | 2 | 0.5, 1.0, 0.5, 0.5 | 2.5, 3.0, 4.0, 4.5 | same fields (per cycle) |

Task duration: 5.0 s in both default modes. ITI (`interTrialRestSec`) 2.0 s. Nominal trial period 7.0 s.

### Timeline of one trial (OneCycle defaults, ME, cup)

```
t (s, from trialAnchor)  0          1.5        2.5          4.0        5.0                    ≥7.0
display                  |CUP-HOLD  |CUP-LIFT  |CUP-PLACE   |REST      |  +  (fixation, "Relax") |next trial
image                    cup on tbl  cup lifted cup on tbl   rest hand   none
marker (BciCore/USB)     21         81         91           51         60,70 (same frame)      21/24 ...
events.csv               phase_onset×4 (PlannedElapsedSec 0,1.5,2.5,4)  task_end, iti_onset (5)
trialdata.csv                                                                                  row written here
cueframes.csv            one row per Unity frame  ........................................... (Phase=ITI)
```

### Scheduling rules (seconds-based, evaluated once per Unity `Update`)

All times are `MonotonicClock.Now` sampled at the start of `Tick` (`Ctrl:240`); scheduling is absolute relative to
`trialAnchor`, so lateness does not accumulate within a trial.

- **Trial start** (`StartTrial`, `Ctrl:319-323`): `trialAnchor = now`; phase 0 is shown immediately (lateness 0).
  `now` is `MonotonicClock.Now` from `Advance()` for the first trial of a run, or the ITI-ending `Tick` time otherwise.
- **Phase advance** (`Ctrl:277-284`): when `now ≥ trialAnchor + onset_i + duration_i`, move to phase i+1. If `now` is
  already ≥ end of phase i+1, the session fails with `timing_overrun` (one phase per frame at most).
- **Phase lateness** (`Ctrl:326`): `late = max(0, now − trialAnchor − onset)`; logged in `events.csv` `Detail`
  (`latenessSec=<R-format>`); `peakLateness = max(...)`; `timingValid &= late ≤ phaseLatenessToleranceSec` (25 ms).
- **Task end** (`Ctrl:285-290`): when the last phase's deadline passes, `taskEnd = now`,
  `late = now − (trialAnchor + taskDuration)` also enters `peakLateness`/`timingValid`; stage → Iti;
  `task_end` (60) then `iti_onset` (70) emitted back-to-back.
- **ITI** (`Ctrl:289,293-303`): `itiEnd = taskEnd + interTrialRestSec` (measured from the *actual* task end), so
  ITI ≥ configured value; the trial row is written when `now ≥ itiEnd`, and the next trial starts in the same `Tick`
  (`TaskStart(n+1) == TrialEnd(n)` exactly).
- **What ends a trial**: completion of the ITI (`EndReason=completed`), or any stop/fail (EndReason = stop reason;
  `TaskEndCpuMonotonicSec` is NaN if the task part did not finish).
- **Between runs**: `breakEnd = now + betweenRunBreakSec` (20 s); Continue is disabled until then, then *Start run*
  (operator-paced, unbounded).
- **Timing quantisation**: phase onsets are detected at frame granularity (≈ 8.3 ms at 120 Hz). Observed on the
  2026-10-27 tablet session: max CPU phase lateness 10.6 ms, min ITI 2.000004 s
  (`output/reach-grasp/tablet-fix/VALIDATION.md`).
- **No timeouts / no feedback**: trials do not wait for any input.

Nominal session length (defaults): 8 runs × 20 trials × 7 s = 1120 s plus ≥ 7 × 20 s breaks plus operator time
(≈ 22 min observed: 1303.7 s from first `run_start` to `experiment_end` on the tablet run).

## 5. Trial planning / randomisation

- **Conditions**: object ∈ {Cup (class 1), Spoon (class 4)} — the only within-session factor. Condition (ME/MI) and
  mode (OneCycle/TwoCycles) are fixed for the whole session.
- **Per run**: exactly `trialsPerObjectPerRun` cups and spoons (default 10 + 10 = 20 trials); `numberOfRuns` runs
  (default 8) → 160 trials, 80 per class. Each run is balanced on its own.
- **Algorithm** (`Design:48-73`), called once at each *Start run* (`Ctrl:313`) with the session's single
  `System.Random`:
  - For each position, compute whether Cup / Spoon is still *feasible*: remaining count > 0, resulting streak ≤
    `maximumConsecutiveObjects` (3), and the remaining items can still be arranged without breaking the limit
    (`own−1 ≤ (other+1)·max − nextStreak` and `other ≤ own·max`).
  - If only one is feasible it is chosen **without consuming a random number**; otherwise
    `random.Next(cup+spoon) < cup ? Cup : Spoon` (probability proportional to remaining counts).
  - The result is a constrained, weighted draw — not uniform over all valid sequences.
- **Seeding** (`Ctrl:153`): `seed = collectionUseFixedSeed ? collectionRandomSeed (918273) :
  unchecked(Environment.TickCount*397 ^ Guid.NewGuid().GetHashCode())`. The realised seed is always stored in
  `session.json.seed`.
- **Reproducibility**: the k-th run's order is the k-th `BuildSequence` call on `new System.Random(seed)`. To
  regenerate offline, port .NET's legacy seeded `System.Random` (Knuth subtractive generator) exactly, or run
  `ReachGraspDesign.BuildSequence` in C#. Tests verify balance, streak limit and same-seed equality
  (`Tests/Editor/ReachGraspTests.cs:35-48`). The realised order is in `trialdata.csv` anyway.

## 6. Stimulus

All drawing is IMGUI in `OnGUI` (`Ctrl:211-215`, `View:45-119`); the task GUI is hidden while the calibration screen
is open. Coordinates are fractions of `Screen.safeArea` (top-left origin):
`Region(x,y,w,h) = (safe.x + x·W, safe.y + y·H, w·W, h·H)`; font scale
`s = clamp(min(W/1280, H/800), 0.65, 2)` (`View:55-59`).

| Element | Region (x, y, w, h) | Content / size | Source |
| --- | --- | --- | --- |
| Background | full screen | `collectionBackground` = (0.07, 0.08, 0.10, 1) | `View:66-67`, `Prefab:78` |
| Progress line | (.04, .03, .92, .06) | `Run r / R | Trials completed: c / (R·2·N)`; 20·s pt | `View:70`, `Ctrl:417` |
| Heading | (.04, .10, .92, .11) | bold 38·s pt; `CUP - HOLD`, `SPOON - LIFT`, `REST`, empty during ITI | `View:71`, `Ctrl:431` |
| Body | (.05, .22, .90, .55) | 29·s pt; empty during trials | `View:72` |
| Cue image | ((1−cw)/2, .75−ch, cw, ch); defaults → (.10, .29, .80, .46) | `ScaleMode.ScaleToFit`, alpha-blended, aspect preserved, centred in the box | `View:73-74` |
| Fixation | (.35, .37, .30, .25) | `+`, 80·s pt, text colour | `View:75-76` |
| Caption | (.04, .76, .92, .08) | 23·s pt; `Trial t / 20 | Use your right hand` (ME) or `… | Imagine; keep your hand still` (MI); `Relax` in ITI | `View:77`, `Ctrl:433,435` |
| Buttons | Stop (.04, .86, .42, .10); advance (.54, .86, .42, .10) | Stop shown in all stages but Exporting/Summary; advance only when it has a label | `View:79-102` |

Text colour (0.93, 0.95, 0.97). Fonts are IMGUI defaults; `ResponsiveGui.FitStyle` may shrink text to fit.

**Image per phase** (`Ctrl:432`):

| Phase | Cup | Spoon | Pixel size of source PNG |
| --- | --- | --- | --- |
| Hold | `HoldingCupHandleOnTable.png` | `HoldingSpoonOnTable.png` | 1821×864 / 1536×1024 |
| Lift | `LiftingCupup.png` | `LiftingSpoonUp.png` | 1448×1086 / 1536×1024 |
| Place | same as Hold | same as Hold | — |
| Rest | `RestHand.png` | `RestHand.png` | **20×34** (upscaled, bilinear) |
| ITI | none (fixation `+`) | none | — |

Example: 1280×800 landscape with defaults → box 1024×368 px at y = 232–600; cup-on-table (aspect 2.11) is drawn
≈ 776×368 px.

Textures: sRGB, no mipmaps, bilinear, uncompressed (default platform), max 2048, alpha-is-transparency
(`Editor/ReachGraspInstaller.cs:19-24`, `Art/*.png.meta`). Project colour space is **Linear**
(`ProjectSettings/ProjectSettings.asset:50`, `m_ActiveColorSpace: 1`); the IMGUI colour values above are the
serialized values — the exact displayed 8-bit value was not measured (≈ sRGB (18, 20, 26) if interpreted as
gamma-space values).

**Flicker / SSVEP**: none. Images are static; no flicker formula, no phase origin (`Log:28`).
**Motion**: none. **Feedback visuals**: none.

Display pacing: `DisplayRateManager.ApplyPresentation(collectionDisplayRateHz=120, collectionVsyncCount=1)` and
`RequestAndroidDisplayRefreshRate(120)` (`Ctrl:159`). On Android `ApplyPresentation` forces
`QualitySettings.vSyncCount = 0` and uses `targetFrameRate`, so `collectionVsyncCount` only matters on desktop
(`Assets/CogLab/Shared/Display/DisplayRateManager.cs:99-114`). The global display-telemetry overlay
(Common setting *Show Display Telemetry*) draws on top of this game if enabled.

## 7. Neurofeedback

**Not applicable.** The game reads no NF channel, uses no `INfPairReader` / `BciCoreNfReader`, and does not consume
`OnNfSample`. In UsbBiosemi mode the shared `UsbBiosemiLink` still reads 24-byte NF records from the bridge if sent
(and replies `R <sampleCount>`), but the game never calls `TryRead`, and readiness uses `IsConnected` only
(`Assets/CogLab/Shared/Bci/UsbBiosemiLink.cs:39-41,65-74`). BciCore `features.csv` may still contain NF/CCA frames
if the board sends them; they are not used by the task. Only stall handling of the **EEG sample stream** exists
(Section 3, `eeg_data_stalled`).

## 8. Responses & scoring

- **Participant inputs**: none are recorded. Movement execution is not measured (no EMG/motion sensor, no
  classifier).
- **Operator inputs**: Continue / Start run / Stop & export buttons; Space/Enter (advance), Escape (stop) when
  `keyboardAdvanceEnabled`. They are not logged as events, except indirectly (`run_start`, stop reason).
- **Accuracy / RT**: not applicable — no correct response, no reaction time, no clock origin for RT.
- **Per-trial quality metrics** (in `trialdata.csv`): `TimingValid` = all phase-onset and task-end lateness
  ≤ `phaseLatenessToleranceSec` **and** `EndReason == completed` (`Ctrl:334`); `PeakPhaseLatenessSec`; measured ITI
  = `TrialEndCpuMonotonicSec − TaskEndCpuMonotonicSec`; EEG samples received during the trial
  = `ProcessedSamplesAtEnd − ProcessedSamplesAtStart` (+ raw).

## 9. Event markers / triggers

### Code formula (`Design:75-82`, bases from settings)

`code = base(phase, cycle, condition) + ObjectCue` with `Cup = 1`, `Spoon = 4`:

| Event (`events.csv` `Event`) | Name in health.csv | Code (Cup / Spoon) | Exact moment emitted | Condition | Source |
| --- | --- | --- | --- | --- | --- |
| `run_start` | `trigger_sent:run_start` | 10 | *Start run* accepted, immediately before trial 1's Hold (same Unity frame, ~2 ms earlier) | every run | `Ctrl:314` |
| `phase_onset` Hold cycle 1, ME | `trigger_sent:phase_onset` | 21 / 24 | `Update` in which the phase starts, after the view state is updated, before that frame is rendered | ME | `Ctrl:322-329` |
| `phase_onset` Hold cycle 1, MI | same | 31 / 34 | same | MI | same |
| `phase_onset` Hold cycle 2 | same | 41 / 44 | same | TwoCycles only, **both ME and MI** | `Design:78-79` |
| `phase_onset` Lift | same | 81 / 84 | same | every cycle | `Design:80` |
| `phase_onset` Place | same | 91 / 94 | same | every cycle | `Design:80` |
| `phase_onset` Rest (in-trial) | same | 51 / 54 | same | every cycle | `Design:80` |
| `task_end` | `trigger_sent:task_end` | 60 | `Update` in which the last phase deadline is passed | every completed task | `Ctrl:288` |
| `iti_onset` | `trigger_sent:iti_onset` | 70 | immediately after `task_end` (same frame, < 1 ms later) | every completed task | `Ctrl:288` |
| `task_abort` | `trigger_sent:task_abort` | **60** (= `taskEndCode`) | on stop/fail while in Task stage | abort during cues | `Ctrl:353` |
| `run_end` | `trigger_sent:run_end` | 11 | after the last trial row of a run is written, or on stop while a run is open | — | `Ctrl:298,336,354` |
| `experiment_end` | `trigger_sent:experiment_end` | 15 | in `StopAndExport`, after `run_end`; **immediately followed by `BciServer.StopServer()`** | always once | `Ctrl:354-358` |
| `marker_echo` (log only) | `marker` | echoed code | main-thread receipt of a board MARKER frame | BciCore | `Ctrl:191` |
| `acquisition_hello` (log only) | — | 0 | board HELLO received (new EEG directory) | BciCore | `Ctrl:179-183` |

Sequence of codes per trial: OneCycle `H L P R 60 70`; TwoCycles `H1 L P R H2 L P R 60 70`, e.g. ME cup TwoCycles
= `21 81 91 51 41 81 91 51 60 70` (`Tests/Editor/ReachGraspTests.cs:23-28`).

### Transport

- **BciCore** (`markers = new BciCoreTriggerSender()`, no UDP fallback, `Ctrl:166`):
  `BciServer.LogTriggerSent(name, code)` (health.csv row `trigger_sent:<name>`) then `BciServer.SendMarker(code)`
  (TCP CMD frame to the board) (`Assets/CogLab/Shared/Bci/BciCoreTriggerSender.cs:25-37`). The board latches the
  code into the `marker` column of subsequent EEG samples and echoes a MARKER frame (→ `OnMarker`). If not
  connected, the send is silently dropped (warning only). `SeparateMarkerEchoesInHealthLog` is left `false`, so
  echoes appear in health.csv with their raw code and event `marker`.
- **UsbBiosemi** (`UsbBiosemiLink`, `127.0.0.1:biosemiBridgePort`): ASCII `"<code>\n"`; `"0\n"` is sent once on
  connect as reset (`UsbBiosemiLink.cs:64,117-143`). A failed write sets `usb.Error` → next frame
  `Fail("bridge_error: …")`. No echoes are logged (`OnMarker` is BciCore-only).
- No UDP trigger is sent in either mode (the Common *UDP trigger port* does not apply).
- The calibration screen's *Reboot* button sends `0xFFFF` directly via `BciServer.SendMarker` (not logged in
  `events.csv`) (`CalibrationScreen.cs:1733-1737`).

### Validation rules (`Ctrl:136-139`)

Every `base+1` and `base+4` for the six bases, plus `taskEndCode`, `itiOnsetCode`, `runStartCode`, `runEndCode`,
`experimentEndCode`, must be in 1–255 and mutually unique; otherwise the game will not launch.

### Observed EEG marker behaviour (BciCore, 2026-10-27 tablet session, `output/reach-grasp/tablet-fix/recordings`)

- The latched code persists ~50 samples (~200 ms at 250 Hz) then the board echoes `0` (568 `marker_echo` rows with
  `Code=0`).
- All 640 `phase_onset` codes appear as marker onsets in `signals.csv`, in the same order as `events.csv`.
- `10` (run start) is visible in only 4/8 runs and `60` (task end) in 104/160 trials: the next code (first Hold, or
  `70`) is sent within ~2 ms and overwrites it in the same or next sample. `70` is visible in 160/160.
- The **final** `11` and `15` never reach the EEG (and are not echoed): the server is stopped right after sending
  them. 7/8 `run_end` codes are visible; `15` 0/1.
- `marker_echo.BoardSampleSeq` equals the echoed code on this firmware (1543/1543 rows); it is **not** a sample
  sequence number (in the October simulator it was).

### Legacy vs shuffled modes

Not applicable (no SSVEP frequency shuffling; marker map is fixed apart from configurable bases).

## 10. Output files

### Locations

| Item | Path pattern | Source |
| --- | --- | --- |
| Task directory | `<root>/p<participant>_s<session>_reachgrasp_<UTC yyyyMMdd_HHmmssfff>_<6 hex>/` | `Log:21-22` |
| `<root>` | `collectionDataFolder` if absolute, else `Application.persistentDataPath/<collectionDataFolder>`; default `BciCoreLogs`; for BciCore a saved value `data` is migrated to `BciCoreLogs` | `Ctrl:154-157` |
| Android `persistentDataPath` | `/storage/emulated/0/Android/data/org.iisc.coglab.games/files` | README |
| EEG directories (BciCore, logging ≠ Disabled) | `Application.persistentDataPath/BciCoreLogs/eeg_reach-grasp_p<P>_s<S>_<local yyyyMMdd_HHmmss>/` — one per board HELLO since server start; absolute paths listed in `session.json.eegDirectories` | `DirectCsvSessionLogger.cs:101-133`, `Ctrl:184-190` |

Participant/session are sanitised to `[A-Za-z0-9_-]`, max 64 chars, `000` if empty (`Log:55-59`). The task
directory is always new (`FileMode.CreateNew`), so there is no append, header-mismatch or schema-versioning logic;
files from older builds may simply have fewer columns (e.g. the 2026-10-27 smoke data lacks the four
`*Samples*` columns of `trialdata.csv`).

All task CSVs: UTF-8 without BOM, comma separated, RFC-4180 quoting when a value contains `,` `"` CR/LF
(`Log:45-54`). Numbers use invariant culture; doubles are written with up to 15 significant digits
(`Convert.ToString`), `NaN` as the literal `NaN`, booleans as `True`/`False`, enums by name.

### `events.csv` (always; flushed at each phase/trial/run boundary) — `Log:23,34-37`, `Ctrl:337-343`

One row per sent marker (`Emit`) and per logged acquisition event (`Record`).

| Column | Meaning | Units / time base | Empty / special |
| --- | --- | --- | --- |
| `Event` | `run_start`, `phase_onset`, `task_end`, `iti_onset`, `task_abort`, `run_end`, `experiment_end`, `marker_echo`, `acquisition_hello` | — | — |
| `Run` | current run (1-based) | — | `0` before the first run |
| `TrialInRun` | trial within run (1-based) if a trial is active | — | `0` outside a trial (run_start/run_end/experiment_end/hello, echoes during breaks) |
| `TrialTotal` | cumulative number of trials **started** so far | — | not reset outside trials (e.g. `run_end` row of run 8 has 160) |
| `Object` | `Cup` / `Spoon` if in trial | — | empty outside trial |
| `Condition` | `MotorExecution` / `MotorImagery` | — | — |
| `Cycle` | cycle (1/2) of the current phase if in trial | — | `0` outside trial; `task_end`/`iti_onset` carry the last phase's cycle |
| `Phase` | in Task stage: `Hold`/`Lift`/`Place`/`Rest`; otherwise the **stage name** at emission (`Calibration`, `RunReady`, `Iti`, `Break`, …) | — | `task_end`, `iti_onset`, `run_end`, final `experiment_end` show `Iti` |
| `Code` | marker code sent (or echoed code; 0 for hello) | — | — |
| `PlannedElapsedSec` | planned onset relative to trialAnchor: phase onset; `TaskDuration` for task_end/iti_onset | s | `NaN` for all other events |
| `CpuMonotonicSec` | `MonotonicClock.Now` at the moment the row was recorded (just after the send call for emitted markers; main-thread dispatch time for echoes) | s, shared monotonic clock (Stopwatch; device uptime origin) | — |
| `TimestampUnixMs` | `unixAnchor + (CpuMonotonicSec − monoAnchor)·1000`; anchors captured once when the log is created | ms since 1970 UTC (mapped, not resampled) | — |
| `PredictedPresentationMonotonicSec` | `PresentationClock.Capture().presentationTime` for the **current Unity frame** (cached; first capture of the frame) | s, same monotonic base | meaningless for `marker_echo` rows |
| `ActualPresentationMonotonicSec` | not measured | — | always `NaN` |
| `UnityFrame` | `Time.frameCount` | frames | — |
| `BoardSampleSeq` | MARKER-frame header `seq` (echo rows only) | firmware-defined | empty for non-echo rows; equals code on current firmware |
| `Detail` | `latenessSec=<R>` for phase_onset (= `now − trialAnchor − onset`, ≥ 0); `EEG channel count=N` for hello | s | empty otherwise |

### `trialdata.csv` (always; one row per started trial, flushed per row) — `Log:24,38-39`, `Ctrl:331-335`

| Column | Meaning | Units / time base | Empty / special |
| --- | --- | --- | --- |
| `Run` | run (1-based) | — | — |
| `TrialInRun` | trial within run (1-based) | — | — |
| `TrialTotal` | session-wide trial index (1-based) — **unique key** | — | — |
| `Object` | `Cup` / `Spoon` | — | — |
| `ClassId` | `1` = Cup, `4` = Spoon (original MATLAB class codes) | — | — |
| `Condition` | `MotorExecution` / `MotorImagery` | — | — |
| `Mode` | `OneCycle` / `TwoCycles` | — | — |
| `TaskDurationSec` | planned cue duration (sum of phases) | s | — |
| `ItiDurationSec` | **configured** `interTrialRestSec` (not measured) | s | — |
| `TaskStartCpuMonotonicSec` | `trialAnchor` = Hold onset scheduling time | s, monotonic | — |
| `TaskEndCpuMonotonicSec` | time the last phase deadline was detected (= `task_end` time base) | s, monotonic | `NaN` if aborted during cues |
| `TrialEndCpuMonotonicSec` | ITI end (completed) or stop time | s, monotonic | — |
| `PeakPhaseLatenessSec` | max lateness of phase onsets and task end | s | 0 if perfect |
| `TimingValid` | all lateness ≤ tolerance **and** EndReason = `completed` | bool | — |
| `EndReason` | `completed` or the stop/fail reason (Section 3) | — | — |
| `RawSamplesAtStart` / `RawSamplesAtEnd` | `BciServer.RawSamplesReceived` at trial start / row write | samples since `StartServer` (all EEG directories) | `-1` for UsbBiosemi |
| `ProcessedSamplesAtStart` / `ProcessedSamplesAtEnd` | `BciServer.ProcessedSamplesReceived` likewise | samples | `-1` for UsbBiosemi |

### `cueframes.csv` (only if `logCueFrames`, default On) — `Log:25,40-41`, `Ctrl:305`

One row per Unity frame while in Task or Iti stage, written at the end of `Tick` (after state changes in that frame).
No row in the frame in which the session stops or a run ends.

| Column | Meaning | Units / time base | Empty / special |
| --- | --- | --- | --- |
| `Run`, `TrialInRun`, `TrialTotal`, `Object` | trial identity | — | — |
| `Phase` | `Hold`/`Lift`/`Place`/`Rest`, or `ITI` (upper-case, unlike `events.csv`'s `Iti`) | — | — |
| `UnityFrame` | `Time.frameCount` | frames | — |
| `CpuMonotonicSec` | `PresentationFrame.sampleTime` = monotonic time of the first `PresentationClock.Capture()` in this frame (often an event `Record` earlier in the same `Tick`) | s, monotonic | — |
| `TimestampUnixMs` | mapped from `CpuMonotonicSec` with the same anchors as events.csv | ms UTC | — |
| `PredictedPresentationMonotonicSec` | predicted vsync time of this frame's lattice slot | s, monotonic | — |
| `ActualPresentationMonotonicSec` | not measured | — | always `NaN` |
| `ClockEpoch` | `PresentationClock` lattice epoch (increments on refresh-rate / native-clock changes) | — | — |
| `ClockSource` | `android_frame_timeline`, `android_choreographer`, `android_extrapolated` (native callback > 0.25 s old), `monotonic_fallback` (editor/desktop) | — | — |

The lattice `slot`, `period`, `androidVsyncId` and uncertainty are **not** logged (contrast with the shared
`FrameStimulusCsvLogger`, which this game does not use).

### `settings.json` (at start) — `Log:26`, `Ctrl:158`

`JsonUtility.ToJson(controller, prettyPrint)` of the running controller: every serialized field. Enums are
**integers** (`movementCondition` 0=MotorExecution 1=MotorImagery; `movementCycle` 0=OneCycle 1=TwoCycles;
`recordingSource` 0=BciCore 1=UsbBiosemi); floats show binary-float noise (e.g. `0.800000011920929`); texture fields
appear as `{"instanceID": N}` (meaningless). Note: `collectionDataFolder` is the raw setting (e.g. `data`), not the
migrated folder.

### `session.json` (rewritten at start, on each HELLO, after each completed trial, at stop and after export) — `Ctrl:104-112,394-398`

| Field | Meaning |
| --- | --- |
| `participant`, `session` | launcher identity (unsanitised) |
| `condition`, `mode`, `recordingSource`, `eegLoggingMode` | enum **names** (`BinaryThenCsv` / `DirectCsv` / `Disabled`) |
| `taskDirectory` | absolute task directory |
| `endReason` | stop/fail reason (empty while running) |
| `exportError` | last export error message (empty on success) |
| `seed` | realised random seed |
| `runsPlanned`, `trialsPerObjectPerRun` | design |
| `trialsStarted`, `trialsCompleted` | counters |
| `requiresEegConnection` | the `requireEegConnection` setting |
| `classificationEnabled` | always `false` |
| `exportComplete` | true after successful export/verification |
| `eegDirectories` | absolute EEG directories created by this session (excludes the previous game's directory) |
| `rawSamplesReceived`, `processedSamplesReceived` | BciCore counters at last save (0 for USB) |
| `csvFiles[]` | `{path, bytes, dataRows}`; task files relative to the task dir, EEG files absolute |

A crash before export leaves `endReason` empty or `runtime_destroyed` and `exportComplete=false`.

### `timing-readme.txt` (at start) — `Log:27-28`

Fixed plain-text explanation of the clocks and marker semantics.

### EEG files (BciCore only; formats in [00-Shared-Infrastructure.md](00-Shared-Infrastructure.md))

Written by the in-process `BciServer`, which this game starts (`Ctrl:165`) with
`enableLogging = (mode ≠ Disabled)`, `directCsvMode = (mode == DirectCsv)`, `participant`, `block = session`.
Recording starts at board HELLO (during calibration) and stops at `StopAndExport`; the EEG therefore contains the
calibration period before the first `run_start`.

| Mode | Files in `eeg_reach-grasp_p<P>_s<S>_<ts>/` |
| --- | --- |
| `DirectCsv` (launcher default) | `<stem>_raw.csv` (`seq,raw<n>…,marker`), `<stem>_signals.csv` (`seq,ch<n>_uv…,marker`), `<stem>_features.csv`, `<stem>_health.csv`, `<stem>_config.txt` |
| `BinaryThenCsv` | `.bin` files + `<stem>_meta.json`, converted at export to CSV (signals header `seq,filt1…filtN,marker`, UTF-8 **with BOM**; health `wall_clock` as `HH:mm:ss`) |
| `Disabled` | none |

Columns the analysis depends on: `seq` (board sample sequence), channel values, `marker` (latched code, 0 = none);
`health.csv` `marker`/`event` (`trigger_sent:<eventName>` rows with `seq=0`; echo rows with event `marker`). A
board that streams only PROC frames yields an empty/absent raw CSV (tablet run: 0 raw, 344,975 processed samples).

UsbBiosemi: no EEG files are written locally; EEG is recorded by the external Biosemi system with the numeric
markers above.

## 11. Settings reference

All fields live in the game's own launcher tab (labels = `Nicify(fieldName)`, `CogLabAppController.cs:223,253-264`)
and are stored in `CogLab.Games.reach-grasp.v1`. Texture fields are Inspector-only and are never saved to or loaded
from PlayerPrefs (`GameModule.cs:46-76`). **Prefab values equal the C# initializers for every field** (`Prefab:48-96`
vs `Ctrl:20-73`).

**Common-tab overrides: none.** No Reach & Grasp field name matches a `SharedSettingsCatalog` alias
(`Assets/CogLab/App/SharedSettingsCatalog.cs:32-48`); a test enforces this (`ReachGraspTests.cs:61-62`). Display rate,
VSync, USB port, timeouts, UDP port, data folder, frame logging, seed and keyboard Common values do **not** affect
this game. From the launcher it receives only participant, session (labelled *Block number*), EEG logging mode,
the return callback, the BciCore `GameName` (`reach-grasp`), and the global display-telemetry overlay toggle.

| UI label | Field | Effective default | Unit / range | Meaning |
| --- | --- | --- | --- | --- |
| *Experiment* | | | | |
| Movement Condition | `movementCondition` | `MotorExecution` (YAML 0) | `MotorExecution`/`MotorImagery` | instructions, captions, Hold code base 20 vs 30 |
| Movement Cycle | `movementCycle` | `OneCycle` (YAML 0) | `OneCycle`/`TwoCycles` | phase table |
| Number Of Runs | `numberOfRuns` | 8 | 1–1000 | runs per session |
| Trials Per Object Per Run | `trialsPerObjectPerRun` | 10 | 1–10000 | cups = spoons per run |
| Maximum Consecutive Objects | `maximumConsecutiveObjects` | 3 | ≥ 1 | max identical objects in a row (within a run) |
| *One cycle timing (seconds)* | | | | |
| One Cycle Hold Sec | `oneCycleHoldSec` | 1.5 | s, ≥ 0.05 | |
| One Cycle Lift Sec | `oneCycleLiftSec` | 1 | s, ≥ 0.05 | |
| One Cycle Place Sec | `oneCyclePlaceSec` | 1.5 | s, ≥ 0.05 | |
| One Cycle Rest Sec | `oneCycleRestSec` | 1 | s, ≥ 0.05 | |
| *Two cycle timing (seconds per cycle)* | | | | |
| Two Cycle Hold Sec | `twoCycleHoldSec` | 0.5 | s, ≥ 0.05 | per cycle |
| Two Cycle Lift Sec | `twoCycleLiftSec` | 1 | s, ≥ 0.05 | |
| Two Cycle Place Sec | `twoCyclePlaceSec` | 0.5 | s, ≥ 0.05 | |
| Two Cycle Rest Sec | `twoCycleRestSec` | 0.5 | s, ≥ 0.05 | |
| *Rest and timing quality* | | | | |
| Inter Trial Rest Sec | `interTrialRestSec` | 2 | s, ≥ 0.05 | minimum fixation ITI after actual task end |
| Between Run Break Sec | `betweenRunBreakSec` | 20 | s, ≥ 0 | minimum break before Continue is enabled |
| Phase Lateness Tolerance Sec | `phaseLatenessToleranceSec` | 0.025 | s, ≥ 0.001 | threshold for `TimingValid` |
| *Acquisition* | | | | |
| Recording Source | `recordingSource` | `BciCore` (YAML 0) | `BciCore`/`UsbBiosemi` | acquisition path |
| Require Eeg Connection | `requireEegConnection` | True (YAML 1) | bool | guards Proceed/Start run and aborts on disconnect/stall |
| Acquisition Port | `acquisitionPort` | 5005 | TCP 1–65535 | BciCore board port |
| Acquisition Fanout Port | `acquisitionFanoutPort` | 5006 | TCP, ≠ acquisitionPort | BciCore fan-out port |
| Biosemi Bridge Port | `biosemiBridgePort` | 5010 | TCP | USB bridge (localhost) |
| Acquisition Timeout Sec | `acquisitionTimeoutSec` | 15 | s, ≥ 1 | USB connect deadline (unused for BciCore) |
| Eeg Data Stall Timeout Sec | `eegDataStallTimeoutSec` | 3 | s, ≥ 0.5 | BciCore sample stall limit |
| *Collection files and randomization* | | | | |
| Collection Data Folder | `collectionDataFolder` | `BciCoreLogs` | path | task-log root (relative to persistentDataPath) |
| Log Cue Frames | `logCueFrames` | True | bool | write `cueframes.csv` |
| Collection Use Fixed Seed | `collectionUseFixedSeed` | False | bool | |
| Collection Random Seed | `collectionRandomSeed` | 918273 | int | used only if fixed |
| *Display and controls* | | | | |
| Collection Display Rate Hz | `collectionDisplayRateHz` | 120 | Hz, 30–240 | target frame rate / Android refresh request |
| Collection Vsync Count | `collectionVsyncCount` | 1 | 0–4 | desktop only |
| Keyboard Advance Enabled | `keyboardAdvanceEnabled` | True | bool | Space/Enter advance, Escape stop |
| Collection Background | `collectionBackground` | (0.07, 0.08, 0.10, 1) | RGBA 0–1 | |
| *Cue appearance* | | | | |
| Cue Width Fraction | `cueWidthFraction` | 0.8 | 0.3–0.95 of safe-area width | |
| Cue Height Fraction | `cueHeightFraction` | 0.46 | 0.2–0.65 of safe-area height | |
| (Inspector only) | `cupOnTable`, `cupLifted`, `spoonOnTable`, `spoonLifted`, `restHand` | the 5 PNGs | Texture2D | all required |
| *Event codes* | | | | |
| Execution Cue Base | `executionCueBase` | 20 | 0–250 | ME first Hold → 21/24 |
| Imagery Cue Base | `imageryCueBase` | 30 | 0–250 | MI first Hold → 31/34 |
| Repeat Hold Base | `repeatHoldBase` | 40 | 0–250 | 2nd-cycle Hold → 41/44 |
| Lift Onset Base | `liftOnsetBase` | 80 | 0–250 | → 81/84 |
| Place Onset Base | `placeOnsetBase` | 90 | 0–250 | → 91/94 |
| Rest Onset Base | `restOnsetBase` | 50 | 0–250 | → 51/54 |
| Task End Code | `taskEndCode` | 60 | 0–255 (validated 1–255) | also used for `task_abort` |
| Iti Onset Code | `itiOnsetCode` | 70 | | |
| Run Start Code | `runStartCode` | 10 | | |
| Run End Code | `runEndCode` | 11 | | |
| Experiment End Code | `experimentEndCode` | 15 | | |

Validation (`Ctrl:118-142`) is run at launch; any failure prevents the game from starting.

## 12. Timing & clock semantics

| Quantity | Clock / origin | Meaning and limits |
| --- | --- | --- |
| `*CpuMonotonicSec`, `CpuMonotonicSec` | `MonotonicClock.Now` = `Stopwatch` seconds; origin = device boot (≈ uptime) | Software scheduling times on the main thread. Resolution sub-µs; values written with ≤ 15 significant digits (≈ 0.1 µs at 10⁶ s). |
| `TimestampUnixMs` | UTC ms, mapped from monotonic via one anchor pair taken when the log was created | Not a separate wall-clock sample; any wall/monotonic drift during the session is not corrected. |
| `PredictedPresentationMonotonicSec` | monotonic; shared VSync lattice (`PresentationClock`) | **Prediction** of the vsync at which the current frame is expected to be presented; anchored to Android Choreographer/FrameTimeline when available. Not a scanout measurement. ~1 frame after the event's CPU time (tablet: ≈ 9.5–14 ms after `phase_onset`). |
| `ActualPresentationMonotonicSec` | — | Always `NaN`. Photodiode-level onset is unknown. |
| `latenessSec`, `PeakPhaseLatenessSec` | difference of monotonic times | CPU detection delay of a phase boundary relative to the absolute schedule; ≥ 0; frame-quantised. |
| EEG `seq` / sample index | board clock (250 Hz nominal) | Not tied to any host clock except through markers. Tablet fit of EEG marker sample index vs `phase_onset.CpuMonotonicSec`: slope 249.68 samples/s (≈ −0.13 % vs nominal), residual SD 1.2 samples, max 11.5 samples. |
| `Raw/ProcessedSamplesAt*` | count of samples received by the host since `StartServer` | Approximate host-time → sample-row map; tablet: Hold onset row − `ProcessedSamplesAtStart` median 4 samples, one outlier of 221. |
| health `wall_clock` / `wall_sec` | local time of day, 1 s resolution | Too coarse for alignment. |

Marker vs display order: in each phase-onset frame the code is sent during `Update`, **before** the frame is rendered
in `OnGUI`, so the EEG marker precedes the earliest possible visual onset by the remainder of the frame plus display
pipeline latency (≥ ~1 frame, unmeasured). Marker transport latency (send → board latch) is also unmeasured; the
echo arrives back at the host ~12 ms after the send on the tablet.

"Dropped frame": not logged or flagged by this game. It can be inferred from `cueframes.csv` as a jump of
`PredictedPresentationMonotonicSec` > 1.5 × median frame period between consecutive rows within one `ClockEpoch`
(`UnityFrame` increments by 1 every rendered frame regardless). A dropped frame delays the *visual* change but not
the schedule; only phase-boundary detection delay is captured by `latenessSec`.

## 13. Analysis guide

### Join keys

- `trialdata.csv` ↔ `events.csv`: `TrialTotal` (unique per session) **and** `TrialInRun > 0` on the event side
  (out-of-trial rows also carry `TrialTotal`). `(Run, TrialInRun)` is an equivalent key.
- `trialdata.csv` ↔ `cueframes.csv`: `TrialTotal`.
- Task directory ↔ EEG: `session.json.eegDirectories` (copy `BciCoreLogs` from the device and use
  `Tools/audit_reach_grasp_session.py <taskdir> --eeg-root <local BciCoreLogs>`).
- Sessions: `session.json.participant`, `session`, `condition`, `mode`, `seed`.

### Aligning EEG markers with CSV rows (BciCore)

1. Load `<stem>_signals.csv` (or `_raw.csv` if the board streamed raw), `encoding='utf-8-sig'`. Sampling rate from
   HELLO / `_config.txt` (250 Hz on the tablet).
2. Marker onsets = rows where `marker != 0` and `marker != previous row's marker`.
3. Keep only **cue codes** {21,24,31,34,41,44,81,84,91,94,51,54} (configurable bases!) and `70`. Do not rely on
   `10`, `60`, or the final `11`/`15` (Section 9).
4. Match cue-code onsets **in order** to `events.csv` rows with `Event == phase_onset` (same `Code` sequence). Assert
   that the code sequences are identical; on the tablet session 640/640 matched.
5. Optionally fit `sample = a + b·CpuMonotonicSec` on matched pairs; use it to place events that have no EEG marker
   (e.g. `experiment_end`, aborts, `cueframes` rows). Check residuals (expect a few samples).
6. Task end per trial: use the `70` onset (or `60` when visible; they are ≤ 1 sample apart).

UsbBiosemi: same procedure on the Biosemi recording's trigger channel; codes are identical.

### Epoching

- Class label: `Object`/`ClassId` from `trialdata.csv` (Cup=1, Spoon=4); the Hold code itself also encodes it
  (`code − base`).
- Reference event: first-cycle Hold onset (21/24 ME, 31/34 MI). Phase windows relative to it (OneCycle defaults):
  Hold [0, 1.5), Lift [1.5, 2.5), Place [2.5, 4.0), Rest [4.0, 5.0), fixation ITI [5.0, ≥ 7.0). TwoCycles: see
  Section 4 table. Use the **actual** settings from `settings.json` (phases can be edited).
- Movement-onset-locked epochs: Lift codes 81/84 (and second-cycle Lift).
- Baseline: the fixation ITI preceding Hold (e.g. [−1.5, −0.2] s). The first trial of every run has **no**
  preceding ITI (it follows the RunReady screen/break) — exclude or treat separately.
- Optionally shift onsets by the per-event `PredictedPresentationMonotonicSec − CpuMonotonicSec` (≈ 1 frame) to
  approximate visual onset; physical display latency remains unknown.

### Performance / quality metrics

- Completion: `trialsCompleted / (numberOfRuns·2·trialsPerObjectPerRun)`; `endReason`.
- Timing: fraction `TimingValid==True`; distribution of `PeakPhaseLatenessSec`; measured ITI
  `TrialEnd − TaskEnd` (≥ `ItiDurationSec`); measured task duration `TaskEnd − TaskStart` (≈ planned + lateness).
- EEG continuity: per-trial `ProcessedSamplesAtEnd − ProcessedSamplesAtStart` ≈ fs × (task + ITI) (tablet min 1743
  ≈ 7 s × 250); `seq` gaps in signals.csv; `pc_gaps`/`board_drops` in health.csv.
- Marker delivery: compare counts of `trigger_sent:*` and `marker` rows in health.csv, `marker_echo` rows in
  events.csv, and EEG marker onsets.
- There is no behavioural accuracy or RT to compute.

### Using frame logs

`cueframes.csv` gives the per-frame visual state. Visual phase onset estimate = `PredictedPresentationMonotonicSec`
of the first row with the new `Phase` within a trial. Frames per trial ≈ 7 s × refresh (tablet ≈ 841 at 120 Hz).

### Sanity checks for a dataset

1. `session.json`: `endReason == completed`, `exportComplete == true`, `trialsStarted == trialsCompleted ==
   runsPlanned·2·trialsPerObjectPerRun`, `eegDirectories` non-empty (BciCore, logging ≠ Disabled).
2. `trialdata.csv`: rows = trialsStarted; per run equal Cup/Spoon counts; max streak ≤ `maximumConsecutiveObjects`;
   `TaskStart(n+1) == TrialEnd(n)` within a run; `EndReason` all `completed`.
3. `events.csv`: `run_start` = `run_end` = runs; `task_end` = `iti_onset` = trials; `experiment_end` = 1;
   `phase_onset` per phase = trials × cycles; `Code` consistent with `Object`/`Condition`/phase formula;
   no `task_abort` in a completed session.
4. Every CSV row has the header's column count; no blank rows.
5. EEG: channels finite and non-constant; cue-code onset count = phase_onset count; sample spacing between Hold and
   Lift onsets ≈ fs × Hold duration (tablet: 376 samples for 1.5 s).
6. `cueframes.csv` `ClockSource` constant (`android_frame_timeline` on the tablet) and `ClockEpoch` constant
   during runs; otherwise inspect presentation timing per epoch.
7. Re-run `Tools/audit_reach_grasp_session.py`.

## 14. Known caveats / doc discrepancies

**Marker / EEG**

1. `task_abort` uses `taskEndCode` (60) — indistinguishable by code from a normal task end; an abort is followed by
   `11`/`15` (often not recorded), a normal end by `70` (`Ctrl:353`).
2. `60` and `70` are sent < 1 ms apart and `10` ~2 ms before the first Hold code; the board's latched marker often
   shows only the later code (tablet: `10` in 4/8 runs, `60` in 104/160 trials). The README notes they "may share
   an EEG sample"; in practice the earlier code is frequently lost entirely.
3. The last `run_end` (11) and `experiment_end` (15) are sent immediately before `BciServer.StopServer()`, so they are
   absent from the EEG and not echoed (`Ctrl:354-358`). README lists 15 as a recorded marker. Markers emitted on
   `acquisition_disconnected` are also lost.
4. `marker_echo.BoardSampleSeq` is not a sample sequence on the current firmware (equals the code); the README and
   column name suggest otherwise.
5. Second-cycle Hold uses 41/44 for both ME and MI; condition is not encoded after the first Hold (constant per
   session anyway).
6. If phase durations are set below ~0.2 s, successive codes will overwrite each other in the EEG marker column
   (observed latch ≈ 200 ms).
7. Calibration *Reboot* sends `0xFFFF` to the board outside the task's logging.

**Flow / robustness**

8. Pressing *Start run* while the EEG is momentarily not ready **aborts the whole session**
   (`Fail("acquisition_not_ready")`, `Ctrl:312`); the README says run start "requires" readiness, implying a block.
9. UsbBiosemi with `requireEegConnection=false` and no bridge: the first marker write fails, sets `usb.Error`, and
   the next frame aborts with `bridge_error` — an unconnected USB rehearsal is not possible (BciCore rehearsal works;
   markers are dropped with a warning).
10. A frame stall longer than one whole phase aborts the session (`timing_overrun`); in TwoCycles defaults that is
    0.5 s. A stall of less than a phase only marks the trial invalid.
11. Stopping during the ITI writes the trial with the stop reason and `TimingValid=False` even though its cue period
    completed; no `task_abort` is sent.
12. `Stage.Error` is never used. Escape is ignored in Summary; Space/Enter cannot trigger *Retry export*; if export
    never succeeds the operator cannot return to the launcher from the UI.
13. `OnApplicationPause` aborts only in Task/Iti; pauses during RunReady/Break are caught only indirectly by the
    disconnect/stall checks.
14. `collectionVsyncCount` has no effect on Android (VSync forced to 0, target frame rate used).

**Logging semantics**

15. `ItiDurationSec` is the configured value; the measured ITI is `TrialEnd − TaskEnd`.
16. `events.csv` `Phase` holds the stage name outside the Task stage (`Iti` for `task_end`/`iti_onset`/`run_end`),
    while `cueframes.csv` uses `ITI`. `TrialTotal` is non-zero on out-of-trial rows.
17. `PredictedPresentationMonotonicSec` in `events.csv` is the frame's cached prediction, also for `marker_echo` rows
    where it is meaningless.
18. `cueframes.csv` omits lattice slot/period, so dropped frames must be inferred.
19. `settings.json` stores enums as integers and texture references as volatile `instanceID`s; its
    `collectionDataFolder` is the unmigrated value.
20. Sample counters (`*SamplesAt*`, `session.json`) count across all EEG directories since server start; a board
    reconnect during calibration creates an additional EEG directory.
21. Task directory timestamp is **UTC**; EEG directory timestamp is **local time**.

**Documentation discrepancies**

22. README: EEG saved in `BciCoreLogs/eeg_<timestamp>/`; code: `eeg_reach-grasp_p<P>_s<S>_<yyyyMMdd_HHmmss>/`
    (`DirectCsvSessionLogger.cs:101-102`). Older recordings (e.g. `output/reach-grasp/tablet-fix/recordings`) show
    the older `eeg_<timestamp>` naming.
23. `Art/PROVENANCE.md` and `output/reach-grasp/VALIDATION.md` describe TextMeshPro screens and a
    `CollectionFont`; the current view is pure IMGUI (`View:1-121`) and no script references TMP or a font field
    (the 2026-10-27 `settings.json` still contains `collectionFont`). The TMP assets are dead weight.
24. `tablet-fix/VALIDATION.md` reports data under `files/data/…` (old default folder); current default is
    `BciCoreLogs`, and a saved `data` value is migrated only when the source is BciCore (`Ctrl:155-156`).
25. README "Settings and data" says the Common tab owns fourteen controls; the catalog now has fifteen
    definitions, none of which bind to this game.
26. `RestHand.png` is only 20×34 px and is upscaled to fill up to 80 % × 46 % of the screen (blurry); Hold and Place
    show the identical picture, distinguished only by the heading text.
27. The old smoke-test data (`output/reach-grasp/smoke-data`) predates the `*SamplesAt*` columns of
    `trialdata.csv` and used a simulator whose echo `seq` was a sample number; do not use it as a schema reference.

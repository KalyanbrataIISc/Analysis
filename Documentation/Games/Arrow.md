# Arrow Game — Direction Response (game id `arrow`)

Verified against the code at commit `af3b034` (branch `Kalyanbrata`) plus the later pre-SSVEP / double-cue / points trial-flow change. Where this document and `README.md` / `BciCore-Documentation.md` disagree, this document follows the code (see section 14).
Shared clocks, transports, BciCore EEG logs and the per-frame stimulus logger are described in [00-Shared-Infrastructure.md](00-Shared-Infrastructure.md). This file states exactly how Arrow uses them.

Abbreviations: `AGC` = `Assets/Games/Arrow/Scripts/ArrowGameController.cs`, `AGA` = `Assets/Games/Arrow/Scripts/ArrowGameController.Aesthetics.cs`, `CORE` = `Assets/Games/Arrow/Scripts/ArrowGameCore.cs`, `LANE` = `Assets/Games/Arrow/Scripts/ArrowLaneLayout.cs`, `REND` = `Assets/Games/Arrow/Scripts/ArrowVisualRenderer.cs`, `PREFAB` = `Assets/Games/Arrow/Prefabs/ArrowGame.prefab`.

---

## 1. Overview & paradigm

**What the participant sees.** On a plain black background (`backgroundSrgb`, camera clear colour, `REND:95`) two groups ("flocks") of filled triangular arrowheads move in straight lines and wrap around a toroidal field. Default: 8 arrows per group (16 total).

* Each group has a **pointing direction** (orientation of the triangle tip) and a **moving direction** (velocity), each one of up/down/left/right. In every trial the four directions `C1Point, C1Move, C2Point, C2Move` are all different (`CORE:51-58`).
* Each arrow is drawn as an outer triangle (the "border") and a smaller inner triangle (the "fill") on top of it.
* **Pre-SSVEP period** (`AppState.PreSsvep`, `preSsvepSec` = 1.5 s, counted in frames; `AGC:804-836`): the trial's layout is already moving; both fills are black (`nfLevel` 0); all borders are steady grey `preSsvepBorderLuminance` = 0.5 (= SSVEP mean, so no luminance jump at SSVEP onset); the **cued group's** borders flash bright red (`preSsvepFlashSrgb`) as a 4 Hz on/off square wave (`preSsvepFlashHz`). Only whole flashes whose red half ends by the last displayed pre-SSVEP frame are shown, so that frame is always grey. No SSVEP, no marker and no NF integration in this period. This flash is the only cue to *which group* is the target.
* **Trial (SSVEP) period**, entered in the same frame the pre-SSVEP period ends: the **border** of group C1 flickers sinusoidally at the C1 SSVEP frequency, the border of group C2 at the C2 frequency (defaults 15 Hz / 17 Hz, possibly swapped per trial, section 5). The start marker is sent at the end of trial frame 1 (SSVEP onset).
* The **fill** encodes neurofeedback (NF): grey level = NF level (0 = black, invisible on the black background, so the arrows first look like flickering outlines); when the level is in the green zone the fill of *both* groups is light green; after the level has been held in the green zone for `NfGreenHoldSec` (1 s) the **colours are revealed** (NF success, marker 50): C1 arrows are filled deep-sky-blue, C2 arrows dark-orange (`AGC:893-896`). If `trialLengthSec` (15 s) runs out without NF success the colours are **revealed anyway** (`RevealTimeout = 1`): no success marker, no REACHED COLOR increment, and the normal response window opens (`AGC:876`).
* A static **double cue** sits at the bottom of the safe area from the first pre-SSVEP frame to the end of the trial: left half orange (`c2Srgb`) "Moving", right half blue (`c1Srgb`) "Pointing" (`AGC:394`, `REND:188-210`). It shows the colour → rule mapping, not the target.
* **Feedback**: after a response the field is emptied and centre-screen text shows "Correct" (green) or "Incorrect" (red) plus "+N points" for `FeedbackSec`. If no response arrives in the window, red "Missed" / "+0 points" is shown for `FeedbackSec`, then the trial stops.

**What the participant does.** After colour reveal (NF or timeout), report one direction with an arrow key or a swipe (`AGC:1073`). Inputs before the reveal is committed are not polled and are ignored.

**Correct-response rule** (`CORE:25`): cue C1 → correct answer is the **pointing** direction of the C1 (blue) group; cue C2 → correct answer is the **moving** direction of the C2 (orange) group. The double cue shows this rule for both colours at all times.

**Cognitive / BCI purpose.** A feature-based-attention SSVEP neurofeedback task: the NF channel used in a trial is the one matching the *cued group's* flicker frequency (section 7). The target is cued by the red pre-SSVEP flash and must be held in memory during the NF phase, when both groups look identical. Reaching the reveal requires sustained positive NF on that channel; the response then tests the pointing-vs-moving rule on the revealed, coloured groups.

**Success / outcome per trial:** `Accuracy = 1` iff a response was given inside the response window and equals `CorrectResponse` (after either kind of reveal). `NfSuccess = 1 − RevealTimeout`. `ResponseTimeout = 1` = no response within `ResponseTimeoutSec` after the reveal (`Accuracy = 0`). **Points** (`AGC:961`): NF success + correct = `pointsNfSuccessCorrect` (100); NF failure + correct = `pointsNfFailureCorrect` (10); everything else 0.

---

## 2. Code map

| File | Class / type | Role |
|---|---|---|
| `Assets/Games/Arrow/Scripts/ArrowGameController.cs` | `ArrowGame.ArrowGameController : MonoBehaviour, IGameSession` (partial) | State machine, settings, NF update, timing, triggers, input, runtime settings UI |
| `Assets/Games/Arrow/Scripts/ArrowGameController.Aesthetics.cs` | same partial class | IMGUI screens (welcome, settings, instructions, HUD, export, summary, fatal), double-cue placement |
| `Assets/Games/Arrow/Scripts/ArrowGameCore.cs` | `Direction4`, `CueKind`, `TrialDefinition`, `DirectionUtil`, `TrialPlanner`, `SsvepPhaseSchedule`, `NfTraceRow`, `DroppedFrameRow`, `SsvepTraceRow`, `CsvLogger` | Trial plan, SSVEP waveform, task CSV writer |
| `Assets/Games/Arrow/Scripts/ArrowLaneLayout.cs` | `ArrowLaneLayout`, `ArrowState`, `FieldChoice`, `LayoutResult` | Field choice (gcd), collision-free lane layout, motion/wrap, path verification |
| `Assets/Games/Arrow/Scripts/ArrowVisualRenderer.cs` | `ArrowVisualRenderer` | Mesh batches (4 batches: border/fill × 2 groups), triangle geometry, double-cue meshes (two half boxes) + cue words, centre feedback text, camera |
| `Assets/Games/Arrow/Scripts/ArrowGameModule.cs` | `ArrowGame.ArrowGameModule : GameModule` | Launcher registration; saved-layout and trial-flow (instruction text) migrations; settings validation |
| `Assets/Games/Arrow/Prefabs/ArrowGame.prefab` | GameObject `ArrowGame` with disabled `ArrowGameController` (settings template) + `ArrowGameModule` | Effective defaults |
| `Assets/Games/Arrow/Tests/Editor/ArrowGameTests.cs` | NUnit EditMode tests | see below |
| `Assets/CogLab/App/Tests/Editor/LeafArrowResponseTimingTests.cs` | NUnit EditMode tests (Leaf + Arrow) | Reveal/response window timing, pre-SSVEP flash, points, Missed feedback, instruction migration |

| Item | Value | Source |
|---|---|---|
| Assembly | `CogLab.Games.Arrow` (refs `CogLab.Framework`, `CogLab.Shared`, `BciCore`, `Unity.InputSystem`, `Unity.ugui`); does not reference Leaf | `Assets/Games/Arrow/CogLab.Games.Arrow.asmdef` |
| Test assembly | `CogLab.Games.Arrow.Tests` (Editor only) | `Assets/Games/Arrow/Tests/Editor/CogLab.Games.Arrow.Tests.asmdef` |
| Namespace | `ArrowGame` | |
| Game ID | `arrow` | `PREFAB:221` |
| Display name | `Arrow Game` (launcher button "Play Arrow Game") | `PREFAB:222` |
| In-game title | `Arrow Game - Direction Response` (`applicationTitle`, standalone welcome screen only) | `PREFAB:166` |
| Launcher colour | RGBA (0.2235, 0.5098, 0.7647, 1) | `PREFAB:223` |
| Launcher module | `ArrowGameModule` | `PREFAB:218` |
| PlayerPrefs key | `CogLab.Games.arrow.v1` (`GameModule.SettingsKey`) | `Assets/CogLab/Framework/GameModule.cs:29` |
| Scene | prefab instance in `Assets/CogLab/App/Scenes/CogLab.unity` (only transform/name overrides; no setting overrides) | |

**Tests (what they pin down).**

| Test | Asserts |
|---|---|
| `TriangleTipMatchesResponseDirection` | 3 vertices, tip at `DirectionUtil.Vector(dir) * L/2`, bbox = `Extents`, positive winding |
| `PlannerBalancesCuesAcrossAllDirectionPermutations` | 24 trials → 12 C1, all 24 combos distinct, 4 distinct directions, `CorrectResponse` rule |
| `NormalArrowsStayDistributedAndSeparateForACompleteWrap` | 6 resolutions; all 24 layouts feasible; ≥2 lanes per group (perpendicular); mirrored lanes (parallel); clearance ≥ 20 % of max outer dimension over a full wrap |
| `MotionWrapsAtBothFieldEdges` | toroidal wrap |
| `SsvepUsesContinuousPresentationTimeAndStopsAtHorizon` | `0.5+0.5 sin(2πft)`; slot 0 at t=0.001; false beyond horizon |
| `RandomizedPlannerBalancesAssignmentsAndDisabledModeKeepsLegacyChannels` | 12/24 swapped, 6 per cue; shuffle off → `NfIndex == cue` |
| `PrefabFrequencyDefaultsAndSavedProfilesUpgradeOnce` | prefab 15/17 Hz; legacy 17/19 profile → 15/17 once |
| `RepeatedSessionsReserveNewArrowFilesWithoutChangingOldData` | 5 files per run, `_r2` suffix, no "leaf" in names |
| `ArrowPrefabRegistersIndependentlyAndRejectsASingleArrowGroup` | id `arrow`, key `CogLab.Games.arrow.v1`, 150 px / 0.42 / 8; `arrowsPerFlock = 1` invalid |
| `SavedLayoutUpgradeRunsOnceAndPreservesCustomProfiles` | 180/0.5/4 → 150/0.42/8 only if unversioned |
| `LeafArrowResponseTimingTests` (8 tests per game) | response window = 4 s from colour onset even past `trialLengthSec`; feedback not cut by trial cap; `RevealExpired` at exactly 15 s; `RequiredPhaseHorizonSec = 15+4+1+2 = 22`; pre-SSVEP flash on/off with only whole flashes, `lastFrameSeconds` passed explicitly (`PreSsvepFlashUsesWholeSlowFlashesAndEndsOnSteadyGrey`); points 100 / 0 / 10 / 0 (`PointsFollowNfOutcomeAndResponseCorrectness`); missed response starts "Missed" feedback with 0 points instead of stopping (`MissedResponseShowsMissedFeedbackInsteadOfEndingTheTrial`); old saved settings get the new instructions once and v1 profiles move 1 s / 2 Hz to 1.5 s / 4 Hz while custom values are kept (`OldSavedSettingsGetTheNewInstructionsOnce`); a touch begun before colour onset is not a swipe (`ColourOnsetDiscardsATouchThatStartedBeforeIt`) |

---

## 3. Session flow / state machine

States: `enum AppState { Setup, Calibration, Instructions, PreSsvep, Trial, Iti, Summary, Fatal, Exporting }` (`AGC:29`). `StartTrial` enters `PreSsvep` when `round(preSsvepSec/ifi) > 0`, else `Trial` directly (`AGC:799-801`).

```
Launcher "Play Arrow Game"
  BciServer.SetSessionIdentity(P, S, "arrow")          CogLabAppController.cs:701
  GameModule.Launch -> new controller, settings copied  GameModule.cs:78
  ConfigureSharedLaunch(P, S, eegLoggingMode)           AGC:310-318
        |
     [Setup] --Start()--> ApplySettingsAndContinue()     AGC:300-307, 499-545
        |  ValidateSettings fails ------------------------------> [Fatal]
        |  InitializeGameplayFromSettings(): display, scale/field auto-fit,
        |     renderer, trigger sender, "reset" marker         AGC:340-373
        |  exception (e.g. auto-fit failed) ---------------------> [Fatal] "Could not start Arrow Game: ..."
        |
        +-- nfSourceType == BciCore --> [Calibration] (shared CalibrationScreen)
        |        Back    -> ExitCalibrationMode, return to launcher (no export, no task files)
        |        Proceed -> ExitCalibrationMode -> BeginSession()
        +-- Tcp / UsbBiosemi --> BeginSession(): stays [Setup] ("Connecting to ...")
        |        until reader IsReady, Error, or nfTcpTimeoutSec ------> [Fatal] on failure
        +-- File --> BeginSession() immediately
        |
  BeginSession(): experimentT0 = MonotonicClock.Now; seed; NF reader      AGC:547-593
  CompleteSessionStart(): plan, re-fit field, verify paths, open CSVs,
        write _session.csv, open stimframes logger (optional)          AGC:612-623
        |
     [Instructions]  "Begin block" -> BeginBlock()      ("Exit to menu" -> export -> launcher)
        |                                                AGC:752-761
     [Iti] lead-in (round(ItiSec/ifi) frames, blank)
        |
     [PreSsvep] -> [Trial] -> [Iti]   x trialsPerBlock   (PreSsvep → Trial in the same frame)
        |
     StartSessionExport()  (resume GC, trial stop marker 30, close triggers,
        await queued trial-log writes, flush stimframes,
        BciCore EEG flush/convert)                       AGC:481
        |
     [Exporting] -> [Summary]  ("Back to games" -> launcher)
```

**Calibration (BciCore only).** `ApplySettingsAndContinue` starts `BciServer.StartServer(enableLogging: mode != Disabled, directCsvMode: mode == DirectCsv, participant, block)` (`AGC:400-402`) and opens `BciCalibration.Open` (`AGC:522-529`). "Proceed to Game" (`CalibrationScreen.TryProceedToGame`, `Assets/CogLab/Shared/Calibration/CalibrationScreen.cs:1679`) calls `BciServer.ExitCalibrationMode()` and then `BeginSession()`. The calibration GUI's "Reboot" button sends marker `0xFFFF` (a firmware command, not a task event); "Stop & Export" and the other calibration controls are shared (see shared doc).

**Instructions.** Scrollable text (`instructionsText`), two example glyphs (right-pointing, filled C1/C2 colour, white border) with captions `instructionC1Label` / `instructionC2Label` (`AGA:245-270`). No markers are sent.

**Lead-in.** "Begin block" (`BeginBlock`, `AGC:752-761`) does not start trial 1 directly: it sets `trialIndex = 0`, calls `RefreshPresentationTiming`, clears the arrows and overlays, sets `itiRemaining = max(1, round(ItiSec/ifi))` and enters `Iti`. Trial 1 is therefore preceded by the same blank ITI (5 s) as every later trial.

**Export (`StartSessionExport`, `AGC:481`).** Triggered by: block completion (`AGC:765`), Escape (`AGC:545`), the HUD "Exit to menu" button (two taps within 3 s, `AGA:381-399`), "Exit to menu" on Instructions/Fatal screens (`ExitToMainMenu`, `AGC:1065`). It resumes garbage collection if paused, always sends `trialstop` (30) first, disposes the trigger sender, then on a background task awaits all queued trial-log writes (`pendingLogWrites`, status "Saving trial logs..."), completes the stimframes logger and, in BciCore mode, calls `BciServer.ConvertCurrentSessionToCsvAsync` (DirectCsv: closes the EEG CSV logger; BinaryThenCsv: converts `.bin` → `.csv`). The trial in progress (if any) is **not** written to the task CSVs.

**Summary screen** (`AGA:185`): `completedTitle`, Points (total points of the run), Accuracy % (= correct / completed trials, missed responses count as incorrect), "Reached color" count (number of NF-earned reveals; timeout reveals not counted), "Trials completed".

**Fatal conditions** (all set `state = Fatal`, resume garbage collection if paused, clear stimuli, log error; shared mode shows "Exit to menu", which exports):

| Condition | Marker sent first | Source |
|---|---|---|
| `ValidateSettings` fails (shared launch) | none | `AGC:506-509` |
| Exception during initialisation (auto-fit / path verification / renderer) | none | `AGC:537-544`, `AGC:666`, `AGC:691-694` |
| TCP/USB not ready within `nfTcpTimeoutSec` or reader error | none | `AGC:601-606` |
| USB link reports an error in any non-Setup state | none | `AGC:489-493` |
| USB: no fresh NF record for `usbNfStallAbortSec` during a trial | 30 | `AGC:846-853` |
| Observed refresh rate deviates > `refreshRateChangeToleranceHz` from the trial's rate | 30 | `AGC:451-463`, `AGC:840` |
| Same, during the pre-SSVEP period | none (no start marker sent yet) | `AGC:806` |
| Layout infeasible at trial start (before frame 1) | none | `AGC:784` |
| SSVEP phase horizon exhausted (mid-trial) | **none** | `AGC:883` |
| Exception in `BeginSession` / `CompleteSessionStart` | none | `AGC:592`, `AGC:609` |

**Escape** (`escapeEndsBlock = true`): in any state except `Setup` (including Calibration, Instructions, PreSsvep, Trial, Iti, Summary, Fatal) Escape sets `finishQueued` and runs `StartSessionExport(ShowSummary)` (`AGC:545`). Standalone (non-launcher) HUD exit returns to `Setup` after export (`AGA:393`).

`OnDestroy` (`AGC:465-474`): resumes garbage collection, waits up to 5 s for queued trial-log writes, flushes stimframes, sends 30 if still in `Trial` (not in `PreSsvep`), stops the BciServer (BciCore), disposes reader/sender.

---

## 4. Trial structure & timing

### 4.1 Timeline of one trial (default settings, 120 Hz display assumed for frame counts)

```
Update frame n (Unity)      : what happens in that frame                                      | end of frame (WaitForEndOfFrame)
---------------------------------------------------------------------------------------------------------------------------------
StartTrial (in Update/OnGUI): plan row, frequencies, start marker chosen, layout, phase schedule;
                              P = round(preSsvepSec/ifi); state = PreSsvep (P > 0) or Trial (nothing drawn)
pre-SSVEP frame 1           : pause GC (section 4.3); move; fills black; borders grey 0.5; cued group red if flash on;  | preSsvepOnsetTime = Elapsed
                              double cue shown (no NF read, no flicker, no marker)              |   (-> CueOnsetTime)
pre-SSVEP frames 2..P       : same; red flash 4 Hz on/off, only whole flashes ending by frame P |
next Update                 : state = Trial and trial frame 1 runs in this same Update
frame 1                     : NF read/update, move, PresentationClock.Capture -> phase origin  | trialStartClock = now;
                              (trialPhaseT0 = predicted presentation of frame 1), draw         |   send START marker (20/21 or 31..34)
frames 2..                  : NF integrate; fill grey=NFLevel, green when level>=0.9           |
first green frame G         :                                                                  | FirstGreenTime = Elapsed
reveal frame R, either
  NF success (G+H-1, H = round(NfGreenHoldSec/ifi) consecutive green frames), or
  timeout (now - trialStartClock >= trialLengthSec without NF success):
                              true colours drawn in this frame                                 | colorOnsetClock = now; ColorOnsetTime;
                                                                                               |   send 50 only for NF success
frames R+1 .. : response polled; window = ResponseTimeoutSec from colorOnsetClock
response frame F            : RT = now - colorOnsetClock; send 40 IMMEDIATELY (mid-frame);
                              points set; feedback starts (K = max(1, round(FeedbackSec/ifi)) frames);
                              field emptied and feedback text drawn already in frame F
  or window-expiry frame F  : ResponseTimeout = 1; "Missed" / "+0 points" feedback starts (no 40)
frames F+1..F+K             : centre text "Correct"/"Incorrect"/"Missed" + "+N points"; no arrows, no flicker;
                              double cue + HUD remain
frame F+K                   :                                                                  | send 30; TrialEnd = Elapsed; total += points;
                                                                                               |   queue rows for background write; resume GC + GC.Collect()
ITI frames (N = max(1, round(ItiSec/ifi)))  : blank background, HUD only; then StartTrial (the same ITI also precedes trial 1, from "Begin block")
```

Pre-SSVEP flash (`PreSsvepFlashOn(t, (P−1)·ifi)`, `AGC:823-829`): on pre-SSVEP frame `i`, `t = (i−1)·ifi`; red when the fractional part of `t·preSsvepFlashHz` is < 0.5 and that flash's red half ends at or before `(P−1)·ifi`, the time of the last displayed pre-SSVEP frame, which is therefore always grey. Defaults (1.5 s, 4 Hz, 120 Hz display): six red flashes of 0.125 s (0–0.125, 0.25–0.375, 0.5–0.625, 0.75–0.875, 1.0–1.125, 1.25–1.375 s), steady grey 1.375–1.5 s.

All trials now end with a feedback period (`AGC:929-958`):
* **Timeout reveal**: `!colorsRevealed && !inFeedback && now − trialStartClock ≥ trialLengthSec` (checked in `UpdateTrial` after the green-hold check, `AGC:876`) → `RevealTimeout = 1`, colours revealed, response window opens as after an NF reveal. An NF reveal in the same frame wins.
* **Response timeout**: `colorOnsetCommitted && now − colorOnsetClock ≥ ResponseTimeoutSec` → `ResponseTimeout = 1`, "Missed" feedback for `FeedbackSec`, then 30. Checked *before* input, so an input in the expiring frame is discarded.

Once revealed, the trial is no longer limited by `trialLengthSec` (README "independent response timing", verified by `LeafArrowResponseTimingTests`). Maximum trial duration (`TrialStart` → `TrialEnd`) ≈ `trialLengthSec + ResponseTimeoutSec + FeedbackSec` = 20 s plus frame quantisation; the pre-SSVEP period (1.5 s) comes before `TrialStart`.

**End conditions**

| Ending | `RevealTimeout` / `NfSuccess` | `ResponseTimeout` | Markers | Points (default) | Feedback |
|---|---|---|---|---|---|
| NF reveal + response | 0 / 1 | 0 | S 50 40 30 | 100 if correct, else 0 | Correct/Incorrect |
| NF reveal + no response | 0 / 1 | 1 | S 50 30 | 0 | Missed |
| Timeout reveal + response | 1 / 0 | 0 | S 40 30 | 10 if correct, else 0 | Correct/Incorrect |
| Timeout reveal + no response | 1 / 0 | 1 | S 30 | 0 | Missed |
| Escape / Exit / Fatal (also in pre-SSVEP) | no row | — | partial | not added | — |

### 4.2 Timing parameters

| Parameter | Default | Seconds- or frame-based | Origin / semantics | Source |
|---|---|---|---|---|
| `preSsvepSec` | 1.5 s | **frames**: `P = max(0, round(preSsvepSec/ifi))` | before trial frame 1; 0 skips it | `AGC:799` |
| `preSsvepFlashHz` | 4 Hz | nominal frame times `(i−1)·ifi` | 50 % duty red flash of the cued group's borders; whole flashes only | `AGC:812`, `AGC:823-829` |
| `preSsvepBorderLuminance` | 0.5 | — | steady pre-SSVEP border grey (= SSVEP mean) | `AGC:813` |
| `trialLengthSec` | 15 s | seconds, `MonotonicClock` | from `trialStartClock` (CPU end of frame 1); only limits the unrevealed stage, then timeout reveal | `AGC:876`, `AGC:923-924` |
| `ResponseTimeoutSec` | 4 s | seconds | from `colorOnsetClock` (CPU end of reveal frame, NF or timeout); expiry starts "Missed" feedback | `AGC:926-927`, `AGC:939-943` |
| `FeedbackSec` | 1 s | **frames**: `max(1, round(FeedbackSec/ifi))` | after a response or a missed response; text shown from the response / expiry frame, countdown from the next frame | `AGC:779`, `AGC:935` |
| `ItiSec` | 5 s | **frames**: `max(1, round(ItiSec/ifi))` | blank frames after trial stop, and once before trial 1 (`BeginBlock`, `AGC:760`) | `AGC:1050`, `AGC:1053` |
| `NfGreenHoldSec` | 1 s | **frames**: `max(1, round(NfGreenHoldSec/ifi))` consecutive green frames | resets to 0 when the level leaves the green zone | `AGC:781`, `AGC:873-874` |
| `NfTraceIntervalSec` | 0.1 s | **frames**: `max(1, round(NfTraceIntervalSec/ifi))` | trace row on frames 1, 1+k, 1+2k … up to the response / miss frame | `AGC:780`, `AGC:904` |
| NF integration | — | per frame, uses nominal `ifi` | not actual frame duration; not run in pre-SSVEP or feedback frames | `AGC:867` |
| Motion | `arrowSpeedPxPerSec` | per frame: displacement `ArrowSpeed*ifi` px | dropped frames slow the motion (no catch-up); continues through pre-SSVEP and trial, stops at feedback | `LANE:135-144` |
| SSVEP waveform | — | **continuous seconds** of predicted presentation time | section 6 | `AGC:880-883` |

`ifi = 1/refreshHz`, where `refreshHz = DisplayRateManager.ObservedRefreshRateHz` if ≥ `minimumValidRefreshHz` (30) else `fallbackRefreshHz` (60), re-evaluated at every `StartTrial` (`AGC:766`).

### 4.3 Frame pacing

A dropped frame breaks the SSVEP phase lattice, so the stimulus frames avoid main-thread stalls:

* **No GUILayout pass**: `Start` sets `useGUILayout = false` (`AGC:346`); the IMGUI code uses no `GUILayout` calls.
* **Garbage collection paused during the stimulus** (player builds only, `#if !UNITY_EDITOR`): `PauseGcForStimulus` (`AGC:1000-1008`) sets `GarbageCollector.GCMode = Disabled` on pre-SSVEP frame 1 (or trial frame 1 when there is no pre-SSVEP period) and records the managed heap size. `FinishAfterPresentation` calls `ResumeGc(true)` (`AGC:1020-1028`), which re-enables collection and runs `GC.Collect()` at the start of the blank ITI. `ResumeGc(false)` is also called from `ShowSummary`, `Fatal`, `StartSessionExport` and `OnDestroy`.
* **Safety net**: `CheckGcPauseHeap` (`AGC:1010-1018`) runs every 128 trial frames; if the managed heap grew more than `GcPauseHeapGrowthLimitBytes` (96 MB, `AGC:255`) since the pause, it logs a warning and resumes collection mid-trial.
* **Per-trial log line**: each resume logs `[ArrowGame] Trial N: heap grew X KB with GC paused; dropped frames D.` (view with `adb logcat -s Unity`). Measured on the tablet: 4–15 MB heap growth per trial.
* **Background CSV writes**: `FinishAfterPresentation` (`AGC:1031-1051`) snapshots the trial values, copies `traceRows`/`droppedRows`/`ssvepRows` to arrays and queues `WriteTrial`/`WriteTrace`/`WriteDropped`/`WriteSsvep` on one ordered background task chain (`QueueLogWrite`, `AGC:987-994`, `pendingLogWrites`; errors are logged). Row content and order are unchanged; the files are written slightly after the trial stop. `StartSessionExport` awaits the chain first ("Saving trial logs..."), and `OnDestroy` waits up to 5 s for it.
* **Shared code**: `ResponsiveGui.FitStyle` uses an allocation-free value-tuple cache key, and `CogLabAppController.Start` (player builds) sets stack-trace logging to `None` for `Log` and `Warning` (errors and exceptions keep their stack traces).

Measured in untouched blocks on the tablet: 0 dropped frames in 8 Arrow trials (1 in 11 Leaf trials). **Android screen recording causes large bursts of dropped frames; do not run it during sessions.**

---

## 5. Trial planning / randomisation

`TrialPlanner.Build(trialsPerBlock, cueC1Probability, rng, randomizeSsvepFrequencies)` (`CORE:47-83`):

1. **Direction combinations**: for each `C1Point ≠ C1Move`, the two remaining directions go to C2 in both orders → 4·3·2 = **24 combos**, each with four distinct directions.
2. **Cues**: `c1Count = round(trialsPerBlock · clamp(p,0,1))` (C# `Math.Round`, banker's rounding: 25 × 0.5 = 12.5 → 12); the remaining trials are C2. The cue list is Fisher–Yates shuffled.
3. **Combos**: for every block of 24 trials a fresh shuffled copy of the 24 combos is used (a partial last cycle takes the first `n` of a shuffled cycle). Cue `i` is assigned to trial `i` in order. With 24 trials, each combo occurs exactly once; cue × combo pairing is random (not balanced).
4. **Frequency assignment** (only if `randomizeSsvepFrequencies`): `SsvepFrequencyAssignment.Build` (`Assets/CogLab/Shared/Timing/SsvepFrequencyAssignment.cs:9-25`). Within each cue, `floor(n_cue/2)` trials are swapped; for an odd cue count one cue gets the extra swap and the other cue does not (random choice), so the whole block is balanced ±1. Default 24 trials: 12 swapped, 6 per cue.
5. Per trial at `StartTrial` (`AGC:713-716`): `FrequencyC1Hz = swapped ? f2 : f1`, `FrequencyC2Hz = swapped ? f1 : f2` (f1 = `frequencyC1Hz` = 15, f2 = `frequencyC2Hz` = 17).

**Seed** (`AGC:554-557`): `seed = useFixedRandomSeed ? fixedRandomSeed : Environment.TickCount*397`; if `mixParticipantAndBlockIntoSeed` (default true) `seed ^= participant.GetHashCode() ^ block.GetHashCode()`. The final seed is written to `_session.csv` (`RandomSeed`).

**RNG consumption order (one `System.Random(seed)`):** cue shuffle → combo shuffles → frequency assignment → (if `verifyArrowPathsAtSetup`) 24 verification layouts in `ValidateLayouts` (`AGC:690`) → per-trial `ArrowLaneLayout.Create` lane offsets/jitter (`AGC:726-727`). Consequences: the trial plan is reproducible from `RandomSeed` alone; the initial arrow positions additionally depend on `verifyArrowPathsAtSetup`, the field size, the scale and `ifi`.

**Reproduction recipe:** set `Use Fixed Random Seed = On`, `Fixed Random Seed = <RandomSeed from _session.csv>`, `Mix Participant And Block Into Seed = Off`, same `trialsPerBlock`, `cueC1Probability`, `randomizeSsvepFrequencies`. (`string.GetHashCode` is runtime-defined; do not rely on recomputing the mixed seed from participant/block.)

The responsive-fit check `AllLayoutsFit` uses its own `System.Random(918273)` and a fixed 24-trial plan (`AGC:671-672`); it does not consume the session RNG.

---

## 6. Stimulus

### 6.1 Geometry (pixels; `s = activePixelScale`)

| Quantity | Formula | Default at s = 1 | Source |
|---|---|---|---|
| Arrow length (tip to base) `L` | `arrowSizePx·s` | 150 px | `AGC:261` |
| Arrow base width `W` | `arrowSizePx·arrowWidthMultiplier·s` | 63 px | `AGC:262` |
| Border `B` | `arrowSizePx·arrowBorderMultiplier·s` | 30 px | `AGC:263` |
| Outer length / width | `L+2B`, `W+2B` | 210 / 123 px | `AGC:264-265` |
| Lane clearance | `max(laneClearanceMarginPx·s, 0.20·max(L+2B, W+2B))` | 42 px | `LANE:33-34`, `AGC:267` |
| Max radius (wrap copy threshold) | `0.5·sqrt((L+2B)²+(W+2B)²)` | 121.7 px | `AGC:268` |
| Speed | `arrowSpeedPxPerSec·s` px/s, applied as `·ifi` px/frame | 200 px/s (1.667 px/frame at 120 Hz) | `AGC:266` |

**Triangle** (`REND:105-114`): local vertices tip `(+L/2, 0)`, base `(−L/2, ±W/2)`, rotated by 0° (Right), 90° (Down), 180° (Left), −90° (Up) in pixel coordinates (y down). The shape is centred on its bounding box, not its centroid. The outer triangle uses the same formula with `(L+2B, W+2B)`, so border thickness is `B` along the axis but varies along the slanted edges. Inner fill is drawn on top (`z = −0.1`, sorting order 2 vs 1, `REND:30-41`, `REND:68-75`). Bounding-box extents: horizontal pointing → `(len, width)`; vertical → `(width, len)` (`LANE:168-169`).

### 6.2 Scale and field

* `s_requested = clamp(min(Screen.w,h)/referenceShortSidePx, minimumScreenScale, maximumScreenScale)` = shortSide/1080 clamped to [0.05, 4] (`AGC:625-630`), or 1 if `useResponsiveSizing` is off.
* Auto-fit (`AGC:647-667`): try `s` from `s_requested` downward in steps of `max(0.01, 0.05·s_requested)` to `max(0.05, 0.25·s_requested)`. For each `s`: viewport = safe area minus padding, × width/height fractions (`AGC:638-645`); required gcd = `ceil(2·(OuterL+OuterW+2·clearance))+1` (835 at s = 1); `ChooseField` (`LANE:36-59`) picks the largest-area `w×h` within `maxFieldShrinkPx·s` of the viewport whose `gcd(w,h) ≥ required` and `w/g, h/g ≥ minRepeatsPerAxis`; the field is centred in the viewport. All 24 combos must lay out (`AllLayoutsFit`). Failure → Fatal "Display auto-fit failed".
  Example: 1920×1080 full-screen safe area at s = 1 → field 1920×960 (gcd 960), offset y = 60.
* The effective `ActivePixelScale` and field rectangle (top-left origin, pixels) are logged in `_session.csv`.
* `ValidateLayouts` (`AGC:683-698`, if `verifyArrowPathsAtSetup`) simulates each of the 24 layouts for `min(verificationMaxFrames, lcm(w,h)/speed)` frames and requires clearance ≥ lane clearance − 0.01 px.

### 6.3 Layout and motion (`LANE:61-133`)

* Group 1 = C1 (`flock=1`, arrows 0..n−1), group 2 = C2. All arrows of a group share pointing and moving direction; velocity = unit direction × `ArrowSpeed·ifi` (Up = (0,−1) in pixel space).
* **Parallel motion** (both groups on the same axis): `laneCount = floor(cross/(maxCrossExtent+clearance))`, capped to `2n`, forced even; lanes alternate C1/C2, C2 lane order reversed; arrows evenly spaced along each lane with a random per-lane offset.
* **Perpendicular motion**: positions placed on an invariant grid modulo the field gcd so the two orthogonal streams never collide; each group uses `min(maxLanes, n)` lanes (≥ 2 required), with random per-lane jitter.
* `Advance` adds the velocity each frame and wraps modulo the field (toroidal) (`LANE:135-144`). Rendering draws up to 4 copies of an arrow near an edge (`REND:115-133`); copies are **not clipped** to the field, so arrows can be partially visible outside the field rectangle by up to `MaxRadius`.

### 6.4 Colours

Project colour space is **Linear** (`ProjectSettings/ProjectSettings.asset: m_ActiveColorSpace: 1`). Every configured colour is an sRGB value converted with `.linear` before being assigned to a material (`Render`, `RenderGray`, `AGC:916-917`); the sRGB framebuffer re-encodes it, so the **displayed code value equals the configured sRGB value**.

| Element | Setting | Default sRGB (0–255) |
|---|---|---|
| C1 fill after reveal; right half of the double cue | `c1Srgb` | (0, 191, 255) |
| C2 fill after reveal; left half of the double cue | `c2Srgb` | (255, 140, 0) |
| Fill while in green zone (both groups, pre-reveal) | `greenZoneSrgb` | (179, 255, 179) |
| Fill pre-reveal, not green | grey `v = NFLevel` | (v, v, v)·255 |
| Fill, pre-SSVEP period | grey 0 | (0, 0, 0) |
| Border, pre-SSVEP period | grey `preSsvepBorderLuminance`; cued group `preSsvepFlashSrgb` while the flash is on | (128, 128, 128); (255, 0, 0) |
| Border (outer triangle), trial | grey `v = BorderLuminance` (SSVEP) | (v, v, v)·255 |
| Background (camera clear) | `backgroundSrgb` | (0, 0, 0) |
| Cue words | `cueTextSrgb` + outline `cueTextOutlineSrgb` (`cueTextOutlinePx·s` px) | black on white outline |
| Feedback text | `successSrgb` (correct) / `failureSrgb` (incorrect, missed); black outline | (0,255,0) / (255,0,0) |

### 6.5 SSVEP flicker

`SsvepPhaseSchedule.TrySampleForPresentation` (`CORE:114-126`):

```
t        = PresentationClock.Capture().presentationTime(frame) − trialPhaseT0      (seconds, ≥ 0)
trialPhaseT0 = presentationTime(trial frame 1)                                      (AGC:854)
mean     = clamp(ssvepMeanLuminance,0,1) = 0.5
amp      = min(mean, 1−mean) · clamp(ssvepModulationDepth,0,1) = 0.5
BorderLuminanceC1 = mean + amp · sin(2π·FrequencyC1Hz·t + phaseC1Degrees·π/180)
BorderLuminanceC2 = mean + amp · sin(2π·FrequencyC2Hz·t + phaseC2Degrees·π/180)
slot     = round(t · refreshHz)
```

* Phase origin: the *predicted* presentation (VSYNC-lattice) time of the trial's first stimulus frame, so frame 1 has `t = 0` and luminance 0.5 (default phases 0), equal to the steady pre-SSVEP border grey, so the flicker starts without a step (a step appears if the mean, phases or `preSsvepBorderLuminance` are changed). One continuous origin per trial up to the response / miss frame; there is no flicker in the pre-SSVEP period, during feedback (field emptied) or in the ITI (meshes cleared).
* The sinusoid is in **sRGB code values** (0..1), not linear light; physical luminance is approximately the display EOTF of these values (contains harmonics).
* Horizon: fails (Fatal) if `t > max(precomputedPhaseHorizonSec, trialLengthSec+ResponseTimeoutSec+FeedbackSec+phaseHorizonSafetyMarginSec)` = max(300, 22) = 300 s (`AGC:787-790`, `AGC:918-920`). The pre-SSVEP period is not included (the phase starts at trial frame 1).
* Fill is not modulated; only borders flicker.

### 6.6 Double cue and feedback text

**Double cue** (`REND:83-89`, `REND:188-210`): one box `doubleCueWidthPx·s × cueHeightPx·s` = 520×90 px split into two 260 px halves; outer corners rounded (radius `min(cueCornerRadiusPx·s, width/4, height/2)` = 20 px, 8 segments), straight inner edge; sorting order 5 (above arrows). Left half `c2Srgb` (orange) with `cueC2Word` "Moving", right half `c1Srgb` (blue) with `cueC1Word` "Pointing"; fixed for the session (`AGC:394`). Position (`AGA:76-86`): always at the bottom, centre `cueBottomMarginPx·s + cueHeightPx·s/2` above the bottom of the safe area. Visible in every pre-SSVEP and trial frame including feedback; hidden in the ITI and other screens. Words: Unity UI `Text`, one per half, best-fit up to `round(cueFontSize·cueCharacterSize·s)` = 32 px at s = 1. Arrows passing under the box are occluded.

**Feedback text** (`REND:97`, `AGC:912-916`, `AGC:954-958`): centre-screen Unity UI `Text`, size `round(feedbackFontSizePx·s)` = 96 px, black outline, `"<verdict>\n+<points> points"` with verdict `correctFeedbackText` / `incorrectFeedbackText` / `missedFeedbackText`. Shown only during feedback; the arrows are cleared then.

**HUD during PreSsvep/Trial/ITI** (`AGA:143`, `AGA:345-370`): three tiles top-right — TIME (mm:ss since `experimentT0`), SCORE (total points of the run, updated at trial end), REACHED COLOR (NF-reveal count) — and an "Exit to menu" button top-left. These IMGUI elements occlude part of the stimulus field and are visible to the participant.

---

## 7. Neurofeedback

### 7.1 Sources (`nfSourceType`, effective default **BciCore**, prefab value `2`)

| Enum (YAML int) | Reader | Fresh-sample semantics | Markers via |
|---|---|---|---|
| `File` (0) | `NfBinaryReader(NfPath)`: little-endian doubles at byte offset `index·8`; `NfPath` = `nfFilePath`, relative → `persistentDataPath` | every successful read returns true (no freshness concept) | UDP `TriggerSender(nfTcpHost, triggerPort)` |
| `Tcp` (1) | `NfTcpReader(nfTcpHost, nfTcpPort)`: 24-byte records = 3 LE doubles; index 0/1 used | true once per new record | UDP `TriggerSender` |
| `BciCore` (2) | `BciCoreNfReader`: index 0 = `NfSample.Smi14gt18Shaped` (or `CcaSample.FbAgtB`), index 1 = `Smi18gt14Shaped` (or `FbBgtA`) | true once per new NF/CCA frame | `BciCoreTriggerSender`: `BciServer.LogTriggerSent` + `BciServer.SendMarker` (CMD 0x08 to ESP32) + UDP fallback to `nfTcpHost:triggerPort` |
| `UsbBiosemi` (3) | `UsbBiosemiLink(127.0.0.1:usbBiosemiPort)`: 24-byte records `[a, b, sampleCount]`; NaN/Inf records dropped; acks `R <count>\n` | true once per record | same socket, ASCII `"<code>\n"` |

Sources: `AGC:351-370`, `AGC:561-590`; `Assets/CogLab/Shared/Bci/NeurofeedbackTransport.cs:44-175`; `Assets/CogLab/Shared/Bci/BciCoreNfReader.cs:30-73`; `Assets/CogLab/Shared/Bci/UsbBiosemiLink.cs:45-154`.

### 7.2 Channel per trial

`NfIndex = cueIndex XOR swapped` (`SsvepFrequencyAssignment.NfIndex`, `CORE:27`), i.e. **the zero-based NF channel matching the frequency of the cued group**: index 0 = the `frequencyC1Hz` (Stimulus 1 / low, 15 Hz) channel, index 1 = `frequencyC2Hz` (Stimulus 2 / high, 17 Hz) channel.

| Cue | Swapped | Cued group's frequency | NfIndex (0-based) | `NFIndexUsed` (CSV, 1-based) | Start marker |
|---|---|---|---|---|---|
| C1 | 0 | f1 (15) | 0 | 1 | 31 |
| C2 | 0 | f2 (17) | 1 | 2 | 32 |
| C1 | 1 | f2 (17) | 1 | 2 | 33 |
| C2 | 1 | f1 (15) | 0 | 1 | 34 |

With `randomizeSsvepFrequencies = Off`: C1 → index 0, C2 → index 1, start markers 20/21.

### 7.3 Update equations (per non-feedback trial frame, `AGC:844-877`; nothing in pre-SSVEP frames)

```
at StartTrial: nfCurrent = 0, nfLevel = 0, greenHoldFrames = 0
each frame:   if TryRead(NfIndex, out x): nfCurrent = x            (zero-order hold otherwise)
              clipped  = clamp(nfCurrent, −NfClip, +NfClip)                     NfClip = 1
              nfLevel  = clamp(nfLevel + NfRatePerUnitPerSec · ifi · clipped, 0, 1)   rate = 3 /s
              inGreen  = nfLevel ≥ 1 − NfWhiteTopRelaxation                      = 0.9
              if !revealed: greenHoldFrames = inGreen ? greenHoldFrames+1 : 0
                            reveal when greenHoldFrames ≥ round(NfGreenHoldSec/ifi)          (NF success)
                            else reveal when now − trialStartClock ≥ trialLengthSec          (timeout reveal)
```

Fastest possible reveal from trial start ≈ 0.3 s (0 → 0.9 at +1 input) + 1 s hold. After reveal the level keeps updating (logged in trace) until the response / miss frame but has no visual effect; feedback frames skip the NF update.

### 7.4 Stall handling

* Tcp / BciCore / UsbBiosemi: if no fresh sample for `nfStreamStallWarnSec` (2 s) within a trial, a single `Debug.LogWarning` per trial; the trial continues with the held value (`AGC:854-859`). Not recorded in CSVs (visible only as `NFReadOk = 0` runs in the trace).
* UsbBiosemi: no fresh record for `usbNfStallAbortSec` (5 s; 0 disables) → marker 30 + Fatal (`AGC:846-853`). Also checked in feedback frames.
* The stall clock is reset at each `StartTrial` (`AGC:776`), i.e. before the pre-SSVEP period, in which NF is not read; the pre-SSVEP time (1.5 s) counts towards both thresholds until the first fresh sample of trial frame 1.

---

## 8. Responses & scoring

* **Inputs** (`TryGetDirection`, `AGC:1073`): keyboard Up/Down/Left/Right arrows (`wasPressedThisFrame`, if `enableKeyboardArrows`; priority Up > Down > Left > Right within one frame), or a primary-touch swipe (if `enableSwipeResponses`): press and release both observed while polling, `|Δ| ≥ swipeThresholdPx·s` (40 px at s = 1); dominant axis decides; screen y up = Up.
* Polled only on frames where `colorsRevealed && colorOnsetCommitted` and not in feedback, i.e. from the frame **after** the reveal frame until the response window expires. Earlier key presses are never seen. The colour-onset commit resets swipe tracking (`touchTracking = false`, `AGC:981`), so only a touch that starts after the committed colour onset can become a swipe.
* Polling starts after either kind of reveal (NF or timeout).
* Only the first valid response counts.
* **Accuracy**: `response == CorrectResponse` (`CORE:25`).
* **Points** (`TrialPoints`, `AGC:961`, set at `AGC:948`): correct after NF success = `pointsNfSuccessCorrect` (100); correct after timeout reveal = `pointsNfFailureCorrect` (10); incorrect or missed = 0. Added to `totalPoints` at trial end (`AGC:1035`); `totalPoints` is reset at `CompleteSessionStart`. Shown in the feedback text, the HUD SCORE tile and the summary.
* **Reaction time** (`AGC:946`): `ReactionTime = now − colorOnsetClock`, both `MonotonicClock` seconds; `now` = time `UpdateTrialOutcome` is called in the response frame's `Update` (after drawing commands are issued), `colorOnsetClock` = CPU end-of-frame of the reveal frame. RT therefore has frame granularity (~8.3 ms at 120 Hz), includes input polling latency, and is not referenced to photon onset or to the OS input-event timestamp.
* `ParticipantResponse` = `up|down|left|right`, or `missedResponseText` (`missed`) if no response within the window.

---

## 9. Event markers / triggers

### 9.1 Marker table (effective defaults)

| Code | Name passed to sender | Exact moment | Condition | Source |
|---|---|---|---|---|
| 0 | `reset` | `InitializeGameplayFromSettings`, i.e. before calibration/instructions, once per launch. USB: sent by the link itself on every (re)connection; `Send("reset")` is a no-op | always | `AGC:404`, `AGC:415`, `UsbBiosemiLink.cs:64`, `:136` |
| 31/32/33/34 | `trialstart` | CPU end of trial frame 1 (`WaitForEndOfFrame`, SSVEP onset, after the pre-SSVEP period), same instant as `trialStartClock` | `randomizeSsvepFrequencies = On`: `31 + cue + 2·swapped` | `AGC:771`, `AGC:967-975` |
| 20 / 21 | `trialstart` | same | shuffle Off: C1 → `trialStartTrigger` (20), C2 → `trialStartC2Trigger` (21) | `AGC:771-772` |
| 50 | `success` | CPU end of the NF reveal frame, same instant as `colorOnsetClock` | NF success only; a timeout reveal sends nothing | `AGC:983` |
| 40 | `response` | **immediately** in `Update` of the response frame (not deferred to end of frame), just after `ReactionTime` is computed | valid response in window (after either kind of reveal) | `AGC:947` |
| 30 | `trialstop` | CPU end of the last feedback frame, immediately before `TrialEnd` is read | every completed trial (after response feedback or Missed feedback) | `AGC:1035` |
| 30 | `trialstop` | refresh-rate abort during a trial (not in pre-SSVEP), USB stall abort | Fatal | `AGC:461`, `AGC:849` |
| 30 | `trialstop` | `StartSessionExport` — after the last trial, on Escape, on Exit to menu, from any state | always once per export | `AGC:493` |
| 30 | `trialstop` | `OnDestroy` if state is `Trial` | | `AGC:470` |

There is **no cue-onset marker** in Arrow and the pre-SSVEP period has no marker; its onset is logged only as `CueOnsetTime`. Cue identity and frequency assignment are encoded in the start marker.

Expected EEG marker sequence per trial: `START → [50] → [40] → 30`, i.e. `S 50 40 30` (NF success, response), `S 50 30` (NF success, missed), `S 40 30` (timeout reveal, response) or `S 30` (timeout reveal, missed). Per session: `0` (may be invisible, see 14) … trials … `30` (extra, from export).

### 9.2 Transports

| `nfSourceType` | Path | Payload |
|---|---|---|
| BciCore | `BciServer.SendMarker(code & 0xFFFF)` → CMD frame to ESP32 (latched into the EEG stream's `marker` column); `BciServer.LogTriggerSent` → `health.csv` row (`seq = 0`, `marker = code`, `event = trigger_sent:<name>`) ; plus UDP datagram to `nfTcpHost:triggerPort` | `Assets/CogLab/Shared/Bci/BciCoreTriggerSender.cs:25-37` |
| Tcp, File | one UDP datagram per marker to `nfTcpHost:triggerPort` (default 10.36.17.144:5007), ASCII decimal, new `UdpClient` each send | `NeurofeedbackTransport.cs:15-29` |
| UsbBiosemi | `"<code>\n"` on the bridge TCP socket (127.0.0.1:5010, ADB reverse); codes must be 0–255 | `UsbBiosemiLink.cs:117-143` |

### 9.3 Validation (`AGC:281-298`, `SsvepFrequencyAssignment.cs:53-79`)

Only when `randomizeSsvepFrequencies = On`:
* `frequencyC1Hz < frequencyC2Hz`, both positive and finite;
* reset, success, response, stop must be distinct, not in {20, 21–24, 31–34}, within 0–255;
* 30 and 60 may only be used as the stop code; stop must be 30 or 60.

With shuffling Off no marker-code validation is done (legacy start codes are never validated in either mode). Other checks always applied: 2 ≤ `arrowsPerFlock` ≤ 100, positive size/width, non-negative border/speed, ≥ 1 trial, p ∈ [0,1], positive trial/response timeouts, non-negative feedback/ITI, positive frequencies/clip/trace interval, consistent scaling settings.

---

## 10. Output files

Task files go to `DataPath` = `dataFolderName` if rooted, else `Application.persistentDataPath/<dataFolderName>` (default `…/data`; on Android `/storage/emulated/0/Android/data/org.iisc.coglab.games/files/data`) (`AGC:279`).

### 10.1 File set and naming

| File | Pattern | Created | Rows appended |
|---|---|---|---|
| Trial data | `p{P}_b{B}_arrow_trialdata{_rN}.csv` | `CompleteSessionStart` (after calibration, before instructions) with header | one row per completed trial, written by a background task shortly after its trial stop (section 4.3) |
| NF trace | `p{P}_b{B}_arrow_nftrace{_rN}.csv` | same | all trace rows of a trial, written by a background task shortly after the trial stop (section 4.3) |
| Dropped frames | `p{P}_b{B}_arrow_droppedframes{_rN}.csv` | same | same |
| SSVEP frames | `p{P}_b{B}_arrow_ssvepframes{_rN}.csv` | same | one row per flickering trial frame (frame 1 to the response / miss frame), same timing |
| Session | `p{P}_b{B}_arrow_session{_rN}.csv` | same; key/value rows written immediately | once |
| Stimulus frames (optional, `logStimulusIntensityEveryFrame`) | `p{P}_b{B}_arrow_stimframes_{yyyyMMdd_HHmmssfff UTC}{_rN}.csv` | `CompleteSessionStart` | batch at each trial end (async), final flush at export |
| Stimframes metadata | same stem + `.metadata.json` | with the stimframes file | — |
| EEG (BciCore only) | `persistentDataPath/BciCoreLogs/eeg_arrow_p{P}_s{B}_{yyyyMMdd_HHmmss local}/…` | on board HELLO (connection), not by the game | see shared doc |

`{P}`, `{B}` = launcher participant and session ("Block number") strings; in the task CSV names invalid file-name characters and `/`, `\` become `_` (`CORE:178-183`); the stimframes name uses the raw strings. `{_rN}`: run 1 has no suffix; if *any* of the five task files of a run already exist, the next run uses `_r2`, `_r3` … up to `_r1000` for **all five** files (`CORE:154-176`). Files are created with `FileMode.CreateNew`; existing files are never appended or overwritten. There is no header-mismatch path and no schema-version column in the five task files (stimframes carries `SchemaVersion = 3`). Aborted sessions leave files with only headers.

Number formats: doubles via `F6` (6 decimals, invariant culture), NaN written as `NaN` (`CORE:210`); booleans as `0/1`; text unquoted except in the session file.

All task-CSV times are **seconds relative to `experimentT0`** = `MonotonicClock.Now` at `BeginSession` (after calibration "Proceed", before the instructions screen; `AGC:605`). `experimentT0` itself is not written to any file (recovery: section 13).

### 10.2 `_trialdata.csv` (`CORE:146`, `CORE:212-222`)

| # | Column | Meaning | Units / time base | Empty/NaN |
|---|---|---|---|---|
| 1 | `TrialNumber` | 1-based trial index | — | |
| 2 | `TrialStart` | CPU end of trial frame 1 (= start marker send time) | s, rel. `experimentT0` | |
| 3–6 | `C1PointDir`, `C1MoveDir`, `C2PointDir`, `C2MoveDir` | `up/down/left/right` | — | |
| 7 | `Cue` | `c1` (Pointing) or `c2` (Moving) | — | |
| 8 | `CueOnsetTime` | CPU end of pre-SSVEP frame 1 (start of the red-flash cue); `TrialStart` if there was no pre-SSVEP period | s, rel. `experimentT0` | ≈ `TrialStart − PreSsvepSec` |
| 9 | `FirstGreenTime` | CPU end of first frame with `NFLevel ≥ 0.9` | s, rel. `experimentT0` | NaN if never green |
| 10 | `ColorOnsetTime` | CPU end of reveal frame (NF reveal = marker 50; timeout reveal = no marker) | s, rel. `experimentT0` | defined for every completed trial |
| 11 | `CorrectResponse` | C1 → `C1PointDir`, C2 → `C2MoveDir` | — | |
| 12 | `ParticipantResponse` | direction or `missed` | — | |
| 13 | `Accuracy` | 1 if correct (also after a timeout reveal) | 0/1 | |
| 14 | `ReactionTime` | response-frame `Update` time − `colorOnsetClock` | s | NaN if no response |
| 15 | `RevealTimeout` | no NF success within `trialLengthSec`; colours revealed by timeout | 0/1 | |
| 16 | `ResponseTimeout` | no response within `ResponseTimeoutSec` after the reveal | 0/1 | |
| 17 | `TrialEnd` | CPU end of last feedback frame (= marker 30) | s, rel. `experimentT0` | |
| 18 | `DroppedFrameCount` | sum of skipped predicted slots from frame 1 to the response / miss frame (section 12) | slots | |
| 19 | `FrequencyC1Hz` | flicker frequency of the C1 group in this trial | Hz | |
| 20 | `FrequencyC2Hz` | flicker frequency of the C2 group | Hz | |
| 21 | `FrequenciesSwapped` | 1 = C1 got f2 and C2 got f1 | 0/1 | |
| 22 | `TrialStartMarker` | start code emitted | 20/21/31–34 | |
| 23 | `NFIndexUsed` | NF channel used, **1-based** | 1/2 | |
| 24 | `PreSsvepSec` | pre-SSVEP length actually shown, `P·ifi` = `round(preSsvepSec/ifi)/refreshHz` (not the setting value) | s | 0 when skipped |
| 25 | `NfSuccess` | colours revealed by NF (= 1 − `RevealTimeout`) | 0/1 | |
| 26 | `Points` | points of this trial (section 8) | int | |
| 27 | `TotalPoints` | running total within this run, including this trial | int | |

The former column `CueFromTrialStart` no longer exists. Derived: response time on the `experimentT0` axis = `ColorOnsetTime + ReactionTime`.

### 10.3 `_nftrace.csv` (`CORE:147`, `CORE:224-232`, rows built at `AGC:904-905`)

One row on trial frames 1, 1+k, 1+2k … with `k = max(1, round(NfTraceIntervalSec/ifi))` (12 at 120 Hz), up to the response / miss frame. Pre-SSVEP and feedback frames are not traced.

| Column | Meaning | Units / base |
|---|---|---|
| `TrialNumber` | | |
| `FrameNumber` | trial frame (1-based) | frames |
| `SampleTime` | `MonotonicClock.Now − experimentT0` when the row is built (late in that frame's `Update`) | s |
| `NFIndexUsed` | 1-based channel | |
| `NFValueRaw` | `nfCurrent` = last fresh value (held; 0 before the first fresh sample in the trial) | source units |
| `NFValueClipped` | `clamp(raw, ±NfClip)` | |
| `NFLevel` | level after this frame's update | 0–1 |
| `InGreenZone` | `NFLevel ≥ 1 − NfWhiteTopRelaxation` | 0/1 |
| `GreenHoldSec` | `greenHoldFrames · ifi` (frozen after reveal) | s |
| `ColorsRevealed` | reveal flag (set in this frame if reveal happened now) | 0/1 |
| `PostCueOnset` | always 1 (the target was cued in the pre-SSVEP period); kept for schema compatibility | 0/1 |
| `NFReadOk` | a fresh sample was consumed **in this frame** (File source: always 1 when readable) | 0/1 |

### 10.4 `_droppedframes.csv` (`CORE:148`, `AGC:884-888`; trial frame 1 to the response / miss frame only)

| Column | Meaning |
|---|---|
| `TrialNumber` | |
| `FrameNumber` | trial frame where a slot jump was detected |
| `VBLTime` | **CPU** time `Elapsed` (s rel. `experimentT0`) when detected — not a VBL timestamp |
| `MissedBySec` | `skippedSlots · ifi` |

### 10.5 `_ssvepframes.csv` (`CORE:149`, `AGC:890-892`)

One row per flickering trial frame, frame 1 to the response / miss frame `F`; pre-SSVEP and feedback frames are not logged. The row of frame `F` holds commanded luminances of a frame whose arrows were cleared for the feedback text before display.

| Column | Meaning | Base |
|---|---|---|
| `TrialNumber`, `FrameNumber` | | |
| `EstimatedDisplayTime` | predicted presentation time of this frame (VSYNC lattice) − `experimentT0` | s |
| `FrameEndTime` | CPU end-of-frame − `experimentT0`; the last logged frame is followed by feedback frames, so it is normally filled | s |
| `PhaseTimeSec` | `predicted − trialPhaseT0` (the `t` of the sinusoid) | s |
| `NominalRefreshSlot` | `round(PhaseTimeSec · RefreshHz)` | slots |
| `BorderLuminanceC1`, `BorderLuminanceC2` | commanded border grey (sRGB code value 0–1) of each group | |
| `FrequencyC1Hz`, `FrequencyC2Hz` | assigned frequencies | Hz |
| `RefreshHz` | controller `refreshHz` for this trial | Hz |

### 10.6 `_session.csv` (`CORE:191-209`; header `Key,Value`)

`Game` = `Arrow Game`; `Shape` = `Triangle`; `Background` = `Plain`; `UtcStart` (ISO-8601 UTC at `CompleteSessionStart`); `RandomSeed` (final seed); `ScreenWidthPx`, `ScreenHeightPx`; `FieldX`, `FieldY` (top-left pixel origin, includes viewport offset), `FieldWidthPx`, `FieldHeightPx`; `ActivePixelScale`; `ObservedRefreshHz` (`refreshHz` at session start); `TargetFrameRate`; `VSyncCount`; `UnityVersion` (quoted); `SettingsJson` = `JsonUtility.ToJson(controller, pretty=true)` — quoted CSV field containing **embedded newlines** and doubled quotes; includes `participant`, `block`, all serialized settings (including `preSsvepSec`, `preSsvepFlashHz`, `preSsvepBorderLuminance` and the points settings) and the hidden `ssvepFrequencyVersion`, `arrowLayoutVersion`, `trialFlowVersion`. Use an RFC-4180 parser.

### 10.7 Stimulus frames (`FrameStimulusCsvLogger`, schema 3)

Created with game tag `"arrow"` (`AGC:671-672`). One row per flickering trial frame (frame 1 to the response / miss frame), recorded at `AGC:898` with: `TrialNumber = trialIndex+1`; `Stage` = `trial` (the code would write `feedback` when `inFeedback` is set, but feedback frames return before the record call, so it never appears; pre-SSVEP frames are not recorded); `PhaseOriginMonotonicSec = trialPhaseT0` (absolute monotonic seconds); `StimulusC1Intensity/C2Intensity` = `BorderLuminanceC1/C2`; frequencies, mean, depth, phases as configured. No rows during ITI/instructions. All `…MonotonicSec` columns are absolute `MonotonicClock` seconds; `ActualPresentationMonotonicSec` is always NaN. Full column semantics: shared doc.

### 10.8 BciCore EEG logs

Written by the in-process server, not by Arrow: folder `eeg_arrow_p{P}_s{B}_{local yyyyMMdd_HHmmss}` (`GameName = "arrow"` set by the launcher). DirectCsv (launcher default): `{stem}_raw.csv`, `_signals.csv`, `_features.csv`, `_health.csv`, `_config.txt`; BinaryThenCsv: `.bin` converted at export; Disabled: none. A new folder starts on every board HELLO (reconnect). DirectCsv logging is closed at the game's export. Arrow-specific content: `marker` columns carry the codes of section 9; `health.csv` gets `trigger_sent:reset|trialstart|success|response|trialstop` rows (`wall_sec` = integer local seconds-of-day). Columns: shared doc.

---

## 11. Settings reference

Effective default = prefab YAML (`PREFAB:48-208`). **The prefab values equal the C# initializers for every field** (`nfSourceType: 2` = `BciCore`, `preSsvepSec: 1.5`, `preSsvepFlashHz: 4`, `doubleCueWidthPx: 520`, `trialFlowVersion: 2`). Runtime values may differ through saved preferences (`CogLab.Games.arrow.v1`) and the launcher's Common tab. "UI label" = `Nicify(fieldName)` as shown in the game tab / standalone settings. **C** = overridden by the launcher Common tab (`Assets/CogLab/App/SharedSettingsCatalog.cs:32-48`; such fields are hidden from the game tab, `CogLabAppController.cs:218`).

**Launcher-supplied (not settings):** participant (`participant` ← `participantNumber`, launcher default `000`), block (`block` ← `sessionNumber`, launcher default `001`; prefab default `000` only used standalone), EEG logging mode (`BinaryThenCsv | DirectCsv | Disabled`, default DirectCsv) (`AGC:310-318`).

| UI label | Field | Default | Unit | C | Meaning |
|---|---|---|---|---|---|
| Trials Per Block | `trialsPerBlock` | 24 | trials | | block length |
| Cue C1 Probability | `cueC1Probability` | 0.5 | — | | fraction of C1 cues (rounded count) |
| Use Fixed Random Seed | `useFixedRandomSeed` | Off | | C | |
| Fixed Random Seed | `fixedRandomSeed` | 918273 | | C | |
| Mix Participant And Block Into Seed | `mixParticipantAndBlockIntoSeed` | On | | | XOR string hashes into seed |
| Pre Ssvep Sec | `preSsvepSec` | 1.5 | s → frames | C | pre-SSVEP red-flash cue period; Common label "Pre-SSVEP period before each trial (seconds) - Leaf / Arrow", range 0–60 (`SharedSettingsCatalog.cs:37`); 0 disables |
| Pre Ssvep Flash Hz | `preSsvepFlashHz` | 4 | Hz (≥ 0.1) | | on/off rate of the red target flash |
| Pre Ssvep Border Luminance | `preSsvepBorderLuminance` | 0.5 | sRGB 0–1 | | steady pre-SSVEP border grey (keep = SSVEP mean) |
| Trial Length Sec | `trialLengthSec` (formerly `cueFirstMaxTrialSec`) | 15 | s | | time for NF success; then timeout reveal |
| Response Timeout Sec | `ResponseTimeoutSec` | 4 | s | | response window from colour onset |
| Feedback Sec | `FeedbackSec` | 1 | s → frames | | after response and after a missed response |
| Iti Sec | `ItiSec` | 5 | s → frames | | |
| Points Nf Success Correct | `pointsNfSuccessCorrect` | 100 | points | | correct after NF reveal |
| Points Nf Failure Correct | `pointsNfFailureCorrect` | 10 | points | | correct after timeout reveal |
| Nf Source Type | `nfSourceType` | BciCore (2) | enum File/Tcp/BciCore/UsbBiosemi | | |
| Nf File Path | `nfFilePath` | `nf.txt` | path | | File source |
| Nf Path Maximum Characters | `nfPathMaximumCharacters` | 1024 | | | unused |
| Nf Tcp Host | `nfTcpHost` | 10.36.17.144 | | | TCP NF host; also UDP trigger host |
| Nf Tcp Port | `nfTcpPort` | 5006 | | | |
| Usb Biosemi Port | `usbBiosemiPort` | 5010 | | C | |
| Nf Tcp Timeout Sec | `nfTcpTimeoutSec` | 10 | s | C | TCP/USB connect timeout (Common min 1 s) |
| Nf Stream Stall Warn Sec | `nfStreamStallWarnSec` | 2 | s | | log-only warning |
| Usb Nf Stall Abort Sec | `usbNfStallAbortSec` | 5 | s | C | 0 disables |
| Data Folder Name | `dataFolderName` | `data` | path | C | |
| Nf Trace Interval Sec | `NfTraceIntervalSec` | 0.1 | s → frames | C | (Common min 0.01) |
| Nf Green Hold Sec | `NfGreenHoldSec` | 1 | s → frames | | |
| Nf Rate Per Unit Per Sec | `NfRatePerUnitPerSec` | 3 | 1/s per NF unit | | integration gain |
| Nf Clip | `NfClip` | 1 | NF units | | |
| Nf White Top Relaxation | `NfWhiteTopRelaxation` | 0.10 | — | | green threshold = 1 − value |
| Frequency C1 Hz | `frequencyC1Hz` | 15 | Hz | C | Stimulus 1 / low |
| Frequency C2 Hz | `frequencyC2Hz` | 17 | Hz | C | Stimulus 2 / high |
| (hidden) | `ssvepFrequencyVersion` | 1 | | | migration marker |
| Randomize Ssvep Frequencies | `randomizeSsvepFrequencies` | On | | | per-trial swap + markers 31–34 |
| Precomputed Phase Horizon Sec | `precomputedPhaseHorizonSec` | 300 | s | | |
| Phase Horizon Safety Margin Sec | `phaseHorizonSafetyMarginSec` | 2 | s | | |
| Ssvep Mean Luminance | `ssvepMeanLuminance` | 0.5 | sRGB 0–1 | | |
| Ssvep Modulation Depth | `ssvepModulationDepth` | 1 | 0–1 | | |
| Phase C1 Degrees / Phase C2 Degrees | `phaseC1Degrees`, `phaseC2Degrees` | 0 / 0 | deg | | |
| Requested Display Refresh Rate Hz | `requestedDisplayRefreshRateHz` | 120 | Hz | C | Android mode request and `targetFrameRate` |
| Target Frame Rate Override | `targetFrameRateOverride` | 0 | fps | | >0 overrides target |
| Vertical Sync Count | `verticalSyncCount` | 1 | | C | |
| Abort Trial On Refresh Rate Change | `abortTrialOnRefreshRateChange` | On | | | |
| Refresh Rate Change Tolerance Hz | `refreshRateChangeToleranceHz` | 0.5 | Hz | | |
| Minimum Valid Refresh Hz | `minimumValidRefreshHz` | 30 | Hz | | |
| Fallback Refresh Hz | `fallbackRefreshHz` | 60 | Hz | | |
| Run In Background | `runInBackground` | On | | | |
| Prevent Screen Sleep | `preventScreenSleep` | On | | | |
| Log Stimulus Intensity Every Frame | `logStimulusIntensityEveryFrame` | Off | | C | stimframes file |
| Trigger Port | `triggerPort` | 5007 | | C | UDP marker port |
| Reset / Trial Start / Trial Start C2 / Success / Response / Trial Stop Trigger | `resetTrigger`, `trialStartTrigger`, `trialStartC2Trigger`, `successTrigger`, `responseTrigger`, `trialStopTrigger` | 0 / 20 / 21 / 50 / 40 / 30 | code | | |
| Use Responsive Sizing | `useResponsiveSizing` | On | | | |
| Reference Short Side Px | `referenceShortSidePx` | 1080 | px | | |
| Minimum / Maximum Screen Scale | `minimumScreenScale`, `maximumScreenScale` | 0.05 / 4 | | | |
| Auto Fit Minimum Fraction / Step Fraction | `autoFitMinimumFraction`, `autoFitStepFraction` | 0.25 / 0.05 | | | |
| Stimulus Width / Height Fraction | `stimulusWidthFraction`, `stimulusHeightFraction` | 1 / 1 | | | of safe area |
| Safe Area Padding Reference Px | `safeAreaPaddingReferencePx` | 0 | px | | |
| Arrow Size Px | `arrowSizePx` | 150 | px @1080 | | length L |
| Arrow Width Multiplier | `arrowWidthMultiplier` | 0.42 | | | W = L·m |
| Arrow Border Multiplier | `arrowBorderMultiplier` | 0.20 | | | B = L·m |
| Arrow Speed Px Per Sec | `arrowSpeedPxPerSec` | 200 | px/s @1080 | | |
| Arrows Per Flock | `arrowsPerFlock` | 8 | | | per group, 2–100 |
| (hidden) | `arrowLayoutVersion` | 1 | | | migration marker |
| Lane Clearance Margin Px | `laneClearanceMarginPx` | 6 | px | | floor raised to 20 % of outer size |
| Max Field Shrink Px | `maxFieldShrinkPx` | 400 | px | | |
| Min Repeats Per Axis | `minRepeatsPerAxis` | 1 | | | |
| Verify Arrow Paths At Setup | `verifyArrowPathsAtSetup` | On | | | also consumes session RNG |
| Verification Max Frames | `verificationMaxFrames` | 40000 | frames | | |
| Double Cue Width / Cue Height / Corner Radius Px | `doubleCueWidthPx`, `cueHeightPx`, `cueCornerRadiusPx` | 520 / 90 / 20 | px | | whole double cue; each half = width/2 |
| Cue Corner Segments | `cueCornerSegments` | 8 | | | |
| Cue Font Size / Cue Character Size | `cueFontSize`, `cueCharacterSize` | 64 / 0.5 | | | max cue-word px = 64·0.5·s |
| Cue Text Outline Px | `cueTextOutlinePx` | 2 | px | | |
| Feedback Font Size Px | `feedbackFontSizePx` | 96 | px @1080 | | centre feedback text |
| Enable Keyboard Arrows | `enableKeyboardArrows` | On | | C | |
| Enable Swipe Responses | `enableSwipeResponses` | On | | | |
| Escape Ends Block | `escapeEndsBlock` | On | | | |
| Swipe Threshold Px | `swipeThresholdPx` | 40 | px @1080 | | |
| C1/C2/Success/Failure/Pre Ssvep Flash/Green Zone/Background/Cue Text/Cue Text Outline/Instruction Border Srgb | colours | see 6.4 (`preSsvepFlashSrgb` = 255,0,0) | sRGB | | |
| Ui Reference Short Side Px, Minimum/Maximum Ui Scale, Title/Body/Center/Button Font Size | UI | 1080, 0.15, 4, 35, 25, 22, 26 | | | |
| Application Title, Participant Label, Block Label, Continue Button Label, Begin Block Button Label | UI text | see prefab | | | `continueButtonLabel` unused |
| Cue C1 Word / Cue C2 Word | `cueC1Word`, `cueC2Word` | Pointing / Moving | | | |
| Correct/Incorrect/Missed Feedback Text, Points Suffix, Missed Response Text | `correctFeedbackText`, `incorrectFeedbackText`, `missedFeedbackText`, `pointsSuffix`, `missedResponseText` | Correct / Incorrect / Missed / points / missed | | | feedback shows `"<verdict>\n+<N> points"`; `missed` is written to the CSV |
| Completed Title, Instruction C1/C2 Label, Instructions Text | | see prefab | | | default instructions (`AGC:204`, `PREFAB:183-205`): target borders flash red before each trial; colours also revealed when time runs out; bottom box = orange → MOVING, blue → POINTING; points 100 / 10 / 0 |
| (hidden) | `trialFlowVersion` | 2 | | | migration marker for the instruction text and the pre-SSVEP defaults |
| Nf Path Label, Resolved Nf Path Label | | | | | unused |
| Participant / Block | `participant`, `block` | 000 / 000 | | | standalone only; launcher overrides |
| Cue Bottom Margin Px | `cueBottomMarginPx` | 24 | px | | gap between the double cue and the bottom of the safe area |
| Panel/Soft Panel/Accent/Accent Hover/Secondary Button Srgb, Welcome Subtitle, Play/Settings/Back Button Label, Time/Score/Reached Board Label | UI | see prefab | | | |

Removed settings: `cueFromTrialStart` (replaced by `preSsvepSec`, also in the Common tab), `cueWidthPx`, `cuePosition` and the `CueScreenPosition` enum; old saved values for them are ignored.

Saved-profile migrations on load (`ArrowGameModule.ApplySavedSettings`, `Assets/Games/Arrow/Scripts/ArrowGameModule.cs:6-12`; `GameModule.cs:70`): unversioned 17/19 Hz → 15/17 Hz; `cueFirstMaxTrialSec` → `trialLengthSec`; unversioned 180 px / 0.5 / 4 per group → 150 / 0.42 / 8 (`MigrateSavedLayout`, `AGC:271`); `MigrateTrialFlow` (`AGC:292-302`): nothing if the saved `trialFlowVersion ≥ 2`; below 1 (or missing) → `instructionsText` reset once to the new default; below 2 → `preSsvepSec` 1 → 1.5 and `preSsvepFlashHz` 2 → 4 only where the saved value is still the old default (custom values kept); then `trialFlowVersion = 2`. Instruction edits made after that are kept.

---

## 12. Timing & clock semantics

| Clock | Definition | Used for |
|---|---|---|
| `MonotonicClock.Now` | `Stopwatch.GetTimestamp()/Frequency` (s) | all game times |
| `experimentT0` | `MonotonicClock.Now` at `BeginSession` | origin of every task-CSV time column and HUD TIME |
| `trialPhaseT0` | `PresentationClock.Capture().presentationTime` of trial frame 1 (absolute monotonic s) | SSVEP phase origin; `PhaseOriginMonotonicSec` in stimframes |
| Predicted presentation | `VsyncLattice` time slot (Android Choreographer / frame timeline when available, else monotonic fallback) | `EstimatedDisplayTime`, `PhaseTimeSec` |
| CPU end of frame | `WaitForEndOfFrame` callback time | `CueOnsetTime` (pre-SSVEP frame 1), `TrialStart`, `FirstGreenTime`, `ColorOnsetTime`, `TrialEnd`, `FrameEndTime`, marker send times (except 40) |
| CPU `Update` time | inside `Update` | `SampleTime` (trace), `VBLTime` (dropped), RT end point, marker 40 |
| EEG | board sample index `seq` (rate in `_config.txt`) | no shared clock with the game |

* **Predicted vs actual**: no actual scanout timestamp exists (stimframes `ActualPresentationMonotonicSec = NaN`). `EstimatedDisplayTime` is a prediction. Event columns (`TrialStart`, `ColorOnsetTime`, …) are CPU end-of-frame times, typically before the predicted presentation of the same frame; the per-frame offset is `EstimatedDisplayTime(frame) − FrameEndTime(frame)` from `_ssvepframes.csv`.
* **"Dropped frame"** in this game = a jump of more than one predicted lattice slot between consecutive trial frames (`slot > previous+1`, `AGC:884-888`), checked only from trial frame 1 to the response / miss frame. The shared lattice advances exactly one slot per Unity frame unless ≥ 1.75 periods passed since the last sample or drift persisted 3 frames (`PresentationClock.cs:21-41`), so this counts long CPU frame intervals, not proven physical drops. Repeated slots are not counted. The lattice period comes from the presentation clock's own refresh estimate while `NominalRefreshSlot` uses the controller `refreshHz`; if they differ, slot arithmetic is inconsistent.
* **Precision**: CSV values are rounded to 1 µs (`F6`); event times are quantised to frames (~8.33 ms at 120 Hz, 16.7 ms at 60 Hz).
* **Frame-counted intervals** (pre-SSVEP period and its flash timing, feedback, ITI, green hold, trace interval) lengthen in real time when frames are slow; NF integration and motion per frame use nominal `ifi`, so they slow down too. Seconds-based limits (reveal deadline, response window) are not affected.
* **Refresh-rate guard**: `refreshHz`/`ifi` are fixed per trial; a deviation > 0.5 Hz of the observed rate aborts the session (Fatal).

---

## 13. Analysis guide

### 13.1 Joining task files

* Key: (`participant`, `block`, run suffix) from the file name; within a run, `TrialNumber` joins trialdata ↔ nftrace ↔ droppedframes ↔ ssvepframes ↔ stimframes; `(TrialNumber, FrameNumber)` joins nftrace ↔ ssvepframes ↔ droppedframes.
* stimframes ↔ ssvepframes: within a trial the n-th stimframes row (ordered by `UnityFrame`) is `FrameNumber = n`. Then `experimentT0 = PredictedPresentationMonotonicSec − EstimatedDisplayTime` (constant to ~1 µs; check it). Alternatively `experimentT0 = PhaseOriginMonotonicSec − EstimatedDisplayTime(frame 1)`.
* Trials ended by Fatal/Escape/Exit are absent from all task CSVs.

### 13.2 Aligning EEG markers with CSV rows (BciCore DirectCsv)

1. In `_raw.csv`/`_signals.csv`, find marker onsets (sample where `marker` changes to a non-zero code). Use the board sample rate from `_config.txt`.
2. Take the onsets with codes in {20, 21, 31–34} in order; the k-th maps to `TrialNumber = k` for completed trials. Verify `code == TrialStartMarker`. A final start without a trial row = interrupted trial (followed by the export 30).
3. For trial k with start-marker sample time `t_s` (EEG clock): any CSV time X of that trial maps to `t_s + (X − TrialStart)`.
4. Validate per trial: `(t_50 − t_s) ≈ ColorOnsetTime − TrialStart` (only `NfSuccess = 1`; timeout reveals have no 50, use `t_s + (ColorOnsetTime − TrialStart)`); `(t_30 − t_s) ≈ TrialEnd − TrialStart`; `t_40 − t_s ≈ ColorOnsetTime + ReactionTime − TrialStart` (40 is sent slightly after `now`). Residuals give marker-transport jitter.
5. Visual onset correction: photons of frame 1 ≈ `t_s + (EstimatedDisplayTime[frame 1] − TrialStart)` (+ unknown display latency).
6. `health.csv` `trigger_sent:*` rows give the software send order (integer-second wall clock only; not for timing). The initial reset (0) is normally not visible in EEG (section 14).
7. USB Biosemi / TCP / File modes: EEG is recorded outside this app; the same marker sequence arrives at the bridge / UDP listener.

### 13.3 Epoching

| Epoch | Start | End | Notes |
|---|---|---|---|
| Pre-SSVEP cue period | start − (`TrialStart − CueOnsetTime`) | start | moving arrows, steady grey borders, 4 Hz red flash of the cued group, no flicker; no marker of its own |
| SSVEP / NF period | start marker (+ frame-1 presentation offset) | 50, or the timeout reveal at start + (`ColorOnsetTime − TrialStart`) ≈ start + `trialLengthSec` if `RevealTimeout = 1` | cued frequency = `FrequencyC1Hz` if `Cue = c1` else `FrequencyC2Hz`; NF channel `NFIndexUsed` |
| Pre-reveal fixed window | start | start + 1…3 s | exclude trials revealing earlier if needed |
| Post-reveal / decision | colour onset (50 or derived) | 40, or window expiry (`ColorOnsetTime + ResponseTimeoutSec`) | colours visible, flicker continues; split by `NfSuccess` |
| Response-locked | 40 − 1 s | 40 + 0.5 s | the field is emptied from the response frame on |
| Feedback | 40 (or window expiry) | 30 | `FeedbackSec` frames; centre text only, **no flicker** |
| Baseline | ITI: 30 + 0.5 s | next start − `PreSsvepSec` | blank screen, HUD visible; the next trial's pre-SSVEP period precedes its start marker |

SSVEP reference signals: `sin(2π f (t − t_phase0) + φ)` with `t_phase0` = presentation of frame 1, or use the exact per-frame `BorderLuminance*` series at `EstimatedDisplayTime` (the commanded waveform; convert through the display EOTF for physical luminance).

### 13.4 Performance metrics

* NF success rate = mean(`NfSuccess`) = mean(`RevealTimeout == 0`); time to NF reveal = `ColorOnsetTime − TrialStart` over `NfSuccess = 1` (≈ `trialLengthSec` by construction for timeout reveals); time to first green = `FirstGreenTime − TrialStart`; minimum possible ≈ 1.3 s.
* Accuracy among responded trials = mean(`Accuracy` | `ResponseTimeout = 0`), split by `NfSuccess`; overall accuracy (as on the summary screen) = mean(`Accuracy`) over all rows.
* Points: `Points` per trial; `TotalPoints` of the last row of a run = summary Points.
* RT: `ReactionTime` (responded trials).
* Error types: compare `ParticipantResponse` with `C1PointDir`, `C1MoveDir`, `C2PointDir`, `C2MoveDir` (wrong dimension of target group vs other group).
* Split by `Cue`, by cued frequency, by `FrequenciesSwapped`, by direction combination, by trial position.
* NF trace: per trial `NFLevel(t)`, fraction of rows in green, `NFReadOk` rate (fraction of sampled frames with a fresh value), `NFValueRaw` distribution before reveal.

### 13.5 Sanity checks

1. Row counts: trialdata rows = completed trials ≤ `trialsPerBlock`; ssvepframes rows per trial = frame of the response / miss ≈ (`TrialEnd − TrialStart`)·`RefreshHz` + 1 − round(`FeedbackSec`·`RefreshHz`).
2. Every trial: four distinct directions; `CorrectResponse` matches the rule; `TrialStartMarker` and `NFIndexUsed` match the table in 7.2; `FrequencyC1Hz/C2Hz` consistent with `FrequenciesSwapped`.
3. Balance (full blocks): C1 count = round(N·p); swapped count per cue = floor(n_cue/2) (±1 for odd counts).
4. Exactly one of {response given, `ResponseTimeout`} per row; `ReactionTime` NaN iff no response; `ReactionTime ≤ ResponseTimeoutSec`; `NfSuccess == 1 − RevealTimeout`.
5. `CueOnsetTime ≤ TrialStart < ColorOnsetTime < TrialEnd`; `TrialStart − CueOnsetTime ≈ PreSsvepSec`; `FirstGreenTime ≤ ColorOnsetTime` when defined; `ColorOnsetTime − TrialStart ≤ trialLengthSec + 1 frame`, ≈ `trialLengthSec` when `RevealTimeout = 1`. `TrialEnd − ColorOnsetTime ≈ ReactionTime + FeedbackSec` (response) or `ResponseTimeoutSec + FeedbackSec` (missed). `Points == (Accuracy ? (NfSuccess ? 100 : 10) : 0)` with default settings; `TotalPoints` = cumulative sum of `Points` in the run.
6. `PhaseTimeSec` of frame 1 = 0 and increments ≈ `1/RefreshHz`; `BorderLuminance = 0.5 + 0.5 sin(2πf·PhaseTimeSec)` for default settings.
7. `DroppedFrameCount` = sum of `MissedBySec/ (1/RefreshHz)` in droppedframes for the trial.
8. EEG: number of start markers = trial rows (+1 if interrupted); every start followed by 30; a 50 exactly in rows with `NfSuccess = 1`; a 40 exactly in rows with `ResponseTimeout = 0`; one extra trailing 30.
9. `_session.csv`: `ObservedRefreshHz` equals `RefreshHz` in ssvepframes; `ActivePixelScale` and field size plausible for the device.

---

## 14. Known caveats / doc discrepancies

**Documentation vs code**

1. Arrow has no cue-onset trigger field and sends no cue-onset marker; the pre-SSVEP cue period has no marker either. The README now says the same; README versions up to commit `5741b44` still listed a **45 "cue onset"** marker for Leaf/Arrow.
2. README versions up to commit `5741b44` described a "pre-cue mode" in which legacy start is 20 for either cue (the current README no longer does). Pre-cue mode was removed (commit `9fa6421`); Arrow always sends 20 for C1 and 21 for C2 when shuffling is Off (`AGC:771-772`). The README's "pre-cue" is unrelated to the current pre-SSVEP period. The README section "Leaf and Arrow independent response timing" (from `README.md:405`) now describes the current flow (pre-SSVEP period, timeout reveal, feedback, points).
3. Instruction text (`PREFAB:183-205`, `AGC:204`) now matches the trial flow (red pre-SSVEP flash, timeout reveal, bottom double cue, points). Profiles saved before the change get it once through `MigrateTrialFlow`; that one-time reset also overwrites any custom instruction text saved earlier. Profiles saved at `trialFlowVersion` 1 keep their text but have the old pre-SSVEP defaults (1 s, 2 Hz) moved to 1.5 s / 4 Hz; read the actual length from `PreSsvepSec`.
4. Comment at `AGC:796-797` says the phase origin is "the preceding frame end"; the code uses the **predicted presentation time** of frame 1 (`AGC:880`).
5. `BciCoreNfReader.cs` header maps index 0 → "C1 / Pointing", 1 → "C2 / Moving". With shuffling, the index is the **frequency channel** (0 = Stimulus 1/low), not the cue.
6. `BciCore-Documentation.md` lists EEG files as `eeg_<ts>_*.csv` with older column names and says UDP 5007 marker output was removed. The code names folders `eeg_arrow_p…_s…_<ts>`, uses `wall_sec,…` health columns, and `BciCoreTriggerSender` still sends a UDP copy of every marker to `nfTcpHost:triggerPort`.
7. `_droppedframes.csv` column `VBLTime` is a CPU `Update` time, not a VBL.
8. README's display-telemetry paragraph lists sub-games without Arrow.

**Behaviour, bugs and oddities**

9. **Target cue only before SSVEP onset**: the target group is shown only by the red pre-SSVEP flash; during the NF phase both groups look identical (grey/green fill), so the participant must remember the target. The double cue shows the colour → rule mapping, not the target. With `preSsvepSec = 0` (or below half a frame) there is no target cue at all, yet `CueOnsetTime = TrialStart` is written. The 4 Hz red flash is itself a periodic stimulus right before SSVEP onset.
10. **Extra trial-stop marker**: `StartSessionExport` always sends 30 (`AGC:493`), producing an unpaired 30 after the last trial and on Escape/Exit from any state (also Instructions, Summary, Fatal).
11. **Interrupted trials**: Escape/Exit/Fatal mid-trial discard the trial's CSV rows (and its points), but its start (and possibly 50/40) markers are in the EEG. An interruption during the pre-SSVEP period leaves no start marker; a refresh-rate abort there sends no 30 of its own.
12. **No 30 on phase-horizon Fatal** (`AGC:883`); the export 30 arrives only when the operator exits.
13. **Reset marker in BciCore mode** is sent right after `StartServer`, before the board can connect and before the EEG logger exists: it reaches only the UDP fallback, not the EEG file or `health.csv`. Code 0 is also indistinguishable from "no marker" in a marker column.
14. **Marker 40 timing** differs from other markers: sent mid-`Update`, not at end of frame; its CSV time is not logged separately.
15. Event times are CPU end-of-frame, not presentation times; RT is frame-quantised and not input-event based (section 8).
16. NF integration, motion, green hold, pre-SSVEP period (and its flash timing), feedback and ITI are frame-counted with nominal `ifi`; slow frames stretch them in real time.
17. `experimentT0` is not logged; recover it from stimframes (section 13.1) or treat CSV times as relative.
18. Arrow initial positions depend on `verifyArrowPathsAtSetup` because `ValidateLayouts` consumes the session RNG (`AGC:690`).
19. `string.GetHashCode` in the seed mix is runtime-dependent; use the logged `RandomSeed`.
20. `cueC1Probability` count uses banker's rounding.
21. `_session.csv` `SettingsJson` is multi-line inside a quoted field; `ParticipantResponse` is written unquoted (a comma in `missedResponseText` would break the row).
22. Stimframes file names use unsanitised participant/session strings and a UTC timestamp; task CSVs sanitise names.
23. `BciCoreNfReader` writes both NF frames (`Smi14gt18Shaped`, `Smi18gt14Shaped`) and HW-CCA frames (`FbAgtB`, `FbBgtA`) into the same pair; if the board streams both, values alternate between sources. Channel names refer to 14/18 Hz while the stimulus defaults are 15/17 Hz: verify the board's NF target frequencies.
24. File NF source: `NFReadOk` is 1 on every readable frame (no freshness), and stall warnings are not issued.
25. With shuffling Off there is no marker-code validation; legacy start codes are never validated.
26. Common-tab bounds differ from field minima (connection timeout ≥ 1 s vs 0.1; trace interval ≥ 0.01 vs 0.001; display rate ≥ 30).
27. HUD (time, points, NF-reveal count) and the exit button are drawn over the stimulus field during the pre-SSVEP period, trials and ITI. The bottom double cue can overlap the lower edge of the field.
28. Unused serialized settings exposed in the UI: `nfPathMaximumCharacters`, `nfPathLabel`, `resolvedNfPathLabel`, `continueButtonLabel`; `TrialDefinition.CueWord` is hard-coded and unused.
29. Escape during `Calibration` starts the export while the calibration component may still be attached.
30. `RefreshPresentationTiming` sets `Application.targetFrameRate` to `requestedDisplayRefreshRateHz` (120) even when the observed panel rate is lower (`AGC:399-400`).
31. In standalone (non-launcher) use, exiting a session returns to Setup with the BciServer still running and its EEG logger already closed; a second run logs EEG only after a board reconnect.
32. **Timeout reveals have no marker**: `ColorOnsetTime` exists for every row, but the EEG has a 50 only for NF-success trials; derive the timeout-reveal time from the start marker (section 13.2). REACHED COLOR / "Reached color" count only NF reveals.
33. **Feedback and pre-SSVEP frames are not logged**: ssvepframes, nftrace, droppedframes and stimframes stop at the response / miss frame (stimframes `feedback` stage never occurs) and start at trial frame 1. The last ssvepframes row is a commanded frame whose arrows were cleared before display. `PreSsvepSec` logs the length actually shown (`P·ifi`), not the setting.
34. **NF stall clock** is reset at `StartTrial`, before the pre-SSVEP period, in which NF is not read; the pre-SSVEP time (1.5 s) counts towards `nfStreamStallWarnSec` / `usbNfStallAbortSec`.

---

## 15. Differences from Leaf

Obtained by diffing `Assets/Games/Arrow/Scripts/*` against `Assets/Games/Leaf/Scripts/*` (after renaming Arrow → Leaf) and the two prefabs. Everything not listed is identical, including: state machine, `TrialDefinition`/`TrialPlanner`, SSVEP schedule, NF equations, response rule, timing logic, trigger field names/defaults/send points, the four CSV headers and their column semantics, the pre-SSVEP period, timeout reveal, points, feedback, the double cue, the HUD, `MigrateTrialFlow`, the lead-in ITI before trial 1, the swipe reset at colour onset, and the frame-pacing measures (GC pause, background CSV writes; only the `[LeafGame]`/`[ArrowGame]` log prefixes differ).

| Area | Leaf | Arrow |
|---|---|---|
| Stimulus shape | leaf polygon: stem + two curved sides, `2·leafArcPoints+3` vertices (`leafArcPoints` 10, clamped 5–64), rendered as a triangle fan from the centre | 3-vertex triangle, one triangle per copy (`REND:105-114`) |
| Gameplay background | sprite from `Resources/LeafGame/BackgroundTexture` (`backgroundTextureResource`), sorting order −100; setup screen uses the texture | plain `backgroundSrgb` (black) camera clear |
| Effective NF source | code `Tcp`, prefab `3` = **UsbBiosemi** | code and prefab **BciCore** |
| `nfFilePath` (prefab) | absolute Windows path `C:\Users\…\nf.txt` | `nf.txt` |
| `minimumScreenScale` / `autoFitMinimumFraction` | 0.25 / 0.35 | 0.05 / 0.25 |
| Group size field | `leavesPerFlock` 8, Range 1–100 | `arrowsPerFlock` 8, Range 2–100, validated ≥ 2 |
| Size fields | `leafSizePx` 150, `leafWidthMultiplier` 0.42, `leafBorderMultiplier` 0.2, `leafSpeedPxPerSec` 200 | `arrow*` equivalents, same values |
| Lane clearance | raw `laneClearanceMarginPx·s` (6 px) | `max(6·s, 0.20·max outer dimension)` (42 px at s = 1) |
| Parallel lanes | all fitting lanes, alternating, may be odd | capped at 2n, even, C2 lane order mirrored |
| Perpendicular lanes | minimum lane count `ceil(n/slots)` (could collapse to one central line) | `min(maxLanes, n)` lanes, ≥ 2 required |
| Path verification | fails only on overlap | also fails if clearance < required clearance |
| `ValidateSettings` | only SSVEP/marker validation | plus geometry, trial, timing, scaling checks (`AGC:281-298`) |
| Saved-profile migration | shared + `MigrateTrialFlow` | shared + `MigrateTrialFlow` + `MigrateSavedLayout` (hidden `arrowLayoutVersion`) |
| Target frame rate in `RefreshPresentationTiming` | rounded observed `refreshHz` | `requestedDisplayRefreshRateHz` (120) |
| Extra field | `requestClosestSupportedRefreshRate` (declared, unused) | — |
| Task file names | `p{P}_b{B}_leaves_{trialdata,nftrace,droppedframes,ssvepframes}.csv`; participant not sanitised | `p{P}_b{B}_arrow_{…}{_rN}.csv` + `_arrow_session.csv`, sanitised |
| Re-runs | **appends** to existing files if the header matches; otherwise new file `…_yyyyMMdd_HHmmss.csv` | never appends; reserves a new `_rN` set of five files |
| Session metadata | none; seed not recorded | `_session.csv` with seed, field, scale, refresh, settings JSON |
| CSV creation order | before field resolution / path verification | after |
| Stimframes game tag | `leaf` | `arrow` |
| EEG folder (launcher) | `eeg_leaf_…` | `eeg_arrow_…` |
| Fallback camera | unparented "Main Camera" | "Game Camera" parented to the controller |
| `ExitToMainMenu` | private | public |
| Refresh-abort message | reports `Screen.currentResolution` | reports `DisplayRateManager.ObservedRefreshRateHz` (message text only) |
| Instruction text | "Two groups of leaves move around the screen …" | "Two groups of triangular arrowheads move around a plain background …"; otherwise the same rules (red flash, timeout reveal, bottom box, points) |
| `nfPathLabel` | `NF file: ` | `NF file path` |
| Launcher colour | (0.17, 0.58, 0.32) green | (0.2235, 0.5098, 0.7647) blue |
| Editor tooling | custom inspector (`Assets/Games/Leaf/Editor`), `[MovedFrom]` attribute | none |
| Unused helper | `LeafVisualRenderer.Offsets` | — |

Session file `Shape`/`Background` keys (`Triangle`/`Plain`) exist only in Arrow.

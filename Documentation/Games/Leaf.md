# Leaf Game — Direction Response (`leaf`)

Reference for analysing data from the Leaf game in the CogLab Games Android app (`org.iisc.coglab.games`). Every statement was checked against the source in this repository. Where the README, `BciCore-Documentation.md` or older reports disagree with the code, the code is treated as correct and the difference is listed in section 14.

Shared infrastructure (clocks, presentation prediction, NF transports, BciCore server and EEG logs, stimulus-frame logger, launcher settings) is described in [00-Shared-Infrastructure.md](00-Shared-Infrastructure.md). This document gives only what is specific to Leaf, and states exactly which part of each shared component Leaf uses.

Abbreviations: **NF** = neurofeedback; **C1 / C2** = the two leaf groups ("flocks"). C1 always has colour `c1Srgb` and always means the *Pointing* rule; C2 always has colour `c2Srgb` and always means the *Moving* rule. **T0** = `experimentT0` (see section 12). **ifi** = nominal inter-frame interval `1/refreshHz`.

---

## 1. Overview & paradigm

**What the participant sees.** Two groups of leaf shapes (default 8 per group, 16 in total) move continuously across a rectangular field and wrap around its edges. Every leaf in a group has the same *pointing* direction (where the tip faces) and the same *moving* direction (where it travels). Across the two groups the four features {C1 pointing, C1 moving, C2 pointing, C2 moving} are always the four different directions Up, Down, Left and Right (`Assets/Games/Leaf/Scripts/LeafGameCore.cs:51-58`).

- Each leaf is drawn as a filled inner shape with a larger outer shape behind it. The visible ring between them is the **border**.
- **Pre-SSVEP period** (`AppState.PreSsvep`, `preSsvepSec`, default 1.5 s, counted in frames; `LeafGameController.cs:770-802`). Before each trial the trial's layout is already on screen and moving. Both groups have black fills (`nfLevel` 0) and steady grey borders (`preSsvepBorderLuminance` 0.5, equal to the SSVEP mean, so there is no luminance jump at SSVEP onset). The **cued group's** borders flash bright red (`preSsvepFlashSrgb`, 255,0,0) as an on/off square wave at `preSsvepFlashHz` (4 Hz). Only whole flashes whose red half ends by the last displayed pre-SSVEP frame are shown, so that frame is always steady grey and the SSVEP starts from grey. This red flash is the only cue to *which group* to attend. There is no flicker, no marker and no NF integration in this period.
- **Trial (SSVEP) period.** The hand-over to the trial happens in the same frame, so motion continues without a skipped or repeated frame. From trial frame 1 the border of each group flickers sinusoidally in grey: C1 at `FrequencyC1Hz` and C2 at `FrequencyC2Hz` (SSVEP tagging; defaults 15 Hz and 17 Hz, randomly swapped per trial). The trial-start marker is sent at the end of trial frame 1.
- Before the reveal, both groups have the same fill: grey with value `nfLevel` (0 to 1), which is continuous NF feedback. While `nfLevel >= 1 - NfWhiteTopRelaxation` (default 0.9) the fill turns light green (`greenZoneSrgb`).
- After the level has stayed in the green zone for `NfGreenHoldSec` (default 1 s, counted in frames), the **colour reveal** happens (NF success, marker 50). C1 is filled with `c1Srgb` (deep-sky-blue, sRGB 0,191,255) and C2 with `c2Srgb` (dark orange, 255,140,0).
- If `trialLengthSec` (15 s) runs out without NF success, the colours are **revealed anyway** (`RevealTimeout = 1`, `NfSuccess = 0`). This reveal sends **no** success marker and does not count towards REACHED COLOR. The normal response window opens in both cases.
- **Double cue** (static rule reminder). From the first pre-SSVEP frame to the end of the trial (including feedback) a split box sits at the bottom of the safe area: left half orange (`c2Srgb`) with "Moving", right half blue (`c1Srgb`) with "Pointing". It shows the rule for each colour; it does not show which group is the target.
- After the reveal the participant reports a direction with an arrow key or a swipe. Responses made before the reveal is committed are ignored and not logged.
- **Feedback.** After a response the leaf field is emptied and centre-screen text shows "Correct" (green, `successSrgb`) or "Incorrect" (red, `failureSrgb`) on one line and "+N points" on the next, for `FeedbackSec` (default 1 s, frames). If the response window runs out, red "Missed" / "+0 points" is shown for `FeedbackSec` in the same way, and only then does the trial end (`trialstop`). An inter-trial interval (ITI) of `ItiSec` (default 5 s, frames) follows, with the leaves and the double cue hidden.
- **Points** (`TrialPoints`, `LeafGameController.cs:927`): NF success + correct = `pointsNfSuccessCorrect` (100); NF failure (timeout reveal) + correct = `pointsNfFailureCorrect` (10); incorrect or missed = 0.
- A heads-up display (HUD) is drawn throughout the pre-SSVEP period, trials and ITIs. In the top-right corner it shows TIME, SCORE (total points of the run) and REACHED COLOR (count of NF-earned reveals). In the top-left corner it shows an "Exit to menu" button (`LeafGameController.Aesthetics.cs:180`, `DrawGameplayHud`).

**Correct-response rule** (`LeafGameCore.cs:25`):

| Cue | Group / colour | Rule | Correct response |
|---|---|---|---|
| C1 | `c1Srgb` (blue) | Pointing | `C1PointDir` |
| C2 | `c2Srgb` (orange) | Moving | `C2MoveDir` |

The four features always use four different directions, so every possible response identifies a single feature. This allows errors to be classified (section 13).

**BCI purpose.** The NF value read each frame comes from the NF channel matched to the *cued group's actual SSVEP frequency* (section 7). The reveal therefore requires sustained SSVEP-based attention to the cued group. This is a covert-attention / SSVEP neurofeedback gate followed by a feature-based direction-response task.

**How the target is cued.** The target group is cued only by the red border flash in the pre-SSVEP period, before any SSVEP flicker starts. During the trial both groups look identical until the reveal, so the participant must remember which group flashed. `CueOnsetTime` is the onset of the pre-SSVEP period (or `TrialStart` when `preSsvepSec` is 0). The double cue at the bottom shows only the colour → rule mapping, which becomes useful after the reveal. The default instruction text describes this flow (it is replaced once in old saved settings, see section 11).

Paradigm background: `output/pdf/Leaf_task_scientific_report.pdf` (September; predates the current marker, cue and trial-flow changes, so treat it as background only).

---

## 2. Code map

| Item | Value |
|---|---|
| Game ID | `leaf` (`Assets/Games/Leaf/Prefabs/LeafGame.prefab:222`) |
| Display name (launcher) | `Leaf Game` (`LeafGame.prefab:223`). The scene instance renames the GameObject to "Leaf Game" (`Assets/CogLab/App/Scenes/CogLab.unity:647-650`) |
| In-game title | `applicationTitle` = "Leaf Game - Direction Response" (standalone welcome screen only) |
| PlayerPrefs key | `CogLab.Games.leaf.v1` (`Assets/CogLab/Framework/GameModule.cs` `SettingsKey`) |
| Launcher module class | `LeafGame.LeafGameModule : CogLab.Framework.GameModule` (`Assets/Games/Leaf/Scripts/LeafGameModule.cs`) |
| Session controller | `LeafGame.LeafGameController : MonoBehaviour, IGameSession` (partial; two files) |
| Assembly | `CogLab.Games.Leaf` (`Assets/Games/Leaf/CogLab.Games.Leaf.asmdef`), references `CogLab.Framework`, `CogLab.Shared`, `BciCore`, `Unity.InputSystem`, `Unity.ugui` |
| Editor assembly | `CogLab.Games.Leaf.Editor` (Editor platform only) |
| Prefab | `Assets/Games/Leaf/Prefabs/LeafGame.prefab`: one GameObject with a **disabled** `LeafGameController` (the settings template) and an enabled `LeafGameModule` |
| Resources | `Assets/Resources/LeafGame/BackgroundTexture.png` (gameplay and setup background) |

| File | Role |
|---|---|
| `Scripts/LeafGameController.cs` | Serialized settings, state machine, session start, pre-SSVEP period, NF reading and integration, trial loop, markers, response handling, points, standalone settings parsing, `MigrateTrialFlow` |
| `Scripts/LeafGameController.Aesthetics.cs` | Background sprite, double-cue positioning, all IMGUI screens (welcome, settings, instructions, HUD, export, summary, fatal), extra visual settings |
| `Scripts/LeafGameCore.cs` | Enums (`Direction4`, `CueKind`), `TrialDefinition`, `DirectionUtil`, `TrialPlanner` (randomisation), `SsvepPhaseSchedule` (flicker luminance), row structs, `CsvLogger` (4 task CSVs) |
| `Scripts/LeafLaneLayout.cs` | Field choice (GCD-based), non-overlapping lane/path layout for every direction combination, per-frame motion with wrap, path verification |
| `Scripts/LeafVisualRenderer.cs` | Leaf polygon generator, batched mesh rendering of borders and fills with wrap copies, double-cue meshes (two half boxes) and uGUI cue words, centre-screen feedback text, orthographic camera setup |
| `Scripts/LeafGameModule.cs` | Launcher registration; `ApplySavedSettings` runs the shared migrations plus `MigrateTrialFlow`; `ValidateSettings` delegates to the controller |
| `Editor/LeafGameControllerEditor.cs` | Inspector extras: NF file chooser (File source only) and help text |
| `Assets/CogLab/App/Tests/Editor/LeafArrowResponseTimingTests.cs` | EditMode tests (Leaf and Arrow) for the reveal limit, the independent 4 s response window, feedback not being cut, the phase horizon (22 s with defaults), the pre-SSVEP whole-flash rule (with an explicit last-frame time), the points rule, Missed feedback before trial stop, the one-time instruction migration and the v1 → v2 pre-SSVEP default migration, and `ColourOnsetDiscardsATouchThatStartedBeforeIt` (8 tests per game) |

Shared code used: `CogLab.Shared.Timing.{MonotonicClock, PresentationClock, SsvepFrequencyAssignment, FrameStimulusCsvLogger}`, `CogLab.Shared.Bci.{NfSourceType, TriggerSender, NfTcpReader, NfBinaryReader, BciCoreNfReader, BciCoreTriggerSender, UsbBiosemiLink}`, `CogLab.Shared.Display.DisplayRateManager`, `CogLab.Shared.Calibration.BciCalibration`, `CogLab.Shared.UI.ResponsiveGui`, `BciCore.BciServer`.

---

## 3. Session flow / state machine

States: `enum AppState { Setup, Calibration, Instructions, PreSsvep, Trial, Iti, Summary, Fatal, Exporting }` (`LeafGameController.cs:31`). `PreSsvep` is entered by every `StartTrial` when `round(preSsvepSec/ifi) > 0`; otherwise `StartTrial` goes straight to `Trial`.

```
 Launcher Play ─► GameModule.Launch: copy template JSON → new controller,
                  ConfigureSharedLaunch(participant, session, eegMode)
                         │
                       Start()  (sharedAppManaged → ApplySettingsAndContinue immediately)
                         │
   Setup ── ValidateSettings fails ───────────────────────────────► Fatal
     │  InitializeGameplayFromSettings: presentation, scale/field, renderer,
     │  trigger transport (+ "reset" marker), BciServer.StartServer if BciCore
     ├─ BciCore ──► Calibration (shared calibration GUI)
     │                ├─ Back ──► ExitCalibrationMode, return to launcher (no export)
     │                └─ Proceed ──► BeginSession
     └─ other  ──► BeginSession
                    │ T0 = MonotonicClock.Now; seed; RNG
                    ├─ Tcp/UsbBiosemi: wait in Setup until the reader is ready
                    │     (timeout nfTcpTimeoutSec or reader error ──► Fatal)
                    └─ File/BciCore: immediately
                 CompleteSessionStart: open CSV loggers, plan trials,
                 fit field, verify all 24 layouts (failure ──► Fatal)
                    │
               Instructions ── "Begin block" ──► Iti (lead-in) ─► PreSsvep(1) ─► Trial(1) ─► Iti ─► PreSsvep(2) ─► Trial(2) … Trial(N) ─► Iti
                    │                                                                                                              │
                    └─ "Exit to menu" ─► Exporting ─► launcher                                                 after the last ITI:  ▼
                                                                                                             Exporting ─► Summary ─► "Back to games"
```

**Lead-in.** "Begin block" (`BeginBlock`, `:718-727`) does not start trial 1 directly. It sets `trialIndex = 0`, calls `RefreshPresentationTiming`, clears the leaves and the overlays, sets `itiRemaining = max(1, round(ItiSec/ifi))` and enters `Iti`. Trial 1 is therefore preceded by the same blank ITI (5 s) as every later trial, and its pre-SSVEP flash does not start the instant the button is tapped.

| Transition | Code |
|---|---|
| Shared launch auto-starts | `Start()` `LeafGameController.cs:268-275` |
| Validation (`SsvepFrequencyAssignment.Validate`, shuffle mode only) | `:265-266`, `:474-478` |
| BciCore → Calibration | `:483-499` |
| Session start, T0, seed | `:515-560` |
| Waiting for TCP / USB NF | `:562-577` |
| Loggers, plan, layout verification | `:579-589` |
| Begin block → lead-in ITI | `BeginBlock` `:718-727` |
| Trial start → PreSsvep (or Trial when the period is 0 frames) | `StartTrial` `:729-768` |
| PreSsvep → Trial (same frame) | `UpdatePreSsvep` `:770-785` |
| Trial → ITI | `FinishAfterPresentation` `:996-1017` |
| ITI → next trial / export at end | `UpdateIti` `:1019`, `StartTrial` `:731` |
| Export → Summary | `StartSessionExport(()=>ShowSummary())` `:449`, `ShowSummary` `:1020` |

**Calibration (BciCore only).** `BciCalibration.Open` adds the shared `CalibrationScreen`. On "Proceed to Game" it calls `BciServer.ExitCalibrationMode()` and then `BeginSession()`. On "Back" it exits calibration mode and returns to the launcher (standalone: back to Setup) without exporting (`:490-497`). The calibration screen's own "Stop & Export" and "Reboot" (`SendMarker(0xFFFF)`) are part of the shared GUI.

**Export (`StartSessionExport`, `:449`).**
1. Resume garbage collection if it is paused, set state to Exporting and clear the stimulus.
2. **Always** send `trialstop` (30), then dispose the trigger transport.
3. On a background task, first wait for all queued trial-log writes (`pendingLogWrites`, status "Saving trial logs..."), then finish the stimulus-frame CSV (if enabled).
4. If BciCore: `BciServer.ConvertCurrentSessionToCsvAsync` (DirectCsv: close the logger; BinaryThenCsv: convert `.bin` to `.csv`).
5. On the main thread, call the completion callback.

Export runs:
- automatically after the last ITI;
- on Escape (if `escapeEndsBlock`, any state except Setup);
- on "Exit to menu" (Instructions, Fatal, or HUD with a 3-second two-tap confirmation);
- standalone: on HUD Exit → back to Setup.

**Summary screen** (`Aesthetics.cs:222`):
- Points = total points of the run (`totalPoints`, reset at session start).
- Accuracy = correct / completed trials (misses count as incorrect; correct answers after a timeout reveal count as correct).
- "Reached color" = number of NF-earned reveals (timeout reveals are not counted).
- "Trials completed" = `min(trialIndex, trials.Count)`.

**Fatal conditions** (all go through `Fatal()` `:1021`; the message is shown and logged with `Debug.LogError`):

| Condition | Marker sent first? | Code |
|---|---|---|
| Shuffle-mode marker/frequency validation failed (shared launch) | no | `:474-477` |
| Start-up exception (e.g. display auto-fit or path verification failed) | no | `:505-511`, `:559` |
| TCP/USB NF not ready within `nfTcpTimeoutSec` or reader error | no | `:568-573` |
| USB link reports an error in any state other than Setup/Fatal | no | `:457-461` |
| Display refresh changed by more than `refreshRateChangeToleranceHz` during a trial (`abortTrialOnRefreshRateChange`) | `trialstop` 30 | `:419-431`, `:806` |
| Same refresh change during the pre-SSVEP period | **no** (no start marker was sent either) | `:772` |
| No fresh USB NF sample for `usbNfStallAbortSec` during a trial | `trialstop` 30 | `:812-819` |
| Layout infeasible at trial start | no (no start marker either) | `:750` |
| SSVEP phase horizon exhausted | **no** | `:849` |

`Fatal()` (`:1021`) also resumes garbage collection if it is paused.

A trial that ends in Fatal, Escape or Exit **produces no `trialdata`/`nftrace`/`droppedframes`/`ssvepframes` rows**. The rows are buffered in memory and handed to the log writer only by `FinishAfterPresentation`.

**Escape / Exit behaviour.** `Escape` (Android Back is normally delivered as Escape by the Input System) with `escapeEndsBlock = true` immediately sets `finishQueued` and starts the export (`:513`). It does this in Calibration, Instructions, PreSsvep, Trial, ITI, Summary and Fatal, and only Setup is excluded. Pressing Escape in Summary runs the export again, which is harmless. Pressing Escape in Calibration exports while the calibration GUI is still attached (see section 14). Destroying the object during a trial sends `trialstop` (`OnDestroy` `:433-442`); during the pre-SSVEP period it sends nothing. `OnDestroy` first resumes garbage collection and waits up to 5 s for queued trial-log writes. If BciCore was started, `OnDestroy` also calls `BciServer.StopServer()`.

---

## 4. Trial structure & timing

### 4.1 Timeline of one trial (defaults, 120 Hz display)

```
Update frame: p1 … pP          1          g               r             r+1 … k          k+1 … k+F         ITI (round(ItiSec/ifi) frames; also before trial 1)
              │                │          │               │              │                │
 state:       PreSsvep         Trial ────────────────────────────────────────────────────────►
 render:  leaves move, fill    leaves+flicker │ fill=green │ true colours  │  field emptied, centre text
          black, borders grey  │  fill=grey(nfLevel)       │ (NF reveal)   │  "Correct"/"Incorrect" + "+N points"
          0.5, cued group      │          │               │              │  (frames k … k+F)
          flashes red (4 Hz)   │          │               │              │
 double cue (bottom): visible from p1 to the end of frame k+F; hidden in the ITI
 end-of-frame:│                │          │               │              │                │
   marker     (none)         trialstart   (none)        success 50       │              trialstop 30 (end of frame k+F)
   CSV time   CueOnsetTime   TrialStart   FirstGreenTime ColorOnsetTime  │              TrialEnd
              │                │                          │              │
 in Update:                                                          response 40 sent in Update of frame k
                                                                     RT = now(k) - colorOnsetClock
 limits:                       ├── RevealExpired: now - trialStartClock >= trialLengthSec (15 s), only while not revealed ──┤
                                          ├── ResponseWindowExpired: now - colorOnsetClock >= ResponseTimeoutSec (4 s) ──┤
```

- `p1 … pP` are the pre-SSVEP frames, `P = round(preSsvepSec/ifi)` (180 at 120 Hz). `p1` is the first `Update` after `StartTrial`. Pre-SSVEP frame 1 (or trial frame 1 when `P = 0`) also pauses garbage collection (section 4.5). On the next `Update` (`preSsvepFrame = P+1`) the state switches to `Trial` and `UpdateTrial` runs in the same `Update` as trial frame 1 (`:776`). With `P = 0` the pre-SSVEP period is skipped and frame 1 is the first `Update` after `StartTrial`.
- Red flash: on pre-SSVEP frame `i` the flash is on when `PreSsvepFlashOn((i−1)·ifi, (P−1)·ifi)` (`:778`, `:789-795`): the fractional part of `t·preSsvepFlashHz` is < 0.5 **and** that flash's red half ends at or before the time of the last pre-SSVEP frame actually displayed, `(P−1)·ifi`. The last pre-SSVEP frame is therefore always grey. With the defaults (1.5 s, 4 Hz, 120 Hz display) there are six red flashes of 0.125 s each (0–0.125, 0.25–0.375, 0.5–0.625, 0.75–0.875, 1.0–1.125 and 1.25–1.375 s), grey in between, and steady grey from 1.375 s to 1.5 s.
- `g` is the first frame with `inGreen`.
- `r` is the reveal frame: either the frame on which `greenHoldFrames` reaches `nfGreenHoldFrames`, i.e. `round(NfGreenHoldSec/ifi)` *consecutive* green frames (NF success, marker 50), or the frame on which `now − trialStartClock ≥ trialLengthSec` without NF success (timeout reveal, **no marker**, `:837-843`). Both draw the true colours in frame `r` and commit `ColorOnsetTime` at its end.
- `k` is the frame on which a valid response is detected, or on which the response window expires (then "Missed" / "+0 points" is shown and no 40 is sent).
- `F = feedbackFrames`. The feedback text is drawn from frame `k` itself (the leaves are cleared at the end of `UpdateTrial` in frame k), so it is on screen for frames k … k+F.

### 4.2 Order of operations inside one frame

**Pre-SSVEP frame** (`UpdatePreSsvep`, `:770-785`):
1. Refresh-rate change check → abort **without** `trialstop` (no trial has started).
2. `preSsvepFrame++`. On pre-SSVEP frame 1, pause garbage collection (`PauseGcForStimulus`, section 4.5). If `preSsvepFrame` now exceeds `P`, switch to `Trial` and run `UpdateTrial` (trial frame 1) in this same `Update`.
3. `LeafLaneLayout.Advance` (motion, one step per frame).
4. Render the leaves: both fills `RenderGray(0)` (black); borders `RenderGray(preSsvepBorderLuminance)`, except the cued group's borders, which are `preSsvepFlashSrgb` while the flash is on.
5. Show the double cue; hide the feedback text.
6. On pre-SSVEP frame 1, schedule the end-of-frame commit of `preSsvepOnsetTime` (`CommitPreSsvepOnset`, `:797-802`).

No NF is read, nothing is integrated, nothing is logged and no marker is sent.

**Trial frame** (`UpdateTrial`, `:804-875`):
1. Refresh-rate change check → abort.
2. `trialFrame++`. On frame 1, pause garbage collection if the pre-SSVEP period did not already (`P = 0`). Every 128 frames, `CheckGcPauseHeap` (section 4.5).
3. `nfReader.TryRead(trial.NfIndex)`. A fresh sample updates `nfCurrent`; otherwise the previous value is held.
4. NF stall handling (section 7).
5. **If in feedback:** draw the feedback (field cleared, double cue, centre text), run `UpdateTrialOutcome` (feedback countdown) and return. Nothing else below runs, so feedback frames have no flicker, no NF integration and no log rows.
6. Clip, integrate `nfLevel`, compute `inGreen`, count the green hold, possibly reveal (NF success); otherwise, if `trialLengthSec` has run out, reveal anyway (`revealTimeout`).
7. `LeafLaneLayout.Advance` (motion, one step per frame).
8. `PresentationClock.Capture()`. On frame 1 the phase origin `trialPhaseT0` is set to that frame's predicted presentation time.
9. Sample the flicker luminance for the predicted presentation time and detect slot skips.
10. Append the `ssvepframes` row.
11. Choose the fills and render the leaves.
12. Write the optional stimframes row.
13. Show the double cue; hide the feedback text.
14. Schedule end-of-frame commits (start / green / reveal).
15. Append an NF trace row every `nfTraceEvery` frames.
16. `UpdateTrialOutcome(MonotonicClock.Now)`: response-window expiry (→ Missed feedback) or response polling (→ 40, points, feedback).
17. If feedback started in this frame, draw it (clears the leaves rendered in step 11).

### 4.3 Timing parameters

| Parameter (field) | Default (effective) | Unit | Time base | What it controls |
|---|---|---|---|---|
| `preSsvepSec` | 1.5 | s → **frames** | `P = max(0, round(preSsvepSec/ifi))` (`:765`) | Pre-SSVEP period before each trial. 0 (or less than half a frame) skips it. Not part of the trial (`TrialStart` is after it). |
| `preSsvepFlashHz` | 4 | Hz (≥ 0.1) | nominal frame times `(i−1)·ifi` from pre-SSVEP frame 1 | On/off rate of the red target flash; 50 % duty; only whole flashes ending by the last displayed pre-SSVEP frame. |
| `preSsvepBorderLuminance` | 0.5 | sRGB 0–1 | — | Steady border grey in the pre-SSVEP period. Keep equal to `ssvepMeanLuminance`. |
| `trialLengthSec` | 15 | s | monotonic, from `trialStartClock` (end of frame 1) | Time allowed for NF success. When it runs out without NF success the colours are revealed anyway (timeout reveal, `:842`, `RevealExpired` `:889-890`). Applies only while not revealed and not in feedback. Formerly `cueFirstMaxTrialSec` (migrated). |
| `ResponseTimeoutSec` | 4 | s | monotonic, from `colorOnsetClock` (end of the reveal frame, NF or timeout reveal) | Response window. Independent of `trialLengthSec`. On expiry the "Missed" feedback starts. Not checked during feedback (`:892-893`, `:903-917`). |
| `FeedbackSec` | 1 | s → **frames** | `feedbackFrames = max(1, round(FeedbackSec/ifi))` (`:745`) | Feedback duration, after a response **and** after a missed response. |
| `ItiSec` | 5 | s → **frames** | `itiRemaining = max(1, round(ItiSec/ifi))` (`:1016`) | ITI duration. |
| `NfGreenHoldSec` | 1 | s → **frames** | `nfGreenHoldFrames = max(1, round(NfGreenHoldSec/ifi))` (`:747`) | Continuous green frames needed for the reveal. A non-green frame resets the count to 0. |
| `NfTraceIntervalSec` | 0.1 | s → **frames** | `nfTraceEvery = max(1, round(NfTraceIntervalSec/ifi))` (`:746`) | NF trace sampling. |
| NF integration | — | per frame | uses nominal `ifi`, not the measured frame duration (`:833`) | Level dynamics. Not run in pre-SSVEP or feedback frames. |
| Leaf motion | `leafSpeedPxPerSec` | px/frame = `LeafSpeed*ifi` | frames | Motion. |
| SSVEP luminance | — | s | predicted presentation time (VSync lattice) | Flicker phase (robust to CPU jitter; see section 6). |
| `nfStreamStallWarnSec` | 2 | s | monotonic | Warning only (once per trial). |
| `usbNfStallAbortSec` | 5 | s | monotonic | USB abort. |
| `nfTcpTimeoutSec` | 10 | s | monotonic | Wait for the first TCP/USB NF record before Instructions. |
| `precomputedPhaseHorizonSec`, `phaseHorizonSafetyMarginSec` | 300, 2 | s | — | Phase horizon = `max(300, trialLengthSec+ResponseTimeoutSec+FeedbackSec+margin)` = 300 s by default (`:753-754`, `:884-886`). The pre-SSVEP period is not part of it (the phase starts at trial frame 1). |
| Points | `pointsNfSuccessCorrect` 100, `pointsNfFailureCorrect` 10 | points | — | Added to `totalPoints` at trial end (`:1001`). |

`ifi = 1/refreshHz`. `refreshHz = DisplayRateManager.ObservedRefreshRateHz` if it is at least `minimumValidRefreshHz` (30), else `fallbackRefreshHz` (60). It is re-read at every `StartTrial` (`:732`). At 120 Hz: pre-SSVEP = 180 frames, hold = 120 frames, feedback = 120 frames, ITI = 600 frames, trace every 12 frames. If frames are missed, frame-counted intervals become longer in wall time.

### 4.4 What ends a trial

Every completed trial is revealed (by NF or by timeout) and then ends with a feedback period. There is no longer an ending without feedback.

| End condition | Flags in CSV | Points | Last frame | Feedback? |
|---|---|---|---|---|
| NF reveal, valid response | `RevealTimeout=0`, `NfSuccess=1`, `ResponseTimeout=0`, `Accuracy` 0/1 | 100 if correct, else 0 | k+F | yes: "Correct"/"Incorrect" + "+N points", frames k … k+F |
| NF reveal, response window expired | `RevealTimeout=0`, `NfSuccess=1`, `ResponseTimeout=1`, `ParticipantResponse=missed`, `Accuracy=0` | 0 | expiry frame + F | yes: red "Missed" / "+0 points" |
| Timeout reveal (`now − trialStartClock ≥ trialLengthSec` without NF success), valid response | `RevealTimeout=1`, `NfSuccess=0`, `ResponseTimeout=0`, `Accuracy` 0/1 | 10 if correct, else 0 | k+F | yes |
| Timeout reveal, response window expired | `RevealTimeout=1`, `NfSuccess=0`, `ResponseTimeout=1`, `ParticipantResponse=missed`, `Accuracy=0` | 0 | expiry frame + F | yes: "Missed" |
| Escape / Exit / Fatal (also during pre-SSVEP) | **no row written** | not added | — | — |

`QueueFinish` / `FinishAfterPresentation` (`:996-1017`) waits for the end of the last feedback frame. It then sends `trialstop`, takes `TrialEnd = Elapsed`, adds the trial's points to `totalPoints`, snapshots the trial values and copies the trace, dropped-frame and SSVEP rows to arrays, and queues the four CSV writes on a background task (`QueueLogWrite`, section 4.5). It then clears the stimulus and the double cue, sets ITI, resumes garbage collection with a full collection (`ResumeGc(true)`), and increments `trialIndex`. The rows reach the files slightly after `trialstop`; their content and order are unchanged.

Maximum trial duration (`TrialStart` → `TrialEnd`) ≈ `trialLengthSec + ResponseTimeoutSec + FeedbackSec` = 20 s, plus frame quantisation; the pre-SSVEP period (1.5 s) precedes `TrialStart`.

Edge cases verified in code and tests:
- A reveal that happens just before `trialLengthSec` keeps the full response window, e.g. reveal at 14.5 s → responses accepted until 18.5 s (`LeafArrowResponseTimingTests.LateRevealKeepsFullResponseWindowPastTrialCapAndIgnoresFrameCount`).
- An NF reveal on the same frame where the limit would expire wins (NF success), because the green hold is checked before `RevealExpired`.
- Responses are polled only when `colorsRevealed && colorOnsetCommitted`. The earliest accepted response is on frame r+1, and a key pressed during frame r is lost (`wasPressedThisFrame`).
- The colour-onset commit clears swipe tracking (`touchTracking = false`, `CommitPresented`, `:947`), so only a touch that starts after the committed colour onset can become a swipe (`ColourOnsetDiscardsATouchThatStartedBeforeIt`).
- On the frame where the window expires, the timeout is checked before input, so a simultaneous press is ignored; the trial goes to "Missed" feedback and does not stop at once (`MissedResponseShowsMissedFeedbackInsteadOfEndingTheTrial`).

**ITI.** The leaves, the double cue and the feedback text are hidden and the background sprite plus HUD remain. The same ITI also runs once before trial 1 (lead-in from "Begin block", section 3). Garbage collection runs at its start. The countdown starts in the `Update` after the trial-end frame (or after "Begin block"). When it reaches 0, `StartTrial` runs in that same `Update`, and pre-SSVEP frame 1 of the next trial (or trial frame 1 if `P = 0`) is the following `Update`. After the final trial's ITI, `StartTrial` triggers the export, which sends **another** `trialstop` (`:731`, `StartSessionExport` `:449`).

### 4.5 Frame pacing

A dropped frame breaks the SSVEP phase lattice, so the stimulus frames avoid main-thread stalls:

- **No GUILayout pass.** `Start` sets `useGUILayout = false` (`:314`); the IMGUI code uses no `GUILayout` calls.
- **Garbage collection paused during the stimulus** (player builds only, `#if !UNITY_EDITOR`). `PauseGcForStimulus` (`:966-974`) sets `GarbageCollector.GCMode = Disabled` on pre-SSVEP frame 1 (or trial frame 1 when there is no pre-SSVEP period) and records the managed heap size. `FinishAfterPresentation` calls `ResumeGc(true)` (`:986-994`), which re-enables collection and runs `GC.Collect()` at the start of the blank ITI. `ResumeGc(false)` is also called from `ShowSummary`, `Fatal`, `StartSessionExport` and `OnDestroy`.
- **Safety net.** `CheckGcPauseHeap` (`:976-984`) runs every 128 trial frames; if the managed heap has grown more than `GcPauseHeapGrowthLimitBytes` (96 MB, `:256`) since the pause, it logs a warning and resumes collection mid-trial.
- **Per-trial log line.** Each resume logs `[LeafGame] Trial N: heap grew X KB with GC paused; dropped frames D.` (view with `adb logcat -s Unity`). Measured on the tablet: 4–15 MB heap growth per trial.
- **Background CSV writes.** `FinishAfterPresentation` hands the trial's snapshot to `QueueLogWrite` (`:953-960`), which chains the `WriteTrial`/`WriteTrace`/`WriteDropped`/`WriteSsvep` calls on one ordered background task chain (`pendingLogWrites`); write errors are logged. `StartSessionExport` awaits the chain before finishing ("Saving trial logs..."), and `OnDestroy` waits up to 5 s for it.
- **Shared code.** `ResponsiveGui.FitStyle` caches fitted styles under an allocation-free value-tuple key, and `CogLabAppController.Start` (player builds) sets stack-trace logging to `None` for `Log` and `Warning` messages (errors and exceptions keep their stack traces).

Measured in untouched blocks on the tablet: 1 dropped frame in 11 Leaf trials (0 in 8 Arrow trials). **Android screen recording causes large bursts of dropped frames; do not run it during sessions.**

---

## 5. Trial planning / randomisation

`TrialPlanner.Build(trialsPerBlock, cueC1Probability, rng, randomizeSsvepFrequencies)` (`LeafGameCore.cs:47-83`):

1. **Direction combinations (24).** For each C1 pointing p1 (4) and C1 moving m1 ≠ p1 (3), the remaining two directions are assigned to (C2 pointing, C2 moving) in both orders (2). This gives 4·3·2 = 24 combinations, and every one uses all four directions exactly once.
2. **Cues.** `c1Count = round(N · clamp(p,0,1))`, using .NET `Math.Round` (banker's rounding: 12.5 → 12). The list [C1 × c1Count, C2 × rest] is Fisher–Yates shuffled.
3. **Combination cycles.** Trials are filled in cycles of 24. Each cycle is a fresh shuffle of all 24 combinations, and the last cycle is truncated. With N = 24 every combination appears exactly once. Cue assignment is **independent** of the combination (cue × combination is not balanced).
4. **Frequency swaps** (only when `randomizeSsvepFrequencies`): `SsvepFrequencyAssignment.Build` (`Assets/CogLab/Shared/Timing/SsvepFrequencyAssignment.cs:9-25`). Within each cue, `floor(n/2)` trials are swapped (n = number of trials with that cue). If n is odd, one extra swap is added to one of the cues (chosen by `rng.Next(2)`). If both cues have odd counts, the extra swap alternates between them, so the whole block stays balanced to within 1. The swapped indices are chosen by shuffling.

At `StartTrial` (`LeafGameController.cs:679-682`):
- `FrequencyC1Hz = swapped ? frequencyC2Hz : frequencyC1Hz` (and the opposite for C2).
- The start marker is computed (section 9).

Defaults: N = 24, p = 0.5 → 12 C1 and 12 C2 trials; 6 swapped per cue.

**Seeding** (`:522-524`):
```
seed = useFixedRandomSeed ? fixedRandomSeed : unchecked(Environment.TickCount * 397)
if mixParticipantAndBlockIntoSeed: seed ^= participant.GetHashCode() ^ block.GetHashCode()
rng = new System.Random(seed)
```
- Defaults: `useFixedRandomSeed = false`, `fixedRandomSeed = 918273`, mixing on.
- **The seed is not written to any output file.** Leaf has no session/metadata file.
- `string.GetHashCode` depends on the runtime. It is stable within a given player build, but do not assume it matches desktop .NET.

**Order of RNG use.** The same `rng` is used for:
1. `TrialPlanner.Build` (cue shuffle, combination shuffles, swap selection);
2. `ValidateLayouts`, which calls `LeafLaneLayout.Create(..., rng)` 24 times when `verifyLeafPathsAtSetup` is on (`:656`);
3. each `StartTrial`'s `LeafLaneLayout.Create` (random lane offsets/jitter, `:692-693`).

The trial plan therefore depends only on the seed, N and p. The leaves' initial positions also depend on `verifyLeafPathsAtSetup` and the field geometry. The field geometry depends on the screen and safe area.

**Reproducibility.** With a fixed seed and identical participant/block strings, settings and device, the full sequence (plan and layouts) repeats. Without a fixed seed, the plan can only be recovered from `trialdata.csv` (all planning columns are logged per trial), and only for trials that completed.

Layout feasibility checks use their own `new System.Random(918273)` (`:637`, `:652`) and do not affect the plan.

---

## 6. Stimulus

### 6.1 Scale and field

All pixel settings are "pixels at a 1080-px reference short side" multiplied by `activePixelScale`.

- Requested scale (`:591-596`):
  ```
  s_req = useResponsiveSizing ? clamp(min(Screen.width, Screen.height) / referenceShortSidePx, minimumScreenScale, maximumScreenScale) : 1
  ```
  Effective prefab values: `referenceShortSidePx` 1080, `minimumScreenScale` **0.25**, `maximumScreenScale` 4.
- **Auto-fit** (`:613-633`): try `s = s_req, s_req − step, …` down to `max(minimumScreenScale, s_req·autoFitMinimumFraction)`, where `step = max(0.01, s_req·autoFitStepFraction)`. Effective values: fraction **0.35**, step 0.05. The first scale is used for which (a) a field exists and (b) all 24 direction combinations have a feasible layout. If none works, start-up fails ("Display auto-fit failed").
- **Viewport**: the safe area (top-left origin), inset by `safeAreaPaddingReferencePx·s` (0), times `stimulusWidthFraction`/`stimulusHeightFraction` (1), centred.
- **Field** (`LeafLaneLayout.ChooseField`, `LeafLaneLayout.cs:31-54`):
  - Search all integer (w, h) within `maxFieldShrinkPx·s` (400·s) of the viewport size such that `gcd(w,h) ≥ required` and `w/g, h/g ≥ minRepeatsPerAxis` (1).
  - `required = ceil(2·(OuterLength + OuterWidth + 2·LaneMargin)) + 1`.
  - Choose the largest area and centre it in the viewport. Leaves move and wrap inside this rectangle; the rest of the screen stays empty apart from leaf overhang at wrap edges.
- **The effective scale and field rectangle are written only to the Unity log** (`Debug.Log` in `ValidateLayouts`, `:663`), not to any data file.

### 6.2 Leaf geometry (at scale s)

| Quantity | Formula | Default (s = 1) |
|---|---|---|
| Inner length `LeafLength` | `leafSizePx·s` | 150 px |
| Inner width `LeafWidth` | `leafSizePx·leafWidthMultiplier·s` | 63 px |
| Border `Border` | `leafSizePx·leafBorderMultiplier·s` | 30 px |
| Outer length / width | `LeafLength + 2·Border`, `LeafWidth + 2·Border` | 210 × 123 px |
| Wrap radius `MaxRadius` | `0.5·sqrt(OuterLength² + OuterWidth²)` | 121.7 px |
| Lane margin | `laneClearanceMarginPx·s` | 6 px |
| Speed | `leafSpeedPxPerSec·s` px/s → `·ifi` px/frame | 200 px/s (1.667 px/frame at 120 Hz) |

**Shape** (`LeafVisualRenderer.CreateLeafShape`, `LeafVisualRenderer.cs:111-143`): a polygon along the local x axis from the stem rear (−L/2) to the tip (+L/2).
- Stem half-width: `min(0.32·W/2, max(0.75, 0.055·W))`. The stem runs from −0.5L to −0.30L.
- Body half-width profile: `stemHalf·(1−t) + (W/2 − stemHalf)·sin(πt)^0.72·organic(t)`, where `t ∈ [0,1]` from −0.30L to the tip. The two sides use slightly different `organic` terms: 0.90 + 0.06 sin πt + 0.04 sin 2πt (one side) and 0.94 + 0.08 sin πt − 0.05 sin 2πt (other side), both capped at 1.
- `leafArcPoints` (10, clamped to 5–64) points per side.
- Rotated by 0° (Right), 90° (Down), 180° (Left) or −90° (Up) in y-down screen coordinates.
- The outer (border) polygon is the same shape built with outer length and width. It is not a uniform offset, so the border is 30·s px at the tip/stem ends and about 30·s px at the widest point.

**Rendering** (`RenderLeaves`, `:145-163`):
- Four meshes: Flock1Border and Flock2Border (sorting order 1, z = 0), Flock1Fill and Flock2Fill (order 2, z = −0.1).
- Shader: URP Unlit (or `Unlit/Color` fallback).
- A leaf within `MaxRadius` of a field edge is also drawn shifted by ±field width/height, giving up to 4 copies. Shapes are not clipped to the field.
- Flock 1 is always the C1 group and flock 2 the C2 group.

**Motion** (`LeafLaneLayout.Create`/`Advance`, `LeafLaneLayout.cs:56-129`):
- Each leaf moves `velocity = dir·LeafSpeed·ifi` px per frame. Directions: Up = (0, −1) and Down = (0, +1) in y-down coordinates. Position wraps modulo the field.
- **Same axis** (both groups move horizontally, or both vertically):
  - `laneCount = floor(crossSize/(crossExtent+margin))` lanes (must be ≥ 2).
  - Lanes alternate between the groups (even lanes C1, odd lanes C2) at centres `(i+0.5)·crossSize/laneCount`.
  - Leaves are spread round-robin over their group's lanes. Within a lane they are evenly spaced (`alongSize/count`) with a random offset per lane.
- **Perpendicular axes**: an "invariant grid" placement using the field gcd `g`.
  - Requires `g > 2·cReq`, where `cReq = (eA.x+eB.x)/2 + (eA.y+eB.y)/2 + 2·margin`.
  - Positions are chosen so that the two groups' trajectories never intersect over the wrap period.
  - Random jitter per lane.
- **Verification** (`Verify`, `:131-151`): when `verifyLeafPathsAtSetup` is on, each of the 24 layouts is simulated for `min(verificationMaxFrames=40000, lcm(w,h)/speed)` frames. Every pair's axis-aligned outer-box clearance (with wrap) must stay ≥ 0, otherwise start-up fails. The worst clearance is logged.

### 6.3 Colours

`Render(c)` returns `c.linear` when the project colour space is Linear, which it is (`ProjectSettings` `m_ActiveColorSpace: 1`). `RenderGray(v)` = `Color(v,v,v).linear` (`LeafGameController.cs:882-883`). All colour settings are therefore specified as **sRGB** values, and grey levels `v` are sRGB code values in [0,1].

| Element | Colour |
|---|---|
| Fill, pre-SSVEP | `RenderGray(0)` (black), both groups |
| Border, pre-SSVEP | `RenderGray(preSsvepBorderLuminance)` (0.5); cued group `preSsvepFlashSrgb` (255,0,0) while the flash is on |
| Fill before reveal, not green | `RenderGray(nfLevel)`, same for both groups |
| Fill before reveal, green | `greenZoneSrgb` (179,255,179) |
| Fill after reveal | C1 `c1Srgb` (0,191,255), C2 `c2Srgb` (255,140,0) |
| Border, trial | `RenderGray(luminanceC1)` / `RenderGray(luminanceC2)` from trial frame 1 to the response / miss frame (no leaves are drawn during feedback) |
| Double cue | left half `c2Srgb` (orange), right half `c1Srgb` (blue) |
| Cue words | `cueTextSrgb` black with `cueTextOutlineSrgb` white outline (`cueTextOutlinePx·s` px) |
| Feedback text | `successSrgb` (0,255,0) when correct, `failureSrgb` (255,0,0) when incorrect or missed; black outline |
| Background | `Resources/LeafGame/BackgroundTexture` sprite stretched to the full screen (z = 80, order −100) in front of the camera clear colour `backgroundSrgb` (black). The image, not black, is the visible background whenever the texture loads. |

### 6.4 SSVEP flicker

`SsvepPhaseSchedule` (`LeafGameCore.cs:94-127`), built per trial at `StartTrial` with that trial's assigned frequencies:

```
mean      = clamp01(ssvepMeanLuminance)                  = 0.5
amplitude = min(mean, 1-mean) * clamp01(ssvepModulationDepth) = 0.5
t         = max(0, predictedPresentation(frame) - trialPhaseT0)       [s]
L_C1(t)   = mean + amplitude * sin(2π·FrequencyC1Hz·t + phaseC1Degrees·π/180)
L_C2(t)   = mean + amplitude * sin(2π·FrequencyC2Hz·t + phaseC2Degrees·π/180)
slot      = round(t · refreshHz_at_trial_start)
```

- **Phase origin.** `trialPhaseT0` is the `PresentationClock.Capture().presentationTime` of trial frame 1, i.e. the *predicted* presentation (VSync-lattice) time of the first stimulus frame (`LeafGameController.cs:846`). Phase is therefore 0 at the predicted presentation of frame 1, and with default phases 0° both borders start at grey 0.5 and rise, i.e. exactly at the pre-SSVEP border grey (`preSsvepBorderLuminance` 0.5), so there is no luminance step at SSVEP onset (a step appears if the mean, the phases or `preSsvepBorderLuminance` are changed). The phase is continuous until the response / miss frame and restarts every trial. There is no flicker in the pre-SSVEP period or during feedback (the field is empty).
- Default range 0 to 1 (full modulation). At 120 Hz, 15 Hz is exactly 8 frames per cycle; 17 Hz is 7.06 frames per cycle, so it is a sampled sinusoid with no integer period.
- Only the borders flicker. Fills do not.
- The sinusoid is in sRGB code-value space (after `RenderGray`), not in linear photometric luminance. Physical luminance is a non-linear (approximately gamma 2.2) function of the logged value, so the light output contains harmonics. Verify with a photometer (see section 14 on colour-conversion uncertainty).

### 6.5 Double cue and feedback text

- **Double cue** (`LeafVisualRenderer.ConfigureDoubleCue`/`PositionDoubleCue`): one box `doubleCueWidthPx × cueHeightPx` (520 × 90 · s) split into two halves of 260·s px. Left half `c2Srgb` (orange) with `cueC2Word` "Moving"; right half `c1Srgb` (blue) with `cueC1Word` "Pointing". The outer corners are rounded with radius `min(cueCornerRadiusPx·s, width/4, height/2)` (20·s) and 8 segments; the inner edge where the halves meet is straight. Sorting order 5, in front of the leaves. The colours and words are fixed for the session; they do not depend on the trial's cue.
- Words: uGUI `Text`, `LegacyRuntime.ttf`, one per half, best-fit between `round(cueFontSize·cueCharacterSize·s)/2` and `round(cueFontSize·cueCharacterSize·s)` (64·0.5·s = 32·s px).
- Position (`Aesthetics.cs:104-114`): always at the bottom; centre at `cueBottomMarginPx·s + cueHeightPx·s/2` (24·s + 45·s px) above the bottom of the safe area, horizontally centred. It can overlap the lower edge of the leaf field.
- Visible in every pre-SSVEP and trial frame, including feedback. Hidden in the ITI, instructions, summary and fatal screens.
- **Feedback text**: one centre-screen uGUI `Text`, font size `round(feedbackFontSizePx·s)` (96·s px, no best-fit), black outline, text `"<verdict>\n+<points> points"` (`BeginFeedback`, `:920-924`; verdict `correctFeedbackText`, `incorrectFeedbackText` or `missedFeedbackText`; suffix `pointsSuffix`). Shown only during feedback, when the leaves are cleared.

---

## 7. Neurofeedback

### 7.1 Sources

`nfSourceType` (`NfSourceType { File=0, Tcp=1, BciCore=2, UsbBiosemi=3 }`, `Assets/CogLab/Shared/Bci/NeurofeedbackTransport.cs:9`).

**Effective default: BciCore (2).** The code initializer is `Tcp`, the prefab stores `3` (UsbBiosemi), and the launcher scene's prefab instance overrides it to `2` (`Assets/CogLab/App/Scenes/CogLab.unity:643-646`). A value saved in `CogLab.Games.leaf.v1` overrides all three.

| Source | Reader | Value delivered for `NfIndex` 0 / 1 | Freshness | Readiness wait |
|---|---|---|---|---|
| File (0) | `NfBinaryReader(NfPath)`: reads the little-endian double at byte `8·index` | doubles 0 / 1 of the file | **every frame** returns true if the file is readable and finite (no freshness concept) | none |
| Tcp (1) | `NfTcpReader(nfTcpHost, nfTcpPort)`: 24-byte records = 3 LE doubles | record doubles 0 / 1 | true once per new record | until the first record, ≤ `nfTcpTimeoutSec` |
| BciCore (2) | `BciCoreNfReader`: in-process `BciServer.OnNfSample` / `OnCcaSample` | NF frame: `Smi14gt18Shaped` / `Smi18gt14Shaped`; HW-CCA frame: `FbAgtB` / `FbBgtA` (whichever frame arrived last) | true once per new sample | none (board may still be connecting) |
| UsbBiosemi (3) | `UsbBiosemiLink` on 127.0.0.1:`usbBiosemiPort` (ADB reverse) | record doubles a / b (the third double is a sample count that is acknowledged with `R <count>`) | true once per new record | until the first record, ≤ `nfTcpTimeoutSec` |

`NfPath` = `nfFilePath` if it is rooted, else `persistentDataPath/nfFilePath`. On Android the prefab's Windows path `C:\Users\...\nf.txt` is not rooted, so it is joined to `persistentDataPath`.

### 7.2 Channel used per trial

`NfIndex = cueIndex XOR swapped` (`SsvepFrequencyAssignment.NfIndex`, `SsvepFrequencyAssignment.cs:29`; `LeafGameCore.cs:27`), with C1 = 0 and C2 = 1.

| Cue | Swapped | Cued group frequency | NfIndex (0-based) | `NFIndexUsed` (1-based, logged) | BciCore field |
|---|---|---|---|---|---|
| C1 | 0 | low (`frequencyC1Hz`, 15) | 0 | 1 | `Smi14gt18Shaped` |
| C2 | 0 | high (`frequencyC2Hz`, 17) | 1 | 2 | `Smi18gt14Shaped` |
| C1 | 1 | high | 1 | 2 | `Smi18gt14Shaped` |
| C2 | 1 | low | 0 | 1 | `Smi14gt18Shaped` |

Channel 1 / index 0 always means "low-frequency target" and channel 2 / index 1 "high-frequency target". With shuffling off, `swapped` is always 0, so `NfIndex = cue`. The NF provider must compute its two values for the configured frequencies. The game never sends the frequencies to the board, and the BciCore field names still refer to 14/18 Hz.

### 7.3 Update equations (per rendered trial frame, `LeafGameController.cs:810-843`)

```
if TryRead(NfIndex) → nfCurrent = fresh                 (else nfCurrent holds its last value; reset to 0 at StartTrial)
clipped  = clamp(nfCurrent, −NfClip, +NfClip)                        NfClip = 1
nfLevel  = clamp01(nfLevel + NfRatePerUnitPerSec · ifi · clipped)    rate = 3 /s per unit; nfLevel = 0 at StartTrial
inGreen  = nfLevel ≥ 1 − NfWhiteTopRelaxation                        threshold 0.9
if !revealed: greenHoldFrames = inGreen ? greenHoldFrames+1 : 0
              reveal when greenHoldFrames ≥ nfGreenHoldFrames        = round(NfGreenHoldSec/ifi)
```

- Integration is per frame with the *nominal* `ifi`. A held (stale) value keeps being integrated every frame.
- With a sustained `clipped = c > 0`, the level reaches 0.9 after 0.3/c s. The fastest possible reveal is therefore ≈ 0.3 s + 1.0 s = 1.3 s after frame 1 (at `c = 1`).
- Negative NF lowers the level.
- After the reveal, `nfLevel` and `inGreen` keep updating and are logged until the response / miss frame, but they no longer affect the display. `greenHoldFrames` is frozen at its reveal value. Nothing is integrated in feedback frames or in the pre-SSVEP period (NF is not read there).
- If NF success is not reached within `trialLengthSec`, the colours are revealed anyway; NF has then failed for this trial (`NfSuccess = 0`).

### 7.4 Stall handling

- **Warning** (Tcp, BciCore, UsbBiosemi): when `now − nfLastFreshClock ≥ nfStreamStallWarnSec` (2 s), `Debug.LogWarning` fires once per trial. The trial continues with the held value. `nfLastFreshClock` is reset at `StartTrial` (`:742`, `:820-825`), i.e. before the pre-SSVEP period, in which NF is not read; the pre-SSVEP time (1.5 s) therefore counts towards the warning and abort thresholds until the first fresh sample of the trial.
- **Abort** (UsbBiosemi only): when `usbNfStallAbortSec > 0` (5 s) and there is no fresh record for that long, `trialstop` is sent and the session goes to Fatal (`:812-819`). The check also runs in feedback frames. A USB link error in any non-Setup state is also Fatal (`:457-461`).
- File source: never stalls (`readOk` is 1 whenever the file is readable). If the file is missing, `readOk = 0` and the level stays at 0.

---

## 8. Responses & scoring

- **Inputs** (`TryGetDirection`, `:1039`):
  - Keyboard arrows (`enableKeyboardArrows`, Common-overridable), using `wasPressedThisFrame`. If several are pressed, priority is Up > Down > Left > Right.
  - Touch swipe (`enableSwipeResponses`): press position to release position. The swipe counts if `|Δ| ≥ swipeThresholdPx·s` (40·s px). The dominant axis decides; screen y is up in Input System coordinates, so Δy < 0 is Down.
- Inputs are polled **only** after the committed reveal (NF or timeout reveal) and while the response window is open (`:903-917`). Earlier inputs are ignored and not logged. Touch press/release tracking is updated only while polling, and the colour-onset commit resets it (`touchTracking = false`, `:947`), so only a touch that starts after the committed colour onset can become a swipe.
- **First response only.** After a response the trial enters feedback, and no more responses are polled.
- **Accuracy**: `response == CorrectResponse` (section 1). Misses (`ResponseTimeout`) give `Accuracy = 0`. A response after a timeout reveal is scored normally (it can be correct).
- **Points** (`TrialPoints`, `:927`; set at the response, `:914`):

| NF outcome | Response | Points (default) |
|---|---|---|
| NF success (`NfSuccess = 1`) | correct | `pointsNfSuccessCorrect` = 100 |
| NF failure / timeout reveal (`NfSuccess = 0`) | correct | `pointsNfFailureCorrect` = 10 |
| either | incorrect or missed | 0 |

  The trial's points are shown in the feedback text, added to `totalPoints` at trial end and logged (`Points`, `TotalPoints`). `totalPoints` is reset at session start (`CompleteSessionStart`).
- **Reaction time**: `ReactionTime = now − colorOnsetClock` (`:912`).
  - `now` = `MonotonicClock.Now` taken in `Update` of the frame that detected the input. Input events are processed once per frame before `Update`; the event's own hardware timestamp is not used.
  - `colorOnsetClock` = `MonotonicClock.Now` at `WaitForEndOfFrame` of the reveal frame (CPU end of frame, after render submission, not photon onset). This holds for NF and timeout reveals alike.
  - Resolution is therefore ≈ 1 frame, and the RT has a constant offset relative to the true visual onset (about the presentation latency).
  - RT ∈ (0, ResponseTimeoutSec) and is written as seconds with 6 decimals. It is NaN when there was no response.
- The summary accuracy is `correct / completed trials`. The HUD SCORE tile shows `totalPoints`, and the summary shows Points as well.

---

## 9. Event markers / triggers

### 9.1 Codes

| Code (default) | Send name | Field | Exact moment | Condition |
|---|---|---|---|---|
| 0 | `reset` | `resetTrigger` | In `InitializeGameplayFromSettings`, right after the transport is created, before calibration and instructions (`:372`, `:383`). USB: sent by the link itself on every new TCP connection (`UsbBiosemiLink.cs:64`); `Send("reset")` is ignored (`:136`). | Once per session start (USB: once per connection) |
| 31 / 32 / 33 / 34 | `trialstart` | computed | `WaitForEndOfFrame` of trial frame 1 (SSVEP onset, after the pre-SSVEP period), i.e. after the CPU submitted the first flickering frame and before its predicted presentation (`:933-941`) | Every started trial, shuffle mode. Code = `31 + cue + 2·swapped` (`SsvepFrequencyAssignment.cs:28`) |
| 20 / 21 | `trialstart` | `trialStartTrigger` (C1) / `trialStartC2Trigger` (C2) | as above | Shuffle off (legacy). C1 → 20, C2 → 21 (`:737-738`) |
| 50 | `success` | `successTrigger` | `WaitForEndOfFrame` of the NF reveal frame (first frame with true colours) (`:949`) | Only trials with NF success. A timeout reveal sends **no** marker |
| 40 | `response` | `responseTrigger` | Immediately in `Update` of the frame that detected the response, before that frame's render (the feedback text replaces the leaves in that same frame) (`:913`) | Trials with a response (after either kind of reveal) |
| 30 | `trialstop` | `trialStopTrigger` | `WaitForEndOfFrame` of the last feedback frame (`:1001`) | Every trial that ends normally, including missed responses |
| 30 (extra) | `trialstop` | — | (a) Every `StartSessionExport`: block completion after the final ITI, Escape, any Exit to menu, including from Instructions or Fatal (`:449`). (b) Refresh-change abort during a trial (`:429`; not during the pre-SSVEP period). (c) USB stall abort (`:815`). (d) `OnDestroy` while in Trial (`:438`). | See section 14 |

No cue-onset marker exists (older README versions listed a "45 cue onset" marker), the pre-SSVEP period has no marker, and no green-zone marker exists. The pre-SSVEP onset is logged only as `CueOnsetTime`. Start-marker meanings in shuffle mode:

| Start | Cue | C1 frequency | C2 frequency | NFIndexUsed |
|---|---|---|---|---|
| 31 | C1 / Pointing | low | high | 1 |
| 32 | C2 / Moving | low | high | 2 |
| 33 | C1 / Pointing | high | low | 2 |
| 34 | C2 / Moving | high | low | 1 |

The start marker encodes the cue, which was shown by the red flash in the pre-SSVEP period just before it.

Normal event order within a trial: `start` → [`50`] → [`40`] → `30`. Possible sequences:

| Sequence | Meaning |
|---|---|
| `S 50 40 30` | NF success, response |
| `S 50 30` | NF success, missed response |
| `S 40 30` | timeout reveal (no 50), response |
| `S 30` | timeout reveal, missed response |

### 9.2 Transport per NF source

| `nfSourceType` | Transport (`ITriggerSender`) | Wire format | Destination |
|---|---|---|---|
| File, Tcp | `TriggerSender` (UDP, new socket per send, errors only logged) | ASCII decimal, no terminator | `nfTcpHost:triggerPort` (10.36.17.144:5007) |
| BciCore | `BciCoreTriggerSender`: (1) `BciServer.LogTriggerSent` → `health.csv` row `event = trigger_sent:<name>`; (2) `BciServer.SendMarker` → CMD frame to the ESP32 board, latched into the EEG stream; (3) UDP copy to `nfTcpHost:triggerPort` | CMD frame; ASCII UDP | Board over TCP; UDP host |
| UsbBiosemi | `UsbBiosemiLink` (same TCP socket as NF) | ASCII decimal + `\n`; marker must be 0..255 or the send throws | 127.0.0.1:`usbBiosemiPort` (5010) via ADB reverse to the MATLAB/P-system bridge |

All markers are sent from the Unity main thread. "Moment emitted" means the call time. Network and board latching delays come on top (see the shared document).

### 9.3 Validation

`ValidateSettings` → `SsvepFrequencyAssignment.Validate(randomize, f1, f2, reset, success, response, stop)` (`LeafGameController.cs:265-266`, `SsvepFrequencyAssignment.cs:57-81`). It runs at launcher launch (`LeafGameModule.ValidateSettings`) and at session start. **Only when `randomizeSsvepFrequencies` is On**:
- `0 < frequencyC1Hz < frequencyC2Hz`, both finite;
- reset, success, response and stop are distinct, within 0..255, and not in {20–24, 31–34};
- reset, success and response are not 30 or 60;
- stop is 30 or 60.

With shuffling Off **nothing is validated**, including the legacy 20/21 codes. All code fields are also clamped to 0..255 by their `[Range]` attributes.

---

## 10. Output files

`DataPath` = `dataFolderName` if it is rooted, else `Application.persistentDataPath/<dataFolderName>`. The default is `data`. On Android this is `/storage/emulated/0/Android/data/org.iisc.coglab.games/files/data/`. `<P>` = participant string, `<B>` = block string (the launcher's "Block number" = `sessionNumber`, default `001`), both used verbatim with no sanitising.

| File | Path pattern | Written when |
|---|---|---|
| Trial data | `DataPath/p<P>_b<B>_leaves_trialdata.csv` | Header at `CompleteSessionStart`; one row per completed trial, written by a background task shortly after its `trialstop` (section 4.5) |
| NF trace | `DataPath/p<P>_b<B>_leaves_nftrace.csv` | Same; all of the trial's trace rows at trial end |
| Dropped frames | `DataPath/p<P>_b<B>_leaves_droppedframes.csv` | Same |
| SSVEP frames | `DataPath/p<P>_b<B>_leaves_ssvepframes.csv` | Same; one row per trial frame |
| Stimulus frames (optional) | `DataPath/p<P>_b<B>_leaf_stimframes_<UTC yyyyMMdd_HHmmssfff>[_r<n>].csv` | Only if `logStimulusIntensityEveryFrame`. File and header created at session start. Rows buffered and written asynchronously at each trial end (`FlushIti`) and at export. |
| Stimulus-frame metadata | same stem + `.metadata.json` | At logger creation |
| BciCore EEG session | `persistentDataPath/BciCoreLogs/eeg_leaf_p<P>_s<B>_<local yyyyMMdd_HHmmss>/` | BciCore source only and logging mode ≠ Disabled. Created when the board connects or sends HELLO. A new folder is started on **every** board (re)connection. |

**Append and versioning behaviour of the 4 task CSVs** (`CsvLogger.Ensure`, `LeafGameCore.cs:162-172`):
- If the file does not exist, it is created with the header.
- If its first line equals the current header exactly, **rows are appended**. Repeated runs with the same P/B append into the same files, and `TrialNumber` restarts at 1. No session or run column exists.
- If the header differs (an older schema), a new file `…_leaves_<name>_<local yyyyMMdd_HHmmss>.csv` is created and the old one is left untouched.

The schema of each file is checked separately, so one run's files can end up with different names. The trial-flow change altered only the `trialdata` header (section 10.1), so the first run after the update with an existing P/B writes a new timestamped `trialdata` file, while the other three files keep appending. Numbers are written with `F6` (6 decimals, invariant culture). NaN is written as the literal `NaN`. Booleans are `0`/`1`. Directions are lower-case `up|down|left|right`. Line ending is `Environment.NewLine` (`\n` on Android).

### 10.1 `…_leaves_trialdata.csv` (one row per completed trial; `LeafGameCore.cs:146`, `:175-186`)

"Elapsed" means seconds since T0 on the monotonic clock (section 12).

| # | Column | Meaning | Units / values | Time base / NaN |
|---|---|---|---|---|
| 1 | `TrialNumber` | 1-based index within this run | int | — |
| 2 | `TrialStart` | CPU end of trial frame 1 (the moment `trialstart` was sent) | s | Elapsed |
| 3–6 | `C1PointDir`, `C1MoveDir`, `C2PointDir`, `C2MoveDir` | Direction features | up/down/left/right | — |
| 7 | `Cue` | Cued group | `c1` (Pointing) / `c2` (Moving) | — |
| 8 | `CueOnsetTime` | Target cue onset: CPU end of pre-SSVEP frame 1 (start of the red-flash period); = `TrialStart` when there was no pre-SSVEP period | s | Elapsed; ≈ `TrialStart − PreSsvepSec` |
| 9 | `FirstGreenTime` | CPU end of the first frame with `inGreen` (start of the *first* green episode, not necessarily the one that revealed) | s | Elapsed; NaN if never green |
| 10 | `ColorOnsetTime` | CPU end of the reveal frame: NF reveal (the moment marker 50 was sent) or timeout reveal (no marker) | s | Elapsed; defined for every completed trial |
| 11 | `CorrectResponse` | `C1PointDir` if c1, else `C2MoveDir` | direction | — |
| 12 | `ParticipantResponse` | Accepted response, or `missedResponseText` (default `missed`) | direction / `missed` | — |
| 13 | `Accuracy` | 1 if response == correct (also after a timeout reveal) | 0/1 (misses = 0) | — |
| 14 | `ReactionTime` | `now(response frame Update) − colorOnsetClock` | s | NaN if no response |
| 15 | `RevealTimeout` | No NF success within `trialLengthSec`; the colours were revealed by timeout | 0/1 | — |
| 16 | `ResponseTimeout` | Revealed (either way) but no response within `ResponseTimeoutSec` | 0/1 | — |
| 17 | `TrialEnd` | CPU end of the last feedback frame (the moment the trial's `trialstop` was sent) | s | Elapsed |
| 18 | `DroppedFrameCount` | Sum of skipped predicted VSync slots from trial frame 1 to the response / miss frame (section 12) | count | — |
| 19 | `FrequencyC1Hz` | C1 border frequency this trial | Hz | — |
| 20 | `FrequencyC2Hz` | C2 border frequency this trial | Hz | — |
| 21 | `FrequenciesSwapped` | 1 = C1 high / C2 low | 0/1 (always 0 with shuffle off) | — |
| 22 | `TrialStartMarker` | Code actually sent as `trialstart` | 31–34 or 20/21 | — |
| 23 | `NFIndexUsed` | NF channel used (`NfIndex + 1`) | 1/2 | — |
| 24 | `PreSsvepSec` | Pre-SSVEP length actually shown, `P·ifi` = `round(preSsvepSec/ifi)/refreshHz` (not the setting value) | s | 0 when skipped |
| 25 | `NfSuccess` | Colours revealed by NF (= `1 − RevealTimeout`) | 0/1 | — |
| 26 | `Points` | Points of this trial (section 8) | int | — |
| 27 | `TotalPoints` | Running total of `Points` in this run, including this trial | int | — |

The former column `CueFromTrialStart` no longer exists.

### 10.2 `…_leaves_nftrace.csv` (`LeafGameCore.cs:147`, `:187-195`; rows created at `LeafGameController.cs:870-871`)

A row is written on trial frames 1, 1+n, 1+2n, … with `n = nfTraceEvery = round(NfTraceIntervalSec/ifi)`, up to the response / miss frame. The interval is set by frame count, not by time. Pre-SSVEP and feedback frames produce no rows.

| Column | Meaning | Units | Notes |
|---|---|---|---|
| `TrialNumber` | Trial | int | Joins `trialdata.TrialNumber` (within a run) |
| `FrameNumber` | Trial frame index (1-based) | int | Joins `ssvepframes.FrameNumber` |
| `SampleTime` | `MonotonicClock.Now − T0` read in `Update` when the row was taken (after rendering commands, before the outcome check) | s, Elapsed | CPU time in Update, not presentation |
| `NFIndexUsed` | 1-based channel | 1/2 | Constant within a trial |
| `NFValueRaw` | `nfCurrent`: the latest fresh value, possibly held from an earlier frame | provider units | 0 until the first fresh sample of the trial |
| `NFValueClipped` | `clamp(raw, ±NfClip)` | provider units | |
| `NFLevel` | `nfLevel` **after** this frame's update | 0..1 | Equals the pre-reveal fill grey of this frame |
| `InGreenZone` | `nfLevel ≥ 1 − NfWhiteTopRelaxation` | 0/1 | |
| `GreenHoldSec` | `greenHoldFrames · ifi` | s (frame-derived) | Frozen after the reveal |
| `ColorsRevealed` | Reveal has occurred (including this frame) | 0/1 | |
| `PostCueOnset` | Always 1 (the target was cued in the pre-SSVEP period, before every trace row) | 0/1 | Kept for schema compatibility |
| `NFReadOk` | A fresh, finite sample was read **on this frame** | 0/1 | File source: always 1 when the file is readable |

### 10.3 `…_leaves_droppedframes.csv` (`LeafGameCore.cs:148`; rows at `LeafGameController.cs:850-854`)

A row is written whenever the predicted slot advances by more than 1 between consecutive trial frames (trial frame 1 to the response / miss frame; pre-SSVEP and feedback frames are not checked).

| Column | Meaning | Units |
|---|---|---|
| `TrialNumber` | Trial | int |
| `FrameNumber` | Trial frame on which the jump was detected (the frame after the gap) | int |
| `VBLTime` | `MonotonicClock.Now − T0` in `Update` of that frame. **Not a VBL timestamp**, despite the name | s, Elapsed |
| `MissedBySec` | `skipped · ifi`, where `skipped = slot − previousSlot − 1` | s |

### 10.4 `…_leaves_ssvepframes.csv` (`LeafGameCore.cs:149`, `:202-212`; rows at `LeafGameController.cs:856-858`)

One row per flickering trial frame, from frame 1 to the response / miss frame `k`. Pre-SSVEP, feedback and ITI frames are not logged. The row of frame `k` holds the commanded luminance of a frame whose leaves were cleared for the feedback text before rendering, so it was not displayed.

| Column | Meaning | Units | Time base |
|---|---|---|---|
| `TrialNumber` | Trial | int | |
| `FrameNumber` | Trial frame index | int | |
| `EstimatedDisplayTime` | Predicted presentation time of this frame (`PresentationClock` VSync lattice) − T0 | s | Elapsed (prediction) |
| `FrameEndTime` | CPU `WaitForEndOfFrame` time of this frame − T0 (set by the `CaptureFrameEndClock` coroutine, `:333-349`) | s | Elapsed. The last logged frame (`k`) is followed by at least one feedback frame, so it is normally filled |
| `PhaseTimeSec` | `EstimatedDisplayTime − EstimatedDisplayTime(frame 1)` = flicker argument t | s | trial-relative |
| `NominalRefreshSlot` | `round(t · RefreshHz)` | int | |
| `BorderLuminanceC1` / `BorderLuminanceC2` | Commanded border grey (sRGB code value, before colour-space conversion) | 0..1 | |
| `FrequencyC1Hz` / `FrequencyC2Hz` | Frequencies this trial | Hz | |
| `RefreshHz` | `refreshHz` fixed at trial start | Hz | |

### 10.5 Stimulus-frame CSV (`FrameStimulusCsvLogger`, schema 3; `Assets/CogLab/Shared/Timing/FrameStimulusCsvLogger.cs`)

Recorded once per flickering trial frame (frame 1 to the response / miss frame) from `UpdateTrial` (`:864`) with:
- `Game = leaf`
- `TrialNumber = trialIndex+1`
- `Stage = trial`. The code still passes `feedback` when `inFeedback` is set, but feedback frames return before the record call, so `feedback` never appears. Pre-SSVEP frames are not recorded.
- `PhaseOriginMonotonicSec = trialPhaseT0`
- intensities `lum1`/`lum2` (C1/C2 border grey)
- this trial's frequencies, mean, depth and phases

All time columns are **absolute** `MonotonicClock` seconds (not relative to T0). `TimestampUnixMs` maps the CPU sample time through one UTC anchor. The full column list and its meaning are in the shared document. The k-th stimframes row of trial n corresponds to `ssvepframes` row (n, FrameNumber = k). The metadata JSON holds the UTC/monotonic anchor, device, screen size and target frame rate.

### 10.6 BciCore EEG logs (BciCore source only)

- Created by `BciServer`. Leaf calls `BciServer.StartServer(enableLogging: mode ≠ Disabled, directCsvMode: mode == DirectCsv, participant, block)` (`LeafGameController.cs:322-324`).
- The launcher sets `GameName = "leaf"` (`CogLabAppController.cs:701`).
- Mode comes from the launcher's Common EEG logging mode (default DirectCsv). A standalone run uses DirectCsv.
- Folder stem: `eeg_leaf_p<P>_s<B>_<local yyyyMMdd_HHmmss>` (participant/block sanitised to letters, digits, `-`, `_`).
- Files: `<stem>_raw.csv`, `_signals.csv`, `_features.csv`, `_health.csv`, `_config.txt` (BinaryThenCsv: `.bin` files plus `_meta.json`, converted to CSV at export).
- Leaf-specific content:
  - The `marker` column of `raw`/`signals` (and `features`) contains the board-latched Leaf codes from section 9.
  - `health.csv` gets one row per Leaf send with `event = trigger_sent:<reset|trialstart|success|response|trialstop>`, `marker = code`, `wall_sec` = local time of day in **integer seconds**, `seq = 0`.
  - `features.csv` `v3`/`v4` (NF frames) are `Smi14gt18Shaped`/`Smi18gt14Shaped`, i.e. NfIndex 0 / 1. For CCA frames, `v1`/`v2` = `FbAgtB`/`FbBgtA`.
- Column definitions: see the shared document.

With File, Tcp or UsbBiosemi sources, Leaf writes **no EEG file**. EEG is recorded by the external system that receives the UDP/USB markers.

### 10.7 Not written

Leaf writes no session or metadata file of its own. Not logged anywhere in data files:
- seed;
- T0;
- effective pixel scale and field rectangle;
- settings values (other than the per-trial columns above);
- NF source;
- device and refresh information (except per-trial `RefreshHz` and the optional stimframes metadata).

Pre-reveal button presses are not logged.

---

## 11. Settings reference

Precedence from lowest to highest:
1. C# initializer;
2. prefab YAML;
3. scene prefab-instance override (only `nfSourceType`);
4. saved per-game JSON `CogLab.Games.leaf.v1` (migrations: 17/19 Hz → 15/17 Hz once via `ssvepFrequencyVersion`; `cueFirstMaxTrialSec` → `trialLengthSec`; `MigrateTrialFlow` (`LeafGameController.cs:276-286`, called from `LeafGameModule.ApplySavedSettings`, `LeafGameModule.cs:6-11`): nothing happens if the saved JSON has `trialFlowVersion ≥ 2`; if it is below 1 (or missing), `instructionsText` is reset once to the new default text; if it is below 2, `preSsvepSec` 1 → 1.5 and `preSsvepFlashHz` 2 → 4, but only where the saved value is still the old default (custom values are kept); then `trialFlowVersion` = 2. Later operator edits are kept. A saved `cueFromTrialStart` value is ignored, since the field no longer exists);
5. Common-tab shared values (`CogLab.Common.v1.sharedValues`), applied to every game that has the field.

The launcher passes participant/session and the EEG logging mode separately (`ConfigureSharedLaunch`, `LeafGameController.cs:278-286`).

UI label = the field name passed through `Nicify` (e.g. `NfGreenHoldSec` → "Nf Green Hold Sec"). Fields marked **[Common]** are hidden from the Leaf tab and edited in the launcher's Common tab under the label given (`Assets/CogLab/App/SharedSettingsCatalog.cs:563-579`; a Common entry exists only if at least two games have the field). "Prefab ≠ code" lists where the prefab value differs from the C# initializer.

### Experiment Design
| UI label | Field | Effective default | Unit | Meaning |
|---|---|---|---|---|
| Trials Per Block | `trialsPerBlock` | 24 | trials (≥ 1) | Block length |
| Cue C1 Probability | `cueC1Probability` | 0.5 | 0–1 | Fraction of C1 (Pointing) cues, rounded half-to-even |
| [Common] Use fixed random seed | `useFixedRandomSeed` | false | bool | Section 5 |
| [Common] Fixed random seed | `fixedRandomSeed` | 918273 | int | |
| Mix Participant And Block Into Seed | `mixParticipantAndBlockIntoSeed` | true | bool | XOR string hashes into the seed |

### Trial Timing / After colour reveal
| UI label | Field | Default | Unit | Meaning |
|---|---|---|---|---|
| [Common] Pre-SSVEP period before each trial (seconds) - Leaf / Arrow | `preSsvepSec` | 1.5 | s → frames (Common range 0–60) | Red-flash cue period before SSVEP onset; 0 disables (`SharedSettingsCatalog.cs:37`) |
| Pre Ssvep Flash Hz | `preSsvepFlashHz` | 4 | Hz (≥ 0.1) | On/off rate of the red target flash |
| Pre Ssvep Border Luminance | `preSsvepBorderLuminance` | 0.5 | sRGB 0–1 | Steady pre-SSVEP border grey (keep = SSVEP mean) |
| Trial Length Sec | `trialLengthSec` | 15 | s | Time allowed for NF success; then timeout reveal (section 4) |
| Response Timeout Sec | `ResponseTimeoutSec` | 4 | s | Response window from colour onset |
| Feedback Sec | `FeedbackSec` | 1 | s → frames | Feedback duration (response and missed) |
| Iti Sec | `ItiSec` | 5 | s → frames | ITI |

### Points
| UI label | Field | Default | Meaning |
|---|---|---|---|
| Points Nf Success Correct | `pointsNfSuccessCorrect` | 100 | Correct response after an NF reveal |
| Points Nf Failure Correct | `pointsNfFailureCorrect` | 10 | Correct response after a timeout reveal |

### Neurofeedback
| UI label | Field | Effective default | Unit | Meaning |
|---|---|---|---|---|
| Nf Source Type | `nfSourceType` | **BciCore** (scene override; prefab `3` UsbBiosemi; code `Tcp`) | enum File/Tcp/BciCore/UsbBiosemi | Section 7 |
| Nf File Path | `nfFilePath` | `C:\Users\Kalyanbrata\Documents\MATLAB\FeatureAttention\nf.txt` (prefab ≠ code `nf.txt`) | path | File source |
| Nf Path Maximum Characters | `nfPathMaximumCharacters` | 1024 | chars | **Unused** |
| Nf Tcp Host | `nfTcpHost` | 10.36.17.144 | host | TCP NF host; UDP trigger host (File/Tcp/BciCore) |
| Nf Tcp Port | `nfTcpPort` | 5006 | port | TCP NF port |
| [Common] USB Biosemi port | `usbBiosemiPort` | 5010 | port | USB bridge (loopback) |
| [Common] Connection timeout (seconds) | `nfTcpTimeoutSec` | 10 | s | First-record wait (Tcp/USB) |
| Nf Stream Stall Warn Sec | `nfStreamStallWarnSec` | 2 | s | Warning threshold (0 = off) |
| [Common] USB NF stall timeout | `usbNfStallAbortSec` | 5 | s | USB abort threshold (0 = off) |
| [Common] Data folder | `dataFolderName` | `data` | path | Task CSV / stimframes folder |
| [Common] NF trace interval (seconds) | `NfTraceIntervalSec` | 0.1 | s → frames | Trace decimation |
| Nf Green Hold Sec | `NfGreenHoldSec` | 1 | s → frames | Reveal hold |
| Nf Rate Per Unit Per Sec | `NfRatePerUnitPerSec` | 3 | 1/s per NF unit | Integration gain |
| Nf Clip | `NfClip` | 1 | NF units | Symmetric clip |
| Nf White Top Relaxation | `NfWhiteTopRelaxation` | 0.10 | 0–1 | Green threshold = 1 − value |

### SSVEP / display
| UI label | Field | Default | Unit | Meaning |
|---|---|---|---|---|
| [Common] Stimulus 1 / … low frequency | `frequencyC1Hz` | 15 | Hz | Low / C1 frequency |
| [Common] Stimulus 2 / … high frequency | `frequencyC2Hz` | 17 | Hz | High / C2 frequency |
| (hidden) | `ssvepFrequencyVersion` | 1 | — | Migration marker |
| Randomize Ssvep Frequencies | `randomizeSsvepFrequencies` | true | bool | Per-trial balanced swap; markers 31–34 |
| Precomputed Phase Horizon Sec | `precomputedPhaseHorizonSec` | 300 | s | Phase horizon floor |
| Phase Horizon Safety Margin Sec | `phaseHorizonSafetyMarginSec` | 2 | s | |
| Ssvep Mean Luminance | `ssvepMeanLuminance` | 0.5 | 0–1 | Flicker mean |
| Ssvep Modulation Depth | `ssvepModulationDepth` | 1 | 0–1 | Amplitude = min(mean, 1−mean)·depth |
| Phase C1 Degrees / Phase C2 Degrees | `phaseC1Degrees`, `phaseC2Degrees` | 0, 0 | deg | Phase offsets (follow the group, not the frequency) |
| [Common] Display / target refresh rate (Hz) | `requestedDisplayRefreshRateHz` | 120 | Hz | Requested panel rate / target fps |
| Target Frame Rate Override | `targetFrameRateOverride` | 0 | fps | If > 0, overrides `Application.targetFrameRate` |
| [Common] VSync count (desktop) | `verticalSyncCount` | 1 | 0–4 | Desktop only; forced to 0 on Android by `DisplayRateManager` |
| Request Closest Supported Refresh Rate | `requestClosestSupportedRefreshRate` | true | bool | **Unused** |
| Abort Trial On Refresh Rate Change | `abortTrialOnRefreshRateChange` | true | bool | Fatal on change |
| Refresh Rate Change Tolerance Hz | `refreshRateChangeToleranceHz` | 0.5 | Hz | |
| Minimum Valid Refresh Hz | `minimumValidRefreshHz` | 30 | Hz | |
| Fallback Refresh Hz | `fallbackRefreshHz` | 60 | Hz | Used if the observed rate is invalid |
| Run In Background | `runInBackground` | true | bool | |
| Prevent Screen Sleep | `preventScreenSleep` | true | bool | |

### Debug Logging / Triggers
| UI label | Field | Default | Meaning |
|---|---|---|---|
| [Common] Log stimulus intensity every frame | `logStimulusIntensityEveryFrame` | false | Enables the stimframes CSV |
| [Common] UDP trigger port | `triggerPort` | 5007 | UDP marker port (File/Tcp/BciCore copy) |
| Reset Trigger | `resetTrigger` | 0 | |
| Trial Start Trigger | `trialStartTrigger` | 20 | Legacy C1 start |
| Trial Start C2 Trigger | `trialStartC2Trigger` | 21 | Legacy C2 start |
| Success Trigger | `successTrigger` | 50 | Colour reveal |
| Response Trigger | `responseTrigger` | 40 | Accepted response |
| Trial Stop Trigger | `trialStopTrigger` | 30 | |

### Responsive Screen Layout
| UI label | Field | Effective default | Code default | Meaning |
|---|---|---|---|---|
| Use Responsive Sizing | `useResponsiveSizing` | true | | Scale by short side |
| Reference Short Side Px | `referenceShortSidePx` | 1080 | | |
| Minimum Screen Scale | `minimumScreenScale` | **0.25** | 0.05 | Scale floor |
| Maximum Screen Scale | `maximumScreenScale` | 4 | | |
| Auto Fit Minimum Fraction | `autoFitMinimumFraction` | **0.35** | 0.25 | Lowest auto-fit scale as a fraction of requested |
| Auto Fit Step Fraction | `autoFitStepFraction` | 0.05 | | |
| Stimulus Width Fraction / Height Fraction | `stimulusWidthFraction`, `stimulusHeightFraction` | 1, 1 | | Viewport fraction of the safe area |
| Safe Area Padding Reference Px | `safeAreaPaddingReferencePx` | 0 | | |

### Leaves
| UI label | Field | Default | Meaning |
|---|---|---|---|
| Leaf Size Px | `leafSizePx` | 150 | Inner length (ref px) |
| Leaf Width Multiplier | `leafWidthMultiplier` | 0.42 | Width / length |
| Leaf Border Multiplier | `leafBorderMultiplier` | 0.20 | Border / length |
| Leaf Speed Px Per Sec | `leafSpeedPxPerSec` | 200 | ref px/s (applied per frame) |
| Leaves Per Flock | `leavesPerFlock` | 8 | Per group (1–100) |
| Lane Clearance Margin Px | `laneClearanceMarginPx` | 6 | |
| Max Field Shrink Px | `maxFieldShrinkPx` | 400 | Field search range |
| Min Repeats Per Axis | `minRepeatsPerAxis` | 1 | |
| Leaf Arc Points | `leafArcPoints` | 10 | Polygon resolution |
| Verify Leaf Paths At Setup | `verifyLeafPathsAtSetup` | true | Also consumes session RNG draws |
| Verification Max Frames | `verificationMaxFrames` | 40000 | |

### Cue
| UI label | Field | Default | Meaning |
|---|---|---|---|
| Double Cue Width Px / Cue Height Px | `doubleCueWidthPx`, `cueHeightPx` | 520, 90 | Whole double cue (ref px); each half is half the width |
| Cue Corner Radius Px / Cue Corner Segments | `cueCornerRadiusPx`, `cueCornerSegments` | 20, 8 | Outer corners only |
| Cue Font Size / Cue Character Size | `cueFontSize`, `cueCharacterSize` | 64, 0.5 | Max cue-word px = 64·0.5·s |
| Cue Text Outline Px | `cueTextOutlinePx` | 2 | |
| Feedback Font Size Px | `feedbackFontSizePx` | 96 | Centre feedback text (ref px) |
| Cue Bottom Margin Px | `cueBottomMarginPx` | 24 | Gap between the double cue and the bottom of the safe area |

`cueWidthPx` and `cuePosition` (and the `CueScreenPosition` enum) were removed; the double cue is always at the bottom.

### Input
| UI label | Field | Default | Meaning |
|---|---|---|---|
| [Common] Enable keyboard controls | `enableKeyboardArrows` | true | Arrow keys |
| Enable Swipe Responses | `enableSwipeResponses` | true | |
| Escape Ends Block | `escapeEndsBlock` | true | Escape → export |
| Swipe Threshold Px | `swipeThresholdPx` | 40 | ref px |

### Colors (sRGB)
`c1Srgb` (0, 0.749, 1) = 0,191,255; `c2Srgb` (1, 0.549, 0) = 255,140,0; `successSrgb` (0,1,0); `failureSrgb` (1,0,0); `preSsvepFlashSrgb` (1,0,0); `greenZoneSrgb` (0.702,1,0.702) = 179,255,179; `backgroundSrgb` black; `cueTextSrgb` black; `cueTextOutlineSrgb` white; `instructionBorderSrgb` white (instruction example border colour only). The prefab and code values are equal.

### UI text and appearance (no effect on data)
- `uiReferenceShortSidePx` 1080, `minimumUiScale` 0.15, `maximumUiScale` 4, `titleFontSize` 35, `bodyFontSize` 25, `centerFontSize` 22, `buttonFontSize` 26.
- `applicationTitle`, `participantLabel`, `blockLabel`.
- `continueButtonLabel` (**unused**), `beginBlockButtonLabel`.
- `cueC1Word` "Pointing", `cueC2Word` "Moving" (words in the right / left halves of the double cue).
- `correctFeedbackText` "Correct", `incorrectFeedbackText` "Incorrect", `missedFeedbackText` "Missed", `pointsSuffix` "points" (feedback text `"<verdict>\n+<N> points"`).
- `missedResponseText` "missed" (**written to `ParticipantResponse`**).
- `completedTitle`, `instructionC1Label`, `instructionC2Label`.
- `nfPathLabel` (prefab `NF file: `, code `NF file path`; **unused**), `resolvedNfPathLabel` (**unused**).
- `instructionsText` (default `DefaultInstructionsText`, `LeafGameController.cs:206`: target borders flash red before each trial; colours are also revealed when time runs out; bottom box = orange → MOVING, blue → POINTING; points 100 / 10 / 0). Hidden `trialFlowVersion` (2) is the migration marker for the instruction text and the pre-SSVEP defaults.
- Aesthetic: `backgroundTextureResource` `LeafGame/BackgroundTexture`, `panelSrgb`, `softPanelSrgb`, `accentSrgb`, `accentHoverSrgb`, `secondaryButtonSrgb`, `welcomeSubtitle`, `playButtonLabel`, `settingsButtonLabel`, `backButtonLabel`, `timeBoardLabel`, `scoreBoardLabel`, `reachedBoardLabel`.

### Session Defaults (standalone only; hidden in the launcher)
`participant` "000", `block` "000". In the launcher these are replaced by Common "Participant number" (default `000`) and "Block number" (`sessionNumber`, default `001`).

---

## 12. Timing & clock semantics

| Clock / origin | Definition | Used by |
|---|---|---|
| `MonotonicClock.Now` | `Stopwatch.GetTimestamp()/Frequency` in seconds (CLOCK_MONOTONIC on Android) | Everything below |
| **T0** (`experimentT0`) | `MonotonicClock.Now` in `BeginSession` (`LeafGameController.cs:573`): after calibration (BciCore) or **before** the TCP/USB connection wait, i.e. before the instructions screen. **Not logged.** | Every time column in the 4 task CSVs ("Elapsed"), HUD TIME |
| `preSsvepOnsetTime` | CPU end of pre-SSVEP frame 1 − T0 | `CueOnsetTime` |
| `trialStartClock` | CPU end of trial frame 1 (SSVEP onset) | Reveal limit (`trialLengthSec`) |
| `colorOnsetClock` | CPU end of the reveal frame (NF or timeout reveal) | Response window, RT |
| `trialPhaseT0` | Predicted presentation of trial frame 1 (absolute monotonic) | SSVEP phase; `PhaseOriginMonotonicSec` in stimframes |
| Predicted presentation | `PresentationClock` VSync lattice: Android Choreographer/frame-timeline expected vsync, or a monotonic fallback (Editor/desktop). One prediction per Unity frame. | `EstimatedDisplayTime`, `PhaseTimeSec`, slots |
| EEG | Board sample `seq` at the board's sample rate; `health.wall_sec` = local time of day (integer s) | EEG logs |

**What the times mean.**
- `CueOnsetTime`, `TrialStart`, `FirstGreenTime`, `ColorOnsetTime` and `TrialEnd` are **CPU end-of-frame** times. They are taken after Unity has issued the frame's rendering and, except `CueOnsetTime`, `FirstGreenTime` and timeout-reveal `ColorOnsetTime`, are the same instants at which the corresponding markers are sent.
- They are *not* photon times. The frame normally appears at the next VSync or later. A latency estimate per trial is `EstimatedDisplayTime(frame 1) − TrialStart` (from `ssvepframes`).
- `ActualPresentationMonotonicSec` in stimframes is always NaN. Actual scan-out is never measured.
- The pre-SSVEP period is frame-counted (`P` frames at nominal ifi); its flash timing uses nominal frame times `(i−1)·ifi`, not predicted presentation times.
- The `success` marker 50 marks the end of the NF reveal frame. The colours become visible about one presentation latency later. A timeout reveal has no marker; its time is only `ColorOnsetTime`.
- The `response` marker 40 is sent in `Update`, so it is the same instant as the RT end-point. The interval 50 → 40 in the EEG therefore corresponds to `ReactionTime`, apart from transport jitter.
- Precision: the CSV is written with 6 decimals (1 µs). The real uncertainty is about one frame (8.3 ms at 120 Hz) for event times and RT, plus scheduling jitter.

**"Dropped frame" here.**
- `slot = round(PhaseTimeSec · RefreshHz)`. A drop is recorded when the slot advances by more than 1 between consecutive trial frames.
- `PhaseTimeSec` comes from `PresentationClock`'s lattice, which advances exactly one slot per Unity frame unless it resynchronises: after a gap of at least 1.75 periods, or after 3 frames of drift above 0.75 slot. So a "drop" is a **predicted / scheduled** slot skip inferred from CPU timing. It is not a confirmed missing physical frame, and duplicated frames are not counted.
- If the lattice period (native Hz) and `RefreshHz` (DisplayRateManager) differ, rounding can create rare spurious ±1 slot artefacts.
- `DroppedFrameCount` = Σ skipped slots for the trial. `VBLTime` is CPU `Update` time.

**Frame-based durations.** Pre-SSVEP period, feedback, ITI, green hold, NF integration, leaf motion and trace decimation are counted in frames at the nominal ifi. When frames are skipped they take longer in wall time, and motion and NF integration slow down. The SSVEP phase is unaffected: it is time-based on predicted presentation, so skipped frames skip phase rather than stretching it.

---

## 13. Analysis guide

### 13.1 Keys and joins

- Within a run: `TrialNumber` joins `trialdata` ↔ `nftrace` ↔ `droppedframes` ↔ `ssvepframes`. (`TrialNumber`, `FrameNumber`) joins `nftrace` ↔ `ssvepframes` ↔ `droppedframes`.
- **Multiple runs in one file.** Files are appended per P/B. Split each file into runs wherever `TrialNumber` stops increasing (it restarts at 1), and check that `TrialStart` drops back (T0 restarts). Split all four files the same way. They are written together per trial, so their run boundaries line up.
- stimframes ↔ ssvepframes: the k-th row with `TrialNumber = n` in stimframes corresponds to `FrameNumber = k`. T0 can then be recovered as `T0 = PredictedPresentationMonotonicSec − EstimatedDisplayTime` (constant within a run; use the median). `PhaseTimeSec` should match in both.
- Task CSV ↔ EEG: through markers only. There is no shared timestamp (BciCore `health.csv` `trigger_sent` rows have only 1-s wall-clock resolution).

### 13.2 Aligning EEG markers with trial rows

1. Extract marker onsets from the EEG marker channel: rising edges / non-zero runs in `raw.csv` `marker` for BciCore, or the Biosemi status channel for USB/UDP set-ups. Collapse repeated samples of the same latched code into one event.
2. Drop leading `0` (reset) events and the board's reboot command (`0xFFFF`).
3. Segment by start codes {31,32,33,34} (shuffle) or {20,21} (legacy). Each trial is `S [50] [40] 30` (section 9.1). A trial without 50 had a timeout reveal (`NfSuccess = 0`); its colour onset is `S + (ColorOnsetTime − TrialStart)`. The pre-SSVEP period lies before `S`, from about `S − (TrialStart − CueOnsetTime)`.
4. Pair the EEG trials, in order, with the `trialdata` rows of the same run. Check the `TrialStartMarker` sequence. Mismatches mean:
   - **a final start with no CSV row**: a trial aborted by Escape/Exit/Fatal; ignore it;
   - **an extra `30` with no preceding start**: the export at block end, Escape or Exit (expected once per session, more for aborts);
   - **a missing reset in BciCore**: the reset is sent before the board is normally connected (see section 14).
5. Cross-check timing: (EEG time of `30`) − (EEG time of `S`) ≈ `TrialEnd − TrialStart`; (`50` − `S`) ≈ `ColorOnsetTime − TrialStart` (NF-success trials); (`40` − `50`) ≈ `ReactionTime`; (`40` − `S`) ≈ `ColorOnsetTime + ReactionTime − TrialStart` (all responded trials). Residuals of more than about 10–20 ms point to transport latency or jitter, or to mis-pairing.

### 13.3 Epoching suggestions

- **Pre-SSVEP (cue) period**: from `S − (TrialStart − CueOnsetTime)` to `S` (`PreSsvepSec`, 1.5 s). Moving leaves, steady grey borders, red flashes of the cued group, no flicker. Usable as a pre-stimulus baseline with a visual cue; note the 4 Hz red flash.
- **SSVEP / NF period**: from `S` + latency (`EstimatedDisplayTime[frame 1] − TrialStart`, typically one or two frames) to `50` (NF reveal) or to the timeout reveal at `S + (ColorOnsetTime − TrialStart)` (≈ `S + trialLengthSec`). The flicker is continuous and phase-locked to predicted frame 1. For phase-sensitive analysis (e.g. TRCA/CCA templates), build the reference from `PhaseTimeSec` per frame, or from `sin(2πf·t)` with t starting at the onset of frame 1.
- **Label for frequency decoding**: the target frequency is the cued group's frequency, `Cue = c1 ? FrequencyC1Hz : FrequencyC2Hz` (equivalently low if `NFIndexUsed = 1`, high if 2). The target was cued by the pre-SSVEP flash in every trial.
- **Reveal-locked**: −1 s to +`ResponseTimeoutSec` around the colour onset (`50`, or the derived time for timeout reveals). Split by `NfSuccess`.
- **Response-locked**: around `40`.
- After the reveal the borders keep flickering until the response / miss frame, so SSVEP is present during the response window. During feedback the field is empty (only the centre text, double cue and HUD), so there is no SSVEP there.
- **ITI baseline**: from `30` to the start of the next pre-SSVEP period (next `S − PreSsvepSec`), not to the next `S`.

### 13.4 Performance metrics

- NF success rate = mean(`NfSuccess`) = mean(`RevealTimeout == 0`).
- Time to NF reveal = `ColorOnsetTime − TrialStart` over `NfSuccess = 1` rows (≥ about 1.3 s with defaults). For timeout reveals it is ≈ `trialLengthSec` by construction. Time to first green = `FirstGreenTime − TrialStart`.
- Response rate = mean(`ResponseTimeout == 0`) (every completed trial is revealed).
- Accuracy among responded trials = mean(`Accuracy`) over rows with `ParticipantResponse ≠ missed`, split by `NfSuccess`. The game's own summary counts misses as incorrect.
- Points: `Points` per trial, `TotalPoints` of the last row of a run = summary Points.
- RT: `ReactionTime` for responded trials. Analyse correct and incorrect separately. The upper limit is `ResponseTimeoutSec`.
- **Error classification** (all four directions differ):

| Cue | Response equals | Interpretation |
|---|---|---|
| c1 | `C1PointDir` | correct |
| c1 | `C1MoveDir` | right group, wrong rule (moving) |
| c1 | `C2PointDir` | wrong group, right rule |
| c1 | `C2MoveDir` | wrong group, wrong rule |
| c2 | `C2MoveDir` | correct |
| c2 | `C2PointDir` | right group, wrong rule |
| c2 | `C1MoveDir` | wrong group, right rule |
| c2 | `C1PointDir` | wrong group, wrong rule |

- Split by `FrequenciesSwapped` / target frequency to check for frequency effects on reveal performance. Also split by `Cue` (Pointing vs Moving rule).

### 13.5 Using the NF trace

- `NFLevel` against `SampleTime` per trial shows the feedback the participant saw before the reveal (fill grey = `NFLevel`; green when `InGreenZone = 1`). The trace starts at trial frame 1 (the pre-SSVEP period has no NF) and ends at the response / miss frame.
- `NFValueRaw` is the held value. Count `NFReadOk` per trial to estimate the fresh-sample rate. Long runs of `NFReadOk = 0` indicate a stall.
- The level can be recomputed per frame only approximately from the trace, because rows are decimated and the held value is integrated every frame: `ΔL ≈ rate · ifi · clipped` per frame. Verify `NFLevel` monotonicity within runs of constant `NFValueClipped`.
- Pre-reveal NF statistic per trial: mean `NFValueClipped` with `ColorsRevealed = 0`. Compare it with the target channel. Only the target channel is logged; the other channel is available only in BciCore `features.csv` (`v3`/`v4`).

### 13.6 Sanity checks to run on every dataset

1. `TrialStartMarker` = `31 + (Cue=='c2') + 2·FrequenciesSwapped` (shuffle), or 20/21 by cue (legacy).
2. `NFIndexUsed − 1 == (Cue=='c2') XOR FrequenciesSwapped`.
3. `CorrectResponse == (Cue=='c1' ? C1PointDir : C2MoveDir)`. The four direction columns are all distinct.
4. Per run: `FrequencyC1Hz`/`FrequencyC2Hz` ∈ {f_low, f_high} and differ. Swaps are balanced within each cue to ±1 for complete blocks. Cue counts = round-half-even(N·p).
5. For each run of 24 trials, the 24 direction combinations each appear exactly once.
6. `NfSuccess == 1 − RevealTimeout`. `ColorOnsetTime` is defined in every row. `RevealTimeout = 1` ⇒ `ColorOnsetTime − TrialStart ≈ trialLengthSec` (+ ≤ 1 frame), no `50` marker in the EEG for that trial, and `Points ∈ {0, pointsNfFailureCorrect}`.
7. `ResponseTimeout = 1` ⇒ `ReactionTime` NaN, `ParticipantResponse = missed`, `Accuracy = 0`, `Points = 0`, and `TrialEnd − ColorOnsetTime ≈ ResponseTimeoutSec + FeedbackSec`.
8. A response ⇒ `0 < ReactionTime < ResponseTimeoutSec`, and `TrialEnd − ColorOnsetTime ≈ ReactionTime + FeedbackSec` (frame-quantised).
9. `FirstGreenTime ≤ ColorOnsetTime − NfGreenHoldSec` for NF-success trials (approximately, frame-based). `TrialStart − CueOnsetTime ≈ PreSsvepSec` (≈ 0 when `PreSsvepSec = 0`).
10. Points: `Points == (Accuracy ? (NfSuccess ? 100 : 10) : 0)` with default settings; `TotalPoints` is the cumulative sum of `Points` within a run.
11. `ssvepframes`:
    - rows per trial = frame of the response / miss ≈ `(TrialEnd − TrialStart)·RefreshHz + 1 − round(FeedbackSec·RefreshHz)`;
    - `FrameNumber` is contiguous from 1;
    - `PhaseTimeSec` is 0 at frame 1 and increases;
    - `BorderLuminanceC1 ≈ 0.5 + 0.5·sin(2π·FrequencyC1Hz·PhaseTimeSec)` (default mean, depth and phase);
    - `NominalRefreshSlot` steps of more than 1 match `droppedframes` rows, and the sum of the steps matches `DroppedFrameCount`.
12. `EstimatedDisplayTime − FrameEndTime` is positive and about 0–2 frames. Large or negative values indicate prediction issues.
13. `RefreshHz` is constant across trials and near the requested rate (120). 60 suggests a fallback, or that the panel was not switched.
14. `nftrace`: `FrameNumber ≡ 1 (mod nfTraceEvery)`; `NFLevel` ∈ [0,1]; `InGreenZone == (NFLevel ≥ 0.9)`; `ColorsRevealed` switches 0 → 1 at most once per trial (a row with 1 can be missing if the response came before the next decimated row); `PostCueOnset` is always 1.
15. EEG: one start per CSV row (plus possibly one aborted final start); every start is followed by `30`; there is exactly one trailing extra `30`.

---

## 14. Known caveats / doc discrepancies

**Effective defaults.**
1. **NF source default.** The code initializer is `Tcp`, the prefab stores `nfSourceType: 3` (UsbBiosemi), and the launcher scene instance overrides it to `2` (**BciCore**) (`CogLab.unity:643-646`). A saved `CogLab.Games.leaf.v1` overrides all three. The source used for a dataset is not logged. Infer it from which files exist: a `BciCoreLogs` folder means BciCore.
2. Prefab ≠ code for `minimumScreenScale` (0.25 vs 0.05), `autoFitMinimumFraction` (0.35 vs 0.25), `nfFilePath` (an absolute Windows path vs `nf.txt`; on Android this becomes `persistentDataPath/C:\Users\...`, which almost certainly does not exist) and `nfPathLabel` (unused).

**Markers.**

3. Marker set: Leaf sends only reset / trialstart / success (50) / response (40) / trialstop (30); the pre-SSVEP period and timeout reveals have no marker, and with shuffling Off the legacy start is always 20 (C1) or 21 (C2) (`LeafGameController.cs:737-738`). The README now says the same. README versions up to commit `5741b44` still listed a "45 cue onset" marker and a "pre-cue mode" (legacy start 20 for either cue); both were obsolete, and that "pre-cue" never referred to the current pre-SSVEP period. The README section "Leaf and Arrow independent response timing" (from `README.md:405`) now describes the current flow (pre-SSVEP period, timeout reveal, feedback, points).
4. **Extra `trialstop` (30) markers.** `StartSessionExport` always sends 30. This produces:
   - an extra 30 after the last trial's own 30 at normal block completion;
   - a 30 with no matching start when exiting from Instructions or Fatal, or when exiting while connecting;
   - two 30s for refresh-change (during a trial) and USB-stall aborts (one at the abort, one at the later exit); a refresh-change abort in the pre-SSVEP period sends none of its own.
5. **Aborted trials.** Escape/Exit/Fatal during a trial send markers (start, maybe 50/40, then 30) but write **no CSV rows** for that trial. An abort in the pre-SSVEP period leaves no start marker and no row, only the export 30. The points of an aborted trial are not added.
6. **Reset marker in BciCore mode.** It is sent immediately after `StartServer`, normally before the board connects. `SendMarker` then fails with a warning, and no EEG logger exists yet to record `trigger_sent:reset`. In addition, code 0 is usually indistinguishable from "no marker" in a marker channel.
7. **BciCore duplicate-marker risk.** `BciCoreTriggerSender` also sends a UDP copy to `nfTcpHost:triggerPort`. `BciServer` itself listens for UDP triggers on port 5007 and forwards them to the board (`EspTcpListener.cs:84`, `:121-136`). If `nfTcpHost` were set to the tablet itself (e.g. 127.0.0.1), each marker would reach the board twice. With the default external host this does not happen.
8. Validation (`SsvepFrequencyAssignment.Validate`) runs only when shuffling is On. With shuffling Off, any marker codes, including overlapping or duplicate ones, are accepted.

**Paradigm / UI.**

9. **Target cue only before SSVEP onset.** The target group is shown only by the red border flash in the pre-SSVEP period; during the trial both groups look identical until the reveal, so the participant must hold the target in memory. The double cue shows the colour → rule mapping, not the target. With `preSsvepSec = 0` (or less than half a frame) there is no target cue at all, yet `CueOnsetTime = TrialStart` is still written. The red flash (4 Hz on/off, `preSsvepFlashSrgb`) is itself a periodic visual stimulus just before SSVEP onset.
10. **Instruction text migration.** Saved settings from before this flow keep their old instruction text until `MigrateTrialFlow` replaces it once (saved `trialFlowVersion` below 1). Any custom text saved before the update is overwritten by that one-time reset. Profiles saved at version 1 keep their text but have the old pre-SSVEP defaults (1 s, 2 Hz) moved to 1.5 s and 4 Hz; values set by an operator are kept, so a dataset's actual length is best read from the `PreSsvepSec` column.
11. The double cue sits at the bottom of the safe area and can overlap the lower edge of the leaf field; leaves pass under it. The HUD (tiles at top right, Exit button at top left) is drawn over the stimulus during the pre-SSVEP period, trials and ITIs. Gameplay background is the `BackgroundTexture` image, not `backgroundSrgb` black.
12. **Feedback frames are not logged.** `ssvepframes`, `nftrace`, `droppedframes` and stimframes stop at the response / miss frame; the stimframes `feedback` stage never occurs. The last `ssvepframes` row (frame k) is a commanded frame whose leaves were cleared before display. `PreSsvepSec` gives the length actually shown (`P·ifi`), not the setting; the pre-SSVEP frames themselves are not logged.
13. **NF stall clock** is reset at `StartTrial`, before the pre-SSVEP period, in which NF is not read. The pre-SSVEP time therefore counts towards `nfStreamStallWarnSec` and `usbNfStallAbortSec` until the first fresh sample of trial frame 1.
14. `TrialDefinition.CueWord` is hard-coded ("Pointing"/"Moving") and unused. The displayed words come from `cueC1Word`/`cueC2Word`.

**Timing.**

15. Pre-SSVEP period, feedback, ITI, green hold, trace interval, NF integration and leaf motion are **frame-counted** using the nominal ifi. With missed frames they last longer in wall time, and NF integration and motion slow down.
16. `VBLTime` in `droppedframes` is CPU `Update` time, not a VBL timestamp. "Dropped" frames are predicted-slot skips (section 12).
17. `FrameEndTime` in `ssvepframes` is filled by an end-of-frame coroutine. Since the last logged frame is now always followed by feedback frames, the earlier NaN on a trial's final row should no longer occur; treat any NaN as a coroutine-ordering artefact.
18. T0, the seed, the effective pixel scale, the field rectangle and the NF source are not written to any data file. Leaf has no session file, unlike Arrow's `_arrow_session.csv`.
19. The task CSVs append across repeated runs with the same participant/block, `TrialNumber` restarts, and there is no run identifier (section 13.1).
20. **Colour-space handling.** `Render()` converts sRGB to linear manually before assigning `material.color` / `Text.color`, in a Linear-colour-space project. Unity may also convert `Material.color` values from gamma to linear in Linear space. If so, the displayed grey would be `toLinear(v)` instead of `v` (darker, and a different flicker waveform). The logged luminances are the pre-conversion `v`. Confirm the actual output with a photometer before making photometric claims.

**Code oddities.**

21. Stray line in `InitializeAestheticGameplayBackground` (`LeafGameController.Aesthetics.cs:62`): `if(state==AppState.Instructions){UpdateInstructionTouch();return;}` sits inside the `if(backgroundTexture!=null)` block. It looks copy-pasted from `UpdateAestheticInput`. In Instructions state it would skip `PositionCue()`/`UpdateInstructionDemo()`. It is harmless in practice, because this method runs from `InitializeGameplayFromSettings` while in Setup.
22. Escape is handled in every state except Setup:
    - in Calibration it starts the export while the calibration GUI component is still attached;
    - in Summary it re-runs the export.
23. Unused serialized fields: `requestClosestSupportedRefreshRate`, `nfPathMaximumCharacters`, `nfPathLabel`, `resolvedNfPathLabel`, `continueButtonLabel`. Also unused: `LeafVisualRenderer.RenderInstructionDemo` and the private `Offsets` helper.
24. `ValidateLayouts` consumes draws from the session `rng` (`:656`). Toggling `verifyLeafPathsAtSetup` therefore changes every trial's initial leaf positions, even with a fixed seed.
25. Swipe tracking state (`touchTracking`, `touchStart`) is updated only while responses are polled, and it is reset at each committed colour onset (`:947`). A touch that started before the colour onset, or was left unreleased in an earlier trial, can no longer complete a swipe.
26. The `AbortForRefreshRateChange` message prints `Screen.currentResolution` rather than the observed rate that triggered the abort (cosmetic).
27. `UsbBiosemiLink.Send` throws `ArgumentOutOfRangeException` for codes outside 0..255, before its try/catch. The `[Range(0,255)]` attributes prevent this in practice.
28. `cueStyle` is built in `InitStyles` but never used.

**Other documentation.**

29. `BciCore-Documentation.md`:
    - uses the old package id `com.featureattention.leafdirectionresponse` and log path `BciCoreLogs/eeg_<yyyyMMdd_HHmmss>/` (current: `org.iisc.coglab.games`, `BciCoreLogs/eeg_leaf_p<P>_s<B>_<yyyyMMdd_HHmmss>/`);
    - gives a standalone path under `LocalLow/DefaultCompany/LeafGame`;
    - describes calibration as added by `ApplySettingsAndContinue` directly (it now goes through `BciCalibration.Open`).
30. `BciCoreNfReader.cs` header comment maps index 0 → "C1 / Pointing" and 1 → "C2 / Moving". With shuffling, the index follows the cued group's *frequency* (low → 0, high → 1), not the cue. The BciCore field names (`14gt18`, `18gt14`) refer to old frequencies, whereas the stimuli default to 15/17 Hz.
31. README says the Common tab owns "fourteen" shared controls. The catalog has 15, including `preSsvepSec` ("Pre-SSVEP period before each trial (seconds) - Leaf / Arrow", range 0–60), which replaced the former `cueFromTrialStart` entry and applies to Leaf/Arrow.
32. README's stimframes description ("written … after each trial, during the ITI") is correct for Leaf. Note that the game tag is `leaf`, while the task CSVs use `leaves`.
33. `output/pdf/Leaf_task_scientific_report.pdf` (September) predates the pre-SSVEP cue period, the double cue, timeout reveals, points, the independent response window, shuffle markers 31–34 and the removal of the 45 marker. Use it for background only.

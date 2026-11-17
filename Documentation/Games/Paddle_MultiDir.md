# Paddle v2 — Direction Change (Multi-Directional) ("Paddlev2", "Pgv2")

Reference documentation for analysts. Verified against the code at commit `af3b034` (branch `Kalyanbrata`).
Shared clocks, transports, BciCore logging and the launcher are described in
[00-Shared-Infrastructure.md](00-Shared-Infrastructure.md). This document says exactly how this game uses them.

All paths are repo-relative. `PMD` = `Assets/Games/Paddle_MultiDir/Scripts/PaddleMultiDirGameController.cs`.

Naming used throughout this document:

- **internal phase** = the C# variable `trialPhase` (0, 1, 2).
- **task phase** = the participant-facing / marker / stimframes naming (phase 1, phase 2 = centre, phase 3).

| internal `trialPhase` | Task phase | stimframes `Stage` | Goal | Marker at its end |
|---|---|---|---|---|
| 0 | Phase 1 (initial cue) | `phase1` | Reach the **cued** edge | 39 `phase1_reached` |
| 1 | Phase 2 (return to centre) | `phase2` | Bring paddle back to screen centre | 40 `center_reached` + 41/42 `phase3_left/right` |
| 2 | Phase 3 (second cue) | `phase3` | Reach the **phase-3** cued edge | 30 `trialstop` |

---

## 1. Overview & paradigm

- The screen shows a wide paddle near the bottom. Its left 300 px and right 300 px (at 1920 px width) are vertical-bar
  gratings whose contrast is sinusoidally modulated at two SSVEP frequencies (default left 15 Hz, right 17 Hz). The middle
  300 px is plain paddle body. Two vertical edge lines are drawn 20 px inside the left and right screen edges.
- The participant steers the paddle horizontally by attending to the left or right flickering end. The BCI produces a pair
  of NF values (one per frequency); the game uses `NFRight − NFLeft` to set either paddle velocity (`VelocityUpdate`, default)
  or paddle offset from screen centre (`PositionUpdate`).
- Each trial has three task phases:
  1. A large arrow (`<` or `>`) cues a side. The participant must move the paddle until its leading edge reaches the cued
     edge line. Reaching the **opposite** edge line first ends the trial as a failure (`WRONG EDGE`).
  2. The arrow disappears and a translucent grey rectangle appears at screen centre. The participant must bring the paddle
     back so that its centre is within ±(blank-middle width / 4) of the screen centre (±75 px at 1920 width). Edge contact
     in this phase has no consequence.
  3. A new arrow cues a (pseudo-randomly planned) side, which can be the same as or opposite to the phase-1 side. The
     participant must reach that edge line; reaching the opposite edge line is `WRONG EDGE`.
- **Success rule**: `Success = 1` only if the phase-3 cued edge is reached (`PMD:466-469`) before `maxTrialDurationSec`
  (default 30 s, counted from motion onset and covering all three phases, `PMD:472`).
- Cognitive/BCI purpose: SSVEP-based lateralised-attention neurofeedback with a direction **change** (reversal or repeat)
  within a trial, giving event-locked transitions (39 → 40/41/42) for studying re-orienting of attention and control switching.
- The class docstring (`PMD:26-30`) still describes the single-edge Paddle port of `gameBreakoutv7p1_val.m`; the 3-phase
  logic is specific to this game.
- The participant-facing instructions text (default, `PMD:124`) is identical to Paddle's and **does not mention** the
  centre return or the second cue (see section 14).

## 2. Code map

| Item | Value | Source |
|---|---|---|
| Game controller | `PaddleGame.PaddleMultiDirGameController : MonoBehaviour, IGameSession` (all logic, rendering, CSV logging) | `PMD:32` |
| Nested logger | `PaddleMultiDirGameController.PaddleCsvLogger` (trialdata / trace / droppedframes CSVs) | `PMD:755-819` |
| Enums | `PaddleConnectionMode { BciCore=0, UsbBiosemi=1 }`, `PaddleMotionMode { VelocityUpdate=0, PositionUpdate=1 }`, private `GameState { WaitingForLaunch, Calibration, Instructions, Preview, Trial, Feedback, Summary, Exporting, Fatal }` | `PMD:21,24,34` |
| Launcher module | `PaddleGame.PaddleMultiDirGameModule : GameModule` (only overrides `ValidateSettings` → controller's) | `Assets/Games/Paddle_MultiDir/Scripts/PaddleMultiDirGameModule.cs:4-8` |
| Assembly | `CogLab.Games.PaddleMultiDir` (refs `CogLab.Framework`, `CogLab.Shared`, `BciCore`, `Unity.InputSystem`) | `Assets/Games/Paddle_MultiDir/CogLab.Games.PaddleMultiDir.asmdef` |
| Prefab | `Assets/Games/Paddle_MultiDir/Prefabs/PaddleMultiDirGame.prefab` (disabled controller template + enabled module) | prefab:43,126 |
| Scene instance | `Assets/CogLab/App/Scenes/CogLab.unity` ("Paddle MultiDir Game"); **overrides `connectionMode` to 0 = BciCore** | `CogLab.unity:840-843` |
| Game ID | `paddle-multidir` | prefab:131 |
| Display name | `Paddlev2` | prefab:132 |
| PlayerPrefs key | `CogLab.Games.paddle-multidir.v1` | `Assets/CogLab/Framework/GameModule.cs:29` |
| Shared helpers used | `BalancedDirectionSchedule` (Build, BuildFinalSides), `SsvepFrequencyAssignment` (Build, StartMarker, MapPair, ValidatePaddle), `PresentationClock`, `FrameStimulusCsvLogger`, `DisplayRateManager.ApplyPresentation`, `BciCoreNfReader`, `BciCoreTriggerSender`, `UsbBiosemiLink`, `BciCalibration`/`CalibrationScreen`, `BciServer` | see sections below |
| Tests | No tests in the game folder. Covered by `Assets/CogLab/App/Tests/Editor/PaddleFamilySettingsTests.cs` (defaults, migration, schedules, start markers, CSV header versioning) and `Assets/CogLab/Shared/Tests/Editor/BalancedDirectionScheduleTests.cs` (balance, run limits incl. interleaved phase-1/phase-3 order, NF mapping, marker validation) | |

Settings persistence: launcher serialises the template with `JsonUtility` into the PlayerPrefs key; on load,
`ApplySavedSettings` also runs `SsvepSettingsMigration` (17/19 → 15/17 Hz once), `TrialLengthSettingsMigration` (no-op here)
and `PaddleSettingsMigration` (clamps saved `maxConsecutiveDirectionTrials > 2` to 2)
(`Assets/CogLab/Framework/GameModule.cs:70-77`, `Assets/CogLab/Framework/PaddleSettingsMigration.cs`).

## 3. Session flow / state machine

```
Launcher "Play" (validates identity + settings, saves prefs, SetSessionIdentity(p,s,"paddle-multidir"))
   |
   v
Start()  -- not launched from launcher --> Fatal("must be started from the launcher")
   |  ApplyPresentation(targetFrameRate, verticalSyncCount); seed rng; experimentT0 = realtimeSinceStartup;
   |  create task CSVs (+ stimframes CSV if enabled)
   |
   +-- connectionMode == UsbBiosemi --> WaitingForLaunch --(link.IsReady)--> Instructions
   |                                         |--(timeout max(1,usbConnectionTimeoutSec) or link error)--> Fatal
   |
   +-- connectionMode == BciCore ----> BciServer.StartServer(logging per launcher mode);
                                       trigger "reset"(0); Calibration (shared GUI)
                                         |-- Proceed --> ExitCalibrationMode; new BciCoreNfReader --> Instructions
                                         |-- Back    --> ReturnToSharedLauncher (no export)
Instructions --"Begin session"--> BeginSession(): ValidateSettings (else Fatal); build schedules
   v
Preview (trial i) --(now - previewStart >= preSpawnDelaySec)--> BeginTrialMotion: marker trialstart --> Trial
Trial --(success / wrong edge / timeout)--> FinishTrial: marker 30, trial row --> Feedback
Feedback --(feedbackDurationSec)--> i++ ; i < N ? Preview : EndSession
EndSession --> Exporting --> Summary --"Back to games"--> launcher
```

| State | Entered | Leaves | Notes / source |
|---|---|---|---|
| `WaitingForLaunch` | Start, USB mode | link ready → Instructions; timeout/error → Fatal | `PMD:223-230,249-264` |
| `Calibration` | Start, BciCore mode | Proceed → Instructions; Back → launcher | `PMD:233-239,266-273`; OnGUI draws nothing (`PMD:579`) |
| `Instructions` | after link/calibration | Begin button → `BeginSession` | `PMD:596-604` |
| `Preview` | `StartTrialPreview` | after `preSpawnDelaySec` → Trial | paddle static at centre, arrow + flicker shown, HUD "GET READY" (`PMD:291-294,324-350`) |
| `Trial` | `BeginTrialMotion` | `FinishTrial` → Feedback | `PMD:352-474` |
| `Feedback` | `FinishTrial` | after `feedbackDurationSec` → next Preview or `EndSession` | only the text "Trial n: SUCCESS!/WRONG EDGE/TIMEOUT!" in green/red; **no paddle, no flicker** (`PMD:632-639`) |
| `Exporting` | `EndSession` / `ExitToMainMenu` | async: stimframes CSV completion, then (BciCore only) `BciServer.ConvertCurrentSessionToCsvAsync` → Summary or launcher | `PMD:507-558` |
| `Summary` | after export (`EndSession`) | "Back to games" → launcher | shows `100*successCount/trialsPerSession` (planned N, even if aborted) (`PMD:619-624`) |
| `Fatal` | errors | only the "Exit to menu" button | `PMD:560-564,626-630` |

Fatal / abort conditions:

| Condition | Effect | Source |
|---|---|---|
| Not launched via launcher (`ConfigureSharedLaunch` not called) | Fatal at Start | `PMD:206-210` |
| Exception in Start (e.g. CSV creation) | Fatal | `PMD:242-246` |
| USB link not ready within `max(1, usbConnectionTimeoutSec)` or link error | Fatal | `PMD:251-261` |
| USB link `Error` non-empty in any state except WaitingForLaunch/Fatal (incl. Summary/Exporting) | Fatal; **no `trialstop` is sent** | `PMD:277-282` |
| USB mode, no fresh NF pair for `usbNfStallAbortSec` (default 5 s) during Trial | sends `trialstop` (30), Fatal; no trial row for that trial | `PMD:385-391` |
| `ValidateSettings` fails at Begin | Fatal | `PMD:309-313` |
| Schedule unavailable | Fatal | `PMD:326-330` |

Escape / Exit:

- **Escape key** (Input System keyboard), honoured in every state except Calibration, Summary, Fatal (`PMD:283-288`):
  `EndSession` → if in Trial sends `trialstop`; flushes task CSVs; exports; shows Summary. The interrupted trial gets **no
  trialdata row** (its trace rows and dropped-frame rows do exist).
- **"Exit to menu" button** (top-right, every state except Calibration, `PMD:582-587`): same as Escape but returns
  straight to the launcher after export (no Summary).
- `OnDestroy` (`PMD:566-575`): flushes stimframes batch (fire-and-forget), sends `trialstop` if still in Trial, flushes task
  CSVs if not already, disposes NF reader/trigger sender, `BciServer.StopServer()` in BciCore mode.

## 4. Trial structure & timing

All gating is done in `Update()` with `now = Time.realtimeSinceStartupAsDouble` (seconds, real time), so every duration is
quantised to the frame on which the check first succeeds (≤ 1 frame late, 8.3 ms at 120 Hz). Motion integration uses
`Time.unscaledDeltaTime` (frame-based).

```
 prev trial end (marker 30)                                              next trial end
   |<-- Feedback: feedbackDurationSec (2 s) -->|<-- Preview: preSpawnDelaySec (2 s) -->|<-------- Trial (motion) ---------->|
   |  text only, no paddle/flicker              |  paddle at centre, arrow (phase-1    |  phase1 --39--> phase2 --40,41/42--> phase3 --30
   |                                            |  side), flicker ON (phase origin t0) |  (any phase) --timeout 30 s from motion onset--> 30
   |                                            |  HUD "GET READY", no NF read         |  HUD "TIME: remaining"
                                         stimframes phase origin                  marker 20/21 or 31-34 = TrialStart
```

| Parameter | Field | Effective default | Used as |
|---|---|---|---|
| Preview / pre-motion | `preSpawnDelaySec` | 2 s | `now - stateStartedAt >= preSpawnDelaySec` (`PMD:293`) |
| Trial timeout | `maxTrialDurationSec` | **30 s** (Paddle: 10 s) | `now - trialStartedAt >= maxTrialDurationSec` checked every Trial frame, after the phase checks (`PMD:472`) |
| Feedback | `feedbackDurationSec` | 2 s | `PMD:299` |
| PositionUpdate glide | const `PositionUpdateIntervalSec` | 0.1 s (not configurable) | `PMD:37,423` |
| Trace interval | `traceLogIntervalSec` | 0.1 s | `PMD:436` |

What ends a trial (`FinishTrial`, `PMD:476-489`, guarded by `state == Trial`):

| End | Condition | Feedback text | Success | Timeout |
|---|---|---|---|---|
| Success | internal phase 2 and leading edge reaches phase-3 cued edge line | `SUCCESS!` (green) | 1 | 0 |
| Wrong edge, phase 1 | internal phase 0 and paddle reaches the opposite edge line | `WRONG EDGE` (red) | 0 | 0 |
| Wrong edge, phase 3 | internal phase 2 and paddle reaches the edge opposite the phase-3 cue | `WRONG EDGE` | 0 | 0 |
| Timeout | elapsed since motion onset ≥ `maxTrialDurationSec`, any phase | `TIMEOUT!` (red) | 0 | 1 |

Same-frame ordering: phase checks run before the timeout check, so a success on the timeout frame counts as success.
A phase transition (39, or 40+41/42) and a timeout (30) can occur on the same frame. A phase-2→3 transition never ends
the trial on the same frame, because the phase-3 edge test runs from the next frame.

ITI: there is no separate ITI. Between motion periods the participant sees Feedback (2 s, no stimulus), then Preview (2 s,
flicker on, static paddle). The first trial also starts with Preview.

Minimum achievable trial duration (VelocityUpdate, defaults, 1920 reference px): phase 1 needs a travel of 490 px
(centre 960 → 470), phase 2 at least 415 px (≤ 470 → ≥ 885), phase 3 415–565 px, so ≥ ~2.2 s at the 600 px/s cap.

## 5. Trial planning / randomisation

Built once in `BeginSession` (`PMD:314-321`) from one `System.Random rng`:

1. `trialSides = BalancedDirectionSchedule.Build(trialsPerSession, rng, maxConsecutiveDirectionTrials)`
   (`Assets/CogLab/Shared/Timing/BalancedDirectionSchedule.cs:15-30`): exactly N/2 left (−1) and N/2 right (+1), no run of
   identical sides longer than `maxConsecutiveDirectionTrials` (1 or 2). Sequential sampling with probability
   `left_remaining/(left+right remaining)` and feasibility bounds (no rejection sampling).
2. `tagRng = new Random(rng.Next())` — one draw from `rng`, **always** (even when shuffling is off).
3. `trialFrequencySwaps = randomizeSsvepFrequencies ? SsvepFrequencyAssignment.Build(cueIndices, tagRng) : all false`
   (`SsvepFrequencyAssignment.cs:9-25`): within each initial-cue stratum, half the trials are swapped (shuffled index set);
   an odd stratum gets the extra swap alternately (random start).
4. `phase3TrialSides = BalancedDirectionSchedule.BuildFinalSides(trialSides, rng, maxConsecutiveDirectionTrials)`
   (`BalancedDirectionSchedule.cs:33-62`): backtracking search; exactly N/2 left phase-3 cues; phase-3 runs ≤ `maxRun`;
   and the **interleaved** cue order `first[0], final[0], first[1], final[1], …` never has more than **2** identical
   directions in a row (hard-coded 2, independent of `maxRun`).

Consequences:

- Phase-3 side is planned independently of whether the participant reaches phase 3. Observed phase-3 cue counts are
  unbalanced when trials end before phase 3.
- "Same vs reversed" (phase-3 side = phase-1 side or not) is **not** explicitly balanced; it is constrained only by the
  interleaved-run rule (e.g. if `final[i-1] == first[i]`, then `final[i]` must differ from `first[i]`).
- Swaps are balanced within the initial-cue stratum only, not within phase-3 side.
- Shuffle on/off does not change `trialSides` or `phase3TrialSides` (tested: `PaddleFamilySettingsTests.cs:257-291`).

Seeding (`PMD:215`): `seed = useFixedRandomSeed ? fixedRandomSeed : unchecked(Environment.TickCount*397 ^ participant.GetHashCode() ^ session.GetHashCode())`.
The seed is **not logged**. With a fixed seed, all three schedules are reproducible (same `trialsPerSession`, `maxConsecutiveDirectionTrials`).
Without it, the realised schedule is recoverable only from the trialdata rows (`InitialTargetSide`, `Phase3TargetSide`,
`FrequenciesSwapped`) of trials that finished.

## 6. Stimulus

Rendering: IMGUI (`OnGUI`), solid rectangles via `GUI.DrawTexture(whiteTexture)` with `GUI.color` (`PMD:736-742`).

Geometry (`GetGeometry`, `PMD:706-719`); `sx = Screen.width/1920`, `sy = Screen.height/1080`; all values in screen px:

| Quantity | Formula | 1920×1080 default |
|---|---|---|
| fieldLeft / fieldRight | `fieldMarginPx*sx` / `W − fieldMarginPx*sx` | 0 / 1920 |
| fieldTop / fieldBottom | `(fieldMarginPx+hudHeightPx)*sy` / `H − fieldMarginPx*sy` | 80 / 1080 |
| paddle width × height | `paddleWidthPx*sx` × `paddleHeightPx*sy` | 900 × 200 |
| paddle bottom / top | `fieldBottom − paddleBottomMarginPx*sy` / `bottom − height` | 1030 / 830 |
| border | `max(1, paddleBorderPx*sx)` drawn around the paddle | 3 |
| grating width (each end) | `paddleGratingWidthPx*sx` | 300 |
| blank middle width | `paddleWidth − 2*gratingWidth` | 300 |
| bar width | `max(1, gratingBarWidthPx*sx)`; `ceil(gratingWidth/barWidth)` bars, last bar truncated | 14 px, 22 bars (last 6 px) |
| leftEdge / rightEdge (thresholds) | `fieldLeft + edgeInsetPx*sx` / `fieldRight − edgeInsetPx*sx` | 20 / 1900 |
| edge lines | rects at x = leftEdge and x = rightEdge, width `max(1, edgeLineThicknessPx*sx)`, from fieldTop to fieldBottom (both lines extend to the **right** of their threshold x) | 4 px |
| paddle centre clamp | `[fieldLeft + w/2 + border, fieldRight − w/2 − border]` | [453, 1467] |
| centre target rect (task phase 2) | x = `W/2 − blank/2`, width = blank, height = `1.5*paddleHeight`, bottom = paddle bottom; colour `(0.5,0.5,0.5,0.5)` drawn **before** the paddle (paddle occludes its lower 2/3) | 810–1110 × 730–1030 |
| arrow | `"<"`/`">"` label, font `150*UiScale`, rect `(W/2 − 190sx, 0.38H, 380sx, 180sy)`, colour `readyColor`; shown in task phases 1 and 3 and in Preview | |
| HUD | "TRIAL i/N" left, "GET READY" (Preview) or "TIME: x.xs" remaining right, white | |

`UiScale = clamp(min(W/1920, H/1080), 0.55, 2.5)` (`PMD:721`). Paddle starts each trial at `W/2` (`PMD:339`).

Hit tests (`PMD:429-434`): `left = centre − w/2`, `right = centre + w/2`; cue left: correct if `left ≤ leftEdge`, wrong if
`right ≥ rightEdge`; cue right: mirror. Centre (task phase 2): `|centre − W/2| ≤ blank/4` (75 px at 1920) (`PMD:456-458`).

Motion: see section 7.

Colours: fields are sRGB; `Render()` converts to linear when the project is in Linear colour space (`PMD:744`); this
project is Linear (`ProjectSettings/ProjectSettings.asset:50`, `m_ActiveColorSpace: 1`). Lerps therefore happen in linear space.

| Field | sRGB (0–255) |
|---|---|
| backgroundColor | 10,12,20 |
| gratingMidColor | 128,128,128 |
| leftBarHigh / leftBarLow | 0,230,230 / 0,80,80 |
| rightBarHigh / rightBarLow | 255,220,0 / 100,80,0 |
| paddleBodyColor / paddleBorderColor | 30,30,60 / 0,180,220 |
| edgeLineColor | 200,200,200 |
| readyColor (arrow) | 0,255,200 |
| successColor / failureColor (feedback text) | 0,255,0 / 255,0,0 |
| hudColor | 220,220,255 — **unused** (HUD text is white) |

SSVEP modulation (`PMD:672-680,694-704`; `Assets/CogLab/Shared/Timing/PresentationClock.cs:134-138`):

```
frame = PresentationClock.Capture()                     // once per Unity frame
origin = frame.presentationTime of the first Preview frame drawn in this trial (reset per trial, PMD:347,675)
t      = max(0, frame.presentationTime − origin)         // predicted presentation time, VSYNC lattice
I_L    = 0.5 + 0.5*sin(2π f_L t)   I_R = 0.5 + 0.5*sin(2π f_R t)      (mean 0.5, depth 1, phase 0°)
even bars = lerp(mid, high, I), odd bars = lerp(mid, low, I)          (I=0 → uniform grey; I=1 → full high/low contrast)
```

- `f_L = trialLeftFrequencyHz`, `f_R = trialRightFrequencyHz`: (gratingLeftFreqHz, gratingRightFreqHz) or swapped for the
  trial when `FrequenciesSwapped=1` (`PMD:332-334`). Constant across Preview and all three phases of a trial.
- One continuous phase origin per trial across Preview and motion; intensity is 0.5 at the first preview frame.
- Contrast-envelope modulation, not phase-reversal; the grating does not move relative to the paddle.
- No flicker during Feedback, Instructions, Summary.

## 7. Neurofeedback

Sources: `connectionMode` selects **BciCore** (in-process `BciServer`, ESP32 board, `BciCoreNfReader`) or **UsbBiosemi**
(`UsbBiosemiLink`, TCP `127.0.0.1:usbBiosemiPort` via adb reverse to a MATLAB "P-system" bridge). The shared
`NfSourceType` File/Tcp sources are **not** supported by this game.

Effective default: **BciCore** (scene override, `CogLab.unity:840-843`); code initializer and prefab say UsbBiosemi.

Reading (every Trial frame, `PMD:376-384`): `TryReadPair(out first, out second)` returns true once per new NF record
(BciCore: `Assets/CogLab/Shared/Bci/BciCoreNfReader.cs:79-90`; USB: `UsbBiosemiLink.cs:156-165`). NF is not read in Preview or
Feedback; the first Trial frame therefore consumes the latest record produced during Preview (if any).

| NF index (0-based / 1-based) | BciCore NF frame | BciCore CCA frame | USB record | Meaning assumed by game |
|---|---|---|---|---|
| 0 / 1 | `Smi14gt18Shaped` | `FbAgtB` | double @ byte 0 | Stimulus-1 (`gratingLeftFreqHz`, default 15 Hz, the "low" tag) |
| 1 / 2 | `Smi18gt14Shaped` | `FbBgtA` | double @ byte 8 | Stimulus-2 (`gratingRightFreqHz`, default 17 Hz, "high") |

Mapping to physical sides (`SsvepFrequencyAssignment.MapPair`, `SsvepFrequencyAssignment.cs:31-32`):
not swapped → `NFLeft = first`, `NFRight = second`; swapped → `NFLeft = second`, `NFRight = first`. Logged as
`NFIndexLeftUsed = swapped?2:1`, `NFIndexRightUsed = swapped?1:2`.

Control law (`PMD:393-427`):

```
signed = NFRight − NFLeft;  if |signed| < paddleNfDeadzone (0.02) → signed = 0
VelocityUpdate (default):
  v = clamp(paddleNfGainPxPerSec*signed, ±paddleMaxSpeedPxPerSec)      // 600*signed, cap 600 (1920-reference px/s)
  if allowKeyboardPaddle: LeftArrow held → v = −keyboardPaddleSpeedPxPerSec; RightArrow held → v = +… (Right wins; not capped)
  x ← clamp(x + v*dt*sx, minCentre, maxCentre)                          // dt = Time.unscaledDeltaTime
PositionUpdate:
  on a fresh pair: glideFrom = x; target = clamp(W/2 + positionGainPx*sx*signed, minCentre, maxCentre); glideStart = now
  x = lerp(glideFrom, target, clamp01((now − glideStart)/0.1))
  v (logged only) = (x − x_prev)/dt/sx                                  // keyboard ignored
```

- Sample-and-hold: between fresh records `NFLeft/NFRight` keep their last values, so in VelocityUpdate the paddle keeps
  moving at the last commanded velocity. A read that returns NaN/Inf (BciCore) or is skipped (USB drops non-finite records)
  leaves the previous values.
- NF values are not clipped by the game. `signed` ∈ [−2, 2] for tanh-shaped inputs; velocity saturates at |signed| ≥ 1.
- PositionUpdate at default gain: edge (phase 1/3 success) needs |signed| ≳ 0.82; centre (phase 2) needs |signed| ≤ 0.125.
- NF values reset to 0 at each Preview start (`PMD:340`).
- Stall handling: USB only — no fresh pair for `usbNfStallAbortSec` (5 s; 0 disables) during Trial → `trialstop` + Fatal
  (`PMD:385-391`). `lastNfAt` is reset at motion onset. BciCore has **no stall detection**; a stalled board leaves the paddle
  running on the last value until timeout.

## 8. Responses & scoring

- Inputs: NF pair (sections 7), optional keyboard arrows (VelocityUpdate only, `allowKeyboardPaddle`), touch/mouse only
  for buttons, Escape key (end session).
- No discrete response. The "response" is the paddle's leading edge reaching an edge line, or its centre reaching the
  centre window.
- Accuracy: `Success` per trial; session success rate = `successCount / trialsPerSession` (summary screen).
- RT-like measures: the trial CSV only stores `TrialStart` (motion onset) and `TrialEnd`; `TrialDuration = TrialEnd − TrialStart`
  is the completion time for successes (clock: `Time.realtimeSinceStartupAsDouble − experimentT0`, Update-time, frame-quantised).
  Phase-1 completion time and centre-return time are **not** in the trial CSV; derive them from EEG markers 39/40 or
  from the trace `TargetEdgeX` transitions (0.1 s resolution).
- Keyboard use is not logged explicitly (see 13.6).

## 9. Event markers / triggers

| Code (default) | Name (`Send` name) | Field | Exact moment emitted | Condition |
|---|---|---|---|---|
| 0 | `reset` | `resetTrigger` | BciCore: in `Start()` right after `StartServer`, before calibration (`PMD:237`). USB: sent by `UsbBiosemiLink` on every (re)connection; `Send("reset")` is a no-op (`UsbBiosemiLink.cs:64,136`) | once per session |
| 20 | `trialstart_left` | `trialStartLeftTrigger` | `BeginTrialMotion`, first Update with Preview elapsed ≥ `preSpawnDelaySec`; same `now` as `TrialStart` (`PMD:352-363`) | shuffle Off, initial cue left |
| 21 | `trialstart_right` | `trialStartRightTrigger` | same | shuffle Off, initial cue right |
| 31 / 32 / 33 / 34 | `trialstart_left` / `_right` | computed `31 + cueIndex + 2*swapped` (`SsvepFrequencyAssignment.cs:28`) | same | shuffle On: 31 L-cue unswapped, 32 R-cue unswapped, 33 L-cue swapped, 34 R-cue swapped |
| 39 | `phase1_reached` | `phase1ReachedTrigger` | Trial frame on which internal phase 0 detects the cued edge (`PMD:447-451`) | phase-1 success |
| 40 | `center_reached` | `trialCenterReachedTrigger` | Trial frame on which the centre window is reached (`PMD:458-462`) | |
| 41 / 42 | `phase3_left` / `phase3_right` | `phase3LeftTrigger` / `phase3RightTrigger` | **immediately after 40, same frame, same call** (`PMD:463`) | phase-3 side −1 / +1 |
| 30 | `trialstop` | `trialStopTrigger` | `FinishTrial` (success/wrong/timeout, same `now` as `TrialEnd`); Escape/Exit during Trial; USB stall; `OnDestroy` during Trial | end of every started trial except USB-link-failure Fatal |

The start marker encodes only the **initial** cue and the tag assignment; the phase-3 cue is encoded by 41/42.
There is no marker for Preview onset (flicker onset), Feedback onset, or session end.

Transport per mode:

| Mode | Path | Payload |
|---|---|---|
| BciCore | `BciCoreTriggerSender.Send` (`Assets/CogLab/Shared/Bci/BciCoreTriggerSender.cs:25-37`): (1) `BciServer.LogTriggerSent` → health.csv row `event=trigger_sent:<name>`, `marker=<code>`; (2) `BciServer.SendMarker(code)` TCP CMD frame to the ESP32 (latched into the EEG `marker` column); (3) UDP to `udpTriggerHost:udpTriggerPort` (default `10.36.17.144:5007`) | UDP: ASCII decimal, no newline |
| UsbBiosemi | `UsbBiosemiLink.Send` → `"<code>\n"` on the TCP socket to the MATLAB bridge (`UsbBiosemiLink.cs:132-143`); also sends `"R <sampleCount>\n"` acks per NF record | no UDP, no app-side EEG log |

Validation (`ValidateSettings`, `PMD:173-202` + `SsvepFrequencyAssignment.ValidatePaddle`, `SsvepFrequencyAssignment.cs:36-51`), applied in both shuffle modes:

- `trialsPerSession` ≥ 2 and even; `maxConsecutiveDirectionTrials` ∈ {1,2}; left ≠ right start code.
- Both legacy start codes must be EEG-board start codes (20–24 or 31–34), even when shuffling makes them unused.
- Stop code must be 30 or 60.
- reset, 39, 40, 41, 42 must be 0–255, distinct from each other and from the stop code, and must not be 20–24, 31–34, 30 or 60.
- Frequencies positive and finite; with shuffle On, `gratingLeftFreqHz < gratingRightFreqHz`.

## 10. Output files

Data root: `dataFolderName` if rooted, else `Application.persistentDataPath/<dataFolderName>` (default `…/data`;
Android: `/storage/emulated/0/Android/data/org.iisc.coglab.games/files/data`) (`PMD:218`).
`P` = participant, `S` = session/"Block number", both trimmed launcher strings (fallback `000`), **not sanitised** in task CSV names.

| File | Path pattern | Written |
|---|---|---|
| Trial data | `<root>/p<P>_b<S>_paddle_multidir_trialdata.csv` | header at Start (if new); rows buffered in memory, appended once at session end (`Flush`) |
| NF trace | `<root>/p<P>_b<S>_paddle_multidir_trace.csv` | same |
| Dropped frames | `<root>/p<P>_b<S>_paddle_multidir_droppedframes.csv` | same |
| Stimulus frames (opt.) | `<root>/p<P>_b<S>_paddle_multidir_stimframes_<UTC yyyyMMdd_HHmmssfff>[_r<n>].csv` + `.metadata.json` | created at Start if `logStimulusIntensityEveryFrame`; batches written in background after each trial (`FlushIti`) and completed during Exporting |
| EEG (BciCore, logging ≠ Disabled) | `persistentDataPath/BciCoreLogs/eeg_paddle-multidir_p<P>_s<S>_<local yyyyMMdd_HHmmss>/` with `<stem>_raw.csv`, `_signals.csv`, `_features.csv`, `_health.csv`, `_config.txt` (`.bin` first, converted at export, in BinaryThenCsv) | from board HELLO/connection; see shared doc |

Header-mismatch / versioning (`Ensure`, `PMD:774-785`): if the target file exists and its first line equals the current
header, rows are **appended** to it (re-running the same P/S appends a new session into the same files). Otherwise the
logger tries `<stem>_schema2_r1.csv`, `_schema2_r2.csv`, … and uses the first that is absent (created) or has a matching
header. The `schema2` label is fixed text, not a version number.

Number formats: floats `F6` invariant (6 decimals); booleans `0/1`; sides `-1/1`. No NaN/empty values in task CSVs
(NF defaults to 0 before the first read). Line ending `Environment.NewLine` for headers, `\n` (AppendLine) for rows on Android.

### 10.1 `_trialdata.csv` (one row per finished trial; aborted trials absent) — `PMD:757,790-797`

| Column | Meaning | Units / time base |
|---|---|---|
| TrialNumber | 1-based trial index in the session | — |
| TrialStart | motion onset = start-marker emission time | s, `realtimeSinceStartupAsDouble − experimentT0` (T0 = controller Start, before calibration) |
| TrialEnd | `FinishTrial` time = `trialstop` emission time | same |
| TrialDuration | TrialEnd − TrialStart | s |
| TargetDistancePx | `W/2 − edgeInsetPx*sx` (distance from screen centre to an edge line). Constant; not the paddle's required travel (that is `W/2 − w/2 − leftEdge`) | **screen px** |
| TargetSide | active target side **at trial end**: phase-3 side if phase 3 was reached, else initial side | −1 left, +1 right |
| Success | 1 = phase-3 edge reached | 0/1 |
| Timeout | 1 = ended by `maxTrialDurationSec` | 0/1 |
| DroppedFrameCount | Σ estimated skipped frames during this trial's motion (see 10.3) | frames |
| FrequencyLeftHz / FrequencyRightHz | actual flicker frequency of left / right grating this trial | Hz |
| FrequenciesSwapped | 1 = left/right tags swapped | 0/1 |
| TrialStartMarker | code actually sent at motion onset | 20/21 or 31–34 |
| NFIndexLeftUsed / NFIndexRightUsed | 1-based NF channel that drove the left / right side | 1 or 2 |
| InitialTargetSide | phase-1 cue | −1/+1 |
| Phase3TargetSide | **planned** phase-3 cue (logged even when phase 3 was not reached) | −1/+1 |
| Phase3Reached | 1 if internal phase was 2 at trial end | 0/1 |

Outcome decoding: `Success=1` → full success. `Success=0, Timeout=0` → wrong edge (phase 1 if `Phase3Reached=0`, phase 3
if 1). `Timeout=1, Phase3Reached=0` → timed out in phase 1 **or** phase 2 (disambiguate with marker 39 or trace `TargetEdgeX`).

### 10.2 `_trace.csv` — `PMD:436-443,758,799-804`

One row on the first Trial frame and then on the first frame with `now − lastTraceAt ≥ traceLogIntervalSec` (`lastTraceAt = now`,
so the effective interval is rounded up to whole frames, ~0.108 s at 120 Hz and 0.1 s setting). Only during Trial state.
Logged before phase checks, so a row on a transition frame shows the pre-transition target.

| Column | Meaning | Units / time base |
|---|---|---|
| TrialNumber | 1-based | — |
| FrameNumber | `Time.frameCount` (joins stimframes `UnityFrame`) | frames |
| SampleTime | `now − experimentT0` | s, realtime clock |
| NFLeft / NFRight | current (held) NF values mapped to physical left/right | NF units |
| NFSigned | deadzoned `NFRight − NFLeft` | NF units |
| NFReadOk | 1 if a fresh pair was consumed **on this frame** (not "since last row") | 0/1 |
| PaddleCenterX | paddle centre after this frame's update | **screen px** (not 1920-normalised) |
| PaddleVxPxPerSec | Velocity mode: commanded velocity (NF or keyboard). Position mode: actual displacement/dt | **1920-reference px/s** |
| TargetEdgeX | internal phase 0/2: x of the active cued edge threshold (leftEdge/rightEdge); phase 1: `W/2` | screen px |

### 10.3 `_droppedframes.csv` — `PMD:367-374,759,806-809`

A row for each Trial frame with `unscaledDeltaTime > 1.5/targetFrameRate`; the per-trial counter adds
`max(1, round(dt/nominal) − 1)`.

| Column | Meaning | Units |
|---|---|---|
| TrialNumber | 1-based | — |
| FrameNumber | `Time.frameCount` | — |
| VBLTime | `now − experimentT0` at Update (CPU time, **not** a VBL timestamp) | s |
| MissedBySec | `dt − 1/targetFrameRate` | s |

### 10.4 Stimulus frames CSV + metadata (optional)

Schema 3, shared format (`Assets/CogLab/Shared/Timing/FrameStimulusCsvLogger.cs:15`); full column semantics in the shared doc.
Game-specific use (`PMD:681-687`):

- One row per rendered (Repaint) frame in **Preview and Trial** states only. `Game = paddle_multidir`.
- `TrialNumber` 1-based; `Stage` ∈ `preview`, `phase1`, `phase2` (centre), `phase3` (stage = state after this frame's Update).
- `StimulusC1Intensity` = left grating envelope `I_L`, `StimulusC2Intensity` = right `I_R` (0–1); `FrequencyC1Hz/C2Hz` =
  `FrequencyLeftHz/RightHz` of the trial.
- `PhaseOriginMonotonicSec` = predicted presentation time of the trial's first preview frame; `PhaseTimeSec` = predicted
  presentation − origin. `MeanLuminance=0.5`, `ModulationDepth=1`, `PhaseC1/C2Degrees=0`.
- All `*MonotonicSec` columns use `MonotonicClock` (Stopwatch), a different clock/origin from the task CSVs; `TimestampUnixMs`
  maps `SampleMonotonicSec` through one UTC anchor. `ActualPresentationMonotonicSec` is always NaN; `CpuFrameEndMonotonicSec`
  NaN if the end-of-frame callback did not fill it.

### 10.5 EEG logs (BciCore)

Recorded by `BciServer` (`Packages/org.iisc.bcicore.server/Runtime/Logging/DirectCsvSessionLogger.cs`, `CsvSessionLogger.cs`).
Game name in the folder is the **game ID** `paddle-multidir` (set by the launcher, `Assets/CogLab/App/CogLabAppController.cs:701`).
This game: every `Send` adds a `trigger_sent:<name>` row to `_health.csv` (`wall_sec` = integer local seconds of day,
`seq=0`); the board's latched marker appears in the `marker` column of `_raw.csv`/`_signals.csv` (per EEG sample `seq`) and as
`marker` events in health; `_features.csv` rows carry the NF values (`v3/v4` = shaped NF for NF frames; `v1/v2` = `FbAgtB/FbBgtA`
for CCA frames) keyed by `seq`. `SeparateMarkerEchoesInHealthLog` is not set by this game. In USB mode the app writes no EEG files.

## 11. Settings reference

UI label = launcher's nicified field name. "Common" = bound to the launcher Common tab (hidden from the Paddlev2 tab;
a saved Common value overrides this game's field on every launch; `Assets/CogLab/App/SharedSettingsCatalog.cs:32-48`).
"Adv." = shown only with **Advanced** (groups Colors, Trigger Codes, Text). All prefab values equal the code initializers
except where noted.

| UI label | Field | Effective default | Unit | Meaning |
|---|---|---|---|---|
| Trials Per Session | trialsPerSession | 24 | trials | must be even ≥ 2 |
| Max Consecutive Direction Trials | maxConsecutiveDirectionTrials | 2 | trials | run limit 1–2 for phase-1 and phase-3 schedules |
| Common "Use fixed random seed" | useFixedRandomSeed | false | — | |
| Common "Fixed random seed" | fixedRandomSeed | 918273 | — | |
| Pre Spawn Delay Sec | preSpawnDelaySec | 2 | s | Preview duration |
| Max Trial Duration Sec | maxTrialDurationSec | 30 | s | whole-trial timeout from motion onset |
| Feedback Duration Sec | feedbackDurationSec | 2 | s | |
| Common "NF trace interval (seconds)" | traceLogIntervalSec | 0.1 | s | trace row interval |
| Field Margin Px | fieldMarginPx | 0 | px@1920×1080 | |
| Paddle Width Px | paddleWidthPx | 900 | px@1920 | |
| Paddle Height Px | paddleHeightPx | 200 | px@1080 | |
| Paddle Bottom Margin Px | paddleBottomMarginPx | 50 | px@1080 | |
| Paddle Border Px | paddleBorderPx | 3 | px@1920 | |
| Paddle Grating Width Px | paddleGratingWidthPx | 300 | px@1920 | each end; also sets blank middle and centre tolerance |
| Grating Bar Width Px | gratingBarWidthPx | 14 | px@1920 | |
| Edge Inset Px | edgeInsetPx | 20 | px@1920 | edge-line threshold inset |
| Edge Line Thickness Px | edgeLineThicknessPx | 4 | px@1920 | visual only |
| Hud Height Px | hudHeightPx | 80 | px@1080 | top of playfield/edge lines |
| Connection Mode | connectionMode | **BciCore** (scene override; code + prefab = UsbBiosemi(1)) | enum | NF/trigger transport |
| Common "USB Biosemi port" | usbBiosemiPort | 5010 | TCP port | |
| Common "Connection timeout (seconds)" | usbConnectionTimeoutSec | 10 | s | USB link wait (min 1 enforced) |
| Common "USB NF stall timeout" | usbNfStallAbortSec | 5 | s | 0 disables |
| Paddle Nf Gain Px Per Sec | paddleNfGainPxPerSec | 600 | px@1920/s per NF unit | Velocity mode |
| Paddle Max Speed Px Per Sec | paddleMaxSpeedPxPerSec | 600 | px@1920/s | Velocity cap |
| Paddle Nf Deadzone | paddleNfDeadzone | 0.02 | NF units | both modes |
| Motion Mode | motionMode | VelocityUpdate (0) | enum | 1 = PositionUpdate |
| Position Gain Px | positionGainPx | 600 | px@1920 per NF unit | Position mode offset |
| Common "Enable keyboard controls" | allowKeyboardPaddle | true | — | Velocity mode only |
| Keyboard Paddle Speed Px Per Sec | keyboardPaddleSpeedPxPerSec | 600 | px@1920/s | |
| Common "Data folder" | dataFolderName | `data` | path | |
| Common "Stimulus 1 / left / shuffle low frequency (Hz)" | gratingLeftFreqHz | 15 | Hz | |
| Common "Stimulus 2 / right / shuffle high frequency (Hz)" | gratingRightFreqHz | 17 | Hz | |
| (hidden) | ssvepFrequencyVersion | 1 | — | migration marker |
| Randomize Ssvep Frequencies | randomizeSsvepFrequencies | false | — | tag shuffle + 31–34 starts |
| Common "Display / target refresh rate (Hz)" | targetFrameRate | 120 | Hz | also nominal for dropped-frame test (Common range 30–1000) |
| Common "VSync count (desktop)" | verticalSyncCount | 1 | — | forced to 0 on Android by `DisplayRateManager` |
| Common "Log stimulus intensity every frame" | logStimulusIntensityEveryFrame | false | — | stimframes CSV |
| Reset Trigger (Adv.) | resetTrigger | 0 | code | |
| Trial Start Left Trigger (Adv.) | trialStartLeftTrigger | 20 | code | `FormerlySerializedAs("trialStartTrigger")` |
| Trial Start Right Trigger (Adv.) | trialStartRightTrigger | 21 | code | |
| Trial Stop Trigger (Adv.) | trialStopTrigger | 30 | code | 30 or 60 |
| Common "UDP trigger port" | udpTriggerPort | 5007 | UDP port | BciCore mode only |
| Phase1 Reached Trigger (Adv.) | phase1ReachedTrigger | 39 | code | |
| Trial Center Reached Trigger (Adv.) | trialCenterReachedTrigger | 40 | code | |
| Phase3 Left Trigger (Adv.) | phase3LeftTrigger | 41 | code | |
| Phase3 Right Trigger (Adv.) | phase3RightTrigger | 42 | code | |
| Udp Trigger Host (Adv.) | udpTriggerHost | `10.36.17.144` | host | BciCore mode only |
| Colors (Adv.) | backgroundColor … failureColor | see section 6 | sRGB | |
| Instructions Text (Adv.) | instructionsText | Paddle text (see 14) | — | |
| Begin Button Label (Adv.) | beginButtonLabel | `Begin session` | — | |

Also passed by the launcher (not fields of this tab): participant, session ("Block number"), EEG logging mode
(`BinaryThenCsv` / `DirectCsv` default / `Disabled`; BciCore only) (`PMD:163-171`).

## 12. Timing & clock semantics

| Time value | Clock | Origin | Captured where | Precision / limits |
|---|---|---|---|---|
| TrialStart, TrialEnd, trace SampleTime, dropped VBLTime | `Time.realtimeSinceStartupAsDouble` | `experimentT0` = controller `Start()` (before calibration/instructions) | start of the relevant `Update()` code path (`now`, `PMD:290`) | double; reflects CPU Update time, not display time; all checks frame-quantised |
| stimframes `SampleMonotonicSec`, `CpuSubmit…`, `CpuFrameEnd…`, `PredictedPresentation…`, `PhaseOrigin…` | `MonotonicClock` (Stopwatch) | arbitrary (device boot-ish) | `PresentationClock.Capture` once per frame / OnGUI / end-of-frame | predicted presentation is a VSYNC-lattice prediction; never measured |
| stimframes `TimestampUnixMs` | UTC via one anchor | Unix epoch | maps `SampleMonotonicSec` | not presentation time |
| EEG `seq`, `marker` | board sample counter | board | ESP32 | sample-accurate for latched marker, plus transport latency |
| health `wall_sec` | local wall clock | midnight | `LogTriggerSent` / health frames | 1 s resolution |

- Task CSV times and stimframes times are on **different clocks**; join them by frame number (`FrameNumber` ↔ `UnityFrame`).
- Markers are sent from `Update()` before the frame that reflects the change is rendered; the visual change (HUD to
  "TIME", arrow swap, end screen) is presented ≥ 1 frame after the marker plus display pipeline latency. Motion actually
  starts on the frame **after** the start marker (state becomes Trial; `UpdateTrial` runs next frame).
- Flicker onset (Preview) has no marker; it occurs ≈ `TrialStart − preSpawnDelaySec` (within one frame) and its exact
  predicted presentation time is `PhaseOriginMonotonicSec`.
- "Dropped frame" here = an Update interval longer than 1.5 × `1/targetFrameRate` during Trial. It is a CPU-side
  estimate; if the panel actually runs below `targetFrameRate` (e.g. 60 Hz), every frame is flagged. Stimframes
  `SkippedScheduleSlots` is a different (lattice-based) estimate and covers Preview too.
- Paddle motion in VelocityUpdate depends on `unscaledDeltaTime`, so a long frame produces a proportionally large jump.

## 13. Analysis guide

### 13.1 Join keys
- Session: `(P, S)` + file; task CSVs may contain **several sessions appended** — split where `TrialNumber` resets to 1 or
  `TrialStart` decreases.
- Trial: `TrialNumber` (trialdata ↔ trace ↔ droppedframes ↔ stimframes `TrialNumber`).
- Frame: trace/droppedframes `FrameNumber` ↔ stimframes `UnityFrame`.
- EEG: via markers only (no shared clock). EEG folder `eeg_paddle-multidir_p<P>_s<S>_<time>`.

### 13.2 Aligning EEG markers with CSV rows (BciCore)
1. In `_signals.csv`/`_raw.csv`, find marker onsets (rows where `marker` changes to a non-zero code). Start codes
   {20,21} or {31–34}; stop {30}; phase {39,40,41,42}.
2. The k-th start marker ↔ k-th trialdata row **only if** no trial was aborted; otherwise pair each start with the next 30
   and drop pairs lacking a trialdata row (the aborted trial is the last one before Escape/Exit/Fatal).
3. Check: `TrialStartMarker` equals the observed start code; `(t_30 − t_start)` from EEG sample counts ≈ `TrialDuration`
   (tolerance a few frames + transport jitter).
4. Fit a linear map `EEG_time = a + b·TrialStart` across trials (use both start and stop) to place trace samples and
   dropped-frame events on the EEG time axis.
5. Expect 40 and 41/42 back-to-back; the board may show only one of them if they latch within the same sample.
   Use `trigger_sent:center_reached` / `phase3_*` rows in `_health.csv` to confirm both were sent.
6. USB mode: markers go to the MATLAB/Biosemi side; use the Biosemi status channel the same way.

### 13.3 Epoching windows
| Epoch | Anchor | Suggested window | Notes |
|---|---|---|---|
| Preview SSVEP (no movement) | start marker − `preSpawnDelaySec` | [0, 2] s | stimulus on, paddle static, arrow visible (phase-1 cue) |
| Motion phase 1 | start marker | [0, t_39] | direction = InitialTargetSide |
| Centre return | 39 | [t_39, t_40] | arrow hidden; required direction is opposite of initial side |
| Direction change | 41/42 | [−1, +2] s | `same` vs `reversed` = Phase3TargetSide vs InitialTargetSide |
| Phase 3 | 41/42 | [t_41/42, t_30] | |
| Feedback (no stimulus) | 30 | [0, 2] s | baseline without flicker |
The SSVEP tag of the attended side in each phase: attended frequency = `FrequencyLeftHz` if the phase's target side is −1, else `FrequencyRightHz`.

### 13.4 Performance metrics
- Success rate (completed trials): `mean(Success)`; also report vs planned N (summary screen uses planned N).
- Phase-1 hit rate = fraction of trials with a 39 marker (or `Phase3Reached=1` or a trace row with `TargetEdgeX = W/2`).
- Phase-wise durations from markers: `t_39 − t_start`, `t_40 − t_39`, `t_30 − t_41/42` (success only).
- Wrong-edge rate by phase (section 10.1 decoding); timeouts by phase via markers.
- Split by same vs reversed phase 3, by `FrequenciesSwapped`, by side.

### 13.5 Using the trace
- `PaddleCenterX/W` (W from stimframes metadata `screenWidthPx`, or `TargetDistancePx + edgeInsetPx*W/1920 = W/2`) gives normalised position.
- Control signal: `NFSigned`; in Velocity mode `PaddleVxPxPerSec ≈ clip(600·NFSigned, ±600)` unless keyboard used.
- Phase from trace: `TargetEdgeX == W/2` → centre phase; otherwise compare with `W − edgeInset·sx` / `edgeInset·sx`.
- `NFReadOk` aliases with 10 Hz NF; to estimate NF freshness, count changes in `(NFLeft, NFRight)`, not `NFReadOk`.
- To relate trace NF values to EEG `_features.csv`, match `(NFLeft,NFRight)` (un-swapped via `NFIndex*Used`) to `v3/v4`
  (NF) or `v1/v2` (CCA) values (G6 vs F6 rounding).

### 13.6 Sanity checks
- Planned balance: among trialdata rows of a complete session, `InitialTargetSide` and `Phase3TargetSide` each 50/50,
  runs ≤ `maxConsecutiveDirectionTrials`, interleaved sequence runs ≤ 2; swaps balanced within initial side when shuffle On.
- `TrialStartMarker` consistent with `InitialTargetSide`, `FrequenciesSwapped` and shuffle mode; `NFIndexLeftUsed = 1 + FrequenciesSwapped`.
- `TargetSide == (Phase3Reached ? Phase3TargetSide : InitialTargetSide)`.
- `Success=1 ⇒ Phase3Reached=1, Timeout=0`; `TrialDuration ≤ maxTrialDurationSec + 1 frame`; timeouts ≈ `maxTrialDurationSec`.
- Inter-trial gap `TrialStart[i+1] − TrialEnd[i] ≈ feedbackDurationSec + preSpawnDelaySec` (+ ≤ 2 frames).
- Trace rows of a trial lie within `[TrialStart, TrialEnd]`; `PaddleCenterX` at first row = W/2 (paddle moves only from the next frame).
- Keyboard use (Velocity mode): rows where `|PaddleVxPxPerSec| = keyboardPaddleSpeedPxPerSec` while `|600·NFSigned|` differs.
- Stimframes: per trial, frequencies constant, stages ordered preview → phase1 → phase2 → phase3; `SkippedScheduleSlots` totals.
- DroppedFrameCount per trial = Σ over droppedframes rows of `max(1, round((MissedBySec + 1/fps)·fps) − 1)`.
- EEG: count of start markers = count of 30 markers; each start followed by 30 before the next start.

## 14. Known caveats / doc discrepancies

1. **Connection mode default**: code initializer and prefab are `UsbBiosemi` (`PMD:66`, prefab:66 `connectionMode: 1`), but
   the scene instance overrides it to `BciCore` (`CogLab.unity:840-843`); "Reset all" restores BciCore (defaults captured
   from the scene, `CogLabAppController.cs:118`).
2. **Instructions text** is copied from Paddle and describes only "reach the cued edge"; it does not mention the centre return or the second cue (`PMD:124`).
3. Class docstring describes the single-phase Paddle (`PMD:26-30`).
4. `TargetSide` is the final active side, not the initial cue; `Phase3TargetSide` is logged even if phase 3 never happened
   (README states this correctly).
5. `TargetDistancePx` is screen-centre-to-edge-line in screen px, not the required paddle travel, and is not in 1920-reference px.
6. Trace mixes units: `PaddleCenterX`/`TargetEdgeX` in screen px, `PaddleVxPxPerSec` in 1920-reference px/s.
7. The trial CSV cannot distinguish a phase-1 timeout from a centre-phase timeout; no phase-1/centre timestamps are logged in task CSVs.
8. Markers 40 and 41/42 are sent in the same call; on the BciCore board they may collapse into one latched sample value.
9. `reset` uses code 0, which is indistinguishable from "no marker" in EEG marker columns.
10. Task CSVs are buffered entirely in memory and written only at session end / OnDestroy; a crash loses the session's task data.
11. Same P/S re-runs append to the same task CSVs (header match), with TrialNumber restarting and a new `experimentT0`.
12. Random seed is not logged.
13. BciCore mode has no NF stall detection; USB link-failure Fatal does not send `trialstop`; USB link errors can turn
    Summary/Exporting into Fatal.
14. Calibration "Back" returns to the launcher without export (BinaryThenCsv `.bin` files are left unconverted until another conversion).
15. `hudColor` is unused; `lastVelocity`, `lastFrameAt`, `phaseT0` are written but never read.
16. If `paddleGratingWidthPx ≥ paddleWidthPx/2`, the blank width is ≤ 0 and the centre phase can never complete (not validated).
17. Dropped-frame detection uses `targetFrameRate` as nominal; on a 60 Hz panel every frame is flagged. `VBLTime` is CPU time.
18. `verticalSyncCount` has no effect on Android (forced 0, `DisplayRateManager.cs:108`).
19. In BciCore CCA mode, each CCA frame raises both `OnCcaSample` and a fallback `OnNfSample` with the same control values;
    the reader is unaffected, but `_features.csv` gets two rows per CCA frame (one `is_cca=1`, one `is_cca=0`) — verify against the shared doc.
20. `BciEvents.cs` / `BciCoreNfReader.cs` channel names (14/18 Hz, "17 Hz"/"19 Hz" for CCA) are legacy; the game assumes NF index 0 = Stimulus-1 (`gratingLeftFreqHz`) and index 1 = Stimulus-2. The board's analysis frequencies must match the configured pair; nothing in the game checks this.
21. Validation requires the unused legacy start codes to be board codes even with shuffling On.
22. README "Stimulus frame debug CSV" says the file goes to `persistentDataPath/data/...`; the code honours `dataFolderName` (rooted or relative).
23. README "Paddle v2 motion mode" says "trials, phases, triggers, timeouts and logging are the same" in both modes — true, except keyboard input is ignored and `PaddleVxPxPerSec` changes meaning in PositionUpdate (README notes the latter).
24. Stimframes `Game` tag is `paddle_multidir` (underscore) while the EEG folder uses the game ID `paddle-multidir` (hyphen).
25. Participant/session strings are not sanitised in task CSV file names (they are in EEG names).

## 15. Differences from Paddle

Diff of `Assets/Games/Paddle_MultiDir` against `Assets/Games/Paddle` (`PaddleGameController.cs`, prefab, module):

| Aspect | Paddle (`paddle`, "Paddle Game") | Paddle v2 (`paddle-multidir`, "Paddlev2") |
|---|---|---|
| Trial structure | single phase: reach cued edge = success, opposite = wrong edge | three phases: cued edge (39) → centre (40) → second cue (41/42) → edge |
| Success | first correct edge | phase-3 correct edge |
| `maxTrialDurationSec` | 10 s | 30 s (covers all phases) |
| Motion modes | velocity only | `motionMode` VelocityUpdate / PositionUpdate + `positionGainPx`; keyboard ignored in PositionUpdate |
| Extra triggers | — | 39, 40, 41, 42 (also included in `ValidatePaddle` other-events) |
| Schedules | `Build` + tag swaps | also `BuildFinalSides` (consumes `rng` after the `tagRng` draw) |
| Visuals | arrow always shown | arrow hidden in centre phase; translucent centre rectangle shown |
| Trace `TargetEdgeX` | cued edge | screen centre during centre phase; phase-3 edge afterwards |
| Stimframes | game `paddle`, stages `preview`/`trial` | game `paddle_multidir`, stages `preview`/`phase1`/`phase2`/`phase3` |
| Task CSV names | `p<P>_b<S>_breakoutval_{trialdata,trace,droppedframes}.csv` | `p<P>_b<S>_paddle_multidir_{…}.csv` |
| Trialdata columns | 15 | 18 (+ `InitialTargetSide`, `Phase3TargetSide`, `Phase3Reached`) |
| `FinishTrial` | no state guard | returns unless `state == Trial` |
| Timeout check | `else if` after edge checks | separate check after phase logic, any phase |
| Export | always via `Task.Run` | skips the background task when USB mode and no stimframes logger |
| `OnDestroy` order | trialstop before stimframes flush | stimframes flush before trialstop |
| Default connection (scene) | BciCore (override) | BciCore (override) |
| Instructions text, colours, geometry, NF law (velocity), SSVEP, trace/dropped schemas | identical | identical |

# Paddle Game (game ID `paddle`)

Verified against the code at commit `af3b034` (branch `Kalyanbrata`). Where README.md or other docs disagree, the code wins; see section 14.
Shared internals (presentation clock, stimulus-frame logger, BciCore server and loggers, USB Biosemi link, launcher settings) are described in [00-Shared-Infrastructure.md](00-Shared-Infrastructure.md). This document states exactly how Paddle uses each one.

Paddle-family siblings: **Paddle v2 / Pgv2** (`Assets/Games/Paddle_MultiDir`, `PaddleMultiDir.md`) and **Breakout** (`Assets/Games/Breakout`, `Breakout.md`). They share these conventions:
- direction coding is **-1 = left, +1 = right**
- balanced left/right schedules with at most 2 identical directions in a row (`BalancedDirectionSchedule`)
- optional SSVEP side-tag shuffling with start codes 31-34
- legacy start codes 20 (left) and 21 (right), and stop code 30
- NF channel 1 (index 0) is the low-frequency channel and NF channel 2 (index 1) is the high-frequency channel, remapped to physical sides
- trial CSV tag columns `FrequencyLeftHz, FrequencyRightHz, FrequenciesSwapped, TrialStartMarker, NFIndexLeftUsed, NFIndexRightUsed`

---

## 1. Overview & paradigm

Paddle is a 1-D, SSVEP-driven BCI cursor task. It is a Unity port of the MATLAB `gameBreakoutv7p1_val.m`, which is why its files are named `breakoutval` (`Assets/Games/Paddle/Scripts/PaddleGameController.cs:23-27`).

**What the participant sees** (landscape screen, dark background):
- A horizontal **paddle** near the bottom of the screen. It is 900 px wide by 200 px tall (1920x1080 reference) and starts horizontally centred on every trial. It has a dark-blue body and a cyan border.
- The paddle's **left 300 px** and **right 300 px** are vertical-bar **gratings**: cyan/dark-cyan on the left and yellow/dark-yellow on the right. Each grating's **contrast** is modulated sinusoidally. With default settings the left grating flickers at **15 Hz** and the right at **17 Hz**. The middle third is plain paddle body.
- Two thin light-grey vertical **edge lines**, 20 px inside the left and right screen edges.
- A large **arrow** glyph (`<` or `>`), mint-green (`readyColor`), slightly above screen centre. It is the **direction cue** and stays visible for the whole preview and motion period.
- A HUD at the top: `TRIAL i/N` on the left. On the right, `GET READY` during preview, then `TIME: x.xs` (a countdown) during motion.

**What the participant does:** attend to the flickering end of the paddle on the cued side. The BCI's pair of NF values drives the paddle's horizontal velocity: `v ∝ (NF_right - NF_left)`. Keyboard arrows can override this when enabled (on by default).

**Purpose:** online validation of SSVEP-based lateralised control (left/right attention to a 15 vs 17 Hz tag). The task produces closed-loop NF traces, trial outcomes and EEG markers for offline SSVEP/NF analysis.

**Success rule** (`PaddleGameController.cs:385-400`), evaluated every motion frame after the paddle moves:
- Cue **left** (`TargetSide = -1`): **success** when the paddle's left edge ≤ the left edge line's x. **Wrong edge** when the paddle's right edge ≥ the right edge line's x.
- Cue **right** (`TargetSide = +1`): success when the right edge ≥ the right line. Wrong edge when the left edge ≤ the left line.
- Otherwise, **timeout** when `now - trialStart ≥ maxTrialDurationSec` (10 s).
- Precedence on a single frame: success, then wrong edge, then timeout.

Only "success" counts as correct. Wrong edge and timeout are both failures (`Success = 0`). `Timeout = 1` only for the timeout case.

---

## 2. Code map

| Item | Value | Source |
|---|---|---|
| Game controller | `PaddleGame.PaddleGameController : MonoBehaviour, IGameSession`. Holds all logic: state machine, schedule, NF→velocity, rendering (IMGUI `OnGUI`), CSV logging | `Assets/Games/Paddle/Scripts/PaddleGameController.cs` (726 lines) |
| Nested logger | `PaddleGameController.PaddleCsvLogger` (private sealed). Writes the trialdata, trace and droppedframes CSVs | `PaddleGameController.cs:660-724` |
| Launcher module | `PaddleGame.PaddleGameModule : GameModule`. Only overrides `ValidateSettings` to call the template's `ValidateSettings` | `Assets/Games/Paddle/Scripts/PaddleGameModule.cs` |
| Connection enum | `PaddleGame.PaddleConnectionMode { BciCore = 0, UsbBiosemi = 1 }` | `PaddleGameController.cs:21` |
| Assembly | `CogLab.Games.Paddle` (refs `CogLab.Framework`, `CogLab.Shared`, `BciCore`, `Unity.InputSystem`; `autoReferenced: true`) | `Assets/Games/Paddle/CogLab.Games.Paddle.asmdef` |
| Prefab | `Assets/Games/Paddle/Prefabs/PaddleGame.prefab`. Root GameObject `PaddleGame` with a **disabled** `PaddleGameController` (settings template, `m_Enabled: 0`) and an enabled `PaddleGameModule` | prefab lines 36-128 |
| Game ID | `paddle` | prefab line 125 |
| Display name | `Paddle Game` | prefab line 126 |
| Launcher colour | (0, 0.58, 0.72) | prefab line 127 |
| PlayerPrefs key | `CogLab.Games.paddle.v1` (`"CogLab.Games." + gameId + ".v1"`) | `Assets/CogLab/Framework/GameModule.cs:29` |
| Shared code used | `BalancedDirectionSchedule`, `SsvepFrequencyAssignment`, `PresentationClock`, `FrameStimulusCsvLogger`, `DisplayRateManager`, `BciCalibration`/`CalibrationScreen`, `BciCoreNfReader`, `BciCoreTriggerSender` (+ UDP `TriggerSender`), `UsbBiosemiLink`, `BciServer`, `ResponsiveGui`, `MainThreadDispatcher` | `using` block, lines 1-17 |
| Tests touching Paddle | `Assets/CogLab/App/Tests/Editor/PaddleFamilySettingsTests.cs` (defaults, run-limit migration, schedule/marker/frequency consistency, logger header versioning); `Assets/CogLab/App/Tests/Editor/SettingsUiTests.cs:23`; shared `Assets/CogLab/Shared/Tests/Editor/{BalancedDirectionScheduleTests,SsvepFrequencyAssignmentTests,PresentationTimingTests}.cs` | |

Launch path: `CogLabAppController.Launch` calls `BciServer.SetSessionIdentity(participant, block, "paddle")` (`Assets/CogLab/App/CogLabAppController.cs:701`). Then `GameModule.Launch` (`GameModule.cs:78-120`) clones the template's JSON into a new runtime `PaddleGameController` and calls `ConfigureSharedLaunch(participant, session, eegLoggingMode, CompleteSession)` (`GameModule.cs:94`). `ConfigureSharedLaunch` calls `BciServer.SetSessionIdentity(participant, session)` again without the game name (`PaddleGameController.cs:149`). That is harmless, because the game name was already set to `paddle` by the launcher.

---

## 3. Session flow / state machine

States (`PaddleGameController.cs:31`): `WaitingForLaunch, Calibration, Instructions, Preview, Trial, Feedback, Summary, Exporting, Fatal`.

```
                   Start()
                     |
     +---------------+------------------------------+
     | connectionMode = UsbBiosemi (default)        | connectionMode = BciCore
     v                                              v
 WaitingForLaunch  -- link ready (>=1 NF record) -> |  BciServer.StartServer(logging per launcher)
  ("Connecting ... P-system USB Biosemi bridge")    |  send "reset"(0)
     | timeout / link error -> Fatal                |  Calibration (shared CalibrationScreen)
     v                                              |   Back -> return to launcher (no export call)
 Instructions <-------------------------------------+   Stop&Export -> EEG export, then return to launcher
     | "Begin session" button -> BeginSession()         Proceed -> ExitCalibrationMode, BciCoreNfReader
     v                                                            -> Instructions
 Preview (trial i)  --(preSpawnDelaySec elapsed, checked in Update)--> Trial   [START MARKER sent]
     ^                                                                  |
     |                                success / wrong edge / timeout    v      [STOP MARKER sent]
     +---- (feedbackDurationSec elapsed, i < N) ---------------------- Feedback
                                         (i == N) -> EndSession -> Exporting -> Summary -> "Back to games"
```

- **Start** (`:185-228`): if not configured by the launcher, the game goes to `Fatal("This game must be started from the CogLab Games launcher.")`. Otherwise it:
  1. calls `DisplayRateManager.ApplyPresentation(targetFrameRate, verticalSyncCount)`
  2. seeds the RNG
  3. sets `experimentT0 = Time.realtimeSinceStartupAsDouble` (origin of every task-CSV time column)
  4. creates `PaddleCsvLogger`, and the optional `FrameStimulusCsvLogger(..., "paddle")`
  5. opens the connection.
- **USB wait** (`:230-245`): polls each frame until `link.IsReady` (at least one valid 24-byte NF record received), `link.Error` is set, or `max(1, usbConnectionTimeoutSec)` elapses. A failure shows `Fatal("Paddle USB Biosemi link has no live NF record...")`.
- **Calibration** (BciCore only): `BciCalibration.Open(gameObject, ProceedFromCalibration, ReturnToSharedLauncher)` (`:220`). No `proceedBlockReason` is supplied, so **Proceed is never blocked**: you can enter the game with no board connected and no NF stream (see section 14). `ProceedFromCalibration` (`:247-254`) destroys the GUI, calls `BciServer.ExitCalibrationMode()` and creates `BciCoreNfReader`. Paddle does not set `OnStopAndExportPressed`, so the calibration screen's own Stop & Export runs `ConvertCurrentSessionToCsvAsync` and then `OnBackPressed` (= return to launcher) (`CalibrationScreen.cs:450-487`).
- **BeginSession** (`:288-302`): re-runs `ValidateSettings` (failure → Fatal), builds the direction schedule and the frequency-swap schedule, then starts preview of trial 1. It is called from the IMGUI button handler, so the timestamp is taken inside `OnGUI`.
- **Preview / Trial / Feedback**: see section 4.
- **End of block**: when Feedback of the last trial elapses, `EndSession()` runs (`:282-283`).
- **EndSession / ExitToMainMenu** (`:418-432`):
  1. If `state == Trial`, send `trialstop` (30). No trial row is written for that interrupted trial.
  2. `logger.Flush()`, which writes **all** buffered task-CSV rows now, synchronously.
  3. `StartExportThenReturn(skipSummary)` (`:434-475`) sets `Exporting`. A background task runs `stimulusFrameLogger.CompleteAsync()`, and in BciCore mode also `BciServer.ConvertCurrentSessionToCsvAsync()`. It then goes to `Summary` (EndSession) or straight back to the launcher (ExitToMainMenu).
- **Summary** (`:536-541`): `SUCCESS RATE = 100*successCount/trialsPerSession`. The denominator is the *planned* count, even if the block was aborted early. Then the "Back to games" button.
- **Escape key** (`:264-269`): when a keyboard exists, Escape in any state except Calibration, Summary and Fatal calls `EndSession()`, i.e. export then Summary.
- **"Exit to menu" button**: drawn top-right in every state except Calibration (`:499-504`), including Preview/Trial, Feedback, Fatal, Exporting and Summary. It calls `ExitToMainMenu()`: export, then return to the launcher without a summary.
- **OnDestroy** (`:483-492`): if `state == Trial`, sends `trialstop`. Then it flushes the stimulus-frame batch (`FlushIti`), flushes the task logger (if not already flushed) and disposes the reader and sender. In BciCore mode it also calls `BciServer.StopServer()`.

**Fatal conditions.** Fatal shows a message plus the Exit button. Escape is disabled.

| Condition | Where | Marker sent |
|---|---|---|
| Not launched from launcher | `:187-191` | none |
| Exception in `Start` (e.g. data folder not creatable, bad USB port) | `:223-227` | none |
| USB link: no NF record before timeout, or link error while waiting | `:237-242` | none |
| USB link `Error` becomes non-empty in any state except WaitingForLaunch/Fatal (disconnect, or a marker write failure) | `:258-263` | none |
| USB NF stall: no fresh NF pair for ≥ `usbNfStallAbortSec` (5 s) **during the motion phase** (`usbNfStallAbortSec > 0`) | `:361-367` | `trialstop` (30) sent before Fatal |
| `ValidateSettings` fails at Begin | `:290-294` | none |
| Schedule missing for trial index | `:306-310` | none |

BciCore mode has **no** NF-stall or disconnect abort.

---

## 4. Trial structure & timing

All task timing is **seconds-based** on `Time.realtimeSinceStartupAsDouble` sampled in `Update` (`now`, `:271`). It is not frame-counted. Each transition happens on the first `Update` whose `now` meets the condition, so every phase overruns by up to one frame (~8.3 ms at 120 Hz).

```
 trial i                       |<-- preSpawnDelaySec = 2 s -->|<----- motion: <= maxTrialDurationSec = 10 s ----->|<-- feedbackDurationSec = 2 s -->|
 screen:  [arrow cue + flickering paddle, static at centre]   [arrow + flickering paddle moving (NF/keyboard)]     [text "Trial i: SUCCESS!/WRONG EDGE/TIMEOUT!"; no paddle, no flicker]
 markers:                                                     ^ start (20/21 or 31-34)                          ^ stop (30)
 CSV:     stimframes Stage=preview                             stimframes Stage=trial; trace rows every >=0.1 s   trial row buffered; stimframes batch written (FlushIti)
 clock:   phase origin = predicted presentation of first preview frame (continuous through motion)
                                                              TrialStart = now at this Update                   TrialEnd = now at finishing Update
```

| Parameter (field) | Effective default | Role |
|---|---|---|
| `preSpawnDelaySec` | 2 s | Preview length. Cue and flicker are on, the paddle is frozen at the centre, NF is not read. `StartTrialPreview` (`:304-326`) → `BeginTrialMotion` when `now - stateStartedAt ≥ preSpawnDelaySec` (`:272-275`). |
| `maxTrialDurationSec` | 10 s | Motion timeout, measured from `trialStartedAt` (`:400`). |
| `feedbackDurationSec` | 2 s | Feedback screen, then the next preview or EndSession (`:280-285`). |
| `traceLogIntervalSec` | 0.1 s | Minimum spacing of NF trace rows (`:392-396`). |

**What ends a trial:** success, wrong edge, timeout (`:398-400`). The trial is also abandoned without a CSV row by Escape, Exit to menu, OnDestroy, or a USB stall/error.

**Inter-trial interval:** there is no separate ITI. Between the stop marker of trial *i* and the start marker of trial *i+1* there is **feedback (2 s) + preview (2 s) ≈ 4 s** plus up to 2 frames. The next trial's cue and flicker start 2 s after the stop marker.

**First-frame detail:** `BeginTrialMotion` runs in `Update` and sends the start marker. That frame's `OnGUI` already draws the `trial` stage (TIME HUD), but the paddle has not moved yet. The first `UpdateTrial` (NF read, movement, first trace row) happens on the **next** frame (`:272-279`, the if/else chain).

**Feedback:** only text, coloured `successColor` (green) when the text contains "SUCCESS", otherwise `failureColor` (red) (`:549-556`). The playfield is not drawn, so there is no flicker during feedback.

---

## 5. Trial planning / randomisation

- **Count:** `trialsPerSession` (24). It must be even and ≥ 2 (`ValidateSettings`, `:156-165`).
- **Direction schedule** (`BalancedDirectionSchedule.Build(trialsPerSession, rng, maxConsecutiveDirectionTrials)`, `:297`; `Assets/CogLab/Shared/Timing/BalancedDirectionSchedule.cs:15-30`):
  - Exactly N/2 left (-1) and N/2 right (+1).
  - No run longer than `maxConsecutiveDirectionTrials` (default 2; allowed values 1-2).
  - Built sequentially: at each position, left is chosen with probability `remainingLeft/(remainingLeft+remainingRight)` among the feasible options. Feasibility uses the closed-form bound `CanFinish`, so there is no rejection sampling.
  - This is **not** a uniform draw over all valid sequences.
  - With `max=1` the schedule is strictly alternating; its first side is random.
- **SSVEP side-tag shuffling** (`randomizeSsvepFrequencies`, default **Off**):
  - On: `SsvepFrequencyAssignment.Build(cueIndices, tagRng)` (`SsvepFrequencyAssignment.cs:9-25`). Within each cue side (0 = left, 1 = right), the trial indices are Fisher-Yates shuffled and `floor(n/2)` of them are marked swapped. An odd stratum gets +1 swap, alternating between strata from a random start. With 24 trials, 6 of 12 left and 6 of 12 right trials are swapped (12 total, as the test asserts at `PaddleFamilySettingsTests.cs:63`).
  - Off: no trials are swapped.
- **Swap semantics** (`:311-316`):
  - Unswapped: left = `gratingLeftFreqHz` (low, 15) and right = `gratingRightFreqHz` (high, 17).
  - Swapped: left = 17 and right = 15.
  - The assignment is fixed for the whole trial (preview and motion).
- **Seeding** (`:196-197`):
  - `seed = useFixedRandomSeed ? fixedRandomSeed (918273) : (Environment.TickCount*397) ^ participant.GetHashCode() ^ session.GetHashCode()`.
  - One `System.Random rng`. The direction schedule consumes it first. Then `tagRng = new System.Random(rng.Next())` (`:298`) is drawn **whether or not shuffling is on**, so toggling shuffling does not change the direction schedule (verified by `PaddleFamilySettingsTests.cs:51-56`).
  - **The seed is not written to any output file.** Non-fixed-seed sessions cannot be reproduced. Reconstruct the realised schedule from the trial CSV instead.
- **Reproducibility:** with the fixed seed, the same N, the same max-run and the same shuffle flag, the schedule and the swaps are identical (same .NET `System.Random` implementation assumed).
- **Early stop:** completed left/right and swap counts may be unbalanced.

---

## 6. Stimulus

### Geometry
Let `W, H` = `Screen.width/height` in pixels, `sx = W/1920`, `sy = H/1080` (non-uniform scaling: on a non-16:9 screen the paddle's aspect ratio changes). `GetGeometry` (`:611-624`):

| Quantity | Formula | 1920x1080 value |
|---|---|---|
| fieldLeft / fieldRight | `fieldMarginPx*sx` / `W - fieldMarginPx*sx` | 0 / 1920 |
| fieldTop / fieldBottom | `(fieldMarginPx+hudHeightPx)*sy` / `H - fieldMarginPx*sy` | 80 / 1080 |
| paddle width / height | `paddleWidthPx*sx` / `paddleHeightPx*sy` | 900 / 200 |
| paddle bottom / top | `fieldBottom - paddleBottomMarginPx*sy` / bottom - height | 1030 / 830 |
| paddle start centre x | `W*0.5` (`:317`) | 960 |
| border | `max(1, paddleBorderPx*sx)`, drawn outside the paddle rect (`:574-575`) | 3 |
| grating width (each end) | `paddleGratingWidthPx*sx` | 300 |
| bar width | `max(1, gratingBarWidthPx*sx)`; `ceil(gratingWidth/barWidth)` bars, last bar truncated (`:603-608`) | 14 (22 bars, last 6 px wide) |
| edge lines x | `leftEdge = fieldLeft + edgeInsetPx*sx`, `rightEdge = fieldRight - edgeInsetPx*sx` | 20, 1900 |
| edge line rect | `[x, x + max(1, edgeLineThicknessPx*sx)]`, from fieldTop to fieldBottom (both lines extend **rightwards** from x, `:567-568`) | 4 px |
| arrow label | rect `(W/2 - 190sx, 0.38H, 380sx, 180sy)`, font `150*u`, `u = clamp(min(sx,sy),0.55,2.5)` | |
| centre clamp | `[fieldLeft + pw/2 + border, fieldRight - pw/2 - border]` (`:380-383`) | [453, 1467] |

**Required travel to the target** (from centre): `(960 - fieldMarginPx - edgeInsetPx - paddleWidthPx/2)*sx = 490*sx` px for both directions. Wrong-edge travel is the same, in the other direction.

### Motion
`paddleCenterX += v * dt * sx`, where `v` is in **reference px/s** (1920-wide) and `dt = Time.unscaledDeltaTime` (`:343, :383`). See section 7 for `v`.

At the speed cap (600 px/s) the target is reached in 490/600 ≈ 0.82 s. With a constant signed NF `d`, reaching it within 10 s requires `|d| ≥ 0.0817`. The deadzone 0.02 corresponds to 12 px/s, which would take about 41 s.

### Colours (sRGB authoring, converted for linear rendering)
Fields are authored as sRGB `Color32`. `Render(c)` returns `c.linear` when `QualitySettings.activeColorSpace == Linear` (`:649`). The project uses **Linear** (`ProjectSettings/ProjectSettings.asset: m_ActiveColorSpace: 1`), so every colour is converted to linear before drawing, and the grating interpolation happens **in linear space**.

| Field | sRGB 0-255 |
|---|---|
| backgroundColor | (10,12,20) |
| gratingMidColor | (128,128,128) |
| leftBarHigh / leftBarLow | (0,230,230) / (0,80,80) |
| rightBarHigh / rightBarLow | (255,220,0) / (100,80,0) |
| paddleBodyColor / paddleBorderColor | (30,30,60) / (0,180,220) |
| edgeLineColor | (200,200,200) |
| readyColor (arrow) | (0,255,200) |
| successColor / failureColor | (0,255,0) / (255,0,0) |
| hudColor | (220,220,255). **Unused**: the HUD text is white (`BuildStyles`, `:633-636`) |

### SSVEP flicker (contrast-envelope grating)
- Per frame (`DrawPlayfield`, `:580-586`):
  - `f = PresentationClock.Capture()` (one cached sample per Unity frame)
  - `origin` = `f.presentationTime` of the **first drawn frame of this trial's preview** (`stimulusPhaseOrigin`, reset to NaN in `StartTrialPreview`, `:323`)
  - `t = max(0, f.presentationTime - origin)`
  - `e_L = 0.5 + 0.5*sin(2π·FrequencyLeftHz·t)`, `e_R` likewise with FrequencyRightHz (`PresentationClock.Intensity`, `PresentationClock.cs:134-138`; mean 0.5, depth 1, phase 0)
- Bar colours (`DrawGrating`, `:599-609`): even bars are `lerp(mid, high, e)` and odd bars are `lerp(mid, low, e)`. At `e = 0` both bars equal mid-grey (no grating). At `e = 1` there is full high/low contrast. The flicker is therefore a **contrast** modulation around a grey mean. It is not a luminance on/off flicker.
- **Phase origin:** one continuous origin per trial covers preview and motion. At the origin frame `e = 0.5` (sine phase 0). The phase is **not** reset at motion onset (start marker), so the phase at the marker is about `2π f · 2 s` plus frame quantisation. Read it from the stimframes `PhaseTimeSec`.
- **`presentationTime`** is a predicted VSYNC-lattice time on the shared monotonic clock (Android Choreographer/FrameTimeline when available, otherwise a monotonic fallback). It is not a measured scanout time. See the shared doc.
- At 120 Hz, 15 Hz = 8 frames/cycle (exact). 17 Hz = 7.06 frames/cycle (sampled sine with a slowly drifting pattern).

### Cue
The arrow glyph is the only target cue. Both edge lines look identical, and the target edge is not highlighted. The arrow is visible from the first preview frame until the end of motion.

---

## 7. Neurofeedback

**Sources** (`connectionMode`):

| Mode | Reader | NF pair (`first`, `second`) | Freshness |
|---|---|---|---|
| `UsbBiosemi` (default, enum 1) | `UsbBiosemiLink` on TCP `127.0.0.1:usbBiosemiPort` (adb-reverse to the MATLAB "P bridge") | 24-byte little-endian records `[double first, double second, double sampleCount]`. Records with NaN/Inf in first/second are skipped (`UsbBiosemiLink.cs:67-73`). The app replies `R <sampleCount>\n` per record | Each new record increments the sequence. `TryReadPair` returns true once per new record |
| `BciCore` (enum 0) | `BciCoreNfReader` subscribed to `BciServer.OnNfSample` and `OnCcaSample` | NF frame: `first = Smi14gt18Shaped`, `second = Smi18gt14Shaped`. CCA frame: `first = FbAgtB`, `second = FbBgtA` (`BciCoreNfReader.cs:30-56`) | Once per new sample. A NaN/Inf pair consumes freshness and returns false (`:79-90`) |

File/Tcp NF sources (`NfSourceType`) are **not** supported by Paddle.

**Channel convention:** index 0 = "NF channel 1" = **low-frequency** channel, and index 1 = "NF channel 2" = **high-frequency** channel. The game does **not** send its frequencies to the board or bridge. The correspondence (index 0 ↔ 15 Hz) relies on the board firmware or MATLAB bridge being configured for the same pair. Legacy field names say 14/18 Hz (NfSample) and 17/19 Hz (CcaSample) (`Packages/org.iisc.bcicore.server/Runtime/Api/BciEvents.cs:37-40, 112-115`).

**Per-trial mapping** (`SsvepFrequencyAssignment.MapPair`, `:356`):
- Unswapped: `NFLeft = first (idx 0)` and `NFRight = second (idx 1)`, i.e. `NFIndexLeftUsed = 1` and `NFIndexRightUsed = 2`.
- Swapped: `NFLeft = second` and `NFRight = first`, i.e. 2 and 1 (`:701`).

**Update equations, once per motion frame** (`UpdateTrial`, `:341-401`):
```
if TryReadPair(fresh):  NFLeft, NFRight = mapped(fresh); lastNfAt = now      (else values are HELD from the last fresh sample)
signed = NFRight - NFLeft
if |signed| < paddleNfDeadzone (0.02): signed = 0
v = clamp(paddleNfGainPxPerSec (600) * signed, -paddleMaxSpeedPxPerSec (600), +600)   [reference px/s]
if allowKeyboardPaddle and keyboard: LeftArrow -> v = -keyboardPaddleSpeedPxPerSec (600); RightArrow -> v = +600 (Right wins if both; NOT capped by max speed)
x_center = clamp(x_center + v*dt*sx, minCenter, maxCenter)
```
- `NFLeft`, `NFRight` and `v` are reset to 0 at each preview start (`:318`). NF is **not read during preview or feedback**. The first motion-frame read returns the newest sample that arrived since the previous trial's last read.
- A positive `signed` moves right. Attending the left (unswapped low-freq) grating should raise index 0 → `NFLeft` up → leftward motion.
- Because values are held, each NF sample drives motion over all the frames until the next sample arrives (sample-and-hold velocity).
- **Stall handling:** USB only. If `now - lastNfAt ≥ usbNfStallAbortSec` during motion, the game sends stop 30 and goes Fatal. `lastNfAt` is reset to motion start every trial (`:331`). BciCore has no stall check; the paddle simply holds the last velocity or stays at 0.
- **Thresholds:** none beyond the deadzone and edge geometry. There is no dwell or hysteresis.

---

## 8. Responses & scoring

- **Inputs:** NF pair (continuous control); optional keyboard Left/Right arrows (`allowKeyboardPaddle`, default **On**); Escape (end session). There are no touch controls in the task, except the Exit/Begin/Back buttons.
- **Outcome per trial:** `Success` (1/0) and `Timeout` (1/0). Wrong edge = `Success = 0, Timeout = 0`.
- **Score:** `successCount`; the summary shows `successCount / trialsPerSession`.
- **RT:** not logged as such. The natural RT is `TrialDuration = TrialEnd - TrialStart` for success rows. Clock: `Time.realtimeSinceStartupAsDouble`, from the `Update` in which the start marker was sent to the `Update` in which the crossing was detected. Both are CPU-frame times, not presentation times, with resolution of one frame.
- **Keyboard use is not flagged in any column.** It can only be inferred from the trace (section 13).

---

## 9. Event markers / triggers

**Transport:**
- **UsbBiosemi:** `UsbBiosemiLink.Send` writes ASCII `"<code>\n"` on the same TCP socket to the MATLAB bridge. Codes must be 0-255. `Send("reset", …)` is ignored, because the link itself sends `resetTrigger` on every (re)connect (`UsbBiosemiLink.cs:64, 132-143`). A write failure sets `Error`, and the game goes Fatal on the next frame.
- **BciCore:** `BciCoreTriggerSender.Send` does three things (`BciCoreTriggerSender.cs:25-37`):
  1. writes a `health.csv` row `event = trigger_sent:<name>` with `marker = code` and `seq = 0` (software send time)
  2. sends a CMD frame to the ESP32 board, which latches the code into the `marker` column of subsequent EEG samples and echoes it (health row `event = marker`, with the sample `seq`)
  3. also sends a **UDP datagram** with the ASCII code to `udpTriggerHost:udpTriggerPort` (default `10.36.17.144:5007`).

| Name (sent string) | Code (default) | Exact moment | Condition |
|---|---|---|---|
| `reset` | `resetTrigger` = 0 | BciCore: in `Start`, right after `StartServer`, before calibration (`:218`). The board is usually not connected yet, so the TCP send fails (warning) and it is not logged; only the UDP copy goes out. USB: sent by the link worker on each TCP connect | always |
| `trialstart_left` | 20 (`trialStartLeftTrigger`) | In `Update`, in `BeginTrialMotion` (`:336-337`): the frame on which preview → motion. This is **motion onset, 2 s after cue onset**. It is *not* cue onset | shuffle Off, cue left |
| `trialstart_right` | 21 (`trialStartRightTrigger`) | same | shuffle Off, cue right |
| `trialstart_left` | 31 / 33 | same | shuffle On, cue left, unswapped (L=low) / swapped (L=high) |
| `trialstart_right` | 32 / 34 | same | shuffle On, cue right, unswapped / swapped |
| `trialstop` | 30 (`trialStopTrigger`) | `FinishTrial` in `Update` on the success/wrong/timeout frame (`:406`). Also on Escape/Exit/OnDestroy while in Trial (`:420, :428, :486`), and on a USB stall before Fatal (`:364`) | every started trial ends with exactly one stop. On Exit-to-menu it is sent from `OnGUI` |

Shuffled code formula: `31 + cueIndex + (swapped ? 2 : 0)`, with cueIndex 0 = left and 1 = right (`SsvepFrequencyAssignment.cs:28`). It equals the `TrialStartMarker` CSV column. In shuffle mode the legacy 20/21 fields are still validated but not emitted.

**Validation** (`ValidateSettings` → `SsvepFrequencyAssignment.ValidatePaddle`, `SsvepFrequencyAssignment.cs:36-51`; run at launch and at Begin):
- left ≠ right start
- both start codes in the EEG-board start set {20, 21-24, 31-34}
- stop ∈ {30, 60}
- reset in 0-255, not a start/stop code
- both frequencies finite and > 0; when shuffling, left (low) < right (high)
- USB port 1-65535
- `maxConsecutiveDirectionTrials` 1-2
- N even and ≥ 2

Calibration screen "Reboot" sends CMD `0xFFFF` (`CalibrationScreen.cs:1735, 1761`). It is not a task marker, and it occurs only before the task starts.

**Marker/row correspondence:** each completed trial = one start + one stop + one trial-CSV row. An aborted trial = start + stop + trace rows, but **no trial row**.

---

## 10. Output files

Folder for task files: `dataFolderName` (default `data`). If it is relative, it is resolved under `Application.persistentDataPath` (`:199`). On Android this is typically `/storage/emulated/0/Android/data/org.iisc.coglab.games/files/data/`. `<P>` is the participant and `<B>` the launcher "Block number" (passed as `session`). Neither is sanitised for the task CSV names.

### 10.1 Task CSVs (`PaddleCsvLogger`, `:660-724`)

| File | Path pattern |
|---|---|
| Trial data | `<data>/p<P>_b<B>_breakoutval_trialdata.csv` |
| NF trace | `<data>/p<P>_b<B>_breakoutval_trace.csv` |
| Dropped frames | `<data>/p<P>_b<B>_breakoutval_droppedframes.csv` |

**When written:**
- The headers are ensured at game `Start`.
- **All rows are buffered in memory** and appended **once**, at `Flush()`: EndSession, ExitToMainMenu, or OnDestroy (`:716-723`).
- A crash or force-kill loses the whole block's task rows.

**Append / versioning** (`Ensure`, `:679-690`):
- If the file exists and its first line equals the current header, new rows are **appended**. Re-running the same `p/b` appends to the same file, and `TrialNumber` restarts at 1 (there is no run ID).
- If the header differs, the logger tries `…_trialdata_schema2_r1.csv`, `_r2`, … and uses the first file that is either missing (created with the header) or has the matching header.
- Each of the three files is versioned independently, so one session's files may carry different suffixes.

Number formatting: invariant culture. Doubles and floats use `F6` (6 decimals), bools 0/1, ints plain. There are no NaN or empty cells.

**`_trialdata.csv`**: one row per completed trial (`AddTrial`, `:695-702`)

| Column | Meaning | Units / time base |
|---|---|---|
| TrialNumber | 1-based trial index in this block | |
| TrialStart | `trialStartedAt - experimentT0`: motion onset (`Update` in which the start marker was sent) | s since game `Start` (`Time.realtimeSinceStartupAsDouble`; includes calibration/instruction time) |
| TrialEnd | finishing `Update` time (stop-marker send) | same clock |
| TrialDuration | TrialEnd - TrialStart (excludes the 2 s preview) | s |
| TargetDistancePx | `W*0.5 - edgeInsetPx*sx`: screen centre to the target edge line. **Not** the required paddle travel (`490*sx`) and ignores `fieldMarginPx` (`:408`) | screen px |
| TargetSide | -1 left, +1 right (cue) | |
| Success | 1 = cued edge reached | |
| Timeout | 1 = max duration reached (Success=0, Timeout=0 ⇒ wrong edge) | |
| DroppedFrameCount | sum over motion frames of estimated skipped frames (section 12). Not the number of droppedframes rows | frames |
| FrequencyLeftHz / FrequencyRightHz | actual flicker frequency of the left / right grating this trial | Hz |
| FrequenciesSwapped | 1 = left shows the high frequency | |
| TrialStartMarker | code actually sent at motion onset (20/21 or 31-34) | |
| NFIndexLeftUsed / NFIndexRightUsed | 1-based NF channel used as the left / right value (1/2 or 2/1) | |

**`_trace.csv`**: during motion only, at most one row per frame, when `now - lastTraceAt ≥ traceLogIntervalSec`. `lastTraceAt = now`, so the spacing is ≥ the interval, quantised to frames and drifting upward. The first motion-update frame always logs (`:392-396`, `:704-709`).

| Column | Meaning | Units / time base |
|---|---|---|
| TrialNumber | 1-based | |
| FrameNumber | `Time.frameCount` (join key to stimframes `UnityFrame`) | frames |
| SampleTime | `now - experimentT0` at this `Update` | s, same clock as TrialStart |
| NFLeft / NFRight | mapped NF values currently held (last fresh sample, or 0 before the first one in this trial) | NF units (board-defined) |
| NFSigned | `NFRight - NFLeft` after the deadzone (0 if \|·\| < deadzone) | |
| NFReadOk | 1 if a fresh pair was read **on this frame** (not "since the previous trace row") | |
| PaddleCenterX | paddle centre after this frame's movement | **screen px** |
| PaddleVxPxPerSec | velocity applied (NF-derived or keyboard override) | **reference px/s (1920-wide)**; multiply by `sx` for screen px/s |
| TargetEdgeX | x of the cued edge line (`leftEdge` or `rightEdge`) | screen px |

**`_droppedframes.csv`**: one row per motion frame with `dt > 1.5/targetFrameRate` (`:343-350`)

| Column | Meaning | Units / time base |
|---|---|---|
| TrialNumber | 1-based | |
| FrameNumber | `Time.frameCount` | |
| VBLTime | `now - experimentT0`, i.e. the CPU `Update` time. **Not a VBL/flip timestamp** despite the name | s, same clock as TrialStart |
| MissedBySec | `dt - 1/targetFrameRate`, with `dt = Time.unscaledDeltaTime` | s |

### 10.2 Stimulus-frame CSV (optional, `logStimulusIntensityEveryFrame`, default Off)

`FrameStimulusCsvLogger(dataPath, P, B, "paddle")`:

| File | Path pattern |
|---|---|
| Stimulus frames | `<data>/p<P>_b<B>_paddle_stimframes_<UTC yyyyMMdd_HHmmssfff>.csv` (or `…_r2.csv`, … if the name exists) |
| Metadata | `<same stem>.metadata.json` (`Path.ChangeExtension(path, "metadata.json")`) |

- The metadata JSON contains: schemaVersion 3, game, utcAnchor (ISO), utcAnchorUnixMs, monotonicAnchorSec, androidNanoTimeToMonotonicOffsetSec, unityVersion, deviceModel, graphicsDevice, screenWidthPx/HeightPx, targetFrameRate, developmentBuild, plus prose fields explaining the clocks.
- The header is written at game Start, never appended to an old file.
- Rows are recorded once per frame on the IMGUI Repaint event while the playfield is drawn (Preview and Trial only, `:587-592`). Batches are written asynchronously at each `FinishTrial` (`FlushIti`, `:415`) and at export (`CompleteAsync`).
- An aborted trial's samples are written at export, or at OnDestroy (`FlushIti`, asynchronous, no wait).

Paddle-specific column semantics (full definitions in the shared doc):

| Column | Paddle meaning |
|---|---|
| TimestampUnixMs | `utcAnchorMs + (SampleMonotonicSec - monotonicAnchor)*1000`. Maps the CPU sample time to Unix epoch ms; it is not presentation time |
| StimulusC1Intensity / StimulusC2Intensity | **left / right** grating contrast envelope `e_L`, `e_R` (0-1) |
| SchemaVersion | 3 |
| Game | `paddle` |
| TrialNumber | `trialIndex+1` |
| Stage | `preview` (cue on, paddle static) or `trial` (motion) |
| UnityFrame | `Time.frameCount` (joins to the trace and droppedframes `FrameNumber`) |
| ClockEpoch | presentation-clock epoch (changes on refresh-rate change) |
| SampleMonotonicSec | MonotonicClock (`Stopwatch`) at `PresentationClock.Capture()` for this frame |
| CpuSubmitMonotonicSec | MonotonicClock at `Record()` (OnGUI Repaint) |
| CpuFrameEndMonotonicSec | MonotonicClock at WaitForEndOfFrame (diagnostic; NaN if not marked) |
| PredictedPresentationMonotonicSec | VSYNC-lattice predicted presentation time |
| ActualPresentationMonotonicSec | always `NaN` (not measured) |
| PhaseOriginMonotonicSec | predicted presentation time of this trial's first preview frame |
| PhaseTimeSec | `max(0, predicted - origin)`: the `t` used in the sine |
| FrequencyC1Hz / FrequencyC2Hz | FrequencyLeftHz / FrequencyRightHz of the trial (shuffled assignment included) |
| VsyncPeriodSec, ScheduledVsyncSlot | lattice period and slot |
| ScheduledSlotStep | slot difference from the previous sample of the same trial and epoch (1 for the first sample of a trial) |
| SkippedScheduleSlots | `max(0, step-1)` |
| RepeatedScheduleSlot | 1 if step = 0 |
| ClockSource | `android_frame_timeline`, `android_choreographer`, `android_extrapolated` (callback > 0.25 s old) or `monotonic_fallback` |
| OsCallbackAgeSec, ClockCalibrationUncertaintySec, AndroidVsyncId | clock health |
| MeanLuminance, ModulationDepth | 0.5, 1 (envelope parameters, not physical luminance) |
| PhaseC1Degrees, PhaseC2Degrees | 0, 0 |

Numbers use the round-trip `R` format.

### 10.3 EEG logs (BciCore mode only; written by the in-process `BciServer`)

- Location: `Application.persistentDataPath/BciCoreLogs/eeg_paddle_p<P>_s<B>_<local yyyyMMdd_HHmmss>/`. It does **not** follow `dataFolderName`. P and B are sanitised to letters, digits, `-` and `_`; spaces become `_`.
- Created when the board connects (Hello or Connected), normally during calibration. Each board reconnect starts a **new** directory.
- Files: `<stem>_raw.csv` (`seq, raw<ch>…, marker`), `<stem>_signals.csv` (`seq, ch<ch>_uv…, marker`), `<stem>_features.csv`, `<stem>_health.csv`, `<stem>_config.txt`. BinaryThenCsv mode additionally keeps `.bin` files and `<stem>_meta.json`; its CSVs are produced at export.
- Disabled mode: no EEG files.
- USB mode: no EEG files on the tablet. EEG and markers are recorded by the external Biosemi/MATLAB system.

How Paddle data appears in them:
- `marker` column (raw/signals/features): board-latched codes 20/21/31-34/30 (and 0).
- `features.csv`:
  - NF mode (`is_cca=0`): `v3` = NF index 0 = `Smi14gt18Shaped`, `v4` = NF index 1 = `Smi18gt14Shaped` (the values Paddle consumes). `v1`, `v2` are the unshaped SMIs.
  - CCA mode (`is_cca=1`): `v1` = FbAgtB (index 0), `v2` = FbBgtA (index 1); `v3`/`v4` are the CCA scores.
  - (`DirectCsvSessionLogger.cs:207-250`)
- `health.csv`:
  - `trigger_sent:trialstart_left`, `trigger_sent:trialstart_right`, `trigger_sent:trialstop`, `trigger_sent:reset` rows (software send, `seq=0`)
  - `marker` rows (board echo, with the EEG sample `seq`)
  - `wall_sec` = integer seconds of **local time of day** (1 s resolution). In BinaryThenCsv mode the column is `wall_clock` (HH:MM:SS) and `board_dsp_max` is named `board_dspmax_us`.

The column-level definitions for these EEG files are in the shared doc.

---

## 11. Settings reference

The UI label in the game tab is `Nicify(fieldName)`, e.g. "Trials Per Session". Fields that are shared with the **Common** tab are hidden from the Paddle tab (`CogLabAppController.cs:218`) and shown with the Common label. Every prefab value equals the C# initializer; there are no differences. `connectionMode: 1` = `UsbBiosemi`. Saved PlayerPrefs (`CogLab.Games.paddle.v1`) and Common `sharedValues` override the prefab at runtime.

| UI label | Field | Effective default | Unit | Meaning | Common override |
|---|---|---|---|---|---|
| Trials Per Session | trialsPerSession | 24 | trials | even, ≥ 2 | |
| Max Consecutive Direction Trials | maxConsecutiveDirectionTrials | 2 | | 1-2; saved > 2 is migrated to 2 (`PaddleSettingsMigration.cs:7-11`) | |
| *Use fixed random seed* | useFixedRandomSeed | false | | | **yes** (`fixedSeedEnabled`) |
| *Fixed random seed* | fixedRandomSeed | 918273 | | | **yes** (`fixedSeed`) |
| Pre Spawn Delay Sec | preSpawnDelaySec | 2 | s | preview (cue + flicker, static paddle) | |
| Max Trial Duration Sec | maxTrialDurationSec | 10 | s | motion timeout | |
| Feedback Duration Sec | feedbackDurationSec | 2 | s | feedback text | |
| *NF trace interval (seconds)* | traceLogIntervalSec | 0.1 | s | min trace spacing (Common range 0.01-3600) | **yes** (`traceInterval`) |
| Field Margin Px | fieldMarginPx | 0 | ref px | outer margin | |
| Paddle Width Px | paddleWidthPx | 900 | ref px (×sx) | | |
| Paddle Height Px | paddleHeightPx | 200 | ref px (×sy) | | |
| Paddle Bottom Margin Px | paddleBottomMarginPx | 50 | ref px (×sy) | | |
| Paddle Border Px | paddleBorderPx | 3 | ref px | also shrinks the centre clamp | |
| Paddle Grating Width Px | paddleGratingWidthPx | 300 | ref px | width of each end grating | |
| Grating Bar Width Px | gratingBarWidthPx | 14 | ref px | single bar width | |
| Edge Inset Px | edgeInsetPx | 20 | ref px | edge line inset = goal line | |
| Edge Line Thickness Px | edgeLineThicknessPx | 4 | ref px | drawing only | |
| Hud Height Px | hudHeightPx | 80 | ref px (×sy) | top of field | |
| Connection Mode | connectionMode | UsbBiosemi (1) | enum | NF/marker transport | |
| *USB Biosemi port* | usbBiosemiPort | 5010 | TCP port | bridge port on 127.0.0.1 | **yes** (`usbPort`) |
| *Connection timeout (seconds)* | usbConnectionTimeoutSec | 10 | s | USB first-record wait (min 1) | **yes** (`connectTimeout`) |
| *USB NF stall timeout* | usbNfStallAbortSec | 5 | s | 0 disables | **yes** (`stallTimeout`) |
| Paddle Nf Gain Px Per Sec | paddleNfGainPxPerSec | 600 | ref px/s per NF unit | | |
| Paddle Max Speed Px Per Sec | paddleMaxSpeedPxPerSec | 600 | ref px/s | NF velocity cap | |
| Paddle Nf Deadzone | paddleNfDeadzone | 0.02 | NF units | | |
| *Enable keyboard controls* | allowKeyboardPaddle | true | | arrow-key override | **yes** (`keyboard`) |
| Keyboard Paddle Speed Px Per Sec | keyboardPaddleSpeedPxPerSec | 600 | ref px/s | not capped | |
| *Data folder* | dataFolderName | `data` | path | relative → persistentDataPath | **yes** (`dataFolder`) |
| *Stimulus 1 / left / shuffle low frequency (Hz)* | gratingLeftFreqHz | 15 | Hz | | **yes** (`frequency1`) |
| *Stimulus 2 / right / shuffle high frequency (Hz)* | gratingRightFreqHz | 17 | Hz | | **yes** (`frequency2`) |
| (hidden) | ssvepFrequencyVersion | 1 | | migration marker: a legacy 17/19 pair becomes 15/17 once | |
| Randomize Ssvep Frequencies | randomizeSsvepFrequencies | false | | side-tag shuffling | |
| *Display / target refresh rate (Hz)* | targetFrameRate | 120 | Hz | `Application.targetFrameRate`, display mode request, **and the dropped-frame nominal** (Common range 30-1000) | **yes** (`displayRate`) |
| *VSync count (desktop)* | verticalSyncCount | 1 | | ignored on Android (forced 0) | **yes** (`vsync`) |
| *Log stimulus intensity every frame* | logStimulusIntensityEveryFrame | false | | stimframes CSV | **yes** (`frameLogging`) |
| Reset Trigger | resetTrigger | 0 | code | | |
| Trial Start Left Trigger | trialStartLeftTrigger | 20 | code | legacy left start (formerly `trialStartTrigger`) | |
| Trial Start Right Trigger | trialStartRightTrigger | 21 | code | legacy right start | |
| Trial Stop Trigger | trialStopTrigger | 30 | code | 30 or 60 | |
| *UDP trigger port* | udpTriggerPort | 5007 | UDP port | BciCore UDP copy destination port | **yes** (`triggerPort`) |
| Udp Trigger Host | udpTriggerHost | `10.36.17.144` | host | BciCore UDP copy destination | |
| Background Color … Failure Color (13 fields) | backgroundColor … failureColor | see section 6 | sRGB | | |
| Instructions Text | instructionsText | "INSTRUCTIONS … Reaching the opposite edge ends the trial as a failure." | | | |
| Begin Button Label | beginButtonLabel | `Begin session` | | | |

From the launcher, not settings: participant, block (= `session`), EEG logging mode (`BinaryThenCsv` / `DirectCsv` (default) / `Disabled`; BciCore only). The Common `cueFromTrialStart` setting does not apply to Paddle (no such field).

---

## 12. Timing & clock semantics

Three unrelated clocks are involved:

| Clock | Used by | Origin |
|---|---|---|
| `Time.realtimeSinceStartupAsDouble` (Unity), offset by `experimentT0` | all task CSV times (TrialStart/End, SampleTime, VBLTime) | game `Start()`, i.e. before calibration and instructions |
| `MonotonicClock.Now` (`Stopwatch`) | stimframes `*MonotonicSec` and the presentation lattice | arbitrary (process/OS) |
| Board sample `seq` (250 Hz default) + latched `marker` | EEG CSVs | board stream |

The task CSVs carry **no Unix time** and no monotonic time. The only bridge to stimframes is `FrameNumber == UnityFrame`; the only bridge to EEG is the marker codes.

- **Event times are CPU times in `Update`.** A start marker sent at `TrialStart` affects the frame whose `OnGUI` runs immediately afterwards. That frame's predicted presentation is the stimframes row with the same `UnityFrame`, typically 1-3 VSYNC periods later. The board latches the marker at its next sample after TCP delivery.
- **Predicted vs actual presentation:** `PredictedPresentationMonotonicSec` is a lattice prediction; `ActualPresentationMonotonicSec` is always NaN. The sine phase uses the prediction, so CPU jitter does not modulate phase, but a frame that actually misses VSYNC still shows the phase computed for its scheduled slot.
- **"Dropped frame" in Paddle CSVs** = a motion frame whose `Time.unscaledDeltaTime > 1.5 × (1/targetFrameRate)`. Skipped count = `max(1, round(dt·targetFrameRate) - 1)`. It is measured against the **requested** rate, not the real panel rate: if the panel runs at 60 Hz while `targetFrameRate = 120`, **every** frame is counted as dropped. Preview frames are not checked. Stimframes `SkippedScheduleSlots` is a different, lattice-based estimate.
- **Precision:**
  - Task CSVs: 6 decimals (1 µs formatting; real resolution is frame-limited, ~8.3 ms).
  - Stimframes: full double precision.
  - health.csv `wall_sec`: 1 s.
- **Trace timing:** the sampling interval is ≥ `traceLogIntervalSec`, phase-locked to frames. NF arrival times are not logged; `NFReadOk` only marks whether a fresh sample happened on that exact frame.
- **Phase:** one origin per trial (first preview frame). Phase at the start marker ≈ `2π·f·(2 s + ≤ 1 frame)`.

---

## 13. Analysis guide

**Identify the files of one session:**
- Task: `p<P>_b<B>_breakoutval_{trialdata,trace,droppedframes}[ _schema2_rN].csv`
- Stimframes: `p<P>_b<B>_paddle_stimframes_<UTC>.csv` and its `.metadata.json`
- EEG: `BciCoreLogs/eeg_paddle_p<P>_s<B>_<local time>/`
- Re-runs with the same P/B **append** to the task CSVs. Split runs where `TrialNumber` drops back to 1 or `TrialStart` decreases.

**Aligning EEG with trial rows** (BciCore):
1. In `signals.csv` / `raw.csv`, find sample indices where `marker` changes to a start code ∈ {20, 21, 31, 32, 33, 34} and to 30. The board latches; check the shared doc for whether the marker persists for one or several samples, and use onset transitions.
2. Pair each start with the next 30. Drop pairs with no following 30.
3. Match the k-th complete pair to the k-th trial row, in order. Check: start code == `TrialStartMarker`; start→stop sample span / Fs ≈ `TrialDuration` (± ~2 frames + transport jitter); stop-to-next-start ≈ 4 s.
4. Aborted trials (Escape, Exit, stall) produce a start/stop pair with **no** trial row; it is always the last pair of a run. Trace rows exist for that trial number.
5. Cross-check with `health.csv` `trigger_sent:*` rows (software order) vs `marker` echo rows (board seq).
- USB mode: do the same on the Biosemi recording's trigger channel.

**Epoching:**
- Cue/flicker onset = start marker − `preSpawnDelaySec` (2 s). Better: use stimframes' first `Stage=preview` row per trial, mapped as below.
- Recommended windows:
  - pre-motion SSVEP (cue + flicker, paddle static): [-2, 0] s around the start marker
  - closed-loop motion: [0, TrialDuration]
  - baseline (no flicker, feedback screen): [stop + 0.2, stop + 2.0] s
- For frequency analysis, use `FrequencyLeftHz` / `FrequencyRightHz` per trial (not fixed 15/17 when shuffled). The attended frequency is `TargetSide < 0 ? FrequencyLeftHz : FrequencyRightHz`.

**Mapping task time ↔ stimframes:**
1. Join trace `FrameNumber` = stimframes `UnityFrame`.
2. Regress `SampleMonotonicSec` on `SampleTime` (slope ≈ 1, offset constant). This gives monotonic and Unix times for TrialStart/TrialEnd.
3. The start-marker frame is the first `Stage=trial` row of the trial. Its `UnityFrame` is one less than the first trace `FrameNumber` of that trial (the first trace row comes from the following frame).

**Performance metrics:**
- Accuracy = mean(Success) over completed rows, overall and by TargetSide, swap state and frequency.
- Wrong-edge rate = mean(Success==0 & Timeout==0).
- Time-to-target = TrialDuration on success rows.
- Chance-level reference: with NF ≈ 0 and no keyboard, every trial times out.
- From the trace:
  - directional accuracy = mean(sign(NFSigned) == TargetSide) over motion samples
  - mean `NFSigned·TargetSide`
  - path efficiency = net displacement toward target / total path length
- Normalise positions: `(PaddleCenterX - W/2) / (490·sx)` = fraction of required travel. `W` comes from the stimframes metadata (`screenWidthPx`); otherwise infer it from `TargetEdgeX` (rightEdge = W - 20·sx) or `TargetDistancePx = W/2 - 20·sx`, so `W = 2·TargetDistancePx/(1 - 40/1920)`.

**Using the traces:**
- Velocity check: `PaddleVxPxPerSec == clamp(600·NFSigned, ±600)`. Rows where it is exactly ±`keyboardPaddleSpeedPxPerSec` and differs from the NF prediction indicate **keyboard override**. Exclude or flag those trials.
- The NF effective sample rate ≈ count(NFReadOk==1)/count(rows) × trace rate. This underestimates when NF is faster than the trace interval.
- Values are held between samples, so do not treat consecutive equal values as independent NF samples.
- To match trace NF to `features.csv`, match on values (`v3`/`v4` or `v1`/`v2`, mapped through `NFIndexLeftUsed`); there is no shared sequence number.

**Sanity checks to run on every dataset:**
1. `#rows(trialdata)` == number of complete start/stop pairs (± 1 aborted trial at the end).
2. For a full block: TargetSide counts are equal; max run of identical TargetSide ≤ `maxConsecutiveDirectionTrials`. With shuffling, `FrequenciesSwapped` is balanced within each TargetSide.
3. `TrialStartMarker` is consistent with (TargetSide, FrequenciesSwapped): legacy 20 ↔ -1 and 21 ↔ +1; shuffled `31 + (side>0) + 2·swapped`. `NFIndexLeftUsed == 1 + swapped`.
4. `FrequencyLeftHz/RightHz` ∈ {f1, f2} and swapped iff Left > Right (given f1 < f2).
5. Timeout rows have `TrialDuration ∈ [maxTrialDurationSec, + 1 frame]`. Success/wrong rows are < max. Success rows: the last trace `PaddleCenterX ± paddleWidth/2` is near `TargetEdgeX`.
6. Successive `TrialStart` differences ≈ previous `TrialDuration + 4 s` (+ ≤ 2 frames).
7. Dropped frames: if nearly every frame is flagged, the panel is not running at `targetFrameRate`. Check stimframes `VsyncPeriodSec` and the metadata `targetFrameRate`.
8. Stimframes: `ClockSource` mostly `android_frame_timeline` or `android_choreographer`; few `SkippedScheduleSlots > 0`; `RepeatedScheduleSlot == 0`; `PhaseTimeSec` increasing within a trial; `FrequencyC1Hz == FrequencyLeftHz` per TrialNumber.
9. EEG: one `eeg_paddle_…` directory per board connection. More than one means a reconnect occurred mid-session.
10. Duplicate markers: if each code appears twice within a few ms in the EEG, the UDP copy reached the tablet's own BciCore UDP listener (section 14).

---

## 14. Known caveats / doc discrepancies

1. **File naming:** task CSVs are `p<P>_b<B>_breakoutval_*.csv`, not `paddle_*`. The stimframes and EEG logs use `paddle`. The README never states the `breakoutval` names (they are only visible in tests, `PaddleFamilySettingsTests.cs:100`).
2. **Task rows are memory-buffered until session end** (`Flush` only in EndSession, Exit, OnDestroy). A crash or kill loses all trial, trace and drop rows. Stimframes are flushed per trial.
3. **Same participant/block re-runs append** to the same task CSVs, with no run identifier. This contradicts the "never-append" policy described in README for Breakout/Arrow. Stimframes and EEG get new timestamped files.
4. **Settings and RNG seed are not logged.** There is no session/settings file (unlike Breakout and Arrow), so gain, deadzone, geometry, screen size, connection mode and seed must be recorded separately. Screen size is available only if stimframes logging was on.
5. **Start marker = motion onset, not cue onset.** The cue arrow and flicker start 2 s earlier, at preview, which has no marker. The README's table heading "Initial cue (Paddle/Pgv2)" can be misread; the README text "one trial-start marker at motion onset" is correct.
6. **Aborted trials** (Escape, Exit, stall, OnDestroy) emit start+stop markers but no trial-CSV row.
7. **Dropped-frame detection uses `targetFrameRate`, not the measured refresh.** At a 60 Hz panel with the 120 target, every frame is flagged. The `VBLTime` column is a CPU Update time, not a VBL time.
8. **Mixed units in the trace:** `PaddleCenterX`/`TargetEdgeX` are in screen px; `PaddleVxPxPerSec` is in 1920-reference px/s.
9. **`TargetDistancePx`** is centre-to-goal-line (`W/2 - 20·sx`). It is not the required travel (`490·sx`) and ignores `fieldMarginPx`.
10. **Goal-line asymmetry:** both edge lines are drawn extending rightwards from their x. The left goal requires the paddle to pass the whole visible left line; the right goal triggers on touching the right line's inner side. The difference is 4 ref px, so it is visually but not geometrically symmetric.
11. **Non-uniform scaling** (`sx ≠ sy` on non-16:9 tablets) changes the paddle aspect ratio and grating bar geometry.
12. **Calibration Proceed is never blocked** (no `proceedBlockReason`). In BciCore mode the block can run with no board or no NF. There is no NF-stall or disconnect abort; the paddle just doesn't move (all timeouts).
13. **BciCore `reset` is sent before the board connects.** The TCP send fails and it is not logged in health.csv; only the UDP copy is sent.
14. **UDP duplicate risk:** BciCore mode always also sends each marker by UDP to `udpTriggerHost:udpTriggerPort` (default `10.36.17.144:5007`). `BciServer` itself listens on UDP **5007** and forwards any received code to the ESP32 (`EspTcpListener.cs:84, 100-134`). If that host address is the tablet itself, every marker is sent to the board twice.
15. **Board NF frequencies are not configured by the game.** The NF index 0 ↔ low (15 Hz) convention depends on firmware/bridge configuration. The event field names still say 14/18 Hz (NfSample) and 17/19 Hz (CcaSample).
16. **Keyboard override is on by default and not logged.** It is not capped by `paddleMaxSpeedPxPerSec`.
17. **Summary success rate** divides by the planned `trialsPerSession`, even after early termination.
18. **`hudColor` is unused** (the HUD is white). `phaseT0`, `lastFrameAt` and `lastVelocity` are written but never used for output.
19. **README "VSync lock"** says tasks default to `verticalSyncCount = 1`. On Android, `DisplayRateManager.ApplyPresentation` forces `QualitySettings.vSyncCount = 0` (`Assets/CogLab/Shared/Display/DisplayRateManager.cs:108`), so the field only matters on desktop.
20. **Exit-to-menu on the Summary screen** runs the export a second time. It is harmless in DirectCsv mode; in BinaryThenCsv mode it re-runs the bin→CSV conversion on the last session directory.
21. **USB `Error` checked in every state**, including Exporting/Summary. A bridge disconnect after the block switches to Fatal, and the pending export completion then overwrites Fatal with Summary.
22. **Legacy key rename:** `trialStartLeftTrigger` has `[FormerlySerializedAs("trialStartTrigger")]`, but launcher PlayerPrefs are loaded via `JsonUtility`, which ignores that attribute. A very old saved `trialStartTrigger` value is not carried over (default 20 is used).
23. **README** says "Separate prefabs retain … 53 Paddle fields". The prefab now serialises 56 controller fields (later additions: max-run, right trigger, shuffle, frequency version). This is informational only.
24. **README Reach & Grasp text** describes `BciCoreLogs/eeg_<timestamp>/`. The actual directory stem is `eeg_<game>_p<P>_s<B>_<yyyyMMdd_HHmmss>` (`DirectCsvSessionLogger.cs:101-102`), in local time.
25. **health.csv time** is integer local time-of-day seconds; it cannot be used for sub-second alignment and wraps at midnight.

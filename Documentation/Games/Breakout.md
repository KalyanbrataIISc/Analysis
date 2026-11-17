# Breakout — game reference for data analysis

Verified against the code at commit `af3b034` (branch `Kalyanbrata`, merge of "Breakout disambiguated triggers 73-86", the code change is in `302340f`).
All `path:line` citations are repo-relative. Shared infrastructure (clocks, NF transports, BciCore logging, stimulus-frame logger, launcher settings) is described in [00-Shared-Infrastructure.md](00-Shared-Infrastructure.md). This file only states how Breakout uses those pieces.

Abbreviations: **ref px** = pixels in the 1920 × 1080 reference frame that all settings use. **screen px** = real device pixels. All CSV positions and speeds are in screen px. **NF** = neurofeedback. **step** = one fixed physics step of 1/120 s.

---

## 1. Overview & paradigm

Breakout is a Unity port of the MATLAB task `SpatialAttention/gameBreakoutv5_WL.m` (`Assets/Games/Breakout/Scripts/BreakoutGameController.cs:25-30`). The participant steers it through an SSVEP spatial-attention BCI.

**What the participant sees**
- A dark playfield (background sRGB 10,12,20). A HUD strip at the top shows `SCORE`, a `mm:ss` countdown of the block time limit (red when 30 s or less remain), and `LIVES: n | TRIAL k/N` (`BreakoutGameController.cs:1107-1123`). A thin horizontal line marks the top of the field.
- A wide paddle near the bottom: 900 × 200 ref px, with a 3 px cyan border. Its left 300 ref px is a flickering cyan/teal bar grating and its right 300 ref px is a flickering yellow/olive bar grating. The middle 300 ref px is an inert dark-blue strip (`BreakoutGameController.cs:1138-1147`).
- A white ball (radius 12 ref px). At most one orange brick (100 × 100 ref px) at a time, in the upper half of the screen.

**What the participant does**
- They do not use their hands. Attending to the LEFT grating should move the paddle left, and attending to the RIGHT grating should move it right. The NF difference `NF_right − NF_left` sets the paddle's velocity (default) or its position (`BreakoutGameController.cs:915-932`). Keyboard arrows can override this in velocity mode (debug/operator use).
- Goal: keep the ball from falling off the bottom, and bounce it into the brick to break it. A new brick appears only after the ball has bounced off the paddle again (`BreakoutCore.cs:43-56`).

**Trial / success rule**
- One trial = one ball = one life (`BreakoutGameController.cs:40-42`). A trial ends when the ball falls below the bottom of the screen (`EndReason = Fell`) or when no brick has been broken for `noBrickTimeoutSec` (120 s) (`EndReason = Timeout`) (`BreakoutGameController.cs:550-551`). Every trial therefore ends in a lost life. There is no trial "success" outcome. Performance is continuous: rally duration, paddle bounces, bricks broken and score.
- The block ends when all `livesAndTrials` (10) balls are used, or, checked only between trials, when the block time limit (360 s) is exceeded (`BreakoutGameController.cs:571-573`).

**BCI purpose**: continuous closed-loop lateralised SSVEP attention control. The two gratings are frequency-tagged (15 Hz left / 17 Hz right by default; optionally swapped per trial). The ball's initial launch direction is balanced left/right over the block. Event markers time-lock ball/paddle kinematics (wall/paddle/brick contacts, crossings of the midline, the paddle centre and a "critical horizon", paddle reversals) for EEG epoching.

---

## 2. Code map

| Item | Value | Source |
|---|---|---|
| Game ID | `breakout` | `Assets/Games/Breakout/Prefabs/BreakoutGame.prefab` (module `gameId`) |
| Display name | `Breakout` | prefab, `displayName` |
| Launcher colour | (0, 0.58, 0.72) | prefab, `launcherColor` |
| PlayerPrefs key | `CogLab.Games.breakout.v1` (plus `CogLab.Common.v1` for shared values) | `Assets/CogLab/Framework/GameModule.cs` (`SettingsKey`) |
| Launcher module class | `BreakoutGame.BreakoutGameModule : GameModule` | `Assets/Games/Breakout/Scripts/BreakoutGameModule.cs:4-8` |
| Controller / settings template | `BreakoutGame.BreakoutGameController : MonoBehaviour, IGameSession` (disabled component on the prefab root) | `BreakoutGameController.cs:31` |
| Assembly | `CogLab.Games.Breakout` (refs `CogLab.Framework`, `CogLab.Shared`, `BciCore`, `Unity.InputSystem`) | `Assets/Games/Breakout/CogLab.Games.Breakout.asmdef` |
| Prefab | `Assets/Games/Breakout/Prefabs/BreakoutGame.prefab` | — |

| File | Class(es) | Role |
|---|---|---|
| `Assets/Games/Breakout/Scripts/BreakoutGameController.cs` | `BreakoutGameController`, enums `BreakoutConnectionMode {BciCore, UsbBiosemi}`, `BreakoutMotionMode {VelocityUpdate, PositionUpdate}` | Settings, validation, state machine, NF reading, paddle control, fixed-step loop, trigger dispatch, CSV row assembly, IMGUI rendering, export |
| `Assets/Games/Breakout/Scripts/BreakoutCore.cs` | `SpeedUpMode`, `RectF`, `Ball`, `StepEvents`, `BrickGate`, `BreakoutPhysics`, `BreakoutSimConfig`, `BreakoutSim` | Pure C# physics: launch, motion (Magnus, renormalisation), wall/paddle/brick collisions, brick spawning, speed schedule, event detection for markers 73-83 |
| `Assets/Games/Breakout/Scripts/BreakoutCsvLogger.cs` | `BreakoutCsvLogger` | Writes the 4 task CSVs (trialdata, trace, droppedframes, session) and reserves the `_rN` suffix |
| `Assets/Games/Breakout/Scripts/BreakoutGameModule.cs` | `BreakoutGameModule` | Launcher registration; forwards `ValidateSettings` to the template |
| Tests | `Assets/CogLab/App/Tests/Editor/PaddleFamilySettingsTests.cs:18-39, 78-91` | Prefab defaults (shuffle off, max run 2, odd trial count rejected), migration of run limit > 2, launch side sign / speed invariance of `InitBall`. `SettingsUiTests.cs:25` includes the prefab in UI tests. There are no Breakout-specific trigger or logger tests. |

Shared pieces used: `DisplayRateManager.ApplyPresentation`, `PresentationClock` (flicker phase), `FrameStimulusCsvLogger` (optional), `BalancedDirectionSchedule`, `SsvepFrequencyAssignment`, `UsbBiosemiLink` or `BciServer` + `BciCoreNfReader` + `BciCoreTriggerSender`, `BciCalibration`/`CalibrationScreen`, `ResponsiveGui`, `MainThreadDispatcher`.

---

## 3. Session flow / state machine

States: `WaitingForLaunch, Calibration, Instructions, Preview, Trial, Feedback, Iti, Summary, Exporting, Fatal` (`BreakoutGameController.cs:33`).

```
Launcher "Launch" ──► GameModule.Launch: copy template settings → ConfigureSharedLaunch(participant, session, EEG mode)
                                         (BreakoutGameController.cs:248-256)
Start() (:334)
  ├─ not launched from launcher ─────────────────────────────► Fatal
  ├─ ApplyPresentation(targetFrameRate, verticalSyncCount); seed; rng; experimentT0 = Time.realtimeSinceStartupAsDouble (:344-347)
  ├─ connectionMode = UsbBiosemi (DEFAULT) ─► WaitingForLaunch ("Connecting to the P-system USB Biosemi bridge...")
  │      UsbBiosemiLink(port, resetTrigger) sends the reset code on TCP connect.
  │      Waits up to max(1, usbConnectionTimeoutSec) for the first NF record (:375-390).
  │      no record / link error ──► Fatal          ready ──► Instructions
  └─ connectionMode = BciCore ─► BciServer.StartServer(logging per launcher EEG mode, participant, block=session)
         triggers = BciCoreTriggerSender(udpTriggerHost, udpTriggerPort); Send("reset", resetTrigger)   (:359-363)
         ► Calibration (shared CalibrationScreen)
              Proceed ─► ExitCalibrationMode, nfReader = BciCoreNfReader ─► Instructions (:392-399)
              Back    ─► return to launcher
Instructions: text (+ speed-up sentence if SpeedUpMode ≠ Off) + "Begin session" button (:1065-1074)
  Begin ─► BeginSession (:443-473): ValidateSettings, geometry, create CSV logger(s), build schedules
         ─► StartTrialPreview(trial 1)
Preview  ─(preSpawnDelaySec, paddle is live, gratings flicker, "Get ready")─► BeginTrialMotion: ball spawns, START MARKER ─► Trial
Trial    ─ fall or no-brick timeout ─► EndTrial ─► Feedback ("MISS!" / "TIME OUT!", lives remaining)
Feedback ─(missDisplaySec)─► FinishFeedback: TRIAL STOP MARKER 30, trial CSV row written+flushed, time-limit check ─► Iti
Iti      ─(itiDurationSec, blank screen)─► sessionOver ? EndSession(false) : StartTrialPreview(next)
EndSession ─► Exporting (stimulus-frame CSV completion; BciCore EEG conversion/close) ─► Summary ─"Back to games"─► launcher
```

**Session end conditions** (`BreakoutGameController.cs:571-573`, `:623`): `sessionOver = livesRemaining <= 0 || sessionTimedOut || trialIndex >= livesAndTrials`. Here `sessionTimedOut = blockTimeLimitSec > 0 && now − blockStartedAt >= blockTimeLimitSec`, evaluated only at the end of each trial's feedback period. The ball in play always finishes first. The summary reason string is `SESSION ABORTED` / `TIME LIMIT REACHED` / `NO LIVES REMAINING` / `ALL TRIALS COMPLETED`. Each trial costs exactly one life, so a completed block always reports `NO LIVES REMAINING`, and `ALL TRIALS COMPLETED` is unreachable (see §14). The reason appears only on screen. It is not logged.

**Escape key** (`:409-414`): in any state except `Calibration`, `Summary` and `Fatal`, Escape calls `EndSession(aborted=true)`. This saves any trial in progress as `Aborted`, sends trial stop if one is pending, exports, and shows the Summary. It also works in `WaitingForLaunch` and `Instructions`; in those states no task CSV exists yet. Escape in `Exporting` is ignored.

**"Exit to menu" button** (`:1060-1062`, `:628-634`): drawn in every state except `Summary` and `Calibration`, including `Fatal`. It aborts and saves the current trial, exports, and returns straight to the launcher without the summary.

**Trial abort semantics** (`AbortCurrentTrial`, `:602-616`):
- In `Trial`: the row is written with `EndReason=Aborted` and `TrialEnd = abort time`, then marker 30 is sent. No life is deducted, and the trial is excluded from the summary's mean rally time.
- In `Feedback` with the row still pending: the row is written with the real reason (`Fell`/`Timeout`) but `TrialEnd = abort time`, then marker 30 is sent.
- In `Preview` or `Iti`: nothing is written. No start marker has been sent for the upcoming trial.

**Fatal conditions** (screen shows the message; data written so far is kept, and `FatalSaving` saves the trial in progress):
| Condition | Where |
|---|---|
| Not started from launcher | `:336-340` |
| Exception in `Start` (e.g. server or socket creation) | `:368-372` |
| USB: no NF record within the connection timeout, or link error before ready | `:375-387` |
| USB: link reports an error at any later time (disconnect, marker send failure) | `:403-408` (`FatalSaving`) |
| USB: no fresh NF pair for `usbNfStallAbortSec` (5 s) while in Preview or Trial (0 disables) | `:807-808` (`FatalSaving`) |
| Settings invalid at Begin, or geometry invalid at Begin or at any trial preview (e.g. screen rotated) | `:445`, `:449`, `:484` |
| Data files cannot be created | `:455-460` |

BciCore has no NF stall detection (§7).

**Export** (`StartExportThenReturn`, `:636-683`): runs on a worker task. It (1) awaits `FrameStimulusCsvLogger.CompleteAsync()` if per-frame logging is on, then (2) in BciCore mode calls `BciServer.ConvertCurrentSessionToCsvAsync` (DirectCsv: closes the CSV logger; BinaryThenCsv: converts `.bin` files). Errors are only logged to the Unity console. The summary still appears.

**Destroy** (`OnDestroy`, `:698-713`): schedules a stimulus-frame write without awaiting it, saves any trial in progress, sends a pending trial stop, flushes, disposes the reader/sender (USB sends `BYE`), and stops `BciServer` in BciCore mode.

---

## 4. Trial structure & timing

### Timeline of one trial

```
t_prev ── StartTrialPreview (:475-504) ───────────────────────────────────────────────────────────
         paddle reset to screen centre, NF pair reset to (0,0), new sim + geometry, NO marker
         flicker phase origin := predicted presentation time of the first Preview frame drawn
         screen: HUD, paddle with flickering gratings, "Get ready"; paddle already NF-controlled
   │  preSpawnDelaySec = 2 s (frame-quantised: first Update with now − t_prev >= 2)
t0 ───── BeginTrialMotion (:506-520) ─────────────────────────────────────────────────────────────
         ball spawned above current paddle centre; START MARKER (20/21 or 31-34) sent;
         TrialStart := t0 − experimentT0
   │  play: fixed 1/120 s steps; markers 72-86 as events occur; trace row every >= traceLogIntervalSec
   │  no brick until the first paddle bounce
t_end ── fall step (marker 84 in that step)  OR  frame where now − lastBrickHit > 120 s (no marker)
         EndTrial (:554-564): lives −1, state Feedback, stimulus-frame batch queued for writing
         screen: HUD + "MISS!" or "TIME OUT!" + "Lives remaining: n" (no paddle, no flicker)
   │  missDisplaySec = 1.5 s
t_stop ─ FinishFeedback (:567-576): MARKER 30 sent; trial row written (TrialEnd := t_stop − experimentT0);
         block time-limit check
   │  itiDurationSec = 1 s, blank background (only the Exit button is drawn)
t_next ─ StartTrialPreview(next) or EndSession
```

Nominal flicker-free gap between trials ≈ 1.5 s (feedback) + 1 s (ITI) = 2.5 s, plus frame quantisation. Flicker runs for ≈ 2 s before the start marker.

### Timing parameters

| Parameter | Field | Effective default | Base | Notes |
|---|---|---|---|---|
| Preview / pre-spawn | `preSpawnDelaySec` | 2 s | seconds, `Time.realtimeSinceStartupAsDouble`, checked per frame | paddle moves, gratings flicker |
| No-brick timeout | `noBrickTimeoutSec` | 120 s | seconds since trial start or since the last brick hit (`lastBrickHitAt` = frame time of the hit step, `:852`) | strict `>` |
| Feedback display | `missDisplaySec` | 1.5 s | seconds | marker 30 and TrialEnd come AFTER this |
| ITI | `itiDurationSec` | 1 s | seconds | blank screen |
| Block time limit | `blockTimeLimitSec` | 360 s | seconds from `blockStartedAt` (Begin press) | checked only at FinishFeedback; 0 disables |
| Physics step | const `PhysicsStepSec` | 1/120 s | sim time | `:35`; at most 8 steps per frame (`:36`), and the accumulator is capped at 8 steps of real time per frame (`:814`) |
| PositionUpdate glide | const `PositionUpdateIntervalSec` | 0.1 s | sim time | `:38` |
| Trace interval | `traceLogIntervalSec` | 0.1 s | seconds, frame-quantised (≈ 12 frames at 120 Hz) | Common override |
| Target frame rate | `targetFrameRate` | 120 | Hz | also the "nominal" frame duration used for dropped-frame detection |

**Frame vs seconds**: every state duration is measured in seconds of `Time.realtimeSinceStartupAsDouble` but evaluated once per `Update`, so actual durations are the configured value rounded up to the next frame (+0 to 1 frame, ≈ 8.3 ms at 120 Hz). Ball and paddle kinematics run in fixed 1/120 s steps driven by `Time.unscaledDeltaTime` through an accumulator (`:812-820`). At 120 Hz rendering that is about 1 step per frame; at 60 Hz, 2 steps. If a frame takes longer than 66.7 ms, simulated time falls behind real time (the game slows down). The speed-up `OverTime` term uses simulated time (`BreakoutSim.ElapsedSec`, `BreakoutCore.cs:307`). The brick time bonus and the no-brick timeout use real time.

**What ends a trial**: ball fall (`Ball.Y − r > FieldBottom`, `BreakoutCore.cs:371`), no-brick timeout, or abort (Esc / Exit / fatal / destroy). In a frame where both the timeout and a fall occur, the timeout wins: `EndReason=Timeout` with `BallFell=1` (`:550-551`).

---

## 5. Trial planning / randomisation

- **Launch side schedule** (`:461`): `BalancedDirectionSchedule.Build(livesAndTrials, rng, maxConsecutiveDirectionTrials)` gives an array of −1 (left) / +1 (right). The counts are exactly equal (N must be even and ≥ 2, `:260`) and no run is longer than `maxConsecutiveDirectionTrials` (1 or 2; default 2). Feasibility-bounded random construction, with no rejection (`Assets/CogLab/Shared/Timing/BalancedDirectionSchedule.cs:15-31`). "Direction" is the sign of the ball's initial horizontal velocity.
- **Frequency swap schedule** (`:462-464`): `tagRng = new Random(rng.Next())` is always drawn, so toggling shuffling does not change later draws from `rng`. If `randomizeSsvepFrequencies` (default Off) is on, `SsvepFrequencyAssignment.Build(launchIndices, tagRng)` balances swapped/unswapped within each launch side, with odd strata differing by one. Off: never swapped.
- **Per-trial assignment** (`:477-482`): `FrequencyLeftHz = swapped ? gratingRightFreqHz : gratingLeftFreqHz` and vice versa. Start marker: shuffle Off → `trialStartTrigger` (20) for left launch, `trialStartRightTrigger` (21) for right launch. Shuffle On → `31 + side + 2·swapped`, where side is 0 = left launch, 1 = right launch.
- **Launch angle** (`BreakoutCore.cs:75-88`): `u ~ U[0,1)` from `rng`; `angle = side · max(1e-6, u) · ballLaunchMaxAngleDeg` from vertical (default 30°). `Vx = v·sin(angle)`, `Vy = −v·cos(angle)` (upward). Speed does not depend on the angle.
- **Brick position** (`BreakoutCore.cs:230-247`): uniform top-left corner inside the brick region. Up to 200 attempts to keep its closest point at least `ballRadius + 40·smin` screen px from the ball centre; otherwise the last candidate is used. Two `rng` draws per attempt.
- **Seeding** (`:345`): `seed = useFixedRandomSeed ? fixedRandomSeed (918273) : unchecked(Environment.TickCount*397 ^ participant.GetHashCode() ^ session.GetHashCode())`. The seed is logged (`session.csv: RandomSeed`).
- **Reproducibility**: with a fixed seed, the launch-side and swap schedules are fully reproducible. Launch angles and brick positions come from the same `rng`, consumed in gameplay order (one draw per spawn, two per brick attempt). From trial 1's first brick onward they depend on the participant's behaviour (how many bricks spawned, rejection attempts), so they are not reproducible across sessions. To recover them, use the trace (`BallVx/BallVy` on frame 1 of each trial, `BrickCenterX/Y`).
- A block ended early (time limit or abort) can leave completed launch sides and swaps unbalanced.

---

## 6. Stimulus

### Geometry (`UpdateGeometry`, `BreakoutGameController.cs:717-736`; `BuildGeometryAndSim`, `:738-780`)

`sx = Screen.width/1920`, `sy = Screen.height/1080`, `smin = min(sx, sy)`. Screen coordinates: origin at top-left, x right, y DOWN (IMGUI and MATLAB convention).

| Quantity | Formula (screen px) | Default at 1920×1080 |
|---|---|---|
| fieldLeft / fieldRight | `fieldMarginPx·sx` / `W − fieldMarginPx·sx` | 0 / 1920 |
| fieldTop | `(fieldMarginPx + hudHeightPx)·sy` | 80 (ball reflects here) |
| fieldBottom | `H − fieldMarginPx·sy` | 1080 (fall line: ball top edge below it) |
| paddleWidth × paddleHeight | `paddleWidthPx·sx` × `paddleHeightPx·sy` | 900 × 200 |
| paddleBottom / paddleTop | `fieldBottom − paddleBottomMarginPx·sy` / `paddleBottom − paddleHeight` | 1030 / 830 |
| paddle border | `max(1, paddleBorderPx·sx)`, drawn outside the paddle rect, not collidable | 3 |
| paddle centre range | `[fieldLeft + W_p/2 + border, fieldRight − W_p/2 − border]` | [453, 1467] |
| gratings | left: `[x_p, x_p + 300·sx]`, right: `[x_p + W_p − 300·sx, x_p + W_p]`, full paddle height | 300 wide each, inert middle 300 |
| grating bars | width `max(1, gratingBarWidthPx·sx)`, `ceil(300/14) = 22` bars, last one clipped | 14 px |
| ball radius | `ballRadiusPx·smin` | 12 |
| ball spawn | x = paddle centre at spawn, y = `paddleTop − r − ballSpawnGapPx·sy` | y = 812 |
| brick | `brickWidthPx·sx` × `brickHeightPx·sy` (anisotropic if aspect ≠ 16:9), border `max(1, round(3·sx))` drawn outside, not collidable | 100 × 100 |
| brick region | x ∈ `[fieldLeft + 60·sx, fieldRight − 60·sx]`, y ∈ `[fieldTop + 80·sy, H/2 − 60·sy]` | x [60,1860], y [160,480] |
| screen midline (76/77) | `x = (fieldLeft + fieldRight)/2` | 960 |
| critical horizon (78) | `y = paddleTop − criticalHorizonOffsetPx·sy` | 580 |

Example tablet in `output/paddle-2026-11-02` (3200 × 2136): sx = 1.667, sy = 1.978. Paddle 1500 × 395.6 screen px, ball r = 20 px, base speed 333.333 px/s.

### Motion (`BreakoutCore.cs`)
Per step, in this order (`BreakoutSim.Step`, `:304-373`):
1. `ElapsedSec += 1/120`; `speed = ScheduledSpeed(...)` (below).
2. `Move` (`:93-119`): Magnus rotation `vx' = vx − k·spin·vy`, `vy' = vy + k·spin·vx` (k = `magnusGainPerFrame` 0.01). Renormalise to `speed·step`. Enforce `|vy| ≥ 0.15·speed·step` (re-solving vx). `spin *= spinDecayPerFrame` (0.1, a retention factor: spin loses 90 % per step). `x += vx`, `y += vy`.
3. Crossing detection (descending ball only, `Vy > 0` after the move): screen midline, paddle meridian (relative to paddle centre, using the paddle's previous-step position), critical horizon (`:318-333`).
4. Wall collisions (`:129-137`): left, else right, then top. Bottom is open.
5. Paddle collision (`:150-191`): only when descending, overlapping in x (ball edge vs paddle edge), and `y + r ≥ paddleTop` and `y ≤ paddleBottom`. Then `y = paddleTop − r`. `hitOffset = clamp((x − x_paddle)/(W_p/2), −1, 1)`. `vx = vx_in + hitOffset·speed'·sin(60°)`, `vy = −|vy|`, `vx += 0.35·carry`. Renormalise to `speed'` (speed for hit n+1). `spin = 0.05·carry`. `carry` = paddle displacement this step, clamped to ±`paddleMaxSpeedPxPerSec·sx/120` (`:338-339`).
6. Brick collision (`:194-227`): circle vs AABB. The reflection axis comes from the previous position (1 px tolerance), else from minimum overlap. The brick is removed immediately (one hit breaks it).
7. Brick spawn if the gate is open and no brick is present: the gate opens on a paddle hit, closes on a brick break or spawn, and resets at ball spawn. So the first brick of a trial appears in the same step as the first paddle hit (`:362-369`). No marker is sent for brick spawn.
8. Fall check.

**Speed schedule** (`BreakoutCore.cs:64-72`): `speed = min(max, base + perHit·paddleHits·[PerPaddleHit|Both] + perSec·ElapsedSec·[OverTime|Both])`, all ×sx. Defaults: `Off`, base 200 ref px/s, cap 1000. Reset at every spawn.

**Paddle motion**: see §7.

### Colours (sRGB authored; `Render()` converts with `.linear` because the project uses Linear colour space, `ProjectSettings/ProjectSettings.asset: m_ActiveColorSpace: 1`, `BreakoutGameController.cs:1227`)

| Element | sRGB (0-255) |
|---|---|
| background | 10, 12, 20 |
| grating mid (zero-contrast) | 128, 128, 128 |
| left bar high / low | 0, 230, 230 / 0, 80, 80 |
| right bar high / low | 255, 220, 0 / 100, 80, 0 |
| paddle body / border | 30, 30, 60 / 0, 180, 220 |
| field line | 200, 200, 200 |
| ball | 255, 255, 255 (anti-aliased disc texture) |
| brick / border | 255, 80, 40 / 255, 180, 60 |
| HUD text / lives | 220, 220, 255 / 255, 220, 0 |
| "Get ready" / "MISS!" | 0, 255, 200 / 255, 0, 0 |

### SSVEP flicker (`BreakoutGameController.cs:1141-1147`, `:1171-1181`; `Assets/CogLab/Shared/Timing/PresentationClock.cs`)
- Each trial: `phaseOrigin` = `presentationTime` (VSYNC-lattice prediction, `MonotonicClock` seconds) of the first frame drawn in Preview. It is reset to NaN at `StartTrialPreview` (`:501`) and is continuous through Preview and Trial.
- For each frame: `t = max(0, presentationTime − phaseOrigin)`. `I_L = 0.5 + 0.5·sin(2π·FrequencyLeftHz·t)` and `I_R = 0.5 + 0.5·sin(2π·FrequencyRightHz·t)`, both in [0,1], phase 0, depth 1.
- Grating: alternating bars `A = lerp(mid, high, I)` and `B = lerp(mid, low, I)`. At I = 0 both bars are uniform mid-grey; at I = 1 they show full high/low contrast. This is a sinusoidal contrast (and mean-colour) envelope on a spatial square-wave grating, not contrast reversal. Interpolation happens on linear-light values.
- Both gratings start in phase (sin = 0, I = 0.5) at the phase origin. Phase at the start marker ≈ `2π·f·(t_start_pres − origin)`; get it from the stimulus-frame CSV.
- No flicker in Feedback, ITI, Instructions or Summary.

### Other visuals
Feedback text ("MISS!" / "TIME OUT!", "Lives remaining: n" or "No lives remaining!"). There is no cue stimulus: the launch direction is revealed only by ball motion.

---

## 7. Neurofeedback

**Sources** (`connectionMode`, effective default **UsbBiosemi** = 1 in both prefab and code):

| Mode | Reader | NF pair (first, second) | Markers |
|---|---|---|---|
| `UsbBiosemi` | `UsbBiosemiLink` (TCP 127.0.0.1:`usbBiosemiPort` 5010 via ADB reverse) | 24-byte records: double first, double second, double sampleCount. The game replies `R <sampleCount>`. NaN/Inf records are skipped. | ASCII `"<code>\n"` on the same socket; the bridge writes the Biosemi trigger. `Send("reset")` is ignored; the reset code is sent on connect. |
| `BciCore` | `BciCoreNfReader` (in-process `BciServer`, ESP32 board on TCP 5005) | NF frame: `Smi14gt18Shaped` (first), `Smi18gt14Shaped` (second); or CCA frame: `FbAgtB`, `FbBgtA` | `BciCoreTriggerSender`: `BciServer.LogTriggerSent` (health.csv), TCP CMD marker to the ESP32, AND UDP ASCII to `udpTriggerHost:udpTriggerPort` (default 10.36.17.144:5007) |

File/TCP NF sources (`NfSourceType`) are not supported by Breakout.

**Channel mapping** (`ReadNf`, `:788-809`; `SsvepFrequencyAssignment.MapPair`): index 0 ("first", NF channel 1) is the low-frequency channel and index 1 (NF channel 2) is the high-frequency channel. `NFLeft = swapped ? second : first` and `NFRight = swapped ? first : second`. Logged as `NFIndexLeftUsed = swapped ? 2 : 1` and `NFIndexRightUsed = swapped ? 1 : 2` (1-based). The firmware field names (14/18 Hz, 17/19 Hz) are legacy labels. The game assumes the board computes its features for the configured frequencies.

**Freshness**: `TryReadPair` returns true once per new NF sample (≈ 10 Hz). Between samples the last pair is held. At every `StartTrialPreview` the pair is reset to (0,0) until the next fresh sample (`:486`). NaN/Inf from BciCore consume the sample but are not applied.

**Update equations** (`UpdatePaddleStep`, `:915-932`), once per physics step:
- `D = NFRight − NFLeft`; `D := 0 if |D| < paddleNfDeadzone (0.02)` (`:782-786`). NF values are not clipped.
- **VelocityUpdate** (default): `v_ref = clamp(paddleNfGainPxPerSec (600) · D, ±paddleMaxSpeedPxPerSec (600))` ref px/s. If `allowKeyboardPaddle` is on: holding ← sets `v_ref = −600`, holding → sets `v_ref = +600` (right wins if both are held). `x += v_ref·(1/120)·sx`, clamped to the paddle centre range.
- **PositionUpdate**: on each fresh pair, `target = clamp(W/2 + positionGainPx (600)·sx·D, range)` and `from = current x`. Each step, `x = lerp(from, target, clamp01((simClock − t_fresh)/0.1 s))`. Keyboard is ignored. The target saturates for |D| ≥ ≈ 0.845 at defaults.
- The paddle velocity passed to the ball (carry/spin) is the actual displacement per step, clamped to ±`paddleMaxSpeedPxPerSec·sx` in both modes.
- The paddle is live in Preview too, so the spawn x position depends on the NF during the 2 s preview.

**Stall handling**: USB only. If `usbNfStallAbortSec` (5 s) > 0 and no fresh pair arrives for that long during Preview or Trial, the result is `FatalSaving` (`:807-808`). BciCore has no stall check: the last pair is held indefinitely, so in VelocityUpdate the paddle keeps moving at the last commanded velocity until it reaches an edge.

---

## 8. Responses & scoring

- **Inputs**: NF (continuous), keyboard arrows (VelocityUpdate only, if enabled), Escape (abort), on-screen buttons (Begin, Exit to menu, Back to games). There are no discrete responses and no RT measure. RT is not applicable.
- **Score** (shown on screen only; not written to any CSV): +`bounceBonus` (10) per paddle hit (`:841-842`). For each brick, `round(brickBasePoints (100) + timeBonusRate (5) · (t_frame − t_trialStart))` with real-time seconds (`:853`), so later bricks score more. The total is cumulative over the block.
- **Lives**: −1 per trial (`:559`), not on abort.
- **Summary** (`:1088-1105`): total score, total bricks, lives used, "mean rally time" = mean `TrialDuration` of non-aborted trials (includes the 1.5 s feedback), per-trial bricks and points.
- **Recomputing score offline**: `10·PaddleBounces + Σ_bricks round(100 + 5·(t_brick − TrialStart))`. `t_brick` is not in the trial CSV. Take it from marker 72 times (EEG), or approximately from the trace frame where `BricksBroken` increments (≤ 0.1 s resolution).

---

## 9. Event markers / triggers

The current scheme comes from commit `302340f` ("disambiguated collision, meridian, horizon, and reversal triggers (73-86)"). All codes are configurable (Advanced → "Trigger Codes"). Defaults below are the code initialisers: the fields `leftWallBounceTrigger`…`paddleRevRtoLTrigger`, `criticalHorizonOffsetPx`, `reversalSpeedThresholdPxPerSec` and `reversalRefractorySec` are absent from the prefab YAML, so the code initialisers are effective (§14).

| Code | Send name (health.csv `trigger_sent:<name>`) | Field | Exact moment emitted | Condition |
|---|---|---|---|---|
| 0 | `reset` | `resetTrigger` | BciCore: in `Start()` right after `StartServer` (`:363`), usually before the board is connected (§14). USB: by the link on every TCP connect (`UsbBiosemiLink.Run`) | once per launch / reconnect |
| 20 | `trialstart_left` | `trialStartTrigger` | `BeginTrialMotion`, in the Update in which the ball is spawned (`:518`), before that frame is drawn | shuffle Off, launch side −1 |
| 21 | `trialstart_right` | `trialStartRightTrigger` | same | shuffle Off, launch side +1 |
| 31 / 32 / 33 / 34 | `trialstart_left` / `trialstart_right` / `trialstart_left` / `trialstart_right` | computed `31+side+2·swapped` | same | shuffle On: 31 = left launch, L low / R high; 32 = right, L low / R high; 33 = left, L high / R low; 34 = right, L high / R low |
| 30 | `trialstop` | `trialStopTrigger` | `FinishFeedback`, i.e. `missDisplaySec` (1.5 s) AFTER the fall/timeout (`:569`); or at abort / destroy | once per started trial (`trialStopPending`) |
| 73 | `wallbounce` | `leftWallBounceTrigger` | physics step in which the ball is reflected off the left wall (`BreakoutCore.cs:133`; `:830-838`) | takes precedence over top if both happen in the same step |
| 74 | `wallbounce` | `rightWallBounceTrigger` | right wall reflection | same |
| 75 | `wallbounce` | `topWallBounceTrigger` | top wall (field top under the HUD) only | |
| 70 | `wallbounce` | `wallBounceTrigger` | fallback when `HitWall` and code = 0; never reached in practice | LEGACY: before 302340f, every wall bounce |
| 81 | `paddlebounce` | `paddleHitLeftTrigger` | paddle reflection with `hitOffset < −1/3` (`BreakoutCore.cs:171-174`; `:839-849`) | at default geometry this is exactly the left grating |
| 82 | `paddlebounce` | `paddleHitCenterTrigger` | `−1/3 ≤ hitOffset ≤ 1/3` | inert middle strip |
| 83 | `paddlebounce` | `paddleHitRightTrigger` | `hitOffset > 1/3` | right grating |
| 71 | `paddlebounce` | `paddleBounceTrigger` | fallback, never reached | LEGACY: every paddle bounce before 302340f |
| 72 | `brickbounce` | `brickBounceTrigger` | step in which the ball hits (and breaks) the brick (`:850-858`) | |
| 84 | `ballfell` | `ballFellTrigger` | step in which the ball's top edge passes below the screen bottom (`:859-864`); the step loop then breaks | new in 302340f; previously no marker at the fall |
| 78 | `criticalhorizon` | `criticalHorizonTrigger` | descending ball centre crosses `y = paddleTop − 250·sy` (prev < h ≤ curr) | only on "quiet" steps (see priority) |
| 79 | `paddlemeridian_ltor` | `paddleMeridianLtoRTrigger` | descending ball crosses the paddle centre from its left to its right side (relative x changes from < 0 to ≥ 0; may be caused by paddle movement) | quiet steps |
| 80 | `paddlemeridian_rtol` | `paddleMeridianRtoLTrigger` | relative x changes from > 0 to ≤ 0 | quiet steps |
| 76 | `screenmidline_ltor` | `screenMidlineLtoRTrigger` | descending ball centre crosses the field midline left→right | quiet steps |
| 77 | `screenmidline_rtol` | `screenMidlineRtoLTrigger` | right→left | quiet steps |
| 85 | `paddlerev_ltor` | `paddleRevLtoRTrigger` | paddle velocity becomes ≥ +50 ref px/s after a committed leftward direction (≤ −50), and ≥ 0.40 s sim time since the last 85/86 | quiet steps, Trial state only |
| 86 | `paddlerev_rtol` | `paddleRevRtoLTrigger` | velocity ≤ −50 after committed rightward, refractory 0.40 s | same |

**Within-step rules** (`AdvanceSimulation`, `:827-911`):
- Collision group: wall, paddle, brick and fall are each sent if they occur, in that order. Several can occur in the same step (e.g. wall + brick), giving several sends at the same instant.
- Fall: sends 84 and stops processing further steps in the frame.
- If no collision or fall occurred in the step, at most ONE of these is sent, in priority order **78 > 79 > 80 > 76 > 77 > reversal (85/86)**. Lower-priority crossings in the same step are lost (e.g. ball crossing the midline and the paddle meridian in the same step gives only 79).
- Reversal state (`committedPaddleDir`) is updated only on quiet steps. It resets to 0 at trial start, so the first committed direction never fires. A reversal inside the refractory window updates the committed direction without a marker. Threshold and refractory use `|v|/sx` (ref px/s) and sim time.
- Crossings are evaluated only when the ball is descending after the move (`Vy > 0`). Ascending crossings are never marked.

**Transport timing**: markers are sent from the main thread inside `Update`, before the frame containing the event is rendered. All physics steps processed in one frame send at almost the same wall-clock time (sub-ms apart). On a 250 Hz EEG stream (BciCore `Fs=250`) or any latched-marker line, two sends within one sample period can overwrite or merge. The code comment "so 250 Hz EEG markers never overwrite" (`:866`) only covers trajectory/reversal vs collision codes.

**Validation** (`ValidateSettings`, `:258-316` + `SsvepFrequencyAssignment.ValidatePaddle`):
- All 21 configured codes (reset, start L/R, stop, 70-86 fields) must be pairwise distinct.
- Start L/R must be EEG-board start codes (20-24 or 31-34) and distinct. Stop must be 30 or 60.
- Every other code (reset, 70-86 fields) must be 0-255 and must not be a board start/stop code (20-24, 31-34, 30, 60).
- With shuffle On: left frequency < right frequency, both positive and finite.
- `livesAndTrials` even and ≥ 2; max run 1-2; positive launch angle; base speed ≤ max speed; tunnelling guard `max·sx/120 ≤ paddleHeight·sy + r` and `≤ min(brickW, brickH) + 2r` (`:319-332`); gratings leave an inert strip; paddle fits; brick fits the region.

**Legacy vs current schemes**

| Version | Start | Collisions | Fall | Trajectory / reversal |
|---|---|---|---|---|
| original port (`cc7ce62`) up to the paddle-family balance change | 20 for either launch | 70 / 71 / 72 | none | none |
| paddle-family change (before 302340f) | 20 left / 21 right, or 31-34 shuffled | 70 / 71 / 72 | none | none |
| current (302340f, merged af3b034) | 20 / 21 or 31-34 | 73/74/75, 81/82/83, 72 | 84 | 76-80, 85/86 |

Identify the scheme of a dataset by the keys in `*_session.csv`: `TriggerLeftWallBounce` present means current; `TriggerTrialStartRight` absent means the oldest scheme.

---

## 10. Output files

All task files go to `dataPath = Path.IsPathRooted(dataFolderName) ? dataFolderName : Application.persistentDataPath/<dataFolderName>` (default `…/data`) (`:450`). They are created at "Begin session", not at launch.

### 10.1 Task CSVs (`BreakoutCsvLogger.cs`)
Names: `p<P>_b<S>_breakout_{trialdata|trace|droppedframes|session}<suffix>.csv`. `P` and `S` have invalid filename characters replaced by `_` (empty → `000`) (`:62-67`). Suffix: `""` for the first run, otherwise `_r2`, `_r3`, … up to `_r1000`. A suffix is used only if none of the four files exists, and all four share it. Files are created with `FileMode.CreateNew`, UTF-8 without BOM, `Environment.NewLine` line endings (CRLF on Windows, LF on Android) (`:35-58`). Existing files are never appended to, so there is no header-mismatch situation. Different code versions write different headers into new files. Rows are buffered in memory and appended at every `Flush`: each trial end, abort, fatal and destroy (`:117-123`). A hard kill mid-trial loses the current trial's trace/drops.

Numeric format: invariant culture; `F6` = 6 decimals, `F3` = 3 decimals; NaN is written as `NaN`; booleans as 0/1.

Time base for all task CSVs: `T = Time.realtimeSinceStartupAsDouble − experimentT0`, in seconds, where `experimentT0` is taken in `Start()` (`:347`), i.e. at game launch, before calibration and instructions. This is NOT the `MonotonicClock` used by the stimulus-frame CSV and NOT synchronised to EEG.

#### `*_trialdata.csv` — one row per started trial (`AddTrial`, `:89-98`; called from `WriteTrialRow`, `:585-599`)

| Column | Meaning | Units / format | Time base / notes |
|---|---|---|---|
| TrialNumber | 1-based trial index | int | |
| TrialStart | time of `BeginTrialMotion` (ball spawn and start-marker send) | s, F6 | T |
| TrialEnd | time of `FinishFeedback` (marker 30 send), i.e. ≈ fall/timeout + `missDisplaySec`; for aborts the abort time | s, F6 | T |
| TrialDuration | TrialEnd − TrialStart (includes feedback period) | s, F6 | |
| PaddleBounces | paddle reflections this ball | count | = number of 81/82/83 markers |
| WallBounces | steps with any wall reflection | count | = number of 73/74/75 markers |
| BricksBroken | bricks broken | count | = number of 72 markers |
| BallFell | 1 if the ball fell | 0/1 | can be 1 with `EndReason=Timeout` (same-frame tie) |
| DroppedFrameCount | Σ over late Trial frames of `max(1, round(dt/nominal) − 1)` | count (estimated frames) | not equal to the droppedframes row count |
| StartBallSpeedPxPerSec | speed at spawn (= base·sx) | screen px/s, F3 | |
| FinalBallSpeedPxPerSec | `sim.SpeedPxPerSec` at the last simulated step | screen px/s, F3 | |
| EndReason | `Fell` / `Timeout` / `Aborted` | string | |
| LaunchSide | −1 left, +1 right | int | planned and realised sign of initial Vx |
| FrequencyLeftHz / FrequencyRightHz | flicker frequency of left / right grating this trial | Hz, F6 | |
| FrequenciesSwapped | 1 if left got the right/high frequency | 0/1 | |
| TrialStartMarker | code sent at TrialStart | int | 20/21 or 31-34 |
| NFIndexLeftUsed / NFIndexRightUsed | 1-based NF channel driving left / right | 1 or 2 | |

#### `*_trace.csv` — periodic kinematics during the Trial state only (`AddTrace`, `:100-109`; `:539-548`)
A row is written in the first Trial frame and then in each frame where `now − lastTraceRow ≥ traceLogIntervalSec`. Values are taken after that frame's physics steps.

| Column | Meaning | Units | Notes |
|---|---|---|---|
| TrialNumber | trial | int | |
| FrameNumber | Trial-state frame counter, 1 at the first Trial frame | int | resets every trial |
| SampleTime | frame Update time | s, F6, T | CPU time, not presentation |
| NFLeft / NFRight | current mapped NF pair (held value) | raw NF units, F6 | 0 until the first fresh pair of the trial |
| NFSigned | NFRight − NFLeft, without deadzone | F6 | the deadzone is applied only in control |
| NFReadOk | 1 if a fresh NF pair arrived in this exact frame | 0/1 | mostly 0 at 10 Hz NF vs 120 Hz frames; not an error flag |
| PaddleCenterX | paddle centre x | screen px, F3 | |
| PaddleVxPxPerSec | last step's actual paddle displacement / step | screen px/s, F3 | not clamped by the carry cap |
| BallX / BallY | ball centre | screen px, F3, y down | |
| BallVxPxPerSec / BallVyPxPerSec | ball velocity | screen px/s, F3 | Vy < 0 means upward |
| BallSpin | spin state (= 0.05·carry px/step, ×0.1 per step) | F6 | practically 0 except right after a paddle hit |
| BrickActive | brick present | 0/1 | |
| BrickCenterX / BrickCenterY | brick centre | screen px, F3; `NaN` if none | |
| BricksBroken | cumulative bricks this trial | int | |
| BallSpeedPxPerSec | scheduled speed | screen px/s, F3 | |

#### `*_droppedframes.csv` (`AddDropped`, `:111-114`; `:526-533`)
One row per Trial-state frame with `unscaledDeltaTime > 1.5/targetFrameRate`. Preview, feedback and ITI frames are not checked.

| Column | Meaning |
|---|---|
| TrialNumber | trial |
| FrameNumber | Trial frame counter (as in trace) |
| VBLTime | Update time of the late frame, s, T (CPU time; not a VBL timestamp despite the name) |
| MissedBySec | `dt − 1/targetFrameRate`, s |

#### `*_session.csv` (`Key,Value`, written once at Begin; `BuildSessionInfo`, `:934-1014`)
Keys in order: `Game, Participant, Session, RandomSeed, UseFixedRandomSeed, StartedLocalTime (yyyy-MM-dd HH:mm:ss, local), UnityVersion, ScreenWidthPx, ScreenHeightPx, ScaleX, PhysicsStepHz, TargetFrameRate, LivesAndTrials, BlockTimeLimitSec, NoBrickTimeoutSec, PreSpawnDelaySec, MissDisplaySec, ItiDurationSec, BallRadiusPx, BallBaseSpeedPxPerSec, BallLaunchMaxAngleDeg, SpeedUpMode, SpeedUpPerPaddleHitPxPerSec, SpeedUpPerSecondPxPerSec, MaxBallSpeedPxPerSec, PaddleBounceMaxAngleDeg, PaddlePushGain, PaddleSpinGain, MagnusGainPerFrame, SpinDecayPerFrame, MinVerticalSpeedFraction, PaddleWidthPx, PaddleHeightPx, PaddleGratingWidthPx, BrickWidthPx, BrickHeightPx, ConnectionMode, MotionMode, PositionGainPx, PaddleNfGainPxPerSec, PaddleMaxSpeedPxPerSec, PaddleNfDeadzone, MaxConsecutiveDirectionTrials, RandomizeSsvepFrequencies, ShuffledStartMarkerMeaning, GratingLeftFreqHz, GratingRightFreqHz, TriggerReset, TriggerTrialStart, TriggerTrialStartRight, TriggerTrialStop, TriggerWallBounce, TriggerPaddleBounce, TriggerBrickBounce, TriggerLeftWallBounce, TriggerRightWallBounce, TriggerTopWallBounce, TriggerScreenMidlineLtoR, TriggerScreenMidlineRtoL, TriggerCriticalHorizon, TriggerPaddleMeridianLtoR, TriggerPaddleMeridianRtoL, TriggerPaddleHitLeft, TriggerPaddleHitCenter, TriggerPaddleHitRight, TriggerBallFell, TriggerPaddleRevLtoR, TriggerPaddleRevRtoL, CriticalHorizonOffsetPx, ReversalSpeedThresholdPxPerSec, ReversalRefractorySec, BrickBasePoints, BounceBonus, TimeBonusRate`. Pixel values are reference px (settings), not screen px. Not logged: see §14.

### 10.2 Stimulus-frame CSV (optional; `logStimulusIntensityEveryFrame`, default Off; Common override)
`<dataPath>/p<P>_b<S>_breakout_stimframes_<UTC yyyyMMdd_HHmmssfff>[_rN].csv` plus a `.metadata.json` next to it, created at Begin (`:452-453`). P and S are not sanitised here. Schema 3, columns as in the shared doc. Breakout-specific usage (`:1148-1153`):
- One row per rendered (Repaint) frame in **Preview** (`Stage=preview`) and **Trial** (`Stage=trial`). No rows in Feedback or ITI.
- `TrialNumber` = trial index + 1; Preview rows carry the number of the upcoming trial.
- `StimulusC1Intensity` = left grating `I_L`, `StimulusC2Intensity` = right `I_R`; `FrequencyC1Hz/C2Hz` = this trial's left/right frequency (after swap).
- `PhaseOriginMonotonicSec` = the trial's phase origin (first Preview frame's predicted presentation); `PhaseTimeSec` = predicted presentation − origin. `MeanLuminance` 0.5, `ModulationDepth` 1, phases 0.
- Written in a batch at each `EndTrial` and completed during export. Lost if the app is killed.

### 10.3 EEG logs (BciCore mode only)
Written by `BciServer` (see the shared doc), not to `dataPath`: `Application.persistentDataPath/BciCoreLogs/eeg_breakout_p<P>_s<S>_<yyyyMMdd_HHmmss>/` with `_raw.csv`, `_signals.csv`, `_features.csv`, `_health.csv`, `_config.txt` (DirectCsv) or binaries converted at export (BinaryThenCsv). Nothing is written when EEG logging is Disabled. The game name `breakout` comes from the launcher's `SetSessionIdentity(..., gameId)`. A new folder is started on every board HELLO / connect, so a reconnect splits the recording. Markers latch into the per-sample `Marker` column. Software sends also appear in `_health.csv` as `trigger_sent:<name>` rows (Seq = 0, `WallClockSec` = integer seconds of local time of day, so 1 s resolution).

USB Biosemi mode: the game writes no EEG. EEG and markers are recorded by the P-system / MATLAB bridge outside this app.

---

## 11. Settings reference

UI label = launcher `Nicify(fieldName)` (`CogLabAppController.cs:253-264`). Fields marked **C** are hidden from the Breakout tab and set from the Common tab (`SharedSettingsCatalog.cs:32-48`). The value is the prefab value unless a Common value was saved. Fields marked **A** are shown only with "Advanced" (groups `Colors…`, `Trigger Codes`, `Text`). "Default" is the effective default (prefab, or code initialiser where the prefab lacks the field). Prefab and code initialisers agree for every field the prefab contains.

| UI label | Field | Default | Unit | Meaning |
|---|---|---|---|---|
| Lives And Trials | `livesAndTrials` | 10 | count (even, ≥ 2) | balls = trials = lives |
| Max Consecutive Direction Trials | `maxConsecutiveDirectionTrials` | 2 | 1-2 | run cap of launch side (saved > 2 migrates to 2) |
| Block Time Limit Sec | `blockTimeLimitSec` | 360 | s (0 = off) | checked between trials |
| No Brick Timeout Sec | `noBrickTimeoutSec` | 120 | s | trial ends if no brick broken |
| C: Use fixed random seed | `useFixedRandomSeed` | false | bool | |
| C: Fixed random seed | `fixedRandomSeed` | 918273 | int | |
| Pre Spawn Delay Sec | `preSpawnDelaySec` | 2 | s | Preview duration |
| Miss Display Sec | `missDisplaySec` | 1.5 | s | feedback duration before marker 30 |
| Iti Duration Sec | `itiDurationSec` | 1 | s | blank ITI |
| C: NF trace interval (seconds) | `traceLogIntervalSec` | 0.1 | s | trace period |
| C: Display / target refresh rate (Hz) | `targetFrameRate` | 120 | Hz | `Application.targetFrameRate`, refresh request, dropped-frame nominal |
| C: VSync count (desktop) | `verticalSyncCount` | 1 | 0-4 | ignored on Android (forced 0) |
| C: Log stimulus intensity every frame | `logStimulusIntensityEveryFrame` | false | bool | stimframes CSV |
| Ball Radius Px | `ballRadiusPx` | 12 | ref px (×smin) | |
| Ball Base Speed Px Per Sec | `ballBaseSpeedPxPerSec` | 200 | ref px/s (×sx) | speed at spawn |
| Ball Spawn Gap Px | `ballSpawnGapPx` | 6 | ref px (×sy) | gap above paddle at spawn |
| Ball Launch Max Angle Deg | `ballLaunchMaxAngleDeg` | 30 | deg from vertical | |
| Speed Up Mode | `speedUpMode` | Off (0) | enum Off/PerPaddleHit/OverTime/Both | |
| Speed Up Per Paddle Hit Px Per Sec | `speedUpPerPaddleHitPxPerSec` | 10 | ref px/s | |
| Speed Up Per Second Px Per Sec | `speedUpPerSecondPxPerSec` | 5 | ref px/s per sim-second | |
| Max Ball Speed Px Per Sec | `maxBallSpeedPxPerSec` | 1000 | ref px/s | cap; tunnelling-checked |
| Paddle Bounce Max Angle Deg | `paddleBounceMaxAngleDeg` | 60 | deg | contact steering |
| Paddle Push Gain | `paddlePushGain` | 0.35 | — | carry added to vx |
| Paddle Spin Gain | `paddleSpinGain` | 0.05 | — | spin from carry |
| Magnus Gain Per Frame | `magnusGainPerFrame` | 0.01 | per step | |
| Spin Decay Per Frame | `spinDecayPerFrame` | 0.1 | retention factor per step | |
| Min Vertical Speed Fraction | `minVerticalSpeedFraction` | 0.15 | fraction of speed | |
| Field Margin Px | `fieldMarginPx` | 0 | ref px | |
| Paddle Width Px | `paddleWidthPx` | 900 | ref px (×sx) | |
| Paddle Height Px | `paddleHeightPx` | 200 | ref px (×sy) | |
| Paddle Bottom Margin Px | `paddleBottomMarginPx` | 50 | ref px (×sy) | |
| Paddle Border Px | `paddleBorderPx` | 3 | ref px | visual only |
| Paddle Grating Width Px | `paddleGratingWidthPx` | 300 | ref px | each side; must be < width/2 |
| Grating Bar Width Px | `gratingBarWidthPx` | 14 | ref px | spatial period 28 |
| Hud Height Px | `hudHeightPx` | 80 | ref px | defines field top |
| Brick Width Px / Brick Height Px | `brickWidthPx`/`brickHeightPx` | 100 / 100 | ref px (×sx / ×sy) | |
| Brick Border Px | `brickBorderPx` | 3 | ref px | visual only |
| Brick Region Top / Side / Bottom Margin Px | `brickRegion{Top,Side,Bottom}MarginPx` | 80 / 60 / 60 | ref px | region bottom = H/2 − margin |
| Brick Spawn Ball Clearance Px | `brickSpawnBallClearancePx` | 40 | ref px (×smin) | plus ball radius |
| Brick Spawn Max Attempts | `brickSpawnMaxAttempts` | 200 | count | |
| Brick Base Points / Bounce Bonus / Time Bonus Rate | `brickBasePoints`/`bounceBonus`/`timeBonusRate` | 100 / 10 / 5 | points, points/s | score only |
| Connection Mode | `connectionMode` | UsbBiosemi (1) | enum BciCore(0)/UsbBiosemi(1) | |
| C: USB Biosemi port | `usbBiosemiPort` | 5010 | TCP port | |
| C: Connection timeout (seconds) | `usbConnectionTimeoutSec` | 10 | s (≥ 1 used) | USB only |
| C: USB NF stall timeout | `usbNfStallAbortSec` | 5 | s (0 = off) | USB only |
| Paddle Nf Gain Px Per Sec | `paddleNfGainPxPerSec` | 600 | ref px/s per NF unit | VelocityUpdate |
| Paddle Max Speed Px Per Sec | `paddleMaxSpeedPxPerSec` | 600 | ref px/s | velocity cap and carry cap |
| Paddle Nf Deadzone | `paddleNfDeadzone` | 0.02 | NF units | |
| Motion Mode | `motionMode` | VelocityUpdate (0) | enum | |
| Position Gain Px | `positionGainPx` | 600 | ref px per NF unit | PositionUpdate |
| C: Enable keyboard controls | `allowKeyboardPaddle` | true | bool | arrows, VelocityUpdate only |
| Keyboard Paddle Speed Px Per Sec | `keyboardPaddleSpeedPxPerSec` | 600 | ref px/s | not capped by max speed |
| C: Data folder | `dataFolderName` | `data` | path | relative to persistentDataPath |
| C: Stimulus 1 / left / shuffle low frequency (Hz) | `gratingLeftFreqHz` | 15 | Hz | |
| C: Stimulus 2 / right / shuffle high frequency (Hz) | `gratingRightFreqHz` | 17 | Hz | |
| (hidden) | `ssvepFrequencyVersion` | 1 | — | migration marker (17/19 → 15/17 once) |
| Randomize Ssvep Frequencies | `randomizeSsvepFrequencies` | false | bool | per-trial balanced swap |
| A: Reset Trigger … Brick Bounce Trigger | `resetTrigger, trialStartTrigger, trialStartRightTrigger, trialStopTrigger, wallBounceTrigger, paddleBounceTrigger, brickBounceTrigger` | 0, 20, 21, 30, 70, 71, 72 | code | §9 |
| A: Left/Right/Top Wall Bounce Trigger | `left/right/topWallBounceTrigger` | 73 / 74 / 75 | code | code default (not in prefab) |
| A: Screen Midline Lto R / Rto L Trigger | `screenMidlineLtoRTrigger`/`…RtoL…` | 76 / 77 | code | code default |
| A: Critical Horizon Trigger | `criticalHorizonTrigger` | 78 | code | code default |
| A: Paddle Meridian Lto R / Rto L Trigger | | 79 / 80 | code | code default |
| A: Paddle Hit Left / Center / Right Trigger | | 81 / 82 / 83 | code | code default |
| A: Ball Fell Trigger | `ballFellTrigger` | 84 | code | code default |
| A: Paddle Rev Lto R / Rto L Trigger | | 85 / 86 | code | code default |
| A: Critical Horizon Offset Px | `criticalHorizonOffsetPx` | 250 | ref px (×sy) above paddle top; 0 disables 78 | code default |
| A: Reversal Speed Threshold Px Per Sec | `reversalSpeedThresholdPxPerSec` | 50 | ref px/s | code default |
| A: Reversal Refractory Sec | `reversalRefractorySec` | 0.40 | s (min 0.1) | code default |
| C: UDP trigger port | `udpTriggerPort` | 5007 | UDP port | BciCore UDP copy |
| A: Udp Trigger Host | `udpTriggerHost` | `10.36.17.144` | host | BciCore UDP copy |
| A: colours (Background Color … Miss Color) | 16 `Color` fields | see §6 | sRGB 0-1 | |
| A: Instructions Text / Speed Up Instructions Text / Begin Button Label | | see prefab | text | |

**Common-tab and launcher inputs that affect Breakout**: `targetFrameRate`, `verticalSyncCount`, `gratingLeftFreqHz`, `gratingRightFreqHz`, `usbBiosemiPort`, `usbConnectionTimeoutSec`, `usbNfStallAbortSec`, `udpTriggerPort`, `dataFolderName`, `logStimulusIntensityEveryFrame`, `traceLogIntervalSec`, `useFixedRandomSeed`, `fixedRandomSeed`, `allowKeyboardPaddle`. Also participant number → `P`; session/"block" number → `S` (file names, BciCore Participant/Block); EEG logging mode (BinaryThenCsv / DirectCsv / Disabled; BciCore mode only). Not shared: `udpTriggerHost`, `connectionMode`, `keyboardPaddleSpeedPxPerSec`. `cueFromTrialStart` does not exist in Breakout.

---

## 12. Timing & clock semantics

| Column / quantity | Clock | Origin | Precision / meaning |
|---|---|---|---|
| trialdata `TrialStart` | `Time.realtimeSinceStartupAsDouble` | `experimentT0` = game `Start()` | CPU time of the Update that spawned the ball and sent the start marker. The first frame showing the ball is presented ≥ 1 frame later (unmeasured). |
| trialdata `TrialEnd` | same | same | CPU time of the marker-30 send (≈ fall + 1.5 s), or abort time |
| trace `SampleTime`, droppedframes `VBLTime` | same | same | CPU Update time; frame-quantised |
| stimframes `SampleMonotonicSec`, `PredictedPresentationMonotonicSec`, `PhaseOriginMonotonicSec` | `MonotonicClock` (Stopwatch) | arbitrary (device boot-ish) | see shared doc; predicted, not actual presentation (`ActualPresentationMonotonicSec` = NaN) |
| stimframes `TimestampUnixMs` | Unix ms via one UTC anchor at logger creation | — | maps SampleMonotonicSec; not presentation |
| physics / sim time (`simClock`, `ElapsedSec`, reversal refractory, glide) | accumulated fixed steps | per session / per spawn | lags real time if a frame exceeds 66.7 ms |
| EEG marker sample | board sample clock (BciCore 250 Hz) or Biosemi | — | the only link between task events and EEG |

- No column maps T to `MonotonicClock` or to EEG time. Align with markers (§13). T and `MonotonicClock` can be related approximately because both advance in real time: compare trial-start rows with the first `Stage=trial` stimframes row of each trial.
- **Dropped frame here** means: `unscaledDeltaTime > 1.5 × (1/targetFrameRate)` for a Trial-state frame. It is a CPU frame-interval heuristic. It does not prove a missed display refresh and it ignores Preview. The stimframes `SkippedScheduleSlots` / `RepeatedScheduleSlot` give a separate VSYNC-lattice view (also scheduled, not measured).
- Physics events are quantised to 1/120 s sim steps, and their markers to the frame in which those steps are processed. Event time error relative to the step ≈ up to 1 frame plus transport latency.
- `TrialDuration` is not the rally length. Rally length ≈ `TrialDuration − missDisplaySec − (0…1 frame)` for Fell/Timeout trials; exact from the 84 marker or the start→84 interval in EEG.

---

## 13. Analysis guide

**Joining files**
- Task CSVs: same stem `p<P>_b<S>_breakout_*<suffix>`; key `TrialNumber` (trialdata ↔ trace ↔ droppedframes).
- Stimframes: same `P`/`S` and creation time ≈ session.csv `StartedLocalTime` (the stimframes name carries UTC, StartedLocalTime is local). Key `TrialNumber` plus `Stage`.
- EEG (BciCore): folder `eeg_breakout_p<P>_s<S>_<local start time>`; there may be several folders if the board reconnected.
- Don't confuse with `*_breakoutval_*` files: those are written by the Paddle game (`Assets/Games/Paddle/Scripts/PaddleGameController.cs:674-676`).

**Aligning EEG markers with CSV rows**
1. Extract marker onsets from the EEG (`Marker` column transitions from 0/other to the code; latched codes can persist over several samples, so use rising edges).
2. Take the start-marker sequence (codes in {20,21,31,32,33,34}). The k-th start marker ↔ trialdata row k. Check that the code equals `TrialStartMarker`. A trial aborted during Preview has neither a marker nor a row. An aborted trial in Trial state has both, plus marker 30 at abort.
3. Fit `t_eeg = a + b·TrialStart` over trials (b ≈ 1). Residuals show frame + transport jitter. Use the fit to map trace `SampleTime` into EEG time when needed.
4. Within a trial, event markers 72-86 lie between the start marker and the following 30. Check: count of {81,82,83} = `PaddleBounces`, {73,74,75} = `WallBounces`, 72 = `BricksBroken`, 84 present iff `BallFell=1` (unless lost by overwrite or the trial was aborted). Mismatches show marker loss through same-sample overwrites.

**Epoching suggestions**
- Paddle contact (81/82/83): e.g. −1.0 to +0.5 s. Condition on sector, launch side, swap.
- Critical horizon (78): pre-contact decision window, e.g. 0 to +0.6 s. Time to reach the paddle ≈ 250·sy / |Vy|; with |Vy| ≤ speed it is ≥ 1.25 s at 200 ref px/s.
- Paddle meridian / midline crossings (76/77/79/80): lateral attention-shift epochs; only descending ball; may be suppressed by higher-priority events in the same step.
- Paddle reversal (85/86): motor/NF reversal epochs, ±0.5 s; refractory 0.4 s.
- Whole-trial SSVEP: from the start marker to 84 (or to `30 − 1.5 s` for Timeout). Flicker also runs ≈ 2 s before the start marker (Preview), so [−2, 0] s is NOT a flicker-free baseline. Flicker-free intervals: Feedback + ITI (≈ fall → fall + 2.5 s) and Instructions.
- Frequency tags per trial: left = `FrequencyLeftHz`, right = `FrequencyRightHz`. Attended side ≈ the side the ball is on relative to the paddle (trace `BallX − PaddleCenterX`).

**Performance metrics**
- Rally duration (start → 84), bricks per trial, paddle bounces per trial, bricks per minute of rally.
- Proportion of Timeout vs Fell. Sector distribution of paddle hits (81/82/83: centre vs grating hits).
- NF control accuracy from trace: for descending-ball rows, `required = sign(BallX − PaddleCenterX)` vs `sign(NFSigned)` (apply deadzone 0.02 yourself), or vs `sign(PaddleVxPxPerSec)`. Correlate `NFSigned` with required direction. Use `NFReadOk=1` rows only to sample distinct NF packets (the trace is frame-sampled; NF is held between packets).
- Launch-side effect: compare early-trial NF sign with `LaunchSide`.
- Score (if needed): §8 formula.

**Sanity checks**
- `count(rows) ≤ LivesAndTrials`. For a complete block, LaunchSide sums to 0 and the max run ≤ `MaxConsecutiveDirectionTrials`. `FrequenciesSwapped` all 0 unless `RandomizeSsvepFrequencies=True`. `TrialStartMarker` matches LaunchSide/swap rules. `NFIndexLeftUsed = 1 + FrequenciesSwapped`.
- `StartBallSpeedPxPerSec ≈ BallBaseSpeedPxPerSec·ScaleX` (speed-up off). `FinalBallSpeedPxPerSec ≤ MaxBallSpeedPxPerSec·ScaleX`.
- `TrialDuration ≥ MissDisplaySec` for non-aborted rows. `EndReason=Fell ⇒ BallFell=1`. Timeout rows should have the last brick or start ≥ `NoBrickTimeoutSec` before TrialEnd − 1.5 s.
- Trace `FrameNumber` steps ≈ `traceLogIntervalSec × refresh`. Long gaps indicate hitches. Trace rows only lie between TrialStart and ≈ TrialEnd − MissDisplaySec.
- Every trial row has a 30 marker. 30s are ≈ 1.5 s after 84.
- Stimframes: `FrequencyC1Hz == FrequencyLeftHz` per trial. `PhaseTimeSec` increases by `VsyncPeriodSec` per row. Count `SkippedScheduleSlots > 0`.
- DroppedFrameCount vs droppedframes rows (they differ by design).
- Session.csv: check the trigger keys to identify the marker scheme (§9). Check `ConnectionMode`/`MotionMode`.

---

## 14. Known caveats / doc discrepancies

1. **README trigger list is stale** (`README.md` "Breakout (ball speed-up & dynamic brick)"): it lists 70 wall / 71 paddle / 72 brick and no 73-86. The code now sends 73/74/75 instead of 70 and 81/82/83 instead of 71, and adds 76-80, 84-86. 70 and 71 remain configurable and validated but are unreachable fallbacks (`BreakoutGameController.cs:832-846`). The "Paddle family" section repeats "Breakout collision events remain 70 wall, 71 paddle, 72 brick" (stale).
2. README says `trialstop` (30) fires when the ball falls or times out. In code it fires `missDisplaySec` (1.5 s) later, at the end of feedback (`:567-570`). The fall itself is now marked by 84; a timeout has no immediate marker.
3. The 17 new fields (triggers 73-86, `criticalHorizonOffsetPx`, `reversalSpeedThresholdPxPerSec`, `reversalRefractorySec`) are not in `BreakoutGame.prefab`. Effective defaults are the C# initialisers. PlayerPrefs saved before 302340f also lack them, so the initialisers apply there as well.
4. `ALL TRIALS COMPLETED` is unreachable: lives = trials, and `livesRemaining<=0` is tested first (`:623`). Normal completion shows `NO LIVES REMAINING`. The session end reason is not logged anywhere.
5. `TrialEnd`/`TrialDuration` include the 1.5 s feedback period, and so does the summary's "mean rally time" (`:596`, `:1093-1095`). There is no CSV column for the fall/timeout time.
6. The score is not written to any file (on-screen summary only).
7. No marker or CSV event for brick spawn (`StepEvents.BrickSpawned` is computed but unused) or for Preview onset.
8. Crossing/reversal markers are mutually exclusive per step (priority 78 > 79 > 80 > 76 > 77 > 85/86) and suppressed on any collision step. Collision markers in the same step, and markers from several physics steps in one frame, are sent at the same instant and can overwrite each other on a 250 Hz latched marker channel. The code comment claiming no overwrites is only partly true.
9. Reversal detection: the first direction after trial start is never marked; reversals within the 0.40 s refractory are swallowed; state is updated only on quiet steps.
10. `NFReadOk` in the trace means "a fresh pair arrived in this frame", not "read succeeded". `NFSigned` is the raw difference without deadzone. The README's statement for Paddlev2 (deadzone-filtered NFSigned) does not apply to Breakout.
11. `session.csv` is described in the README as a "complete parameter … snapshot" but omits: `ScaleY`/`smin`, `VerticalSyncCount`, `TraceLogIntervalSec`, EEG logging mode, `AllowKeyboardPaddle`, `KeyboardPaddleSpeedPxPerSec`, `BallSpawnGapPx`, `FieldMarginPx`, `PaddleBottomMarginPx`, `PaddleBorderPx`, `GratingBarWidthPx`, `HudHeightPx`, brick region margins, brick clearance/attempts, USB port/timeouts, UDP host/port, colours, `LogStimulusIntensityEveryFrame`, and the planned launch/swap schedules. ScaleY can be recomputed as `ScreenHeightPx/1080`.
12. All CSV positions and speeds are screen px (scaled), while session.csv values are 1920×1080 reference px. Bricks scale anisotropically on non-16:9 screens.
13. `spinDecayPerFrame = 0.1` is a retention multiplier (90 % spin loss per step), so the Magnus effect is negligible after ~2 steps. This matches the MATLAB-port constant but the name suggests otherwise.
14. BciCore mode: no NF stall detection. A frozen NF stream leaves the paddle moving at its last velocity (VelocityUpdate). `BciCoreNfReader.Error` is always null.
15. BciCore mode: the `reset` marker is sent immediately after `StartServer`, before the ESP32 normally connects, so it usually reaches only the UDP fallback and health.csv (`:363`). Every BciCore marker is also sent by UDP to the hard-coded default host `10.36.17.144:5007`.
16. README calls the gratings "contrast square-wave gratings". The spatial profile is a square-wave bar grating, but the temporal modulation is a sinusoidal 0-1 contrast envelope (not on/off, not reversal), interpolated in linear colour space.
17. Task CSV time base (`Time.realtimeSinceStartupAsDouble − experimentT0`, origin at game launch) differs from the stimframes `MonotonicClock`. `droppedframes.VBLTime` is CPU Update time, not a VBL timestamp. `DroppedFrameCount` ≠ number of droppedframes rows. Preview frames are never checked.
18. With a fixed seed, only the launch-side and swap schedules are reproducible. Launch angles and brick positions depend on gameplay because they share `rng`. (The README's "shuffling uses a separate random stream" claim is correct: `rng.Next()` is always consumed at `:462`.)
19. A tie between timeout and fall in the same frame records `EndReason=Timeout` with `BallFell=1`.
20. Filename sanitisation differs between files: task CSVs replace invalid chars with `_`, stimframes use P/S raw, and BciCore drops non-alphanumerics. Stems can differ for unusual participant IDs.
21. `OnDestroy` only queues the last stimulus-frame batch without awaiting it. Stimframes can be incomplete if the app is killed or the object destroyed without the Exit/Esc export path.
22. `*_breakoutval_*` files in existing data folders come from the Paddle game, not Breakout.
23. Unused or legacy code: `flickerT0` is set but never used. `AddTrace` parameter names `nf17/nf19` are legacy (the columns are `NFLeft/NFRight`).
24. In `Fatal` state Escape is disabled, but "Exit to menu" works and runs the export path.
25. Keyboard override speed (600) is not limited by `paddleMaxSpeedPxPerSec`. The carry passed to the ball is capped.

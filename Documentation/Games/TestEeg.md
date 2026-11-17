# Test EEG (`test-eeg`): signal-quality check utility

> Scope: everything the **Test EEG** launcher entry does and records, checked against the code at commit `af3b034` (the entry was added in `81b93b8`).
> Shared internals (BciCore server, loggers, frame protocol, clocks) are covered in [00-Shared-Infrastructure.md](00-Shared-Infrastructure.md). This page states only how Test EEG uses them.
> Paths are repo-relative. `TestEegController.cs` means `Assets/Games/TestEeg/Scripts/TestEegController.cs`.

**Summary for an analysis agent.** Test EEG is **not a task**. It has no trials, stimuli, responses, scoring or task CSV. It has no neurofeedback or SSVEP logic of its own and **it never sends a trigger itself**. It starts the in-process BciCore server and shows the shared BCI GUI (`CalibrationScreen`) so an operator can inspect live waveforms, the FFT and the per-electrode filtered ADC counts. When any exit button is pressed, it saves the BciCore EEG recording. The only data it produces is a normal BciCore session folder named `eeg_test-eeg_p<participant>_s<session>_<yyyyMMdd_HHmmss>/`. Treat that folder as a resting / signal-check recording with no task structure.

---

## 1. Overview & paradigm

| Item | Value |
|---|---|
| What the participant sees | Nothing designed for the participant. The screen shows the operator-facing "BCI Telemetry V2" GUI: a network and packet-loss panel, a multi-channel waveform or FFT view (screen 1), and a per-channel filtered-ADC-count level/box plot (screen 2). See `CalibrationScreen.cs:1-33`. |
| What the participant does | Nothing is required. Typically the participant sits still while electrodes are checked. Nothing is instructed or recorded about the participant's behaviour. |
| Purpose | Check electrode contact and signal quality (raw µV waveforms, spectrum, ADC count levels) without launching a task, and keep a recording of that check (`TestEegController.cs:10-14`; commit message of `81b93b8`). |
| Correct-response / success rule | Not applicable: there are no trials or responses. "Success" only means that a board connected and an EEG session folder was written (see `RecordedThisRun`, `TestEegController.cs:110-118`). |

## 2. Code map

| Item | Value |
|---|---|
| Folder | `Assets/Games/TestEeg/` |
| `TestEegController` (`Scripts/TestEegController.cs:15`) | `MonoBehaviour, IGameSession`. Starts and stops `BciServer`, opens the shared `CalibrationScreen`, exports the EEG on exit, and draws a status/error overlay. |
| `TestEegGameModule` (`Scripts/TestEegGameModule.cs:6`) | Empty subclass of `CogLab.Framework.GameModule`, used for launcher registration only ("opens the BCI GUI without any task"). It adds no overrides, so the base `ValidateSettings` and `ApplySavedSettings` apply. |
| Assembly | `Assets/Games/TestEeg/CogLab.Games.TestEeg.asmdef`: name `CogLab.Games.TestEeg`, references `CogLab.Framework`, `CogLab.Shared`, `BciCore`, `autoReferenced: true`. |
| Prefab | `Assets/Games/TestEeg/Prefabs/TestEegGame.prefab` (GUID `30dca1d68eb62a040923bbb94a6d3682`). It has one GameObject `TestEegGame` with a **disabled** `TestEegController` (the settings template, `m_Enabled: 0`, prefab line 43) and an enabled `TestEegGameModule`. |
| Scene placement | Prefab instance in `Assets/CogLab/App/Scenes/CogLab.unity` (renamed `TestEegGame`, scene line ~318), under the launcher's games root. |
| Game ID | `test-eeg` (prefab line 65) |
| Display name | `Test EEG` (prefab line 66) |
| Launcher colour | `(0.55, 0.25, 0.62, 1)` (prefab line 67). This differs from the `GameModule` code default `(0.17, 0.58, 0.32)` (`Assets/CogLab/Framework/GameModule.cs:15`). |
| PlayerPrefs key | `CogLab.Games.test-eeg.v1` (`GameModule.cs:29`) |
| Launcher module class | `CogLab.Games.TestEeg.TestEegGameModule` |
| Shared code used | `BciCore.BciServer` (`Packages/org.iisc.bcicore.server/Runtime/Api/BciServer.cs`), `CogLab.Shared.Calibration.BciCalibration` / `CalibrationScreen`, `BciCore.MainThreadDispatcher`, `CogLab.Framework.EegLoggingMode`. It uses none of Timing, NeurofeedbackTransport, TriggerSender, UsbBiosemiLink or DisplayRateManager. |

## 3. Session flow / state machine

There is no explicit state enum. The states below are implied by the `screen`, `serverStarted`, `finishing`, `status` and `error` fields (`TestEegController.cs:29-32`).

```
Launcher "Test EEG" tile
  │  CogLabAppController.Launch (CogLabAppController.cs:690-710)
  │   - validates participant/session non-empty, saves PlayerPrefs
  │   - BciServer.SetSessionIdentity(participant, session, "test-eeg")   (:701)
  │   - GameModule.Launch → AddComponent(TestEegController), copy template JSON,
  │     ConfigureSharedLaunch(participant, session, eegLoggingMode, CompleteSession)  (GameModule.cs:78-120)
  ▼
Start()  (TestEegController.cs:45-70)
  │  Screen.sleepTimeout = NeverSleep (if keepScreenAwake); Application.runInBackground = true
  │  previousSessionDir = BciServer.CurrentSessionDir
  │  BciServer.StartServer(acquisitionPort, acquisitionFanoutPort,
  │       enableLogging = mode != Disabled, directCsvMode = mode == DirectCsv,
  │       participant, block = session)
  ├── exception ──► ERROR overlay "Could not start the EEG test: …\n\nTap to return."
  │                 BciServer.StopServer(); a MouseUp → ReturnToLauncher()   (:63-69, :139)
  ▼
CALIBRATION GUI (CalibrationScreen added via BciCalibration.Open, :58-61)
  │  OnEnable → BciServer.EnterCalibrationMode()   (CalibrationScreen.cs:201)
  │  Screen 1 [Back] [Stop & Export] [Reboot] [Next ▶]
  │  Screen 2 [◀ Back] [Stop & Export] [Reboot] [Finish EEG Test]
  │      ready message: "Check every electrode, then finish to save and return."
  │
  │  Back (screen 1)        → Finish()      (OnBackPressed = Finish)
  │  Stop & Export (1 or 2) → Finish()      (OnStopAndExportPressed = Finish)
  │  Finish EEG Test (2)    → Finish()      (OnProceedPressed = Finish; ProceedBlockReason always null → always enabled)
  │  ◀ Back (screen 2)      → screen 1 only
  │  Reboot                 → BciServer.SendMarker(0xFFFF) (firmware reboot command), stay
  ▼
Finish()  (:72-89), idempotent via `finishing`
  │  destroy CalibrationScreen; BciServer.ExitCalibrationMode()
  │  status overlay: "Saving EEG recording..." (or "Closing EEG test..." if Disabled)
  │  background Task: if serverStarted && RecordedThisRun → BciServer.ConvertCurrentSessionToCsvAsync(progress → status)
  │  finally → MainThreadDispatcher.Enqueue(ReturnToLauncher)
  ▼
ReturnToLauncher()  (:91-98)
  │  StopServer() → BciServer.StopServer() (disposes listener + logger; LastSessionDir set)
  │  Debug.Log "[TestEeg] EEG saved to <dir>" or "No EEG recorded (no board connected or logging disabled)."
  │  invoke launcher callback (GameModule.CompleteSession → destroys runtime, restores camera)
  │  Destroy(gameObject)
  ▼
Launcher FinishReturn (CogLabAppController.cs:715-727): DisplayRateManager.ApplyPresentation(120,1),
restores runInBackground and sleepTimeout, returns to Home.
```

| Aspect | Behaviour |
|---|---|
| Calibration (BciCore) | The whole game *is* the calibration GUI. `ProceedBlockReason` is `() => null` (`:58`), so the final button never waits for EEG: an operator can finish with no board connected. |
| Instructions | None. |
| Export | `ConvertCurrentSessionToCsvAsync`. In DirectCsv mode this only disposes/flushes the direct logger. In BinaryThenCsv mode it disposes the binary logger and converts `.bin` to `.csv` (`BciServer.cs:272-298`). It is skipped when `RecordedThisRun` is false. |
| Summary screen | None. The only feedback is the full-screen status text during export (`OnGUI`, `:126-140`) and a Unity log line. |
| Fatal / abort | Only an exception from `StartServer` or `BciCalibration.Open`. In practice the only bind failure that throws is the acquisition TCP port (`acquisitionPort`, `EspTcpListener.cs:88-90`). Failures to bind the fan-out port (`acquisitionFanoutPort`, `GameFanoutListener.cs:40-45`) or UDP trigger port 5007 (`EspTcpListener.cs:106-119`) are caught inside BciCore and logged only as warnings, so Test EEG runs on without them. If a BciServer listener is already running when `Start()` calls `StartServer`, the call returns early (`BciServer.cs:178-183`): participant/block are applied, but the new port, `enableLogging` and `directCsvMode` are **not**. The error overlay waits for a MouseUp (tap or click). There is no keyboard path. A board disconnecting mid-test does **not** abort: `BciServer` keeps listening and the GUI shows "Listening…/Disconnected". |
| Escape / Android Back | **Not handled.** No `KeyCode.Escape` handling exists in `TestEegController`, `CalibrationScreen` or `Assets/CogLab/**`. |
| Application pause | Not handled (no `OnApplicationPause`). `Application.runInBackground = true` only affects desktop/editor. |
| External teardown | If the runtime object is destroyed some other way (for example, the module is disabled), `OnDestroy` (`:120-124`) calls `StopServer()` **without** `ConvertCurrentSessionToCsvAsync`. In BinaryThenCsv mode the `.bin` files are kept but no CSVs are produced. |

## 4. Trial structure & timing

Not applicable: there are no trials. The only timing-related behaviour:

- The recording is continuous. It starts when the board connects. The `Connected` handler creates a logger only when none exists (`_logger == null && _directLogger == null`), which within one Test EEG run happens only on the first board connection, because loggers are not disposed on disconnect. Every `HELLO` disposes the current logger and creates a new one (`BciServer.cs:302-328, 402-419`; details in section 10.1). It ends when `Finish()` disposes the logger (DirectCsv: inside `ConvertCurrentSessionToCsvAsync`; Binary: likewise, before conversion) or at `StopServer()`.
- No timeouts, no ITI, no feedback. Frame rate is whatever the launcher left. The launcher applies 120 Hz / vSync 1 on return (`CogLabAppController.cs:722`), and Test EEG never calls `DisplayRateManager`.
- GUI-internal timers, which do not affect the data: FFT refresh 0.25 s over a 500-sample window, raw view span 5 s, filtered-count window 5 s, ring buffer history 10 s (`CalibrationScreen.cs:59-62, 109`; `ChannelRingBuffer.HistorySeconds = 10`).

## 5. Trial planning / randomisation

Not applicable: there are no conditions, no RNG and no seed.

## 6. Stimulus

Not applicable: Test EEG presents no stimulus and no SSVEP flicker. The visuals are only the operator GUI (`CalibrationScreen`, dark background `(0.07,0.08,0.12)`) and, during export or error, a full-screen `(0.04,0.05,0.08)` panel with white centred text sized `32 × u` px, where `u = clamp(min(W,H)/1080, 0.5, 3)` (`TestEegController.cs:131-138`).

## 7. Neurofeedback

Not applicable. Test EEG does not read NF. BciCore still receives NF/CCA frames if the firmware sends them, logs them to `features.csv` and broadcasts them on the fan-out port (`acquisitionFanoutPort`, default 5006), but nothing in this game uses them. No NF channel index, no thresholds, no stall handling.

## 8. Responses & scoring

Not applicable. No responses are collected and no RT is defined. GUI button presses are not logged as events, except Reboot, which emits a firmware command (section 9).

## 9. Event markers / triggers

Test EEG **defines no trigger codes**. It never calls `BciServer.SendMarker` or `BciServer.LogTriggerSent`, and it has no UDP `TriggerSender`. A Test EEG recording can still contain non-zero markers from these sources:

| Code | Name | Source / exact moment | Transport | Notes |
|---|---|---|---|---|
| 65535 (`0xFFFF`) | Firmware reboot command | Operator presses **Reboot** on either GUI screen (`CalibrationScreen.cs:1733-1736, 1759-1762`) | `BciServer.SendMarker` → TCP CMD frame to the ESP32 | The board is meant to reboot. Whether 65535 is ever latched or echoed into `raw`/`signals`/`health` depends on the firmware. Expect a disconnect, a reconnect and a **new session folder** after it (section 10). |
| any 0–65535 | External UDP trigger | Any host sends an ASCII integer datagram to UDP **5007** while Test EEG runs | `EspTcpListener` UDP loop → `SendMarker` (`Packages/org.iisc.bcicore.server/Runtime/Networking/EspTcpListener.cs:84, 100-143`) | Port 5007 is the hard-coded default of `StartListening`. `BciServer.StartServer` does not pass it, and the launcher's "UDP trigger port" Common setting does **not** affect it. The payload is parsed as an `int` and masked with `& 0xFFFF` (`EspTcpListener.cs:128-134`), so `-1` or `65535` becomes `0xFFFF`, the **firmware reboot command**, and other out-of-range values wrap silently. |
| any | Board-echoed markers | Firmware MARKER frames (type `Marker`, 2-byte code) | ESP32 → TCP | Logged as a `health` row with `event = "marker"` and `seq` = the frame seq (`BciServer.cs:380-390`). `SeparateMarkerEchoesInHealthLog` is false here: only FingerDecoding sets it, and it restores it on dispose. |

Host-side logging of sent codes: **none**. Neither a UDP trigger nor the Reboot button writes anything to the BciCore files on the host; the only trace is a Unity `Debug.Log` (`EspTcpListener.cs:135, 551`; `CalibrationScreen.cs:1736, 1762`). A sent code appears in the data only if the firmware latches it into `raw`/`signals`/`health` or echoes a MARKER frame. When no board is connected, `SendMarker` returns `false` silently (`_stream == null`, `EspTcpListener.cs:543-547`), so the code is lost without trace.

Validation rules, legacy vs shuffled modes: not applicable.

**Analysis rule:** in a Test EEG folder, non-zero markers do not mark task events. Any marker is either a reboot command, a stray external UDP trigger, or firmware behaviour.

## 10. Output files

Test EEG writes **no task CSV, no stimframes file, no NF trace and no task metadata/settings JSON**. Its only output is the BciCore session folder. The launcher also persists its settings to PlayerPrefs (`CogLab.Games.test-eeg.v1`, `CogLab.Common.v1`), which is not a data file.

**Encoding:** every BciCore CSV (DirectCsv: `StreamWriter(..., Encoding.UTF8)`, `LogQueue.cs:85`; converted: `BinToCsvConverter.cs:149, 198, 247, 290`) and `config.txt` / `meta.json` (`File.WriteAllText(..., Encoding.UTF8)`, `DirectCsvSessionLogger.cs:416`, `CsvSessionLogger.cs:399, 504`) start with a **UTF-8 BOM** (`EF BB BF`). A naive reader sees the first column as `﻿seq` / `﻿wall_sec` / `﻿wall_clock`, and a strict JSON parser may reject `meta.json`. Read with `encoding='utf-8-sig'`.

### 10.1 Location and naming

| Item | Value |
|---|---|
| Root | `Application.persistentDataPath/BciCoreLogs/` (`BciServer.cs:190-192`; Test EEG passes no `logDir`). On Android: `/storage/emulated/0/Android/data/org.iisc.coglab.games/files/BciCoreLogs/`. The Common "Data folder" setting does **not** apply. |
| Folder / file stem | `eeg_{game}_p{participant}_s{session}_{yyyyMMdd_HHmmss}` (`DirectCsvSessionLogger.cs:102-103`), so `eeg_test-eeg_p<P>_s<S>_<local start time>`. |
| `game` | `test-eeg` from the launcher's `SetSessionIdentity(..., GameId)` (`CogLabAppController.cs:701`). `ConfigureSharedLaunch` uses the 2-argument overload and does not change it (`TestEegController.cs:42`). |
| Sanitising | `SanitizeTag` keeps letters, digits, `-` and `_`, maps spaces to `_`, and drops everything else. An empty result becomes `000` / `001` / `bci` (`DirectCsvSessionLogger.cs:105-118`). |
| Timestamp | Host local time `DateTime.Now` when the logger is constructed, which is at board connect/HELLO, **not** at game launch. |
| When created | Only after a board connects and logging is enabled. No board means no folder. `Disabled` mode means no folder. |
| Multiple folders | A new logger and folder are created on **every HELLO** (each reconnect, including after Reboot; `BciServer.cs:302-328`). On the **first** connection of a run, a `Connected`-state logger is also always created first, because no logger exists yet and `Connected` is dispatched on accept, before HELLO (`EspTcpListener.cs:204, 614`; `BciServer.cs:402-416`). It uses the default `Config` from `StartServer` (Fs 250, 32 ch, analysis ch 16, no `ch_map`), and HELLO disposes it straight away. If the two fall in different wall-clock seconds, the result is an extra **stub folder** just before the real one: header-only CSVs and a `config.txt` with `COMPLETED`, 0 samples and Transmission Mode `CONNECTING` (`DirectCsvSessionLogger.cs:337-344`). If they fall in the same second, the HELLO logger reuses the stem and overwrites the files (`FileMode.Create`). On a reconnect (for example after Reboot) the previous HELLO logger is still alive (loggers are not disposed on disconnect), so `Connected` creates nothing and only HELLO starts a new folder. A HELLO that arrives after `Finish()` disposed the logger but before `StopServer()` also creates a new folder, which in BinaryThenCsv mode is never converted. Drop stub folders with 0 samples. In BinaryThenCsv mode **only the last folder is converted** (`ConvertCurrentSessionToCsvAsync` uses `CurrentSessionDir`). Earlier folders keep only `.bin`, `config.txt` and `meta.json`. |

### 10.2 Files per logging mode (`EegLoggingMode`: 0 = BinaryThenCsv, 1 = DirectCsv, 2 = Disabled; `Assets/CogLab/Framework/IGameSession.cs:5`)

| File | DirectCsv (launcher default) | BinaryThenCsv | Written |
|---|---|---|---|
| `{stem}_config.txt` | yes | yes | At creation, after the board config (HELLO), and on dispose ("COMPLETED") |
| `{stem}_meta.json` | **no** | yes | At construction, again at `SetBoardConfig` (immediately after creation, with the HELLO or default config), and on dispose (`CsvSessionLogger.cs:142-143, 309-313, 346-347`) |
| `{stem}_raw.csv` | live, background thread | after Finish, converted from `.bin` | |
| `{stem}_signals.csv` | live | converted | |
| `{stem}_features.csv` | live | converted | |
| `{stem}_health.csv` | live | converted | |
| `{stem}_{raw,signals,features,health}.bin` | no | yes, **retained** after conversion | live |

The **column names differ between modes** for signals, features and health. Detect the schema from the header.

### 10.3 `raw.csv`, one row per RAW sample frame

| Column | Meaning | Units | Time base |
|---|---|---|---|
| `seq` | Board sample sequence number (uint32, wraps) | samples | Board sample clock (Fs from HELLO; default 250 SPS assumed by the server) |
| `raw<k>`, one per channel | Raw ADC count; `k` = physical channel = `ChMap[wire]+1`, or `wire+1` if there is no map | counts (µV = counts × `uv_per_count`, default 0.02235174) | same row |
| `marker` | Marker latched by the board on this sample (0 = none) | code | same row |

Header is the same in both modes (`DirectCsvSessionLogger.cs:66-76`, `BinToCsvConverter.cs:151-158`). In binary mode exactly 32 int32 counts are stored and the converter emits `num_ch` from `meta.json`. In DirectCsv mode a missing channel is written as `0`.

### 10.4 `signals.csv`, one row per PROC sample frame (board-filtered)

| Column (DirectCsv) | Column (Binary→CSV) | Meaning | Units / format |
|---|---|---|---|
| `seq` | `seq` | Board sample seq | samples |
| `ch<k>_uv` | `filt<k>` | Board-filtered signal, physical channel k | µV; DirectCsv `G6`, converted `F6` |
| `marker` | `marker` | Latched marker | code |

Raw and proc frames may both be present ("RAW + PROC" mode in `config.txt`). Rows with the same `seq` in the two files refer to the same sample.

### 10.5 `features.csv`, one row per NF frame, two rows per CCA frame (only if the firmware streams them)

DirectCsv header (`DirectCsvSessionLogger.cs:90-92`):
`seq,is_cca,marker,v1,v2,v3,v4,alpha_nf,ssvep_nf,alpha_left,alpha_right,ssvep_right14,ssvep_left18,a1..a16`

Binary→CSV header (`BinToCsvConverter.cs:313-325`), chosen from the **first record only**:
- NF: `seq,marker,smi_14gt18,smi_18gt14,smi_14gt18_shaped,smi_18gt14_shaped,alphaNF,ssvepNF,alphaLeft,alphaRight,ssvepRight14,ssvepLeft18,alpha1..alpha{analysis_ch}`
- CCA: `seq,marker,fb_AgtB,fb_BgtA,score_A,score_B,…` (same tail)

| Field | NF frame | CCA frame |
|---|---|---|
| v1 / v2 / v3 / v4 | smi_14gt18 / smi_18gt14 / smi_14gt18_shaped / smi_18gt14_shaped | fb_AgtB / fb_BgtA / score_A / score_B |
| alpha_nf … ssvep_left18 | always 0 (legacy columns) | always 0 |
| a1..a16 / alpha1..N | Alpha band power buffered from the ANALYSIS frame with the same seq; 0 if none | same |

`seq` is the frame's seq. Test EEG does not use these values.

**Rows per frame.** Each NF frame gives one row (`is_cca = 0`). Each CCA frame gives **two rows with the same `seq`**, because the listener dispatches `OnCcaSample` and a synthetic `NfSample` fallback in the same closure (`EspTcpListener.cs:446-464`), and both `InternalOnCca` and `InternalOnNf` write features (`BciServer.cs:350-367`):

| Order | Source | `is_cca` | v1 / v2 / v3 / v4 | alpha |
|---|---|---|---|---|
| 1st | `OnCcaSample` → `WriteCcaFeatures` | 1 | fb_AgtB / fb_BgtA / score_A / score_B | buffered alpha for that seq |
| 2nd | NfSample fallback → `WriteFeatures` | 0 | score_A / score_B / fb_AgtB / fb_BgtA | all 0 (the first row already removed the buffered alpha) |

Deduplicate by `seq`, or keep only `is_cca = 1` rows when CCA is streaming. The Binary→CSV file has **no `is_cca` column** (the byte is read but not written, `BinToCsvConverter.cs:297`), so the duplicate rows can be told apart only by the swapped v-order and zero alpha; its header is chosen from the first record, which for CCA streams is the CCA row.

**When alpha is non-zero.** ANALYSIS frames reach BciServer's alpha buffer only while `BciServer.CalibrationMode` is true (`EspTcpListener.cs:403-412`). Test EEG keeps the CalibrationScreen open for the whole run (`OnEnable` → `EnterCalibrationMode`, `CalibrationScreen.cs:201`), so `a1..a16` can be non-zero throughout a Test EEG recording, unlike task recordings where the GUI is closed. NF/CCA rows logged after `Finish()` calls `ExitCalibrationMode` (`TestEegController.cs:77`) have alpha = 0. In Binary→CSV the header lists `alpha1..alpha{analysis_ch}`, but at most 16 values are written per row (`BinToCsvConverter.cs:323, 342-346`), so header and data are misaligned if `analysis_ch > 16`.

### 10.6 `health.csv`

| DirectCsv | Binary→CSV | Meaning | Time base |
|---|---|---|---|
| `wall_sec` | `wall_clock` | Host local time of day when the row was logged. DirectCsv: integer seconds since midnight. Converted: `HH:MM:SS`. | Host `DateTime.Now`, 1 s resolution |
| `board_ms` | `board_ms` | Board uptime | ms, board clock (0 on marker rows) |
| `seq` | `seq` | HEALTH frame seq, or MARKER frame seq for marker rows | |
| `board_drops` | same | Board ring-buffer drops (cumulative) | count |
| `pc_gaps` | same | Host-detected seq gaps, raw + proc, from the last stats snapshot | count |
| `board_bad` | same | Bad SPI-status frames | count |
| `board_miss` | same | Missed DRDY | count |
| `board_dsp_max` | `board_dspmax_us` | Peak DSP burst | µs |
| `srv_bad` | same | Host-side bad frames | count |
| `free_heap` | same | Board free heap | bytes |
| `marker` | same | Latched marker in the HEALTH frame, or the echoed code for marker rows | code |
| `event` | same | `""` for HEALTH rows, `marker` for board-echoed MARKER frames. In binary mode it is truncated to 32 ASCII bytes. | |

Rows come from HEALTH frames (about 1 Hz) and MARKER frames. Test EEG adds no `trigger_sent:*` rows.

**Marker rows** (`event = "marker"`) are built from `new HealthFrame { Seq = seq, Marker = code }` (`BciServer.cs:387-388`), so `board_ms`, `board_drops`, `board_bad`, `board_miss`, `board_dsp_max` and `free_heap` are **all 0** on them; only `pc_gaps` and `srv_bad` carry real (last-snapshot) host values. Filter to `event == ""` before using any board counter. Because `WriteHealth` also overwrites the logger's last-seen board counters (`DirectCsvSessionLogger.cs:256-258`; `CsvSessionLogger.cs:285-287`), a marker row logged last before dispose makes `config.txt` report `Board Ring Drops / Board Bad SPI Frames / Board Missed DRDY` as 0. Peak DSP is a running maximum and is not affected.

### 10.7 `config.txt` / `meta.json`

`config.txt` is a human-readable report (`DirectCsvSessionLogger.cs:319-422`; same in `CsvSessionLogger`). It includes `Game : test-eeg`, Participant, Block / Session, Session Status (`ACTIVE …` / `COMPLETED`), start/end local time, duration, Fs, channel count, µV/count, FIR length, DC-blocker R, analysis channels, hemisphere maps, transmission mode, sample counts, first/last seq, expected samples, gap samples and drop rate, board drop/bad/miss counters, peak DSP, and the set of non-zero markers seen.

`meta.json` (Binary mode only) is machine-readable: `session_id, game, participant, block, start_time, end_time, duration_sec, fs, num_ch, uv_per_count, fir_len, dcr, proto_ver, montage_id, stream_mask, ch_map, analysis_ch, raw_samples, signals_samples, features_samples, health_records, total_gaps`.

No NaN convention is used: missing values are written as `0`. There is no header-mismatch or versioning logic, because every file is created fresh (`FileMode.Create`).

## 11. Settings reference

Settings appear in the launcher's **Test EEG** tab. Labels come from `Nicify(fieldName)` (`CogLabAppController.cs:223, 253`). `[Range]` is enforced at launch (`:657-659`).

| UI label | Field | Code initializer | Effective default (prefab) | Unit | Meaning |
|---|---|---|---|---|---|
| Acquisition Port | `acquisitionPort` (`TestEegController.cs:18`) | `BciServer.DefaultPort` = 5005 | 5005 (prefab line 48) | TCP port, 1–65535 | Port the ESP32 board connects to |
| Acquisition Fanout Port | `acquisitionFanoutPort` (`:19`) | `BciServer.DefaultFanoutPort` = 5006 | 5006 (line 49) | TCP port, 1–65535 | Port that broadcasts NF/CCA values to external clients (unused by Test EEG) |
| Keep Screen Awake | `keepScreenAwake` (`:20`) | true | true (line 50) | bool | Sets `Screen.sleepTimeout = NeverSleep`. The launcher restores the previous value on return. |
| *(hidden)* | `participant` (`:23`) | "000" | "000" (line 51) | string | Hidden in the tab (`CogLabAppController.cs:217`). Always overwritten by the launcher's Participant number. |
| Session | `session` (`:24`) | "001" | "001" (line 52) | string | **Shown but ineffective.** The hide-list covers only `participant`, `block`, `participantNumber` and `sessionNumber`, so this field is listed. At launch it is always overwritten by the launcher's Block number, which must be non-empty. |
| *(not serialized)* | `loggingMode` (`:26`) | DirectCsv | from the launcher's Common "Eeg Logging Mode" (`CogLabAppController.cs:28`, default DirectCsv, with a one-time forced migration at `:135-138`) | enum | Disabled: no logging. DirectCsv: live CSV. BinaryThenCsv: `.bin`, then converted. |

**Common-tab overrides:** none of the 15 shared settings in `SharedSettingsCatalog.Definitions` (`Assets/CogLab/App/SharedSettingsCatalog.cs:31-47`: displayRate, vsync, frequency1, frequency2, cueFromTrialStart, usbPort, connectTimeout, stallTimeout, triggerPort, dataFolder, frameLogging, traceInterval, fixedSeedEnabled, fixedSeed, keyboard) has an alias matching a Test EEG field (`acquisitionPort`, `acquisitionFanoutPort`, `keepScreenAwake`, `participant`, `session`; `TestEegController.cs:18-24`). Display rate, VSync, frequencies, "Show cue from trial start", USB port, connection and stall timeouts, UDP trigger port, data folder, frame logging, NF trace interval, fixed seed and keyboard therefore **do not affect** Test EEG. Only participant, session (block) and the EEG logging mode are passed in, through `ConfigureSharedLaunch`.

## 12. Timing & clock semantics

| Quantity | Clock / origin | Precision / limits |
|---|---|---|
| `seq` (raw, signals, features, health) | Board sample counter, incrementing at Fs | Sample-exact. The only intra-recording time axis: `t = (seq − seq0)/Fs`. Gaps (missing seq) are real data loss. Transport gaps are counted in `config.txt` / `meta.json`; rows dropped by the host log writer are **not** counted there (section 14, item 13). |
| `board_ms` | Board uptime (ms) | Resets on board reboot |
| `wall_sec` / `wall_clock` | Host local time of day when the health row was enqueued (main thread for HEALTH/MARKER) | 1 s, includes dispatch latency, wraps at midnight |
| Folder timestamp | Host local `DateTime.Now` at logger creation (board connect/HELLO) | 1 s |
| `start_time` / `end_time` / duration | Host local; end = logger dispose (Finish or StopServer) | start/end: 1 s in both files. Duration: `meta.json` `duration_sec` with 3 decimals (`F3`, BinaryThenCsv only, `CsvSessionLogger.cs:381`); `config.txt` "Session Duration" with 2 decimals (`F2`) plus an h/m/s breakdown (`DirectCsvSessionLogger.cs:355`, `CsvSessionLogger.cs:443`) |

There are no presentation, frame or vsync timestamps, and "dropped frame" has no meaning here. No host-monotonic (`MonotonicClock`) column exists in a Test EEG recording.

## 13. Analysis guide

1. **Identify the file set.** Select folders matching `eeg_test-eeg_p*_s*_*`. Expect several folders for one Test EEG run if the board reconnected or was rebooted, and order them by timestamp. In Binary mode, check whether `.csv` files exist next to the `.bin` files, and convert the earlier folders yourself if needed (the record formats are given in `BinToCsvConverter.cs:5-12`).
2. **Detect the schema.** Use `signals.csv` with `ch<k>_uv` for DirectCsv or `filt<k>` for Binary→CSV, `health.csv` with `wall_sec` or `wall_clock`, and `features.csv` with or without `is_cca`. Open every file with `encoding='utf-8-sig'` (UTF-8 BOM, section 10).
3. **Signal-quality metrics** (what the GUI shows):
   - Per channel: raw µV = `raw<k> × uv_per_count`, then remove DC.
   - PSD (Welch, about 2 s windows): look for 50 Hz line noise and broadband EMG.
   - Filtered-count level (`CalibrationScreen.cs:325-418`): take the most recent `n = round(window × Fs)` samples (window `_countsWindowSec`, default 5 s, clamped to 1–10 s; `n` clamped to [32, ring capacity]; `:110, 180, 343`). The source is `ProcRingBuffer` (PROC µV, i.e. `signals`) if any PROC sample has been written, otherwise the raw ring (`raw × uv_per_count`) (`:325-335`). Convert to counts with `counts = µV / uv_per_count` (`BciServer.Config.UvPerCount`). Split into `numEpochs = clamp(n/16, 1, 20)` equal sub-epochs, the last one taking the remainder (`:386-394`). Each sub-epoch RMS is computed about that sub-epoch's own mean (a per-sub-epoch standard deviation). P10/Q1/median/Q3/P90 are taken over the sorted sub-epoch RMS values with linear interpolation (`PercentileSorted`, `:423-432`). By default only channels 9–16 are shown on a 32-channel montage, all channels on 8/16-channel montages (`:220-231`). (Lines 93–104 hold only the stats struct.)
   - Flag channels whose median RMS is very high (saturated or open lead) or near 0 (shorted or dead).
4. **Data-integrity checks:**
   - `diff(seq)` should be 1 everywhere. Compare with `Missing / Gap Samples` in `config.txt`. A gap not explained by `config.txt` gaps / `pc_gaps` points to host-side writer overflow (section 14, item 13).
   - Raw row count ≈ `(last_seq − first_seq + 1)`.
   - In `health.csv`, first keep only rows with `event == ""` (marker rows carry 0 and would create spurious negative deltas). `board_drops`, `board_bad` and `board_miss` are cumulative: `diff()` of each should be 0 throughout. A positive delta marks data loss or SPI/DRDY errors in that ~1 s interval; a negative delta means a board reboot (`board_ms` also resets).
   - In `features.csv`, deduplicate CCA rows by `seq` (section 10.5).
   - `Session Status : COMPLETED`. An `ACTIVE` status means the app was killed before dispose.
   - `Game : test-eeg`.
   - Duration ≈ how long the operator kept the GUI open.
5. **Markers.** Expect `marker` = 0 everywhere. List any non-zero codes and their seq. 65535 indicates a reboot command; other codes are external UDP triggers on port 5007. Do not epoch on them as task events.
6. **Joining to task sessions.** Test EEG has no task files. To associate a check with the task session that followed it, match on `participant` + `block` in the folder name and on wall-clock order of the folder timestamps. Folders of other games start `eeg_<their game id>_…`.

## 14. Known caveats / doc discrepancies

1. **No board means no recording, silently.** "Finish EEG Test" is always enabled (`ProceedBlockReason` returns null). If no board connected, only a log line says "No EEG recorded" (`TestEegController.cs:106`), and the operator sees the overlay only briefly.
2. **The "Session" setting in the Test EEG tab does nothing.** The `session` field is not in the launcher's identity hide-list (`CogLabAppController.cs:217`), so it is shown, and `ConfigureSharedLaunch` always overwrites it (`TestEegController.cs:39`).
3. **The GUI title shows the wrong port.** It always displays `BciServer.DefaultPort` (5005) (`CalibrationScreen.cs:582-583`), even if `acquisitionPort` was changed.
4. **UDP port 5007 is live and not configurable.** Any process on the network can inject markers into a Test EEG recording. `BciCore-Documentation.md:27` says the UDP 5007 marker input was "**Removed**" and `:453` ("What Was Intentionally Not Ported") says "**Omitted**", but both are stale: the code binds it by default (`EspTcpListener.cs:84, 100-103`).
5. **Reboot and reconnect split the recording.** Each HELLO starts a new folder; the first connection of a run can also leave a 0-sample stub folder from the `Connected`-state logger (section 10.1). In BinaryThenCsv mode only the last folder is converted to CSV, and same-second recreation can overwrite files (stem resolution is 1 s).
6. **External teardown skips export.** Destroying the object outside `Finish()` (`OnDestroy`) stops the server without converting, so Binary mode leaves only `.bin`.
7. **Escape, Android Back and app pause are not handled.** On Android, backgrounding the app can stall acquisition, which shows up as seq gaps or a disconnect.
8. **Error overlay accepts only MouseUp.** There is no keyboard dismissal.
9. **Benign races.** `status` is written from a thread-pool thread (`:84`). During DirectCsv export the logger is disposed while the listener is still running, so samples arriving between Finish and `StopServer` are not logged: `ConvertCurrentSessionToCsvAsync` disposes the logger and sets `_directLogger`/`_logger` to null (`BciServer.cs:272-294`), and the null-conditional writes in `LogRaw`/`LogProc` skip them (`:95-108`); they are never enqueued. The recording effectively ends at Finish (except for a late HELLO, section 10.1).
10. **Schemas differ between logging modes.** Signals (`ch<k>_uv` vs `filt<k>`), health (`wall_sec` integer vs `wall_clock` HH:MM:SS, `board_dsp_max` vs `board_dspmax_us`) and features (`is_cca` and `v1..v4`/`a1..a16` vs named columns and `alpha1..N`) all differ. The Binary features header is chosen from the first record only.
11. **Stale docs.**
    - `BciCore-Documentation.md` describes folders as `eeg_<yyyyMMdd_HHmmss>` and Android paths under `com.featureattention.leafdirectionresponse`. The code uses `eeg_{game}_p{P}_s{S}_{ts}` under `org.iisc.coglab.games`.
    - That document also lists only the converted-CSV headers (`filt`, `wall_clock`), not the DirectCsv headers, even though DirectCsv is the launcher default.
    - `README.md` "Settings and data" still says "Both games", and `README.md:378` documents `eeg_<timestamp>/`.
    - The README snippet at line 138 shows `BinaryThenCsv` as the logging default, but the code default is DirectCsv (`CogLabAppController.cs:28`).
12. **The prefab launcher colour differs from the code default** (purple vs green). This is cosmetic.
13. **Host log writers can drop rows silently.** Each writer uses a queue bounded at 65536 items and `TryAdd(item, 0)` (`LogQueue.cs:23, 59, 77, 115`), which drops rows when the queue is full. Sequence tracking, row counts and the marker set are updated **before** the enqueue (`DirectCsvSessionLogger.cs:189-204`; `CsvSessionLogger.cs:218-234`), so writer-dropped rows do **not** appear in `config.txt` "Missing / Gap Samples" or `meta.json` `total_gaps`, yet show up as seq gaps in the CSV/`.bin`; `config.txt` "Recorded Samples" can then exceed the CSV row count. `Dispose()` waits only 3 s per writer thread (`Join(3000)`, `LogQueue.cs:68, 124`) before writing `COMPLETED` (`DirectCsvSessionLogger.cs:306-317`; `CsvSessionLogger.cs:336-347`), so the status can say COMPLETED while a CSV is still being flushed.
14. **CCA frames are logged twice in `features.csv`** (one `is_cca=1` row and one synthetic NF row with swapped v-order and zero alpha, same `seq`); see section 10.5.
15. **All output files carry a UTF-8 BOM** (section 10).

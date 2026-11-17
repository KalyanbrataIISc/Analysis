# EMG32 and CogLab Finger Decoding: source and execution walkthrough

Source snapshot: 13 October 2026. “EMG2” is interpreted as `/Users/swikriti/Documents/GitHub/EMG32`, the board project used in this task. This is documentation only: firmware, models, game behaviour, Leaf and Paddle were not changed.

Read this guide for the signal-processing meaning and execution order. Open [SourceAtlas.html](SourceAtlas.html) alongside it for the actual code, numbered lines and per-line reading notes. The atlas includes all board `src`, top-level/include EEGNet headers, PC utilities, Finger scripts/editor/tools, the relevant shared CogLab/BciCore files, and the two supplied MATLAB scripts. Its notes distinguish critical domain statements from syntax/context explanations; long expressions are interpreted as units. It does not assign a separate physiological meaning to each learned weight coefficient. The JSON source index records original paths and hashes so you can tell whether the source has changed since this snapshot.

## 1. First principles: four different jobs

A measured EEG voltage is not a finger label. A classifier must identify a pattern across electrodes and time. The experiment must know what the person was asked to do independently of the classifier.

1. **Acquisition:** ADS1299 hardware produces signed ADC counts for 32 channels at the configured rate. At 250 Hz a sample arrives every 4 ms.
2. **Preprocessing and inference:** choose model channels, convert units, re-reference/filter, assemble a window, normalize it and run trained weights. The output is a class score/probability, not a physical movement measurement.
3. **Experiment:** Unity generates balanced finger instructions and controls run/trial/ITI timing. ME means execute movement; MI means imagine movement. Selecting MI changes IDs/instructions; it does not retrain an ME classifier into an MI classifier.
4. **Presentation and recording:** Unity displays a cue and prediction, compares them, logs software timing, and sends markers to stamp EEG samples.

The cue is experimental ground truth for the instruction. A green circle means the predicted class agrees with that instruction; it does not independently prove that the participant moved that finger. The real EEGNet model does not see Unity's cue as a shortcut input.

There are two model locations:

- **Board inference:** trained parameters are compiled into EMG32 firmware. Unity receives decoded ML results.
- **Computer inference:** MATLAB/Python loads a model externally and sends explicit finger IDs to Unity over UDP. Unity still does not load its weights.

Current Unity supports receiving results; it has no `.mat`, `.pt`, `.pth`, ONNX or neural-network execution engine for Finger Decoding.

## 2. What is actually enabled in the board source?

[Config.h, line 47](</Users/swikriti/Documents/GitHub/EMG32/include/Config.h:47>) selects `ROLE_CUSTOM`. The non-EEGNet branch selects Stage 6. `EEGNET_ENABLED` defaults to 0 outside `ROLE_EEGNET`.

Consequences under this source configuration:

- ADC acquisition, rings and RAW network output exist.
- Standard filtering guarded by `STAGE >= 7` does not exist in this build.
- EEGNet `begin()` returns false and `pushSample()` does nothing through inline stubs in [EegNet.h, line 62](</Users/swikriti/Documents/GitHub/EMG32/include/EegNet.h:62>).
- A header full of model weights being present on disk does not make inference run.
- Higher-stage alpha/SSVEP/CCA functions are not automatically active.

This describes the checked-out source, not the unknown exact binary currently flashed on the board. The recent recording reports **RAW ONLY** and zero processed/features samples; it does not by itself prove whether ML frames are present.

For the supplied board EEGNet path, `ROLE_EEGNET` selects Stage 7, 250 Hz, live input by default, RAW+PROC streaming, and EEGNet compilation. `EEGNET_SOURCE_REPLAY` instead enables CSV injection on port 5007. `EEGNET_PREPROC` selects OWN versus BOARD conditioning; these are different signal transforms, not equivalent menu labels.

## 3. Board file map: what each module does

| File | Job | Runs in the finger EEGNet path? |
|---|---|---|
| `platformio.ini` | Select ESP32/ESP32-S3 build environment and PSRAM/flash options | Build time |
| `include/Config.h` | Roles, stage, pin/rate/network/filter/model configuration | Compile time plus constants at runtime |
| `src/main.cpp` | `setup`, interrupts, acquisition and processing tasks | Yes |
| `src/ADS1299.cpp`, `include/ADS1299*.h` | Chip commands, configuration/readback, SPI/GDMA and signed count decoding | Live acquisition |
| `src/Transport.cpp`, `include/Transport.hwrute` | Sample/result structs, ring buffers, overflow counters, marker latch | Yes |
| `src/Filters.cpp`, `include/Filters.h` | Standard 32-channel DC blocker/FIR/glitch conditioning | Stage 7+ when processing enabled |
| `src/EegNet.cpp`, `include/EegNet.h` | Window queue, inference worker and ML result | Only when EEGNET_ENABLED |
| `include/eegnet/eegnet_filter.h` | 8-channel CAR and causal 1–40 Hz bandpass | OWN preprocessing |
| `include/eegnet/eegnet_pipeline.h` | Gap handling, warm-up, circular window and z-score | EEGNet |
| `include/eegnet/eegnet_fast_fp32.h` | Optimized forward pass | EEGNet |
| `include/eegnet/eegnet_weights.h` | Generated learned constants | EEGNet build/inference |
| `src/Protocol.cpp`, `include/Protocol.h` | Packet encoding and command parsing | Yes |
| `src/NetLink.cpp`, `include/NetLink.h` | Wi-Fi, TCP owner, batching, reconnect, markers, health and optional replay input | Yes |
| `src/Analysis.cpp`, `include/Analysis.h` | Goertzel band powers and SSVEP analysis | Higher stages; distinct from finger EEGNet |
| `src/Neurofeedback.cpp`, `include/Neurofeedback.h` | Legacy spectral SMI feedback and median/baseline shaping | Stage 11 legacy NF selection |
| `src/CcaNeurofeedback.cpp`, `include/CcaNeurofeedback.h`, `include/CcaRefTables.h` | CCA SSVEP against sinusoidal references | Stage 11 CCA selection |
| `include/RollingMedian.h` | Shared rolling median implementation | Spectral/CCA paths, not Unity probability smoothing |
| `src/SdLogger.cpp`, `include/SdLogger.h` | Optional queued binary SD recording | Only LOG_SD/LOG_BOTH |
| `include/core0/BuildInfo.h` | Supporting build metadata | Not trained model parameters |

PC utilities are not executed inside the board. `eeg_tcp_server.py` is an alternative receiver/logger; `bci_gui_v2.py` a PC telemetry interface; `eegnet_csv_streamer.py` a replay sender; `eegnet_score.py` a scorer; `bin_to_csv.py` a converter. `make_testdata.py` creates replay data; `make_cca_tables.py` creates CCA references; `validate_cca.py` validates that separate algorithm. `nf_tcp_server.py` and `relay_csv_to_board.py` support other networking/replay paths. None of those names means it trains or exports the current EEGNet weights.

## 4. Board startup: exact causal order

[main.cpp, line 428](</Users/swikriti/Documents/GitHub/EMG32/src/main.cpp:428>) is called once after the Arduino runtime starts.

For live Stage 6+:

1. `Serial.begin`, short delay and banner.
2. Initialize/reset ADS driver for live input.
3. `transportInit()` allocates processed-ring storage in PSRAM. Missing PSRAM/allocation failure stops safely; tasks cannot use an unallocated ring.
4. For each chip: verify chip ID, configure registers and check readback; select normal/test/shorted input. The current source prints failed-chip warnings but has its all-chips-fatal refusal commented out. A network connection is therefore not proof that all electrodes/chips are good.
5. `EegNet::begin()` initializes the inference module, or runs a disabled stub.
6. Initialize board filter/analysis/NF modules that compile for this stage.
7. Start `procTask` on Core 1, priority 20.
8. Start SD logging if configured.
9. `NetLink::begin()` initializes Wi-Fi/networking. Live startup waits for the Unity/PC TCP server.
10. Start `acqTask` on Core 0, priority 24. Start ADS acquisition, then attach the DRDY interrupt only after its task handle is valid.
11. The normal Arduino `loop()` mainly yields. Real work now runs in FreeRTOS tasks.

Task creation is not a promise that every function then executes in a fixed serial sequence. A scheduler runs tasks according to readiness and priority.

## 5. One raw EEG sample, line by line through acquisition

[main.cpp, line 78](</Users/swikriti/Documents/GitHub/EMG32/src/main.cpp:78>):

- `IRAM_ATTR` places the interrupt handler in instruction RAM so it can execute predictably.
- `BaseType_t woken = pdFALSE` starts with no higher-priority task marked ready.
- `vTaskNotifyGiveFromISR(acqTaskHandle, &woken)` increments the acquisition task's notification count.
- `portYIELD_FROM_ISR(woken)` permits the scheduler to switch to the woken task.
- No filtering, classifier or TCP operation runs in this ISR.

[main.cpp, line 371](</Users/swikriti/Documents/GitHub/EMG32/src/main.cpp:371>):

- `for (;;)` means run forever, sleeping when there is no work.
- `ulTaskNotifyTake(pdTRUE, portMAX_DELAY)` sleeps until DRDY notification and clears the accumulated count.
- Counts greater than one increase `missCount`; coalesced notifications represent missed acquisition opportunities. This is distinct from network sequence gaps.
- `ads.queueAllChips()` starts SPI DMA reads for the chips.
- `ads.collectAllChips(raw)` waits/yields for completion and decodes counts/status into the 32-element array.
- `seqCounter++` assigns a logical sample sequence even if this acquisition is later rejected.
- Bad status increases `badCount` and skips the sample; sequence discontinuity then exposes the discarded frame.
- The `RawSample` receives sequence, a snapshot of `eventMarker`, and channel counts via `memcpy`.
- Marker timeout clears the shared latch after about 200 ms. The already-copied sample keeps its marker.
- Optional SD logging and `rawPush(s)` hand the sample to other modules.
- Serial diagnostics report counters; they are not trial triggers.

ADS driver lines perform register and transaction operations, not model logic. Signed 24-bit ADC values are represented as signed 32-bit integers. Voltage conversion uses `UV_PER_COUNT`; changing gain/reference requires the scaling contract to remain consistent with the HELLO packet and training input units.

## 6. Processing and inference are decoupled

[main.cpp, line 299](</Users/swikriti/Documents/GitHub/EMG32/src/main.cpp:299>) consumes `rawRing` on Core 1:

1. `rawPop(raw)` gets a frame; no frame means yield briefly.
2. Copy sequence, marker and counts into `Sample`.
3. When processing is enabled and Stage 7+ exists, convert counts to µV and call `filt.conditionFrame`.
4. Higher stages can calculate analysis and spectral/CCA feedback; these are separate from EEGNet.
5. `EegNet::pushSample(raw.ch, processingEnabled ? s.filt : nullptr, raw.seq)` feeds the model front end. OWN ignores the provided filtered pointer; BOARD needs it.
6. Queue the sample to `procRing` only while network transmission can drain it. Filtering/inference state may continue while disconnected.

[Filters.cpp, line 38](</Users/swikriti/Documents/GitHub/EMG32/src/Filters.cpp:38>) computes the standard board filter:

```text
DC output = x[n] - x[n-1] + R × previous_DC_output
FIR output = sum(tap[i] × buffered_DC_sample[i])
```

`conditionFrame()` clamps extreme raw values, rejects abrupt single-sample glitches by substituting previous accepted values, filters, clamps output and updates its glitch history. This FIR is 61 taps at the fixed design rate. Its nominal group delay is 30 samples = 120 ms at 250 Hz. Its 2–28 Hz band differs from EEGNet OWN's 1–40 Hz band.

## 7. EEGNet input: eight channels, not all 32

[Config.h, line 621](</Users/swikriti/Documents/GitHub/EMG32/include/Config.h:621>) starts at zero-based 8: physical channels **9–16**, in that exact row order. Each row must represent the electrode/channel used during training.

[EegNet.cpp, line 119](</Users/swikriti/Documents/GitHub/EMG32/src/EegNet.cpp:119>):

- `if (!s_ok) return` prevents use before successful initialization.
- `uv[N_EEG_CH]` is the eight-value model input for this instant.
- OWN selects raw counts, scales to µV and clamps extreme values before IIR state can overflow.
- BOARD selects the corresponding already-conditioned values; null filtered input means skip.
- `s_pipe.step`/`stepFiltered` returns false until a complete eligible window is ready.
- A free-slot queue supplies one prepared-window storage slot without blocking acquisition/processing. No free slot means increment dropped-window count.
- Copy/normalize the current window into that slot and record its newest sequence.
- Queue the slot index for inference; do not run the full network inline in `procTask`.

In [eegnet_pipeline.h, line 72](</Users/swikriti/Documents/GitHub/EMG32/include/eegnet/eegnet_pipeline.h:72>) OWN subtracts the mean across the eight channels (CAR) and applies the causal filter in `eegnet_filter.h`. BOARD applies only optional CAR after the board's filter. Both then store values in the same circular window.

`sequence()` checks continuity. Small holes invalidate/refill the window without necessarily resetting filter history. Repeated/backward sequence or sufficiently large holes restart filter state/warm-up. The zero-based input sequence is not an absolute wall clock.

`push()` increments the circular position, total and contiguous sample counts. It requires:

```text
at least 250 contiguous samples
warm-up completed
hop boundary reached (25 samples)
```

OWN warm-up defaults to 1,000 samples (4 seconds); BOARD to 7,500 samples (30 seconds). Every 25 new samples schedules a prediction: 100 ms at 250 Hz.

`emit()` copies oldest-to-newest samples, calculates each channel's mean and population standard deviation, then emits `(sample - mean) / standard_deviation`. Zero deviation is replaced by 1 to avoid division by zero.

This is **free-running**. Board markers are acquired/logged, but EEGNet does not reset its filter/window at each trial and does not restrict its input to post-cue EEG. Unity's feedback delay is not equivalent to MATLAB's fully post-cue-window test.

## 8. The neural network forward pass

[eegnet_fast_fp32.h, line 95](</Users/swikriti/Documents/GitHub/EMG32/include/eegnet/eegnet_fast_fp32.h:95>) reads generated weights.

Current shape:

```text
Input                 8 × 250
F1 temporal filters   16
Depth multiplier D    2
Spatial feature maps  32
F2 output maps        64
First kernel          32 samples
Second kernel         16 samples
Pooling               4, then 8
Dense input           64 × 7 = 448 values
Classes               2
```

Block order:

1. Spatial mix across eight channels with the depthwise weights.
2. Fused temporal convolution, bias, ELU and average pooling by 4.
3. Depthwise/separable 16-tap temporal convolution.
4. Pointwise feature mixing, ELU and average pooling by 8.
5. Channel-major flatten and dense weighted sum into class logits.

The spatial operation can be moved before the temporal linear operation because the exported BN layers are folded and there is no intervening nonlinearity in that fused portion. Activation and pooling cannot be moved arbitrarily. The `static_assert` statements enforce the hard-unrolled assumptions: eight channels, 32/16 kernels, first pool 4, compatible second pooling and even F2.

`eegfast_init()` precomputes a fused bias. `ef_elu()` approximates the exponential on the negative branch for speed. Arrays `ef_yp`, `ef_p1`, `ef_s1`, `ef_p2` are intermediate buffers, not model files. Pointer arithmetic indexes contiguous tensor storage; wrong tensor flatten/layout silently changes the model's meaning.

Batch normalization folding means the engine expects transformed weights. A typical channel-wise fold is:

```text
scale = gamma / sqrt(running_variance + epsilon)
folded_weight = scale × original_weight
folded_bias = scale × (original_bias - running_mean) + beta
```

Exact folding targets and tensor layout must match the exported architecture. Do not copy raw checkpoint tensors into these arrays without a compatible exporter.

## 9. Inference task: every important statement

[EegNet.cpp, line 48](</Users/swikriti/Documents/GitHub/EMG32/src/EegNet.cpp:48>) is a separate lower-priority Core 1 worker:

```cpp
uint8_t idx;
```

A small integer identifies a PSRAM window slot; it does not identify a finger.

```cpp
xQueueReceive(s_filledQ, &idx, portMAX_DELAY)
```

Wait until preprocessing has produced a window. It blocks the inference worker, not the high-priority acquisition task.

```cpp
Slot& sl = s_slots[idx];
float logits[EEGNET_NCLASS], prob[EEGNET_NCLASS];
```

Reference that slot without duplicating its whole window; allocate output score/probability arrays.

```cpp
const uint32_t t0 = micros();
eegfast_forward(sl.win, logits);
const uint32_t us = micros() - t0;
const int pred = softmaxArgmax(logits, prob);
```

Measure **forward-pass** time, run the network, then convert logits to probabilities/select the class. This latency excludes window collection, preprocessing, queue wait, transmission and rendering.

Stable softmax subtracts the maximum score before exponentiation, divides each numerator by their sum, then selects the largest probability.

```cpp
r.seq = sl.seq;
r.predictedClass = (uint8_t)pred;
r.confidence = prob[pred];
r.latencyMs = us / 1000.0f;
```

Attach the newest EEG sample sequence, zero-based class, its softmax probability and forward latency. **All logits and all probabilities are not transmitted.**

```cpp
if (!mlPush(r)) s_mlDrops++;
xQueueSend(s_freeQ, &idx, 0);
```

Enqueue the result for networking, count dropped output if necessary, and release the window slot for reuse. Remaining lines maintain timing/drop diagnostics.

`begin()` allocates slots/queues, fills the free-slot queue, initializes fused biases and pipeline state, creates the inference task and sets `s_ok`. Any allocation/task failure leaves inference disabled while the rest of the board can continue.

## 10. From the board to Unity

[Protocol.cpp, line 4](</Users/swikriti/Documents/GitHub/EMG32/src/Protocol.cpp:4>) writes nine header bytes:

```text
AA 55 | frame type (1 byte) | sequence (4 bytes LE) | payload length (2 bytes LE)
```

RAW payload contains 32 signed count values plus marker. PROC contains filtered floats plus marker. HELLO announces rate/channels/scaling/filter identity/montage. HEALTH reports board counters. ML type 0x09 currently contains nine payload bytes:

```text
predicted class: uint8
confidence: float32
forward latency ms: float32
```

ML header sequence is newest EEG sample sequence. By contrast, the board marker echo currently uses the code itself as header sequence; it is **not** a reliable EEG alignment timestamp.

`NetLink::txTask` is the sole owner of the TCP socket. It reconnects, announces HELLO, polls incoming commands, drains result queues including ML, emits health about once per second, and batches raw/proc samples. No other core should write this `WiFiClient` directly.

Streaming RAW and running a model are distinct choices. Internal filtering can run while PROC transmission is disabled. Conversely receiving RAW/FFT traces in Unity is not proof that a classifier is producing predictions.

## 11. Trigger path and why spacing was necessary

```text
Unity Event(code > 0)
→ FingerAcquisition.Send
→ BciServer.LogTriggerSent and SendMarker
→ TCP CMD packet
→ board pollIncoming
→ eventMarker = code; markerTimestamp = millis()
→ next acquired raw samples carry code
→ board echo packet comes back
```

The board has one marker latch, not a marker FIFO for raw sample stamping. A second command can replace the first before acquisition records it. At 250 Hz a frame is 4 ms, but TCP command buffering can make two host commands appear together. The latch holds a nonzero marker for about 200 ms; count its rising transition, not every marked row.

Finger controller now uses a >=300 ms guard from run start 10 to first cue, full final ITI from last 60 to run end 11, and a hold before stopping/advancing. Trial cue duration remains measured from the first visible cue. Echo labels 1010/1021/etc exist only in Finger health logs; RAW/PROC retain original hardware markers.

Both online and offline send one ME cue 21–24 (MI 31–34) at trial start and 60 at trial end. Flash, predictions and ITI use software event code 0, not hardware triggers. Run boundaries are 10/11.

## 12. CogLab module-by-module execution

[GameModule.cs, line 41](</Users/swikriti/Documents/GitHub/CogLab-Games/Assets/CogLab/Framework/GameModule.cs:41>) validates a registration, creates an inactive runtime object, adds the template controller type, copies serialized configuration with `JsonUtility`, assigns identity/logging/return callback, creates a session camera copy and activates the controller. The disabled scene controller remains a settings template.

[FingerExperimentController.cs, line 150](</Users/swikriti/Documents/GitHub/CogLab-Games/Assets/Games/FingerDecoding/Scripts/FingerExperimentController.cs:150>) runs once on activation: capture orientation, constrain landscape, ensure a background camera, create Canvas, assign Begin/Exit callbacks and build the settings view. A visual demo is a separate no-recording path.

`SelectedFingers()` returns checked classes. `ApplyClassPreset()` changes included fingers and adjusts the total to retain a per-class count. `ValidateSettings()` prevents invalid counts/times/ports, invalid smoothing/scale and incompatible direct EMG32 class selections. The current direct EMG32 online model permits two mapped classes only.

`BeginExperiment()` is the session initializer:

1. Prevent duplicate start or restart during export; resume a between-run pause when requested.
2. Validate, capture settings into private session variables and lock configuration.
3. Capture marker gap, hand scale, cue pattern, mode and acquisition method.
4. Decide whether to smooth; default already-smoothed external UDP/BciCoreMl skips Unity accumulation.
5. Capture selected durations. Prediction interval is clamped to >=0.1 s.
6. Capture Flash on/off or SinglePulse length. Online feedback cannot start before the first configured on-period has completed; default start is 1 s.
7. Generate balanced randomized runs. Fixed seed reproduces the same sequence; balance does not prohibit consecutive same-finger trials.
8. Create prediction receiver. Simulation bypasses real acquisition. Other sources start BciCore or UsbBiosemi acquisition.
9. Real BciCore opens shared calibration/EEG/FFT; Proceed requires a board connection and starts the session.

`OpenSignalChecker()` is a separate preflight: real BciCore telemetry, no trial and no recording. Closing it restores settings and closes its connection. It is not a substitute for starting a real recording session.

`StartSession()` creates task CSV, settings JSON and plan CSV, then `BeginRun()`. The task plan is an authoritative record of instructions; the classifier can disagree.

`Update()` executes once per Unity frame, checks Escape/disconnects/errors, handles demo mode, then calls `AdvanceSession(now)`.

The state machine is:

```text
Settings → Calibration → RunLeadIn → Trial → ITI → Trial ...
                                      final ITI → RunEndHold → BetweenRuns → RunLeadIn
                                                             or Complete/export
```

- `BeginRun`: trigger 10, blank lead-in deadline.
- `BeginTrial`: reset smoothing/queue, set cue/deadlines, show hand and issue one cue trigger.
- `TickTrial`: trial end takes precedence over cue/prediction updates. At deadline clear display, issue 60, start ITI and flush logs.
- `AdvanceSession`: after nonfinal ITI start the next trial; after final ITI send 11, hold, then pause or complete.
- `ResumeRun`: log software pause end and begin next run.
- `Exit`/abort coroutine: blank immediately, separate stop/run-abort codes and hold before closing acquisition.
- `Finish`: stop/dispose receiver/acquisition/logger, convert BciCore binaries when enabled, unlock settings after export, return or allow a new unique session.
- `SetPredictionSource`: retains the chosen source in Finger module saved settings. It changes only Finger settings.

## 13. Unity predictions, smoothing and display: exact order

[EspTcpListener.cs, line 488](</Users/swikriti/Documents/GitHub/CogLab-Games/Packages/org.iisc.bcicore.server/Runtime/Networking/EspTcpListener.cs:488>) verifies the nine-byte ML payload, parses it and queues callback dispatch onto the Unity main thread. `BciServer.OnMlResult` then notifies `FingerPredictions`.

For EMG32, `TryMapEmg32()` accepts class 0/1, validates distinct mapped fingers, and converts to ME/MI IDs. `OnEmg32Ml()` validates finite confidence and queues the result with sequence and latency source metadata. Default mapping is class 0 Thumb, class 1 Pinky, but training labels must establish this; names in a menu do not prove it.

For `BciCoreMl`, classes must already be explicit finger IDs. For UDP, the parser accepts `id[,confidence[,source_stamp]]`, checks IDs and finite [0,1] confidence, rejects oversized packets and runs a background receiver. `ConcurrentQueue` makes reception/presentation thread-safe and is bounded to 4,096 items.

During each trial, `TickTrial()` drains arrivals, rejects wrong task/classes or receipt times outside the trial and records valid arrivals. It retains the newest eligible result. At the next presentation tick it consumes that pending result, not every stale queued result. No new packet means the current dot remains.

Smoothing in [FingerFeedbackSmoother.cs, line 11](</Users/swikriti/Documents/GitHub/CogLab-Games/Assets/Games/FingerDecoding/Scripts/FingerFeedbackSmoother.cs:11>):

```text
If two classes and genuine winning softmax confidence:
  evidence[predicted] = confidence
  evidence[other] = 1 - confidence
Otherwise:
  evidence[predicted] = 1; others = 0   (label votes)
For each selected class: h = alpha*h + evidence
Winner = largest h (stable selected order on an exact tie)
Displayed confidence = h[winner] / sum(h)
```

Default alpha=.90. History resets at every trial, not every flash. Only the latest pending prediction per tick contributes; this is not necessarily identical to MATLAB when input rates/drop behaviour differ. Three/four-class one-hot voting is not full softmax-vector smoothing. Already-smoothed MATLAB predictions must bypass Unity smoothing. Current board code has no probability-history smoothing, so EMG32 raw output is smoothed once in Unity.

`SetPrediction(decoded, decoded==cue)` uses cue only for colour: green for agreement, red for disagreement. `FingerCanvasView` positions one existing marker above the decoded fingertip, scaled with the hand. `SetCue` changes masks only, so turning the blue cue off cannot erase the feedback dot.

`nextPrediction = now + interval` prevents catch-up bursts. Visible dot changes can be less frequent than updates when the winning class stays the same. Rendering/frame cadence still quantizes event presentation.

## 14. Real-time ordering: concurrent, not one sequential script

Board Core 0 high-priority acquisition responds to DRDY. Board Core 1 processing consumes samples and fills model windows. Core 1 low-priority inference consumes complete windows. Core 0 networking transmits queued results. Unity networking receives frames on worker threads, dispatches callbacks to its main thread, and `Update()` presents at its own deadlines.

```text
Every ~4 ms, live acquisition:
DRDY → ISR → acqTask → rawRing → procTask → model front end / procRing

After warm-up, every 25 samples (~100 ms):
complete model window → filled slot → eegnetTask → logits → softmax
→ mlring → txTask → TCP → Unity parser → main-thread callback
→ prediction queue → latest eligible result → optional smoothing → dot
```

Networking and inference may be delayed by queues/scheduling. Model forward latency is not end-to-end latency. Unity arrival time, board newest-sample sequence, trial scheduled time, actual presentation time and wall clock describe different points in this chain.

Example online SinglePulse trial relative to cue onset:

```text
0.0 s: finger cue/trigger once
0–1 s: blue finger, no default prediction presentation
1–3 s: plain hand with prediction updates no faster than 100 ms
3.0 s: trigger60 and blank display
3–5 s: ITI
5.0 s: next cue, or11 if final trial
```

Flash instead alternates blue/plain every .5 s throughout the same 3-second trial while retaining eligible feedback. Offline defaults to 5 seconds, Flash or SinglePulse, no prediction display. Run lead-in/hold add boundary time outside trials; pause defaults to 20 seconds and can be skipped by tap.

## 15. Applying a trained or fine-tuned model: which file changes?

### A. Keep the current board architecture; replace only trained parameters

The deployment target is [eegnet_weights.h, line 7](</Users/swikriti/Documents/GitHub/EMG32/include/eegnet/eegnet_weights.h:7>). Its header identifies source checkpoint `ME_sess1_2class_Orig_P04_eegnet_ema_full_runs1to8_pt.zip` and says BatchNorm is folded.

For a fine-tuned checkpoint with **the same architecture**:

1. Save/export the final trained checkpoint in evaluation mode with its running BatchNorm statistics.
2. Use the original compatible exporter (or implement/validate an equivalent) to fold normalization and write matching C arrays/macros.
3. Replace the **whole generated `include/eegnet/eegnet_weights.h`** while keeping a versioned original/model hash and recording the new training/model metadata.
4. Confirm channel order, units, causal filtering, z-score, 250 Hz and 250-sample window match training.
5. Select `ROLE_EEGNET` and the appropriate preprocessing in Config.h. Rebuild and flash the **board firmware**, not just the Unity APK.
6. Compare exported PC versus board logits on the same preprocessed windows; test replay and live signals before using it experimentally.
7. In Unity select BciCore + Emg32EegNet, two matching fingers and the verified class mapping.

The header references `export_eegnet_weights.py`, but that exporter and the originating checkpoint were not found in this EMG32 checkout. Do not use an invented command for an absent script. Obtain the exporter/training definitions from the model/hardware lab. The separate EEGNet checkout contains no visible training/inference files in this inspection.

No Unity source or APK change is needed for a compatible two-class weight swap that preserves the current packet format. Unity Inspector class mapping may need changing if training labels change. Changing the mapping relabels output; it does not improve/retrain a model.

### B. Change channels, sample rate, window, layers or preprocessing

Replacing the header alone is unsafe. Audit and potentially change:

- `eegnet_fast_fp32.h`: hard-unrolled channels/kernel/pool architecture and tensor indexing.
- `eegnet_filter.h`: channel-state dimensions and coefficients for a changed rate/band.
- `eegnet_pipeline.h`: window, normalization, gap/warm-up and hop contract.
- `Config.h`: channel map, rate, role, source, preprocessing and task/memory allocation.
- `EegNet.cpp`: arrays/slots/queue memory, timing, output classes.
- Exporter and parity tests: tensor layout, padding, batchnorm fold, flatten order and evaluation mode.

Some dimensions use macros but static assertions and eight-channel unrolled pointers are intentional constraints. Simply setting EEGNET_CHANS=32/128 cannot turn this engine into a compatible different-channel model.

### C. Apply your existing Biosemi MAT models on the computer

[run_online_prediction.m, line 116](</Users/swikriti/Downloads/run_online_prediction.m:116>) chooses `WEIGHT_FILE`, then `model = load(WEIGHT_FILE)`. Change the selected filename/path to a compatible fine-tuned MAT file, keep the correct nClass, and run inference externally. If architecture changes, update `eegnet_inference.m` and preprocessing accordingly.

The supplied P10 MAT files have 128-channel spatial weight tensors and 2/3-class dense output. The current board model uses eight channels and two classes. They are not interchangeable. Verify the actual output of your external preprocessing step; the MATLAB driver requests 32 input channels, and the preprocessing implementation was not supplied here, so its compatibility with a 128-channel model cannot be assumed.

MATLAB currently writes `ft_shared.txt`; Finger Unity does not read it directly. Add a sender/bridge that maps MATLAB cue values 1/2/4 to explicit IDs 21/22/24 for ME, or 31/32/34 for MI, and sends UDP to the tablet. Keep External Predictions Already Smoothed true because the MATLAB script already smooths probabilities. USB connection is for installation/debugging, not the classifier's Wi-Fi transport.

### D. Extend the board/Unity to full logits or more classes

Current ML payload exposes only winner/confidence. To transmit full logits, coordinate all ends:

- Board `MlResult` struct in Transport.h.
- EegNet.cpp retains/copies the logits into that result.
- Protocol.h/Protocol.cpp define a versioned compatible payload.
- NetLink transmits it.
- Unity FrameProtocol/BciEvents/EspTcpListener parse and validate it.
- FingerPredictions carries a vector/class mapping.
- FingerFeedbackSmoother applies softmax then probability history for all selected classes.
- Update packet tests and recordings to retain raw vector/provenance.

Unity's current `Emg32EegNet` mapping accepts only class 0/1. Increasing board output classes alone will make extra labels fail mapping. The dense engine loops over EEGNET_NCLASS, but the UI adapter/protocol must also be updated. For unchanged two-class softmax, Unity already reconstructs the complete vector from winner/confidence; logits are not required merely to smooth that binary case.

## 16. Practical model acceptance checklist

Record these facts with each deployed model:

- Training task ME versus MI, participant/session and class labels.
- Physical electrode names/order, reference, count-to-µV scaling.
- Sampling rate, input length, hop and preprocessing order.
- Causal versus zero-phase filter behaviour and filter-state initialization.
- Per-window normalization and padding/flatten conventions.
- Architecture and class count; exported weights hash.
- Numerical parity against the training framework in evaluation mode.
- Board measured inference latency, dropped windows/results and connection stability.
- Which component smooths predictions (exactly one intended stage).
- Live raw marker capture and independent display timing where required by the study.

A model trained on a different input transform can compile and emit confident predictions while still being scientifically wrong. Correct class confidence does not establish cross-task or cross-participant validity.

## 17. Reading language syntax in the atlas

`#include` imports C++ declarations before compilation. `#if` removes or includes a block at compile time. `static` at file scope gives module-local storage; static arrays live beyond a function call. `const` disallows mutation through that declaration. `volatile` signals externally changing shared state but is not a substitute for full thread synchronization. `&` can mean reference/address; `*` can mean pointer/dereference/multiplication by context. `memcpy` copies bytes, not semantic model tensors.

`for (;;)` is an infinite loop. Queue blocking yields the task to the scheduler. A FreeRTOS priority/core number describes scheduling; it is not a neural-network layer number. ISR-safe APIs must be used in interrupts.

C# `using` imports namespaces; `readonly` restricts field reassignment; `?.` calls only if nonnull; `=>` defines an expression body/callback. `Action` is an event/callback delegate. `+=` subscribes to an event; `-=` unsubscribes. `ConcurrentQueue` is the cross-thread prediction handoff. `yield return` suspends a Unity coroutine. A Inspector `[Tooltip]`, `[Min]` or `[Range]` describes UI/validation metadata, not EEG processing.

Blank lines/braces/comments have structural/documentation meanings but no independent physiological operation. Many compact C# lines contain multiple statements; read every semicolon-delimited operation. The atlas keeps original line numbers instead of changing production files to add teaching comments.

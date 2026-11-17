%% LEAF_SSVEP_ANALYSIS  SSVEP / CCA neurofeedback analysis for one day of Leaf-game blocks.
%
% To analyse another day: change cfg.dataDir below and run. The day folder must contain
%   eeg_<yyyymmdd_HHMMSS>/   BciCore logs (…_signals.csv with ch*_uv + marker, …_config.txt)
%   gameData/                p<P>_b<B>_leaves_trialdata.csv (one per block)
% EEG folders are matched to game blocks by their trial-start marker sequences, so folder
% order and names do not matter.
%
% Figures (PNG + FIG), per-trial table and a results .mat are written to cfg.outDir.
%
% Plots
%   1. MT power spectrum of the EEG over the whole session, mean ± SEM across blocks
%   2. MT power spectrum of the dynamic-CCA-projected time series (U_f for every SSVEP f)
%   3. CCA score, target vs non-target frequency, locked to colour reveal (± SEM across trials)
%   4. SSVEP power of the dynamic-CCA projection, target vs non-target, locked to colour reveal
%   5. Reaction time (colour reveal -> response) per block (± SEM across trials)
%   6. Time from trial start to colour reveal per block, revealed trials (± SEM across trials)
%
% Dynamic CCA follows matlab/RT_acquisition_CCA.m: every cfg.cca.hopSec, fit hardware-friendly
% CCA (power iteration) between the last cfg.cca.windowSec of EEG (all channels) and sin/cos
% references of each SSVEP frequency. The score is the canonical correlation; the projection is
% the EEG multiplied by the X-side canonical weights (unit norm). The weights fitted at each
% update project the newly arrived hop of samples, giving a continuous causal projected series.

clear; close all; clc;

%% =============================== USER SETTINGS ===============================
here        = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(here));   % scripts/leaf -> project root

% ---- Paths (change cfg.dataDir for another day) ----
cfg.dataDir     = fullfile(projectRoot, 'data', '2026-11-16');
cfg.eegPattern  = 'eeg_*';                         % EEG session folders inside dataDir
cfg.gameDir     = fullfile(cfg.dataDir, 'gameData');
cfg.gamePattern = '*_leaves_trialdata.csv';
[~, dayTag]     = fileparts(cfg.dataDir);
cfg.outDir      = fullfile(projectRoot, 'plots', [dayTag '_leaf_matlab']);
cfg.chronuxDir  = fullfile(projectRoot, 'Toolbox', 'chronux_2_12', 'chronux_2_12', 'spectral_analysis');

% ---- Recording ----
cfg.fsDefault       = 2000;           % used only if the config file has no sampling rate
cfg.channelPattern  = '^ch\d+_uv$';  % EEG columns in _signals.csv
cfg.channels        = [];            % indices into the matched columns; [] = all
cfg.minMarkerSamples = 1;            % ignore marker runs shorter than this (real markers can latch for 1 sample)
cfg.mergeSameCodeSec = 0.4;          % same code re-appearing within this time = one (split) marker

% ---- Event codes (Leaf game, shuffle mode; 20/21 = legacy starts) ----
cfg.codes.start    = [31 32 33 34 20 21];
cfg.codes.reveal   = 50;
cfg.codes.response = 40;
cfg.codes.stop     = 30;

% ---- Preprocessing (applied to each whole recording before anything else) ----
cfg.pre.highpassHz  = 1;      % Butterworth high-pass (zero phase); [] to skip
cfg.pre.lowpassHz   = 45;     % Butterworth low-pass; [] to skip
cfg.pre.filterOrder = 4;
cfg.pre.notchHz     = 50;     % line-noise band-stop centre; [] to skip
cfg.pre.notchWidthHz = 2;     % total width of the band-stop
cfg.pre.car         = true;   % common-average re-reference (RT script: demean_reref)

% ---- Session span used for the spectra (plots 1-2) ----
cfg.sessionSpan = 'trials';   % 'trials' = first trial start to last trial stop; 'file' = whole file

% ---- Multitaper spectra (chronux) ----
cfg.epochLenSec   = 5;        % epoch length for the session spectra
cfg.artifactUv    = 200;      % drop epochs whose max |preprocessed EEG| exceeds this (Inf = keep all)
cfg.mt.tapers     = [1 1];    % [TW K]
cfg.mt.pad        = 0;
cfg.mt.fpass      = [1 45];

% ---- SSVEP frequencies ----
cfg.ssvepHz = [];             % [] = taken from the game files (FrequencyC1Hz / FrequencyC2Hz)

% ---- Dynamic CCA (as in RT_acquisition_CCA.m) ----
cfg.cca.windowSec   = 1;      % analysis window
cfg.cca.hopSec      = 0.1;    % update interval (game NF ~100 ms)
cfg.cca.nHarmonics  = 1;      % sin/cos pairs per frequency
cfg.cca.nPowerIters = 8;      % power iterations (RT script uses 8)
cfg.cca.regX        = 1e-6;   % ridge on Cxx, relative to mean channel power (needed: CAR makes Cxx singular)
cfg.cca.regY        = 1e-8;   % ridge on Cyy
cfg.cca.powerInDb   = true;   % plot 4 in dB (10*log10 of µV²/Hz)

% ---- Reveal-locked analysis (plots 3-4) ----
cfg.lock.windowSec = [-6 3];  % time around colour reveal (s)
cfg.lock.maskMode  = 'endpoint'; % 'endpoint': keep updates whose time lies inside the trial
                                 % 'window'  : keep only updates whose whole CCA window is inside
                                 % 'none'    : keep everything (ITI/next trial can leak in)
cfg.lock.minTrials = 10;      % blank time points with fewer trials than this (trials end ~RT+1 s after reveal)

% ---- Trial selection ----
cfg.rtTrials     = 'responded';  % plot 5: 'responded' (all responses) or 'correct'
cfg.revealTrials = 'revealed';   % plot 6: 'revealed' (reached colour reveal) or 'correct'

% ---- Plot appearance ----
cfg.plot.specFreqLim  = [5 30];  % x-limits of the spectra (Hz)
cfg.plot.specYLim     = [];      % [] = automatic
cfg.plot.specInDb     = true;
cfg.plot.scoreYLim    = [];      % plot 3
cfg.plot.powerYLim    = [];      % plot 4
cfg.plot.behavYLimRT  = [];      % plot 5
cfg.plot.behavYLimRev = [];      % plot 6
cfg.plot.showTrials   = true;    % scatter individual trials on plots 5-6
cfg.plot.ruleNames    = {'Pointing', 'Moving'};          % cue C1 = Pointing, C2 = Moving (plots 5-6)
cfg.plot.ruleColors   = [0.00 0.45 0.70; 0.84 0.37 0.00]; % Pointing blue, Moving orange
cfg.plot.ruleOffset   = 0.12;    % horizontal offset of the two rules within a block
cfg.plot.trialJitter  = 0.08;    % horizontal jitter of single-trial points
cfg.plot.colTarget    = [0.84 0.37 0.00];
cfg.plot.colNonTarget = [0.00 0.45 0.70];
cfg.plot.colEEG       = [0.20 0.20 0.20];
cfg.plot.freqColors   = [0.00 0.45 0.70; 0.84 0.37 0.00; 0.00 0.62 0.45; 0.80 0.47 0.74];
cfg.plot.alpha        = 0.25;    % SEM shading
cfg.plot.theme        = 'light';  % 'light' or 'dark' (R2025a+ follows the desktop theme otherwise)
cfg.plot.formats      = {'png', 'fig'};
cfg.plot.dpi          = 600;
%% =============================================================================

if ~exist(cfg.chronuxDir, 'dir'), error('Chronux not found at %s', cfg.chronuxDir); end
addpath(genpath(cfg.chronuxDir));
if ~exist(cfg.outDir, 'dir'), mkdir(cfg.outDir); end

%% ----------------------------- Load game files ------------------------------
gameRuns = load_game_runs(cfg);
fprintf('Found %d game run(s) in %s\n', numel(gameRuns), cfg.gameDir);
if isempty(cfg.ssvepHz)
    allF = [];
    for g = 1:numel(gameRuns), allF = [allF; gameRuns(g).T.FrequencyC1Hz; gameRuns(g).T.FrequencyC2Hz]; end %#ok<AGROW>
    cfg.ssvepHz = unique(round(allF(:)' * 1000) / 1000);
end
nF = numel(cfg.ssvepHz);
fprintf('SSVEP frequencies: %s Hz\n', mat2str(cfg.ssvepHz));

%% --------------------- Load, preprocess and pair EEG blocks -----------------
eegDirs = dir(fullfile(cfg.dataDir, cfg.eegPattern));
eegDirs = eegDirs([eegDirs.isdir]);
if isempty(eegDirs), error('No EEG folders matching %s in %s', cfg.eegPattern, cfg.dataDir); end

blocks = struct([]);
for d = 1:numel(eegDirs)
    folder = fullfile(eegDirs(d).folder, eegDirs(d).name);
    sigFile = dir(fullfile(folder, '*_signals.csv'));
    if isempty(sigFile), warning('No _signals.csv in %s, skipped', folder); continue; end
    fs = read_fs(folder, cfg.fsDefault);
    [X, marker, chanNames] = read_signals(fullfile(folder, sigFile(1).name), cfg);
    ev     = marker_events(marker, cfg.minMarkerSamples, round(cfg.mergeSameCodeSec * fs));
    trials = segment_trials(ev, cfg.codes);
    [g, nPair] = match_game_run(trials, gameRuns);
    if isempty(g)
        warning('%s: no game run has the same trial-start marker sequence, skipped', eegDirs(d).name);
        continue;
    end
    trials = trials(1:nPair);
    T = gameRuns(g).T(1:nPair, :);
    check_pairing(trials, T, fs, eegDirs(d).name);

    Xp = preprocess(X, fs, cfg.pre);
    if any(~isfinite(Xp(:)))
        error('%s: %d non-finite samples after preprocessing (raw non-finite: %d)', eegDirs(d).name, ...
            nnz(~isfinite(Xp)), nnz(~isfinite(X)));
    end

    b = numel(blocks) + 1;
    blocks(b).name      = eegDirs(d).name;
    blocks(b).blockNum  = gameRuns(g).block;
    blocks(b).gameFile  = gameRuns(g).file;
    blocks(b).fs        = fs;
    blocks(b).chanNames = chanNames;
    blocks(b).X         = Xp;
    blocks(b).trials    = trials;
    blocks(b).T         = T;
    fprintf('%s -> block %d (%s): %d samples, %d channels, %d trials\n', blocks(b).name, ...
        blocks(b).blockNum, gameRuns(g).file, size(Xp, 1), size(Xp, 2), nPair);
end
if isempty(blocks), error('No EEG folder could be paired with a game file.'); end
[~, order] = sort([blocks.blockNum]);
blocks = blocks(order);
nB = numel(blocks);
fs = blocks(1).fs;
if any([blocks.fs] ~= fs), error('Blocks have different sampling rates.'); end

%% ---------------------------- Dynamic CCA ----------------------------------
W = round(cfg.cca.windowSec * fs);
H = round(cfg.cca.hopSec * fs);
Y = cell(1, nF); CyyInv = cell(1, nF);
for k = 1:nF, [Y{k}, CyyInv{k}] = reference_terms(cfg.ssvepHz(k), W, fs, cfg.cca.nHarmonics, cfg.cca.regY); end
taperKernel = mt_kernels(cfg.ssvepHz, W, fs, cfg.mt.tapers);   % for single-frequency MT power

for b = 1:nB
    fprintf('Dynamic CCA, block %d ...\n', blocks(b).blockNum);
    [blocks(b).score, blocks(b).power, blocks(b).U, blocks(b).updSample] = ...
        dynamic_cca(blocks(b).X, Y, CyyInv, taperKernel, W, H, cfg.cca);
    fprintf('  %d updates; median score %s; projected samples %d of %d\n', numel(blocks(b).updSample), ...
        mat2str(median(blocks(b).score, 1), 3), nnz(~isnan(blocks(b).U(:, 1))), size(blocks(b).U, 1));
end

%% ------------------------- Plot 1-2: session spectra -----------------------
specEEG = []; specU = [];
for b = 1:nB
    [s0, s1] = session_span(blocks(b), cfg.sessionSpan);
    E = round(cfg.epochLenSec * fs);
    nEp = floor((s1 - s0 + 1) / E);
    if nEp < 1, error('Block %d is shorter than one epoch.', blocks(b).blockNum); end
    idx = s0 + (0:nEp*E-1);
    Xs = blocks(b).X(idx, :);
    Us = blocks(b).U(idx, :);
    epMax = squeeze(max(max(abs(reshape(Xs, E, nEp, size(Xs, 2))), [], 1), [], 3));
    good = epMax(:)' <= cfg.artifactUv & ~any(isnan(reshape(Us(:,1), E, nEp)), 1);
    blocks(b).nEpochs = [nEp, nnz(good)];
    fprintf('Block %d spectra: %d of %d epochs kept\n', blocks(b).blockNum, nnz(good), nEp);

    params = struct('tapers', cfg.mt.tapers, 'pad', cfg.mt.pad, 'Fs', fs, 'fpass', cfg.mt.fpass, 'trialave', 1);
    Sch = [];
    for c = 1:size(Xs, 2)
        ep = reshape(Xs(:, c), E, nEp);
        [S, f] = mtspectrumc(ep(:, good), params);
        Sch(:, c) = S; %#ok<SAGROW>
    end
    specEEG(:, b) = mean(Sch, 2); %#ok<SAGROW>
    for k = 1:nF
        ep = reshape(Us(:, k), E, nEp);
        specU(:, b, k) = mtspectrumc(ep(:, good), params); %#ok<SAGROW>
    end
end
fSpec = f(:);

fig1 = figure('Name', 'Session spectrum', 'Color', 'w', 'Position', [80 80 760 480]);
hold on;
plot_shaded(fSpec, to_db(specEEG, cfg.plot.specInDb), cfg.plot.colEEG, cfg.plot.alpha, 'EEG (mean of channels)');
format_spectrum(cfg, sprintf('EEG power spectrum, whole session (%d blocks, mean \\pm SEM across blocks)', nB));
save_fig(fig1, fullfile(cfg.outDir, '1_session_spectrum'), cfg.plot);

fig2 = figure('Name', 'CCA projected spectrum', 'Color', 'w', 'Position', [100 100 760 480]);
hold on;
for k = 1:nF
    plot_shaded(fSpec, to_db(specU(:, :, k), cfg.plot.specInDb), cfg.plot.freqColors(k, :), cfg.plot.alpha, ...
        sprintf('U_{%g Hz} (CCA weights for %g Hz)', cfg.ssvepHz(k), cfg.ssvepHz(k)));
end
format_spectrum(cfg, sprintf('Dynamic-CCA projected spectrum (%g s window, %g ms updates; mean \\pm SEM across %d blocks)', ...
    cfg.cca.windowSec, 1000 * cfg.cca.hopSec, nB));
save_fig(fig2, fullfile(cfg.outDir, '2_cca_projected_spectrum'), cfg.plot);

%% -------------------- Plot 3-4: reveal-locked time series ------------------
tLock = (cfg.lock.windowSec(1):cfg.cca.hopSec:cfg.lock.windowSec(2))';
lockScore = {}; lockPower = {}; trialRows = {};
for b = 1:nB
    tr = blocks(b).trials; T = blocks(b).T;
    tUpd = blocks(b).updSample;
    for j = 1:numel(tr)
        targetHz = target_frequency(T(j, :));
        kT = find(abs(cfg.ssvepHz - targetHz) < 1e-6, 1);
        if isempty(kT), error('Target %g Hz not in cfg.ssvepHz', targetHz); end
        kN = setdiff(1:nF, kT);
        if strcmpi(strtrim(T.Cue(j)), "c1"), rule = cfg.plot.ruleNames{1}; else, rule = cfg.plot.ruleNames{2}; end
        trialRows(end+1, :) = {blocks(b).blockNum, T.TrialNumber(j), rule, targetHz, cfg.ssvepHz(kN(1)), ...
            ~isnan(tr(j).reveal), T.Accuracy(j), T.ReactionTime(j), T.ColorOnsetTime(j) - T.TrialStart(j)}; %#ok<SAGROW>
        if isnan(tr(j).reveal), continue; end
        keep = mask_updates(tUpd, tr(j), W, cfg.lock.maskMode);
        rel = (tUpd - tr(j).reveal) / fs;
        sc = [blocks(b).score(:, kT), mean(blocks(b).score(:, kN), 2)];
        pw = [blocks(b).power(:, kT), mean(blocks(b).power(:, kN), 2)];
        sc(~keep, :) = NaN; pw(~keep, :) = NaN;
        sel = rel >= tLock(1) - 1 & rel <= tLock(end) + 1;
        lockScore{end+1} = interp1(rel(sel), sc(sel, :), tLock, 'linear', NaN); %#ok<SAGROW>
        lockPower{end+1} = interp1(rel(sel), pw(sel, :), tLock, 'linear', NaN); %#ok<SAGROW>
    end
end
lockScore = cat(3, lockScore{:});   % time x [target nontarget] x trials
lockPower = cat(3, lockPower{:});
nLock = size(lockScore, 3);
lockN = squeeze(sum(~isnan(lockScore(:, 1, :)), 3));
lockScore(lockN < cfg.lock.minTrials, :, :) = NaN;
lockPower(lockN < cfg.lock.minTrials, :, :) = NaN;
if cfg.cca.powerInDb, lockPowerPlot = 10 * log10(lockPower); powUnit = 'dB (µV^2/Hz)';
else, lockPowerPlot = lockPower; powUnit = 'µV^2/Hz'; end

fig3 = figure('Name', 'Reveal-locked CCA score', 'Color', 'w', 'Position', [120 120 760 480]);
plot_locked(tLock, lockScore, cfg, 'CCA score (canonical correlation)', cfg.plot.scoreYLim, ...
    sprintf('Dynamic CCA score locked to colour reveal (%d trials, mean \\pm SEM)', nLock));
save_fig(fig3, fullfile(cfg.outDir, '3_reveal_locked_cca_score'), cfg.plot);

fig4 = figure('Name', 'Reveal-locked SSVEP power', 'Color', 'w', 'Position', [140 140 760 480]);
plot_locked(tLock, lockPowerPlot, cfg, ['SSVEP power of CCA projection, ' powUnit], cfg.plot.powerYLim, ...
    sprintf('SSVEP power (MT [%g %g], %g s window) locked to colour reveal (%d trials, mean \\pm SEM)', ...
    cfg.mt.tapers, cfg.cca.windowSec, nLock));
save_fig(fig4, fullfile(cfg.outDir, '4_reveal_locked_ssvep_power'), cfg.plot);

%% ------------------------- Plot 5-6: behaviour by block --------------------
trialTable = cell2table(trialRows, 'VariableNames', {'Block', 'TrialNumber', 'Rule', 'TargetHz', 'NonTargetHz', ...
    'Revealed', 'Accuracy', 'ReactionTime', 'TimeToReveal'});
blockNums = [blocks.blockNum];

switch cfg.rtTrials
    case 'responded', rtSel = ~isnan(trialTable.ReactionTime);
    case 'correct',   rtSel = ~isnan(trialTable.ReactionTime) & trialTable.Accuracy == 1;
    otherwise, error('cfg.rtTrials must be ''responded'' or ''correct''');
end
switch cfg.revealTrials
    case 'revealed', revSel = trialTable.Revealed == 1;
    case 'correct',  revSel = trialTable.Revealed == 1 & trialTable.Accuracy == 1;
    otherwise, error('cfg.revealTrials must be ''revealed'' or ''correct''');
end

fig5 = figure('Name', 'Reaction time by block', 'Color', 'w', 'Position', [160 160 620 460]);
rtStats = plot_by_block(trialTable.Block(rtSel), trialTable.ReactionTime(rtSel), trialTable.Rule(rtSel), ...
    blockNums, cfg, cfg.plot.behavYLimRT);
ylabel('Reaction time, colour reveal \rightarrow response (s)');
title(sprintf('Reaction time per block by rule (%s trials, mean \\pm SEM)', cfg.rtTrials), 'FontWeight', 'normal');
save_fig(fig5, fullfile(cfg.outDir, '5_reaction_time_by_block'), cfg.plot);

fig6 = figure('Name', 'Time to reveal by block', 'Color', 'w', 'Position', [180 180 620 460]);
revStats = plot_by_block(trialTable.Block(revSel), trialTable.TimeToReveal(revSel), trialTable.Rule(revSel), ...
    blockNums, cfg, cfg.plot.behavYLimRev);
ylabel('Trial start \rightarrow colour reveal (s)');
title(sprintf('Time to colour reveal per block by rule (%s trials, mean \\pm SEM)', cfg.revealTrials), 'FontWeight', 'normal');
save_fig(fig6, fullfile(cfg.outDir, '6_time_to_reveal_by_block'), cfg.plot);

%% ------------------------------- Save & report ------------------------------
writetable(trialTable, fullfile(cfg.outDir, 'trials.csv'));
results = struct('cfg', cfg, 'fSpec', fSpec, 'specEEG', specEEG, 'specU', specU, 'tLock', tLock, ...
    'lockScore', lockScore, 'lockPower', lockPower, 'lockN', lockN, 'trialTable', trialTable, 'rtStats', rtStats, ...
    'revStats', revStats, 'blockInfo', rmfield(blocks, {'X', 'U', 'score', 'power'}));
save(fullfile(cfg.outDir, 'results.mat'), '-struct', 'results', '-v7.3');

fprintf('\n=== Summary (%s) ===\n', dayTag);
fprintf('Block  Rule      trials  revealed  responded  correct  RT mean±SEM (s)   reveal time mean±SEM (s)\n');
for i = 1:nB
    for g = 1:numel(cfg.plot.ruleNames)
        s = trialTable.Block == blockNums(i) & strcmp(trialTable.Rule, cfg.plot.ruleNames{g});
        fprintf('%5d  %-8s  %6d  %8d  %9d  %7d  %5.3f ± %5.3f     %6.2f ± %5.2f\n', blockNums(i), ...
            cfg.plot.ruleNames{g}, nnz(s), nnz(s & trialTable.Revealed == 1), nnz(s & ~isnan(trialTable.ReactionTime)), ...
            nnz(s & trialTable.Accuracy == 1), rtStats(g).mean(i), rtStats(g).sem(i), revStats(g).mean(i), revStats(g).sem(i));
    end
end
fprintf('Outputs written to %s\n', cfg.outDir);


%% ============================== LOCAL FUNCTIONS ===============================

function runs = load_game_runs(cfg)
% Every trialdata file, split into runs where TrialNumber restarts (files append across runs).
files = dir(fullfile(cfg.gameDir, cfg.gamePattern));
if isempty(files), error('No game files matching %s in %s', cfg.gamePattern, cfg.gameDir); end
runs = struct('file', {}, 'block', {}, 'run', {}, 'T', {});
for i = 1:numel(files)
    opts = detectImportOptions(fullfile(files(i).folder, files(i).name), 'VariableNamingRule', 'preserve');
    opts = setvartype(opts, {'Cue', 'ParticipantResponse', 'CorrectResponse'}, 'string');
    T = readtable(fullfile(files(i).folder, files(i).name), opts);
    tok = regexp(files(i).name, '_b(\d+)_', 'tokens', 'once');
    if isempty(tok), blockNum = i; else, blockNum = str2double(tok{1}); end
    starts = [1; find(diff(T.TrialNumber) <= 0) + 1];
    edges = [starts; height(T) + 1];
    for r = 1:numel(starts)
        runs(end+1) = struct('file', files(i).name, 'block', blockNum, 'run', r, ...
            'T', T(edges(r):edges(r+1)-1, :)); %#ok<AGROW>
    end
end
end

function fs = read_fs(folder, fsDefault)
fs = fsDefault;
cf = dir(fullfile(folder, '*_config.txt'));
if isempty(cf), return; end
txt = fileread(fullfile(folder, cf(1).name));
tok = regexp(txt, 'Sampling Rate[^:]*:\s*([\d.]+)', 'tokens', 'once');
if ~isempty(tok), fs = str2double(tok{1}); end
end

function [X, marker, chanNames] = read_signals(file, cfg)
opts = detectImportOptions(file, 'VariableNamingRule', 'preserve');
names = opts.VariableNames;
names = strrep(names, char(65279), '');            % strip a UTF-8 BOM if present
opts.VariableNames = names;
isCh = ~cellfun(@isempty, regexp(names, cfg.channelPattern, 'once'));
chanNames = names(isCh);
if ~isempty(cfg.channels), chanNames = chanNames(cfg.channels); end
opts.SelectedVariableNames = [chanNames, {'marker'}];
opts = setvartype(opts, opts.SelectedVariableNames, 'double');
M = readmatrix(file, opts);
X = M(:, 1:end-1);
marker = M(:, end);
marker(isnan(marker)) = 0;
X = fillmissing(X, 'linear', 1, 'EndValues', 'nearest');
end

function ev = marker_events(marker, minLen, mergeSamples)
% Onsets of latched marker codes: one event per run of a non-zero code.
chg = [true; diff(marker) ~= 0];
idx = find(chg);
len = diff([idx; numel(marker) + 1]);
code = marker(idx);
keep = code ~= 0 & len >= minLen;
idx = idx(keep); code = code(keep);
dup = [false; diff(code) == 0 & diff(idx) <= mergeSamples];   % a glitch split one latched run
ev.sample = idx(~dup); ev.code = code(~dup);
end

function trials = segment_trials(ev, codes)
% Start [50 [40]] 30. Starts without a following 30 (aborted trials) are dropped.
iS = find(ismember(ev.code, codes.start));
trials = struct('startCode', {}, 'start', {}, 'reveal', {}, 'response', {}, 'stop', {});
for j = 1:numel(iS)
    if j < numel(iS), last = iS(j+1) - 1; else, last = numel(ev.code); end
    seg = iS(j)+1:last;
    s = seg(find(ev.code(seg) == codes.stop, 1));
    if isempty(s), continue; end
    seg = seg(seg < s);
    r = seg(find(ev.code(seg) == codes.reveal, 1));
    p = seg(find(ev.code(seg) == codes.response, 1));
    trials(end+1) = struct('startCode', ev.code(iS(j)), 'start', ev.sample(iS(j)), ...
        'reveal', pick(ev.sample, r), 'response', pick(ev.sample, p), 'stop', ev.sample(s)); %#ok<AGROW>
end
end

function v = pick(x, i)
if isempty(i), v = NaN; else, v = x(i); end
end

function [g, n] = match_game_run(trials, runs)
% Game run whose TrialStartMarker sequence equals the EEG start codes (EEG may have extra aborted trials).
g = []; n = 0;
eegCodes = [trials.startCode]';
for i = 1:numel(runs)
    gc = runs(i).T.TrialStartMarker;
    m = min(numel(gc), numel(eegCodes));
    if m > 0 && isequal(gc(1:m), eegCodes(1:m)) && m >= 0.9 * numel(gc) && m > n
        g = i; n = m;
    end
end
end

function check_pairing(trials, T, fs, name)
revealedEEG = ~isnan([trials.reveal])';
revealedCSV = T.RevealTimeout == 0;
if ~isequal(revealedEEG, revealedCSV)
    warning('%s: reveal markers disagree with RevealTimeout for %d trial(s)', name, nnz(revealedEEG ~= revealedCSV));
end
dEEG = ([trials.reveal]' - [trials.start]') / fs;
dCSV = T.ColorOnsetTime - T.TrialStart;
res = abs(dEEG - dCSV);
fprintf('%s: start->reveal EEG vs game clock, max |difference| = %.0f ms\n', name, 1000 * max(res(~isnan(res))));
if max(res(~isnan(res))) > 0.1
    warning('%s: EEG and game timing differ by more than 100 ms; check pairing', name);
end
end

function Xp = preprocess(X, fs, p)
Xp = X - mean(X, 1);
if ~isempty(p.highpassHz)
    [b, a] = butter(p.filterOrder, p.highpassHz / (fs/2), 'high');
    Xp = filtfilt(b, a, Xp);
end
if ~isempty(p.lowpassHz)
    [b, a] = butter(p.filterOrder, p.lowpassHz / (fs/2), 'low');
    Xp = filtfilt(b, a, Xp);
end
if ~isempty(p.notchHz) && p.notchHz + p.notchWidthHz/2 < fs/2
    [b, a] = butter(2, (p.notchHz + [-1 1] * p.notchWidthHz/2) / (fs/2), 'stop');
    Xp = filtfilt(b, a, Xp);
end
if p.car
    Xp = Xp - mean(Xp, 2);
end
end

function [Y, CyyInv] = reference_terms(freq, n, fs, nHarm, reg)
t = (0:n-1)' / fs;
Y = zeros(n, 2 * nHarm);
for h = 1:nHarm
    Y(:, 2*h-1) = sin(2*pi*freq*h*t);
    Y(:, 2*h)   = cos(2*pi*freq*h*t);
end
Y = Y - mean(Y, 1);
CyyInv = inv(Y' * Y + reg * eye(2 * nHarm));
end

function K = mt_kernels(freqs, n, fs, tapers)
% Chronux-normalised single-frequency multitaper kernels: S = mean_k |sum(u .* K(:,k,f))|^2
h = dpss(n, tapers(1), tapers(2)) * sqrt(fs);
t = (0:n-1)' / fs;
K = zeros(n, tapers(2), numel(freqs));
for i = 1:numel(freqs)
    K(:, :, i) = h .* exp(-2i*pi*freqs(i)*t) / fs;
end
end

function [score, power, U, updSample] = dynamic_cca(X, Y, CyyInv, K, W, H, c)
% Every H samples: HW-CCA on the last W samples for each frequency.
%   score(k,f) canonical correlation; power(k,f) MT power at f of the window projected on the
%   f-weights; U(:,f) causal projection (each update's weights applied to the newly arrived hop).
[N, C] = size(X);
nF = numel(Y);
updSample = (W:H:N)';
nU = numel(updSample);
score = zeros(nU, nF); power = zeros(nU, nF);
U = nan(N, nF);
wPrev = zeros(C, nF);
for u = 1:nU
    e = updSample(u);
    Xw = X(e-W+1:e, :);
    mu = mean(Xw, 1);
    Xw = Xw - mu;
    Cxx = Xw' * Xw;
    Cxx = Cxx + c.regX * trace(Cxx) / C * eye(C);
    if u == 1, newIdx = 1:e; else, newIdx = updSample(u-1)+1:e; end
    for f = 1:nF
        Cxy = Xw' * Y{f};
        M = Cxx \ (Cxy * CyyInv{f} * Cxy');
        % RT script starts from ones/sqrt(C); after CAR that vector is the null direction
        % (channels sum to 0, so M*ones = 0). Start from a fixed zero-mean ramp instead.
        v = (1:C)' - (C + 1) / 2;
        v = v / norm(v);
        ok = all(isfinite(M(:)));
        for it = 1:c.nPowerIters * ok
            v = M * v;
            nv = norm(v);
            if ~(nv >= 1e-12), ok = false; break; end
            v = v / nv;
        end
        if ~ok, score(u, f) = 0; power(u, f) = NaN; continue; end
        if wPrev(:, f)' * v < 0, v = -v; end      % keep a consistent sign across updates
        wPrev(:, f) = v;
        score(u, f) = sqrt(max(v' * M * v, 0));
        proj = Xw * v;
        power(u, f) = mean(abs(sum(proj .* K(:, :, f), 1)).^2);
        U(newIdx, f) = (X(newIdx, :) - mu) * v;
    end
end
end

function [s0, s1] = session_span(blk, mode)
switch mode
    case 'trials', s0 = blk.trials(1).start; s1 = blk.trials(end).stop;
    case 'file',   s0 = 1; s1 = size(blk.X, 1);
    otherwise, error('cfg.sessionSpan must be ''trials'' or ''file''');
end
s0 = max(s0, find(~isnan(blk.U(:, 1)), 1));   % the projection starts after the first full window
end

function hz = target_frequency(row)
if strcmpi(strtrim(row.Cue), "c1"), hz = row.FrequencyC1Hz; else, hz = row.FrequencyC2Hz; end
end

function keep = mask_updates(tUpd, tr, W, mode)
switch mode
    case 'endpoint', keep = tUpd >= tr.start & tUpd <= tr.stop;
    case 'window',   keep = tUpd - W + 1 >= tr.start & tUpd <= tr.stop;
    case 'none',     keep = true(size(tUpd));
    otherwise, error('cfg.lock.maskMode must be ''endpoint'', ''window'' or ''none''');
end
end

function y = to_db(x, inDb)
if inDb, y = 10 * log10(x); else, y = x; end
end

function h = plot_shaded(x, Ymat, col, alpha, label)
% Mean ± SEM across columns (NaNs ignored).
m = mean(Ymat, 2, 'omitnan');
n = sum(~isnan(Ymat), 2);
s = std(Ymat, 0, 2, 'omitnan') ./ sqrt(n);
ok = ~isnan(m) & ~isnan(s);
x = x(:);
fill([x(ok); flipud(x(ok))], [m(ok) - s(ok); flipud(m(ok) + s(ok))], col, ...
    'FaceAlpha', alpha, 'EdgeColor', 'none', 'HandleVisibility', 'off');
h = plot(x, m, 'Color', col, 'LineWidth', 1.6, 'DisplayName', label);
end

function format_spectrum(cfg, ttl)
xlim(cfg.plot.specFreqLim);
if ~isempty(cfg.plot.specYLim), ylim(cfg.plot.specYLim); end
yl = ylim;
for k = 1:numel(cfg.ssvepHz)
    xline(cfg.ssvepHz(k), ':', sprintf('%g Hz', cfg.ssvepHz(k)), 'Color', cfg.plot.freqColors(k, :), ...
        'HandleVisibility', 'off', 'LabelVerticalAlignment', 'bottom');
end
ylim(yl);
xlabel('Frequency (Hz)');
if cfg.plot.specInDb, ylabel('PSD (dB re 1 µV^2/Hz)'); else, ylabel('PSD (µV^2/Hz)'); end
title(ttl, 'FontWeight', 'normal');
legend('Location', 'northeast'); grid on; box off;
end

function plot_locked(t, D, cfg, yl, ylimits, ttl)
% D: time x [target nontarget] x trials
hold on;
plot_shaded(t, squeeze(D(:, 1, :)), cfg.plot.colTarget, cfg.plot.alpha, 'Target frequency');
plot_shaded(t, squeeze(D(:, 2, :)), cfg.plot.colNonTarget, cfg.plot.alpha, 'Non-target frequency');
xline(0, 'k--', 'colour reveal', 'HandleVisibility', 'off', 'LabelVerticalAlignment', 'bottom');
xlim(t([1 end]));
if ~isempty(ylimits), ylim(ylimits); end
xlabel('Time from colour reveal (s)'); ylabel(yl);
title(ttl, 'FontWeight', 'normal');
legend('Location', 'best'); grid on; box off;
end

function st = plot_by_block(blockOfTrial, values, rule, blockNums, cfg, ylimits)
% One line (mean ± SEM across trials) per rule, single trials as points in the rule's colour.
names = cfg.plot.ruleNames;
nG = numel(names);
offs = ((1:nG) - (nG + 1) / 2) * 2 * cfg.plot.ruleOffset / max(nG - 1, 1);
st = struct('rule', names, 'block', blockNums(:), 'mean', [], 'sem', [], 'n', []);
hold on;
for g = 1:nG
    col = cfg.plot.ruleColors(g, :);
    inG = strcmp(rule, names{g}) & ~isnan(values);
    st(g).mean = nan(numel(blockNums), 1); st(g).sem = st(g).mean; st(g).n = zeros(numel(blockNums), 1);
    for i = 1:numel(blockNums)
        v = values(inG & blockOfTrial == blockNums(i));
        st(g).n(i) = numel(v); st(g).mean(i) = mean(v); st(g).sem(i) = std(v) / sqrt(numel(v));
    end
    if cfg.plot.showTrials
        jit = (rand(nnz(inG), 1) - 0.5) * 2 * cfg.plot.trialJitter;
        scatter(blockOfTrial(inG) + offs(g) + jit, values(inG), 16, col, 'filled', 'MarkerFaceAlpha', 0.45, ...
            'HandleVisibility', 'off');
    end
    errorbar(st(g).block + offs(g), st(g).mean, st(g).sem, '-o', 'Color', col, 'MarkerFaceColor', col, ...
        'LineWidth', 1.6, 'CapSize', 8, 'DisplayName', sprintf('%s (mean \\pm SEM)', names{g}));
    for i = 1:numel(blockNums)
        if st(g).n(i) == 0, continue; end
        text(st(g).block(i) + offs(g), st(g).mean(i) + st(g).sem(i), sprintf('n=%d', st(g).n(i)), ...
            'Color', col, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);
    end
end
xticks(blockNums); xlim([min(blockNums) - 0.5, max(blockNums) + 0.5]);
if ~isempty(ylimits)
    ylim(ylimits);
elseif any(~isnan(values))
    r = [min(values), max(values)]; pad = 0.08 * max(diff(r), eps);
    ylim([r(1) - pad, r(2) + 2 * pad]);
end
xlabel('Block'); legend('Location', 'southoutside', 'Orientation', 'horizontal'); grid on; box off;
end

function save_fig(fig, base, p)
if exist('theme', 'file') || exist('theme', 'builtin'), theme(fig, p.theme); end
for i = 1:numel(p.formats)
    switch p.formats{i}
        case 'fig', savefig(fig, [base '.fig']);
        otherwise, exportgraphics(fig, [base '.' p.formats{i}], 'Resolution', p.dpi);
    end
end
end

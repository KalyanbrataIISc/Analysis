%% LEAF_RT_CONGRUENCY_CCA_ANALYSIS  Rule-repetition RT effects and pre-reveal SSVEP vs RT, one day of Leaf blocks.
%
% Companion of leaf_ssvep_analysis.m: same inputs, block pairing, preprocessing and dynamic CCA.
% To analyse another day: change cfg.dataDir below and run. The day folder must contain
%   eeg_<yyyymmdd_HHMMSS>/   BciCore logs (…_signals.csv with ch*_uv + marker, …_config.txt)
%   gameData/                p<P>_b<B>_leaves_trialdata.csv (one per block)
% EEG folders are matched to game blocks by their trial-start marker sequences.
%
% Figures (PNG + FIG), per-trial table and a results .mat are written to cfg.outDir.
%
% Reaction time (RT) = colour onset -> response (game ReactionTime column).
% Rule: cue C1 = Pointing, cue C2 = Moving.
%
% Plots
%   1. RT, congruent vs incongruent trials, all blocks pooled and split into a first and second
%      half (cfg.halfMode): 2 x 2 subplots, rule (rows) x half (columns), mean ± SEM across trials.
%      Congruent = the previous trial (same block) had the same rule, incongruent = the other rule.
%      The first trial of each block and trials that follow an incorrect or missed response are
%      excluded. Welch t-test p-value in each subplot.
%   2. Per-trial scatter: RT (x) vs the maximum, over the cfg.preWin window before colour onset,
%      of (target-frequency CCA score - non-target CCA score). OLS fit with 95% CI, slope ± SE,
%      Pearson r, R^2 and the slope's t-test p-value.
%   3. Same as 2 with the SSVEP power of the dynamic-CCA projection (target - non-target).
%
% Dynamic CCA follows leaf_ssvep_analysis.m / matlab/RT_acquisition_CCA.m: every cfg.cca.hopSec,
% fit hardware-friendly CCA (power iteration) between the last cfg.cca.windowSec of EEG (all
% channels) and sin/cos references of each SSVEP frequency. Score = canonical correlation; power =
% single-frequency multitaper power at f of the window projected on the f-weights.

clear; close all; clc;

%% =============================== USER SETTINGS ===============================
here        = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(here));

% ---- Paths (change cfg.dataDir for another day) ----
cfg.dataDir     = fullfile(projectRoot, 'data', '2026-11-16');
cfg.eegPattern  = 'eeg_*';                         % EEG session folders inside dataDir
cfg.gameDir     = fullfile(cfg.dataDir, 'gameData');
cfg.gamePattern = '*_leaves_trialdata.csv';
[~, dayTag]     = fileparts(cfg.dataDir);
cfg.outDir      = fullfile(projectRoot, 'plots', [dayTag '_leaf_rt_congruency_matlab']);

% ---- Recording ----
cfg.fsDefault        = 2000;          % used only if the config file has no sampling rate
cfg.channelPattern   = '^ch\d+_uv$'; % EEG columns in _signals.csv
cfg.channels         = [];           % indices into the matched columns; [] = all
cfg.minMarkerSamples = 1;            % ignore marker runs shorter than this
cfg.mergeSameCodeSec = 0.4;          % same code re-appearing within this time = one (split) marker

% ---- Event codes (Leaf game, shuffle mode; 20/21 = legacy starts) ----
cfg.codes.start    = [31 32 33 34 20 21];
cfg.codes.reveal   = 50;
cfg.codes.response = 40;
cfg.codes.stop     = 30;

% ---- Preprocessing (applied to each whole recording before anything else) ----
cfg.pre.highpassHz   = 1;      % Butterworth high-pass (zero phase); [] to skip
cfg.pre.lowpassHz    = 45;     % Butterworth low-pass; [] to skip
cfg.pre.filterOrder  = 4;
cfg.pre.notchHz      = 50;     % line-noise band-stop centre; [] to skip
cfg.pre.notchWidthHz = 2;      % total width of the band-stop
cfg.pre.car          = true;   % common-average re-reference

% ---- SSVEP frequencies ----
cfg.ssvepHz = [];              % [] = taken from the game files (FrequencyC1Hz / FrequencyC2Hz)

% ---- Dynamic CCA (as in leaf_ssvep_analysis.m) ----
cfg.cca.windowSec   = 1;       % analysis window
cfg.cca.hopSec      = 0.1;     % update interval (game NF ~100 ms)
cfg.cca.nHarmonics  = 1;       % sin/cos pairs per frequency
cfg.cca.nPowerIters = 8;       % power iterations
cfg.cca.regX        = 1e-6;    % ridge on Cxx, relative to mean channel power (CAR makes Cxx singular)
cfg.cca.regY        = 1e-8;    % ridge on Cyy
cfg.cca.mtTapers    = [1 1];   % [TW K] for the single-frequency multitaper power
cfg.cca.powerInDb   = true;    % plot 3: difference of dB values (10*log10 power ratio); false = µV²/Hz

% ---- Pre-colour-onset window (plots 2-3) ----
cfg.preWin.windowSec = [-4 0];     % CCA updates whose end time lies in this range around colour onset (s)
cfg.preWin.maskMode  = 'endpoint'; % 'endpoint': keep updates whose time lies inside the trial
                                   % 'window'  : keep only updates whose whole CCA window is inside
                                   % 'none'    : keep everything (ITI/previous trial can leak in)

% ---- Trial selection ----
cfg.congruencyTrials = 'correct';    % plot 1, current trial: 'correct' or 'responded'
cfg.halfMode         = 'session';    % plot 1 halves: 'session' = all trials of the day in order, split at
                                     %   the midpoint (a block can be cut in two); 'withinBlock' = first vs
                                     %   second half of the trials of every block, pooled over blocks
cfg.scatterTrials    = 'responded';  % plots 2-3: 'responded' or 'correct'
cfg.includeRevealTimeouts = true;    % include trials whose colour appeared after the NF reveal timeout
                                     % (no 50 marker; onset taken from the game clock)

% ---- Plot appearance ----
cfg.plot.ruleNames      = {'Pointing', 'Moving'};          % cue C1 = Pointing, C2 = Moving
cfg.plot.ruleColors     = [0.00 0.45 0.70; 0.84 0.37 0.00]; % Pointing blue, Moving orange
cfg.plot.colCongruent   = [0.00 0.62 0.45];
cfg.plot.colIncongruent = [0.80 0.47 0.74];
cfg.plot.colFit         = [0.20 0.20 0.20];
cfg.plot.alpha          = 0.20;  % CI shading
cfg.plot.showTrials     = true;  % single-trial points on plot 1
cfg.plot.trialJitter    = 0.12;  % horizontal jitter of single-trial points (plot 1)
cfg.plot.congYLim       = [];    % plot 1 (shared by all subplots); [] = automatic
cfg.plot.scoreYLim      = [];    % plot 2
cfg.plot.powerYLim      = [];    % plot 3
cfg.plot.theme          = 'light';  % 'light' or 'dark' (R2025a+ follows the desktop theme otherwise)
cfg.plot.formats        = {'png', 'fig'};
cfg.plot.dpi            = 300;   % 600 dpi clipped tick labels lying beyond ~3700 px (R2026a raster export)
%% =============================================================================

if ~exist(cfg.outDir, 'dir'), mkdir(cfg.outDir); end
rng(0);   % reproducible jitter

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
eegDirs = list_dir(cfg.dataDir, cfg.eegPattern);
eegDirs = eegDirs([eegDirs.isdir]);
if isempty(eegDirs), error('No EEG folders matching %s in %s', cfg.eegPattern, cfg.dataDir); end

blocks = struct([]);
for d = 1:numel(eegDirs)
    folder = fullfile(eegDirs(d).folder, eegDirs(d).name);
    sigFile = list_dir(folder, '*_signals.csv');
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
taperKernel = mt_kernels(cfg.ssvepHz, W, fs, cfg.cca.mtTapers);

for b = 1:nB
    fprintf('Dynamic CCA, block %d ...\n', blocks(b).blockNum);
    [blocks(b).score, blocks(b).power, blocks(b).updSample] = ...
        dynamic_cca(blocks(b).X, Y, CyyInv, taperKernel, W, H, cfg.cca);
    fprintf('  %d updates; median score %s\n', numel(blocks(b).updSample), mat2str(median(blocks(b).score, 1), 3));
end

%% ------------------- Per-trial congruency and pre-onset SSVEP ---------------
names = cfg.plot.ruleNames;
rows = {};
for b = 1:nB
    tr = blocks(b).trials; T = blocks(b).T;
    tUpd = blocks(b).updSample;
    if cfg.cca.powerInDb, P = 10 * log10(blocks(b).power); else, P = blocks(b).power; end
    for j = 1:numel(tr)
        rule = rule_name(T.Cue(j), names);
        targetHz = target_frequency(T(j, :));
        kT = find(abs(cfg.ssvepHz - targetHz) < 1e-6, 1);
        if isempty(kT), error('Target %g Hz not in cfg.ssvepHz', targetHz); end
        kN = setdiff(1:nF, kT);

        % congruency with the previous trial of the same block
        if j == 1
            prevRule = ''; cong = 'excluded (first trial)';
        else
            prevRule = rule_name(T.Cue(j-1), names);
            if ~responded_correctly(T(j-1, :))
                cong = 'excluded (previous incorrect/missed)';
            elseif strcmp(prevRule, rule)
                cong = 'congruent';
            else
                cong = 'incongruent';
            end
        end

        % colour onset: reveal marker, else (reveal timeout) the game clock offset from the start marker
        if ~isnan(tr(j).reveal)
            onset = tr(j).reveal;
        elseif isfinite(T.ColorOnsetTime(j))
            onset = tr(j).start + round((T.ColorOnsetTime(j) - T.TrialStart(j)) * fs);
        else
            onset = NaN;
        end

        maxScore = NaN; tMaxScore = NaN; maxPow = NaN; tMaxPow = NaN; nUpd = 0;
        if ~isnan(onset)
            inWin = tUpd >= onset + cfg.preWin.windowSec(1) * fs & tUpd <= onset + cfg.preWin.windowSec(2) * fs;
            keep = find(inWin & mask_updates(tUpd, tr(j), W, cfg.preWin.maskMode));
            nUpd = numel(keep);
            if nUpd > 0
                rel = (tUpd(keep) - onset) / fs;
                dS = blocks(b).score(keep, kT) - mean(blocks(b).score(keep, kN), 2);
                dP = P(keep, kT) - mean(P(keep, kN), 2);
                [maxScore, iS] = max(dS, [], 'omitnan'); tMaxScore = rel(iS);
                [maxPow,   iP] = max(dP, [], 'omitnan'); tMaxPow   = rel(iP);
                if isnan(maxScore), tMaxScore = NaN; end
                if isnan(maxPow),   tMaxPow   = NaN; end
            end
        end

        rows(end+1, :) = {blocks(b).blockNum, T.TrialNumber(j), rule, prevRule, cong, T.Accuracy(j), ...
            T.ResponseTimeout(j), T.RevealTimeout(j), T.ReactionTime(j), targetHz, cfg.ssvepHz(kN(1)), ...
            nUpd, maxScore, tMaxScore, maxPow, tMaxPow}; %#ok<SAGROW>
    end
end
trialTable = cell2table(rows, 'VariableNames', {'Block', 'TrialNumber', 'Rule', 'PrevRule', 'Congruency', ...
    'Accuracy', 'ResponseTimeout', 'RevealTimeout', 'ReactionTime', 'TargetHz', 'NonTargetHz', ...
    'NPreOnsetUpdates', 'MaxScoreDiff', 'TimeOfMaxScoreDiff', 'MaxPowerDiff', 'TimeOfMaxPowerDiff'});
blockNums = [blocks.blockNum];

% first / second half (the table is in chronological order: blocks sorted, trials in order)
nAll = height(trialTable);
switch cfg.halfMode
    case 'session'
        half = 1 + ((1:nAll)' > ceil(nAll / 2));
        halfLabels = cell(1, 2);
        for h = 1:2
            ih = find(half == h);
            halfLabels{h} = sprintf('block %d trial %d \\rightarrow block %d trial %d', trialTable.Block(ih(1)), ...
                trialTable.TrialNumber(ih(1)), trialTable.Block(ih(end)), trialTable.TrialNumber(ih(end)));
        end
    case 'withinBlock'
        half = zeros(nAll, 1);
        for i = 1:numel(blockNums)
            ib = find(trialTable.Block == blockNums(i));
            half(ib) = 1 + ((1:numel(ib))' > ceil(numel(ib) / 2));
        end
        halfLabels = {'first half of every block', 'second half of every block'};
    otherwise, error('cfg.halfMode must be ''session'' or ''withinBlock''');
end
trialTable.Half = half;
halfNames = {'First half', 'Second half'};

hasRT = ~isnan(trialTable.ReactionTime) & trialTable.ResponseTimeout == 0;
isCorrect = hasRT & trialTable.Accuracy == 1;
timeoutOk = cfg.includeRevealTimeouts | trialTable.RevealTimeout == 0;

%% ------------------------- Plot 1: RT congruency ---------------------------
switch cfg.congruencyTrials
    case 'correct',   congSel = isCorrect & timeoutOk;
    case 'responded', congSel = hasRT & timeoutOk;
    otherwise, error('cfg.congruencyTrials must be ''correct'' or ''responded''');
end
condNames = {'congruent', 'incongruent'};
condCols  = [cfg.plot.colCongruent; cfg.plot.colIncongruent];

fig1 = figure('Name', 'RT congruency', 'Color', 'w', 'Position', [60 60 820 740]);
tl = tiledlayout(fig1, numel(names), 2, 'TileSpacing', 'compact', 'Padding', 'loose');
ax = gobjects(numel(names), 2);
congStats = struct('half', {}, 'halfLabel', {}, 'rule', {}, 'n', {}, 'mean', {}, 'sem', {}, 'p', {});
for r = 1:numel(names)
    for h = 1:2
        ax(r, h) = nexttile(tl, (r - 1) * 2 + h);
        base = congSel & trialTable.Half == h & strcmp(trialTable.Rule, names{r});
        vals = cell(1, 2);
        for c = 1:2, vals{c} = trialTable.ReactionTime(base & strcmp(trialTable.Congruency, condNames{c})); end
        st = plot_conditions(ax(r, h), vals, {'Congruent', 'Incongruent'}, condCols, cfg);
        p = welch_p(vals{1}, vals{2});
        congStats(end+1) = struct('half', h, 'halfLabel', halfLabels{h}, 'rule', names{r}, 'n', st.n, ...
            'mean', st.mean, 'sem', st.sem, 'p', p); %#ok<SAGROW>
        title(ax(r, h), sprintf('%s · %s', halfNames{h}, names{r}), 'FontWeight', 'normal', ...
            'Color', cfg.plot.ruleColors(r, :));
        subtitle(ax(r, h), {halfLabels{h}, sprintf('Welch p = %s', fmt_p(p))}, 'FontSize', 8);
        if h == 1, ylabel(ax(r, h), 'Reaction time (s)'); end
    end
end
allV = trialTable.ReactionTime(congSel & ismember(trialTable.Congruency, condNames));
if ~isempty(cfg.plot.congYLim)
    set(ax, 'YLim', cfg.plot.congYLim);
elseif ~isempty(allV)
    rr = [min(allV), max(allV)]; pad = 0.08 * max(diff(rr), eps);
    set(ax, 'YLim', [rr(1) - pad, rr(2) + pad]);
end
title(tl, 'RT (colour onset \rightarrow response): previous trial same rule (congruent) vs other rule (incongruent)', ...
    'FontSize', 10);
subtitle(tl, {sprintf('Blocks %s pooled, split into halves (%s); %s trials; mean \\pm SEM across trials', ...
    strjoin(arrayfun(@num2str, blockNums, 'UniformOutput', false), ', '), cfg.halfMode, cfg.congruencyTrials), ...
    'Excluded: first trial of each block, trials following an incorrect or missed response'}, 'FontSize', 9);
save_fig(fig1, fullfile(cfg.outDir, '1_rt_congruency_by_half_rule'), cfg.plot);

%% ------------------------ Plots 2-3: RT vs pre-onset SSVEP -----------------
switch cfg.scatterTrials
    case 'responded', scSel = hasRT & timeoutOk;
    case 'correct',   scSel = isCorrect & timeoutOk;
    otherwise, error('cfg.scatterTrials must be ''responded'' or ''correct''');
end
winTxt = sprintf('[%g, %g] s around colour onset', cfg.preWin.windowSec);

fig2 = figure('Name', 'RT vs CCA score difference', 'Color', 'w', 'Position', [100 100 760 540]);
fitScore = plot_rt_scatter(trialTable, scSel, 'MaxScoreDiff', cfg, cfg.plot.scoreYLim, ...
    'max (CCA score_{target} - CCA score_{non-target})', ...
    {'RT vs peak target - non-target dynamic-CCA score', sprintf('window %s, %s trials', winTxt, cfg.scatterTrials)});
save_fig(fig2, fullfile(cfg.outDir, '2_rt_vs_max_cca_score_diff'), cfg.plot);

if cfg.cca.powerInDb, powLab = 'max (P_{target} - P_{non-target}) of CCA projection (dB)';
else, powLab = 'max (P_{target} - P_{non-target}) of CCA projection (µV^2/Hz)'; end
fig3 = figure('Name', 'RT vs SSVEP power difference', 'Color', 'w', 'Position', [120 120 760 540]);
fitPower = plot_rt_scatter(trialTable, scSel, 'MaxPowerDiff', cfg, cfg.plot.powerYLim, powLab, ...
    {'RT vs peak target - non-target SSVEP power of the dynamic-CCA projection', ...
    sprintf('MT [%g %g], %g s CCA window; window %s, %s trials', cfg.cca.mtTapers, cfg.cca.windowSec, ...
    winTxt, cfg.scatterTrials)});
save_fig(fig3, fullfile(cfg.outDir, '3_rt_vs_max_ssvep_power_diff'), cfg.plot);

%% ------------------------------- Save & report ------------------------------
writetable(trialTable, fullfile(cfg.outDir, 'trials.csv'));
results = struct('cfg', cfg, 'trialTable', trialTable, 'congStats', congStats, 'fitScore', fitScore, ...
    'fitPower', fitPower, 'blockInfo', rmfield(blocks, {'X', 'score', 'power'}));
save(fullfile(cfg.outDir, 'results.mat'), '-struct', 'results', '-v7.3');

fprintf('\n=== Congruency (%s, %s trials, halves: %s) ===\n', dayTag, cfg.congruencyTrials, cfg.halfMode);
for h = 1:2, fprintf('Half %d: %s\n', h, strrep(halfLabels{h}, '\rightarrow', '->')); end
fprintf('Half  Rule      congruent: n  RT mean±SEM     incongruent: n  RT mean±SEM     Welch p\n');
for s = 1:numel(congStats)
    c = congStats(s);
    fprintf('%4d  %-8s  %12d  %5.3f ± %5.3f  %14d  %5.3f ± %5.3f  %s\n', c.half, c.rule, c.n(1), c.mean(1), ...
        c.sem(1), c.n(2), c.mean(2), c.sem(2), fmt_p(c.p));
end
fprintf('\n=== RT regressions (%s trials, window %s) ===\n', cfg.scatterTrials, winTxt);
report_fit('CCA score diff  ', fitScore);
report_fit('SSVEP power diff', fitPower);
fprintf('Outputs written to %s\n', cfg.outDir);


%% ============================== LOCAL FUNCTIONS ===============================

function runs = load_game_runs(cfg)
% Every trialdata file, split into runs where TrialNumber restarts (files append across runs).
files = list_dir(cfg.gameDir, cfg.gamePattern);
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
cf = list_dir(folder, '*_config.txt');
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

function [score, power, updSample] = dynamic_cca(X, Y, CyyInv, K, W, H, c)
% Every H samples: HW-CCA on the last W samples for each frequency.
%   score(k,f) canonical correlation; power(k,f) MT power at f of the window projected on the f-weights.
[N, C] = size(X);
nF = numel(Y);
updSample = (W:H:N)';
nU = numel(updSample);
score = zeros(nU, nF); power = zeros(nU, nF);
v0 = (1:C)' - (C + 1) / 2;   % zero-mean start vector (ones/sqrt(C) is the CAR null direction)
v0 = v0 / norm(v0);
for u = 1:nU
    e = updSample(u);
    Xw = X(e-W+1:e, :);
    Xw = Xw - mean(Xw, 1);
    Cxx = Xw' * Xw;
    Cxx = Cxx + c.regX * trace(Cxx) / C * eye(C);
    for f = 1:nF
        Cxy = Xw' * Y{f};
        M = Cxx \ (Cxy * CyyInv{f} * Cxy');
        v = v0;
        ok = all(isfinite(M(:)));
        for it = 1:c.nPowerIters * ok
            v = M * v;
            nv = norm(v);
            if ~(nv >= 1e-12), ok = false; break; end
            v = v / nv;
        end
        if ~ok, score(u, f) = 0; power(u, f) = NaN; continue; end
        score(u, f) = sqrt(max(v' * M * v, 0));
        proj = Xw * v;
        power(u, f) = mean(abs(sum(proj .* K(:, :, f), 1)).^2);
    end
end
end

function name = rule_name(cue, names)
if strcmpi(strtrim(cue), "c1"), name = names{1}; else, name = names{2}; end
end

function hz = target_frequency(row)
if strcmpi(strtrim(row.Cue), "c1"), hz = row.FrequencyC1Hz; else, hz = row.FrequencyC2Hz; end
end

function ok = responded_correctly(row)
ok = row.Accuracy == 1 && row.ResponseTimeout == 0 && ~isnan(row.ReactionTime);
end

function keep = mask_updates(tUpd, tr, W, mode)
switch mode
    case 'endpoint', keep = tUpd >= tr.start & tUpd <= tr.stop;
    case 'window',   keep = tUpd - W + 1 >= tr.start & tUpd <= tr.stop;
    case 'none',     keep = true(size(tUpd));
    otherwise, error('cfg.preWin.maskMode must be ''endpoint'', ''window'' or ''none''');
end
end

function st = plot_conditions(ax, vals, labels, cols, cfg)
% Mean ± SEM per condition, single trials as jittered points.
hold(ax, 'on');
nC = numel(vals);
st = struct('n', zeros(1, nC), 'mean', nan(1, nC), 'sem', nan(1, nC));
tickLab = cell(1, nC);
for c = 1:nC
    v = vals{c}(:);
    st.n(c) = numel(v);
    if ~isempty(v), st.mean(c) = mean(v); st.sem(c) = std(v) / sqrt(numel(v)); end
    if cfg.plot.showTrials && ~isempty(v)
        jit = (rand(numel(v), 1) - 0.5) * 2 * cfg.plot.trialJitter;
        scatter(ax, c + jit, v, 14, cols(c, :), 'filled', 'MarkerFaceAlpha', 0.4, 'HandleVisibility', 'off');
    end
    errorbar(ax, c, st.mean(c), st.sem(c), 'o', 'Color', cols(c, :), 'MarkerFaceColor', cols(c, :), ...
        'MarkerSize', 7, 'LineWidth', 1.8, 'CapSize', 10);
    tickLab{c} = sprintf('%s\\newline(n=%d)', labels{c}, st.n(c));
end
plot(ax, 1:nC, st.mean, '-', 'Color', [0.5 0.5 0.5], 'LineWidth', 1, 'HandleVisibility', 'off');
xlim(ax, [0.4, nC + 0.6]); xticks(ax, 1:nC); xticklabels(ax, tickLab);
grid(ax, 'on'); box(ax, 'off');
end

function p = welch_p(a, b)
% Two-sided Welch t-test (no Statistics Toolbox needed).
a = a(~isnan(a)); b = b(~isnan(b));
na = numel(a); nb = numel(b);
if na < 2 || nb < 2, p = NaN; return; end
va = var(a) / na; vb = var(b) / nb;
if va + vb == 0, p = NaN; return; end
t = (mean(a) - mean(b)) / sqrt(va + vb);
df = (va + vb)^2 / (va^2 / (na - 1) + vb^2 / (nb - 1));
p = betainc(df / (df + t^2), df / 2, 0.5);
end

function st = ols_fit(x, y)
% y = b0 + b1*x by least squares; two-sided t-test on the slope, 95% CI of the fitted mean.
x = x(:); y = y(:); n = numel(x);
st = struct('n', n, 'intercept', NaN, 'slope', NaN, 'slopeSE', NaN, 't', NaN, 'df', n - 2, ...
    'p', NaN, 'r', NaN, 'R2', NaN, 'tcrit', NaN, 's2', NaN, 'xMean', mean(x), 'Sxx', NaN);
if n < 3 || all(x == x(1)), return; end
Xd = [ones(n, 1), x];
beta = Xd \ y;
res = y - Xd * beta;
df = n - 2;
s2 = sum(res.^2) / df;
Sxx = sum((x - mean(x)).^2);
se = sqrt(s2 / Sxx);
t = beta(2) / se;
st.intercept = beta(1); st.slope = beta(2); st.slopeSE = se; st.t = t; st.s2 = s2; st.Sxx = Sxx;
st.p = betainc(df / (df + t^2), df / 2, 0.5);
st.r = sum((x - mean(x)) .* (y - mean(y))) / sqrt(Sxx * sum((y - mean(y)).^2));
st.R2 = st.r^2;
st.tcrit = fzero(@(q) 0.5 * betainc(df / (df + q^2), df / 2, 0.5) - 0.025, [0 1e4]);
end

function st = plot_rt_scatter(tbl, sel, yName, cfg, ylimits, ylab, ttl)
% Single trials coloured by rule (open = NF reveal timeout), pooled OLS fit with 95% CI.
names = cfg.plot.ruleNames;
y = tbl.(yName);
ok = sel & ~isnan(y) & ~isnan(tbl.ReactionTime);
x = tbl.ReactionTime;
hold on;
for g = 1:numel(names)
    col = cfg.plot.ruleColors(g, :);
    inG = ok & strcmp(tbl.Rule, names{g});
    s = inG & tbl.RevealTimeout == 0;
    scatter(x(s), y(s), 30, col, 'filled', 'MarkerFaceAlpha', 0.6, 'DisplayName', ...
        sprintf('%s (n=%d)', names{g}, nnz(s)));
    s = inG & tbl.RevealTimeout ~= 0;
    if any(s)
        scatter(x(s), y(s), 30, col, 'LineWidth', 1.2, 'DisplayName', ...
            sprintf('%s, reveal timeout (n=%d)', names{g}, nnz(s)));
    end
end
st = ols_fit(x(ok), y(ok));
if ~isnan(st.slope)
    xx = linspace(min(x(ok)), max(x(ok)), 200)';
    yy = st.intercept + st.slope * xx;
    hw = st.tcrit * sqrt(st.s2 * (1 / st.n + (xx - st.xMean).^2 / st.Sxx));
    fill([xx; flipud(xx)], [yy - hw; flipud(yy + hw)], cfg.plot.colFit, 'FaceAlpha', cfg.plot.alpha, ...
        'EdgeColor', 'none', 'DisplayName', '95% CI of fit');
    plot(xx, yy, '-', 'Color', cfg.plot.colFit, 'LineWidth', 1.8, 'DisplayName', 'OLS fit (all trials)');
    txt = sprintf(['slope = %.3g \\pm %.2g per s (SE)\nr = %.2f,  R^2 = %.3f\n' ...
        't(%d) = %.2f,  p = %s'], st.slope, st.slopeSE, st.r, st.R2, st.df, st.t, fmt_p(st.p));
    text(0.98, 0.97, txt, 'Units', 'normalized', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
        'BackgroundColor', [1 1 1 0.85], 'EdgeColor', [0.7 0.7 0.7], 'Margin', 4, 'FontSize', 9);
end
yline(0, ':', 'Color', [0.5 0.5 0.5], 'HandleVisibility', 'off');
if ~isempty(ylimits), ylim(ylimits); end
xlabel('Reaction time, colour onset \rightarrow response (s)'); ylabel(ylab);
title(ttl, 'FontWeight', 'normal');
legend('Location', 'southoutside', 'Orientation', 'horizontal', 'NumColumns', 3); grid on; box off;
end

function s = fmt_p(p)
if isnan(p), s = 'n/a';
elseif p < 1e-4, s = sprintf('%.1e', p);
else, s = sprintf('%.3f', p); end
end

function report_fit(label, st)
fprintf('%s: n = %d, slope = %.4g ± %.3g (SE) per s, intercept = %.4g, r = %.3f, R^2 = %.3f, t(%d) = %.2f, p = %s\n', ...
    label, st.n, st.slope, st.slopeSE, st.intercept, st.r, st.R2, st.df, st.t, fmt_p(st.p));
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

function L = list_dir(folder, pattern)
% dir() that works the same on Windows, macOS and Linux: drops hidden entries (macOS '._*'
% AppleDouble files and .DS_Store, which match patterns like '*_signals.csv') and sorts by
% name, since dir's order depends on the operating system.
L = dir(fullfile(folder, pattern));
L = L(~startsWith({L.name}, '.'));
[~, order] = sort({L.name});
L = L(order);
end

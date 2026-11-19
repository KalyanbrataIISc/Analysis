%% LEAF_ERP_ANALYSIS  Event-related potentials for one day of Leaf-game blocks.
%
% Companion of leaf_ssvep_analysis.m: same inputs, block pairing and marker handling.
% To analyse another day: change cfg.dataDir below and run. The day folder must contain
%   eeg_<...>/   BciCore logs (…_signals.csv with ch*_uv + marker, …_config.txt)
%   gameData/    p<P>_b<B>_leaves_trialdata.csv (one per block)
% EEG folders are matched to game blocks by their trial-start marker sequences.
%
% Figures (PNG + FIG), per-trial table and a results .mat are written to cfg.outDir. The figures are
% made twice: for all blocks pooled (in cfg.outDir) and for each block alone (cfg.outDir/block_<N>/).
%
% Events (cfg.events)
%   Pre-SSVEP onset  trial-start marker - the trial's PreSsvepSec from the game file (cfg.preSsvepSec = [];
%                    a number forces that fixed offset instead)
%   Trial start      trial-start marker (31-34 / legacy 20-21), sent at the end of trial frame 1
%   Colour onset     reveal marker 50; on NF reveal timeouts (no 50) the game-clock offset from the
%                    start marker is used (cfg.includeRevealTimeouts)
%   Trial end        trial-stop marker 30, sent at the end of the last feedback frame; the screen is
%                    then cleared for the ITI
%
% Each epoch is baseline-corrected (cfg.events(e).baselineSec) and rejected if any channel exceeds
% cfg.rejectUv anywhere in the window. ERP = mean ± SEM across trials.
%
% Plots
%   1-4. One figure per event: ERP of every channel (one subplot per channel).
%   5.   Mean over all channels, one subplot per event (pooled figure: thin lines = per-block
%        averages).
%
% Note: the mean over channels of a common-average-referenced signal is zero, so cfg.pre.car is
% off by default. With it on, plot 5 is flat.

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
cfg.outDir      = fullfile(projectRoot, 'plots', [dayTag '_leaf_erp_matlab']);

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

% ---- Preprocessing for ERPs (whole recording, zero-phase Butterworth in second-order sections) ----
cfg.pre.highpassHz   = 0.1;    % high-pass; [] to skip (BciCore already applies a ~0.16 Hz DC blocker)
cfg.pre.lowpassHz    = 30;     % low-pass; [] to skip
cfg.pre.filterOrder  = 4;
cfg.pre.notchHz      = 50;     % line-noise band-stop centre; [] to skip
cfg.pre.notchWidthHz = 2;      % total width of the band-stop
cfg.pre.ssvepStop    = false;  % also band-stop every SSVEP frequency (removes the flicker response)
cfg.pre.ssvepWidthHz = 1;      % total width of each SSVEP band-stop
cfg.pre.car          = false;  % common-average re-reference (makes the channel mean, plot 5, zero)

% ---- Events ----
cfg.preSsvepSec = [];    % pre-SSVEP onset = trial start - this (s); [] = per-trial PreSsvepSec from the game file
cfg.events = struct( ...
    'key',         {'pre_ssvep_onset', 'trial_start', 'colour_onset', 'trial_end'}, ...
    'label',       {'Pre-SSVEP onset', 'Trial start', 'Colour onset', 'Trial end'}, ...
    'anchor',      {'preSsvep', 'start', 'colour', 'stop'}, ... % do not change
    'windowSec',   {[-0.5 1.5], [-0.5 1.0], [-0.5 1.0], [-0.5 1.0]}, ...   % epoch around the event (s)
    'baselineSec', {[-0.2 0],   [-0.2 0],   [-0.2 0],   [-0.2 0]});      % subtracted per channel (s)

% ---- Trial selection and artefacts ----
cfg.trials = 'all';              % 'all', 'responded' (response given) or 'correct'
cfg.includeRevealTimeouts = true; % colour onset of trials whose colour appeared after the NF reveal
                                  % timeout (no 50 marker; onset taken from the game clock)
cfg.rejectUv = 150;              % drop an epoch if any channel's |baseline-corrected EEG| exceeds this (Inf = keep all)

% ---- Plot appearance ----
cfg.plot.erpYLim      = [];      % per-channel figures (shared by all channels); [] = automatic
cfg.plot.grandYLim    = [];      % grand-average figure; [] = automatic
cfg.plot.negativeUp   = false;   % true = negative up
cfg.plot.showBlocks   = true;    % per-block averages as thin lines in the grand-average figure
cfg.plot.colERP       = [0.00 0.45 0.70];
cfg.plot.colBlocks    = [0.60 0.60 0.60];
cfg.plot.colEventLine = [0.84 0.37 0.00];  % other events at a fixed offset (e.g. trial start in plot 1)
cfg.plot.alpha        = 0.25;    % SEM shading
cfg.plot.theme        = 'light'; % 'light' or 'dark' (R2025a+ follows the desktop theme otherwise)
cfg.plot.formats      = {'png', 'fig'};
cfg.plot.dpi          = 300;
%% =============================================================================

if ~exist(cfg.outDir, 'dir'), mkdir(cfg.outDir); end
nE = numel(cfg.events);

%% ----------------------------- Load game files ------------------------------
gameRuns = load_game_runs(cfg);
fprintf('Found %d game run(s) in %s\n', numel(gameRuns), cfg.gameDir);
allF = [];
for g = 1:numel(gameRuns), allF = [allF; gameRuns(g).T.FrequencyC1Hz; gameRuns(g).T.FrequencyC2Hz]; end %#ok<AGROW>
ssvepHz = unique(round(allF(:)' * 1000) / 1000);

%% ------------------- Load, preprocess, pair and epoch EEG blocks ------------
eegDirs = list_dir(cfg.dataDir, cfg.eegPattern);
eegDirs = eegDirs([eegDirs.isdir]);
if isempty(eegDirs), error('No EEG folders matching %s in %s', cfg.eegPattern, cfg.dataDir); end

ep      = cell(nE, 0);   % ep{e, b}: samples x channels x kept trials
blocks  = struct([]);
rows    = {};
fs = [];
for d = 1:numel(eegDirs)
    folder = fullfile(eegDirs(d).folder, eegDirs(d).name);
    sigFile = list_dir(folder, '*_signals.csv');
    if isempty(sigFile), warning('No _signals.csv in %s, skipped', folder); continue; end
    fsB = read_fs(folder, cfg.fsDefault);
    if isempty(fs), fs = fsB; elseif fsB ~= fs, error('Blocks have different sampling rates.'); end
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
    check_stop_timing(trials, T, fs, eegDirs(d).name);

    Xp = preprocess_erp(X, fs, cfg.pre, ssvepHz);
    if any(~isfinite(Xp(:)))
        error('%s: %d non-finite samples after preprocessing', eegDirs(d).name, nnz(~isfinite(Xp)));
    end
    N = size(Xp, 1);

    % pre-SSVEP offset: fixed, or the game's per-trial PreSsvepSec
    if ismember('PreSsvepSec', T.Properties.VariableNames), gamePre = T.PreSsvepSec; else, gamePre = nan(nPair, 1); end
    if isempty(cfg.preSsvepSec)
        preSec = gamePre;
        if any(isnan(preSec)), error('%s: no PreSsvepSec in the game file; set cfg.preSsvepSec', eegDirs(d).name); end
    else
        preSec = repmat(cfg.preSsvepSec, nPair, 1);
        bad = abs(gamePre - cfg.preSsvepSec) > 1e-3;
        if any(bad)
            warning(['%s: cfg.preSsvepSec = %g s but the game''s PreSsvepSec is %s s for %d/%d trials; ' ...
                'the "pre-SSVEP onset" epochs are not locked to the real pre-SSVEP onset there'], ...
                eegDirs(d).name, cfg.preSsvepSec, mat2str(unique(gamePre(bad))'), nnz(bad), nPair);
        end
    end

    b = numel(blocks) + 1;
    blocks(b).name      = eegDirs(d).name;
    blocks(b).blockNum  = gameRuns(g).block;
    blocks(b).gameFile  = gameRuns(g).file;
    blocks(b).fs        = fs;
    blocks(b).chanNames = chanNames;
    blocks(b).nTrials   = nPair;
    blocks(b).status    = cell(nPair, nE);   % per trial and event: used / reason not used
    blocks(b).evTime    = nan(nPair, nE);    % event time in the recording (s)
    if b > 1 && ~isequal(chanNames, blocks(1).chanNames), error('%s: channels differ from the first block', blocks(b).name); end

    for e = 1:nE
        w = cfg.events(e).windowSec; bl = cfg.events(e).baselineSec;
        if bl(1) < w(1) || bl(2) > w(2), error('Event %s: baseline lies outside the epoch window', cfg.events(e).key); end
        rel = round(w(1) * fs):round(w(2) * fs);
        iBl = rel >= round(bl(1) * fs) & rel <= round(bl(2) * fs);
        E = nan(numel(rel), size(Xp, 2), nPair);
        status = repmat({''}, nPair, 1); evTime = nan(nPair, 1);
        for j = 1:nPair
            s0 = event_sample(cfg.events(e).anchor, trials(j), T(j, :), preSec(j), fs, cfg);
            if isnan(s0), status{j} = 'no event'; continue; end
            evTime(j) = (s0 - 1) / fs;
            if ~trial_selected(T(j, :), cfg.trials), status{j} = 'excluded (selection)'; continue; end
            idx = s0 + rel;
            if idx(1) < 1 || idx(end) > N, status{j} = 'out of recording'; continue; end
            x = Xp(idx, :);
            x = x - mean(x(iBl, :), 1);
            if max(abs(x(:))) > cfg.rejectUv, status{j} = 'rejected (artefact)'; continue; end
            E(:, :, j) = x;
            status{j} = 'used';
        end
        used = strcmp(status, 'used');
        ep{e, b} = E(:, :, used);
        blocks(b).status(:, e) = status;
        blocks(b).evTime(:, e) = evTime;
    end

    for j = 1:nPair
        rows(end+1, :) = [{blocks(b).blockNum, T.TrialNumber(j), rule_name(T.Cue(j), {'Pointing', 'Moving'}), ...
            T.Accuracy(j), T.ResponseTimeout(j), T.RevealTimeout(j), T.ReactionTime(j), gamePre(j)}, ...
            reshape([num2cell(blocks(b).evTime(j, :)); blocks(b).status(j, :)], 1, [])]; %#ok<SAGROW>
    end
    fprintf('%s -> block %d (%s): %d channels, %d trials; epochs used per event: %s\n', blocks(b).name, ...
        blocks(b).blockNum, gameRuns(g).file, size(Xp, 2), nPair, ...
        mat2str(cellfun(@(s) nnz(strcmp(s, 'used')), num2cell(blocks(b).status, 1))));
    clear X Xp E
end
if isempty(blocks), error('No EEG folder could be paired with a game file.'); end
[~, order] = sort([blocks.blockNum]);
blocks = blocks(order); ep = ep(:, order);
nB = numel(blocks);
blockNums = [blocks.blockNum];
chanNames = blocks(1).chanNames;
nCh = numel(chanNames);

evCols = reshape([strcat({cfg.events.key}, '_time_s'); strcat({cfg.events.key}, '_status')], 1, []);
trialTable = cell2table(rows, 'VariableNames', [{'Block', 'TrialNumber', 'Rule', 'Accuracy', ...
    'ResponseTimeout', 'RevealTimeout', 'ReactionTime', 'GamePreSsvepSec'}, evCols]);
trialTable = sortrows(trialTable, {'Block', 'TrialNumber'}, 'ascend');

%% ------------------------------- ERP averages -------------------------------
erp = compute_erp(ep, cfg, fs, nCh);                 % all blocks pooled
erpByBlock = cell(1, nB);                            % each block on its own
for b = 1:nB, erpByBlock{b} = compute_erp(ep(:, b), cfg, fs, nCh); end

%% -------------------------------- Figures ------------------------------------
% all blocks pooled -> cfg.outDir; each block -> cfg.outDir/block_<N>
preTxt = pre_ssvep_text(cfg, trialTable.GamePreSsvepSec);
blkTxt = strjoin(arrayfun(@num2str, blockNums, 'UniformOutput', false), ', ');
scope = struct('desc', sprintf('%s · blocks %s pooled', dayTag, blkTxt), 'multiBlock', nB > 1, ...
    'grandTitle', 'Grand-average ERP: mean over all channels and all blocks');
plot_erp_set(erp, cfg.outDir, scope, preTxt, pre_mark(cfg, trialTable.GamePreSsvepSec), chanNames, cfg);
for b = 1:nB
    bDir = fullfile(cfg.outDir, sprintf('block_%d', blockNums(b)));
    if ~exist(bDir, 'dir'), mkdir(bDir); end
    gp = trialTable.GamePreSsvepSec(trialTable.Block == blockNums(b));
    scope = struct('desc', sprintf('%s · block %d', dayTag, blockNums(b)), 'multiBlock', false, ...
        'grandTitle', sprintf('ERP of block %d: mean over all channels', blockNums(b)));
    plot_erp_set(erpByBlock{b}, bDir, scope, pre_ssvep_text(cfg, gp), pre_mark(cfg, gp), chanNames, cfg);
end

%% ------------------------------- Save & report ------------------------------
writetable(trialTable, fullfile(cfg.outDir, 'trials.csv'));
blockInfo = rmfield(blocks, {'status', 'evTime'});
results = struct('cfg', cfg, 'fs', fs, 'chanNames', {chanNames}, 'blockNums', blockNums, 'erp', erp, ...
    'erpByBlock', {erpByBlock}, 'trialTable', trialTable, 'blockInfo', blockInfo);
save(fullfile(cfg.outDir, 'results.mat'), '-struct', 'results', '-v7.3');

fprintf('\n=== ERP epochs (%s, %s trials, reject > %g µV) ===\n', dayTag, cfg.trials, cfg.rejectUv);
fprintf('%-16s %6s %9s %9s %9s %9s\n', 'Event', 'used', 'rejected', 'no event', 'excluded', 'outside');
for e = 1:nE
    s = trialTable.(sprintf('%s_status', cfg.events(e).key));
    fprintf('%-16s %6d %9d %9d %9d %9d\n', cfg.events(e).label, nnz(strcmp(s, 'used')), ...
        nnz(startsWith(s, 'rejected')), nnz(strcmp(s, 'no event')), nnz(startsWith(s, 'excluded')), ...
        nnz(strcmp(s, 'out of recording')));
end
fprintf('%s\n', preTxt);
fprintf('Outputs written to %s\n', cfg.outDir);


%% ============================== LOCAL FUNCTIONS ===============================

function erp = compute_erp(ep, cfg, fs, nCh)
% ERPs of the epochs in ep (events x blocks cell of samples x channels x trials): every channel and
% the channel mean, mean ± SEM across trials of all given blocks, plus each block's average.
nE = size(ep, 1); nB = size(ep, 2);
erp = struct('key', {cfg.events.key}, 'label', {cfg.events.label}, 't', [], 'n', [], 'nBlock', [], ...
    'mean', [], 'sem', [], 'blockMean', [], 'grandMean', [], 'grandSem', [], 'grandBlockMean', []);
for e = 1:nE
    w = cfg.events(e).windowSec;
    erp(e).t = (round(w(1) * fs):round(w(2) * fs))' / fs;
    A = cat(3, ep{e, :});                       % samples x channels x trials
    erp(e).n = size(A, 3);
    erp(e).nBlock = cellfun(@(x) size(x, 3), ep(e, :));
    [erp(e).mean, erp(e).sem] = mean_sem(A, 3);
    [erp(e).grandMean, erp(e).grandSem] = mean_sem(reshape(mean(A, 2), size(A, 1), []), 2);  % channel mean per trial
    erp(e).blockMean = nan(numel(erp(e).t), nCh, nB);
    erp(e).grandBlockMean = nan(numel(erp(e).t), nB);
    for b = 1:nB
        if isempty(ep{e, b}), continue; end
        erp(e).blockMean(:, :, b) = mean(ep{e, b}, 3);
        erp(e).grandBlockMean(:, b) = mean(erp(e).blockMean(:, :, b), 2);
    end
end
end

function plot_erp_set(erp, outDir, scope, preTxt, preMark, chanNames, cfg)
% Figures 1..nE: one per event, every channel in its own subplot.
% Figure nE+1: channel mean, one subplot per event (per-block lines when scope.multiBlock).
nE = numel(erp); nCh = numel(chanNames);
nCols = min(nCh, 4); nRows = ceil(nCh / nCols);
for e = 1:nE
    fig = figure('Name', ['ERP ' cfg.events(e).label], 'Color', 'w', 'Position', [40 40 300 * nCols, 250 * nRows + 90]);
    tl = tiledlayout(fig, nRows, nCols, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = gobjects(1, nCh);
    for c = 1:nCh
        ax(c) = nexttile(tl);
        plot_erp(ax(c), erp(e).t, erp(e).mean(:, c), erp(e).sem(:, c), [], e, preMark, cfg);
        title(ax(c), strrep(chanNames{c}, '_', '\_'), 'FontWeight', 'normal');
        if mod(c - 1, nCols) == 0, ylabel(ax(c), 'Amplitude (µV)'); end
        if c > nCh - nCols, xlabel(ax(c), sprintf('Time from %s (s)', lower_first(cfg.events(e).label))); end
    end
    set_ylim(ax, [erp(e).mean - erp(e).sem; erp(e).mean + erp(e).sem], cfg.plot.erpYLim);
    title(tl, sprintf('ERP locked to %s, every channel', lower_first(cfg.events(e).label)), 'FontSize', 11);
    sub = {sprintf('%s · n = %d trials (%s), mean \\pm SEM across trials', scope.desc, erp(e).n, cfg.trials), ...
        sprintf('baseline [%g, %g] s · %s · reject |x| > %g µV', cfg.events(e).baselineSec, ...
        filter_text(cfg.pre), cfg.rejectUv)};
    if strcmp(cfg.events(e).anchor, 'preSsvep'), sub{end+1} = preTxt; end %#ok<AGROW>
    subtitle(tl, sub, 'FontSize', 9);
    save_fig(fig, fullfile(outDir, sprintf('%d_erp_%s_by_channel', e, cfg.events(e).key)), cfg.plot);
    close(fig);
end

showBlocks = cfg.plot.showBlocks && scope.multiBlock;
nColsG = min(nE, 2); nRowsG = ceil(nE / nColsG);
fig = figure('Name', 'Channel-mean ERPs', 'Color', 'w', 'Position', [60 60 520 * nColsG, 330 * nRowsG + 90]);
tl = tiledlayout(fig, nRowsG, nColsG, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = gobjects(1, nE); lims = [];
for e = 1:nE
    ax(e) = nexttile(tl);
    if showBlocks, blk = erp(e).grandBlockMean; else, blk = []; end
    plot_erp(ax(e), erp(e).t, erp(e).grandMean, erp(e).grandSem, blk, e, preMark, cfg);
    title(ax(e), sprintf('%s (n = %d)', cfg.events(e).label, erp(e).n), 'FontWeight', 'normal');
    if strcmp(cfg.events(e).anchor, 'preSsvep'), subtitle(ax(e), preTxt, 'FontSize', 8); end
    xlabel(ax(e), sprintf('Time from %s (s)', lower_first(cfg.events(e).label)));
    if mod(e - 1, nColsG) == 0, ylabel(ax(e), 'Amplitude (µV)'); end
    lims = [lims; erp(e).grandMean - erp(e).grandSem; erp(e).grandMean + erp(e).grandSem]; %#ok<AGROW>
    if showBlocks, lims = [lims; erp(e).grandBlockMean(:)]; end %#ok<AGROW>
end
set_ylim(ax, lims, cfg.plot.grandYLim);
if showBlocks, blkLeg = ', thin grey = per-block averages'; else, blkLeg = ''; end
title(tl, scope.grandTitle, 'FontSize', 11);
subtitle(tl, {sprintf('%s · %d channels · %s trials · mean \\pm SEM across trials%s', scope.desc, nCh, ...
    cfg.trials, blkLeg), sprintf('%s · reject |x| > %g µV', filter_text(cfg.pre), cfg.rejectUv)}, 'FontSize', 9);
save_fig(fig, fullfile(outDir, sprintf('%d_erp_grand_average', nE + 1)), cfg.plot);
close(fig);
end

function m = pre_mark(cfg, gamePre)
% Pre-SSVEP onset -> trial start offset for the reference line ([] unless the same in every trial).
if ~isempty(cfg.preSsvepSec), m = cfg.preSsvepSec; else, m = unique(gamePre(~isnan(gamePre))); end
if numel(m) ~= 1, m = []; end
end

function s0 = event_sample(anchor, tr, row, preSec, fs, cfg)
% Sample index of an event in one trial (NaN if the trial has none).
switch anchor
    case 'preSsvep'
        s0 = tr.start - round(preSec * fs);
    case 'start'
        s0 = tr.start;
    case 'colour'
        if ~isnan(tr.reveal)
            s0 = tr.reveal;
        elseif cfg.includeRevealTimeouts && isfinite(row.ColorOnsetTime)
            s0 = tr.start + round((row.ColorOnsetTime - row.TrialStart) * fs);
        else
            s0 = NaN;
        end
    case 'stop'
        s0 = tr.stop;
    otherwise
        error('Unknown event anchor %s', anchor);
end
end

function s = lower_first(s)
% 'Trial start' -> 'trial start', 'Pre-SSVEP onset' -> 'pre-SSVEP onset'
s(1) = lower(s(1));
end

function ok = trial_selected(row, mode)
switch mode
    case 'all',       ok = true;
    case 'responded', ok = row.ResponseTimeout == 0 && ~isnan(row.ReactionTime);
    case 'correct',   ok = row.Accuracy == 1 && row.ResponseTimeout == 0 && ~isnan(row.ReactionTime);
    otherwise, error('cfg.trials must be ''all'', ''responded'' or ''correct''');
end
end

function check_stop_timing(trials, T, fs, name)
% Start -> trial-end markers vs the game clock (TrialEnd - TrialStart).
dEEG = ([trials.stop]' - [trials.start]') / fs;
res = abs(dEEG - (T.TrialEnd - T.TrialStart));
res = res(~isnan(res));
if isempty(res), return; end
fprintf('%s: start->trial end EEG vs game clock, max |difference| = %.0f ms (%d trials)\n', ...
    name, 1000 * max(res), numel(res));
if max(res) > 0.1
    warning('%s: trial-end marker and game TrialEnd differ by more than 100 ms', name);
end
end

function Xp = preprocess_erp(X, fs, p, ssvepHz)
% Zero-phase Butterworth filters in second-order sections (stable at very low cut-offs), optional CAR.
Xp = X - mean(X, 1);
if ~isempty(p.highpassHz)
    [z, pl, k] = butter(p.filterOrder, p.highpassHz / (fs/2), 'high');
    [sos, gn] = zp2sos(z, pl, k); Xp = filtfilt(sos, gn, Xp);
end
if ~isempty(p.lowpassHz)
    [z, pl, k] = butter(p.filterOrder, p.lowpassHz / (fs/2), 'low');
    [sos, gn] = zp2sos(z, pl, k); Xp = filtfilt(sos, gn, Xp);
end
stops = [];
if ~isempty(p.notchHz), stops = [stops; p.notchHz, p.notchWidthHz]; end
if p.ssvepStop, stops = [stops; ssvepHz(:), repmat(p.ssvepWidthHz, numel(ssvepHz), 1)]; end
for i = 1:size(stops, 1)
    edges = stops(i, 1) + [-1 1] * stops(i, 2) / 2;
    if edges(2) >= fs/2, continue; end
    [z, pl, k] = butter(2, edges / (fs/2), 'stop');
    [sos, gn] = zp2sos(z, pl, k); Xp = filtfilt(sos, gn, Xp);
end
if p.car
    Xp = Xp - mean(Xp, 2);
end
end

function txt = filter_text(p)
parts = {};
if ~isempty(p.highpassHz) || ~isempty(p.lowpassHz)
    parts{end+1} = sprintf('%s-%s Hz', num2str(p.highpassHz), num2str(p.lowpassHz));
end
if ~isempty(p.notchHz), parts{end+1} = sprintf('%g Hz notch', p.notchHz); end
if p.ssvepStop, parts{end+1} = 'SSVEP band-stop'; end
if p.car, parts{end+1} = 'CAR'; else, parts{end+1} = 'no re-reference'; end
txt = strjoin(parts, ', ');
end

function txt = pre_ssvep_text(cfg, gamePre)
g = unique(gamePre(~isnan(gamePre)))';
if isempty(cfg.preSsvepSec)
    txt = sprintf('Pre-SSVEP onset = trial start - game PreSsvepSec (%s s)', mat2str(g));
elseif isempty(g) || all(abs(g - cfg.preSsvepSec) < 1e-3)
    txt = sprintf('Pre-SSVEP onset = trial start - %g s', cfg.preSsvepSec);
else
    txt = sprintf('Pre-SSVEP onset = trial start - %g s (game PreSsvepSec = %s s: not the real pre-SSVEP onset)', ...
        cfg.preSsvepSec, mat2str(g));
end
end

function [m, s] = mean_sem(A, dim)
n = size(A, dim);
m = mean(A, dim);
if n > 1, s = std(A, 0, dim) / sqrt(n); else, s = nan(size(m)); end
if n == 0, m = nan(size(m)); s = m; end
end

function plot_erp(ax, t, m, s, blk, e, preMark, cfg)
% Mean ± SEM, optional per-block lines, zero lines and other events at a fixed offset.
hold(ax, 'on');
if ~isempty(blk)
    plot(ax, t, blk, '-', 'Color', cfg.plot.colBlocks, 'LineWidth', 0.6);
end
if ~all(isnan(s))
    fill(ax, [t; flipud(t)], [m - s; flipud(m + s)], cfg.plot.colERP, 'FaceAlpha', cfg.plot.alpha, 'EdgeColor', 'none');
end
plot(ax, t, m, '-', 'Color', cfg.plot.colERP, 'LineWidth', 1.4);
xline(ax, 0, '-', 'Color', [0.3 0.3 0.3]);
yline(ax, 0, ':', 'Color', [0.5 0.5 0.5]);
% pre-SSVEP onset and trial start are a fixed time apart: mark the other one if it is in the window
if ~isempty(preMark)
    switch cfg.events(e).anchor
        case 'preSsvep', x = preMark;  lab = 'trial start';
        case 'start',    x = -preMark; lab = 'pre-SSVEP';
        otherwise,       x = NaN; lab = '';
    end
    if x >= t(1) && x <= t(end)
        xline(ax, x, '--', lab, 'Color', cfg.plot.colEventLine, 'FontSize', 8, 'LabelVerticalAlignment', 'bottom');
    end
end
xlim(ax, [t(1) t(end)]);
if cfg.plot.negativeUp, set(ax, 'YDir', 'reverse'); end
grid(ax, 'on'); box(ax, 'off');
end

function set_ylim(ax, vals, fixed)
if ~isempty(fixed), set(ax, 'YLim', fixed); return; end
vals = vals(isfinite(vals));
if isempty(vals), return; end
r = [min(vals), max(vals)]; pad = 0.08 * max(diff(r), eps);
set(ax, 'YLim', [r(1) - pad, r(2) + pad]);
end

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

function name = rule_name(cue, names)
if strcmpi(strtrim(cue), "c1"), name = names{1}; else, name = names{2}; end
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

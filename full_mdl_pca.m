clearvars -except dataX dataY dataZ dataXY dataXZ dataYZ dataXYZ
close all; clc

% CONFIGURATION PANEL

cfg = struct();

% Set true if you want this script to create dataX, dataY, dataZ, dataXY, dataXZ, dataYZ, dataXYZ using prepData().
cfg.run_data_setup = false;

% Dataset suffixes passed to prepData() when cfg.run_data_setup = true.
cfg.K_values = {'X','Y','Z','XY','XZ','YZ','XYZ'};

% Datasets used for PCA and movement analyses.
cfg.datasetNamesWanted = {'dataX','dataY','dataZ','dataXY','dataXZ','dataYZ','dataXYZ'};

% Velocity threshold that starts a movement.
cfg.onset_velocity_threshold  = 0.0002;

% Velocity threshold used to end a movement.
cfg.offset_velocity_threshold = 0.00007;

% Number of consecutive below-threshold bins required to end a movement.
cfg.movement_end_criterion    = 10;

% Time interval used from each dataset. Use [1 inf] for the full recording.
cfg.time_interval = [1, inf];

% Neuron interval used from each dataset. Use [1 inf] for all common neurons.
cfg.pixel_interval = [1, inf];

% If true, the PCA uses only neuron IDs present in every selected dataset.
cfg.use_common_neuron_count = true;

% Z-score mode before PCA: 'global', 'perDataset', or 'none'.
cfg.zscore_mode = 'global';

% Axis mapping from original position columns to internal [X Y Z]. Use [3 2 1] if original is [Z Y X].
cfg.axis_order_original_to_internal = [3 2 1];

% Minimum displacement needed to classify an axis direction.
cfg.delta_eps = 0.01;

% If true, classify movement direction using position before onset versus position near movement offset.
cfg.compare_pos_at_end = true;

% Number of bins before offset used for end-position comparison.
cfg.pos_offset_from_end = 0;

% Window around movement onset used for movement labels and trajectories.
cfg.pre_post_window = [-60, 90];

% Preparation phase window relative to onset.
cfg.phase_preparation_window = [-60, -1];

% Last relative bin included in attenuation.
cfg.phase_attenuation_end = 90;

% Number of PCs to compute and analyze.
cfg.nPCsToAnalyze = 20;

% Number of top loading neurons stored per PC.
cfg.nTopLoadingNeurons = 10;

% Row stride for PCA. Use 1 for all bins, 2 for every second bin, etc.
cfg.row_stride_for_pca = 1;

% If true, compute PC encoding statistics.
cfg.run_pc_statistics = true;

% If true, run single-PC classification checks.
cfg.run_single_pc_classifiers = true;

% Number of folds for classifiers.
cfg.classifier_kfold = 5;

% If true, make summary figures from the PCA analysis.
cfg.enable_figures = true;

% If true, save generated figures.
cfg.save_figures = false;

% Folder for saved figures.
cfg.output_folder = 'GLOBAL_PCA_OUTPUTS';

% Smoothing window for average trajectories.
cfg.smooth_window = 10;

% Maximum number of PC trajectory summary figures.
cfg.max_pc_trajectory_figures = 20;

% If true, create ALL_MOVEMENT_RECORDS including multi-axis movements.
cfg.run_all_movement_screening = true;

% If true, run the PC-vs-PC environment trajectory plot after PCA.
cfg.run_pc_environment_plot = true;

% PC used on the x-axis of the PC-vs-PC trajectory plot.
cfg.plot.pcX = 6;

% PC used on the y-axis of the PC-vs-PC trajectory plot.
cfg.plot.pcY = 3;

% Divisor applied to the x-axis PC score.
cfg.plot.pcX_divisor = 0.75;

% Divisor applied to the y-axis PC score.
cfg.plot.pcY_divisor = 1;

% Time window relative to onset used in the PC-vs-PC plot.
cfg.plot.time_window = [0, 40];

% Environments included in the PC-vs-PC plot.
cfg.plot.environmentsToPlot = {'dataX','dataY','dataZ','dataXY','dataXZ','dataYZ'};

% Targets included in the PC-vs-PC plot.
cfg.plot.targetsToPlot = {'+Y','-Y','+X','-X'};

% Smoothing window for the PC-vs-PC plot.
cfg.plot.smooth_window = 5;

% If true, show legend on the PC-vs-PC plot.
cfg.plot.show_legend = true;

% If true, use equal axis scaling on the PC-vs-PC plot.
cfg.plot.use_equal_axis = true;

% If true, show zero lines on the PC-vs-PC plot.
cfg.plot.show_zero_lines = true;

% Title for the PC-vs-PC plot.
cfg.plot.title = 'PC neural trajectories by target and environment';

% If true, write key tables to CSV files.
cfg.write_csv = true;

rng(1);

if cfg.save_figures && ~exist(cfg.output_folder, 'dir')
    mkdir(cfg.output_folder);
end

if cfg.run_data_setup
    for i = 1:numel(cfg.K_values)
        K = cfg.K_values{i};
        dataK = prepData(K);
        varName = ['data' K];
        assignin('base', varName, dataK);
        fprintf('Saved %s\n', varName);
    end
end

availableDatasetNames = {};
for i = 1:numel(cfg.datasetNamesWanted)
    nm = cfg.datasetNamesWanted{i};
    if evalin('base', sprintf('exist(''%s'',''var'')', nm)) || exist(nm,'var')
        availableDatasetNames{end+1} = nm;
    end
end

if isempty(availableDatasetNames)
    error('No requested datasets found. Expected selected data variables in the workspace or set cfg.run_data_setup = true.');
end

fprintf('\nAvailable datasets:\n');
disp(availableDatasetNames(:));

if cfg.run_all_movement_screening
    ALL_MOVEMENT_RECORDS = buildAllMovementRecords(availableDatasetNames, cfg);
    assignin('base', 'ALL_MOVEMENT_RECORDS', ALL_MOVEMENT_RECORDS);
    fprintf('Exported to workspace: ALL_MOVEMENT_RECORDS\n');
end

nNeuronsEach = zeros(numel(availableDatasetNames),1);
nTimeEach = zeros(numel(availableDatasetNames),1);

for d = 1:numel(availableDatasetNames)
    dsName = availableDatasetNames{d};
    data = getDatasetFromWorkspace(dsName);
    assert(isfield(data,'Kinematics') && isfield(data.Kinematics,'ActualPos'), '%s missing Kinematics.ActualPos', dsName);
    assert(isfield(data,'Kinematics') && isfield(data.Kinematics,'ActualVel'), '%s missing Kinematics.ActualVel', dsName);
    assert(isfield(data,'SpikeCount'), '%s missing SpikeCount', dsName);
    nTimeEach(d) = size(data.SpikeCount,1);
    nNeuronsEach(d) = size(data.SpikeCount,2);
end

p_min = max(1, round(cfg.pixel_interval(1)));
p_max_user = cfg.pixel_interval(2);
if isinf(p_max_user)
    p_max_common = min(nNeuronsEach);
else
    p_max_common = min(min(nNeuronsEach), round(p_max_user));
end

globalNeuronIDs = p_min:p_max_common;

if isempty(globalNeuronIDs)
    error('No valid neurons selected. Check cfg.pixel_interval and dataset neuron counts.');
end

fprintf('Using %d neurons for global PCA: neuron IDs %d to %d.\n', numel(globalNeuronIDs), globalNeuronIDs(1), globalNeuronIDs(end));

X_blocks = cell(numel(availableDatasetNames),1);
LABEL_blocks = cell(numel(availableDatasetNames),1);
DATASET_SUMMARY = table();
ALL = struct();

for d = 1:numel(availableDatasetNames)
    dsName = availableDatasetNames{d};
    data = getDatasetFromWorkspace(dsName);

    fprintf('\n==============================\n');
    fprintf('Processing %s\n', dsName);
    fprintf('==============================\n');

    pos = double(data.Kinematics.ActualPos);
    velRaw = double(data.Kinematics.ActualVel);
    spk = double(data.SpikeCount);

    T = size(spk,1);

    assert(size(pos,1)==T, '%s: ActualPos rows must match SpikeCount rows.', dsName);
    assert(size(velRaw,1)==T || numel(velRaw)==T, '%s: ActualVel rows/length must match SpikeCount rows.', dsName);

    posXYZ = pos(:, cfg.axis_order_original_to_internal);

    if isvector(velRaw)
        velXYZ = nan(T,3);
        speed = abs(double(velRaw(:)));
        velForDetection = double(velRaw(:));
    else
        if size(velRaw,2) >= 3
            velXYZ = double(velRaw(:, cfg.axis_order_original_to_internal));
            speed = sqrt(sum(velXYZ.^2, 2));
            velForDetection = speed;
        else
            velXYZ = nan(T,3);
            speed = abs(double(velRaw(:,1)));
            velForDetection = double(velRaw(:,1));
        end
    end

    t_min = max(1, round(cfg.time_interval(1)));
    if isinf(cfg.time_interval(2))
        t_max = T;
    else
        t_max = min(T, round(cfg.time_interval(2)));
    end
    assert(t_min <= t_max, '%s: invalid cfg.time_interval.', dsName);

    timeIdx = (t_min:t_max).';
    if cfg.row_stride_for_pca > 1
        timeIdx = timeIdx(1:cfg.row_stride_for_pca:end);
    end

    spkUse = spk(timeIdx, globalNeuronIDs);

    [movementRecords, binLabels] = detectMovementsAndLabelBins(dsName, posXYZ, velForDetection, speed, T, t_min, t_max, cfg);

    labelsThis = makeLabelTable(dsName, timeIdx, velForDetection, speed, velXYZ, posXYZ, movementRecords, binLabels, cfg);

    if strcmpi(cfg.zscore_mode, 'perDataset')
        spkUse = zscoreSafe(spkUse);
    end

    X_blocks{d} = spkUse;
    LABEL_blocks{d} = labelsThis;

    ALL.(dsName).datasetName = dsName;
    ALL.(dsName).timeIdx = timeIdx;
    ALL.(dsName).posXYZ = posXYZ;
    ALL.(dsName).velForDetection = velForDetection;
    ALL.(dsName).speed = speed;
    ALL.(dsName).velXYZ = velXYZ;
    ALL.(dsName).movementRecords = movementRecords;
    ALL.(dsName).binLabels = binLabels;

    nRows = numel(timeIdx);
    nMov = numel(movementRecords);
    taskDim = datasetNameToDim(dsName);

    Tsum = table({dsName}, taskDim, T, nRows, nMov, ...
        sum(strcmp(labelsThis.Target,'+X')), sum(strcmp(labelsThis.Target,'-X')), ...
        sum(strcmp(labelsThis.Target,'+Y')), sum(strcmp(labelsThis.Target,'-Y')), ...
        sum(strcmp(labelsThis.Target,'+Z')), sum(strcmp(labelsThis.Target,'-Z')), ...
        'VariableNames', {'Dataset','TaskDim','TotalBins','BinsUsed','NumMovements','Bins_posX','Bins_negX','Bins_posY','Bins_negY','Bins_posZ','Bins_negZ'});
    DATASET_SUMMARY = [DATASET_SUMMARY; Tsum];

    fprintf('%s: %d bins used for PCA; %d valid one-axis movements detected.\n', dsName, nRows, nMov);
end

Xall_raw = vertcat(X_blocks{:});
LABELS = vertcat(LABEL_blocks{:});

if strcmpi(cfg.zscore_mode, 'global')
    Xall = zscoreSafe(Xall_raw);
elseif strcmpi(cfg.zscore_mode, 'perDataset') || strcmpi(cfg.zscore_mode, 'none')
    Xall = Xall_raw;
else
    error('Unknown cfg.zscore_mode: %s', cfg.zscore_mode);
end

fprintf('\nGlobal PCA matrix size: %d rows/time-bins x %d neurons.\n', size(Xall,1), size(Xall,2));

maxPCs = min([cfg.nPCsToAnalyze, size(Xall,2), size(Xall,1)-1]);
if maxPCs < cfg.nPCsToAnalyze
    warning('Only %d PCs can be computed from current data size.', maxPCs);
end

fprintf('\nRunning memory-safe global PCA...\n');
[coeff, score, latent, explained, mu] = memorySafePCA_fromCovariance(Xall, maxPCs);

PC_SCORE_TABLE = LABELS;
for pc = 1:maxPCs
    PC_SCORE_TABLE.(sprintf('PC%d', pc)) = score(:,pc);
end

EXPLAINED_TABLE = table((1:maxPCs).', explained(:), cumsum(explained(:)), latent(:), ...
    'VariableNames', {'PC','ExplainedPercent','CumulativeExplainedPercent','Eigenvalue'});

PC_BREAKDOWN = table();
PC_ENCODING_STATS = struct();
PC_CLASSIFICATION = table();
PC_TARGET_PHASE_ETA = table();
PC_TARGET_ONEVREST_PHASE_ETA = table();
PC_TARGET_PREFERENCE_BY_PHASE = table();

if cfg.run_pc_statistics
    fprintf('\nComputing PC encoding statistics...\n');

    for pc = 1:maxPCs
        y = score(:,pc);
        pcName = sprintf('PC%d', pc);

        stats = struct();
        stats.Dataset = oneWayEncodingStrength(y, LABELS.Dataset);
        stats.TaskDim = oneWayEncodingStrength(y, categorical(LABELS.TaskDim));
        stats.Axis = oneWayEncodingStrength(y, LABELS.Axis);
        stats.Sign = oneWayEncodingStrength(y, LABELS.SignLabel);
        stats.Target = oneWayEncodingStrength(y, LABELS.Target);
        stats.Phase = oneWayEncodingStrength(y, LABELS.Phase);
        stats.VelAbs = continuousEncodingStrength(y, LABELS.VelAbs);
        stats.TimeRel = continuousEncodingStrength(y, LABELS.TimeRel);

        PC_ENCODING_STATS.(pcName) = stats;

        names = {'Dataset','TaskDim','Axis','Sign','Target','Phase','VelAbs','TimeRel'};
        etaVals = [stats.Dataset.Eta2, stats.TaskDim.Eta2, stats.Axis.Eta2, stats.Sign.Eta2, ...
                   stats.Target.Eta2, stats.Phase.Eta2, stats.VelAbs.R2, stats.TimeRel.R2];
        pVals = [stats.Dataset.P, stats.TaskDim.P, stats.Axis.P, stats.Sign.P, ...
                 stats.Target.P, stats.Phase.P, stats.VelAbs.P, stats.TimeRel.P];

        [bestVal, bestIdx] = max(etaVals);
        bestName = names{bestIdx};
        bestP = pVals(bestIdx);

        row = table(pc, explained(pc), sum(explained(1:pc)), ...
            stats.Dataset.Eta2, stats.Dataset.P, ...
            stats.TaskDim.Eta2, stats.TaskDim.P, ...
            stats.Axis.Eta2, stats.Axis.P, ...
            stats.Sign.Eta2, stats.Sign.P, ...
            stats.Target.Eta2, stats.Target.P, ...
            stats.Phase.Eta2, stats.Phase.P, ...
            stats.VelAbs.R2, stats.VelAbs.P, ...
            stats.TimeRel.R2, stats.TimeRel.P, ...
            {bestName}, bestVal, bestP, ...
            'VariableNames', {'PC','ExplainedPercent','CumulativeExplainedPercent', ...
            'Dataset_Eta2','Dataset_P','TaskDim_Eta2','TaskDim_P','Axis_Eta2','Axis_P', ...
            'Sign_Eta2','Sign_P','Target_Eta2','Target_P','Phase_Eta2','Phase_P', ...
            'Velocity_R2','Velocity_P','TimeRel_R2','TimeRel_P', ...
            'BestEncodedVariable','BestEncodingStrength','BestEncodingP'});

        PC_BREAKDOWN = [PC_BREAKDOWN; row];
    end

    [PC_TARGET_PHASE_ETA, PC_TARGET_ONEVREST_PHASE_ETA] = computeTargetEtaByPhase(score, LABELS, explained, maxPCs);
    PC_TARGET_PREFERENCE_BY_PHASE = computeTargetPreferenceByPhase(PC_TARGET_ONEVREST_PHASE_ETA);
end

if cfg.run_single_pc_classifiers
    fprintf('\nRunning single-PC classification checks...\n');
    labelSpecs = { ...
        'Dataset', LABELS.Dataset; ...
        'TaskDim', categorical(LABELS.TaskDim); ...
        'Axis', LABELS.Axis; ...
        'Sign', LABELS.SignLabel; ...
        'Target', LABELS.Target; ...
        'Phase', LABELS.Phase};

    for pc = 1:maxPCs
        xpc = score(:,pc);
        for k = 1:size(labelSpecs,1)
            labelName = labelSpecs{k,1};
            lab = labelSpecs{k,2};
            acc = singlePCClassifierAccuracy(xpc, lab, cfg.classifier_kfold);
            PC_CLASSIFICATION = [PC_CLASSIFICATION; table(pc, {labelName}, acc, ...
                'VariableNames', {'PC','LabelDecoded','Accuracy'})];
        end
    end
end

PC_LOADING_TABLE = table();
TOP5_NEURONS_BY_PC = table();
for pc = 1:maxPCs
    loadings = coeff(:,pc);
    [~, ordAbs] = sort(abs(loadings), 'descend');
    nTopLoad = min(cfg.nTopLoadingNeurons, numel(ordAbs));
    for r = 1:nTopLoad
        idx = ordAbs(r);
        rowLoad = table(pc, globalNeuronIDs(idx), loadings(idx), abs(loadings(idx)), r, ...
            'VariableNames', {'PC','NeuronID','Loading','AbsLoading','RankWithinPC'});
        PC_LOADING_TABLE = [PC_LOADING_TABLE; rowLoad];
        if r <= 5
            TOP5_NEURONS_BY_PC = [TOP5_NEURONS_BY_PC; rowLoad];
        end
    end
end

PC_TRAJ = buildMovementAlignedPCTrajectories(score, LABELS, cfg, maxPCs);

if cfg.enable_figures
    makeGlobalPCAFigures(EXPLAINED_TABLE, PC_BREAKDOWN, PC_CLASSIFICATION, PC_TRAJ, cfg, maxPCs);
end

GLOBAL_PCA_RESULTS = struct();
GLOBAL_PCA_RESULTS.cfg = cfg;
GLOBAL_PCA_RESULTS.availableDatasetNames = availableDatasetNames;
GLOBAL_PCA_RESULTS.globalNeuronIDs = globalNeuronIDs;
GLOBAL_PCA_RESULTS.Xall_raw = Xall_raw;
GLOBAL_PCA_RESULTS.Xall_used_for_PCA = Xall;
GLOBAL_PCA_RESULTS.LABELS = LABELS;
GLOBAL_PCA_RESULTS.coeff = coeff;
GLOBAL_PCA_RESULTS.score = score;
GLOBAL_PCA_RESULTS.latent = latent;
GLOBAL_PCA_RESULTS.explained = explained;
GLOBAL_PCA_RESULTS.mu = mu;
GLOBAL_PCA_RESULTS.PC_SCORE_TABLE = PC_SCORE_TABLE;
GLOBAL_PCA_RESULTS.EXPLAINED_TABLE = EXPLAINED_TABLE;
GLOBAL_PCA_RESULTS.PC_BREAKDOWN = PC_BREAKDOWN;
GLOBAL_PCA_RESULTS.PC_ENCODING_STATS = PC_ENCODING_STATS;
GLOBAL_PCA_RESULTS.PC_CLASSIFICATION = PC_CLASSIFICATION;
GLOBAL_PCA_RESULTS.PC_TARGET_PHASE_ETA = PC_TARGET_PHASE_ETA;
GLOBAL_PCA_RESULTS.PC_TARGET_ONEVREST_PHASE_ETA = PC_TARGET_ONEVREST_PHASE_ETA;
GLOBAL_PCA_RESULTS.PC_TARGET_PREFERENCE_BY_PHASE = PC_TARGET_PREFERENCE_BY_PHASE;
GLOBAL_PCA_RESULTS.TOP5_NEURONS_BY_PC = TOP5_NEURONS_BY_PC;
GLOBAL_PCA_RESULTS.PC_LOADING_TABLE = PC_LOADING_TABLE;
GLOBAL_PCA_RESULTS.DATASET_SUMMARY = DATASET_SUMMARY;
GLOBAL_PCA_RESULTS.PC_TRAJ = PC_TRAJ;
GLOBAL_PCA_RESULTS.ALL = ALL;

assignin('base', 'GLOBAL_PCA_RESULTS', GLOBAL_PCA_RESULTS);
assignin('base', 'GLOBAL_PCA_PC_BREAKDOWN', PC_BREAKDOWN);
assignin('base', 'GLOBAL_PCA_PC_LOADING_TABLE', PC_LOADING_TABLE);
assignin('base', 'GLOBAL_PCA_PC_SCORE_TABLE', PC_SCORE_TABLE);
assignin('base', 'GLOBAL_PCA_EXPLAINED_TABLE', EXPLAINED_TABLE);
assignin('base', 'GLOBAL_PCA_DATASET_SUMMARY', DATASET_SUMMARY);
assignin('base', 'GLOBAL_PCA_TARGET_PHASE_ETA', PC_TARGET_PHASE_ETA);
assignin('base', 'GLOBAL_PCA_TARGET_ONEVREST_PHASE_ETA', PC_TARGET_ONEVREST_PHASE_ETA);
assignin('base', 'GLOBAL_PCA_TARGET_PREFERENCE_BY_PHASE', PC_TARGET_PREFERENCE_BY_PHASE);
assignin('base', 'GLOBAL_PCA_TOP5_NEURONS_BY_PC', TOP5_NEURONS_BY_PC);

if cfg.run_pc_environment_plot
    plot_PC_environment_trajectories(GLOBAL_PCA_RESULTS, cfg.plot);
end

if cfg.write_csv
    writetable(GLOBAL_PCA_PC_BREAKDOWN, 'GLOBAL_PCA_PC_BREAKDOWN.csv');
    writetable(GLOBAL_PCA_EXPLAINED_TABLE, 'GLOBAL_PCA_EXPLAINED_TABLE.csv');
    writetable(GLOBAL_PCA_TARGET_PHASE_ETA, 'GLOBAL_PCA_TARGET_PHASE_ETA.csv');
    writetable(GLOBAL_PCA_TARGET_ONEVREST_PHASE_ETA, 'GLOBAL_PCA_TARGET_ONEVREST_PHASE_ETA.csv');
    writetable(GLOBAL_PCA_TARGET_PREFERENCE_BY_PHASE, 'GLOBAL_PCA_TARGET_PREFERENCE_BY_PHASE.csv');
    writetable(GLOBAL_PCA_TOP5_NEURONS_BY_PC, 'GLOBAL_PCA_TOP5_NEURONS_BY_PC.csv');
    if exist('ALL_MOVEMENT_RECORDS','var')
        writetable(ALL_MOVEMENT_RECORDS, 'ALL_MOVEMENT_RECORDS.csv');
    end
end

fprintf('\nDone. Main workspace outputs:\n');
fprintf('GLOBAL_PCA_RESULTS\n');
fprintf('GLOBAL_PCA_PC_BREAKDOWN\n');
fprintf('GLOBAL_PCA_PC_LOADING_TABLE\n');
fprintf('GLOBAL_PCA_PC_SCORE_TABLE\n');
fprintf('GLOBAL_PCA_EXPLAINED_TABLE\n');
fprintf('GLOBAL_PCA_DATASET_SUMMARY\n');
fprintf('GLOBAL_PCA_TARGET_PHASE_ETA\n');
fprintf('GLOBAL_PCA_TARGET_ONEVREST_PHASE_ETA\n');
fprintf('GLOBAL_PCA_TARGET_PREFERENCE_BY_PHASE\n');
fprintf('GLOBAL_PCA_TOP5_NEURONS_BY_PC\n');
if exist('ALL_MOVEMENT_RECORDS','var')
    fprintf('ALL_MOVEMENT_RECORDS\n');
end



function ALL_MOVEMENT_RECORDS = buildAllMovementRecords(availableDatasetNames, cfg)
    ALL_MOVEMENT_RECORDS = table();

    for d = 1:numel(availableDatasetNames)
        dsName = availableDatasetNames{d};
        data = getDatasetFromWorkspace(dsName);

        pos = double(data.Kinematics.ActualPos);
        velRaw = double(data.Kinematics.ActualVel);

        if isvector(velRaw)
            vel = velRaw(:);
        else
            if size(velRaw,2) >= 3
                velXYZ = double(velRaw(:, cfg.axis_order_original_to_internal));
                vel = sqrt(sum(velXYZ.^2, 2));
            else
                vel = double(velRaw(:,1));
            end
        end

        T = size(pos,1);
        posXYZ = pos(:, cfg.axis_order_original_to_internal);

        t_min = max(1, round(cfg.time_interval(1)));
        if isinf(cfg.time_interval(2))
            t_max = T;
        else
            t_max = min(T, round(cfg.time_interval(2)));
        end

        aboveOn  = abs(vel) >= cfg.onset_velocity_threshold;
        belowOff = abs(vel) <= cfg.offset_velocity_threshold;

        onsets = [];
        offsets = [];
        inMove = false;
        belowCount = 0;

        for t = t_min:t_max
            if ~inMove
                if aboveOn(t)
                    inMove = true;
                    belowCount = 0;
                    onsets(end+1,1) = t;
                end
            else
                if belowOff(t)
                    belowCount = belowCount + 1;
                    if belowCount >= cfg.movement_end_criterion
                        off = t - cfg.movement_end_criterion + 1;
                        offsets(end+1,1) = off;
                        inMove = false;
                        belowCount = 0;
                    end
                else
                    belowCount = 0;
                end
            end
        end

        if numel(offsets) < numel(onsets)
            offsets(end+1,1) = t_max;
        end

        signDB = @(x) (x > cfg.delta_eps) - (x < -cfg.delta_eps);

        for i = 1:numel(onsets)
            t0 = onsets(i);
            t1 = offsets(i);
            tBefore = max(1, t0-1);

            if cfg.compare_pos_at_end
                tAfter = t1 - cfg.pos_offset_from_end;
                tAfter = max(tAfter, t0+1);
                tAfter = min(T, max(1, tAfter));
            else
                tAfter = min(T, t0+1);
            end

            dXYZ = posXYZ(tAfter,:) - posXYZ(tBefore,:);
            sXYZ = [signDB(dXYZ(1)), signDB(dXYZ(2)), signDB(dXYZ(3))];

            directionParts = {};
            if sXYZ(1) > 0
                directionParts{end+1} = '+X';
            elseif sXYZ(1) < 0
                directionParts{end+1} = '-X';
            end
            if sXYZ(2) > 0
                directionParts{end+1} = '+Y';
            elseif sXYZ(2) < 0
                directionParts{end+1} = '-Y';
            end
            if sXYZ(3) > 0
                directionParts{end+1} = '+Z';
            elseif sXYZ(3) < 0
                directionParts{end+1} = '-Z';
            end

            if isempty(directionParts)
                directionLabel = "NoClearDirection";
            else
                directionLabel = string(strjoin(directionParts, ''));
            end

            nAxesMoved = nnz(sXYZ ~= 0);

            newRow = table(string(dsName), i, t0, t1, tBefore, tAfter, ...
                dXYZ(1), dXYZ(2), dXYZ(3), sXYZ(1), sXYZ(2), sXYZ(3), nAxesMoved, directionLabel, ...
                'VariableNames', {'Dataset','MovementIndex','Onset','Offset','TBefore','TAfter','dX','dY','dZ','signX','signY','signZ','nAxesMoved','DirectionLabel'});

            ALL_MOVEMENT_RECORDS = [ALL_MOVEMENT_RECORDS; newRow];
        end

        fprintf('%s: %d total movements detected for ALL_MOVEMENT_RECORDS.\n', dsName, numel(onsets));
    end
end

function data = getDatasetFromWorkspace(dsName)
    if evalin('caller', sprintf('exist(''%s'',''var'')', dsName))
        data = evalin('caller', dsName);
    else
        data = evalin('base', dsName);
    end
end

function Xz = zscoreSafe(X)
    mu = mean(X,1,'omitnan');
    sd = std(X,0,1,'omitnan');
    sd(sd == 0 | isnan(sd)) = 1;
    Xz = (X - mu) ./ sd;
    Xz(isnan(Xz)) = 0;
end

function taskDim = datasetNameToDim(dsName)
    core = erase(dsName, 'data');
    taskDim = numel(core);
end

function [movementRecords, binLabels] = detectMovementsAndLabelBins(dsName, posXYZ, velDetect, speed, T, t_min, t_max, cfg)
    aboveOn  = abs(velDetect) >= cfg.onset_velocity_threshold;
    belowOff = abs(velDetect) <= cfg.offset_velocity_threshold;

    onsets = [];
    offsets = [];

    inMove = false;
    belowCount = 0;

    for t = t_min:t_max
        if ~inMove
            if aboveOn(t)
                inMove = true;
                belowCount = 0;
                onsets(end+1,1) = t;
            end
        else
            if belowOff(t)
                belowCount = belowCount + 1;
                if belowCount >= cfg.movement_end_criterion
                    off = t - cfg.movement_end_criterion + 1;
                    offsets(end+1,1) = off;
                    inMove = false;
                    belowCount = 0;
                end
            else
                belowCount = 0;
            end
        end
    end

    if numel(offsets) < numel(onsets)
        offsets(end+1,1) = t_max;
    end

    signDB = @(x) (x > cfg.delta_eps) - (x < -cfg.delta_eps);

    movementRecords = struct( ...
        'direction', {}, 'axis', {}, 'sign', {}, 'onset', {}, 'offset', {}, 'velocityApex', {}, ...
        'dXYZ', {}, 'trialIndex', {}, 'dataset', {}, 'taskDim', {});

    tPre = round(cfg.pre_post_window(1));
    tPost = round(cfg.pre_post_window(2));

    trialCounter = 0;
    for i = 1:numel(onsets)
        t0 = onsets(i);
        t1 = offsets(i);

        searchIdx = t0:t1;
        [~, localApexIdx] = max(speed(searchIdx));
        velocityApex = searchIdx(localApexIdx);

        tBefore = max(1, t0-1);

        if cfg.compare_pos_at_end
            tAfter = t1 - cfg.pos_offset_from_end;
            tAfter = max(tAfter, t0+1);
            tAfter = min(T, max(1, tAfter));
        else
            tAfter = min(T, t0+1);
        end

        dXYZ = posXYZ(tAfter,:) - posXYZ(tBefore,:);
        sXYZ = [signDB(dXYZ(1)), signDB(dXYZ(2)), signDB(dXYZ(3))];

        nNonZero = nnz(sXYZ ~= 0);
        if nNonZero ~= 1
            continue
        end

        if sXYZ(1) ~= 0
            ax = 'X'; sg = sXYZ(1);
        elseif sXYZ(2) ~= 0
            ax = 'Y'; sg = sXYZ(2);
        else
            ax = 'Z'; sg = sXYZ(3);
        end

        if sg > 0
            dirLabel = ['+' ax];
        else
            dirLabel = ['-' ax];
        end

        if (t0 + tPre) < 1 || (t0 + tPost) > T
        end

        trialCounter = trialCounter + 1;
        movementRecords(trialCounter).direction  = dirLabel;
        movementRecords(trialCounter).axis       = ax;
        movementRecords(trialCounter).sign       = sg;
        movementRecords(trialCounter).onset      = t0;
        movementRecords(trialCounter).offset     = t1;
        movementRecords(trialCounter).velocityApex = velocityApex;
        movementRecords(trialCounter).dXYZ       = dXYZ;
        movementRecords(trialCounter).trialIndex = trialCounter;
        movementRecords(trialCounter).dataset    = dsName;
        movementRecords(trialCounter).taskDim    = datasetNameToDim(dsName);
    end

    binLabels = table((1:T).', repmat(categorical("none"),T,1), repmat(categorical("none"),T,1), ...
        repmat(categorical("none"),T,1), nan(T,1), nan(T,1), nan(T,1), nan(T,1), ...
        'VariableNames', {'TimeIndex','Target','Axis','SignLabel','SignNumeric','TrialIndex','TimeRel','VelocityApexRel'});

    binLabels.Phase = repmat(categorical("none"), T, 1);

    for m = 1:numel(movementRecords)
        t0 = movementRecords(m).onset;
        t1 = movementRecords(m).offset;

        winStart = max(1, t0 + tPre);
        winEnd = min(T, t0 + tPost);
        idxWin = (winStart:winEnd).';
        rel = idxWin - t0;

        binLabels.Target(idxWin) = categorical(string(movementRecords(m).direction));
        binLabels.Axis(idxWin) = categorical(string(movementRecords(m).axis));
        if movementRecords(m).sign > 0
            binLabels.SignLabel(idxWin) = categorical("positive");
        else
            binLabels.SignLabel(idxWin) = categorical("negative");
        end
        binLabels.SignNumeric(idxWin) = movementRecords(m).sign;
        binLabels.TrialIndex(idxWin) = movementRecords(m).trialIndex;
        binLabels.TimeRel(idxWin) = rel;
        binLabels.VelocityApexRel(idxWin) = movementRecords(m).velocityApex - t0;

        apexRel = movementRecords(m).velocityApex - t0;
        for ii = 1:numel(idxWin)
            if rel(ii) >= cfg.phase_preparation_window(1) && rel(ii) <= cfg.phase_preparation_window(2)
                binLabels.Phase(idxWin(ii)) = categorical("preparation");
            elseif rel(ii) >= 0 && rel(ii) <= apexRel
                binLabels.Phase(idxWin(ii)) = categorical("reach");
            elseif rel(ii) > apexRel && rel(ii) <= cfg.phase_attenuation_end
                binLabels.Phase(idxWin(ii)) = categorical("attenuation");
            else
                binLabels.Phase(idxWin(ii)) = categorical("none");
            end
        end
    end
end

function labelsThis = makeLabelTable(dsName, timeIdx, velDetect, speed, velXYZ, posXYZ, movementRecords, binLabels, cfg)
    n = numel(timeIdx);
    taskDim = datasetNameToDim(dsName);

    labelsThis = table();
    labelsThis.Dataset = repmat(categorical(string(dsName)), n, 1);
    labelsThis.TaskDim = repmat(taskDim, n, 1);
    labelsThis.TimeIndex = timeIdx(:);
    labelsThis.Vel = velDetect(timeIdx(:));
    labelsThis.VelAbs = speed(timeIdx(:));
    labelsThis.VelX = velXYZ(timeIdx(:),1);
    labelsThis.VelY = velXYZ(timeIdx(:),2);
    labelsThis.VelZ = velXYZ(timeIdx(:),3);
    labelsThis.PosX = posXYZ(timeIdx(:),1);
    labelsThis.PosY = posXYZ(timeIdx(:),2);
    labelsThis.PosZ = posXYZ(timeIdx(:),3);

    labelsThis.Target = binLabels.Target(timeIdx(:));
    labelsThis.Axis = binLabels.Axis(timeIdx(:));
    labelsThis.SignLabel = binLabels.SignLabel(timeIdx(:));
    labelsThis.SignNumeric = binLabels.SignNumeric(timeIdx(:));
    labelsThis.TrialIndex = binLabels.TrialIndex(timeIdx(:));
    labelsThis.TimeRel = binLabels.TimeRel(timeIdx(:));
    labelsThis.Phase = binLabels.Phase(timeIdx(:));
    labelsThis.VelocityApexRel = binLabels.VelocityApexRel(timeIdx(:));

    labelsThis.HasMovementLabel = labelsThis.Target ~= categorical("none");
    labelsThis.HasAxisLabel = labelsThis.Axis ~= categorical("none");

    labelsThis.NumDetectedMovements = repmat(numel(movementRecords), n, 1);
end

function out = oneWayEncodingStrength(y, group)
    y = y(:);
    group = categorical(group(:));
    valid = isfinite(y) & ~isundefined(group) & group ~= categorical("none");

    out = struct('Eta2', NaN, 'P', NaN, 'N', sum(valid), 'NumLevels', NaN);

    if sum(valid) < 10
        return
    end

    g = group(valid);
    yy = y(valid);
    levels = categories(g);
    levels = levels(countcats(g) > 0);
    out.NumLevels = numel(levels);

    if numel(levels) < 2
        return
    end

    grandMean = mean(yy);
    ssTotal = sum((yy - grandMean).^2);
    ssBetween = 0;

    for i = 1:numel(levels)
        idx = g == categorical(string(levels{i}));
        ni = sum(idx);
        if ni > 0
            ssBetween = ssBetween + ni * (mean(yy(idx)) - grandMean).^2;
        end
    end

    if ssTotal > 0
        out.Eta2 = ssBetween / ssTotal;
    else
        out.Eta2 = NaN;
    end

    try
        out.P = anova1(yy, g, 'off');
    catch
        out.P = NaN;
    end
end

function out = continuousEncodingStrength(y, x)
    y = y(:);
    x = x(:);
    valid = isfinite(y) & isfinite(x);

    out = struct('R2', NaN, 'P', NaN, 'N', sum(valid));

    if sum(valid) < 10 || std(x(valid)) == 0 || std(y(valid)) == 0
        return
    end

    xx = x(valid);
    yy = y(valid);
    r = corr(xx, yy, 'Rows', 'complete');
    out.R2 = r.^2;

    n = numel(xx);
    t = r * sqrt((n-2) / max(eps, 1-r^2));
    out.P = 2 * (1 - tcdf(abs(t), n-2));
end


function [TARGET_PHASE_ETA, TARGET_ONEVREST_PHASE_ETA] = computeTargetEtaByPhase(score, LABELS, explained, maxPCs)

    phaseOrder = {'preparation','reach','attenuation'};
    targetOrder = {'+X','-X','+Y','-Y','+Z','-Z'};

    TARGET_PHASE_ETA = table();
    TARGET_ONEVREST_PHASE_ETA = table();

    for pc = 1:maxPCs
        y = score(:,pc);
        for ph = 1:numel(phaseOrder)
            phaseName = phaseOrder{ph};
            idxPhase = LABELS.Phase == categorical(string(phaseName)) & LABELS.Target ~= categorical("none");

            st = oneWayEncodingStrength(y(idxPhase), LABELS.Target(idxPhase));
            TARGET_PHASE_ETA = [TARGET_PHASE_ETA; table(pc, explained(pc), {phaseName}, st.Eta2, st.P, st.N, st.NumLevels, ...
                'VariableNames', {'PC','ExplainedPercent','Phase','Target_Eta2','Target_P','N','NumTargets'})];

            for tg = 1:numel(targetOrder)
                targetName = targetOrder{tg};
                idx = idxPhase & (LABELS.Target == categorical(string(targetName)) | LABELS.Target ~= categorical("none"));
                yy = y(idx);
                isTarget = LABELS.Target(idx) == categorical(string(targetName));

                if sum(isTarget) >= 5 && sum(~isTarget) >= 5
                    binaryStrings = repmat("Other", numel(yy), 1);
                    binaryStrings(isTarget) = "ThisTarget";
                    binaryGroup = categorical(binaryStrings);
                    st2 = oneWayEncodingStrength(yy, binaryGroup);
                    meanThis = mean(yy(isTarget), 'omitnan');
                    meanOther = mean(yy(~isTarget), 'omitnan');
                    rmsThis = sqrt(mean(yy(isTarget).^2, 'omitnan'));
                    rmsOther = sqrt(mean(yy(~isTarget).^2, 'omitnan'));
                    nThis = sum(isTarget);
                    nOther = sum(~isTarget);
                else
                    st2 = struct('Eta2', NaN, 'P', NaN, 'N', sum(isfinite(yy)), 'NumLevels', NaN);
                    meanThis = NaN; meanOther = NaN; rmsThis = NaN; rmsOther = NaN;
                    nThis = sum(isTarget); nOther = sum(~isTarget);
                end

                TARGET_ONEVREST_PHASE_ETA = [TARGET_ONEVREST_PHASE_ETA; table(pc, explained(pc), {phaseName}, {targetName}, ...
                    st2.Eta2, st2.P, st2.N, nThis, nOther, meanThis, meanOther, rmsThis, rmsOther, ...
                    'VariableNames', {'PC','ExplainedPercent','Phase','Target','OneVsRest_Eta2','OneVsRest_P','N','N_Target','N_Other','Mean_Target','Mean_Other','RMS_Target','RMS_Other'})];
            end
        end
    end
end


function TARGET_PREFERENCE_BY_PHASE = computeTargetPreferenceByPhase(TARGET_ONEVREST_PHASE_ETA)

    targetOrder = {'+X','-X','+Y','-Y','+Z','-Z'};
    phaseOrder = {'preparation','reach','attenuation'};

    TARGET_PREFERENCE_BY_PHASE = table();

    if isempty(TARGET_ONEVREST_PHASE_ETA)
        return
    end

    pcs = unique(TARGET_ONEVREST_PHASE_ETA.PC(:)).';

    for pc = pcs
        for ph = 1:numel(phaseOrder)
            phaseName = phaseOrder{ph};
            idxBase = TARGET_ONEVREST_PHASE_ETA.PC == pc & strcmp(TARGET_ONEVREST_PHASE_ETA.Phase, phaseName);

            etaVals = nan(1, numel(targetOrder));
            pVals   = nan(1, numel(targetOrder));
            meanVals = nan(1, numel(targetOrder));
            rmsVals  = nan(1, numel(targetOrder));
            nVals    = nan(1, numel(targetOrder));

            for tg = 1:numel(targetOrder)
                targetName = targetOrder{tg};
                idx = idxBase & strcmp(TARGET_ONEVREST_PHASE_ETA.Target, targetName);
                if any(idx)
                    etaVals(tg)  = TARGET_ONEVREST_PHASE_ETA.OneVsRest_Eta2(find(idx,1));
                    pVals(tg)    = TARGET_ONEVREST_PHASE_ETA.OneVsRest_P(find(idx,1));
                    meanVals(tg) = TARGET_ONEVREST_PHASE_ETA.Mean_Target(find(idx,1));
                    rmsVals(tg)  = TARGET_ONEVREST_PHASE_ETA.RMS_Target(find(idx,1));
                    nVals(tg)    = TARGET_ONEVREST_PHASE_ETA.N_Target(find(idx,1));
                end
            end

            if all(isnan(etaVals))
                preferredTarget = "none";
                preferredEta2 = NaN;
                preferredP = NaN;
                preferredMean = NaN;
                preferredRMS = NaN;
            else
                [preferredEta2, bestIdx] = max(etaVals, [], 'omitnan');
                preferredTarget = string(targetOrder{bestIdx});
                preferredP = pVals(bestIdx);
                preferredMean = meanVals(bestIdx);
                preferredRMS = rmsVals(bestIdx);
            end

            row = table(pc, {phaseName}, preferredTarget, preferredEta2, preferredP, preferredMean, preferredRMS, ...
                etaVals(1), etaVals(2), etaVals(3), etaVals(4), etaVals(5), etaVals(6), ...
                pVals(1), pVals(2), pVals(3), pVals(4), pVals(5), pVals(6), ...
                meanVals(1), meanVals(2), meanVals(3), meanVals(4), meanVals(5), meanVals(6), ...
                rmsVals(1), rmsVals(2), rmsVals(3), rmsVals(4), rmsVals(5), rmsVals(6), ...
                nVals(1), nVals(2), nVals(3), nVals(4), nVals(5), nVals(6), ...
                'VariableNames', {'PC','Phase','PreferredTarget','PreferredTarget_Eta2','PreferredTarget_P','PreferredTarget_MeanScore','PreferredTarget_RMSScore', ...
                'Eta2_posX','Eta2_negX','Eta2_posY','Eta2_negY','Eta2_posZ','Eta2_negZ', ...
                'P_posX','P_negX','P_posY','P_negY','P_posZ','P_negZ', ...
                'Mean_posX','Mean_negX','Mean_posY','Mean_negY','Mean_posZ','Mean_negZ', ...
                'RMS_posX','RMS_negX','RMS_posY','RMS_negY','RMS_posZ','RMS_negZ', ...
                'N_posX','N_negX','N_posY','N_negY','N_posZ','N_negZ'});

            TARGET_PREFERENCE_BY_PHASE = [TARGET_PREFERENCE_BY_PHASE; row];
        end
    end
end

function acc = singlePCClassifierAccuracy(xpc, labels, kfold)
    acc = NaN;
    xpc = xpc(:);
    labels = categorical(labels(:));
    valid = isfinite(xpc) & ~isundefined(labels) & labels ~= categorical("none");

    if sum(valid) < 20
        return
    end

    X = xpc(valid);
    Y = labels(valid);

    cats = categories(Y);
    counts = countcats(Y);
    keepCats = cats(counts >= kfold);
    keep = ismember(cellstr(Y), keepCats);
    X = X(keep);
    Y = Y(keep);

    if numel(categories(Y)) < 2 || numel(Y) < 20
        return
    end

    try
        mdl = fitcdiscr(X, Y, 'DiscrimType', 'linear', 'KFold', min(kfold, min(countcats(Y))));
        acc = 1 - kfoldLoss(mdl);
    catch
        try
            mdl = fitcecoc(X, Y, 'KFold', min(kfold, min(countcats(Y))));
            acc = 1 - kfoldLoss(mdl);
        catch
            acc = NaN;
        end
    end
end

function PC_TRAJ = buildMovementAlignedPCTrajectories(score, LABELS, cfg, maxPCs)
    tPre = round(cfg.pre_post_window(1));
    tPost = round(cfg.pre_post_window(2));
    tRel = (tPre:tPost).';

    targets = {'+X','-X','+Y','-Y','+Z','-Z'};
    datasets = categories(LABELS.Dataset);

    PC_TRAJ = struct();
    PC_TRAJ.tRel = tRel;
    PC_TRAJ.targets = targets;
    PC_TRAJ.datasets = datasets;

    for pc = 1:maxPCs
        pcField = sprintf('PC%d', pc);
        PC_TRAJ.(pcField) = struct();
        pcScore = score(:,pc);

        for d = 1:numel(datasets)
            dsName = datasets{d};
            dsField = matlab.lang.makeValidName(dsName);
            PC_TRAJ.(pcField).(dsField) = struct();

            for it = 1:numel(targets)
                targetName = targets{it};
                targetField = targetToField(targetName);

                meanCurve = nan(numel(tRel),1);
                semCurve = nan(numel(tRel),1);
                nCurve = nan(numel(tRel),1);

                for tt = 1:numel(tRel)
                    idx = LABELS.Dataset == categorical(string(dsName)) & ...
                          LABELS.Target == categorical(string(targetName)) & ...
                          LABELS.TimeRel == tRel(tt);
                    vals = pcScore(idx);
                    vals = vals(isfinite(vals));
                    if ~isempty(vals)
                        meanCurve(tt) = mean(vals);
                        semCurve(tt) = std(vals) / sqrt(numel(vals));
                        nCurve(tt) = numel(vals);
                    end
                end

                PC_TRAJ.(pcField).(dsField).(targetField).mean = meanCurve;
                PC_TRAJ.(pcField).(dsField).(targetField).sem = semCurve;
                PC_TRAJ.(pcField).(dsField).(targetField).n = nCurve;
            end
        end
    end
end

function fld = targetToField(targetName)
    fld = strrep(targetName, '+', 'pos');
    fld = strrep(fld, '-', 'neg');
end

function makeGlobalPCAFigures(EXPLAINED_TABLE, PC_BREAKDOWN, PC_CLASSIFICATION, PC_TRAJ, cfg, maxPCs)
    fig = figure('Name','Global PCA explained variance','Color','w','Position',[100 100 900 450]);
    tiledlayout(fig,1,2,'TileSpacing','compact','Padding','compact');

    nexttile; hold on
    bar(EXPLAINED_TABLE.PC, EXPLAINED_TABLE.ExplainedPercent);
    xlabel('PC'); ylabel('% variance explained');
    title('Global PCA variance explained'); grid on

    nexttile; hold on
    plot(EXPLAINED_TABLE.PC, EXPLAINED_TABLE.CumulativeExplainedPercent, '-o', 'LineWidth', 1.5);
    xlabel('PC'); ylabel('Cumulative % variance');
    title('Cumulative variance'); grid on

    if cfg.save_figures
        exportgraphics(fig, fullfile(cfg.output_folder, 'global_pca_explained_variance.png'), 'Resolution', 220);
    end

    if ~isempty(PC_BREAKDOWN)
        fig = figure('Name','PC behavioral encoding strength','Color','w','Position',[100 100 1200 650]);
        vars = {'Dataset_Eta2','TaskDim_Eta2','Axis_Eta2','Sign_Eta2','Target_Eta2','Phase_Eta2','Velocity_R2','TimeRel_R2'};
        M = zeros(height(PC_BREAKDOWN), numel(vars));
        for v = 1:numel(vars)
            M(:,v) = PC_BREAKDOWN.(vars{v});
        end
        imagesc(M);
        colorbar;
        xticks(1:numel(vars)); xticklabels(strrep(vars, '_', '\_'));
        yticks(1:height(PC_BREAKDOWN)); yticklabels(string(PC_BREAKDOWN.PC));
        xlabel('Behavioral variable'); ylabel('PC');
        title('Encoding strength per PC: eta^2 for categorical variables, R^2 for continuous variables');

        if cfg.save_figures
            exportgraphics(fig, fullfile(cfg.output_folder, 'pc_encoding_strength_heatmap.png'), 'Resolution', 220);
        end
    end

    if ~isempty(PC_CLASSIFICATION)
        fig = figure('Name','Single-PC decoding accuracy','Color','w','Position',[100 100 1200 650]);
        labels = unique(PC_CLASSIFICATION.LabelDecoded, 'stable');
        M = nan(maxPCs, numel(labels));
        for i = 1:height(PC_CLASSIFICATION)
            pc = PC_CLASSIFICATION.PC(i);
            lab = PC_CLASSIFICATION.LabelDecoded{i};
            j = find(strcmp(labels, lab), 1);
            M(pc,j) = PC_CLASSIFICATION.Accuracy(i);
        end
        imagesc(M);
        colorbar;
        xticks(1:numel(labels)); xticklabels(labels);
        yticks(1:maxPCs); yticklabels(string(1:maxPCs));
        xlabel('Decoded label'); ylabel('PC');
        title('Single-PC classifier accuracy');

        if cfg.save_figures
            exportgraphics(fig, fullfile(cfg.output_folder, 'single_pc_decoding_heatmap.png'), 'Resolution', 220);
        end
    end

    nTrajFigs = min(maxPCs, cfg.max_pc_trajectory_figures);
    targetOrder = {'+X','-X','+Y','-Y','+Z','-Z'};
    targetFields = cellfun(@targetToField, targetOrder, 'UniformOutput', false);

    for pc = 1:nTrajFigs
        pcField = sprintf('PC%d', pc);
        if ~isfield(PC_TRAJ, pcField)
            continue
        end

        fig = figure('Name',sprintf('%s movement-aligned trajectories', pcField), ...
            'Color','w','Position',[50 50 1400 780]);
        tl = tiledlayout(fig, 2, 3, 'TileSpacing','compact','Padding','compact');
        title(tl, sprintf('%s average trajectories by dataset and target', pcField), 'Interpreter','none');

        dsNames = PC_TRAJ.datasets;
        for t = 1:numel(targetOrder)
            ax = nexttile(tl,t); hold(ax,'on')
            targetName = targetOrder{t};
            targetField = targetFields{t};

            legendEntries = {};
            for d = 1:numel(dsNames)
                dsName = dsNames{d};
                dsField = matlab.lang.makeValidName(dsName);
                if isfield(PC_TRAJ.(pcField), dsField) && isfield(PC_TRAJ.(pcField).(dsField), targetField)
                    y = PC_TRAJ.(pcField).(dsField).(targetField).mean;
                    if all(isnan(y))
                        continue
                    end
                    y = movmean(y, cfg.smooth_window, 'omitnan');
                    plot(ax, PC_TRAJ.tRel, y, 'LineWidth', 1.7);
                    legendEntries{end+1} = dsName;
                end
            end
            xline(ax, 0, 'k--');
            title(ax, targetName, 'Interpreter','none');
            xlabel(ax, 'Time relative to onset');
            ylabel(ax, 'PC score');
            grid(ax,'on')
            if ~isempty(legendEntries)
                legend(ax, legendEntries, 'Location','best', 'Interpreter','none');
            end
        end

        if cfg.save_figures
            exportgraphics(fig, fullfile(cfg.output_folder, sprintf('%s_movement_aligned_trajectories.png', pcField)), 'Resolution', 220);
        end
    end
end


function [coeff, score, latent, explained, mu] = memorySafePCA_fromCovariance(X, nPCs)

    X = double(X);
    goodRows = all(isfinite(X), 2);
    if ~all(goodRows)
        warning('Removing %d rows with NaN/Inf before PCA.', sum(~goodRows));
        X = X(goodRows, :);
    end

    mu = mean(X, 1, 'omitnan');
    Xc = X - mu;

    nObs = size(Xc, 1);
    nFeat = size(Xc, 2);
    nPCs = min([nPCs, nFeat, nObs - 1]);

    C = (Xc' * Xc) ./ max(nObs - 1, 1);
    C = (C + C') ./ 2;

    try
        opts = struct();
        opts.disp = 0;
        [V,D] = eigs(C, nPCs, 'largestreal', opts);
        latent = diag(D);
    catch
        [V,D] = eig(C, 'vector');
        [latent, ord] = sort(D, 'descend');
        V = V(:, ord);
        V = V(:, 1:nPCs);
        latent = latent(1:nPCs);
    end

    [latent, ord] = sort(real(latent), 'descend');
    coeff = real(V(:, ord));

    for j = 1:size(coeff,2)
        [~, imax] = max(abs(coeff(:,j)));
        if coeff(imax,j) < 0
            coeff(:,j) = -coeff(:,j);
        end
    end

    score = Xc * coeff;

    allEig = eig(C, 'vector');
    totalVar = sum(max(real(allEig), 0));
    explained = 100 .* latent ./ totalVar;
end
function plot_PC_environment_trajectories(GLOBAL_PCA_RESULTS, cfgPlot)

PC_TRAJ = GLOBAL_PCA_RESULTS.PC_TRAJ;

pcX = sprintf('PC%d', cfgPlot.pcX);
pcY = sprintf('PC%d', cfgPlot.pcY);

if ~isfield(PC_TRAJ, pcX) || ~isfield(PC_TRAJ, pcY)
    error('PC_TRAJ does not contain %s or %s.', pcX, pcY);
end

if ~isfield(cfgPlot,'pcX_divisor')
    cfgPlot.pcX_divisor = 1;
end

if ~isfield(cfgPlot,'pcY_divisor')
    cfgPlot.pcY_divisor = 1;
end

if cfgPlot.pcX_divisor == 0 || cfgPlot.pcY_divisor == 0
    error('PC divisors cannot be zero.');
end

targetBaseColorMap = containers.Map();

targetBaseColorMap('+Y') = [0.00 0.60 0.00];
targetBaseColorMap('-Y') = [0.50 0.50 0.50];
targetBaseColorMap('+X') = [0.00 0.25 1.00];
targetBaseColorMap('-X') = [1.00 0.00 0.00];

targetFieldMap = containers.Map();
targetFieldMap('+X') = 'posX';
targetFieldMap('-X') = 'negX';
targetFieldMap('+Y') = 'posY';
targetFieldMap('-Y') = 'negY';
targetFieldMap('+Z') = 'posZ';
targetFieldMap('-Z') = 'negZ';

tRel = PC_TRAJ.tRel(:);
idxTime = tRel >= cfgPlot.time_window(1) & tRel <= cfgPlot.time_window(2);

if ~any(idxTime)
    error('No time points found in cfgPlot.time_window = [%g %g].', ...
        cfgPlot.time_window(1), cfgPlot.time_window(2));
end

fig = figure('Color','w','Name','PC neural trajectories');
ax = axes(fig);
hold(ax,'on');

for e = 1:numel(cfgPlot.environmentsToPlot)

    dsName = cfgPlot.environmentsToPlot{e};
    dsField = matlab.lang.makeValidName(dsName);

    if ~isfield(PC_TRAJ.(pcX), dsField) || ~isfield(PC_TRAJ.(pcY), dsField)
        warning('Skipping %s: missing %s or %s trajectory.', dsName, pcX, pcY);
        continue
    end

    [lineStyle, markerStyle, lineWidth] = getEnvironmentStyle(dsName);

    for t = 1:numel(cfgPlot.targetsToPlot)

        targetName = cfgPlot.targetsToPlot{t};

        if ~isKey(targetFieldMap, targetName)
            warning('Skipping target %s: unknown target label.', targetName);
            continue
        end

        if ~isKey(targetBaseColorMap, targetName)
            warning('Skipping target %s: no color defined.', targetName);
            continue
        end

        targetField = targetFieldMap(targetName);

        if ~isfield(PC_TRAJ.(pcX).(dsField), targetField) || ...
           ~isfield(PC_TRAJ.(pcY).(dsField), targetField)
            warning('Skipping %s in %s: missing target trajectory.', targetName, dsName);
            continue
        end

        x = PC_TRAJ.(pcX).(dsField).(targetField).mean(:);
        y = PC_TRAJ.(pcY).(dsField).(targetField).mean(:);

        if numel(x) ~= numel(tRel) || numel(y) ~= numel(tRel)
            warning('Skipping %s in %s: trajectory length does not match PC_TRAJ.tRel.', ...
                targetName, dsName);
            continue
        end

        x = x(idxTime);
        y = y(idxTime);

        x = x ./ cfgPlot.pcX_divisor;
        y = y ./ cfgPlot.pcY_divisor;

        if all(isnan(x)) || all(isnan(y))
            continue
        end

        x = movmean(x, cfgPlot.smooth_window, 'omitnan');
        y = movmean(y, cfgPlot.smooth_window, 'omitnan');

        baseCol = targetBaseColorMap(targetName);
        shadeLevel = getEnvironmentShadeLevel(dsName);
        col = applyColorShade(baseCol, shadeLevel);

        plot(ax, x, y, ...
            'Color', col, ...
            'LineStyle', lineStyle, ...
            'Marker', markerStyle, ...
            'LineWidth', lineWidth, ...
            'MarkerSize', 4, ...
            'DisplayName', [targetName ' | ' dsName]);

        validIdx = find(isfinite(x) & isfinite(y));

        if ~isempty(validIdx)
            iStart = validIdx(1);
            iEnd = validIdx(end);

            plot(ax, x(iStart), y(iStart), 'o', ...
                'Color', col, ...
                'MarkerFaceColor', 'w', ...
                'MarkerSize', 7, ...
                'HandleVisibility','off');

            plot(ax, x(iEnd), y(iEnd), 'o', ...
                'Color', col, ...
                'MarkerFaceColor', col, ...
                'MarkerSize', 7, ...
                'HandleVisibility','off');
        end
    end
end

if cfgPlot.show_zero_lines
    xline(ax, 0, 'k--', 'HandleVisibility','off');
    yline(ax, 0, 'k--', 'HandleVisibility','off');
end

xlabel(ax, sprintf('PC%d score / %.3g', cfgPlot.pcX, cfgPlot.pcX_divisor));
ylabel(ax, sprintf('PC%d score / %.3g', cfgPlot.pcY, cfgPlot.pcY_divisor));
title(ax, cfgPlot.title, 'Interpreter','none');

grid(ax,'on');

if cfgPlot.use_equal_axis
    axis(ax,'equal');
end

if cfgPlot.show_legend
    legend(ax, 'Location','eastoutside', 'Interpreter','none');
end

end


function [lineStyle, markerStyle, lineWidth] = getEnvironmentStyle(dsName)

switch dsName

    case {'dataX','dataY','dataZ'}
        lineStyle = ':';
        markerStyle = 'none';
        lineWidth = 2.0;

    case 'dataXYZ'
        lineStyle = '-';
        markerStyle = 'none';
        lineWidth = 2.5;

    case 'dataXY'
        lineStyle = '-';
        markerStyle = 'none';
        lineWidth = 1.8;

    case 'dataXZ'
        lineStyle = '-';
        markerStyle = 'none';
        lineWidth = 1.8;

    case 'dataYZ'
        lineStyle = '-';
        markerStyle = 'none';
        lineWidth = 1.8;

    otherwise
        lineStyle = '--';
        markerStyle = 'none';
        lineWidth = 1.5;
end

end


function shadeLevel = getEnvironmentShadeLevel(dsName)

switch dsName

    case {'dataX','dataY','dataZ'}
        shadeLevel = 'light';

    case {'dataXY','dataXZ','dataYZ'}
        shadeLevel = 'medium';

    case 'dataXYZ'
        shadeLevel = 'dark';

    otherwise
        shadeLevel = 'medium';
end

end


function col = applyColorShade(baseCol, shadeLevel)

switch shadeLevel

    case 'light'
        col = 0.65 * [1 1 1] + 0.35 * baseCol;

    case 'medium'
        col = 0.35 * [1 1 1] + 0.65 * baseCol;

    case 'dark'
        col = 0.75 * baseCol;

    otherwise
        col = baseCol;
end

col = max(min(col, 1), 0);

end

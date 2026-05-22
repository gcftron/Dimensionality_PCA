**Inputs in dataK :**
SpikeCount [Bin x Neuron];
ActualPos [Bin x 3];
ActualVel [Bin x 1]

**Features :**

- Dataset selection (cfg.datasetNamesWanted): Choose which environments (dataX, dataY, dataZ, dataXY, dataXZ, dataYZ, dataXYZ) are included in the analysis.- 
- Movement detection (cfg.onset_velocity_threshold, cfg.offset_velocity_threshold, cfg.movement_end_criterion): Adjust movement onset, offset, and termination thresholds.
- Time selection (cfg.time_interval): Restrict analysis to specific recording periods.
- Neuron selection (cfg.pixel_interval): Select channel ranges included in PCA.
- Common neuron mode (cfg.use_common_neuron_count): Restrict PCA to neurons shared across datasets.
- Preprocessing (cfg.zscore_mode): Select global normalization, per-dataset normalization, or raw activity.
- Axis mapping (cfg.axis_order_original_to_internal): Define coordinate remapping between recorded and internal axes.
- Direction sensitivity (cfg.delta_eps): Set movement-direction classification thresholds.
- Movement comparison (cfg.compare_pos_at_end, cfg.pos_offset_from_end): Control how movement direction is computed.
- Alignment window (cfg.pre_post_window): Define time windows around movement onset.
 -Phase segmentation (cfg.phase_preparation_window, cfg.phase_attenuation_end): Customize preparation, reach, and attenuation periods.
- PCA settings (cfg.nPCsToAnalyze, cfg.row_stride_for_pca): Control dimensionality and optional downsampling.
- Loading analysis (cfg.nTopLoadingNeurons): Specify the number of top contributing neurons reported per PC.
- Statistical analysis (cfg.run_pc_statistics): Enable or disable PC encoding analyses.
- Classification (cfg.run_single_pc_classifiers, cfg.classifier_kfold): Enable decoding and set cross-validation settings.
- Visualization (cfg.enable_figures, cfg.smooth_window, cfg.max_pc_trajectory_figures): Configure figure generation and display behavior.
- Export (cfg.save_figures, cfg.output_folder): Configure output saving behavior and locations.

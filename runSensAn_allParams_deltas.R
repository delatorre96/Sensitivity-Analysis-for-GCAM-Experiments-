source("R/Experiment/7_1_init_experiment_dfParams.R")

#----- Arguments from command line -----

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 2) {
  stop("Usage: Rscript script.R <experiment_id|NULL> <suffix>")
}

experiment_id_to_add <- if (args[1] == "NULL") NULL else args[1]
suffix <- args[2]

if (is.null(suffix) || is.na(suffix)) {
  stop("Suffix cannot be NULL or NA")
}

message(
  "Experiment ID: ",
  if (is.null(experiment_id_to_add)) "NULL (new experiment)" else experiment_id_to_add
)

message("Worker suffix: ", suffix)


xml_files <- c(
  "en_supply_EUR.xml",
  "en_transformation_EUR.xml",
  "elec_segments_water_EUR.xml",
  "heat_EUR.xml",
  "en_distribution_EUR.xml",
  "other_industry_EUR.xml",
  "iron_steel_EUR.xml",
  "iron_steel_trade_EUR.xml",
  "Off_road_EUR.xml",
  "chemical_EUR.xml",
  "aluminum_EUR.xml",
  "paper_EUR.xml",
  "food_processing_EUR.xml",
  "cement_EUR.xml",
  "en_Fert_EUR.xml",
  "building_det_EUR.xml",
  "transportation_UCD_CORE_EUR.xml",
  "an_input_EUR.xml",
  "bio_trade_EUR.xml",
  "ag_trade_EUR.xml",
  "desalination_EUR.xml",
  "water_td_EUR.xml",
  "EFW_irrigation_EUR.xml",
  "EFW_manufacturing_EUR.xml",
  "EFW_municipal_EUR.xml",
  "ind_urb_processing_sectors_EUR.xml",
  "gas_trade_EUR.xml"
)


regions_eur <- c(
  "Austria",
  "Belgium",
  "Bulgaria",
  "Croatia",
  "Cyprus",
  "Czech Republic",
  "Denmark",
  "Estonia",
  "Finland",
  "France",
  "Germany",
  "Greece",
  "Hungary",
  "Ireland",
  "Italy",
  "Latvia",
  "Lithuania",
  "Luxembourg",
  "Malta",
  "Netherlands",
  "Poland",
  "Portugal",
  "Romania",
  "Slovakia",
  "Slovenia",
  "Spain",
  "Sweden",
  "Albania",
  "Bosnia and Herzegovina",
  "Iceland",
  "Macedonia",
  "Moldova",
  "Norway",
  "Serbia and Montenegro",
  "Turkey",
  "UK",
  "Ukraine"
)


gcam_path = '../gcam_europe'
alreadyPrepeared = T
queries_of_interest = 'outputs by tech'
regions_of_interest = regions_eur
xml_files = xml_files
n_iterations = 110
project = 'Hindcasting'
experiment_name = 'RL tuning of logits, satiation_level and price_elasticity deltas'
description = 'Policy-gradient agent proposes one relative delta per parameter class to minimise MAE vs observed 2021'
perturbation_strategy = 'Reinforcement learning (Gaussian policy gradient over class deltas)'
distribution = 'uniform'
distribution_parameters = list('logit' = list('minVal' = 0.01, 'maxVal' = 4),
                               'price_elasticity' = list('minVal' = 0.01, 'maxVal' = 2),
                               'satiation_level' = list('minVal' = 0.01, 'maxVal' = 3))
interested_query_columns = list('outputs by tech' = c('region', 'sector', 'subsector', 'output', 'technology', '2021','run_id'))
uncertainty_introduction_function = 'introduce_heterogeneous_uncertainty_by_delta'
df_params_path = "../Hindcasting/4_SensitivityAnalysis/create_dfParams/df_allParams.csv"
paramCol = "param"

# 'rl': el agente de 8_reinforcementLearning.R propone los deltas
# 'random': muestreo aleatorio con uncertainty_introduction_function (baseline)
optimizer = 'rl'
reference_errors_path = '../Hindcasting/2. Extraction/Data/all_errors_output_by_tech.csv'
rl_config = list(
  mode         = 'train',  # 'exploit' para correr con la media de la politica aprendida
  batch_size   = 4,        # runs por actualizacion de la politica
  lr_mean      = 0.30,
  lr_log_sigma = 0.10,
  init_sigma   = 1.5,
  min_sigma    = 0.10,
  reward_type  = 'log_ratio'
)


init_experiment(gcam_path, alreadyPrepeared , queries_of_interest, regions_of_interest,
                xml_files, n_iterations, project , experiment_name, description ,
                uncertainty_introduction_function, df_params_path, paramCol,
                perturbation_strategy, distribution, distribution_parameters,
                interested_query_columns, experiment_id_to_add, suffix,
                optimizer = optimizer, rl_config = rl_config,
                reference_errors_path = reference_errors_path)






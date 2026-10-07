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
alreadyPrepeared = F
queries_of_interest = 'outputs by tech'
regions_of_interest = regions_eur
xml_files = xml_files
n_iterations = 110
project = 'Hindcasting'
experiment_name = 'monte carlo logits, satiation_level and price_elasticity'
description = 'Test different random values per parameter using global parameter-space exploration'
perturbation_strategy = 'Global parameter-space exploration'
distribution = 'uniform'
distribution_parameters = list('logit' = list('minVal' = -20, 'maxVal' = -0.01),
                               'price_elasticity' = list('minVal' = -1.5, 'maxVal' = -0.01),
                               'satiation_level' = list('minVal' = 0.001, 'maxVal' = 3))
interested_query_columns = list('outputs by tech' = c('region', 'sector', 'subsector', 'output', 'technology', '2021','run_id'))
uncertainty_introduction_function = 'introduce_heterogeneous_uncertainty_by_type'
df_params_path = "../Hindcasting/4_SensitivityAnalysis/create_dfParams/df_allParams.csv"
paramCol = "param"


init_experiment(gcam_path, alreadyPrepeared , queries_of_interest, regions_of_interest,
                xml_files, n_iterations, project , experiment_name, description ,
                uncertainty_introduction_function, df_params_path, paramCol,
                perturbation_strategy, distribution, distribution_parameters,
                interested_query_columns, experiment_id_to_add, suffix)






source("R/Experiment/7_1_init_experiment_dfParams.R")

xml_files <- c("transportation_UCD_CORE_EUR.xml")
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


gcam_path = 'C:/GCAM/Nacho/gcam_europe'
alreadyPrepeared = T
queries_of_interest = 'outputs by tech'
regions_of_interest = regions_eur
xml_files = xml_files
n_iterations = 300
project = 'Hindcasting'
experiment_name = 'price elasticity exploration'
description = 'Test how sensitive is price elasticity for outputs'
perturbation_strategy = 'aditive'
distribution = 'uniform'
distribution_parameters = list('minVal' = 1, 'maxVal' = 20)
interested_query_columns = list('outputs by tech' = c('region', 'sector', 'subsector', 'output', 'technology', '2021','run_id'))
uncertainty_introduction_function = 'introduce_aditive_uncertainty'
df_params_path = "C:/GCAM/Nacho/Hindcasting/4_SensitivityAnalysis/df_params_price_elasticity.csv"
paramCol = "price_elasticity"
experiment_id_to_add = NULL

init_experiment(gcam_path, alreadyPrepeared , queries_of_interest, regions_of_interest, 
                xml_files, n_iterations, project , experiment_name, description , 
                uncertainty_introduction_function, df_params_path, paramCol,
                perturbation_strategy, distribution, distribution_parameters,
                interested_query_columns, experiment_id_to_add )






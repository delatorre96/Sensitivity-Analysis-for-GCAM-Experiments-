source("R/Experiment/7_init_experiment.R")

xml_files <- c( "en_supply_EUR.xml","en_transformation_EUR.xml", "elec_segments_water_EUR.xml",
                'ag_an_demand_input.xml')
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
n_iterations = 200
project = 'Hindcasting'
experiment_name = 'monte carlo'
description = 'Test different random values per logit parameter using additive perturbation'
perturbation_strategy = 'aditive heterogeneous'
distribution = 'uniform'
distribution_parameters = list('minVal' = -5, 'maxVal' = 5)
interested_query_columns = list('outputs by tech' = c('region', 'sector', 'subsector', 'output', 'technology', '2021','run_id'))
experiment_id_to_add = NULL
uncertainty_introduction_function = 'introduce_aditive_heterogeneous_uncertainty'


init_experiment(gcam_path, alreadyPrepeared , queries_of_interest, regions_of_interest, 
                xml_files, n_iterations, project , experiment_name, description , 
                uncertainty_introduction_function,
                perturbation_strategy, distribution, distribution_parameters,
                interested_query_columns, experiment_id_to_add )



source("R/Experiment/7_1_init_experiment_dfParams.R")

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
  "Africa_Eastern",
  "Africa_Northern",
  "Africa_Southern",
  "Africa_Western",
  "Albania",
  "Appenine_Peninsula",
  "Argentina",
  "Australia_NZ",
  "Austria",
  "Belarus",
  "Belgium",
  "Bosnia and Herzegovina",
  "Brazil",
  "British_Isles",
  "Bulgaria",
  "Canada",
  "Central America and Caribbean",
  "Central Asia",
  "Central_Eastern_Europe",
  "Central_Western_Europe",
  "China",
  "Colombia",
  "Croatia",
  "Cyprus",
  "Czech Republic",
  "Denmark",
  "Estonia",
  "European_Single_Market",
  "Finland",
  "France",
  "Germany",
  "Greece",
  "Hungary",
  "Iberian_Peninsula",
  "Iceland",
  "India",
  "Indonesia",
  "Ireland",
  "Italy",
  "Japan",
  "Latvia",
  "Lithuania",
  "Luxembourg",
  "Macedonia",
  "Malta",
  "Mexico",
  "Middle East",
  "Moldova",
  "Netherlands",
  "Northern_Europe",
  "Norway",
  "Pakistan",
  "Poland",
  "Portugal",
  "Romania",
  "Russia",
  "Serbia and Montenegro",
  "Slovakia",
  "Slovenia",
  "South Africa",
  "South America_Northern",
  "South America_Southern",
  "South Asia",
  "South Korea",
  "South_Eastern_Europe",
  "Southeast Asia",
  "Spain",
  "Sweden",
  "Switzerland",
  "Taiwan",
  "Turkey",
  "UK",
  "USA",
  "Ukraine",
  "Ukraine_Moldova"
)


gcam_path = 'C:/GCAM/Nacho/gcam_europe'
alreadyPrepeared = T
queries_of_interest = 'outputs by tech'
regions_of_interest = regions_eur
xml_files = xml_files
n_iterations = 10000
project = 'Hindcasting'
experiment_name = 'monte carlo logits, satiation_level and price_elasticity'
description = 'Test different random values per parameter using additive perturbation'
perturbation_strategy = 'aditive heterogeneous'
distribution = 'uniform'
distribution_parameters = list('minVal' = -20, 'maxVal' = 20)
interested_query_columns = list('outputs by tech' = c('region', 'sector', 'subsector', 'output', 'technology', '2021','run_id'))
uncertainty_introduction_function = 'introduce_aditive_heterogeneous_uncertainty'
df_params_path = "C:/GCAM/Nacho/Hindcasting/4_SensitivityAnalysis/create_dfParams/df_allParams.csv"
paramCol = "param"
experiment_id_to_add = NULL

init_experiment(gcam_path, alreadyPrepeared , queries_of_interest, regions_of_interest,
                xml_files, n_iterations, project , experiment_name, description ,
                uncertainty_introduction_function, df_params_path, paramCol,
                perturbation_strategy, distribution, distribution_parameters,
                interested_query_columns, experiment_id_to_add )






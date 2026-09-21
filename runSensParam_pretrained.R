source("R/Experiment/7_2_init_experiment_dfParams_withoutUncer.R")

df_params_path = "C:/GCAM/Nacho/Hindcasting/4_SensitivityAnalysis/df_params_new_inputs_GAM.csv"
df_params = read.csv(df_params_path)
xml_files <- unique(df_params$xml_file)
regions_eur <- unique(df_params$region)


gcam_path = 'C:/GCAM/Nacho/gcam_europe'
alreadyPrepeared = T
queries_of_interest = 'outputs by tech'
regions_of_interest = regions_eur
xml_files = xml_files
n_iterations = max(df_params$param_config)
project = 'Hindcasting'
experiment_name = 'pretrained_param_config'
description = 'trying diferent parametric configurations that, according to GAM, minimize errors'
perturbation_strategy = NULL
distribution = NULL
distribution_parameters = NULL
interested_query_columns = list('outputs by tech' = c('region', 'sector', 'subsector', 'output', 'technology', '2021','run_id'))
uncertainty_introduction_function =NULL
paramCol = NULL
experiment_id_to_add = NULL

init_experiment(gcam_path, alreadyPrepeared , queries_of_interest, regions_of_interest, 
                xml_files, n_iterations, project , experiment_name, description , 
                uncertainty_introduction_function, df_params_path, paramCol,
                perturbation_strategy, distribution, distribution_parameters,
                interested_query_columns, experiment_id_to_add )






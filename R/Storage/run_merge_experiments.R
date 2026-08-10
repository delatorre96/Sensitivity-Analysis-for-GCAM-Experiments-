source('merge_experiments.R')
source('../Experiment/0_mainFunctions.R')
check_packages()



con <- dbConnect(
     SQLite(),
     "../../gcam_sensitivity.sqlite"
   )
experiments <- dbReadTable(con, "Experiments")
experiment_ids <- experiments$experiment_id
experiment_ids

merge_experiments(con = con, experiment_ids = experiment_ids)

update_number_iterations(con = con, experiment_id = 'EXP_5a2e3191')

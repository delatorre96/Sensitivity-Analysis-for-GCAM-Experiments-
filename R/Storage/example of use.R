library(DBI)
library(RSQLite)
source('R/Storage/explore_dataBase.R')
con <- dbConnect(
  SQLite(),
  "gcam_sensitivity.sqlite"
)

### See tables:
dbListTables(con)

#See interested experiments:
experiments <- dbReadTable(con, "Experiments")

runs <- dbReadTable(con, "Runs")

datasets <- dbReadTable(con, "Datasets")

query_name <- "outputs_by_tech"

###read output data
experiment_id <- "EXP_336161ed"

inputs <- read_experiment_inputs(
  con = con,
  experiment_id
)


outputs_by_tech <- read_experiment_output(
  con = con,
  experiment_id = experiment_id,
  query_name = query_name
)


### Check data base integrity

check <- check_experiment_integrity(
  con = con,
  parquet_root = "Experiments"
)

check


### Clean database

result <- clean_empty_experiments(
  con = con,
  parquet_root = "Experiments",
  dry_run = FALSE
)

##Delete specific experiment

delete_experiment(
  con = con,
  experiment_id = "EXP_336161ed",
  dry_run = FALSE,
  delete_physical_files = TRUE
)



### Delete orphan parquets


check <- clean_orphan_experiments(
  con = con,
  experiments_root = "Experiments",
  dry_run = TRUE
)

### Check files to delete
check$orphan_experiments


clean_orphan_experiments(
  con = con,
  experiments_root = "Experiments",
  dry_run = FALSE,
  delete_physical_files = TRUE
)




# update_number_iterations cuando hemos hecho un experiment pero se ha interrumpido y queremos actualizar la cantidad de runs
update_number_iterations(con, experiment_id = NULL)

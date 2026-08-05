library(DBI)
library(RSQLite)

con <- dbConnect(
  SQLite(),
  "gcam_sensitivity.sqlite"
)

### See tables:
dbListTables(con)

#See interested experiments:
experiments <- dbReadTable(con, "Experiments")
experiment_id <- "EXP_83417ce3"

runs <- dbReadTable(con, "Runs")

datasets <- dbReadTable(con, "Datasets")

query_name <- "outputs_by_tech"

###read output data


inputs <- read_experiment_inputs(
  con = con,
  experiment_id
)


outputs_by_tech <- read_experiment_output(
  con = con,
  experiment_id = experiment_id,
  query_name = query_name
)

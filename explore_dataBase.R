
library(DBI)
library(dplyr)
library(arrow)
library(purrr)

read_experiment_inputs <- function(con, experiment_id) {
  
  # Runs del experimento
  runs <- dbGetQuery(
    con,
    sprintf(
      "SELECT run_id
       FROM Runs
       WHERE experiment_id = '%s'",
      experiment_id
    )
  )
  
  # Datasets de tipo input
  datasets <- dbGetQuery(
    con,
    sprintf(
      "SELECT *
       FROM Datasets
       WHERE dataset_type = 'input'
       AND run_id IN (%s)",
      paste(sprintf("'%s'", runs$run_id), collapse = ",")
    )
  )
  
  # Leer todos los Parquet
  purrr::map_dfr(
    datasets$filepath,
    arrow::read_parquet
  )
  
}

read_experiment_output <- function(con,
                                   experiment_id,
                                   query_name) {
  
  runs <- dbGetQuery(
    con,
    sprintf(
      "SELECT run_id
       FROM Runs
       WHERE experiment_id='%s'",
      experiment_id
    )
  )
  
  datasets <- dbGetQuery(
    con,
    sprintf(
      "SELECT *
       FROM Datasets
       WHERE dataset_type='output'
       AND dataset_name='%s'
       AND run_id IN (%s)",
      query_name,
      paste(sprintf("'%s'", runs$run_id), collapse = ",")
    )
  )
  
  purrr::map_dfr(
    datasets$filepath,
    arrow::read_parquet
  )
  
}

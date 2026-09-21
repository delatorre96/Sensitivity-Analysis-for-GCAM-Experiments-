
library(DBI)
library(dplyr)
library(arrow)
library(purrr)


read_experiment_inputs <- function(con,
                                   experiment_id = NULL,
                                   execution_errors = NULL) {
  
  sql <- "
    SELECT d.*
    FROM Datasets d
    INNER JOIN Runs r
      ON d.run_id = r.run_id
    WHERE d.dataset_type = 'input'
  "
  
  params <- list()
  
  # Por defecto: excluir runs con errores
  if (is.null(execution_errors)) {
    sql <- paste0(sql, " AND r.execution_errors = 0")
  }
  
  # Si se especifican experimentos, limitar a esos experimentos
  # Acepta tanto un único ID como un vector de IDs
  if (!is.null(experiment_id)) {
    
    # Aseguramos que sea un vector
    experiment_id <- as.vector(experiment_id)
    
    # Creamos tantos ? como experimentos haya
    placeholders <- paste(rep("?", length(experiment_id)), collapse = ", ")
    
    sql <- paste0(
      sql,
      " AND r.experiment_id IN (", placeholders, ")"
    )
    
    params <- as.list(experiment_id)
  }
  
  # Ejecutar query
  if (length(params) == 0) {
    datasets <- DBI::dbGetQuery(con, sql)
  } else {
    datasets <- DBI::dbGetQuery(
      con,
      sql,
      params = params
    )
  }
  
  if (nrow(datasets) == 0) {
    return(tibble::tibble())
  }
  
  # Leer todos los Parquet
  purrr::map_dfr(
    datasets$filepath,
    arrow::read_parquet
  )
}



read_experiment_output <- function(con,
                                   query_name,
                                   experiment_id = NULL,
                                   execution_errors = NULL) {
  
  sql <- "
    SELECT d.*
    FROM Datasets d
    INNER JOIN Runs r
      ON d.run_id = r.run_id
    WHERE d.dataset_type = 'output'
      AND d.dataset_name = ?
  "
  
  params <- list(query_name)
  
  # Por defecto: excluir runs con errores
  if (is.null(execution_errors)) {
    sql <- paste0(sql, " AND r.execution_errors = 0")
  }
  
  # Si se especifican experimentos, limitar a esos experimentos
  # Acepta tanto un único ID como un vector de IDs
  if (!is.null(experiment_id)) {
    
    # Aseguramos que sea un vector
    experiment_id <- as.vector(experiment_id)
    
    # Creamos tantos ? como experimentos haya
    placeholders <- paste(
      rep("?", length(experiment_id)),
      collapse = ", "
    )
    
    sql <- paste0(
      sql,
      " AND r.experiment_id IN (", placeholders, ")"
    )
    
    params <- c(
      params,
      as.list(experiment_id)
    )
  }
  
  datasets <- DBI::dbGetQuery(
    con,
    sql,
    params = params
  )
  
  if (nrow(datasets) == 0) {
    return(tibble::tibble())
  }
  
  purrr::map_dfr(
    datasets$filepath,
    arrow::read_parquet
  )
}

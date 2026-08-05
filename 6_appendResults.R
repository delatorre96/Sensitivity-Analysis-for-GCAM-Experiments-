create_experiment_folders <- function(
    experiment_id,
    root_dir = file.path(getwd(), "Experiments")
) {
  
  experiment_dir <- file.path(root_dir, experiment_id)
  
  dir.create(
    file.path(experiment_dir, "inputs"),
    recursive = TRUE,
    showWarnings = FALSE
  )
  
  dir.create(
    file.path(experiment_dir, "outputs"),
    recursive = TRUE,
    showWarnings = FALSE
  )
  
  invisible(experiment_dir)
  
}


write_experiment_info <- function(con,
                                  experiment_id,
                                  repo,
                                  experiment_name,
                                  n_iterations,
                                  inputs_xml,
                                  outputs_queries,
                                  regions,
                                  perturbation_strategy,
                                  distribution,
                                  distribution_parameters,
                                  description = NULL,
                                  project = NULL){
  

  gcam_version <- system2(
    "git",
    c("-C", repo, "describe", "--tags"),
    stdout = TRUE
  )
  
  info <- data.frame(
    experiment_id = experiment_id,
    gcam_version = gcam_version,
    project = project,
    name = experiment_name,
    number_iterations = n_iterations,
    description = description,
    created_at = as.character(Sys.time()),
    inputs_xml = toJSON(inputs_xml, auto_unbox = TRUE),
    outputs_queries = toJSON(outputs_queries, auto_unbox = TRUE),
    regions = toJSON(regions, auto_unbox = TRUE),
    perturbation_strategy = perturbation_strategy,
    distribution = distribution,
    distribution_parameters = toJSON(distribution_parameters, auto_unbox = TRUE),
    stringsAsFactors = FALSE
  )
  
  dbAppendTable(con, "Experiments", info)
  

}

write_run_info <- function(con,
                           run_id,
                           experiment_id,
                           execution_time,
                           execution_errors = NULL,
                           delta = NA){
  
  
  info <- data.frame(
    run_id = run_id,
    experiment_id = experiment_id,
    execution_time = execution_time,
    execution_errors = execution_errors,
    delta = delta,
    stringsAsFactors = FALSE
  )
  
  dbAppendTable(con, "Runs", info)
  
}


save_inputs_parquet <- function(
    df_params_copy,
    experiment_id,
    run_id,
    root_dir = file.path(getwd(), "Experiments")
) {
  
  library(arrow)
  library(dplyr)
  
  df <- df_params_copy %>%
    select(-any_of(c(
      "id",
      "level",
      "destination_file"
    )))
  
  df$run_id <- run_id
  
  output_file <- file.path(
    root_dir,
    experiment_id,
    "inputs",
    paste0(run_id, ".parquet")
  )
  
  write_parquet(
    df,
    output_file
  )
  
  file_size_mb <- file.info(output_file)$size / (1024^2)
  
  data.frame(
    experiment_id = experiment_id,
    
    run_id = run_id,
    
    dataset_type = "input",
    
    dataset_name = "parameters",
    
    filepath = output_file,
    
    size_mb = round(file_size_mb, 2),
    
    stringsAsFactors = FALSE
    
  )
  
}



save_run_outputs <- function(
    experiment_id,
    run_id,
    queries_of_interest,
    gcam_output_dir = file.path(getwd(), "data"),
    database_dir = file.path(getwd(), "Experiments"),
    interested_query_columns = NULL
) {
  
  #Format object interested_query_columns
  if (is.list(interested_query_columns)){
    missing_queries <- setdiff(queries_of_interest, names(interested_query_columns))
    interested_query_columns[missing_queries] <- replicate(
      length(missing_queries),
      NULL,
      simplify = FALSE
    )
    
    names(interested_query_columns) <- gsub(
      "\\s+",
      "_",
      names(interested_query_columns)
    )
  }else if(is.vector(interested_query_columns)){
    interested_query_columns <- setNames(
      replicate(
        length(queries_of_interest),
        interested_query_columns,
        simplify = FALSE
      ),
      queries_of_interest
    )
    
    names(interested_query_columns) <- gsub(
      "\\s+",
      "_",
      names(interested_query_columns)
    )
  }
  
  library(arrow)
  
  source_files <- list.files(
    gcam_output_dir,
    pattern = "0\\.csv$",
    full.names = TRUE
  )
  
  datasets_info <- list()
  
  for (source_file in source_files) {
    
    ##------------------------------------------------------------
    ## Validar archivo
    ##------------------------------------------------------------
    
    lines <- tryCatch(
      readLines(source_file, warn = FALSE),
      error = function(e) NULL
    )
    
    if (is.null(lines) ||
        length(lines) < 2 ||
        grepl("had error", lines[1], ignore.case = TRUE)) {
      
      warning(
        sprintf(
          "Se omite '%s' porque el resultado es inválido.",
          basename(source_file)
        ),
        call. = FALSE
      )
      
      next
    }
    
    ##------------------------------------------------------------
    ## Leer CSV
    ##------------------------------------------------------------
    
    df <- tryCatch(
      read.csv(
        source_file,
        check.names = FALSE,
        skip = 1
      ),
      error = function(e) NULL
    )
    
    if (is.null(df)) {
      
      warning(
        sprintf(
          "No se pudo leer '%s'.",
          basename(source_file)
        ),
        call. = FALSE
      )
      
      next
    }
    
    ## Eliminar columnas vacías
    
    df <- df[, colSums(!is.na(df)) > 0, drop = FALSE]
    
    if (nrow(df) == 0) {
      
      warning(
        sprintf(
          "La consulta '%s' no devolvió filas.",
          basename(source_file)
        ),
        call. = FALSE
      )
      
      next
    }
    
    ##------------------------------------------------------------
    ## Añadir run_id
    ##------------------------------------------------------------
    
    
    ##------------------------------------------------------------
    ## Obtener nombre de la query
    ##------------------------------------------------------------
    
    query_name <- sub(
      "0\\.csv$",
      "",
      basename(source_file)
    )
    
    cols_to_save <- interested_query_columns[[query_name]]
    
    if (!is.null(interested_query_columns)) {
      
      cols_to_save <- interested_query_columns[[query_name]]
      
      if (!is.null(cols_to_save)) {
        
        cols <- intersect(cols_to_save, names(df))
        
        df <- df[, cols, drop = FALSE]
        
      }
      
    }
    
    df$run_id <- run_id
    
    ##------------------------------------------------------------
    ## Crear estructura de carpetas
    ##------------------------------------------------------------
    
    output_dir <- file.path(
      database_dir,
      experiment_id,
      "outputs",
      query_name
    )
    
    dir.create(
      output_dir,
      recursive = TRUE,
      showWarnings = FALSE
    )
    
    output_file <- file.path(
      output_dir,
      paste0(run_id, ".parquet")
    )
    
    ##------------------------------------------------------------
    ## Escribir parquet
    ##------------------------------------------------------------
    
    write_parquet(
      df,
      output_file
    )
    
    file_size_mb <- file.info(output_file)$size / (1024^2)
    ##------------------------------------------------------------
    ## Guardar metadatos
    ##------------------------------------------------------------
    
    datasets_info[[length(datasets_info) + 1]] <-
      
      data.frame(
        
        experiment_id = experiment_id,
        
        run_id = run_id,
        
        dataset_type = "output",
        
        dataset_name = query_name,
        
        filepath = output_file,
        
        size_mb = round(file_size_mb, 2),
        
        stringsAsFactors = FALSE
        
      )
    
  }
  
  ##------------------------------------------------------------
  ## Devolver información para insertar en SQLite
  ##------------------------------------------------------------
  
  if (length(datasets_info) == 0) {
    
    return(NULL)
    
  }
  
  do.call(rbind, datasets_info)
  
}


write_datasets_info <- function(
    con,
    datasets
) {
  
  dbAppendTable(con, "Datasets", datasets)
  
}



delete_iteration_csvs <- function(data_dir = file.path(getwd(), "Data")) {
  
  files <- list.files(
    data_dir,
    pattern = "0\\.csv$",
    full.names = TRUE
  )
  
  if (length(files) > 0) {
    file.remove(files)
  }
  
  invisible(NULL)
}



merge_experiments <- function(
    con,
    experiment_ids,
    experiments_dir = "Experiments"
) {
  
  ##------------------------------------------------------------
  ## 0. Comprobaciones iniciales
  ##------------------------------------------------------------
  
  if(length(experiment_ids) < 2)
    stop("At least two experiments are required.")
  
  experiment_ids <- unique(experiment_ids)
  
  experiments <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT * FROM Experiments
             WHERE experiment_id IN (%s)",
      paste(sprintf("'%s'", experiment_ids),
            collapse = ",")
    )
  )
  
  if(nrow(experiments) != length(experiment_ids))
    stop("Some experiment_ids do not exist.")
  
  ##------------------------------------------------------------
  ## 1. Verificar que son equivalentes
  ##------------------------------------------------------------
  
  compare_cols <- c(
    "project",
    "gcam_version",
    "number_iterations",
    "inputs_xml",
    "outputs_queries",
    "regions",
    "perturbation_strategy",
    "distribution",
    "distribution_parameters"
  )
  
  reference <- experiments[1, compare_cols]
  
  for(i in seq_len(nrow(experiments))){
    
    if(!identical(
      as.list(reference),
      as.list(experiments[i, compare_cols])
    )){
      stop(
        "Experiments are not equivalent and cannot be merged."
      )
    }
    
  }
  
  message("Experiments successfully validated.")
  
  ##------------------------------------------------------------
  ## 2. Crear nuevo experiment_id
  ##------------------------------------------------------------
  
  new_experiment_id <- paste0(
    "EXP_",
    substr(uuid::UUIDgenerate(),1,8)
  )
  
  message(
    "New experiment id: ",
    new_experiment_id
  )
  
  ##------------------------------------------------------------
  ## 3. Crear nuevo registro
  ##------------------------------------------------------------
  
  new_exp <- experiments[1, ]
  
  new_exp$experiment_id <- new_experiment_id
  
  new_exp$created_at <- as.character(Sys.time())
  
  DBI::dbWriteTable(
    con,
    "Experiments",
    new_exp,
    append = TRUE
  )
  
  ##------------------------------------------------------------
  ## 4. Crear estructura de carpetas
  ##------------------------------------------------------------
  
  new_folder <- file.path(
    experiments_dir,
    new_experiment_id
  )
  
  dir.create(
    file.path(new_folder,"inputs"),
    recursive = TRUE,
    showWarnings = FALSE
  )
  
  dir.create(
    file.path(new_folder,"outputs"),
    recursive = TRUE,
    showWarnings = FALSE
  )
  
  ##------------------------------------------------------------
  ## 5. Mover inputs
  ##------------------------------------------------------------
  
  for(exp in experiment_ids){
    
    input_dir <- file.path(
      experiments_dir,
      exp,
      "inputs"
    )
    
    files <- list.files(
      input_dir,
      full.names = TRUE
    )
    
    if(length(files)>0){
      
      file.rename(
        files,
        file.path(
          new_folder,
          "inputs",
          basename(files)
        )
      )
      
    }
    
  }
  
  ##------------------------------------------------------------
  ## 6. Mover outputs
  ##------------------------------------------------------------
  
  for(exp in experiment_ids){
    
    output_root <- file.path(
      experiments_dir,
      exp,
      "outputs"
    )
    
    queries <- list.dirs(
      output_root,
      recursive = FALSE,
      full.names = FALSE
    )
    
    for(query in queries){
      
      source_query <- file.path(
        output_root,
        query
      )
      
      target_query <- file.path(
        new_folder,
        "outputs",
        query
      )
      
      dir.create(
        target_query,
        recursive = TRUE,
        showWarnings = FALSE
      )
      
      files <- list.files(
        source_query,
        full.names = TRUE
      )
      
      if(length(files)>0){
        
        file.rename(
          files,
          file.path(
            target_query,
            basename(files)
          )
        )
        
      }
      
    }
    
  }
  
  ##------------------------------------------------------------
  ## 7. Actualizar SQL
  ##------------------------------------------------------------
  
  DBI::dbBegin(con)
  
  tryCatch({
    
    DBI::dbExecute(
      con,
      sprintf(
        "UPDATE Runs
                 SET experiment_id='%s'
                 WHERE experiment_id IN (%s)",
        new_experiment_id,
        paste(
          sprintf("'%s'",experiment_ids),
          collapse=","
        )
      )
    )
    
    DBI::dbExecute(
      con,
      sprintf(
        "UPDATE Datasets
                 SET
                    experiment_id='%s',
                    filepath=REPLACE(filepath,
                        experiment_id,
                        '%s')
                 WHERE experiment_id IN (%s)",
        new_experiment_id,
        new_experiment_id,
        paste(
          sprintf("'%s'",experiment_ids),
          collapse=","
        )
      )
    )
    
    DBI::dbExecute(
      con,
      sprintf(
        "DELETE FROM Experiments
                 WHERE experiment_id IN (%s)",
        paste(
          sprintf("'%s'",experiment_ids),
          collapse=","
        )
      )
    )
    
    DBI::dbCommit(con)
    
  },
  error=function(e){
    
    DBI::dbRollback(con)
    
    stop(e)
    
  })
  
  ##------------------------------------------------------------
  ## 8. Eliminar carpetas vacías
  ##------------------------------------------------------------
  
  for(exp in experiment_ids){
    
    unlink(
      file.path(
        experiments_dir,
        exp
      ),
      recursive = TRUE
    )
    
  }
  
  message(
    "Merge completed successfully."
  )
  
  invisible(new_experiment_id)
  
}



update_number_iterations <- function(con, experiment_id = NULL){
  
  if(is.null(experiment_id)){
    
    ids <- DBI::dbGetQuery(
      con,
      "SELECT experiment_id FROM Experiments"
    )$experiment_id
    
  } else {
    
    ids <- experiment_id
    
  }
  
  for(id in ids){
    
    n <- DBI::dbGetQuery(
      con,
      sprintf(
        "SELECT COUNT(*) AS n
         FROM Runs
         WHERE experiment_id='%s'",
        id
      )
    )$n
    
    DBI::dbExecute(
      con,
      sprintf(
        "UPDATE Experiments
         SET number_iterations=%d
         WHERE experiment_id='%s'",
        n,
        id
      )
    )
    
  }
  
  invisible(TRUE)
  
}




create_or_add_experiment_id <- function(experiment_id_to_add){
  if (is.null(experiment_id_to_add)){
    experiment_id <- paste0(
      "EXP_",
      substr(UUIDgenerate(), 1, 8))
    message(paste0('Starting experiment: ',experiment_id))
  }else{
    #check if experiment_id_to_add exists in the db
    if (file.exists('gcam_sensitivity.sqlite')){
      con <- dbConnect(
        SQLite(),
        "gcam_sensitivity.sqlite"
      )
      experiments_table <- dbReadTable(con, "Experiments")
      if (experiment_id_to_add %in% experiments_table$experiment_id){
        experiment_id = experiment_id_to_add
        message(paste0('Adding to: ',experiment_id))
      } else{
        message(paste0('Experiment id does not exist. Re-run experiment seting experiment_id_to_add as NULL or any existent experiment_id'))
        stop()
      }
      
    } else{
      message(paste0('db does not exist. Re-run experiment seting experiment_id_to_add as NULL'))
      stop()
    }
  }
  return(experiment_id)
}




# ============================================================
# CHECK PARQUET
# ============================================================

check_parquet_file <- function(filepath, check_read = TRUE) {
  
  if (is.na(filepath) || !nzchar(filepath)) {
    return(list(
      exists = FALSE,
      valid = FALSE,
      reason = "empty_filepath"
    ))
  }
  
  if (!file.exists(filepath)) {
    return(list(
      exists = FALSE,
      valid = FALSE,
      reason = "file_not_found"
    ))
  }
  
  # A parquet file should not be empty
  file_size <- file.info(filepath)$size
  
  if (is.na(file_size) || file_size == 0) {
    return(list(
      exists = TRUE,
      valid = FALSE,
      reason = "empty_file"
    ))
  }
  
  # Check that the file can actually be read by Arrow
  if (check_read) {
    
    read_result <- tryCatch(
      {
        arrow::read_parquet(
          filepath,
          as_data_frame = FALSE
        )
        
        TRUE
      },
      error = function(e) {
        FALSE
      }
    )
    
    if (!read_result) {
      return(list(
        exists = TRUE,
        valid = FALSE,
        reason = "cannot_read_parquet"
      ))
    }
  }
  
  list(
    exists = TRUE,
    valid = TRUE,
    reason = "valid"
  )
}


# ============================================================
# CHECK EXPERIMENT INTEGRITY
# ============================================================

check_experiment_integrity <- function(
    con,
    experiment_id = NULL,
    parquet_root = ".",
    check_read = TRUE
) {
  
  # ----------------------------------------------------------
  # Get experiments
  # ----------------------------------------------------------
  
  if (is.null(experiment_id)) {
    
    experiments <- DBI::dbGetQuery(
      con,
      "SELECT experiment_id FROM Experiments"
    )
    
  } else {
    
    experiments <- data.frame(
      experiment_id = experiment_id,
      stringsAsFactors = FALSE
    )
  }
  
  
  # ----------------------------------------------------------
  # Empty database
  # ----------------------------------------------------------
  
  if (nrow(experiments) == 0) {
    return(data.frame())
  }
  
  
  results <- vector("list", nrow(experiments))
  
  
  # ==========================================================
  # Loop over experiments
  # ==========================================================
  
  for (i in seq_len(nrow(experiments))) {
    
    exp_id <- experiments$experiment_id[i]
    
    
    # --------------------------------------------------------
    # Runs associated with experiment
    # --------------------------------------------------------
    
    runs <- DBI::dbGetQuery(
      con,
      "
      SELECT
        run_id,
        execution_errors
      FROM Runs
      WHERE experiment_id = ?
      ",
      params = list(exp_id)
    )
    
    
    # --------------------------------------------------------
    # Datasets associated with experiment
    # --------------------------------------------------------
    
    datasets <- DBI::dbGetQuery(
      con,
      "
      SELECT
        experiment_id,
        run_id,
        dataset_type,
        dataset_name,
        filepath
      FROM Datasets
      WHERE experiment_id = ?
      ",
      params = list(exp_id)
    )
    
    
    # --------------------------------------------------------
    # Check every parquet registered in Datasets
    # --------------------------------------------------------
    
    if (nrow(datasets) > 0) {
      
      datasets$filepath_resolved <- vapply(
        datasets$filepath,
        function(x) {
          
          if (is.na(x) || !nzchar(x)) {
            return(NA_character_)
          }
          
          # If filepath is already absolute, use it directly
          if (grepl("^(/|[A-Za-z]:[/\\\\])", x)) {
            return(normalizePath(
              x,
              winslash = "/",
              mustWork = FALSE
            ))
          }
          
          # Otherwise interpret it relative to parquet_root
          normalizePath(
            file.path(parquet_root, x),
            winslash = "/",
            mustWork = FALSE
          )
        },
        character(1)
      )
      
      
      parquet_checks <- lapply(
        datasets$filepath_resolved,
        check_parquet_file,
        check_read = check_read
      )
      
      datasets$parquet_exists <- vapply(
        parquet_checks,
        `[[`,
        logical(1),
        "exists"
      )
      
      datasets$parquet_valid <- vapply(
        parquet_checks,
        `[[`,
        logical(1),
        "valid"
      )
      
      datasets$parquet_status <- vapply(
        parquet_checks,
        `[[`,
        character(1),
        "reason"
      )
      
    } else {
      
      datasets$filepath_resolved <- character(0)
      datasets$parquet_exists <- logical(0)
      datasets$parquet_valid <- logical(0)
      datasets$parquet_status <- character(0)
    }
    
    
    # --------------------------------------------------------
    # Summary
    # --------------------------------------------------------
    
    n_runs <- nrow(runs)
    n_datasets <- nrow(datasets)
    
    n_existing_parquet <- if (n_datasets > 0) {
      sum(datasets$parquet_exists)
    } else {
      0L
    }
    
    n_valid_parquet <- if (n_datasets > 0) {
      sum(datasets$parquet_valid)
    } else {
      0L
    }
    
    
    # --------------------------------------------------------
    # Which runs have a valid parquet?
    # --------------------------------------------------------
    
    runs_with_valid_parquet <- if (n_datasets > 0) {
      unique(
        datasets$run_id[datasets$parquet_valid]
      )
    } else {
      character(0)
    }
    
    n_runs_with_valid_parquet <- length(
      runs_with_valid_parquet
    )
    
    
    # --------------------------------------------------------
    # Decide whether experiment should be deleted
    # --------------------------------------------------------
    
    delete_experiment <- n_valid_parquet == 0
    
    
    if (delete_experiment) {
      
      if (n_runs == 0) {
        reason <- "no_runs"
        
      } else if (n_datasets == 0) {
        reason <- "runs_without_datasets"
        
      } else if (n_existing_parquet == 0) {
        reason <- "all_parquet_missing"
        
      } else {
        reason <- "all_parquet_invalid"
      }
      
    } else {
      
      reason <- "valid_parquet_exists"
    }
    
    
    # --------------------------------------------------------
    # Store result
    # --------------------------------------------------------
    
    results[[i]] <- data.frame(
      experiment_id = exp_id,
      n_runs = n_runs,
      n_datasets = n_datasets,
      n_existing_parquet = n_existing_parquet,
      n_valid_parquet = n_valid_parquet,
      n_runs_with_valid_parquet = n_runs_with_valid_parquet,
      delete_experiment = delete_experiment,
      reason = reason,
      stringsAsFactors = FALSE
    )
  }
  
  
  dplyr::bind_rows(results)
}


# ============================================================
# CLEAN EMPTY EXPERIMENTS
# ============================================================

clean_empty_experiments <- function(
    con,
    parquet_root = ".",
    experiment_id = NULL,
    dry_run = TRUE,
    check_read = TRUE,
    delete_physical_files = FALSE
) {
  
  # ----------------------------------------------------------
  # First perform integrity check
  # ----------------------------------------------------------
  
  integrity <- check_experiment_integrity(
    con = con,
    experiment_id = experiment_id,
    parquet_root = parquet_root,
    check_read = check_read
  )
  
  
  experiments_to_delete <- integrity$experiment_id[
    integrity$delete_experiment
  ]
  
  
  # ----------------------------------------------------------
  # Nothing to delete
  # ----------------------------------------------------------
  
  if (length(experiments_to_delete) == 0) {
    
    message("No empty experiments found.")
    
    return(list(
      integrity = integrity,
      deleted = character(0),
      dry_run = dry_run
    ))
  }
  
  
  # ----------------------------------------------------------
  # DRY RUN
  # ----------------------------------------------------------
  
  if (dry_run) {
    
    message(
      "DRY RUN: ",
      length(experiments_to_delete),
      " experiment(s) would be deleted."
    )
    
    return(list(
      integrity = integrity,
      deleted = character(0),
      would_delete = experiments_to_delete,
      dry_run = TRUE
    ))
  }
  
  
  # ==========================================================
  # DELETE
  # ==========================================================
  
  DBI::dbBegin(con)
  
  success <- FALSE
  
  tryCatch({
    
    for (exp_id in experiments_to_delete) {
      
      # ------------------------------------------------------
      # Get physical parquet files before deleting DB records
      # ------------------------------------------------------
      
      datasets <- DBI::dbGetQuery(
        con,
        "
        SELECT filepath
        FROM Datasets
        WHERE experiment_id = ?
        ",
        params = list(exp_id)
      )
      
      
      # ------------------------------------------------------
      # Delete Datasets
      # ------------------------------------------------------
      
      DBI::dbExecute(
        con,
        "
        DELETE FROM Datasets
        WHERE experiment_id = ?
        ",
        params = list(exp_id)
      )
      
      
      # ------------------------------------------------------
      # Delete Runs
      # ------------------------------------------------------
      
      DBI::dbExecute(
        con,
        "
        DELETE FROM Runs
        WHERE experiment_id = ?
        ",
        params = list(exp_id)
      )
      
      
      # ------------------------------------------------------
      # Delete Experiment
      # ------------------------------------------------------
      
      DBI::dbExecute(
        con,
        "
        DELETE FROM Experiments
        WHERE experiment_id = ?
        ",
        params = list(exp_id)
      )
      
      
      # ------------------------------------------------------
      # Optionally delete physical parquet files
      # ------------------------------------------------------
      
      if (delete_physical_files && nrow(datasets) > 0) {
        
        for (filepath in datasets$filepath) {
          
          if (is.na(filepath) || !nzchar(filepath)) {
            next
          }
          
          if (grepl("^(/|[A-Za-z]:[/\\\\])", filepath)) {
            full_path <- filepath
          } else {
            full_path <- file.path(
              parquet_root,
              filepath
            )
          }
          
          if (file.exists(full_path)) {
            file.remove(full_path)
          }
        }
      }
    }
    
    
    DBI::dbCommit(con)
    success <- TRUE
    
  }, error = function(e) {
    
    DBI::dbRollback(con)
    
    stop(
      "Experiment cleanup failed. ",
      "All database changes were rolled back.\n",
      "Original error: ",
      conditionMessage(e)
    )
  })
  
  
  # ----------------------------------------------------------
  # Return summary
  # ----------------------------------------------------------
  
  message(
    length(experiments_to_delete),
    " experiment(s) deleted successfully."
  )
  
  
  list(
    integrity = integrity,
    deleted = experiments_to_delete,
    dry_run = FALSE,
    success = success
  )
}


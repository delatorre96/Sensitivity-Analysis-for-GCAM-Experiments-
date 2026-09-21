
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







delete_experiment <- function(
    con,
    experiment_id,
    dry_run = TRUE,
    delete_physical_files = FALSE
) {
  
  # ==========================================================
  # 1. Check that experiment exists
  # ==========================================================
  
  experiment <- DBI::dbGetQuery(
    con,
    "
    SELECT *
    FROM Experiments
    WHERE experiment_id = ?
    ",
    params = list(experiment_id)
  )
  
  if (nrow(experiment) == 0) {
    stop(
      "Experiment '", experiment_id,
      "' does not exist in the database."
    )
  }
  
  
  # ==========================================================
  # 2. Get associated runs
  # ==========================================================
  
  runs <- DBI::dbGetQuery(
    con,
    "
    SELECT *
    FROM Runs
    WHERE experiment_id = ?
    ",
    params = list(experiment_id)
  )
  
  
  # ==========================================================
  # 3. Get associated datasets and filepaths
  # ==========================================================
  
  datasets <- DBI::dbGetQuery(
    con,
    "
    SELECT *
    FROM Datasets
    WHERE experiment_id = ?
    ",
    params = list(experiment_id)
  )
  
  
  parquet_paths <- character(0)
  
  if (
    delete_physical_files &&
    nrow(datasets) > 0 &&
    "filepath" %in% names(datasets)
  ) {
    
    parquet_paths <- unique(
      datasets$filepath[
        !is.na(datasets$filepath) &
          nzchar(datasets$filepath)
      ]
    )
  }
  
  
  # ==========================================================
  # 4. Show what will be deleted
  # ==========================================================
  
  message("Experiment: ", experiment_id)
  message("Runs:       ", nrow(runs))
  message("Datasets:   ", nrow(datasets))
  
  if (delete_physical_files) {
    message(
      "Parquet files to delete: ",
      length(parquet_paths)
    )
  }
  
  
  # ==========================================================
  # 5. DRY RUN
  # ==========================================================
  
  if (dry_run) {
    
    message("----------------------------")
    message("DRY RUN: no changes made.")
    
    return(
      invisible(
        list(
          experiment_id = experiment_id,
          experiment = experiment,
          runs = runs,
          datasets = datasets,
          parquet_paths = parquet_paths,
          dry_run = TRUE
        )
      )
    )
  }
  
  
  # ==========================================================
  # 6. Delete from database
  # ==========================================================
  
  DBI::dbBegin(con)
  
  tryCatch({
    
    # Delete datasets
    DBI::dbExecute(
      con,
      "
      DELETE FROM Datasets
      WHERE experiment_id = ?
      ",
      params = list(experiment_id)
    )
    
    
    # Delete runs
    DBI::dbExecute(
      con,
      "
      DELETE FROM Runs
      WHERE experiment_id = ?
      ",
      params = list(experiment_id)
    )
    
    
    # Delete experiment
    DBI::dbExecute(
      con,
      "
      DELETE FROM Experiments
      WHERE experiment_id = ?
      ",
      params = list(experiment_id)
    )
    
    
    DBI::dbCommit(con)
    
  }, error = function(e) {
    
    DBI::dbRollback(con)
    
    stop(
      "Could not delete experiment '",
      experiment_id,
      "'. Database changes were rolled back.\n",
      conditionMessage(e)
    )
  })
  
  
  # ==========================================================
  # 7. Delete physical parquet files
  # ==========================================================
  
  deleted_files <- character(0)
  missing_files <- character(0)
  
  if (
    delete_physical_files &&
    length(parquet_paths) > 0
  ) {
    
    for (filepath in parquet_paths) {
      
      if (file.exists(filepath)) {
        
        if (file.remove(filepath)) {
          
          deleted_files <- c(
            deleted_files,
            filepath
          )
          
        }
        
      } else {
        
        missing_files <- c(
          missing_files,
          filepath
        )
      }
    }
  }
  
  
  # ==========================================================
  # 8. Final message
  # ==========================================================
  
  message(
    "Experiment '",
    experiment_id,
    "' deleted successfully."
  )
  
  message(
    "Runs deleted: ",
    nrow(runs)
  )
  
  message(
    "Datasets deleted: ",
    nrow(datasets)
  )
  
  if (delete_physical_files) {
    
    message(
      "Parquet files deleted: ",
      length(deleted_files)
    )
    
    message(
      "Parquet files not found: ",
      length(missing_files)
    )
  }
  
  
  invisible(
    list(
      success = TRUE,
      experiment_id = experiment_id,
      n_runs_deleted = nrow(runs),
      n_datasets_deleted = nrow(datasets),
      deleted_files = deleted_files,
      missing_files = missing_files
    )
  )
}



# ============================================================
# CHECK ONE EXPERIMENT DIRECTORY
# ============================================================

check_experiment_directory <- function(
    experiment_path,
    experiment_id
) {
  
  inputs_path <- file.path(
    experiment_path,
    "inputs"
  )
  
  outputs_path <- file.path(
    experiment_path,
    "outputs"
  )
  
  
  # ----------------------------------------------------------
  # Inputs
  # ----------------------------------------------------------
  
  if (dir.exists(inputs_path)) {
    
    input_files <- list.files(
      inputs_path,
      pattern = "\\.parquet$",
      full.names = TRUE,
      recursive = FALSE,
      ignore.case = TRUE
    )
    
  } else {
    
    input_files <- character(0)
  }
  
  
  # ----------------------------------------------------------
  # Outputs
  # ----------------------------------------------------------
  
  if (dir.exists(outputs_path)) {
    
    output_files <- list.files(
      outputs_path,
      pattern = "\\.parquet$",
      full.names = TRUE,
      recursive = FALSE,
      ignore.case = TRUE
    )
    
  } else {
    
    output_files <- character(0)
  }
  
  
  n_inputs <- length(input_files)
  n_outputs <- length(output_files)
  
  
  inputs_empty <- (
    !dir.exists(inputs_path) ||
      n_inputs == 0
  )
  
  outputs_empty <- (
    !dir.exists(outputs_path) ||
      n_outputs == 0
  )
  
  
  # ----------------------------------------------------------
  # Reason
  # ----------------------------------------------------------
  
  if (inputs_empty && outputs_empty) {
    
    reason <- "inputs_and_outputs_empty"
    
  } else if (inputs_empty) {
    
    reason <- "inputs_empty"
    
  } else if (outputs_empty) {
    
    reason <- "outputs_empty"
    
  } else {
    
    reason <- "valid"
  }
  
  
  data.frame(
    experiment_id = experiment_id,
    experiment_path = normalizePath(
      experiment_path,
      winslash = "/",
      mustWork = FALSE
    ),
    inputs_exists = dir.exists(inputs_path),
    outputs_exists = dir.exists(outputs_path),
    n_input_parquets = n_inputs,
    n_output_parquets = n_outputs,
    inputs_empty = inputs_empty,
    outputs_empty = outputs_empty,
    reason = reason,
    stringsAsFactors = FALSE
  )
}



# ============================================================
# CHECK PHYSICAL EXPERIMENT
# ============================================================

check_physical_experiment <- function(experiment_path) {
  
  inputs_path <- file.path(
    experiment_path,
    "inputs"
  )
  
  outputs_path <- file.path(
    experiment_path,
    "outputs"
  )
  
  
  # ----------------------------------------------------------
  # Find parquet files recursively
  # ----------------------------------------------------------
  
  input_parquets <- character(0)
  output_parquets <- character(0)
  
  
  if (dir.exists(inputs_path)) {
    
    input_parquets <- list.files(
      inputs_path,
      pattern = "\\.parquet$",
      recursive = TRUE,
      full.names = TRUE,
      ignore.case = TRUE
    )
  }
  
  
  if (dir.exists(outputs_path)) {
    
    output_parquets <- list.files(
      outputs_path,
      pattern = "\\.parquet$",
      recursive = TRUE,
      full.names = TRUE,
      ignore.case = TRUE
    )
  }
  
  
  # ----------------------------------------------------------
  # Return information
  # ----------------------------------------------------------
  
  n_inputs <- length(input_parquets)
  n_outputs <- length(output_parquets)
  n_total <- n_inputs + n_outputs
  
  
  list(
    exists = TRUE,
    inputs_exists = dir.exists(inputs_path),
    outputs_exists = dir.exists(outputs_path),
    input_parquets = input_parquets,
    output_parquets = output_parquets,
    n_input_parquets = n_inputs,
    n_output_parquets = n_outputs,
    n_parquets = n_total,
    has_parquet = n_total > 0
  )
}


# ============================================================
# CLEAN ORPHAN EXPERIMENTS
# ============================================================

clean_orphan_experiments <- function(
    con,
    experiments_root,
    dry_run = TRUE,
    delete_physical_files = TRUE
) {
  
  # ==========================================================
  # 1. Validate root directory
  # ==========================================================
  
  if (!dir.exists(experiments_root)) {
    
    stop(
      "Experiments directory does not exist: ",
      experiments_root
    )
  }
  
  
  experiments_root <- normalizePath(
    experiments_root,
    winslash = "/",
    mustWork = TRUE
  )
  
  
  # ==========================================================
  # 2. Get experiments from SQLite
  # ==========================================================
  
  db_experiments <- DBI::dbGetQuery(
    con,
    "
    SELECT experiment_id
    FROM Experiments
    "
  )
  
  
  db_experiment_ids <- unique(
    as.character(db_experiments$experiment_id)
  )
  
  
  # ==========================================================
  # 3. Get physical experiment directories
  # ==========================================================
  
  physical_experiment_dirs <- list.dirs(
    experiments_root,
    full.names = TRUE,
    recursive = FALSE
  )
  
  
  # Keep only directories beginning with EXP_
  
  physical_experiment_dirs <- physical_experiment_dirs[
    grepl(
      "^EXP_[^/\\\\]+$",
      basename(physical_experiment_dirs)
    )
  ]
  
  
  physical_experiment_ids <- basename(
    physical_experiment_dirs
  )
  
  
  # ==========================================================
  # 4. Check every physical experiment
  # ==========================================================
  
  physical_checks <- vector(
    "list",
    length(physical_experiment_dirs)
  )
  
  
  if (length(physical_experiment_dirs) > 0) {
    
    for (i in seq_along(physical_experiment_dirs)) {
      
      experiment_id <- physical_experiment_ids[i]
      experiment_path <- physical_experiment_dirs[i]
      
      check <- check_physical_experiment(
        experiment_path
      )
      
      
      physical_checks[[i]] <- data.frame(
        experiment_id = experiment_id,
        experiment_path = experiment_path,
        in_database = experiment_id %in% db_experiment_ids,
        inputs_exists = check$inputs_exists,
        outputs_exists = check$outputs_exists,
        n_input_parquets = check$n_input_parquets,
        n_output_parquets = check$n_output_parquets,
        n_parquets = check$n_parquets,
        has_parquet = check$has_parquet,
        stringsAsFactors = FALSE
      )
    }
  }
  
  
  physical_results <- if (
    length(physical_checks) > 0
  ) {
    dplyr::bind_rows(physical_checks)
  } else {
    data.frame(
      experiment_id = character(0),
      experiment_path = character(0),
      in_database = logical(0),
      inputs_exists = logical(0),
      outputs_exists = logical(0),
      n_input_parquets = integer(0),
      n_output_parquets = integer(0),
      n_parquets = integer(0),
      has_parquet = logical(0),
      stringsAsFactors = FALSE
    )
  }
  
  
  # ==========================================================
  # 5. Physical orphan experiments
  # ==========================================================
  #
  # A physical experiment is orphan if:
  #
  #   - its folder exists
  #   - it contains NO parquet anywhere under
  #     inputs or outputs
  #
  # OR
  #
  #   - it is not registered in the database
  #
  # ==========================================================
  
  physical_orphans <- physical_results[
    !physical_results$in_database |
      !physical_results$has_parquet,
    ,
    drop = FALSE
  ]
  
  
  # ==========================================================
  # 6. Experiments registered in DB but with no physical folder
  # ==========================================================
  
  db_only_experiments <- setdiff(
    db_experiment_ids,
    physical_experiment_ids
  )
  
  
  # ==========================================================
  # 7. Classify physical orphan reason
  # ==========================================================
  
  if (nrow(physical_orphans) > 0) {
    
    physical_orphans$reason <- NA_character_
    
    
    for (i in seq_len(nrow(physical_orphans))) {
      
      in_db <- physical_orphans$in_database[i]
      has_parquet <- physical_orphans$has_parquet[i]
      
      
      if (!in_db && !has_parquet) {
        
        physical_orphans$reason[i] <-
          "not_in_database_and_no_parquet"
        
      } else if (!in_db) {
        
        physical_orphans$reason[i] <-
          "physical_experiment_not_in_database"
        
      } else if (!has_parquet) {
        
        physical_orphans$reason[i] <-
          "database_experiment_without_parquet"
      }
    }
  }
  
  
  # ==========================================================
  # 8. DRY RUN
  # ==========================================================
  
  if (dry_run) {
    
    message("")
    message("========================================")
    message("DRY RUN")
    message("========================================")
    
    
    message(
      "Experiments in database: ",
      length(db_experiment_ids)
    )
    
    message(
      "Physical experiment folders: ",
      length(physical_experiment_ids)
    )
    
    message(
      "Physical orphan experiments: ",
      nrow(physical_orphans)
    )
    
    message(
      "Database experiments without folder: ",
      length(db_only_experiments)
    )
    
    
    # --------------------------------------------------------
    # Show orphan experiments
    # --------------------------------------------------------
    
    if (nrow(physical_orphans) > 0) {
      
      message("")
      message("Experiments that would be deleted:")
      message("")
      
      for (i in seq_len(nrow(physical_orphans))) {
        
        message(
          " - ",
          physical_orphans$experiment_id[i],
          " | ",
          physical_orphans$reason[i],
          " | ",
          physical_orphans$n_parquets[i],
          " parquet(s)"
        )
      }
    }
    
    
    # --------------------------------------------------------
    # Return
    # --------------------------------------------------------
    
    return(
      invisible(
        list(
          physical_results = physical_results,
          orphan_experiments = physical_orphans,
          database_without_folder = db_only_experiments,
          deleted = character(0),
          dry_run = TRUE
        )
      )
    )
  }
  
  
  # ==========================================================
  # 9. DELETE
  # ==========================================================
  
  experiments_to_delete <- physical_orphans$experiment_id
  
  
  if (length(experiments_to_delete) == 0) {
    
    message(
      "No orphan experiments found."
    )
    
    return(
      invisible(
        list(
          physical_results = physical_results,
          orphan_experiments = physical_orphans,
          database_without_folder = db_only_experiments,
          deleted = character(0),
          dry_run = FALSE,
          success = TRUE
        )
      )
    )
  }
  
  
  deleted <- character(0)
  failed <- character(0)
  
  
  for (experiment_id in experiments_to_delete) {
    
    experiment_path <- physical_orphans$experiment_path[
      physical_orphans$experiment_id == experiment_id
    ]
    
    
    # --------------------------------------------------------
    # Delete from database if present
    # --------------------------------------------------------
    
    if (experiment_id %in% db_experiment_ids) {
      
      DBI::dbBegin(con)
      
      tryCatch({
        
        DBI::dbExecute(
          con,
          "
          DELETE FROM Datasets
          WHERE experiment_id = ?
          ",
          params = list(experiment_id)
        )
        
        
        DBI::dbExecute(
          con,
          "
          DELETE FROM Runs
          WHERE experiment_id = ?
          ",
          params = list(experiment_id)
        )
        
        
        DBI::dbExecute(
          con,
          "
          DELETE FROM Experiments
          WHERE experiment_id = ?
          ",
          params = list(experiment_id)
        )
        
        
        DBI::dbCommit(con)
        
      }, error = function(e) {
        
        DBI::dbRollback(con)
        
        stop(
          "Could not delete experiment '",
          experiment_id,
          "' from database.\n",
          conditionMessage(e)
        )
      })
    }
    
    
    # --------------------------------------------------------
    # Delete physical directory
    # --------------------------------------------------------
    
    if (
      delete_physical_files &&
      dir.exists(experiment_path)
    ) {
      
      success <- unlink(
        experiment_path,
        recursive = TRUE,
        force = TRUE
      ) == 0
      
      
      if (success) {
        
        deleted <- c(
          deleted,
          experiment_id
        )
        
      } else {
        
        failed <- c(
          failed,
          experiment_id
        )
      }
      
    } else {
      
      deleted <- c(
        deleted,
        experiment_id
      )
    }
  }
  
  
  # ==========================================================
  # 10. Final message
  # ==========================================================
  
  message("")
  message(
    length(deleted),
    " orphan experiment(s) deleted."
  )
  
  
  if (length(failed) > 0) {
    
    message(
      length(failed),
      " experiment(s) could not be completely deleted."
    )
  }
  
  
  # ==========================================================
  # 11. Return
  # ==========================================================
  
  invisible(
    list(
      physical_results = physical_results,
      orphan_experiments = physical_orphans,
      database_without_folder = db_only_experiments,
      deleted = deleted,
      failed = failed,
      dry_run = FALSE,
      success = length(failed) == 0
    )
  )
}



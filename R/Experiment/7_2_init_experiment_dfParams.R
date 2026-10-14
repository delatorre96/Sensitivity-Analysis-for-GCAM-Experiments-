
init_experiment <- function(gcam_path = 'C:/GCAM/Nacho/gcam_europe', alreadyPrepeared = T, queries_of_interest = 'outputs by tech', regions_of_interest = regions_eur,
                            xml_files = xml_files, n_iterations = 100, project = 'Hindcasting', experiment_name = 'Prueba', description = NULL,
                            uncertainty_introduction_function = 'introduce_aditive_uncertainty', df_params_path, paramCol,
                            perturbation_strategy = 'aditive', distribution = 'uniform', distribution_parameters = list('minVal' = -2, 'maxVal' = 2),
                            interested_query_columns = NULL, experiment_id_to_add = NULL, suffix){

  #----- Monitorizacion de tiempo, RAM y CPU -----

  monitor_dir <- file.path(getwd(), "monitoring")
  dir.create(monitor_dir, showWarnings = FALSE, recursive = TRUE)

  worker_id <- gsub("[^A-Za-z0-9_-]", "", suffix)

  metrics_file <- file.path(
    monitor_dir,
    paste0("steps_", worker_id, ".csv")
  )

  iterations_file <- file.path(
    monitor_dir,
    paste0("iterations_", worker_id, ".csv")
  )

  #----- Obtener frecuencia real del contador de CPU -----

  ticks_per_second <- tryCatch(
    as.numeric(system2("getconf", "CLK_TCK", stdout = TRUE))[1],
    error = function(e) NA_real_
  )

  if (is.na(ticks_per_second) || ticks_per_second <= 0) {
    ticks_per_second <- 100
  }

  #----- Leer metricas del proceso R -----

  get_process_metrics <- function() {

    result <- list(
      rss_mb = NA_real_,
      cpu_seconds = NA_real_
    )

    tryCatch({

      status <- readLines("/proc/self/status", warn = FALSE)
      rss_line <- grep("^VmRSS:", status, value = TRUE)

      if (length(rss_line) > 0) {
        rss_kb <- as.numeric(
          sub("^VmRSS:\\s*([0-9]+).*", "\\1", rss_line[1])
        )
        result$rss_mb <- rss_kb / 1024
      }

      stat_line <- readLines("/proc/self/stat", warn = FALSE)

      if (length(stat_line) > 0) {

        # El nombre del proceso puede contener espacios y parentesis.
        close_paren <- max(gregexpr("\\)", stat_line)[[1]])

        fields <- strsplit(
          trimws(substring(stat_line, close_paren + 1)),
          "\\s+"
        )[[1]]

        # Despues de PID y comm, utime y stime son los campos 12 y 13.
        if (length(fields) >= 13) {
          cpu_ticks <- as.numeric(fields[12]) +
            as.numeric(fields[13])

          result$cpu_seconds <- cpu_ticks / ticks_per_second
        }
      }

    }, error = function(e) {
      # Un fallo de monitorizacion no debe interrumpir GCAM.
      invisible(NULL)
    })

    result
  }
  #----- Escribir eventos inmediatamente en CSV -----

  append_csv <- function(data, path) {

    write.table(
      data,
      file = path,
      sep = ",",
      row.names = FALSE,
      col.names = !file.exists(path),
      append = file.exists(path),
      quote = TRUE,
      na = ""
    )
  }

  #----- Marcar el inicio de cada etapa -----

  start_step <- function(iteration, step) {

    metrics <- get_process_metrics()

    state <- list(
      iteration = iteration,
      step = step,
      start_time = Sys.time(),
      start_metrics = metrics
    )

    append_csv(
      data.frame(
        timestamp = format(
          state$start_time,
          "%Y-%m-%d %H:%M:%OS3",
          tz = "UTC"
        ),
        worker = worker_id,
        iteration = iteration,
        step = step,
        event = "START",
        elapsed_seconds = 0,
        r_rss_mb = metrics$rss_mb,
        r_cpu_seconds = metrics$cpu_seconds,
        r_cpu_percent = NA_real_
      ),
      metrics_file
    )

    state
  }

  #----- Marcar el final de cada etapa -----

  end_step <- function(state) {

    end_time <- Sys.time()
    metrics <- get_process_metrics()

    elapsed <- as.numeric(
      difftime(end_time, state$start_time, units = "secs")
    )

    cpu_delta <- metrics$cpu_seconds -
      state$start_metrics$cpu_seconds

    append_csv(
      data.frame(
        timestamp = format(
          end_time,
          "%Y-%m-%d %H:%M:%OS3",
          tz = "UTC"
        ),
        worker = worker_id,
        iteration = state$iteration,
        step = state$step,
        event = "END",
        elapsed_seconds = elapsed,
        r_rss_mb = metrics$rss_mb,
        r_cpu_seconds = metrics$cpu_seconds,
        r_cpu_percent = if (elapsed > 0) {
          100 * cpu_delta / elapsed
        } else {
          NA_real_
        }
      ),
      metrics_file
    )

    invisible(NULL)
  }

  source(here::here('R','Experiment','0_mainFunctions.R'))
  check_packages()

  source(here::here('R','Experiment','1_create_dataBase.R'))
  source(here::here('R','Experiment','2_PrepareGCAM.R'))
  source(here::here('R','Experiment','3_createDF_paramsXML.R'))
  source(here::here('R','Experiment','4_introduceUncertainty.R'))
  source(here::here('R','Experiment','5_createNewXml.R'))
  source(here::here('R','Experiment','6_appendResults.R'))
  source(here::here('R','Storage','manageExperiments.R'))

  experiment_id = create_or_add_experiment_id(experiment_id_to_add)

  thisScript_path <<- getwd()
  print(thisScript_path)

  set_gcam_paths(gcam_path = gcam_path, suffix = suffix)

  if (!file.exists("gcam_sensitivity.sqlite")) {
    message('No sqlite DDBB. Creating...')
    create_database("gcam_sensitivity.sqlite")
  }


  con <- DBI::dbConnect(
    RSQLite::SQLite(),
    "gcam_sensitivity.sqlite"
  )
  message('sqlite DDBB in memory...')

  if (alreadyPrepeared == F){
    GCAM_preparation(gcam_path = gcam_path,
                     queries_of_interest = queries_of_interest,
                     regions_per_query = regions_eur)
  }

  df_params <- read.csv(df_params_path) %>%
    mutate(
      destination_file = sub("_cal\\.xml$", paste0(suffix, ".xml"), destination_file)
    ) #%>% filter (xml_file != 'building_det_EUR.xml')

  if (is.null(experiment_id_to_add)){
    write_experiment_info(con = con,
                          experiment_id = experiment_id,
                          inputs_xml = xml_files,
                          repo = gcam_path,
                          regions = regions_of_interest,
                          experiment_name = experiment_name,
                          outputs_queries = queries_of_interest,
                          n_iterations = n_iterations,
                          description = description,
                          project = project,
                          perturbation_strategy = perturbation_strategy,
                          distribution = distribution,
                          distribution_parameters = distribution_parameters)
    create_experiment_folders(experiment_id = experiment_id)
  }


  create_new_config(df_params, exe_dir, config_file, suffix)
  message('new config created in ',config_file)
  create_new_run_gcam(suffix)
  message('new run_gcam script created in ',run_gcam_file_cal)

  cache <- build_xml_cache(df = df_params, dir_xml)
  xml_lines <- cache$lines
  df_params <- cache$df
  for (i in 1:n_iterations){
    message(paste0('************ITERATION ',i,'************' ))
    t1 <- Sys.time()
    run_id <- paste0(
      "RUN_",
      substr(UUIDgenerate(), 1, 8)
    )
    t_iteration <- Sys.time()

    step <- start_step(i, "introduce_uncertainty")
    message('Introducing parametric uncertainty...')
    res <- get(uncertainty_introduction_function)(n_iterations = n_iterations,
                                                  distribution_parameters = distribution_parameters,
                                                  df_params = df_params,
                                                  paramCol = paramCol)
    end_step(step)

    step <- start_step(i, "create_xml")

    message('Wrtiting new xml files...')

    createNewXml_fast(res$df_params_copy, xml_lines, dir_xml)

    end_step(step)

    #----- Ejecutar GCAM -----

    message("Running GCAM...")

    step <- start_step(i, "run_gcam")

    run_gcam(run_gcam_file_cal)

    end_step(step)

    #----- Comprobar errores de GCAM -----

    step <- start_step(i, "check_gcam_errors")

    executionErrors <- any(
      grepl("error", readLines(log_gcam, warn = FALSE),
            ignore.case = TRUE)
    )

    end_step(step)

    #----- Preparar identificador de ejecucion -----

    step <- start_step(i, "prepare_run_results")

    df_params_copy <- res$df_params_copy
    df_params_copy$run_id <- run_id

    end_step(step)

    #----- Guardar parametros de entrada -----

    message("Saving input parameters...")

    step <- start_step(i, "save_inputs_parquet")

    df_info_inputs <- save_inputs_parquet(
      df_params_copy = df_params_copy,
      experiment_id = experiment_id,
      run_id = run_id
    )

    end_step(step)

    #----- Extraer y guardar resultados -----

    message("Saving output results...")

    step <- start_step(i, "save_run_outputs")

    df_info_outputs <- save_run_outputs(
      experiment_id = experiment_id,
      run_id = run_id,
      queries_of_interest = queries_of_interest,
      interested_query_columns = interested_query_columns
    )

    end_step(step)

    #----- Registrar metadatos de datasets -----

    step <- start_step(i, "write_datasets_info")

    datasets <- rbind(
      df_info_inputs,
      df_info_outputs
    )

    write_datasets_info(
      con = con,
      datasets = datasets
    )

    end_step(step)

    #----- Eliminar CSV intermedios -----

    step <- start_step(i, "delete_iteration_csvs")

    delete_iteration_csvs()

    end_step(step)

    #----- Registrar ejecucion -----

    t2 <- Sys.time()

    step <- start_step(i, "write_run_info")

    write_run_info(
      con = con,
      run_id = run_id,
      experiment_id = experiment_id,
      execution_time = as.numeric(t2 - t1, units = "mins"),
      execution_errors = executionErrors
    )

    end_step(step)

    #----- Actualizar contador de iteraciones -----

    step <- start_step(i, "update_number_iterations")

    update_number_iterations(
      con = con,
      experiment_id = experiment_id
    )

    end_step(step)

    #----- Registrar finalizacion de iteracion -----

    iteration_elapsed <- as.numeric(
      difftime(Sys.time(), t1, units = "secs")
    )

    append_csv(
      data.frame(
        timestamp = format(
          Sys.time(),
          "%Y-%m-%d %H:%M:%OS3",
          tz = "UTC"
        ),
        worker = worker_id,
        iteration = i,
        run_id = run_id,
        elapsed_seconds = iteration_elapsed,
        execution_errors = executionErrors,
        status = "COMPLETED"
      ),
      iterations_file
    )

    message(
      sprintf(
        "Iteration %d completed in %.1f minutes",
        i,
        iteration_elapsed / 60
      )
    )



  }

}


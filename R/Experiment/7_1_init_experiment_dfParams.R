
init_experiment <- function(gcam_path = 'C:/GCAM/Nacho/gcam_europe', alreadyPrepeared = T, queries_of_interest = 'outputs by tech', regions_of_interest = regions_eur,
                            xml_files = xml_files, n_iterations = 100, project = 'Hindcasting', experiment_name = 'Prueba', description = NULL,
                            uncertainty_introduction_function = 'introduce_aditive_uncertainty', df_params_path, paramCol,
                            perturbation_strategy = 'aditive', distribution = 'uniform', distribution_parameters = list('minVal' = -2, 'maxVal' = 2),
                            interested_query_columns = NULL, experiment_id_to_add = NULL, suffix){


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
    ) %>% filter(priority %in% c(1,2,3)) %>% select(  "xml_file",
                                             "destination_file",
                                             "type_of_param",
                                             "tag",
                                             "param",
                                             "occ",
                                             # Construcción de etiquetas XML
                                             "fillout",
                                             # Agrupación de satiation_level
                                             "region",
                                             'supplysector',
                                             'subsector',
                                             'gcam_consumer',
                                             "input_type",
                                             "input_name",
                                             'group', 'demand_sector') %>%
    mutate(param_default = param)

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

    message('Introducing parametric uncertainty...')
    res <- get(uncertainty_introduction_function)(n_iterations = n_iterations,
                                                            distribution_parameters = distribution_parameters,
                                                            df_params = df_params,
                                                            paramCol = paramCol)
    delta <- res$delta
    message('Wrtiting new xml files...')

    createNewXml_fast(res$df_params_copy, xml_lines, dir_xml)

    # Borrar los CSV de este worker antes de ejecutar GCAM: si GCAM no llega a
    # escribirlos, no se puede guardar por error el resultado de un run anterior
    delete_iteration_csvs(suffix = suffix)

    message("Running GCAM...")

    gcam_status <- run_gcam(run_gcam_file_cal)

    # Si GCAM falla o no escribe los CSV de las queries, no se guarda nada de
    # este run (ni inputs, ni outputs, ni registro en la base de datos)
    expected_csvs <- file.path(here::here("data"),
                               paste0(gsub("\\s+", "_", queries_of_interest), suffix, "_0.csv"))
    missing_csvs <- expected_csvs[!file.exists(expected_csvs)]
    if (gcam_status != 0 || length(missing_csvs) > 0) {
      message("RUN DESCARTADO ", run_id, ": GCAM salió con código ", gcam_status,
              if (length(missing_csvs) > 0)
                paste0(" y faltan los CSV: ", paste(basename(missing_csvs), collapse = ", ")),
              ". No se guarda nada de este run.")
      next
    }

    executionErrors <- file.exists(log_gcam) &&
      any(grepl("error", readLines(log_gcam), ignore.case = TRUE))

    message('Saving results....')
    df_params_copy <- res$df_params_copy
    df_params_copy$run_id <- run_id

    df_info_inputs <- save_inputs_parquet(df_params_copy = df_params_copy,
                        experiment_id = experiment_id,
                        run_id = run_id)
    df_info_outputs <- save_run_outputs(experiment_id = experiment_id,
                                        run_id = run_id,
                                        queries_of_interest = queries_of_interest,
                                        interested_query_columns = interested_query_columns,
                                        suffix = suffix)
    datasets = rbind(df_info_inputs,
                     df_info_outputs)

    write_datasets_info(con = con,
                        datasets = datasets)


    delete_iteration_csvs(suffix = suffix)





    t2 <- Sys.time()

    write_run_info(con = con,
                   run_id = run_id,
                   experiment_id = experiment_id,
                   execution_time =  as.numeric(t2 - t1, units = "mins"),
                   execution_errors = executionErrors,
                   delta = delta
                   )


      update_number_iterations(con = con,
                               experiment_id = experiment_id)


  }

}


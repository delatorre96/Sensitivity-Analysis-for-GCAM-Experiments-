
init_experiment <- function(gcam_path = 'C:/GCAM/Nacho/gcam_europe', alreadyPrepeared = T, queries_of_interest = 'outputs by tech', regions_of_interest = regions_eur,
                            xml_files = xml_files, n_iterations = 100, project = 'Hindcasting', experiment_name = 'Prueba', description = NULL,
                            uncertainty_introduction_function = 'introduce_aditive_uncertainty', df_params_path, paramCol,
                            perturbation_strategy = 'aditive', distribution = 'uniform', distribution_parameters = list('minVal' = -2, 'maxVal' = 2),
                            interested_query_columns = NULL, experiment_id_to_add = NULL, suffix,
                            optimizer = 'rl',            # 'rl': deltas propuestos por el agente; 'random': uncertainty_introduction_function
                            rl_config = list(),          # ver rl_default_config() en 8_reinforcementLearning.R
                            reference_errors_path = '../Hindcasting/2. Extraction/Data/all_errors_output_by_tech.csv'){

  optimizer <- match.arg(optimizer, c('rl', 'random'))

  source(here::here('R','Experiment','0_mainFunctions.R'))
  check_packages()

  source(here::here('R','Experiment','1_create_dataBase.R'))
  source(here::here('R','Experiment','2_PrepareGCAM.R'))
  source(here::here('R','Experiment','3_createDF_paramsXML.R'))
  source(here::here('R','Experiment','4_introduceUncertainty.R'))
  source(here::here('R','Experiment','5_createNewXml.R'))
  source(here::here('R','Experiment','6_appendResults.R'))
  source(here::here('R','Experiment','8_reinforcementLearning.R'))
  source(here::here('R','Storage','manageExperiments.R'))
  source(here::here('R','Storage','explore_dataBase.R'))   # read_run_output()


  ############# Reinforcement: referencia #############
  # Errores del modelo base frente a lo observado (2021). El MAE de referencia
  # de cada run se calcula sobre las mismas filas que el MAE del run.
  track_mae <- file.exists(reference_errors_path)
  if (!track_mae && optimizer == 'rl') {
    stop('optimizer = "rl" necesita el fichero de referencia: ', reference_errors_path)
  }
  if (track_mae) {
    ref_values <- rl_load_reference(reference_errors_path, regions_of_interest)
    MAE_ref_global <- mean(ref_values$abs_error)
    message('MAE de referencia (todas las filas): ', signif(MAE_ref_global, 5))
  }
  ############# Reinforcement: referencia #############


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
  on.exit(DBI::dbDisconnect(con), add = TRUE)
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


  ############# Reinforcement: agente #############
  # Un agente por experimento y worker (suffix). Si el experimento ya existe
  # (experiment_id_to_add) y hay estado guardado, el agente se reanuda.
  if (track_mae) {
    rl_state_file <- rl_state_path(experiment_id, suffix)
    if (optimizer == 'random') {
      # en modo random el agente solo registra MAE/reward, no aprende
      rl_config <- utils::modifyList(rl_config, list(mode = 'observe'))
    }
    agent <- rl_init_agent(distribution_parameters = distribution_parameters,
                           rl_config = rl_config,
                           state_path = rl_state_file)
  }
  ############# Reinforcement: agente #############


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
    if (optimizer == 'rl') {
      # el agente propone los deltas (exploración/explotación según su política)
      proposal <- rl_propose(agent)
      res <- apply_deltas_to_params(df_params = df_params,
                                    deltas = proposal$deltas,
                                    paramCol = paramCol)
    } else {
      res <- get(uncertainty_introduction_function)(n_iterations = n_iterations,
                                                    distribution_parameters = distribution_parameters,
                                                    df_params = df_params,
                                                    paramCol = paramCol)
      random_delta <- if (!is.null(names(res$delta)) && all(rl_param_types %in% names(res$delta))) {
        res$delta[rl_param_types]
      } else {
        setNames(rep(NA_real_, length(rl_param_types)), rl_param_types)
      }
      proposal <- list(u = NULL, deltas = random_delta, mode = 'random')
    }
    delta <- res$delta
    message('Deltas: ', paste(names(delta), delta, sep = ' = ', collapse = ', '))
    message('Wrtiting new xml files...')

    createNewXml_fast(res$df_params_copy, xml_lines, dir_xml)

    message("Running GCAM...")

    run_gcam(run_gcam_file_cal)
    executionErrors <- any(grepl("error", readLines(log_gcam), ignore.case = TRUE))

    message('Saving results....')
    df_params_copy <- res$df_params_copy
    df_params_copy$run_id <- run_id

    df_info_inputs <- save_inputs_parquet(df_params_copy = df_params_copy,
                        experiment_id = experiment_id,
                        run_id = run_id)
    df_info_outputs <- save_run_outputs(experiment_id = experiment_id,
                                        run_id = run_id,
                                        queries_of_interest = queries_of_interest,
                                        interested_query_columns = interested_query_columns)
    datasets = rbind(df_info_inputs,
                     df_info_outputs)

    write_datasets_info(con = con,
                        datasets = datasets)


    delete_iteration_csvs()


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


    ########### Reinforcement: evaluación, recompensa y aprendizaje ##########
    if (track_mae) {
      # mismo criterio de fallo que en la tabla Runs (errores en el log de GCAM)
      failed <- isTRUE(executionErrors)

      evaluation <- if (failed) {
        list(MAE_run = NA_real_, MAE_ref = NA_real_, n_obs = 0L)
      } else {
        rl_evaluate_run(con = con,
                        run_id = run_id,
                        query_name = queries_of_interest[1],
                        ref_values = ref_values)
      }

      MAE_run <- evaluation$MAE_run
      MAE_ref <- evaluation$MAE_ref

      # refuerzo positivo si MAE_run < MAE_ref, negativo si MAE_run > MAE_ref
      reward <- rl_reward(MAE_run = MAE_run, MAE_ref = MAE_ref,
                          failed = failed || evaluation$n_obs == 0,
                          config = agent$config)

      agent <- rl_update(agent = agent,
                         proposal = proposal,
                         reward = reward,
                         evaluation = evaluation,
                         run_id = run_id)

      rl_save_agent(agent, rl_state_file)
      rl_write_history(con = con, experiment_id = experiment_id,
                       suffix = suffix, agent = agent)
    }
    ########### Reinforcement ##########

  }

  if (track_mae) {
    rl_summary(agent)
    return(invisible(agent))
  }

}

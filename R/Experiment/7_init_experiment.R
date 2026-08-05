
init_experiment <- function(gcam_path = 'C:/GCAM/Nacho/gcam_europe', alreadyPrepeared = T, queries_of_interest = 'outputs by tech', regions_of_interest = regions_eur, 
                            xml_files = xml_files, n_iterations = 100, project = 'Hindcasting', experiment_name = 'Prueba', description = NULL, 
                            perturbation_strategy = 'aditive', distribution = 'uniform', distribution_parameters = list('minVal' = -2, 'maxVal' = 2),
                            interested_query_columns = NULL, experiment_id_to_add = NULL){

  
  source('0_mainFunctions.R')
  check_packages()
  
  source('1_create_dataBase.R')
  source('2_PrepareGCAM.R')
  source('3_createDF_paramsXML.R')
  source('4_introduceUncertainty.R')
  source('5_createNewXml.R')
  source('6_appendResults.R')
  
  experiment_id = create_or_add_experiment_id(experiment_id_to_add)
  
  thisScript_path <- getwd()

  set_gcam_paths(gcam_path)
  
  if (!file.exists("gcam_sensitivity.sqlite")) {
    create_database("gcam_sensitivity.sqlite")
  }
  
  con <- DBI::dbConnect(
    RSQLite::SQLite(),
    "gcam_sensitivity.sqlite"
  )
  
  
  if (alreadyPrepeared == F){
    GCAM_preparation(gcam_path = gcam_path, 
                     queries_of_interest = queries_of_interest, 
                     regions_per_query = regions_eur)
  }
  
  
  
  df_params <- createDF_params(xml_files, regions_eur)
  
  create_new_config(df_params, exe_dir, config_file)
  create_new_run_gcam()
  
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
  
  for (i in 1:n_iterations){
    t1 <- Sys.time()
    run_id <- paste0(
      "RUN_",
      substr(UUIDgenerate(), 1, 8)
    )
    
    min_val = distribution_parameters$minVal
    max_val = distribution_parameters$maxVal
    uncertainVars <- introduce_aditive_uncertainty(min_val = min_val, 
                                                    max_val = max_val, 
                                                    df_params = df_params)
    delta <- uncertainVars$delta
    df_params_copy <- uncertainVars$df_params_copy
    
    
    createNewXml(df_params_copy)
    
    
    
    run_gcam(run_gcam_file_cal)
    executionErrors <- any(grepl("error", readLines(log_gcam), ignore.case = TRUE))
    
    message('Saving results....')
    
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
    
    
    
  }
  
}


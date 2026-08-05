check_packages <- function() {
  
  packages <- c(
    "DBI",
    "RSQLite",
    "XML",
    "xml2",
    "uuid",
    "dplyr",
    "arrow",
    "jsonlite",
    "purrr",
    "tibble",
    "stringr"
  )
  
  missing <- packages[!packages %in% installed.packages()[, "Package"]]
  
  if (length(missing) > 0) {
    
    message("Installing missing packages...")
    
    install.packages(
      missing,
      repos = "https://cloud.r-project.org"
    )
    
  }
  
  invisible(
    lapply(packages, library, character.only = TRUE)
  )
  
}

set_gcam_paths <- function(gcam_path) {
  #Exmple:
  #dir_gcamdata <- "C:/Users/ignacio.delatorre/Documents/Understanding GCAM/gcam-core/input/gcamdata"
  dir_gcam <<- gcam_path
  config_file <<-  paste0(gcam_path,'/exe/configuration.xml')
  exe_dir <<- paste0(gcam_path,'/exe')
  run_gcam_file <<- paste0(gcam_path,'/exe/run-gcam.bat')
  run_gcam_file_cal <<- paste0(gcam_path,'/exe/run-gcam_cal.bat')
  dir_gcamdata <<- paste0(gcam_path,'/input/gcamdata')
  dir_xml <<- paste0(gcam_path,'/input/gcamdata/xml')
  log_gcam <<- paste0(gcam_path,'/exe/logs/main_log.txt')
  
  print(dir_gcam)
  print(config_file)
  print(run_gcam_file)
  print(run_gcam_file_cal)
  print(dir_gcamdata)
  print(dir_xml)
}


create_new_config <- function(df_logits, exe_dir, config_file){
  config <- read_xml(config_file)
  
  archivos_modificar <- unique(df_logits$xml_file)
  
  # Todos los nodos <Value> de ScenarioComponents
  nodos <- xml_find_all(config, ".//ScenarioComponents/Value")
  
  for (nodo in nodos) {
    
    ruta <- xml_text(nodo)
    archivo <- basename(ruta)
    
    if (archivo %in% archivos_modificar) {
      
      ruta_nueva <- sub("\\.xml$", "_cal.xml", ruta)
      
      xml_text(nodo) <- ruta_nueva
    }
  }
  
  # Guardar conotro nombre
  write_xml(config, paste0(exe_dir,"/configuration_cal.xml"))
}


run_gcam <- function(bat_path) {
  message('Running GCAM..')
  bat_dir <- dirname(bat_path)
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(bat_dir)
  status <- system2("cmd.exe", args = c("/c", basename(bat_path)), stdout = "", stderr = "")
  cat(sprintf("\nGCAM terminó con código de salida %d\n", status))
  return(status)
}


create_new_run_gcam <- function(){
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  new_run_gcam_file <- "C:/GCAM/Nacho/gcam_europe/exe/run-gcam_cal.bat"
  
  bat_lines <- readLines(run_gcam_file)
  
  bat_lines <- gsub(
    "gcam\\.exe -C configuration\\.xml",
    "gcam.exe -C configuration_cal.xml",
    bat_lines
  )
  
  bat_lines <- gsub(
    "^pause$",
    "REM pause",
    bat_lines
  )
  
  writeLines(bat_lines, new_run_gcam_file)
  
}


create_or_add_experiment_id <- function(experiment_id_to_add){
  if (is.null(experiment_id_to_add)){
    experiment_id <- paste0(
      "EXP_",
      substr(UUIDgenerate(), 1, 8))
    message(paste0('Starting experiment: ',experiment_id))
  }else{
    #check if experiment_id_to_add exists in the db
    if (exists('gcam_sensitivity.sqlite')){
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



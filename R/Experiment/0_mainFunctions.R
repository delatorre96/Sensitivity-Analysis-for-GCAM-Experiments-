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

set_gcam_paths <- function(gcam_path, suffix) {
  #Exmple:
  #dir_gcamdata <- "C:/Users/ignacio.delatorre/Documents/Understanding GCAM/gcam-core/input/gcamdata"
  suffix <<- suffix
  dir_gcam <<- gcam_path
  config_file <<-  paste0(gcam_path,'/exe/configuration.xml')
  exe_dir <<- paste0(gcam_path,'/exe')
  run_gcam_file <<- paste0(gcam_path,'/exe/run-gcam.sh')
  run_gcam_file_cal <<- paste0(gcam_path,'/exe/run-gcam',suffix,'.sh')
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


create_new_config <- function(df_params, exe_dir, config_file, suffix){
  config <- read_xml(config_file)

  archivos_modificar <- unique(df_params$xml_file)

  # Todos los nodos <Value> de ScenarioComponents
  nodos <- xml_find_all(config, ".//ScenarioComponents/Value")

  for (nodo in nodos) {

    ruta <- xml_text(nodo)
    archivo <- basename(ruta)

    if (archivo %in% archivos_modificar) {

      ruta_nueva <- sub("\\.xml$", paste0(suffix,".xml"), ruta)

      xml_text(nodo) <- ruta_nueva
    }
  }

  # Guardar conotro nombre
  write_xml(config, paste0(exe_dir,"/configuration",suffix,".xml"))
}


run_gcam <- function(run_file) {



  run_dir <- dirname(run_file)
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)

  setwd(run_dir)

  if (.Platform$OS.type == "windows") {

    status <- system2(
      "cmd.exe",
      args = c("/c", basename(run_file)),
      stdout = "",
      stderr = ""
    )

  } else {

    status <- system2(
      "bash",
      args = basename(run_file),
      stdout = "",
      stderr = ""
    )

  }

  cat(sprintf("\nGCAM terminó con código de salida %d\n", status))

  return(status)
}


create_new_run_gcam <- function(
    suffix,
    exe_dir = "../gcam_europe/exe") {

  run_gcam_file <- file.path(exe_dir, "run-gcam.sh")

  new_run_gcam_file <- file.path(
    exe_dir,
    paste0("run-gcam", suffix, ".sh")
  )

  sh_lines <- readLines(run_gcam_file)

  sh_lines <- gsub(
    "gcam\\.exe -C configuration\\.xml",
    paste0("./gcam.exe -C configuration", suffix, ".xml"),
    sh_lines
  )

  writeLines(sh_lines, new_run_gcam_file)

  Sys.chmod(new_run_gcam_file, mode = "0755")

  return(new_run_gcam_file)
}

#
# create_new_run_gcam <- function(suffix){
#   old_wd <- getwd()
#   on.exit(setwd(old_wd), add = TRUE)
#   new_run_gcam_file <- paste0("C:/GCAM/Nacho/gcam_europe/exe/run-gcam",suffix,".bat")
#
#   bat_lines <- readLines(run_gcam_file)
#
#   bat_lines <- gsub(
#     "gcam\\.exe -C configuration\\.xml",
#     paste0("gcam.exe -C configuration",suffix,".xml"),
#     bat_lines
#   )
#
#   bat_lines <- gsub(
#     "^pause$",
#     "REM pause",
#     bat_lines
#   )
#
#   writeLines(bat_lines, new_run_gcam_file)
#
# }
#




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
  if (is.null(suffix) || is.na(suffix) || !nzchar(suffix)) {
    stop("El suffix no puede estar vacío: cada worker necesita su propio directorio de GCAM.")
  }
  suffix <<- suffix
  dir_gcam <<- gcam_path
  config_file <<-  paste0(gcam_path,'/exe/configuration.xml')
  exe_dir <<- paste0(gcam_path,'/exe')

  # Cada worker ejecuta GCAM desde su propio directorio, hermano de exe/
  # (gcam_path/exe<suffix>): ahí tiene su configuration<suffix>.xml, su
  # XMLDBDriver.properties, su batch de queries (con su propio CSV de salida)
  # y sus logs. exe/ queda como plantilla y ningún worker la modifica.
  # Al estar al mismo nivel que exe/, las rutas "../input/..." siguen valiendo.
  worker_dir <<- paste0(gcam_path,'/exe',suffix)

  run_ext <- if (.Platform$OS.type == "windows") ".bat" else ".sh"
  run_gcam_file <<- paste0(gcam_path,'/exe/run-gcam',run_ext)              # plantilla
  run_gcam_file_cal <<- paste0(worker_dir,'/run-gcam',suffix,run_ext)      # del worker
  dir_gcamdata <<- paste0(gcam_path,'/input/gcamdata')
  dir_xml <<- paste0(gcam_path,'/input/gcamdata/xml')
  log_gcam <<- paste0(worker_dir,'/logs/main_log.txt')

  print(dir_gcam)
  print(config_file)
  print(run_gcam_file)
  print(run_gcam_file_cal)
  print(worker_dir)
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

  # GCAM se ejecuta desde worker_dir: las rutas "../..." valen igual, pero las
  # relativas a exe/ sin "../" (p. ej. batch_ag.xml) hay que reapuntarlas a
  # ../exe/. Si apuntan a un subdirectorio de salida de exe/ (p. ej. restart/),
  # se crea en worker_dir para que cada worker escriba en el suyo.
  for (nodo in xml_find_all(config, ".//Value")) {
    ruta <- xml_text(nodo)
    if (!nzchar(ruta) || grepl("^(\\.\\./|/|[A-Za-z]:)", ruta)) next
    if (file.exists(file.path(exe_dir, ruta)) && !dir.exists(file.path(exe_dir, ruta))) {
      xml_text(nodo) <- paste0("../exe/", ruta)
    } else if (dirname(ruta) != "." && dir.exists(file.path(exe_dir, dirname(ruta)))) {
      dir.create(file.path(worker_dir, dirname(ruta)), recursive = TRUE, showWarnings = FALSE)
    }
  }

  # Guardar en el directorio del worker
  dir.create(worker_dir, recursive = TRUE, showWarnings = FALSE)
  write_xml(config, file.path(worker_dir, paste0("configuration", suffix, ".xml")))
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


# Crea el script de ejecución del worker (run-gcam<suffix>.sh / .bat) en
# worker_dir a partir de la plantilla exe/run-gcam.sh (.bat en Windows).
# El script se ejecuta desde worker_dir y lanza el gcam.exe de exe/:
#   ../exe/gcam.exe -C configuration<suffix>.xml -L ../exe/log_conf.xml
# y busca XMLDBDriver.jar en ../exe/. Así GCAM lee el XMLDBDriver.properties
# del worker y escribe sus logs en worker_dir/logs.
create_new_run_gcam <- function(
    suffix,
    exe_dir = get("exe_dir", envir = globalenv()),
    out_dir = get("worker_dir", envir = globalenv())) {

  windows <- .Platform$OS.type == "windows"
  ext     <- if (windows) ".bat" else ".sh"
  rel_exe <- if (windows) "..\\exe\\" else "../exe/"

  template <- file.path(exe_dir, paste0("run-gcam", ext))
  if (!file.exists(template)) stop("No existe la plantilla ", template)
  new_run_gcam_file <- file.path(out_dir, paste0("run-gcam", suffix, ext))

  lines <- readLines(template, warn = FALSE)

  # Llamada a GCAM (exactamente una): si no se sustituye, el worker correría
  # configuration.xml sin perturbaciones, así que mejor parar.
  call_pat <- "(\\.[/\\\\])?gcam\\.exe -C configuration\\.xml"
  i_call <- grep(call_pat, lines)
  if (length(i_call) != 1) {
    stop("La plantilla ", template, " debe contener exactamente una llamada ",
         "'gcam.exe -C configuration.xml' (tiene ", length(i_call), ").")
  }
  m <- regexpr(call_pat, lines[i_call])
  regmatches(lines[i_call], m) <- paste0(rel_exe, "gcam.exe -C configuration", suffix,
                                         ".xml -L ", rel_exe, "log_conf.xml")

  # CLASSPATH: XMLDBDriver.jar está en exe/
  jar_pat <- "(?<=^|[=;:\"' ])XMLDBDriver\\.jar"
  i_jar <- grep(jar_pat, lines, perl = TRUE)
  for (i in i_jar) {
    m <- gregexpr(jar_pat, lines[i], perl = TRUE)
    regmatches(lines[i], m) <- list(rep(paste0(rel_exe, "XMLDBDriver.jar"), length(m[[1]])))
  }
  if (length(i_jar) == 0) {
    warning("La plantilla ", template, " no menciona XMLDBDriver.jar: revisa el CLASSPATH.")
  }

  # En Windows, que el .bat no se quede esperando al final
  if (windows) lines <- sub("^\\s*pause\\s*$", "REM pause", lines, ignore.case = TRUE)

  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, new_run_gcam_file)
  if (!windows) Sys.chmod(new_run_gcam_file, mode = "0755")

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




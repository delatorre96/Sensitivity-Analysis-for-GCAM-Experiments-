# =============================================================================
# prepare_suffix_files.R
#
# Crea (--mode=create) y/o comprueba (--mode=check) los ficheros de GCAM de un
# sufijo, reutilizando create_new_config() y create_new_run_gcam() de
# R/Experiment/0_mainFunctions.R (sin modificarlas):
#   <gcam>/exe/configuration<suffix>.xml
#   <gcam>/exe/run-gcam<suffix>.sh
#
# Uso:
#   Rscript --vanilla bash_pipeline/prepare_suffix_files.R --mode=check --suffix=_999 \
#     [--gcam-path=../gcam_europe] [--df-params=...] [--config=...] [--repo-dir=.]
#
# Necesita xml2 (lo usa create_new_config()). Salida 0 = correcto; 1 = error.
# =============================================================================

.pipeline_dir <- local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(normalizePath(f[1], mustWork = FALSE)) else file.path(getwd(), "bash_pipeline")
})
source(file.path(.pipeline_dir, "lib_pipeline.R"))

kv <- tryCatch(parse_kv_args(), error = function(e) { message(conditionMessage(e)); quit(status = 2) })
mode           <- arg_or(kv$mode, "check")
suffix         <- kv$suffix
repo_dir       <- arg_or(kv$repo_dir, getwd())
gcam_path      <- arg_or(kv$gcam_path, "../gcam_europe")
df_params_path <- arg_or(kv$df_params, "../Hindcasting/4_SensitivityAnalysis/create_dfParams/df_allParams.csv")
config_path    <- arg_or(kv$config, file.path(.pipeline_dir, "sensitivity_config.R"))

if (is.null(suffix) || !grepl("^_[A-Za-z0-9]+$", suffix)) { message("--suffix obligatorio (_XXX)"); quit(status = 2) }
if (!mode %in% c("create", "check")) { message("--mode debe ser create o check"); quit(status = 2) }

main <- function() {
  suppressPackageStartupMessages(library(xml2))
  cfg <- new.env(parent = globalenv()); sys.source(config_path, envir = cfg)

  exe_dir     <- file.path(gcam_path, "exe")
  base_config <- file.path(exe_dir, "configuration.xml")
  new_config  <- file.path(exe_dir, paste0("configuration", suffix, ".xml"))
  new_run     <- file.path(exe_dir, paste0("run-gcam", suffix, ".sh"))
  dir_xml     <- normalizePath(file.path(gcam_path, "input", "gcamdata", "xml"), mustWork = TRUE)

  df_params <- read.csv(df_params_path, stringsAsFactors = FALSE)
  if (length(cfg$exclude_xml_files))
    df_params <- df_params[!(df_params$xml_file %in% cfg$exclude_xml_files), , drop = FALSE]

  if (mode == "create") {
    for (f in c(base_config, file.path(exe_dir, "run-gcam.sh")))
      if (!file.exists(f)) stop("No existe ", f)
    fx <- new.env(parent = globalenv())
    load_functions(list(
      create_new_config   = list(file = "R/Experiment/0_mainFunctions.R"),
      create_new_run_gcam = list(file = "R/Experiment/0_mainFunctions.R")), repo_dir, fx)
    fx$create_new_config(df_params, exe_dir, base_config, suffix)
    fx$create_new_run_gcam(suffix, exe_dir = exe_dir)
    message("Creados: ", new_config, " y ", new_run)
  }

  # ---------------- Comprobaciones ----------------
  if (!file.exists(new_config)) stop("No existe ", new_config, " (usar --prepare)")
  if (!file.exists(new_run))    stop("No existe ", new_run,    " (usar --prepare)")

  values <- xml_text(xml_find_all(read_xml(new_config), ".//ScenarioComponents/Value"))
  bnames <- basename(values)
  originals <- unique(df_params$xml_file)
  expected  <- sub("\\.xml$", paste0(suffix, ".xml"), originals)

  missing <- setdiff(expected, bnames)
  if (length(missing))
    stop("configuration", suffix, ".xml no referencia: ", paste(missing, collapse = ", "),
         " (¿el XML no está en configuration.xml?)")
  still_orig <- intersect(originals, bnames)
  if (length(still_orig))
    stop("configuration", suffix, ".xml sigue cargando los originales: ", paste(still_orig, collapse = ", "))

  # Los XML con sufijo deben resolverse (desde exe/) al directorio donde escribe R
  dirs <- unique(normalizePath(dirname(file.path(exe_dir, values[bnames %in% expected])), mustWork = FALSE))
  if (!all(dirs == dir_xml))
    stop("configuration", suffix, ".xml apunta a directorios distintos de ", dir_xml, ": ",
         paste(dirs, collapse = ", "))

  run_lines <- readLines(new_run, warn = FALSE)
  if (!any(grepl(paste0("configuration", suffix, ".xml"), run_lines, fixed = TRUE)))
    stop("run-gcam", suffix, ".sh no contiene 'configuration", suffix, ".xml'. ",
         "create_new_run_gcam() solo sustituye 'gcam.exe -C configuration.xml'; revisar run-gcam.sh")
  if (any(grepl("\r$", run_lines)))
    stop("run-gcam", suffix, ".sh tiene finales de línea CRLF (Windows)")

  message("OK: ", new_config, " (", length(expected), " XML con sufijo) y ", new_run)
}

tryCatch(main(), error = function(e) { message("ERROR: ", conditionMessage(e)); quit(save = "no", status = 1) })
quit(save = "no", status = 0)

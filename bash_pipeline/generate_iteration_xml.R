# =============================================================================
# generate_iteration_xml.R
#
# Genera los XML de entrada de GCAM para UNA iteración. No ejecuta GCAM, no
# exporta consultas y no controla el loop (eso lo hace run_sensitivity_bash.sh).
#
# Reutiliza, sin modificarlas, las funciones del repositorio:
#   build_xml_cache()                               (3_createDF_paramsXML.R)
#   introduce_heterogeneous_uncertainty_by_type()   (4_introduceUncertainty.R)
#   createNewXml_fast(), write_xml_fast(), fmt_num() (5_createNewXml.R)
# Solo necesita R base (no xml2, dplyr ni renv).
#
# Uso (desde el directorio de trabajo):
#   Rscript --vanilla bash_pipeline/generate_iteration_xml.R \
#     --experiment-id=EXP_c9b80e40 --iteration=1 --suffix=_999 --seed=1001 \
#     --out-dir=logs_bash/.../iter_001 \
#     [--n-iterations=100] [--gcam-path=../gcam_europe] \
#     [--df-params=../Hindcasting/4_SensitivityAnalysis/create_dfParams/df_allParams.csv] \
#     [--config=bash_pipeline/sensitivity_config.R] [--repo-dir=.]
#
# Salidas en --out-dir (nunca compartidas entre iteraciones):
#   r_meta.csv               experimento, iteración, semilla, tiempos, estado, error
#   params_used.csv          parámetros muestreados (df_params_copy)
#   satiation_multipliers.csv  factores por grupo (si los hay)
#   xml_manifest.csv         XML generados: ruta, bytes, md5, filas cambiadas
#   functions_used.csv       procedencia (fichero, nº de definición, md5) de cada función
#   r_status.txt             "OK" solo si TODO ha ido bien (se escribe al final)
#
# Código de salida: 0 correcto; 1 error; 2 argumentos.
# =============================================================================

t_start <- Sys.time()

.pipeline_dir <- local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(normalizePath(f[1], mustWork = FALSE)) else file.path(getwd(), "bash_pipeline")
})
source(file.path(.pipeline_dir, "lib_pipeline.R"))

usage_error <- function(msg) {
  message("ERROR (argumentos): ", msg)
  quit(save = "no", status = 2)
}

# ----------------------------------------------------------------------------
# Argumentos
# ----------------------------------------------------------------------------
args <- tryCatch(parse_kv_args(), error = function(e) usage_error(conditionMessage(e)))

experiment_id  <- args$experiment_id
iteration_chr  <- args$iteration
suffix         <- args$suffix
seed_chr       <- args$seed
out_dir        <- args$out_dir
n_iter_chr     <- args$n_iterations
repo_dir       <- arg_or(args$repo_dir, getwd())
gcam_path      <- arg_or(args$gcam_path, "../gcam_europe")
df_params_path <- arg_or(args$df_params, "../Hindcasting/4_SensitivityAnalysis/create_dfParams/df_allParams.csv")
config_path    <- arg_or(args$config, file.path(.pipeline_dir, "sensitivity_config.R"))

if (is.null(experiment_id) || !grepl("^[A-Za-z0-9_.-]+$", experiment_id))
  usage_error("--experiment-id obligatorio (letras, números, _ . -)")
if (is.null(iteration_chr) || !grepl("^[0-9]+$", iteration_chr) || as.integer(iteration_chr) < 1)
  usage_error("--iteration obligatorio (entero >= 1)")
if (is.null(suffix) || !grepl("^_[A-Za-z0-9]+$", suffix))
  usage_error("--suffix obligatorio con formato _XXX (p. ej. _999)")
if (!is.null(seed_chr) && !grepl("^[0-9]+$", seed_chr))
  usage_error("--seed debe ser un entero no negativo")
if (!is.null(n_iter_chr) && !grepl("^[0-9]+$", n_iter_chr))
  usage_error("--n-iterations debe ser un entero")
if (is.null(out_dir)) usage_error("--out-dir obligatorio")

iteration    <- as.integer(iteration_chr)
n_iterations <- if (is.null(n_iter_chr)) NULL else as.integer(n_iter_chr)
if (is.null(seed_chr)) {
  set.seed(NULL)
  seed <- sample.int(.Machine$integer.max - 1L, 1)   # se registra para poder reproducirla
} else {
  seed <- as.numeric(seed_chr)
  if (seed > .Machine$integer.max) usage_error("--seed demasiado grande")
  seed <- as.integer(seed)
}

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
if (!dir.exists(out_dir)) usage_error(paste("No se puede crear --out-dir:", out_dir))
status_file <- file.path(out_dir, "r_status.txt")
unlink(status_file)

# ----------------------------------------------------------------------------
# Metadatos: se escriben SIEMPRE (también si falla)
# ----------------------------------------------------------------------------
meta <- list(n_params = NA_integer_, n_params_changed = NA_integer_, n_xml = NA_integer_,
             t_load_s = NA_real_, t_cache_s = NA_real_, t_sample_s = NA_real_,
             t_write_s = NA_real_, t_validate_s = NA_real_)

write_meta <- function(status, error_message = "") {
  m <- data.frame(
    experiment_id = experiment_id, iteration = iteration, suffix = suffix, seed = seed,
    n_params = meta$n_params, n_params_changed = meta$n_params_changed, n_xml = meta$n_xml,
    t_load_s = meta$t_load_s, t_cache_s = meta$t_cache_s, t_sample_s = meta$t_sample_s,
    t_write_s = meta$t_write_s, t_validate_s = meta$t_validate_s,
    t_generation_s = secs_since(t_start),
    status = status, error_message = gsub("[\r\n]+", " | ", error_message),
    r_version = R.version$version.string, host = Sys.info()[["nodename"]], pid = Sys.getpid(),
    stringsAsFactors = FALSE)
  write.csv(m, file.path(out_dir, "r_meta.csv"), row.names = FALSE)
}

# ----------------------------------------------------------------------------
# Comprobación independiente de un XML generado frente a su original:
#  - nº de líneas = original + nº de filas logit/price_elasticity (insertadas)
#  - cada valor muestreado está en su sitio (satiation: línea sustituida;
#    logit/elasticidad: línea insertada tras la original, con year=)
#  - ninguna otra línea del original ha cambiado
# ----------------------------------------------------------------------------
validate_generated_xml <- function(orig, out_path, d, year_value) {
  new <- readLines(out_path, encoding = "UTF-8", warn = FALSE)
  is_ins <- d$type_of_param %in% c("logit", "price_elasticity")
  is_sat <- d$type_of_param == "satiation_level"
  probs  <- character(0)

  if (length(new) != length(orig) + sum(is_ins))
    return(sprintf("nº de líneas %d, esperado %d", length(new), length(orig) + sum(is_ins)))

  ins_lines <- sort(d$line[is_ins])
  new_pos   <- function(L) L + findInterval(L - 0.5, ins_lines)   # posición de la línea original L
  num_of    <- function(x) suppressWarnings(as.numeric(sub("^[^>]*>([^<]*)<.*$", "\\1", x)))
  close_to  <- function(a, b) !is.na(a) & abs(a - b) <= 1e-6 * pmax(1, abs(b))

  # Posiciones de las líneas insertadas
  m_by_line <- table(d$line[is_ins])
  ins_pos <- unlist(lapply(names(m_by_line), function(L) {
    p <- new_pos(as.integer(L)); p + seq_len(m_by_line[[L]]) }))

  # Resto del fichero: igual al original salvo las líneas de satiation
  kept <- if (length(ins_pos)) new[-ins_pos] else new
  changed <- which(kept != orig)
  unexpected <- setdiff(changed, d$line[is_sat])
  if (length(unexpected))
    probs <- c(probs, sprintf("%d líneas cambiadas fuera de los parámetros (p. ej. línea %d)",
                              length(unexpected), unexpected[1]))

  # Satiation: línea sustituida con el valor muestreado
  for (k in which(is_sat)) {
    x <- new[new_pos(d$line[k])]
    if (!grepl("<satiation-level>", x, fixed = TRUE) || !close_to(num_of(x), d$param[k]))
      probs <- c(probs, sprintf("satiation línea %d: '%s' (esperado %s)", d$line[k], trimws(x), d$param[k]))
  }
  # Logit / elasticidad: línea insertada justo después de la original
  tag <- c(logit = "logit-exponent", price_elasticity = "price-elasticity")
  for (k in which(is_ins)) {
    p  <- new_pos(d$line[k])
    cand <- new[p + seq_len(m_by_line[[as.character(d$line[k])]])]
    ok <- grepl(paste0("<", tag[[d$type_of_param[k]]], "[ >]"), cand) &
          grepl(paste0('year="', year_value[k], '"'), cand, fixed = TRUE) &
          close_to(num_of(cand), d$param[k])
    if (!any(ok))
      probs <- c(probs, sprintf("%s línea %d no insertado (valor %s)", d$type_of_param[k], d$line[k], d$param[k]))
  }
  if (length(probs)) paste(head(probs, 3), collapse = " ; ") else ""
}

# ----------------------------------------------------------------------------
# Lógica principal
# ----------------------------------------------------------------------------
main <- function() {
  message(sprintf("[generate_iteration_xml] experimento=%s iteración=%d sufijo=%s semilla=%d",
                  experiment_id, iteration, suffix, seed))

  # ---- Rutas -----------------------------------------------------------------
  if (!dir.exists(repo_dir)) stop("No existe repo_dir: ", repo_dir)
  repo_dir <- normalizePath(repo_dir, mustWork = TRUE)
  if (!file.exists(df_params_path))
    stop("No se encuentra la tabla de parámetros: '", df_params_path, "' (directorio actual: ", getwd(), ")")
  if (!dir.exists(gcam_path))
    stop("No se encuentra gcam_path: '", gcam_path, "' (directorio actual: ", getwd(), ")")
  dir_xml <- normalizePath(file.path(gcam_path, "input", "gcamdata", "xml"), mustWork = FALSE)
  if (!dir.exists(dir_xml)) stop("No existe el directorio XML: ", dir_xml)
  if (!file.exists(config_path)) stop("No existe el fichero de configuración: ", config_path)

  # ---- Configuración y funciones existentes ---------------------------------
  t0 <- Sys.time()
  cfg <- new.env(parent = globalenv())
  sys.source(config_path, envir = cfg)
  if (!identical(cfg$paramCol, "param"))
    stop("paramCol debe ser 'param': write_xml_fast() escribe siempre la columna 'param'")

  fx <- new.env(parent = globalenv())
  fun_info <- load_functions(cfg$function_sources, repo_dir, fx)
  write.csv(fun_info, file.path(out_dir, "functions_used.csv"), row.names = FALSE)
  for (i in seq_len(nrow(fun_info)))
    message(sprintf("  función %-45s <- %s (definición %d de %d, md5 %s)",
                    fun_info$function_name[i], fun_info$file[i], fun_info$definition_used[i],
                    fun_info$n_definitions[i], substr(fun_info$body_md5[i], 1, 8)))
  meta$t_load_s <<- secs_since(t0)

  # ---- Tabla de parámetros ---------------------------------------------------
  df_params <- read.csv(df_params_path, stringsAsFactors = FALSE)   # igual que init_experiment()
  if (nrow(df_params) == 0) stop("La tabla de parámetros está vacía: ", df_params_path)
  miss <- setdiff(cfg$required_columns, names(df_params))
  if (length(miss)) stop("Faltan columnas en df_params: ", paste(miss, collapse = ", "),
                         ". Disponibles: ", paste(names(df_params), collapse = ", "))
  for (tp in names(cfg$required_columns_by_type)) {
    rows <- df_params$type_of_param == tp
    for (cl in cfg$required_columns_by_type[[tp]]) {
      if (any(rows) && (!cl %in% names(df_params) || anyNA(df_params[[cl]][rows]) ||
                        any(df_params[[cl]][rows] == "")))
        stop("La columna '", cl, "' falta o tiene vacíos en filas de tipo ", tp)
    }
  }
  if (anyNA(df_params$occ) || anyNA(df_params$param_default))
    stop("Hay NA en occ o param_default")

  if (length(cfg$exclude_xml_files))
    df_params <- df_params[!(df_params$xml_file %in% cfg$exclude_xml_files), , drop = FALSE]

  # Misma transformación que init_experiment(): *_cal.xml -> *<suffix>.xml
  df_params$destination_file <- sub("_cal\\.xml$", paste0(suffix, ".xml"), df_params$destination_file)

  # ---- Protección de originales y calibración / coherencia con la config ----
  map <- unique(df_params[, c("xml_file", "destination_file")])
  if (any(duplicated(map$xml_file)) || any(duplicated(map$destination_file)))
    stop("La relación xml_file -> destination_file no es 1:1")
  if (any(map$destination_file %in% map$xml_file) || any(grepl("_cal\\.xml$", map$destination_file)))
    stop("Algún destination_file coincide con un XML original o de calibración. Abortado.")
  # create_new_config() hace configuration: X.xml -> X<suffix>.xml; los XML que
  # escribe R deben tener exactamente ese nombre o GCAM no los cargaría.
  expected <- sub("\\.xml$", paste0(suffix, ".xml"), map$xml_file)
  if (any(expected != map$destination_file))
    stop("destination_file no coincide con lo que carga configuration", suffix, ".xml: ",
         paste(head(paste(map$destination_file, "!=", expected)[expected != map$destination_file], 3),
               collapse = "; "))

  missing_orig <- map$xml_file[!file.exists(file.path(dir_xml, map$xml_file))]
  if (length(missing_orig))
    stop("No existen XML originales en ", dir_xml, ": ", paste(missing_orig, collapse = ", "))

  # ---- Borrar XML generados en iteraciones anteriores ------------------------
  dest_paths <- file.path(dir_xml, map$destination_file)
  old <- dest_paths[file.exists(dest_paths)]
  if (length(old) && !all(file.remove(old)))
    stop("No se pudieron borrar XML de una iteración anterior en ", dir_xml)

  # ---- Caché: lee los ORIGINALES y comprueba que coinciden con param_default --
  t0 <- Sys.time()
  cache <- fx$build_xml_cache(df = df_params, dir_xml)
  df_params <- cache$df
  xml_lines <- cache$lines
  meta$t_cache_s <<- secs_since(t0)

  # ---- Muestreo --------------------------------------------------------------
  t0 <- Sys.time()
  set.seed(seed)
  fn <- get(cfg$uncertainty_introduction_function, envir = fx, mode = "function")
  res <- fn(n_iterations = n_iterations, i = iteration,
            distribution_parameters = cfg$distribution_parameters,
            paramCol = cfg$paramCol, df_params = df_params)
  meta$t_sample_s <<- secs_since(t0)

  d <- res$df_params_copy
  if (is.null(d) || nrow(d) != nrow(df_params)) stop("La función de incertidumbre no devolvió df_params_copy válido")
  if (any(!is.finite(d$param))) stop("Hay valores NA/no finitos en los parámetros muestreados")
  meta$n_params <<- nrow(d)
  meta$n_params_changed <<- sum(abs(d$param - d$param_default) > 1e-12)
  meta$n_xml <<- nrow(map)

  write.csv(cbind(experiment_id = experiment_id, iteration = iteration, seed = seed, d),
            file.path(out_dir, "params_used.csv"), row.names = FALSE)
  if (!is.null(res$satiation_multipliers))
    write.csv(data.frame(experiment_id = experiment_id, iteration = iteration, seed = seed,
                         group = names(res$satiation_multipliers),
                         multiplier = unname(res$satiation_multipliers)),
              file.path(out_dir, "satiation_multipliers.csv"), row.names = FALSE)

  # ---- Escritura (función existente) ----------------------------------------
  t0 <- Sys.time()
  fx$createNewXml_fast(d, xml_lines, dir_xml)
  meta$t_write_s <<- secs_since(t0)

  # ---- Validación ------------------------------------------------------------
  t0 <- Sys.time()
  not_written <- dest_paths[!file.exists(dest_paths)]
  if (length(not_written)) stop("No se generaron estos XML: ", paste(basename(not_written), collapse = ", "))
  info <- file.info(dest_paths)
  if (any(info$size == 0)) stop("Hay XML generados vacíos")

  problems <- character(0)
  n_changed_file <- integer(nrow(map))
  for (j in seq_len(nrow(map))) {
    dj <- d[d$xml_file == map$xml_file[j], , drop = FALSE]
    n_changed_file[j] <- sum(abs(dj$param - dj$param_default) > 1e-12)
    p <- validate_generated_xml(xml_lines[[map$xml_file[j]]], dest_paths[j], dj, dj$year)
    if (nzchar(p)) problems <- c(problems, paste0(map$destination_file[j], ": ", p))
  }
  if (length(problems))
    stop(length(problems), " XML generados no superan la validación. ", paste(head(problems, 3), collapse = " || "))
  meta$t_validate_s <<- secs_since(t0)

  manifest <- data.frame(
    xml_file = map$xml_file, destination_file = map$destination_file, path = dest_paths,
    bytes = info$size, md5 = unname(tools::md5sum(dest_paths)),
    md5_original = unname(tools::md5sum(file.path(dir_xml, map$xml_file))),
    n_params = as.integer(table(factor(d$xml_file, levels = map$xml_file))),
    n_params_changed = n_changed_file,
    stringsAsFactors = FALSE)
  write.csv(manifest, file.path(out_dir, "xml_manifest.csv"), row.names = FALSE)

  write_meta("OK")
  writeLines("OK", status_file)
  message(sprintf("[generate_iteration_xml] OK: %d parámetros (%d cambiados), %d XML, %.1f s",
                  meta$n_params, meta$n_params_changed, meta$n_xml, secs_since(t_start)))
}

tryCatch(main(), error = function(e) {
  msg <- conditionMessage(e)
  message("ERROR: ", msg)
  try(write_meta("FAILED", msg), silent = TRUE)
  try(writeLines("FAILED", status_file), silent = TRUE)
  quit(save = "no", status = 1)
})
quit(save = "no", status = 0)

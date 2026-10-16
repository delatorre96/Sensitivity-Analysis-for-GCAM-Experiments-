# =============================================================================
# lib_pipeline.R — utilidades comunes de los scripts R de bash_pipeline/
#
# Solo usa R base. Se carga con:
#   source(file.path(pipeline_dir(), "lib_pipeline.R"))
# =============================================================================

# Argumentos en formato --clave=valor -> lista (guiones -> guiones bajos)
parse_kv_args <- function(args = commandArgs(trailingOnly = TRUE)) {
  out <- list()
  for (a in args) {
    if (!grepl("^--[A-Za-z0-9_-]+=", a))
      stop("Argumento no reconocido (formato --clave=valor): ", a)
    key <- gsub("-", "_", sub("^--([A-Za-z0-9_-]+)=.*$", "\\1", a))
    out[[key]] <- sub("^--[A-Za-z0-9_-]+=", "", a)
  }
  out
}

arg_or <- function(x, default) if (is.null(x) || identical(x, "")) default else x

# -----------------------------------------------------------------------------
# load_functions(): carga del código del repositorio SOLO las definiciones de
# función pedidas, sin ejecutar nada más del fichero (ni library(), ni código
# suelto). Así se reutiliza la implementación existente tal cual, sin
# depender de dplyr/xml2/here, y se elige explícitamente qué definición usar
# cuando una función está definida varias veces en el mismo fichero.
#
#   specs: lista nombrada  nombre_funcion = list(file = "...", occurrence = 1L,
#                                                 must_contain = "regex")
#   occurrence: 1 = primera definición del fichero, -1 = última
# Devuelve un data.frame con la procedencia de cada función (para el log).
# -----------------------------------------------------------------------------
load_functions <- function(specs, repo_dir, env) {
  info <- list()
  parsed <- list()
  for (nm in names(specs)) {
    sp   <- specs[[nm]]
    path <- file.path(repo_dir, sp$file)
    if (!file.exists(path)) stop("No existe el fichero R a reutilizar: ", path)
    if (is.null(parsed[[path]])) parsed[[path]] <- parse(path, keep.source = FALSE)

    defs <- Filter(function(e) {
      is.call(e) && length(e) == 3 &&
        (identical(e[[1]], as.name("<-")) || identical(e[[1]], as.name("="))) &&
        is.name(e[[2]]) && identical(as.character(e[[2]]), nm) &&
        is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function"))
    }, as.list(parsed[[path]]))

    if (length(defs) == 0) stop("No se encuentra la función '", nm, "' en ", sp$file)
    occ <- if (is.null(sp$occurrence)) 1L else as.integer(sp$occurrence)
    idx <- if (occ < 0) length(defs) + occ + 1L else occ
    if (idx < 1 || idx > length(defs))
      stop("'", nm, "' tiene ", length(defs), " definiciones en ", sp$file,
           "; occurrence=", occ, " no existe")

    eval(defs[[idx]], envir = env)
    body_txt <- paste(deparse(get(nm, envir = env)), collapse = "\n")
    if (!is.null(sp$must_contain) && !grepl(sp$must_contain, body_txt))
      stop("La definición elegida de '", nm, "' (", sp$file, ", nº ", idx,
           ") no contiene '", sp$must_contain, "'. ¿Ha cambiado el código?")

    info[[nm]] <- data.frame(
      function_name = nm, file = sp$file, n_definitions = length(defs),
      definition_used = idx,
      body_md5 = md5_text(body_txt),
      stringsAsFactors = FALSE)
  }
  do.call(rbind, info)
}

# md5 de un texto (tools::md5sum solo admite ficheros)
md5_text <- function(txt) {
  f <- tempfile(); on.exit(unlink(f))
  writeLines(txt, f)
  unname(tools::md5sum(f))
}

# Directorio de un script lanzado con Rscript
script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f) == 0) return(getwd())
  dirname(normalizePath(f[1], mustWork = FALSE))
}

secs_since <- function(t0) round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2)

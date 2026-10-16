# =============================================================================
# make_batch_xml.R   (solo R base: no necesita xml2)
#
# Crea una COPIA del batch de ModelInterface (xmldb_batch.xml) cambiando
# ÚNICAMENTE el contenido de <outFile> dentro del <command> cuyo <queryFile>
# coincide. No es una sustitución global: se localiza el bloque <command>,
# dentro de él la única línea <outFile>…</outFile>, y se verifica después
# que el fichero resultante solo difiere de la plantilla en esa línea.
# La plantilla no se modifica.
#
# Uso:
#   Rscript --vanilla bash_pipeline/make_batch_xml.R \
#     --template=<xmldb_batch original> --out=<copia de la iteración> \
#     --out-file=<ruta ABSOLUTA del CSV> --query-file=batch_queries/outputs_by_tech.xml
# =============================================================================

.pipeline_dir <- local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(normalizePath(f[1], mustWork = FALSE)) else file.path(getwd(), "bash_pipeline")
})
source(file.path(.pipeline_dir, "lib_pipeline.R"))

kv <- tryCatch(parse_kv_args(), error = function(e) { message(conditionMessage(e)); quit(status = 2) })

tag_text <- function(line, tag) {
  m <- regmatches(line, regexec(paste0("<", tag, ">\\s*([^<]*?)\\s*</", tag, ">"), line, perl = TRUE))[[1]]
  if (length(m) == 2) m[2] else NA_character_
}

main <- function() {
  for (k in c("template", "out", "out_file", "query_file"))
    if (is.null(kv[[k]]) || kv[[k]] == "") stop("Falta --", gsub("_", "-", k))
  if (!file.exists(kv$template)) stop("No existe la plantilla: ", kv$template)
  if (!grepl("^/", kv$out_file)) stop("--out-file debe ser una ruta absoluta (GCAM se ejecuta desde exe/)")
  if (grepl("[<>&\"']", kv$out_file)) stop("--out-file contiene caracteres no válidos en XML")

  txt <- readLines(kv$template, warn = FALSE)
  # Copia "limpia" para buscar: los comentarios <!-- ... --> se sustituyen por
  # espacios conservando los saltos de línea (mismo nº de líneas que txt).
  full  <- paste(txt, collapse = "\n")
  clean <- full
  m <- gregexpr("(?s)<!--.*?-->", full, perl = TRUE)
  regmatches(clean, m) <- lapply(regmatches(full, m), function(x) gsub("[^\n]", " ", x))
  cl <- strsplit(clean, "\n", fixed = TRUE)[[1]]
  length(cl) <- length(txt); cl[is.na(cl)] <- ""

  s <- which(grepl("<command[ >]", cl))
  e <- which(grepl("</command>", cl, fixed = TRUE))
  if (length(s) == 0 || length(s) != length(e) || any(e <= s))
    stop("No se reconoce la estructura <command> ... </command> del batch")

  qf <- vapply(seq_along(s), function(k) {
    l <- grep("<queryFile>", cl[s[k]:e[k]], value = TRUE, fixed = TRUE)
    if (length(l) == 1) tag_text(l, "queryFile") else NA_character_
  }, character(1))
  sel <- which(qf == kv$query_file)
  if (length(sel) != 1)
    stop("Se esperaba exactamente un <command> con queryFile='", kv$query_file,
         "'; encontrados: ", length(sel), ". queryFile presentes: ", paste(qf, collapse = ", "))
  if (length(s) > 1)
    message("AVISO: el batch tiene ", length(s), " <command>; solo se modifica el de ", kv$query_file)

  block <- s[sel]:e[sel]
  ol <- block[grepl("<outFile>", cl[block], fixed = TRUE)]
  if (length(ol) != 1 || is.na(tag_text(txt[ol], "outFile")))
    stop("El <command> debe tener una única línea <outFile>…</outFile>")

  old_value <- tag_text(txt[ol], "outFile")
  new <- txt
  repl <- gsub("\\\\", "\\\\\\\\", kv$out_file)
  new[ol] <- sub("(<outFile>)[^<]*(</outFile>)", paste0("\\1", repl, "\\2"), txt[ol])

  # Verificación: solo cambia esa línea y contiene exactamente el nuevo valor
  if (length(new) != length(txt) || any(new[-ol] != txt[-ol]))
    stop("Verificación: el batch cambiaría en algo más que <outFile>")
  if (!identical(tag_text(new[ol], "outFile"), kv$out_file))
    stop("Verificación fallida del outFile escrito")

  tmp <- paste0(kv$out, ".tmp")
  writeLines(new, tmp)
  if (!identical(readLines(tmp, warn = FALSE), new)) stop("Verificación de escritura fallida")
  if (!file.rename(tmp, kv$out)) stop("No se pudo mover ", tmp, " a ", kv$out)
  message("outFile: '", old_value, "' -> '", kv$out_file, "'")
}

tryCatch(main(), error = function(e) { message("ERROR: ", conditionMessage(e)); quit(save = "no", status = 1) })
quit(save = "no", status = 0)

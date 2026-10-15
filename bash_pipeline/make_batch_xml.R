# =============================================================================
# make_batch_xml.R
#
# Crea una COPIA del batch de ModelInterface (xmldb_batch.xml) cambiando
# ÚNICAMENTE el texto de <outFile> del <command> cuyo <queryFile> coincide.
# Se manipula con xml2 (no con sustitución de texto), así que el resto de
# etiquetas no puede cambiar. El fichero de plantilla no se toca.
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

main <- function() {
  for (k in c("template", "out", "out_file", "query_file"))
    if (is.null(kv[[k]]) || kv[[k]] == "") stop("Falta --", gsub("_", "-", k))
  if (!file.exists(kv$template)) stop("No existe la plantilla: ", kv$template)
  if (!grepl("^/", kv$out_file)) stop("--out-file debe ser una ruta absoluta (GCAM se ejecuta desde exe/)")

  suppressPackageStartupMessages(library(xml2))
  doc  <- read_xml(kv$template)
  cmds <- xml_find_all(doc, ".//command")
  qf   <- vapply(cmds, function(c) xml_text(xml_find_first(c, "./queryFile")), character(1))
  sel  <- which(qf == kv$query_file)
  if (length(sel) != 1)
    stop("Se esperaba exactamente un <command> con queryFile='", kv$query_file,
         "'; encontrados: ", length(sel), ". queryFile presentes: ", paste(qf, collapse = ", "))
  if (length(cmds) > 1)
    message("AVISO: el batch tiene ", length(cmds), " <command>; solo se modifica el de ", kv$query_file)

  node <- xml_find_first(cmds[[sel]], "./outFile")
  if (inherits(node, "xml_missing")) stop("El <command> no tiene <outFile>")
  old_value <- xml_text(node)
  xml_text(node) <- kv$out_file

  tmp <- paste0(kv$out, ".tmp")
  write_xml(doc, tmp)

  # Verificación: releer y comparar con la plantilla etiqueta a etiqueta
  chk  <- read_xml(tmp)
  orig <- read_xml(kv$template)
  ccmd <- xml_find_all(chk, ".//command")
  if (length(ccmd) != length(cmds)) stop("Verificación: cambió el nº de <command>")
  got <- xml_text(xml_find_first(ccmd[[sel]], "./outFile"))
  if (!identical(got, kv$out_file)) stop("Verificación fallida del outFile escrito")
  a <- xml_find_all(orig, ".//*[not(*)]"); b <- xml_find_all(chk, ".//*[not(*)]")
  if (length(a) != length(b)) stop("Verificación: cambió el nº de etiquetas del batch")
  diff_nodes <- which(xml_text(a) != xml_text(b) | xml_name(a) != xml_name(b))
  if (length(diff_nodes) > 1 || (length(diff_nodes) == 1 && xml_name(b[[diff_nodes]]) != "outFile"))
    stop("Verificación: el batch generado difiere de la plantilla en algo más que <outFile>")

  if (!file.rename(tmp, kv$out)) stop("No se pudo mover ", tmp, " a ", kv$out)
  message("outFile: '", old_value, "' -> '", kv$out_file, "'")
}

tryCatch(main(), error = function(e) { message("ERROR: ", conditionMessage(e)); quit(save = "no", status = 1) })
quit(save = "no", status = 0)

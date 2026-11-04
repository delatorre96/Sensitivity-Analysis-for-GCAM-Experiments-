st1_get_all_queries <- function(print_queries = F){
  xml_file <- file.path(thisScript_path, "files", "allQueries.xml")

  txt <- paste(readLines(xml_file, warn = FALSE), collapse = "\n")
  txt <- sub("^\\s*<\\?xml[^>]*\\?>", "", txt)
  txt <- paste0("<root>", txt, "</root>")

  doc <- read_xml(txt)

  # Todos los nodos que tienen un atributo title
  queries <- xml_find_all(doc, ".//*[@title]")

  df_queries <- data.frame(
    title = xml_attr(queries, "title"),
    type = xml_name(queries),
    query_xml = vapply(queries, as.character, character(1)),
    stringsAsFactors = FALSE
  )
  if (print_queries){
    print(df_queries$title)
  }
  return(df_queries)

  #save(df_queries, file = "all_queries_xpath.RData")
}



st2_create_query_xml <- function(query_title,
                             regions = NULL,
                             df_queries,
                             output_dir = "files") {

  ## Buscar la query
  idx <- match(query_title, df_queries$title)

  if (is.na(idx)) {
    stop(sprintf("No se encontró la query '%s'.", query_title))
  }

  ## XML de la query
  query_xml <- df_queries$query_xml[idx]

  ## Regiones
  if (is.null(regions)){
    regions <- c(
      "USA",
      "Canada",
      "Africa_Eastern",
      "Africa_Northern",
      "Africa_Southern",
      "Africa_Western",
      "Japan",
      "South Korea",
      "China",
      "India",
      "Brazil",
      "Central America and Caribbean",
      "Central Asia",
      "EU-12",
      "EU-15",
      "Europe_Eastern",
      "Europe_Non_EU",
      "European Free Trade Association",
      "Indonesia",
      "Mexico",
      "Middle East",
      "Pakistan",
      "Russia",
      "South Africa",
      "South America_Northern",
      "South America_Southern",
      "South Asia",
      "Southeast Asia",
      "Taiwan",
      "Argentina",
      "Colombia",
      "Australia_NZ"
    )
  }

  region_xml <- paste0(
    '    <region name="',
    regions,
    '" />',
    collapse = "\n"
  )

  ## Documento completo
  xml_text <- paste0(
    '<?xml version="1.0" encoding="UTF-8"?>\n',
    '<queries>\n\n',
    '  <aQuery>\n\n',
    '    <!-- Regions whose data will be stored -->\n',
    region_xml,
    '\n\n',
    query_xml,
    '\n\n',
    '  </aQuery>\n',
    '</queries>\n'
  )

  output_file <- file.path(output_dir, paste0(
    gsub("\\s+", "_", query_title),
    ".xml"
  ))

  writeLines(xml_text, output_file)

  invisible(output_file)
}



st2_change_xmldb_batch <- function(
    queries_of_interest,
    regions_per_query = NULL,
    xmldb_batch_file = file.path(thisScript_path, "files", "xmldb_batch.xml"),
    out_file = xmldb_batch_file,   # dónde escribir el batch (por defecto, sobre la plantilla)
    suffix = "",                   # se añade al CSV de salida: <query><suffix>_0.csv
    query_dir = "files"            # dónde escribir los XML de cada query
) {


  # EXAMPLE OF USE:
  # queries_of_interest <- c("resource production", "resource supply curves")
  # regions_per_query <- list("resource production" = c('USA', 'Argentina', 'Russia'),
  #                           "resource supply curves" = NULL)
  # Also we can set a vector with all interested regions that will be in every query

  df_queries <- st1_get_all_queries()

  # Leer el XML
  doc <- read_xml(xmldb_batch_file)

  # Nodo <class>
  class_node <- xml_find_first(doc, ".//class")

  if (inherits(class_node, "xml_missing")) {
    stop("No se encontró el nodo <class> en el XML.")
  }

  # Eliminar los <command> existentes
  xml_remove(xml_find_all(class_node, "./command"))

  # Crear un <command> por cada query
  for (query_title in queries_of_interest) {

    query_name <- gsub("\\s+", "_", query_title)

    # Crear el nodo <command>
    command <- xml_add_child(
      class_node,
      "command",
      name = "XMLDB Batch File"
    )

    xml_add_child(
      command,
      "queryFile",
      paste0("batch_queries/", query_name, ".xml")
    )

    xml_add_child(
      command,
      "outFile",
      file.path(
        thisScript_path,
        "data",
        paste0(query_name, suffix, "_0.csv")
      )
    )

    xml_add_child(
      command,
      "xmldbLocation",
      "../database_basexdb"
    )

    xml_add_child(
      command,
      "batchQueryResultsInDifferentSheets",
      "false"
    )

    xml_add_child(
      command,
      "batchQueryIncludeCharts",
      "false"
    )

    xml_add_child(
      command,
      "batchQuerySplitRunsInDifferentSheets",
      "false"
    )

    xml_add_child(
      command,
      "batchQueryReplaceResults",
      "true"
    )

    # Crear el XML de la query
    if (is.null(regions_per_query)){
    st2_create_query_xml(
      query_title = query_title,
      df_queries = df_queries,
      regions = NULL,
      output_dir = query_dir)
    }
    else if (is.vector(regions_per_query)){
      st2_create_query_xml(
        query_title = query_title,
        df_queries = df_queries,
        regions = regions_per_query,
        output_dir = query_dir)
    }else{
      st2_create_query_xml(
        query_title = query_title,
        df_queries = df_queries,
        regions = regions_per_query[[query_title]],
        output_dir = query_dir)
    }

  }

  # Guardar el XML actualizado
  write_xml(doc, out_file)

  invisible(out_file)
}


# -----------------------------------------------------------------------------
# Filtro STX de la salida de GCAM hacia la XML database
#
# GCAM pasa el escenario entero por files/xmldb_filter.stx antes de escribirlo
# en la base de datos en memoria, así que Java solo carga lo que lee la query
# "outputs by tech" (region/sector/subsector/technology/output/physical-output).
# Sin filtro, el volcado lleva el proceso de ~7-9 GB a ~31 GB.
#
# Se configura en la COPIA de XMLDBDriver.properties que hay en el directorio
# desde el que se ejecuta GCAM (worker_dir): el fichero de files/ queda como
# plantilla y no se modifica.
#   use_filter = TRUE  -> copia xmldb_filter.stx allí y activa filter-script
#   use_filter = FALSE -> deja filter-script vacío (salida completa)
# La ruta del filtro es relativa a ese directorio.
# -----------------------------------------------------------------------------
configure_xmldb_filter <- function(gcam_run_dir, use_filter = TRUE,
                                   filter_file = "xmldb_filter.stx") {

  props_file <- file.path(gcam_run_dir, "XMLDBDriver.properties")
  if (!file.exists(props_file)) {
    stop("No existe ", props_file, ": no se puede configurar el filtro de la XML database.")
  }

  if (use_filter) {
    src <- file.path(thisScript_path, "files", filter_file)
    if (!file.exists(src)) {
      stop("No existe ", src, ". Hace falta para filtrar la salida de GCAM ",
           "(o llama a GCAM_preparation con use_xmldb_filter = FALSE).")
    }
    if (!file.copy(src, gcam_run_dir, overwrite = TRUE)) {
      stop("No se pudo copiar ", src, " a ", gcam_run_dir)
    }
  }

  props <- readLines(props_file, warn = FALSE)
  pattern <- '<entry key="filter-script">[^<]*</entry>'
  hits <- grep(pattern, props)
  if (length(hits) != 1) {
    stop("No encuentro una única entrada filter-script en ", props_file)
  }
  value <- if (use_filter) filter_file else ""
  props[hits] <- sub(pattern,
                     paste0('<entry key="filter-script">', value, '</entry>'),
                     props[hits])
  writeLines(props, props_file)

  message(if (use_filter) paste0("Filtro de la XML database ACTIVADO: ", file.path(gcam_run_dir, filter_file))
          else "Filtro de la XML database DESACTIVADO (salida completa de GCAM)")
  invisible(props_file)
}


GCAM_preparation <- function(gcam_path, queries_of_interest, regions_per_query,
                             use_xmldb_filter = TRUE){

  # Prepara el directorio propio del worker (worker_dir = gcam_path/exe<suffix>,
  # ver set_gcam_paths). GCAM busca XMLDBDriver.properties en el directorio
  # desde el que se ejecuta, así que cada worker tiene el suyo, con su batch
  # de queries y su CSV de salida: data/<query><suffix>_0.csv. Ni exe/ ni los
  # ficheros de files/ se modifican, de modo que los workers no se pisan.

  if (normalizePath(worker_dir, mustWork = FALSE) == normalizePath(exe_dir, mustWork = FALSE)) {
    stop("worker_dir no puede ser exe/: hace falta un suffix no vacío.")
  }

  if (!dir.exists(file.path("data"))) {
    dir.create('data', recursive = TRUE)
  }

  batch_dir <- file.path(worker_dir, "batch_queries")
  if (dir.exists(batch_dir)) {
    unlink(list.files(batch_dir, full.names = TRUE), recursive = TRUE, force = TRUE)
  }
  dir.create(batch_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(worker_dir, "logs"), recursive = TRUE, showWarnings = FALSE)

  # Batch de queries del worker (a partir de la plantilla files/xmldb_batch.xml)
  st2_change_xmldb_batch(queries_of_interest, regions_per_query,
                         out_file  = file.path(batch_dir, "xmldb_batch.xml"),
                         suffix    = suffix,
                         query_dir = batch_dir)

  # XMLDBDriver.properties del worker (sus rutas son relativas a worker_dir)
  if (!file.copy(from = file.path(thisScript_path, 'files', 'XMLDBDriver.properties'),
                 to = worker_dir, overwrite = TRUE)) {
    stop("No se pudo copiar XMLDBDriver.properties a ", worker_dir)
  }

  # Filtro STX de la salida de GCAM (reduce mucho la memoria del volcado final)
  configure_xmldb_filter(worker_dir, use_filter = use_xmldb_filter)

  message('Directorio de GCAM del worker preparado: ', worker_dir)
}

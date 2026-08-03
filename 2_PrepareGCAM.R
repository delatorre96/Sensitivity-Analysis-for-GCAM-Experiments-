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
                             df_queries) {
  
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
  
  output_file <- paste0('files/',
    gsub("\\s+", "_", query_title),
    ".xml"
  )
  
  writeLines(xml_text, output_file)
  
  invisible(output_file)
}



st2_change_xmldb_batch <- function(
    queries_of_interest,
    regions_per_query = NULL,
    xmldb_batch_file = file.path(thisScript_path, "files", "xmldb_batch.xml")
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
        paste0(query_name, "_0.csv")
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
      regions = NULL)
    }
    else if (is.vector(regions_per_query)){
      st2_create_query_xml(
        query_title = query_title,
        df_queries = df_queries,
        regions = regions_per_query)
    }else{
      st2_create_query_xml(
        query_title = query_title,
        df_queries = df_queries,
        regions = regions_per_query[[query_title]])
    }
    
  }
  
  # Guardar el XML actualizado
  write_xml(doc, xmldb_batch_file)
  
  invisible(xmldb_batch_file)
}


GCAM_preparation <- function(gcam_path, queries_of_interest, regions_per_query){
  
  set_gcam_paths(gcam_path)
  
  st2_change_xmldb_batch(queries_of_interest, regions_per_query)
  
  file.copy(from = paste0(thisScript_path,'/files/XMLDBDriver.properties'), to = exe_dir)
  
  if (!dir.exists(file.path(exe_dir, "/batch_queries"))) {
    dir.create(path, recursive = TRUE)
  } else{
    unlink(
      list.files(path, full.names = TRUE),
      recursive = TRUE,
      force = TRUE)
  }
  
  file.copy(from = paste0(thisScript_path,'/files/xmldb_batch.xml'), to = (paste0(exe_dir, "/batch_queries/xmldb_batch.xml")))
  for (query_title in queries_of_interest){
    output_file <- paste0(gsub("\\s+", "_", query_title),
                          ".xml")
    file.copy(from =  paste0(thisScript_path,'/files/',output_file), to = (paste0(exe_dir, "/batch_queries/", output_file)))
  }
  
}
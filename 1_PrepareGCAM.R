library(dplyr)
library(xml2)

thisScript_path <- getwd()

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

get_all_queries <- function(print_queries = F){
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



create_query_xml <- function(query_title,
                             df_queries) {
  
  ## Buscar la query
  idx <- match(query_title, df_queries$title)
  
  if (is.na(idx)) {
    stop(sprintf("No se encontró la query '%s'.", query_title))
  }
  
  ## XML de la query
  query_xml <- df_queries$query_xml[idx]
  
  ## Regiones
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
  
  output_file <- paste0(
    gsub("\\s+", "_", query_title),
    ".xml"
  )
  
  writeLines(xml_text, output_file)
  
  invisible(output_file)
}





change_xmldb_batch <- function(
    queries_of_interest,
    thisScript_path,
    xmldb_batch_file = file.path(thisScript_path, "files", "xmldb_batch.xml")
) {
  
  df_queries <- get_all_queries()
  
  
  # Leer el XML
  doc <- read_xml(xmldb_batch_file)
  
  # Nodo <class>
  class_node <- xml_find_first(doc, ".//class")
  
  # Eliminar los command existentes (opcional)
  xml_remove(xml_find_all(class_node, "./command"))
  
  for (query_title in queries_of_interest) {
    
    # Sustituir espacios por guiones
    query_name <- gsub(" ", "_", query_title)
    
    # Crear el nodo command
    command <- xml_new_node("command")
    xml_set_attr(command, "name", "XMLDB Batch File")
    
    xml_add_child(command, "queryFile",
                  paste0("batch_queries/", query_name, ".xml"))
    
    xml_add_child(command, "outFile",
                  file.path(
                    thisScript_path,
                    "data",
                    paste0(query_name, "_0.csv")
                  ))
    
    xml_add_child(command, "xmldbLocation",
                  "../database_basexdb")
    
    xml_add_child(command,
                  "batchQueryResultsInDifferentSheets",
                  "false")
    
    xml_add_child(command,
                  "batchQueryIncludeCharts",
                  "false")
    
    xml_add_child(command,
                  "batchQuerySplitRunsInDifferentSheets",
                  "false")
    
    xml_add_child(command,
                  "batchQueryReplaceResults",
                  "true")
    
    # Añadir el command al nodo class
    xml_add_child(class_node, command)
    
    create_query_xml(query_title,
                     df_queries)
  }
  
  # Guardar el XML
  write_xml(doc, xmldb_batch_file)
}



GCAM_preparation <- function(gcam_path, queries_of_interest){
  
  set_gcam_paths(gcam_path)
  
  file.copy(from = paste0(thisScript_path,'/files/XMLDBDriver.properties'), to = exe_dir)
  
}
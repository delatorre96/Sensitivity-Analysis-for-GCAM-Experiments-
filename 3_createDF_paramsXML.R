st1_get_xml_files <- function(config_file) {
  
  # Leer el XML
  doc <- read_xml(config_file)
  
  # Extraer todos los Value de ScenarioComponents
  paths <- xml_text(xml_find_all(doc, "//ScenarioComponents/Value"))
  
  # Quedarse sólo con los archivos de gcamdata/xml
  paths <- paths[grepl("gcamdata/xml", paths)]
  
  # Extraer únicamente el nombre del archivo
  xml_files <- basename(paths)
  
  return(xml_files)
}

st1_get_xmls_with_logit <- function(xml_files, xml_dir) {
  Filter(function(f) {
    doc <- read_xml(file.path(xml_dir, f))
    length(xml_find_all(doc, ".//logit-exponent")) > 0
  }, xml_files)
}




st2_extract_logits_anyXML<- function(xml_file){
  
  
  doc <- read_xml(xml_file)
  
  logits <- xml_find_all(doc, ".//logit-exponent")
  
  salida <- vector("list", length(logits))
  
  for(i in seq_along(logits)){
    
    logit <- logits[[i]]
    
    padres <- xml_parents(logit)
    
    region <- NA
    supplysector <- NA
    subsector <- NA
    nesting_subsector  <- NA
    level <- NA
    
    for(p in padres){
      
      etiqueta <- xml_name(p)
      
      if(etiqueta == "region"){
        region <- xml_attr(p,"name")
      }
      
      if(etiqueta == "supplysector"){
        supplysector <- xml_attr(p,"name")
        level <- "supplysector"
      }
      
      if(etiqueta == "subsector"){
        subsector <- xml_attr(p,"name")
        level <- "subsector"
      }
      if(etiqueta == "nesting-subsector"){
        nesting_subsector <- xml_attr(p,"name")
        level <- "nesting-subsector"
      }
      
    }
    
    salida[[i]] <- data.frame(
      
      xml_file = basename(xml_file),
      
      id = i,
      
      region = region,
      
      supplysector = supplysector,
      
      subsector = subsector,
      
      level = level,
      
      nesting_subsector = nesting_subsector,
      
      fillout = xml_attr(logit,"fillout"),
      
      year = as.numeric(xml_attr(logit,"year")),
      
      logit = as.numeric(xml_text(logit)),
      
      xpath = xml_path(logit),
      
      stringsAsFactors = FALSE
      
    )
    
  }
  
  do.call(rbind,salida)
  
}


createDF_params <- function(xml_files, regions = NULL, interested_subsectors = NULL, interested_sectors = NULL){
  ##Poner regions como una lista para cada xml_file
  # EXAMPLE OF USE:
  # xml_files <- c("en_supply_EUR.xml", "ag_an_demand_input.xml")
  # regions <- list("en_supply_EUR.xml" = c('USA', 'Argentina', 'Russia'),
  #                           "ag_an_demand_input.xml" = NULL) OR just  c('USA', 'Argentina', 'Russia') for all queries
  

  
  logit_table_list <- list()
  
  for (xml_file in xml_files) {
    message(paste0('extracting logits from ', xml_file))
    xml_file_path <- file.path(dir_xml, xml_file)
    
    
    table_logit_i <- st2_extract_logits_anyXML(xml_file_path) 
    
    if(!is.null(regions)){
      if (typeof(regions) == "list"){
      regions_xml <- regions[[xml_file]]
      table_logit_i <- table_logit_i %>% 
      filter(region %in% regions_xml)
      
      }else if (typeof(regions) == "character"){
        table_logit_i <- table_logit_i %>% 
          filter(region %in% regions)
      }
    }
    
    if (!(is.null(interested_subsectors))) {
      table_logit_i <- table_logit_i %>%
        filter(
          subsector    %in% interested_subsectors
        )
    }
    if (!(is.null(interested_sectors))){
      table_logit_i <- table_logit_i %>%
        filter(
          sector %in% interested_sectors
        )
    }
    if (nrow(table_logit_i) > 0) {
      logit_table_list[[xml_file]] <- table_logit_i
    }
  }
  df_params <- bind_rows(logit_table_list) %>%
    mutate(destination_file = sub("\\.xml$", "_cal.xml", xml_file)) #%>% filter(xml_file != 'building_det_EUR.xml')
  
  write.csv(df_params, 'df_params.csv', row.names = FALSE)
  return(df_params)
}




xml_files <- st1_get_xml_files(config_file)

results <- list()

for(xml_file in xml_files){
  
  xml_file_path <- file.path(dir_xml, xml_file)
  
  doc <- read_xml(xml_file_path)
  
  # Buscar todos los calOutputValue
  nodes <- xml_find_all(doc, ".//calOutputValue")
  
  if(length(nodes) == 0) next
  
  df_xml <- map_dfr(nodes, function(node){
    
    # Padres desde la raíz hasta el padre inmediato
    parents <- xml_parents(node)
    parents <- rev(parents)
    
    row <- list()
    
    # Nombre del xml
    row$xml_file <- xml_file
    
    # XPath completo
    row$xpath <- xml_path(node)
    
    # Valor del calOutputValue
    row$calOutputValue <- as.numeric(xml_text(node))
    
    # Recorrer todos los padres
    for(p in parents){
      
      tag <- xml_name(p)
      
      attrs <- xml_attrs(p)
      
      if("name" %in% names(attrs)){
        value <- attrs["name"]
      } else if("year" %in% names(attrs)){
        value <- attrs["year"]
      } else if(length(xml_text(p)) > 0 &&
                length(xml_children(p)) == 0){
        value <- xml_text(p)
      } else{
        value <- NA_character_
      }
      
      row[[tag]] <- value
    }
    
    as_tibble(row)
    
  })
  
  results[[xml_file]] <- df_xml
}

df_caloutput <- bind_rows(results)


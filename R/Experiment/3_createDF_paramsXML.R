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

st1_get_xmls_with_value <- function(xml_files, dir_xml, value) {

  result <- lapply(value, function(v) {
    Filter(function(f) {
      doc <- read_xml(file.path(dir_xml, f))
      !is.na(xml_find_first(doc, paste0(".//", v)))
    }, xml_files)
  })

  names(result) <- value

  result
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


st2_extract_satiation_level <- function(xml_file) {
  doc <- read_xml(xml_file)
  sl  <- xml_find_all(doc, ".//satiation-level")
  inp <- xml_parent(xml_parent(sl))          # input del que cuelga la satiation-demand-function

  data.frame(
    xml_file      = basename(xml_file),
    id            = seq_along(sl),
    region        = xml_attr(xml_find_first(sl, "ancestor::region"), "name"),
    gcam_consumer = xml_attr(xml_find_first(sl, "ancestor::gcam-consumer"), "name"),
    input_type    = xml_name(inp),           # building-node-input / thermal-... / building-service-input
    input_name    = xml_attr(inp, "name"),   # comm_building, comm cooling EUR, comm others EUR...
    value_default = as.numeric(xml_text(sl)),
    xpath         = xml_path(sl),
    stringsAsFactors = FALSE
  ) |>
    mutate(group = case_when(
      input_type == "building-node-input"     ~ "floorspace",
      grepl("heating", input_name)            ~ "heating",
      grepl("cooling", input_name)            ~ "cooling",
      TRUE                                    ~ "other_services"))
}



st2_extract_price_elasticity_anyXML<- function(xml_file){


  doc <- read_xml(xml_file)

  prices <- xml_find_all(doc, ".//price-elasticity")

  salida <- vector("list", length(prices))

  for(i in seq_along(prices)){

    price_elasticity <- prices[[i]]

    padres <- xml_parents(price_elasticity)

    region <- NA

    for(p in padres){

      etiqueta <- xml_name(p)

      if(etiqueta == "region"){
        region <- xml_attr(p,"name")
      }

    }

    salida[[i]] <- data.frame(

      xml_file = basename(xml_file),

      id = i,

      region = region,

      year = as.numeric(xml_attr(price_elasticity,"year")),

      price_elasticity = as.numeric(xml_text(price_elasticity)),

      xpath = xml_path(price_elasticity),

      stringsAsFactors = FALSE

    )

  }

  do.call(rbind,salida)

}


# -----------------------------------------------------------------------------
# 2. Índice de aparición: para cada fila, qué número de <tag> es en el fichero.
#    Se ejecuta UNA vez, en el script que construye df_allParams.
# -----------------------------------------------------------------------------
tag_of <- c(logit            = "logit-exponent",
            price_elasticity = "price-elasticity",
            satiation_level  = "satiation-level")
add_occurrence_index <- function(df, dir_xml) {
  df$tag <- unname(tag_of[df$type_of_param])
  df$occ <- NA_integer_
  for (f in unique(df$xml_file)) {
    doc <- read_xml(file.path(dir_xml, f))
    for (tg in unique(df$tag[df$xml_file == f])) {
      rows  <- which(df$xml_file == f & df$tag == tg)
      paths <- xml_path(xml_find_all(doc, paste0("//", tg)))
      df$occ[rows] <- match(df$xpath[rows], paths)
    }
    rm(doc); gc()
  }
  if (anyNA(df$occ)) {
    stop("Hay xpath que no se encuentran entre los nodos de su etiqueta: ",
         paste(head(df$xpath[is.na(df$occ)], 5), collapse = " | "))
  }
  df
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
    mutate(destination_file = sub("\\.xml$", paste0(suffix, ".xml"), xml_file)) #%>% filter(xml_file != 'building_det_EUR.xml')

  #write.csv(df_params, here::here("R", "df_params.csv"), row.names = FALSE) Expansion: Use existent df_params if other experiment with same xml is run instead of creating other
  return(df_params)
}



build_xml_cache <- function(df, dir_xml) {
  lines_list <- list()
  df$line <- NA_integer_
  for (f in unique(df$xml_file)) {
    lines <- readLines(file.path(dir_xml, f), encoding = "UTF-8", warn = FALSE)
    rows  <- which(df$xml_file == f)
    for (tg in unique(df$tag[rows])) {
      pos <- grep(paste0("<", tg, "[ >]"), lines, perl = TRUE)
      r   <- rows[df$tag[rows] == tg]
      if (max(df$occ[r]) > length(pos)) stop("occ fuera de rango en ", f, " / ", tg)
      df$line[r] <- pos[df$occ[r]]
    }
    # Verificación: el valor original de esa línea debe ser param_default
    orig <- as.numeric(sub("^[^>]*>([^<]*)<.*$", "\\1", lines[df$line[rows]]))
    bad  <- is.na(orig) | abs(orig - df$param_default[rows]) > 1e-6 * pmax(1, abs(orig))
    if (any(bad)) {
      stop("En ", f, " hay ", sum(bad), " filas cuya línea no contiene el valor esperado. ",
           "¿Ha cambiado el XML original desde que se creó df_params?")
    }
    lines_list[[f]] <- lines
  }
  list(lines = lines_list, df = df)
}

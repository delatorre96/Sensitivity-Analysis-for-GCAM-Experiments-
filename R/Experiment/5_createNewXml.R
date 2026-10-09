
insert_params <- function(xml_entrada,
                          table_params,
                          xml_salida){

  doc <- read_xml(xml_entrada)

  for(i in seq_len(nrow(table_params))){

    nodo <- xml_find_first(doc, table_params$xpath[i])

    if(!inherits(nodo, "xml_missing")){

      # Crear el nuevo nodo
      nuevo <- read_xml(sprintf(
        '<logit-exponent fillout="%s" year="%s">%s</logit-exponent>',
        table_params$fillout[i],
        table_params$year[i],
        table_params$logit[i]
      ))

      # Insertarlo después del logit existente
      xml_add_sibling(nodo, nuevo, .where = "after")
    }
  }

  write_xml(doc, xml_salida, options = "format")
}


createNewXml <- function (df_params_copy){

  xml_files_set <- unique(df_params_copy$xml_file)


  for (xml_i in xml_files_set){
    message(paste0('Processing ',xml_i,'...'))
    df_params_i <- df_params_copy[df_params_copy$xml_file == xml_i, ]
    xml_file_path <- paste0(dir_xml, '/', unique(df_params_i$xml_file))
    xml_file_cal  <- paste0(dir_xml,'/',unique(df_params_i$destination_file))

    df_params_i$xml_file <- NULL
    df_params_i$destination_file <- NULL

    insert_params(
      xml_file_path,
      df_params_i,
      xml_file_cal
    )

  }

}



insert_params_others<- function(xml_entrada,
                          table_params,
                          xml_salida,
                          type_of_param){


  if (type_of_param == 'price_elasticity'){
  doc <- read_xml(xml_entrada)

  for(i in seq_len(nrow(table_params))){

    nodo <- xml_find_first(doc, table_params$xpath[i])

    if(!inherits(nodo, "xml_missing")){

      # Crear el nuevo nodo
      nuevo <- read_xml(sprintf(
        '<price-elasticity year="%s">%s</price-elasticity>',
        table_params$year[i],
        table_params$param[i]
      ))

      # Insertarlo después del logit existente
      xml_add_sibling(nodo, nuevo, .where = "after")
    }
  }

  write_xml(doc, xml_salida, options = "format")
  } else if (type_of_param ==  "satiation_level"){

    # Leer XML
    doc <- read_xml(xml_entrada)

    # Recorrer las filas de la tabla
    for (i in seq_len(nrow(table_params))) {

      # Buscar el nodo mediante el XPath
      nodo <- xml_find_first(doc, table_params$xpath[i])

      if (!inherits(nodo, "xml_missing")) {

        # Sustituir directamente el contenido del nodo
        nuevo <- read_xml(sprintf(
          '<satiation-level>%s</satiation-level>',
          table_params$param[i]
        ))

        # Insertarlo después del logit existente
        xml_replace(nodo, nuevo)
      }
    }

    # Guardar XML modificado
    write_xml(doc, xml_salida, options = "format")
  }else if (type_of_param == 'logit'){
    doc <- read_xml(xml_entrada)

    for(i in seq_len(nrow(table_params))){

      nodo <- xml_find_first(doc, table_params$xpath[i])

      if(!inherits(nodo, "xml_missing")){

        # Crear el nuevo nodo
        nuevo <- read_xml(sprintf(
          '<logit-exponent fillout="%s" year="%s">%s</logit-exponent>',
          table_params$fillout[i],
          table_params$year[i],
          table_params$param[i]
        ))

        # Insertarlo después del logit existente
        xml_add_sibling(nodo, nuevo, .where = "after")
      }
    }

    write_xml(doc, xml_salida, options = "format")
  }
}



createNewXml_other_params <- function (df_params_copy){

  xml_files_set <- unique(df_params_copy$xml_file)


  for (xml_i in xml_files_set){
    t1 <- Sys.time()
    df_params_i <- df_params_copy[df_params_copy$xml_file == xml_i, ]
    xml_file_path <- paste0(dir_xml, '/', unique(df_params_i$xml_file))
    xml_file_cal  <- paste0(dir_xml,'/',unique(df_params_i$destination_file))

    type_of_param <- unique(df_params_i$type_of_param)
    if (length(type_of_param) > 1 ){
      for (param in type_of_param){
        insert_params_others(
          xml_entrada = xml_file_path,
          table_params=  df_params_i,
          xml_salida = xml_file_cal,
          type_of_param = param
        )
      }
    }else{
      insert_params_others(
        xml_entrada = xml_file_path,
        table_params=  df_params_i,
        xml_salida = xml_file_cal,
        type_of_param = type_of_param
      )
    }
    t2 <- Sys.time()
    last <- round(as.numeric(t2 - t1, units = "mins"),2)
    message(xml_i, ' processed in ',last, ' mins')
  }

}



fmt_num <- function(x) trimws(formatC(x, digits = 8, format = "g"))

write_xml_fast <- function(lines, d, out_file) {
  new <- lines
  ind <- sub("<.*$", "", lines[d$line])          # sangría original de cada línea

  # satiation-level: se SUSTITUYE la línea
  s <- d$type_of_param == "satiation_level"
  if (any(s)) {
    new[d$line[s]] <- paste0(ind[s], "<satiation-level>", fmt_num(d$param[s]), "</satiation-level>")
  }

  # logit / price-elasticity: se INSERTA una línea después de la original
  ins <- character(nrow(d))
  l <- d$type_of_param == "logit"
  if (any(l)) {
    ins[l] <- sprintf('%s<logit-exponent fillout="%s" year="%s">%s</logit-exponent>',
                      ind[l], d$fillout[l], d$year[l], fmt_num(d$param[l]))
  }
  p <- d$type_of_param == "price_elasticity"
  if (any(p)) {
    ins[p] <- sprintf('%s<price-elasticity year="%s">%s</price-elasticity>',
                      ind[p], d$year[p], fmt_num(d$param[p]))
  }
  k <- l | p
  if (any(k)) {
    add <- tapply(ins[k], d$line[k], paste, collapse = "\n")   # por si dos filas apuntan a la misma línea
    pos <- as.integer(names(add))
    new[pos] <- paste0(new[pos], "\n", add)
  }

  con <- file(out_file, open = "w", encoding = "UTF-8")
  on.exit(close(con))
  writeLines(new, con)
}

createNewXml_fast <- function(df_params_copy, xml_lines, dir_xml) {
  for (f in unique(df_params_copy$xml_file)) {
    message("Processing ", f,'..')
    t1 <- Sys.time()
    d  <- df_params_copy[df_params_copy$xml_file == f, ]
    write_xml_fast(xml_lines[[f]], d, file.path(dir_xml, unique(d$destination_file)))
    message("Built in ", round(as.numeric(Sys.time() - t1, units = "secs"), 1), " s")
  }
}



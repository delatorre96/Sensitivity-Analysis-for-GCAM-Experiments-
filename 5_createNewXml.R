
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



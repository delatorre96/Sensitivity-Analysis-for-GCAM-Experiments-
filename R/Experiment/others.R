# =============================================================================
# fast_xml_params.R
# Escritura rápida de parámetros en XML de GCAM sin DOM (edición por líneas)
# + extracción corregida de satiation-level + muestreo por multiplicador.
#
# Idea: los XML de gcamdata tienen un elemento por línea (comprobado en
# building_det_EUR.xml y transportation_UCD_CORE_EUR.xml). Así que:
#   1. Al construir df_params (una sola vez) se guarda, para cada fila, su
#      posición de aparición ("occ") entre los nodos de esa etiqueta.
#   2. Al empezar cada job se leen los XML originales como texto (una vez) y se
#      traduce occ -> número de línea, verificando que el valor de esa línea
#      coincide con param_default (si no coincide, se para).
#   3. En cada iteración solo se sustituyen/insertan líneas y se escribe.
# El resto del fichero queda byte a byte igual que el original.
# =============================================================================

library(xml2)
library(dplyr)

tag_of <- c(logit            = "logit-exponent",
            price_elasticity = "price-elasticity",
            satiation_level  = "satiation-level")

# -----------------------------------------------------------------------------
# 1. Extracción de satiation-level (sustituye a st2_extract_satiation_level)
# -----------------------------------------------------------------------------
st2_extract_satiation_level <- function(xml_file) {
  doc <- read_xml(xml_file)
  sl  <- xml_find_all(doc, "//satiation-level")
  inp <- xml_parent(xml_parent(sl))   # input del que cuelga <satiation-demand-function>

  data.frame(
    xml_file        = basename(xml_file),
    id              = seq_along(sl),
    region          = xml_attr(xml_find_first(sl, "ancestor::region"), "name"),
    gcam_consumer   = xml_attr(xml_find_first(sl, "ancestor::gcam-consumer"), "name"),
    level           = "gcam-consumer",            # se mantiene por compatibilidad
    input_type      = xml_name(inp),              # building-node-input / thermal-building-service-input / building-service-input
    input_name      = xml_attr(inp, "name"),
    satiation_level = as.numeric(xml_text(sl)),
    xpath           = xml_path(sl),
    stringsAsFactors = FALSE
  ) |>
    mutate(group = case_when(
      input_type == "building-node-input" ~ "floorspace",
      grepl("heating", input_name)        ~ "heating",
      grepl("cooling", input_name)        ~ "cooling",
      TRUE                                ~ "other_services"))
}

# -----------------------------------------------------------------------------
# 2. Índice de aparición: para cada fila, qué número de <tag> es en el fichero.
#    Se ejecuta UNA vez, en el script que construye df_allParams.
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# 3. Cargar los XML originales como texto y asignar número de línea a cada fila.
#    Se ejecuta UNA vez por job, antes del bucle de iteraciones.
#    Devuelve list(lines = <lista de vectores de líneas>, df = df con columna line)
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# 4. Escritura rápida de un XML a partir de sus líneas originales
# -----------------------------------------------------------------------------
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
    t1 <- Sys.time()
    d  <- df_params_copy[df_params_copy$xml_file == f, ]
    write_xml_fast(xml_lines[[f]], d, file.path(dir_xml, unique(d$destination_file)))
    message(f, " escrito en ", round(as.numeric(Sys.time() - t1, units = "secs"), 1), " s")
  }
}

# -----------------------------------------------------------------------------
# 5. Muestreo: satiation como multiplicador log-uniforme sobre param_default
# -----------------------------------------------------------------------------
introduce_heterogeneous_uncertainty_by_type <- function(
    n_iterations = NULL, i = NULL,
    distribution_parameters, paramCol = "param", df_params) {

  df_params_copy <- df_params
  df_params_copy$year <- 2021

  is_logit            <- df_params$type_of_param == "logit"
  is_price_elasticity <- df_params$type_of_param == "price_elasticity"
  is_satiation        <- df_params$type_of_param == "satiation_level"

  if (any(!(is_logit | is_price_elasticity | is_satiation))) {
    stop("Tipos de parámetro no reconocidos: ",
         paste(unique(df_params$type_of_param[!(is_logit | is_price_elasticity | is_satiation)]),
               collapse = ", "))
  }

  new_param <- df_params$param_default
  mult_sat  <- NULL

  if (any(is_logit)) {
    dp <- distribution_parameters$logit
    new_param[is_logit] <- runif(sum(is_logit), dp$minVal, dp$maxVal)
  }

  if (any(is_price_elasticity)) {
    dp <- distribution_parameters$price_elasticity
    new_param[is_price_elasticity] <- runif(sum(is_price_elasticity), dp$minVal, dp$maxVal)
  }

  if (any(is_satiation)) {
    dp  <- distribution_parameters$satiation_level        # minVal/maxVal son MULTIPLICADORES
    grp <- df_params$group[is_satiation]
    if (identical(dp$by, "row")) {                        # un factor por fila
      mult <- exp(runif(sum(is_satiation), log(dp$minVal), log(dp$maxVal)))
    } else {                                              # por defecto: un factor por grupo
      g        <- unique(grp)
      mult_sat <- setNames(exp(runif(length(g), log(dp$minVal), log(dp$maxVal))), g)
      mult     <- unname(mult_sat[grp])
    }
    new_param[is_satiation] <- df_params$param_default[is_satiation] * mult
  }

  # round(., 3) convertiría satiation de 1.8e-05 en 0: se usan cifras significativas
  df_params_copy[[paramCol]] <- ifelse(is_satiation, signif(new_param, 6), round(new_param, 3))

  list(df_params_copy = df_params_copy, delta = NA_real_, satiation_multipliers = mult_sat)
}

# =============================================================================
# USO
# =============================================================================
# --- (a) En "createDFParams_for satiationAndPriceElasticity.R", al final: ---
#
# df_allParams <- bind_rows(df_logits, df_price_elas, df_satiationlevel) |>
#   mutate(param_default = param) |>
#   add_occurrence_index(dir_xml)
# write.csv(df_allParams, "df_allParams.csv", row.names = FALSE)
#
# --- (b) En cada job, después de leer df_params y cambiar destination_file: ---
#
# cache     <- build_xml_cache(df_params, dir_xml)   # una vez por job
# df_params <- cache$df
# xml_lines <- cache$lines
#
# distribution_parameters <- list(
#   logit            = list(minVal = -20,  maxVal = -0.01),
#   price_elasticity = list(minVal = -1.5, maxVal = -0.01),
#   satiation_level  = list(minVal = 0.5,  maxVal = 2, by = "group"))
#
# for (it in seq_len(n_iterations)) {
#   res <- introduce_heterogeneous_uncertainty_by_type(
#            distribution_parameters = distribution_parameters, df_params = df_params)
#   createNewXml_fast(res$df_params_copy, xml_lines, dir_xml)
#   # ... lanzar run-gcam<suffix>.bat, guardar res$df_params_copy y res$satiation_multipliers
# }

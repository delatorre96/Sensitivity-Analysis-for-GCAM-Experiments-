
introduce_aditive_uncertainty <- function(n_iterations = NULL, i = NULL, min_val, max_val, df_params, paramCol = 'logit'){

  df_params_copy <- df_params
  df_params_copy$year  <- 2021

  if (all(df_params[[paramCol]] <= 0)){
  repeat {

    delta <- round(runif(1,min_val,max_val),2)

    new_logit <- df_params[[paramCol]] * (1 + delta)

    if (all(new_logit <= 0)) break
    }
  } else if (all(df_params[[paramCol]] >= 0)){
    repeat {

      delta <- round(runif(1,min_val,max_val),2)

      new_logit <- df_params[[paramCol]] * (1 + delta)

      if (all(new_logit >= 0)) break
    }
  }else{
    delta <- round(runif(1,min_val,max_val),2)

    new_logit <- df_params[[paramCol]] * (1 + delta)
  }


  df_params_copy[[paramCol]] <- round(new_logit, 2)
  return(list('df_params_copy' = df_params_copy,
              'delta' = delta))

}


introduce_aditive_Latin_HyperCube_uncertainty <- function(n_iterations, i, min_val, max_val, df_params, paramCol = 'logit'){

  df_params_copy <- df_params
  df_params_copy$year  <- 2021

  total_delta <- round(
    seq(max_val, min_val, length.out = n_iterations),
    2
  )


  delta <- total_delta[i]

  new_logits <- df_params[[paramCol]] * (1 + delta)

  invalid <- new_logits > 0


  while (any(invalid)) {
    new_logits[invalid] <- new_logits[invalid] * (-1)
    invalid <- new_logits > 0
  }

  df_params_copy[[paramCol]] <- round(new_logits, 2)


  return(list('df_params_copy' = df_params_copy,
              'delta' = delta))

}

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



introduce_hierarchical_uncertainty <- function(relative_uncertainty =  round(runif(1,0.1,1),1), paramCol = 'logit', df_params){

  message('Inducing uncertainty in the parameters...')

  df_params_copy <- df_params
  df_params_copy$year  <- 2021

  factor <- runif(
    1,
    1 - relative_uncertainty,
    1 + relative_uncertainty
  )
  while (factor < 0) {
    factor <- runif(
      1,
      1 - relative_uncertainty,
      1 + relative_uncertainty
    )
  }

  df_params_copy[[paramCol]] <- round(df_params_copy[[paramCol]] * factor, 2)

  return(df_params_copy)

}





introduce_heterogeneous_uncertainty_by_type <- function(
    n_iterations = NULL,
    i = NULL,
    distribution_parameters,
    paramCol = "param",
    df_params
) {

  df_params_copy <- df_params
  df_params_copy$year <- 2021


  #----- Identificar tipo de parámetro -----

  is_logit <- df_params$type_of_param == "logit"
  is_price_elasticity <- df_params$type_of_param == "price_elasticity"
  is_satiation <- df_params$type_of_param == "satiation_level"


  #----- Generar nuevos valores -----

  new_param <- numeric(nrow(df_params))


  # Logits
  # Distribución uniforme entre -15 y -0.01
  if (any(is_logit)) {

    new_param[is_logit] <- runif(
      sum(is_logit),
      min = distribution_parameters$logit$minVal,
      max = distribution_parameters$logit$maxVal
    )

  }


  # Price elasticities
  # Distribución uniforme entre -1.5 y -0.01
  if (any(is_price_elasticity)) {

    new_param[is_price_elasticity] <- runif(
      sum(is_price_elasticity),
      min = distribution_parameters$price_elasticity$minVal,
      max = distribution_parameters$price_elasticity$maxVal
    )

  }


  # Satiation levels
  # Distribución uniforme entre 0.001 y 3
  if (any(is_satiation)) {

    new_param[is_satiation] <- runif(
      sum(is_satiation),
      min = distribution_parameters$satiation_level$minVal,
      max = distribution_parameters$satiation_level$maxVal
    )

  }


  #----- Comprobar parámetros no reconocidos -----

  is_known_type <- is_logit |
    is_price_elasticity |
    is_satiation

  if (any(!is_known_type)) {

    unknown_types <- unique(
      df_params$type_of_param[!is_known_type]
    )

    stop(
      "Se han encontrado tipos de parámetro no reconocidos: ",
      paste(unknown_types, collapse = ", ")
    )

  }


  #----- Guardar nuevos parámetros -----

  df_params_copy[[paramCol]] <- round(new_param, 3)


  return(
    list(
      df_params_copy = df_params_copy,
      delta = NA_real_
    )
  )
}


introduce_aditive_heterogeneous_uncertainty_satiation <- function(
    n_iterations = NULL,
    i = NULL,
    paramCol = 'param',
    min_val,
    max_val,
    df_params,
    use_param_range_for_satiation = TRUE
) {

  df_params_copy <- df_params
  df_params_copy$year <- 2021


  #----- Definir límites de la distribución uniforme -----

  if (use_param_range_for_satiation &&
      any(df_params$type_of_param == "satiation_level")) {

    df_satiation <- df_params[
      df_params$type_of_param == "satiation_level",
      ,
      drop = FALSE
    ]

    min_val_satiation <- min(
      df_satiation[[paramCol]],
      na.rm = TRUE
    )

    max_val_satiation <- max(
      df_satiation[[paramCol]],
      na.rm = TRUE
    )

  } else {

    min_val_satiation <- min_val
    max_val_satiation <- max_val

  }


  #----- Generar un delta independiente para cada parámetro -----

  deltas <- numeric(nrow(df_params))

  is_satiation <- df_params$type_of_param == "satiation_level"


  # Para satiation_level:
  # usar el rango observado en df_params
  if (use_param_range_for_satiation && any(is_satiation)) {

    deltas[is_satiation] <- runif(
      sum(is_satiation),
      min_val_satiation,
      max_val_satiation
    )

  }


  # Para el resto de parámetros:
  # usar los límites proporcionados a la función
  if (any(!is_satiation)) {

    deltas[!is_satiation] <- runif(
      sum(!is_satiation),
      min_val,
      max_val
    )

  }


  deltas <- round(deltas, 3)


  #----- Calcular nuevos parámetros -----

  new_param <- df_params[[paramCol]] * (1 + deltas)


  #----- Evitar logits positivos -----

  is_logit <- df_params$type_of_param == "logit"

  invalid <- is_logit & new_param > 0


  while (any(invalid)) {

    new_param[invalid] <- new_param[invalid] * (-1)
    invalid <- is_logit & new_param > 0

  }


  df_params_copy[[paramCol]] <- round(new_param, 2)


  return(
    list(
      df_params_copy = df_params_copy,
      delta = deltas
    )
  )
}






introduce_heterogeneous_uncertainty_by_delta <- function(
    n_iterations = NULL, i = NULL,
    distribution_parameters,
    paramCol = "param",
    df_params,
    max_attempts = 10000) {

  #----- preparar datos -----

  df_params_copy <- df_params
  df_params_copy$year <- 2021

  is_logit            <- df_params$type_of_param == "logit"
  is_price_elasticity <- df_params$type_of_param == "price_elasticity"
  is_satiation        <- df_params$type_of_param == "satiation_level"

  if (anyNA(df_params$type_of_param) ||
      any(!(is_logit | is_price_elasticity | is_satiation))) {
    stop("Existen tipos de parámetro no reconocidos.")
  }

  if (any(!is.finite(df_params$param_default))) {
    stop("param_default contiene valores no finitos.")
  }

  required_types <- c(
    "logit", "price_elasticity", "satiation_level"
  )

  if (!all(required_types %in% names(distribution_parameters))) {
    stop("Faltan distribuciones para uno o más tipos de parámetros.")
  }

  #----- validar límites -----

  for (type in required_types) {
    dp <- distribution_parameters[[type]]

    if (is.null(dp$minVal) || is.null(dp$maxVal) ||
        length(dp$minVal) != 1 || length(dp$maxVal) != 1 ||
        !is.finite(dp$minVal) || !is.finite(dp$maxVal) ||
        dp$minVal > dp$maxVal) {
      stop("Límites minVal/maxVal no válidos para: ", type)
    }

    if (dp$minVal <= -1) {
      stop("minVal debe ser mayor que -1 para: ", type)
    }
  }

  #----- muestrear delta y comprobar restricciones -----

  sample_valid_delta <- function(type, mask, sign_constraint) {

    dp <- distribution_parameters[[type]]
    reference <- df_params$param_default[mask]

    for (attempt in seq_len(max_attempts)) {

      delta <- round(runif(1, dp$minVal, dp$maxVal), 3)
      candidate <- reference * (1 + delta)

      valid <- switch(
        sign_constraint,
        negative = all(candidate < 0),
        positive = all(candidate > 0)
      )

      if (valid) {
        return(delta)
      }
    }

    stop(
      "No se encontró un delta válido para ", type,
      " después de ", max_attempts, " intentos. ",
      "Comprueba los valores de referencia y los límites."
    )
  }

  #----- generar los tres deltas -----

  deltas <- c(
    logit = sample_valid_delta(
      "logit", is_logit, "negative"
    ),
    price_elasticity = sample_valid_delta(
      "price_elasticity", is_price_elasticity, "negative"
    ),
    satiation_level = sample_valid_delta(
      "satiation_level", is_satiation, "positive"
    )
  )

  #----- aplicar perturbaciones -----

  new_param <- as.numeric(as.character(df_params$param))

  if (anyNA(new_param) || any(!is.finite(new_param))) {
    stop("param contiene valores no numéricos o no finitos.")
  }

  new_param[is_logit] <-
    df_params$param[is_logit] * (1 + deltas["logit"])

  new_param[is_price_elasticity] <-
    df_params$param[is_price_elasticity] *
    (1 + deltas["price_elasticity"])

  new_param[is_satiation] <-
    df_params$param[is_satiation] *
    (1 + deltas["satiation_level"])

  #----- redondear y validar resultado final -----

  new_param[is_logit | is_price_elasticity] <-
    round(new_param[is_logit | is_price_elasticity], 3)

  new_param[is_satiation] <-
    signif(new_param[is_satiation], 6)

  if (any(new_param[is_logit] > 0) ||
      any(new_param[is_price_elasticity] > 0) ||
      any(new_param[is_satiation] < 0)) {
    stop("La perturbación genera parámetros inválidos tras el redondeo.")
  }

  df_params_copy[[paramCol]] <- new_param

  #----- devolver resultados -----

  list(
    df_params_copy = df_params_copy,
    delta = deltas
  )
}






#' Perturba parámetros de GCAM de forma relativa (porcentual) según su tipo
#'
#' Cada parámetro se multiplica por (1 + delta), con delta ~ U(minVal, maxVal)
#' definido por tipo en `distribution_parameters`. Por ejemplo,
#' list(minVal = -0.4, maxVal = 0.4) permite variar el valor original entre
#' -40 % y +40 %.
#'
#' Restricciones de dominio (tras redondear):
#'   - logit            < 0
#'   - price_elasticity < 0
#'   - satiation_level  > 0
#' Si un valor perturbado se sale del dominio, se vuelve a muestrear su delta
#' hasta cumplirlo (como máximo `max_tries` veces).
#'
#' Nota: con perturbación multiplicativa el signo solo puede cambiar si
#' delta <= -1 (es decir, minVal <= -1, reducciones de 100 % o más), o si el
#' redondeo lleva a 0 un valor muy pequeño. Un valor original igual a 0 no
#' puede llevarse al dominio con un porcentaje; esos casos se gestionan con
#' `zero_action`.
#'
#' Restricción adicional para satiation_level: todos los gcam_consumers de un
#' mismo grupo (region, input_type, input_name sin el sufijo de decil "_dN")
#' reciben la MISMA perturbación. P. ej. en Spain, "resid heating modern
#' EUR_d1" ... "EUR_d10" comparten un único delta.
#'
#' @param n_iterations,i Se mantienen por compatibilidad con la función original.
#' @param distribution_parameters Lista con minVal/maxVal (proporciones) por tipo.
#' @param paramCol Columna con el valor del parámetro.
#' @param df_params Data frame de parámetros (con columna `type_of_param`).
#' @param digits Decimales del redondeo si |x| >= 1; cifras significativas si |x| < 1.
#' @param max_tries Número máximo de remuestreos por parámetro.
#' @param zero_action Qué hacer con valores originales igual a 0 (o NA):
#'   "keep" (se dejan como están y se avisa) o "error".
#' @param satiation_group_cols Columnas que definen el grupo de satiation_level.
#' @param decile_pattern Regex que se elimina de las columnas de agrupación
#'   (por defecto el sufijo de decil, "_d1" ... "_d10").
#'
#' @return list(df_params_copy, delta), donde `delta` es el vector de
#'   perturbaciones relativas aplicadas (NA en las filas no perturbadas).
introduce_relative_uncertainty_by_type <- function(
    n_iterations = NULL,
    i = NULL,
    distribution_parameters,
    paramCol = "param",
    df_params,
    digits = 3,
    max_tries = 1000,
    zero_action = c("keep", "error"),
    satiation_group_cols = c("region", "input_type", "input_name"),
    decile_pattern = "_d[0-9]+$"
) {

  zero_action <- match.arg(zero_action)

  df_params_copy <- df_params
  df_params_copy$year <- 2021

  original <- as.numeric(df_params[[paramCol]])
  type <- df_params$type_of_param


  #----- Comprobar tipos de parámetro -----

  known_types <- c("logit", "price_elasticity", "satiation_level")

  if (any(!type %in% known_types)) {

    unknown_types <- unique(type[!type %in% known_types])

    stop(
      "Se han encontrado tipos de parámetro no reconocidos: ",
      paste(unknown_types, collapse = ", ")
    )

  }


  #----- Comprobar distribution_parameters -----

  for (tp in unique(type)) {

    dp <- distribution_parameters[[tp]]

    if (is.null(dp) || is.null(dp$minVal) || is.null(dp$maxVal)) {
      stop("Falta minVal/maxVal en distribution_parameters para '", tp, "'.")
    }

    if (dp$minVal > dp$maxVal) {
      stop("minVal > maxVal para '", tp, "'.")
    }

  }


  #----- Redondeo -----

  # Para |x| >= 1 se redondea a `digits` decimales (como la función original).
  # Para |x| < 1 se usan `digits` cifras significativas, para no convertir en 0
  # satiation levels muy pequeños (p. ej. 1.8e-05).
  round_param <- function(x) {
    ifelse(abs(x) >= 1, round(x, digits), signif(x, digits))
  }


  #----- Función de dominio por tipo -----

  in_domain <- function(x, tp) {
    switch(
      tp,
      logit            = !is.na(x) & x < 0,
      price_elasticity = !is.na(x) & x < 0,
      satiation_level  = !is.na(x) & x > 0
    )
  }


  #----- Valores originales que no pueden perturbarse -----

  # Un 0 (o NA) multiplicado por (1 + delta) sigue siendo 0 (o NA):
  # nunca entraría en el dominio, así que no se remuestrea.
  not_perturbable <- is.na(original) | original == 0

  if (any(not_perturbable)) {

    msg <- paste0(
      sum(not_perturbable), " parámetro(s) con valor original 0 o NA ",
      "(tipos: ", paste(unique(type[not_perturbable]), collapse = ", "), "). ",
      "Una perturbación porcentual no puede moverlos al dominio."
    )

    if (zero_action == "error") stop(msg)

    warning(msg, " Se mantienen sin cambios.")

  }


  #----- Grupos de perturbación -----

  # Cada fila de un grupo recibe el mismo delta.
  #   - logit y price_elasticity: cada fila es su propio grupo.
  #   - satiation_level: region + input_type + input_name sin sufijo de decil,
  #     de modo que resid EUR_d1 ... resid EUR_d10 comparten perturbación.
  group_key <- as.character(seq_len(nrow(df_params)))

  is_satiation <- type == "satiation_level"

  if (any(is_satiation)) {

    missing_cols <- setdiff(satiation_group_cols, names(df_params))

    if (length(missing_cols) > 0) {
      stop(
        "Faltan columnas para agrupar satiation_level: ",
        paste(missing_cols, collapse = ", ")
      )
    }

    key_parts <- lapply(
      satiation_group_cols,
      function(col) sub(decile_pattern, "", as.character(df_params[[col]][is_satiation]))
    )

    group_key[is_satiation] <- paste0(
      "satiation|", do.call(paste, c(key_parts, sep = "|"))
    )

    # Aviso si los valores originales difieren dentro de un grupo
    # (se aplica igualmente el mismo delta relativo)
    n_vals <- tapply(
      original[is_satiation],
      group_key[is_satiation],
      function(v) length(unique(v))
    )

    if (any(n_vals > 1)) {
      warning(
        sum(n_vals > 1), " grupo(s) de satiation_level tienen valores originales ",
        "distintos entre gcam_consumers. Se les aplica el mismo delta relativo."
      )
    }

  }


  #----- Generar nuevos valores -----

  new_param <- original
  delta <- rep(NA_real_, length(original))

  for (tp in known_types) {

    idx <- which(type == tp & !not_perturbable)

    if (length(idx) == 0) next

    minVal <- distribution_parameters[[tp]]$minVal
    maxVal <- distribution_parameters[[tp]]$maxVal

    # Índice de grupo (1..n_groups) para cada fila de este tipo
    groups <- unique(group_key[idx])
    gid <- match(group_key[idx], groups)

    # Un delta por grupo
    delta_grp <- runif(length(groups), min = minVal, max = maxVal)

    delta[idx] <- delta_grp[gid]
    new_param[idx] <- round_param(original[idx] * (1 + delta[idx]))

    # Un grupo es inválido si alguna de sus filas se sale del dominio;
    # en ese caso se remuestrea el grupo entero (mantiene el delta común)
    bad_groups <- unique(gid[!in_domain(new_param[idx], tp)])
    tries <- 0

    while (length(bad_groups) > 0 && tries < max_tries) {

      delta_grp[bad_groups] <- runif(length(bad_groups), min = minVal, max = maxVal)
      delta[idx] <- delta_grp[gid]
      new_param[idx] <- round_param(original[idx] * (1 + delta[idx]))

      bad_groups <- unique(gid[!in_domain(new_param[idx], tp)])
      tries <- tries + 1

    }

    if (length(bad_groups) > 0) {
      stop(
        "No se ha encontrado un valor válido para ", length(bad_groups),
        " grupo(s) de tipo '", tp, "' tras ", max_tries,
        " intentos. Revisa minVal/maxVal (si minVal y maxVal son <= -1 ",
        "es imposible respetar el signo)."
      )
    }

  }


  #----- Guardar nuevos parámetros -----

  df_params_copy[[paramCol]] <- new_param


  return(
    list(
      df_params_copy = df_params_copy,
      delta = delta
    )
  )
}


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


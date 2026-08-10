
introduce_aditive_uncertainty <- function(n_iterations = NULL, i = NULL, min_val, max_val, df_params){
  
  df_params_copy <- df_params
  df_params_copy$year  <- 2021
  
  
  repeat {
    
    delta <- round(runif(1,min_val,max_val),2)
    
    new_logit <- df_params$logit * (1 + delta)
    
    if (all(new_logit <= 0)) break
    
  }
  
  
  df_params_copy$logit <- round(new_logit, 2)
  return(list('df_params_copy' = df_params_copy,
              'delta' = delta))

}


introduce_aditive_Latin_HyperCube_uncertainty <- function(n_iterations, i, min_val, max_val, df_params){
  
  df_params_copy <- df_params
  df_params_copy$year  <- 2021
  
  total_delta <- round(seq(min_val, max_val,  length.out = n_iterations),2)
  
    
  delta <- total_delta[i]
  
  new_logits <- df_params$logit * (1 + delta)
  
  invalid <- new_logits > 0
  
  
  while (any(invalid)) {
    new_logits[invalid] <- new_logits[invalid] * (-1)
    invalid <- new_logits > 0
  }
  
  df_params_copy$logit <- round(new_logits, 2)
  
  
  
  df_params_copy$logit <- round(new_logits, 2)
  return(list('df_params_copy' = df_params_copy,
              'delta' = delta))
  
}


introduce_aditive_heterogeneous_uncertainty <- function(
    n_iterations = NULL,
    i = NULL,
    min_val,
    max_val,
    df_params
) {
  
  df_params_copy <- df_params
  df_params_copy$year <- 2021
  
  # Generar un delta independiente para cada logit
  deltas <- round(
    runif(length(df_params$logit), min_val, max_val),
    3
  )
  
  # Calcular nuevos logits
  new_logits <- df_params$logit * (1 + deltas)
  
  # Si algún logit resulta positivo, regenerar solo esos deltas
  invalid <- new_logits > 0
  
  
  while (any(invalid)) {
    new_logits[invalid] <- new_logits[invalid] * (-1)
    invalid <- new_logits > 0
  }
  
  df_params_copy$logit <- round(new_logits, 2)
  
  return(
    list(
      df_params_copy = df_params_copy,
      delta = NA_real_
    )
  )
}



introduce_hierarchical_uncertainty <- function(relative_uncertainty =  round(runif(1,0.1,1),1), df_params){

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

  df_params_copy$logit <- round(df_params_copy$logit * factor, 2)
  
  return(df_params_copy)
  
}



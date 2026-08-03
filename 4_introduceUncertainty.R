
introduce_aditive_uncertainty <- function(min_val, max_val, df_params){
  
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



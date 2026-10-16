##############################################################################
# 8_reinforcementLearning.R
#
# Agente de reinforcement learning que ajusta los tres hiperparámetros delta
# (logit, price_elasticity, satiation_level) para minimizar el MAE del run de
# GCAM frente a los datos observados de 2021.
#
# Formulación
# -----------
# Cada iteración es un episodio de un paso (bandit continuo):
#   acción     a = (delta_logit, delta_price_elasticity, delta_satiation_level)
#   recompensa r = f(MAE_ref, MAE_run)  (> 0 si MAE_run < MAE_ref, < 0 si no)
#
# Política: gaussiana en un espacio no acotado u, transformada a los límites
# [minVal, maxVal] de distribution_parameters con una sigmoide (logit-normal):
#   u_k ~ N(m_k, s_k^2),  z_k = plogis(u_k),  delta_k = lo_k + z_k (hi_k - lo_k)
# Así los deltas siempre respetan los rangos sin recortar la distribución.
#
# Aprendizaje: REINFORCE (policy gradient) por lotes, con baseline
# leave-one-out dentro del lote, ventajas normalizadas y Adam sobre (m, log s).
# Al principio s es grande (exploración amplia); a medida que el agente
# encuentra regiones con menor MAE, m se desplaza hacia ellas y s se reduce
# (explotación), con un mínimo min_sigma para no dejar de explorar.
#
# Uso desde 7_1_init_experiment_dfParams.R:
#   agent    <- rl_init_agent(distribution_parameters, rl_config, state_path)
#   prop     <- rl_propose(agent)            # antes de escribir los xml
#   res      <- apply_deltas_to_params(df_params, prop$deltas, paramCol)
#   ... GCAM ...
#   eval     <- rl_evaluate_run(con, run_id, queries_of_interest, ref_values)
#   reward   <- rl_reward(eval$MAE_run, eval$MAE_ref, failed, agent$config)
#   agent    <- rl_update(agent, prop, reward, eval, run_id)
#   rl_save_agent(agent, state_path)
##############################################################################


#----- configuración por defecto ---------------------------------------------

rl_default_config <- function() {
  list(
    mode            = "train",    # "train": explora y aprende; "exploit": usa la media de la política sin aprender
    reward_type     = "log_ratio",# "log_ratio": log(MAE_ref/MAE_run); "relative": (MAE_ref - MAE_run)/MAE_ref
    failure_reward  = -1,         # recompensa si GCAM falla o no hay outputs comparables
    reward_clip     = c(-3, 3),   # recorte de recompensas extremas
    batch_size      = 4,          # runs por actualización de la política
    lr_mean         = 0.30,       # tasa de aprendizaje de m (Adam)
    lr_log_sigma    = 0.10,       # tasa de aprendizaje de log s (Adam)
    init_mean       = 0,          # m inicial en el espacio u (0 = centro del rango)
    init_sigma      = 1.5,        # s inicial (1.5 cubre casi todo el rango)
    min_sigma       = 0.10,       # s mínimo: exploración residual
    max_sigma       = 3.00,
    delta_digits    = 3,          # redondeo de los deltas (igual que el muestreo aleatorio)
    resume          = TRUE,       # reanudar el agente si existe un estado guardado
    seed            = NULL        # semilla opcional
  )
}

rl_param_types <- c("logit", "price_elasticity", "satiation_level")


#----- datos de referencia (observado vs GCAM base) --------------------------

# Lee el csv de errores del modelo base y se queda solo con las columnas
# necesarias para unir con los outputs del run, evitando columnas duplicadas.
rl_load_reference <- function(path, regions_of_interest,
                              keys = c("region", "sector", "subsector", "output", "technology")) {

  ref <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
  ref <- ref[, colSums(!is.na(ref)) > 0, drop = FALSE]
  ref <- ref[ref$region %in% regions_of_interest, , drop = FALSE]

  needed <- c(keys, "value_ref", "abs_error")
  missing_cols <- setdiff(needed, names(ref))
  if (length(missing_cols) > 0) {
    stop("El fichero de referencia no tiene las columnas: ",
         paste(missing_cols, collapse = ", "))
  }

  ref <- ref[, needed]
  ref$value_ref <- as.numeric(ref$value_ref)
  ref$abs_error <- as.numeric(ref$abs_error)

  dup <- duplicated(ref[, keys])
  if (any(dup)) {
    warning(sum(dup), " filas duplicadas en la referencia para las claves; se usa la primera.")
    ref <- ref[!dup, ]
  }

  attr(ref, "keys") <- keys
  ref
}


#----- evaluación de un run ---------------------------------------------------

# Devuelve MAE_run y MAE_ref calculados sobre EXACTAMENTE las mismas filas
# (las que existen en el output del run y en la referencia), de modo que la
# comparación sea justa aunque falten tecnologías en algún run.
rl_evaluate_run <- function(con, run_id, query_name, ref_values, year_col = "2021") {

  keys <- attr(ref_values, "keys")
  if (is.null(keys)) keys <- c("region", "sector", "subsector", "output", "technology")

  df_run <- read_run_output(con = con, query_name = query_name, run_id = run_id)

  empty <- list(MAE_run = NA_real_, MAE_ref = NA_real_, n_obs = 0L, df = NULL)
  if (is.null(df_run) || nrow(df_run) == 0 || !(year_col %in% names(df_run))) {
    return(empty)
  }

  df_run <- as.data.frame(df_run, check.names = FALSE)
  df_run$value_run <- suppressWarnings(as.numeric(df_run[[year_col]]))
  df_run <- df_run[, c(keys, "value_run")]

  df <- merge(df_run, ref_values, by = keys)
  df <- df[!is.na(df$value_ref) & !is.na(df$value_run) & !is.na(df$abs_error), ]

  if (nrow(df) == 0) return(empty)

  df$error     <- df$value_ref - df$value_run
  df$error_abs <- abs(df$error)

  list(
    MAE_run = mean(df$error_abs),
    MAE_ref = mean(df$abs_error),
    n_obs   = nrow(df),
    df      = df
  )
}


#----- recompensa -------------------------------------------------------------

# Positiva si MAE_run < MAE_ref, negativa si MAE_run > MAE_ref.
rl_reward <- function(MAE_run, MAE_ref, failed = FALSE, config = rl_default_config()) {

  if (isTRUE(failed) || !is.finite(MAE_run) || !is.finite(MAE_ref) || MAE_ref <= 0) {
    return(config$failure_reward)
  }

  r <- switch(
    config$reward_type,
    log_ratio = log(MAE_ref / max(MAE_run, .Machine$double.eps)),
    relative  = (MAE_ref - MAE_run) / MAE_ref,
    stop("reward_type no reconocido: ", config$reward_type)
  )

  min(max(r, config$reward_clip[1]), config$reward_clip[2])
}


#----- agente -----------------------------------------------------------------

rl_init_agent <- function(distribution_parameters, rl_config = list(), state_path = NULL) {

  config <- utils::modifyList(rl_default_config(), rl_config)

  if (!all(rl_param_types %in% names(distribution_parameters))) {
    stop("distribution_parameters debe tener: ", paste(rl_param_types, collapse = ", "))
  }

  lower <- sapply(rl_param_types, function(t) distribution_parameters[[t]]$minVal)
  upper <- sapply(rl_param_types, function(t) distribution_parameters[[t]]$maxVal)
  if (any(lower <= -1)) stop("minVal debe ser > -1 para conservar el signo de los parámetros.")
  if (any(lower >= upper)) stop("minVal debe ser menor que maxVal para todos los tipos.")

  if (!is.null(config$seed)) set.seed(config$seed)

  # reanudar si existe estado previo con los mismos límites
  if (isTRUE(config$resume) && !is.null(state_path) && file.exists(state_path)) {
    agent <- readRDS(state_path)
    if (isTRUE(all.equal(agent$lower, lower)) && isTRUE(all.equal(agent$upper, upper))) {
      agent$config <- utils::modifyList(agent$config, rl_config)  # permite cambiar p.ej. mode
      message("RL: agente reanudado desde ", state_path,
              " (", agent$step, " pasos, mejor MAE = ", signif(agent$best$MAE_run, 5), ")")
      return(agent)
    }
    warning("RL: el estado guardado tiene otros límites; se crea un agente nuevo.")
  }

  k <- length(rl_param_types)
  zeros <- stats::setNames(rep(0, k), rl_param_types)

  agent <- list(
    config  = config,
    lower   = lower,
    upper   = upper,
    m       = stats::setNames(rep(config$init_mean, k), rl_param_types),
    log_s   = stats::setNames(rep(log(config$init_sigma), k), rl_param_types),
    adam    = list(t = 0, m1 = c(zeros, zeros), m2 = c(zeros, zeros)),
    buffer  = list(),
    step    = 0L,
    updates = 0L,
    best    = list(MAE_run = Inf, reward = -Inf, deltas = NULL, run_id = NA_character_),
    history = data.frame()
  )

  message("RL: agente nuevo. Rango de deltas: ",
          paste0(rl_param_types, " [", lower, ", ", upper, "]", collapse = "; "))
  agent
}


rl_u_to_delta <- function(agent, u) {
  z <- stats::plogis(u)
  d <- agent$lower + z * (agent$upper - agent$lower)
  d <- round(d, agent$config$delta_digits)
  pmin(pmax(d, agent$lower), agent$upper)
}

# Media actual de la política expresada en deltas (útil para seguimiento)
rl_policy_mean_delta <- function(agent) rl_u_to_delta(agent, agent$m)


# Propone los deltas del siguiente run.
rl_propose <- function(agent) {

  if (identical(agent$config$mode, "exploit")) {
    u <- agent$m
  } else {
    u <- stats::rnorm(length(agent$m), mean = agent$m, sd = exp(agent$log_s))
    names(u) <- names(agent$m)
  }

  list(u = u, deltas = rl_u_to_delta(agent, u), mode = agent$config$mode)
}


# Registra el resultado del run y, cuando el lote está completo, actualiza la política.
rl_update <- function(agent, proposal, reward, evaluation = NULL, run_id = NA_character_) {

  agent$step <- agent$step + 1L

  MAE_run <- if (is.null(evaluation)) NA_real_ else evaluation$MAE_run
  MAE_ref <- if (is.null(evaluation)) NA_real_ else evaluation$MAE_ref
  n_obs   <- if (is.null(evaluation)) 0L else evaluation$n_obs

  # mejor run observado
  if (is.finite(MAE_run) && MAE_run < agent$best$MAE_run) {
    agent$best <- list(MAE_run = MAE_run, MAE_ref = MAE_ref, reward = reward,
                       deltas = proposal$deltas, run_id = run_id, step = agent$step)
    message("RL: nuevo mejor run ", run_id, " con MAE = ", signif(MAE_run, 5))
  }

  # aprendizaje solo en modo train
  if (identical(agent$config$mode, "train")) {
    agent$buffer[[length(agent$buffer) + 1]] <- list(u = proposal$u, reward = reward)
    if (length(agent$buffer) >= agent$config$batch_size) {
      agent <- rl_policy_gradient_step(agent)
    }
  }

  # historial (estado de la política DESPUÉS de este paso)
  row <- data.frame(
    step       = agent$step,
    run_id     = run_id,
    mode       = proposal$mode,
    t(stats::setNames(proposal$deltas, paste0("delta_", names(proposal$deltas)))),
    MAE_run    = MAE_run,
    MAE_ref    = MAE_ref,
    n_obs      = n_obs,
    reward     = reward,
    t(stats::setNames(rl_policy_mean_delta(agent), paste0("policy_mean_", rl_param_types))),
    t(stats::setNames(exp(agent$log_s), paste0("policy_sigma_", rl_param_types))),
    updates    = agent$updates,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  agent$history <- rbind(agent$history, row)

  message(sprintf("RL paso %d | MAE_run = %s | MAE_ref = %s | reward = %.4f | media política: %s",
                  agent$step, signif(MAE_run, 5), signif(MAE_ref, 5), reward,
                  paste(names(agent$m), rl_policy_mean_delta(agent), sep = "=", collapse = ", ")))
  agent
}


# REINFORCE por lotes con baseline leave-one-out y Adam.
rl_policy_gradient_step <- function(agent) {

  cfg <- agent$config
  U   <- do.call(rbind, lapply(agent$buffer, `[[`, "u"))
  r   <- vapply(agent$buffer, `[[`, numeric(1), "reward")
  n   <- length(r)
  agent$buffer <- list()

  # ventaja: recompensa menos la media del resto del lote, normalizada
  baseline <- (sum(r) - r) / (n - 1)
  adv <- r - baseline
  sdr <- stats::sd(r)
  if (!is.finite(sdr) || sdr < 1e-8) {
    message("RL: recompensas idénticas en el lote; no se actualiza la política.")
    return(agent)
  }
  adv <- adv / sdr

  s  <- exp(agent$log_s)
  M  <- matrix(agent$m, n, length(s), byrow = TRUE)
  S  <- matrix(s,       n, length(s), byrow = TRUE)
  eps <- (U - M) / S                             # ruido estandarizado

  grad_m     <- colMeans(adv * eps / S)          # d log pi / d m
  grad_log_s <- colMeans(adv * (eps^2 - 1))      # d log pi / d log s
  g <- c(grad_m, grad_log_s)

  # Adam (ascenso)
  b1 <- 0.9; b2 <- 0.999; e <- 1e-8
  ad <- agent$adam
  ad$t  <- ad$t + 1
  ad$m1 <- b1 * ad$m1 + (1 - b1) * g
  ad$m2 <- b2 * ad$m2 + (1 - b2) * g^2
  mhat  <- ad$m1 / (1 - b1^ad$t)
  vhat  <- ad$m2 / (1 - b2^ad$t)
  step  <- mhat / (sqrt(vhat) + e)
  k <- length(agent$m)
  lr <- c(rep(cfg$lr_mean, k), rep(cfg$lr_log_sigma, k))
  step <- lr * step

  agent$m     <- agent$m + step[1:k]
  agent$log_s <- agent$log_s + step[(k + 1):(2 * k)]
  agent$log_s <- pmin(pmax(agent$log_s, log(cfg$min_sigma)), log(cfg$max_sigma))
  agent$m     <- pmin(pmax(agent$m, -8), 8)  # evita saturar la sigmoide
  agent$adam  <- ad
  agent$updates <- agent$updates + 1L

  agent
}


#----- aplicar deltas a df_params ---------------------------------------------

# Versión determinista de introduce_heterogeneous_uncertainty_by_delta():
# aplica los deltas propuestos por el agente con el mismo redondeo y validación.
apply_deltas_to_params <- function(df_params, deltas, paramCol = "param") {

  df_params_copy <- df_params
  df_params_copy$year <- 2021

  is_logit            <- df_params$type_of_param == "logit"
  is_price_elasticity <- df_params$type_of_param == "price_elasticity"
  is_satiation        <- df_params$type_of_param == "satiation_level"

  if (anyNA(df_params$type_of_param) ||
      any(!(is_logit | is_price_elasticity | is_satiation))) {
    stop("Existen tipos de parámetro no reconocidos.")
  }
  if (!all(rl_param_types %in% names(deltas))) {
    stop("deltas debe ser un vector nombrado con: ", paste(rl_param_types, collapse = ", "))
  }

  base <- as.numeric(as.character(df_params[[paramCol]]))
  if (anyNA(base) || any(!is.finite(base))) {
    stop(paramCol, " contiene valores no numéricos o no finitos.")
  }

  new_param <- base
  new_param[is_logit]            <- base[is_logit]            * (1 + deltas[["logit"]])
  new_param[is_price_elasticity] <- base[is_price_elasticity] * (1 + deltas[["price_elasticity"]])
  new_param[is_satiation]        <- base[is_satiation]        * (1 + deltas[["satiation_level"]])

  new_param[is_logit | is_price_elasticity] <- round(new_param[is_logit | is_price_elasticity], 3)
  new_param[is_satiation] <- signif(new_param[is_satiation], 6)

  if (any(new_param[is_logit] > 0) ||
      any(new_param[is_price_elasticity] > 0) ||
      any(new_param[is_satiation] < 0)) {
    stop("Los deltas propuestos generan parámetros con signo inválido.")
  }

  df_params_copy[[paramCol]] <- new_param
  list(df_params_copy = df_params_copy, delta = deltas[rl_param_types])
}


#----- persistencia -----------------------------------------------------------

rl_state_path <- function(experiment_id, suffix, root_dir = here::here("Experiments")) {
  dir <- file.path(root_dir, experiment_id, "rl")
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  file.path(dir, paste0("agent", suffix, ".rds"))
}

rl_save_agent <- function(agent, state_path) {
  tmp <- paste0(state_path, ".tmp")
  saveRDS(agent, tmp)
  file.rename(tmp, state_path)
  utils::write.csv(agent$history, sub("\\.rds$", "_history.csv", state_path), row.names = FALSE)
  invisible(state_path)
}


# Tabla RL_History en la base de datos sqlite (una fila por run).
rl_write_history <- function(con, experiment_id, suffix, agent) {

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS RL_History (
      run_id TEXT PRIMARY KEY,
      experiment_id TEXT,
      worker_suffix TEXT,
      step INTEGER,
      mode TEXT,
      delta_logit REAL,
      delta_price_elasticity REAL,
      delta_satiation_level REAL,
      MAE_run REAL,
      MAE_ref REAL,
      n_obs INTEGER,
      reward REAL,
      policy_mean_logit REAL,
      policy_mean_price_elasticity REAL,
      policy_mean_satiation_level REAL,
      policy_sigma_logit REAL,
      policy_sigma_price_elasticity REAL,
      policy_sigma_satiation_level REAL,
      updates INTEGER,
      created_at TEXT,
      FOREIGN KEY (run_id) REFERENCES Runs(run_id)
    );
  ")

  row <- utils::tail(agent$history, 1)
  row$experiment_id <- experiment_id
  row$worker_suffix <- suffix
  row$created_at    <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  DBI::dbAppendTable(con, "RL_History", row)
}


rl_summary <- function(agent) {
  message("========== RL resumen ==========")
  message("Pasos: ", agent$step, " | actualizaciones de política: ", agent$updates)
  message("Media de la política (deltas): ",
          paste(names(agent$m), rl_policy_mean_delta(agent), sep = "=", collapse = ", "))
  message("Sigma de la política: ",
          paste(names(agent$log_s), round(exp(agent$log_s), 3), sep = "=", collapse = ", "))
  if (is.finite(agent$best$MAE_run)) {
    message("Mejor run: ", agent$best$run_id, " | MAE = ", signif(agent$best$MAE_run, 5),
            " | deltas: ", paste(names(agent$best$deltas), agent$best$deltas, sep = "=", collapse = ", "))
  }
  invisible(agent)
}

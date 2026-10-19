
create_database <- function(db_path = here::here("gcam_sensitivity.sqlite")) {

  #----- conectar a la base de datos -----

  con <- DBI::dbConnect(
    RSQLite::SQLite(),
    db_path
  )

  #----- crear tabla Experiments -----

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS Experiments (
      experiment_id TEXT PRIMARY KEY,
      project TEXT,
      gcam_version TEXT NOT NULL,
      name TEXT NOT NULL,
      number_iterations INTEGER,
      description TEXT,
      created_at TEXT,
      inputs_xml TEXT,
      outputs_queries TEXT,
      regions TEXT,
      perturbation_strategy TEXT,
      distribution TEXT,
      distribution_parameters TEXT
    );
  ")

  #----- crear tabla Runs -----

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS Runs (
      run_id TEXT PRIMARY KEY,
      experiment_id INTEGER NOT NULL,
      execution_time REAL,
      execution_errors TEXT,
      delta REAL,
      delta_logit REAL,
      delta_price_elasticity REAL,
      delta_satiation_level REAL,

      FOREIGN KEY (experiment_id)
        REFERENCES Experiments(experiment_id)
    );
  ")

  #----- crear tabla Datasets -----

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS Datasets (
      experiment_id TEXT,
      run_id TEXT,
      dataset_type TEXT NOT NULL,
      dataset_name TEXT,
      filepath TEXT,
      size_mb REAL,

      FOREIGN KEY (experiment_id)
        REFERENCES Experiments(experiment_id),
      FOREIGN KEY (run_id)
        REFERENCES Runs(run_id)
    );
  ")

  #----- desconectar -----

  DBI::dbDisconnect(con)
}


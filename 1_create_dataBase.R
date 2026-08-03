create_database <- function(db_path = "gcam_sensitivity.sqlite") {

con <- dbConnect(
  SQLite(),
  "gcam_sensitivity.sqlite"
)


dbExecute(con, "
CREATE TABLE IF NOT EXISTS Experiments (
    experiment_id TEXT PRIMARY KEY ,
    project TEXT ,
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


dbExecute(con, "
CREATE TABLE IF NOT EXISTS Runs (
    run_id TEXT PRIMARY KEY ,
    experiment_id INTEGER NOT NULL,
    execution_time REAL,
    execution_errors TEXT,
    delta REAL,

    FOREIGN KEY (experiment_id)
        REFERENCES Experiments(experiment_id)
);
")

dbExecute(con, "
CREATE TABLE IF NOT EXISTS Datasets (
    experiment_id TEXT,
    run_id TEXT ,
    dataset_type TEXT NOT NULL,
    dataset_name TEXT,
    filepath TEXT,
    ncols INTEGER,
    nrows INTEGER,

    FOREIGN KEY (experiment_id)
        REFERENCES Experiments(experiment_id),
    FOREIGN KEY (run_id)
        REFERENCES Runs(run_id)
);
")



dbDisconnect(con)
}

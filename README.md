# Sensitivity Analysis for GCAM Experiments

An R framework for running **parametric-uncertainty experiments on GCAM-Europe**. It stores the parameters and outputs of every run in a traceable way and can **search for configurations that reduce the 2021 hindcasting error** with a reinforcement-learning agent (optional).

It belongs to the *Hindcasting and evaluation of GCAM-Europe* project (BC3). Within the project architecture it mainly covers **Phase 3 (uncertainty and sensitivity analysis)** and feeds **Phases 4–5 (surrogate models and calibration)**.

---

## 1. What it does, in one sentence

For each iteration it **perturbs** logit exponents, price elasticities and/or satiation levels in GCAM's input XMLs, **runs GCAM**, extracts the query of interest (`outputs by tech` by default), **saves inputs and outputs as Parquet**, and records everything in a **SQLite catalogue** (`gcam_sensitivity.sqlite`).

```
df_allParams.csv ──► perturbation ──► XML *_<suffix>.xml ──► GCAM (configuration<suffix>.xml)
                                                                     │
                                                    batch query (ModelInterface)
                                                                     ▼
 gcam_sensitivity.sqlite ◄── metadata ── Experiments/<EXP_id>/{inputs,outputs}/…/<RUN_id>.parquet
```

---

## 2. Repository layout

```
.
├── runSensAn_allParams_monteCarlo_debug.R   # Launcher: global Monte Carlo (absolute uniform sampling)
├── runSensAn_allParams_deltas.R             # Launcher: relative deltas + RL agent (or random sampling)
├── runSensParam_pretrained.R                # Launcher: evaluate fixed configurations (e.g. proposed by the GAM)
│
├── R/
│   ├── Experiment/                          # Execution pipeline (numbered by stage)
│   │   ├── 0_mainFunctions.R                # Packages, GCAM paths, per-worker config/.bat, run_gcam()
│   │   ├── 1_create_dataBase.R              # SQLite schema (Experiments, Runs, Datasets)
│   │   ├── 2_PrepareGCAM.R                  # Prepares the ModelInterface batch queries
│   │   ├── 3_createDF_paramsXML.R           # Extracts parameters from the XMLs and builds the line cache
│   │   ├── 4_introduceUncertainty.R         # Perturbation strategies
│   │   ├── 5_createNewXml.R                 # Writes the perturbed XMLs
│   │   ├── 6_appendResults.R                # Saves Parquet files and records them in SQLite
│   │   ├── 7_init_experiment.R              # (legacy) original loop, logits only
│   │   ├── 7_1_init_experiment_dfParams.R   # Loop with optimizer = 'rl' | 'random'
│   │   ├── 7_2_init_experiment_dfParams.R   # Monte Carlo loop + CPU/RAM monitoring
│   │   ├── 7_2_init_experiment_dfParams_withoutUncer.R  # Loop without perturbation (predefined configs)
│   │   ├── 8_reinforcementLearning.R        # REINFORCE agent (Gaussian policy gradient)
│   │   └── others.R                         # Copies/drafts of functions (not loaded by the pipeline)
│   └── Storage/                             # Querying and maintaining results
│       ├── explore_dataBase.R               # read_experiment_inputs / read_experiment_output / read_run_output
│       ├── manageExperiments.R              # Merge, integrity checks, cleaning and deletion of experiments
│       ├── example of use.R                 # Usage examples for the Storage functions
│       └── run_merge_experiments.R          # Script to merge equivalent experiments
│
├── files/                                   # ModelInterface templates
│   ├── allQueries.xml                       # Full catalogue of GCAM queries
│   ├── xmldb_batch.xml                      # Batch file (rewritten during preparation)
│   ├── XMLDBDriver.properties               # Copied to gcam/exe: in-memory DB + batch queries
│   └── query.xml, resource_*.xml            # Example queries
│
├── Experiments.dvc                          # Data versioned with DVC (Experiments/, ~300 MB)
├── gcam_sensitivity.sqlite.dvc              # SQLite catalogue versioned with DVC
├── renv.lock, renv/, .Rprofile              # Reproducible R environment (renv)
└── GCAM_sensitivity_analysis.Rproj          # Project root for here::here()
```

`Experiments/`, `data/`, `gcam_sensitivity.sqlite`, CSV and RDS files, etc. are listed in `.gitignore`: the heavy data is versioned with **DVC**, not git.

---

## 3. Requirements

- **R** (renv is set up with R 4.5 on Windows; on DIPC the `r44` conda environment has been used).
- A built **GCAM-Europe** installation with `exe/configuration.xml`, `exe/run-gcam.bat` (Windows) and the generated XMLs in `input/gcamdata/xml/`. The GCAM version is recorded automatically with `git describe --tags` on the GCAM repo, so **GCAM must be a git repository with tags**.
- **Java** (for ModelInterface / GCAM batch queries).
- **DVC** (optional) to fetch `Experiments/` and `gcam_sensitivity.sqlite`.
- Files outside this repo, referenced by relative paths:
  - `../gcam_europe`: the GCAM installation.
  - `../Hindcasting/4_SensitivityAnalysis/create_dfParams/df_allParams.csv`: the parameter table (see §5).
  - `../Hindcasting/2. Extraction/Data/all_errors_output_by_tech.csv`: base-model errors against 2021 observations (only needed for RL / MAE tracking).

Set up the environment:

```r
renv::restore()           # installs the versions pinned in renv.lock
```

`check_packages()` also installs any missing package among: DBI, RSQLite, XML, xml2, uuid, dplyr, arrow, jsonlite, purrr, tibble, stringr (`here` and `withr` are used as well).

---

## 4. Running an experiment

**Always run from the repository root** (paths are resolved with `here::here()` and `getwd()`):

```bash
Rscript runSensAn_allParams_monteCarlo_debug.R NULL _w1
#                                              │    └── worker suffix
#                                              └────── experiment_id (NULL = new experiment)
```

Arguments:

| Argument | Meaning |
|---|---|
| `experiment_id` | `NULL` creates a new experiment (`EXP_xxxxxxxx`). An existing id **adds runs** to that experiment (it must exist in the SQLite file). |
| `suffix` | Worker identifier. Used to generate `configuration<suffix>.xml`, `run-gcam<suffix>.bat` and the perturbed XMLs `<name><suffix>.xml`, so that workers neither overwrite the original XMLs nor each other's. It also names the monitoring files. |

To run in parallel, start the first worker with `NULL`, take the `EXP_…` id it creates, and start the remaining workers with that id and different suffixes (`_w2`, `_w3`, …).

### The three launchers

| Script | Loop it uses | Strategy | Typical use |
|---|---|---|---|
| `runSensAn_allParams_monteCarlo_debug.R` | `7_2_init_experiment_dfParams.R` | `introduce_heterogeneous_uncertainty_by_type`: each parameter gets an independent **absolute** value ~ U(min, max) by type | Global exploration of the parameter space (Monte Carlo) |
| `runSensAn_allParams_deltas.R` | `7_1_init_experiment_dfParams.R` | `optimizer = 'rl'`: the agent proposes one **relative delta per parameter type**; `optimizer = 'random'`: `introduce_heterogeneous_uncertainty_by_delta` | Calibration / directed search to minimise MAE |
| `runSensParam_pretrained.R` | `7_2_init_experiment_dfParams_withoutUncer.R` | No perturbation: runs each `param_config` from a CSV of already-fixed parameters | Checking in GCAM the configurations proposed by a surrogate (GAM) |

The experiment settings are edited **inside the launcher itself**, not on the command line: `gcam_path`, `xml_files`, `regions_of_interest`, `n_iterations`, `queries_of_interest`, `distribution_parameters`, `interested_query_columns`, `df_params_path`, experiment name and description, etc.

---

## 5. The parameter table (`df_allParams.csv`)

This is the central input: **one row per perturbable parameter** in GCAM's XMLs. It is built outside this repo (in `../Hindcasting/4_SensitivityAnalysis/create_dfParams/`) with the functions in `3_createDF_paramsXML.R`:

- `st2_extract_logits_anyXML()` → `<logit-exponent>` (with region, supplysector, subsector, nesting-subsector, level, `fillout`, year).
- `st2_extract_price_elasticity_anyXML()` → `<price-elasticity>`.
- `st2_extract_satiation_level()` → building `<satiation-level>`, grouped into `floorspace`, `heating`, `cooling`, `other_services`.
- `add_occurrence_index()` → adds `tag` and `occ` (which occurrence of that tag it is within the file).

Columns used by the pipeline: `xml_file`, `destination_file`, `type_of_param` (`logit` | `price_elasticity` | `satiation_level`), `param`, `param_default`, `tag`, `occ`, `xpath`, `region`, `year`, `fillout`, `group` (satiation) and, for predefined configurations, `param_config`.

`destination_file` is generated with a `_cal.xml` suffix, which the loop replaces with `<suffix>.xml` at start-up.

---

## 6. What happens in each iteration

1. **Setup (once per worker)**
   - `set_gcam_paths()` sets global GCAM paths (`exe/`, `configuration.xml`, `gcamdata/xml`, log).
   - If `gcam_sensitivity.sqlite` does not exist, it is created (`create_database()`).
   - If `alreadyPrepeared = F`, `GCAM_preparation()` generates the queries from `files/allQueries.xml`, rewrites `xmldb_batch.xml`, and copies everything to `gcam/exe/batch_queries/` together with `XMLDBDriver.properties`. With `T` this is assumed to be done already.
   - For a new experiment: `write_experiment_info()` (`Experiments` table) and `create_experiment_folders()`.
   - `create_new_config()` creates `configuration<suffix>.xml` pointing to the suffixed XMLs; `create_new_run_gcam()` creates `run-gcam<suffix>.bat`.
   - `build_xml_cache()` reads the original XMLs into memory once and locates the **line** of each parameter. It checks that the value on that line matches `param_default`; if not, it stops (a sign that the XML has changed since `df_params` was generated).

2. **Loop (`n_iterations`)**
   1. Generates `run_id = RUN_xxxxxxxx`.
   2. **Perturbation** with the chosen strategy (or the RL agent's proposal).
   3. **XML writing** with `createNewXml_fast()`, which works on text lines (much faster than rewriting with xml2):
      - `satiation-level`: the line is **replaced**.
      - `logit-exponent` / `price-elasticity`: a new line with `year="2021"` is **inserted** right after the original, so GCAM uses the perturbed value from 2021 onwards.
   4. **Runs GCAM** (`run_gcam()`; `cmd.exe` on Windows, `bash` on Linux).
   5. Sets `execution_errors = TRUE` if the word "error" appears in `exe/logs/main_log.txt`.
   6. Saves the **inputs** (`save_inputs_parquet()`) and the batch-query **outputs** (`save_run_outputs()`, only the columns listed in `interested_query_columns`).
   7. Registers the files in `Datasets`, deletes the intermediate CSVs in `data/`, records the run in `Runs` and updates `number_iterations`.
   8. (Only in `7_1`, if the reference file exists) computes the run's MAE and reward, and updates the RL agent.

---

## 7. Perturbation strategies (`4_introduceUncertainty.R`)

| Function | What it does |
|---|---|
| `introduce_heterogeneous_uncertainty_by_type` | Independent **absolute** value per parameter: `runif(minVal, maxVal)` by `type_of_param`. Used for Monte Carlo. |
| `introduce_heterogeneous_uncertainty_by_delta` | One **relative delta shared per type**: `param × (1 + δ_type)`, resampling δ until signs are respected (logit < 0, elasticity < 0, satiation > 0). Requires `minVal > −1` and all three types in `distribution_parameters`. |
| `introduce_aditive_uncertainty` | One delta for the whole column, with a sign constraint. |
| `introduce_aditive_Latin_HyperCube_uncertainty` | Evenly spaced deltas between `max_val` and `min_val` by iteration. |
| `introduce_aditive_heterogeneous_uncertainty_satiation` | Independent delta per row; for satiation it uses the range observed in `df_params`. |
| `introduce_hierarchical_uncertainty` | Common multiplicative factor ~ U(1 − u, 1 + u). |

`distribution_parameters` is passed as a list by type, e.g.:

```r
distribution_parameters = list(
  logit            = list(minVal = -20,   maxVal = -0.01),
  price_elasticity = list(minVal = -1.5,  maxVal = -0.01),
  satiation_level  = list(minVal = 0.001, maxVal = 3)
)
```

It is serialised as JSON in the `Experiments` table, so each experiment keeps the ranges it was generated with.

---

## 8. Reinforcement-learning agent (`8_reinforcementLearning.R`)

Formulated as a **continuous bandit**: each run is a one-step episode.

- **Action**: a vector of relative deltas, one per parameter type in `rl_param_types`. **Currently only `price_elasticity`** (logit and satiation are commented out).
- **Policy**: Gaussian in an unbounded space `u ~ N(m, s²)`, mapped through a sigmoid to `[minVal, maxVal]`, so deltas always stay within bounds.
- **Reward**: `log(MAE_ref / MAE_run)` (or relative), clipped to `[-3, 3]`; `-1` if GCAM fails or there are no comparable rows. `MAE_ref` and `MAE_run` are computed on **the same rows** (joined on `region, sector, subsector, output, technology`) using the 2021 value.
- **Learning**: batched REINFORCE (`batch_size`), leave-one-out baseline, normalised advantages and Adam on `(m, log s)`; `s` decreases down to `min_sigma`.
- **Modes**: `train` (explores and learns), `exploit` (uses the policy mean) and `observe` (with `optimizer = 'random'`: only records the MAE).
- **Persistence**: state in `Experiments/<EXP>/rl/agent<suffix>.rds` (+ `_history.csv`); resumed if it exists (`resume = TRUE`). History is also written to the SQLite table `RL_History`.

With `distribution_parameters$price_elasticity = [0.01, 2]` (current launcher), the agent only explores **increases** in elasticity magnitude (factor 1.01×–3×).

---

## 9. Result storage

### SQLite: `gcam_sensitivity.sqlite`

| Table | One row per… | Main fields |
|---|---|---|
| `Experiments` | experiment | `experiment_id`, `project`, `gcam_version`, `name`, `number_iterations`, `description`, `created_at`, `inputs_xml`, `outputs_queries`, `regions`, `perturbation_strategy`, `distribution`, `distribution_parameters` (JSON) |
| `Runs` | GCAM run | `run_id`, `experiment_id`, `execution_time` (min), `execution_errors`, `delta`, `delta_logit`, `delta_price_elasticity`, `delta_satiation_level` |
| `Datasets` | Parquet file | `experiment_id`, `run_id`, `dataset_type` (`input`/`output`), `dataset_name`, `filepath`, `size_mb` |
| `RL_History` | run evaluated by the agent | `run_id`, `worker_suffix`, `step`, `mode`, deltas, `MAE_run`, `MAE_ref`, `n_obs`, `reward`, policy mean and sigma by type |

### Parquet: `Experiments/`

```
Experiments/
└── EXP_xxxxxxxx/
    ├── inputs/
    │   └── RUN_yyyyyyyy.parquet          # parameters used in the run
    ├── outputs/
    │   └── outputs_by_tech/
    │       └── RUN_yyyyyyyy.parquet      # query output (selected columns + run_id)
    └── rl/                               # only for experiments with the agent
```

### Monitoring

`7_2_init_experiment_dfParams.R` writes to `monitoring/`:
- `steps_<worker>.csv`: start/end, duration, RSS and CPU of the R process for each stage.
- `iterations_<worker>.csv`: duration and status of each iteration.

RAM/CPU metrics are read from `/proc` and are only available on Linux (they are left empty on Windows).

---

## 10. Querying and maintaining experiments (`R/Storage/`)

```r
library(DBI); library(RSQLite)
source("R/Storage/explore_dataBase.R")
source("R/Storage/manageExperiments.R")
con <- dbConnect(SQLite(), "gcam_sensitivity.sqlite")

dbReadTable(con, "Experiments")
inputs  <- read_experiment_inputs(con, "EXP_xxxxxxxx")
outputs <- read_experiment_output(con, experiment_id = "EXP_xxxxxxxx", query_name = "outputs_by_tech")
one_run <- read_run_output(con, query_name = "outputs_by_tech", run_id = "RUN_yyyyyyyy")
```

Maintenance (most functions default to `dry_run = TRUE`: review first, then run with `FALSE`):

| Function | Purpose |
|---|---|
| `check_experiment_integrity()` | Checks that registered Parquet files exist and can be read. |
| `clean_empty_experiments()` | Removes experiments with no valid runs. |
| `delete_experiment()` | Deletes an experiment from SQLite (and optionally its files). |
| `clean_orphan_experiments()` | Finds/deletes folders in `Experiments/` with no record in SQLite. |
| `update_number_iterations()` | Recomputes `number_iterations` from `Runs` (useful after an interrupted experiment). |
| `merge_experiments()` | Merges **equivalent** experiments (same GCAM version, XMLs, queries, regions, strategy and distribution) into a new one. |

`R/Storage/example of use.R` has examples for all of them.

---

## 11. Data versioned with DVC

```bash
dvc pull      # fetches Experiments/ and gcam_sensitivity.sqlite
# after new experiments:
dvc add Experiments gcam_sensitivity.sqlite
git add Experiments.dvc gcam_sensitivity.sqlite.dvc
dvc push
```

`.dvc/config` has no remote configured in this repository: add one (`dvc remote add -d …`) before `push`/`pull`.

---

## 12. Things to be aware of

Details of the current code worth knowing before running or interpreting experiments:

- **Duplicate definitions: the last one wins.**
  - `introduce_heterogeneous_uncertainty_by_type` is defined twice in `4_introduceUncertainty.R`. The second one (the one actually used) samples **absolute values** for `satiation_level` too; the first one treated them as log-uniform **multipliers** of the default value, by group. With an absolute `satiation_level ∈ [0.001, 3]`, the original scale of each satiation level is ignored.
  - `create_new_run_gcam` is defined twice in `0_mainFunctions.R`. The one used creates a **`.bat` with a hard-coded path** `C:/GCAM/Nacho/gcam_europe/exe/`; the `.sh` version for Linux/HPC is overridden.
- **Hard-coded paths**: `xmldb_batch.xml` has an absolute Windows `outFile` (only regenerated when `alreadyPrepeared = F`), and `runSensParam_pretrained.R` uses `C:/GCAM/Nacho/...` paths.
- **Parallel workers on the same GCAM installation**: the suffix isolates the configuration, `.bat` and XMLs, but all workers share `data/<query>_0.csv` (the batch-query output), `exe/logs/main_log.txt` and the CSV clean-up in `data/`. Use one copy of GCAM (and of the working directory) per worker, or check that they don't overwrite each other.
- **Error detection**: `execution_errors` is based on searching for "error" in the log. It can give false positives/negatives; runs with errors **are still saved**, so filter them at analysis time (rather than silently dropping them, to avoid selection bias).
- **Sign convention**: `rl_evaluate_run()` computes `error = value_ref − value_run` (observed − model), the opposite of the `ŷ − y` convention in the methodology document. Only the sign is affected; MAE is unchanged.
- **Fixed year**: perturbations are inserted with `year = 2021` and evaluation uses the `2021` column.
- **`runSensAn_allParams_deltas.R` with `optimizer = 'random'`** would fail, because `introduce_heterogeneous_uncertainty_by_delta` requires all three types in `distribution_parameters` and the launcher only defines `price_elasticity`.
- **`run_merge_experiments.R`** calls `source('merge_experiments.R')`, which does not exist: `merge_experiments()` lives in `manageExperiments.R`.
- **`others.R`** contains copies of functions; no loop loads it.
- `alreadyPrepeared` (sic) is the actual argument name.

---

## 13. How it fits into the wider project

- **Input**: the parameter table and the reference hindcasting errors come from the `Hindcasting` repo/folder (Phases 1–2).
- **Output**: the input/output Parquet files and the SQLite catalogue are the basis for sensitivity analysis, PCA, surrogate models (GAM, XGBoost…) and calibration (Phases 3–5).
- **Closed loop**: configurations proposed by a surrogate are re-run in GCAM with `runSensParam_pretrained.R`, so the error that counts is always GCAM's, not the one predicted by the surrogate.

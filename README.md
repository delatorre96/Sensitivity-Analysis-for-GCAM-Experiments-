# Sensitivity Analysis for GCAM Experiments

Framework en R para lanzar **experimentos de incertidumbre paramétrica sobre GCAM-Europe**, guardar de forma trazable los parámetros y las salidas de cada ejecución, y (opcionalmente) **buscar configuraciones que reduzcan el error de hindcasting de 2021** con un agente de reinforcement learning.

Forma parte del proyecto *Hindcasting and evaluation of GCAM-Europe* (BC3). En la arquitectura del proyecto corresponde sobre todo a la **Fase 3 (incertidumbre y sensibilidad)** y alimenta las **Fases 4–5 (modelos sustitutos y calibración)**.

---

## 1. Qué hace, en una frase

Para cada iteración: **perturba** logits, elasticidades de precio y/o niveles de saciedad en los XML de entrada de GCAM → **ejecuta GCAM** → extrae la query de interés (por defecto `outputs by tech`) → guarda **inputs y outputs en Parquet** → registra todo en un **catálogo SQLite** (`gcam_sensitivity.sqlite`).

```
df_allParams.csv ──► perturbación ──► XML *_<suffix>.xml ──► GCAM (configuration<suffix>.xml)
                                                                     │
                                                    batch query (ModelInterface)
                                                                     ▼
 gcam_sensitivity.sqlite ◄── metadatos ── Experiments/<EXP_id>/{inputs,outputs}/…/<RUN_id>.parquet
```

---

## 2. Estructura del repositorio

```
.
├── runSensAn_allParams_monteCarlo_debug.R   # Lanzador: Monte Carlo global (muestreo uniforme absoluto)
├── runSensAn_allParams_deltas.R             # Lanzador: deltas relativos + agente RL (o muestreo aleatorio)
├── runSensParam_pretrained.R                # Lanzador: evaluar configuraciones fijas (p. ej. propuestas por el GAM)
│
├── R/
│   ├── Experiment/                          # Pipeline de ejecución (numerado por etapa)
│   │   ├── 0_mainFunctions.R                # Paquetes, rutas de GCAM, config/.bat por worker, run_gcam()
│   │   ├── 1_create_dataBase.R              # Esquema SQLite (Experiments, Runs, Datasets)
│   │   ├── 2_PrepareGCAM.R                  # Prepara las batch queries de ModelInterface
│   │   ├── 3_createDF_paramsXML.R           # Extrae parámetros de los XML y construye la caché de líneas
│   │   ├── 4_introduceUncertainty.R         # Estrategias de perturbación
│   │   ├── 5_createNewXml.R                 # Escribe los XML perturbados
│   │   ├── 6_appendResults.R                # Guarda Parquet y registra en SQLite
│   │   ├── 7_init_experiment.R              # (legado) bucle original, solo logits
│   │   ├── 7_1_init_experiment_dfParams.R   # Bucle con optimizer = 'rl' | 'random'
│   │   ├── 7_2_init_experiment_dfParams.R   # Bucle Monte Carlo + monitorización de CPU/RAM
│   │   ├── 7_2_init_experiment_dfParams_withoutUncer.R  # Bucle sin perturbación (configs predefinidas)
│   │   ├── 8_reinforcementLearning.R        # Agente REINFORCE (policy gradient gaussiano)
│   │   └── others.R                         # Copias/borradores de funciones (no se carga en el pipeline)
│   └── Storage/                             # Consulta y mantenimiento de resultados
│       ├── explore_dataBase.R               # read_experiment_inputs / read_experiment_output / read_run_output
│       ├── manageExperiments.R              # merge, integridad, limpieza y borrado de experimentos
│       ├── example of use.R                 # Ejemplos de uso de las funciones de Storage
│       └── run_merge_experiments.R          # Script para fusionar experimentos equivalentes
│
├── files/                                   # Plantillas de ModelInterface
│   ├── allQueries.xml                       # Catálogo completo de queries de GCAM
│   ├── xmldb_batch.xml                      # Batch file (se reescribe en la preparación)
│   ├── XMLDBDriver.properties               # Se copia a gcam/exe: BD en memoria + batch queries
│   └── query.xml, resource_*.xml            # Queries de ejemplo
│
├── Experiments.dvc                          # Datos versionados con DVC (Experiments/, ~300 MB)
├── gcam_sensitivity.sqlite.dvc              # Catálogo SQLite versionado con DVC
├── renv.lock, renv/, .Rprofile              # Entorno R reproducible (renv)
└── GCAM_sensitivity_analysis.Rproj          # Raíz del proyecto para here::here()
```

`Experiments/`, `data/`, `gcam_sensitivity.sqlite`, CSV, RDS, etc. están en `.gitignore`: los datos pesados se versionan con **DVC**, no con git.

---

## 3. Requisitos

- **R** (renv está configurado con R 4.5 en Windows; en DIPC se ha usado el entorno conda `r44`).
- **GCAM-Europe** compilado, con `exe/configuration.xml`, `exe/run-gcam.bat` (Windows) y los XML generados en `input/gcamdata/xml/`. La versión se registra automáticamente con `git describe --tags` sobre el repo de GCAM, así que **GCAM debe ser un repositorio git con tags**.
- **Java** (para ModelInterface / batch queries de GCAM).
- **DVC** (opcional) para descargar `Experiments/` y `gcam_sensitivity.sqlite`.
- Ficheros externos al repo, referenciados con rutas relativas:
  - `../gcam_europe` — instalación de GCAM.
  - `../Hindcasting/4_SensitivityAnalysis/create_dfParams/df_allParams.csv` — tabla de parámetros (ver §5).
  - `../Hindcasting/2. Extraction/Data/all_errors_output_by_tech.csv` — errores del modelo base frente a 2021 (solo para RL / seguimiento de MAE).

Instalación del entorno:

```r
renv::restore()           # instala las versiones de renv.lock
```

`check_packages()` instala además cualquier paquete que falte de: DBI, RSQLite, XML, xml2, uuid, dplyr, arrow, jsonlite, purrr, tibble, stringr (se usan también `here` y `withr`).

---

## 4. Cómo lanzar un experimento

**Siempre desde la raíz del repositorio** (las rutas se resuelven con `here::here()` y `getwd()`):

```bash
Rscript runSensAn_allParams_monteCarlo_debug.R NULL _w1
#                                              │    └── suffix del worker
#                                              └────── experiment_id (NULL = experimento nuevo)
```

Argumentos:

| Argumento | Significado |
|---|---|
| `experiment_id` | `NULL` crea un experimento nuevo (`EXP_xxxxxxxx`). Un id existente **añade runs** a ese experimento (debe existir en el SQLite). |
| `suffix` | Identificador del worker. Se usa para generar `configuration<suffix>.xml`, `run-gcam<suffix>.bat` y los XML perturbados `<nombre><suffix>.xml`, de modo que varios procesos no sobrescriban los XML originales ni los de otro worker. También nombra los ficheros de monitorización. |

Para paralelizar, se lanza el primer worker con `NULL`, se toma el `EXP_…` creado y se lanzan los demás con ese id y sufijos distintos (`_w2`, `_w3`, …).

### Los tres lanzadores

| Script | Bucle que usa | Estrategia | Uso típico |
|---|---|---|---|
| `runSensAn_allParams_monteCarlo_debug.R` | `7_2_init_experiment_dfParams.R` | `introduce_heterogeneous_uncertainty_by_type`: cada parámetro recibe un valor **absoluto** independiente ~ U(min, max) según su tipo | Exploración global del espacio paramétrico (Monte Carlo) |
| `runSensAn_allParams_deltas.R` | `7_1_init_experiment_dfParams.R` | `optimizer = 'rl'`: el agente propone un **delta relativo por tipo de parámetro**; `optimizer = 'random'`: `introduce_heterogeneous_uncertainty_by_delta` | Calibración / búsqueda dirigida que minimiza el MAE |
| `runSensParam_pretrained.R` | `7_2_init_experiment_dfParams_withoutUncer.R` | Sin perturbación: ejecuta cada `param_config` de un CSV de parámetros ya fijados | Validar en GCAM las configuraciones propuestas por un sustituto (GAM) |

Los parámetros del experimento se editan **dentro del propio lanzador** (no por línea de comandos): `gcam_path`, `xml_files`, `regions_of_interest`, `n_iterations`, `queries_of_interest`, `distribution_parameters`, `interested_query_columns`, `df_params_path`, nombre y descripción del experimento, etc.

---

## 5. La tabla de parámetros (`df_allParams.csv`)

Es la entrada central: **una fila por parámetro perturbable** de los XML de GCAM. Se construye fuera de este repo (en `../Hindcasting/4_SensitivityAnalysis/create_dfParams/`) con las funciones de `3_createDF_paramsXML.R`:

- `st2_extract_logits_anyXML()` → `<logit-exponent>` (con región, supplysector, subsector, nesting-subsector, nivel, `fillout`, año).
- `st2_extract_price_elasticity_anyXML()` → `<price-elasticity>`.
- `st2_extract_satiation_level()` → `<satiation-level>` de edificios, agrupado en `floorspace`, `heating`, `cooling`, `other_services`.
- `add_occurrence_index()` → añade `tag` y `occ` (qué ocurrencia de esa etiqueta es dentro del fichero).

Columnas que usa el pipeline: `xml_file`, `destination_file`, `type_of_param` (`logit` | `price_elasticity` | `satiation_level`), `param`, `param_default`, `tag`, `occ`, `xpath`, `region`, `year`, `fillout`, `group` (satiation) y, para configuraciones predefinidas, `param_config`.

`destination_file` se genera con sufijo `_cal.xml`, que el bucle sustituye por `<suffix>.xml` al arrancar.

---

## 6. Qué ocurre en cada iteración

1. **Preparación (una vez por worker)**
   - `set_gcam_paths()` fija rutas globales de GCAM (`exe/`, `configuration.xml`, `gcamdata/xml`, log).
   - Si no existe `gcam_sensitivity.sqlite`, se crea (`create_database()`).
   - Si `alreadyPrepeared = F`, `GCAM_preparation()` genera las queries a partir de `files/allQueries.xml`, reescribe `xmldb_batch.xml`, y copia todo a `gcam/exe/batch_queries/` junto con `XMLDBDriver.properties`. Con `T` se asume que ya está hecho.
   - Si el experimento es nuevo: `write_experiment_info()` (tabla `Experiments`) y `create_experiment_folders()`.
   - `create_new_config()` crea `configuration<suffix>.xml` apuntando a los XML con sufijo; `create_new_run_gcam()` crea `run-gcam<suffix>.bat`.
   - `build_xml_cache()` lee una sola vez los XML originales en memoria y localiza la **línea** de cada parámetro. Comprueba que el valor de esa línea coincide con `param_default`; si no, se detiene (señal de que el XML ha cambiado desde que se generó `df_params`).

2. **Bucle (`n_iterations`)**
   1. Genera `run_id = RUN_xxxxxxxx`.
   2. **Perturbación** con la estrategia elegida (o propuesta del agente RL).
   3. **Escritura de XML** con `createNewXml_fast()`, que trabaja sobre líneas de texto (mucho más rápido que reescribir con xml2):
      - `satiation-level`: se **sustituye** la línea.
      - `logit-exponent` / `price-elasticity`: se **inserta** una nueva línea con `year="2021"` justo después de la original, de modo que GCAM usa el valor perturbado a partir de 2021.
   4. **Ejecuta GCAM** (`run_gcam()`; `cmd.exe` en Windows, `bash` en Linux).
   5. Marca `execution_errors = TRUE` si la palabra "error" aparece en `exe/logs/main_log.txt`.
   6. Guarda los **inputs** (`save_inputs_parquet()`) y los **outputs** de las batch queries (`save_run_outputs()`, solo las columnas de `interested_query_columns`).
   7. Registra los ficheros en `Datasets`, borra los CSV intermedios de `data/`, registra la ejecución en `Runs` y actualiza `number_iterations`.
   8. (Solo `7_1`, si existe el fichero de referencia) calcula el MAE del run, la recompensa y actualiza el agente RL.

---

## 7. Estrategias de perturbación (`4_introduceUncertainty.R`)

| Función | Qué hace |
|---|---|
| `introduce_heterogeneous_uncertainty_by_type` | Valor **absoluto** independiente por parámetro: `runif(minVal, maxVal)` según `type_of_param`. Es la usada en Monte Carlo. |
| `introduce_heterogeneous_uncertainty_by_delta` | Un **delta relativo común por tipo**: `param × (1 + δ_tipo)`, re-muestreando δ hasta respetar los signos (logit < 0, elasticidad < 0, saciedad > 0). Requiere `minVal > −1` y los tres tipos en `distribution_parameters`. |
| `introduce_aditive_uncertainty` | Un único delta para toda la columna, con restricción de signo. |
| `introduce_aditive_Latin_HyperCube_uncertainty` | Deltas equiespaciados entre `max_val` y `min_val` según la iteración. |
| `introduce_aditive_heterogeneous_uncertainty_satiation` | Delta independiente por fila; para satiation usa el rango observado en `df_params`. |
| `introduce_hierarchical_uncertainty` | Factor multiplicativo común ~ U(1 − u, 1 + u). |

`distribution_parameters` se pasa como lista por tipo, p. ej.:

```r
distribution_parameters = list(
  logit            = list(minVal = -20,   maxVal = -0.01),
  price_elasticity = list(minVal = -1.5,  maxVal = -0.01),
  satiation_level  = list(minVal = 0.001, maxVal = 3)
)
```

Se serializa como JSON en la tabla `Experiments`, así que cada experimento conserva los rangos con que se generó.

---

## 8. Agente de reinforcement learning (`8_reinforcementLearning.R`)

Planteado como un **bandit continuo**: cada run es un episodio de un paso.

- **Acción**: un vector de deltas relativos, uno por tipo de parámetro en `rl_param_types`. **Actualmente solo `price_elasticity`** (logit y satiation están comentados).
- **Política**: gaussiana en un espacio no acotado `u ~ N(m, s²)`, transformada con sigmoide al intervalo `[minVal, maxVal]`, por lo que los deltas siempre respetan los límites.
- **Recompensa**: `log(MAE_ref / MAE_run)` (o relativa), recortada a `[-3, 3]`; `-1` si GCAM falla o no hay filas comparables. `MAE_ref` y `MAE_run` se calculan sobre **las mismas filas** (unión por `region, sector, subsector, output, technology`) con el valor de 2021.
- **Aprendizaje**: REINFORCE por lotes (`batch_size`), baseline leave-one-out, ventajas normalizadas y Adam sobre `(m, log s)`; `s` decrece hasta `min_sigma`.
- **Modos**: `train` (explora y aprende), `exploit` (usa la media de la política) y `observe` (con `optimizer = 'random'`: solo registra MAE).
- **Persistencia**: estado en `Experiments/<EXP>/rl/agent<suffix>.rds` (+ `_history.csv`); se reanuda si existe (`resume = TRUE`). Historial también en la tabla SQLite `RL_History`.

Con `distribution_parameters$price_elasticity = [0.01, 2]` (lanzador actual), el agente solo explora **aumentos** de la magnitud de las elasticidades (factor 1.01×–3×).

---

## 9. Almacenamiento de resultados

### SQLite: `gcam_sensitivity.sqlite`

| Tabla | Una fila por… | Campos principales |
|---|---|---|
| `Experiments` | experimento | `experiment_id`, `project`, `gcam_version`, `name`, `number_iterations`, `description`, `created_at`, `inputs_xml`, `outputs_queries`, `regions`, `perturbation_strategy`, `distribution`, `distribution_parameters` (JSON) |
| `Runs` | ejecución de GCAM | `run_id`, `experiment_id`, `execution_time` (min), `execution_errors`, `delta`, `delta_logit`, `delta_price_elasticity`, `delta_satiation_level` |
| `Datasets` | fichero Parquet | `experiment_id`, `run_id`, `dataset_type` (`input`/`output`), `dataset_name`, `filepath`, `size_mb` |
| `RL_History` | run evaluado por el agente | `run_id`, `worker_suffix`, `step`, `mode`, deltas, `MAE_run`, `MAE_ref`, `n_obs`, `reward`, media y sigma de la política por tipo |

### Parquet: `Experiments/`

```
Experiments/
└── EXP_xxxxxxxx/
    ├── inputs/
    │   └── RUN_yyyyyyyy.parquet          # parámetros usados en el run
    ├── outputs/
    │   └── outputs_by_tech/
    │       └── RUN_yyyyyyyy.parquet      # salida de la query (columnas seleccionadas + run_id)
    └── rl/                               # solo experimentos con agente
```

### Monitorización

`7_2_init_experiment_dfParams.R` escribe en `monitoring/`:
- `steps_<worker>.csv`: inicio/fin, duración, RSS y CPU del proceso R por cada etapa.
- `iterations_<worker>.csv`: duración y estado de cada iteración.

Las métricas de RAM/CPU leen `/proc` y solo están disponibles en Linux (en Windows quedan vacías).

---

## 10. Consultar y mantener los experimentos (`R/Storage/`)

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

Mantenimiento (casi todas tienen `dry_run = TRUE` por defecto: primero revisar, luego ejecutar con `FALSE`):

| Función | Uso |
|---|---|
| `check_experiment_integrity()` | Comprueba que los Parquet registrados existen y se pueden leer. |
| `clean_empty_experiments()` | Elimina experimentos sin runs válidos. |
| `delete_experiment()` | Borra un experimento del SQLite (y opcionalmente sus ficheros). |
| `clean_orphan_experiments()` | Detecta/borra carpetas en `Experiments/` sin registro en el SQLite. |
| `update_number_iterations()` | Recalcula `number_iterations` a partir de `Runs` (útil tras interrumpir un experimento). |
| `merge_experiments()` | Fusiona experimentos **equivalentes** (misma versión de GCAM, XML, queries, regiones, estrategia y distribución) en uno nuevo. |

`R/Storage/example of use.R` contiene ejemplos de todas ellas.

---

## 11. Datos versionados con DVC

```bash
dvc pull      # descarga Experiments/ y gcam_sensitivity.sqlite
# tras nuevos experimentos:
dvc add Experiments gcam_sensitivity.sqlite
git add Experiments.dvc gcam_sensitivity.sqlite.dvc
dvc push
```

`.dvc/config` no tiene ningún remoto configurado en este repositorio: hay que añadirlo (`dvc remote add -d …`) antes de `push`/`pull`.

---

## 12. Cosas a tener en cuenta

Detalles del código actual que conviene conocer antes de lanzar o interpretar experimentos:

- **Definiciones duplicadas: la última es la que vale.**
  - `introduce_heterogeneous_uncertainty_by_type` está definida dos veces en `4_introduceUncertainty.R`. La segunda (la que se usa) muestrea **valores absolutos** también para `satiation_level`; la primera los trataba como **multiplicadores** log-uniformes del valor por defecto, por grupo. Con `satiation_level ∈ [0.001, 3]` absoluto, se ignora la escala original de cada saciedad.
  - `create_new_run_gcam` está definida dos veces en `0_mainFunctions.R`. La que se usa crea un **`.bat` con ruta fija** `C:/GCAM/Nacho/gcam_europe/exe/`; la versión `.sh` para Linux/HPC queda sobrescrita.
- **Rutas fijas**: `xmldb_batch.xml` tiene un `outFile` absoluto de Windows (se regenera solo si `alreadyPrepeared = F`), y `runSensParam_pretrained.R` usa rutas `C:/GCAM/Nacho/...`.
- **Workers en paralelo sobre la misma instalación de GCAM**: el sufijo aísla configuración, `.bat` y XML, pero todos los workers comparten `data/<query>_0.csv` (salida de la batch query), `exe/logs/main_log.txt` y la limpieza de CSV de `data/`. Conviene usar una copia de GCAM (y del directorio de trabajo) por worker o comprobar que no se pisan.
- **Detección de errores**: `execution_errors` se basa en buscar "error" en el log. Puede dar falsos positivos/negativos; los runs con error **se guardan igualmente**, así que hay que filtrarlos al analizar (y no descartarlos sin más, para evitar sesgo de selección).
- **Convención de signo**: `rl_evaluate_run()` calcula `error = value_ref − value_run` (observado − modelo), la contraria a `ŷ − y` del documento metodológico. Solo afecta al signo; el MAE no cambia.
- **Año fijo**: la perturbación inserta valores con `year = 2021` y la evaluación usa la columna `2021`.
- **`runSensAn_allParams_deltas.R` con `optimizer = 'random'`** fallaría, porque `introduce_heterogeneous_uncertainty_by_delta` exige los tres tipos en `distribution_parameters` y el lanzador solo define `price_elasticity`.
- **`run_merge_experiments.R`** hace `source('merge_experiments.R')`, que no existe: `merge_experiments()` está en `manageExperiments.R`.
- **`others.R`** son copias de funciones; no lo carga ningún bucle.
- `alreadyPrepeared` (sic) es el nombre real del argumento.

---

## 13. Relación con el resto del proyecto

- **Entrada**: la tabla de parámetros y los errores de referencia del hindcasting vienen del repo/carpeta `Hindcasting` (Fases 1–2).
- **Salida**: los Parquet de inputs/outputs y el catálogo SQLite son la base para el análisis de sensibilidad, PCA, modelos sustitutos (GAM, XGBoost…) y calibración (Fases 3–5).
- **Bucle cerrado**: las configuraciones propuestas por un sustituto se vuelven a ejecutar en GCAM con `runSensParam_pretrained.R`, de modo que el error que cuenta es siempre el de GCAM y no el predicho por el sustituto.

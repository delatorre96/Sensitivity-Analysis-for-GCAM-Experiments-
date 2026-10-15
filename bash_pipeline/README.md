# Loop de sensibilidad de GCAM en Bash

**Bash controla el loop**, **R solo genera los XML** de cada iteración, y **GCAM ejecuta el modelo y, al terminar, lanza él mismo la consulta de ModelInterface** (vía `XMLDBDriver.properties`).

| Fichero | Función |
|---|---|
| `run_sensitivity_bash.sh` | Loop secuencial, comprobaciones, logs, códigos de salida |
| `generate_iteration_xml.R` | Muestrea parámetros y escribe los XML de **una** iteración (solo R base) |
| `sensitivity_config.R` | Rangos científicos y qué funciones del repo se reutilizan |
| `lib_pipeline.R` | Utilidades: argumentos y `load_functions()` |
| `prepare_suffix_files.R` | Crea/comprueba `configuration<suffix>.xml` y `run-gcam<suffix>.sh` con `create_new_config()` / `create_new_run_gcam()` |
| `make_batch_xml.R` | Copia de `xmldb_batch.xml` cambiando solo `<outFile>` del `<command>` de la consulta (R base, verificado) |
| `slurm_sensitivity.sbatch` | Lanzamiento dentro de Slurm |

## Qué código existente se reutiliza

`generate_iteration_xml.R` no hace `source()` de los ficheros de `R/Experiment/`; con `load_functions()` carga **solo la definición** de estas funciones, sin ejecutar `library()` ni código suelto (así no necesita renv, dplyr, xml2 ni here):

| Función | Fichero |
|---|---|
| `build_xml_cache()` | `3_createDF_paramsXML.R` |
| `introduce_heterogeneous_uncertainty_by_type()` | `4_introduceUncertainty.R`, **definición nº 1** |
| `createNewXml_fast()`, `write_xml_fast()`, `fmt_num()` | `5_createNewXml.R` |

> **Atención, decisión científica pendiente.** `4_introduceUncertainty.R` define `introduce_heterogeneous_uncertainty_by_type()` **dos veces**:
> 1. satiation = `param_default` × multiplicador log-uniforme por `group`, `signif(., 6)`. Es la descrita en la especificación y **la que se usa aquí**.
> 2. satiation ~ U(minVal, maxVal) **absoluta**, `round(., 3)`. Es la que ganaba en `init_experiment()`, porque `source()` deja la última definición.
>
> Con los rangos de `runSensAn_allParams_monteCarlo.R` (`satiation_level` 0.001–3), la nº 1 da multiplicadores entre ×0.001 y ×3 (mediana ≈ ×0.055). Revisa si ese rango es el que quieres para un multiplicador. Para volver a la nº 2: `occurrence = 2L, must_contain = NULL` en `sensitivity_config.R`.
>
> `building_det_EUR.xml` **no** se excluye, igual que en `init_experiment()` (allí el filtro está comentado).

## Cómo funciona una iteración

1. `iter_NNN/.start_marker`, con la semilla registrada.
2. **R** (`Rscript --vanilla`): borra los `*<suffix>.xml` anteriores, lee los XML **originales** (`build_xml_cache()` comprueba que coinciden con `param_default`), muestrea con `set.seed(semilla)` y escribe con `createNewXml_fast()`. Después valida cada fichero de forma independiente: el número de líneas, cada valor en su línea y que ninguna otra línea haya cambiado. Escribe `r_status.txt = OK` solo al final.
3. **Bash** comprueba `r_status.txt`, el manifiesto, que los XML existen y son posteriores al marcador, y que su md5 difiere del original.
4. **Bash** genera `iter_NNN/xmldb_batch.xml` (`outFile = iter_NNN/outputs_by_tech.partial.csv`) y lo instala con copia + `mv` atómico en `exe/batch_queries/xmldb_batch.xml`.
5. **GCAM**: `cd exe && bash run-gcam<suffix>.sh`. El ejecutable vuelca los resultados en la base de datos en memoria y ejecuta el batch.
6. **Bash** comprueba:
   - el código de salida;
   - que `logs/main_log.txt` se ha reescrito en esta iteración;
   - que contiene `Model run completed`.

   Copia los logs a `iter_NNN/gcam_logs/`.
7. **Bash** valida el CSV:
   - existe, no está vacío y es posterior al marcador;
   - no contiene `had error` ni `no results`;
   - tiene una cabecera con `region` y `2021`, y al menos una fila;
   - no es idéntico al anterior.

   Solo entonces lo mueve a `data/<EXP><suffix>/outputs_by_tech_NNN.csv`.
8. Se añade una fila a `iterations.csv`. Al salir (también con error, Ctrl-C o `scancel`) se restaura el `xmldb_batch.xml` original.

Estados: `OK`, `OK_UNSOLVED`, `XML_ONLY`, `FAILED_R`, `FAILED_BATCH`, `FAILED_GCAM`, `FAILED_EXPORT`, `FAILED_UNSOLVED`, `INTERRUPTED`. Por defecto el loop **se detiene en el primer fallo**. Un CSV que no supera la validación nunca llega a `data/`: se queda en `iter_NNN/` como `*.invalid.csv`, `*.gcam_failed.csv` u otro similar, para poder diagnosticarlo.

## Estructura de salida

```
logs_bash/EXP_c9b80e40_999/
├── iterations_all_runs.csv            # acumulado de todas las ejecuciones Bash
└── bash_20261014T183152_12345/        # una ejecución Bash (run_tag ≠ experiment_id)
    ├── run.log  events.csv  iterations.csv
    ├── configuration_999.xml  run-gcam_999.sh  XMLDBDriver.properties
    ├── sensitivity_config.R  xmldb_batch.original.xml
    └── iter_001/
        ├── r_generate.log r_meta.csv r_status.txt r_time.txt
        ├── params_used.csv satiation_multipliers.csv xml_manifest.csv functions_used.csv
        ├── xmldb_batch.xml make_batch.log
        └── gcam_stdout.log gcam_time.txt gcam_logs/{main_log.txt,batch_queries.log}
data/EXP_c9b80e40_999/
    outputs_by_tech_001.csv  params_used_001.csv  satiation_multipliers_001.csv ...
```

Columnas de `iterations.csv`: `run_tag, experiment_id, suffix, iteration, seed, start_time, end_time, t_xml_s, t_gcam_s, t_export_s, t_total_s, exit_r, exit_gcam, exit_export, n_xml, gcam_error_lines, gcam_unsolved_lines, maxrss_r_kb, maxrss_gcam_kb, csv_rows, csv_md5, status, csv_file, error_message`.

- `t_gcam_s` **incluye** la consulta de ModelInterface, porque la lanza gcam.exe al terminar.
- `t_export_s` y `exit_export` corresponden a la validación del CSV, no a un proceso Java aparte.
- `maxrss_r_kb` y `maxrss_gcam_kb` se miden por separado con `/usr/bin/time -v`; quedan vacíos si no está instalado. Para el trabajo completo, usa `sacct`.
- `gcam_error_lines` sigue el mismo criterio que `init_experiment()` (líneas con "error" en `main_log.txt`). Es informativo.

## Pruebas

Todo desde `/scratch/gcamteam/hindcasting/GCAM_sensitivity_analysis`, después de `git pull`. GCAM se ejecuta **en un nodo de cómputo** (`salloc` / `srun --pty bash`), no en el nodo de login.

### 0. Comprobaciones previas (no ejecuta GCAM)

```bash
bash bash_pipeline/run_sensitivity_bash.sh EXP_c9b80e40 1 _999 --check-only
# (añadir --prepare solo si hay que regenerar configuration_999.xml / run-gcam_999.sh; necesita xml2)
cat $(ls -td logs_bash/EXP_c9b80e40_999/bash_* | head -1)/run.log
```

En `run.log` revisa:
- la versión de R y de xml2, y `batch-queries` / `in-memory`;
- la línea de `run-gcam_999.sh` que llama a `gcam.exe`. Si no es la última orden aparece un AVISO, porque el script podría ocultar el código de salida.

### 1. Solo XML (sin GCAM)

```bash
bash bash_pipeline/run_sensitivity_bash.sh EXP_c9b80e40 3 _999 --xml-only --seed-base 1000
R=$(ls -td logs_bash/EXP_c9b80e40_999/bash_* | head -1)
cat $R/iterations.csv
cat $R/iter_001/r_generate.log      # funciones usadas, tiempos, nº de parámetros cambiados
cat $R/iter_001/functions_used.csv
for i in 1 2 3; do cut -d, -f2,5,6 $R/iter_00$i/xml_manifest.csv | sed -n 2,3p; done   # md5 distintos
```

### 2. Una iteración completa

```bash
bash bash_pipeline/run_sensitivity_bash.sh EXP_c9b80e40 1 _999 --seed-base 1000
R=$(ls -td logs_bash/EXP_c9b80e40_999/bash_* | head -1)
cat $R/iterations.csv; cat $R/events.csv
grep -i 'configuration\|completed' $R/iter_001/gcam_logs/main_log.txt | head
tail -5 $R/iter_001/gcam_logs/batch_queries.log
head -4 data/EXP_c9b80e40_999/outputs_by_tech_001.csv
```

**Comprueba en esta prueba** que `Model run completed` aparece en el `main_log.txt` de una ejecución correcta de vuestra versión de GCAM. Si la frase es otra, ajústala con `GCAM_SUCCESS_PATTERN="..."`, o déjala vacía (`GCAM_SUCCESS_PATTERN=`) para no comprobarla. Haz lo mismo con `UNSOLVED_PATTERN` para los periodos no resueltos. Si la cabecera del CSV no tiene `region` y `2021`, ajusta `REQUIRED_HEADER_COLS`.

### 3. Tres iteraciones

```bash
bash bash_pipeline/run_sensitivity_bash.sh EXP_c9b80e40 3 _999 --start 2 --seed-base 1000
R=$(ls -td logs_bash/EXP_c9b80e40_999/bash_* | head -1)
cut -d, -f4,5,11,22 $R/iterations.csv                   # estado OK
md5sum data/EXP_c9b80e40_999/outputs_by_tech_00{1,2,3}.csv  # tres hashes distintos
md5sum data/EXP_c9b80e40_999/params_used_00{1,2,3}.csv
```

El script no sobrescribe CSV finales existentes. Usa `--start`, otro sufijo o `--overwrite`.

### 4. Experimento completo en Slurm

```bash
mkdir -p logs_bash
sbatch bash_pipeline/slurm_sensitivity.sbatch EXP_c9b80e40 100 _999 --seed-base 10000
squeue -u $USER
tail -f $(ls -td logs_bash/EXP_c9b80e40_999/bash_* | head -1)/run.log
sacct -j <JOBID> --format=JobID,Elapsed,MaxRSS,State,ExitCode
```

Para reanudar tras un fallo o un corte: `... EXP_c9b80e40 100 _999 --start 37 --seed-base 10000`. Con `--seed-base`, la iteración *i* usa siempre la semilla `10000 + i`, así que es reproducible.

## Opciones

```
--start N / --end N      rango de iteraciones
--seed-base N            semilla = N + iteración (reproducible); sin ella, aleatoria y registrada
--continue-on-error      no detener tras un fallo
--unsolved-policy flag|fail
--prepare                regenerar configuration<suffix>.xml y run-gcam<suffix>.sh
--overwrite              permitir sobrescribir CSV finales
--ignore-running-gcam    no abortar si ya hay procesos gcam.exe del usuario
--xml-only               generar y validar XML sin ejecutar GCAM
--check-only             solo comprobaciones previas
```

Variables de entorno: `RSCRIPT`, `GCAM_PATH`, `DF_PARAMS`, `QUERY_NAME`, `DATA_ROOT`, `LOG_ROOT`, `GCAM_SUCCESS_PATTERN`, `UNSOLVED_PATTERN`, `REQUIRED_HEADER_COLS`, `R_CONFIG`.

## Requisitos de R

- `generate_iteration_xml.R`: solo R base (≥ 4.1, porque los ficheros del repo usan `|>`).
- `make_batch_xml.R` y la comprobación de `prepare_suffix_files.R`: solo R base.
- Solo `--prepare` (que llama a `create_new_config()`) necesita **xml2**. Si `configuration<suffix>.xml` y `run-gcam<suffix>.sh` ya existen, no hace falta.
- Todo se ejecuta con `Rscript --vanilla`, así que `.Rprofile` y renv no se activan. Se usa `$HOME/.conda/envs/r44/bin/Rscript`, o el de la variable `RSCRIPT`.

## Concurrencia

Solo puede haber **un loop por directorio `exe/`** (lock con `flock` en `exe/.sensitivity_bash.lock`). `main_log.txt`, `batch_queries/xmldb_batch.xml` y `XMLDBDriver.properties` son compartidos por todo lo que se ejecuta en ese `exe/`. Además, el script aborta si encuentra procesos `gcam.exe` del usuario, por ejemplo workers de R antiguos todavía vivos. Para paralelizar más adelante, cada worker necesitará su propia copia de `exe/` y su propio sufijo.

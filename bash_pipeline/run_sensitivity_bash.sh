#!/usr/bin/env bash
# =============================================================================
# run_sensitivity_bash.sh
#
# Loop SECUENCIAL de sensibilidad de GCAM-Europe. Por iteración:
#   1. R genera parámetros y XML           (generate_iteration_xml.R)
#   2. Bash comprueba los XML              (r_status.txt, manifiesto, fechas)
#   3. Bash crea el batch de ModelInterface con el outFile de la iteración
#   4. GCAM: run-gcam<suffix>.sh -> gcam.exe -C configuration<suffix>.xml
#      Al terminar, el propio gcam.exe lanza ModelInterface sobre la base de
#      datos (XMLDBDriver.properties: batch-queries=batch_queries/xmldb_batch.xml)
#   5. Bash comprueba el código de salida y el main_log de GCAM
#   6. Bash valida el CSV y SOLO entonces lo mueve a su nombre final
#   7. Todo se registra en events.csv / iterations.csv tras cada etapa
#
# Uso (desde el directorio de trabajo, p. ej.
#      /scratch/gcamteam/hindcasting/GCAM_sensitivity_analysis):
#   bash bash_pipeline/run_sensitivity_bash.sh EXP_ID N_ITER SUFFIX [opciones]
#
#   bash bash_pipeline/run_sensitivity_bash.sh EXP_c9b80e40 1 _999 --check-only
#   bash bash_pipeline/run_sensitivity_bash.sh EXP_c9b80e40 3 _999 --xml-only --seed-base 1000
#   bash bash_pipeline/run_sensitivity_bash.sh EXP_c9b80e40 100 _999 --seed-base 1000
#
# Opciones:
#   --start N              primera iteración (defecto 1)
#   --end N                última iteración (defecto N_ITER)
#   --seed-base N          semilla = N + iteración (reproducible; recomendado).
#                          Sin ella: semilla aleatoria por iteración (se registra).
#   --continue-on-error    no detener el loop tras una iteración fallida
#   --unsolved-policy P    flag (defecto): periodos sin resolver -> OK_UNSOLVED
#                          fail: -> FAILED_UNSOLVED (el CSV no pasa a resultados)
#   --prepare              (re)crear configuration<suffix>.xml y run-gcam<suffix>.sh
#   --overwrite            permitir sobrescribir CSV finales existentes
#   --ignore-running-gcam  no abortar si ya hay procesos gcam.exe del usuario
#   --xml-only             solo generar y validar XML (no ejecuta GCAM)
#   --check-only           solo comprobaciones previas
#
# Variables de entorno (defecto):
#   RSCRIPT    ($HOME/.conda/envs/r44/bin/Rscript)
#   GCAM_PATH  (../gcam_europe)
#   DF_PARAMS  (../Hindcasting/4_SensitivityAnalysis/create_dfParams/df_allParams.csv)
#   QUERY_NAME (outputs_by_tech)  -> exe/batch_queries/<QUERY_NAME>.xml
#   DATA_ROOT  (data)   LOG_ROOT (logs_bash)
#   GCAM_SUCCESS_PATTERN ("Model run completed")  vacío = no comprobar
#   UNSOLVED_PATTERN     ("did not solve")
#   GCAM_UNSOLVED_EXIT_CODES ("1")  exit de gcam.exe aceptado si hay periodos sin resolver
#   REQUIRED_HEADER_COLS ("region,2021")
#   R_CONFIG   (bash_pipeline/sensitivity_config.R)
# =============================================================================

set -u
set -o pipefail
# Sin `set -e`: los códigos de salida se capturan, registran y gestionan a mano.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WORK_DIR="$(pwd -P)"

RSCRIPT="${RSCRIPT:-$HOME/.conda/envs/r44/bin/Rscript}"
GCAM_PATH="${GCAM_PATH:-../gcam_europe}"
DF_PARAMS="${DF_PARAMS:-../Hindcasting/4_SensitivityAnalysis/create_dfParams/df_allParams.csv}"
QUERY_NAME="${QUERY_NAME:-outputs_by_tech}"
DATA_ROOT="${DATA_ROOT:-data}"
LOG_ROOT="${LOG_ROOT:-logs_bash}"
GCAM_SUCCESS_PATTERN="${GCAM_SUCCESS_PATTERN-Model run completed}"
UNSOLVED_PATTERN="${UNSOLVED_PATTERN:-did not solve}"
GCAM_UNSOLVED_EXIT_CODES="${GCAM_UNSOLVED_EXIT_CODES:-1}"
REQUIRED_HEADER_COLS="${REQUIRED_HEADER_COLS:-region,2021}"
R_CONFIG="${R_CONFIG:-$SCRIPT_DIR/sensitivity_config.R}"

# ----------------------------------------------------------------------------
# Utilidades
# ----------------------------------------------------------------------------
ts()      { date '+%Y-%m-%d %H:%M:%S'; }
now()     { date +%s.%N; }
elapsed() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.1f", b-a}'; }
log()     { echo "[$(ts)] $*" | tee -a "${MAIN_LOG:-/dev/null}"; }
die()     { echo "[$(ts)] ERROR: $*" | tee -a "${MAIN_LOG:-/dev/null}" >&2; exit 1; }
csvq()    { local s="${1//\"/\'}"; s="${s//$'\n'/ | }"; printf '"%s"' "$s"; }
usage()   { sed -n '2,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }

# Ejecuta un comando midiendo tiempo/memoria con GNU time si existe.
# Devuelve el código de salida del propio comando.
run_timed() {
  local tf="$1"; shift
  if [[ -x /usr/bin/time ]] && /usr/bin/time -v true >/dev/null 2>&1; then
    /usr/bin/time -v -o "$tf" "$@"
  else
    "$@"
  fi
}
maxrss_kb() { [[ -f "$1" ]] && awk -F': ' '/Maximum resident set size/{print $2}' "$1" || true; }

# Campo n (1-based) de la línea 2 de un CSV sencillo escrito por R (sin comas internas)
csv_field() { awk -F, -v n="$2" 'NR==2{gsub(/"/,"",$n); print $n}' "$1" 2>/dev/null; }

# ----------------------------------------------------------------------------
# Argumentos
# ----------------------------------------------------------------------------
[[ $# -lt 3 ]] && usage
EXP_ID="$1"; N_ITER="$2"; SUFFIX="$3"; shift 3

START=1; END=""; SEED_BASE=""; ON_ERROR="stop"; UNSOLVED_POLICY="flag"
PREPARE=0; OVERWRITE=0; IGNORE_RUNNING=0; CHECK_ONLY=0; XML_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --start)               START="${2:-}"; shift 2 ;;
    --end)                 END="${2:-}"; shift 2 ;;
    --seed-base)           SEED_BASE="${2:-}"; shift 2 ;;
    --continue-on-error)   ON_ERROR="continue"; shift ;;
    --unsolved-policy)     UNSOLVED_POLICY="${2:-}"; shift 2 ;;
    --prepare)             PREPARE=1; shift ;;
    --overwrite)           OVERWRITE=1; shift ;;
    --ignore-running-gcam) IGNORE_RUNNING=1; shift ;;
    --xml-only)            XML_ONLY=1; shift ;;
    --check-only)          CHECK_ONLY=1; shift ;;
    -h|--help)             usage ;;
    *) echo "Opción desconocida: $1" >&2; usage ;;
  esac
done
END="${END:-$N_ITER}"

[[ "$EXP_ID" =~ ^[A-Za-z0-9_.-]+$ ]] || die "EXP_ID no válido: $EXP_ID"
[[ "$SUFFIX" =~ ^_[A-Za-z0-9]+$ ]]  || die "SUFFIX debe tener formato _XXX (p. ej. _999): $SUFFIX"
for v in N_ITER START END; do [[ "${!v}" =~ ^[0-9]+$ ]] || die "$v debe ser un entero: ${!v}"; done
[[ -z "$SEED_BASE" || "$SEED_BASE" =~ ^[0-9]+$ ]] || die "--seed-base debe ser un entero"
(( START >= 1 && START <= END && END <= N_ITER )) || die "Rango inválido: start=$START end=$END n=$N_ITER"
[[ "$UNSOLVED_POLICY" == flag || "$UNSOLVED_POLICY" == fail ]] || die "--unsolved-policy: flag|fail"

# ----------------------------------------------------------------------------
# Rutas (comprobadas desde el directorio de trabajo real)
# ----------------------------------------------------------------------------
[[ -d "$GCAM_PATH" ]] || die "No existe GCAM_PATH='$GCAM_PATH' desde $WORK_DIR"
GCAM_ABS="$(cd "$GCAM_PATH" && pwd -P)"
EXE_DIR="$GCAM_ABS/exe"
XML_DIR="$GCAM_ABS/input/gcamdata/xml"
[[ -f "$DF_PARAMS" ]] || die "No existe la tabla de parámetros '$DF_PARAMS' desde $WORK_DIR"
DF_PARAMS_ABS="$(cd "$(dirname "$DF_PARAMS")" && pwd -P)/$(basename "$DF_PARAMS")"

RUN_GCAM="run-gcam${SUFFIX}.sh"
CONFIG="configuration${SUFFIX}.xml"
BATCH_LIVE="$EXE_DIR/batch_queries/xmldb_batch.xml"
QUERY_FILE_REL="batch_queries/${QUERY_NAME}.xml"
GCAM_MAIN_LOG="$EXE_DIR/logs/main_log.txt"

RUN_TAG="bash_$(date +%Y%m%dT%H%M%S)_$$"
EXP_DIR_NAME="${EXP_ID}${SUFFIX}"
RUN_DIR="$WORK_DIR/$LOG_ROOT/$EXP_DIR_NAME/$RUN_TAG"
OUT_DIR="$WORK_DIR/$DATA_ROOT/$EXP_DIR_NAME"
mkdir -p "$RUN_DIR" "$OUT_DIR" || die "No se pueden crear $RUN_DIR / $OUT_DIR"
MAIN_LOG="$RUN_DIR/run.log"
EVENTS="$RUN_DIR/events.csv"
ITERS="$RUN_DIR/iterations.csv"
ITERS_ALL="$WORK_DIR/$LOG_ROOT/$EXP_DIR_NAME/iterations_all_runs.csv"

ITER_HEADER="run_tag,experiment_id,suffix,iteration,seed,start_time,end_time,t_xml_s,t_gcam_s,t_export_s,t_total_s,exit_r,exit_gcam,exit_export,n_xml,gcam_error_lines,gcam_unsolved_lines,maxrss_r_kb,maxrss_gcam_kb,csv_rows,csv_md5,status,csv_file,error_message"
echo "timestamp,run_tag,experiment_id,suffix,iteration,stage,status,exit_code,seconds,message" > "$EVENTS"
echo "$ITER_HEADER" > "$ITERS"
[[ -f "$ITERS_ALL" ]] || echo "$ITER_HEADER" > "$ITERS_ALL"

event() {  # iteración etapa estado exit segundos mensaje
  echo "$(ts),$RUN_TAG,$EXP_ID,$SUFFIX,$1,$2,$3,$4,$5,$(csvq "$6")" >> "$EVENTS"
}

log "=== run_sensitivity_bash: $EXP_ID sufijo=$SUFFIX iteraciones $START..$END (de $N_ITER)$( (( XML_ONLY )) && echo ' [--xml-only]') ==="
log "run_tag=$RUN_TAG  host=$(hostname)  slurm_job=${SLURM_JOB_ID:-none}  pid=$$"
log "WORK_DIR=$WORK_DIR"
log "GCAM=$GCAM_ABS"
log "DF_PARAMS=$DF_PARAMS_ABS"
log "RUN_DIR=$RUN_DIR"
log "OUT_DIR=$OUT_DIR"
log "seed_base=${SEED_BASE:-aleatoria}  on_error=$ON_ERROR  unsolved_policy=$UNSOLVED_POLICY"

# ----------------------------------------------------------------------------
# Comprobaciones previas
# ----------------------------------------------------------------------------
[[ -x "$RSCRIPT" ]] || die "No se encuentra Rscript ejecutable: $RSCRIPT (variable RSCRIPT)"
command -v flock >/dev/null || die "No se encuentra 'flock'"
"$RSCRIPT" --vanilla -e 'cat(R.version.string, "| xml2:", if (requireNamespace("xml2", quietly=TRUE)) as.character(packageVersion("xml2")) else "NO INSTALADO", "\n")' \
  >> "$MAIN_LOG" 2>&1 || die "No se puede ejecutar '$RSCRIPT --vanilla' (ver $MAIN_LOG)"
# xml2 solo hace falta para --prepare (create_new_config()); el resto usa R base.

for f in "$EXE_DIR/run-gcam.sh" "$EXE_DIR/configuration.xml" "$EXE_DIR/XMLDBDriver.properties" \
         "$BATCH_LIVE" "$EXE_DIR/$QUERY_FILE_REL" "$SCRIPT_DIR/generate_iteration_xml.R" "$R_CONFIG"; do
  [[ -f "$f" ]] || die "No existe $f"
done
[[ -d "$XML_DIR" ]] || die "No existe $XML_DIR"

# XMLDBDriver.properties: gcam.exe debe lanzar el batch que vamos a preparar
BQ="$(sed -n 's:.*<entry key="batch-queries">\(.*\)</entry>.*:\1:p' "$EXE_DIR/XMLDBDriver.properties")"
INMEM="$(sed -n 's:.*<entry key="in-memory">\(.*\)</entry>.*:\1:p' "$EXE_DIR/XMLDBDriver.properties")"
BLOG="$(sed -n 's:.*<entry key="batch-logfile">\(.*\)</entry>.*:\1:p' "$EXE_DIR/XMLDBDriver.properties")"
log "XMLDBDriver.properties: batch-queries='$BQ' in-memory='$INMEM' batch-logfile='$BLOG'"
[[ "$BQ" == "batch_queries/xmldb_batch.xml" ]] || \
  die "XMLDBDriver.properties no lanza batch_queries/xmldb_batch.xml (valor: '$BQ')"
[[ "$INMEM" == "true" ]] || log "AVISO: in-memory != true: los resultados se acumulan en la base de datos XMLDB en disco"

# Un solo loop por directorio exe/ (main_log, batch y properties son compartidos)
exec 9> "$EXE_DIR/.sensitivity_bash.lock"
flock -n 9 || die "Otro run_sensitivity_bash.sh está usando $EXE_DIR (lock $EXE_DIR/.sensitivity_bash.lock)"

if pgrep -u "$(id -u)" -x 'gcam.exe' > /dev/null 2>&1; then
  pgrep -u "$(id -u)" -a -x 'gcam.exe' 2>/dev/null | tee -a "$MAIN_LOG"
  if (( IGNORE_RUNNING )); then
    log "AVISO: hay procesos gcam.exe en ejecución (ignorado por --ignore-running-gcam)"
  else
    die "Hay procesos gcam.exe de este usuario en ejecución (¿workers R antiguos?). Revisar o usar --ignore-running-gcam."
  fi
fi

# configuration<suffix>.xml y run-gcam<suffix>.sh (funciones R existentes)
R_COMMON=(--suffix="$SUFFIX" --gcam-path="$GCAM_ABS" --df-params="$DF_PARAMS_ABS"
          --config="$R_CONFIG" --repo-dir="$WORK_DIR")
if (( PREPARE )) || [[ ! -f "$EXE_DIR/$CONFIG" || ! -f "$EXE_DIR/$RUN_GCAM" ]]; then
  log "Creando $CONFIG y $RUN_GCAM con create_new_config()/create_new_run_gcam()"
  "$RSCRIPT" --vanilla "$SCRIPT_DIR/prepare_suffix_files.R" --mode=create "${R_COMMON[@]}" >> "$MAIN_LOG" 2>&1 \
    || die "Fallo creando los ficheros del sufijo (ver $MAIN_LOG)"
fi
"$RSCRIPT" --vanilla "$SCRIPT_DIR/prepare_suffix_files.R" --mode=check "${R_COMMON[@]}" >> "$MAIN_LOG" 2>&1 \
  || die "Comprobación de $CONFIG / $RUN_GCAM fallida (ver $MAIN_LOG)"

# ¿Puede run-gcam<suffix>.sh ocultar el código de salida de gcam.exe?
GCAM_LINE="$(grep -n 'gcam\.exe' "$EXE_DIR/$RUN_GCAM" | grep -v '^[0-9]*:[[:space:]]*#' | tail -1)"
LAST_LINE="$(grep -nv '^[[:space:]]*\(#.*\)\{0,1\}$' "$EXE_DIR/$RUN_GCAM" | tail -1)"
log "Llamada a GCAM en $RUN_GCAM -> ${GCAM_LINE:-NO ENCONTRADA}"
log "Última orden de $RUN_GCAM  -> $LAST_LINE"
[[ -n "$GCAM_LINE" ]] || die "$RUN_GCAM no contiene ninguna llamada a gcam.exe"
if [[ "${GCAM_LINE%%:*}" != "${LAST_LINE%%:*}" ]]; then
  log "AVISO: gcam.exe no es la última orden de $RUN_GCAM: su código de salida puede quedar oculto."
  log "       Se comprueba además '$GCAM_SUCCESS_PATTERN' en main_log.txt (GCAM_SUCCESS_PATTERN)."
fi
cp "$EXE_DIR/$RUN_GCAM" "$EXE_DIR/$CONFIG" "$EXE_DIR/XMLDBDriver.properties" "$R_CONFIG" "$RUN_DIR/"

# No sobrescribir resultados existentes
if (( ! OVERWRITE && ! XML_ONLY )); then
  for (( it=START; it<=END; it++ )); do
    f="$OUT_DIR/${QUERY_NAME}_$(printf '%03d' "$it").csv"
    [[ -e "$f" ]] && die "Ya existe $f. Usa --start para reanudar, otro sufijo o --overwrite."
  done
fi

# Plantilla del batch: copia prístina; el original se restaura al salir
cp "$BATCH_LIVE" "$RUN_DIR/xmldb_batch.original.xml" || die "No se pudo copiar $BATCH_LIVE"
restore_batch() {
  if [[ -f "$RUN_DIR/xmldb_batch.original.xml" ]] && ! cmp -s "$RUN_DIR/xmldb_batch.original.xml" "$BATCH_LIVE"; then
    cp "$RUN_DIR/xmldb_batch.original.xml" "$BATCH_LIVE.restore.$$" && mv -f "$BATCH_LIVE.restore.$$" "$BATCH_LIVE" \
      && log "Restaurado el $BATCH_LIVE original"
  fi
}

# ----------------------------------------------------------------------------
# Estado de la iteración en curso (variables globales) y su registro
# ----------------------------------------------------------------------------
reset_iter_state() {
  I_IT="$1"; I_SEED=""; I_START=""; I_T0=""; I_TXML=""; I_TGCAM=""; I_TEXP=""
  I_EXIT_R=""; I_EXIT_G=""; I_EXIT_E=""; I_NXML=""; I_ERRL=""; I_UNSOLVED=""
  I_RSS_R=""; I_RSS_G=""; I_ROWS=""; I_MD5=""; I_STATUS="RUNNING"; I_CSV=""; I_ERR=""
  I_RECORDED=0
}
record_iteration() {
  (( I_RECORDED )) && return 0
  local t_end; t_end="$(now)"
  echo "$RUN_TAG,$EXP_ID,$SUFFIX,$I_IT,$I_SEED,$I_START,$(ts),$I_TXML,$I_TGCAM,$I_TEXP,$(elapsed "$I_T0" "$t_end"),$I_EXIT_R,$I_EXIT_G,$I_EXIT_E,$I_NXML,$I_ERRL,$I_UNSOLVED,$I_RSS_R,$I_RSS_G,$I_ROWS,$I_MD5,$I_STATUS,$I_CSV,$(csvq "$I_ERR")" \
    | tee -a "$ITERS" >> "$ITERS_ALL"
  event "$I_IT" total "$I_STATUS" "" "$(elapsed "$I_T0" "$t_end")" "$I_ERR"
  log "Iteración $(printf '%03d' "$I_IT"): $I_STATUS${I_ERR:+ - $I_ERR}"
  I_RECORDED=1
}
fail_iter() {  # estado etapa exit mensaje
  I_STATUS="$1"; I_ERR="$4"
  event "$I_IT" "$2" FAILED "$3" "" "$4"
  record_iteration
  return 1
}

IN_ITER=0
on_signal() {
  log "Señal recibida: interrumpiendo"
  if (( IN_ITER )); then I_STATUS="INTERRUPTED"; I_ERR="señal recibida"; record_iteration; fi
  exit 130
}
trap restore_batch EXIT
trap on_signal INT TERM HUP

log "Comprobaciones previas OK"
if (( CHECK_ONLY )); then log "--check-only: fin"; exit 0; fi

# ----------------------------------------------------------------------------
# Validación del CSV de ModelInterface. Escribe "fila_cabecera filas_datos".
# La cabecera es la primera de las 5 primeras líneas que contiene todas las
# columnas de REQUIRED_HEADER_COLS (ModelInterface pone el título en la línea 1).
# ----------------------------------------------------------------------------
csv_shape() {
  awk -F, -v req="$REQUIRED_HEADER_COLS" '
    BEGIN { n = split(tolower(req), R, ",") }
    !h && NR <= 5 {
      ok = 1
      for (i = 1; i <= n; i++) {
        f = 0
        for (j = 1; j <= NF; j++) { x = tolower($j); gsub(/^[ "\r]+|[ "\r]+$/, "", x); if (x == R[i]) f = 1 }
        if (!f) ok = 0
      }
      if (ok) { h = NR; next }
    }
    h && NF > 1 { rows++ }
    END { print h + 0, rows + 0 }' "$1"
}

# ----------------------------------------------------------------------------
# Una iteración. Devuelve 0 si OK / OK_UNSOLVED / XML_ONLY, 1 si falla.
# ----------------------------------------------------------------------------
run_iteration() {
  local it="$1" I3; I3="$(printf '%03d' "$it")"
  local IT_DIR="$RUN_DIR/iter_$I3"
  local CSV_PARTIAL="$IT_DIR/${QUERY_NAME}.partial.csv"
  local CSV_FINAL="$OUT_DIR/${QUERY_NAME}_${I3}.csv"
  local MARKER="$IT_DIR/.start_marker"
  local t rc

  reset_iter_state "$it"
  mkdir -p "$IT_DIR" || { fail_iter FAILED_R setup 1 "No se puede crear $IT_DIR"; return 1; }
  if [[ -n "$SEED_BASE" ]]; then I_SEED=$(( SEED_BASE + it ))
  else I_SEED=$(( ( (RANDOM << 15) | RANDOM ) % 2147483646 + 1 )); fi
  I_START="$(ts)"; I_T0="$(now)"
  touch "$MARKER"; sleep 1   # resolución de mtime en el sistema de ficheros

  log "---------- Iteración $I3 (semilla $I_SEED) ----------"
  event "$it" start RUNNING "" "" "seed=$I_SEED"

  # ---- 1-2. Generación de XML (R) ------------------------------------------
  t="$(now)"
  run_timed "$IT_DIR/r_time.txt" "$RSCRIPT" --vanilla "$SCRIPT_DIR/generate_iteration_xml.R" \
      --experiment-id="$EXP_ID" --iteration="$it" --n-iterations="$N_ITER" --seed="$I_SEED" \
      --out-dir="$IT_DIR" "${R_COMMON[@]}" > "$IT_DIR/r_generate.log" 2>&1
  I_EXIT_R=$?
  I_TXML="$(elapsed "$t" "$(now)")"; I_RSS_R="$(maxrss_kb "$IT_DIR/r_time.txt")"

  if (( I_EXIT_R != 0 )); then
    fail_iter FAILED_R generate_xml "$I_EXIT_R" "R exit $I_EXIT_R: $(grep -m1 'ERROR' "$IT_DIR/r_generate.log" | cut -c1-400)"
    return 1
  fi
  # Comprobación independiente en Bash: estado, manifiesto, existencia y fecha
  local n=0 bad=0 differ=0 p md5 md5o
  if [[ "$(cat "$IT_DIR/r_status.txt" 2>/dev/null)" != "OK" || ! -s "$IT_DIR/xml_manifest.csv" ]]; then
    fail_iter FAILED_R generate_xml 0 "R terminó con 0 pero sin r_status.txt=OK o sin manifiesto"; return 1
  fi
  while IFS=, read -r _ _ p _ md5 md5o _; do
    p="${p//\"/}"; md5="${md5//\"/}"; md5o="${md5o//\"/}"; n=$((n+1))
    [[ -s "$p" && ! "$p" -ot "$MARKER" ]] || bad=$((bad+1))
    [[ "$md5" != "$md5o" ]] && differ=$((differ+1))
  done < <(tail -n +2 "$IT_DIR/xml_manifest.csv")
  I_NXML="$n"
  if (( n == 0 || bad > 0 || differ != n )); then
    fail_iter FAILED_R generate_xml 0 "XML no válidos: manifiesto=$n ausentes/antiguos=$bad distintos_del_original=$differ"
    return 1
  fi
  event "$it" generate_xml OK 0 "$I_TXML" "$n XML; cambiados=$(csv_field "$IT_DIR/r_meta.csv" 6) de $(csv_field "$IT_DIR/r_meta.csv" 5) parámetros"

  if (( XML_ONLY )); then
    I_STATUS="XML_ONLY"; record_iteration; return 0
  fi

  # ---- 3. Batch de ModelInterface para esta iteración ----------------------
  rm -f "$CSV_PARTIAL"
  "$RSCRIPT" --vanilla "$SCRIPT_DIR/make_batch_xml.R" --template="$RUN_DIR/xmldb_batch.original.xml" \
      --out="$IT_DIR/xmldb_batch.xml" --out-file="$CSV_PARTIAL" --query-file="$QUERY_FILE_REL" \
      > "$IT_DIR/make_batch.log" 2>&1
  rc=$?
  if (( rc == 0 )); then
    cp "$IT_DIR/xmldb_batch.xml" "$BATCH_LIVE.tmp.$$" && mv -f "$BATCH_LIVE.tmp.$$" "$BATCH_LIVE" \
      && cmp -s "$IT_DIR/xmldb_batch.xml" "$BATCH_LIVE"
    rc=$?
  fi
  if (( rc != 0 )); then
    I_EXIT_E=$rc; fail_iter FAILED_BATCH batch_xml "$rc" "No se pudo preparar/instalar el batch XML (ver make_batch.log)"; return 1
  fi
  event "$it" batch_xml OK 0 "" "outFile=$CSV_PARTIAL"

  # ---- 4-5. GCAM (incluye la consulta de ModelInterface) -------------------
  t="$(now)"
  ( cd "$EXE_DIR" && run_timed "$IT_DIR/gcam_time.txt" bash "./$RUN_GCAM" ) < /dev/null > "$IT_DIR/gcam_stdout.log" 2>&1
  I_EXIT_G=$?
  I_TGCAM="$(elapsed "$t" "$(now)")"; I_RSS_G="$(maxrss_kb "$IT_DIR/gcam_time.txt")"

  mkdir -p "$IT_DIR/gcam_logs"
  local lf
  for lf in "$EXE_DIR"/logs/*; do
    [[ -f "$lf" && ! "$lf" -ot "$MARKER" ]] && cp "$lf" "$IT_DIR/gcam_logs/"
  done
  if [[ -f "$GCAM_MAIN_LOG" ]]; then
    I_ERRL="$(grep -ci 'error' "$GCAM_MAIN_LOG")"            # mismo criterio que init_experiment()
    I_UNSOLVED="$(grep -ci "$UNSOLVED_PATTERN" "$GCAM_MAIN_LOG")"
  fi

  local gerr=""
  if [[ ! -f "$GCAM_MAIN_LOG" || "$GCAM_MAIN_LOG" -ot "$MARKER" ]]; then
    gerr="GCAM exit $I_EXIT_G; main_log.txt no se actualizó en esta iteración"
  elif [[ -n "$GCAM_SUCCESS_PATTERN" ]] && ! grep -q "$GCAM_SUCCESS_PATTERN" "$GCAM_MAIN_LOG"; then
    gerr="GCAM exit $I_EXIT_G; main_log.txt sin '$GCAM_SUCCESS_PATTERN'"
  elif (( I_EXIT_G != 0 )); then
    # gcam.exe devuelve 1 cuando la ejecución termina pero algún periodo no
    # resolvió. Solo se acepta ese caso (exit en GCAM_UNSOLVED_EXIT_CODES +
    # 'Model run completed' + líneas UNSOLVED_PATTERN); lo decide --unsolved-policy.
    if [[ ",$GCAM_UNSOLVED_EXIT_CODES," == *",$I_EXIT_G,"* && "${I_UNSOLVED:-0}" -gt 0 ]]; then
      log "GCAM exit $I_EXIT_G con $I_UNSOLVED líneas '$UNSOLVED_PATTERN': ejecución completa con periodos sin resolver"
    else
      gerr="GCAM exit $I_EXIT_G sin periodos sin resolver identificados (ver gcam_stdout.log)"
    fi
  fi
  if [[ -n "$gerr" ]]; then
    [[ -f "$CSV_PARTIAL" ]] && mv -f "$CSV_PARTIAL" "$IT_DIR/${QUERY_NAME}.gcam_failed.csv"
    fail_iter FAILED_GCAM gcam "$I_EXIT_G" "$gerr"; return 1
  fi
  event "$it" gcam OK "$I_EXIT_G" "$I_TGCAM" "error_lines=$I_ERRL unsolved_lines=$I_UNSOLVED maxrss_kb=$I_RSS_G"

  # ---- 6. Validación del CSV exportado ------------------------------------
  t="$(now)"
  local verr="" shape hline
  if [[ ! -s "$CSV_PARTIAL" ]]; then
    verr="CSV no generado o vacío; ver gcam_logs/$(basename "${BLOG:-batch_queries.log}")"
  elif [[ "$CSV_PARTIAL" -ot "$MARKER" ]]; then
    verr="CSV anterior al inicio de la iteración"
  elif head -3 "$CSV_PARTIAL" | grep -qi 'had error\|no results'; then
    verr="ModelInterface: $(head -3 "$CSV_PARTIAL" | tr '\n' ' ' | cut -c1-200)"
  else
    shape="$(csv_shape "$CSV_PARTIAL")"; hline="${shape% *}"; I_ROWS="${shape#* }"
    if (( hline == 0 )); then verr="cabecera sin las columnas '$REQUIRED_HEADER_COLS'"
    elif (( I_ROWS == 0 )); then verr="CSV sin filas de datos"; fi
  fi
  I_TEXP="$(elapsed "$t" "$(now)")"
  if [[ -n "$verr" ]]; then
    I_EXIT_E=1
    [[ -f "$CSV_PARTIAL" ]] && mv -f "$CSV_PARTIAL" "$IT_DIR/${QUERY_NAME}.invalid.csv"
    fail_iter FAILED_EXPORT export 1 "$verr"; return 1
  fi
  I_EXIT_E=0
  I_MD5="$(md5sum "$CSV_PARTIAL" | cut -d' ' -f1)"
  # Un CSV idéntico al de la iteración anterior indica reutilización accidental
  local prev; prev="$(ls -1 "$OUT_DIR/${QUERY_NAME}_"[0-9]*.csv 2>/dev/null | grep -v "_${I3}.csv$" | tail -1)"
  if [[ -n "$prev" ]] && [[ "$(md5sum "$prev" | cut -d' ' -f1)" == "$I_MD5" ]]; then
    I_EXIT_E=1; mv -f "$CSV_PARTIAL" "$IT_DIR/${QUERY_NAME}.duplicate.csv"
    fail_iter FAILED_EXPORT export 1 "CSV idéntico a $(basename "$prev")"; return 1
  fi

  # ---- 7. Estado final ----------------------------------------------------
  if [[ "${I_UNSOLVED:-0}" -gt 0 && "$UNSOLVED_POLICY" == fail ]]; then
    mv -f "$CSV_PARTIAL" "$IT_DIR/${QUERY_NAME}.unsolved.csv"
    event "$it" export OK 0 "$I_TEXP" "CSV conservado solo en $IT_DIR"
    I_STATUS="FAILED_UNSOLVED"; I_ERR="GCAM con periodos sin resolver ($I_UNSOLVED líneas)"
    record_iteration; return 1
  fi

  if ! mv -f "$CSV_PARTIAL" "$CSV_FINAL"; then
    I_EXIT_E=1; fail_iter FAILED_EXPORT export 1 "No se pudo mover el CSV a $CSV_FINAL"; return 1
  fi
  cp "$IT_DIR/params_used.csv" "$OUT_DIR/params_used_${I3}.csv"
  [[ -f "$IT_DIR/satiation_multipliers.csv" ]] && cp "$IT_DIR/satiation_multipliers.csv" "$OUT_DIR/satiation_multipliers_${I3}.csv"
  I_CSV="$CSV_FINAL"
  event "$it" export OK 0 "$I_TEXP" "$CSV_FINAL ($I_ROWS filas)"

  if [[ "${I_UNSOLVED:-0}" -gt 0 ]]; then
    I_STATUS="OK_UNSOLVED"; I_ERR="GCAM con periodos sin resolver ($I_UNSOLVED líneas)"
  else
    I_STATUS="OK"
  fi
  record_iteration
  return 0
}

# ----------------------------------------------------------------------------
# Loop secuencial
# ----------------------------------------------------------------------------
n_ok=0; n_fail=0
for (( it=START; it<=END; it++ )); do
  IN_ITER=1
  if run_iteration "$it"; then
    n_ok=$((n_ok+1))
  else
    n_fail=$((n_fail+1))
    if [[ "$ON_ERROR" == stop ]]; then
      log "Deteniendo el loop tras el fallo de la iteración $it (usa --continue-on-error para seguir)"
      IN_ITER=0; break
    fi
  fi
  IN_ITER=0
done

log "=== Fin: correctas=$n_ok fallidas=$n_fail. Registro: $ITERS ==="
(( n_fail == 0 ))

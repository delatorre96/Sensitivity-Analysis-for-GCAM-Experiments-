#!/bin/bash
#===============================================================================
# launch_gcam_workers.sh
#
# Lanza en Slurm (DIPC) una campaña de sensitivity analysis de GCAM basada en
# runSensAn_allParams_deltas.R. Se ejecuta con `bash` desde el nodo de login,
# NO con `sbatch`: el propio script se encarga de enviar los jobs.
#
# Cómo funciona
# -------------
# 1. BOOTSTRAP. Un primer job ejecuta
#        Rscript runSensAn_allParams_deltas.R NULL <suffix>
#    lo que crea (si no existen) gcam_sensitivity.sqlite, sus tablas, el
#    experimento y Experiments/<EXP_ID>/. El bootstrap lee el EXP_ID del log de R
#    ("Starting experiment: EXP_xxxxxxxx"), espera a que el experimento esté
#    registrado (aparece Experiments/<EXP_ID>/) y, por defecto, a que su
#    primer run de GCAM haya guardado outputs (canario: si GCAM está roto no se
#    lanzan miles de workers). Entonces guarda el EXP_ID en la carpeta de la
#    campaña y envía los workers.
#
# 2. WORKERS. N_WORKERS ejecuciones de
#        Rscript runSensAn_allParams_deltas.R <EXP_ID> <suffix>
#    enviadas como job arrays por bloques de CHUNK_SIZE tareas, con como mucho
#    MAX_PARALLEL tareas a la vez. Cuando un bloque termina, un job "relay"
#    muy pequeño envía el siguiente. Así nunca hay más de CHUNK_SIZE tareas en
#    cola (no chocamos con MaxArraySize ni con el límite de jobs por usuario) y
#    los miles de workers se van repartiendo en el tiempo solos.
#
# 3. SLOTS (suffix). El suffix no es único por worker sino un "slot"
#    reutilizable (_s0001, _s0002, ...). Dos workers que corren a la vez nunca
#    comparten slot (reserva atómica con mkdir en .gcam_slots/), pero un worker
#    nuevo reutiliza configuration<suffix>.xml, run-gcam<suffix> y los XML
#    <name><suffix>.xml de uno que ya terminó. Así el nº de ficheros que se
#    crean en gcam_europe está acotado por MAX_PARALLEL y no por N_WORKERS.
#    Los slots de jobs muertos (timeout, cancelados, nodo caído) se recuperan
#    automáticamente comprobando en squeue que su job ya no existe.
#
# Uso
# ---
#   bash launch_gcam_workers.sh [opciones]
#
#     -n N    nº total de workers (cada uno hace n_iterations runs)  [1000]
#     -p N    máximo de workers ejecutándose a la vez                [100]
#     -c N    tamaño de cada job array (bloque)                      [1000]
#     -e ID   añadir a un experimento ya existente (sin bootstrap)
#     -t T    time limit por worker (formato Slurm)                  [1-00:00:00]
#     -m M    memoria por worker                                     [32G]
#     -q Q    QOS                                                    [regular]
#     -N      no esperar al primer run del bootstrap (sin canario)
#     -h      ayuda
#
#   bash launch_gcam_workers.sh --status <campaña>   estado de una campaña
#   bash launch_gcam_workers.sh --stop   <campaña>   no encolar más; cancela lo pendiente
#
#   <campaña> es el id (p.ej. 20261021_134500) o la ruta de su carpeta.
#
# Todo lo de una campaña queda en slurm_campaigns/<campaña>/:
#   campaign.env    parámetros usados        experiment_id   EXP_ID de la campaña
#   jobs.tsv        jobs enviados            results.tsv     resultado de cada worker
#   logs/slurm/     salida de Slurm          logs/r/         log de R de cada worker
#
# Cualquier parámetro también se puede pasar como variable de entorno, p.ej.
#   PARTITION=... ACCOUNT=... RSCRIPT=... bash launch_gcam_workers.sh -n 5000
#===============================================================================

set -uo pipefail

#----- Configuración por defecto (sobrescribible con variables de entorno) -----
WORKDIR="${WORKDIR:-/scratch/gcamteam/hindcasting/GCAM_sensitivity_analysis}"
RSCRIPT="${RSCRIPT:-$HOME/.conda/envs/r44/bin/Rscript}"
R_SCRIPT="${R_SCRIPT:-runSensAn_allParams_deltas.R}"

N_WORKERS="${N_WORKERS:-1000}"
MAX_PARALLEL="${MAX_PARALLEL:-100}"
CHUNK_SIZE="${CHUNK_SIZE:-1000}"
EXPERIMENT_ID="${EXPERIMENT_ID:-}"

QOS="${QOS:-regular}"
PARTITION="${PARTITION:-}"
ACCOUNT="${ACCOUNT:-}"
WORKER_TIME="${WORKER_TIME:-1-00:00:00}"
WORKER_MEM="${WORKER_MEM:-32G}"
WORKER_CPUS="${WORKER_CPUS:-1}"
RELAY_TIME="${RELAY_TIME:-00:15:00}"

JOB_PREFIX="${JOB_PREFIX:-gcam_sa}"
WAIT_FIRST_RUN="${WAIT_FIRST_RUN:-1}"   # 1 = canario: esperar al 1er run del bootstrap
SLOT_MARGIN="${SLOT_MARGIN:-8}"         # slots extra sobre MAX_PARALLEL
SLOT_WAIT_MAX="${SLOT_WAIT_MAX:-3600}"  # s máximos esperando un slot libre
POLL_SECONDS="${POLL_SECONDS:-20}"      # s entre comprobaciones del bootstrap

ROLE="${GCAM_ROLE:-launcher}"

#===============================================================================
# Utilidades
#===============================================================================
log()    { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }
die()    { log "ERROR: $*" >&2; exit 1; }
is_int() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
me()     { echo "${USER:-$(id -un)}"; }

usage() { sed -n '/^# Uso/,/^#====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; /^====/d'; }

CONFIG_VARS=(WORKDIR RSCRIPT R_SCRIPT N_WORKERS MAX_PARALLEL CHUNK_SIZE QOS PARTITION
             ACCOUNT WORKER_TIME WORKER_MEM WORKER_CPUS RELAY_TIME WAIT_FIRST_RUN
             SLOT_POOL SLOT_WAIT_MAX POLL_SECONDS SCRIPT_PATH CAMPAIGN_ID CAMPAIGN_DIR
             JOB_NAME)

save_config() {
  local v
  for v in "${CONFIG_VARS[@]}"; do printf '%s=%q\n' "$v" "${!v}"; done \
    > "$CAMPAIGN_DIR/campaign.env"
}

load_config() {
  local dir="${1:-${GCAM_CAMPAIGN_DIR:-}}"
  [[ -f "$dir/campaign.env" ]] || die "No encuentro $dir/campaign.env"
  # shellcheck disable=SC1091
  source "$dir/campaign.env"
}

# Resuelve "<id>" o "<ruta>" a la carpeta de una campaña
campaign_path() {
  if [[ -f "$1/campaign.env" ]]; then (cd "$1" && pwd)
  elif [[ -f "$WORKDIR/slurm_campaigns/$1/campaign.env" ]]; then echo "$WORKDIR/slurm_campaigns/$1"
  else die "Campaña no encontrada: $1"; fi
}

valid_exp_id() { [[ "${1:-}" =~ ^EXP_[0-9A-Za-z]+$ ]]; }

# El experimento está registrado en SQLite cuando existe su carpeta: el R la
# crea (create_experiment_folders) justo después de write_experiment_info().
exp_registered() { [[ -d "$WORKDIR/Experiments/$1/inputs" ]]; }

# Al menos un run con outputs guardados en parquet
exp_has_outputs() { compgen -G "$WORKDIR/Experiments/$1/outputs/*/*.parquet" > /dev/null; }

#===============================================================================
# Envío de jobs
#===============================================================================

# sbatch "limpio": si se llama desde dentro de un job (bootstrap o relay), el job
# nuevo no debe heredar las variables SLURM_* del job actual.
slurm_submit() {
  (
    for v in $(compgen -v | grep -E '^(SLURM|SBATCH)_'); do unset "$v"; done
    opts=(--parsable --qos="$QOS")
    [[ -n "$PARTITION" ]] && opts+=(--partition="$PARTITION")
    [[ -n "$ACCOUNT"   ]] && opts+=(--account="$ACCOUNT")
    out=$(sbatch "${opts[@]}" "$@") || exit 1
    echo "${out%%;*}"
  )
}

# Envía el bloque de workers que empieza en el índice global $1 y, si quedan
# más, un relay que enviará el siguiente bloque cuando este termine.
submit_chunk() {
  local offset=$1

  if [[ -e "$CAMPAIGN_DIR/STOP" ]]; then
    log "Encontrado $CAMPAIGN_DIR/STOP: no se envían más bloques."
    return 0
  fi

  local remaining=$(( N_WORKERS - offset ))
  if (( remaining <= 0 )); then
    log "Todos los workers de la campaña ya están enviados."
    return 0
  fi

  local size=$(( remaining < CHUNK_SIZE ? remaining : CHUNK_SIZE ))
  local par=$(( MAX_PARALLEL < size ? MAX_PARALLEL : size ))
  local last=$(( offset + size - 1 ))

  local array_id
  array_id=$(slurm_submit \
      --job-name="$JOB_NAME" \
      --array="0-$(( size - 1 ))%${par}" \
      --ntasks=1 --cpus-per-task="$WORKER_CPUS" \
      --mem="$WORKER_MEM" --time="$WORKER_TIME" \
      --output="$CAMPAIGN_DIR/logs/slurm/worker_%A_%a.out" \
      --error="$CAMPAIGN_DIR/logs/slurm/worker_%A_%a.err" \
      --export="ALL,GCAM_ROLE=worker,GCAM_CAMPAIGN_DIR=$CAMPAIGN_DIR,GCAM_OFFSET=$offset" \
      "$SCRIPT_PATH") || { log "ERROR: sbatch falló al enviar los workers $offset..$last"; return 1; }

  printf '%s\tworkers\t%s\t%s-%s\n' "$(date '+%F %T')" "$array_id" "$offset" "$last" \
    >> "$CAMPAIGN_DIR/jobs.tsv"
  log "Bloque enviado: workers $offset..$last -> job array $array_id (máx. $par a la vez)"

  local next=$(( offset + size ))
  if (( next < N_WORKERS )); then
    local relay_id
    relay_id=$(slurm_submit \
        --job-name="$JOB_NAME" \
        --dependency="afterany:$array_id" \
        --ntasks=1 --cpus-per-task=1 --mem=1G --time="$RELAY_TIME" \
        --output="$CAMPAIGN_DIR/logs/slurm/relay_%j.out" \
        --export="ALL,GCAM_ROLE=relay,GCAM_CAMPAIGN_DIR=$CAMPAIGN_DIR,GCAM_OFFSET=$next" \
        "$SCRIPT_PATH") || { log "ERROR: sbatch falló al enviar el relay del bloque $next"; return 1; }
    printf '%s\trelay\t%s\tnext=%s\n' "$(date '+%F %T')" "$relay_id" "$next" \
      >> "$CAMPAIGN_DIR/jobs.tsv"
    log "Relay $relay_id enviará el bloque que empieza en $next cuando acabe $array_id"
  fi
}

#===============================================================================
# Slots (suffix reutilizable)
#===============================================================================
SLOT_PATH=""
SUFFIX=""

owner_id() {
  if [[ -n "${SLURM_ARRAY_JOB_ID:-}" ]]; then
    echo "${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}"
  else
    echo "${SLURM_JOB_ID:-pid$$}"
  fi
}

# Libera slots cuyo job ya no está en Slurm. Si squeue falla no se toca nada.
# Devuelve 0 si ha liberado alguno.
reclaim_stale_slots() {
  local live d owner freed=1
  live=$(squeue -h -r -u "$(me)" -o '%i' 2>/dev/null) || return 1
  live=$(awk '{print $1}' <<< "$live")
  for d in "$SLOT_DIR"/slot_*; do
    [[ -d "$d" ]] || continue
    owner=$(cat "$d/owner" 2>/dev/null || true)
    if [[ -z "$owner" ]]; then
      # sin owner: sólo se recupera si lleva > 10 min así
      [[ -n "$(find "$d" -maxdepth 0 -mmin +10 2>/dev/null)" ]] || continue
    elif grep -qxF "$owner" <<< "$live"; then
      continue
    fi
    if mv "$d" "$d.stale.$$" 2>/dev/null; then
      rm -rf "$d.stale.$$"
      log "Slot huérfano liberado: $(basename "$d") (job ${owner:-?})"
      freed=0
    fi
  done
  return $freed
}

# Reserva un slot libre (mkdir es atómico) -> fija SUFFIX y SLOT_PATH
acquire_slot() {
  local index=$1 me_id start k s d waited=0
  SLOT_DIR="$WORKDIR/.gcam_slots"
  mkdir -p "$SLOT_DIR"
  me_id=$(owner_id)
  start=$(( index % SLOT_POOL ))
  while :; do
    for (( k = 0; k < SLOT_POOL; k++ )); do
      s=$(( (start + k) % SLOT_POOL + 1 ))
      printf -v d '%s/slot_%04d' "$SLOT_DIR" "$s"
      if mkdir "$d" 2>/dev/null; then
        echo "$me_id" > "$d/owner"
        SLOT_PATH=$d
        printf -v SUFFIX '_s%04d' "$s"
        return 0
      fi
    done
    reclaim_stale_slots && continue
    (( waited >= SLOT_WAIT_MAX )) && die "No hay slots libres tras ${SLOT_WAIT_MAX}s ($SLOT_DIR)"
    sleep 30
    waited=$(( waited + 30 ))
  done
}

release_slot() {
  [[ -n "$SLOT_PATH" && -d "$SLOT_PATH" ]] || return 0
  if [[ "$(cat "$SLOT_PATH/owner" 2>/dev/null)" == "$(owner_id)" ]]; then
    rm -rf "$SLOT_PATH"
  fi
  SLOT_PATH=""
}

#===============================================================================
# Roles
#===============================================================================

#----- Nodo de login: prepara la campaña y envía el bootstrap (o los workers) ---
role_launcher() {
  if [[ -n "${SLURM_JOB_ID:-}" ]]; then
    die "Ejecuta este script con 'bash launch_gcam_workers.sh', no con sbatch."
  fi

  local no_canary=0
  while getopts ":n:p:c:e:t:m:q:Nh" opt; do
    case $opt in
      n) N_WORKERS=$OPTARG ;;
      p) MAX_PARALLEL=$OPTARG ;;
      c) CHUNK_SIZE=$OPTARG ;;
      e) EXPERIMENT_ID=$OPTARG ;;
      t) WORKER_TIME=$OPTARG ;;
      m) WORKER_MEM=$OPTARG ;;
      q) QOS=$OPTARG ;;
      N) no_canary=1 ;;
      h) usage; exit 0 ;;
      :) die "La opción -$OPTARG necesita un valor" ;;
      *) die "Opción desconocida: -$OPTARG (usa -h)" ;;
    esac
  done
  (( no_canary )) && WAIT_FIRST_RUN=0

  #----- Validaciones -----
  local v
  for v in N_WORKERS MAX_PARALLEL CHUNK_SIZE; do
    is_int "${!v}" && (( ${!v} >= 1 )) || die "$v debe ser un entero >= 1 (es '${!v}')"
  done
  command -v sbatch > /dev/null || die "sbatch no está disponible"
  command -v squeue > /dev/null || die "squeue no está disponible"
  [[ -d "$WORKDIR" ]]            || die "No existe WORKDIR: $WORKDIR"
  cd "$WORKDIR"                  || die "No puedo entrar en $WORKDIR"
  [[ -f "$R_SCRIPT" ]]           || die "No existe $WORKDIR/$R_SCRIPT"
  [[ -x "$RSCRIPT" ]]            || die "No encuentro Rscript ejecutable en $RSCRIPT"

  if [[ -n "$EXPERIMENT_ID" ]]; then
    valid_exp_id "$EXPERIMENT_ID" || die "Experiment id no válido: $EXPERIMENT_ID"
    exp_registered "$EXPERIMENT_ID" || die "No existe Experiments/$EXPERIMENT_ID/ en $WORKDIR"
  fi

  #----- Límites del cluster -----
  local max_array
  max_array=$(scontrol show config 2>/dev/null | awk -F'= *' '/^MaxArraySize/{print $2+0}')
  if is_int "$max_array" && (( max_array > 0 && CHUNK_SIZE > max_array )); then
    log "CHUNK_SIZE=$CHUNK_SIZE supera MaxArraySize=$max_array del cluster: uso $max_array"
    CHUNK_SIZE=$max_array
  fi
  (( MAX_PARALLEL > CHUNK_SIZE )) && MAX_PARALLEL=$CHUNK_SIZE
  (( MAX_PARALLEL > N_WORKERS ))  && MAX_PARALLEL=$N_WORKERS
  SLOT_POOL=$(( MAX_PARALLEL + 1 + SLOT_MARGIN ))   # +1 por el bootstrap

  #----- Carpeta de la campaña -----
  SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
  CAMPAIGN_ID=$(date '+%Y%m%d_%H%M%S')
  CAMPAIGN_DIR="$WORKDIR/slurm_campaigns/$CAMPAIGN_ID"
  JOB_NAME="${JOB_PREFIX}_${CAMPAIGN_ID}"
  [[ -e "$CAMPAIGN_DIR" ]] && die "Ya existe $CAMPAIGN_DIR (espera un segundo y relanza)"
  mkdir -p "$CAMPAIGN_DIR/logs/slurm" "$CAMPAIGN_DIR/logs/r" || die "No puedo crear $CAMPAIGN_DIR"
  printf 'index\tjob\tsuffix\texit_code\tstart\tend\tnode\n' > "$CAMPAIGN_DIR/results.tsv"
  save_config

  local iters boot=0
  [[ -z "$EXPERIMENT_ID" ]] && boot=1
  iters=$(grep -oE '^[[:space:]]*n_iterations[[:space:]]*(=|<-)[[:space:]]*[0-9]+' "$R_SCRIPT" \
          | grep -oE '[0-9]+$' | head -1)

  echo "=================================================="
  echo "Campaña:          $CAMPAIGN_ID"
  echo "Carpeta:          $CAMPAIGN_DIR"
  echo "Job name:         $JOB_NAME"
  echo "Script R:         $R_SCRIPT (n_iterations = ${iters:-?})"
  echo "Workers:          $N_WORKERS (bloques de $CHUNK_SIZE, máx. $MAX_PARALLEL a la vez)"
  [[ -n "$iters" ]] && \
  echo "Runs de GCAM:     ~$(( (N_WORKERS + boot) * iters ))"
  echo "Recursos/worker:  $WORKER_CPUS CPU, $WORKER_MEM, $WORKER_TIME (QOS $QOS)"
  echo "=================================================="

  if [[ -n "$EXPERIMENT_ID" ]]; then
    echo "$EXPERIMENT_ID" > "$CAMPAIGN_DIR/experiment_id"
    log "Añadiendo runs al experimento existente $EXPERIMENT_ID"
    submit_chunk 0 || die "No se pudieron enviar los workers"
  else
    local boot_id
    boot_id=$(slurm_submit \
        --job-name="$JOB_NAME" \
        --ntasks=1 --cpus-per-task="$WORKER_CPUS" \
        --mem="$WORKER_MEM" --time="$WORKER_TIME" \
        --output="$CAMPAIGN_DIR/logs/slurm/bootstrap_%j.out" \
        --error="$CAMPAIGN_DIR/logs/slurm/bootstrap_%j.err" \
        --export="ALL,GCAM_ROLE=bootstrap,GCAM_CAMPAIGN_DIR=$CAMPAIGN_DIR" \
        "$SCRIPT_PATH") || die "No se pudo enviar el bootstrap"
    printf '%s\tbootstrap\t%s\t-\n' "$(date '+%F %T')" "$boot_id" >> "$CAMPAIGN_DIR/jobs.tsv"
    log "Bootstrap enviado: job $boot_id (crea el experimento con experiment_id = NULL)"
    if (( WAIT_FIRST_RUN )); then
      log "Los workers se enviarán cuando el bootstrap registre el experimento y complete su primer run."
    else
      log "Los workers se enviarán en cuanto el bootstrap registre el experimento."
    fi
  fi

  echo
  echo "Seguimiento:  bash $(basename "$SCRIPT_PATH") --status $CAMPAIGN_ID"
  echo "Parar:        bash $(basename "$SCRIPT_PATH") --stop $CAMPAIGN_ID"
  echo "Cancelar ya:  scancel -n $JOB_NAME"
}

#----- Bootstrap: crea el experimento y, cuando está listo, envía los workers ---
role_bootstrap() {
  load_config
  cd "$WORKDIR" || die "No puedo entrar en $WORKDIR"

  acquire_slot 0
  trap release_slot EXIT
  trap 'exit 143' TERM INT

  local rlog="$CAMPAIGN_DIR/logs/r/bootstrap.log"
  local start; start=$(date '+%F %T')
  echo "=================================================="
  echo "Rol:          bootstrap (experiment_id = NULL)"
  echo "Suffix:       $SUFFIX"
  echo "Node:         $(hostname)"
  echo "Job ID:       ${SLURM_JOB_ID:-}"
  echo "Log R:        $rlog"
  echo "Start:        $start"
  echo "=================================================="

  "$RSCRIPT" "$R_SCRIPT" NULL "$SUFFIX" > "$rlog" 2>&1 &
  local rpid=$! exp="" ready=0 submitted=0

  is_ready() {
    [[ -n "$exp" ]] && exp_registered "$exp" || return 1
    (( WAIT_FIRST_RUN )) || return 0
    exp_has_outputs "$exp"
  }

  while :; do
    if [[ -z "$exp" ]]; then
      exp=$(grep -m1 -oE 'Starting experiment: EXP_[0-9A-Za-z]+' "$rlog" 2>/dev/null \
            | awk '{print $3}')
      [[ -n "$exp" ]] && log "Experiment id detectado en el log de R: $exp"
    fi
    if is_ready; then ready=1; break; fi
    kill -0 "$rpid" 2>/dev/null || break   # R terminó
    sleep "$POLL_SECONDS"
  done

  if (( ready )); then
    echo "$exp" > "$CAMPAIGN_DIR/experiment_id"
    log "Experimento $exp registrado y listo. Enviando workers..."
    if submit_chunk 0; then
      submitted=1
    else
      log "ERROR: no se pudieron enviar los workers desde el nodo de cómputo."
      log "Envíalos a mano desde el login con:"
      log "  bash $SCRIPT_PATH -e $exp -n $N_WORKERS -p $MAX_PARALLEL -c $CHUNK_SIZE"
    fi
  fi

  wait "$rpid"
  local status=$?

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "bootstrap" "${SLURM_JOB_ID:-}" "$SUFFIX" \
    "$status" "$start" "$(date '+%F %T')" "$(hostname)" >> "$CAMPAIGN_DIR/results.tsv"

  if (( ! ready )); then
    if [[ -z "$exp" ]]; then
      die "R terminó (código $status) sin crear el experimento. Revisa $rlog"
    elif ! exp_registered "$exp"; then
      die "R terminó (código $status) sin registrar $exp. Revisa $rlog"
    else
      echo "$exp" > "$CAMPAIGN_DIR/experiment_id"
      die "El primer run de $exp no guardó outputs (canario). No se lanzan workers. Revisa $rlog"
    fi
  fi

  log "Bootstrap terminado (código $status). Workers enviados: $(( submitted ))"
  exit "$status"
}

#----- Worker: un Rscript vinculado al experimento de la campaña ---------------
role_worker() {
  load_config
  cd "$WORKDIR" || die "No puedo entrar en $WORKDIR"

  is_int "${GCAM_OFFSET:-}" && is_int "${SLURM_ARRAY_TASK_ID:-}" \
    || die "Faltan GCAM_OFFSET / SLURM_ARRAY_TASK_ID"
  local index=$(( GCAM_OFFSET + SLURM_ARRAY_TASK_ID ))
  local label; printf -v label 'w%06d' "$index"

  local exp=""
  [[ -f "$CAMPAIGN_DIR/experiment_id" ]] && exp=$(< "$CAMPAIGN_DIR/experiment_id")
  valid_exp_id "$exp"   || die "experiment_id no válido en $CAMPAIGN_DIR/experiment_id: '$exp'"
  exp_registered "$exp" || die "No existe Experiments/$exp/"

  acquire_slot "$index"
  trap release_slot EXIT
  trap 'exit 143' TERM INT

  local rlog="$CAMPAIGN_DIR/logs/r/${label}.log"
  local start; start=$(date '+%F %T')
  echo "=================================================="
  echo "Worker:       $label (array ${SLURM_ARRAY_JOB_ID:-}_${SLURM_ARRAY_TASK_ID})"
  echo "Suffix:       $SUFFIX"
  echo "Experiment:   $exp"
  echo "Node:         $(hostname)"
  echo "Log R:        $rlog"
  echo "Start:        $start"
  echo "=================================================="

  # En segundo plano + wait para que SIGTERM (timeout/scancel) libere el slot
  "$RSCRIPT" "$R_SCRIPT" "$exp" "$SUFFIX" > "$rlog" 2>&1 &
  wait $!
  local status=$?

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$label" \
    "${SLURM_ARRAY_JOB_ID:-}_${SLURM_ARRAY_TASK_ID}" "$SUFFIX" "$status" "$start" \
    "$(date '+%F %T')" "$(hostname)" >> "$CAMPAIGN_DIR/results.tsv"

  echo "=================================================="
  echo "Worker finished: $label  exit code $status  $(date)"
  echo "=================================================="
  exit "$status"
}

#----- Relay: envía el siguiente bloque cuando termina el anterior -------------
role_relay() {
  load_config
  cd "$WORKDIR" || die "No puedo entrar en $WORKDIR"
  is_int "${GCAM_OFFSET:-}" || die "Falta GCAM_OFFSET"
  submit_chunk "$GCAM_OFFSET" || die "No se pudo enviar el bloque $GCAM_OFFSET"
}

#----- --status ---------------------------------------------------------------
role_status() {
  local dir; dir=$(campaign_path "$1")
  load_config "$dir"
  local exp="(aún no creado)"
  [[ -f "$CAMPAIGN_DIR/experiment_id" ]] && exp=$(< "$CAMPAIGN_DIR/experiment_id")

  echo "Campaña:       $CAMPAIGN_ID   ($CAMPAIGN_DIR)"
  echo "Experimento:   $exp"
  echo "Workers:       $N_WORKERS en total, bloques de $CHUNK_SIZE, máx. $MAX_PARALLEL a la vez"
  [[ -e "$CAMPAIGN_DIR/STOP" ]] && echo "Estado:        STOP (no se encolan más bloques)"

  echo; echo "Jobs en Slurm ($JOB_NAME):"
  squeue -h -r -n "$JOB_NAME" -u "$(me)" -o '%T' 2>/dev/null | sort | uniq -c \
    | awk '{printf "  %-12s %s\n", $2, $1}'

  echo; echo "Workers terminados:"
  awk -F'\t' 'NR > 1 { n++; if ($4 == 0) ok++; else ko++ }
              END { printf "  %d (OK: %d, con error: %d)\n", n, ok, ko }' "$CAMPAIGN_DIR/results.tsv"

  if valid_exp_id "$exp" && [[ -d "$WORKDIR/Experiments/$exp/inputs" ]]; then
    echo; echo "Runs guardados en Experiments/$exp/inputs (todas las campañas del experimento):"
    echo "  $(find "$WORKDIR/Experiments/$exp/inputs" -name '*.parquet' | wc -l)"
  fi

  echo; echo "Últimos envíos (jobs.tsv):"
  tail -n 5 "$CAMPAIGN_DIR/jobs.tsv" 2>/dev/null | sed 's/^/  /'
}

#----- --stop -----------------------------------------------------------------
role_stop() {
  local dir; dir=$(campaign_path "$1")
  load_config "$dir"
  touch "$CAMPAIGN_DIR/STOP"
  scancel -n "$JOB_NAME" -u "$(me)" -t PENDING 2>/dev/null || true
  log "Campaña $CAMPAIGN_ID parada: no se encolan más bloques y se han cancelado los jobs pendientes."
  log "Los workers que ya están corriendo terminarán normalmente (scancel -n $JOB_NAME para matarlos)."
}

#===============================================================================
# Main
#===============================================================================
case "${1:-}" in
  --status) [[ -n "${2:-}" ]] || die "Uso: --status <campaña>"; role_status "$2"; exit 0 ;;
  --stop)   [[ -n "${2:-}" ]] || die "Uso: --stop <campaña>";   role_stop "$2";   exit 0 ;;
  --help)   usage; exit 0 ;;
esac

case "$ROLE" in
  launcher)  role_launcher "$@" ;;
  bootstrap) role_bootstrap ;;
  worker)    role_worker ;;
  relay)     role_relay ;;
  *)         die "GCAM_ROLE desconocido: $ROLE" ;;
esac

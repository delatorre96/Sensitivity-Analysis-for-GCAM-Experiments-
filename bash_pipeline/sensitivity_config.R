# =============================================================================
# sensitivity_config.R
#
# Configuración científica y de reutilización de código para
# generate_iteration_xml.R. Solo define variables; no ejecuta nada.
#
# NO cambiar los rangos sin una decisión científica explícita.
# =============================================================================

# -----------------------------------------------------------------------------
# Rangos de distribución: copiados literalmente de
# runSensAn_allParams_monteCarlo.R (configuración del experimento EXP_c9b80e40).
#
# OJO: con la función de incertidumbre elegida abajo (definición nº 1),
# minVal/maxVal de satiation_level son MULTIPLICADORES log-uniformes sobre
# param_default (un factor por `group`, salvo by = "row").
# -----------------------------------------------------------------------------
distribution_parameters <- list(
  "logit"            = list("minVal" = -20,   "maxVal" = -0.01),
  "price_elasticity" = list("minVal" = -1.5,  "maxVal" = -0.01),
  "satiation_level"  = list("minVal" = 0.001, "maxVal" = 3)
  # factor por fila en lugar de por grupo:
  # "satiation_level" = list("minVal" = 0.001, "maxVal" = 3, "by" = "row")
)

# Columna de df_allParams.csv con el valor del parámetro.
# write_xml_fast() escribe siempre d$param, así que debe ser "param".
paramCol <- "param"

# Ficheros XML a excluir. Vacío = igual que init_experiment() actual
# (el filtro de building_det_EUR.xml está comentado allí).
exclude_xml_files <- character(0)

# -----------------------------------------------------------------------------
# Funciones existentes que se reutilizan (se carga SOLO su definición).
#
# introduce_heterogeneous_uncertainty_by_type() está definida DOS veces en
# 4_introduceUncertainty.R:
#   nº 1: satiation = param_default * multiplicador por grupo, signif(., 6)
#         -> es la lógica descrita en la especificación  (USADA)
#   nº 2: satiation ~ U(minVal, maxVal) absoluta, round(., 3)
#         -> es la que gana con source() en init_experiment()
# Para usar la nº 2: occurrence = 2L y must_contain = NULL.
# -----------------------------------------------------------------------------
function_sources <- list(
  build_xml_cache   = list(file = "R/Experiment/3_createDF_paramsXML.R"),
  fmt_num           = list(file = "R/Experiment/5_createNewXml.R"),
  write_xml_fast    = list(file = "R/Experiment/5_createNewXml.R"),
  createNewXml_fast = list(file = "R/Experiment/5_createNewXml.R"),
  introduce_heterogeneous_uncertainty_by_type = list(
    file = "R/Experiment/4_introduceUncertainty.R",
    occurrence = 1L,
    must_contain = "signif\\("
  )
)

uncertainty_introduction_function <- "introduce_heterogeneous_uncertainty_by_type"

# Columnas exigidas en df_allParams.csv (las que usan las funciones anteriores).
required_columns <- c("xml_file", "destination_file", "tag", "occ",
                      "param_default", "type_of_param", paramCol)
required_columns_by_type <- list(
  logit           = c("fillout"),
  satiation_level = c("group")
)

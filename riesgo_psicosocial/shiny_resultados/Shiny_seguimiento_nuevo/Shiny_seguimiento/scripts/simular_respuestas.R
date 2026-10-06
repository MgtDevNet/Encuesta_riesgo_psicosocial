#!/usr/bin/env Rscript
# -----------------------------------------------------------------------------
# simular_respuestas.R
# Crea respuestas SIMULADAS en seguimiento.respuestas_odk para el marco cargado.
#
#   Rscript scripts/simular_respuestas.R
#
# Es el paso que faltaba: simular_items.R solo vuelve a simular los items de
# filas que YA existen, y el CSV del que se alimentaba cargar_datos_simulados.R
# se quedo con el marco sintetico. Aqui nacen las filas.
#
# Despues de este script hay que correr, en este orden:
#   Rscript scripts/simular_items.R   # calibra los items contra los baremos
#   Rscript conectar_bd.R             # califica y reescribe seguimiento.respuestas
#
# Que se simula y con que criterio:
#   - Responde COBERTURA del marco. Quien fue citado envia despues de su cita
#     --que es como ocurre en campo-- y quien no, en cualquier dia del periodo.
#   - Las sociodemograficas usan los mismos codigos del formulario que tenia la
#     simulacion anterior (se leyeron de la tabla de respaldo del 8/09).
#   - Los items nacen en cero y los calibra simular_items.R. Lo que si se decide
#     aqui es el patron de VACIOS, que ese script respeta tal cual:
#       * forma A: p106..p114 solo quien atiende publico (65%), p115..p123 solo
#         quien tiene personal a cargo (15%);
#       * forma B: p89..p97 solo quien tiene personal a cargo (72%);
#       * ademas un 0,5% de items sueltos sin contestar, que es lo que hace que
#         un envio cuente como incompleto.
# -----------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(DBI); library(RPostgres); library(pool)
})

SEMILLA   <- 2026
COBERTURA <- 0.60    # parte del marco que responde
P_PUBLICO <- 0.65    # forma A: atiende publico
P_CARGO_A <- 0.15    # forma A: tiene personal a cargo
P_CARGO_B <- 0.72    # forma B: tiene personal a cargo
# Items sueltos sin contestar. Ojo con subirlo: como "completa" exige que no
# falte ninguno de los 62 items de extralaboral y estres, un 0,5% por item deja
# menos de la mitad de los envios completos. Con 0,05% quedan ~95%, que es la
# proporcion que tenia la simulacion anterior.
P_HUECO   <- 0.0005
DIAS_CAMPO <- 60L    # desde cuando se reciben envios

ruta <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
if (length(ruta) == 1) setwd(dirname(dirname(normalizePath(ruta))))
if (file.exists(".Renviron")) readRenviron(".Renviron")
source("R/utils_db.R", encoding = "UTF-8")
source("R/helpers.R", encoding = "UTF-8")
source("R/utils_auth.R", encoding = "UTF-8")
source("R/utils_seguimiento.R", encoding = "UTF-8")

conexion <- db_probar()
if (!isTRUE(conexion)) stop(conexion, call. = FALSE)
set.seed(SEMILLA)

m <- db_get("SELECT id_anonimizado, nombre, dependencia, tipo_dependencia,
                    tipo_vinculacion, nivel_empleo, forma_cuestionario
               FROM seguimiento.marco
              WHERE estado_vinculacion = 'Activo' ORDER BY id_anonimizado")
if (nrow(m) == 0) stop("El marco esta vacio.", call. = FALSE)

# La primera citacion de cada quien: el envio va despues de ella.
cita <- db_get("SELECT id_anonimizado, min(fecha) AS dia FROM seguimiento.citaciones
                 GROUP BY 1")
m$cita <- cita$dia[match(m$id_anonimizado, cita$id_anonimizado)]

hoy <- seg_hoy()

# Solo responde quien YA pudo hacerlo: sin cita, o con la cita ya pasada. Si se
# muestrea sobre todo el marco, a los citados para las proximas semanas hay que
# empujarles el envio hasta hoy, y el grafico de avance amanece con un pico
# artificial --478 envios en un dia contra 30 de los demas-- y con gente que
# respondio antes de que la citaran.
pueden <- is.na(m$cita) | m$cita <= hoy
q <- m[pueden, , drop = FALSE]
q <- q[sort(sample(nrow(q), floor(nrow(q) * COBERTURA))), , drop = FALSE]
n <- nrow(q)

# Fecha de envio: el dia de la cita o poco despues; sin cita, cualquier dia del
# periodo. Nunca en el futuro.
desfase <- sample(0:6, n, replace = TRUE, prob = c(0.45, 0.2, 0.12, 0.09, 0.06, 0.05, 0.03))
dia <- as.Date(ifelse(is.na(q$cita),
                      as.numeric(hoy - sample(seq_len(DIAS_CAMPO), n, replace = TRUE)),
                      as.numeric(q$cita + desfase)), origin = "1970-01-01")
dia[dia > hoy] <- hoy
inicio <- as.POSIXct(paste(dia, sprintf("%02d:%02d:00", sample(7:18, n, TRUE),
                                        sample(0:59, n, TRUE))), tz = SEG_TZ)
dur <- round(runif(n, 18, 75), 1)

cod <- function(valores, pesos) sample(valores, n, replace = TRUE, prob = pesos)

d <- data.frame(
  clave              = sprintf("uuid:sim-%s-%04d", format(hoy, "%Y%m%d"), seq_len(n)),
  id_anonimizado     = q$id_anonimizado,
  submission_date    = inicio + dur * 60,
  inicio             = inicio,
  fin                = inicio + dur * 60,
  duracion_min       = dur,
  deviceid           = "simulado",
  dependencia        = q$dependencia,
  sede_seccional     = NA_character_,
  tipo_vinculacion   = q$tipo_vinculacion,
  nivel_empleo       = q$nivel_empleo,
  forma_cuestionario = q$forma_cuestionario,
  nombre             = q$nombre,
  cedula             = q$id_anonimizado,
  consentimiento     = ifelse(runif(n) < 0.02, 2L, 1L),   # 2 = no acepta
  sexo               = cod(1:2, c(0.49, 0.51)),
  # La fecha de nacimiento no es adorno: conectar_bd.R saca de ella `edad_anios`
  # y de ahi el corte "Grupo de edad" de la pestana de Resultados. Sin esta
  # columna ese corte sale entero como "Sin dato".
  nacimiento         = format(hoy - as.integer(runif(n, 24, 68) * 365.25), "%Y-%m-%d"),
  estado_civil       = cod(1:6, c(0.32, 0.31, 0.20, 0.10, 0.06, 0.01)),
  nivel_academico    = cod(c(3, 4, 6, 7, 8, 11), c(0.04, 0.07, 0.11, 0.04, 0.10, 0.64)),
  estrato            = cod(1:6, c(0.06, 0.19, 0.34, 0.21, 0.14, 0.06)),
  vivienda           = cod(1:3, c(0.42, 0.40, 0.18)),
  dependientes       = cod(0:4, c(0.30, 0.28, 0.25, 0.12, 0.05)),
  departamento       = "05",
  ciudad             = "05001",
  departamento_lab   = "05",
  ciudad_lab         = "05001",
  anos_lab_num       = sample(1:35, n, replace = TRUE),
  anos_cargo_num     = sample(1:25, n, replace = TRUE),
  cargo              = q$nivel_empleo,
  tipo_cargo         = cod(1:4, c(0.06, 0.76, 0.10, 0.08)),
  area               = q$tipo_dependencia,
  tipo_contrato      = cod(c(1, 2, 3, 5, 6), c(0.02, 0.27, 0.62, 0.08, 0.01)),
  horas              = cod(c(2, 3, 4, 8, 9, 10), c(0.06, 0.04, 0.15, 0.68, 0.05, 0.02)),
  tipo_salario       = cod(1:3, c(0.84, 0.01, 0.15)),
  form_intra         = ifelse(q$forma_cuestionario == "A", 1L, 2L),
  ila_val1           = NA_integer_, ila_val2 = NA_integer_, ilb_val1 = NA_integer_,
  stringsAsFactors   = FALSE)

# Los items: cero donde la persona contesta, NA donde no. simular_items.R
# reemplaza los ceros por valores calibrados y respeta los NA.
publico  <- runif(n) < P_PUBLICO
cargo_a  <- runif(n) < P_CARGO_A
cargo_b  <- runif(n) < P_CARGO_B
es_a     <- q$forma_cuestionario == "A"

bloque <- function(prefijo, cuantos) {
  nombres <- sprintf("%s%d", prefijo, seq_len(cuantos))
  for (i in seq_along(nombres)) {
    nm <- nombres[i]
    vale <- switch(
      prefijo,
      ila_p = es_a & if (i >= 115) cargo_a else if (i >= 106) publico else TRUE,
      ilb_p = !es_a & if (i >= 89) cargo_b else TRUE,
      rep(TRUE, n))                      # el_p y ee_p los contestan todos
    vale <- vale & runif(n) >= P_HUECO
    d[[nm]] <<- ifelse(vale, 0L, NA_integer_)
  }
}
bloque("ila_p", 123); bloque("ilb_p", 97); bloque("el_p", 31); bloque("ee_p", 31)

message("simulando ", n, " respuestas de ", nrow(m), " personas del marco (",
        round(100 * n / nrow(m)), "%)")
message("  forma A: ", sum(es_a), " · forma B: ", sum(!es_a),
        " · no aceptan: ", sum(d$consentimiento == 2))
message("  envios del ", format(min(dia), "%d/%m/%Y"), " al ", format(max(dia), "%d/%m/%Y"))

db_tx(function(con) {
  DBI::dbExecute(con, "DELETE FROM seguimiento.respuestas_odk")
  DBI::dbAppendTable(con, DBI::Id(schema = "seguimiento", table = "respuestas_odk"), d)
})

message("\nListo. Ahora:")
message("  Rscript scripts/simular_items.R")
message("  Rscript conectar_bd.R")
db_cerrar()

#!/usr/bin/env Rscript
# -----------------------------------------------------------------------------
# simular_agenda.R
# Arma una agenda de citaciones SIMULADA sobre el marco que este cargado.
#
#   Rscript scripts/simular_agenda.R              # escribe en la base
#   Rscript scripts/simular_agenda.R --excel      # ademas deja el .xlsx
#   Rscript scripts/simular_agenda.R --solo-excel # NO toca la base: exporta
#                                                 # al .xlsx la agenda cargada
#
# --solo-excel es para cuando ya hay una agenda buena en la base y lo que se
# quiere es el archivo. Volver a sortearla cambiaria las citaciones, dejaria
# huerfanos los grupos ya asignados y descuadraria las respuestas simuladas,
# que se generaron despues de la citacion de cada persona.
#
# Hacia falta porque la agenda anterior (Agenda_citaciones_SIMULADA.xlsx) esta
# hecha con los ids del marco sintetico: con el marco real no cita a nadie.
#
# Como es la jornada (lo que define la simulacion):
#   - sesiones de DURACION_MIN minutos, CUATRO al dia (FRANJAS);
#   - hasta POR_GRUPO personas por sesion;
#   - hasta SEG_CIT_GRUPOS_HORA sesiones a la vez en cada franja.
# Las franjas no comparten ninguna hora de reloj entre si, asi que con dos
# sesiones simultaneas de 30 personas quedan 60 por hora: por debajo del tope de
# SEG_CIT_POR_HORA que verifica la app al cargar (ver seg_cit_capacidad).
#
# Las fechas caen a ambos lados de hoy a proposito: las pasadas alimentan
# "citados sin responder" y el recuadro por dia, y las futuras dejan grupos que
# un psicologo puede tomar y anotar.
# -----------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(DBI); library(RPostgres); library(pool)
})

SEMILLA       <- 2026
COBERTURA     <- 0.95   # parte del marco que alcanza a ser citada
POR_GRUPO     <- 30L    # personas por sesion (el maximo del operativo)
DURACION_MIN  <- 90L    # hora y media por sesion
DIAS_ATRAS    <- 60L    # desde cuando hay sesiones ya hechas
DIAS_ADELANTE <- 15L    # hasta cuando hay sesiones programadas
FRANJAS <- c("08:00", "10:00", "13:30", "15:30")   # inicio de las cuatro del dia

ARCHIVO <- file.path("..", "Agenda_citaciones_SIMULADA.xlsx")

ruta <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
if (length(ruta) == 1) setwd(dirname(dirname(normalizePath(ruta))))
if (file.exists(".Renviron")) readRenviron(".Renviron")
source("R/utils_db.R", encoding = "UTF-8")
source("R/helpers.R", encoding = "UTF-8")
source("R/utils_auth.R", encoding = "UTF-8")
source("R/utils_seguimiento.R", encoding = "UTF-8")

args       <- commandArgs(trailingOnly = TRUE)
solo_excel <- "--solo-excel" %in% args
excel      <- solo_excel || "--excel" %in% args

conexion <- db_probar()
if (!isTRUE(conexion)) stop(conexion, call. = FALSE)

# Suma minutos a un "HH:MM" y devuelve "HH:MM".
mas_minutos <- function(hhmm, minutos) {
  m <- as.integer(substr(hhmm, 1, 2)) * 60L + as.integer(substr(hhmm, 4, 5)) + minutos
  sprintf("%02d:%02d", m %/% 60L, m %% 60L)
}

if (solo_excel) {

  cit <- db_get("
    SELECT id_anonimizado, fecha,
           to_char(hora_inicio, 'HH24:MI') AS hora_inicio,
           to_char(hora_fin,    'HH24:MI') AS hora_fin,
           link, nombre
      FROM seguimiento.citaciones
     ORDER BY fecha, hora_inicio, id_anonimizado")
  if (nrow(cit) == 0) {
    stop("No hay agenda en la base: corra el script sin --solo-excel.", call. = FALSE)
  }
  message("agenda cargada en la base: ", nrow(cit), " citaciones de ",
          length(unique(cit$id_anonimizado)), " personas")

} else {

  set.seed(SEMILLA)
  m <- db_get("SELECT id_anonimizado, nombre FROM seguimiento.marco
                WHERE estado_vinculacion = 'Activo' ORDER BY id_anonimizado")
  if (nrow(m) == 0) stop("El marco esta vacio: cargue primero el marco.", call. = FALSE)

  citadas <- m[sort(sample(nrow(m), floor(nrow(m) * COBERTURA))), , drop = FALSE]
  citadas <- citadas[sample(nrow(citadas)), , drop = FALSE]   # se reparten al azar
  n_grupos <- ceiling(nrow(citadas) / POR_GRUPO)

  hoy   <- seg_hoy()
  dias  <- seq(hoy - DIAS_ATRAS, hoy + DIAS_ADELANTE, by = "day")
  dias  <- dias[!format(dias, "%u") %in% c("6", "7")]
  ranuras <- expand.grid(fecha = dias, hora = FRANJAS, grupo = seq_len(SEG_CIT_GRUPOS_HORA),
                         stringsAsFactors = FALSE)
  ranuras <- ranuras[order(ranuras$fecha, ranuras$hora, ranuras$grupo), ]
  if (nrow(ranuras) < n_grupos) {
    stop("No caben ", n_grupos, " grupos en ", nrow(ranuras), " ranuras: ",
         "amplie el periodo o suba POR_GRUPO.", call. = FALSE)
  }
  # Repartidos a lo largo de TODO el periodo, no en las primeras ranuras: con 8
  # ranuras por dia habil, tomarlas en orden dejaba todos los grupos en los
  # primeros dias y ni uno en el futuro, justo lo que hace falta para poder
  # tomar y anotar un grupo desde la app.
  ranuras <- ranuras[round(seq(1, nrow(ranuras), length.out = n_grupos)), ]

  g <- rep(seq_len(n_grupos), each = POR_GRUPO)[seq_len(nrow(citadas))]
  cit <- data.frame(
    id_anonimizado = citadas$id_anonimizado,
    fecha          = ranuras$fecha[g],
    hora_inicio    = ranuras$hora[g],
    hora_fin       = mas_minutos(ranuras$hora[g], DURACION_MIN),
    link           = sprintf("https://meet.google.com/rps-%s-%s-g%d",
                             format(ranuras$fecha[g], "%m%d"),
                             sub(":", "", ranuras$hora[g]), ranuras$grupo[g]),
    nombre         = citadas$nombre,
    stringsAsFactors = FALSE)

  # Las mismas comprobaciones que hace la app al cargar un archivo.
  cap <- seg_cit_capacidad(cit)
  if (nrow(cap)) {
    message("AVISO: ", nrow(cap), " franjas pasan la capacidad")
    print(utils::head(cap, 5), row.names = FALSE)
  }
  fuera <- seg_cit_fuera_marco(cit)
  if (length(fuera)) stop(length(fuera), " citados no estan en el marco.", call. = FALSE)

  seg_cit_guardar(cit)

  message("agenda simulada: ", nrow(cit), " citaciones · ",
          length(unique(cit$id_anonimizado)), " personas · ", n_grupos, " grupos de ",
          POR_GRUPO, " · sesiones de ", DURACION_MIN, " min")
  message("  del ", format(min(cit$fecha), "%d/%m/%Y"), " al ",
          format(max(cit$fecha), "%d/%m/%Y"),
          " (", sum(unique(cit$fecha) < hoy), " dias ya pasados)")
}

if (excel) {
  if (!requireNamespace("writexl", quietly = TRUE)) {
    message("AVISO: sin el paquete writexl no se escribe el .xlsx")
  } else {
    # Las mismas columnas y los mismos nombres con que llega la agenda de
    # verdad, para que el archivo se pueda volver a cargar desde la app.
    salida <- data.frame(
      Fecha                    = as.Date(cit$fecha),
      `Hora inicio programada` = cit$hora_inicio,
      `Hora final programada`  = cit$hora_fin,
      `ID persona`             = cit$id_anonimizado,
      Nombre                   = cit$nombre,
      `Link donde se aplica`   = cit$link,
      check.names = FALSE, stringsAsFactors = FALSE)
    writexl::write_xlsx(salida, ARCHIVO)
    message("  archivo: ", normalizePath(ARCHIVO), " (", nrow(salida), " filas)")
  }
}

db_cerrar()

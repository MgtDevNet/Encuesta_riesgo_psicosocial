#!/usr/bin/env Rscript
# -----------------------------------------------------------------------------
# exportar_odk_csv.R
# Vuelca seguimiento.respuestas_odk a Simulacion_respuestas_ODK.csv.
#
#   Rscript scripts/exportar_odk_csv.R
#
# Es el viaje de vuelta de cargar_respuestas_odk.sh, y hace falta porque
# simular_items.R escribe directo en la base: sin esto el CSV se queda con la
# simulacion vieja --items en escala 1..5-- y cualquiera que recargue desde el
# archivo deshace el trabajo sin enterarse.
#
# El cargador hace un \copy POSICIONAL, asi que lo que manda es el orden de las
# columnas, no el nombre. Por eso el orden y la cabecera se toman del CSV que ya
# existe y solo se reemplaza el contenido: asi el archivo que sale se puede
# volver a cargar con cargar_respuestas_odk.sh sin tocar nada.
# -----------------------------------------------------------------------------

suppressMessages({ library(DBI); library(RPostgres) })

buscar <- function(rel) {
  for (b in c(".", "..", "../..", "Shiny_seguimiento")) {
    p <- file.path(b, rel); if (file.exists(p)) return(normalizePath(p))
  }
  stop("no encuentro ", rel, " desde ", getwd())
}
CSV <- buscar("Simulacion_respuestas_ODK.csv")

# ODK nombra distinto que la base: la cabecera del CSV se conserva tal cual y
# solo se traduce para saber que columna de la base va en cada posicion.
TRAD <- c(SubmissionDate = "submission_date", start = "inicio", end = "fin",
          KEY = "clave", "años_lab" = "anos_lab", "años_lab_num" = "anos_lab_num",
          "años_cargo" = "anos_cargo", "años_cargo_num" = "anos_cargo_num")

cab <- names(read.csv(CSV, nrows = 1, check.names = FALSE, encoding = "UTF-8"))
col_bd <- ifelse(cab %in% names(TRAD), TRAD[cab], cab)

con <- dbConnect(RPostgres::Postgres(),
                 host     = Sys.getenv("PG_HOST", "postgres"),
                 port     = as.integer(Sys.getenv("PG_PORT", "5432")),
                 dbname   = Sys.getenv("PG_DB", "riesgo_psicosocial"),
                 user     = Sys.getenv("PG_USER", Sys.info()[["user"]]),
                 password = Sys.getenv("PG_PASSWORD", "1568"),
                 timezone = "America/Bogota")
on.exit(if (dbIsValid(con)) dbDisconnect(con))

d <- dbGetQuery(con, sprintf("SELECT %s FROM seguimiento.respuestas_odk ORDER BY clave",
                             paste(sprintf('"%s"', col_bd), collapse = ", ")))
stopifnot(ncol(d) == length(cab))

# ODK escribe las marcas de tiempo como 2026-08-07T18:31:35 y las fechas sueltas
# como 1964-10-11. Si se dejan con el formato por defecto de R, el \copy las
# lee igual pero el archivo deja de ser identico al que baja de ODK.
for (v in names(d)) {
  if (inherits(d[[v]], "POSIXct"))
    d[[v]] <- format(d[[v]], "%Y-%m-%dT%H:%M:%S", tz = "America/Bogota")
  else if (inherits(d[[v]], "Date"))
    d[[v]] <- format(d[[v]], "%Y-%m-%d")
}

# ODK escribe la duracion con un decimal siempre ("44.0", no "44"), y el
# cargador cuenta con eso --guarda el texto del CSV tal cual--. write.csv se
# come el .0 de los enteros, asi que se formatea a mano.
d$duracion_min <- ifelse(is.na(d$duracion_min), NA_character_,
                         sprintf("%.1f", d$duracion_min))

names(d) <- cab
write.csv(d, CSV, row.names = FALSE, na = "", fileEncoding = "UTF-8")
cat(sprintf("%s: %d filas, %d columnas\n", basename(CSV), nrow(d), ncol(d)))

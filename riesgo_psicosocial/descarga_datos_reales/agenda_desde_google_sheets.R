library(googlesheets4)
library(DBI)
library(RPostgres)

# Arma la agenda de citaciones a partir de las inscripciones del Google Form
# ("Formulario Riesgo Psicosocial (Respuestas)"). Dos formas de usarlo:
#
#   Manual:     Rscript agenda_desde_google_sheets.R
#               Deja agenda_citaciones.xlsx en esta carpeta, para subirlo en la
#               Shiny: Administracion > Agenda de citaciones. Ahi se revisa
#               antes de cargarlo.
#
#   Recurrente: Rscript agenda_desde_google_sheets.R --cargar
#               Escribe la agenda directo en la base, sin pasar por la app. Es
#               lo que corre actualizar_agenda.sh desde el cron (cada 30 min)
#               dentro del contenedor de la Shiny. Solo toca la base si la
#               agenda cambio: sale con 10 si la reemplazo y con 0 si no.
#
# OJO: en modo recurrente el Sheet manda. Una agenda subida a mano desde la app
# se reemplaza en la siguiente corrida por lo que diga el Sheet.
#
# Cada inscripcion trae la cedula y la franja elegida, en un texto como
#   "Martes, 20/10/2026 10:30 a. m. – 11:30 a. m."
# La cedula se cambia por el id anonimizado con el marco de la base, porque la
# agenda trabaja solo con id_anonimizado. Quien no esta en el marco no entra:
# se lista al final para revisarlo a mano.
#
# La lectura y el guardado son los mismos de la app (seg_cit_normalizar y
# seg_cit_guardar en R/utils_seguimiento.R): la carga recurrente valida igual
# que la manual y, como ella, les quita el psicologo a los grupos que salen.
#
# El Excel de salida lleva nombres: NO va a git (ver .gitignore).

cargar <- "--cargar" %in% commandArgs(trailingOnly = TRUE)

# 1. Credenciales: el .Renviron de esta carpeta (GOOGLE_SA_KEY y PG_*)
args_file  <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
dir_script <- if (length(args_file) == 1) dirname(normalizePath(args_file)) else getwd()

# Las PG_* que ya trae el entorno mandan sobre las del archivo, igual que en
# conexion_resultados_odk.R: dentro del contenedor PG_HOST es "postgres" y el
# localhost del .Renviron apuntaria al propio contenedor.
pg_entorno <- Sys.getenv(c("PG_HOST", "PG_PORT", "PG_DB", "PG_USER", "PG_PASSWORD"),
                         unset = NA)
readRenviron(file.path(dir_script, ".Renviron"))
pg_entorno <- pg_entorno[!is.na(pg_entorno)]
if (length(pg_entorno)) do.call(Sys.setenv, as.list(pg_entorno))

# Link de la sesion, si es el mismo para todas (el formulario no lo trae).
# Se deja vacio si no se conoce: en la agenda es opcional.
LINK_SESION <- ""

salida <- file.path(dir_script, "agenda_citaciones.xlsx")

# 2. Funciones de la agenda de la app. En el contenedor la app esta en /app; en
#    el equipo, en shiny_resultados/ junto a esta carpeta.
dir_app <- Filter(dir.exists, c(
  Sys.getenv("APP_DIR"), "/app",
  file.path(dir_script, "..", "shiny_resultados", "Shiny_seguimiento_nuevo",
            "Shiny_seguimiento")))[1]
if (is.na(dir_app)) stop("No se encuentra la carpeta de la app (Shiny_seguimiento).")
suppressPackageStartupMessages(library(stringi))
source(file.path(dir_app, "R", "helpers.R"))
source(file.path(dir_app, "R", "utils_db.R"))
source(file.path(dir_app, "R", "utils_seguimiento.R"))

# 3. Inscripciones del Google Sheet. La ruta del .Renviron es la del equipo:
#    dentro del contenedor esta carpeta es /descarga, asi que si esa ruta no
#    existe se busca la llave aqui mismo, con el mismo nombre.
llave_google <- Sys.getenv("GOOGLE_SA_KEY")
if (nzchar(llave_google) && !file.exists(llave_google)) {
  llave_google <- file.path(dir_script, basename(gsub("\\\\", "/", llave_google)))
}
if (!nzchar(llave_google) || !file.exists(llave_google)) {
  stop("Falta GOOGLE_SA_KEY en el .Renviron, o el archivo no existe: '", llave_google, "'")
}
gs4_deauth()
gs4_auth(path = llave_google)
sheet_id <- "1vKfcjjDbzE7ybtQem4WEd6oOVy6THGbAancw5GTWSIk"
insc <- as.data.frame(read_sheet(sheet_id, sheet = "Respuestas de formulario 1"))
if (nrow(insc) == 0) stop("El Sheet no trae inscripciones; la agenda no se toca.")

# 4. Fecha y franja desde el texto de "Fecha de diligenciamiento"
franja <- gsub("\\s+", " ", insc$`Fecha de diligenciamiento`)
fecha  <- as.Date(regmatches(franja, regexpr("[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}", franja)),
                  format = "%d/%m/%Y")

# "2:00 p. m." / "4:30 p.m" -> "14:00" / "16:30"
horas <- regmatches(franja, gregexpr("[0-9]{1,2}:[0-9]{2} ?[ap]\\. ?m\\.?", franja))
a_24h <- function(h) {
  hh <- as.integer(sub(":.*", "", h))
  mm <- sub("^[0-9]+:([0-9]{2}).*", "\\1", h)
  pm <- grepl("p", h)
  hh <- ifelse(pm & hh < 12, hh + 12L, ifelse(!pm & hh == 12, 0L, hh))
  sprintf("%02d:%s", hh, mm)
}
if (any(lengths(horas) != 2)) {
  stop("No se pudo leer la franja de estas inscripciones (filas del Sheet): ",
       paste(which(lengths(horas) != 2) + 1, collapse = ", "))
}

insc$fecha       <- fecha
insc$hora_inicio <- a_24h(vapply(horas, `[`, "", 1))
insc$hora_final  <- a_24h(vapply(horas, `[`, "", 2))
insc$documento   <- trimws(format(insc$`Número de documento de identidad`,
                                  scientific = FALSE, trim = TRUE))

# 5. Cedula -> id anonimizado con el marco
marco <- db_get("SELECT identificacion, id_anonimizado FROM seguimiento.marco")
insc$id <- marco$id_anonimizado[match(insc$documento, marco$identificacion)]

# 6. La agenda: una fila por persona y franja. Quien se inscribio dos veces en
#    la misma franja queda una sola vez; en franjas distintas, queda citado en
#    las dos.
agenda <- data.frame(
  fecha                    = format(insc$fecha, "%d/%m/%Y"),
  `hora inicio programada` = insc$hora_inicio,
  `hora final programada`  = insc$hora_final,
  id                       = insc$id,
  persona                  = insc$`Nombre completo`,
  link                     = LINK_SESION,
  check.names = FALSE, stringsAsFactors = FALSE)
agenda <- agenda[!is.na(agenda$id), ]
agenda <- agenda[!duplicated(agenda[, c("fecha", "hora inicio programada",
                                        "hora final programada", "id")]), ]
agenda <- agenda[order(as.Date(agenda$fecha, "%d/%m/%Y"),
                       agenda$`hora inicio programada`, agenda$persona), ]
if (nrow(agenda) == 0) stop("Ninguna inscripcion esta en el marco; la agenda no se toca.")

# 7. Resumen
fuera <- unique(insc[is.na(insc$id), c("documento", "Nombre completo")])
cat("\nInscripciones en el Sheet:", nrow(insc), "\n")
cat("Citaciones en la agenda:  ", nrow(agenda), "de", length(unique(agenda$id)), "personas\n")
print(table(paste(agenda$fecha, agenda$`hora inicio programada`, "-",
                  agenda$`hora final programada`)))
if (nrow(fuera)) {
  cat("\nNo estan en el marco (no entran en la agenda):", nrow(fuera), "\n")
  print(fuera, row.names = FALSE)
}

# 8a. Manual: el Excel para subir en la app
if (!cargar) {
  writexl::write_xlsx(agenda, salida)
  cat("\nArchivo:", salida, "\n")
  cat("Subalo en la Shiny: Administracion > Agenda de citaciones.\n")
  quit(status = 0)
}

# 8b. Recurrente: directo a la base, solo si cambio
cit <- seg_cit_normalizar(agenda)

clave <- function(x) {
  x <- x[, c("id_anonimizado", "fecha", "hora_inicio", "hora_fin", "link", "nombre")]
  x$fecha <- as.character(as.Date(x$fecha))
  x$link  <- ifelse(is.na(x$link), "", x$link)
  sort(do.call(paste, c(x, sep = "|")))
}
en_base <- db_get("
  SELECT id_anonimizado, fecha,
         to_char(hora_inicio, 'HH24:MI') AS hora_inicio,
         to_char(hora_fin, 'HH24:MI')    AS hora_fin,
         link, nombre
    FROM seguimiento.citaciones")

if (identical(clave(cit), clave(en_base))) {
  cat("\nLa agenda de la base ya esta al dia; no se toca.\n")
  db_cerrar()
  quit(status = 0)
}

huerfanos <- seg_grupos_huerfanos(cit)
seg_cit_guardar(cit)
invisible(db_exec(
  "INSERT INTO auth.bitacora_accesos (usuario, evento, detalle, origen)
   VALUES ($1, 'agenda_cargada', $2, $3)",
  params = list("sistema",
                sprintf("%s citaciones desde Google Sheets (antes %s)",
                        nrow(cit), nrow(en_base)),
                "agenda_desde_google_sheets.R")))
db_cerrar()

cat(sprintf("\nAgenda reemplazada en la base: %s citaciones (antes %s).\n",
            nrow(cit), nrow(en_base)))
if (nrow(huerfanos)) cat(nrow(huerfanos), "grupos salieron de la agenda y perdieron su psicologo.\n")
quit(status = 10)

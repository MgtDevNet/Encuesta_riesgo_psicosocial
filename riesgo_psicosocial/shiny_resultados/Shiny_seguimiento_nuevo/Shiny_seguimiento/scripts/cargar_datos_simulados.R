#!/usr/bin/env Rscript
# -----------------------------------------------------------------------------
# Carga el marco muestral y las respuestas simuladas al esquema `seguimiento`.
#
#   Rscript scripts/cargar_datos_simulados.R
#
# Es idempotente: vuelve a crear el contenido de marco y respuestas en cada
# corrida. Las METAS (el número planeado por dependencia) NO se tocan: son
# datos que edita el usuario desde la app.
# -----------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(DBI); library(RPostgres); library(pool); library(readxl)
})

if (!file.exists("R/utils_db.R")) setwd(dirname(dirname(normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))))))
if (file.exists(".Renviron")) readRenviron(".Renviron")
source("R/utils_db.R", encoding = "UTF-8")

DATOS <- normalizePath(file.path("..", ""), mustWork = TRUE)
f_marco <- file.path(DATOS, "Marco_muestral_SINTETICO_UdeA.xlsx")
f_resp  <- file.path(DATOS, "Simulacion_respuestas_ODK.csv")
f_punt  <- file.path(DATOS, "Simulacion_puntajes.csv")

for (f in c(f_marco, f_resp, f_punt)) {
  if (!file.exists(f)) stop("No se encuentra: ", f, call. = FALSE)
}

conexion <- db_probar()
if (!isTRUE(conexion)) stop(conexion, call. = FALSE)

message("creando esquema seguimiento...")
db_exec("CREATE SCHEMA IF NOT EXISTS seguimiento")

db_exec("
  CREATE TABLE IF NOT EXISTS seguimiento.marco (
    id_anonimizado               text PRIMARY KEY,
    dependencia                  text NOT NULL,
    tipo_dependencia             text,
    nivel_jerarquico_dependencia text,
    centro_costo                 text,
    sede_seccional               text,
    municipio                    text,
    tipo_vinculacion             text,
    nivel_empleo                 text,
    forma_cuestionario           text,
    estado_vinculacion           text,
    dedicacion                   text,
    modalidad_trabajo            text,
    trabaja_por_turnos           text
  )")

db_exec("
  CREATE TABLE IF NOT EXISTS public.respuestas_procesadas (
    clave              text PRIMARY KEY,
    id_anonimizado     text,
    submission_date    timestamptz,
    inicio             timestamptz,
    fin                timestamptz,
    duracion_min       numeric,
    forma_cuestionario text,
    completa           boolean,
    trans_intralaboral numeric,
    trans_extralaboral numeric,
    trans_estres       numeric
  )")

# Metas: lo único que edita el usuario. No se borra al recargar.
db_exec("
  CREATE TABLE IF NOT EXISTS seguimiento.metas (
    dependencia   text PRIMARY KEY,
    planeado      integer NOT NULL DEFAULT 0,
    nota          text,
    actualizado   timestamptz NOT NULL DEFAULT now(),
    actualizado_por text
  )")

db_exec("CREATE INDEX IF NOT EXISTS idx_marco_dep ON seguimiento.marco (dependencia)")
db_exec("CREATE INDEX IF NOT EXISTS idx_resp_id  ON public.respuestas_procesadas (id_anonimizado)")

# --- marco --------------------------------------------------------------------
message("leyendo marco muestral...")
m <- readxl::read_excel(f_marco, sheet = "Marco_muestral")
cols <- c("id_anonimizado", "dependencia", "tipo_dependencia",
          "nivel_jerarquico_dependencia", "centro_costo", "sede_seccional",
          "municipio", "tipo_vinculacion", "nivel_empleo", "forma_cuestionario",
          "estado_vinculacion", "dedicacion", "modalidad_trabajo", "trabaja_por_turnos")
m <- as.data.frame(m[, cols])

db_exec("TRUNCATE seguimiento.marco")
pool::poolWithTransaction(db_pool(), function(con) {
  DBI::dbAppendTable(con, DBI::Id(schema = "seguimiento", table = "marco"), m)
})
message("  marco: ", nrow(m), " registros")

# --- respuestas ---------------------------------------------------------------
message("leyendo respuestas y puntajes...")
r <- utils::read.csv(f_resp, stringsAsFactors = FALSE, check.names = FALSE,
                     colClasses = "character")
p <- utils::read.csv(f_punt, stringsAsFactors = FALSE, check.names = FALSE)

# "completa": ningún ítem aplicable quedó en blanco
items <- grep("^(ila_p|ilb_p|el_p|ee_p)[0-9]+$", names(r), value = TRUE)
aplicables <- function(fila) {
  pref <- if (fila[["forma_cuestionario"]] == "A") "ila_p" else "ilb_p"
  cs <- items[grepl(paste0("^(", pref, "|el_p|ee_p)"), items)]
  cs
}
completa <- vapply(seq_len(nrow(r)), function(i) {
  cs <- aplicables(r[i, ])
  v <- unlist(r[i, cs], use.names = FALSE)
  # los ítems no aplicables por filtro también vienen vacíos; se usa el conteo
  # de vacíos frente al patrón esperado, así que basta con exigir que los
  # bloques extralaboral y estrés estén completos y que no falte ninguno de los
  # ítems que sí se presentaron.
  all(unlist(r[i, grep("^(el_p|ee_p)", names(r))], use.names = FALSE) != "")
}, logical(1))

num <- function(x) suppressWarnings(as.numeric(ifelse(x == "", NA, x)))
pi_ <- setNames(p$trans_intralaboral_total, p$id_anonimizado)
pe_ <- setNames(p$trans_extralaboral_total, p$id_anonimizado)
ps_ <- setNames(p$trans_estres,             p$id_anonimizado)

resp <- data.frame(
  clave              = r$KEY,
  id_anonimizado     = r$id_anonimizado,
  submission_date    = as.POSIXct(r$SubmissionDate, format = "%Y-%m-%dT%H:%M:%S", tz = "America/Bogota"),
  inicio             = as.POSIXct(r$start, format = "%Y-%m-%dT%H:%M:%S", tz = "America/Bogota"),
  fin                = as.POSIXct(r$end,   format = "%Y-%m-%dT%H:%M:%S", tz = "America/Bogota"),
  duracion_min       = num(r$duracion_min),
  forma_cuestionario = r$forma_cuestionario,
  completa           = completa,
  trans_intralaboral = as.numeric(pi_[r$id_anonimizado]),
  trans_extralaboral = as.numeric(pe_[r$id_anonimizado]),
  trans_estres       = as.numeric(ps_[r$id_anonimizado]),
  stringsAsFactors   = FALSE
)

db_exec("TRUNCATE public.respuestas_procesadas")
pool::poolWithTransaction(db_pool(), function(con) {
  DBI::dbAppendTable(con, DBI::Id(schema = "seguimiento", table = "respuestas"), resp)
})
message("  respuestas: ", nrow(resp), " registros")

# --- metas: se crean solo las que falten, con el N elegible como valor inicial -
n <- db_exec("
  INSERT INTO seguimiento.metas (dependencia, planeado, nota, actualizado_por)
  SELECT dependencia, count(*) FILTER (WHERE estado_vinculacion = 'Activo'),
         'Valor inicial = elegibles del marco', 'carga inicial'
    FROM seguimiento.marco
   GROUP BY dependencia
  ON CONFLICT (dependencia) DO NOTHING")
message("  metas creadas: ", n, " (las existentes no se tocaron)")

r1 <- db_get("SELECT count(*) n FROM seguimiento.marco")$n
r2 <- db_get("SELECT count(*) n FROM public.respuestas_procesadas")$n
r3 <- db_get("SELECT count(*) n FROM seguimiento.metas")$n
message(sprintf("\nlisto: marco=%s respuestas=%s metas=%s", r1, r2, r3))

huerfanas <- db_get("
  SELECT count(*) n FROM public.respuestas_procesadas r
   WHERE NOT EXISTS (SELECT 1 FROM seguimiento.marco m
                      WHERE m.id_anonimizado = r.id_anonimizado)")$n
message("respuestas sin correspondencia en el marco: ", huerfanas)

db_cerrar()

#!/usr/bin/env Rscript
# -----------------------------------------------------------------------------
# cargar_marco_bateria.R
# Carga el marco REAL --el export de nomina "Bateria 2026"-- tal cual viene.
#
#   Rscript scripts/cargar_marco_bateria.R "../Bateria 2026 (1).xlsx"
#   Rscript scripts/cargar_marco_bateria.R <archivo> --conservar
#
# Tambien se llega aqui solo: preparar_bd.R --marco= reconoce este archivo por
# sus encabezados en la fila 5 y delega en este script, pasandole --conservar
# salvo que le hayan dado --limpiar. Las dos formas de invocarlo son validas;
# esta es la directa.
#
# Aqui el archivo NO se modifica: sus columnas se guardan tal cual --en
# minusculas, que es lo unico que cambia, porque SQL no distingue mayusculas--
# y al lado se calculan las que la app consulta.
#
# El archivo trae CEDULA y NOMBRE. Es la primera vez que datos personales entran
# a la base: hasta ahora la app trabajaba solo con id_anonimizado. Se hace a
# peticion expresa, y la app los muestra en la pestana de personas.
#
# Que se deriva, y de donde (lo que el archivo no trae queda en NULL, y sus
# filtros se ocultan solos en la app):
#
#   id_anonimizado     IDENTIFICACION            dependencia        DESCRIPCION_DEPENDENCIA
#   nombre             NOMBRE                    tipo_dependencia   DESCRIPCION_UNIDAD
#   tipo_vinculacion   TIPO_VINCULACION          nivel_empleo       GRUPO
#   estado_vinculacion 'Activo' (ver abajo)      forma_cuestionario sorteo (ver abajo)
#
# estado_vinculacion: el archivo es la nomina vigente y su columna NOVEDAD vale
# 0 en todas las filas, asi que no hay de donde sacar bajas. Todos entran como
# activos, que es el denominador del avance.
#
# forma_cuestionario: la Bateria se responde en forma A o B segun el cargo, y el
# archivo no lo dice. Por ahora se reparte al azar con la proporcion que tienen
# las respuestas ya cargadas (FORMA_SEMILLA lo hace reproducible). Es un dato
# PROVISIONAL: cuando llegue el bueno, se cambia aqui y se vuelve a cargar.
#
# Por defecto BORRA lo simulado que cuelga del marco viejo --respuestas,
# puntajes, citaciones, grupos, anotaciones y contactos-- porque sus ids
# (UDEA-#####) no existen en el marco nuevo y dejarlos descuadra cada cifra de
# la app. Con --conservar se cargan solo las personas y no se borra nada.
# Las METAS no se tocan nunca: son lo unico que se edita a mano.
# -----------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(DBI); library(RPostgres); library(pool); library(readxl)
})

# La fila 5 del Excel es la de encabezados: encima hay tres de titulo y una
# vacia. Si el archivo cambia de forma, esto es lo primero que hay que revisar.
FILAS_TITULO  <- 4
FORMA_SEMILLA <- 2026

# La hoja del marco es SIEMPRE la primera del libro. Antes se buscaba por
# nombre ("Bateria 2026") y eso ataba la carga al titulo que le pusieran al
# export de turno. El libro trae ademas hojas anexas del reporte --la que llego
# tiene una Hoja4 con novedades de personal, comisiones y sabaticos-- y NINGUNA
# se mira: solo la primera entra al marco.

args <- commandArgs(trailingOnly = TRUE)
conservar <- "--conservar" %in% args
f_marco <- args[!startsWith(args, "--")][1]
if (is.na(f_marco)) {
  stop("Uso: Rscript scripts/cargar_marco_bateria.R <archivo.xlsx> [--conservar]",
       call. = FALSE)
}

# Ubicarse en la carpeta de la app sin importar desde donde se invoque.
ruta <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
if (length(ruta) == 1) setwd(dirname(dirname(normalizePath(ruta))))
if (file.exists(".Renviron")) readRenviron(".Renviron")
source("R/utils_db.R", encoding = "UTF-8")
source("R/utils_auth.R", encoding = "UTF-8")
source("R/helpers.R", encoding = "UTF-8")
source("R/utils_seguimiento.R", encoding = "UTF-8")
source("R/utils_contactos.R", encoding = "UTF-8")

paso <- function(...) message("\n== ", ..., " ==")

conexion <- db_probar()
if (!isTRUE(conexion)) stop(conexion, call. = FALSE)
seg_init_db(); cto_init_db()

paso("Lectura")
# `.name_repair = "minimal"` deja los encabezados crudos: si no, readxl renombra
# los repetidos a su manera (CATEGORIA...11) y el nombre de la columna en la
# base dependeria de en que posicion vino. La limpieza se hace aqui, que es
# donde se puede leer.
hojas <- readxl::excel_sheets(normalizePath(f_marco))
hoja  <- hojas[1]
message("  hoja: ", hoja,
        if (length(hojas) > 1)
          paste0("  (se ignoran las anexas: ",
                 paste(hojas[-1], collapse = ", "), ")"))

m <- as.data.frame(readxl::read_excel(normalizePath(f_marco), sheet = hoja,
                                      skip = FILAS_TITULO, col_types = "text",
                                      .name_repair = "minimal"))

# A minusculas con guion bajo, la columna sin encabezado toma el numero de su
# posicion, y los repetidos --el archivo trae OFICIO y CATEGORIA dos veces--
# quedan como oficio, oficio_1, categoria, categoria_1.
crudos <- names(m)
limpio <- tolower(gsub("^_+|_+$", "", gsub("[^A-Za-z0-9]+", "_", crudos)))
limpio[!nzchar(limpio)] <- paste0("col_", which(!nzchar(limpio)))
names(m) <- make.unique(limpio, sep = "_")
m <- m[!is.na(m$identificacion) & nzchar(trimws(m$identificacion)), , drop = FALSE]
message("  ", nrow(m), " personas, ", ncol(m), " columnas del archivo")

rep <- unique(m$identificacion[duplicated(m$identificacion)])
if (length(rep)) {
  stop("IDENTIFICACION repetida (", length(rep), "): ",
       paste(utils::head(rep, 5), collapse = ", "), call. = FALSE)
}

paso("Derivadas")
# La proporcion A/B de lo ya respondido. Si no hay respuestas, todo forma A.
p <- db_get("SELECT forma_cuestionario AS f, count(*)::int AS n
               FROM public.respuestas_procesadas
              WHERE forma_cuestionario IN ('A', 'B') GROUP BY 1")
prop_a <- if (nrow(p) && sum(p$n) > 0) sum(p$n[p$f == "A"]) / sum(p$n) else 1
set.seed(FORMA_SEMILLA)
forma <- sample(c("A", "B"), nrow(m), replace = TRUE, prob = c(prop_a, 1 - prop_a))

texto <- function(x) { x <- trimws(x); ifelse(is.na(x) | !nzchar(x), NA_character_, x) }

m$id_anonimizado     <- texto(m$identificacion)
m$nombre             <- texto(m$nombre)
m$dependencia        <- texto(m$descripcion_dependencia)
m$tipo_dependencia   <- texto(m$descripcion_unidad)
m$tipo_vinculacion   <- texto(m$tipo_vinculacion)
m$nivel_empleo       <- texto(m$grupo)
m$estado_vinculacion <- "Activo"
m$forma_cuestionario <- forma

sin_dep <- sum(is.na(m$dependencia))
if (sin_dep) stop(sin_dep, " personas sin DESCRIPCION_DEPENDENCIA.", call. = FALSE)

message("  dependencias: ", length(unique(m$dependencia)),
        " · unidades: ", length(unique(m$tipo_dependencia)))
message(sprintf("  forma A: %s (%.0f%%) · forma B: %s",
                sum(forma == "A"), 100 * prop_a, sum(forma == "B")))

# Solo las columnas que existen en la tabla: si el archivo trae una nueva, se
# avisa en vez de fallar a mitad de la carga.
cols_bd <- db_get("SELECT column_name FROM information_schema.columns
                    WHERE table_schema = 'seguimiento' AND table_name = 'marco'")$column_name
sobran <- setdiff(names(m), cols_bd)
if (length(sobran)) {
  message("  AVISO: columnas del archivo que la tabla no tiene y no se cargan: ",
          paste(sobran, collapse = ", "))
}
m <- m[, intersect(names(m), cols_bd), drop = FALSE]

paso(if (conservar) "Carga (se conserva lo simulado)" else "Carga (se borra lo simulado)")
db_tx(function(con) {
  if (!conservar) {
    # Orden: lo que referencia primero. puntajes cuelga de respuestas_odk con
    # ON DELETE CASCADE, asi que se va con ella.
    for (t in c("seguimiento.observacionespsicologos", "seguimiento.grupos_aplicador",
                "seguimiento.citaciones", "seguimiento.contactos",
                "public.respuestas_procesadas", "seguimiento.puntajes",
                "public.respuestas_procesadas_odk")) {
      n <- DBI::dbExecute(con, sprintf("DELETE FROM %s", t))
      message("  ", t, ": ", n, " filas borradas")
    }
  }
  DBI::dbExecute(con, "TRUNCATE seguimiento.marco")
  DBI::dbAppendTable(con, DBI::Id(schema = "seguimiento", table = "marco"), m)
})

# Las metas nuevas se siembran con los elegibles de cada dependencia; las que ya
# estaban editadas no se tocan (ON CONFLICT DO NOTHING dentro de la funcion).
seg_sembrar_metas(usuario = "carga del marco real")

paso("Resultado")
print(db_get("
  SELECT (SELECT count(*) FROM seguimiento.marco)::int           AS marco,
         (SELECT count(DISTINCT dependencia) FROM seguimiento.marco)::int AS dependencias,
         (SELECT count(*) FROM public.respuestas_procesadas)::int      AS respuestas,
         (SELECT count(*) FROM seguimiento.citaciones)::int      AS citaciones,
         (SELECT count(*) FROM seguimiento.metas)::int           AS metas"),
  row.names = FALSE)

db_cerrar()
message("\nListo. El marco real quedo cargado.")

#!/usr/bin/env Rscript
# -----------------------------------------------------------------------------
# cargar_marco_bateria.R
# Carga el marco REAL --el export de nomina "Bateria 2026"-- tal cual viene.
#
#   Rscript scripts/cargar_marco_bateria.R <archivo.xlsx> --rehacer-metas
#   Rscript scripts/cargar_marco_bateria.R <archivo.xlsx> --rehacer-metas --corte=2026-05-01
#
# Con un marco nuevo use SIEMPRE --rehacer-metas: las metas por dependencia se
# sembraron con los esperados del marco viejo, y sin rehacerlas Esperados
# quedaria con esas cifras.
#
# Tambien se llega aqui desde preparar_bd.R --marco=, que reconoce el archivo por
# sus encabezados y delega en este script. Las dos formas son validas; esta es
# la directa.
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
#   tipo_vinculacion   TIPO_VINCULACION          nivel_empleo       GRUPO o GRUPO_CATEGORIA
#   estado_vinculacion FECHAINIVINC (ver abajo)  forma_cuestionario FORMA, o el grupo (ver abajo)
#
# Hay dos versiones del export: la primera ("Bateria 2026") trae tres filas de
# titulo y una vacia encima de los encabezados, y la columna GRUPO; la de
# noviembre de 2026 ("bateria_nueva_completa", hoja marco_muestral) trae los
# encabezados en la fila 1 y GRUPO_CATEGORIA, que es el grupo y la categoria
# pegados con un guion ("PROFESIONAL -Profesional 6"): el nivel del empleo es
# lo de antes del guion. La fila de encabezados se busca sola.
#
# estado_vinculacion: el archivo es la nomina vigente, sin bajas. Se espera
# solo a quien se vinculo hasta la fecha de corte (SEG_CORTE_VINCULACION, o
# --corte=): esos son 'Activo' y forman el denominador. Los de despues entran
# como SEG_POST_CORTE --no elegibles-- y, si responden, se decide en Avance si
# su respuesta se usa. Un archivo sin FECHAINIVINC deja a todos activos.
#
# Una persona con dos vinculaciones viene en dos filas. Queda la de inicio mas
# reciente: el marco es una fila por persona.
#
# forma_cuestionario: la Bateria (MinTrabajo y Javeriana, 2010) asigna la forma
# por el tipo de cargo. A: jefaturas, profesionales, tecnicos y tecnologos. B:
# auxiliares, asistentes, operarios y servicios generales. El grupo de la nomina
# (FORMA_GRUPO) los separa. Si el archivo trae una columna FORMA con A o B, manda
# esa columna, persona por persona; si no la trae, la forma sale del grupo. Solo
# cuenta para los esperados A/B de Avance: quien responde se califica con la
# forma que contesto en ODK.
#
# Solo se reemplazan las PERSONAS del marco. No se borra nada mas: respuestas,
# citaciones, contactos, grupos, anotaciones y decisiones se quedan, y quien
# respondio y no esta en el marco nuevo pasa a la lista de "respondieron sin
# estar en el marco" de la pestana Avance. (Antes, sin --conservar, se borraba lo
# que colgaba del marco simulado; ya no hay datos simulados y --conservar se
# acepta pero no cambia nada.)
# -----------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(DBI); library(RPostgres); library(pool); library(readxl)
})

# La fila de encabezados es la primera, entre las MAX_FILAS_TITULO + 1 de
# arriba, que tiene IDENTIFICACION.
MAX_FILAS_TITULO <- 10

# Forma de la Bateria segun el grupo de la nomina. Un grupo que no este aqui
# detiene la carga: hay que decidir su forma antes de cargarlo.
# Los musicos (Trab. Oficial Musico, Banda Sinfonica) van en A por decision del
# equipo: tocar en la banda exige formacion especializada. Revisable.
FORMA_GRUPO <- c(
  "Salario por Ptos"          = "A",  # profesores de carrera y ocasionales
  "Asigancion por categoria"  = "A",  # profesores de catedra
  "PROFESIONAL"               = "A",
  "DIRECTIVO"                 = "A",
  "TECNICO"                   = "A",
  "Trab. Oficial Director"    = "A",  # director de la Banda Sinfonica
  "Trab. Oficial Musico"      = "A",
  "ASISTENCIAL"               = "B",  # auxiliares, secretarias, vigilantes
  "Trab. Oficial Calificado1" = "B",  # aseadores, chaperos, peon, carpintero
  "Trab. Oficial Calificado2" = "B",
  "Trab. Oficial Calificado3" = "B"
)

# La hoja del marco es SIEMPRE la primera del libro. Antes se buscaba por
# nombre ("Bateria 2026") y eso ataba la carga al titulo que le pusieran al
# export de turno. El libro trae ademas hojas anexas del reporte --la que llego
# tiene una Hoja4 con novedades de personal, comisiones y sabaticos-- y NINGUNA
# se mira: solo la primera entra al marco.

args <- commandArgs(trailingOnly = TRUE)
conservar     <- "--conservar" %in% args
rehacer_metas <- "--rehacer-metas" %in% args
corte_arg     <- sub("^--corte=", "", grep("^--corte=", args, value = TRUE))
f_marco <- args[!startsWith(args, "--")][1]
if (is.na(f_marco)) {
  stop("Uso: Rscript scripts/cargar_marco_bateria.R <archivo.xlsx> --rehacer-metas",
       " [--corte=AAAA-MM-DD]", call. = FALSE)
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

corte <- if (length(corte_arg)) as.Date(corte_arg) else SEG_CORTE_VINCULACION
if (is.na(corte)) stop("--corte debe ser una fecha AAAA-MM-DD.", call. = FALSE)

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

arriba <- readxl::read_excel(normalizePath(f_marco), sheet = hoja, col_names = FALSE,
                             n_max = MAX_FILAS_TITULO + 1, col_types = "text",
                             .name_repair = "minimal")
fila_enc <- which(apply(arriba, 1, function(x)
  "IDENTIFICACION" %in% toupper(trimws(x))))[1]
if (is.na(fila_enc)) {
  stop("No se encuentra la columna IDENTIFICACION en las primeras ",
       MAX_FILAS_TITULO + 1, " filas de la hoja ", hoja, ".", call. = FALSE)
}
message("  encabezados en la fila ", fila_enc)

m <- as.data.frame(readxl::read_excel(normalizePath(f_marco), sheet = hoja,
                                      skip = fila_enc - 1, col_types = "text",
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

# Las fechas llegan como texto (col_types = "text"): un numero de serie de
# Excel ("46136") o, si la celda era texto, la fecha escrita. Se guardan ISO.
fecha_excel <- function(x) {
  x <- trimws(x)
  serie <- suppressWarnings(as.numeric(x))
  out <- as.Date(serie, origin = "1899-12-30")
  txt <- is.na(serie) & !is.na(x) & nzchar(x)
  out[txt] <- as.Date(x[txt], tryFormats = c("%Y-%m-%d", "%d/%m/%Y"), optional = TRUE)
  out
}
hay_fecha <- "fechainivinc" %in% names(m)
if (hay_fecha) {
  ini <- fecha_excel(m$fechainivinc)
  if (anyNA(ini)) stop(sum(is.na(ini)), " filas sin FECHAINIVINC legible.", call. = FALSE)
  m$fechainivinc <- format(ini)
  if ("fechafinvinc" %in% names(m)) {
    fin <- fecha_excel(m$fechafinvinc)
    m$fechafinvinc <- ifelse(is.na(fin), NA_character_, format(fin))
  }
}

m$identificacion <- trimws(m$identificacion)
rep <- unique(m$identificacion[duplicated(m$identificacion)])
if (length(rep)) {
  if (!hay_fecha) {
    stop("IDENTIFICACION repetida (", length(rep), "): ",
         paste(utils::head(rep, 5), collapse = ", "), call. = FALSE)
  }
  # La vinculacion de inicio mas reciente. A igual fecha, la fila cuyo grupo
  # cuadra con el tipo de vinculacion --un profesor con su grupo de
  # profesorado, no con PROFESIONAL--, y si aun empatan, la ultima.
  grupo <- if ("grupo" %in% names(m)) m$grupo else sub("\\s*-.*$", "", m$grupo_categoria)
  coherente <- grepl("^Profesor", trimws(m$tipo_vinculacion)) ==
    (trimws(grupo) %in% c("Salario por Ptos", "Asigancion por categoria"))
  fila  <- seq_len(nrow(m))
  queda <- fila[order(m$identificacion, m$fechainivinc, coherente, fila,
                      decreasing = TRUE)]
  queda <- queda[!duplicated(m$identificacion[queda])]
  m <- m[sort(queda), , drop = FALSE]
  message("  ", length(rep), " cedulas con dos o mas filas: queda la de inicio mas reciente")
}
message("  ", nrow(m), " personas")

paso("Derivadas")
texto <- function(x) { x <- trimws(x); ifelse(is.na(x) | !nzchar(x), NA_character_, x) }

m$id_anonimizado     <- texto(m$identificacion)
m$nombre             <- texto(m$nombre)
m$dependencia        <- texto(m$descripcion_dependencia)
m$tipo_dependencia   <- texto(m$descripcion_unidad)
m$tipo_vinculacion   <- texto(m$tipo_vinculacion)
m$nivel_empleo       <- texto(if ("grupo" %in% names(m)) m$grupo
                              else sub("\\s*-.*$", "", m$grupo_categoria))
m$estado_vinculacion <- if (hay_fecha)
  ifelse(as.Date(m$fechainivinc) <= corte, "Activo", SEG_POST_CORTE) else "Activo"
if ("forma" %in% names(m)) {
  # Columna FORMA del archivo: A o B por persona.
  m$forma_cuestionario <- toupper(texto(m$forma))
  mala <- which(!m$forma_cuestionario %in% c("A", "B"))
  if (length(mala)) {
    stop(length(mala), " personas con FORMA vacia o distinta de A y B (fila de la ",
         "primera: cedula ", m$identificacion[mala[1]], ").", call. = FALSE)
  }
  message("  forma A/B: de la columna FORMA del archivo")
} else {
  m$forma_cuestionario <- unname(FORMA_GRUPO[m$nivel_empleo])
  sin_forma <- unique(m$nivel_empleo[is.na(m$forma_cuestionario)])
  if (length(sin_forma)) {
    stop("Grupo sin forma A/B en FORMA_GRUPO: ",
         paste(sin_forma, collapse = ", "),
         ". Agregue una columna FORMA (A o B) al archivo, o el grupo a FORMA_GRUPO.",
         call. = FALSE)
  }
  message("  forma A/B: deducida del grupo de la nomina (FORMA_GRUPO)")
}

sin_dep <- sum(is.na(m$dependencia))
if (sin_dep) stop(sin_dep, " personas sin DESCRIPCION_DEPENDENCIA.", call. = FALSE)

message("  dependencias: ", nrow(unique(m[, c("dependencia", "tipo_dependencia")])),
        " · unidades: ", length(unique(m$tipo_dependencia)))
message(sprintf("  esperados (vinculados hasta el %s): %s · despues del corte: %s",
                format(corte, "%d/%m/%Y"), sum(m$estado_vinculacion == "Activo"),
                sum(m$estado_vinculacion != "Activo")))
act <- m$estado_vinculacion == "Activo"
message(sprintf("  esperados forma A: %s · forma B: %s",
                sum(m$forma_cuestionario[act] == "A"),
                sum(m$forma_cuestionario[act] == "B")))

# Solo las columnas que existen en la tabla: si el archivo trae una nueva, se
# avisa en vez de fallar a mitad de la carga.
cols_bd <- db_get("SELECT column_name FROM information_schema.columns
                    WHERE table_schema = 'seguimiento' AND table_name = 'marco'")$column_name
sobran <- setdiff(names(m), c(cols_bd, "forma"))  # FORMA ya quedo en forma_cuestionario
if (length(sobran)) {
  message("  AVISO: columnas del archivo que la tabla no tiene y no se cargan: ",
          paste(sobran, collapse = ", "))
}
m <- m[, intersect(names(m), cols_bd), drop = FALSE]

paso("Carga")
invisible(db_tx(function(con) {
  DBI::dbExecute(con, "TRUNCATE seguimiento.marco")
  DBI::dbAppendTable(con, DBI::Id(schema = "seguimiento", table = "marco"), m)
  # Con un marco distinto las metas viejas no cuadran con nada: --rehacer-metas
  # las borra, y abajo se siembran otra vez con los esperados de cada dependencia.
  # Se pierde lo que se hubiera editado a mano.
  if (rehacer_metas) {
    n <- DBI::dbExecute(con, "DELETE FROM seguimiento.metas")
    message("  seguimiento.metas: ", n, " filas borradas (--rehacer-metas)")
  }
}))

# Las metas nuevas se siembran con los elegibles de cada dependencia; las que ya
# estaban editadas no se tocan (ON CONFLICT DO NOTHING dentro de la funcion).
invisible(seg_sembrar_metas(usuario = "carga del marco real"))

# La vista marco_completo se rehace al arrancar la app, pero si el marco trae
# columnas nuevas la vieja ya no le corresponde: se rehace aqui tambien.
invisible(seg_crear_marco_completo())

paso("Resultado")
print(db_get("
  SELECT (SELECT count(*) FROM seguimiento.marco)::int           AS marco,
         (SELECT count(*) FROM seguimiento.marco
           WHERE estado_vinculacion = 'Activo')::int             AS esperados,
         (SELECT count(*) FROM (SELECT DISTINCT dependencia, tipo_dependencia FROM seguimiento.marco) d)::int AS dependencias,
         (SELECT count(*) FROM public.respuestas_procesadas)::int      AS respuestas,
         (SELECT count(*) FROM seguimiento.citaciones)::int      AS citaciones,
         (SELECT count(*) FROM seguimiento.metas)::int           AS metas"),
  row.names = FALSE)

db_cerrar()
message("\nListo. El marco real quedo cargado.")

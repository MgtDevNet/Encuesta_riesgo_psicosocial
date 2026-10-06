#!/usr/bin/env Rscript
# -----------------------------------------------------------------------------
# preparar_bd.R
# Deja la base lista en un equipo nuevo. Lo unico que hay que traer es
# PostgreSQL corriendo y los dos insumos externos: el MARCO MUESTRAL y el
# EXPORT DE ODK. Todo lo demas --esquemas, tablas, indices, el tipo
# nivel_riesgo, la tabla derivada public.respuestas_procesadas y las metas iniciales--
# lo genera este script.
#
#   Rscript scripts/preparar_bd.R                          # verifica y deriva
#   Rscript scripts/preparar_bd.R --marco=Marco.xlsx       # + carga el marco
#   Rscript scripts/preparar_bd.R --odk=respuestas.csv     # + carga ODK
#   Rscript scripts/preparar_bd.R --marco=M.xlsx --odk=R.csv   # todo de una
#   Rscript scripts/preparar_bd.R --citaciones=agenda.xlsx     # + carga la agenda
#
#   Las citaciones son un tercer insumo, opcional: la app funciona sin ellas y,
#   cuando estan, dibuja la linea de citados y el grupo de citados sin responder.
#
#   --solo-esquema   crea las tablas vacias y no deriva nada (util para dejar
#                    la base lista ANTES de tener los archivos)
#   --limpiar        solo con un marco de nomina: borra lo que cuelga del marco
#                    viejo (ver el paso 3)
#
# --marco= acepta los DOS formatos que existen --el canonico y el export de
# nomina-- y reconoce cual es cual. Es el unico comando que hay que recordar:
# no hay que saber de antemano que archivo llego. El paso 3 lo explica.
#
# Es idempotente: se puede volver a correr cuantas veces haga falta. El marco se
# reemplaza entero, ODK se hace por upsert y las METAS ya editadas no se tocan.
# -----------------------------------------------------------------------------

# --- 0. Ubicacion y paquetes --------------------------------------------------
# El script se invoca desde la raiz de la app (por las rutas de Diccionarios/),
# pero si alguien lo llama desde otro lado se acomoda solo.
if (!file.exists("R/utils_db.R")) {
  arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(arg)) setwd(dirname(dirname(normalizePath(sub("^--file=", "", arg)))))
}
if (!file.exists("R/utils_db.R"))
  stop("Ejecute el script desde la carpeta de la app.", call. = FALSE)

# Los que necesita la app mas los que necesita conectar_bd.R para calificar la
# escala. Se revisan todos aqui y de una vez: es mas util una sola lista que
# descubrirlos de a uno en mitad del proceso.
PAQUETES <- c("shiny", "bslib", "DBI", "RPostgres", "pool", "scrypt", "stringi",
              "officer", "flextable",
              "dplyr", "stringr", "tidyverse", "readxl", "magrittr", "openssl")

faltan_paq <- PAQUETES[!vapply(PAQUETES, requireNamespace, logical(1),
                               quietly = TRUE)]
if (length(faltan_paq)) {
  stop("Faltan paquetes de R. Instalelos con:\n  install.packages(c(",
       paste(sprintf('"%s"', faltan_paq), collapse = ", "), "))",
       call. = FALSE)
}

suppressPackageStartupMessages({
  library(DBI); library(RPostgres); library(pool); library(scrypt)
  library(stringi)
})

if (file.exists(".Renviron")) readRenviron(".Renviron")
source("R/helpers.R",            encoding = "UTF-8")
source("R/utils_db.R",           encoding = "UTF-8")
source("R/utils_auth.R",         encoding = "UTF-8")
source("R/utils_contactos.R",    encoding = "UTF-8")
source("R/utils_seguimiento.R",  encoding = "UTF-8")

args <- commandArgs(trailingOnly = TRUE)
opcion <- function(nombre) {
  v <- grep(paste0("^--", nombre, "="), args, value = TRUE)
  if (length(v)) sub(paste0("^--", nombre, "="), "", v[length(v)]) else NULL
}
f_marco      <- opcion("marco")
f_odk        <- opcion("odk")
f_cit        <- opcion("citaciones")
solo_esquema <- "--solo-esquema" %in% args
limpiar      <- "--limpiar" %in% args

desconocidos <- setdiff(grep("^--", args, value = TRUE),
                        c(grep("^--(marco|odk|citaciones)=", args, value = TRUE),
                          "--solo-esquema", "--limpiar"))
if (length(desconocidos))
  stop("Opcion no reconocida: ", paste(desconocidos, collapse = ", "),
       call. = FALSE)

for (f in c(f_marco, f_odk, f_cit))
  if (!file.exists(f)) stop("No se encuentra el archivo: ", f, call. = FALSE)

paso <- function(...) message("\n== ", ...)


# --- 1. Conexion --------------------------------------------------------------
paso("Conexion")
conexion <- db_probar()
if (!isTRUE(conexion))
  stop(conexion,
       "\n\nRevise que PostgreSQL este arriba y que exista la base. En un equipo",
       "\nnuevo suele bastar con:",
       "\n  sudo -u postgres createdb -O $USER riesgo_psicosocial",
       "\nSi la conexion no es por socket local, ponga PG_HOST, PG_PORT, PG_DB,",
       "\nPG_USER y PG_PASSWORD en un archivo .Renviron en esta carpeta.",
       call. = FALSE)
cfg <- db_config()
message("  ", cfg$user, "@", cfg$host, ":", cfg$port, "/", cfg$dbname, " OK")


# --- 2. Esquemas y tablas -----------------------------------------------------
# Las tres funciones son las mismas que corre la app al arrancar. Se llaman aqui
# para que la base quede completa aunque nadie haya abierto todavia la Shiny.
paso("Esquemas y tablas")
auth_init_db()   # auth.usuarios, auth.bitacora_accesos
seg_init_db()    # seguimiento: marco, respuestas_odk, metas
cto_init_db()    # seguimiento.contactos
message("  auth y seguimiento listos")


# --- 3. Carga del marco muestral ----------------------------------------------
# Se reemplaza entero, no se hace upsert: el marco es una foto de la nomina en
# una fecha, y una persona que ya no esta tiene que desaparecer del denominador.
# Las metas, que son lo unico editado a mano, viven en otra tabla y no se rozan.
#
# Llegan dos formatos distintos y este paso reconoce cual es cual:
#
#   CANONICO  la hoja Marco_muestral --o un CSV-- con las columnas ya nombradas
#             como las de la tabla. Se carga aqui mismo.
#   NOMINA    el export "Bateria 2026": los encabezados en la fila 5 y los
#             nombres del sistema de personal, que no se parecen a los de la
#             tabla. Lo carga cargar_marco_bateria.R, que sabe derivar las
#             columnas que consulta la app. Aqui solo se reconoce y se delega.
#
# Antes esto exigia las catorce columnas canonicas y nada mas, asi que el
# archivo real --el unico que existe hoy-- no pasaba: se detenia con "le faltan
# columnas" listando las catorce, y quien lo corriera no tenia como saber que el
# script que si lo carga es el otro.
#
# Del formato canonico ahora solo se exigen id_anonimizado y dependencia, que
# son las dos NOT NULL de la tabla. Las otras doce se cargan si vienen y se
# avisan si no: ninguna fuente real las trae todas --la nomina no sabe de sedes
# ni de modalidad de trabajo-- y la app oculta sola los filtros sin dato.

MARCO_HOJA       <- "Marco_muestral"
MARCO_MINIMAS    <- c("id_anonimizado", "dependencia")
MARCO_OPCIONALES <- c("tipo_dependencia", "nivel_jerarquico_dependencia",
                      "centro_costo", "sede_seccional", "municipio",
                      "tipo_vinculacion", "nivel_empleo", "forma_cuestionario",
                      "estado_vinculacion", "dedicacion", "modalidad_trabajo",
                      "trabaja_por_turnos")

# Como se reconoce la nomina: sus encabezados viven en la fila 5 --encima hay
# tres de titulo y una vacia-- y estas dos columnas no existen en el formato
# canonico. Tiene que coincidir con FILAS_TITULO de cargar_marco_bateria.R.
NOMINA_FILAS_TITULO <- 4
NOMINA_SENAL        <- c("IDENTIFICACION", "DESCRIPCION_DEPENDENCIA")
NOMINA_SCRIPT       <- "scripts/cargar_marco_bateria.R"

# Los encabezados de una hoja sin traerse las filas. `.name_repair = "minimal"`
# los deja crudos: si no, readxl renombra los repetidos --la nomina trae OFICIO
# y CATEGORIA dos veces-- y la senal dependeria de eso.
# n_max = 1 y no 0: hay versiones de readxl donde pedir cero filas falla, y aqui
# lo unico que importa son los nombres.
#
# El error NO se descarta. Descartarlo es lo que convierte un problema de
# entorno --un readxl viejo, un archivo a medio copiar-- en un "no se reconoce
# el formato", que manda a revisar el Excel cuando el Excel esta bien.
marco_encabezados <- function(f, hoja, saltar) {
  tryCatch(
    names(readxl::read_excel(f, sheet = hoja, skip = saltar, n_max = 1,
                             .name_repair = "minimal")),
    error = function(e) structure(character(0), fallo = conditionMessage(e)))
}

# El mismo mensaje sirve para el archivo que no se reconoce y para el que ni
# siquiera se deja leer: en los dos casos lo util es recordar cuales son los dos
# formatos que existen, no el error interno de readxl o de read.csv.
marco_lista <- function(x, n = 12) {
  fallo <- attr(x, "fallo")
  if (!is.null(fallo)) return(paste0("no se pudieron leer -> ", fallo))
  x <- x[nzchar(trimws(x))]
  if (!length(x)) return("(ninguno)")
  paste0(paste(utils::head(x, n), collapse = ", "),
         if (length(x) > n) paste0(", ... (", length(x), " en total)"))
}

# Que se encontro de verdad dentro del archivo. Sin esto el mensaje dice que no
# reconoce el formato pero no que vio, y no hay forma de arreglarlo sin abrir el
# Excel a mano --que es justo lo que no se puede hacer en el servidor.
marco_diagnostico <- function(f) {
  if (!grepl("\\.xlsx?$", f, ignore.case = TRUE)) {
    cab <- tryCatch(names(utils::read.csv(f, nrows = 1, check.names = FALSE)),
                    error = function(e) character(0))
    return(paste0("\n  Es un CSV. Sus encabezados son:\n    ", marco_lista(cab)))
  }
  hojas <- tryCatch(readxl::excel_sheets(f),
                    error = function(e)
                      structure(character(0), fallo = conditionMessage(e)))
  # Que el libro no se deje ni abrir es informacion, no un caso sin salida: pasa
  # con una copia a medias o con un .xls disfrazado de .xlsx.
  if (!length(hojas))
    return(paste0("\n  El libro no se pudo abrir: ",
                  if (is.null(attr(hojas, "fallo"))) "no tiene hojas"
                  else attr(hojas, "fallo"),
                  "\n  Pesa ", file.size(f), " bytes. Revise que la copia este",
                  " completa y que sea .xlsx de verdad.",
                  "\n  (readxl ", as.character(utils::packageVersion("readxl")),
                  ", ", R.version.string, ")"))
  h <- hojas[1]
  paste0(
    "\n  El libro tiene ", length(hojas), " hoja(s): ", marco_lista(hojas),
    "\n  Solo se mira la primera (", h, "), y sus encabezados son:",
    "\n    fila 1: ", marco_lista(marco_encabezados(f, h, 0)),
    "\n    fila ", NOMINA_FILAS_TITULO + 1, ": ",
    marco_lista(marco_encabezados(f, h, NOMINA_FILAS_TITULO)),
    if (length(hojas) > 1)
      paste0("\n  Si el marco esta en otra hoja, pasela de primera en el libro."),
    "\n  (readxl ", as.character(utils::packageVersion("readxl")),
    ", ", R.version.string, ")")
}

marco_no_reconocido <- function(f, detalle = NULL) {
  paste0("No se reconoce el formato del marco: ", basename(f),
         if (!is.null(detalle)) paste0("\n  (", detalle, ")"),
         marco_diagnostico(f),
         "\n  Se esperaba una de estas dos cosas:",
         "\n    - el marco canonico: la hoja ", MARCO_HOJA, " (o un CSV) con al",
         "\n      menos las columnas ", paste(MARCO_MINIMAS, collapse = " y "),
         "\n    - el export de nomina: encabezados en la fila ",
         NOMINA_FILAS_TITULO + 1, " y las columnas",
         "\n      ", paste(NOMINA_SENAL, collapse = " y "))
}

# Devuelve el formato ("canonico", "nomina" o NA) y la hoja donde esta.
marco_formato <- function(f) {
  # Un CSV no puede ser la nomina: ese export siempre llega en Excel, con sus
  # tres filas de titulo, y un CSV no tendria como traerlas.
  if (!grepl("\\.xlsx?$", f, ignore.case = TRUE))
    return(list(formato = "canonico", hoja = NA_character_))

  hojas <- readxl::excel_sheets(f)
  if (MARCO_HOJA %in% hojas)
    return(list(formato = "canonico", hoja = MARCO_HOJA))

  # La hoja del marco es SIEMPRE la primera, y solo esa se mira. Recorrer el
  # libro entero seria peor: el export de nomina trae hojas anexas del reporte
  # --una Hoja4 con novedades de personal, keyed por otra cosa y con gente que
  # ni siquiera esta en la nomina-- y basta con que una de ellas se pareciera a
  # un marco para cargar como personas algo que no lo es. Lo que no este en la
  # primera hoja no entra.
  h <- hojas[1]
  if (all(MARCO_MINIMAS %in% marco_encabezados(f, h, 0)))
    return(list(formato = "canonico", hoja = h))
  senal <- toupper(trimws(marco_encabezados(f, h, NOMINA_FILAS_TITULO)))
  if (all(NOMINA_SENAL %in% senal))
    return(list(formato = "nomina", hoja = h))

  list(formato = NA_character_, hoja = NA_character_)
}

if (!is.null(f_marco)) {
  paso("Marco muestral")
  tipo <- marco_formato(f_marco)

  if (is.na(tipo$formato)) stop(marco_no_reconocido(f_marco), call. = FALSE)

  if (identical(tipo$formato, "nomina")) {
    message("  formato: export de nomina (hoja: ", tipo$hoja, ")")
    message("  lo carga ", NOMINA_SCRIPT, ", que deriva las columnas de la app")
    if (!file.exists(NOMINA_SCRIPT))
      stop("No se encuentra ", NOMINA_SCRIPT, call. = FALSE)

    # Por defecto se CONSERVA lo que cuelga del marco --respuestas, citaciones,
    # contactos--: este script se anuncia idempotente, y recargar el mismo marco
    # no puede llevarse por delante el export de ODK que ya esta cargado. Lo que
    # quede huerfano se avisa en el resumen del paso 7. Con --limpiar se borra,
    # que es lo que hace falta cuando el marco nuevo no comparte un solo id con
    # el viejo; corrido suelto, cargar_marco_bateria.R borra por defecto.
    extra <- if (limpiar) character(0) else "--conservar"
    message(if (limpiar) "  --limpiar: se borra lo que cuelga del marco viejo"
            else         "  se conserva lo que cuelga del marco (use --limpiar para borrarlo)")

    codigo <- system2(file.path(R.home("bin"), "Rscript"),
                      c(shQuote(NOMINA_SCRIPT), shQuote(normalizePath(f_marco)),
                        extra))
    if (codigo != 0)
      stop("La carga del marco fallo (codigo ", codigo, "). La base quedo como ",
           "estaba: ese script carga dentro de una transaccion.", call. = FALSE)

  } else {
    message("  formato: canonico",
            if (!is.na(tipo$hoja)) paste0(" (hoja: ", tipo$hoja, ")") else " (CSV)")

    # Un CSV no se puede reconocer antes de leerlo --marco_formato() lo da por
    # canonico sin mirarlo-- asi que si no es tabular revienta aqui, y el error
    # de read.csv ("more columns than column names") no le dice nada a nadie.
    m <- tryCatch(
      if (grepl("\\.xlsx?$", f_marco, ignore.case = TRUE)) {
        as.data.frame(readxl::read_excel(f_marco, sheet = tipo$hoja))
      } else {
        utils::read.csv(f_marco, stringsAsFactors = FALSE, check.names = FALSE,
                        colClasses = "character", encoding = "UTF-8")
      },
      error = function(e)
        stop(marco_no_reconocido(f_marco, conditionMessage(e)), call. = FALSE))

    ausentes <- setdiff(MARCO_MINIMAS, names(m))
    if (length(ausentes))
      stop("Al marco le faltan columnas que no pueden faltar: ",
           paste(ausentes, collapse = ", "), call. = FALSE)

    faltan <- setdiff(MARCO_OPCIONALES, names(m))
    if (length(faltan))
      message("  AVISO: columnas que el archivo no trae y quedan vacias (sus\n",
              "  filtros se ocultan solos en la app): ",
              paste(faltan, collapse = ", "))

    m <- m[, intersect(c(MARCO_MINIMAS, MARCO_OPCIONALES), names(m)),
           drop = FALSE]

    # Sin estado_vinculacion no hay elegibles, y los elegibles son el denominador
    # de todo el seguimiento: la app mostraria cero avance en cada dependencia
    # sin que nada fallara. Se asume activo --que es lo que significa estar en
    # una foto de la nomina-- igual que en cargar_marco_bateria.R.
    if (!"estado_vinculacion" %in% names(m)) {
      m$estado_vinculacion <- "Activo"
      message("  sin estado_vinculacion: todos entran como Activo")
    }

    # Un id repetido rompe la llave primaria a mitad de la carga, cuando la tabla
    # ya esta vacia. Mejor detenerse antes de tocarla.
    rep <- unique(m$id_anonimizado[duplicated(m$id_anonimizado)])
    if (length(rep))
      stop("id_anonimizado repetido en el marco (", length(rep), "): ",
           paste(utils::head(rep, 5), collapse = ", "), call. = FALSE)

    db_tx(function(con) {
      DBI::dbExecute(con, "TRUNCATE seguimiento.marco")
      DBI::dbAppendTable(con, DBI::Id(schema = "seguimiento", table = "marco"), m)
    })
    message("  marco: ", nrow(m), " personas, ",
            length(unique(m$dependencia)), " dependencias")
  }
} else if (limpiar) {
  message("\n  AVISO: --limpiar no hace nada sin --marco=; se ignora.")
}


# --- 4. Carga del export de ODK -----------------------------------------------
# La hace cargar_respuestas_odk.sh, que ya resuelve lo delicado: el orden de las
# columnas del CSV, los nombres de ODK y el huso horario del \copy.
if (!is.null(f_odk)) {
  paso("Respuestas de ODK")
  sh <- "scripts/cargar_respuestas_odk.sh"
  if (!file.exists(sh)) stop("No se encuentra ", sh, call. = FALSE)

  # El .sh llama a psql, que no conoce las variables PG_* de la app sino las
  # PG* de libpq. Se traducen aqui para que la carga vaya a la misma base a la
  # que acaba de conectarse este script y no a la que adivine psql.
  entorno <- c(sprintf("PG_DB=%s",      cfg$dbname),
               sprintf("PGDATABASE=%s", cfg$dbname),
               sprintf("PGHOST=%s",     cfg$host),
               sprintf("PGPORT=%s",     cfg$port),
               sprintf("PGUSER=%s",     cfg$user))
  if (nzchar(cfg$password))
    entorno <- c(entorno, sprintf("PGPASSWORD=%s", cfg$password))

  codigo <- system2("bash", c(shQuote(sh), shQuote(normalizePath(f_odk))),
                    env = entorno)
  if (codigo != 0)
    stop("La carga de ODK fallo (codigo ", codigo, "). La base quedo como ",
         "estaba: el script carga todo dentro de una transaccion.", call. = FALSE)
}


# --- 4b. Carga de las citaciones ----------------------------------------------
# La agenda llega en una base aparte (fecha, hora de inicio y final programadas,
# id de la persona, nombre y link). Se reemplaza entera, como el marco: es una
# foto de la programacion. seg_cit_normalizar() lee los encabezados con o sin
# tildes y espacios, y se detiene ANTES de tocar la tabla si alguna fila no se
# puede leer. Las franjas pasadas de cupo y los ids que no estan en el marco se
# avisan pero no detienen la carga: la agenda es la que es.
if (!is.null(f_cit)) {
  paso("Citaciones")
  cit <- seg_cit_normalizar(seg_cit_leer(f_cit))

  fuera <- seg_cit_fuera_marco(cit)
  if (length(fuera)) {
    message("  AVISO: ", length(fuera), " personas citadas no estan en el marco y no ",
            "cuentan en ningun avance (", paste(utils::head(fuera, 5), collapse = ", "),
            if (length(fuera) > 5) ", ..." else "", ").\n  Revise que la columna ",
            "de id traiga el id_anonimizado y no la cedula.")
  }

  cap <- seg_cit_capacidad(cit)
  if (nrow(cap)) {
    message(sprintf("  AVISO: %s franjas pasan la capacidad de %s personas o %s grupos por hora:",
                    nrow(cap), SEG_CIT_POR_HORA, SEG_CIT_GRUPOS_HORA))
    for (i in utils::head(seq_len(nrow(cap)), 10))
      message(sprintf("    %s  %s personas en %s grupos",
                      cap$franja[i], cap$personas[i], cap$grupos[i]))
  }

  huerfanos <- seg_grupos_huerfanos(cit)
  if (nrow(huerfanos)) {
    message("  AVISO: ", nrow(huerfanos), " grupos con aplicador asignado no estan en ",
            "esta agenda y pierden la asignacion.")
  }

  seg_cit_guardar(cit)
  message("  citaciones: ", nrow(cit), " de ", length(unique(cit$id_anonimizado)),
          " personas, del ", format(min(cit$fecha), "%d/%m/%Y"),
          " al ", format(max(cit$fecha), "%d/%m/%Y"))
}


# --- 5. Tabla derivada public.respuestas_procesadas ---------------------------------
# conectar_bd.R lee public.respuestas_procesadas_odk, califica la escala con los
# diccionarios de Diccionarios/ y reescribe public.respuestas_procesadas, que es la
# tabla que consulta la app. Se corre en un proceso aparte --tal como esta
# pensado-- para no arrastrar aqui tidyverse ni su conexion propia.
if (solo_esquema) {
  paso("Tablas vacias creadas (--solo-esquema)")
  message("  no se derivo public.respuestas_procesadas")
} else {
  n_odk <- seg_conteo("public.respuestas_procesadas_odk")
  if (!isTRUE(n_odk > 0)) {
    paso("public.respuestas_procesadas: nada que derivar")
    message("  public.respuestas_procesadas_odk esta vacia. Cargue el export de ODK y",
            "\n  vuelva a correr este script.")
  } else {
    paso("Calificando la escala y reescribiendo public.respuestas_procesadas")
    message("  ", n_odk, " formularios; puede tardar un par de minutos...")
    codigo <- system2(file.path(R.home("bin"), "Rscript"), "conectar_bd.R")
    if (codigo != 0)
      stop("conectar_bd.R fallo (codigo ", codigo, "). public.respuestas_procesadas ",
           "quedo como estaba.", call. = FALSE)

    # conectar_bd.R borra la vista seguimiento.estado_persona para poder soltar
    # la tabla de la que cuelga. Se reconstruye aqui y no se deja para el
    # arranque de la app: entre la carga y el primer arranque, cualquier consulta
    # de informe contra la vista fallaria sin que nadie entienda por que.
    if (isTRUE(seg_crear_vista_estado()))
      message("  vista seguimiento.estado_persona reconstruida")
  }
}


# --- 6. Metas iniciales -------------------------------------------------------
if (isTRUE(seg_conteo("seguimiento.marco") > 0)) {
  paso("Metas")
  nuevas <- seg_sembrar_metas()
  message("  ", nuevas, " dependencias nuevas con meta inicial (las ya ",
          "existentes no se tocaron)")
}


# --- 7. Resumen ---------------------------------------------------------------
paso("Estado de la base")
for (t in c("seguimiento.marco", "public.respuestas_procesadas_odk",
            "public.respuestas_procesadas", "seguimiento.metas",
            "seguimiento.contactos", "seguimiento.citaciones", "auth.usuarios")) {
  n <- seg_conteo(t)
  message(sprintf("  %-28s %s", t, if (is.na(n)) "NO EXISTE" else n))
}

if (isTRUE(seg_conteo("public.respuestas_procesadas") > 0)) {
  # as.integer(): RPostgres devuelve count(*) como entero de 64 bits, que
  # message() imprimiria como un numero sin sentido.
  huerfanas <- as.integer(db_get("
    SELECT count(*) AS n FROM public.respuestas_procesadas r
     WHERE NOT EXISTS (SELECT 1 FROM seguimiento.marco m
                        WHERE m.id_anonimizado = r.id_anonimizado)")$n)
  if (huerfanas > 0)
    message("\n  AVISO: ", huerfanas, " respuestas sin persona en el marco. ",
            "Esas encuestas\n  no cuentan en ningun avance porque el ",
            "denominador es el marco.")
}

pendientes <- seg_faltantes()
if (length(pendientes)) {
  message("\nTodavia falta:")
  for (p in pendientes) message("  - ", p)
} else if (!auth_hay_usuarios()) {
  message("\nLa base esta lista. Falta el primer usuario, que se crea al abrir",
          "\nla app: aparece el formulario de primer arranque en vez de la",
          "\npantalla de ingreso. Desde la terminal tambien se puede:",
          "\n  Rscript scripts/gestionar_usuarios.R crear <usuario> \"Nombre Completo\"",
          "\n\nLevante la app con:",
          "\n  R -e 'shiny::runApp(\".\", launch.browser = TRUE)'")
} else {
  message("\nTodo listo. Levante la app con:",
          "\n  R -e 'shiny::runApp(\".\", launch.browser = TRUE)'")
}

db_cerrar()

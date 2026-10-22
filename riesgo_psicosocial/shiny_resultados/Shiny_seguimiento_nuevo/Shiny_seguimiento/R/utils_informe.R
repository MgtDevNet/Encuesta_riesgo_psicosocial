# -----------------------------------------------------------------------------
# utils_informe.R
# Informe individual de resultados en Word, sobre la plantilla del formato de
# entrega (plantillas/informe_individual.docx). Los datos salen de la vista
# public.respuestas_procesadas_exportacion_ind (RES_VISTA_EXPORTACION_IND).
#
# Se llenan los datos del trabajador, la tabla de resultados (puntaje
# transformado y nivel) y la fecha de elaboracion. Los datos del evaluador, las
# observaciones y las recomendaciones quedan en blanco: los escribe el
# psicologo en el Word antes de firmar.
#
# La plantilla es de la forma A. Para la B se cambia el titulo y se quitan las
# tres filas de las dimensiones que solo tiene la A (RES_SOLO_A).
#
# Se escribe sobre el XML de la plantilla y no con body_replace_*: asi el Word
# conserva tal cual las celdas combinadas, bordes y fuentes del formato.
# -----------------------------------------------------------------------------

INF_PLANTILLA <- file.path("plantillas", "informe_individual.docx")
INF_EMPRESA   <- "Universidad de Antioquia"

# Fila de la tabla de resultados (el texto que trae la plantilla) -> rotulo de
# la medida en la vista. El nivel es "<prefijo> <rotulo>" y el puntaje
# "Puntaje <rotulo>" (ver res_crear_vista_export_una()). Los textos de la
# plantilla no siempre son los de la base: "Nivel de responsabilidad del cargo"
# es Exigencias de responsabilidad del cargo.
INF_FILAS <- list(
  "Características del liderazgo"           = c("Dim.", RES_DIMS[["caracteristicas_liderazgo"]]),
  "Relaciones sociales en el trabajo"       = c("Dim.", RES_DIMS[["relaciones_sociales_trabajo"]]),
  "Retroalimentación del desempeño"         = c("Dim.", RES_DIMS[["retroalimentacion_desempeno"]]),
  "Relación con los colaboradores"          = c("Dim.", RES_DIMS[["relacion_colaboradores"]]),
  "Liderazgo y relaciones sociales en el trabajo" =
    c("Dom.", RES_DOMS[["liderazgo_relaciones_sociales_trabajo"]]),
  "Claridad de rol"                         = c("Dim.", RES_DIMS[["claridad_rol"]]),
  "Capacitación"                            = c("Dim.", RES_DIMS[["capacitacion"]]),
  "Oportunidades para el uso y desarrollo de habilidades y conocimientos" =
    c("Dim.", RES_DIMS[["oportunidades_uso_desarrollo_habilidades"]]),
  "Participación y manejo del cambio"       = c("Dim.", RES_DIMS[["participacion_manejo_cambio"]]),
  "Control y autonomía sobre el trabajo"    = c("Dim.", RES_DIMS[["control_autonomia_trabajo"]]),
  "Control sobre el trabajo"                = c("Dom.", RES_DOMS[["control_trabajo"]]),
  "Demandas ambientales y de esfuerzo físico" =
    c("Dim.", RES_DIMS[["demandas_ambientales_esfuerzo_fisico"]]),
  "Nivel de responsabilidad del cargo"      = c("Dim.", RES_DIMS[["exigencias_responsabilidad_cargo"]]),
  "Consistencia del rol"                    = c("Dim.", RES_DIMS[["consistencia_rol"]]),
  "Demandas emocionales"                    = c("Dim.", RES_DIMS[["demandas_emocionales"]]),
  "Demandas de la jornada de trabajo"       = c("Dim.", RES_DIMS[["demandas_jornada_trabajo"]]),
  "Influencia del trabajo sobre el entorno extralaboral" =
    c("Dim.", RES_DIMS[["influencia_trabajo_entorno_extralaboral"]]),
  "Demandas cuantitativas"                  = c("Dim.", RES_DIMS[["demandas_cuantitativas"]]),
  "Demandas de carga mental"                = c("Dim.", RES_DIMS[["demandas_carga_mental"]]),
  "Demandas del trabajo"                    = c("Dom.", RES_DOMS[["demandas_trabajo"]]),
  "Reconocimiento y compensación"           = c("Dim.", RES_DIMS[["reconocimiento_compensacion"]]),
  "Recompensas derivadas de la pertenencia a la organización y del trabajo que se realiza" =
    c("Dim.", RES_DIMS[["recompensas_derivadas_pertenencia_organizacion"]]),
  "Recompensas"                             = c("Dom.", RES_DOMS[["recompensas"]]),
  "Puntaje total Intralaboral"              = c("", "Total intralaboral"),
  "Tiempo fuera del trabajo"                = c("Extra.", RES_EXTRA[["balance_vida_laboral_familiar"]]),
  "Relaciones familiares"                   = c("Extra.", RES_EXTRA[["relaciones_familiares"]]),
  "Comunicación y relaciones interpersonales" =
    c("Extra.", RES_EXTRA[["comunicacion_relaciones_interpersonales"]]),
  "Situación económica"                     = c("Extra.", RES_EXTRA[["situacion_economica_grupo_familiar"]]),
  "Características de la vivienda y de su entorno" =
    c("Extra.", RES_EXTRA[["caracteristicas_vivienda_entorno"]]),
  "Influencia del entorno extralaboral sobre el trabajo" =
    c("Extra.", RES_EXTRA[["influencia_entorno_extralaboral_trabajo"]]),
  "Desplazamiento vivienda – trabajo – vivienda" =
    c("Extra.", RES_EXTRA[["desplazamiento_vivienda_trabajo_vivienda"]]),
  "Puntaje extralaboral"                    = c("", "Total extralaboral"),
  "Estrés"                                  = c("", "Estrés"))

# El nivel se escribe con los textos de la leyenda del propio formato
# (VALORACION DEL RIESGO), no con los del manual que guarda la base: el
# informe tiene que decir lo mismo en la tabla y en la leyenda.
INF_NIVELES <- c(
  "Sin riesgo o riesgo despreciable" = "RIESGO MUY BAJO",
  "Riesgo bajo"                      = "RIESGO BAJO",
  "Riesgo medio"                     = "RIESGO MEDIO",
  "Riesgo alto"                      = "RIESGO ALTO",
  "Riesgo muy alto"                  = "RIESGO MUY ALTO")

inf_nivel <- function(x) {
  x <- inf_txt(x)
  if (!nzchar(x)) return("")
  if (!x %in% names(INF_NIVELES)) stop("Nivel de riesgo desconocido: ", x, call. = FALSE)
  INF_NIVELES[[x]]
}

# Las filas que se quitan en la forma B.
INF_SOLO_A <- c("Relación con los colaboradores", "Nivel de responsabilidad del cargo",
                "Consistencia del rol")

# Columnas de nivel y puntaje de una fila de la plantilla. Los totales y el
# estres no llevan prefijo; su puntaje va en minuscula ("Puntaje total
# intralaboral", "Puntaje estrés").
inf_columnas <- function(fila) {
  m <- INF_FILAS[[fila]]
  if (nzchar(m[1])) c(nivel = paste(m[1], m[2]), puntaje = paste("Puntaje", m[2]))
  else c(nivel = m[2], puntaje = paste("Puntaje", tolower(m[2])))
}

inf_hay_vista <- function() {
  partes <- strsplit(RES_VISTA_EXPORTACION_IND, ".", fixed = TRUE)[[1]]
  n <- tryCatch(
    db_get("SELECT count(*) AS n FROM information_schema.views
             WHERE table_schema = $1 AND table_name = $2",
           params = as.list(partes))$n,
    error = function(e) 0)
  isTRUE(as.numeric(n) > 0)
}

# Quienes tienen informe, para el buscador: una fila por persona.
inf_personas <- function() {
  db_get(sprintf('
    SELECT DISTINCT "Cédula" AS cedula, "Nombre" AS nombre
      FROM %s ORDER BY 2, 1', RES_VISTA_EXPORTACION_IND))
}

# La fila de una persona. Si mando la encuesta mas de una vez, la mas reciente.
inf_datos <- function(cedula) {
  d <- db_get(sprintf('
    SELECT * FROM %s WHERE "Cédula" = $1
     ORDER BY "Fecha de aplicación" DESC NULLS LAST LIMIT 1',
    RES_VISTA_EXPORTACION_IND), params = list(as.character(cedula)))
  if (nrow(d) == 1) d else NULL
}


# --- escritura sobre el XML de Word ------------------------------------------

INF_NS <- c(w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main")

inf_texto <- function(nodo) {
  trimws(paste(xml2::xml_text(xml2::xml_find_all(nodo, ".//w:t", INF_NS)), collapse = ""))
}

# Agrega `texto` al final del primer parrafo de `celda` (o del parrafo mismo),
# con el formato que la plantilla dejo preparado en ese parrafo (w:pPr/w:rPr):
# asi cada valor sale con la fuente, el tamano y el color del formato.
inf_escribir <- function(nodo, texto, negrita = NULL) {
  p <- if (xml2::xml_name(nodo) == "p") nodo
       else xml2::xml_find_first(nodo, ".//w:p", INF_NS)
  r <- xml2::xml_add_child(p, "w:r")
  rpr <- xml2::xml_find_first(p, "./w:pPr/w:rPr", INF_NS)
  if (!inherits(rpr, "xml_missing")) {
    nuevo <- xml2::xml_add_child(r, rpr)
    if (isFALSE(negrita))
      xml2::xml_remove(xml2::xml_find_all(nuevo, "./w:b | ./w:bCs", INF_NS))
  }
  t <- xml2::xml_add_child(r, "w:t", texto)
  xml2::xml_set_attr(t, "xml:space", "preserve")
  invisible(r)
}

# Cambia el texto de una celda: deja el primer w:t con `texto` y vacia los demas.
inf_reemplazar <- function(celda, texto) {
  ts <- xml2::xml_find_all(celda, ".//w:t", INF_NS)
  xml2::xml_text(ts[[1]]) <- texto
  for (t in ts[-1]) xml2::xml_text(t) <- ""
}

inf_celdas <- function(fila) xml2::xml_find_all(fila, "./w:tc", INF_NS)

inf_num <- function(x) {
  if (length(x) != 1 || is.na(x)) "" else formatC(as.numeric(x), format = "f",
                                                  digits = 1, decimal.mark = ",")
}

inf_fecha <- function(x) {
  if (length(x) != 1 || is.na(x)) "" else format(as.Date(x), "%d/%m/%Y")
}

inf_txt <- function(x) {
  if (length(x) != 1 || is.na(x)) "" else as.character(x)
}

# Escribe el informe de la fila `p` (de inf_datos()) en `archivo`.
inf_generar <- function(p, archivo, plantilla = INF_PLANTILLA) {
  if (!file.exists(plantilla)) stop("No se encuentra la plantilla ", plantilla, call. = FALSE)
  forma <- inf_txt(p[["Forma"]])
  if (!forma %in% c("A", "B")) stop("Forma del cuestionario desconocida: ", forma, call. = FALSE)

  doc  <- officer::read_docx(plantilla)
  body <- officer::docx_body_xml(doc)
  tablas <- xml2::xml_find_all(body, "//w:tbl", INF_NS)
  cab <- function(t) inf_texto(xml2::xml_find_first(t, "./w:tr", INF_NS))
  tabla <- function(titulo) {
    i <- which(vapply(tablas, cab, "") == titulo)
    if (length(i) != 1) stop("La plantilla no tiene la tabla ", titulo, call. = FALSE)
    tablas[[i]]
  }

  # --- titulo ---
  marca <- xml2::xml_find_first(body, "//w:t[normalize-space(.) = 'FORMA A']", INF_NS)
  if (inherits(marca, "xml_missing")) stop("La plantilla no tiene el titulo FORMA A", call. = FALSE)
  xml2::xml_text(marca) <- paste("FORMA", forma)
  xml2::xml_remove(xml2::xml_find_all(xml2::xml_parent(marca), "./w:rPr/w:highlight", INF_NS))

  # --- datos del trabajador ---
  valores <- c(
    "Nombre del trabajador"                = inf_txt(p[["Nombre"]]),
    "Número de identificación (ID)"        = inf_txt(p[["Cédula"]]),
    "Cargo"                                = inf_txt(p[["Cargo"]]),
    "Edad"                                 = inf_txt(p[["Edad"]]),
    "Sexo"                                 = inf_txt(p[["Sexo"]]),
    "Fecha de aplicación del cuestionario" = inf_fecha(p[["Fecha de aplicación"]]),
    "Nombre de la empresa"                 = INF_EMPRESA)
  vistos <- character(0)
  for (fila in xml2::xml_find_all(tabla("DATOS DEL TRABAJADOR EVALUADO"), "./w:tr", INF_NS)) {
    cel <- inf_celdas(fila)
    if (length(cel) != 2) next
    rot <- sub(":\\s*$", "", inf_texto(cel[[1]]))
    if (rot == "Departamento o sección") {
      # Se parte en dos filas: la dependencia del marco y el area que la
      # persona escribio en la encuesta.
      copia <- xml2::xml_add_sibling(fila, fila, .where = "after")
      inf_reemplazar(cel[[1]], "Dependencia: ")
      inf_escribir(cel[[2]], inf_txt(p[["Dependencia"]]))
      cel2 <- inf_celdas(copia)
      inf_reemplazar(cel2[[1]], "Área: ")
      inf_escribir(cel2[[2]], inf_txt(p[["Área"]]))
      vistos <- c(vistos, rot)
    } else if (rot %in% names(valores)) {
      inf_escribir(cel[[2]], valores[[rot]])
      vistos <- c(vistos, rot)
    }
  }
  falta <- setdiff(c(names(valores), "Departamento o sección"), vistos)
  if (length(falta)) stop("La plantilla no tiene las filas: ", paste(falta, collapse = ", "),
                          call. = FALSE)

  # --- resultados ---
  # La fila se reconoce por el texto que va justo antes de las dos celdas de
  # valores: la dimension, o el dominio y los totales, que ocupan dos columnas.
  vistos <- character(0)
  for (fila in xml2::xml_find_all(tabla("RESULTADOS DEL CUESTIONARIO"), "./w:tr", INF_NS)) {
    cel <- inf_celdas(fila)
    n <- length(cel)
    if (n < 3) next
    rot <- inf_texto(cel[[n - 2]])
    if (!rot %in% names(INF_FILAS)) next
    vistos <- c(vistos, rot)
    if (forma == "B" && rot %in% INF_SOLO_A) {
      xml2::xml_remove(fila)
      next
    }
    k <- inf_columnas(rot)
    faltan <- setdiff(k, names(p))
    if (length(faltan)) stop("La vista no tiene las columnas: ", paste(faltan, collapse = ", "),
                             call. = FALSE)
    inf_escribir(cel[[n - 1]], inf_num(p[[k[["puntaje"]]]]))
    inf_escribir(cel[[n]],     inf_nivel(p[[k[["nivel"]]]]))
  }
  falta <- setdiff(names(INF_FILAS), vistos)
  if (length(falta)) stop("La plantilla no tiene las filas de resultados: ",
                          paste(falta, collapse = ", "), call. = FALSE)

  # --- fecha de elaboracion ---
  fecha <- xml2::xml_find_first(
    body, "//w:p[w:r/w:t[starts-with(normalize-space(.), 'Fecha de elaboración del informe')]]",
    INF_NS)
  if (inherits(fecha, "xml_missing"))
    stop("La plantilla no tiene la fecha de elaboracion", call. = FALSE)
  inf_escribir(fecha, format(Sys.Date(), "%d/%m/%Y"), negrita = FALSE)

  print(doc, target = archivo)
  invisible(archivo)
}

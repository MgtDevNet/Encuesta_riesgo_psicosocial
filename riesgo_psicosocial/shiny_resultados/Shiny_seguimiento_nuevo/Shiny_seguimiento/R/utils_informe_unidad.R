# -----------------------------------------------------------------------------
# utils_informe_unidad.R
# Informe de resultados de UNA unidad o de UNA dependencia en PowerPoint, sobre
# la presentacion del equipo (plantillas/informe_unidad.pptx).
#
# Lo que se llena, diapositiva por diapositiva (lo demas queda como viene):
#
#   portada, objetivo y cierre   el nombre de la unidad o dependencia, tal cual
#                                esta en el marco; el cierre lleva ademas la
#                                fecha de descarga
#   Cobertura                    esperados, encuestados y cobertura (las cifras
#                                de Avance), cuantos hombres y mujeres, y una
#                                barra con la meta sugerida del 80 %
#   cuatro sociodemograficas     una grafica de barras por variable: personas y
#                                % sobre los encuestados; la de area pasa a ser
#                                por dependencia de la nomina (con esperados)
#   intra / extra / estres       el nivel de riesgo de la unidad en cada forma
#   nivel de riesgo (nueva)      despues de la anterior: tabla de niveles por
#                                dominio, total intralaboral, extralaboral y
#                                estres; Forma A y Forma B
#   cinco resumenes por dominio  % en riesgo alto o muy alto por columna: UDEA,
#                                la unidad, sus formas A y B y sus tipos de
#                                empleado; en rojo desde el 30 %
#   dos diapositivas nuevas      despues de los resumenes: las dimensiones
#                                ordenadas por riesgo, y unidad contra
#                                universidad por dominio
#
# Los resultados salen de res_datos() --los mismos de la pestana Resultados-- y
# siguen su regla: un grupo con menos de RES_MIN_N personas no se muestra. Si la
# unidad entera no llega, las diapositivas con resultados llevan un aviso en vez
# de los datos; la cobertura se muestra siempre (son conteos, no resultados).
#
# Las diapositivas se encuentran por su texto y no por su numero, y si la
# plantilla cambia y un texto ya no esta, el informe se detiene diciendo cual
# falta: es mejor eso que un informe con una tabla a medio llenar.
# -----------------------------------------------------------------------------

IU_PLANTILLA <- file.path("plantillas", "informe_unidad.pptx")

# Linea base de intervencion de la propia presentacion: un 30 % o mas de
# personas en riesgo alto o muy alto. Desde ahi la cifra va en rojo.
IU_UMBRAL <- 30
IU_META_COBERTURA <- 80

# Colores de la Universidad de Antioquia: el verde es el del logo. El rojo es
# solo para lo que esta en riesgo, y el gris para la universidad cuando se
# compara contra la unidad.
IU_ROJO        <- "FF0000"
IU_VERDE       <- "0D6939"
IU_VERDE_CLARO <- "8DC63F"
IU_VERDE_SUAVE <- "E8F3EC"
IU_VERDE_PALIDO <- "CDE5D3"
IU_GRIS        <- "A6A6A6"
IU_TEXTO       <- "404040"

# Letras: Century Gothic en los titulos y Calibri en el resto, las dos vienen
# con Microsoft Office. Las graficas son imagenes que se dibujan en el
# servidor, que no tiene Calibri: usan Carlito, que es igual a Calibri (el
# Dockerfile la instala); si no esta, la letra sans del sistema.
IU_LETRA_TITULO <- "Century Gothic"
IU_LETRA        <- "Calibri"
iu_letra_grafica <- function() {
  fams <- tryCatch(systemfonts::system_fonts()$family, error = function(e) character(0))
  if ("Carlito" %in% fams) "Carlito" else "sans"
}

# Alto de la diapositiva de la plantilla, en pulgadas, con un margen abajo, y
# lo minimo que se deja a cada fila del encabezado de los resumenes.
IU_ALTO_DIAPOSITIVA <- 14.8
IU_ALTO_CABECERA    <- 0.85

# Ancho de la diapositiva, en pulgadas.
IU_ANCHO_DIAPOSITIVA <- 24120475 / 914400

# Ancho de las graficas de la diapositiva de representacion por unidad (informe
# de toda la universidad), una en cada mitad. En pulgadas.
IU_SOCIO_GRAFICA_ANCHO <- 11.5

# Las graficas sociodemograficas van en dos diapositivas de cuatro, en una
# rejilla de 2 x 2: arriba del titulo de cada fila y el alto maximo de cada
# grafica, en pulgadas.
IU_GRILLA_TITULO   <- c(1.15, 7.85)
IU_GRILLA_ALTO     <- 5.25
IU_GRILLA_ANCHO    <- 10.8

# La tabla de cobertura, ya con cinco columnas: posicion y ancho en pulgadas.
IU_IZQ_COBERTURA   <- 2.0
IU_ANCHO_COBERTURA <- 22.4

IU_NS <- c(a = "http://schemas.openxmlformats.org/drawingml/2006/main",
           p = "http://schemas.openxmlformats.org/presentationml/2006/main")
IU_EMU <- 914400

IU_NIVELES <- c(unidad = "Unidad", dependencia = "Dependencia", universidad = "Universidad")
IU_COLUMNA <- c(unidad = "tipo_dependencia", dependencia = "dependencia")

# El informe de toda la universidad: todos los encuestados y todo el avance.
IU_NOMBRE_UDEA <- "Universidad de Antioquia"

# Columnas por tipo de empleado de la nomina, en este orden. Solo se ponen las
# que tienen gente en la unidad.
IU_TIPOS <- c("Profesor"                  = "Profesores",
              "Docente Catedra por Horas" = "Docentes de cátedra",
              "Personal Administrativo"   = "Administrativos",
              "Trabajador Oficial"        = "Trabajadores oficiales")

# Las graficas sociodemograficas: el titulo que trae la plantilla y la variable
# de res_datos(). La de tipo de contrato se cambia por el tipo de vinculacion
# de la nomina, porque el formulario ya no guarda el contrato. La de area se
# cambia por la dependencia de la nomina: el area de ODK es texto libre y cada
# quien la escribe a su manera (30 escrituras para 38 personas en el piloto).
# `titulo` es el texto de la plantilla (para encontrar sus diapositivas) y
# `nuevo` el que se escribe sobre cada grafica.
IU_SOCIO <- list(
  list(titulo = "% de personas por Edad",                         var = "edad",
       nuevo  = "% de personas por edad"),
  list(titulo = "% de personas por Estado Civil",                 var = "estado_civil",
       nuevo  = "% de personas por estado civil"),
  list(titulo = "% de personas por nivel de escolaridad",         var = "nivel_academico",
       nuevo  = "% de personas por nivel de escolaridad"),
  list(titulo = "% de personas por estrato socioeconómico",       var = "estrato",
       nuevo  = "% de personas por estrato socioeconómico"),
  list(titulo = "% de personas por tipo de vivienda",             var = "vivienda",
       nuevo  = "% de personas por tipo de vivienda"),
  list(titulo = "% de personas por tipo de contrato",             var = "tipo_vinculacion",
       nuevo  = "% de personas por tipo de vinculación"),
  list(titulo = "% de personas por Antigüedad en la institución", var = "antiguedad",
       nuevo  = "% de personas por antigüedad en la institución"),
  list(titulo = "% Representación por área",                      var = "dependencia",
       nuevo  = "% representación por dependencia"))

# Una grafica sociodemografica no pasa de este numero de barras: las categorias
# mas chicas se juntan en "Otras".
IU_MAX_CATEGORIAS <- 12L

# Fila de los resumenes por dominio (el texto de la plantilla) -> medida.
IU_FILAS <- c(
  "Demandas ambientales y de esfuerzo físico"            = "dim_demandas_ambientales_esfuerzo_fisico",
  "Exigencias de responsabilidad del cargo"              = "dim_exigencias_responsabilidad_cargo",
  "Consistencia del rol"                                 = "dim_consistencia_rol",
  "Demandas emocionales"                                 = "dim_demandas_emocionales",
  "Demandas de la jornada de trabajo"                    = "dim_demandas_jornada_trabajo",
  "Influencia del trabajo sobre el entorno extralaboral" = "dim_influencia_trabajo_entorno_extralaboral",
  "Demandas cuantitativas"                               = "dim_demandas_cuantitativas",
  "Demandas de carga mental"                             = "dim_demandas_carga_mental",
  "Total dominio Demandas del trabajo"                   = "dom_demandas_trabajo",
  "Claridad de rol"                                      = "dim_claridad_rol",
  "Capacitación"                                         = "dim_capacitacion",
  "Oportunidades para el uso y desarrollo de habilidades y conocimientos" =
    "dim_oportunidades_uso_desarrollo_habilidades",
  "Participación y manejo del cambio"                    = "dim_participacion_manejo_cambio",
  "Control y autonomía sobre el trabajo"                 = "dim_control_autonomia_trabajo",
  "Total dominio Control sobre el trabajo"               = "dom_control_trabajo",
  "Características del liderazgo"                        = "dim_caracteristicas_liderazgo",
  "Relaciones sociales en el trabajo"                    = "dim_relaciones_sociales_trabajo",
  "Retroalimentación del desempeño"                      = "dim_retroalimentacion_desempeno",
  "Relación con los colaboradores"                       = "dim_relacion_colaboradores",
  "Total Dominio Liderazgo y relaciones sociales en el trabajo" =
    "dom_liderazgo_relaciones_sociales_trabajo",
  "Reconocimiento y compensación"                        = "dim_reconocimiento_compensacion",
  "Recompensas derivadas de la pertenencia a la organización y del trabajo que se realiza" =
    "dim_recompensas_derivadas_pertenencia_organizacion",
  "Total dominio Recompensas"                            = "dom_recompensas",
  "Tiempo fuera del trabajo"                             = "ex_balance_vida_laboral_familiar",
  "Relaciones familiares"                                = "ex_relaciones_familiares",
  "Comunicación y relaciones interpersonales"            = "ex_comunicacion_relaciones_interpersonales",
  "Situación económica"                                  = "ex_situacion_economica_grupo_familiar",
  "Características de la vivienda y de su entorno"       = "ex_caracteristicas_vivienda_entorno",
  "Influencia del entorno extralaboral sobre el trabajo" = "ex_influencia_entorno_extralaboral_trabajo",
  "Desplazamiento vivienda – trabajo – vivienda"         = "ex_desplazamiento_vivienda_trabajo_vivienda",
  "Estrés"                                               = "tot_estres")

# Los titulos de los cinco resumenes, para encontrar sus diapositivas.
IU_RESUMENES <- c("Resumen resultados Dominio: Demanda del trabajo",
                  "Resumen resultados Dominio: Control sobre el trabajo",
                  "Resumen resultados Dominio: Liderazgo",
                  "Resumen resultados Dominio: Recompensas",
                  "Resumen resultados Extralaborales y estrés")

# Los tres niveles de la diapositiva de intralaboral, extralaboral y estres:
# el texto que trae la plantilla, el que lo reemplaza y la medida.
IU_TRES <- list(
  list(viejo = "Nivel de riesgo intralaboral",    nuevo = "Riesgo intralaboral",  clave = "tot_intra"),
  list(viejo = "Nivel de riesgo extralaboral",    nuevo = "Riesgo extralaboral",  clave = "tot_extra"),
  list(viejo = "Escala de valoración del estrés", nuevo = "Estrés",               clave = "tot_estres"))

# Los dominios para la grafica unidad contra universidad.
IU_DOMINIOS <- c(dom_demandas_trabajo                      = "Demandas del trabajo",
                 dom_control_trabajo                       = "Control sobre el trabajo",
                 dom_liderazgo_relaciones_sociales_trabajo = "Liderazgo y relaciones sociales",
                 dom_recompensas                           = "Recompensas",
                 tot_extra                                 = "Extralaboral",
                 tot_estres                                = "Estrés")

# --- nivel de riesgo del grupo ------------------------------------------------
# La Bateria califica personas: cada una cae en un nivel segun su puntaje
# transformado y el baremo de su forma. Para la unidad se usa el mismo baremo
# sobre el PROMEDIO del puntaje transformado de las personas de cada forma
# (redondeado a un decimal, como los puntajes individuales).
#
# A y B no se promedian entre si: cada una tiene su baremo, y un 25 en la A no
# dice lo mismo que un 25 en la B. Tampoco hay nivel general: el manual no trae
# una regla para combinar las dos formas, asi que el grupo se informa siempre
# por forma (decision del equipo, 2026-11-06).
#
# Los cortes son los de conectar_bd.R, que es donde se califica a cada persona.
# iu_verificar_baremos() comprueba en cada informe que, aplicados al puntaje
# de cada persona, den el mismo nivel que le asigno la calificacion: si
# alguien cambia un corte alla y no aqui, el informe se detiene.
IU_BAREMOS <- list(
  tot_intra = list(A = c(19.7, 25.8, 31.5, 38.0), B = c(20.6, 26.0, 31.2, 38.7)),
  dom_liderazgo_relaciones_sociales_trabajo =
              list(A = c( 9.1, 17.7, 25.6, 34.8), B = c( 8.3, 17.5, 26.7, 38.3)),
  dom_control_trabajo =
              list(A = c(10.7, 19.0, 29.8, 40.5), B = c(19.4, 26.4, 34.7, 43.1)),
  dom_demandas_trabajo =
              list(A = c(28.5, 35.0, 41.5, 47.5), B = c(26.9, 33.3, 37.8, 44.2)),
  dom_recompensas =
              list(A = c( 4.5, 11.4, 20.5, 29.5), B = c( 2.5, 10.0, 17.5, 27.5)),
  tot_extra  = list(A = c(11.3, 16.9, 22.6, 29.0), B = c(12.9, 17.7, 24.2, 32.3)),
  tot_estres = list(A = c( 7.8, 12.6, 17.7, 25.0), B = c( 6.5, 11.8, 17.0, 23.4)))

# Filas de la tabla de niveles, en orden de lectura.
IU_NIVEL_FILAS <- c(
  dom_liderazgo_relaciones_sociales_trabajo = "Dominio Liderazgo y relaciones sociales en el trabajo",
  dom_control_trabajo                       = "Dominio Control sobre el trabajo",
  dom_demandas_trabajo                      = "Dominio Demandas del trabajo",
  dom_recompensas                           = "Dominio Recompensas",
  tot_intra                                 = "Total intralaboral",
  tot_extra                                 = "Extralaboral",
  tot_estres                                = "Estrés")

# Los niveles con las palabras y los colores de la leyenda de la presentacion
# (diapositiva "¿Como lo interpretamos?"): sin riesgo es "muy bajo".
IU_NIVEL_TXT   <- c("Muy bajo", "Bajo", "Medio", "Alto", "Muy alto")
IU_NIVEL_COLOR <- c("92D050", "00B050", "FFFF00", "FFC000", "FF0000")

# Columna del puntaje transformado de una medida en res_datos(). Extralaboral
# y estres tienen una sola columna; lo que cambia con la forma es el baremo.
iu_col_pt <- function(clave, forma) {
  f <- tolower(forma)
  if (clave %in% c("tot_extra", "tot_estres")) return(paste0("pt_", clave))
  paste0("pt_", clave, "_", f)
}

# Nivel (1 = muy bajo ... 5 = muy alto) de un puntaje con unos cortes: el
# baremo deja cada corte dentro del nivel de abajo.
iu_nivel_de <- function(x, cortes) 1L + sum(x > cortes)

# Nivel de una medida en un grupo, por forma.
#   $A, $B    list(n, promedio, nivel)  (nivel NA si no hay personas)
iu_nivel_grupo <- function(d, clave) {
  lapply(c(A = "A", B = "B"), function(f) {
    col <- iu_col_pt(clave, f)
    x <- if (col %in% names(d)) d[[col]][d$forma %in% f] else numeric(0)
    x <- as.numeric(x[!is.na(x)])
    if (!length(x)) return(list(n = 0L, promedio = NA_real_, nivel = NA_integer_))
    prom <- redondear(mean(x), 1)
    list(n = length(x), promedio = prom, nivel = iu_nivel_de(prom, IU_BAREMOS[[clave]][[f]]))
  })
}

# Lo que se escribe de un nivel: la palabra, "< 7" si el grupo no llega al
# minimo, o una raya si no hay nadie de esa forma.
iu_nivel_txt <- function(n, nivel) {
  if (n == 0 || is.na(nivel)) return("\u2014")
  if (n < RES_MIN_N) return(sprintf("< %d", RES_MIN_N))
  IU_NIVEL_TXT[nivel]
}

# Comprueba que los cortes de IU_BAREMOS den, persona por persona, el mismo
# nivel que guardo la calificacion. Se corre sobre toda la universidad.
iu_verificar_baremos <- function(d) {
  for (clave in names(IU_BAREMOS)) for (f in c("A", "B")) {
    col <- iu_col_pt(clave, f)
    if (!col %in% names(d))
      stop("No se encuentran los puntajes transformados (", col, "): hay que volver a ",
           "calificar con conectar_bd.R.", call. = FALSE)
    sel <- d$forma %in% f & !is.na(d[[col]]) & !is.na(d[[clave]])
    if (!any(sel)) next
    calc <- RES_NIVELES[vapply(as.numeric(d[[col]][sel]), iu_nivel_de, 1L,
                               cortes = IU_BAREMOS[[clave]][[f]])]
    mal <- sum(calc != d[[clave]][sel])
    if (mal > 0)
      stop(sprintf(paste("Los cortes del baremo de %s (forma %s) no coinciden con la",
                         "calificacion en %d personas: revisar IU_BAREMOS contra conectar_bd.R."),
                   clave, f, mal), call. = FALSE)
  }
  invisible(TRUE)
}

IU_MESES <- c("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
              "agosto", "septiembre", "octubre", "noviembre", "diciembre")


# --- datos -------------------------------------------------------------------

# Las unidades y dependencias que se pueden elegir, con sus encuestados.
# Las dependencias, cada una con su unidad. Hay nombres de dependencia que se
# repiten en varias unidades ("Departamento de Formacion Academica" esta en
# cuatro escuelas): son dependencias distintas y en el informe van por
# separado, con la unidad en el nombre ("... · Escuela de Idiomas"). Las demas
# se llaman como siempre. Se cuentan persona por persona, con las reglas de
# seg_avance() (esperados = activos; encuestados = activos con algun envio).
# (La pestana Avance y Resultados todavia las juntan por nombre.)
iu_dependencias_lista <- function() {
  a <- db_get(sprintf("
    SELECT m.tipo_dependencia AS unidad, m.dependencia,
           count(*)::int AS esperados,
           count(DISTINCT r.id_anonimizado)::int AS encuestados
      FROM seguimiento.marco_completo m
      LEFT JOIN %s r ON m.id_anonimizado = r.id_anonimizado
     WHERE m.estado_vinculacion = 'Activo'
       AND m.dependencia IS NOT NULL AND m.dependencia <> ''
     GROUP BY 1, 2", SEG_RESPONDIO))
  repetida <- a$dependencia %in% a$dependencia[duplicated(a$dependencia)]
  a$etiqueta <- ifelse(repetida, paste(a$dependencia, a$unidad, sep = " \u00b7 "), a$dependencia)
  a
}

# Las unidades se cuentan persona por persona (iu_unidades_avance()): sumar el
# avance por dependencia las mezcla cuando un nombre de dependencia se repite.
iu_opciones <- function(av = seg_avance()) {
  ordenar <- function(a) {
    a <- a[!is.na(a$v) & nzchar(a$v), , drop = FALSE]
    a[order(to_key(a$v)), , drop = FALSE]
  }
  u <- iu_unidades_avance()
  dl <- iu_dependencias_lista()
  list(unidad = ordenar(data.frame(v = u$dependencia, x = u$encuestados, stringsAsFactors = FALSE)),
       dependencia = ordenar(data.frame(v = dl$etiqueta, x = dl$encuestados, stringsAsFactors = FALSE)))
}

# Todo lo que necesita el informe de una unidad o dependencia. `d` son las
# encuestas con resultados de toda la universidad (res_datos()) y `av` el
# avance por dependencia (seg_avance()); se pueden pasar para no consultar dos
# veces la base.
iu_poblacion <- function(nivel, valor, d = res_datos(), av = seg_avance()) {
  if (!nivel %in% names(IU_NIVELES)) stop("Nivel desconocido: ", nivel, call. = FALSE)
  if (identical(nivel, "universidad")) {
    valor <- IU_NOMBRE_UDEA
    a <- av
    du <- d
  } else {
    # La unidad se pide a seg_avance() ya filtrada: sin filtro, el avance va por
    # NOMBRE de dependencia, y hay nombres que se repiten en varias unidades
    # ("Departamento de Formacion Academica" esta en cuatro escuelas): cada
    # uno quedaba entero en una sola unidad y la cobertura de las otras salia
    # mal. Filtrando por la unidad se cuentan solo sus personas.
    if (identical(nivel, "unidad")) {
      a <- seg_avance(tipos = valor)
      du <- if (nrow(d)) d[!is.na(d$tipo_dependencia) & d$tipo_dependencia == valor, , drop = FALSE] else d
    } else {
      # La dependencia va con su unidad (ver iu_dependencias_lista()): `valor`
      # es su nombre, o "nombre · unidad" si el nombre se repite.
      dl <- iu_dependencias_lista()
      fila <- dl[dl$etiqueta == valor, , drop = FALSE]
      if (nrow(fila) != 1) stop("No hay dependencia llamada ", valor, call. = FALSE)
      a <- seg_avance(tipos = fila$unidad)
      a <- a[!is.na(a$dependencia) & a$dependencia == fila$dependencia, , drop = FALSE]
      du <- if (nrow(d)) d[d$dependencia %in% fila$dependencia &
                           d$tipo_dependencia %in% fila$unidad, , drop = FALSE] else d
    }
    if (!nrow(a)) stop("No hay ", tolower(IU_NIVELES[[nivel]]), " llamada ", valor, call. = FALSE)
  }
  # Encuestas efectivas: las personas cuyo ultimo envio acepto el
  # consentimiento, que son justo las que trae res_datos() (la misma regla que
  # Avance, seg_sql_efectiva()).
  list(nivel = nivel, valor = valor, d = d, du = du, av = a,
       esperados = sum(a$elegibles), encuestados = sum(a$encuestados),
       efectivas = nrow(du),
       reservado = nrow(du) < RES_MIN_N)
}

# % en riesgo alto o muy alto de una medida en un grupo, o NA si el grupo no
# llega al minimo (res_reparto() ya redondea a un decimal).
iu_alto <- function(d, clave) {
  if (is.null(d) || !nrow(d) || !clave %in% names(d)) return(NA_real_)
  r <- res_reparto(d[[clave]])
  if (is.null(r)) NA_real_ else r$alto
}

iu_rojo <- function(x) !is.na(x) & redondear(x, 1) >= IU_UMBRAL

# Siempre con un decimal: "33,3%", "25,0%", "100,0%".
iu_pct <- function(x) {
  if (length(x) != 1 || is.na(x)) return("—")
  paste0(formatC(redondear(x, 1), format = "f", digits = 1, decimal.mark = ","), "%")
}

# "la Facultad de Medicina", "el Instituto de Filosofia": el articulo segun la
# primera palabra del nombre. La universidad es "la universidad".
IU_MASCULINOS <- c("instituto", "departamento", "centro", "programa", "grupo", "laboratorio",
                   "museo", "parque", "sistema", "comite", "consejo", "posgrado")
iu_con_articulo <- function(nivel, valor) {
  if (identical(nivel, "universidad")) return("la universidad")
  primera <- to_key(sub("\\s.*$", "", trimws(valor)))
  paste(if (primera %in% IU_MASCULINOS) "el" else "la", valor)
}

iu_personas <- function(n) sprintf("%s %s", fmt_num(n), if (n == 1) "persona" else "personas")

iu_fecha <- function(x = Sys.Date()) {
  sprintf("%d de %s de %s", as.integer(format(x, "%d")),
          IU_MESES[as.integer(format(x, "%m"))], format(x, "%Y"))
}

# Las columnas de los resumenes por dominio: la universidad, la unidad, sus
# dos formas y los tipos de empleado que tiene. En el informe de toda la
# universidad no va la columna de la unidad: repetiria la de la UDEA.
iu_columnas <- function(pob) {
  du <- pob$du
  cols <- c(
    list(list(titulo = "Resultado UDEA", d = pob$d)),
    if (!identical(pob$nivel, "universidad"))
      list(list(titulo = paste("Resultado", IU_NIVELES[[pob$nivel]]), d = du)),
    list(list(titulo = "Forma A", d = du[du$forma %in% "A", , drop = FALSE], forma = "A"),
         list(titulo = "Forma B", d = du[du$forma %in% "B", , drop = FALSE], forma = "B")))
  tipos <- intersect(names(IU_TIPOS), du$tipo_empleado)
  c(cols, lapply(tipos, function(t)
    list(titulo = IU_TIPOS[[t]], d = du[du$tipo_empleado %in% t, , drop = FALSE])))
}

# Lo que va en una celda de un resumen: el %, "< 7" si el grupo no llega al
# minimo, o "No aplica" si la forma B no mide esa dimension.
iu_celda_valor <- function(col, clave) {
  if (identical(col$forma, "B") && clave %in% RES_SOLO_A_CLAVES)
    return(list(texto = "No aplica", rojo = FALSE))
  x <- iu_alto(col$d, clave)
  if (is.na(x)) list(texto = sprintf("< %d", RES_MIN_N), rojo = FALSE)
  else list(texto = iu_pct(x), rojo = iu_rojo(x))
}

# Frecuencias de una variable sociodemografica entre los encuestados: el orden
# propio de la variable si lo tiene (edad, antiguedad, estrato) y si no de
# mayor a menor; "Sin dato" al final. Pasando IU_MAX_CATEGORIAS, las mas chicas
# se juntan en "Otras".
iu_frecuencias <- function(du, var) {
  x <- as.character(du[[var]])
  x[is.na(x) | !nzchar(trimws(x))] <- RES_SIN_DATO
  t <- table(x)
  cats <- names(t)
  ord <- RES_DESC_ORDEN[[var]]
  sin <- RES_SIN_DATO %in% cats
  cats <- setdiff(cats, RES_SIN_DATO)
  cats <- if (!is.null(ord)) c(intersect(ord, cats), sort(setdiff(cats, ord)))
          else cats[order(-as.integer(t[cats]), to_key(cats))]
  n <- as.integer(t[cats])
  if (length(cats) > IU_MAX_CATEGORIAS) {
    k <- IU_MAX_CATEGORIAS - 1L
    resto <- sum(n[-seq_len(k)])
    otras <- sprintf("Otras (%d)", length(cats) - k)
    cats <- c(cats[seq_len(k)], otras)
    n <- c(n[seq_len(k)], resto)
  }
  if (sin) {
    cats <- c(cats, RES_SIN_DATO)
    n <- c(n, as.integer(t[[RES_SIN_DATO]]))
  }
  data.frame(categoria = cats, n = n, pct = 100 * n / sum(n), stringsAsFactors = FALSE)
}

# Las dependencias de una unidad con sus esperados y encuestados (las cifras de
# Avance, las mismas de la diapositiva de cobertura), de la mas grande a la mas
# chica. El % es la parte de los encuestados de la unidad que aporta cada una.
iu_dependencias <- function(pob) {
  a <- pob$av[order(-pob$av$elegibles, to_key(pob$av$dependencia)), , drop = FALSE]
  tot <- sum(a$encuestados)
  data.frame(dependencia = a$dependencia, esperados = a$elegibles,
             encuestados = a$encuestados,
             pct = if (tot > 0) 100 * a$encuestados / tot else NA_real_,
             stringsAsFactors = FALSE)
}


# --- escritura sobre el XML de PowerPoint ------------------------------------

iu_norm <- function(x) gsub("\\s+", " ", trimws(to_key(gsub(" ", " ", x))))

iu_texto <- function(nodo) {
  paste(xml2::xml_text(xml2::xml_find_all(nodo, ".//a:t", IU_NS)), collapse = "")
}

iu_xml <- function(doc, i) doc$slide$get_slide(i)$get()

# La diapositiva que tiene un parrafo con ese texto. Tiene que haber una sola.
iu_buscar <- function(doc, texto) {
  t <- iu_norm(texto)
  i <- which(vapply(seq_len(length(doc)), function(k) {
    ps <- xml2::xml_find_all(iu_xml(doc, k), "//a:p", IU_NS)
    any(grepl(t, iu_norm(vapply(ps, iu_texto, "")), fixed = TRUE))
  }, FALSE))
  if (length(i) != 1)
    stop("La plantilla no tiene (o tiene repetido) el texto: ", texto, call. = FALSE)
  i
}

# El parrafo de una diapositiva que contiene ese texto.
iu_parrafo <- function(x, texto) {
  ps <- xml2::xml_find_all(x, "//a:p", IU_NS)
  i <- which(grepl(iu_norm(texto), iu_norm(vapply(ps, iu_texto, "")), fixed = TRUE))
  if (length(i) < 1) stop("La plantilla no tiene el texto: ", texto, call. = FALSE)
  ps[[i[1]]]
}

# La figura (cuadro de texto o imagen) que contiene un nodo.
iu_figura <- function(nodo) {
  xml2::xml_find_first(nodo, "ancestor-or-self::p:sp | ancestor-or-self::p:graphicFrame", IU_NS)
}

# Lo que queda a la izquierda de algo de ese ancho centrado en la diapositiva.
iu_centro_x <- function(ancho) (IU_ANCHO_DIAPOSITIVA - ancho) / 2

# Mueve una figura (cuadro de texto o tabla) a esa posicion, en pulgadas.
iu_mover <- function(fig, left, top, width, height) {
  xf <- xml2::xml_find_first(fig, "./p:spPr/a:xfrm | ./p:xfrm", IU_NS)
  e <- function(v) format(round(v * IU_EMU), scientific = FALSE)
  off <- xml2::xml_find_first(xf, "./a:off", IU_NS)
  ext <- xml2::xml_find_first(xf, "./a:ext", IU_NS)
  xml2::xml_set_attr(off, "x", e(left)); xml2::xml_set_attr(off, "y", e(top))
  xml2::xml_set_attr(ext, "cx", e(width)); xml2::xml_set_attr(ext, "cy", e(height))
  invisible(fig)
}

# Posicion y tamano de una figura, en pulgadas.
iu_caja <- function(fig) {
  xf <- xml2::xml_find_first(fig, "./p:spPr/a:xfrm | ./p:xfrm", IU_NS)
  off <- xml2::xml_find_first(xf, "./a:off", IU_NS)
  ext <- xml2::xml_find_first(xf, "./a:ext", IU_NS)
  v <- function(n, a) as.numeric(xml2::xml_attr(n, a)) / IU_EMU
  list(left = v(off, "x"), top = v(off, "y"), width = v(ext, "cx"), height = v(ext, "cy"))
}

# Deja el texto del run y le quita el resaltado amarillo con el que la
# plantilla marca los valores de ejemplo.
iu_run_texto <- function(run, texto) {
  t <- xml2::xml_find_first(run, "./a:t", IU_NS)
  xml2::xml_text(t) <- texto
  xml2::xml_remove(xml2::xml_find_all(run, "./a:rPr/a:highlight", IU_NS))
  invisible(run)
}

# Todo el parrafo pasa a decir `texto`, con el formato de su primer run.
iu_parrafo_texto <- function(p, texto) {
  runs <- xml2::xml_find_all(p, "./a:r", IU_NS)
  iu_run_texto(runs[[1]], texto)
  for (r in runs[-1]) xml2::xml_remove(r)
  invisible(p)
}

iu_celdas <- function(tr) xml2::xml_find_all(tr, "./a:tc", IU_NS)

# Escribe en una celda de tabla. Rojo y negrita si `rojo`; `tam` en puntos
# cambia el tamano de letra de la plantilla.
iu_celda <- function(tc, texto, rojo = FALSE, centrado = TRUE, tam = NULL) {
  p <- xml2::xml_find_first(tc, "./a:txBody/a:p", IU_NS)
  runs <- xml2::xml_find_all(p, "./a:r", IU_NS)
  if (!length(runs)) stop("Celda sin texto en la plantilla", call. = FALSE)
  iu_run_texto(runs[[1]], texto)
  for (r in runs[-1]) xml2::xml_remove(r)
  if (centrado) {
    ppr <- xml2::xml_find_first(p, "./a:pPr", IU_NS)
    if (!inherits(ppr, "xml_missing")) xml2::xml_set_attr(ppr, "algn", "ctr")
    # Centrado tambien en vertical: la plantilla deja algunas celdas abajo.
    tcpr <- xml2::xml_find_first(tc, "./a:tcPr", IU_NS)
    if (!inherits(tcpr, "xml_missing")) xml2::xml_set_attr(tcpr, "anchor", "ctr")
  }
  if (!is.null(tam)) {
    rpr <- xml2::xml_find_first(runs[[1]], "./a:rPr", IU_NS)
    xml2::xml_set_attr(rpr, "sz", as.character(tam * 100))
  }
  if (rojo) {
    rpr <- xml2::xml_find_first(runs[[1]], "./a:rPr", IU_NS)
    xml2::xml_set_attr(rpr, "b", "1")
    col <- xml2::xml_find_first(rpr, "./a:solidFill/a:srgbClr", IU_NS)
    if (inherits(col, "xml_missing")) {
      fill <- xml2::xml_add_child(rpr, "a:solidFill", .where = 0)
      col  <- xml2::xml_add_child(fill, "a:srgbClr")
    }
    xml2::xml_set_attr(col, "val", IU_ROJO)
  }
  invisible(tc)
}

# Deja la tabla con 1 + k columnas: quita las ultimas o copia la ultima, y
# reparte el ancho entre las columnas de datos sin cambiar el de la tabla. Con
# 7 u 8 columnas de datos la de la dimension se angosta, para que los
# encabezados no se partan a media palabra.
iu_columnas_tabla <- function(tbl, k) {
  grid <- function() xml2::xml_find_all(tbl, "./a:tblGrid/a:gridCol", IU_NS)
  trs <- xml2::xml_find_all(tbl, "./a:tr", IU_NS)
  total <- sum(as.numeric(xml2::xml_attr(grid(), "w")))
  while (length(grid()) - 1 > k) {
    g <- grid(); xml2::xml_remove(g[[length(g)]])
    for (tr in trs) { c <- iu_celdas(tr); xml2::xml_remove(c[[length(c)]]) }
  }
  while (length(grid()) - 1 < k) {
    g <- grid(); xml2::xml_add_sibling(g[[length(g)]], g[[length(g)]], .where = "after")
    for (tr in trs) { c <- iu_celdas(tr); xml2::xml_add_sibling(c[[length(c)]], c[[length(c)]], .where = "after") }
  }
  g <- grid()
  primera <- as.numeric(xml2::xml_attr(g[[1]], "w"))
  if (k >= 7) {
    primera <- floor(total * 0.30)
    xml2::xml_set_attr(g[[1]], "w", format(primera, scientific = FALSE))
  }
  ancho <- floor((total - primera) / k)
  for (j in seq_len(k)) xml2::xml_set_attr(g[[j + 1]], "w", format(ancho, scientific = FALSE))
  invisible(tbl)
}


# Deja la tabla con k columnas del mismo ancho, copiando la ultima si faltan.
# `total` es el ancho de la tabla en EMU (por defecto, el que ya tiene).
iu_columnas_iguales <- function(tbl, k, total = NULL) {
  grid <- function() xml2::xml_find_all(tbl, "./a:tblGrid/a:gridCol", IU_NS)
  if (is.null(total)) total <- sum(as.numeric(xml2::xml_attr(grid(), "w")))
  trs <- xml2::xml_find_all(tbl, "./a:tr", IU_NS)
  while (length(grid()) < k) {
    g <- grid(); xml2::xml_add_sibling(g[[length(g)]], g[[length(g)]], .where = "after")
    for (tr in trs) { c <- iu_celdas(tr); xml2::xml_add_sibling(c[[length(c)]], c[[length(c)]], .where = "after") }
  }
  for (g in grid()) xml2::xml_set_attr(g, "w", format(floor(total / k), scientific = FALSE))
  invisible(tbl)
}


# --- piezas que agrega officer ------------------------------------------------

iu_fp <- function(tam, color = "000000", negrita = FALSE, cursiva = FALSE, letra = IU_LETRA) {
  officer::fp_text(font.size = tam, color = paste0("#", color), bold = negrita,
                   italic = cursiva, font.family = letra)
}

# Un cuadro de texto en la diapositiva activa. `texto` puede ser un vector: un
# parrafo por elemento.
iu_cuadro <- function(doc, texto, left, top, width, height, tam = 24,
                      color = "000000", negrita = FALSE, alinear = "center",
                      letra = IU_LETRA) {
  pars <- lapply(texto, function(t)
    officer::fpar(officer::ftext(t, iu_fp(tam, color, negrita, letra = letra)),
                  fp_p = officer::fp_par(text.align = alinear)))
  officer::ph_with(doc, do.call(officer::block_list, pars),
                   location = officer::ph_location(left = left, top = top,
                                                   width = width, height = height))
}

iu_aviso_texto <- function(pob) {
  sprintf(paste("Esta %s tiene %s con resultados. Para proteger la confidencialidad,",
                "no se presentan resultados de grupos con menos de %d personas."),
          tolower(IU_NIVELES[[pob$nivel]]), iu_personas(nrow(pob$du)), RES_MIN_N)
}

# Grafica de ggplot a PNG del tamano en que va en la diapositiva, y de ahi a la
# diapositiva activa. ragg da el mismo resultado en cualquier servidor.
iu_imagen <- function(doc, g, left, top, width, height) {
  f <- tempfile(fileext = ".png")
  ragg::agg_png(f, width = width, height = height, units = "in", res = 150, background = "white")
  tryCatch(print(g), finally = grDevices::dev.off())
  officer::ph_with(doc, officer::external_img(f, width = width, height = height),
                   location = officer::ph_location(left = left, top = top,
                                                   width = width, height = height))
}

iu_tema <- function(base) {
  ggplot2::theme_minimal(base_size = base, base_family = iu_letra_grafica()) +
    ggplot2::theme(panel.grid = ggplot2::element_blank(),
                   axis.text.x = ggplot2::element_blank(),
                   axis.title = ggplot2::element_blank(),
                   axis.text.y = ggplot2::element_text(color = paste0("#", IU_TEXTO), size = base),
                   legend.position = "top", legend.title = ggplot2::element_blank(),
                   legend.text = ggplot2::element_text(size = base),
                   plot.caption = ggplot2::element_text(color = "grey35", hjust = 0,
                                                        size = base * 0.9),
                   plot.caption.position = "plot")
}

# La linea del 30 % y su rotulo, en horizontal encima de la barra de arriba. Va
# antes de las barras, para quedar detras de ellas y de sus cifras.
# `n` es el numero de categorias del eje (las barras van de abajo hacia arriba
# despues de coord_flip, asi que la de arriba es la n).
iu_linea_umbral <- function(n, base) {
  list(ggplot2::geom_hline(yintercept = IU_UMBRAL, linetype = "dashed",
                           color = paste0("#", IU_ROJO), linewidth = 1),
       ggplot2::annotate("text", x = n + 0.75, y = IU_UMBRAL,
                         label = sprintf("%d %%: línea base de intervención", IU_UMBRAL),
                         hjust = 0.5, size = base / ggplot2::.pt * 0.8,
                         family = iu_letra_grafica(), color = paste0("#", IU_ROJO)),
       ggplot2::scale_x_discrete(expand = ggplot2::expansion(add = c(0.6, 1.5))))
}

# Barras horizontales de la unidad contra la universidad.
iu_grafica_comparar <- function(pob, claves, rotulos, base = 30) {
  nombre <- IU_NIVELES[[pob$nivel]]
  udea <- "Universidad (UDEA)"
  df <- data.frame(
    medida = rep(rotulos, 2),
    grupo  = rep(c(nombre, udea), each = length(claves)),
    pct    = c(vapply(claves, function(k) iu_alto(pob$du, k), 0),
               vapply(claves, function(k) iu_alto(pob$d, k), 0)),
    stringsAsFactors = FALSE)
  df$medida <- factor(df$medida, levels = rev(rotulos))
  df$grupo  <- factor(df$grupo, levels = c(udea, nombre))
  df$etq    <- ifelse(is.na(df$pct), sprintf("< %d personas", RES_MIN_N),
                      vapply(df$pct, iu_pct, ""))
  tope <- max(c(df$pct, IU_UMBRAL), na.rm = TRUE)
  ggplot2::ggplot(df, ggplot2::aes(x = medida, y = ifelse(is.na(pct), 0, pct), fill = grupo)) +
    iu_linea_umbral(length(claves), base) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.85), width = 0.8) +
    ggplot2::geom_text(ggplot2::aes(label = etq), position = ggplot2::position_dodge(width = 0.85),
                       hjust = -0.12, size = base / ggplot2::.pt * 0.85,
                       family = iu_letra_grafica(), color = paste0("#", IU_TEXTO)) +
    ggplot2::scale_fill_manual(values = stats::setNames(paste0("#", c(IU_GRIS, IU_VERDE)),
                                                        c(udea, nombre)),
                               breaks = c(nombre, udea)) +
    ggplot2::scale_y_continuous(limits = c(0, tope * 1.22), expand = c(0, 0)) +
    ggplot2::coord_flip(clip = "off") +
    iu_tema(base) +
    ggplot2::labs(caption = "Porcentaje de personas en riesgo alto o muy alto, sobre los encuestados de cada grupo.")
}

# Los dominios, el extralaboral y el estres de un solo grupo (el informe de
# toda la universidad, que no tiene contra quien compararse), en verde, con la
# linea del 30 %.
iu_grafica_dominios <- function(pob, base = 30) {
  rot <- unname(IU_DOMINIOS)
  df <- data.frame(medida = factor(rot, levels = rev(rot)),
                   pct = vapply(names(IU_DOMINIOS), function(k) iu_alto(pob$du, k), 0),
                   stringsAsFactors = FALSE)
  df$etq   <- ifelse(is.na(df$pct), sprintf("< %d personas", RES_MIN_N), vapply(df$pct, iu_pct, ""))
  ggplot2::ggplot(df, ggplot2::aes(x = medida, y = ifelse(is.na(pct), 0, pct))) +
    iu_linea_umbral(nrow(df), base) +
    ggplot2::geom_col(width = 0.7, fill = paste0("#", IU_VERDE)) +
    ggplot2::geom_text(ggplot2::aes(label = etq), hjust = -0.12, size = base / ggplot2::.pt * 0.85,
                       family = iu_letra_grafica(), color = paste0("#", IU_TEXTO)) +
    ggplot2::scale_y_continuous(limits = c(0, max(c(df$pct, IU_UMBRAL), na.rm = TRUE) * 1.22),
                                expand = c(0, 0)) +
    ggplot2::coord_flip(clip = "off") +
    iu_tema(base) +
    ggplot2::labs(caption = "Porcentaje de personas en riesgo alto o muy alto, sobre los encuestados.")
}

# Todas las dimensiones, de mayor a menor riesgo en la unidad. En rojo las que
# llegan al 30 %.
iu_grafica_ranking <- function(pob, base = 24) {
  claves <- c(paste0("dim_", names(RES_DIMS)), paste0("ex_", names(RES_EXTRA)))
  rot <- c(unname(RES_DIMS), paste(unname(RES_EXTRA), "(extralaboral)"))
  pct <- vapply(claves, function(k) iu_alto(pob$du, k), 0)
  ok <- !is.na(pct)
  df <- data.frame(medida = rot[ok], pct = pct[ok], stringsAsFactors = FALSE)
  df <- df[order(df$pct, decreasing = TRUE), , drop = FALSE]
  df$medida <- factor(df$medida, levels = rev(df$medida))
  df$color  <- ifelse(iu_rojo(df$pct), "rojo", "gris")
  df$etq    <- vapply(df$pct, iu_pct, "")
  nota <- sprintf("Porcentaje de personas de la %s en riesgo alto o muy alto. En rojo: %d %% o más.",
                  tolower(IU_NIVELES[[pob$nivel]]), IU_UMBRAL)
  if (any(!ok))
    nota <- paste0(nota, "\nNo se muestran (menos de ", RES_MIN_N, " personas): ",
                   paste(rot[!ok], collapse = ", "), ".")
  ggplot2::ggplot(df, ggplot2::aes(x = medida, y = pct, fill = color)) +
    iu_linea_umbral(nrow(df), base) +
    ggplot2::geom_col(width = 0.78) +
    ggplot2::geom_text(ggplot2::aes(label = etq), hjust = -0.12, size = base / ggplot2::.pt * 0.85,
                       family = iu_letra_grafica(), color = paste0("#", IU_TEXTO)) +
    ggplot2::scale_fill_manual(values = c(rojo = paste0("#", IU_ROJO), gris = paste0("#", IU_GRIS)),
                               guide = "none") +
    ggplot2::scale_y_continuous(limits = c(0, max(c(df$pct, IU_UMBRAL)) * 1.18), expand = c(0, 0)) +
    ggplot2::coord_flip(clip = "off") +
    iu_tema(base) +
    ggplot2::labs(caption = nota)
}

# Una sola barra: la cobertura, con la marca de la meta sugerida.
iu_grafica_cobertura <- function(pob, base = 26) {
  cob <- if (pob$esperados > 0) min(100, 100 * pob$encuestados / pob$esperados) else 0
  tam <- base / ggplot2::.pt
  ggplot2::ggplot() +
    ggplot2::annotate("rect", xmin = 0, xmax = 100, ymin = 0, ymax = 1, fill = paste0("#", IU_VERDE_SUAVE)) +
    ggplot2::annotate("rect", xmin = 0, xmax = cob, ymin = 0, ymax = 1, fill = paste0("#", IU_VERDE)) +
    ggplot2::annotate("segment", x = IU_META_COBERTURA, xend = IU_META_COBERTURA,
                      y = -0.25, yend = 1.25, linetype = "dashed", linewidth = 1.1,
                      color = paste0("#", IU_ROJO)) +
    ggplot2::annotate("text", x = IU_META_COBERTURA, y = 1.35, vjust = 0, size = tam * 0.85,
                      family = iu_letra_grafica(),
                      label = sprintf("Meta sugerida: %d %%", IU_META_COBERTURA),
                      color = paste0("#", IU_ROJO)) +
    ggplot2::annotate("text", x = 0, y = -0.35, hjust = 0, vjust = 1, size = tam,
                      family = iu_letra_grafica(), color = paste0("#", IU_VERDE),
                      fontface = "bold", label = sprintf("Cobertura: %s", iu_pct(cob))) +
    ggplot2::scale_x_continuous(limits = c(-1, 101), expand = c(0, 0)) +
    ggplot2::scale_y_continuous(limits = c(-1.1, 1.9), expand = c(0, 0)) +
    ggplot2::theme_void(base_size = base)
}

# Graficas de las diapositivas sociodemograficas: barras horizontales, una por
# categoria, con las personas y el % al final de cada barra. Cada barra ocupa
# lo mismo en todas las graficas, y ninguna pasa del borde de la diapositiva.
iu_alto_socio <- function(n) min(10.8, 1.4 + 1.0 * n)
iu_alto_grilla <- function(n) min(IU_GRILLA_ALTO, 0.9 + 0.55 * n)
iu_letra_grilla <- function(n) if (n > 14) 12 else if (n > 9) 14 else if (n > 6) 17 else 20

# Parte un rotulo largo en renglones para el eje de la grafica.
iu_envolver <- function(x, ancho) {
  vapply(x, function(s) paste(strwrap(s, ancho), collapse = "\n"), "", USE.NAMES = FALSE)
}

# Frecuencias de una variable (de iu_frecuencias()), en el orden que traen: de
# arriba hacia abajo. "Sin dato" va en gris.
iu_grafica_socio <- function(f, base = 28) {
  rot <- iu_envolver(f$categoria, 26)
  df <- data.frame(cat  = factor(rot, levels = rev(rot)),
                   pct  = f$pct,
                   etq  = sprintf("%s (%s)", fmt_num(f$n), vapply(f$pct, iu_pct, "")),
                   gris = f$categoria == RES_SIN_DATO)
  ggplot2::ggplot(df, ggplot2::aes(x = cat, y = pct, fill = gris)) +
    ggplot2::geom_col(width = 0.7) +
    ggplot2::geom_text(ggplot2::aes(label = etq), hjust = -0.1, size = base / ggplot2::.pt * 0.85,
                       family = iu_letra_grafica(), color = paste0("#", IU_TEXTO)) +
    ggplot2::scale_fill_manual(values = c(`FALSE` = paste0("#", IU_VERDE), `TRUE` = paste0("#", IU_GRIS)),
                               guide = "none") +
    ggplot2::scale_y_continuous(limits = c(0, max(df$pct) * 1.45), expand = c(0, 0)) +
    ggplot2::coord_flip(clip = "off") +
    iu_tema(base) +
    ggplot2::labs(caption = sprintf("Total: %s", iu_personas(sum(f$n))))
}

# Las dependencias de la unidad (de iu_dependencias()): la barra clara son los
# esperados y la verde, encima, los encuestados; asi se ve cuanto respondio cada
# una.
iu_grafica_dependencias <- function(f, base = if (nrow(f) > 10) 18 else 26,
                                    nota = sprintf("Barra verde: encuestados; barra clara: esperados. Total: %s de %s.",
                                                   fmt_num(sum(f$encuestados)), fmt_num(sum(f$esperados)))) {
  # Con muchas barras no hay alto para dos renglones por nombre.
  rot <- iu_envolver(f$dependencia, if (nrow(f) > 10) 70 else 34)
  df <- data.frame(cat = factor(rot, levels = rev(rot)), esp = f$esperados, enc = f$encuestados,
                   etq = sprintf("%s de %s", fmt_num(f$encuestados), fmt_num(f$esperados)))
  ggplot2::ggplot(df, ggplot2::aes(x = cat)) +
    ggplot2::geom_col(ggplot2::aes(y = esp), fill = paste0("#", IU_VERDE_PALIDO), width = 0.7) +
    ggplot2::geom_col(ggplot2::aes(y = enc), fill = paste0("#", IU_VERDE), width = 0.7) +
    ggplot2::geom_text(ggplot2::aes(y = esp, label = etq), hjust = -0.1, size = base / ggplot2::.pt * 0.85,
                       family = iu_letra_grafica(), color = paste0("#", IU_TEXTO)) +
    ggplot2::scale_y_continuous(limits = c(0, max(c(df$esp, 1)) * 1.4), expand = c(0, 0)) +
    ggplot2::coord_flip(clip = "off") +
    iu_tema(base) +
    ggplot2::labs(caption = nota)
}

# Las unidades de toda la universidad con sus esperados y encuestados, de la
# mas grande a la mas chica. Se cuentan persona por persona con las reglas de
# seg_avance() (esperados = activos; encuestados = activos con algun envio) y
# no sumando su resultado: ese va por nombre de dependencia, y hay nombres
# repetidos en varias unidades. Mismas columnas que iu_dependencias(), para
# dibujarlas con iu_grafica_dependencias().
iu_unidades_avance <- function() {
  a <- db_get(sprintf("
    SELECT m.tipo_dependencia AS dependencia,
           count(*)::int AS esperados,
           count(DISTINCT r.id_anonimizado)::int AS encuestados
      FROM seguimiento.marco_completo m
      LEFT JOIN %s r ON m.id_anonimizado = r.id_anonimizado
     WHERE m.estado_vinculacion = 'Activo'
       AND m.tipo_dependencia IS NOT NULL AND m.tipo_dependencia <> ''
     GROUP BY 1", SEG_RESPONDIO))
  a[order(-a$esperados, to_key(a$dependencia)), , drop = FALSE]
}


# La tabla de niveles de la unidad: una fila por dominio intralaboral, total
# intralaboral, extralaboral y estres; columnas Forma A y Forma B.
# Cada celda con el color del semaforo de la leyenda de la presentacion.
iu_tabla_niveles <- function(du, ancho) {
  niv <- lapply(names(IU_NIVEL_FILAS), function(k) iu_nivel_grupo(du, k))
  celda <- function(x, parte) iu_nivel_txt(x[[parte]]$n, x[[parte]]$nivel)
  nivel_de <- function(x, parte) if (x[[parte]]$n >= RES_MIN_N) x[[parte]]$nivel else NA_integer_
  t <- data.frame(medida = unname(IU_NIVEL_FILAS),
                  A = vapply(niv, celda, "", parte = "A"),
                  B = vapply(niv, celda, "", parte = "B"),
                  stringsAsFactors = FALSE)
  n_a <- sum(du$forma %in% "A"); n_b <- sum(du$forma %in% "B")
  ft <- flextable::flextable(t)
  ft <- flextable::set_header_labels(ft, medida = "Medida",
    A = sprintf("Forma A\n%s", iu_personas(n_a)),
    B = sprintf("Forma B\n%s", iu_personas(n_b)))
  ft <- flextable::font(ft, fontname = IU_LETRA, part = "all")
  ft <- flextable::fontsize(ft, size = 26, part = "all")
  ft <- flextable::fontsize(ft, size = 22, part = "header")
  ft <- flextable::bold(ft, part = "header")
  ft <- flextable::bg(ft, bg = paste0("#", IU_VERDE), part = "header")
  ft <- flextable::color(ft, color = "white", part = "header")
  ft <- flextable::bg(ft, j = 1, bg = paste0("#", IU_VERDE_SUAVE), part = "body")
  ft <- flextable::color(ft, j = 1, color = paste0("#", IU_TEXTO), part = "body")
  # El total intralaboral va en negrita: agrupa a los cuatro dominios de arriba.
  ft <- flextable::bold(ft, i = which(names(IU_NIVEL_FILAS) == "tot_intra"), j = 1, part = "body")
  for (i in seq_along(niv)) for (j in 2:3) {
    nv <- nivel_de(niv[[i]], c("A", "B")[j - 1])
    if (is.na(nv)) {
      ft <- flextable::color(ft, i = i, j = j, color = "#7F7F7F", part = "body")
    } else {
      ft <- flextable::bg(ft, i = i, j = j, bg = paste0("#", IU_NIVEL_COLOR[nv]), part = "body")
      ft <- flextable::bold(ft, i = i, j = j, part = "body")
      ft <- flextable::color(ft, i = i, j = j, part = "body",
                             color = if (nv == 5) "white" else "black")
    }
  }
  ft <- flextable::align(ft, j = 2:3, align = "center", part = "all")
  ft <- flextable::valign(ft, valign = "center", part = "all")
  blanco <- officer::fp_border(color = "white", width = 3)
  ft <- flextable::border_remove(ft)
  ft <- flextable::border_inner(ft, border = blanco, part = "all")
  ft <- flextable::padding(ft, padding.top = 8, padding.bottom = 8, padding.left = 10,
                           padding.right = 10, part = "all")
  flextable::width(ft, j = 1:3, width = ancho * c(0.56, 0.22, 0.22))
}


# Niveles de riesgo de cada unidad de la universidad, para el informe de toda
# la universidad, en una sola forma: filas = unidades (las que se le pasen, en
# ese orden), columnas = las medidas de la tabla de niveles. Cada celda es el
# nivel de las personas de esa forma en la unidad, con el semaforo.
IU_UNIDADES_POR_DIAPOSITIVA <- 14L
IU_NIVEL_COLUMNAS <- c(
  dom_liderazgo_relaciones_sociales_trabajo = "Dominio\nLiderazgo y relaciones sociales",
  dom_control_trabajo                       = "Dominio\nControl sobre el trabajo",
  dom_demandas_trabajo                      = "Dominio\nDemandas del trabajo",
  dom_recompensas                           = "Dominio\nRecompensas",
  tot_intra                                 = "Total\nintralaboral",
  tot_extra                                 = "Extralaboral",
  tot_estres                                = "Estrés")
stopifnot(identical(names(IU_NIVEL_COLUMNAS), names(IU_NIVEL_FILAS)))

iu_tabla_unidades <- function(d, unidades, forma, ancho) {
  claves <- names(IU_NIVEL_COLUMNAS)
  d <- d[d$forma %in% forma, , drop = FALSE]
  niv <- lapply(unidades, function(u) {
    du <- d[!is.na(d$tipo_dependencia) & d$tipo_dependencia == u, , drop = FALSE]
    lapply(claves, function(k) iu_nivel_grupo(du, k)[[forma]])
  })
  n_unidad <- vapply(unidades, function(u) sum(d$tipo_dependencia %in% u), 0L)
  t <- data.frame(unidad = unidades, n = fmt_num(n_unidad), stringsAsFactors = FALSE)
  for (j in seq_along(claves))
    t[[claves[j]]] <- vapply(niv, function(x) iu_nivel_txt(x[[j]]$n, x[[j]]$nivel), "")
  ft <- flextable::flextable(t)
  ft <- do.call(flextable::set_header_labels,
                c(list(ft, unidad = "Unidad", n = "Personas"), as.list(IU_NIVEL_COLUMNAS)))
  ft <- flextable::font(ft, fontname = IU_LETRA, part = "all")
  ft <- flextable::fontsize(ft, size = 20, part = "body")
  ft <- flextable::fontsize(ft, size = 16, part = "header")
  ft <- flextable::bold(ft, part = "header")
  ft <- flextable::bg(ft, bg = paste0("#", IU_VERDE), part = "header")
  ft <- flextable::color(ft, color = "white", part = "header")
  ft <- flextable::bg(ft, j = 1:2, bg = paste0("#", IU_VERDE_SUAVE), part = "body")
  ft <- flextable::color(ft, j = 1:2, color = paste0("#", IU_TEXTO), part = "body")
  for (i in seq_along(unidades)) for (j in seq_along(claves)) {
    x <- niv[[i]][[j]]
    col <- j + 2
    if (x$n < RES_MIN_N || is.na(x$nivel)) {
      ft <- flextable::color(ft, i = i, j = col, color = "#7F7F7F", part = "body")
    } else {
      ft <- flextable::bg(ft, i = i, j = col, bg = paste0("#", IU_NIVEL_COLOR[x$nivel]), part = "body")
      ft <- flextable::bold(ft, i = i, j = col, part = "body")
      ft <- flextable::color(ft, i = i, j = col, part = "body",
                             color = if (x$nivel == 5) "white" else "black")
    }
  }
  ft <- flextable::align(ft, j = seq(2, ncol(t)), align = "center", part = "all")
  ft <- flextable::valign(ft, valign = "center", part = "all")
  blanco <- officer::fp_border(color = "white", width = 2)
  ft <- flextable::border_remove(ft)
  ft <- flextable::border_inner(ft, border = blanco, part = "all")
  ft <- flextable::padding(ft, padding.top = 7, padding.bottom = 7, padding.left = 8,
                           padding.right = 8, part = "all")
  flextable::width(ft, j = seq_len(ncol(t)),
                   width = ancho * c(0.27, 0.07, rep(0.66 / length(claves), length(claves))))
}


# --- informe -----------------------------------------------------------------

# Escribe en `archivo` el informe de la unidad o dependencia `valor`.
# `nivel` es "unidad" o "dependencia".
iu_generar <- function(nivel, valor, archivo, plantilla = IU_PLANTILLA,
                       d = res_datos(), av = seg_avance(), hoy = Sys.Date()) {
  if (!file.exists(plantilla)) stop("No se encuentra la plantilla ", plantilla, call. = FALSE)
  pob <- iu_poblacion(nivel, valor, d, av)
  valor <- pob$valor
  universidad <- identical(nivel, "universidad")
  nombre_nivel <- tolower(IU_NIVELES[[nivel]])
  # Antes de clasificar a la unidad: los cortes tienen que reproducir la
  # calificacion de cada persona de la universidad.
  iu_verificar_baremos(pob$d)

  doc <- officer::read_pptx(plantilla)
  # La plantilla trae las graficas sociodemograficas en cuatro diapositivas de
  # dos; el informe las pone en dos de cuatro. Se quitan la tercera y la cuarta
  # antes de buscar las demas, que asi quedan en su numero definitivo.
  quitar <- unique(vapply(IU_SOCIO[5:8], function(s) iu_buscar(doc, s$titulo), 0L))
  for (k in sort(quitar, decreasing = TRUE)) doc <- officer::remove_slide(doc, index = k)

  # Todas se buscan antes de tocar nada: si la plantilla cambio, el error sale
  # aqui y no a medio informe.
  i_portada  <- iu_buscar(doc, "FACULTAD… INSTITUTO….")
  i_objetivo <- iu_buscar(doc, "LA FACULTAD……….")
  i_cierre   <- iu_buscar(doc, "Realizada por")
  i_cober    <- iu_buscar(doc, "# Trabajadores pactados para medición")
  i_socio    <- c(iu_buscar(doc, IU_SOCIO[[1]]$titulo), iu_buscar(doc, IU_SOCIO[[3]]$titulo))
  i_tres     <- iu_buscar(doc, IU_TRES[[1]]$viejo)
  i_resumen  <- vapply(IU_RESUMENES, function(t) iu_buscar(doc, t), 0L)

  # --- nombre y fecha ---
  iu_parrafo_texto(iu_parrafo(iu_xml(doc, i_portada), "FACULTAD… INSTITUTO…."), valor)
  t <- xml2::xml_find_first(iu_xml(doc, i_objetivo), "//a:t[contains(., 'LA FACULTAD')]", IU_NS)
  iu_run_texto(xml2::xml_parent(t), paste0(valor, " "))
  x <- iu_xml(doc, i_cierre)
  iu_parrafo_texto(iu_parrafo(x, "FACULTAD……"), valor)
  iu_parrafo_texto(iu_parrafo(x, "Noviembre 2026"), iu_fecha(hoy))

  # --- cobertura ---
  x <- iu_xml(doc, i_cober)
  tbl <- xml2::xml_find_first(x, "//a:tbl", IU_NS)
  fila <- xml2::xml_find_all(tbl, "./a:tr", IU_NS)[[2]]
  cob <- if (pob$esperados > 0) 100 * pob$encuestados / pob$esperados else NA
  efe <- if (pob$encuestados > 0) 100 * pob$efectivas / pob$encuestados else NA
  # La plantilla trae tres columnas; se agregan las de encuestas efectivas. Con
  # cinco, la tabla se ensancha a casi toda la diapositiva, el encabezado baja a
  # 28 puntos y las filas se ajustan a su texto, para no tapar los iconos.
  fr10 <- xml2::xml_find_first(x, "//p:graphicFrame[.//a:tbl]", IU_NS)
  ancho <- round(IU_ANCHO_COBERTURA * IU_EMU)
  iu_columnas_iguales(tbl, 5, total = ancho)
  xml2::xml_set_attr(xml2::xml_find_first(fr10, "./p:xfrm/a:off", IU_NS), "x",
                     format(round(IU_IZQ_COBERTURA * IU_EMU), scientific = FALSE))
  filas10 <- xml2::xml_find_all(tbl, "./a:tr", IU_NS)
  altos <- round(c(1.15, 1.0) * IU_EMU)
  for (k in 1:2) xml2::xml_set_attr(filas10[[k]], "h", format(altos[k], scientific = FALSE))
  ext10 <- xml2::xml_find_first(fr10, "./p:xfrm/a:ext", IU_NS)
  xml2::xml_set_attr(ext10, "cx", format(ancho, scientific = FALSE))
  xml2::xml_set_attr(ext10, "cy", format(sum(altos), scientific = FALSE))
  cab <- c("# Trabajadores pactados para medición", "# Trabajadores participantes",
           "% cobertura", "# Encuestas efectivas", "% encuestas efectivas")
  vals <- c(fmt_num(pob$esperados), fmt_num(pob$encuestados), iu_pct(cob),
            fmt_num(pob$efectivas), iu_pct(efe))
  filas <- xml2::xml_find_all(tbl, "./a:tr", IU_NS)
  for (j in seq_along(vals)) {
    iu_celda(iu_celdas(filas[[1]])[[j]], cab[j], tam = 28)
    iu_celda(iu_celdas(fila)[[j]], vals[j])
  }
  # Los dos cuadros de debajo de los iconos: el de la izquierda es el hombre.
  sexo <- as.character(pob$du$sexo)
  n_sexo <- function(s) sum(sexo %in% s)
  pct_sexo <- function(s) if (length(sexo)) 100 * n_sexo(s) / length(sexo) else NA
  cuadros <- xml2::xml_find_all(x, "//p:sp[.//a:t[normalize-space(.) = '25%' or normalize-space(.) = '75%']]", IU_NS)
  if (length(cuadros) != 2) stop("La plantilla no tiene los dos cuadros de sexo", call. = FALSE)
  cuadros <- cuadros[order(vapply(cuadros, function(f) iu_caja(f)$left, 0))]
  # Los iconos con sus cifras van centrados en la mitad izquierda, y la barra
  # de cobertura en la derecha, a la misma altura.
  figs <- c(as.list(xml2::xml_find_all(x, "//p:pic", IU_NS)), as.list(cuadros))
  cajas <- lapply(figs, iu_caja)
  izq <- min(vapply(cajas, `[[`, 0, "left"))
  der <- max(vapply(cajas, function(k) k$left + k$width, 0))
  dx <- IU_ANCHO_DIAPOSITIVA / 4 - (izq + der) / 2
  for (k in seq_along(figs))
    iu_mover(figs[[k]], cajas[[k]]$left + dx, cajas[[k]]$top, cajas[[k]]$width, cajas[[k]]$height)
  centro_y <- (min(vapply(cajas, `[[`, 0, "top")) +
               max(vapply(cajas, function(k) k$top + k$height, 0))) / 2
  for (k in 1:2) {
    s <- c("Masculino", "Femenino")[k]
    ps <- xml2::xml_find_all(cuadros[[k]], ".//a:p", IU_NS)
    iu_parrafo_texto(ps[[1]], iu_pct(pct_sexo(s)))
    iu_parrafo_texto(ps[[2]], fmt_num(n_sexo(s)))
  }
  doc <- officer::on_slide(doc, i_cober)
  ct <- iu_caja(xml2::xml_find_first(x, "//p:graphicFrame[.//a:tbl]", IU_NS))
  alto_t <- sum(as.numeric(xml2::xml_attr(xml2::xml_find_all(tbl, "./a:tr", IU_NS), "h"))) / IU_EMU
  # Las formulas de los dos porcentajes, debajo de la tabla.
  doc <- iu_cuadro(doc, c(
    "% cobertura = # trabajadores participantes / # trabajadores pactados para medición × 100",
    paste("% encuestas efectivas = # encuestas efectivas / # trabajadores participantes × 100",
          "(efectiva: la persona aceptó el consentimiento informado)")),
    left = ct$left, top = ct$top + alto_t + 0.02, width = ct$width, height = 1.0,
    tam = 22, color = "595959", alinear = "left")
  otros <- setdiff(unique(sexo), c("Masculino", "Femenino"))
  otros <- otros[!is.na(otros)]
  na_sexo <- sum(is.na(sexo))
  extra <- c(vapply(otros, function(s) sprintf("%s: %s (%s)", s, fmt_num(n_sexo(s)),
                                                iu_pct(pct_sexo(s))), ""),
             if (na_sexo) sprintf("Sin dato de sexo: %s", fmt_num(na_sexo)))
  ci <- iu_caja(cuadros[[1]]); cd <- iu_caja(cuadros[[2]])
  if (length(extra))
    doc <- iu_cuadro(doc, extra, left = ci$left - 1, top = ci$top + ci$height + 0.05,
                     width = cd$left + cd$width - ci$left + 2, height = 0.5 * length(extra) + 0.2,
                     tam = 24, color = IU_VERDE)
  doc <- iu_imagen(doc, iu_grafica_cobertura(pob), left = IU_ANCHO_DIAPOSITIVA * 3 / 4 - 3.8,
                   top = centro_y - 1.8, width = 7.6, height = 3.6)
  # Mientras la encuesta siga en campo, el mismo informe cambia de un dia a otro.
  doc <- iu_cuadro(doc, sprintf("Datos con corte al %s", iu_fecha(hoy)), left = 14, top = 13.9,
                   width = 11.8, height = 0.6, tam = 22, color = "595959", alinear = "right")

  # --- sociodemograficas ---
  # Dos diapositivas con cuatro graficas cada una, en rejilla de 2 x 2: cada
  # una centrada en su cuarto, con su titulo encima. Los titulos de la
  # plantilla se quitan.
  for (h in 1:2) {
    i <- i_socio[h]
    x <- iu_xml(doc, i)
    for (s in IU_SOCIO[c(2 * h - 1, 2 * h)]) xml2::xml_remove(iu_figura(iu_parrafo(x, s$titulo)))
    doc <- officer::on_slide(doc, i)
    if (pob$reservado) {
      doc <- iu_cuadro(doc, iu_aviso_texto(pob), left = iu_centro_x(20.3), top = 6, width = 20.3,
                       height = 2, tam = 40, color = IU_VERDE)
      next
    }
    for (q in 1:4) {
      s <- IU_SOCIO[[4 * (h - 1) + q]]
      centro <- IU_ANCHO_DIAPOSITIVA * (2 * ((q - 1) %% 2) + 1) / 4
      arriba <- IU_GRILLA_TITULO[(q - 1) %/% 2 + 1]
      izq <- centro - IU_GRILLA_ANCHO / 2
      abajo <- arriba + 0.95
      titulo_q <- s$nuevo
      if (identical(s$var, "dependencia") && universidad) titulo_q <- "% representación por unidad"
      doc <- iu_cuadro(doc, titulo_q, left = centro - 6.4, top = arriba, width = 12.8, height = 0.9,
                       tam = 36, color = IU_VERDE, letra = IU_LETRA_TITULO)
      if (identical(s$var, "dependencia")) {
        # Universidad: la representacion por unidad va en su propia diapositiva
        # (son demasiadas). Dependencia: no tiene a quien repartir.
        doc <- if (universidad || identical(nivel, "dependencia"))
          iu_cuadro(doc, if (universidad) "Ver la representación por unidad en la diapositiva siguiente."
                         else "Informe de una sola dependencia.",
                    left = izq, top = abajo, width = IU_GRILLA_ANCHO, height = 1,
                    tam = 24, color = IU_VERDE)
        else {
          fd <- iu_dependencias(pob)
          iu_imagen(doc, iu_grafica_dependencias(fd, base = iu_letra_grilla(nrow(fd))),
                    left = izq, top = abajo, width = IU_GRILLA_ANCHO, height = iu_alto_grilla(nrow(fd)))
        }
        next
      }
      f <- iu_frecuencias(pob$du, s$var)
      doc <- iu_imagen(doc, iu_grafica_socio(f, base = iu_letra_grilla(nrow(f))),
                       left = izq, top = abajo, width = IU_GRILLA_ANCHO, height = iu_alto_grilla(nrow(f)))
    }
  }

  # --- intralaboral, extralaboral y estres ---
  # El nivel de riesgo de la unidad en los tres, un renglon por cada forma que
  # tenga personas. Los tres cuadros van en fila, del mismo ancho.
  x <- iu_xml(doc, i_tres)
  for (k in seq_along(IU_TRES)) {
    tr <- IU_TRES[[k]]
    nv <- iu_nivel_grupo(pob$du, tr$clave)
    p <- iu_parrafo(x, tr$viejo)
    runs <- xml2::xml_find_all(p, "./a:r", IU_NS)
    iu_run_texto(runs[[1]], tr$nuevo)
    for (r in runs[-1]) xml2::xml_remove(r)
    # Debajo, un parrafo por forma: "Forma A: " y el nivel en negrita.
    formas <- Filter(function(f) nv[[f]]$n > 0, c("A", "B"))
    for (f in rev(formas)) {
      q <- xml2::xml_add_sibling(p, p, .where = "after")
      r1 <- xml2::xml_find_first(q, "./a:r", IU_NS)
      r2 <- xml2::xml_add_sibling(r1, r1, .where = "after")
      iu_run_texto(r1, sprintf("Forma %s: ", f))
      iu_run_texto(r2, iu_nivel_txt(nv[[f]]$n, nv[[f]]$nivel))
      xml2::xml_set_attr(xml2::xml_find_first(r1, "./a:rPr", IU_NS), "b", "0")
      xml2::xml_set_attr(xml2::xml_find_first(r2, "./a:rPr", IU_NS), "b", "1")
    }
    fig <- iu_figura(p)
    iu_mover(fig, IU_ANCHO_DIAPOSITIVA * (2 * k - 1) / 6 - 3.9, 5.2, 7.8, 3.4)
    for (q in xml2::xml_find_all(fig, ".//a:p", IU_NS)) {
      ppr <- xml2::xml_find_first(q, "./a:pPr", IU_NS)
      if (inherits(ppr, "xml_missing")) ppr <- xml2::xml_add_child(q, "a:pPr", .where = 0)
      xml2::xml_set_attr(ppr, "algn", "ctr")
    }
  }
  doc <- officer::on_slide(doc, i_tres)
  doc <- iu_cuadro(doc, sprintf("¿Cómo está %s en términos generales?", iu_con_articulo(nivel, valor)),
                   left = iu_centro_x(19.2), top = 1.0, width = 19.2, height = 2.4, tam = 48,
                   color = IU_VERDE, letra = IU_LETRA_TITULO)
  if (pob$reservado)
    doc <- iu_cuadro(doc, iu_aviso_texto(pob), left = iu_centro_x(20.3), top = 8.8, width = 20.3,
                     height = 2, tam = 40, color = IU_VERDE)

  # --- resumenes por dominio ---
  cols <- iu_columnas(pob)
  # Textos del equipo (2026-11-06).
  notas <- c(
    sprintf(paste("Cada cifra es la suma del porcentaje de personas en riesgo alto o muy alto,",
                  "calculado sobre los encuestados de cada columna. En rojo: %d %% o más. No se",
                  "presentan datos de grupos con < %d: grupo con menos de %d personas, quedan como",
                  "parte del resultado general."),
            IU_UMBRAL, RES_MIN_N, RES_MIN_N))
  nota_a <- paste("No aplica: esta dimensión solo se evalúa en la Forma A (jefes, profesionales y",
                  "técnicos); por eso, en las demás columnas su porcentaje sale únicamente de quienes",
                  "respondieron la Forma A.")
  for (i in i_resumen) {
    x <- iu_xml(doc, i)
    fr <- xml2::xml_find_first(x, "//p:graphicFrame[.//a:tbl]", IU_NS)
    caja <- iu_caja(fr)
    doc <- officer::on_slide(doc, i)
    if (pob$reservado) {
      xml2::xml_remove(fr)
      doc <- iu_cuadro(doc, iu_aviso_texto(pob), left = iu_centro_x(20.3), top = 6, width = 20.3, height = 2,
                       tam = 40, color = IU_VERDE)
      next
    }
    tbl <- xml2::xml_find_first(fr, ".//a:tbl", IU_NS)
    iu_columnas_tabla(tbl, length(cols))
    # Centrada en la diapositiva; la nota de abajo la sigue.
    iu_mover(fr, iu_centro_x(caja$width), caja$top, caja$width, caja$height)
    caja$left <- iu_centro_x(caja$width)
    trs <- xml2::xml_find_all(tbl, "./a:tr", IU_NS)
    if (iu_norm(iu_texto(iu_celdas(trs[[1]])[[1]])) != iu_norm("Dimensión"))
      stop("La tabla de resumen no empieza con Dimensión", call. = FALSE)
    # Letra del encabezado segun cuantas columnas haya: 28 puntos, como la
    # plantilla, hasta cinco.
    tam_cab <- c(28, 28, 28, 28, 28, 26, 22, 20)[min(length(cols), 8)]
    for (j in seq_along(cols)) {
      iu_celda(iu_celdas(trs[[1]])[[j + 1]], cols[[j]]$titulo, tam = tam_cab)
      iu_celda(iu_celdas(trs[[2]])[[j + 1]], iu_personas(nrow(cols[[j]]$d)), tam = tam_cab)
    }
    con_a <- FALSE
    filas <- stats::setNames(unname(IU_FILAS), iu_norm(names(IU_FILAS)))
    for (tr in trs[-(1:2)]) {
      cel <- iu_celdas(tr)
      rot <- iu_norm(iu_texto(cel[[1]]))
      if (!rot %in% names(filas)) stop("Fila desconocida en la plantilla: ", iu_texto(cel[[1]]),
                                       call. = FALSE)
      clave <- filas[[rot]]
      if (clave %in% RES_SOLO_A_CLAVES) con_a <- TRUE
      for (j in seq_along(cols)) {
        v <- iu_celda_valor(cols[[j]], clave)
        iu_celda(cel[[j + 1]], v$texto, rojo = v$rojo)
      }
    }
    # La nota va debajo de la tabla. Si no cabe antes del borde de la
    # diapositiva, se achican las dos filas del encabezado, que en la
    # plantilla son mas altas de lo que necesita su texto.
    nota <- c(notas, if (con_a) nota_a)
    # Renglones de 20 puntos: la nota general ocupa dos y la de "No aplica" otros dos.
    alto_nota <- 0.4 * (2 + 2 * con_a) + 0.15
    h <- as.numeric(xml2::xml_attr(trs, "h"))
    sobra <- caja$top + sum(h) / IU_EMU + 0.05 + alto_nota - IU_ALTO_DIAPOSITIVA
    if (sobra > 0) {
      for (k in 1:2) {
        nuevo <- max(h[k] - sobra / 2 * IU_EMU, IU_ALTO_CABECERA * IU_EMU)
        xml2::xml_set_attr(trs[[k]], "h", format(round(nuevo), scientific = FALSE))
      }
      h <- as.numeric(xml2::xml_attr(trs, "h"))
      ext <- xml2::xml_find_first(fr, "./p:xfrm/a:ext", IU_NS)
      xml2::xml_set_attr(ext, "cy", format(round(sum(h)), scientific = FALSE))
    }
    doc <- iu_cuadro(doc, nota, left = caja$left, top = caja$top + sum(h) / IU_EMU + 0.05,
                     width = caja$width, height = alto_nota, tam = 20, alinear = "left")
  }

  # --- diapositivas nuevas ---
  # Cada una dice despues de cual diapositiva de la plantilla va y como se
  # llena. Se agregan al final, cuando ya no se va a tocar ninguna otra por su
  # numero, y luego se mueven a su sitio:
  #   la tabla de niveles               despues de intralaboral, extralaboral y estres
  #   niveles por unidad (universidad)  ahi mismo, a continuacion
  #   representacion por unidad (id.)   despues de la de antiguedad
  #   las dos graficas de riesgo        despues del ultimo resumen; en el de la
  #                                     universidad la segunda es solo de ella
  despues <- max(i_resumen)
  # El numero de diapositiva es un campo que trae cada diapositiva de la
  # plantilla salvo la portada; a las nuevas se les copia el de la del
  # objetivo. La plantilla numera desde 0 (la portada no cuenta), asi que el
  # valor guardado es la posicion menos uno; PowerPoint lo recalcula al abrir.
  numero <- xml2::xml_find_first(iu_xml(doc, i_objetivo), "//p:sp[.//p:ph[@type='sldNum']]", IU_NS)
  if (inherits(numero, "xml_missing")) stop("La plantilla no tiene el numero de diapositiva", call. = FALSE)
  numerar <- function(doc, n) {
    arbol <- xml2::xml_find_first(iu_xml(doc, length(doc)), "//p:spTree", IU_NS)
    nuevo <- xml2::xml_add_child(arbol, numero)
    t <- xml2::xml_find_first(nuevo, ".//a:fld/a:t", IU_NS)
    xml2::xml_text(t) <- as.character(n)
    doc
  }
  titulo <- function(doc, t)
    iu_cuadro(doc, t, left = iu_centro_x(19.2), top = 0.9, width = 19.2, height = 1.4, tam = 54, color = IU_VERDE,
              letra = IU_LETRA_TITULO)
  # El nombre de la unidad junto al numero, en todas menos la portada: quien
  # lee una diapositiva suelta sabe de que unidad es.
  pie <- function(doc)
    iu_cuadro(doc, valor, left = 0.95, top = 0.24, width = 9.5, height = 0.55, tam = 20,
              color = "595959", alinear = "left")
  for (k in setdiff(seq_len(length(doc)), i_portada)) {
    doc <- officer::on_slide(doc, k)
    doc <- pie(doc)
  }
  aviso <- function(doc)
    iu_cuadro(doc, iu_aviso_texto(pob), left = iu_centro_x(20.3), top = 6, width = 20.3, height = 2,
              tam = 40, color = IU_VERDE)
  nueva <- function(tras, llenar) list(tras = tras, llenar = llenar)

  nuevas <- list(nueva(i_tres, function(doc) {
    doc <- titulo(doc, sprintf("Nivel de riesgo de la %s", nombre_nivel))
    doc <- pie(doc)
    if (pob$reservado) return(aviso(doc))
    ancho <- 20
    doc <- officer::ph_with(doc, iu_tabla_niveles(pob$du, ancho),
                            location = officer::ph_location(left = iu_centro_x(ancho), top = 2.9))
    # Las explicaciones de "< 7" y de la raya solo van si la tabla las tiene.
    n_forma <- c(A = sum(pob$du$forma %in% "A"), B = sum(pob$du$forma %in% "B"))
    sin_forma <- names(n_forma)[n_forma == 0]
    pocas <- names(n_forma)[n_forma > 0 & n_forma < RES_MIN_N]
    nota <- c(
      if (length(pocas))
        sprintf("< %d: la Forma %s tiene menos de %d personas en esta %s; su nivel no se muestra.",
                RES_MIN_N, pocas[1], RES_MIN_N, nombre_nivel),
      if (length(sin_forma))
        sprintf("\u2014: en esta %s nadie respondió la Forma %s.", nombre_nivel, sin_forma[1]))
    if (!length(nota)) return(doc)
    iu_cuadro(doc, nota, left = iu_centro_x(ancho), top = 9.1, width = ancho, height = 1.2, tam = 22,
              color = "595959", alinear = "left")
  }))

  if (universidad) {
    # Niveles por unidad, una tabla por forma (primero toda la A, despues la
    # B), en orden alfabetico y repartidas en varias diapositivas.
    unidades <- iu_unidades_avance()$dependencia
    unidades <- unidades[order(to_key(unidades))]
    trozos <- split(unidades, ceiling(seq_along(unidades) / IU_UNIDADES_POR_DIAPOSITIVA))
    por_forma <- function(f) lapply(seq_along(trozos), function(k) nueva(i_tres, function(doc) {
      doc <- titulo(doc, if (length(trozos) > 1)
        sprintf("Nivel de riesgo por unidad \u2014 Forma %s (%d de %d)", f, k, length(trozos))
        else sprintf("Nivel de riesgo por unidad \u2014 Forma %s", f))
      doc <- pie(doc)
      ancho <- 24.4
      doc <- officer::ph_with(doc, iu_tabla_unidades(pob$d, trozos[[k]], f, ancho),
                              location = officer::ph_location(left = iu_centro_x(ancho), top = 2.5))
      iu_cuadro(doc,
        sprintf(paste("Personas: las de la Forma %s en la unidad. < %d: son menos de %d; su nivel",
                      "no se muestra. \u2014: nadie de la Forma %s en la unidad ha respondido."),
                f, RES_MIN_N, RES_MIN_N, f),
        left = iu_centro_x(ancho), top = 2.5 + 1.0 + 0.6 * length(trozos[[k]]) + 0.3,
        width = ancho, height = 0.9, tam = 20, color = "595959", alinear = "left")
    }))
    nuevas <- c(nuevas, por_forma("A"), por_forma("B"))
    # Representacion por unidad: esperados y encuestados, en las dos mitades.
    nuevas <- c(nuevas, list(nueva(i_socio[length(i_socio)], function(doc) {
      doc <- titulo(doc, "Representación por unidad")
      doc <- pie(doc)
      fu <- iu_unidades_avance()
      mitad <- ceiling(nrow(fu) / 2)
      partes <- list(fu[seq_len(mitad), , drop = FALSE], fu[-seq_len(mitad), , drop = FALSE])
      ancho <- IU_SOCIO_GRAFICA_ANCHO
      for (k in 1:2) {
        f <- partes[[k]]
        if (!nrow(f)) next
        nota <- if (k == 2 || !nrow(partes[[2]]))
          sprintf("Barra verde: encuestados; barra clara: esperados. Total: %s de %s.",
                  fmt_num(sum(fu$encuestados)), fmt_num(sum(fu$esperados))) else ""
        doc <- iu_imagen(doc, iu_grafica_dependencias(f, base = 18, nota = nota),
                         left = IU_ANCHO_DIAPOSITIVA * (2 * k - 1) / 4 - ancho / 2, top = 2.6,
                         width = ancho, height = iu_alto_socio(max(nrow(partes[[1]]), nrow(partes[[2]]))))
      }
      doc
    })))
  }

  nuevas <- c(nuevas, list(nueva(despues, function(doc) {
    doc <- titulo(doc, "Dimensiones ordenadas por riesgo")
    doc <- pie(doc)
    if (pob$reservado) aviso(doc)
    else iu_imagen(doc, iu_grafica_ranking(pob), left = iu_centro_x(23.9), top = 2.3, width = 23.9, height = 12.3)
  })))
  # La comparacion con la universidad no va en el informe de la universidad: en
  # su lugar, los mismos dominios solo para la universidad.
  if (universidad) nuevas <- c(nuevas, list(nueva(despues, function(doc) {
    doc <- titulo(doc, "Riesgo alto o muy alto por dominio")
    doc <- pie(doc)
    if (pob$reservado) aviso(doc)
    else iu_imagen(doc, iu_grafica_dominios(pob), left = iu_centro_x(23.3), top = 2.5,
                   width = 23.3, height = 11.5)
  })))
  if (!universidad) nuevas <- c(nuevas, list(nueva(despues, function(doc) {
    doc <- titulo(doc, sprintf("%s frente a la universidad, por dominio",
                               if (nivel == "unidad") "La unidad" else "La dependencia"))
    doc <- pie(doc)
    if (pob$reservado) aviso(doc)
    else iu_imagen(doc, iu_grafica_comparar(pob, names(IU_DOMINIOS), unname(IU_DOMINIOS)),
                   left = iu_centro_x(23.3), top = 2.5, width = 23.3, height = 11.5)
  })))

  # Se insertan en orden de sitio (las de un mismo sitio, en el orden de la
  # lista). La nueva j queda en la posicion tras + j, y una de la plantilla en
  # su posicion mas las nuevas que van antes que ella: con eso se ajusta el
  # numero guardado de cada una antes de insertar.
  nuevas <- nuevas[order(vapply(nuevas, `[[`, 0, "tras"), seq_along(nuevas))]
  tras <- vapply(nuevas, `[[`, 0, "tras")
  for (k in seq.int(2, length(doc))) {
    t <- xml2::xml_find_first(iu_xml(doc, k), "//p:sp[.//p:ph[@type='sldNum']]//a:fld/a:t", IU_NS)
    if (!inherits(t, "xml_missing")) xml2::xml_text(t) <- as.character(k + sum(tras < k) - 1)
  }
  for (j in seq_along(nuevas)) {
    pos <- tras[j] + j
    doc <- officer::add_slide(doc, layout = "TITLE", master = officer::layout_summary(doc)$master[1])
    doc <- nuevas[[j]]$llenar(doc)
    doc <- numerar(doc, pos - 1)
    doc <- officer::move_slide(doc, index = length(doc), to = pos)
  }

  print(doc, target = archivo)
  invisible(archivo)
}

# Nombre de archivo: informe_unidad_facultad_de_medicina_20261105.pptx (y
# informe_universidad_de_antioquia_20261105.pptx para toda la universidad)
iu_archivo <- function(nivel, valor, hoy = Sys.Date()) {
  if (identical(nivel, "universidad"))
    return(sprintf("informe_universidad_de_antioquia_%s.pptx", format(hoy, "%Y%m%d")))
  slug <- gsub("_+", "_", gsub("[^a-z0-9]+", "_", to_key(valor)))
  slug <- substr(gsub("^_|_$", "", slug), 1, 50)
  sprintf("informe_%s_%s_%s.pptx", nivel, slug, format(hoy, "%Y%m%d"))
}

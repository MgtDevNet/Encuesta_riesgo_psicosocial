# -----------------------------------------------------------------------------
# utils_resultados.R
# Resultados de la Batería por grupos de personas. Sin nada de UI.
#
# La unidad es la ENCUESTA EFECTIVA: una por persona activa del marco, su envío
# más reciente, y solo si aceptó el consentimiento. Es exactamente la regla con
# que la pestaña de avance cuenta sus "efectivas" (seg_sql_efectiva(), la vista
# estado_persona), así que el n de aquí y el de allá son el mismo número. No
# hace falta filtrar por ítems en blanco: el formulario tiene todas las
# preguntas obligatorias, y quien acepta contesta entero.
#
# El denominador de un grupo es por tanto "los que contestaron", que no es el
# mismo de utils_seguimiento.R para el avance (allí es la población elegible).
# Son dos preguntas distintas --cuánto falta por aplicar / qué salió-- y
# mezclar sus denominadores es la forma más fácil de publicar un número que no
# cuadra.
#
# Formas A y B: cada persona contesta una sola, y la decide el PUESTO --A para
# jefaturas, profesionales y técnicos; B para auxiliares y operarios--. Cada
# forma tiene sus propios ítems y su propio baremo, así que aquí son medidas
# distintas y viven en columnas distintas: nada las funde. Ver el catálogo.
# -----------------------------------------------------------------------------

# Mínimo de cuestionarios para mostrar el resultado de un grupo. Es el mismo
# criterio de SEG_MIN_N y la misma razón: por debajo de este número el reparto
# delata la respuesta de una persona concreta (manual general, §6.2).
RES_MIN_N <- 7L

RES_NIVELES <- c("Sin riesgo o riesgo despreciable", "Riesgo bajo",
                 "Riesgo medio", "Riesgo alto", "Riesgo muy alto")

# Los dos niveles que disparan intervención. Todo el módulo resume el reparto
# en este porcentaje, que es la cifra que se lleva a una decisión.
RES_ALTOS <- 4:5


# --- catálogo de medidas ------------------------------------------------------
# La Batería no es una lista de medidas homogéneas, y este archivo dejó de
# tratarla como tal. Son tres instrumentos distintos y, dentro del intralaboral,
# dos formas con ítems y baremos propios:
#
#   Intralaboral forma A   jefaturas, profesionales y técnicos   19 dimensiones
#   Intralaboral forma B   auxiliares y operarios                16 dimensiones
#   Extralaboral           el mismo cuestionario para todos       7 dimensiones
#   Estrés                 el mismo cuestionario para todos       1 total
#
# Antes las dos formas se fundían con COALESCE en una sola columna. El NIVEL de
# riesgo sí es comparable --para eso está el baremo de cada forma--, pero el
# instrumento no: A tiene tres dimensiones que B no tiene, y una diferencia de
# composición A/B se leía como diferencia de la gente. Ahora cada forma es su
# propia medida, con su propio denominador y su propia referencia. Que un A y un
# B no se comparen entre sí pasó a ser una propiedad del catálogo, no un aviso
# que había que leer.
#
# Efecto lateral de separarlas: la columna de una medida de la forma A está
# vacía en quien contestó la B, así que res_reparto() --que descarta NA-- ya
# cuenta solo a los A. La referencia por forma sale sola y no hace falta
# ajustarla a mano.
#
# El total general (intralaboral + extralaboral) tiene baremo propio en el
# manual: NO es el promedio de los otros dos, y es la cifra con la que se decide
# si un puesto entra en vigilancia. También depende de la forma.

RES_DOMS <- c(
  liderazgo_relaciones_sociales_trabajo = "Liderazgo y relaciones sociales",
  control_trabajo                       = "Control sobre el trabajo",
  demandas_trabajo                      = "Demandas del trabajo",
  recompensas                           = "Recompensas")

# Las 19 dimensiones intralaborales. Las tres de RES_SOLO_A existen únicamente
# en la forma A, y por eso el bloque de la B tiene 16 filas y el de la A, 19.
RES_DIMS <- c(
  caracteristicas_liderazgo                     = "Características del liderazgo",
  relaciones_sociales_trabajo                   = "Relaciones sociales en el trabajo",
  retroalimentacion_desempeno                   = "Retroalimentación del desempeño",
  relacion_colaboradores                        = "Relación con los colaboradores",
  claridad_rol                                  = "Claridad de rol",
  capacitacion                                  = "Capacitación",
  participacion_manejo_cambio                   = "Participación y manejo del cambio",
  oportunidades_uso_desarrollo_habilidades      = "Oportunidades de uso y desarrollo de habilidades",
  control_autonomia_trabajo                     = "Control y autonomía sobre el trabajo",
  demandas_ambientales_esfuerzo_fisico          = "Demandas ambientales y esfuerzo físico",
  demandas_emocionales                          = "Demandas emocionales",
  demandas_cuantitativas                        = "Demandas cuantitativas",
  influencia_trabajo_entorno_extralaboral       = "Influencia del trabajo sobre el entorno extralaboral",
  demandas_carga_mental                         = "Demandas de carga mental",
  demandas_jornada_trabajo                      = "Demandas de la jornada de trabajo",
  exigencias_responsabilidad_cargo              = "Exigencias de responsabilidad del cargo",
  consistencia_rol                              = "Consistencia del rol",
  recompensas_derivadas_pertenencia_organizacion= "Recompensas por pertenecer a la organización",
  reconocimiento_compensacion                   = "Reconocimiento y compensación")

# Solo en la forma A. "Relación con los colaboradores" además solo la contesta
# quien tiene personal a cargo, así que su n es menor que el del bloque: la fila
# lo dice, porque cada fila lleva su propio n.
RES_SOLO_A <- c("relacion_colaboradores",
                "exigencias_responsabilidad_cargo",
                "consistencia_rol")

RES_EXTRA <- c(
  balance_vida_laboral_familiar           = "Tiempo fuera del trabajo",
  relaciones_familiares                   = "Relaciones familiares",
  comunicacion_relaciones_interpersonales = "Comunicación y relaciones interpersonales",
  situacion_economica_grupo_familiar      = "Situación económica del grupo familiar",
  caracteristicas_vivienda_entorno        = "Características de la vivienda y su entorno",
  influencia_entorno_extralaboral_trabajo = "Influencia del entorno extralaboral sobre el trabajo",
  desplazamiento_vivienda_trabajo_vivienda= "Desplazamiento vivienda-trabajo-vivienda")

# Qué dimensión cuelga de qué dominio (Ministerio de la Protección Social,
# 2010). Es la única declaración de la jerarquía: de aquí salen el orden de
# lectura, la sangría de la tabla y las claves de cada forma.
RES_DOM_DIMS <- list(
  liderazgo_relaciones_sociales_trabajo = c(
    "caracteristicas_liderazgo",
    "relaciones_sociales_trabajo",
    "retroalimentacion_desempeno",
    "relacion_colaboradores"),
  control_trabajo = c(
    "claridad_rol",
    "capacitacion",
    "participacion_manejo_cambio",
    "oportunidades_uso_desarrollo_habilidades",
    "control_autonomia_trabajo"),
  demandas_trabajo = c(
    "demandas_ambientales_esfuerzo_fisico",
    "demandas_emocionales",
    "demandas_cuantitativas",
    "influencia_trabajo_entorno_extralaboral",
    "demandas_carga_mental",
    "demandas_jornada_trabajo",
    "exigencias_responsabilidad_cargo",
    "consistencia_rol"),
  recompensas = c(
    "recompensas_derivadas_pertenencia_organizacion",
    "reconocimiento_compensacion"))

RES_FORMA_TXT <- c(
  A = "jefaturas, profesionales y técnicos",
  B = "auxiliares y operarios")

# Las dimensiones que tiene una forma, en el orden del manual. La vista total
# las tiene TODAS: es la unión de las dos formas y no su intersección, porque
# esconder las tres exclusivas de la A haría creer que no existen.
res_dims_de <- function(forma) {
  d <- names(RES_DIMS)
  if (identical(forma, "B")) setdiff(d, RES_SOLO_A) else d
}


# --- las tres vistas de un cuestionario ---------------------------------------
# La Batería son TRES instrumentos --intralaboral, extralaboral y estrés-- y el
# intralaboral se responde en dos formas según el puesto. En pantalla eso eran
# cuatro bloques (A, B, extralaboral, estrés); ahora son los tres cuestionarios
# y la forma se elige DENTRO de cada uno.
#
# El mecanismo es uno solo para los tres: la vista FILTRA LAS FILAS por forma.
#
#   A   solo quien contestó la forma A
#   B   solo quien contestó la B
#   T   todas las encuestas efectivas del segmento
#
# En el intralaboral basta con eso porque sus columnas llegan FUNDIDAS (ver
# res_datos()): cada persona aporta el nivel que le calculó SU baremo, así que
# quedarse con las filas de la A deja exactamente la forma A. En extralaboral y
# estrés el cuestionario ya era uno solo para todos, y la vista parte la
# población igual que cualquier otro corte.
#
# QUÉ SE PUEDE Y QUÉ NO. El NIVEL es comparable entre formas --para eso existe
# el baremo de cada una, que traduce puntajes de instrumentos distintos a la
# misma escala de cinco niveles-- y por eso la vista total puede sumarlos. El
# PUNTAJE no lo sería, pero aquí no se usa ninguno: todo el módulo cuenta
# niveles. Lo que sigue sin poder hacerse es leer una diferencia entre la vista
# A y la vista B como una diferencia de la gente: son dos tablas de calificación
# distintas, y quien mira tiene que saberlo antes de restarlas.
RES_VISTAS <- c("Forma A" = "A", "Forma B" = "B", "Total" = "T")
RES_VISTA_DEF <- "T"

res_vista_txt <- function(v) {
  i <- match(v, RES_VISTAS)
  if (is.na(i)) "Total" else names(RES_VISTAS)[i]
}

# Las filas de una vista. Es la ÚNICA operación de toda la pantalla que
# distingue una forma de la otra: no hay ninguna otra rama que pregunte por
# `forma`, y por eso agregar una cuarta vista sería agregar una entrada a
# RES_VISTAS, no otro camino de cálculo.
res_vista <- function(d, vista = RES_VISTA_DEF) {
  if (is.null(d) || !nrow(d) || identical(vista, "T")) return(d)
  d[!is.na(d$forma) & d$forma == vista, , drop = FALSE]
}

# Claves del intralaboral, en orden de lectura: total general, total
# intralaboral y después cada dominio seguido de sus dimensiones. SIN sufijo de
# forma, porque la columna ya viene fundida.
res_claves_intra <- function() {
  c("tot_ie", "tot_intra",
    unlist(lapply(names(RES_DOMS), function(dm)
      c(sprintf("dom_%s", dm),
        sprintf("dim_%s", RES_DOM_DIMS[[dm]]))),
      use.names = FALSE))
}

# Las tres exclusivas de la forma A, ya como claves. En la vista B no se listan
# --el instrumento no las mide, y una fila vacía inventaría una medida que no
# existe-- y en la vista total se listan MARCADAS: sin la marca, un n de 1.215
# en medio de filas de 1.499 se lee como un error de cálculo.
RES_SOLO_A_CLAVES <- paste0("dim_", RES_SOLO_A)

# Los tres cuestionarios de la pantalla. Dentro de una vista todas las filas de
# un cuestionario comparten población y referencia, que son las dos cosas que
# hacen que se puedan poner una debajo de otra. Entre cuestionarios no se
# compara nada.
RES_BLOQUES <- list(
  list(id = "intra",  titulo = "Intralaboral",
       sub    = "el trabajo · dos formas según el puesto",
       claves = res_claves_intra()),
  list(id = "extra",  titulo = "Extralaboral",
       sub    = "fuera del trabajo · el mismo cuestionario para todos",
       claves = c("tot_extra", paste0("ex_", names(RES_EXTRA)))),
  list(id = "estres", titulo = "Estrés",
       sub    = "síntomas · el mismo cuestionario para todos",
       claves = "tot_estres"))

# Las claves de un cuestionario EN UNA VISTA. Solo el intralaboral cambia: la
# forma B no tiene las tres dimensiones exclusivas de la A.
res_claves_bloque <- function(b, vista = RES_VISTA_DEF) {
  if (identical(b$id, "intra") && identical(vista, "B"))
    setdiff(b$claves, RES_SOLO_A_CLAVES)
  else b$claves
}

# Todas las medidas, en orden de lectura. El catálogo es el que manda: las
# claves no se escriben a mano en ningún otro sitio.
RES_MEDIDAS <- unlist(lapply(RES_BLOQUES, function(b) b$claves), use.names = FALSE)

# El cuestionario al que pertenece cada medida.
RES_BLOQUE_DE <- unlist(lapply(RES_BLOQUES, function(b)
  stats::setNames(rep(b$id, length(b$claves)), b$claves)))

# La clave sin el sufijo de forma. Solo las de cabecera lo llevan --tot_ie_a--,
# porque las tarjetas siguen dando una cifra por baremo; las del catálogo ya
# vienen fundidas. Ninguna dimensión ni dominio termina en _a o _b, así que el
# recorte no puede comerse parte de un nombre.
res_base_clave <- function(clave) sub("_[ab]$", "", clave)

# "total", "dominio" o "dimension": es lo único que la tabla necesita para
# sangrar y jerarquizar.
res_nivel_de <- function(clave) {
  k <- res_base_clave(clave)
  if (grepl("^tot_", k)) "total"
  else if (grepl("^dom_", k)) "dominio"
  else "dimension"
}

# El dominio al que pertenece cada dimensión intralaboral. Es la vuelta de
# RES_DOM_DIMS, y hace falta porque en el ranking ordenado por riesgo la
# jerarquía se pierde: una dimensión puede quedar veinte filas por debajo del
# dominio que la contiene, o encima.
RES_DOM_DE <- unlist(lapply(names(RES_DOM_DIMS), function(dm)
  stats::setNames(rep(dm, length(RES_DOM_DIMS[[dm]])), RES_DOM_DIMS[[dm]])))

# De qué se compone un cuestionario en una vista: "2 totales · 4 dominios · 19
# dimensiones". Se calcula sobre las claves de ESA vista, porque la forma B
# tiene tres dimensiones menos y un subtítulo fijo mentiría en una de las tres.
res_composicion <- function(claves) {
  niv <- vapply(claves, res_nivel_de, "")
  n   <- function(x) sum(niv == x)
  paste(c(
    if (n("total"))     sprintf("%s %s", n("total"),
                                if (n("total") == 1) "total" else "totales"),
    if (n("dominio"))   sprintf("%s %s", n("dominio"),
                                if (n("dominio") == 1) "dominio" else "dominios"),
    if (n("dimension")) sprintf("%s %s", n("dimension"),
                                if (n("dimension") == 1) "dimensión" else "dimensiones")),
    collapse = " · ")
}

# Dónde está una medida dentro de su cuestionario, para el `title` de cada fila.
# Un dominio agrega a sus dimensiones y un total a sus dominios: sin esto, con
# el ranking ordenado por riesgo, "Demandas del trabajo" y "Demandas
# emocionales" son dos filas idénticas de las que una está contada dentro de la
# otra.
#
# Cuántas dimensiones agrega un dominio DEPENDE DE LA VISTA, porque dos de los
# cuatro pierden filas en la forma B. En la vista total se dicen las dos cifras:
# es el único sitio donde conviven las dos formas.
res_sitio_de <- function(clave, vista = RES_VISTA_DEF) {
  k <- res_base_clave(clave)

  if (identical(k, "tot_ie"))
    return(list(nivel = "Total", detalle = "intralaboral + extralaboral"))
  if (identical(k, "tot_intra"))
    return(list(nivel = "Total",
                detalle = sprintf("agrupa sus %s dominios", length(RES_DOMS))))
  if (identical(k, "tot_extra"))
    return(list(nivel = "Total",
                detalle = sprintf("agrupa sus %s dimensiones", length(RES_EXTRA))))
  if (identical(k, "tot_estres"))
    return(list(nivel = "Total", detalle = NULL))
  if (grepl("^ex_", k))
    return(list(nivel = "Dimensión", detalle = NULL))

  if (grepl("^dom_", k)) {
    dm <- sub("^dom_", "", k)
    ka <- length(intersect(RES_DOM_DIMS[[dm]], res_dims_de("A")))
    kb <- length(intersect(RES_DOM_DIMS[[dm]], res_dims_de("B")))
    det <- if (ka == kb || identical(vista, "A")) sprintf("agrupa %s dimensiones", ka)
           else if (identical(vista, "B"))        sprintf("agrupa %s dimensiones", kb)
           else sprintf("agrupa %s dimensiones (%s en la forma B)", ka, kb)
    return(list(nivel = "Dominio", detalle = det))
  }

  st <- sub("^dim_", "", k)
  list(nivel = "Dimensión", detalle = sprintf("de %s", RES_DOMS[[RES_DOM_DE[[st]]]]))
}

# El rótulo sale de la clave, no de una segunda lista que habría que mantener a
# la par. La vista NO va en el rótulo: la dice el cuestionario, y repetirla en
# cada una de las 25 filas solo gasta renglón. res_rotulo_vista() la añade donde
# la fila viaja sola --los focos, el detalle, el Excel--.
res_rotulo_de <- function(clave) {
  k <- res_base_clave(clave)
  if (identical(k, "tot_ie"))     return("Total general (intra + extra)")
  if (identical(k, "tot_intra"))  return("Intralaboral (total)")
  if (identical(k, "tot_extra"))  return("Extralaboral (total)")
  if (identical(k, "tot_estres")) return("Estrés")
  if (grepl("^ex_",  k)) return(unname(RES_EXTRA[[sub("^ex_",  "", k)]]))
  if (grepl("^dom_", k)) return(unname(RES_DOMS[[sub("^dom_", "", k)]]))
  if (grepl("^dim_", k)) return(unname(RES_DIMS[[sub("^dim_", "", k)]]))
  clave
}

# Las cifras que encabezan la pantalla. Siguen PARTIDAS POR FORMA y no fundidas,
# a diferencia del resto: son las cifras con las que se decide, y un 40 % de la
# A y un 40 % de la B no salen de la misma tabla de calificación. Abajo, en los
# cuestionarios, fundirlas es una vista que se elige; aquí arriba, donde no hay
# nada que elegir, cada baremo lleva su propia tarjeta.
#
# Van agrupadas por población: primero las dos de la forma A, luego las dos de
# la B, y al final las dos que contestan todos.
#
# El total general y el intralaboral van los dos porque contestan preguntas
# distintas: el general decide si el puesto entra en vigilancia --tiene baremo
# propio, no es el promedio de nada-- y el intralaboral dice cuánto de ese
# riesgo viene del trabajo, que es sobre lo que la universidad puede actuar.
RES_CABEZA <- c("tot_ie_a", "tot_intra_a",
                "tot_ie_b", "tot_intra_b",
                "tot_extra", "tot_estres")

# La forma de las claves de cabecera, que son las únicas que siguen partidas.
RES_FORMA_DE <- c(tot_ie_a  = "A", tot_intra_a = "A",
                  tot_ie_b  = "B", tot_intra_b = "B",
                  tot_extra = NA_character_, tot_estres = NA_character_)

# Todo lo que el módulo calcula: las medidas de los tres cuestionarios más las
# claves por forma de las tarjetas.
RES_CLAVES <- unique(c(RES_MEDIDAS, RES_CABEZA))

RES_ROTULOS <- stats::setNames(vapply(RES_CLAVES, res_rotulo_de, ""), RES_CLAVES)

res_rotulo_forma <- function(clave) {
  f <- unname(RES_FORMA_DE[clave])
  r <- unname(RES_ROTULOS[clave])
  ifelse(is.na(f), r, sprintf("%s · forma %s", r, f))
}

# El rótulo con la vista pegada, para donde la fila viaja SOLA y el cuestionario
# ya no está encima para decirla: los focos, el detalle y el Excel.
res_rotulo_vista <- function(clave, vista = RES_VISTA_DEF) {
  r <- unname(RES_ROTULOS[clave])
  if (identical(vista, "T")) r else sprintf("%s · forma %s", r, vista)
}

# Las dimensiones, que son las únicas candidatas a foco: un total o un dominio
# agrega a las dimensiones que ya compiten, y dejarlo entrar contaría lo mismo
# dos veces.
RES_DIMENSIONES <- RES_MEDIDAS[vapply(RES_MEDIDAS, res_nivel_de, "") == "dimension"]


# --- cruces disponibles -------------------------------------------------------
# El orden es el de la lista desplegable: primero lo laboral (que es sobre lo
# que la universidad puede actuar) y después lo sociodemográfico.

# Dedicación y modalidad de trabajo estuvieron aquí y se quitaron: el marco
# real es un export de nómina que no trae esas columnas, así que el corte solo
# ofrecía un grupo "Sin dato" con toda la población. La consulta de res_datos()
# las sigue leyendo; si algún día el marco las trae, basta con devolverlas a
# esta lista. La sede también se quitó, pero del todo: ya no se usa.
RES_CRUCES <- c(
  # El rotulo es la palabra que usa la nomina, DESCRIPCION_UNIDAD, y nada mas:
  # sus 40 valores son facultades, escuelas, institutos, vicerrectorias y
  # direcciones, y los dos cortes son una jerarquia --unidad > dependencia--,
  # no una clasificacion: la Facultad de Medicina agrupa 18 dependencias y 485
  # personas. Se llamo "Tipo de dependencia" (hacia buscar un tipo que no
  # existe) y luego "Unidad academica o administrativa", que describia el
  # contenido con palabras que tampoco estan en el archivo. Lo que se ve es el
  # nombre de la columna de origen; lo demas se explica aqui.
  tipo_dependencia = "Unidad",
  dependencia      = "Dependencia",
  tipo_vinculacion = "Tipo de vinculación",
  nivel_empleo     = "Nivel del empleo (grupo de nómina)",
  tipo_salario     = "Tipo de salario",
  antiguedad       = "Antigüedad en la universidad",
  tiempo_cargo     = "Tiempo en el cargo",
  jornada          = "Jornada diaria",
  forma            = "Forma del cuestionario",
  sexo             = "Sexo",
  edad             = "Grupo de edad",
  estado_civil     = "Estado civil",
  estrato          = "Estrato",
  nivel_academico  = "Nivel académico",
  vivienda         = "Tipo de vivienda",
  dependientes     = "Personas a cargo")


# --- lectura ------------------------------------------------------------------

# TRUE si la tabla de respuestas ya trae las columnas de clasificación. Sin
# ellas el módulo no tiene nada que mostrar: las escribe conectar_bd.R, que es
# un paso aparte del cargue del marco.
res_hay_datos <- function() {
  n <- tryCatch(
    db_get("SELECT count(*) AS n
              FROM information_schema.columns
             WHERE table_schema = 'public'
               AND table_name   = 'respuestas_procesadas'
               AND column_name LIKE 'clas\\_%'")$n,
    error = function(e) 0)
  isTRUE(as.numeric(n) > 0)
}

# TRUE si public.respuestas_procesadas tiene esa columna.
res_hay_columna <- function(col) {
  n <- tryCatch(
    db_get("SELECT count(*) AS n
              FROM information_schema.columns
             WHERE table_schema = 'public'
               AND table_name   = 'respuestas_procesadas'
               AND column_name  = $1", params = list(col))$n,
    error = function(e) 0)
  isTRUE(as.numeric(n) > 0)
}

# Las etiquetas de la ficha de datos generales --sexo, estrato, nivel
# academico-- vivian aqui, copiadas de las del XLSForm. Se quitaron: las escribe
# conectar_bd.R al cargar, `respuestas` las guarda ya traducidas y res_datos()
# las lee de ahi. Dos copias de la misma lista acabaron diciendo cosas distintas
# y solo una comprobaba los codigos nuevos del formulario.

# El marco es un export de nómina y su columna GRUPO mezcla dos cosas en la
# misma lista: el nivel del empleo de los no docentes --que llega en versales--
# y el régimen salarial del profesorado. Aquí solo se arregla lo que se ve; el
# marco se queda como llegó.
#
# Qué es cada régimen lo dice el cruce con tipo_vinculacion, no una suposición:
# "Salario por Ptos" son profesores de carrera y ocasionales, y "Asigancion por
# categoria" --con la errata del archivo original-- son los de cátedra. Por eso
# la etiqueta los nombra como profesorado: puestos al lado de "Asistencial" o
# "Directivo", sin decir de quién son, no se entiende qué se está comparando.
RES_NIVEL_EMPLEO <- c(
  "Salario por Ptos"          = "Profesorado (salario por puntos)",
  "Asigancion por categoria"  = "Profesorado (asignación por categoría)",
  "DIRECTIVO"                 = "Directivo",
  "PROFESIONAL"               = "Profesional",
  "TECNICO"                   = "Técnico",
  "ASISTENCIAL"               = "Asistencial",
  "Trab. Oficial Calificado1" = "Trabajador oficial calificado 1",
  "Trab. Oficial Calificado2" = "Trabajador oficial calificado 2",
  "Trab. Oficial Calificado3" = "Trabajador oficial calificado 3",
  "Trab. Oficial Musico"      = "Trabajador oficial músico")

RES_SIN_DATO <- "Sin dato"

# Un solo viaje a la base por sesión: 2.251 filas por 35 columnas es un pañuelo,
# y tenerlas en memoria evita una consulta por cada cambio de cruce. Todo el
# resto del archivo agrega sobre este data.frame.
res_datos <- function() {
  # Una columna por medida y por forma. Quien contestó la B tiene NA en todas
  # las columnas de la A y al revés, que es justo lo que hace que res_reparto()
  # cuente cada bloque sobre su propia población sin pedirle permiso a nadie.
  por_forma <- function(f) c(
    sprintf("r.clas_total_intraextra_%s AS tot_ie_%s", f, f),
    sprintf("r.clas_total_intra_%s      AS tot_intra_%s", f, f),
    sprintf("r.clas_dom_%s_%s AS dom_%s_%s", f, names(RES_DOMS), names(RES_DOMS), f),
    sprintf("r.clas_dim_%s_%s AS dim_%s_%s", f, res_dims_de(toupper(f)),
            res_dims_de(toupper(f)), f))

  sel <- c(
    por_forma("a"),
    por_forma("b"),
    sprintf("r.clas_dim_ex_%s AS ex_%s", names(RES_EXTRA), names(RES_EXTRA)),
    "r.clas_total_extra  AS tot_extra",
    "r.clas_total_estres AS tot_estres")

  # estado_civil volvio al formulario el 2026-10-20. Una `respuestas` escrita
  # antes de eso no tiene la columna: la pestana abre igual, con todo el mundo
  # en "Sin dato", hasta la proxima vez que se corra conectar_bd.R.
  ecivil <- if (res_hay_columna("estado_civil")) "r.estado_civil" else "NULL::text"

  d <- db_get(sprintf("
    SELECT m.dependencia,
           m.tipo_dependencia,
           m.tipo_vinculacion,
           m.nivel_empleo,
           m.dedicacion,
           m.modalidad_trabajo AS modalidad,
           r.forma_cuestionario AS forma,
           -- TODAS las sociodemograficas se leen de `respuestas`, donde
           -- conectar_bd.R ya las dejo etiquetadas: aqui no se traduce ningun
           -- codigo. Las tres primeras se leian del crudo de ODK y se volvian a
           -- traducir con tablas propias de este archivo, y las dos versiones
           -- habian divergido: Tecnico / tecnologico contra Tecnico o
           -- tecnologico, y el codigo 9 del estrato --que es No se, una
           -- respuesta-- se contaba aqui como Sin dato, que es su ausencia.
           -- Ademas solo conectar_bd.R comprueba que no llegue un codigo nuevo
           -- del formulario sin etiqueta.
           -- (Sin comillas dobles: este comentario va DENTRO de la cadena de R
           -- que lleva la consulta, y una comilla la cierra a media frase.)
           r.sexo,
           r.estrato,
           r.nivel_academico,
           -- La edad sale de `respuestas`, no del crudo de ODK. Antes era
           -- age(o.nacimiento), que tiene dos problemas: mide la edad de HOY
           -- --el mismo informe da otro numero el mes que viene, porque la
           -- gente cumple anos-- y obliga a unir respuestas_odk solo para eso.
           -- conectar_bd.R ya guarda edad_anios, que es la edad AL RESPONDER,
           -- que es la que corresponde a una encuesta. De paso desaparece la
           -- unica dependencia que tenia este modulo del tipo de dato de
           -- respuestas_odk: si esa columna quedo como texto en alguna
           -- instalacion --CREATE TABLE IF NOT EXISTS no corrige tipos-- la
           -- consulta reventaba con un function age(character varying) does
           -- not exist y la pestana de resultados no abria.
           r.edad_anios,
           %s AS estado_civil,
           r.vivienda,
           r.dependientes,
           r.tipo_salario,
           r.anos_empresa,
           r.anos_cargo,
           r.horas_diarias,
           %s
      -- Un envio por persona, el mas reciente, igual que seg_sql_efectiva():
      -- quien mando el cuestionario dos veces es una sola encuesta efectiva.
      FROM (SELECT DISTINCT ON (id_anonimizado) *
              -- FROM seguimiento.respuestas
              FROM public.respuestas_procesadas
             ORDER BY id_anonimizado, submission_date DESC NULLS LAST, clave DESC) r
      JOIN seguimiento.marco_completo m         ON r.id_anonimizado = m.id_anonimizado
     WHERE m.estado_vinculacion = 'Activo'
       AND %s IS TRUE", ecivil, paste(sel, collapse = ",\n           "),
    seg_sql_acepta("r")))

  if (nrow(d) == 0) return(d)

  # --- el intralaboral, fundido -----------------------------------------------
  # A y B son instrumentos distintos --19 dimensiones contra 16, items propios y
  # baremos propios-- y por eso llegan en columnas separadas: quien contesto la
  # B tiene NA en todas las de la A y al reves. Aqui se funden en UNA columna
  # por medida, tomando de cada persona el nivel que le calculo SU baremo. Es
  # exactamente lo que conectar_bd.R ya hacia con extralaboral y estres, que se
  # califican dos veces y se unen en una sola columna.
  #
  # Lo que se funde es el NIVEL, no el puntaje: para eso existe el baremo de
  # cada forma, y todo este archivo cuenta niveles. Las columnas por forma se
  # quedan --las usan las tarjetas de cabecera, que siguen dando una cifra por
  # baremo-- y la forma de cada persona viaja en `forma`, asi que elegir vista
  # es filtrar FILAS y no cambiar de tabla (ver res_vista()).
  #
  # Las tres dimensiones exclusivas de la forma A no tienen columna _b: su
  # version fundida es la de la A y su n es el de los A, mas chico que el del
  # cuestionario. La pantalla las marca en vez de dejar que parezca un error.
  for (k in res_claves_intra()) {
    va <- if (paste0(k, "_a") %in% names(d)) d[[paste0(k, "_a")]] else NA_character_
    vb <- if (paste0(k, "_b") %in% names(d)) d[[paste0(k, "_b")]] else NA_character_
    d[[k]] <- ifelse(is.na(va), vb, va)
  }

  # Sexo, estrato y nivel academico ya no se tocan: llegan etiquetados de la
  # consulta. El bucle del final convierte en "Sin dato" lo que venga vacio.
  d$nivel_empleo <- res_etiqueta_libre(d$nivel_empleo, RES_NIVEL_EMPLEO)

  # Cortes de edad decenales, que es como se leen en salud ocupacional. El
  # primero y el último son abiertos porque tienen pocas personas.
  d$edad <- as.character(cut(d$edad_anios, c(-Inf, 29, 39, 49, 59, Inf),
                             labels = c("Hasta 29", "30 a 39", "40 a 49",
                                        "50 a 59", "60 o más")))
  d$edad[is.na(d$edad)] <- RES_SIN_DATO

  # La antigüedad y la jornada llegan en números: 35 años distintos serían 35
  # grupos de una persona cada uno, que no se puede leer ni comparar. Se agrupan
  # en tramos, igual que la edad. Las personas a cargo no: van de 0 a 4 y cada
  # valor es un grupo con sentido propio.
  d$antiguedad <- as.character(cut(d$anos_empresa, c(-Inf, 1, 5, 10, 20, Inf),
                                   labels = c("Menos de 2 años", "2 a 5", "6 a 10",
                                              "11 a 20", "Más de 20")))
  d$antiguedad[is.na(d$antiguedad)] <- RES_SIN_DATO

  d$tiempo_cargo <- as.character(cut(d$anos_cargo, c(-Inf, 1, 5, 10, Inf),
                                     labels = c("Menos de 2 años", "2 a 5",
                                                "6 a 10", "Más de 10")))
  d$tiempo_cargo[is.na(d$tiempo_cargo)] <- RES_SIN_DATO

  d$jornada <- as.character(cut(d$horas_diarias, c(-Inf, 4, 8, Inf),
                                labels = c("Hasta 4 horas", "5 a 8 horas",
                                           "Más de 8 horas")))
  d$jornada[is.na(d$jornada)] <- RES_SIN_DATO

  d$dependientes <- ifelse(is.na(d$dependientes), RES_SIN_DATO,
                    ifelse(d$dependientes == 0, "Ninguna",
                    ifelse(d$dependientes == 1, "1 persona",
                           paste(d$dependientes, "personas"))))

  for (cv in names(RES_CRUCES)) {
    d[[cv]][is.na(d[[cv]]) | !nzchar(trimws(d[[cv]]))] <- RES_SIN_DATO
  }

  d
}

# Traduce lo que esté en el mapa y deja tal cual lo que no, en vez de hacerlo
# caer en "Sin dato". Es para valores que YA llegan en texto: la nómina puede
# traer mañana un grupo nuevo, y hacerlo desaparecer en un cajón de sastre es
# peor que mostrarlo sin arreglar: así se ve que existe y se añade al mapa.
res_etiqueta_libre <- function(x, mapa) {
  v <- trimws(as.character(x))
  i <- match(v, names(mapa))
  ifelse(is.na(i), v, unname(mapa)[i])
}


# --- agregación ---------------------------------------------------------------

# Reparto de una medida en los cinco niveles, para un vector ya filtrado.
# Devuelve NULL cuando el grupo no llega al mínimo: quien llama decide si lo
# pinta como "reservado" o lo esconde, pero nunca recibe el dato.
res_reparto <- function(x) {
  v <- factor(x, levels = RES_NIVELES)
  n <- sum(!is.na(v))
  if (n < RES_MIN_N) return(NULL)
  cn <- as.integer(table(v))
  list(n = n, conteo = cn, pct = 100 * cn / n,
       alto = round(100 * sum(cn[RES_ALTOS]) / n, 1))
}

# Una fila por categoría del cruce, para una medida. Ordenadas de mayor a menor
# porcentaje en riesgo alto: el grupo que primero hay que mirar queda arriba.
# Las categorías reservadas van al final, que es donde estorban menos.
# Mayor porcentaje en riesgo alto primero; los reservados al final, que es donde
# estorban menos. El nombre desempata, para que el orden sea estable.
res_ordenar <- function(xs) {
  con <- Filter(function(x) !is.null(x$rep), xs)
  sin <- Filter(function(x)  is.null(x$rep), xs)
  con <- con[order(-vapply(con, function(x) x$rep$alto, 0),
                    vapply(con, function(x) x$categoria, ""))]
  sin <- sin[order(vapply(sin, function(x) x$categoria, ""))]
  c(con, sin)
}

# Los niveles de un cruce, tal como los ve la pantalla: ordenados y sin vacíos.
# Lo comparten res_por_grupo() y el contador de grupos del módulo porque tienen
# que contar lo MISMO. Si uno incluyera los vacíos y el otro no, un cruce con un
# solo nivel real más un hueco encendería la bandera del mapa --que pide dos
# grupos-- para dibujar una sola columna. Hoy no pasa, porque res_datos() cambia
# todo vacío por "Sin dato" antes de salir; esto es para que siga sin pasar.
res_categorias <- function(d, cruce) {
  v <- as.character(d[[cruce]])
  sort(unique(v[!is.na(v) & nzchar(trimws(v))]))
}

# `cats` deja fijar la lista de grupos desde fuera. Hace falta desde que cada
# cuestionario tiene su vista: los grupos se cuentan sobre la poblacion de la
# vista --los de la forma B, si es la que se esta mirando-- pero la LISTA es la
# del segmento entero, para que un grupo que no tiene a nadie de esa forma
# aparezca reservado en vez de desaparecer. Desaparecer haria creer que el
# grupo no existe, que es el mismo error que esconder una medida reservada.
res_por_grupo <- function(d, cruce, medida, cats = NULL) {
  if (is.null(d) || nrow(d) == 0) return(list())
  if (is.null(cats)) cats <- res_categorias(d, cruce)

  res_ordenar(lapply(cats, function(ct) {
    sub <- d[!is.na(d[[cruce]]) & d[[cruce]] == ct, , drop = FALSE]
    list(categoria = ct, n_grupo = nrow(sub), rep = res_reparto(sub[[medida]]))
  }))
}

# Matriz medida x categoría con el porcentaje en riesgo alto o muy alto. Es lo
# que alimenta el mapa de calor. NA donde el grupo queda reservado.
res_matriz <- function(d, cruce, categorias, medidas = RES_MEDIDAS) {
  m <- matrix(NA_real_, nrow = length(medidas), ncol = length(categorias),
              dimnames = list(medidas, categorias))
  if (is.null(d) || nrow(d) == 0) return(m)

  for (j in seq_along(categorias)) {
    sub <- d[d[[cruce]] == categorias[j], , drop = FALSE]
    for (i in seq_along(medidas)) {
      r <- res_reparto(sub[[medidas[i]]])
      if (!is.null(r)) m[i, j] <- r$alto
    }
  }
  m
}

# El porcentaje en riesgo alto del conjunto, medida por medida: la referencia
# contra la que se lee cada grupo.
res_referencia <- function(d, medidas = RES_MEDIDAS) {
  vapply(medidas, function(k) {
    r <- res_reparto(d[[k]])
    if (is.null(r)) NA_real_ else r$alto
  }, 0)
}


# Separador de las partes del título del segmento.
RES_SEP_COMBO <- " · "


# --- segmento -----------------------------------------------------------------
# Un segmento es la población que queda después de filtrar por cualquiera de
# las variables de RES_CRUCES: "la Facultad de Ciencias Económicas", "las
# mujeres de 30 a 39 de esa facultad". Filtrar RESTRINGE la población;
# desagregar la SUBDIVIDE en grupos comparables. Son cosas distintas y
# conviven: se filtra hasta el segmento que interesa y, si hace falta, se abre
# ese segmento en grupos.
#
# `filtros` es una lista con nombre: cada elemento es un vector de valores
# admitidos de esa variable. Vacío o NULL = esa variable no filtra.
res_filtrar <- function(d, filtros) {
  if (is.null(d) || nrow(d) == 0 || !length(filtros)) return(d)
  sel <- rep(TRUE, nrow(d))
  for (cv in names(filtros)) {
    v <- filtros[[cv]]
    if (is.null(v) || !length(v) || !cv %in% names(d)) next
    sel <- sel & as.character(d[[cv]]) %in% v
  }
  d[sel, , drop = FALSE]
}

# Deja solo los filtros que de verdad restringen algo, y descarta valores que
# ya no existen en los datos (al cambiar de fuente, o entre recargas). Lo que
# sobrevive aquí es lo que se muestra en el título: así el título no puede
# prometer un filtro que el cálculo no aplicó.
res_filtros_vivos <- function(d, filtros) {
  out <- list()
  for (cv in names(RES_CRUCES)) {
    v <- filtros[[cv]]
    if (is.null(v) || !length(v) || !cv %in% names(d)) next
    v <- intersect(as.character(v), unique(as.character(d[[cv]])))
    if (length(v)) out[[cv]] <- sort(v)
  }
  out
}

# Título que describe el segmento. Se arma con los valores elegidos y no con
# los nombres de las variables ("Facultad de Ciencias Económicas · Femenino",
# no "Dependencia: ... / Sexo: ..."): quien lee ya sabe que "Femenino" es un
# sexo, y el nombre de la variable solo gasta renglón. Cuando una variable
# tiene demasiados valores marcados se resume con su rótulo, que ahí sí hace
# falta para que "8" signifique algo.
RES_MAX_EN_TITULO <- 3L

res_titulo_segmento <- function(filtros_vivos) {
  if (!length(filtros_vivos)) return("Toda la universidad")

  partes <- vapply(names(filtros_vivos), function(cv) {
    v <- filtros_vivos[[cv]]
    if (length(v) <= RES_MAX_EN_TITULO) paste(v, collapse = ", ")
    else sprintf("%s valores de %s", length(v), tolower(RES_CRUCES[[cv]]))
  }, "")

  paste(partes, collapse = RES_SEP_COMBO)
}


# =============================================================================
# COMPARACIÓN CONTRA LA UNIVERSIDAD
# =============================================================================
# Nada de aquí inventa un indicador nuevo: todo se apoya en res_reparto() y
# res_referencia(), que son las que ya calculaban el porcentaje en riesgo alto o
# muy alto. Lo que se agrega es la RESTA, que hasta ahora se hacía suelta en
# cada vista y ahora se calcula una vez y en un solo sitio.
#
# La diferencia es DESCRIPTIVA: la resta de dos porcentajes observados. No hay
# prueba de hipótesis detrás, así que en ninguna parte se dice "significativa".

# Distancia mínima, en puntos porcentuales, para que una diferencia entre a las
# reglas que la pantalla DECLARA: qué dimensiones son focos de atención
# (res_focos()) y dónde cortan las bandas del mapa de calor (res_banda()). Es
# una convención de lectura para no llamar "foco" a un decimal, no un umbral
# estadístico, y por eso se imprime siempre al lado de la regla que gobierna.
#
# Ya NO decide ningún color: la señal de por encima / por debajo es de dos
# estados y se parte en cero (ver res_senal()). El nombre se queda por lo que
# fue, pero lo que hace hoy es marcar el mínimo de una regla visible.
RES_UMBRAL_SIMILAR <- 2

# DOS estados y no tres: o el segmento está por encima de su referencia, o está
# por debajo. La banda gris de "similar" --las diferencias dentro de ±2 pp-- se
# quitó: en una escala donde MÁS por ciento es MÁS riesgo, pintar de gris una
# diferencia de 1,9 pp la presenta como si no existiera, y lo que hace es
# esconderla justo en el tramo donde todavía se puede actuar.
#
# El umbral RES_UMBRAL_SIMILAR sigue vivo, pero solo donde declara una REGLA que
# se imprime en pantalla y se puede auditar: los focos de atención
# (res_focos()) y las bandas del mapa de calor (res_banda()). Ahí el corte es
# una decisión explícita; aquí era un color que callaba.
#
# El cero exacto se cuenta del lado verde --no está por encima-- pero se rotula
# "Igual", que es lo que es. Llamarlo "Por debajo" sería falso, y darle un
# tercer color devolvería el gris por la puerta de atrás.
res_senal <- function(delta) {
  if (length(delta) != 1 || is.na(delta)) {
    return(list(cls = "nula", txt = "Sin dato", sig = "–"))
  }
  if (delta > 0) {
    list(cls = "arriba", txt = "Por encima", sig = "▲")
  } else if (delta < 0) {
    list(cls = "abajo",  txt = "Por debajo", sig = "▼")
  } else {
    list(cls = "abajo",  txt = "Igual",      sig = "=")
  }
}

# Una fila por medida: el porcentaje en riesgo alto o muy alto del segmento, el
# de la universidad y su diferencia. Es la tabla de la que salen el ranking, los
# focos, la tabla analítica y el detalle de una dimensión: los cuatro leen el
# mismo objeto, así que no pueden discrepar entre sí.
#
# `reservado` marca las medidas que no llegan al mínimo. La fila se conserva
# --esconderla haría creer que la medida no existe-- pero sin ningún porcentaje.
res_ranking <- function(seg, ref, medidas = RES_MEDIDAS) {
  filas <- lapply(medidas, function(k) {
    rp <- res_reparto(seg[[k]])
    n  <- sum(!is.na(seg[[k]]))
    u  <- unname(ref[k])
    data.frame(
      clave     = k,
      rotulo    = unname(RES_ROTULOS[[k]]),
      bloque_id = unname(RES_BLOQUE_DE[[k]]),
      # La forma ya no es un atributo de la medida --la columna esta fundida--
      # sino de la vista, que es del cuestionario entero. Lo unico que sigue
      # siendo de la fila es si esa dimension SOLO existe en la forma A.
      solo_a    = k %in% RES_SOLO_A_CLAVES,
      n         = n,
      pct       = if (is.null(rp)) NA_real_ else rp$alto,
      univ      = u,
      delta     = if (is.null(rp) || is.na(u)) NA_real_ else round(rp$alto - u, 1),
      reservado = is.null(rp),
      stringsAsFactors = FALSE)
  })
  do.call(rbind, filas)
}

# El reparto completo de una medida, para el detalle. Se busca por clave sobre
# el mismo segmento, así que el número que muestra el detalle es por
# construcción el mismo que muestra su fila del ranking.
res_detalle_medida <- function(seg, ref, clave, vista = RES_VISTA_DEF) {
  if (!clave %in% names(seg)) return(NULL)
  rp <- res_reparto(seg[[clave]])
  u  <- unname(ref[clave])
  list(
    clave  = clave,
    # El modal se abre solo, fuera de su cuestionario, asi que el rotulo lleva
    # la vista: sin ella no hay forma de saber de que poblacion es la cifra.
    rotulo = res_rotulo_vista(clave, vista),
    vista  = vista,
    solo_a = clave %in% RES_SOLO_A_CLAVES,
    n      = sum(!is.na(seg[[clave]])),
    rep    = rp,
    univ   = u,
    delta  = if (is.null(rp) || is.na(u)) NA_real_ else round(rp$alto - u, 1))
}

# Modos de ordenación y recorte del ranking. Con 30 medidas, obligar a recorrer
# las 30 para encontrar las tres que importan es trabajo que puede hacer la
# máquina. `dif_*` sólo tiene sentido comparando: sin comparación se cae a
# riesgo_alto, que es el orden equivalente más cercano.
RES_ORDENES <- c(
  "Estructura del instrumento"       = "estructura",
  "Mayores riesgos"                  = "riesgo_alto",
  "Menores riesgos"                  = "riesgo_bajo",
  "Mayores diferencias, por encima"  = "dif_alta",
  "Mayores diferencias, por debajo"  = "dif_baja",
  "Nombre de la medida"              = "nombre")

res_ordenar_ranking <- function(rk, modo = "estructura", comparar = TRUE) {
  if (is.null(rk) || !nrow(rk)) return(rk)
  if (!comparar && modo %in% c("dif_alta", "dif_baja")) modo <- "estructura"

  # El orden del INSTRUMENTO --el que trae RES_MEDIDAS: el total, y despues cada
  # dominio seguido de las dimensiones que lo componen-- es el mismo con el que
  # la tabla de "Datos detallados" arma su jerarquia, asi que las dos secciones
  # se recorren igual y una dimension esta siempre debajo de su dominio.
  #
  # Aqui las reservadas NO se mandan al final: en los demas ordenes van abajo
  # porque no tienen valor con el que ordenarse, pero en este el sitio de una
  # medida es su sitio en el cuestionario, y sacarla de ahi romperia justamente
  # la jerarquia que este orden existe para mostrar.
  if (identical(modo, "estructura")) {
    return(rk[order(match(rk$clave, RES_MEDIDAS)), , drop = FALSE])
  }

  orden <- switch(
    modo,
    riesgo_bajo = order(rk$reservado,  rk$pct,   rk$rotulo),
    dif_alta    = order(rk$reservado, -rk$delta, rk$rotulo),
    dif_baja    = order(rk$reservado,  rk$delta, rk$rotulo),
    nombre      = order(rk$reservado,  rk$rotulo),
                  order(rk$reservado, -rk$pct,   rk$rotulo))
  rk[orden, , drop = FALSE]
}

# Focos de atención: las medidas donde el segmento está más por encima del
# conjunto. La regla es explícita y se imprime en pantalla, porque un "top 3"
# sin regla visible es una afirmación que el lector no puede auditar.
#
# Se exige que la diferencia supere el umbral de "similar": si nada lo supera,
# no hay focos, y decirlo es más honesto que rellenar tres casillas.
# Los focos se buscan solo entre las DIMENSIONES, no entre los totales ni los
# dominios: un total es la suma de sus dimensiones, así que dejarlo competir con
# ellas contaría lo mismo dos veces y llenaría el podio de agregados en vez de
# señalar dónde mirar.
res_focos <- function(rk, n = 3, medidas = RES_DIMENSIONES) {
  if (is.null(rk) || !nrow(rk)) return(rk[0, , drop = FALSE])
  cand <- rk[rk$clave %in% medidas & !rk$reservado & !is.na(rk$delta) &
               rk$delta >= RES_UMBRAL_SIMILAR, , drop = FALSE]
  if (!nrow(cand)) return(cand)
  cand <- cand[order(-cand$delta, cand$rotulo), , drop = FALSE]
  utils::head(cand, n)
}


# =============================================================================
# GRUPOS (desagregación)
# =============================================================================

# Recorte de grupos para el mapa: los N con mayor porcentaje en riesgo alto.
# Sustituye al aviso de "demasiadas columnas", que dejaba al usuario sin salida.
# 0 = todos.
RES_TOPES_GRUPO <- c("20 grupos" = "20", "50 grupos" = "50", "Todos" = "0")

res_top_grupos <- function(nodos, tope = 0L) {
  tope <- suppressWarnings(as.integer(tope))
  if (is.na(tope) || tope <= 0 || length(nodos) <= tope) return(nodos)
  con <- Filter(function(x) !is.null(x$rep), nodos)
  con <- con[order(-vapply(con, function(x) x$rep$alto, 0))]
  utils::head(con, tope)
}


# =============================================================================
# ESTRUCTURA DEL INSTRUMENTO
# =============================================================================
# La Batería no es una lista plana de medidas: cada dimensión pertenece a un
# dominio, cada dominio a un cuestionario y --en el intralaboral-- cada
# cuestionario a una forma. Leer una dimensión sin ese contexto obliga a
# recordarlo de memoria, y poner una dimensión de la forma A junto a una de la B
# invita a restarlas, que es exactamente lo que no se puede hacer.
#
# Toda la estructura está declarada arriba, en RES_BLOQUES y RES_DOM_DIMS. Aquí
# solo se aplana en la tabla que consumen la tabla analítica y el CSV.

# Las medidas en orden de lectura, cada una con su nivel, su bloque y su forma.
res_estructura <- function() {
  do.call(rbind, lapply(RES_BLOQUES, function(b) data.frame(
    clave  = b$claves,
    nivel  = vapply(b$claves, res_nivel_de, ""),
    bloque = b$titulo,
    solo_a = b$claves %in% RES_SOLO_A_CLAVES,
    stringsAsFactors = FALSE, row.names = NULL)))
}

# Comprobación de que el catálogo no se contradiga: que toda dimensión cuelgue
# de un dominio y de uno solo, que las exclusivas de la forma A existan, y que
# ninguna clave se repita. Si alguna vez se agrega una dimensión y se olvida
# colgarla, esto lo dice en el arranque en vez de dejarla desaparecer sin ruido.
res_catalogo_coherente <- function() {
  colgadas <- unlist(RES_DOM_DIMS, use.names = FALSE)
  setequal(colgadas, names(RES_DIMS)) &&
    !anyDuplicated(colgadas) &&
    all(RES_SOLO_A %in% names(RES_DIMS)) &&
    !anyDuplicated(RES_MEDIDAS) &&
    setequal(res_estructura()$clave, RES_MEDIDAS)
}

# Se comprueba al cargar el archivo, no cuando alguien abra la pestaña: si el
# catálogo se contradice, la app se niega a arrancar en vez de servir una tabla
# a la que le falta una medida sin decir nada.
if (!res_catalogo_coherente()) {
  stop("El catálogo de medidas se contradice: hay dimensiones sin dominio, ",
       "colgadas dos veces, o claves repetidas.", call. = FALSE)
}


# =============================================================================
# FORMAS A / B
# =============================================================================
# La forma la determina el PUESTO --A para jefaturas, profesionales y técnicos;
# B para auxiliares y operarios-- y cada una tiene sus propios ítems y baremos.
#
# Ya no hace falta que el catálogo las separe en bloques distintos: el
# intralaboral llega fundido de res_datos() y la forma se elige como VISTA (ver
# res_vista()). Lo único que queda por saber es cuántos hay de cada una, para
# que cada cuestionario diga sobre cuántos cuestionarios está hablando y para
# poder decir que una forma no está en el segmento en vez de dibujarla vacía.

res_cuenta_formas <- function(x) {
  if (is.null(x) || !nrow(x)) return(c(A = 0L, B = 0L))
  v <- x$forma[!is.na(x$forma)]
  c(A = sum(v == "A"), B = sum(v == "B"))
}

# Cuántas encuestas efectivas tiene una vista. Es el n de la cabecera del
# cuestionario, y el que decide si se puede mostrar algo: por debajo de
# RES_MIN_N no se calcula nada, igual que con el segmento entero.
res_n_vista <- function(x, vista = RES_VISTA_DEF) {
  if (is.null(x) || !nrow(x)) return(0L)
  if (identical(vista, "T")) return(nrow(x))
  unname(res_cuenta_formas(x)[[vista]])
}


# =============================================================================
# RESUMEN DESCRIPTIVO
# =============================================================================
# Quien contesto la Bateria: su perfil sociodemografico y laboral, y si se
# parece a la poblacion que debia contestarla. Es contexto que se lee una vez
# --por eso la seccion nace plegada-- pero sin el, las cifras de riesgo de abajo
# se leen como si describieran a toda la universidad.
#
# La unidad es la misma que en el resto del archivo: la ENCUESTA EFECTIVA.
# Los bloques 2 y 3 se calculan sobre el segmento ya filtrado --el mismo
# data.frame que alimenta el ranking-- asi que no vuelven a la base y no pueden
# describir una poblacion distinta de la que se esta analizando.

# Las variables del descriptivo, en dos bloques y en orden de lectura. Los
# rotulos se toman de RES_CRUCES donde existan --son las mismas variables, y dos
# listas de nombres acabarian divergiendo-- y solo se escriben aqui los de las
# que no son cruce.
#
# `tipo`: "cat" se resume con frecuencias; "num" con n, media, mediana y rango.
# Las numericas van ADEMAS de su version agrupada (edad, antiguedad,
# tiempo_cargo) y no en su lugar: el grupo dice como se reparte y el promedio
# dice por donde anda, y son dos lecturas distintas de la misma columna.
RES_DESC_BLOQUES <- list(
  list(
    id     = "socio",
    titulo = "Perfil sociodemográfico",
    vars   = list(
      list(v = "sexo",            tipo = "cat"),
      list(v = "edad",            tipo = "cat"),
      list(v = "edad_anios",      tipo = "num", rotulo = "Edad (años)"),
      list(v = "estado_civil",    tipo = "cat"),
      list(v = "nivel_academico", tipo = "cat"),
      list(v = "estrato",         tipo = "cat"),
      list(v = "vivienda",        tipo = "cat"),
      # `dependientes` llega YA etiquetada de res_datos() --"Ninguna",
      # "1 persona", "2 personas"...-- asi que es categorica: pedirle una media
      # daba n = 0, porque as.numeric() no puede con esas etiquetas.
      list(v = "dependientes",    tipo = "cat"))),
  list(
    id     = "laboral",
    titulo = "Perfil laboral",
    vars   = list(
      list(v = "tipo_salario",  tipo = "cat"),
      list(v = "antiguedad",    tipo = "cat"),
      list(v = "anos_empresa",  tipo = "num", rotulo = "Años en la universidad"),
      list(v = "tiempo_cargo",  tipo = "cat"),
      list(v = "anos_cargo",    tipo = "num", rotulo = "Años en el cargo"),
      list(v = "jornada",       tipo = "cat"),
      list(v = "horas_diarias", tipo = "num", rotulo = "Horas diarias"))))

res_desc_rotulo <- function(x) {
  if (!is.null(x$rotulo)) return(x$rotulo)
  r <- unname(RES_CRUCES[x$v])
  if (is.na(r)) x$v else r
}

# Frecuencias de una categorica, de mayor a menor y con "Sin dato" siempre al
# final: es la ausencia del dato, no una categoria mas, y ordenarla por tamano
# la mete en medio de la lista como si compitiera con las demas.
res_desc_frec <- function(v) {
  v <- as.character(v)
  v[is.na(v) | !nzchar(v)] <- RES_SIN_DATO
  t <- sort(table(v), decreasing = TRUE)
  x <- data.frame(categoria = names(t), n = as.integer(t),
                  stringsAsFactors = FALSE)
  x <- rbind(x[x$categoria != RES_SIN_DATO, , drop = FALSE],
             x[x$categoria == RES_SIN_DATO, , drop = FALSE])
  x$pct <- if (sum(x$n) > 0) round(100 * x$n / sum(x$n), 1) else 0
  rownames(x) <- NULL
  x
}

# Resumen de una numerica. Se descartan los NA y se dice sobre cuantos se
# calculo: un promedio sobre 12 de 1.499 no es el promedio del segmento, y sin
# la n no hay forma de saberlo.
res_desc_num <- function(v) {
  v <- suppressWarnings(as.numeric(v))
  v <- v[!is.na(v)]
  if (!length(v)) {
    return(list(n = 0L, media = NA_real_, mediana = NA_real_,
                min = NA_real_, max = NA_real_))
  }
  list(n = length(v), media = round(mean(v), 1),
       mediana = round(stats::median(v), 1), min = min(v), max = max(v))
}

# Bloques 2 y 3: una lista por bloque, y dentro una entrada por variable con su
# rotulo, su tipo y su resumen. La UI solo pinta; las decisiones de que entra y
# como se resume estan aqui.
res_descriptivo <- function(seg, bloques = RES_DESC_BLOQUES) {
  lapply(bloques, function(b) {
    vs <- Filter(Negate(is.null), lapply(b$vars, function(x) {
      if (is.null(seg) || !x$v %in% names(seg)) return(NULL)
      list(v      = x$v,
           rotulo = res_desc_rotulo(x),
           tipo   = x$tipo,
           res    = if (identical(x$tipo, "num")) res_desc_num(seg[[x$v]])
                    else res_desc_frec(seg[[x$v]]))
    }))
    list(id = b$id, titulo = b$titulo, vars = vs)
  })
}


# --- cruce de dos variables ----------------------------------------------------
# Tabla de contingencia entre dos categoricas del descriptivo, elegidas por
# quien mira. Solo entran las categoricas: las numericas ya tienen su version
# agrupada en la lista (edad, antiguedad, tiempo en el cargo, jornada), que es
# la que se puede cruzar.

# Las categoricas del descriptivo, agrupadas por bloque, para el selector.
res_desc_opciones_cruce <- function(bloques = RES_DESC_BLOQUES) {
  op <- lapply(bloques, function(b) {
    vs <- Filter(function(x) identical(x$tipo, "cat"), b$vars)
    stats::setNames(vapply(vs, function(x) x$v, ""),
                    vapply(vs, res_desc_rotulo, ""))
  })
  stats::setNames(op, vapply(bloques, function(b) b$titulo, ""))
}

res_desc_rotulo_de <- function(v) {
  x <- Filter(function(x) identical(x$v, v),
              unlist(lapply(RES_DESC_BLOQUES, function(b) b$vars), recursive = FALSE))
  if (length(x)) res_desc_rotulo(x[[1]]) else v
}

# Las variables con orden propio. En una columna suelta da igual ordenar por
# tamano, pero en una tabla cruzada "Hasta 29" entre "40 a 49" y "60 o mas" no
# deja leer la tendencia. Son las mismas etiquetas que escribe res_datos(); un
# valor que no este aqui no se pierde, va despues de los conocidos.
RES_DESC_ORDEN <- list(
  edad         = c("Hasta 29", "30 a 39", "40 a 49", "50 a 59", "60 o más"),
  antiguedad   = c("Menos de 2 años", "2 a 5", "6 a 10", "11 a 20", "Más de 20"),
  tiempo_cargo = c("Menos de 2 años", "2 a 5", "6 a 10", "Más de 10"),
  jornada      = c("Hasta 4 horas", "5 a 8 horas", "Más de 8 horas"),
  estrato      = paste("Estrato", 1:6),
  dependientes = c("Ninguna", "1 persona", paste(2:20, "personas")))

# Las categorias de una variable en el orden de la tabla: el propio si lo tiene
# y si no de mayor a menor, como en las barras sueltas. "Sin dato" siempre al
# final, por la misma razon que en res_desc_frec().
res_desc_niveles <- function(x, v) {
  x <- unique(x)
  sin <- RES_SIN_DATO %in% x
  x <- setdiff(x, RES_SIN_DATO)
  ord <- RES_DESC_ORDEN[[v]]
  x <- if (!is.null(ord)) c(intersect(ord, x), sort(setdiff(x, ord)))
       else res_desc_frec(x)$categoria
  if (sin) c(x, RES_SIN_DATO) else x
}

# Conteos del cruce, con los margenes dentro de la matriz: la ultima fila y la
# ultima columna son los totales. Van dentro y no aparte porque los porcentajes
# de los margenes se calculan con la misma regla que los de las celdas (ver
# res_desc_cruce_pct()).
res_desc_cruce <- function(seg, fila, col) {
  if (is.null(seg) || !all(c(fila, col) %in% names(seg))) return(NULL)
  limpio <- function(v) {
    v <- as.character(v)
    v[is.na(v) | !nzchar(trimws(v))] <- RES_SIN_DATO
    v
  }
  f <- limpio(seg[[fila]])
  k <- limpio(seg[[col]])
  tb <- table(factor(f, levels = res_desc_niveles(f, fila)),
              factor(k, levels = res_desc_niveles(k, col)))
  n <- matrix(as.integer(tb), nrow = nrow(tb), dimnames = dimnames(tb))
  n <- cbind(n, Total = rowSums(n))
  n <- rbind(n, Total = colSums(n))
  list(fila = fila, col = col,
       rot_fila = res_desc_rotulo_de(fila), rot_col = res_desc_rotulo_de(col),
       n = n)
}

RES_DESC_PCT <- c("% de la fila" = "fila", "% de la columna" = "columna",
                  "% del total" = "total")

# Porcentajes de la matriz con margenes. La base de cada celda es su total de
# fila, de columna o el gran total, y la misma regla da los margenes: con "% de
# la fila" la fila Total es el reparto de la variable de columnas en todo el
# segmento, que es contra lo que se lee cada fila.
res_desc_cruce_pct <- function(n, modo = "fila") {
  base <- switch(modo,
    fila    = matrix(n[, ncol(n)], nrow(n), ncol(n)),
    columna = matrix(n[nrow(n), ], nrow(n), ncol(n), byrow = TRUE),
    matrix(n[nrow(n), ncol(n)], nrow(n), ncol(n)))
  p <- ifelse(base > 0, round(100 * n / base, 1), NA_real_)
  dimnames(p) <- dimnames(n)
  p
}

# =============================================================================
# 0. UTILIDADES GENERALES
# =============================================================================

`%||%` <- function(x, y) if (is.null(x)) y else x

# Normaliza texto a minusculas sin tildes para comparaciones robustas.
to_key <- function(x) {
  tolower(stringi::stri_trans_general(as.character(x), "Latin-ASCII"))
}

# Caja de alerta reutilizable (ingreso, cambio de clave, avisos de modulo).
alerta <- function(texto, tipo = "danger") {
  if (is.null(texto)) return(NULL)
  shiny::div(class = paste0("alert alert-", tipo, " auth-alerta"),
             role = "alert", texto)
}

# Todo lo que se baja de la app va en Excel: se abre de un clic, sin el
# asistente de importacion ni la pelea del separador decimal que traia el CSV.
# Los vacios se escriben vacios, no como NA.
#
# writexl no necesita Java ni escribe nada en disco fuera de `archivo`, que es
# el que Shiny entrega al navegador.
#
# `x` es una tabla, que va en la hoja `hoja`, o una lista con nombre de tablas,
# una hoja por cada una y en ese orden.
escribir_excel <- function(x, archivo, hoja = "Datos") {
  if (!requireNamespace("writexl", quietly = TRUE)) {
    stop("Falta el paquete writexl para bajar el archivo en Excel.", call. = FALSE)
  }
  hojas <- if (is.data.frame(x)) stats::setNames(list(x), hoja) else x
  hojas <- lapply(hojas, function(h) {
    h <- as.data.frame(h, stringsAsFactors = FALSE)
    for (v in names(h)) if (is.character(h[[v]])) h[[v]][is.na(h[[v]])] <- ""
    h
  })
  writexl::write_xlsx(hojas, archivo)
  invisible(archivo)
}

# Estado de avance de una dependencia. Los umbrales viven aqui y en ningun otro
# sitio, y el estado siempre viaja con texto y simbolo: el color por si solo no
# es una senal accesible (daltopia rojo-verde, monocromo, impresion).
#
# Los dos cortes son constantes con nombre para que quien necesite UNO DE CADA
# estado --los faroles del semaforo-- pida estado_avance(AVANCE_CORTE_BIEN) en
# vez de inventarse un 100 o un 75 que caigan dentro. Con valores de muestra,
# subir el corte medio por encima de ese 75 dejaba dos faroles rojos y ninguno
# amarillo, que es justo lo que este comentario dice que no puede pasar.
AVANCE_CORTE_BIEN  <- 90
AVANCE_CORTE_MEDIO <- 60

estado_avance <- function(avance) {
  if (length(avance) != 1 || is.na(avance)) {
    list(cls = "nulo",  txt = "Sin dato", sig = "\u2013")
  } else if (avance >= AVANCE_CORTE_BIEN) {
    list(cls = "bien",  txt = "Al d\u00eda",  sig = "\u2713")
  } else if (avance >= AVANCE_CORTE_MEDIO) {
    list(cls = "medio", txt = "En curso", sig = "\u25d0")
  } else {
    list(cls = "bajo",  txt = "Cr\u00edtico",  sig = "\u25cf")
  }
}

# Etiqueta de estado. El simbolo va oculto al lector de pantalla: aporta a la
# vista, pero leido en voz alta ("circulo negro") solo estorba.
chip_estado <- function(e) {
  shiny::span(
    class = paste("chip", e$cls),
    shiny::span(`aria-hidden` = "true", e$sig),
    e$txt
  )
}

# --- semaforo continuo -------------------------------------------------------
# La escala de color del avance: rojo -> amarillo -> verde, con la transicion a
# la vista, para que una dependencia que sube del 62% al 78% se vea subir y no
# se quede del mismo color hasta cruzar un umbral.
#
# Las anclas estan atadas a los mismos cortes de estado_avance(): amarillo justo
# en el 60 (donde empieza "En curso") y verde institucional en el 100. Por debajo
# del 45 el rojo se mantiene plano, para que lo critico se vea critico y no
# naranja. Entre el 90 y el 100 el verde se cierra hacia el institucional, que el
# manual reserva para lo que ya esta listo.
#
# ATENCION: estos colores son para SUPERFICIES RELLENAS --el mosaico del
# semaforo-- donde el color es el fondo y el texto se pone encima con
# texto_sobre(). No sirven para texto ni para bordes sobre blanco: el amarillo
# puro da 1,7:1 contra blanco, muy por debajo del 3:1 que pide la WCAG. Para eso
# siguen los tres tonos oscuros de las tarjetas y los chips (#9B2C1E, #7D5700,
# #005F2C), que son la misma senal en un soporte que no admite brillo.
SEMAFORO_ROJO     <- "#B3261E"
SEMAFORO_AMARILLO <- "#F2C200"
SEMAFORO_VERDE    <- "#005F2C"

SEMAFORO_RAMPA <- list(
  list(p =   0, col = SEMAFORO_ROJO),
  list(p =  45, col = SEMAFORO_ROJO),
  list(p =  60, col = SEMAFORO_AMARILLO),
  list(p =  90, col = "#3F9E4D"),
  list(p = 100, col = SEMAFORO_VERDE)
)

hex_rgb <- function(col) as.numeric(grDevices::col2rgb(col))

color_avance <- function(v) {
  if (length(v) != 1 || is.na(v)) return("#8A8F94")   # sin dato
  v <- max(0, min(100, as.numeric(v)))
  cortes <- vapply(SEMAFORO_RAMPA, function(x) x$p, numeric(1))
  i <- max(which(cortes <= v))
  if (i == length(cortes)) return(SEMAFORO_RAMPA[[i]]$col)
  a <- SEMAFORO_RAMPA[[i]]
  b <- SEMAFORO_RAMPA[[i + 1]]
  t <- (v - a$p) / (b$p - a$p)
  con_contraste(mezcla_rgb(a$col, b$col, t))
}

mezcla_rgb <- function(a, b, t) {
  m <- round((1 - t) * hex_rgb(a) + t * hex_rgb(b))
  grDevices::rgb(m[1], m[2], m[3], maxColorValue = 255)
}

# Hay una franja del degradado --el naranja del cruce entre el rojo y el
# amarillo-- donde ni el texto blanco ni el oscuro alcanzan el 4,5:1 que la WCAG
# pide para texto pequeno: el color se queda justo en el medio de la escala de
# luminancia. Ahi se oscurece el fondo lo justo para que el blanco lo alcance.
# Conserva el tono --sigue siendo el mismo naranja, mas hondo-- y el degradado no
# se rompe, porque el ajuste entra y sale de forma gradual.
con_contraste <- function(col, minimo = 4.5) {
  for (k in seq(1, 0.4, by = -0.02)) {
    c2 <- mezcla_rgb("#000000", col, k)
    if (contraste(c2, texto_sobre(c2)) >= minimo) return(c2)
  }
  col
}

# Luminancia relativa y razon de contraste de la WCAG 2.1, para elegir el color
# del texto midiendo y no a ojo: sobre el rojo y el verde gana el blanco, sobre
# el amarillo y los verdes claros del tramo de subida gana el texto oscuro.
lum_relativa <- function(col) {
  c <- hex_rgb(col) / 255
  f <- ifelse(c <= 0.03928, c / 12.92, ((c + 0.055) / 1.055)^2.4)
  sum(f * c(0.2126, 0.7152, 0.0722))
}

contraste <- function(a, b) {
  l <- sort(c(lum_relativa(a), lum_relativa(b)))
  (l[2] + 0.05) / (l[1] + 0.05)
}

texto_sobre <- function(fondo, claro = "#FFFFFF", oscuro = "#1B1B1B") {
  if (contraste(fondo, claro) >= contraste(fondo, oscuro)) claro else oscuro
}


# Prioridad de intervencion. Se mide en personas pendientes, no en porcentaje:
# el porcentaje no distingue entre una unidad de 14 personas al 50% (faltan 7) y
# una facultad de 244 al 67% (faltan 81). Los cortes son magnitudes absolutas, no
# cuantiles de la distribucion, para que no cambien de significado cada semana.
PRIO_ALTA  <- 35L   # personas pendientes: mas de una semana de trabajo de campo
PRIO_MEDIA <- 15L

prioridad_pendientes <- function(faltan) {
  if (length(faltan) != 1 || is.na(faltan)) {
    list(cls = "nulo",  txt = "Sin dato", sig = "\u2013")
  } else if (faltan >= PRIO_ALTA) {
    list(cls = "alta",  txt = "Alta",  sig = "\u25cf")
  } else if (faltan >= PRIO_MEDIA) {
    list(cls = "media", txt = "Media", sig = "\u25d0")
  } else {
    list(cls = "baja",  txt = "Baja",  sig = "\u25cb")
  }
}

# Por debajo de este numero de filas la tabla pierde su ventaja (comparar) y las
# tarjetas ganan la suya (detalle), asi que la vista se releva sola.
UMBRAL_TARJETAS <- 12L


# --- situacion de una persona frente a la encuesta ---------------------------
# La unidad es la PERSONA, no la respuesta: quien envio el cuestionario dos
# veces sigue siendo una sola persona, y manda su envio mas reciente. Las cuatro
# situaciones son excluyentes, asi que los conteos suman la poblacion y ninguna
# persona se cuenta dos veces.
#
#   sin respuesta ....................... falta
#   respondio y acepto .................. efectiva
#   respondio y no acepto ............... rechazo
#   dijo que no participa ............... rechazo   (los dos los pone la bitacora
#   no contesto a ninguna convocatoria .. ausente     de contactos, cto_aplicar())
#   fuera del marco activo .............. no_elegible (no entra al denominador)
#
# Se reutilizan las clases de color de estado_avance(): rojo lo que falta y
# verde lo que esta listo. Y como alli, el estado viaja
# con texto y simbolo, no solo con color.
#
# El rechazo y la ausencia no son ninguno de esos tres: no son un logro, no estan
# a medias y ya no hay nada que perseguir. Van en gris y con su propio signo, que
# es como se lee un caso cerrado sin encuesta. Y NINGUNO cuenta como encuestado:
# el numerador del avance sale solo de public.respuestas_procesadas.
#
# Se distinguen entre si porque no son lo mismo: el rechazo es una decision que
# la persona tomo y comunico --aspa, algo que se dijo-- y la ausencia es que
# nunca contesto --circulo punteado, algo que no llego--. En el informe una habla
# de voluntad y la otra del alcance del operativo.
SITUACIONES <- list(
  efectiva    = list(cls = "bien",    txt = "Efectiva",    sig = "\u2713"),
  falta       = list(cls = "bajo",    txt = "Falta",       sig = "\u25cb"),
  rechazo     = list(cls = "rechazo", txt = "Rechazo",     sig = "\u2715"),
  ausente     = list(cls = "ausente", txt = "Ausente",     sig = "\u25cc"),
  no_elegible = list(cls = "nulo",    txt = "No elegible", sig = "\u2013")
)

situacion_persona <- function(s) {
  if (length(s) != 1 || is.na(s) || is.null(SITUACIONES[[s]])) SITUACIONES$no_elegible
  else SITUACIONES[[s]]
}

# Grupos de la lista desplegable. Cuenta FILAS de un data.frame que ya trae una
# fila por persona; nunca respuestas. "elegibles" es el denominador de todo el
# modulo (los mismos activos con los que seg_avance() calcula el avance), y los
# no elegibles quedan aparte porque no entran en ese denominador.
# "respondieron" incluye los casos cerrados sin encuesta --rechazos y ausentes--:
# el grupo es "lo que ya no hay que perseguir". Se cuentan aparte para poder
# decirlo en el resumen, porque el rotulo del grupo tapa la diferencia entre una
# respuesta recibida y una puerta cerrada.
# Citados que no han respondido: elegibles a los que ya se les paso la hora de
# alguna citacion y que no tienen NINGUN envio. Atraviesa las situaciones: a
# quien la bitacora cerro como ausente o rechazo tambien se le cito y no
# respondio, y sale aqui; el rechazo del formulario no, porque ese envio existe.
# Es la misma regla con que seg_serie() cuenta los citados sin responder del
# grafico, asi que la cifra de la leyenda y la del desplegable cuadran.
citado_sin_responder <- function(p) {
  if (is.null(p) || nrow(p) == 0) return(logical(0))
  if (is.null(p$citado)) return(rep(FALSE, nrow(p)))
  (p$citado %in% TRUE) & is.na(p$submission_date) &
    as.character(p$situacion) != "no_elegible"
}

grupos_personas <- function(p) {
  s <- if (is.null(p) || nrow(p) == 0) character(0) else as.character(p$situacion)
  n_falta <- sum(s == "falta")
  n_efec  <- sum(s == "efectiva")
  n_rech  <- sum(s == "rechazo")
  n_aus   <- sum(s == "ausente")
  list(
    faltan       = n_falta,
    respondieron = n_efec + n_rech + n_aus,
    efectivas    = n_efec,
    rechazos     = n_rech,
    ausentes     = n_aus,
    elegibles    = n_falta + n_efec + n_rech + n_aus,
    no_elegibles = sum(s == "no_elegible"),
    citados      = sum(citado_sin_responder(p)),
    cerrados     = sum(cerrado_bitacora(p))
  )
}

# Los casos que cerro LA BITACORA --rechazo o ausente puestos a mano--, que son
# los unicos que se pueden reabrir. El rechazo del formulario no entra: ahi
# manda el envio. La marca la pone cto_aplicar(); sin ella no hay ninguno.
cerrado_bitacora <- function(p) {
  if (is.null(p) || nrow(p) == 0) return(logical(0))
  if (is.null(p$cierre_bitacora)) return(rep(FALSE, nrow(p)))
  p$cierre_bitacora %in% TRUE
}

GRUPOS_PERSONAS <- c("todos", "respondieron", "faltan", "citados", "cerrados",
                     "no_elegibles")

filtrar_personas <- function(p, grupo = "faltan") {
  if (is.null(p) || nrow(p) == 0) return(p)
  s <- as.character(p$situacion)
  quedan <- switch(
    grupo,
    faltan       = s == "falta",
    citados      = citado_sin_responder(p),
    cerrados     = cerrado_bitacora(p),
    respondieron = s %in% c("efectiva", "rechazo", "ausente"),
    no_elegibles = s == "no_elegible",
    s != "no_elegible"          # "todos" = todos los elegibles
  )
  p[quedan, , drop = FALSE]
}

# Numeros en convencion colombiana: punto para los miles, coma para los
# decimales (NTC 1000, sistema internacional). format() con big.mark = "." deja
# el punto tambien como separador decimal, que es ambiguo y ademas avisa.
fmt_num <- function(x, dec = 0) {
  if (length(x) == 0 || all(is.na(x))) return("\u2014")
  formatC(as.numeric(x), format = "f", digits = dec,
          big.mark = ".", decimal.mark = ",")
}

# Porcentaje ya formateado. Un decimal, que es la precision con la que la base
# devuelve el avance.
fmt_pct <- function(x, dec = 1) {
  if (length(x) == 0 || all(is.na(x))) return("\u2014")
  paste0(fmt_num(x, dec), "%")
}

# Fecha/hora legible para mostrar en pantalla (la base guarda timestamptz).
fmt_momento <- function(x) {
  if (length(x) == 0 || all(is.na(x))) return(NA_character_)
  format(as.POSIXct(x), "%Y-%m-%d %H:%M")
}

# Version para columnas de tabla: un texto por elemento, con relleno para los
# vacios. fmt_momento() colapsa a un unico NA cuando todo falta, que sirve para
# un dato suelto pero desalinea una columna.
fmt_momento_v <- function(x, vacio = "\u2014") {
  if (length(x) == 0) return(character(0))
  out <- format(as.POSIXct(x), "%Y-%m-%d %H:%M")
  ifelse(is.na(out), vacio, out)
}

# Fechas sin hora, como las que guarda la bitacora de contactos (columna `date`).
# No pasa por fmt_dia(): ese convierte a POSIXct, y una fecha a medianoche UTC
# formateada en la zona de Medellin retrocede un dia entero.
fmt_fecha <- function(x, vacio = "\u2014") {
  if (length(x) == 0) return(character(0))
  out <- format(as.Date(x), "%d/%m/%Y")
  ifelse(is.na(out), vacio, out)
}

# Solo la fecha: en una tabla de 244 filas la hora es ruido.
fmt_dia <- function(x, vacio = "\u2014") {
  if (length(x) == 0) return(character(0))
  out <- format(as.POSIXct(x), "%Y-%m-%d")
  ifelse(is.na(out), vacio, out)
}

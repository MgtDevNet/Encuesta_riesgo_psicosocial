# Modules/mod_descarga.R
# Módulo 5: descarga de datos. Baja a Excel la vista
# public.respuestas_procesadas_exportacion (RES_VISTA_EXPORTACION), completa o
# filtrada por las variables sociodemográficas.
#
#   mod_descarga_ui(id)
#   mod_descarga_server(id, r)
#
# Solo con el permiso `descargar_datos` (administrador y especialista): el
# archivo lleva la cédula. Cada descarga vuelve a mirar el rol en la base y
# queda en la bitácora.
#
# Los filtros se arman sobre las columnas de la propia vista, con sus rótulos,
# y no sobre los cruces de Resultados: aquella pestaña cruza con el marco y esta
# no, así que filtrar por unidad o dependencia aquí no tendría de dónde salir.

# Variables que se filtran eligiendo valores, y las que se filtran por rango.
# Si la vista deja de traer alguna, su filtro simplemente no se dibuja.
DES_FILTROS_LISTA <- c(
  "Forma", "Sexo", "Estado civil", "Nivel académico", "Estrato",
  "Tipo de vivienda", "Personas a cargo", "Horas diarias de trabajo",
  "Tipo de salario", "Cargo", "Área")
DES_FILTROS_RANGO <- c("Edad", "Años en la universidad", "Años en el cargo")

# Hoja "Filtros" del Excel: que se bajo, cuando, quien y con que filtros. Fuera
# de la app nadie recuerda de que grupo era un archivo, y dos descargas
# filtradas son iguales por fuera.
des_hoja_filtros <- function(f, completo, n, total, usuario) {
  cuando <- format(Sys.time(), "%Y-%m-%d %H:%M", tz = SEG_TZ)
  quien  <- if (is.null(usuario)) "" else
    sprintf("%s (%s)", usuario$nombre %||% "", usuario$usuario %||% "")
  cab <- data.frame(
    Campo = c("Descarga", "Fecha y hora", "Descargado por", "Envíos en el archivo"),
    Valor = c(if (completo) "Datos completos" else "Datos filtrados",
              cuando, quien, sprintf("%d de %d", n, total)))
  if (completo || !length(f$lista) && !length(f$rango))
    return(rbind(cab, data.frame(Campo = "Filtros", Valor = "Sin filtros")))
  rbind(cab, data.frame(
    Campo = c("Filtros", names(f$lista), names(f$rango)),
    Valor = c("Se incluyen solo quienes cumplen TODOS:",
              vapply(f$lista, paste, "", collapse = ", "),
              vapply(f$rango, function(x)
                sprintf("de %s a %s (sin dato queda fuera)", x[1], x[2]), "")),
    row.names = NULL))
}

# Filas de la vista previa: es para reconocer los datos, no para leerlos.
DES_MAX_PREVIA <- 20L

des_hay_vista <- function() {
  partes <- strsplit(RES_VISTA_EXPORTACION, ".", fixed = TRUE)[[1]]
  n <- tryCatch(
    db_get("SELECT count(*) AS n FROM information_schema.views
             WHERE table_schema = $1 AND table_name = $2",
           params = as.list(partes))$n,
    error = function(e) 0)
  isTRUE(as.numeric(n) > 0)
}

des_datos <- function() {
  db_get(sprintf("SELECT * FROM %s", RES_VISTA_EXPORTACION))
}

# Un vacío también es un valor que se puede elegir: quien no contestó el estado
# civil tiene que poder quedar dentro, o fuera, de un filtro.
des_valores <- function(x) {
  x <- as.character(x)
  x[is.na(x) | !nzchar(trimws(x))] <- RES_SIN_DATO
  x
}

des_orden <- function(v) {
  num <- suppressWarnings(as.numeric(v))
  if (!anyNA(num[v != RES_SIN_DATO])) v[order(v == RES_SIN_DATO, num)]
  else v[order(v == RES_SIN_DATO, to_key(v))]
}

# `lista`: valores admitidos por columna. `rango`: c(min, max) por columna; un
# rango que cubre todos los datos no filtra, y así no saca a quien no tiene el
# dato. Uno recortado sí lo saca: no se sabe si cae dentro.
des_filtrar <- function(d, lista, rango) {
  sel <- rep(TRUE, nrow(d))
  for (v in names(lista)) sel <- sel & des_valores(d[[v]]) %in% lista[[v]]
  for (v in names(rango)) {
    x <- suppressWarnings(as.numeric(d[[v]]))
    sel <- sel & !is.na(x) & x >= rango[[v]][1] & x <= rango[[v]][2]
  }
  d[sel, , drop = FALSE]
}


mod_descarga_ui <- function(id) {
  ns <- NS(id)

  fluidPage(
    div(class = "res-cabecera",
        div(class = "res-eyebrow", "Descarga de datos"),
        h3(class = "res-seg-titulo", "Respuestas procesadas en Excel"),
        uiOutput(ns("conteo"))),

    uiOutput(ns("aviso")),

    div(
      class = "res-bloque res-bloque-filtrar",
      div(class = "res-bloque-cab",
          span(class = "res-bloque-eyebrow", "Filtrar"),
          span(class = "res-bloque-preg",
               "Sin filtros se descarga todo. Cada filtro deja solo a quienes cumplen.")),
      div(class = "res-filtros-rejilla", uiOutput(ns("filtros"))),
      actionLink(ns("limpiar"), "Quitar todos los filtros", class = "res-restablecer")
    ),

    div(class = "des-botones",
        downloadButton(ns("bajar_todo"), "Descargar todo",
                       class = "btn-outline-primary"),
        downloadButton(ns("bajar_filtrado"), "Descargar filtrado",
                       class = "btn-primary")),

    h5(class = "des-previa-titulo", "Vista previa"),
    uiOutput(ns("previa_nota")),
    div(class = "des-previa", tableOutput(ns("previa")))
  )
}


mod_descarga_server <- function(id, r = reactiveValues()) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Una consulta por sesión, como en Resultados.
    datos <- reactive({
      if (!des_hay_vista()) return(NULL)
      des_datos()
    })

    lista_cols <- reactive(intersect(DES_FILTROS_LISTA, names(datos())))
    rango_cols <- reactive(intersect(DES_FILTROS_RANGO, names(datos())))
    id_lista <- function(i) paste0("fl_", i)
    id_rango <- function(i) paste0("fr_", i)

    # Límites enteros de cada rango, o NULL si la columna está vacía.
    limites <- reactive({
      d <- datos()
      stats::setNames(lapply(rango_cols(), function(v) {
        x <- suppressWarnings(as.numeric(d[[v]]))
        if (all(is.na(x))) NULL else c(floor(min(x, na.rm = TRUE)),
                                       ceiling(max(x, na.rm = TRUE)))
      }), rango_cols())
    })

    output$aviso <- renderUI({
      d <- datos()
      if (is.null(d))
        return(alerta(paste("La vista", RES_VISTA_EXPORTACION, "no existe todavía.",
                            "Se crea al correr conectar_bd.R."), "warning"))
      if (!nrow(d)) return(alerta("La vista no tiene filas todavía.", "secondary"))
      NULL
    })

    # Se dibujan una vez desde los datos y no leen sus propios valores, para no
    # rehacerse con cada selección.
    output$filtros <- renderUI({
      d <- datos()
      if (is.null(d) || !nrow(d)) return(NULL)
      lim <- limites()
      c(
        lapply(seq_along(lista_cols()), function(i) {
          v <- lista_cols()[i]
          selectizeInput(
            ns(id_lista(i)), v, choices = des_orden(unique(des_valores(d[[v]]))),
            multiple = TRUE, width = "100%",
            options = list(placeholder = "Todos", plugins = list("remove_button")))
        }),
        lapply(seq_along(rango_cols()), function(i) {
          l <- lim[[rango_cols()[i]]]
          if (is.null(l)) return(NULL)
          sliderInput(ns(id_rango(i)), rango_cols()[i], min = l[1], max = l[2],
                      value = l, step = 1, sep = "", width = "100%")
        })
      )
    })

    filtros <- reactive({
      lista <- list()
      for (i in seq_along(lista_cols())) {
        x <- input[[id_lista(i)]]
        if (length(x)) lista[[lista_cols()[i]]] <- x
      }
      rango <- list()
      lim <- limites()
      for (i in seq_along(rango_cols())) {
        x <- input[[id_rango(i)]]
        l <- lim[[rango_cols()[i]]]
        if (length(x) == 2 && !is.null(l) && (x[1] > l[1] || x[2] < l[2]))
          rango[[rango_cols()[i]]] <- x
      }
      list(lista = lista, rango = rango)
    })

    filtrados <- reactive({
      d <- datos()
      if (is.null(d)) return(NULL)
      f <- filtros()
      des_filtrar(d, f$lista, f$rango)
    })

    observeEvent(input$limpiar, {
      for (i in seq_along(lista_cols()))
        updateSelectizeInput(session, id_lista(i), selected = character(0))
      lim <- limites()
      for (i in seq_along(rango_cols())) {
        l <- lim[[rango_cols()[i]]]
        if (!is.null(l)) updateSliderInput(session, id_rango(i), value = l)
      }
    })

    output$conteo <- renderUI({
      d <- datos(); f <- filtrados()
      if (is.null(d)) return(NULL)
      n_f <- length(filtros()$lista) + length(filtros()$rango)
      div(class = "res-seg-sub",
          span(class = "res-seg-n", fmt_num(nrow(f)), "de", fmt_num(nrow(d)), "envíos"),
          span(class = "sep", "·"),
          span(if (n_f == 0) "sin filtros"
               else sprintf("%d %s", n_f, if (n_f == 1) "filtro activo" else "filtros activos")),
          span(class = "sep", "·"),
          span(fmt_num(ncol(d)), "columnas"))
    })

    output$previa_nota <- renderUI({
      f <- filtrados()
      if (is.null(f) || nrow(f) <= DES_MAX_PREVIA) return(NULL)
      p(class = "text-muted small",
        sprintf("Se muestran las primeras %d filas; el Excel lleva las %s.",
                DES_MAX_PREVIA, fmt_num(nrow(f))))
    })

    output$previa <- renderTable({
      f <- filtrados()
      if (is.null(f) || !nrow(f)) return(NULL)
      utils::head(f, DES_MAX_PREVIA)
    }, striped = TRUE, hover = TRUE, spacing = "xs", na = "")

    # La descarga vuelve a preguntar el rol a la base, como toda acción: quitar
    # el permiso tiene que valer aunque la pestaña siga abierta.
    bajar <- function(completo) downloadHandler(
      filename = function() {
        sprintf("datos_%s_%s.xlsx", if (completo) "completos" else "filtrados",
                format(Sys.Date(), "%Y%m%d"))
      },
      content = function(archivo) {
        u <- r$usuario$usuario
        if (!auth_puede_usuario(u, "descargar_datos"))
          stop("Su usuario ya no tiene permiso para descargar datos.", call. = FALSE)
        x <- if (completo) datos() else filtrados()
        if (is.null(x)) stop("La vista de exportación no existe.", call. = FALSE)
        escribir_excel(list(
          Datos   = x,
          Filtros = des_hoja_filtros(filtros(), completo, nrow(x), nrow(datos()),
                                     r$usuario)), archivo)
        try(auth_bitacora("descarga_datos", u,
                          sprintf("%s: %d filas", if (completo) "completo" else "filtrado",
                                  nrow(x))))
      }
    )
    output$bajar_todo     <- bajar(TRUE)
    output$bajar_filtrado <- bajar(FALSE)
  })
}

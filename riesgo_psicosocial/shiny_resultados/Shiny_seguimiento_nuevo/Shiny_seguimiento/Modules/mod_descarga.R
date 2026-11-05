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
# Abajo va el informe individual en Word de una persona (R/utils_informe.R),
# con el mismo permiso: también lleva nombre y cédula. Y debajo, el informe en
# PowerPoint de una unidad o una dependencia (R/utils_informe_unidad.R), con el
# mismo permiso.
#
# Los filtros se arman sobre las columnas de la propia vista, con sus rótulos,
# y no sobre los cruces de Resultados. Unidad y Dependencia las trae la vista
# desde el marco (o de empleados_no_registrados para quien no está en él).
#
# "Usar contratos menores a 6 meses" va aparte de los demás: Sí (lo de siempre)
# no filtra nada, y No saca a quien tiene "Sí" en la columna RES_COL_CONTRATO,
# es decir, a quien se vinculó después de la fecha de corte.

# Variables que se filtran eligiendo valores, y las que se filtran por rango.
# Si la vista deja de traer alguna, su filtro simplemente no se dibuja.
DES_FILTROS_LISTA <- c(
  "Unidad", "Dependencia",
  "Forma", "Sexo", "Estado civil", "Nivel académico", "Estrato",
  "Tipo de vivienda", "Personas a cargo", "Horas diarias de trabajo",
  "Tipo de salario", "Cargo", "Área")
DES_ROT_CONTRATOS <- "Usar contratos menores a 6 meses"
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
  if (completo || f$contratos && !length(f$lista) && !length(f$rango))
    return(rbind(cab, data.frame(Campo = "Filtros", Valor = "Sin filtros")))
  rbind(cab, data.frame(
    Campo = c("Filtros", if (!f$contratos) DES_ROT_CONTRATOS, names(f$lista),
              names(f$rango)),
    Valor = c("Se incluyen solo quienes cumplen TODOS:",
              if (!f$contratos)
                sprintf("No: se excluye a quien se vinculó después del %s",
                        format(SEG_CORTE_VINCULACION, "%d/%m/%Y")),
              vapply(f$lista, paste, "", collapse = ", "),
              vapply(f$rango, function(x)
                sprintf("de %s a %s (sin dato queda fuera)", x[1], x[2]), "")),
    row.names = NULL))
}

# Mientras se arma un archivo se muestra una ventana grande: la barrita de
# progreso de Shiny, abajo en una esquina, casi no se ve. Se cierra sola al
# terminar; si algo falla, se cambia por una ventana que dice que paso.
des_en_proceso <- function(session, texto, expr) {
  showModal(modalDialog(
    div(class = "text-center py-3",
        div(class = "spinner-border text-success mb-3", role = "status",
            style = "width: 3.5rem; height: 3.5rem;"),
        h4(texto),
        p(class = "text-muted mb-0",
          "Esto puede tardar unos segundos. El archivo se descargará solo.")),
    footer = NULL, easyClose = FALSE), session = session)
  tryCatch({
    force(expr)
    removeModal(session = session)
  }, error = function(e) {
    showModal(modalDialog(title = "No se pudo generar el archivo", conditionMessage(e),
                          easyClose = TRUE, footer = modalButton("Cerrar")),
              session = session)
    stop(e)
  })
  invisible(TRUE)
}

# El boton de descarga de un informe solo aparece con algo elegido: descargar
# sin elegir bajaba una pagina de error de Shiny como archivo .html. Antes, en
# su lugar, va un boton igual que solo avisa que falta elegir.
des_boton_informe <- function(ns, entrada, id_bajar, id_falta, rotulo) {
  tagList(
    conditionalPanel(condition = sprintf("input.%s", entrada), ns = ns,
                     downloadButton(ns(id_bajar), rotulo, class = "btn-primary")),
    conditionalPanel(condition = sprintf("!input.%s", entrada), ns = ns,
                     actionButton(ns(id_falta), rotulo, icon = icon("download"),
                                  class = "btn-primary")))
}

des_aviso_elegir <- function(texto) {
  showModal(modalDialog(title = "Falta elegir", texto, easyClose = TRUE,
                        footer = modalButton("Entendido")))
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
des_filtrar <- function(d, lista, rango, contratos = TRUE) {
  sel <- rep(TRUE, nrow(d))
  if (!contratos && RES_COL_CONTRATO %in% names(d))
    sel <- sel & !d[[RES_COL_CONTRATO]] %in% "Sí"
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
      div(class = "res-filtros-rejilla",
          radioButtons(ns("contratos"), DES_ROT_CONTRATOS, inline = TRUE,
                       choices = c("Sí" = "si", "No" = "no"), selected = "si"),
          uiOutput(ns("filtros"))),
      actionLink(ns("limpiar"), "Quitar todos los filtros", class = "res-restablecer")
    ),

    div(class = "des-botones",
        downloadButton(ns("bajar_todo"), "Descargar todo",
                       class = "btn-outline-primary"),
        downloadButton(ns("bajar_filtrado"), "Descargar filtrado",
                       class = "btn-primary")),

    div(
      class = "res-bloque res-bloque-filtrar des-informe",
      div(class = "res-bloque-cab",
          span(class = "res-bloque-eyebrow", "Informe individual"),
          span(class = "res-bloque-preg",
               "El formato de entrega de resultados en Word, para una persona.")),
      uiOutput(ns("informe_aviso")),
      selectizeInput(ns("persona"), "Persona", choices = NULL, width = "100%",
                     options = list(placeholder = "Escriba el nombre o la cédula")),
      des_boton_informe(ns, "persona", "bajar_informe", "informe_falta",
                        "Descargar informe (Word)")),

    div(
      class = "res-bloque res-bloque-filtrar des-informe",
      div(class = "res-bloque-cab",
          span(class = "res-bloque-eyebrow", "Informe por unidad o dependencia"),
          span(class = "res-bloque-preg",
               "La presentación de resultados en PowerPoint, para una unidad o una dependencia.")),
      radioButtons(ns("iu_nivel"), "Informe por", inline = TRUE,
                   choices = c("Unidad" = "unidad", "Dependencia" = "dependencia"),
                   selected = "unidad"),
      selectizeInput(ns("iu_valor"), NULL, choices = NULL, width = "100%",
                     options = list(placeholder = "Escriba el nombre")),
      uiOutput(ns("iu_nota")),
      des_boton_informe(ns, "iu_valor", "bajar_iu", "iu_falta",
                        "Descargar informe (PowerPoint)")),

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
      list(lista = lista, rango = rango,
           contratos = !identical(input$contratos, "no"))
    })

    filtrados <- reactive({
      d <- datos()
      if (is.null(d)) return(NULL)
      f <- filtros()
      des_filtrar(d, f$lista, f$rango, f$contratos)
    })

    observeEvent(input$limpiar, {
      updateRadioButtons(session, "contratos", selected = "si")
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
      n_f <- length(filtros()$lista) + length(filtros()$rango) + !filtros()$contratos
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
        x <- if (completo) datos() else filtrados()
        des_en_proceso(session, "Preparando la descarga…", {
          if (!auth_puede_usuario(u, "descargar_datos"))
            stop("Su usuario ya no tiene permiso para descargar datos.", call. = FALSE)
          if (is.null(x)) stop("La vista de exportación no existe.", call. = FALSE)
          escribir_excel(list(
            Datos   = x,
            Filtros = des_hoja_filtros(filtros(), completo, nrow(x), nrow(datos()),
                                       r$usuario)), archivo)
        })
        try(auth_bitacora("descarga_datos", u,
                          sprintf("%s: %d filas", if (completo) "completo" else "filtrado",
                                  nrow(x))))
      }
    )
    output$bajar_todo     <- bajar(TRUE)
    output$bajar_filtrado <- bajar(FALSE)

    # --- informe individual ----------------------------------------------------

    personas <- reactive(if (inf_hay_vista()) inf_personas() else NULL)

    output$informe_aviso <- renderUI({
      if (is.null(personas()))
        alerta(paste("La vista", RES_VISTA_EXPORTACION_IND, "no existe todavía.",
                     "Se crea al correr conectar_bd.R."), "warning")
    })

    # Del lado del servidor: el buscador no carga en el navegador la lista
    # entera de nombres y cédulas.
    observe({
      p <- personas()
      if (is.null(p)) return()
      updateSelectizeInput(
        session, "persona", server = TRUE, selected = character(0),
        choices = stats::setNames(p$cedula, sprintf("%s · %s",
                                                    ifelse(is.na(p$nombre), "Sin nombre", p$nombre),
                                                    p$cedula)))
    })

    observeEvent(input$informe_falta,
      des_aviso_elegir("Primero elija una persona en el buscador para descargar su informe."))

    output$bajar_informe <- downloadHandler(
      filename = function() {
        sprintf("informe_individual_%s_%s.docx",
                gsub("[^0-9A-Za-z]", "", input$persona %||% ""), format(Sys.Date(), "%Y%m%d"))
      },
      content = function(archivo) {
        u <- r$usuario$usuario
        des_en_proceso(session, "Armando el informe individual…", {
          if (!auth_puede_usuario(u, "descargar_datos"))
            stop("Su usuario ya no tiene permiso para descargar datos.", call. = FALSE)
          if (!nzchar(input$persona %||% ""))
            stop("Elija primero a la persona.", call. = FALSE)
          p <- inf_datos(input$persona)
          if (is.null(p)) stop("No hay resultados de esa persona.", call. = FALSE)
          inf_generar(p, archivo)
        })
        try(auth_bitacora("informe_individual", u, paste("cédula", input$persona)))
      }
    )

    # --- informe por unidad o dependencia --------------------------------------

    # Se rehace cuando llegan respuestas nuevas, como el avance.
    iu_av  <- reactive({ r$respuestas; seg_avance() })
    iu_ops <- reactive(iu_opciones(iu_av()))
    iu_nivel <- reactive(if (identical(input$iu_nivel, "dependencia")) "dependencia" else "unidad")

    # Cada opción dice cuántos encuestados tiene, para saber antes de bajar el
    # informe si alcanza el mínimo.
    observe({
      op <- iu_ops()[[iu_nivel()]]
      updateSelectizeInput(
        session, "iu_valor", selected = character(0),
        choices = stats::setNames(op$v, sprintf("%s · %s", op$v,
                                                ifelse(op$x == 1, "1 encuestado",
                                                       paste(fmt_num(op$x), "encuestados")))),
        options = list(placeholder = sprintf("Escriba el nombre de la %s",
                                             tolower(IU_NIVELES[[iu_nivel()]]))))
    })

    output$iu_nota <- renderUI({
      v <- input$iu_valor
      if (!nzchar(v %||% "")) return(NULL)
      op <- iu_ops()[[iu_nivel()]]
      n <- op$x[match(v, op$v)]
      if (!is.na(n) && n < RES_MIN_N)
        p(class = "text-muted small",
          sprintf(paste("Tiene menos de %d encuestados: el informe sale con la cobertura",
                        "y un aviso de confidencialidad en lugar de los resultados."), RES_MIN_N))
    })

    observeEvent(input$iu_falta,
      des_aviso_elegir(sprintf("Primero elija la %s para descargar el informe.",
                               tolower(IU_NIVELES[[iu_nivel()]]))))

    output$bajar_iu <- downloadHandler(
      filename = function() iu_archivo(iu_nivel(), input$iu_valor %||% ""),
      content = function(archivo) {
        u <- r$usuario$usuario
        v <- input$iu_valor %||% ""
        des_en_proceso(session, "Armando el informe en PowerPoint…", {
          if (!auth_puede_usuario(u, "descargar_datos"))
            stop("Su usuario ya no tiene permiso para descargar datos.", call. = FALSE)
          if (!nzchar(v))
            stop(sprintf("Elija primero la %s.", tolower(IU_NIVELES[[iu_nivel()]])), call. = FALSE)
          if (!res_hay_datos())
            stop("Todavía no hay resultados calificados.", call. = FALSE)
          iu_generar(iu_nivel(), v, archivo, d = res_datos(), av = iu_av())
        })
        try(auth_bitacora("informe_unidad", u, sprintf("%s: %s", IU_NIVELES[[iu_nivel()]], v)))
      }
    )
  })
}

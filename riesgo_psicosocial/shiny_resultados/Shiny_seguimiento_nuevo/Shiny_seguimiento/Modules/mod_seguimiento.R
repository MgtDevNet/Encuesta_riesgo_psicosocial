# Modules/mod_seguimiento.R
# Módulo 2: avance de la aplicación por dependencia.
#
#   mod_seguimiento_ui(id)
#   mod_seguimiento_server(id, r)
#
# El grafico tiene dos vistas en la misma tarjeta, con una minipestana:
#
#   Dias     la curva del acumulado dia a dia, con cruceta y tooltip. Es la
#            vista que arranca.
#   Semanas  barras apiladas por semana de campo, con los tres numeros a la
#            vista (acumulado anterior, nuevas de la semana y total) y la meta
#            como linea punteada.
#
# Las dos cuentan las mismas personas: la semanal agrupa en R la misma serie
# diaria que consulta la curva, no vuelve a la base.
#
# El listado se adapta al numero de dependencias: tabla cuando hay muchas (para
# comparar) y tarjetas cuando el filtro deja pocas (para ver detalle). Al hacer
# clic en una fila o tarjeta se abre el detalle, en dos pestanas:
#
#   Avance    cifras de la dependencia y como va la encuesta.
#   Personas  una fila por PERSONA del marco, con un desplegable que separa
#             quienes faltan de quienes ya respondieron. Arranca en "Faltan",
#             que es la pregunta operativa, y se puede bajar en CSV.
#
# La unidad de la segunda pestana es la persona y no la respuesta: quien envio
# el cuestionario dos veces sigue siendo una sola persona (ver seg_personas()).
# Los estilos viven en www/custom.css.

mod_seguimiento_ui <- function(id) {
  ns <- NS(id)

  fluidPage(
    # Un solo manejador delegado para las dos formas del listado: la fila de la
    # tabla y la tarjeta emiten el mismo evento, asi que el server no distingue.
    tags$script(HTML(sprintf(
      "$(document).on('click keydown', '#%s [data-dep]', function(e){
         if (e.type === 'keydown' && e.key !== 'Enter' && e.key !== ' ') return;
         if (e.type === 'keydown') e.preventDefault();
         Shiny.setInputValue('%s', $(this).data('dep'), {priority: 'event'});
       });
       $(document).on('click', '#%s th button[data-col]', function(){
         Shiny.setInputValue('%s', $(this).data('col'), {priority: 'event'});
       });",
      ns("listado"), ns("dep_click"), ns("listado"), ns("ordenar_por")
    ))),

    # Seleccion multiple y boton de contacto en la tabla de personas. Mismo
    # patron delegado que el listado: renderUI() rehace la tabla entera con cada
    # cambio, y un listener pegado a la fila se iria con la fila vieja.
    #
    # La lista de marcadas viaja completa en cada cambio --no de a un id-- para
    # que el servidor no tenga que ir acumulando y descontando; asi lo que el
    # servidor cree seleccionado es siempre lo que se ve marcado.
    tags$script(HTML(sprintf(
      "(function(){
         var caja = '#%s';
         function marcadas(){
           var ids = $(caja + ' .sel-persona:checked').map(function(){
             return String($(this).attr('data-per'));
           }).get();
           Shiny.setInputValue('%s', ids, {priority: 'event'});
         }
         $(document).on('change', caja + ' .sel-todas', function(){
           $(caja + ' .sel-persona').prop('checked', this.checked);
           marcadas();
         });
         $(document).on('change', caja + ' .sel-persona', marcadas);
         // El boton de contactar tambien esta en el recuadro de citados por dia
         // (al final de la pestana), que es otra caja distinta.
         $(document).on('click', caja + ' [data-contactar], #%s [data-contactar]', function(){
           Shiny.setInputValue('%s', String($(this).attr('data-contactar')),
                               {priority: 'event'});
         });
         // Reabrir un caso cerrado por la bitacora: mismo patron, otro evento.
         $(document).on('click', caja + ' [data-reabrir], #%s [data-reabrir]', function(){
           Shiny.setInputValue('%s', String($(this).attr('data-reabrir')),
                               {priority: 'event'});
         });
       })();",
      ns("tabla_personas"), ns("seleccion"), ns("tabla_dia"), ns("contactar"),
      ns("tabla_dia"), ns("reabrir")
    ))),

    # Cruceta y tooltip del grafico. Va en un archivo aparte y no incrustado:
    # no necesita ns() --trabaja delegado sobre .grafico-acum-- y asi el
    # navegador lo cachea en vez de traerlo dentro de cada pagina.

    div(
      class = "d-flex flex-wrap gap-3 align-items-end mb-3",
      div(style = "min-width:220px;",
          # Mismo rotulo que en Resultados y el mismo de la nomina:
          # DESCRIPCION_UNIDAD, la facultad, escuela o direccion de la que
          # cuelga la dependencia. No es una clasificacion de dependencias.
          selectizeInput(ns("tipos"), "Unidad", choices = NULL,
                         multiple = TRUE, width = "100%",
                         options = list(placeholder = "Todos"))),
      div(style = "min-width:200px;",
          textInput(ns("buscar"), "Buscar dependencia", width = "100%",
                    placeholder = "Escriba parte del nombre")),
      div(style = "min-width:190px;",
          selectInput(ns("orden"), "Ordenar por", width = "100%",
                      # Por pendientes primero: es el trabajo que queda. Ordenar
                      # por avance sube las unidades pequenas muy rezagadas y
                      # entierra las grandes a medio camino, que son las que
                      # concentran el esfuerzo.
                      choices = c("Más pendientes"   = "faltan",
                                  "Menor avance"     = "avance",
                                  "Más encuestados"  = "encuestados",
                                  "Nombre"           = "dependencia",
                                  "Más grandes"      = "planeado"),
                      selected = "faltan")),
      actionButton(ns("limpiar"), "Limpiar filtros", class = "btn-sm btn-outline-secondary mb-1")
    ),

    # El informe en Word ya no se baja desde aqui: es solo para administradores
    # y vive en la pestana Administracion (ver mod_informe_ui()).
    uiOutput(ns("indicadores")),
    uiOutput(ns("grafico")),

    # El selector es estatico --no depende de los datos-- asi que vive en la UI
    # y no dentro del render: cambiar de vista no lo redibuja, y no hace falta
    # guardar su valor aparte como en el grafico.
    div(
      class = "barra-listado",
      uiOutput(ns("resumen")),
      selector_vista(ns("vista_lista"), "listado", VISTAS_LISTADO)
    ),

    uiOutput(ns("listado")),
    uiOutput(ns("detalle")),

    # Va al final, despues del detalle: es una lista de trabajo --a quien llamar
    # de la jornada de tal dia-- y no parte de la lectura del avance, que es lo
    # que ocupa el resto de la pestana.
    uiOutput(ns("citados_dia")),

    # Quien respondio sin estar en el marco, para completarle los datos del
    # marco. Va de ultimo: es trabajo de depuracion, no lectura del avance.
    uiOutput(ns("no_registrados")),
    tags$script(HTML(sprintf(
      "$(document).on('click', '#%s [data-completar]', function(){
         Shiny.setInputValue('%s', String($(this).attr('data-completar')),
                             {priority: 'event'});
       });",
      ns("no_registrados"), ns("nr_completar")))),
    # Los dos recuadros de abajo nacen plegados y se redibujan solos (llegan
    # respuestas, cambia la agenda): sin recordar en R que se desplegaron, cada
    # redibujo los volveria a cerrar. El evento 'toggle' de <details> no
    # burbujea, asi que se escucha el clic en el <summary> y se manda el estado
    # que va a quedar, el contrario del actual. Mismo patron que en Resultados.
    tags$script(HTML(sprintf(
      "$(document).on('click', '#%s details.seg-pleg > summary, #%s details.seg-pleg > summary', function(){
         var d = $(this).closest('details');
         Shiny.setInputValue('%s',
           d.attr('data-plegable') + '|' + (d.prop('open') ? '0' : '1') + '|' + Date.now(),
           {priority: 'event'});
       });",
      ns("citados_dia"), ns("no_registrados"), ns("plegar")))),
    # Borrar una persona (solo administrador): pide confirmacion en el servidor.
    tags$script(HTML(sprintf(
      "$(document).on('click', '#%s [data-borrar], #%s [data-borrar]', function(){
         Shiny.setInputValue('%s', {id:     String($(this).attr('data-borrar')),
                                    origen: String($(this).attr('data-origen'))},
                             {priority: 'event'});
       });",
      ns("citados_dia"), ns("no_registrados"), ns("borrar"))))
  )
}


mod_seguimiento_server <- function(id, r = reactiveValues()) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    seleccionada <- reactiveVal(NULL)

    observe({
      updateSelectizeInput(session, "tipos", choices = seg_tipos_dependencia(), server = FALSE)
    })

    observeEvent(input$limpiar, {
      updateSelectizeInput(session, "tipos", selected = character(0))
      updateTextInput(session, "buscar", value = "")
      updateSelectInput(session, "orden", selected = "faltan")
      seleccionada(NULL)
    })

    # La lista se arma en tres pasos y no en una sola reactiva, porque cada paso
    # cambia con cosas distintas y cuesta cosas distintas. Junta, teclear en el
    # buscador --que filtra en R, sin tocar la base-- invalidaba tambien al
    # grafico, y eso son ~280 ms de consulta por letra en un R de un solo hilo
    # que atiende a todas las sesiones. Reordenar el listado hacia lo mismo, para
    # dibujar exactamente el mismo grafico.
    #
    #   avance_base      lo unico que va a la base: la unidad.
    #   avance_filtrado  + el buscador. Es la POBLACION que se esta mirando, y de
    #                    aqui cuelgan los indicadores y el grafico.
    #   avance           + el orden, que solo le importa al listado.
    #
    # Y el buscador espera a que se deje de teclear: aun filtrando solo en R,
    # cada letra rehacia la tabla de 163 filas entera.
    buscar <- debounce(reactive(input$buscar %||% ""), 300)

    avance_base <- reactive({
      # Una agenda nueva cargada desde la pestana de citaciones rehace el
      # grafico y los citados sin recargar la pagina (ver mod_citaciones).
      r$citaciones
      # Igual con las respuestas nuevas que deja conectar_bd.R (ver app.R).
      r$respuestas
      # Cerrar o reabrir un caso mueve "Faltan" (ver seg_sql_cierre()): sin
      # esto, el listado y los cajones no lo verian hasta recargar la pagina.
      recarga_cto()
      seg_avance(input$tipos)
    })

    avance_filtrado <- reactive({
      a <- avance_base()
      b <- buscar()
      if (!nzchar(b)) return(a)
      a[grepl(to_key(b), to_key(a$dependencia), fixed = TRUE), , drop = FALSE]
    })

    # Sin filtro de unidades ni buscador se mira la universidad entera, y solo
    # entonces cuentan los citados fuera del marco (ver SEG_CIT_SIN_MARCO).
    sin_filtro <- reactive(length(input$tipos) == 0 && !nzchar(buscar()))

    avance <- reactive({
      a <- avance_filtrado()
      # Menor avance primero (lo urgente arriba); las demás, de mayor a menor.
      # El nombre desempata siempre, para que el orden sea estable.
      switch(input$orden %||% "faltan",
        avance      = a[order( a$avance,   a$dependencia), , drop = FALSE],
        faltan      = a[order(-a$faltan,   a$dependencia), , drop = FALSE],
        encuestados = a[order(-a$encuestados, a$dependencia), , drop = FALSE],
        planeado    = a[order(-a$planeado, a$dependencia), , drop = FALSE],
        dependencia = a[order( a$dependencia), , drop = FALSE],
        a)
    })

    # --- fila de indicadores -------------------------------------------------

    # Las dos formas van pegadas a "Encuestados" porque lo descomponen: A + B es
    # exactamente ese numero, y lo mismo pasa con sus efectivas. Con las citadas
    # no: sin filtro, el total suma tambien a los citados fuera del marco, que
    # no tienen forma, y por eso la Cobertura Citados va solo en el total.
    # Dentro de cada una van los otros dos indicadores de ESA forma, que es de donde
    # sale la pregunta util: si A va al 63% de efectividad y B al 58%, el campo
    # esta rindiendo distinto en las dos y hay que mirar por que.
    #
    # La misma fila se dibuja en el detalle de cada dependencia (ver
    # output$detalle), con las mismas funciones y los mismos rotulos: leer una
    # dependencia tiene que ser leer lo mismo que el total, pero en pequeno.
    output$indicadores <- renderUI({
      a <- avance_filtrado()
      t <- seg_totales(a)

      # Con el filtro sin coincidencias no se puede consultar: la lista de
      # dependencias viaja vacia y el SQL la lee como "sin filtro", que
      # devolveria los totales de TODA la universidad justo cuando la pantalla
      # dice que no hay nada. Se arma la fila en ceros a mano.
      ceros <- list(marco = 0L, encuestados = 0L, efectivas = 0L, citados = 0L,
                    efectividad = NA_real_, no_efectivas = 0L,
                    pct_no_efectivas = NA_real_, cob_citados = NA_real_,
                    cob_esperados = NA_real_)
      ti <- if (nrow(a) == 0) list(total = ceros, A = ceros, B = ceros)
            else seg_totales_indicadores(sort(a$dependencia), sin_marco = sin_filtro())

      caja <- function(valor, etiqueta, clase = "") {
        div(class = "kpi-caja",
            div(class = paste("kpi-valor", clase), fmt_num(valor)),
            div(class = "kpi-etiqueta", etiqueta))
      }
      div(class = "kpi-fila mb-3",
          caja(t$planeado, "Esperados"),
          caja(t$encuestados, "Encuestados", "text-success"),
          caja_forma("A", t$encuestados_a, ti$A),
          caja_forma("B", t$encuestados_b, ti$B),
          caja(t$faltan, "Faltan", "text-danger"),
          caja_indicador("Efectividad",         ti$total$efectividad,
                         ti$total$efectivas,   "aceptaron"),
          caja_indicador("No efectivas",        ti$total$pct_no_efectivas,
                         ti$total$no_efectivas, "no aceptaron"),
          caja_indicador("Cobertura Citados",   ti$total$cob_citados,
                         ti$total$encuestados, "encuestadas",
                         ti$total$citados, "citadas"),
          caja_indicador("Cobertura Esperados", ti$total$cob_esperados,
                         ti$total$encuestados, "encuestadas"),
          caja(t$dependencias, "Dependencias"),
          caja(t$completas, "Al 100%"))
    })

    # --- grafico de avance: barras por semana o curva diaria ------------------

    # Se alimenta de la lista de dependencias que YA paso por los filtros, no de
    # input$tipos: el buscador filtra en R y nunca llega al SQL, asi
    # que pasarle los mismos filtros a la consulta dejaria la curva midiendo una
    # poblacion distinta de la que cuentan los indicadores de arriba. Con la
    # lista resuelta, la curva cierra exactamente en su "Encuestados".
    #
    # Las dos vistas cuentan exactamente las mismas personas: seg_semanas() no
    # vuelve a la base, agrupa la serie diaria que ya se consulto. Cambiar de
    # minipestana no puede cambiar el total.
    #
    # El valor de la minipestana se guarda en un reactiveVal aparte porque el
    # selector se dibuja DENTRO de la tarjeta que este render produce: leer
    # input$vista aqui haria que la primera respuesta del navegador --la misma
    # que acaba de enviarse-- invalidara el render y repitiera las consultas.
    # reactiveVal no avisa cuando le vuelven a poner el valor que ya tenia.
    vista <- reactiveVal("linea")
    observeEvent(input$vista, vista(input$vista))

    # La metrica se guarda aparte del grano, por lo mismo: son dos preguntas
    # independientes, y su selector tambien se dibuja dentro de la tarjeta.
    metrica <- reactiveVal("avance")
    observeEvent(input$metrica, metrica(input$metrica))

    # Origen de la numeracion de las semanas. No depende de los filtros: la
    # primera semana de campo ya paso y no va a cambiar mientras dure la sesion,
    # asi que la consulta se hace una sola vez.
    inicio_campo <- reactive(seg_inicio_campo())

    output$grafico <- renderUI({
      a <- avance_filtrado()
      if (nrow(a) == 0) return(NULL)
      # Ordenada alfabeticamente, no en el orden del listado: la poblacion es la
      # misma se mire como se mire, y asi mover "Ordenar por" no cambia la cadena
      # que viaja al SQL. Colgado de avance(), cada reordenamiento repetia estas
      # dos consultas para dibujar el mismo grafico.
      deps <- sort(a$dependencia)

      # Los dos selectores viajan juntos: el grano arriba y la metrica debajo,
      # en el mismo sitio de la cabecera donde antes iba el unico que habia.
      ctrl <- tagList(
        selector_vista(ns("vista"),   vista()),
        selector_vista(ns("metrica"), metrica(), VISTAS_METRICA))

      sem <- identical(vista(), "semanas")
      ind <- INDICADORES[[metrica()]]

      # Avance es la tarjeta de siempre; los tres indicadores comparten forma y
      # solo se diferencian en la formula que les pasa INDICADORES.
      if (is.null(ind)) {
        serie <- seg_serie(deps, sin_marco = sin_filtro())
        meta  <- sum(a$planeado)
        if (sem) {
          grafico_semanas(seg_semanas(serie, desde = inicio_campo()), meta,
                          seg_ultimo_envio(deps), control = ctrl)
        } else {
          grafico_acumulado(serie, meta, control = ctrl)
        }
      } else {
        per <- seg_periodos(seg_serie_indicadores(deps, sin_marco = sin_filtro()),
                            por = if (sem) "semana" else "dia",
                            desde = inicio_campo())
        grafico_indicador(per, ind, marco = seg_marco_total(deps),
                          por = if (sem) "semana" else "dia", control = ctrl)
      }
    })

    # --- quien no contesto, por dia de citacion ------------------------------
    # Se elige un dia y salen las personas citadas ese dia que HOY siguen sin
    # ningun envio (seg_citados_dia()). Va sobre toda la universidad, pero
    # respeta el filtro de unidad de la barra de arriba, que es el de
    # toda la pestana.
    #
    # El selector de dia se dibuja con los datos --sus opciones son los dias que
    # existen-- y guarda lo elegido aparte: al recargar la agenda o cambiar un
    # filtro, el dia sigue puesto si todavia existe.
    dia_elegido <- reactiveVal(NULL)
    observeEvent(input$dia, dia_elegido(input$dia))

    dias_citados <- reactive({
      r$citaciones
      r$respuestas
      seg_dias_citados(input$tipos)
    })

    dia_actual <- reactive({
      d <- dias_citados()
      if (nrow(d) == 0) return(NULL)
      elegido <- dia_elegido()
      if (!is.null(elegido) && elegido %in% as.character(d$dia)) elegido
      else as.character(d$dia[1])
    })

    # Que recuadros plegables estan abiertos. Se leen AISLADOS en los render: el
    # navegador ya abre y cierra el <details> por su cuenta, y lo que hace falta
    # es recordarlo para la proxima vez que se redibuje.
    abiertos <- reactiveValues()
    observeEvent(input$plegar, {
      x <- strsplit(input$plegar, "|", fixed = TRUE)[[1]]
      if (length(x) >= 2) abiertos[[x[1]]] <- identical(x[2], "1")
    })

    output$citados_dia <- renderUI({
      d <- dias_citados()
      if (nrow(d) == 0) return(NULL)
      etiquetas <- sprintf("%s · %s sin responder de %s citadas",
                           format(d$dia, "%d/%m/%Y"), fmt_num(d$sin_responder),
                           fmt_num(d$citados))
      card_plegable(
        "citados_dia", isolate(abiertos$citados_dia),
        "Quién no contestó, por día de citación",
        # Plegado no es escondido: la cabecera dice como va el ultimo dia.
        sprintf("· último día %s: %s sin responder de %s citadas",
                format(d$dia[1], "%d/%m/%Y"), fmt_num(d$sin_responder[1]),
                fmt_num(d$citados[1])),
        div(class = "dia-barra",
            div(class = "dia-selector",
                selectInput(ns("dia"), "Día de la citación", width = "100%",
                            selectize = FALSE,
                            choices = stats::setNames(as.character(d$dia), etiquetas),
                            selected = dia_actual())),
            div(class = "small text-muted",
                "Citadas ese día que todavía no han enviado nada. ",
                "Respeta el filtro de unidad de arriba.")),
        uiOutput(ns("tabla_dia"))
      )
    })

    citados_del_dia <- reactive({
      dia <- dia_actual()
      req(dia)
      r$citaciones
      r$respuestas
      # Tambien cuando se registra un contacto: la columna "Ultimo contacto" de
      # este recuadro sale de la bitacora, y sin esta dependencia seguia
      # diciendo "Sin contactar" hasta recargar la pagina. `recarga_cto` se
      # declara mas abajo, con lo demas de la bitacora; para cuando esta
      # reactiva se evalua, ya existe.
      recarga_cto()
      seg_citados_dia(dia, input$tipos)
    })

    output$tabla_dia <- renderUI({
      dia <- dia_actual()
      req(dia)
      p <- citados_del_dia()
      if (nrow(p) == 0) {
        return(alerta(sprintf("Todas las personas citadas el %s ya enviaron algo.",
                              format(as.Date(dia), "%d/%m/%Y")), "success"))
      }
      tagList(
        div(class = "d-flex flex-wrap justify-content-between align-items-center gap-2 mb-2",
            span(class = "small text-muted",
                 sprintf("%s personas citadas el %s siguen sin responder, en %s dependencias.",
                         fmt_num(nrow(p)), format(as.Date(dia), "%d/%m/%Y"),
                         fmt_num(length(unique(p$dependencia))))),
            downloadButton(ns("bajar_dia"), "Descargar Excel",
                           class = "btn-sm btn-outline-secondary")),
        tabla_citados_dia(p, borrar = auth_puede(r$usuario$rol, "borrar_personas"))
      )
    })

    output$bajar_dia <- downloadHandler(
      filename = function() {
        sprintf("sin_responder_%s.xlsx", gsub("-", "", dia_actual() %||% "dia"))
      },
      content = function(archivo) {
        p <- citados_del_dia()
        salida <- data.frame(
          dia_citacion     = rep(dia_actual(), nrow(p)),
          id_anonimizado   = p$id_anonimizado,
          nombre           = p$nombre %||% NA_character_,
          dependencia      = p$dependencia,
          tipo_vinculacion = p$tipo_vinculacion,
          franjas          = p$franjas,
          link             = ifelse(is.na(p$link), "", p$link),
          veces_citada     = p$citaciones,
          contactos        = p$contactos,
          ultimo_contacto  = fmt_fecha(p$ultimo_contacto, vacio = ""),
          ultimo_resultado = ifelse(is.na(p$ultimo_resultado), "",
                                    cto_resultado_txt(p$ultimo_resultado)),
          stringsAsFactors = FALSE
        )
        escribir_excel(salida, archivo)
      }
    )

    # Viven dentro de un <details> plegado. Shiny no dibuja una salida oculta, y
    # abrir un <details> no le avisa de que ya se ve: sin esto el recuadro se
    # desplegaba en blanco.
    for (sal in c("tabla_dia", "bajar_dia")) {
      outputOptions(output, sal, suspendWhenHidden = FALSE)
    }

    # --- quien respondio sin estar en el marco -------------------------------
    # Ver seg_crear_marco_completo(). Cada vez que llegan respuestas se da de
    # alta a los nuevos; la lista trae a todos, completos o no, para que se vea
    # que paso con cada uno.
    no_registrados <- reactive({
      r$respuestas
      tryCatch(seg_sincronizar_no_registrados(), error = function(e) NULL)
      seg_no_registrados()
    })

    output$no_registrados <- renderUI({
      # Con INCLUIR_NO_REGISTRADOS=no no cuentan en ninguna parte: completarlos
      # no cambiaria nada, asi que la lista no se ofrece.
      if (!seg_incluir_no_registrados()) return(NULL)
      p <- no_registrados()
      if (nrow(p) == 0) return(NULL)
      pendientes <- sum(is.na(p$completado_en))
      card_plegable(
        "no_registrados", isolate(abiertos$no_registrados),
        "Personas que respondieron sin estar en el marco",
        sprintf("· etapa %s · %s", seg_etapa(),
                if (pendientes > 0) sprintf("%s de %s por completar",
                                            fmt_num(pendientes), fmt_num(nrow(p)))
                else "todas completas"),
        div(class = "small text-muted mb-2",
            "Contestaron la encuesta pero su cédula no está en el marco muestral. ",
            "Mientras no se completen su dependencia, tipo de vinculación y nivel ",
            "del empleo, no cuentan en el avance ni aparecen en Resultados. ",
            tags$b("Una vez guardados, los datos quedan fijos.")),
        div(class = "small mb-2",
            if (pendientes > 0)
              sprintf("%s de %s por completar.", fmt_num(pendientes), fmt_num(nrow(p)))
            else "Todas tienen los datos completos."),
        tabla_no_registrados(p, borrar = auth_puede(r$usuario$rol, "borrar_personas"))
      )
    })

    nr_actual <- reactiveVal(NULL)
    nr_opciones <- reactiveVal(NULL)

    observeEvent(input$nr_completar, {
      p <- no_registrados()
      f <- p[p$id_anonimizado == input$nr_completar, , drop = FALSE]
      req(nrow(f) == 1)
      if (!is.na(f$completado_en)) {
        showNotification("Los datos de esta persona ya están completos y quedaron fijos.",
                         type = "warning")
        return()
      }
      nr_actual(f$id_anonimizado)
      output$nr_aviso <- renderUI(NULL)
      op <- seg_opciones_no_registrados()
      nr_opciones(op)
      showModal(modal_no_registrado(ns, f, op))
    })

    # La unidad se muestra al elegir la dependencia: no se pregunta, se deriva.
    output$nr_unidad <- renderUI({
      op <- nr_opciones()
      dep <- input$nr_dependencia
      req(op, dep)
      u <- op$dependencia$unidad[match(dep, op$dependencia$dependencia)]
      if (!is.na(u)) div(class = "small text-muted mb-3", "Unidad: ", tags$b(u))
    })

    observeEvent(input$nr_guardar, {
      id <- nr_actual()
      req(id)
      quien <- if (!is.null(r$usuario)) r$usuario$usuario else NA_character_
      res <- tryCatch({
        seg_completar_no_registrado(id, input$nr_dependencia, input$nr_tipo_vinculacion,
                                    input$nr_nivel_empleo, quien)
        NULL
      }, error = function(e) conditionMessage(e))
      if (!is.null(res)) {
        output$nr_aviso <- renderUI(alerta(res, "warning"))
        return()
      }
      removeModal()
      nr_actual(NULL)
      showNotification("Datos guardados. La persona ya cuenta en el avance y en Resultados.",
                       type = "message")
      # Rehace esta lista y el avance, el detalle y los indicadores, que leen
      # marco_completo.
      r$respuestas <- isolate(r$respuestas) + 1
    })

    # --- borrar personas -------------------------------------------------------
    # Solo el administrador (permiso `borrar_personas`), que se vuelve a leer de
    # la base en cada paso: el boton se dibuja segun el rol de la ficha, pero un
    # input se puede mandar a mano. Ver seg_borrar_persona().
    puede_borrar <- function() isTRUE(tryCatch(
      auth_puede_usuario(r$usuario$usuario, "borrar_personas"),
      error = function(e) FALSE))
    borrar_actual <- reactiveVal(NULL)

    observeEvent(input$borrar, {
      b <- input$borrar
      req(b$id)
      if (!puede_borrar()) {
        showNotification("No tiene permiso para borrar personas.", type = "error")
        return()
      }
      p <- tryCatch(if (identical(b$origen, "no_registrados")) no_registrados()
                    else citados_del_dia(), error = function(e) NULL)
      nombre <- if (is.null(p)) NA_character_
                else p$nombre[match(b$id, p$id_anonimizado)]
      borrar_actual(list(id = b$id, nombre = nombre, origen = b$origen))
      showModal(modal_borrar(ns, b$id, nombre))
    })

    observeEvent(input$borrar_ok, {
      b <- borrar_actual()
      req(b)
      removeModal()
      borrar_actual(NULL)
      if (!puede_borrar()) {
        showNotification("No tiene permiso para borrar personas.", type = "error")
        return()
      }
      res <- tryCatch({
        seg_borrar_persona(b$id, b$nombre, b$origen, r$usuario$usuario)
        NULL
      }, error = function(e) conditionMessage(e))
      if (!is.null(res)) {
        showNotification(paste("No se pudo borrar:", res), type = "error")
        return()
      }
      try(auth_bitacora("persona_borrada", r$usuario$usuario,
                        sprintf("%s, desde %s", b$id, SEG_BORRADA_ORIGEN[b$origen] %||% b$origen),
                        r$usuario$origen %||% NA_character_), silent = TRUE)
      showNotification(paste("Persona borrada: ya no cuenta en el seguimiento.",
                             "Se puede restaurar desde Administración."), type = "message")
      SEG_BORRADAS(SEG_BORRADAS() + 1)
      # Rehace el avance, los indicadores y los dos recuadros. Los grupos de
      # Citaciones se releen solos cada minuto.
      r$respuestas <- isolate(r$respuestas) + 1
    })

    # --- listado: tabla o tarjetas -------------------------------------------

    # Resumen de lo que se esta viendo. Evita el error de leer un total filtrado
    # como si fuera el global, y anuncia el cambio a un lector de pantalla.
    # El total sin filtros no cambia mientras dure la sesion: se consulta aparte
    # para no pegarle a la base con cada tecla del buscador.
    total_dependencias <- reactive({
      nrow(seg_avance())
    })

    output$resumen <- renderUI({
      a <- avance_filtrado()
      div(
        class = "resumen-listado",
        role  = "status",
        span(sprintf("Mostrando %s de %s dependencias", nrow(a), total_dependencias())),
        span(class = "sep", "\u00b7"),
        span(sprintf("%s personas pendientes", fmt_num(sum(a$faltan))))
      )
    })

    output$listado <- renderUI({
      a <- avance()
      if (nrow(a) == 0) {
        return(div(class = "alert alert-secondary",
                   "Ninguna dependencia coincide con el filtro."))
      }
      sel <- seleccionada()
      if (identical(input$vista_lista %||% "listado", "semaforo")) {
        return(mosaico_semaforo(a, sel))
      }
      if (nrow(a) <= UMBRAL_TARJETAS) rejilla_tarjetas(a, sel) else tabla_dependencias(a, sel)
    })

    # Ordenar pulsando una cabecera: se limita a mover el selectInput, asi que
    # el criterio queda visible en el filtro y no hay dos estados que sincronizar.
    observeEvent(input$ordenar_por, {
      updateSelectInput(session, "orden", selected = input$ordenar_por)
    })

    observeEvent(input$dep_click, {
      seleccionada(input$dep_click)
    })

    # --- detalle de la dependencia -------------------------------------------

    output$detalle <- renderUI({
      dep <- seleccionada()
      if (is.null(dep)) {
        return(div(class = "text-muted small mt-3",
                   "Haga clic en una dependencia para ver el detalle."))
      }
      d <- detalle_dat()
      if (nrow(d$cabecera) == 0) return(NULL)
      cab <- d$cabecera[1, ]
      cmp <- d$campo[1, ]
      planeado <- if (nrow(d$meta)) d$meta$planeado[1] else cab$elegibles
      # Mismo descuento que seg_avance(): los casos cerrados por la bitacora
      # no son pendientes.
      faltan   <- max(0, planeado - cab$encuestados - cab$cerrados)
      pct      <- if (planeado > 0) round(100 * cab$encuestados / planeado, 1) else 0

      tabla <- function(df, rotulo) {
        if (is.null(df) || nrow(df) == 0) return(NULL)
        df$avance <- ifelse(df$elegibles > 0,
                            fmt_pct(round(100 * df$encuestados / df$elegibles, 1)), "\u2014")
        tags$table(
          class = "table table-sm tabla-detalle",
          tags$thead(tags$tr(tags$th(rotulo), tags$th("Elegibles"),
                             tags$th("Encuestados"), tags$th("Avance"))),
          tags$tbody(lapply(seq_len(nrow(df)), function(i) tags$tr(
            tags$td(df$categoria[i]), tags$td(df$elegibles[i]),
            tags$td(df$encuestados[i]), tags$td(df$avance[i]))))
        )
      }

      n_resp <- cmp$n %||% 0

      g <- grupos_personas(personas())

      div(
        class = "mt-4",
        navset_card_tab(
          id = ns("pestana"),
          title = div(
            class = "d-flex justify-content-between align-items-start gap-3 w-100",
            div(
              div(strong(cab$dependencia)),
              # Solo lo que el marco trae: con el export de nomina, municipio
              # y centro de costo vienen vacios, y el subtitulo decia
              # "NA · centro NA".
              local({
                partes <- c(cab$tipo_dependencia, cab$municipio,
                            if (!is.na(cab$centro_costo)) paste("centro", cab$centro_costo))
                partes <- partes[!is.na(partes)]
                if (length(partes))
                  div(class = "text-muted small fw-normal", paste(partes, collapse = " · "))
              })
            ),
            actionButton(ns("cerrar"), "Cerrar",
                         class = "btn-sm btn-outline-secondary flex-shrink-0")
          ),

          nav_panel(
            title = "Avance",

            # Misma fila que la de arriba y con los mismos cajones, para que
            # leer una dependencia sea leer lo mismo que el total pero en
            # pequeno: si el detalle mostrara otras cifras, compararlo con la
            # cabecera obligaria a traducir.
            div(class = "kpi-fila mb-3",
                div(class = "kpi-caja", div(class = "kpi-valor", fmt_num(planeado)),
                    div(class = "kpi-etiqueta", "Esperados")),
                div(class = "kpi-caja",
                    div(class = "kpi-valor text-success", fmt_num(cab$encuestados)),
                    div(class = "kpi-etiqueta", "Encuestados")),
                caja_forma("A", d$indicadores$A$encuestados, d$indicadores$A),
                caja_forma("B", d$indicadores$B$encuestados, d$indicadores$B),
                div(class = "kpi-caja", div(class = "kpi-valor text-danger", fmt_num(faltan)),
                    div(class = "kpi-etiqueta", "Faltan")),
                caja_indicador("Efectividad",         d$indicadores$total$efectividad,
                               d$indicadores$total$efectivas,   "aceptaron"),
                caja_indicador("No efectivas",        d$indicadores$total$pct_no_efectivas,
                               d$indicadores$total$no_efectivas, "no aceptaron"),
                caja_indicador("Cobertura Citados",   d$indicadores$total$cob_citados,
                               d$indicadores$total$encuestados, "encuestadas",
                               d$indicadores$total$citados, "citadas"),
                caja_indicador("Cobertura Esperados", d$indicadores$total$cob_esperados,
                               d$indicadores$total$encuestados, "encuestadas")),

            # La barra se queda, pero el cajon de "Avance" ya no esta para
            # rotularla: el porcentaje va ahora a su lado, y la barra declara lo
            # suyo con los atributos ARIA en vez de apoyarse en el cajon vecino.
            div(class = "d-flex align-items-center gap-2 mb-3",
                div(class = "progress flex-grow-1", style = "height: 10px;",
                    role = "progressbar", `aria-valuenow` = pct,
                    `aria-valuemin` = 0, `aria-valuemax` = 100,
                    `aria-label` = paste("Avance de", cab$dependencia),
                    div(class = "progress-bar",
                        style = sprintf("width:%s%%;", min(100, pct)))),
                span(class = "small text-muted",
                     sprintf("Avance %s", fmt_pct(pct)))),

            h6("Cómo va la encuesta"),
            tags$ul(
              class = "small",
              tags$li(sprintf("Respuestas recibidas: %s", fmt_num(n_resp %||% 0))),
              tags$li(sprintf("Duración media: %s minutos", fmt_num(cmp$duracion_media, 1))),
              tags$li(sprintf("Primera respuesta: %s", fmt_momento(cmp$primera) %||% "—")),
              tags$li(sprintf("Última respuesta: %s", fmt_momento(cmp$ultima) %||% "—"))
            ),

            # Output aparte, como la tabla de personas: cambiar de minipestana
            # no puede rehacer la tarjeta entera, que devolveria la pestana
            # "Personas" a "Avance" mientras se la esta mirando.
            uiOutput(ns("grafico_det")),

            hr(),
            layout_columns(
              col_widths = c(6, 6),
              tabla(d$por_forma, "Forma del cuestionario"),
              tabla(d$por_estado, "Estado de la vinculación")
            )
          ),

          # El desplegable se redibuja con la dependencia, así que vuelve solo a
          # "Faltan" al cambiar de unidad. La tabla es un output aparte para que
          # cambiar de grupo no rehaga la tarjeta entera (que reiniciaría el
          # desplegable que acabas de mover).
          nav_panel(
            title = sprintf("Personas (%s)", g$elegibles),

            div(
              class = "personas-barra",
              div(class = "personas-selector",
                  selectInput(ns("grupo"), "Mostrar",
                              choices  = opciones_personas(g),
                              selected = "faltan",
                              width    = "100%")),
              downloadButton(ns("bajar"), "Descargar Excel",
                             class = "btn-sm btn-outline-secondary")
            ),

            # Output aparte del de la tabla: lleva el contador de marcadas, asi
            # que se redibuja con cada clic en una casilla. Si viviera dentro de
            # la tabla, cada clic la rehria entera y borraria las casillas que
            # se acaban de marcar.
            uiOutput(ns("barra_contacto")),
            uiOutput(ns("tabla_personas"))
          )
        )
      )
    })

    observeEvent(input$cerrar, seleccionada(NULL))

    # Una sola consulta del detalle para la tarjeta y para su grafico.
    detalle_dat <- reactive({
      dep <- seleccionada()
      req(dep)
      r$respuestas
      seg_detalle(dep)
    })

    vista_det <- reactiveVal("linea")
    observeEvent(input$vista_det, vista_det(input$vista_det))

    # Mismas dos vistas que arriba, con la meta de ESTA dependencia: la de la
    # tabla `metas` si esta editada, y si no sus elegibles, que es el mismo
    # respaldo que usa seg_avance().
    output$grafico_det <- renderUI({
      d   <- detalle_dat()
      cab <- d$cabecera
      if (nrow(cab) == 0) return(NULL)
      meta <- if (nrow(d$meta)) d$meta$planeado[1] else cab$elegibles[1]
      ctrl <- selector_vista(ns("vista_det"), vista_det())
      if (identical(vista_det(), "semanas")) {
        grafico_semanas(seg_semanas(d$serie, desde = inicio_campo()), meta,
                        seg_ultimo_envio(cab$dependencia[1]), control = ctrl)
      } else {
        grafico_acumulado(d$serie, meta, control = ctrl)
      }
    })

    # --- pestaña de personas -------------------------------------------------
    # Una sola consulta por dependencia, compartida por el conteo del
    # desplegable, la tabla y la descarga.

    personas <- reactive({
      dep <- seleccionada()
      req(dep)
      r$citaciones
      r$respuestas
      seg_personas(dep)
    })

    # --- bitacora de contactos -----------------------------------------------
    # La lista de personas y la de contactos se consultan por separado y se
    # cruzan en R: personas() depende de la dependencia y contactos() ademas de
    # recarga_cto(), asi que registrar un contacto no vuelve a pedir el marco.
    recarga_cto <- reactiveVal(0)

    contactos <- reactive({
      dep <- seleccionada()
      req(dep)
      recarga_cto()
      cto_resumen_dependencia(dep)
    })

    # La lista con la que trabaja toda la pestana: es la del marco mas lo que
    # diga la bitacora (ver cto_aplicar()).
    personas_ctc <- reactive(cto_aplicar(personas(), contactos()))

    # Lo que el navegador reporta marcado. Se guarda aparte del input para poder
    # vaciarlo desde el servidor cuando la tabla se rehace.
    marcadas <- reactiveVal(character(0))
    observeEvent(input$seleccion,
                 marcadas(as.character(unlist(input$seleccion))),
                 ignoreNULL = FALSE)

    # Solo cuenta lo que sigue a la vista: si se cambia de grupo o de
    # dependencia con casillas marcadas, esas casillas ya no estan en pantalla y
    # no pueden seguir contando.
    seleccion <- reactive({
      vis <- filtrar_personas(personas_ctc(), grupo_activo())$id_anonimizado
      intersect(marcadas(), as.character(vis))
    })

    # Los conteos del desplegable se dibujan con la tarjeta del detalle, que no
    # se rehace al registrar un contacto: hay que refrescarlos aparte o quedarian
    # diciendo "Faltan (74)" mientras la tabla ya muestra 73.
    observeEvent(personas_ctc(), {
      updateSelectInput(session, "grupo",
                        choices  = opciones_personas(grupos_personas(personas_ctc())),
                        selected = grupo_activo())
    })

    # En "Casos cerrados" la barra hace lo contrario que en los pendientes: no
    # registra un contacto, reabre. Es la misma barra para que la seleccion se
    # use igual en los tres grupos.
    output$barra_contacto <- renderUI({
      g <- grupo_activo()
      if (!g %in% c("faltan", "citados", "cerrados")) return(NULL)
      n <- length(seleccion())
      quienes <- if (n == 1) "1 persona" else paste(n, "personas")
      reabre <- identical(g, "cerrados")
      div(
        class = "barra-contacto",
        if (reabre)
          actionButton(ns("reabrir_lote"),
                       if (n > 0) sprintf("Reabrir el caso a %s", quienes) else "Reabrir caso",
                       icon = icon("rotate-left"),
                       class = "btn-sm btn-primary", disabled = if (n == 0) NA)
        else
          actionButton(ns("contactar_lote"),
                       if (n > 0) sprintf("Registrar contacto a %s", quienes)
                       else "Registrar contacto",
                       class = "btn-sm btn-primary", disabled = if (n == 0) NA),
        span(class = "text-muted small",
             if (reabre) {
               if (n > 0) "Vuelven a «Faltan» y el seguimiento sigue como con cualquier pendiente."
               else "Marque personas con las casillas, o use el botón Reabrir de cada fila."
             } else {
               if (n > 0) "Se guardará el mismo contacto para todas las marcadas."
               else "Marque personas con las casillas, o use el botón de cada fila."
             })
      )
    })

    aviso_cto <- reactiveVal(NULL)
    output$cto_aviso <- renderUI(alerta(aviso_cto(), "warning"))
    destinatarios <- reactiveVal(character(0))

    # La misma ventana sirve para registrar un contacto y para reabrir un caso;
    # lo que cambia es que al guardar se llama a cto_registrar() o a
    # cto_reabrir(). Se recuerda aqui porque el boton de guardar es uno solo.
    modo_cto <- reactiveVal("contacto")

    abrir_contacto <- function(ids, modo = "contacto") {
      ids <- as.character(ids)
      if (length(ids) == 0) return(invisible(NULL))
      destinatarios(ids)
      modo_cto(modo)
      aviso_cto(NULL)
      # El contacto se abre desde dos tablas distintas (personas de la
      # dependencia y citados del dia), asi que el nombre se lee del marco.
      nombre <- if (length(ids) == 1) db_get(
        "SELECT nombre FROM seguimiento.marco_completo WHERE id_anonimizado = $1",
        params = list(ids))$nombre[1]
      showModal(modal_contacto(
        ns, ids, nombre = nombre,
        hist = if (length(ids) == 1) cto_historial(ids) else NULL,
        hoy  = seg_hoy(), modo = modo))
    }

    observeEvent(input$contactar, abrir_contacto(input$contactar))
    observeEvent(input$reabrir,   abrir_contacto(input$reabrir, "reabrir"))

    observeEvent(input$contactar_lote, {
      ids <- seleccion()
      if (length(ids) == 0) {
        showNotification("Marque al menos una persona.", type = "warning")
      } else {
        abrir_contacto(ids)
      }
    })

    observeEvent(input$reabrir_lote, {
      ids <- seleccion()
      if (length(ids) == 0) {
        showNotification("Marque al menos una persona.", type = "warning")
      } else {
        abrir_contacto(ids, "reabrir")
      }
    })

    observeEvent(input$cto_guardar, {
      ids <- destinatarios()
      quien <- if (!is.null(r$usuario)) r$usuario$usuario else NA_character_
      reabre <- identical(modo_cto(), "reabrir")
      n <- tryCatch(
        if (reabre) {
          cto_reabrir(ids, input$cto_medio, input$cto_otro, input$cto_obs, quien)
        } else {
          cto_registrar(ids, input$cto_fecha, input$cto_medio, input$cto_otro,
                        input$cto_obs, input$cto_resultado, quien)
        },
        error = function(e) { aviso_cto(conditionMessage(e)); NULL })

      if (!is.null(n)) {
        removeModal()
        marcadas(character(0))
        recarga_cto(recarga_cto() + 1)
        quienes <- if (n == 1) "1 persona" else paste(n, "personas")
        showNotification(
          if (reabre) sprintf("Caso reabierto para %s: vuelve%s a «Faltan».",
                              quienes, if (n == 1) "" else "n")
          else sprintf("Contacto registrado para %s.", quienes),
          type = "message")
      }
    })

    # Al cambiar de dependencia el selectInput se vuelve a dibujar, y en ese
    # parpadeo input$grupo todavía trae el valor anterior (que puede ser un grupo
    # que esta dependencia no ofrece). Se valida contra la lista y se cae a
    # "faltan", que es el valor inicial de todas formas.
    grupo_activo <- reactive({
      g <- input$grupo %||% "faltan"
      if (g %in% GRUPOS_PERSONAS) g else "faltan"
    })

    output$tabla_personas <- renderUI({
      p     <- personas_ctc()
      g     <- grupos_personas(p)
      grupo <- grupo_activo()
      sub   <- filtrar_personas(p, grupo)

      if (nrow(sub) == 0) {
        return(div(class = "alert alert-secondary mb-0", switch(
          grupo,
          faltan       = "Todas las personas elegibles de esta dependencia ya respondieron.",
          citados      = "Ninguna persona citada está pendiente de responder.",
          cerrados     = "No hay casos cerrados por el registro de contactos.",
          respondieron = "Todavía no hay ninguna respuesta en esta dependencia.",
          no_elegibles = "Todas las personas del marco están activas.",
          "Esta dependencia no tiene personas elegibles en el marco.")))
      }

      tagList(
        div(
          class = "resumen-listado",
          role  = "status",
          span(if (identical(grupo, "no_elegibles")) {
            sprintf("%s personas fuera del marco activo; no cuentan en el avance",
                    nrow(sub))
          } else {
            sprintf("Mostrando %s de %s personas elegibles", nrow(sub), g$elegibles)
          }),
          # El rotulo del grupo dice "Respondieron", pero ahi dentro hay tres
          # cosas distintas: hay que decir cuantas son de cada una.
          if (identical(grupo, "respondieron") &&
              (g$rechazos > 0 || g$ausentes > 0)) {
            tagList(span(class = "sep", "·"),
                    span(sprintf("%s efectivas, %s rechazos, %s ausentes",
                                 g$efectivas, g$rechazos, g$ausentes)))
          }
        ),
        tabla_personas(sub, grupo)
      )
    })

    # Se baja lo que está en pantalla, con el mismo filtro.
    output$bajar <- downloadHandler(
      filename = function() {
        sprintf("personas_%s_%s_%s.xlsx",
                gsub("[^a-z0-9]+", "_", to_key(seleccionada() %||% "dependencia")),
                grupo_activo(), format(Sys.Date(), "%Y%m%d"))
      },
      content = function(archivo) {
        sub <- filtrar_personas(personas_ctc(), grupo_activo())
        salida <- data.frame(
          dependencia        = rep(seleccionada() %||% NA_character_, nrow(sub)),
          id_anonimizado     = sub$id_anonimizado,
          nombre             = sub$nombre %||% NA_character_,
          situacion          = unname(vapply(as.character(sub$situacion),
                                             function(s) situacion_persona(s)$txt, "")),
          # Una sola columna para todos los casos cerrados sin encuesta: el
          # rechazo del formulario, el rechazo anotado por un gestor y el
          # ausente. Cual de los tres fue lo dice `situacion`.
          no_participa       = ifelse(sub$situacion %in% CTO_CIERRES, "Sí", "No"),
          forma              = sub$forma,
          tipo_vinculacion   = sub$tipo_vinculacion,
          nivel_empleo       = sub$nivel_empleo,
          estado_vinculacion = sub$estado_vinculacion,
          dedicacion         = sub$dedicacion,
          modalidad_trabajo  = sub$modalidad_trabajo,
          fecha_respuesta    = fmt_momento_v(sub$submission_date, vacio = ""),
          contactos          = sub$contactos,
          ultimo_contacto    = fmt_fecha(sub$ultimo_contacto, vacio = ""),
          ultimo_medio       = vapply(seq_len(nrow(sub)), function(i)
                                 if (is.na(sub$ultimo_medio[i])) ""
                                 else cto_medio_txt(sub$ultimo_medio[i],
                                                    sub$ultimo_medio_otro[i]), ""),
          citacion_fecha     = fmt_fecha(sub$cita_fecha, vacio = ""),
          citacion_inicio    = ifelse(is.na(sub$cita_inicio), "", sub$cita_inicio),
          citacion_fin       = ifelse(is.na(sub$cita_fin), "", sub$cita_fin),
          citacion_link      = ifelse(is.na(sub$cita_link), "", sub$cita_link),
          citado_sin_responder = ifelse(citado_sin_responder(sub), "Sí", "No"),
          stringsAsFactors   = FALSE
        )
        escribir_excel(salida, archivo)
      }
    )

  })
}


# --- cajones de la fila de indicadores ----------------------------------------
# Los tres indicadores --Efectividad, Cobertura Citados y Cobertura Esperados--
# aparecen dos veces en esta fila y con dos formas distintas, porque contestan
# dos preguntas distintas:
#
#   en TOTAL, un cajon cada uno, con el porcentaje de numero grande. Ocupan el
#   sitio donde antes iba "Avance", que era la unica razon que la fila mostraba.
#
#   por FORMA, los tres juntos dentro del cajon de A y el de B, en letra chica,
#   debajo del numero grande de encuestados. Ahi no compiten con nada: sirven
#   para comparar A contra B de un vistazo, que es lo unico que se hace con
#   ellos.
#
# Los dos cajones grandes llevan el numero ademas del porcentaje, que es lo que
# se pidio: el porcentaje dice como va y el numero dice de cuanta gente habla.
# Sin el, un 62,5% no distingue 5 personas de 1.593.
#
# Las cifras salen de seg_totales_indicadores() y no se recalculan aqui: la
# fila, el grafico de Efectividad y la vista estado_persona tienen que decir el
# mismo numero, y la unica forma de garantizarlo es que haya un solo sitio donde
# se divida.

# Cajon de un indicador en total: porcentaje grande, nombre, y el numerador
# debajo con lo que cuenta. `unidad` nombra a las personas del numerador
# --"efectivas", "encuestadas"-- porque no son las mismas en los tres.
# Con `den`, el pie dice tambien sobre que se divide ("36 encuestadas" y debajo
# "40 citadas"), para que el porcentaje se pueda rehacer a mano. Va en una
# linea aparte: .kpi-pie no parte el texto y en una sola se salia del cajon.
caja_indicador <- function(nombre, pct, num, unidad, den = NULL, den_unidad = NULL) {
  div(
    class = "kpi-caja",
    div(class = "kpi-valor", fmt_pct(pct)),
    div(class = "kpi-etiqueta", nombre),
    div(class = "kpi-pie", sprintf("%s %s", fmt_num(num), unidad)),
    if (!is.null(den)) div(class = "kpi-pie", sprintf("%s %s", fmt_num(den), den_unidad))
  )
}

# Recuadro que nace PLEGADO y se despliega con un clic en la cabecera. Es una
# tarjeta de Bootstrap con un <details> dentro: la cabecera es el <summary>.
# `abierto` es lo que el usuario dejo la ultima vez (ver input$plegar), para
# que un redibujo no lo cierre. `resumen` va al lado del titulo, para que
# plegado no sea escondido.
card_plegable <- function(id, abierto, titulo, resumen = NULL, ...) {
  div(class = "card shadow-sm mb-3",
      tags$details(
        class = "seg-pleg", `data-plegable` = id,
        open = if (isTRUE(abierto)) NA,
        tags$summary(class = "card-header seg-pleg-sum",
                     tags$b(titulo),
                     if (!is.null(resumen)) span(class = "text-muted small", resumen)),
        div(class = "card-body", ...)))
}

# Cajon de una forma del cuestionario: el numero grande sigue siendo cuanta
# gente de esa forma se ha encuestado --en verde, como el cajon de
# "Encuestados", del que A y B son el desglose-- y debajo van Efectividad y
# Cobertura Esperados de ESA forma, cada uno con su porcentaje y su numero.
# La Cobertura Citados no va: los citados fuera del marco no tienen forma, asi
# que A y B no suman los citados del total (ver SEG_CIT_SIN_MARCO).
#
# El porcentaje va antes que el numero y los dos en columnas alineadas, para que
# las filas del cajon de A se comparen con las del de B leyendo en vertical,
# sin tener que buscar donde empieza cada cifra.
caja_forma <- function(letra, encuestados, ind) {
  linea <- function(nombre, pct, num) div(
    class = "kpi-linea",
    span(class = "kpi-linea-nom", nombre),
    span(class = "kpi-linea-pct", fmt_pct(pct)),
    span(class = "kpi-linea-num", fmt_num(num)))

  div(
    class = "kpi-caja kpi-caja-forma",
    div(class = "kpi-valor text-success", fmt_num(encuestados)),
    div(class = "kpi-etiqueta", paste("Forma", letra)),
    div(class = "kpi-indicadores",
        linea("Efectividad",    ind$efectividad,   ind$efectivas),
        linea("Cob. Esperados", ind$cob_esperados, ind$encuestados))
  )
}


# --- formas del listado -------------------------------------------------------
# Viven fuera del server porque no tocan reactivos: reciben un data.frame y
# devuelven etiquetas. Asi se pueden probar sueltas.

# Rejilla de tarjetas: pocas unidades, con sitio para detalle.
rejilla_tarjetas <- function(a, sel = NULL) {
  tarjetas <- lapply(seq_len(nrow(a)), function(i) {
    f <- a[i, ]
    e <- estado_avance(f$avance)
    div(
      class = paste("tarjeta-dep", e$cls, if (identical(sel, f$dependencia)) "activa"),
      `data-dep` = f$dependencia,
      tabindex = "0",
      role = "button",
      `aria-pressed` = tolower(identical(sel, f$dependencia)),
      `aria-label` = sprintf("%s. Avance %s%%. %s de %s encuestados, faltan %s.",
                             f$dependencia, f$avance, f$encuestados,
                             f$planeado, f$faltan),

      div(class = "tarjeta-titulo", f$dependencia),
      div(class = "tarjeta-sede",
          chip_estado(e)),

      div(class = "progress tarjeta-barra", role = "progressbar",
          `aria-valuenow` = f$avance, `aria-valuemin` = 0, `aria-valuemax` = 100,
          `aria-label` = paste("Avance de", f$dependencia),
          div(class = "progress-bar", style = sprintf("width: %s%%;", min(100, f$avance)))),

      div(class = "tarjeta-cifras",
          div(span(class = "cifra", f$planeado),    span(class = "rotulo", "Planeado")),
          div(span(class = "cifra text-success", f$encuestados), span(class = "rotulo", "Encuestados")),
          div(span(class = "cifra text-danger",  f$faltan),      span(class = "rotulo", "Faltan"))),

      div(class = "tarjeta-avance", fmt_pct(f$avance))
    )
  })
  div(class = "rejilla-dep", tarjetas)
}

# Tabla: muchas unidades, para comparar. Los numeros alineados en columna se
# comparan mirando; en tarjetas hay que leerlos uno a uno.
tabla_dependencias <- function(a, sel = NULL) {
  max_falt <- max(a$faltan, 1)

  cabecera <- function(col, rotulo, der = FALSE) {
    tags$th(
      scope = "col", class = if (der) "der",
      tags$button(type = "button", `data-col` = col, rotulo)
    )
  }

  filas <- lapply(seq_len(nrow(a)), function(i) {
    f <- a[i, ]
    e <- estado_avance(f$avance)
    p <- prioridad_pendientes(f$faltan)
    tags$tr(
      class = paste("fila-dep", if (identical(sel, f$dependencia)) "activa"),
      `data-dep` = f$dependencia,
      tabindex = "0",
      `aria-label` = sprintf("%s. Avance %s%%. Faltan %s personas de %s.",
                             f$dependencia, f$avance, f$faltan, f$planeado),

      tags$td(class = "col-dep", f$dependencia),
      tags$td(
        div(class = "col-avance",
            div(class = paste("pista", e$cls), role = "img",
                `aria-label` = sprintf("Avance %s por ciento", f$avance),
                div(class = "relleno", style = sprintf("width:%s%%;", min(100, f$avance)))),
            span(class = "valor", fmt_pct(f$avance)))
      ),
      tags$td(class = "der col-enc", sprintf("%s / %s", f$encuestados, f$planeado)),
      tags$td(
        class = "der",
        div(class = "col-pend",
            span(class = paste("chip", p$cls), title = paste("Prioridad", p$txt),
                 span(`aria-hidden` = "true", p$sig),
                 span(class = "visually-hidden", paste("Prioridad", p$txt))),
            span(class = "esfuerzo",
                 style = sprintf("width:%spx;", max(3, round(46 * f$faltan / max_falt)))),
            span(class = "valor", f$faltan))
      )
    )
  })

  div(
    class = "tabla-dep-caja",
    tags$table(
      class = "tabla-dep",
      tags$caption(class = "visually-hidden",
                   "Avance de la aplicacion por dependencia. Pulse una fila para ver el detalle."),
      tags$thead(tags$tr(
        cabecera("dependencia", "Dependencia"),
        cabecera("avance", "Avance"),
        cabecera("encuestados", "Encuestados", der = TRUE),
        cabecera("faltan", "Pendientes", der = TRUE)
      )),
      tags$tbody(filas),
      tags$tfoot(tags$tr(
        tags$td(colspan = "2",
                sprintf("%s dependencias", nrow(a))),
        tags$td(class = "der", sprintf("%s / %s",
                                       fmt_num(sum(a$encuestados)),
                                       fmt_num(sum(a$planeado)))),
        tags$td(class = "der", fmt_num(sum(a$faltan)))
      ))
    )
  )
}


# --- semaforo del avance ------------------------------------------------------
# Otra lectura del mismo listado, para la pregunta que la tabla contesta despacio:
# cuantas dependencias estan en rojo y cuales son. Cada unidad es un mosaico del
# color de su estado, y arriba van los tres faroles con el recuento.
#
# Los umbrales y los rotulos NO se definen aqui: salen de estado_avance()
# (helpers.R), que es el mismo que pinta el borde de las tarjetas y el chip de
# la tabla. Si algun dia se mueve el corte del 90% o del 60%, se mueve en un solo
# sitio y las tres vistas cambian juntas.
#
# El color sale de color_avance() (helpers.R): un degradado continuo rojo ->
# amarillo -> verde, no tres cajones. Asi una dependencia que sube del 62% al 78%
# se ve subir, en vez de quedarse del mismo color hasta cruzar un umbral. El
# color del texto de encima lo elige texto_sobre() midiendo el contraste, no a
# ojo: sobre el rojo y el verde va blanco, sobre el amarillo y los verdes claros
# va oscuro, y en toda la rampa queda por encima del 4,5:1 de la WCAG.
#
# Y como en el resto del modulo, el estado no viaja solo en el color: cada
# mosaico lleva tambien su simbolo y su palabra.

# Los tres estados en el orden en que se leen, lo urgente primero, cada uno con
# el color de su extremo de la rampa. Los rotulos y los umbrales se le piden a
# estado_avance(), y se le piden CON SUS PROPIOS CORTES: un 0, un 75 y un 100
# escritos a mano acertaban de casualidad, y habrian dejado de acertar en
# cuanto los cortes se movieran.
SEMAFORO <- list(
  list(e = estado_avance(0),                  col = SEMAFORO_ROJO),
  list(e = estado_avance(AVANCE_CORTE_MEDIO), col = SEMAFORO_AMARILLO),
  list(e = estado_avance(AVANCE_CORTE_BIEN),  col = SEMAFORO_VERDE)
)

pintar <- function(col) sprintf("background:%s;color:%s;", col, texto_sobre(col))

faroles_semaforo <- function(a) {
  cls <- vapply(a$avance, function(v) estado_avance(v)$cls, "")

  # La escala se dibuja muestreando la MISMA funcion que pinta los mosaicos, en
  # vez de repetir los colores en el CSS: no hay forma de que la leyenda y el
  # mosaico se desincronicen.
  paradas <- vapply(seq(0, 100, by = 5),
                    function(v) sprintf("%s %s%%", color_avance(v), v), "")

  tagList(
    div(
      class = "faroles",
      lapply(SEMAFORO, function(f) {
        q <- cls == f$e$cls
        n <- sum(q)
        div(
          class = "farol", style = pintar(f$col),
          div(class = "farol-luz", `aria-hidden` = "true", f$e$sig),
          div(
            div(class = "farol-nombre", f$e$txt),
            div(class = "farol-cifra",
                if (n == 1) "1 dependencia" else sprintf("%s dependencias", fmt_num(n))),
            div(class = "farol-pie",
                sprintf("%s personas pendientes", fmt_num(sum(a$faltan[q]))))
          )
        )
      })
    ),
    div(
      class = "semaforo-escala",
      span("0%"),
      div(class = "escala-barra", role = "img",
          `aria-label` = "Escala de color del avance, de rojo en cero a verde en cien por ciento",
          style = sprintf("background:linear-gradient(90deg,%s);",
                          paste(paradas, collapse = ","))),
      span("100%")
    )
  )
}


# Sigue el orden que pida el filtro de arriba, igual que la tabla: son la misma
# lista vista de otra manera, y dos ordenes distintos obligarian a buscar dos
# veces la misma dependencia.
mosaico_semaforo <- function(a, sel = NULL) {
  piezas <- lapply(seq_len(nrow(a)), function(i) {
    f <- a[i, ]
    e <- estado_avance(f$avance)
    div(
      class = paste("mosaico-dep", e$cls, if (identical(sel, f$dependencia)) "activa"),
      style = pintar(color_avance(f$avance)),
      `data-dep` = f$dependencia,
      tabindex = "0",
      role = "button",
      `aria-pressed` = tolower(identical(sel, f$dependencia)),
      `aria-label` = sprintf("%s. %s. Avance %s%%. %s de %s encuestados, faltan %s.",
                             f$dependencia, e$txt, f$avance, f$encuestados,
                             f$planeado, f$faltan),

      div(class = "mos-estado",
          span(`aria-hidden` = "true", e$sig), span(e$txt)),
      div(class = "mos-nombre", f$dependencia),
      div(class = "mos-pct", fmt_pct(f$avance)),
      div(class = "mos-pie",
          span(sprintf("%s / %s", f$encuestados, f$planeado)),
          span(sprintf("faltan %s", f$faltan)))
    )
  })

  tagList(
    faroles_semaforo(a),
    div(class = "mosaico", piezas),
    div(class = "grafico-nota",
        "Pulse una dependencia para ver el detalle.")
  )
}


# --- pestana de personas ------------------------------------------------------

# Opciones del desplegable, con el conteo en la etiqueta. Van de la poblacion
# completa al subconjunto; la seleccionada es "faltan", que es la pregunta
# operativa. Los no elegibles solo aparecen cuando los hay: una opcion con (0)
# es una opcion que estorba, y en la mayoria de dependencias no existe.
#
# Ojo con "Todos": son todos los ELEGIBLES. Los no elegibles quedan fuera de ese
# total a proposito, porque es el mismo denominador con el que el listado calcula
# el avance; si entraran aqui, los dos numeros no cuadrarian.
opciones_personas <- function(g) {
  op <- c("todos", "respondieron", "faltan")
  et <- c(sprintf("Todos los elegibles (%s)", g$elegibles),
          sprintf("Respondieron (%s)",        g$respondieron),
          sprintf("Faltan (%s)",              g$faltan))
  # Mismo criterio que los no elegibles: sin agenda cargada, o sin nadie citado
  # pendiente, la opcion no aparece.
  if (isTRUE(g$citados > 0)) {
    op <- c(op, "citados")
    et <- c(et, sprintf("Citados sin responder (%s)", g$citados))
  }
  # Los que cerro la bitacora, que son los que se pueden reabrir. Tambien estan
  # dentro de "Respondieron"; aqui van solos para poder marcarlos en lote.
  if (isTRUE(g$cerrados > 0)) {
    op <- c(op, "cerrados")
    et <- c(et, sprintf("Casos cerrados: rechazo o ausente (%s)", g$cerrados))
  }
  if (g$no_elegibles > 0) {
    op <- c(op, "no_elegibles")
    et <- c(et, sprintf("No elegibles (%s)", g$no_elegibles))
  }
  stats::setNames(op, et)
}

# Tabla de personas. Las columnas cambian con el grupo porque la pregunta
# cambia: quien busca pendientes necesita saber a quien buscar (vinculacion,
# nivel del empleo) y como va la gestion (cuantos contactos lleva, cuando fue el
# ultimo); quien revisa lo recibido necesita cuando llego y como.
# Hereda la caja y la cabecera pegajosa de .tabla-dep, pero sus filas no se
# pulsan: debajo de una persona no hay ningun detalle que abrir.
#
# Las casillas de seleccion solo salen en "Faltan" y en "Citados sin responder",
# que son los grupos donde el contacto en lote tiene sentido. El boton de contacto sale ademas en las
# filas que cerro LA BITACORA --rechazo y ausente puestos a mano--: es la unica
# manera de deshacer un cierre mal puesto, porque la bitacora se corrige
# agregando y no borrando (ver cto_resumen_dependencia()). En las que cerro el
# formulario no aparece: ahi manda el dato, y un contacto posterior no lo movera.
tabla_personas <- function(p, grupo = "faltan") {
  # La tabla se dibuja igual aunque no haya bitacora: si la lista llega sin las
  # columnas de contacto, se rellenan vacias en vez de reventar.
  if (is.null(p$contactos)) {
    p$contactos         <- 0L
    p$ultimo_contacto   <- as.Date(NA)
    p$ultimo_medio      <- NA_character_
    p$ultimo_medio_otro <- NA_character_
    p$cierre_bitacora   <- FALSE
  }
  if (is.null(p$cita_fecha)) {
    p$cita_fecha  <- as.Date(NA)
    p$cita_inicio <- NA_character_
    p$cita_fin    <- NA_character_
  }

  rotulos <- c(sel         = "",
               id          = "Persona",
               forma       = "Forma",
               vinculacion = "Vinculación",
               nivel       = "Nivel del empleo",
               estado      = "Estado de la vinculación",
               fecha       = "Fecha de respuesta",
               duracion    = "Duración (min)",
               situacion   = "Situación",
               contactos   = "Contactos",
               ultimo      = "Último contacto",
               citacion    = "Citación",
               accion      = "")

  cols <- switch(
    grupo,
    respondieron = c("id", "forma", "fecha", "duracion", "situacion", "contactos", "accion"),
    todos        = c("id", "forma", "vinculacion", "fecha", "situacion", "contactos", "accion"),
    no_elegibles = c("id", "forma", "vinculacion", "estado", "situacion"),
    # La situacion vuelve en los citados porque ahi conviven pendientes y casos
    # que la bitacora ya cerro como ausentes.
    citados      = c("sel", "id", "forma", "vinculacion", "citacion", "situacion",
                     "contactos", "ultimo", "accion"),
    # Las casillas vuelven porque aqui tambien se actua en lote: reabrir.
    cerrados     = c("sel", "id", "forma", "vinculacion", "situacion",
                     "contactos", "ultimo", "accion"),
                   c("sel", "id", "forma", "vinculacion", "nivel", "citacion",
                     "contactos", "ultimo", "accion")
  )

  txt <- function(x) if (length(x) == 0 || is.na(x)) "—" else as.character(x)

  celda <- function(f, col) switch(
    col,
    sel         = tags$td(
      class = "col-sel",
      tags$input(type = "checkbox", class = "sel-persona",
                 `data-per` = f$id_anonimizado,
                 `aria-label` = paste("Seleccionar", f$id_anonimizado))),
    # Desde el marco real hay nombre: va arriba y el documento debajo, que es
    # con lo que se cruza con nomina. Si el marco viniera sin nombre --una carga
    # vieja-- queda solo el documento, como antes.
    id          = tags$td(
      class = "col-id",
      if (is.null(f$nombre) || is.na(f$nombre)) txt(f$id_anonimizado)
      else tagList(span(class = "col-nombre", f$nombre),
                   span(class = "col-medio", txt(f$id_anonimizado)))),
    forma       = tags$td(txt(f$forma)),
    vinculacion = tags$td(txt(f$tipo_vinculacion)),
    nivel       = tags$td(class = "col-tenue", txt(f$nivel_empleo)),
    estado      = tags$td(class = "col-tenue", txt(f$estado_vinculacion)),
    fecha       = tags$td(class = "col-fecha", fmt_dia(f$submission_date)),
    duracion    = tags$td(class = "der col-num", fmt_num(f$duracion_min, 1)),
    situacion   = tags$td(chip_estado(situacion_persona(f$situacion))),
    contactos   = tags$td(class = "der col-num",
                          if (isTRUE(f$contactos > 0)) fmt_num(f$contactos) else "—"),
    ultimo      = tags$td(
      class = "col-fecha",
      if (is.na(f$ultimo_contacto)) "—" else tagList(
        fmt_fecha(f$ultimo_contacto),
        span(class = "col-medio",
             cto_medio_txt(f$ultimo_medio, f$ultimo_medio_otro)))),
    # La citacion mas reciente: el dia arriba y la franja debajo, con el mismo
    # formato de dos lineas que el ultimo contacto.
    citacion    = tags$td(
      class = "col-fecha",
      if (is.na(f$cita_fecha)) "—" else tagList(
        fmt_fecha(f$cita_fecha),
        span(class = "col-medio", sprintf("%s–%s", f$cita_inicio, f$cita_fin)))),
    # En un caso cerrado por la bitacora el boton ya no es "Contactar" sino
    # "Reabrir": es lo unico que se puede hacer con el, y antes habia que
    # adivinar que se reabria registrando un contacto con "La gesti\u00f3n sigue
    # abierta".
    accion      = tags$td(
      class = "col-accion",
      if (isTRUE(f$cierre_bitacora))
        tags$button(
          type = "button", class = "btn btn-sm btn-outline-primary",
          `data-reabrir` = f$id_anonimizado,
          `aria-label` = paste("Reabrir el caso de", f$id_anonimizado),
          "Reabrir")
      else if (identical(f$situacion, "falta"))
        tags$button(
          type = "button", class = "btn btn-sm btn-outline-secondary",
          `data-contactar` = f$id_anonimizado,
          `aria-label` = paste("Registrar contacto con", f$id_anonimizado),
          if (isTRUE(f$contactos > 0)) "Contactar\u2026" else "Contactar"))
  )

  filas <- lapply(seq_len(nrow(p)), function(i) {
    f <- p[i, ]
    tags$tr(class = paste("fila-per", f$situacion),
            lapply(cols, function(col) celda(f, col)))
  })

  encabezado <- function(col) {
    if (identical(col, "sel")) {
      return(tags$th(
        scope = "col", class = "col-sel",
        tags$input(type = "checkbox", class = "sel-todas",
                   `aria-label` = "Seleccionar todas las personas de la lista")))
    }
    tags$th(scope = "col",
            class = if (col %in% c("duracion", "contactos")) "der",
            rotulos[[col]])
  }

  div(
    class = "tabla-dep-caja",
    tags$table(
      class = "tabla-dep tabla-per",
      tags$caption(class = "visually-hidden",
                   "Personas de la dependencia y su situacion frente a la encuesta."),
      tags$thead(tags$tr(lapply(cols, encabezado))),
      tags$tbody(filas)
    )
  )
}


# --- quien no contesto, por dia de citacion -----------------------------------

# El resultado del ultimo contacto, en corto. CTO_RESULTADOS trae la frase larga
# del formulario ("Rechazo: manifestó que no participará"), que no cabe en una
# celda; aqui basta con cual fue. Va vectorizada porque la descarga de citados
# del dia la aplica a una columna entera, y switch() solo acepta un valor.
cto_resultado_txt <- function(x) {
  x <- as.character(x)
  unname(ifelse(x %in% "rechazo", "Rechazo",
         ifelse(x %in% "ausente", "Ausente",
         ifelse(x %in% CTO_REAPERTURA, "Reabierto", "Contactada"))))
}

tabla_citados_dia <- function(p, borrar = FALSE) {
  filas <- lapply(seq_len(nrow(p)), function(i) {
    f <- p[i, ]
    cerrado <- isTRUE(f$ultimo_resultado %in% CTO_CIERRES)
    tags$tr(
      tags$td(class = "col-id",
              if (is.null(f$nombre) || is.na(f$nombre)) f$id_anonimizado
              else tagList(span(class = "col-nombre", f$nombre),
                           span(class = "col-medio", f$id_anonimizado))),
      tags$td(class = "col-dep", f$dependencia),
      tags$td(f$tipo_vinculacion),
      tags$td(class = "col-fecha", f$franjas),
      tags$td(class = "col-num der", fmt_num(f$citaciones)),
      tags$td(class = "col-fecha",
              if (is.na(f$ultimo_contacto)) span(class = "col-tenue", "Sin contactar")
              else tagList(
                fmt_fecha(f$ultimo_contacto),
                span(class = if (cerrado) "chip bajo" else "col-medio",
                     cto_resultado_txt(f$ultimo_resultado)))),
      # Se contacta desde aqui mismo: este recuadro es la lista de a quien hay
      # que llamar, y mandar a buscar la persona en su dependencia para pulsar
      # el mismo boton no tenia sentido. Abre la misma ventana de registro. Si
      # la bitacora ya cerro el caso, el boton es Reabrir, como en la lista de
      # personas.
      tags$td(class = "col-accion",
              if (cerrado)
                tags$button(type = "button", class = "btn btn-sm btn-outline-primary",
                            `data-reabrir` = f$id_anonimizado,
                            `aria-label` = paste("Reabrir el caso de", f$id_anonimizado),
                            "Reabrir")
              else
                tags$button(type = "button", class = "btn btn-sm btn-outline-secondary",
                            `data-contactar` = f$id_anonimizado,
                            `aria-label` = paste("Registrar contacto con", f$id_anonimizado),
                            if (isTRUE(f$contactos > 0)) "Contactar…" else "Contactar"),
              if (borrar) boton_borrar(f$id_anonimizado, "citados_dia")))
  })

  div(class = "tabla-dep-caja",
      tags$table(
        class = "tabla-dep tabla-per tabla-dia",
        tags$thead(tags$tr(tags$th("Persona"), tags$th("Dependencia"), tags$th("Vinculación"),
                           tags$th("Franja"), tags$th(class = "der", "Veces citada"),
                           tags$th("Último contacto"), tags$th(""))),
        tags$tbody(filas)))
}


# --- personas fuera del marco ---------------------------------------------------

tabla_no_registrados <- function(p, borrar = FALSE) {
  # Son timestamptz: fmt_fecha() pasaria por as.Date() en UTC y un envio de
  # la noche saldria con el dia siguiente.
  dia <- function(x) if (is.na(x)) "—" else format(as.POSIXct(x), "%d/%m/%Y", tz = SEG_TZ)
  filas <- lapply(seq_len(nrow(p)), function(i) {
    f <- p[i, ]
    completo <- !is.na(f$completado_en)
    tags$tr(
      tags$td(class = "col-id",
              if (is.na(f$nombre)) f$id_anonimizado
              else tagList(span(class = "col-nombre", f$nombre),
                           span(class = "col-medio", f$id_anonimizado))),
      tags$td(class = "col-fecha", dia(f$primer_envio)),
      tags$td(class = "col-dep",
              if (completo) f$dependencia else span(class = "col-tenue", "Sin dato")),
      tags$td(if (completo) f$tipo_vinculacion else span(class = "col-tenue", "Sin dato")),
      tags$td(if (completo) f$nivel_empleo else span(class = "col-tenue", "Sin dato")),
      tags$td(class = "col-accion",
              if (completo)
                tagList(chip_estado(list(cls = "bien", txt = "Fijo", sig = "✓")),
                        span(class = "col-medio",
                             paste(c(if (!is.na(f$completado_por)) f$completado_por,
                                     dia(f$completado_en)), collapse = " · ")))
              else
                tags$button(type = "button", class = "btn btn-sm btn-outline-primary",
                            `data-completar` = f$id_anonimizado,
                            `aria-label` = paste("Completar datos de", f$id_anonimizado),
                            "Completar datos"),
              if (borrar) boton_borrar(f$id_anonimizado, "no_registrados")))
  })

  div(class = "tabla-dep-caja",
      tags$table(
        class = "tabla-dep tabla-per tabla-dia",
        tags$thead(tags$tr(tags$th("Persona"), tags$th("Envío"), tags$th("Dependencia"),
                           tags$th("Vinculación"), tags$th("Nivel del empleo"),
                           tags$th(""))),
        tags$tbody(filas)))
}

# Las opciones son las del marco (seg_opciones_no_registrados()): la dependencia
# tiene 160 y pico, por eso va con buscador.
modal_no_registrado <- function(ns, f, op) {
  quien <- if (is.na(f$nombre)) f$id_anonimizado
           else sprintf("%s (%s)", f$nombre, f$id_anonimizado)
  elegir <- function(id, rotulo, opciones) {
    selectizeInput(ns(id), rotulo, choices = c("", opciones), width = "100%",
                   options = list(placeholder = "Elija una opción"))
  }
  modalDialog(
    title = paste("Completar datos ·", quien),
    size = "m",
    easyClose = FALSE,
    div(
      elegir("nr_dependencia", SEG_NR_CAMPOS[["dependencia"]],
             op$dependencia$dependencia),
      uiOutput(ns("nr_unidad")),
      elegir("nr_tipo_vinculacion", SEG_NR_CAMPOS[["tipo_vinculacion"]],
             op$tipo_vinculacion),
      elegir("nr_nivel_empleo", SEG_NR_CAMPOS[["nivel_empleo"]], op$nivel_empleo),
      div(class = "alert alert-warning small",
          tags$b("Revise antes de guardar: "),
          "una vez guardados, estos datos quedan fijos y no se pueden cambiar ",
          "desde la aplicación."),
      uiOutput(ns("nr_aviso"))
    ),
    footer = tagList(
      modalButton("Cancelar"),
      actionButton(ns("nr_guardar"), "Guardar y dejar fijo", class = "btn-primary")
    )
  )
}


# --- registro de un contacto --------------------------------------------------
# La ventana sirve para una persona y para una seleccion entera: lo unico que
# cambia es el titulo y que el historial solo se puede mostrar cuando hay una
# sola. Los campos son los mismos, porque el contacto que se registra es el
# mismo para todas las marcadas.
#
# `modo = "reabrir"` es la misma ventana para deshacer un cierre. Pierde la
# fecha --la reapertura se fecha hoy, ver cto_reabrir()-- y la pregunta de como
# queda el seguimiento, que ya tiene respuesta: vuelve a "Faltan".

modal_contacto <- function(ns, ids, hist = NULL, hoy = Sys.Date(), nombre = NULL,
                           modo = "contacto") {
  n <- length(ids)
  quien <- if (length(nombre) == 1 && !is.na(nombre) && nzchar(nombre)) nombre else ids[1]
  reabre <- identical(modo, "reabrir")
  accion <- if (reabre) "Reabrir caso" else "Registrar contacto"

  modalDialog(
    title = if (n == 1) sprintf("%s \u00b7 %s", accion, quien)
            else sprintf("%s \u00b7 %s personas", accion, n),
    size = "m",
    easyClose = FALSE,

    div(
      class = "form-contacto",

      if (reabre) div(
        class = "alert alert-info small",
        sprintf(paste("%s dejará de estar en rechazo o ausente y volverá a «Faltan»,",
                      "con el seguimiento abierto como cualquier pendiente. El cierre",
                      "anterior se conserva en el historial."),
                if (n == 1) "La persona" else "Las personas")),

      # max = hoy: es una bitacora de lo que ya paso, no una agenda.
      if (!reabre)
        dateInput(ns("cto_fecha"), "Fecha del contacto", value = hoy, max = hoy,
                  language = "es", weekstart = 1, format = "dd/mm/yyyy",
                  width = "100%"),

      radioButtons(ns("cto_medio"),
                   if (reabre) "¿Por qué medio avisó que quiere responder?"
                   else "Medio del contacto",
                   choices = CTO_MEDIOS, selected = "correo", inline = TRUE),

      conditionalPanel(
        condition = sprintf("input['%s'] == 'otro'", ns("cto_medio")),
        textInput(ns("cto_otro"), "\u00bfCuál?", width = "100%",
                  placeholder = "WhatsApp, visita, mensaje por la jefatura\u2026")),

      textAreaInput(ns("cto_obs"), "Observación (opcional)", width = "100%",
                    rows = 3, resize = "vertical",
                    placeholder = if (reabre) "Por qué se reabre el caso\u2026"
                                  else "Qué se le dijo, qué respondió, cuándo volver a buscarla\u2026"),

      if (!reabre)
        radioButtons(ns("cto_resultado"), "Cómo queda el seguimiento",
                     choices = CTO_RESULTADOS, selected = "contacto"),

      uiOutput(ns("cto_aviso")),

      if (!is.null(hist) && nrow(hist) > 0) tagList(
        hr(),
        h6(sprintf("Contactos anteriores (%s)", nrow(hist))),
        tabla_historial(hist))
    ),

    footer = tagList(
      modalButton("Cancelar"),
      actionButton(ns("cto_guardar"), if (reabre) "Reabrir caso" else "Guardar contacto",
                   class = "btn-primary")
    )
  )
}

tabla_historial <- function(h) {
  filas <- lapply(seq_len(nrow(h)), function(i) {
    f <- h[i, ]
    tags$tr(
      tags$td(class = "col-fecha", fmt_fecha(f$fecha)),
      tags$td(cto_medio_txt(f$medio, f$medio_otro),
              if (isTRUE(f$resultado %in% CTO_CIERRES))
                chip_estado(situacion_persona(f$resultado))
              else if (identical(f$resultado, CTO_REAPERTURA))
                chip_estado(list(cls = "bien", txt = "Reabierto", sig = "\u21ba"))),
      tags$td(class = "col-obs",
              if (is.na(f$observacion) || !nzchar(f$observacion)) "\u2014"
              else f$observacion),
      tags$td(class = "col-tenue", f$registrado_por %||% "\u2014"))
  })

  div(
    class = "tabla-dep-caja tabla-historial",
    tags$table(
      class = "tabla-dep",
      tags$thead(tags$tr(
        tags$th(scope = "col", "Fecha"),
        tags$th(scope = "col", "Medio"),
        tags$th(scope = "col", "Observación"),
        tags$th(scope = "col", "Registró"))),
      tags$tbody(filas)
    )
  )
}


# --- piezas comunes de los graficos -------------------------------------------

# Cabecera de la tarjeta de un grafico. La comparten la curva diaria y las
# barras semanales porque son la MISMA tarjeta vista de dos maneras: si cada una
# dibujara su encabezado, cambiar de vista movería el titulo un pixel y la
# minipestana saltaria de sitio.
cab_grafico <- function(titulo, izq = NULL, der = NULL) {
  div(
    class = "grafico-cab",
    div(class = "grafico-cab-lado",
        span(class = "grafico-titulo", titulo), izq),
    div(class = "grafico-cab-lado", der)
  )
}

# Minipestanas: dos vistas de lo mismo en el mismo sitio. Es un radioButtons
# disfrazado con CSS y no un conjunto de botones a mano, para no reimplementar
# el estado ni el manejo de teclado: las flechas ya recorren un grupo de radios,
# y el lector de pantalla ya lo anuncia como lo que es, un selector de una sola
# opcion.
#
# Arranca en "Días", la curva del acumulado: es la vista continua, la que no
# obliga a decidir donde corta una semana. Las barras semanales quedan a un
# clic, para cuando la pregunta es cuanto rindio el campo cada semana.
VISTAS_GRAFICO <- c("Semanas" = "semanas", "Días" = "linea")

# El listado tiene las suyas: la de siempre --tabla o tarjetas segun cuantas
# dependencias queden-- y el semaforo, que responde otra pregunta. La tabla es
# para comparar cifras; el semaforo, para ver de un golpe cuantas unidades estan
# en rojo y cuales son.
VISTAS_LISTADO <- c("Listado" = "listado", "Mapa de avance" = "semaforo")

# La tarjeta del grafico lleva DOS selectores, no uno con cinco opciones,
# porque son dos preguntas independientes y mezclarlas obligaria a repetir cada
# metrica dos veces:
#
#   Grano    en que periodos se parte el tiempo   Semanas / Dias
#   Metrica  que se esta midiendo                 Avance / los tres indicadores
#
# Cualquier combinacion de las dos filas es valida, y cada una se recuerda por
# separado: cambiar de metrica no devuelve el grano a su valor inicial.
#
# "Avance" es lo que la tarjeta dibujaba siempre --la curva del acumulado y las
# barras apiladas-- y sigue siendo la que arranca. Los otros tres son
# porcentajes y comparten una sola forma de grafico (ver grafico_indicador()).
VISTAS_METRICA <- c("Avance"              = "avance",
                    "Efectividad"         = "efectividad",
                    "Cobertura Citados"   = "cob_citados",
                    "Cobertura Esperados" = "cob_esperados")

# Cada indicador es un numerador, un denominador y como se llama. Las formulas
# viven AQUI y en un solo sitio: el grafico no sabe que esta dibujando, solo
# divide lo que esta lista le dice.
#
# `den = "marco"` es el unico denominador que no es una serie: el marco es una
# foto y no cambia con el periodo, asi que el mismo numero se repite en todos
# (ver seg_marco_total()).
#
# Son las mismas formulas de seg_totales_indicadores(), que alimenta los
# cajones: si una cambia, la otra tambien.
#
#   Efectividad          encuestas efectivas (aceptaron) / encuestados
#   Cobertura Citados    encuestados / citados
#   Cobertura Esperados  encuestados / marco
INDICADORES <- list(
  efectividad = list(
    nombre = "Efectividad",
    num    = "efectivas",
    den    = "encuestados",
    unidad = "encuestas efectivas",
    titulo = "Efectividad: encuestas efectivas sobre encuestados",
    pie    = paste("Personas que aceptaron el consentimiento, sobre las",
                   "personas con al menos un envío (aceptaran o no).")),
  cob_citados = list(
    nombre = "Cobertura Citados",
    num    = "encuestados",
    den    = "citados",
    unidad = "personas encuestadas",
    titulo = "Cobertura Citados: encuestados sobre personas citadas",
    pie    = paste("Personas con al menos un envío, sobre las personas citadas",
                   "cuya hora de citación ya pasó. Cuenta también a quien",
                   "respondió sin cita, así que puede pasar de 100 %.")),
  cob_esperados = list(
    nombre = "Cobertura Esperados",
    num    = "encuestados",
    den    = "marco",
    unidad = "personas encuestadas",
    titulo = "Cobertura Esperados: encuestados sobre el marco",
    pie    = paste("Personas con al menos un envío, sobre el total de personas",
                   "activas del marco de la selección.")))

selector_vista <- function(id_input, valor = "linea", opciones = VISTAS_GRAFICO) {
  div(class = "selector-vista",
      radioButtons(id_input, label = NULL, choices = opciones,
                   selected = valor, inline = TRUE))
}


# --- grafico de avance acumulado ----------------------------------------------
# SVG construido a mano, como el resto del modulo. No entra ggplot2 ni plotly:
# un PNG no hereda la tipografia ni los colores del tema, se ve borroso en
# pantallas densas y no tiene equivalente accesible. El SVG se estiliza desde
# custom.css con las variables de Bootstrap, o sea que sigue al tema solo.
#
# Es una funcion pura --recibe un data.frame y devuelve etiquetas-- asi que se
# prueba suelta, igual que tabla_dependencias().
#
# La interaccion (cruceta, tooltip, teclado) vive en www/grafico.js y lee el
# JSON de `data-serie`. Ahi van las coordenadas YA calculadas y los numeros YA
# formateados: el navegador no vuelve a escalar ni a formatear nada, y no hay
# dos versiones de fmt_num(), una en R y otra en JavaScript.

# Cortes redondos para el eje: el paso sale de la magnitud del dato, no de
# dividir el maximo en cuatro (que dejaria marcas como 592,75).
escala_y <- function(v, n = 4) {
  if (!is.finite(v) || v <= 0) v <- 1
  crudo <- v / n
  p     <- 10^floor(log10(crudo))
  mult  <- c(1, 2, 2.5, 5, 10)
  paso  <- p * mult[which(crudo <= p * mult)[1]]
  tope  <- ceiling(v / paso) * paso
  list(tope = tope, cortes = seq(0, tope, by = paso))
}

# Lienzo en unidades del viewBox. El SVG se sirve con width:100%, asi que estas
# son coordenadas relativas: el navegador las escala al ancho que haya.
GRAF <- list(W = 720, H = 240, ML = 54, MR = 58, MT = 18, MB = 30)

grafico_acumulado <- function(serie, meta = 0,
                              titulo = "Cobertura y efectividad, acumulado",
                              control = NULL) {

  meta <- suppressWarnings(as.numeric(meta %||% 0))
  if (length(meta) != 1 || !is.finite(meta) || meta < 0) meta <- 0

  llave <- function(cls, txt) tagList(
    span(class = paste("graf-llave", cls), `aria-hidden` = "true"),
    span(class = "graf-llave-txt", txt))

  # Las dos curvas miden dos cosas distintas del mismo operativo y por eso van
  # juntas: la de arriba es cuanta gente respondio al llamado --acepte o rechace
  # la encuesta-- y la de abajo cuanta acepto el consentimiento (encuestas
  # efectivas). La franja que queda entre las dos es quien no acepto.
  #
  # La efectividad lleva su cifra en la leyenda porque es la unica de las dos que
  # no se puede leer del grafico: la cobertura termina en un numero rotulado, y
  # esta es una proporcion entre dos curvas que casi se tocan.
  #
  # Los citados van primero porque son la curva de arriba, y su rotulo lleva
  # los que no han respondido: es la cifra de control, y en el grafico solo se
  # ve como una distancia entre dos lineas.
  leyenda <- function(pct = NULL, sin_resp = NULL) span(
    class = "graf-leyenda",
    if (!is.null(sin_resp))
      llave("citados", sprintf("Citados · %s sin responder", fmt_num(sin_resp))),
    llave("cobertura",   "Cobertura"),
    llave("efectividad",
          if (is.null(pct)) "Efectividad (aceptaron)"
          else sprintf("Efectividad %s", fmt_pct(pct))))

  if (is.null(serie) || nrow(serie) == 0) {
    return(div(
      class = "grafico-acum",
      cab_grafico(titulo, der = control),
      div(class = "grafico-vacio",
          "Todavía no hay respuestas registradas en esta selección.")))
  }

  o      <- order(as.Date(serie$dia))
  dia    <- as.Date(serie$dia)[o]
  nuevos <- as.numeric(serie$n)[o]
  acum   <- cumsum(nuevos)
  np     <- length(dia)

  # La serie de efectivas puede no venir (una llamada vieja, una prueba con un
  # data.frame a mano): entonces se dibuja solo la cobertura, como antes.
  hay_comp <- !is.null(serie$n_efectivas)
  comp     <- if (hay_comp) cumsum(as.numeric(serie$n_efectivas)[o]) else NULL

  # Efectividad: de quienes respondieron, cuantos aceptaron. Es un porcentaje
  # sobre la cobertura de ESE dia, no sobre la meta: mide lo que sirve de lo
  # recibido, no el avance del operativo.
  efec <- if (hay_comp) ifelse(acum > 0, round(100 * comp / acum, 1), NA_real_) else NULL

  # Citados: personas a las que ya se les paso la hora de la cita, por el dia de
  # la primera (ver seg_serie()). Los sin responder son los citados menos los
  # citados que ya enviaron algo, no la distancia entre las dos curvas: a la
  # cobertura tambien llega quien respondio sin que lo citaran. Sin agenda
  # cargada no se dibuja nada y el grafico queda como estaba.
  hay_cit  <- !is.null(serie$n_citados) &&
              sum(as.numeric(serie$n_citados), na.rm = TRUE) > 0
  cit      <- if (hay_cit) cumsum(as.numeric(serie$n_citados)[o]) else NULL
  sin_resp <- if (hay_cit) cit - cumsum(as.numeric(serie$n_citados_resp)[o]) else NULL

  W <- GRAF$W; H <- GRAF$H
  X0 <- GRAF$ML; X1 <- W - GRAF$MR
  Y0 <- GRAF$MT; Y1 <- H - GRAF$MB

  ey <- escala_y(max(c(acum, meta, cit)))
  py <- function(v) round(Y1 - (v / ey$tope) * (Y1 - Y0), 1)

  # El eje x es la FECHA, no la posicion en la lista: un fin de semana sin
  # envios tiene que verse como un tramo plano, no desaparecer del ancho.
  #
  # Se llama `ancho_dias` y no `span` porque `span()` es la etiqueta HTML de
  # shiny, y la leyenda de aqui arriba la usa. Funcionaba de milagro --R, al
  # resolver una llamada, salta los enlaces que no son funciones-- pero basta
  # con que alguien guarde el resultado de span() en una variable para que deje
  # de funcionar, y el fallo aparecería lejos de esta linea.
  ancho_dias <- as.numeric(max(dia) - min(dia))
  px   <- if (ancho_dias > 0) {
    round(X0 + (as.numeric(dia - min(dia)) / ancho_dias) * (X1 - X0), 1)
  } else {
    rep(X1, np)   # un solo dia: el punto se planta en el borde derecho
  }

  trazo <- function(v) {
    pts <- paste0(px, ",", py(v))
    list(linea = paste0("M", paste(pts, collapse = "L")),
         area  = paste0("M", px[1], ",", Y1, "L", paste(pts, collapse = "L"),
                        "L", px[np], ",", Y1, "Z"))
  }
  t_cob  <- trazo(acum)
  t_comp <- if (hay_comp) trazo(comp)
  t_cit  <- if (hay_cit)  trazo(cit)

  sv <- function(nombre, ...) tag(nombre, list(...))

  # Cuando el paso es fraccionario (0, 2,5, 5, 7,5, 10) el rotulo necesita el
  # decimal: redondeado a entero, la marca de 2,5 diria "2" y la rejilla estaria
  # mintiendo sobre su propia altura.
  dec_y <- if (any(ey$cortes %% 1 != 0)) 1 else 0

  # Rejilla: una linea de pelo por corte, con su valor a la izquierda.
  rejilla <- lapply(ey$cortes, function(v) {
    y <- py(v)
    list(
      sv("line", class = "graf-rejilla", x1 = X0, x2 = X1, y1 = y, y2 = y),
      sv("text", class = "graf-eje-y", x = X0 - 8, y = y,
         `text-anchor` = "end", `dominant-baseline` = "middle", fmt_num(v, dec_y))
    )
  })

  # Hasta cinco fechas: mas marcas se pisan entre si en pantallas angostas.
  idx  <- unique(round(seq(1, np, length.out = min(np, 5))))
  ejex <- lapply(idx, function(i) {
    sv("text", class = "graf-eje-x", x = px[i], y = Y1 + 18,
       `text-anchor` = if (i == 1) "start" else if (i == np) "end" else "middle",
       format(dia[i], "%d/%m"))
  })

  y_fin  <- py(acum[np])
  y_meta <- py(meta)

  # La etiqueta del final va encima del punto, salvo que ahi este la linea de
  # meta: cuando el avance esta cerca del 100% los dos rotulos caen al mismo
  # sitio, y se lee uno encima del otro.
  arriba <- meta <= 0 || abs(y_fin - y_meta) >= 18
  y_rotu <- if (arriba) y_fin - 11 else y_fin + 19

  meta_marca <- if (meta > 0) list(
    sv("line", class = "graf-meta", x1 = X0, x2 = X1, y1 = y_meta, y2 = y_meta),
    sv("text", class = "graf-meta-rotulo", x = X1 + 6, y = y_meta,
       `dominant-baseline` = "middle",
       sprintf("meta %s", fmt_num(meta)))
  )

  # Numeros y fechas ya formateados en R con los mismos helpers que el resto de
  # la app (miles con punto, decimales con coma). El JS solo hace textContent.
  jn <- function(v) paste0("[", paste(v, collapse = ","), "]")
  jt <- function(v) paste0("[", paste0('"', v, '"', collapse = ","), "]")
  datos <- paste0(
    '{"x":',   jn(px),
    ',"y":',   jn(py(acum)),
    ',"t":',   jt(format(dia, "%Y-%m-%d")),
    ',"a":',   jt(fmt_num(acum)),
    ',"nu":',  jt(fmt_num(nuevos)),
    ',"p":',   jt(if (meta > 0) fmt_pct(round(100 * acum / meta, 1)) else rep("—", np)),
    if (hay_comp) paste0(
      ',"y2":', jn(py(comp)),
      ',"c":',  jt(fmt_num(comp)),
      # Un dia sin cobertura no tiene efectividad: raya y no "NA%". Con la
      # agenda cargada es mas frecuente, porque la serie puede empezar en un
      # dia de citas en el que todavia no ha respondido nadie.
      ',"ef":', jt(ifelse(is.na(efec), "—", fmt_pct(efec)))),
    if (hay_cit) paste0(
      ',"y3":', jn(py(cit)),
      ',"ci":', jt(fmt_num(cit)),
      ',"sr":', jt(fmt_num(sin_resp))),
    '}')

  resumen <- sprintf(
    "Cobertura acumulada del %s al %s. Termina en %s personas%s.%s%s",
    format(min(dia), "%Y-%m-%d"), format(max(dia), "%Y-%m-%d"), fmt_num(acum[np]),
    if (meta > 0) sprintf(" de %s planeadas, %s", fmt_num(meta),
                          fmt_pct(round(100 * acum[np] / meta, 1))) else "",
    if (hay_comp) sprintf(" De ellas %s aceptaron la encuesta, %s de efectividad.",
                          fmt_num(comp[np]), fmt_pct(efec[np])) else "",
    if (hay_cit) sprintf(" Citadas: %s personas, de las que %s no han respondido.",
                         fmt_num(cit[np]), fmt_num(sin_resp[np])) else "")

  div(
    class = "grafico-acum",
    `data-serie` = datos,
    tabindex = "0",
    cab_grafico(
      titulo,
      izq = if (hay_comp || hay_cit)
              leyenda(if (hay_comp) efec[np], if (hay_cit) sin_resp[np]),
      der = tagList(span(class = "grafico-pista", "Pase el cursor o use las flechas"),
                    control)),

    sv("svg", class = "graf-svg", viewBox = sprintf("0 0 %d %d", W, H),
       role = "img", `aria-label` = resumen,
       preserveAspectRatio = "xMidYMid meet",

       rejilla,
       ejex,
       meta_marca,

       # El area de efectivas va encima de la de cobertura y mas cargada: las
       # dos empiezan en la linea de base, asi que la franja mas clara que
       # asoma por arriba es exactamente quien no acepto.
       sv("path", class = "graf-area", d = t_cob$area),
       if (hay_comp) sv("path", class = "graf-area comp", d = t_comp$area),
       # Los citados van sin area --taparian las otras dos-- y debajo de la
       # linea de cobertura, que es la que manda cuando se cruzan.
       if (hay_cit) sv("path", class = "graf-linea cit", d = t_cit$linea),
       sv("path", class = "graf-linea", d = t_cob$linea),
       if (hay_comp) sv("path", class = "graf-linea comp", d = t_comp$linea),

       # Cruceta: oculta hasta que el puntero o el teclado la mueven.
       sv("g", class = "graf-cursor", `aria-hidden` = "true",
          sv("line", class = "graf-guia", x1 = 0, x2 = 0, y1 = Y0, y2 = Y1),
          sv("circle", class = "graf-punto-cursor", cx = 0, cy = 0, r = 4.5),
          if (hay_comp)
            sv("circle", class = "graf-punto-cursor comp", cx = 0, cy = 0, r = 4),
          if (hay_cit)
            sv("circle", class = "graf-punto-cursor cit", cx = 0, cy = 0, r = 4)),

       if (hay_cit)
         sv("circle", class = "graf-punto-fin cit", cx = px[np], cy = py(cit[np]), r = 4),
       sv("circle", class = "graf-punto-fin", cx = px[np], cy = y_fin, r = 4.5),
       sv("text", class = "graf-rotulo-fin", x = px[np], y = y_rotu,
          `text-anchor` = "end", fmt_num(acum[np]))
    ),

    # Nace oculto: el JS solo lo destapa al posarse el cursor. Sin este
    # `hidden` quedaria una caja vacia flotando hasta el primer hover.
    div(class = "grafico-tip", hidden = NA, `aria-hidden` = "true"),
    div(class = "grafico-voz visually-hidden", role = "status", `aria-live` = "polite"),

    # Equivalente en texto: lo que muestra el tooltip, sin necesitar el tooltip.
    tags$table(
      class = "visually-hidden",
      tags$caption(resumen),
      tags$thead(tags$tr(tags$th("Fecha"), tags$th("Nuevas"), tags$th("Cobertura"),
                         if (hay_comp) tags$th("Efectivas"),
                         if (hay_comp) tags$th("Efectividad"),
                         if (hay_cit)  tags$th("Citados"),
                         if (hay_cit)  tags$th("Citados sin responder"))),
      tags$tbody(lapply(seq_len(np), function(i) tags$tr(
        tags$td(format(dia[i], "%Y-%m-%d")),
        tags$td(fmt_num(nuevos[i])),
        tags$td(fmt_num(acum[i])),
        if (hay_comp) tags$td(fmt_num(comp[i])),
        if (hay_comp) tags$td(fmt_pct(efec[i])),
        if (hay_cit)  tags$td(fmt_num(cit[i])),
        if (hay_cit)  tags$td(fmt_num(sin_resp[i])))))
    )
  )
}

# --- grafico de barras por semana ---------------------------------------------
# Mismo SVG dibujado a mano y mismas variables del tema que la curva diaria (ver
# el comentario de grafico_acumulado()); lo que cambia es la pregunta que
# contesta.
#
# Cada barra es una semana de campo y esta APILADA con los tres numeros a la
# vista, que es lo que se viene a leer de una sola mirada:
#
#        2.116   <- total acumulado al cerrar la semana (encima de la barra)
#      +-------+
#      |  594  |  <- nuevas de esa semana (segmento oscuro)
#      +-------+
#      | 1.522 |  <- acumulado anterior  (segmento claro)
#      +-------+
#          S4
#
# Los tres salen tal cual de seg_semanas() --nuevos, previo y acum, con
# acum = previo + nuevos-- y aqui solo se formatean con fmt_num(): la grafica no
# vuelve a calcular nada, para que no pueda decir un numero distinto del que
# cuentan los indicadores.
#
# Las semanas sin envios no se saltan (ver seg_semanas()): su segmento oscuro
# mide cero y la barra se queda a la misma altura que la anterior, que es como se
# ve un hueco de campo en una serie acumulada. Encima va el acumulado, igual que
# en las demas semanas; no se dibuja ningun "0" suelto, porque un cero flotando
# junto al total se lee como si fueran dos cifras del mismo tipo. El cero sigue
# estando en el tooltip y en la tabla equivalente.
#
# La meta se dibuja dos veces porque son dos lecturas distintas: una LINEA
# punteada que cruza las semanas --para comparar cualquier barra con ella sin
# arrastrar la vista hasta el borde-- y una COLUMNA de referencia al final, que
# cierra la fila y deja comparar altura contra altura. La columna no es una
# semana mas: va detras de un espacio y de un separador, en gris punteado y no
# en verde, y su rotulo del eje dice "Meta" y no "S10".
#
# La ultima barra casi siempre esta cortada, porque la semana no ha terminado:
# lleva marco punteado, asterisco en el eje, nota al pie y la hora del ultimo
# envio recibido en la cabecera. Sin eso, una semana a medias se lee como una
# caida del ritmo.

# MT deja sitio para los DOS renglones que van encima de cada barra --el
# acumulado y su porcentaje de la meta--, tambien en la barra mas alta, que es
# la que toca el tope del eje.
GRAF_SEM <- list(W = 720, H = 250, ML = 54, MR = 14, MT = 46, MB = 36)

# Alto minimo (en unidades del viewBox) para meter un numero DENTRO de un
# segmento sin que roce sus bordes. Por debajo de esto la etiqueta sale afuera.
SEM_ALTO_ETIQUETA <- 12

# Aire entre la ultima semana y la columna de meta. La meta no es un periodo mas
# de la serie: es contra lo que se comparan todos, y el espacio lo dice sin
# necesidad de escribirlo.
SEM_SEP <- 18

# Ancho minimo de barra para que quepa un numero de cuatro o cinco cifras. Con
# campanas largas las barras se estrechan y las etiquetas de dentro estorban mas
# de lo que informan: se quedan solo los totales.
SEM_ANCHO_ETIQUETA <- 30

rango_semana <- function(inicio, fin) {
  sprintf("lun %s a vie %s",
          format(as.Date(inicio), "%d/%m"), format(as.Date(fin), "%d/%m"))
}

# Version corta para la clave de semanas. Las dos fechas llevan siempre su mes,
# aunque se repita: ahorrarlo obliga a mirar la segunda para saber de que mes es
# la primera, y en una lista donde unas entradas cruzan el mes y otras no, las
# dos formas conviviendo se leen peor que la repeticion.
rango_corto <- function(inicio, fin) {
  sprintf("%s–%s",
          format(as.Date(inicio), "%d/%m"), format(as.Date(fin), "%d/%m"))
}

# El corte se rotula con la hora del ULTIMO ENVIO recibido, no con la hora de
# ahora: la barra llega hasta donde llegan los datos. Se formatea en la zona del
# campo por lo mismo que seg_serie() convierte alli el dia (la conexion viene en
# UTC, y un envio de las 20:00 de Medellin diria "21:00 del dia siguiente").
fmt_corte <- function(ultimo) {
  if (is.null(ultimo) || length(ultimo) != 1 || all(is.na(ultimo))) return(NULL)
  sprintf("corte: %s", format(as.POSIXct(ultimo), "%d/%m %H:%M", tz = SEG_TZ))
}

grafico_semanas <- function(semanas, meta = 0, ultimo = NULL,
                            titulo = "Avance por semana", control = NULL) {

  meta <- suppressWarnings(as.numeric(meta %||% 0))
  if (length(meta) != 1 || !is.finite(meta) || meta < 0) meta <- 0

  llave <- function(cls, txt) tagList(
    span(class = paste("graf-llave", cls), `aria-hidden` = "true"),
    span(class = "graf-llave-txt", txt))

  # Los rotulos nombran lo que es cada segmento sin ambiguedad: "acumulado" a
  # secas se confundia con el total de la barra, que es otra cosa.
  leyenda <- span(
    class = "graf-leyenda",
    llave("nueva",  "Nuevas en la semana"),
    llave("previo", "Acumulado anterior"),
    if (meta > 0) llave("meta", "Meta"))

  cab <- function(...) cab_grafico(
    titulo,
    izq = if (nrow(semanas %||% data.frame()) > 0) leyenda,
    der = tagList(..., control))

  if (is.null(semanas) || nrow(semanas) == 0) {
    return(div(
      class = "grafico-acum grafico-barras",
      cab(),
      div(class = "grafico-vacio",
          "Todavía no hay respuestas registradas en esta selección.")))
  }

  W <- GRAF_SEM$W; H <- GRAF_SEM$H
  X0 <- GRAF_SEM$ML; X1 <- W - GRAF_SEM$MR
  Y0 <- GRAF_SEM$MT; Y1 <- H - GRAF_SEM$MB

  nw  <- nrow(semanas)

  # El eje va numerado --S1, S2...-- y no fechado. Una fila de "13/07 20/07
  # 27/07" obliga a leer cinco cifras para saber de que semana se habla y a
  # calcular cuantas van; "S3" se dice y se recuerda. Las fechas no se pierden:
  # bajan a la clave, que es donde se consultan una vez y no en cada mirada.
  # La numeracion arranca en el inicio de campo (ver seg_semanas(desde)), asi
  # que S3 es la misma semana aqui y en el detalle de cualquier dependencia.
  nom <- paste0("S", seq_len(nw))

  ey <- escala_y(max(c(semanas$acum, meta)))
  py <- function(v) round(Y1 - (v / ey$tope) * (Y1 - Y0), 1)

  # El avance en campo de cada semana: el acumulado de esa semana sobre la meta.
  # Es la misma cuenta que ya llevaba la tabla equivalente en su columna "De la
  # meta"; lo que cambia es que ahora tambien se ve. Sin meta no hay avance que
  # dar --no es 0%, es que no hay contra que medirlo-- y no se dibuja nada.
  pct_sem <- if (meta > 0) round(100 * semanas$acum / meta, 1) else rep(NA_real_, nw)

  # El rotulo va a entero, que es como se dice en voz alta, pero el redondeo no
  # puede cruzar los extremos: un 99,5% que se pinta "100%" afirma que la meta
  # esta cumplida cuando no lo esta, y un 0,4% que se pinta "0%" dice que no ha
  # entrado nadie cuando ya entro gente. En los dos casos gana el dato.
  etq_pct <- function(p) {
    if (is.na(p)) return(NA_character_)
    e <- round(p)
    if (e >= 100 && p < 100) e <- 99
    if (e <= 0   && p > 0)   e <- 1
    fmt_pct(e, 0)
  }

  # nw + 1 puestos: las semanas y, al final, la columna de meta.
  #
  # Las barras llenan su puesto y solo dejan un hilo de aire entre ellas: la
  # serie es acumulada, asi que pegadas dibujan una escalera continua --lo que
  # ya se llevaba, semana a semana-- en vez de nueve columnas sueltas que hay
  # que ir emparejando con la vista. El tope evita que con tres o cuatro semanas
  # las barras se conviertan en bloques desproporcionados.
  slot  <- (X1 - X0 - SEM_SEP) / (nw + 1)
  ancho <- min(72, slot - 3)
  cx    <- function(i) round(X0 + slot * (i - 0.5) + if (i > nw) SEM_SEP else 0, 1)
  cabe  <- ancho >= SEM_ANCHO_ETIQUETA

  sv <- function(nombre, ...) tag(nombre, list(...))

  dec_y <- if (any(ey$cortes %% 1 != 0)) 1 else 0

  rejilla <- lapply(ey$cortes, function(v) {
    y <- py(v)
    list(
      sv("line", class = "graf-rejilla", x1 = X0, x2 = X1, y1 = y, y2 = y),
      sv("text", class = "graf-eje-y", x = X0 - 8, y = y,
         `text-anchor` = "end", `dominant-baseline` = "middle", fmt_num(v, dec_y))
    )
  })

  # Con muchas semanas los rotulos se pisan: se muestra uno de cada `paso`,
  # contando desde la ULTIMA hacia atras para que la semana en curso --que es la
  # que se viene a mirar-- nunca sea la que se salta.
  vis <- function(unidad) {
    paso <- max(1L, as.integer(ceiling(unidad / slot)))
    rev(seq(nw, 1L, by = -paso))
  }
  vis_x <- vis(20)   # "S12" mas su aire
  vis_n <- vis(30)   # "2.116"

  barras <- lapply(seq_len(nw), function(i) {
    s <- semanas[i, ]
    x <- round(cx(i) - ancho / 2, 1)

    y_tot  <- py(s$acum)     # techo de la barra: el acumulado de la semana
    y_prev <- py(s$previo)   # frontera entre lo anterior y lo nuevo

    alto_nuevas <- round(y_prev - y_tot, 1)
    alto_previo <- round(Y1 - y_prev, 1)
    curso <- isTRUE(s$en_curso)

    # La etiqueta de nuevas vive dentro de su segmento mientras quepa; si el
    # segmento es muy fino, sube justo encima de la barra y el total se corre
    # para dejarle sitio. Sin nuevas no hay etiqueta que poner: encima queda solo
    # el acumulado, que es la cifra que esa semana sigue teniendo.
    dentro_nuevas <- cabe && alto_nuevas >= SEM_ALTO_ETIQUETA && s$nuevos > 0
    dentro_previo <- cabe && alto_previo >= SEM_ALTO_ETIQUETA && s$previo > 0
    fuera_nuevas  <- !dentro_nuevas && s$nuevos > 0 && s$previo > 0 &&
                     i %in% vis_n

    sv("g",
       class = paste("graf-barra", if (curso) "en-curso"),
       sv("title", sprintf("%s (%s): %s acumuladas antes, %s nuevas, %s en total%s%s",
                           nom[i], rango_semana(s$inicio, s$fin),
                           fmt_num(s$previo), fmt_num(s$nuevos), fmt_num(s$acum),
                           if (is.na(pct_sem[i])) ""
                           else sprintf(", %s de la meta de %s",
                                        fmt_pct(pct_sem[i]), fmt_num(meta)),
                           if (curso) ". Semana en curso" else "")),

       if (s$previo > 0)
         sv("rect", class = "graf-barra-previo", x = x, y = y_prev,
            width = ancho, height = alto_previo),
       if (s$nuevos > 0)
         sv("rect", class = "graf-barra-nueva", x = x, y = y_tot,
            width = ancho, height = alto_nuevas),

       # El marco punteado dice, sin depender del color, que esta barra todavia
       # se esta llenando.
       if (curso)
         sv("rect", class = "graf-marco-curso", x = x, y = y_tot,
            width = ancho, height = round(Y1 - y_tot, 1)),

       if (dentro_previo)
         sv("text", class = "graf-dentro previo", x = cx(i),
            y = round(y_prev + alto_previo / 2, 1),
            `text-anchor` = "middle", `dominant-baseline` = "middle",
            fmt_num(s$previo)),

       if (dentro_nuevas)
         sv("text", class = "graf-dentro nueva", x = cx(i),
            y = round(y_tot + alto_nuevas / 2, 1),
            `text-anchor` = "middle", `dominant-baseline` = "middle",
            fmt_num(s$nuevos)),

       # Fuera de la barra solo si el numero aporta algo: en la primera semana
       # --sin acumulado anterior-- las nuevas SON el total, y repetir la misma
       # cifra dos veces, una encima de la otra, se lee como dos cantidades
       # distintas.
       if (fuera_nuevas)
         sv("text", class = "graf-fuera-nuevas",
            x = cx(i), y = round(y_tot - 5, 1), `text-anchor` = "middle",
            fmt_num(s$nuevos)),

       # Encima de la barra van el acumulado y, sobre el, que parte de la meta
       # es. El numero queda pegado a la barra --es el dato que la barra mide--
       # y el porcentaje arriba: se lee de un vistazo por toda la fila sin que
       # cada cifra haya que dividirla mentalmente por la columna de meta.
       #
       # Va redondeado a entero, que es como se dice en voz alta; el decimal
       # sigue en el tooltip y en la tabla equivalente, que es donde se consulta
       # una cifra exacta. Aparece con el total y no por su cuenta: un
       # porcentaje suelto encima de una barra sin su numero se lee como si
       # fuera el numero.
       if (i %in% vis_n)
         sv("text", class = "graf-rotulo-total", x = cx(i),
            y = round(y_tot - (if (fuera_nuevas) 18 else 6), 1),
            `text-anchor` = "middle", fmt_num(s$acum)),

       if (i %in% vis_n && !is.na(pct_sem[i]))
         sv("text", class = "graf-rotulo-pct", x = cx(i),
            y = round(y_tot - (if (fuera_nuevas) 30 else 18), 1),
            `text-anchor` = "middle", etq_pct(pct_sem[i]))
    )
  })

  # El asterisco marca la semana cortada. Va en el rotulo y no solo en el marco
  # punteado: la senal que se lee en voz alta o se imprime en gris tiene que
  # estar tambien en el texto.
  ejex <- lapply(vis_x, function(i) {
    sv("text",
       class = paste("graf-eje-x", if (isTRUE(semanas$en_curso[i])) "en-curso"),
       x = cx(i), y = Y1 + 18, `text-anchor` = "middle",
       paste0(nom[i], if (isTRUE(semanas$en_curso[i])) "*" else ""))
  })

  y_meta <- py(meta)
  x_meta <- round(cx(nw + 1) - ancho / 2, 1)
  x_sep  <- round(X0 + slot * nw + SEM_SEP / 2, 1)

  # La linea arranca en el eje y muere justo donde empieza la columna: asi las
  # dos se leen como una sola cosa --la altura de la meta-- y no como dos datos.
  # El numero va encima de la columna y el rotulo debajo, en el mismo sitio en
  # que cada semana lleva su total y su nombre, para que la comparacion sea
  # inmediata.
  bloque_meta <- if (meta > 0) list(
    sv("line", class = "graf-meta", x1 = X0, x2 = x_meta, y1 = y_meta, y2 = y_meta),
    sv("line", class = "graf-sep", x1 = x_sep, x2 = x_sep, y1 = Y0 - 8, y2 = Y1),
    sv("g", class = "graf-barra",
       sv("title", sprintf("Meta: %s personas", fmt_num(meta))),
       sv("rect", class = "graf-barra-meta", x = x_meta, y = y_meta,
          width = ancho, height = round(Y1 - y_meta, 1))),
    sv("text", class = "graf-rotulo-total meta", x = cx(nw + 1),
       y = round(y_meta - 6, 1), `text-anchor` = "middle", fmt_num(meta)),
    sv("text", class = "graf-eje-x meta", x = cx(nw + 1), y = Y1 + 18,
       `text-anchor` = "middle", "Meta")
  )

  acum_fin <- semanas$acum[nw]
  pct <- if (meta > 0) round(100 * acum_fin / meta, 1) else NA_real_

  resumen <- sprintf(
    "Avance por semana, de S1 (semana del %s) a %s (semana del %s). %s personas encuestadas%s. La ultima semana esta en curso.",
    format(semanas$inicio[1], "%Y-%m-%d"), nom[nw],
    format(semanas$inicio[nw], "%Y-%m-%d"),
    fmt_num(acum_fin),
    if (meta > 0) sprintf(" de %s planeadas, %s", fmt_num(meta), fmt_pct(pct)) else "")

  div(
    class = "grafico-acum grafico-barras",
    cab(span(class = "grafico-pista", fmt_corte(ultimo))),

    sv("svg", class = "graf-svg", viewBox = sprintf("0 0 %d %d", W, H),
       role = "img", `aria-label` = resumen,
       preserveAspectRatio = "xMidYMid meet",

       rejilla,
       ejex,
       bloque_meta,
       barras
    ),

    # Clave de las semanas: el eje dice cual es cada barra y esto dice que dias
    # cubre. Va debajo y no en el eje porque son dos preguntas de frecuencia muy
    # distinta --de que semana hablamos se pregunta a cada mirada; que dias
    # fueron, una sola vez-- y meterlas juntas en el eje llenaba la fila de
    # cifras que hay que descifrar cada vez.
    div(
      class = "graf-clave-semanas",
      lapply(seq_len(nw), function(i) span(
        class = paste("clave-sem", if (isTRUE(semanas$en_curso[i])) "en-curso"),
        span(class = "clave-nom",
             paste0(nom[i], if (isTRUE(semanas$en_curso[i])) "*" else "")),
        span(class = "clave-dias", rango_corto(semanas$inicio[i], semanas$fin[i]))
      ))
    ),

    div(class = "grafico-nota",
        "* semana en curso (barra con borde punteado): llega hasta el último envío recibido."),

    # Equivalente en texto, igual que en la curva: los mismos tres numeros que
    # muestra la grafica, para quien no puede verla.
    tags$table(
      class = "visually-hidden",
      tags$caption(resumen),
      tags$thead(tags$tr(tags$th("Semana"), tags$th("Acumulado anterior"),
                         tags$th("Nuevas"), tags$th("Total acumulado"),
                         tags$th("De la meta"))),
      tags$tbody(lapply(seq_len(nw), function(i) tags$tr(
        tags$td(sprintf("%s, %s", nom[i],
                        rango_semana(semanas$inicio[i], semanas$fin[i]))),
        tags$td(fmt_num(semanas$previo[i])),
        tags$td(fmt_num(semanas$nuevos[i])),
        tags$td(fmt_num(semanas$acum[i])),
        tags$td(if (meta > 0) fmt_pct(round(100 * semanas$acum[i] / meta, 1)) else "—"))))
    )
  )
}


# --- grafico de un indicador porcentual ---------------------------------------
# La forma que comparten Efectividad, Cobertura Citados y Cobertura Esperados:
# los tres son un numerador sobre un denominador, y los tres se leen igual. Una
# sola funcion los dibuja, y cual se dibuja lo dice INDICADORES; asi agregar un
# cuarto indicador es agregar una entrada a esa lista, no otro grafico.
#
# Lleva las DOS lecturas del mismo dato, que es lo que se pidio:
#
#   BARRA   el porcentaje DEL PERIODO: como rindio esa semana (o ese dia).
#           Sube y baja con el campo, y es donde se ve un mal periodo.
#   LINEA   el porcentaje ACUMULADO hasta ese periodo: como va la campana. Es
#           una razon entre los dos acumulados --no el promedio de las barras--
#           porque los periodos no pesan lo mismo.
#
# Y en la cabecera va el NUMERO, no solo el porcentaje: el acumulado del
# numerador, que es la cifra que se pidio explicitamente ("efectividad numero",
# "cobertura citados numero").
#
# Un periodo sin denominador --un dia sin citaciones, un fin de semana-- no
# tiene porcentaje: no se dibuja su barra y no se inventa un cero, que se leeria
# como que ese dia se trabajo y no rindio. El dato sigue en la tabla equivalente.
#
# Mismo lienzo y mismas variables del tema que los otros dos graficos.
GRAF_IND <- list(W = 720, H = 250, ML = 46, MR = 14, MT = 34, MB = 36)

grafico_indicador <- function(per, ind, marco = 0, por = "semana", control = NULL) {

  cab <- function(...) cab_grafico(ind$titulo, ...)

  if (is.null(per) || nrow(per) == 0) {
    return(div(
      class = "grafico-acum grafico-barras grafico-ind",
      cab(der = control),
      div(class = "grafico-vacio",
          "Todavía no hay datos suficientes en esta selección.")))
  }

  n   <- nrow(per)
  sem <- identical(por, "semana")

  # El denominador del marco no es una serie: el mismo numero en todos los
  # periodos, tanto para la barra como para la linea.
  num    <- as.numeric(per[[ind$num]])
  num_ac <- as.numeric(per[[paste0(ind$num, "_ac")]])
  if (identical(ind$den, "marco")) {
    den <- den_ac <- rep(as.numeric(marco), n)
  } else {
    den    <- as.numeric(per[[ind$den]])
    den_ac <- as.numeric(per[[paste0(ind$den, "_ac")]])
  }

  pct    <- ifelse(den    > 0, 100 * num    / den,    NA_real_)
  pct_ac <- ifelse(den_ac > 0, 100 * num_ac / den_ac, NA_real_)

  W <- GRAF_IND$W; H <- GRAF_IND$H
  X0 <- GRAF_IND$ML; X1 <- W - GRAF_IND$MR
  Y0 <- GRAF_IND$MT; Y1 <- H - GRAF_IND$MB

  # El eje se corta en el dato y no siempre en 100: con todo entre el 50 y el 70
  # un eje 0-100 deja la mitad del lienzo vacio y aplana las diferencias, que es
  # justo lo que se viene a mirar. El tope nunca pasa de 100, que es el maximo
  # que un porcentaje puede valer.
  cima <- suppressWarnings(max(c(pct, pct_ac), na.rm = TRUE))
  if (!is.finite(cima) || cima <= 0) cima <- 1
  ey <- escala_y(min(100, cima))
  ey$cortes <- ey$cortes[ey$cortes <= 100]
  py <- function(v) round(Y1 - (pmin(v, ey$tope) / ey$tope) * (Y1 - Y0), 1)

  slot  <- (X1 - X0) / n
  ancho <- min(72, slot - 3)
  cx    <- function(i) round(X0 + slot * (i - 0.5), 1)

  sv <- function(nombre, ...) tag(nombre, list(...))

  nom <- if (sem) paste0("S", seq_len(n)) else format(per$inicio, "%d/%m")

  dec_y <- if (any(ey$cortes %% 1 != 0)) 1 else 0
  rejilla <- lapply(ey$cortes, function(v) {
    y <- py(v)
    list(
      sv("line", class = "graf-rejilla", x1 = X0, x2 = X1, y1 = y, y2 = y),
      sv("text", class = "graf-eje-y", x = X0 - 8, y = y,
         `text-anchor` = "end", `dominant-baseline` = "middle",
         paste0(fmt_num(v, dec_y), "%")))
  })

  # Con muchos periodos los rotulos se pisan: se muestra uno de cada `paso`,
  # contando desde el ULTIMO hacia atras para que el periodo en curso --el que
  # se viene a mirar-- nunca sea el que se salta. Mismo criterio que las barras
  # semanales; en la vista diaria el rotulo es mas ancho ("13/07").
  vis <- function(unidad) {
    paso <- max(1L, as.integer(ceiling(unidad / slot)))
    rev(seq(n, 1L, by = -paso))
  }
  vis_x <- vis(if (sem) 20 else 34)
  vis_n <- vis(30)

  rango <- function(i) if (sem) rango_semana(per$inicio[i], per$fin[i])
                       else format(per$inicio[i], "%d/%m/%Y")

  barras <- lapply(seq_len(n), function(i) {
    curso <- isTRUE(per$en_curso[i])
    titulo <- sprintf("%s (%s): %s de %s%s",
                      nom[i], rango(i), fmt_num(num[i]), fmt_num(den[i]),
                      if (is.na(pct[i])) ", sin denominador"
                      else sprintf(" = %s", fmt_pct(round(pct[i], 1))))
    if (is.na(pct[i]) || pct[i] <= 0) {
      return(sv("g", class = "graf-barra", sv("title", titulo)))
    }
    x <- round(cx(i) - ancho / 2, 1)
    y <- py(pct[i])
    sv("g", class = paste("graf-barra", if (curso) "en-curso"),
       sv("title", titulo),
       sv("rect", class = "graf-barra-periodo", x = x, y = y,
          width = ancho, height = round(Y1 - y, 1)),
       if (curso)
         sv("rect", class = "graf-marco-curso", x = x, y = y,
            width = ancho, height = round(Y1 - y, 1)),
       if (i %in% vis_n && ancho >= SEM_ANCHO_ETIQUETA)
         sv("text", class = "graf-rotulo-total", x = cx(i), y = round(y - 6, 1),
            `text-anchor` = "middle", fmt_pct(round(pct[i], 1))))
  })

  # La linea del acumulado arranca en el primer periodo con denominador: antes
  # de eso no hay razon que calcular, y unir desde el cero dibujaria una subida
  # que no ocurrio.
  hay <- which(!is.na(pct_ac))
  linea <- if (length(hay) >= 2) {
    pts <- paste0(cx(hay), ",", py(pct_ac[hay]))
    list(
      sv("path", class = "graf-linea-acum",
         d = paste0("M", paste(pts, collapse = "L"))),
      sv("circle", class = "graf-punto-fin", cx = cx(max(hay)),
         cy = py(pct_ac[max(hay)]), r = 4))
  }

  ult_ac <- if (length(hay)) pct_ac[max(hay)] else NA_real_

  leyenda <- span(
    class = "graf-leyenda",
    span(class = "graf-llave periodo", `aria-hidden` = "true"),
    span(class = "graf-llave-txt", if (sem) "% de la semana" else "% del día"),
    span(class = "graf-llave acumulado", `aria-hidden` = "true"),
    span(class = "graf-llave-txt", sprintf("%% acumulado %s", fmt_pct(round(ult_ac, 1)))))

  resumen <- sprintf(
    "%s por %s, de %s a %s. %s acumulado: %s de %s, %s.",
    ind$nombre, if (sem) "semana" else "día", rango(1), rango(n),
    ind$nombre, fmt_num(num_ac[n]), fmt_num(den_ac[n]),
    fmt_pct(round(ult_ac, 1)))

  div(
    class = "grafico-acum grafico-barras grafico-ind",
    cab(izq = leyenda,
        der = tagList(
          span(class = "grafico-cifra",
               sprintf("%s %s", fmt_num(num_ac[n]), ind$unidad)),
          control)),

    sv("svg", class = "graf-svg", viewBox = sprintf("0 0 %d %d", W, H),
       role = "img", `aria-label` = resumen,
       preserveAspectRatio = "xMidYMid meet",
       rejilla,
       lapply(vis_x, function(i) sv(
         "text",
         class = paste("graf-eje-x", if (isTRUE(per$en_curso[i])) "en-curso"),
         x = cx(i), y = Y1 + 18, `text-anchor` = "middle",
         paste0(nom[i], if (isTRUE(per$en_curso[i])) "*" else ""))),
       barras,
       linea),

    div(class = "grafico-nota", ind$pie,
        if (any(per$en_curso))
          sprintf(" El último %s está en curso (*): llega hasta hoy.",
                  if (sem) "periodo" else "día")),

    # Equivalente en texto, igual que en los otros dos graficos.
    tags$table(
      class = "visually-hidden",
      tags$caption(resumen),
      tags$thead(tags$tr(
        tags$th(if (sem) "Semana" else "Día"),
        tags$th("Numerador"), tags$th("Denominador"),
        tags$th("% del periodo"), tags$th("% acumulado"))),
      tags$tbody(lapply(seq_len(n), function(i) tags$tr(
        tags$td(sprintf("%s, %s", nom[i], rango(i))),
        tags$td(fmt_num(num[i])),
        tags$td(fmt_num(den[i])),
        tags$td(if (is.na(pct[i]))    "—" else fmt_pct(round(pct[i], 1))),
        tags$td(if (is.na(pct_ac[i])) "—" else fmt_pct(round(pct_ac[i], 1)))))))
  )
}


# --- personas borradas ----------------------------------------------------------
# Ver seg_borrar_persona(). Se borra desde los dos recuadros del final de Avance
# y se restaura desde Administracion (mod_borradas_*).

# Cambios de la lista, contados en el proceso y no en la sesion, como
# CIT_CARGAS: quien tiene Administracion abierta ve lo que borro otra persona.
SEG_BORRADAS <- reactiveVal(0)

# De que recuadro se borro, para la bitacora y la lista de Administracion.
SEG_BORRADA_ORIGEN <- c(citados_dia    = "Quién no contestó",
                        no_registrados = "Sin estar en el marco")

boton_borrar <- function(id, origen) {
  tags$button(type = "button", class = "btn btn-sm btn-outline-danger ms-1",
              `data-borrar` = id, `data-origen` = origen,
              `aria-label` = paste("Borrar a", id), "Borrar")
}

modal_borrar <- function(ns, id, nombre) {
  quien <- if (is.na(nombre) || !nzchar(nombre)) id else sprintf("%s (%s)", nombre, id)
  modalDialog(
    title = "¿Está seguro de que quiere borrar a esta persona?",
    easyClose = FALSE,
    p(tags$b(quien)),
    tags$ul(class = "small",
      tags$li("Deja de verse en la aplicación: no cuenta como citada ni como ",
              "encuestada, y sale de los grupos, de Avance y de Resultados."),
      tags$li("No vuelve a la agenda aunque siga en el Google Sheet."),
      tags$li("Sus respuestas de ODK no se borran de la base.")),
    p(class = "small text-muted mb-0",
      "Si fue un error, se puede restaurar desde Administración › Personas borradas."),
    footer = tagList(
      modalButton("Cancelar"),
      actionButton(ns("borrar_ok"), "Sí, borrar", class = "btn-danger"))
  )
}

mod_borradas_ui <- function(id) {
  ns <- NS(id)
  tagList(
    tags$script(HTML(sprintf(
      "$(document).on('click', '#%s [data-restaurar]', function(){
         Shiny.setInputValue('%s', String($(this).attr('data-restaurar')),
                             {priority: 'event'});
       });", ns("tabla"), ns("restaurar")))),
    h5("Personas borradas", class = "mb-1"),
    p(class = "small text-muted mb-2",
      "Las que se borraron desde Avance. No cuentan en ninguna parte de la ",
      "aplicación. Al restaurarlas vuelven a contar de inmediato; a la agenda ",
      "vuelven con la siguiente actualización desde el Google Sheet."),
    uiOutput(ns("tabla"))
  )
}

mod_borradas_server <- function(id, r = reactiveValues()) {
  moduleServer(id, function(input, output, session) {
    puede <- function() isTRUE(tryCatch(
      auth_puede_usuario(r$usuario$usuario, "borrar_personas"),
      error = function(e) FALSE))

    lista <- reactive({
      SEG_BORRADAS()
      invalidateLater(60 * 1000)
      req(puede())
      seg_personas_borradas()
    })

    output$tabla <- renderUI({
      p <- lista()
      if (nrow(p) == 0) return(div(class = "small text-muted", "No hay personas borradas."))
      cuando <- function(x) format(as.POSIXct(x), "%d/%m/%Y %H:%M", tz = SEG_TZ)
      filas <- lapply(seq_len(nrow(p)), function(i) {
        f <- p[i, ]
        tags$tr(
          tags$td(class = "col-id",
                  if (is.na(f$nombre)) f$id_anonimizado
                  else tagList(span(class = "col-nombre", f$nombre),
                               span(class = "col-medio", f$id_anonimizado))),
          tags$td(SEG_BORRADA_ORIGEN[f$origen] %||% f$origen),
          tags$td(f$borrado_por),
          tags$td(class = "col-fecha", cuando(f$borrado_en)),
          tags$td(class = "col-accion",
                  tags$button(type = "button", class = "btn btn-sm btn-outline-primary",
                              `data-restaurar` = f$id_anonimizado,
                              `aria-label` = paste("Restaurar a", f$id_anonimizado),
                              "Restaurar")))
      })
      div(class = "tabla-dep-caja",
          tags$table(
            class = "tabla-dep tabla-per tabla-dia",
            tags$thead(tags$tr(tags$th("Persona"), tags$th("Desde"), tags$th("Borrada por"),
                               tags$th("Fecha"), tags$th(""))),
            tags$tbody(filas)))
    })

    observeEvent(input$restaurar, {
      id <- input$restaurar
      if (!puede()) {
        showNotification("No tiene permiso para restaurar personas.", type = "error")
        return()
      }
      res <- tryCatch({ seg_restaurar_persona(id); NULL },
                      error = function(e) conditionMessage(e))
      if (!is.null(res)) {
        showNotification(paste("No se pudo restaurar:", res), type = "error")
        return()
      }
      try(auth_bitacora("persona_restaurada", r$usuario$usuario, id,
                        r$usuario$origen %||% NA_character_), silent = TRUE)
      showNotification(paste("Persona restaurada. Si está en el Google Sheet, vuelve a la",
                             "agenda en la próxima actualización (máximo 30 minutos)."),
                       type = "message")
      SEG_BORRADAS(SEG_BORRADAS() + 1)
      r$respuestas <- isolate(r$respuestas) + 1
    })
  })
}


# --- informe en Word ----------------------------------------------------------
# Solo para administradores (permiso `informe_avance`): se baja desde la pestana
# Administracion, que monta mod_informe_ui()/mod_informe_server() igual que monta
# la carga de la agenda. Estaba encima de los cajones de Avance y se saco de ahi
# a proposito; ese modulo ya no tiene ninguna salida que lo genere, asi que
# tampoco se puede pedir a mano desde el navegador.
#
# Las cifras no se recalculan aqui: salen de las mismas funciones que la
# pantalla de Avance --seg_totales(), seg_totales_indicadores(),
# seg_periodos()--, asi que con los mismos filtros el informe cierra en los
# mismos numeros que los cajones.

mod_informe_ui <- function(id) {
  ns <- NS(id)
  tagList(
    h5("Informe de avance (Word)", class = "mb-1"),
    p(class = "small text-muted mb-2",
      "Las cifras de la pestaña Avance por dependencia —indicadores, avance por ",
      "semana y por día, y dependencias completadas y pendientes— en un documento ",
      "de Word. Sin filtros, cubre toda la universidad."),
    div(class = "d-flex flex-wrap gap-3 align-items-end",
        div(style = "min-width:260px;",
            selectizeInput(ns("tipos"), "Unidad", choices = NULL, multiple = TRUE,
                           width = "100%", options = list(placeholder = "Todas"))),
        div(class = "mb-3",
            downloadButton(ns("bajar"), "Descargar informe (Word)",
                           class = "btn-outline-primary")))
  )
}

mod_informe_server <- function(id, r = reactiveValues()) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Se vuelve a leer el rol en la base en cada descarga, como las demas
    # acciones de Administracion: pudo cambiar con la sesion abierta.
    puede <- function() isTRUE(tryCatch(
      auth_puede_usuario(r$usuario$usuario, "informe_avance"),
      error = function(e) FALSE))

    # Mismos filtros de la barra de Avance, menos el buscador: aqui no hay un
    # listado sobre el que buscar.
    observe({
      updateSelectizeInput(session, "tipos", choices = seg_tipos_dependencia(),
                           server = FALSE)
    })

    output$bajar <- downloadHandler(
      filename = function() sprintf("informe_avance_%s.docx", format(seg_hoy(), "%Y%m%d")),
      content  = function(archivo) {
        if (!puede()) stop("Sin permiso para descargar el informe.", call. = FALSE)
        filtros <- c(
          if (length(input$tipos)) paste("Unidad:", paste(input$tipos, collapse = ", ")))
        informe_word(seg_avance(input$tipos), archivo, filtros,
                     seg_inicio_campo(), sin_marco = length(input$tipos) == 0)
      }
    )
  })
}
#
# Las tablas por periodo llevan los encuestados NUEVOS del periodo y el resto
# ACUMULADO hasta su cierre: la ultima fila de cada una es la fila de cajones.
#
#   Cobertura Citados    encuestados / citados cuya hora ya paso
#   Cobertura Esperados  encuestados / personas del marco
#   Efectividad          efectivas (aceptaron) / encuestados
#   No efectivas         encuestados que no aceptaron / encuestados
#
# En la tabla diaria solo van los dias con movimiento: los fines de semana y los
# dias sin campo serian filas de ceros que no dicen nada.
#
# Una dependencia esta COMPLETADA cuando no le falta nadie (faltan = 0, que ya
# descuenta los casos cerrados por la bitacora) y PENDIENTE en cualquier otro
# caso, asi que las dos listas suman todas las dependencias de la seleccion.

# Porcentajes y numeros con los mismos formatos de la pantalla, elemento por
# elemento (fmt_num() solo pinta la raya cuando TODO el vector es NA).
inf_pct <- function(x) vapply(x, function(v) fmt_pct(round(v, 1)), "")
inf_num <- function(x) vapply(x, function(v) fmt_num(v), "")
# El denominador se recicla al largo del numerador: el del marco es un solo
# numero, y ifelse() devolveria entonces un solo valor para toda la columna.
inf_razon <- function(num, den) {
  den <- rep_len(den, length(num))
  ifelse(den > 0, 100 * num / den, NA_real_)
}

# Filas de la tabla de un periodo: semana o dia.
inf_tabla_periodos <- function(per, marco, semanal = TRUE) {
  if (is.null(per) || nrow(per) == 0) return(NULL)
  if (!semanal) {
    per <- per[per$encuestados > 0 | per$efectivas > 0 | per$citados > 0, , drop = FALSE]
    if (nrow(per) == 0) return(NULL)
  }
  enc  <- per$encuestados_ac
  comp <- per$efectivas_ac
  noef <- enc - comp
  periodo <- if (semanal) {
    sprintf("S%s · %s%s", seq_len(nrow(per)), rango_corto(per$inicio, per$fin),
            ifelse(per$en_curso, " *", ""))
  } else {
    paste0(format(per$inicio, "%d/%m/%Y"), ifelse(per$en_curso, " *", ""))
  }
  data.frame(
    check.names = FALSE, stringsAsFactors = FALSE,
    "Periodo"                   = periodo,
    "Encuestados nuevos"        = inf_num(per$encuestados),
    "Encuestados acumulados"    = inf_num(enc),
    "Cobertura Citados %"       = inf_pct(inf_razon(enc, per$citados_ac)),
    "Cobertura Esperados %"     = inf_pct(inf_razon(enc, marco)),
    "Efectividad n"             = inf_num(comp),
    "Efectividad %"             = inf_pct(inf_razon(comp, enc)),
    "No efectivas n"            = inf_num(noef),
    "No efectivas %"            = inf_pct(inf_razon(noef, enc))
  )
}

# Formato comun de todas las tablas: cabecera en el verde institucional,
# numeros a la derecha y ancho ajustado a la pagina.
#
# Los anchos se fijan a mano, en pesos relativos que se reparten en el ancho
# util de la hoja horizontal. Ni el ajuste automatico de Word ni autofit() de
# flextable servian: los dos miden con otra fuente que la que termina usando el
# procesador, y la primera columna quedaba estrecha y partia la semana y los
# nombres en dos o tres renglones. Sin pesos, todas las columnas iguales.
# Pulgadas utiles de una carta horizontal con los margenes por defecto.
INF_ANCHO_PAGINA <- 9

inf_flex <- function(df, pesos = rep(1, ncol(df))) {
  ft <- flextable::flextable(df)
  ft <- flextable::theme_vanilla(ft)
  ft <- flextable::bg(ft, bg = UDEA_VERDE, part = "header")
  ft <- flextable::color(ft, color = "white", part = "header")
  ft <- flextable::bold(ft, part = "header")
  ft <- flextable::fontsize(ft, size = 9, part = "body")
  # Un punto menos en la cabecera: en negrita y a 9 las palabras largas
  # ("Encuestados", "Efectividad") no cabian y Word las partia por la mitad.
  ft <- flextable::fontsize(ft, size = 8, part = "header")
  ft <- flextable::align(ft, j = seq_len(ncol(df))[-1], align = "right", part = "all")
  ft <- flextable::width(ft, width = INF_ANCHO_PAGINA * pesos / sum(pesos))
  flextable::set_table_properties(ft, layout = "fixed")
}

informe_word <- function(a, archivo, filtros = character(0), desde = NULL,
                         sin_marco = FALSE) {
  deps  <- sort(a$dependencia)
  vacio <- nrow(a) == 0
  t     <- seg_totales(a)
  # Sin dependencias no se consulta: la lista vacia el SQL la lee como "todas"
  # (ver output$indicadores). Se arma en ceros, como los cajones.
  ti    <- if (vacio) list(total = list(encuestados = 0L, efectivas = 0L,
                                        no_efectivas = 0L, cob_citados = NA_real_,
                                        cob_esperados = NA_real_, efectividad = NA_real_,
                                        pct_no_efectivas = NA_real_))
           else seg_totales_indicadores(deps, sin_marco = sin_marco)
  marco <- if (vacio) 0L else seg_marco_total(deps)
  serie <- if (vacio) NULL else seg_serie_indicadores(deps, sin_marco = sin_marco)
  sem   <- inf_tabla_periodos(seg_periodos(serie, "semana", desde = desde), marco, TRUE)
  dia   <- inf_tabla_periodos(seg_periodos(serie, "dia",    desde = desde), marco, FALSE)

  tot <- ti$total
  resumen <- data.frame(
    check.names = FALSE, stringsAsFactors = FALSE,
    "Indicador" = c("Esperados", "Encuestados", "Encuestados forma A",
                    "Encuestados forma B", "Faltan", "Cobertura Citados",
                    "Cobertura Esperados", "Efectividad", "No efectivas",
                    "Dependencias", "Dependencias completadas"),
    "Número" = c(inf_num(t$planeado), inf_num(t$encuestados), inf_num(t$encuestados_a),
                 inf_num(t$encuestados_b), inf_num(t$faltan),
                 inf_num(tot$encuestados), inf_num(tot$encuestados),
                 inf_num(tot$efectivas), inf_num(tot$no_efectivas),
                 inf_num(t$dependencias), inf_num(sum(a$faltan == 0))),
    "Porcentaje" = c("", "", "", "", "",
                     inf_pct(tot$cob_citados), inf_pct(tot$cob_esperados),
                     inf_pct(tot$efectividad), inf_pct(tot$pct_no_efectivas),
                     "", "")
  )

  comp <- a[a$faltan == 0, , drop = FALSE]
  comp <- comp[order(comp$dependencia), , drop = FALSE]
  t_comp <- if (nrow(comp)) data.frame(
    check.names = FALSE, stringsAsFactors = FALSE,
    "Dependencia" = comp$dependencia,
    "Unidad"      = ifelse(is.na(comp$tipo_dependencia), "", comp$tipo_dependencia),
    "Esperados"   = inf_num(comp$planeado),
    "Encuestados" = inf_num(comp$encuestados),
    "% encuestados" = inf_pct(inf_razon(comp$encuestados, comp$planeado)))

  pend <- a[a$faltan > 0, , drop = FALSE]
  pend <- pend[order(-pend$faltan, pend$dependencia), , drop = FALSE]
  t_pend <- if (nrow(pend)) data.frame(
    check.names = FALSE, stringsAsFactors = FALSE,
    "Dependencia" = pend$dependencia,
    "Unidad"      = ifelse(is.na(pend$tipo_dependencia), "", pend$tipo_dependencia),
    "Esperados"   = inf_num(pend$planeado),
    "Pendientes"  = inf_num(pend$faltan),
    "% pendientes" = inf_pct(inf_razon(pend$faltan, pend$planeado)))

  doc <- officer::read_docx()
  doc <- officer::body_set_default_section(
    doc, officer::prop_section(page_size = officer::page_size(orient = "landscape")))

  titulo <- function(d, x) officer::body_add_par(d, x, style = "heading 2")
  nota   <- function(d, x) officer::body_add_par(d, x, style = "Normal")
  tabla  <- function(d, df, sin, pesos = rep(1, ncol(df))) {
    if (is.null(df)) nota(d, sin) else flextable::body_add_flextable(d, inf_flex(df, pesos))
  }
  # Periodo ancho y las ocho cifras iguales; en las dependencias, el nombre y la
  # unidad se llevan casi todo.
  p_per <- c(1.5, rep(1, 8))
  p_dep <- c(3, 2.6, 1, 1.2, 1.2)

  doc <- officer::body_add_par(doc, "Seguimiento riesgo psicosocial: informe de avance",
                               style = "heading 1")
  doc <- nota(doc, sprintf("Generado el %s.", format(Sys.time(), "%d/%m/%Y %H:%M", tz = SEG_TZ)))
  doc <- nota(doc, if (length(filtros)) paste("Filtros:", paste(filtros, collapse = "; "))
                   else "Sin filtros: toda la universidad.")

  doc <- titulo(doc, "Resumen general")
  doc <- tabla(doc, resumen, "", c(3, 1.2, 1.2))

  doc <- titulo(doc, "Avance semanal acumulado")
  doc <- nota(doc, paste("Encuestados nuevos de cada semana; el resto, acumulado al cierre",
                         "de la semana. * semana en curso."))
  doc <- tabla(doc, sem, "Todavía no hay datos en esta selección.", p_per)

  doc <- titulo(doc, "Avance diario")
  doc <- nota(doc, paste("Solo los días con movimiento. Encuestados nuevos del día; el resto,",
                         "acumulado al cierre del día. * hoy."))
  doc <- tabla(doc, dia, "Todavía no hay datos en esta selección.", p_per)

  doc <- titulo(doc, sprintf("Dependencias completadas (%s)", nrow(comp)))
  doc <- tabla(doc, t_comp, "Ninguna dependencia está completada todavía.", p_dep)

  doc <- titulo(doc, sprintf("Dependencias pendientes (%s)", nrow(pend)))
  doc <- nota(doc, "De la que tiene más personas pendientes a la que tiene menos.")
  doc <- tabla(doc, t_pend, "No queda ninguna dependencia pendiente.", p_dep)

  print(doc, target = archivo)
  invisible(archivo)
}

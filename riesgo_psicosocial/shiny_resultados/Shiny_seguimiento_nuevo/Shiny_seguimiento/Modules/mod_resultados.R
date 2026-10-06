# Modules/mod_resultados.R
# Módulo 3: resultados de la Batería por segmentos de población.
#
#   mod_resultados_ui(id)
#   mod_resultados_server(id, r)
#
# La pantalla está ordenada como el recorrido que hace quien la usa, y cada
# sección contesta UNA pregunta:
#
#   Cabecera        ¿a quién estoy mirando, y cuántos son?
#   Resumen         ¿cómo está en lo general, y contra la universidad?
#   Ranking         ¿qué medidas están peor, o más lejos del conjunto?
#   Focos           ¿por dónde empiezo a mirar?
#   Desagregación   ¿qué grupos dentro del segmento se separan?
#   Mapa            ¿hay un patrón medida x grupo?
#   Tabla           los números exactos, para un informe.
#
# Dos gestos, y la diferencia manda en todo lo demás:
#
#   FILTRAR     restringe la población. Lo que queda es el SEGMENTO.
#   DESAGREGAR  parte el segmento en grupos para compararlos. Es opcional.
#
# La pantalla va partida en los TRES cuestionarios de la Batería
# --intralaboral, extralaboral y estrés-- y dentro de cada uno se elige la
# FORMA: A, B o las dos juntas. No es decoración. Cada cuestionario tiene su
# propia población, su propia referencia y su propio juego de medidas, y
# ponerlos en una sola lista invitaba a restar un dominio con una dimensión que
# ya está contada dentro de él. Dentro de un cuestionario las filas sí son
# comparables; entre cuestionarios no.
#
# La forma es una VISTA y no un bloque aparte, porque la pregunta de quien mira
# es "cómo va el intralaboral" y no "cómo va la forma A". Elegir una forma
# cambia la población del cuestionario y con ella su referencia: la forma B se
# compara contra la forma B de la universidad. La vista se elige en el ranking
# y la siguen el mapa, la tabla de datos detallados y el Excel, para que la
# misma medida no dé dos cifras distintas según dónde se mire.
#
# Sobre el lenguaje: todas las diferencias son DESCRIPTIVAS --la resta de dos
# porcentajes observados--. No hay prueba de hipótesis detrás de ninguna cifra
# de esta pantalla, así que no se usa "significativo" ni lenguaje causal.
#
# Los cálculos viven en R/utils_resultados.R; aquí solo hay etiquetas. Los
# estilos viven en www/custom.css.

mod_resultados_ui <- function(id) {
  ns <- NS(id)

  fluidPage(
    # Manejadores delegados, como en mod_seguimiento.R: renderUI rehace estos
    # nodos con cada cambio, y un listener pegado al nodo se iría con el nodo.
    tags$script(HTML(sprintf(
      "$(document).on('click', '#%s [data-quitar]', function(){
         Shiny.setInputValue('%s', Date.now() + '|' + $(this).data('quitar'),
                             {priority: 'event'});
       });
       $(document).on('click keydown', '#%s [data-dim]', function(e){
         if (e.type === 'keydown' && e.key !== 'Enter' && e.key !== ' ') return;
         if (e.type === 'keydown') e.preventDefault();
         Shiny.setInputValue('%s', $(this).data('dim'), {priority: 'event'});
       });
       $(document).on('click', '#%s [data-plegar], #%s [data-plegar]', function(){
         var abierto = $(this).attr('aria-expanded') === 'true';
         $(this).closest('tbody').toggleClass('plegado', abierto);
         $(this).attr('aria-expanded', abierto ? 'false' : 'true');
       });
       // La forma se elige con botones de verdad y no con un radioButtons:
       // renderUI rehace estos nodos con cada filtro, y un input de Shiny
       // metido ahi se reconstruiria y perderia lo elegido. El estado vive en
       // R (ver `vistas` en el server) y estos manejadores solo lo avisan.
       $(document).on('click', '#%s [data-vista]', function(e){
         e.preventDefault(); e.stopPropagation();
         Shiny.setInputValue('%s', $(this).data('vista') + '|' + Date.now(),
                             {priority: 'event'});
       });
       // Que cuestionario queda desplegado tambien se guarda en R: al cambiar
       // de vista el bloque se vuelve a dibujar, y sin esto se cerraria justo
       // el que se esta mirando. El evento 'toggle' de <details> no burbujea,
       // asi que se escucha el clic en el <summary> y se manda el estado que
       // va a quedar, que es el contrario del actual.
       $(document).on('click', '#%s details.res-bl > summary', function(){
         var d = $(this).closest('details');
         Shiny.setInputValue('%s',
           d.attr('data-bloque') + '|' + (d.prop('open') ? '0' : '1') +
           '|' + Date.now(), {priority: 'event'});
       });",
      ns("chips"), ns("quitar"), ns("ranking"), ns("dim_click"),
      ns("tabla"), ns("mapa"), ns("ranking"), ns("vista"),
      ns("ranking"), ns("abrir")))),

    # Los cuestionarios del mapa nacen plegados, y el mapa se redibuja con cada
    # cambio de métrica, tope o filtro: sin recordar en R cuál se desplegó, cada
    # uno de esos cambios lo volvería a cerrar. Este manejador va DESPUÉS del
    # que conmuta la clase, así que lee el estado que acaba de quedar.
    tags$script(HTML(sprintf(
      "$(document).on('click', '#%s [data-plegar]', function(){
         Shiny.setInputValue('%s',
           $(this).data('bloque') + '|' + $(this).attr('aria-expanded') +
           '|' + Date.now(), {priority: 'event'});
       });
       if (!window.resPlegarRegistrado) {
         window.resPlegarRegistrado = true;
         Shiny.addCustomMessageHandler('res-plegar', function(id){
           $('#' + id).prop('open', false);
         });
       }",
      ns("mapa"), ns("mapa_abrir")))),

    uiOutput(ns("cabecera")),
    uiOutput(ns("reserva")),

    # --- panel de control: dos bloques, porque son dos preguntas distintas ---
    div(
      class = "res-control",

      div(
        class = "res-bloque res-bloque-filtrar",
        div(class = "res-bloque-cab",
            span(class = "res-bloque-eyebrow", "Filtrar población"),
            span(class = "res-bloque-preg", "¿A quién quiero analizar?")),
        uiOutput(ns("chips")),
        tags$details(
          class = "res-desplegable",
          tags$summary(uiOutput(ns("resumen_filtros"), inline = TRUE)),
          div(class = "res-filtros-rejilla", uiOutput(ns("filtros")))
        )
      ),

      div(
        class = "res-bloque res-bloque-desagregar",
        div(class = "res-bloque-cab",
            span(class = "res-bloque-eyebrow", "Desagregar"),
            span(class = "res-bloque-preg", "¿Con qué grupos comparar?")),
        selectInput(ns("desagregar"), NULL, width = "100%",
                    choices  = c("No desagregar" = "",
                                 stats::setNames(names(RES_CRUCES), unname(RES_CRUCES))),
                    selected = ""),
        # Solo aparece con un cruce elegido: sin desagregación no hay nada que
        # quitar. Es un conditionalPanel y no un renderUI para que el selector
        # de arriba no se reconstruya al aparecer el botón.
        conditionalPanel(
          condition = "input.desagregar !== ''", ns = ns,
          actionButton(ns("quitar_desag"), "Quitar desagregación",
                       icon = icon("xmark"),
                       class = "btn-sm btn-outline-secondary res-quitar-desag")),
        radioButtons(ns("comparar"), "Comparar con", inline = TRUE,
                     choices  = c("Universidad" = "univ", "Sin comparación" = "no"),
                     selected = "univ")
      )
    ),

    uiOutput(ns("resumen")),

    # --- resumen descriptivo ---
    # Va aquí, antes del ranking, porque es de quién hablan las cifras de abajo;
    # y nace plegado porque es contexto que se lee una vez (ver
    # res_descriptivo_ui()).
    #
    # El <details> y los mandos del cruce son ESTÁTICOS, por la misma razón que
    # las cabeceras de sección: dentro de un renderUI cada cambio de filtro
    # devolvía los selectores a su valor inicial y volvía a plegar la sección.
    # Solo se redibuja lo que depende del segmento.
    conditionalPanel(
      condition = "output.hay_segmento", ns = ns,
      tags$details(
        class = "res-desc",
        tags$summary(
          class = "res-desc-sum",
          div(class = "res-desc-sum-tit", "Resumen descriptivo"),
          uiOutput(ns("desc_sub"), class = "res-desc-sum-sub")),
        div(
          class = "res-desc-cuerpo",
          uiOutput(ns("descriptivo")),
          div(
            class = "res-desc-bloque res-cruce",
            h6("Cruce de dos variables"),
            p(class = "text-muted small",
              "Elija dos de las variables de arriba para ver cómo se reparten",
              "juntas: una va en las filas y otra en las columnas."),
            div(
              class = "res-cruce-mandos",
              selectInput(ns("cruce_fila"), "Filas", width = "100%",
                          choices = res_desc_opciones_cruce(), selected = "edad"),
              selectInput(ns("cruce_col"), "Columnas", width = "100%",
                          choices = res_desc_opciones_cruce(), selected = "sexo"),
              div(class = "res-interruptor",
                  radioButtons(ns("cruce_pct"), "Porcentaje", inline = TRUE,
                               choices = RES_DESC_PCT, selected = "fila"))),
            uiOutput(ns("desc_cruce")))
        )
      )
    ),

    # --- ¿qué está pasando? ---
    # La cabecera y sus dos mandos son ESTÁTICOS a propósito. Metidos en un
    # renderUI, como estaban, cada cambio de filtro los reconstruía: el
    # desplegable parpadeaba y quien navega con teclado perdía el foco. Lo
    # único que cambia es la nota, que sí depende de si hay comparación.
    conditionalPanel(
      condition = "output.hay_segmento", ns = ns,
      div(
        class = "res-seccion-cab",
        div(h5("¿Qué está pasando?"),
            # El sentido de la escala no es evidente y se lee al revés de lo
            # que la costumbre sugiere: en casi cualquier tablero, más por
            # ciento es mejor. Aquí todas las cifras son el porcentaje de gente
            # en riesgo alto o muy alto, así que subir es empeorar. Va en
            # negrilla y antes de los datos porque una vez leidos con el signo
            # cambiado ya no se corrigen solos.
            p(class = "res-aviso-escala mb-1",
              tags$strong("Importante: a mayor porcentaje, mayor es el nivel ",
                          "de riesgo y por tanto peores son los resultados.")),
            uiOutput(ns("ranking_nota"))),
        div(
          class = "res-seccion-mandos",
          div(style = "min-width:250px;",
              selectInput(ns("orden"), "Ordenar dentro de cada bloque",
                          width = "100%", choices = RES_ORDENES,
                          selected = "estructura")),
          div(class = "res-interruptor",
              radioButtons(ns("vista_perfil"), "Ver", inline = TRUE,
                           choices  = c("Comparación" = "comp",
                                        "Distribución" = "dist"),
                           selected = "comp")))
      )
    ),
    uiOutput(ns("ranking")),

    # --- datos detallados ---
    # Justo debajo del ranking porque son SUS números en texto --la misma
    # lista, la misma forma por cuestionario--, y plegados porque quien ya leyó
    # el ranking solo los abre para copiar una cifra o bajar el Excel. Van
    # antes que los focos y la desagregación, que es análisis aparte y queda al
    # final. El <details> y sus mandos son estáticos: dentro de un renderUI la
    # búsqueda se borraba y la sección se volvía a plegar con cada filtro.
    conditionalPanel(
      condition = "output.hay_segmento", ns = ns,
      tags$details(
        class = "res-desag res-detalle",
        tags$summary(
          class = "res-desag-sum",
          tags$span(class = "res-desag-flecha", `aria-hidden` = "true"),
          div(div(class = "res-desag-sum-tit", "Datos detallados"),
              div(class = "res-desag-sum-sub",
                  "Los números de «¿Qué está pasando?» en texto, con buscador",
                  "y descarga en Excel."))),
        div(
          class = "res-desag-cuerpo",
          div(
            class = "res-seccion-cab",
            p(class = "text-muted small mb-0",
              "Los mismos números en texto, sin depender del color. Un bloque",
              "por cuestionario y con la forma elegida arriba, como el ranking."),
            div(class = "res-seccion-mandos",
                div(style = "min-width:220px;",
                    textInput(ns("buscar"), "Buscar medida", width = "100%",
                              placeholder = "Escriba parte del nombre")),
                div(class = "res-interruptor",
                    radioButtons(ns("orden_tabla"), "Orden dentro de cada bloque",
                                 inline = TRUE,
                                 choices  = c("Estructura del instrumento" = "jer",
                                              "Por riesgo" = "rk"),
                                 selected = "jer")),
                div(class = "res-bajar",
                    downloadButton(ns("bajar"), "Descargar Excel",
                                   class = "btn-sm btn-outline-secondary")))),
          uiOutput(ns("tabla"))
        )
      )
    ),

    uiOutput(ns("focos")),

    # --- desagregación ---
    # Estática por la misma razón que la de arriba. El selector de medida vivía
    # dentro del renderUI que dibuja los grupos, y los grupos dependen de la
    # medida: elegir otra rehacía el propio selector, que parpadeaba y se
    # llevaba el foco. Solo el título, que depende del cruce, se redibuja.
    #
    # Toda la sección va dentro de un <details> que nace PLEGADO: con un cruce
    # de 40 grupos la distribución y el mapa ocupan varias pantallas, y quien
    # solo quería elegir el cruce se encontraba empujado lejos de todo lo demás.
    # Es estático, como sus mandos, así que cambiar un filtro no lo vuelve a
    # cerrar; sí se cierra cada vez que se AÑADE una desagregación (ver el
    # observeEvent de desagregar() en el server).
    conditionalPanel(
      condition = "output.hay_grupos", ns = ns,
      tags$details(
        id = ns("desag_det"),
        class = "res-desag",
        tags$summary(
          class = "res-desag-sum",
          tags$span(class = "res-desag-flecha", `aria-hidden` = "true"),
          div(div(class = "res-desag-sum-tit", "Resultados de la desagregación"),
              uiOutput(ns("desag_sub"), class = "res-desag-sum-sub"))),
        div(
          class = "res-desag-cuerpo",
          div(
            class = "res-seccion-cab",
            uiOutput(ns("desag_titulo")),
            div(class = "res-seccion-mandos",
                div(style = "min-width:290px;",
                    selectInput(ns("medida"), "Medida a comparar", width = "100%",
                                choices  = res_opciones_medida(),
                                selected = "tot_estres")))),
          uiOutput(ns("desagregacion")),

          conditionalPanel(
            condition = "output.hay_mapa", ns = ns,
            div(
              class = "res-seccion-cab",
              div(
                h5("Mapa de medidas por grupo"),
                p(class = "text-muted small mb-0",
                  "Se lee por filas: qué medida aprieta, y en qué grupo. Las",
                  "columnas son las mismas en los tres cuestionarios, así que un",
                  "grupo se sigue de arriba abajo. Cada cuestionario usa la forma",
                  "elegida arriba y nace plegado: despliegue el que quiera ver.")),
              div(
                class = "res-seccion-mandos",
                # Sin comparación no hay diferencia que pintar: la métrica se
                # esconde y el mapa se queda en el porcentaje.
                conditionalPanel(
                  condition = "input.comparar === 'univ'", ns = ns,
                  div(class = "res-interruptor",
                      radioButtons(ns("metrica"), "Métrica", inline = TRUE,
                                   choices  = c("% riesgo alto" = "pct",
                                                "Diferencia vs universidad" = "delta"),
                                   selected = "pct"))),
                conditionalPanel(
                  condition = "output.muchos_grupos", ns = ns,
                  div(style = "min-width:150px;",
                      selectInput(ns("tope"), "Mostrar", width = "100%",
                                  choices = RES_TOPES_GRUPO, selected = "20")))
              )
            )
          ),
          uiOutput(ns("mapa"))
        )
      )
    )
  )
}


mod_resultados_server <- function(id, r = reactiveValues()) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Una sola consulta por sesión. Todo el filtrado y la agregación ocurren en
    # R sobre este data.frame.
    datos <- reactive({
      if (!res_hay_datos()) return(NULL)
      res_datos()
    })

    # --- filtros -------------------------------------------------------------

    # Los selectores se dibujan una vez desde los datos y NO leen sus propios
    # valores: si lo hicieran se reconstruirían con cada selección y perderían
    # lo que se acaba de marcar.
    output$filtros <- renderUI({
      d <- datos()
      if (is.null(d) || nrow(d) == 0) return(NULL)
      lapply(names(RES_CRUCES), function(cv) {
        selectizeInput(
          ns(paste0("f_", cv)), RES_CRUCES[[cv]],
          choices  = sort(unique(as.character(d[[cv]]))),
          multiple = TRUE, width = "100%",
          options  = list(placeholder = "Todas", plugins = list("remove_button")))
      })
    })

    filtros <- reactive({
      d <- datos()
      if (is.null(d)) return(list())
      crudos <- lapply(names(RES_CRUCES), function(cv) input[[paste0("f_", cv)]])
      names(crudos) <- names(RES_CRUCES)
      res_filtros_vivos(d, crudos)
    })

    n_filtros <- reactive(sum(lengths(filtros())))

    output$resumen_filtros <- renderUI({
      n <- n_filtros()
      span(class = "res-contador",
           if (n == 0) "Sin filtros: toda la universidad. Abrir para elegir."
           else sprintf("%s %s activo%s. Abrir para cambiar.",
                        fmt_num(n), if (n == 1) "filtro" else "filtros",
                        if (n == 1) "" else "s"))
    })

    # Fichas de lo que está aplicado, cada una con su aspa. Repiten el nombre de
    # la variable --que el título deliberadamente omite-- porque aquí sí hace
    # falta: son controles, y hay que saber qué se está quitando.
    output$chips <- renderUI({
      f <- filtros()
      if (!length(f)) return(NULL)
      div(
        class = "res-chips",
        lapply(names(f), function(cv) lapply(f[[cv]], function(v)
          tags$button(
            class = "res-chip", type = "button",
            `data-quitar` = paste(cv, v, sep = RES_SEP_CHIP),
            `aria-label` = sprintf("Quitar el filtro %s: %s", RES_CRUCES[[cv]], v),
            tags$em(RES_CRUCES[[cv]]), v,
            tags$span(`aria-hidden` = "true", class = "res-aspa", "×")))),
        tags$button(class = "res-chip res-chip-limpiar", type = "button",
                    `data-quitar` = "", "Quitar todos")
      )
    })

    observeEvent(input$quitar, {
      # El reloj va DELANTE para que un valor que contenga "|" no rompa el
      # corte; solo sirve para que dos clics seguidos sean eventos distintos.
      pieza  <- sub("^[0-9]+\\|", "", input$quitar)
      partes <- strsplit(pieza, RES_SEP_CHIP, fixed = TRUE)[[1]]

      if (length(partes) < 2 || !nzchar(partes[1])) {
        for (cv in names(RES_CRUCES)) {
          updateSelectizeInput(session, paste0("f_", cv), selected = character(0))
        }
        return()
      }
      cv <- partes[1]; v <- partes[2]
      queda <- setdiff(input[[paste0("f_", cv)]] %||% character(0), v)
      updateSelectizeInput(session, paste0("f_", cv), selected = queda)
    })

    # --- estado derivado -----------------------------------------------------

    segmento <- reactive({
      d <- datos()
      if (is.null(d)) return(NULL)
      res_filtrar(d, filtros())
    })

    comparar   <- reactive(identical(input$comparar %||% "univ", "univ"))
    desagregar <- reactive(input$desagregar %||% "")
    medida     <- reactive(input$medida %||% "tot_estres")

    # Por debajo del mínimo no se calcula nada: es la puerta que impide que un
    # porcentaje delate una respuesta individual.
    hay_segmento <- reactive({
      s <- segmento()
      !is.null(s) && nrow(s) >= RES_MIN_N
    })

    # --- la forma de cada cuestionario ---------------------------------------
    # Una vista por cuestionario --A, B o el total--, y el estado vive en R, no
    # en el DOM: el renderUI del ranking rehace los desplegables con cada
    # cambio de filtro, y un radioButtons metido ahí se reconstruiría y
    # perdería lo elegido. Es la misma razón por la que los mandos de las
    # cabeceras de sección son estáticos.
    #
    # La vista NO es solo lo que se dibuja: cambia la población del
    # cuestionario y, con ella, su referencia. Elegir la forma B es analizar a
    # los auxiliares y operarios contra los auxiliares y operarios de la
    # universidad.
    ids_bloque <- vapply(RES_BLOQUES, function(b) b$id, "")

    vistas <- do.call(reactiveValues,
      stats::setNames(as.list(rep(RES_VISTA_DEF, length(ids_bloque))), ids_bloque))

    # Qué cuestionario está desplegado. También en R: al cambiar de vista el
    # bloque se vuelve a dibujar, y sin esto se cerraría justo el que se está
    # mirando. Nacen todos plegados (ver res_bloque_ranking()).
    abiertos <- do.call(reactiveValues,
      stats::setNames(as.list(rep(FALSE, length(ids_bloque))), ids_bloque))

    # El reloj va delante para que dos clics seguidos sean eventos distintos,
    # igual que en las fichas de filtro.
    partes_evento <- function(x) strsplit(sub("\\|[0-9]+$", "", x), "|", fixed = TRUE)[[1]]

    observeEvent(input$vista, {
      p <- partes_evento(input$vista)
      if (length(p) != 2 || !p[1] %in% ids_bloque || !p[2] %in% RES_VISTAS) return()
      vistas[[p[1]]]   <- p[2]
      # Quien acaba de elegir una forma se queda mirando ese cuestionario.
      abiertos[[p[1]]] <- TRUE
    })

    observeEvent(input$abrir, {
      p <- partes_evento(input$abrir)
      if (length(p) != 2 || !p[1] %in% ids_bloque) return()
      abiertos[[p[1]]] <- identical(p[2], "1")
    })

    # La referencia de cada medida es esa misma medida en toda la universidad,
    # restringida a la forma de la vista. Aquí va la del conjunto --la que usan
    # las tarjetas de cabecera, que no tienen vista--; la de cada cuestionario
    # se calcula en bloques(), sobre su propia población.
    referencia <- reactive({
      d <- datos()
      if (is.null(d) || nrow(d) == 0) return(NULL)
      res_referencia(d, RES_CLAVES)
    })

    # Sin filtros el segmento ES la universidad, y compararlo contra sí mismo da
    # cero en todas las medidas: dos puntos superpuestos y una columna de "±0,0
    # pp". Las tarjetas y los focos ya lo escondían; el ranking no, y por eso
    # esto es una sola condición que usan los tres.
    hay_comparacion <- reactive(comparar() && length(filtros()) > 0)

    # Las tarjetas de cabecera siguen partidas por forma --cada baremo con su
    # cifra-- así que su reparto se calcula sobre el segmento entero y no sobre
    # ninguna vista.
    repartos_cabeza <- reactive({
      if (!hay_segmento()) return(list())
      s <- segmento()
      stats::setNames(lapply(RES_CABEZA, function(k) res_reparto(s[[k]])), RES_CABEZA)
    })

    # --- un contexto por cuestionario ----------------------------------------
    # Todo lo que una sección necesita saber de un cuestionario, calculado UNA
    # vez: su vista, su población, su referencia, su ranking y el reparto de
    # cada medida. El ranking, los focos, la desagregación, el mapa, la tabla y
    # el Excel leen esta misma lista, así que no pueden discrepar entre sí ni
    # quedarse una sección con una forma y otra con otra.
    bloques <- reactive({
      d <- datos()
      if (is.null(d) || !hay_segmento()) return(NULL)
      s <- segmento()
      lapply(RES_BLOQUES, function(b) {
        v  <- vistas[[b$id]] %||% RES_VISTA_DEF
        ks <- res_claves_bloque(b, v)
        sg <- res_vista(s, v)
        un <- res_vista(d, v)
        rf <- res_referencia(un, ks)
        list(b = b, id = b$id, vista = v, claves = ks,
             n = nrow(sg), n_univ = nrow(un), seg = sg, ref = rf,
             rk  = res_ranking(sg, rf, ks),
             rep = stats::setNames(lapply(ks, function(k) res_reparto(sg[[k]])), ks))
      })
    })

    # El contexto de un cuestionario por su id, para las secciones que trabajan
    # sobre una sola medida.
    bloque_de <- function(clave) {
      bl <- bloques()
      if (is.null(bl)) return(NULL)
      id <- unname(RES_BLOQUE_DE[clave])
      if (is.na(id)) return(NULL)
      i <- which(vapply(bl, function(x) identical(x$id, id), logical(1)))
      if (!length(i)) NULL else bl[[i[1]]]
    }

    # Bandera para el conditionalPanel de la cabecera del ranking.
    output$hay_segmento <- reactive(hay_segmento())
    outputOptions(output, "hay_segmento", suspendWhenHidden = FALSE)

    # Sin comparación los dos órdenes por diferencia no significan nada, y
    # dejarlos en la lista para luego cambiarlos en silencio por "Mayores
    # riesgos" es mentirle a quien los eligió: se quitan y se vuelven a poner.
    observeEvent(hay_comparacion(), {
      op  <- if (hay_comparacion()) RES_ORDENES else RES_ORDENES[!grepl("^dif_", RES_ORDENES)]
      act <- input$orden %||% "estructura"
      updateSelectInput(session, "orden", choices = op,
                        selected = if (act %in% op) act else "estructura")
    })

    # --- cabecera ------------------------------------------------------------

    output$cabecera <- renderUI({
      d <- datos()
      if (is.null(d))   return(res_aviso_sin_clasificacion())
      if (nrow(d) == 0) return(res_aviso_sin_respuestas())

      s <- segmento()
      f <- filtros()

      # El tamaño del segmento se dice UNA vez y aquí. Antes salía tres veces
      # --el n, la "población analizada" y una tarjeta del resumen con las mismas
      # dos cifras--; la cabecera es la que se queda porque es la única que se
      # ve también cuando el segmento queda reservado.
      div(
        class = "res-cabecera",
        div(class = "res-eyebrow", "Resultados de la Batería"),
        h3(class = "res-seg-titulo", res_titulo_segmento(f)),
        div(
          class = "res-seg-sub",
          span(class = "res-seg-n", sprintf("%s encuestas efectivas", fmt_num(nrow(s)))),
          if (length(f)) tagList(
            span(class = "sep", "·"),
            span(class = "res-poblacion",
                 sprintf("%s de los %s de la universidad",
                         fmt_pct(100 * nrow(s) / nrow(d)), fmt_num(nrow(d))))),
          if (nrow(s) > 0) local({
            cf <- res_cuenta_formas(s)
            tagList(
              span(class = "sep", "·"),
              span(class = "res-formas",
                   sprintf("forma A: %s · forma B: %s",
                           fmt_num(cf[["A"]]), fmt_num(cf[["B"]]))))
          })
        ),
        if (length(f)) actionLink(ns("restablecer"), "Restablecer filtros",
                                  class = "res-restablecer")
      )
    })

    observeEvent(input$restablecer, {
      for (cv in names(RES_CRUCES)) {
        updateSelectizeInput(session, paste0("f_", cv), selected = character(0))
      }
    })

    # Vuelve a "No desagregar". Las secciones de grupos y el mapa se esconden
    # solas, porque cuelgan de desagregar().
    observeEvent(input$quitar_desag, {
      updateSelectInput(session, "desagregar", selected = "")
    })

    # El aviso de reserva va pegado a la cabecera: es lo primero que hay que
    # leer cuando el segmento se quedó corto, antes que cualquier mando.
    output$reserva <- renderUI({
      d <- datos()
      if (is.null(d) || nrow(d) == 0 || hay_segmento()) return(NULL)
      res_aviso_reserva(nrow(segmento()))
    })

    # --- resumen ejecutivo ---------------------------------------------------

    output$resumen <- renderUI({
      d <- datos()
      if (is.null(d) || nrow(d) == 0) return(NULL)
      s <- segmento()

      if (!hay_segmento()) return(NULL)

      ref <- referencia()
      cmp <- hay_comparacion()

      tagList(
        div(
          class = "res-tarjetas",
          # Solo cifras de decisión: cuántos cuestionarios hay ya lo dice la
          # cabecera, justo encima.
          #
          # Las cifras de decisión, por forma. El baremo lo está: un 40 % de
          # la A y un 40 % de la B no salen de la misma tabla de calificación,
          # y por eso cada una lleva la suya escrita en el rótulo.
          #
          # Una forma que el segmento no tiene ocupa UNA tarjeta, no una por
          # medida: repetir "sin forma B" dos veces no informa de nada más y
          # desplaza a las que sí traen cifra.
          lapply(res_claves_cabeza(s), function(k) {
            if (startsWith(k, "!")) return(res_tarjeta_sin_forma(substring(k, 2)))
            rp <- repartos_cabeza()[[k]]
            u  <- unname(ref[k])
            dl <- if (is.null(rp) || is.na(u)) NA_real_ else round(rp$alto - u, 1)
            sn <- res_senal(dl)
            div(
              class = "res-tarjeta",
              div(class = "res-t-rotulo", res_rotulo_forma(k)),
              div(class = "res-t-cifra", if (is.null(rp)) "—" else fmt_pct(rp$alto)),
              div(class = "res-t-pie",
                  if (is.null(rp))
                    sprintf("menos de %s encuestas efectivas en el segmento", RES_MIN_N)
                  else sprintf("en riesgo alto o muy alto · n = %s", fmt_num(rp$n))),
              if (cmp && !is.na(dl)) {
                div(class = paste("res-t-delta", sn$cls),
                    span(class = "res-senal", `aria-hidden` = "true", sn$sig),
                    sprintf("%s%s pp contra la misma medida en la universidad (%s)",
                            if (dl > 0) "+" else if (dl < 0) "−" else "±",
                            fmt_num(abs(dl), 1), fmt_pct(u)))
              })
          })
        ),
        res_micro(paste(
          "Riesgo alto o muy alto: proporción de encuestas efectivas clasificadas en",
          "los dos niveles superiores de la Batería. El total general no es el",
          "promedio del intralaboral y el extralaboral: tiene baremo propio.",
          if (cmp)
            paste("La diferencia en pp es descriptiva --la resta de dos porcentajes",
                  "observados--; no hay prueba estadística detrás.")))
      )
    })

    # --- ranking: ¿qué está pasando? -----------------------------------------
    # Una lista por bloque, nunca una sola lista de 56 filas. El orden elegido
    # se aplica DENTRO de cada bloque: ordenar entre bloques pondría un dominio
    # de la forma A al lado de una dimensión de la B, que es la lectura que
    # esta pantalla tiene que impedir.

    # --- resumen descriptivo -------------------------------------------------
    # Sale de segmento(), que es el mismo data.frame del ranking: se calcula en
    # R y no vuelve a la base.
    #
    # Por debajo del mínimo no se dibuja nada, igual que el resto de la pantalla:
    # una tabla de frecuencias sobre cuatro personas es tan identificable como un
    # reparto de riesgo sobre cuatro personas.
    output$desc_sub <- renderUI({
      if (!hay_segmento()) return(NULL)
      sprintf(paste("Quién contestó: perfil sociodemográfico y laboral de",
                    "%s encuestas efectivas."),
              fmt_num(nrow(segmento())))
    })

    output$descriptivo <- renderUI({
      if (!hay_segmento()) return(NULL)
      res_descriptivo_ui(res_descriptivo(segmento()))
    })

    # El cruce sale del mismo segmento, así que sigue a los filtros como el
    # resto del descriptivo.
    output$desc_cruce <- renderUI({
      if (!hay_segmento()) return(NULL)
      fila <- input$cruce_fila %||% ""
      col  <- input$cruce_col  %||% ""
      if (!nzchar(fila) || !nzchar(col)) return(NULL)
      if (identical(fila, col))
        return(div(class = "res-focos-vacio",
                   "Elija dos variables distintas para las filas y las columnas."))
      cr <- res_desc_cruce(segmento(), fila, col)
      if (is.null(cr)) return(NULL)
      res_desc_cruce_ui(cr, input$cruce_pct %||% "fila")
    })

    output$ranking_nota <- renderUI({
      cmp <- hay_comparacion()
      p(class = "text-muted small mb-0",
        sprintf(paste("Los tres cuestionarios de la Batería. Dentro de cada uno",
                      "se elige la forma: A, B o las dos juntas.")),
        if (cmp) {
          " Cada medida se compara contra esa misma medida en la universidad, dentro de la forma elegida."
        } else if (comparar()) {
          " Sin filtros el segmento es toda la universidad, así que no hay contra qué compararlo."
        } else {
          " La comparación con la universidad está desactivada."
        })
    })

    output$ranking <- renderUI({
      bl <- bloques()
      if (is.null(bl)) return(NULL)

      dist  <- identical(input$vista_perfil %||% "comp", "dist")
      cmp   <- hay_comparacion()
      orden <- input$orden %||% "estructura"

      # La sangria de los nombres solo se puede dibujar cuando las filas van en
      # orden de estructura; en cualquier otro orden el nivel se escribe (ver
      # res_nom_fila()).
      jerarquia <- identical(orden, "estructura")

      # Sin ningún filtro puesto el segmento ES toda la universidad. No es lo
      # mismo que tener la comparación apagada: allí el punto único sigue siendo
      # el segmento. La fila y la leyenda necesitan saberlo para nombrar bien la
      # única marca que queda en la pista.
      univ_sola <- length(filtros()) == 0

      tagList(
        if (dist) res_leyenda_niveles() else res_leyenda_comparacion(cmp, univ_sola),
        # `abiertos` se lee AISLADO: el navegador ya abre y cierra el <details>
        # por su cuenta, así que depender de él haría que cada clic en una
        # cabecera reconstruyera la sección entera para dejarla como ya estaba.
        # Lo que hace falta es recordarlo para la PRÓXIMA vez que se redibuje
        # --al cambiar de forma o de filtro-- y eso lo da el valor aislado.
        lapply(bl, function(ctx)
          res_bloque_ranking(ctx, res_ordenar_ranking(ctx$rk, orden, cmp),
                             dist, cmp, univ_sola, jerarquia,
                             abierto = isolate(isTRUE(abiertos[[ctx$id]])))),
        res_micro(
          paste("Los cuestionarios no se comparan entre sí, y dentro de uno las",
                "filas tampoco son independientes: un total agrega a sus",
                "dominios y un dominio a sus dimensiones, así que cada fila dice",
                "qué es y de qué dominio viene."),
          paste("La forma A y la B son instrumentos distintos, con ítems y",
                "baremos propios: la vista total suma sus NIVELES --que es para",
                "lo que existe cada baremo-- pero una diferencia entre las dos",
                "vistas no es una diferencia de la gente."),
          if (dist) "Cada barra suma 100 % del cuestionario."
          else if (cmp) paste("El punto hueco es la referencia del cuestionario y",
                              "el lleno el segmento; la distancia entre ambos es",
                              "la diferencia.")
          else NULL,
          "Pulse una medida para ver su detalle.")
      )
    })

    # --- detalle de una medida (modal) ---------------------------------------

    # El detalle se calcula sobre el contexto de SU cuestionario --su vista, su
    # población y su referencia-- así que la cifra del modal es por construcción
    # la misma que la de la fila que se acaba de pulsar.
    observeEvent(input$dim_click, {
      ctx <- bloque_de(input$dim_click)
      if (is.null(ctx)) return()
      det <- res_detalle_medida(ctx$seg, ctx$ref, input$dim_click, ctx$vista)
      if (is.null(det)) return()
      showModal(modalDialog(
        title = det$rotulo, easyClose = TRUE, size = "l",
        footer = modalButton("Cerrar"),
        res_detalle_ui(det, hay_comparacion())))
    })

    # --- focos de atención ---------------------------------------------------

    # Los focos compiten entre los TRES cuestionarios, cada dimensión contra la
    # referencia de la vista en que se está mirando su cuestionario. Por eso la
    # fila se lleva su vista pegada: el podio es una lista suelta y ahí el
    # nombre de la medida no basta para saber de qué población habla.
    output$focos <- renderUI({
      bl <- bloques()
      if (is.null(bl) || !hay_comparacion()) return(NULL)
      rk <- do.call(rbind, lapply(bl, function(ctx) {
        if (is.null(ctx$rk) || !nrow(ctx$rk)) return(NULL)
        ctx$rk$vista <- ctx$vista
        ctx$rk
      }))
      if (is.null(rk) || !nrow(rk)) return(NULL)
      fc <- res_focos(rk)

      div(
        class = "res-focos",
        div(class = "res-focos-cab",
            h5("Focos de atención"),
            span(class = "res-regla",
                 sprintf(paste("Regla: dimensiones con la mayor diferencia",
                               "descriptiva por encima de su propia referencia, a",
                               "partir de %s pp. Cada una compite contra la",
                               "referencia de su cuestionario en la forma que se",
                               "está mirando. Los totales y los dominios",
                               "quedan fuera, porque agregan a las dimensiones que",
                               "ya compiten."),
                         RES_UMBRAL_SIMILAR))),
        if (!nrow(fc)) {
          div(class = "res-focos-vacio",
              sprintf(paste("Ninguna dimensión se separa más de %s pp por encima",
                            "de su referencia en este segmento."), RES_UMBRAL_SIMILAR))
        } else {
          div(class = "res-focos-lista",
              lapply(seq_len(nrow(fc)), function(i) {
                f <- fc[i, ]
                div(class = "res-foco",
                    div(class = "res-foco-num", i),
                    div(class = "res-foco-cuerpo",
                        div(class = "res-foco-nom",
                            res_rotulo_vista(f$clave, f$vista)),
                        div(class = "res-foco-det",
                            sprintf(paste("%s del segmento en riesgo alto o muy alto,",
                                          "contra %s de la universidad."),
                                    fmt_pct(f$pct), fmt_pct(f$univ)))),
                    div(class = "res-foco-delta",
                        sprintf("+%s pp", fmt_num(f$delta, 1))))
              }))
        }
      )
    })

    # --- desagregación -------------------------------------------------------
    # La medida elegida pertenece a un cuestionario, y ese cuestionario tiene
    # una vista: los grupos se calculan sobre ESA población y contra ESA
    # referencia. Si no, la misma medida daría dos cifras distintas según la
    # sección en que se mire, que es justo lo que este módulo evita.
    ctx_medida <- reactive(bloque_de(medida()))

    grupos <- reactive({
      ctx <- ctx_medida()
      if (is.null(ctx) || !nzchar(desagregar())) return(list())
      res_por_grupo(ctx$seg, desagregar(), medida(),
                    cats = res_categorias(segmento(), desagregar()))
    })

    # Cuántos grupos salen del cruce. Se cuenta sobre el SEGMENTO y no sobre la
    # vista, para que las banderas de las cabeceras estáticas no se muevan al
    # cambiar de medida --una medida de otro cuestionario puede traer otra
    # forma-- y para que las columnas del mapa sean las mismas en los tres.
    n_grupos <- reactive({
      if (!hay_segmento() || !nzchar(desagregar())) return(0L)
      length(res_categorias(segmento(), desagregar()))
    })

    output$hay_grupos    <- reactive(n_grupos() > 0)
    output$hay_mapa      <- reactive(n_grupos() >= 2)
    output$muchos_grupos <- reactive(n_grupos() > 20)
    for (bandera in c("hay_grupos", "hay_mapa", "muchos_grupos")) {
      outputOptions(output, bandera, suspendWhenHidden = FALSE)
    }

    # Qué cuestionarios del mapa están desplegados. Nacen todos plegados y se
    # vuelven a plegar con cada cruce nuevo, que trae otra tabla; los demás
    # cambios --métrica, tope, filtros, forma-- los respetan.
    mapa_abiertos <- do.call(reactiveValues,
      stats::setNames(as.list(rep(FALSE, length(ids_bloque))), ids_bloque))

    observeEvent(input$mapa_abrir, {
      p <- partes_evento(input$mapa_abrir)
      if (length(p) != 2 || !p[1] %in% ids_bloque) return()
      mapa_abiertos[[p[1]]] <- identical(p[2], "true")
    })

    # Cada desagregación que se AÑADE llega con la sección plegada. Cambiar de
    # un cruce a otro con la sección abierta no la cierra: quien está mirando
    # los grupos quiere ver los del cruce nuevo, no volver a desplegar.
    # Prioridad alta para que corra ANTES de que el mapa se redibuje con el
    # cruce nuevo y lea `mapa_abiertos`.
    desag_previa <- ""
    observeEvent(desagregar(), priority = 10, {
      for (id in ids_bloque) mapa_abiertos[[id]] <- FALSE
      if (!nzchar(desag_previa) && nzchar(desagregar()))
        session$sendCustomMessage("res-plegar", ns("desag_det"))
      desag_previa <<- desagregar()
    })

    output$desag_sub <- renderUI({
      n <- n_grupos()
      if (!n) return(NULL)
      sprintf("Por %s · %s %s en este segmento. Despliegue para ver la distribución y el mapa.",
              tolower(RES_CRUCES[[desagregar()]]), fmt_num(n),
              if (n == 1) "grupo" else "grupos")
    })

    output$desag_titulo <- renderUI({
      n <- n_grupos()
      if (!n) return(NULL)
      ctx <- ctx_medida()
      tagList(
        h5(sprintf("Comparar por %s", tolower(RES_CRUCES[[desagregar()]]))),
        p(class = "text-muted small mb-0",
          sprintf("%s %s en este segmento.", fmt_num(n),
                  if (n == 1) "grupo disponible" else "grupos disponibles"),
          # De qué población habla esta sección. Va aquí y no en una nota al
          # pie porque cambia el denominador de todas las filas de abajo.
          if (!is.null(ctx) && !identical(ctx$vista, "T"))
            sprintf(" Sobre la forma %s de %s, que es la vista elegida en ese cuestionario.",
                    ctx$vista, tolower(ctx$b$titulo))))
    })

    output$desagregacion <- renderUI({
      g   <- grupos()
      ctx <- ctx_medida()
      if (!length(g) || is.null(ctx)) return(NULL)

      k   <- medida()
      cv  <- desagregar()
      cmp <- comparar()

      # La referencia es la misma de todo el cuestionario: esa medida en la
      # universidad, dentro de la vista. Un grupo sí se compara aunque no haya
      # filtros --un grupo no es la universidad--; la fila del cuestionario
      # entero, en cambio, sin filtros ES la universidad y queda de referencia.
      u <- if (cmp) unname(ctx$ref[k]) else NA_real_

      # Una medida que la vista no tiene: las tres dimensiones exclusivas de la
      # forma A cuando se está mirando la B. Se dice y no se dibuja una tabla
      # entera de "reservado", que no informaría de nada.
      if (!k %in% ctx$claves) {
        return(div(class = "res-focos-vacio",
          sprintf(paste("«%s» solo existe en la forma A, y en %s se está mirando",
                        "la forma B. Cambie la vista de ese cuestionario o elija",
                        "otra medida."),
                  RES_ROTULOS[[k]], tolower(ctx$b$titulo))))
      }

      tagList(
        h6(class = "res-sub", "Distribución en los cinco niveles"),
        res_leyenda_niveles(),
        div(class = "res-filas",
            res_encabezado_filas(RES_CRUCES[[cv]], "la universidad",
                                 dist = TRUE, comparar = cmp),
            res_fila_grupo(
              if (identical(ctx$vista, "T")) "Todo el segmento"
              else sprintf("Todo el segmento · forma %s", ctx$vista),
              ctx$n, res_reparto(ctx$seg[[k]]),
              if (hay_comparacion()) u else NA_real_, total = TRUE,
              vacio = if (cmp) "referencia" else "—"),
            lapply(g, function(x)
              res_fila_grupo(x$categoria, x$n_grupo, x$rep, u))),
        res_micro(
          "Los grupos van ordenados por su porcentaje en riesgo alto o muy alto.",
          if (!identical(ctx$vista, "T"))
            sprintf(paste("Solo cuenta quien contestó la forma %s: un grupo sin",
                          "nadie de esa forma sale reservado, no desaparece."),
                    ctx$vista),
          if (cmp) paste("El pp de la derecha compara cada grupo con esa misma",
                         "medida en la universidad, igual que el ranking y el",
                         "mapa, y es una diferencia descriptiva: no se ha",
                         "aplicado ninguna prueba."))
      )
    })

    # --- mapa de calor -------------------------------------------------------
    # Las columnas son las mismas en los tres cuestionarios --por eso salen del
    # segmento y no de ninguna vista-- y cada cuestionario dice, en su propia
    # cabecera, sobre qué forma está hablando.

    output$mapa <- renderUI({
      bl <- bloques()
      if (is.null(bl) || n_grupos() < 2) return(NULL)
      g <- grupos()
      if (!length(g)) return(NULL)

      tope <- if (length(g) > 20) (input$tope %||% "20") else "0"
      gg   <- res_top_grupos(g, tope)
      cats <- vapply(Filter(function(x) !is.null(x$rep), gg), function(x) x$categoria, "")
      if (!length(cats)) return(NULL)

      cv <- desagregar()
      s  <- segmento()
      n_de <- stats::setNames(
        vapply(cats, function(ct) sum(!is.na(s[[cv]]) & s[[cv]] == ct), 0L), cats)

      met <- if (comparar()) input$metrica %||% "pct" else "pct"
      ms  <- lapply(bl, function(ctx)
        c(ctx, list(m = res_matriz(ctx$seg, cv, cats, ctx$claves))))

      tagList(
        if (length(gg) < length(g))
          res_micro(sprintf(paste("Mostrando los %s grupos con mayor porcentaje en",
                                  "riesgo alto, de %s. La tabla de abajo no recorta."),
                            fmt_num(length(gg)), fmt_num(length(g)))),
        res_leyenda_mapa(met),
        # Aislado, igual que `abiertos` en el ranking: el navegador ya pliega y
        # despliega solo, y depender de esto redibujaría el mapa en cada clic.
        res_mapa_calor(ms, cats, n_de, met, RES_CRUCES[[cv]],
                       abiertos = isolate(reactiveValuesToList(mapa_abiertos))),
        res_micro(
          if (identical(met, "delta"))
            paste("Escala centrada en cero: por debajo de cero el grupo está mejor",
                  "que la universidad en esa medida; por encima, peor.")
          else "Porcentaje del grupo en los dos niveles superiores de riesgo.",
          "La n de cada columna es la del segmento entero; cada cuestionario dice aparte sobre qué forma habla.")
      )
    })

    # --- tabla analítica -----------------------------------------------------

    # El orden de la tabla es SUYO y no el del ranking: son dos preguntas
    # distintas --dónde está una medida en el instrumento, o cuál aprieta más--
    # y el rótulo del interruptor dice cuál se está pidiendo.
    orden_tabla <- reactive({
      if (identical(input$orden_tabla %||% "jer", "jer")) "estructura" else "riesgo_alto"
    })

    # Las filas de cada cuestionario, ya ordenadas y recortadas por la búsqueda.
    # El recorte es solo de PANTALLA: el Excel se arma aparte y lleva todo.
    tabla_bloques <- reactive({
      bl <- bloques()
      if (is.null(bl)) return(NULL)
      q   <- input$buscar %||% ""
      ord <- orden_tabla()
      cmp <- hay_comparacion()
      lapply(bl, function(ctx) {
        rk <- res_ordenar_ranking(ctx$rk, ord, cmp)
        if (nzchar(q) && !is.null(rk) && nrow(rk))
          rk <- rk[grepl(to_key(q), to_key(rk$rotulo), fixed = TRUE), , drop = FALSE]
        c(ctx, list(filas = rk))
      })
    })

    output$tabla <- renderUI({
      bt <- tabla_bloques()
      if (is.null(bt)) return(NULL)
      if (!sum(vapply(bt, function(x) nrow(x$filas), 0L)))
        return(div(class = "alert alert-secondary",
                   "Ninguna medida coincide con la búsqueda."))
      res_tabla_analitica(bt, hay_comparacion(),
                          jerarquia = identical(orden_tabla(), "estructura"))
    })

    output$bajar <- downloadHandler(
      filename = function() {
        sprintf("resultados_%s_%s.xlsx",
                gsub("[^a-z0-9]+", "_", to_key(res_titulo_segmento(filtros()))),
                format(Sys.Date(), "%Y%m%d"))
      },
      content = function(archivo) {
        # El archivo lleva SIEMPRE todas las medidas, aunque haya una búsqueda
        # puesta: la búsqueda sirve para encontrar una fila en pantalla, y un
        # archivo al que le faltan medidas sin decirlo pasa por completo. Van en
        # el orden que muestra la tabla: por cuestionario y, dentro, por
        # estructura o por riesgo según el interruptor.
        bl  <- bloques()
        ord <- orden_tabla()
        cmp <- hay_comparacion()
        est <- res_estructura()

        # La VISTA va en su propia columna. Fuera de la app nadie recuerda que
        # el intralaboral se estaba mirando en forma B, y sin esa columna dos
        # descargas del mismo segmento con vistas distintas serían dos archivos
        # iguales por fuera y distintos por dentro.
        salida <- do.call(rbind, lapply(bl, function(ctx) {
          rk <- res_ordenar_ranking(ctx$rk, ord, cmp)
          if (is.null(rk) || !nrow(rk)) return(NULL)
          niv <- do.call(rbind, lapply(rk$clave, function(k) {
            x <- ctx$rep[[k]]
            if (is.null(x)) rep(NA_real_, 5) else round(x$pct, 1)
          }))
          colnames(niv) <- c("sin_riesgo", "bajo", "medio", "alto", "muy_alto")
          x <- cbind(
            data.frame(segmento     = res_titulo_segmento(filtros()),
                       cuestionario = ctx$b$titulo,
                       vista        = res_vista_txt(ctx$vista),
                       n_vista      = ctx$n,
                       nivel        = c(total = "Total", dominio = "Dominio",
                                        dimension = "Dimensión")[
                                          est$nivel[match(rk$clave, est$clave)]],
                       medida       = rk$rotulo,
                       solo_forma_a = rk$solo_a,
                       n            = rk$n,
                       stringsAsFactors = FALSE),
            as.data.frame(niv),
            data.frame(alto_o_muy_alto = rk$pct,
                       universidad     = rk$univ,
                       diferencia_pp   = rk$delta,
                       stringsAsFactors = FALSE))
          x[rk$reservado,
            setdiff(names(x), c("segmento", "cuestionario", "vista", "n_vista",
                                "nivel", "medida", "solo_forma_a", "n"))] <- NA
          x
        }))

        escribir_excel(salida, archivo)
      }
    )

    # Las salidas que viven dentro de un <details> plegado. Shiny no dibuja una
    # salida oculta, y abrir un <details> no le avisa de que ya se ve: sin esto
    # la sección se desplegaba en blanco. Son datos en memoria, así que
    # calcularlas aunque estén plegadas no cuesta nada que se note.
    for (sal in c("descriptivo", "desc_cruce", "desag_titulo", "desagregacion",
                  "mapa", "tabla", "bajar")) {
      outputOptions(output, sal, suspendWhenHidden = FALSE)
    }
  })
}


# =============================================================================
# PIEZAS SIN REACTIVOS
# =============================================================================
# Reciben datos y devuelven etiquetas, así que se pueden probar sueltas, igual
# que tabla_dependencias() en el módulo de seguimiento.

# Separador interno de las fichas de filtro. Es un carácter de control porque
# los valores llevan espacios, tildes y paréntesis, y cualquier separador
# imprimible podría aparecer dentro de uno de ellos.
RES_SEP_CHIP <- "\u001f"

# Las claves de las tarjetas de cabecera para un segmento concreto. Devuelve
# RES_CABEZA tal cual, salvo que una forma no esté presente: entonces sus dos
# medidas se colapsan en una sola entrada marcada con "!" --"!B"--, que
# res_tarjeta_sin_forma() pinta como una única tarjeta.
res_claves_cabeza <- function(seg) {
  cf <- res_cuenta_formas(seg)
  Reduce(function(acc, k) {
    f <- unname(RES_FORMA_DE[[k]])
    if (is.na(f) || cf[[f]] > 0) return(c(acc, k))
    marca <- paste0("!", f)
    if (marca %in% acc) acc else c(acc, marca)
  }, RES_CABEZA, character(0))
}

# La forma que el segmento no tiene. No se esconde --que falte es un dato sobre
# el segmento, no una casilla vacía-- pero ocupa una tarjeta apagada y no dos.
res_tarjeta_sin_forma <- function(f) {
  div(
    class = "res-tarjeta res-tarjeta-vacia",
    div(class = "res-t-rotulo", sprintf("Forma %s", f)),
    div(class = "res-t-cifra", "—"),
    div(class = "res-t-pie",
        sprintf("ningún cuestionario de %s en el segmento", RES_FORMA_TXT[[f]])))
}

res_opciones_medida <- function() {
  op <- lapply(RES_BLOQUES, function(b)
    stats::setNames(b$claves, unname(RES_ROTULOS[b$claves])))
  stats::setNames(op, vapply(RES_BLOQUES, function(b) b$titulo, ""))
}

# Explicación de una línea, pegada a lo que explica. El tablero tiene que
# entenderse sin manual, y un párrafo largo no lo lee nadie.
res_micro <- function(...) {
  txt <- paste(Filter(nzchar, c(...)), collapse = " ")
  if (!nzchar(txt)) return(NULL)
  p(class = "res-micro", txt)
}

res_leyenda_niveles <- function() {
  div(class = "res-leyenda",
      lapply(seq_along(RES_NIVELES), function(i)
        span(class = "res-leyenda-it",
             span(class = paste0("res-muestra niv", i)),
             RES_NIVELES[i])))
}

# La referencia NO se llama "Universidad" a secas: en un bloque de forma es la
# universidad restringida a esa forma, y cada cabecera de bloque dice cuál y
# sobre cuántos cuestionarios.
#
# El punto lleno tiene DOS colores: lo pinta res_senal() según de qué lado de la
# referencia cae --carmín por encima, verde por debajo--, y la leyenda enseñaba
# solo el carmín. Los dos estados se sacan de la propia res_senal(), llamándola
# con un delta representativo de cada uno, así que si cambia un color la leyenda
# cambia con él y no hay forma de que se desincronicen.
res_leyenda_comparacion <- function(comparar = TRUE, es_universidad = FALSE) {
  nota <- span(class = "res-leyenda-it res-leyenda-nota",
               "El eje va de 0 a 100 % en todas las filas.")

  # Sin comparación hay un solo punto y no hay tres estados que explicar, pero
  # la leyenda sí tiene que decir DE QUIÉN es ese punto: de toda la universidad
  # cuando no hay filtros, o del segmento cuando la comparación se apagó a mano.
  # La muestra es en cada caso la misma marca que dibuja la fila; si no, la
  # leyenda explicaría algo que no está en pantalla.
  if (!comparar) {
    marca <- if (isTRUE(es_universidad)) "res-muestra res-m-univ"
             else "res-muestra res-m-pt nula"
    return(div(
      class = "res-leyenda",
      span(class = "res-leyenda-it",
           span(class = marca),
           if (isTRUE(es_universidad)) "Universidad" else "Segmento"),
      nota))
  }

  estados <- lapply(c(1, -1), res_senal)

  div(
    class = "res-leyenda",
    span(class = "res-leyenda-it",
         span(class = "res-muestra res-m-univ"), "Referencia del bloque"),
    span(class = "res-leyenda-it res-leyenda-rot", "Segmento:"),
    lapply(estados, function(e)
      span(class = "res-leyenda-it",
           span(class = paste("res-muestra res-m-pt", e$cls)),
           # El símbolo va también aquí, y no solo el color: es el mismo ▲ ▼ que
           # lleva la columna de pp, así que la leyenda sirve igual en gris o
           # impresa.
           span(class = paste("res-senal", e$cls), `aria-hidden` = "true", e$sig),
           tolower(e$txt))),
    nota)
}


# --- el selector de forma -----------------------------------------------------
# Tres botones de HTML puro, no un radioButtons: el bloque entero se redibuja
# con cada cambio de filtro, y un input de Shiny metido aquí se reconstruiría y
# perdería lo elegido. El estado vive en el server y aquí solo se pinta cuál
# está activo; el clic lo recoge un manejador delegado (ver mod_resultados_ui).
#
# `aria-pressed` y no `aria-checked` porque son botones, no un grupo de radio:
# la diferencia importa para quien navega con lector de pantalla.
res_selector_vista <- function(bloque, actual) {
  div(
    class = "res-vista", role = "group",
    `aria-label` = "Forma del cuestionario",
    span(class = "res-vista-rot", "Ver"),
    lapply(seq_along(RES_VISTAS), function(i) {
      v <- unname(RES_VISTAS[i])
      tags$button(
        type = "button",
        class = paste("res-vista-op", if (identical(v, actual)) "activa"),
        `data-vista` = paste(bloque, v, sep = "|"),
        `aria-pressed` = tolower(identical(v, actual)),
        names(RES_VISTAS)[i])
    }))
}


# --- un cuestionario del ranking ----------------------------------------------
# Un bloque es un CUESTIONARIO --intralaboral, extralaboral o estrés-- y dentro
# se elige la forma. Antes eran cuatro bloques (A, B, extralaboral, estrés) y la
# forma era una propiedad del bloque; ahora es una vista del mismo, porque la
# pregunta de quien mira es "cómo va el intralaboral", no "cómo va la forma A".
#
# La vista NO es un filtro de presentación: cambia la población del cuestionario
# y con ella su referencia. Elegir la forma B es analizar a los auxiliares y
# operarios contra los auxiliares y operarios de la universidad. Por eso la
# cabecera dice siempre las dos cosas: la vista y contra qué se compara.
#
# Nacen todos PLEGADOS. Abiertos, la sección arrancaba con decenas de filas y la
# cabecera --la advertencia de que a mayor porcentaje peor-- quedaba encima de
# un muro. Cerrados, lo primero que se ve son los tres títulos con su n, que es
# la pregunta de antes: de cuál de los tres hablamos.
#
# Pero el selector va DENTRO, así que un cuestionario cuya vista se acaba de
# cambiar tiene que quedarse abierto: `abierto` viene del server, que recuerda
# cuál está desplegado. Sin eso, elegir "Forma B" cerraría justo el bloque que
# se está mirando.
#
# El cuestionario sin cuestionarios en esa vista NO se esconde: se muestra con
# su selector y diciendo que está vacío, que es la única forma de poder volver a
# otra vista. Esconderlo dejaría a quien eligió la forma B sin manera de salir.
res_bloque_ranking <- function(ctx, rk, dist = FALSE, comparar = TRUE,
                               es_universidad = FALSE, jerarquia = TRUE,
                               abierto = FALSE) {
  b <- ctx$b
  v <- ctx$vista

  contra <- if (identical(v, "T")) "la universidad"
            else sprintf("la forma %s de la universidad", v)

  cabecera <- tags$summary(
    class = "res-bl-sum",
    div(class = "res-bl-tit", b$titulo,
        tags$span(class = paste("res-bl-vista", if (!identical(v, "T")) "forma"),
                  res_vista_txt(v)),
        tags$span(class = "res-bl-n", sprintf("n = %s", fmt_num(ctx$n)))),
    div(class = "res-bl-sub",
        sprintf("%s · %s", b$sub, res_composicion(ctx$claves)),
        if (comparar && ctx$n > 0)
          sprintf(" · se compara contra %s (%s encuestas efectivas)",
                  contra, fmt_num(ctx$n_univ))))

  selector <- res_selector_vista(b$id, v)

  # Una vista bajo el mínimo se resuelve de una vez: enseñar filas que dicen
  # "reservado" no informa de nada y entierra lo que sí tiene datos.
  # En la vista total esto solo pasa si el segmento entero se quedó corto, y
  # entonces la pantalla ni llega aquí; el caso real es una forma que este
  # segmento no tiene.
  en_forma <- if (identical(v, "T")) "" else sprintf(" en la forma %s", v)

  cuerpo <- if (ctx$n < RES_MIN_N) {
    div(class = "res-bl-nota",
        if (ctx$n == 0)
          sprintf(paste("Este cuestionario no tiene ningún dato%s dentro del",
                        "segmento, así que no hay nada que calcular. Elija otra",
                        "forma aquí arriba, o quite algún filtro."), en_forma)
        else
          sprintf(paste("Resultado reservado: %s %s%s en este segmento, por debajo",
                        "del mínimo de %s. El reparto en los niveles permitiría",
                        "inferir respuestas individuales."),
                  fmt_num(ctx$n),
                  if (ctx$n == 1) "encuesta efectiva" else "encuestas efectivas",
                  en_forma, RES_MIN_N))
  } else {
    div(class = "res-filas",
        # La columna dice "la referencia" y no la frase entera: no cabe en 5,6
        # rem, y la cabecera del bloque --que está justo encima-- ya deletrea
        # cuál es y sobre cuántos cuestionarios. Es además el mismo término que
        # usa la leyenda, así que el vocabulario de la sección es uno solo.
        res_encabezado_filas("Medida", "la referencia", dist, comparar),
        lapply(seq_len(nrow(rk)), function(i) {
          f <- rk[i, ]
          if (dist) res_fila_dist(f, ctx$rep[[f$clave]], comparar, jerarquia, v)
          else      res_fila_comp(f, comparar, es_universidad, jerarquia, v)
        }))
  }

  tags$details(
    class = paste("res-bl", if (ctx$n < RES_MIN_N) "res-bl-vacio"),
    `data-bloque` = b$id,
    open = if (isTRUE(abierto)) NA else NULL,
    cabecera,
    div(class = "res-bl-cuerpo", selector, cuerpo))
}


# --- encabezado de la lista de filas ------------------------------------------
# Las dos columnas de la derecha son números sin unidad evidente: una es el
# porcentaje en los dos niveles superiores y la otra una distancia en puntos
# porcentuales CONTRA ALGO. Ese "algo" cambia de sección: la referencia del
# bloque en el ranking --que la cabecera de cada bloque deletrea-- y el segmento
# entero al desagregar. El rótulo lo nombra en vez de dejarlo a la memoria de
# quien mira, pero corto: la columna mide 5,6 rem.
res_encabezado_filas <- function(primera = "Medida", contra = "la universidad",
                                 dist = TRUE, comparar = TRUE) {
  eje <- if (dist) {
    div(class = "res-eje-rot", "Reparto en los cinco niveles (suma 100 %)")
  } else {
    # En la vista de comparación la pista es una escala de verdad, así que
    # lleva sus marcas: sin ellas no se sabe dónde cae un punto.
    div(class = "res-eje",
        lapply(c(0, 25, 50, 75, 100), function(v)
          span(style = sprintf("left:%s%%;", v),
               if (v == 100) "100 %" else as.character(v))))
  }

  div(
    class = "res-fila res-encabezado",
    div(class = "res-nom", primera),
    eje,
    div(class = "res-val", "Alto o", tags$br(), "muy alto"),
    div(class = "res-delta",
        if (comparar) tagList("pp contra", tags$br(), contra) else NULL)
  )
}

# --- nombre de una fila del ranking -------------------------------------------
# Mismo diseño que los rótulos de fila del mapa de medidas por grupo (ver
# res_mapa_calor()): el nombre solo, con la jerarquía dibujada en la SANGRÍA y
# el peso --total → dominio → dimensión-- en vez de en una segunda línea con el
# nivel escrito. Son la misma lista de medidas vista de dos maneras, y tenían
# dos tipografías distintas.
#
# Pero la sangría solo dice la verdad si las filas van en orden de estructura.
# Ordenado por riesgo, "Demandas del trabajo" (dominio) puede quedar pegada a
# "Demandas emocionales" (una de las dimensiones que ese dominio agrega), y una
# sangría ahí afirmaría un parentesco entre vecinas que no existe: son dos filas
# de las que una está contada dentro de la otra. Por eso `jerarquia` decide cuál
# de los dos recursos se usa --sangría, o etiqueta de nivel escrita--, que es la
# misma solución que ya tomaba res_tabla_analitica().
#
# El nivel viaja SIEMPRE en texto oculto, porque un lector de pantalla no oye un
# margen izquierdo. Y `n` y el sitio dentro del cuestionario se mudan al `title`:
# el mapa tampoco los pone en la fila, y seguían estando en la tabla de datos
# detallados y en el detalle de la medida.
# Las tres dimensiones que solo existen en la forma A llevan marca en la vista
# total: su n es el de los A --1.215 de 1.499-- y sin decirlo, una fila con
# menos gente que sus vecinas se lee como un error de calculo. En la vista A no
# hace falta, porque alli todas las filas son de la A.
res_nom_fila <- function(f, jerarquia = TRUE, vista = RES_VISTA_DEF) {
  st  <- res_sitio_de(f$clave, vista)
  niv <- res_nivel_de(f$clave)
  solo_a <- isTRUE(f$solo_a) && !identical(vista, "A")

  div(
    class = paste0("res-nom", if (jerarquia) paste0(" res-rf-", niv)),
    title = sprintf("%s%s · n = %s%s", st$nivel,
                    if (!is.null(st$detalle))
                      paste0(if (startsWith(st$detalle, "de ")) " " else " · ",
                             st$detalle)
                    else "",
                    fmt_num(f$n),
                    if (solo_a) " · solo la contesta la forma A" else ""),
    tags$span(class = "visually-hidden", sprintf("%s. ", st$nivel)),
    f$rotulo,
    if (solo_a)
      tags$span(class = "res-nivel-tag res-nv-solo-a", "solo forma A"),
    if (!jerarquia)
      tags$span(class = paste0("res-nivel-tag res-nv-", niv), st$nivel))
}

# --- fila del ranking, vista de comparación -----------------------------------
# Un punto hueco (universidad) y uno lleno (segmento) sobre una pista de 0 a
# 100 %, unidos por el tramo que los separa: la distancia ES la diferencia, y se
# ve sin leer ningún número. La escala es fija y no se ajusta al rango de los
# datos, para que dos segmentos distintos se puedan comparar mirando.
#
# Los dos papeles no se intercambian NUNCA: la universidad es siempre el aro sin
# relleno y el segmento siempre el punto macizo que se tiñe de rojo o verde. Por
# eso la referencia se dibuja la última --y con z-index propio en el CSS--: es la
# marca que tiene que verse igual en las 56 filas, incluso cuando el segmento
# cae justo encima de ella.
#
# El color nunca va solo: la fila lleva además el signo en texto (+9,9 pp) y un
# símbolo (▲ ▬ ▼), así que sobrevive al daltonismo y a una impresión en gris.
res_fila_comp <- function(f, comparar = TRUE, es_universidad = FALSE,
                          jerarquia = TRUE, vista = RES_VISTA_DEF) {
  if (isTRUE(f$reservado)) return(res_fila_reservada(f, jerarquia, vista))

  sn <- res_senal(if (comparar) f$delta else NA_real_)
  x  <- max(0, min(100, f$pct))
  u  <- if (comparar && !is.na(f$univ)) max(0, min(100, f$univ)) else NA_real_

  # Cuando no hay comparación queda UN punto, y hay que decir de quién es. Son
  # dos situaciones distintas que no se pueden pintar igual:
  #   - sin filtros, el segmento ES la universidad --por eso se apaga la
  #     comparación: restarla de sí misma daría cero en las 56 medidas--, así
  #     que ese punto es el puntaje de la universidad y lleva su aro, el mismo
  #     de las filas comparadas;
  #   - con filtros y la comparación apagada a mano, el punto es el segmento y
  #     sigue siendo macizo: ponerle el aro diría que es la universidad.
  solo_univ <- !comparar && isTRUE(es_universidad)

  # Dónde va el aro: en el valor de la universidad cuando se compara, y en el
  # punto único cuando el segmento es la universidad entera.
  aro <- if (!is.na(u)) u else if (solo_univ) x else NA_real_

  pista <- div(
    class = "res-pista", role = "img",
    `aria-label` = if (comparar && !is.na(f$delta)) {
      sprintf("%s: %s del segmento, %s de la universidad.",
              f$rotulo, fmt_pct(f$pct), fmt_pct(f$univ))
    } else if (solo_univ) {
      sprintf("%s: %s de la universidad.", f$rotulo, fmt_pct(f$pct))
    } else sprintf("%s: %s del segmento.", f$rotulo, fmt_pct(f$pct)),
    lapply(c(25, 50, 75), function(g)
      span(class = "res-guia", style = sprintf("left:%s%%;", g))),
    if (!is.na(u)) span(class = paste("res-tramo", sn$cls),
                        style = sprintf("left:%s%%; width:%s%%;",
                                        min(x, u), abs(x - u))),
    if (!solo_univ) span(class = paste("res-punto res-p-seg", sn$cls),
                         style = sprintf("left:%s%%;", x)),
    if (!is.na(aro)) span(class = "res-punto res-p-univ",
                          style = sprintf("left:%s%%;", aro))
  )

  div(
    class = "res-fila res-fila-comp", `data-dim` = f$clave,
    tabindex = "0", role = "button",
    res_nom_fila(f, jerarquia, vista),
    pista,
    div(class = "res-val", fmt_pct(f$pct)),
    div(class = paste("res-delta", sn$cls),
        if (comparar && !is.na(f$delta)) tagList(
          span(class = "res-senal", `aria-hidden` = "true", sn$sig),
          sprintf("%s%s pp",
                  if (f$delta > 0) "+" else if (f$delta < 0) "−" else "±",
                  fmt_num(abs(f$delta), 1)))
        else tags$span(class = "res-sin-comp", "—"))
  )
}

# --- fila del ranking, vista de distribución ----------------------------------
res_fila_dist <- function(f, rep, comparar = TRUE, jerarquia = TRUE,
                          vista = RES_VISTA_DEF) {
  if (isTRUE(f$reservado) || is.null(rep))
    return(res_fila_reservada(f, jerarquia, vista))

  div(
    class = "res-fila res-fila-dist", `data-dim` = f$clave,
    tabindex = "0", role = "button",
    res_nom_fila(f, jerarquia, vista),
    res_barra_apilada(rep, f$rotulo),
    div(class = "res-val", fmt_pct(f$pct)),
    div(class = paste("res-delta", res_senal(if (comparar) f$delta else NA_real_)$cls),
        if (comparar && !is.na(f$delta))
          sprintf("%s%s pp",
                  if (f$delta > 0) "+" else if (f$delta < 0) "−" else "±",
                  fmt_num(abs(f$delta), 1))
        else tags$span(class = "res-sin-comp", "—"))
  )
}

# La fila reservada se conserva: esconderla haría creer que la medida no existe.
res_fila_reservada <- function(f, jerarquia = TRUE, vista = RES_VISTA_DEF) {
  div(
    class = "res-fila res-fila-reservada",
    res_nom_fila(f, jerarquia, vista),
    div(class = "res-reservado",
        sprintf("Resultado reservado: menos de %s encuestas efectivas", RES_MIN_N)),
    div(class = "res-val", "—"),
    div(class = "res-delta", "—"))
}

# Barra de cinco tramos. El porcentaje se escribe dentro solo si el tramo pasa
# RES_MIN_ROTULO: por debajo quedaría cortado o invadiría el vecino, y ese valor
# sigue en el globo del tramo, en el detalle y en la tabla.
RES_MIN_ROTULO <- 7

res_barra_apilada <- function(rep, nombre = "") {
  div(
    class = "res-barra", role = "img",
    `aria-label` = sprintf("%s: %s en riesgo alto o muy alto, de %s encuestas efectivas.",
                           nombre, fmt_pct(rep$alto), fmt_num(rep$n)),
    lapply(seq_along(rep$conteo), function(i) {
      if (rep$conteo[i] == 0) return(NULL)
      div(class = paste0("res-seg niv", i),
          style = sprintf("flex:%d;", rep$conteo[i]),
          title = sprintf("%s: %s (%s de %s)", RES_NIVELES[i],
                          fmt_pct(rep$pct[i]), fmt_num(rep$conteo[i]), fmt_num(rep$n)),
          if (rep$pct[i] >= RES_MIN_ROTULO) fmt_num(rep$pct[i], 1))
    }))
}

# --- fila de un grupo (desagregación) -----------------------------------------
# `ref_alto` es el porcentaje de la universidad en la medida, o NA si no hay con
# qué comparar; entonces la columna dice `vacio`. La diferencia lleva color y
# símbolo, como en el ranking: es el mismo pp contra la misma referencia.
res_fila_grupo <- function(nombre, n, rep, ref_alto = NA_real_, total = FALSE,
                           vacio = "—") {
  if (is.null(rep)) {
    return(div(
      class = "res-fila res-fila-reservada",
      div(class = "res-nom", nombre, tags$em(sprintf("n = %s", fmt_num(n)))),
      div(class = "res-reservado",
          sprintf("Resultado reservado: menos de %s encuestas efectivas", RES_MIN_N)),
      div(class = "res-val", "—"),
      div(class = "res-delta", "—")))
  }

  d  <- if (is.null(ref_alto) || is.na(ref_alto)) NA_real_
        else round(rep$alto - ref_alto, 1)
  sn <- res_senal(d)

  div(
    class = paste("res-fila res-fila-dist", if (total) "res-total"),
    div(class = "res-nom", nombre, tags$em(sprintf("n = %s", fmt_num(n)))),
    res_barra_apilada(rep, nombre),
    div(class = "res-val", fmt_pct(rep$alto)),
    div(class = paste("res-delta", sn$cls),
        if (is.na(d)) tags$span(class = "res-sin-comp", vacio)
        else tagList(
          span(class = "res-senal", `aria-hidden` = "true", sn$sig),
          sprintf("%s%s pp", if (d > 0) "+" else if (d < 0) "−" else "±",
                  fmt_num(abs(d), 1)))))
}

# --- detalle de una medida (contenido del modal) ------------------------------
res_detalle_ui <- function(det, comparar = TRUE) {
  if (is.null(det$rep)) {
    return(div(class = "alert alert-secondary",
               sprintf(paste("Resultado reservado: esta medida tiene %s",
                             "encuestas efectivas en el segmento, por debajo",
                             "del mínimo de %s."), fmt_num(det$n), RES_MIN_N)))
  }

  sn <- res_senal(if (comparar) det$delta else NA_real_)

  tagList(
    div(class = "res-det-cifras",
        div(class = "res-det-caja",
            div(class = "res-t-cifra", fmt_pct(det$rep$alto)),
            div(class = "res-t-rotulo", "riesgo alto o muy alto")),
        if (comparar && !is.na(det$univ)) div(class = "res-det-caja",
            div(class = "res-t-cifra", fmt_pct(det$univ)),
            div(class = "res-t-rotulo", "la universidad")),
        if (comparar && !is.na(det$delta)) div(class = paste("res-det-caja", sn$cls),
            div(class = "res-t-cifra",
                sprintf("%s%s", if (det$delta > 0) "+" else if (det$delta < 0) "−" else "±",
                        fmt_num(abs(det$delta), 1))),
            div(class = "res-t-rotulo", sprintf("pp · %s", tolower(sn$txt)))),
        div(class = "res-det-caja",
            div(class = "res-t-cifra", fmt_num(det$rep$n)),
            div(class = "res-t-rotulo", "encuestas efectivas"))),

    res_leyenda_niveles(),
    res_barra_apilada(det$rep, det$rotulo),

    div(class = "tabla-dep-caja mt-3",
        tags$table(
          class = "tabla-dep res-tabla",
          tags$thead(tags$tr(
            tags$th(scope = "col", "Nivel"),
            tags$th(scope = "col", class = "der", "Cuestionarios"),
            tags$th(scope = "col", class = "der", "% del segmento"))),
          tags$tbody(lapply(seq_along(RES_NIVELES), function(i) tags$tr(
            tags$th(scope = "row",
                    span(class = paste0("res-muestra niv", i)), RES_NIVELES[i]),
            tags$td(class = "der", fmt_num(det$rep$conteo[i])),
            tags$td(class = "der", fmt_pct(det$rep$pct[i]))))))),

    res_micro(if (comparar && !is.na(det$delta))
      paste("La diferencia es descriptiva: la resta del porcentaje del segmento",
            "menos el de la universidad en esta misma medida.")
      else "Reparto de las encuestas efectivas del segmento en los cinco niveles.")
  )
}

# --- cabecera de cuestionario dentro de una tabla -----------------------------
# Las tablas grandes se parten en los mismos tres cuestionarios que el ranking,
# por la misma razón: son instrumentos distintos y no se restan entre sí. Aquí
# no se puede usar <details> --no es HTML válido dentro de <table>, y partir la
# tabla en tres descuadraría el ancho de las columnas, que es justo lo que
# permite seguir a un grupo de arriba abajo--, así que el pliegue es una clase
# sobre el <tbody> y un botón que la conmuta. Es un <button> de verdad: Enter y
# espacio funcionan sin escribir una línea de teclado.
#
# La VISTA va en la cabecera aunque no se pueda cambiar desde aquí: se elige
# arriba, en "¿Qué está pasando?", y sin decirla estas filas parecerían las de
# todo el mundo cuando pueden ser las de una sola forma.
#
# `abierto = FALSE` es para el cuestionario que no tiene nada que enseñar. No se
# esconde, se pliega: esconderlo haría creer que no existe.
res_cab_bloque_tabla <- function(ctx, ncols, n_filas, abierto = TRUE,
                                 nota = NULL) {
  n_total <- length(ctx$claves)
  # "12 de 25 medidas" cuando la búsqueda recortó el cuestionario: si solo
  # dijera "12 medidas" parecería que el instrumento tiene doce.
  cuenta <- if (n_filas == n_total) sprintf("%s medidas", fmt_num(n_filas))
            else sprintf("%s de %s medidas", fmt_num(n_filas), fmt_num(n_total))
  if (n_filas == 1) cuenta <- sub("^1 medidas$", "1 medida", cuenta)

  tags$tr(
    class = "res-tb-cab",
    tags$th(
      scope = "colgroup", colspan = ncols,
      tags$button(
        type = "button", class = "res-tb-boton", `data-plegar` = "",
        `data-bloque` = ctx$id,
        `aria-expanded` = if (abierto) "true" else "false",
        tags$span(class = "res-tb-flecha", `aria-hidden` = "true"),
        tags$span(class = "res-tb-tit", ctx$b$titulo),
        tags$span(class = paste("res-bl-vista",
                                if (!identical(ctx$vista, "T")) "forma"),
                  res_vista_txt(ctx$vista)),
        tags$span(class = "res-tb-sub",
                  sprintf("%s · n = %s · %s", ctx$b$sub, fmt_num(ctx$n), cuenta)),
        if (!is.null(nota)) tags$span(class = "res-tb-nota", nota))))
}


# --- mapa de calor ------------------------------------------------------------

res_leyenda_mapa <- function(metrica) {
  it <- if (identical(metrica, "delta")) {
    list(c("mejor", "por debajo de la universidad"), c("cero", "igual (±2 pp)"),
         c("b2", "2 a 6 pp encima"), c("b3", "6 a 12 pp encima"),
         c("b4", "más de 12 pp encima"))
  } else {
    list(c("b1", "lo más bajo"), c("b2", "intermedio bajo"),
         c("b3", "intermedio alto"), c("b4", "lo más alto"))
  }
  div(class = "res-leyenda",
      lapply(it, function(x)
        span(class = "res-leyenda-it",
             span(class = paste0("res-muestra banda-", x[1])), x[2])))
}

# En la métrica de porcentaje los cortes salen del rango que ocupa la propia
# tabla (con datos apretados, cortar sobre 0-100 dejaría todo del mismo color);
# en la de diferencia son puntos porcentuales fijos y CENTRADOS EN CERO, para
# que el color signifique lo mismo esta semana y la siguiente.
res_banda <- function(v, lo, hi, metrica) {
  if (is.na(v)) return("banda-nula")
  if (identical(metrica, "delta")) {
    if (v <= -RES_UMBRAL_SIMILAR) return("banda-mejor")
    if (v <   RES_UMBRAL_SIMILAR) return("banda-cero")
    return(if (v < 6) "banda-b2" else if (v < 12) "banda-b3" else "banda-b4")
  }
  if (!is.finite(hi - lo) || hi - lo < 1) return("banda-b2")
  i <- min(4L, max(1L, as.integer(floor((v - lo) / (hi - lo) * 4)) + 1L))
  paste0("banda-b", i)
}

# `bloques` son los contextos de los tres cuestionarios, cada uno ya con su
# matriz medida x grupo calculada sobre SU vista. Las columnas --y su n-- son
# las mismas para los tres y salen del segmento entero, que es lo que permite
# seguir a un grupo de arriba abajo aunque el intralaboral se esté mirando en
# forma B y el extralaboral en total.
#
# Las bandas de color se calculan sobre TODOS los valores juntos, no bloque a
# bloque: un color tiene que significar lo mismo en toda la tabla.
#
# `abiertos` dice qué cuestionarios van desplegados, por id. Por defecto
# ninguno: el mapa entero son decenas de filas por cuestionario, y plegados lo
# primero que se ve son los tres títulos con su n.
res_mapa_calor <- function(bloques, cats, n_de, metrica, rotulo_cruce,
                           abiertos = list()) {

  vals <- unlist(lapply(bloques, function(ctx) {
    if (identical(metrica, "delta"))
      as.vector(ctx$m - ctx$ref[rownames(ctx$m)])
    else as.vector(ctx$m)
  }), use.names = FALSE)
  vals <- vals[!is.na(vals)]
  lo <- if (length(vals)) min(vals) else 0
  hi <- if (length(vals)) max(vals) else 1

  celda <- function(ctx, k, ct) {
    v <- ctx$m[k, ct]
    d <- if (is.na(v)) NA_real_ else round(v - unname(ctx$ref[k]), 1)
    val <- if (identical(metrica, "delta")) d else v

    txt <- if (is.na(val)) "res." else if (identical(metrica, "delta")) {
      sprintf("%s%s", if (val > 0) "+" else if (val < 0) "−" else "±",
              fmt_num(abs(val), 1))
    } else fmt_num(val, 1)

    # El globo dice la vista: la misma celda vale otra cosa en la forma A que
    # en el total, y aquí no hay cabecera de bloque a la vista si la tabla se
    # ha desplazado.
    forma <- if (identical(ctx$vista, "T")) "todas las formas"
             else sprintf("forma %s", ctx$vista)

    tags$td(
      class = paste("res-cel", res_banda(val, lo, hi, metrica)),
      title = if (is.na(v)) {
        sprintf("%s · %s (%s): resultado reservado (menos de %s encuestas efectivas).",
                ct, RES_ROTULOS[[k]], forma, RES_MIN_N)
      } else {
        sprintf(paste("Grupo: %s (n = %s en el segmento)\nMedida: %s (%s)",
                      "\nValor: %s en riesgo alto o muy alto\nUniversidad: %s",
                      "\nDiferencia: %s%s pp"),
                ct, fmt_num(unname(n_de[ct])), RES_ROTULOS[[k]], forma,
                fmt_pct(v), fmt_pct(unname(ctx$ref[k])),
                if (d > 0) "+" else if (d < 0) "−" else "±", fmt_num(abs(d), 1))
      },
      txt)
  }

  div(
    class = "tabla-dep-caja res-mapa-caja",
    tags$table(
      class = "res-mapa",
      tags$caption(class = "visually-hidden",
                   sprintf(paste("Porcentaje en riesgo alto o muy alto por %s,",
                                 "para cada medida de la Bateria."),
                           tolower(rotulo_cruce))),
      tags$thead(tags$tr(
        tags$th(scope = "col", class = "res-esquina", rotulo_cruce),
        lapply(cats, function(ct) tags$th(
          scope = "col", div(ct),
          tags$span(class = "res-n", sprintf("n = %s", fmt_num(unname(n_de[ct])))))))),
      # Un <tbody> por cuestionario. El que sale entero reservado --la forma B
      # de una facultad de profesores-- además lo dice en la cabecera, para que
      # no haya que desplegarlo para ver 22 filas de "res.".
      lapply(bloques, function(ctx) {
        con_dato <- any(!is.na(ctx$m))
        abierto  <- con_dato && isTRUE(abiertos[[ctx$id]])
        tags$tbody(
          class = paste("res-tb", if (!abierto) "plegado"),
          res_cab_bloque_tabla(ctx, length(cats) + 1, length(ctx$claves),
                               abierto = abierto,
                               nota = if (!con_dato) "sin datos en estos grupos"),
          # Las filas van en orden de estructura, así que aquí la jerarquía sí
          # se puede dibujar: la sangría dice si es total, dominio o dimensión.
          lapply(ctx$claves, function(k) tags$tr(
            tags$th(scope = "row",
                    class = paste0("res-rot-fila res-rf-", res_nivel_de(k)),
                    tags$span(class = "visually-hidden",
                              sprintf("%s. ", res_sitio_de(k, ctx$vista)$nivel)),
                    RES_ROTULOS[[k]],
                    if (k %in% RES_SOLO_A_CLAVES && !identical(ctx$vista, "A"))
                      tags$span(class = "res-nivel-tag res-nv-solo-a", "solo forma A")),
            lapply(cats, function(ct) celda(ctx, k, ct)))))
      })
    )
  )
}

# --- tabla analítica ----------------------------------------------------------
# La Batería tiene estructura: total → dominios → dimensiones. La tabla la
# respeta por defecto, porque leer una dimensión sin su dominio encima obliga a
# recordar de memoria a cuál pertenece, y poner dos dimensiones de dominios
# distintos una al lado de la otra invita a compararlas como si fueran
# hermanas. El orden por riesgo sigue disponible: es otra pregunta, y entonces
# la jerarquía se anuncia con una etiqueta en vez de con la sangría.
# `bloques` son los contextos, cada uno con sus filas ya ordenadas y recortadas
# por la búsqueda. La tabla no vuelve a ordenar ni a filtrar: si lo hiciera,
# podría discrepar del ranking de arriba, que es de donde salen estas filas.
res_tabla_analitica <- function(bloques, comparar = TRUE, jerarquia = TRUE) {
  corto <- c("Sin riesgo", "Bajo", "Medio", "Alto", "Muy alto")
  est   <- res_estructura()
  etiqueta_nivel <- c(total = "Total", dominio = "Dominio", dimension = "Dimensión")

  nombre <- function(f, ctx) {
    lv <- est$nivel[match(f$clave, est$clave)] %||% "dimension"
    tagList(
      # El nivel viaja SIEMPRE en texto, no solo en la sangría: un lector de
      # pantalla no oye el margen izquierdo.
      tags$span(class = "visually-hidden",
                sprintf("%s. %s. ", ctx$b$titulo, etiqueta_nivel[[lv]])),
      f$rotulo,
      # La marca de las exclusivas de la forma A va SIEMPRE visible en la vista
      # total: su n es más chico que el de sus vecinas y sin la marca parece un
      # error de cálculo.
      if (isTRUE(f$solo_a) && !identical(ctx$vista, "A"))
        tags$span(class = "res-nivel-tag res-nv-solo-a", "solo forma A"),
      if (!jerarquia) tags$span(class = paste0("res-nivel-tag res-nv-", lv),
                                etiqueta_nivel[[lv]]))
  }

  fila <- function(f, ctx) {
    lv  <- est$nivel[match(f$clave, est$clave)] %||% "dimension"
    rp  <- ctx$rep[[f$clave]]
    cls <- paste0("res-tr-", lv, if (jerarquia) " res-jerarquia" else "")

    if (isTRUE(f$reservado) || is.null(rp)) {
      return(tags$tr(
        class = cls,
        tags$th(scope = "row", nombre(f, ctx)),
        tags$td(class = "der", fmt_num(f$n)),
        tags$td(colspan = if (comparar) "8" else "6", class = "text-muted",
                sprintf("Reservado (menos de %s)", RES_MIN_N))))
    }

    sn <- res_senal(if (comparar) f$delta else NA_real_)
    tags$tr(
      class = cls,
      tags$th(scope = "row", nombre(f, ctx)),
      tags$td(class = "der", fmt_num(f$n)),
      lapply(rp$pct, function(p) tags$td(class = "der", fmt_pct(p))),
      tags$td(class = "der res-col-clave", fmt_pct(f$pct)),
      if (comparar) tags$td(class = "der", fmt_pct(f$univ)),
      if (comparar) tags$td(
        class = paste("der res-delta-cel", sn$cls),
        span(class = "res-senal", `aria-hidden` = "true", sn$sig),
        sprintf("%s%s", if (f$delta > 0) "+" else if (f$delta < 0) "−" else "±",
                fmt_num(abs(f$delta), 1))))
  }

  div(
    class = "tabla-dep-caja",
    tags$table(
      class = "tabla-dep res-tabla res-tabla-analitica",
      tags$caption(class = "visually-hidden",
                   paste("Reparto de cada medida de la Bateria en los cinco",
                         "niveles de riesgo, por total, dominio y dimension.")),
      tags$thead(tags$tr(
        tags$th(scope = "col", "Medida"),
        tags$th(scope = "col", class = "der", "n"),
        lapply(corto, function(h) tags$th(scope = "col", class = "der", h)),
        tags$th(scope = "col", class = "der res-col-clave", "Alto + muy alto"),
        if (comparar) tags$th(scope = "col", class = "der", "Universidad"),
        if (comparar) tags$th(scope = "col", class = "der", "Δ pp"))),
      # Un <tbody> por cuestionario, igual que el ranking y el mapa. El orden
      # elegido --estructura o riesgo-- se aplica DENTRO de cada uno: entre
      # cuestionarios no hay orden que signifique nada.
      lapply(bloques, function(ctx) {
        fb <- ctx$filas
        # Con la búsqueda puesta, un cuestionario sin coincidencias sí se
        # omite: el usuario acaba de pedir explícitamente que se recorte.
        if (is.null(fb) || !nrow(fb)) return(NULL)
        con_dato <- any(!fb$reservado)
        tags$tbody(
          class = paste("res-tb", if (!con_dato) "plegado"),
          res_cab_bloque_tabla(
            ctx, if (comparar) 10L else 8L, nrow(fb), abierto = con_dato,
            nota = if (!con_dato) "todo reservado en esta vista"),
          lapply(seq_len(nrow(fb)), function(i) fila(fb[i, ], ctx)))
      })
    )
  )
}

# --- avisos -------------------------------------------------------------------

res_aviso_reserva <- function(n) {
  div(
    class = "res-reserva-aviso",
    div(class = "res-reserva-tit", "Resultado reservado"),
    tags$p(sprintf(paste("El segmento tiene %s %s. Por debajo de %s no se muestran",
                         "resultados: el reparto en los niveles permitiría",
                         "inferir respuestas individuales."),
                   fmt_num(n), if (n == 1) "encuesta efectiva" else "encuestas efectivas",
                   RES_MIN_N)),
    tags$p(class = "small mb-0",
           "Quite alguno de los filtros para ampliar la población analizada."))
}

res_aviso_sin_clasificacion <- function() {
  div(class = "alert alert-secondary",
      tags$p(tags$strong("Todavía no hay resultados calificados.")),
      tags$p(class = "small mb-0",
             "La tabla ", tags$code("public.respuestas_procesadas"),
             " no trae las columnas de clasificación. Las escribe ",
             tags$code("conectar_bd.R"), ", que es un paso aparte del cargue del marco."))
}

res_aviso_sin_respuestas <- function() {
  div(class = "alert alert-secondary",
      "Todavía no hay ninguna encuesta efectiva que calificar.")
}


# --- resumen descriptivo ------------------------------------------------------
# Quien contesto la Bateria: su perfil, y si se parece a quien debia contestarla.
# Nace PLEGADO --<details> sin `open`-- porque es contexto que se consulta una
# vez y no en cada mirada, el mismo criterio con el que se pliegan los bloques
# del ranking. Plegado no es escondido: la cabecera dice de cuanta gente habla,
# asi que se ve sin abrirlo si el descriptivo merece un vistazo.
#
# Los bloques 2 y 3 salen del segmento YA filtrado, el mismo data.frame que
# alimenta el ranking: no vuelven a la base y no pueden describir una poblacion
# distinta de la que se esta analizando.

# Una variable categorica: un grafico de barras horizontales, una por categoria
# y ordenadas de mayor a menor. La barra ocupa el ancho util y el valor se
# escribe AL FINAL de la barra, no en una columna aparte: asi la cifra viaja con
# su barra y no hay que cruzar la vista entre dos columnas para emparejarlas,
# que es lo que convertia esto en una tabla.
#
# COLOR. Todas las barras van del mismo verde institucional, a media opacidad.
# Es deliberado y hay que dejarlo escrito: la app tiene dos paletas con
# significado --los cinco niveles de riesgo (--niv1..5) y las bandas del mapa--
# y ninguna de las dos vale aqui. Pintar el estrato 1 de rojo y el 6 de verde,
# o al reves, afirmaria un orden de gravedad que un descriptivo NO mide: esto
# dice cuanta gente hay en cada categoria, no si esa categoria esta mejor o peor.
# Un solo color neutro es la unica lectura honesta.
#
# "Sin dato" es la excepcion, en gris: no es una categoria mas, es la ausencia
# de la categoria, y ya iba en gris cuando esto era una tabla.
#
# `tope` fija la escala desde fuera: los paneles del cruce la comparten para que
# una barra de un panel se pueda comparar con la del vecino.
res_desc_cat <- function(x, tope = NULL) {
  if (is.null(tope)) tope <- max(c(x$res$pct, 1), na.rm = TRUE)
  div(
    class = "res-desc-cat", role = "img",
    `aria-label` = sprintf("%s: %s.", x$rotulo,
      paste(sprintf("%s %s por ciento", x$res$categoria, fmt_num(x$res$pct, 1)),
            collapse = "; ")),
    lapply(seq_len(nrow(x$res)), function(i) {
      f <- x$res[i, ]
      sin <- identical(f$categoria, RES_SIN_DATO)
      div(
        class = paste("res-desc-it", if (sin) "sin-dato"),
        div(class = "res-desc-et", title = f$categoria, f$categoria),
        div(class = "res-desc-pista",
            # El ancho se escala al MAYOR de la variable y no a 100: con la
            # categoria mas grande en el 34% --el estrato 3-- escalar sobre 100
            # dejaria las seis barras en el tercio izquierdo y sin diferencias
            # visibles. Los porcentajes van escritos, asi que la escala relativa
            # no puede enganar sobre la magnitud.
            span(class = "res-desc-barra",
                 style = sprintf("width:%s%%;", round(100 * f$pct / tope, 2))),
            span(class = "res-desc-cifra-bar",
                 tags$b(fmt_pct(f$pct)),
                 tags$span(class = "res-desc-nn", fmt_num(f$n)))))
    }))
}

# Una variable numerica: cuatro cifras en una linea. No hay grafico porque no
# hay nada que dibujar --son cuatro escalares, no una distribucion-- y una caja
# de bigotes por cada una anadiria tinta sin anadir lectura.
#
# Van con la n sobre la que se calcularon porque una media sobre 12 de 1.499 no
# es la media del segmento y sin la n no hay forma de notarlo.
res_desc_num_ui <- function(x) {
  r <- x$res
  cifra <- function(et, v) div(class = "res-desc-cifra",
                               div(class = "res-desc-cv", fmt_num(v, 1)),
                               div(class = "res-desc-ce", et))
  div(
    class = "res-desc-nums",
    cifra("media", r$media),
    cifra("mediana", r$mediana),
    div(class = "res-desc-cifra",
        div(class = "res-desc-cv", sprintf("%s\u2013%s", fmt_num(r$min), fmt_num(r$max))),
        div(class = "res-desc-ce", "rango")),
    div(class = "res-desc-cifra",
        div(class = "res-desc-cv", fmt_num(r$n)),
        div(class = "res-desc-ce", "con dato")))
}

res_desc_bloque <- function(b) {
  if (!length(b$vars)) return(NULL)
  div(
    class = "res-desc-bloque",
    h6(b$titulo),
    div(class = "res-desc-rejilla",
        lapply(b$vars, function(x) div(
          class = "res-desc-var",
          div(class = "res-desc-tit", x$rotulo),
          if (identical(x$tipo, "num")) res_desc_num_ui(x) else res_desc_cat(x))))
  )
}

# El cuerpo de la sección. El <details> que la envuelve y su cabecera --que
# dice de cuánta gente habla sin desplegarla-- son estáticos y viven en
# mod_resultados_ui().
res_descriptivo_ui <- function(desc) {
  tagList(lapply(desc, res_desc_bloque))
}


# --- cruce de dos variables ---------------------------------------------------
# Una tabla y un gráfico con los mismos números. La tabla lleva conteos y
# porcentajes; el gráfico, solo los porcentajes elegidos.
#
# El gráfico son PANELES, uno por categoría, cada uno con las mismas barras
# horizontales de las variables sueltas (res_desc_cat()). No son barras
# apiladas ni agrupadas por color porque el descriptivo va en un solo color
# neutro (ver arriba): colorear las categorías de la segunda variable exigiría
# una paleta que no tiene nada que decir. Los paneles siguen la base del
# porcentaje --con "% de la columna" hay uno por columna-- para que cada panel
# sume 100 %, y la escala es COMÚN a todos, para que se comparen entre sí.
res_desc_cruce_ui <- function(cr, modo = "fila") {
  n  <- cr$n
  p  <- res_desc_cruce_pct(n, modo)
  nf <- nrow(n) - 1L
  nc <- ncol(n) - 1L

  tabla <- div(
    class = "res-cruce-envoltura",
    tags$table(
      class = "table table-sm res-cruce-tabla",
      tags$thead(
        tags$tr(
          tags$th(scope = "col", rowspan = 2, class = "res-cruce-esq", cr$rot_fila),
          tags$th(scope = "colgroup", colspan = nc + 1L, cr$rot_col)),
        tags$tr(lapply(seq_len(ncol(n)), function(j) {
          ct <- colnames(n)[j]
          tags$th(scope = "col",
                  class = paste(if (j > nc) "res-cruce-marg",
                                if (identical(ct, RES_SIN_DATO)) "sin-dato"),
                  ct)
        }))),
      tags$tbody(lapply(seq_len(nrow(n)), function(i) {
        ct <- rownames(n)[i]
        tags$tr(
          class = paste(if (i > nf) "res-cruce-total",
                        if (identical(ct, RES_SIN_DATO)) "sin-dato"),
          tags$th(scope = "row", ct),
          lapply(seq_len(ncol(n)), function(j)
            tags$td(class = if (j > nc) "res-cruce-marg",
                    tags$b(fmt_pct(p[i, j])),
                    tags$span(class = "res-desc-nn", fmt_num(n[i, j])))))
      }))))

  # Paneles por fila, salvo con "% de la columna".
  por_col <- identical(modo, "columna")
  celdas  <- function(m) {
    m <- m[seq_len(nf), seq_len(nc), drop = FALSE]
    if (por_col) t(m) else m
  }
  pn  <- celdas(n)
  pp  <- celdas(p)
  tot <- if (por_col) n[nrow(n), seq_len(nc)] else n[seq_len(nf), ncol(n)]
  rot <- if (por_col) cr$rot_col else cr$rot_fila
  tope <- max(c(pp, 1), na.rm = TRUE)

  grafico <- div(
    class = "res-desc-rejilla",
    lapply(seq_len(nrow(pn)), function(i) {
      nom <- rownames(pn)[i]
      x <- list(rotulo = sprintf("%s: %s", rot, nom),
                res = data.frame(categoria = colnames(pn), n = pn[i, ],
                                 pct = ifelse(is.na(pp[i, ]), 0, pp[i, ]),
                                 stringsAsFactors = FALSE))
      div(class = paste("res-desc-var", if (identical(nom, RES_SIN_DATO)) "sin-dato"),
          div(class = "res-desc-tit", nom,
              tags$span(class = "res-desc-nn", sprintf("n = %s", fmt_num(tot[i])))),
          res_desc_cat(x, tope))
    }))

  lectura <- switch(modo,
    fila = sprintf(paste("Cada fila suma 100 %%: se lee cómo se reparte %s dentro",
                         "de cada grupo de %s. La fila Total es ese reparto en todo",
                         "el segmento, y sirve de punto de comparación."),
                   tolower(cr$rot_col), tolower(cr$rot_fila)),
    columna = sprintf(paste("Cada columna suma 100 %%: se lee cómo se reparte %s",
                            "dentro de cada grupo de %s. La columna Total es ese",
                            "reparto en todo el segmento."),
                      tolower(cr$rot_fila), tolower(cr$rot_col)),
    paste("Todas las celdas juntas suman 100 %: cada una es la parte del segmento",
          "que cae a la vez en esa fila y esa columna."))

  tagList(
    tabla,
    res_micro(lectura, "Junto a cada porcentaje, en gris, el número de encuestas efectivas."),
    h6(class = "res-sub", "En barras"),
    grafico,
    res_micro(sprintf(paste("Un panel por grupo de %s. Todas las barras usan la",
                            "misma escala, así que se comparan también entre paneles."),
                      tolower(rot))))
}

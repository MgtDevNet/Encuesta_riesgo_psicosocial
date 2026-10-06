# Modules/mod_citaciones.R
# Grupos de aplicación, anotaciones de la sesión y carga de la agenda. Son dos
# módulos:
#
#   mod_citaciones_ui(id, rol)   pestaña Citaciones: calendario, grupos y
#   mod_citaciones_server(id, r) anotaciones
#   mod_agenda_ui(id)            carga de la agenda; se dibuja dentro de la
#   mod_agenda_server(id, r)     pestaña Administración (Modules/mod_usuarios.R)
#
# Lo que puede hacer cada uno sale de AUTH_PERMISOS (R/utils_auth.R):
#   tomar_grupos      el psicólogo, que es quien aplica, se asigna un grupo libre
#                     y lo puede soltar mientras no haya empezado;
#   asignar_grupos    le pone o le quita el psicólogo a cualquier grupo;
#   cargar_agenda     sube el Excel y reemplaza la agenda;
#   registrar_sesion  el psicólogo del grupo escribe las anotaciones de su sesión
#                     (seg_obs_* en utils_seguimiento.R);
#   revisar_sesiones  lee y corrige cualquier anotación.
#
# Las anotaciones van en una subpestaña fija --no en una ventana emergente-- con
# un selector de grupo: una anotación para toda la sesión y, cuando hace falta,
# una para alguien en particular. Los botones del calendario y de la tabla llevan
# a esa subpestaña con el grupo ya elegido.
#
# La interfaz se dibuja según el rol de la ficha, pero esa no es la protección:
# cada acción vuelve a leer el rol de la base, porque pudo cambiar con la sesión
# abierta y un input se puede mandar a mano.
#
# La agenda se reemplaza entera: es una foto de la programacion, y una cita que
# se quito tiene que dejar de contar. Los grupos que salen pierden su psicólogo,
# pero las anotaciones se quedan: son lo que pasó. Al guardar sube CIT_CARGAS,
# que se comparte entre sesiones; cada sesion lo copia en r$citaciones, que el
# modulo de seguimiento escucha para rehacer sus cifras sin recargar la pagina.

# Filas que se muestran en la revision. Es para ver que las columnas se leyeron
# bien, no para revisar la agenda fila por fila.
CIT_VISTA_FILAS <- 200L

# Cargas de agenda y cambios de grupos hechos desde la app, contados en el
# proceso y no en la sesion: quien tiene la app abierta ve lo que hizo otra
# persona sin recargar. Lo que se cambie con scripts/preparar_bd.R no pasa por
# aqui; los grupos, de todos modos, se releen cada minuto.
CIT_CARGAS <- reactiveVal(0)
CIT_GRUPOS <- reactiveVal(0)

# El permiso se lee de la base en cada accion (ver el encabezado).
cit_puede <- function(r, permiso) {
  isTRUE(tryCatch(auth_puede_usuario(r$usuario$usuario, permiso),
                  error = function(e) FALSE))
}

# Cambios de grupos, de agenda y de anotaciones a la bitácora, con quién y desde
# dónde. Si escribirla falla, lo que ya se guardó no se deshace.
cit_bitacora <- function(r, evento, detalle) {
  try(auth_bitacora(evento, r$usuario$usuario, detalle,
                    r$usuario$origen %||% NA_character_), silent = TRUE)
}


# === Grupos y anotaciones (pestaña Citaciones) ===============================

mod_citaciones_ui <- function(id, rol) {
  ns     <- NS(id)
  toma   <- auth_puede(rol, "tomar_grupos")
  asigna <- auth_puede(rol, "asignar_grupos")
  anota  <- auth_puede(rol, "registrar_sesion") || auth_puede(rol, "revisar_sesiones")

  fluidPage(
    class = "py-3",

    # Botones de la tabla y del calendario. Mismo patron delegado de
    # mod_seguimiento: renderUI() rehace todo, y un listener pegado a la fila se
    # iria con la fila vieja.
    tags$script(HTML(sprintf(
      "$(document).on('click', '#%s [data-grupo], #%s [data-grupo]', function(){
         Shiny.setInputValue('%s', {accion: String($(this).attr('data-accion')),
                                    clave:  String($(this).attr('data-grupo'))},
                             {priority: 'event'});
       });",
      ns("grupos"), ns("calendario"), ns("grupo_accion")
    ))),

    h4("Grupos de aplicación", class = "mb-1"),
    p(class = "text-muted mb-3",
      if (toma) paste("Asígnese un grupo libre. Puede soltarlo mientras no haya empezado;",
                      "desde la hora de inicio queda fijo.")
      else if (asigna) "Los grupos los aplican los psicólogos. Asígnelos con «Asignar…»."
      else "Los grupos los aplican los psicólogos.",
      if (anota)
        paste(" Desde la hora de inicio, el botón «Anotar» lleva a las anotaciones de la",
              "sesión: una del grupo y, si hace falta, una de alguien en particular.")),

    navset_underline(
      id = ns("vista"),
      selected = if (toma) "calendario" else "grupos",

      nav_panel(
        "Calendario", value = "calendario",
        div(class = "pt-3",
            div(class = "cal-barra",
                uiOutput(ns("cal_selector")),
                div(class = "cal-nav",
                    actionButton(ns("cal_prev"), NULL, icon = icon("chevron-left"),
                                 class = "btn-sm btn-outline-secondary",
                                 title = "Semana anterior", `aria-label` = "Semana anterior"),
                    actionButton(ns("cal_hoy"), "Esta semana",
                                 class = "btn-sm btn-outline-secondary"),
                    actionButton(ns("cal_next"), NULL, icon = icon("chevron-right"),
                                 class = "btn-sm btn-outline-secondary",
                                 title = "Semana siguiente", `aria-label` = "Semana siguiente"))),
            uiOutput(ns("calendario")))
      ),

      nav_panel(
        "Grupos", value = "grupos",
        div(class = "pt-3",
            uiOutput(ns("grupos_resumen")),
            radioButtons(ns("ver"), NULL, inline = TRUE,
                         choices = c(if (toma) c("Disponibles" = "libres", "Mis grupos" = "mios")
                                     else c("Sin asignar" = "libres"),
                                     if (anota) c("Sin anotar" = "anotar"),
                                     "Todos" = "todos")),
            uiOutput(ns("grupos")))
      ),

      nav_panel(
        "Anotaciones", value = "anotaciones",
        div(class = "pt-3",
            uiOutput(ns("anot_selector")),
            uiOutput(ns("anotaciones")))
      )
    )
  )
}


mod_citaciones_server <- function(id, r = reactiveValues()) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    grupo_modal <- reactiveVal(NULL) # el grupo abierto en la ventana de asignar
    anot_clave  <- reactiveVal(NULL) # el grupo elegido en Anotaciones
    anot_aviso  <- reactiveVal(NULL)

    observeEvent(CIT_CARGAS(), r$citaciones <- CIT_CARGAS(), ignoreInit = TRUE)

    # Los datos, y los mismos datos con reloj. El calendario y la tabla se releen
    # cada minuto --un grupo deja de poderse tomar a su hora de inicio aunque
    # nadie toque nada--, pero las anotaciones NO: con el reloj, el bloque se
    # redibujaría mientras el psicólogo escribe y le borraría lo escrito.
    grupos_datos <- reactive({
      CIT_GRUPOS()
      r$citaciones
      seg_grupos()
    })
    grupos <- reactive({
      invalidateLater(60000)
      grupos_datos()
    })

    # --- calendario ----------------------------------------------------------
    # Una semana a la vista. Muestra solo lo asignado: un grupo sin psicólogo no
    # es de nadie todavía, y ese se ve en la tabla de Grupos.

    semana <- reactiveVal(seg_lunes(seg_hoy()))
    observeEvent(input$cal_prev, semana(semana() - 7))
    observeEvent(input$cal_next, semana(semana() + 7))
    observeEvent(input$cal_hoy,  semana(seg_lunes(seg_hoy())))

    # A quién se mira: "" es todos los psicólogos. Antes de que el selector se
    # dibuje, el psicólogo se ve a sí mismo y los demás roles ven a todos.
    cal_quien <- function() {
      x <- input$cal_psicologo
      if (!is.null(x)) return(x)
      if (auth_puede(r$usuario$rol, "tomar_grupos")) r$usuario$usuario else ""
    }

    output$cal_selector <- renderUI({
      u <- r$usuario
      propio  <- auth_puede(u$rol, "tomar_grupos")
      aplican <- tryCatch(auth_listar_usuarios(), error = function(e) NULL)
      aplican <- if (is.null(aplican)) data.frame(usuario = character(0), nombre = character(0))
                 else aplican[aplican$rol %in% AUTH_PERMISOS$tomar_grupos, , drop = FALSE]
      nombres <- ifelse(aplican$usuario == u$usuario,
                        paste0(aplican$nombre, " (usted)"), aplican$nombre)
      div(class = "cal-selector",
          selectInput(ns("cal_psicologo"), "Psicólogo", width = "100%", selectize = FALSE,
                      choices = c("Todos los psicólogos" = "",
                                  stats::setNames(aplican$usuario, nombres)),
                      selected = if (propio) u$usuario else ""))
    })

    cal_grupos <- reactive({
      g <- grupos()
      g <- g[!is.na(g$usuario), , drop = FALSE]
      quien <- cal_quien()
      if (nzchar(quien)) g <- g[g$usuario == quien, , drop = FALSE]
      g
    })

    output$calendario <- renderUI({
      calendario_semana(cal_grupos(), semana(), hoy = seg_hoy(),
                        yo = r$usuario$usuario, con_nombre = !nzchar(cal_quien()), ns = ns,
                        rol = r$usuario$rol)
    })

    observeEvent(input$cal_proximo, {
      sig <- cal_grupos()$fecha
      sig <- sig[sig > semana() + 6]
      if (length(sig)) semana(seg_lunes(min(sig)))
    })

    # --- tabla de grupos -----------------------------------------------------

    output$grupos_resumen <- renderUI({
      g <- grupos()
      if (nrow(g) == 0) return(NULL)
      rol  <- r$usuario$rol
      toma <- auth_puede(rol, "tomar_grupos")
      div(class = "kpi-fila mb-2",
          cit_caja(fmt_num(nrow(g)), "Grupos"),
          cit_caja(fmt_num(sum(is.na(g$usuario) & !g$empezo)),
                   if (toma) "Disponibles" else "Sin asignar por empezar"),
          if (toma) cit_caja(fmt_num(sum(g$usuario %in% r$usuario$usuario)), "Mis grupos"),
          if (auth_puede(rol, "registrar_sesion") || auth_puede(rol, "revisar_sesiones"))
            cit_caja(fmt_num(sum(obs_por_anotar(g, r$usuario$usuario, rol))), "Sin anotar"))
    })

    output$grupos <- renderUI({
      g <- grupos()
      if (nrow(g) == 0) {
        return(alerta(paste("Todavía no hay agenda cargada: no hay grupos que asignar.",
                            "La carga el administrador en la pestaña Administración."),
                      "secondary"))
      }
      yo  <- r$usuario$usuario
      ver <- input$ver %||% "libres"
      sub <- switch(ver,
                    libres = g[is.na(g$usuario) & !g$empezo, , drop = FALSE],
                    mios   = g[g$usuario %in% yo, , drop = FALSE],
                    anotar = g[obs_por_anotar(g, yo, r$usuario$rol), , drop = FALSE],
                    g)
      if (nrow(sub) == 0) {
        return(alerta(switch(ver,
                             libres = "No queda ningún grupo libre por empezar.",
                             mios   = "Todavía no tiene grupos asignados.",
                             anotar = paste("No hay sesiones sin anotar. El botón «Anotar»",
                                            "aparece desde la hora de inicio de cada grupo."),
                             "No hay grupos."),
                      "secondary"))
      }
      tabla_grupos(sub, yo,
                   toma   = auth_puede(r$usuario$rol, "tomar_grupos"),
                   asigna = auth_puede(r$usuario$rol, "asignar_grupos"),
                   rol    = r$usuario$rol)
    })

    observeEvent(input$grupo_accion, {
      yo <- r$usuario$usuario
      a  <- input$grupo_accion
      g  <- seg_grupo_de_clave(a$clave)
      req(yo, g, a$accion %in% c("tomar", "soltar", "asignar", "anotar"))

      # Anotar no tiene ventana: lleva a la subpestaña con el grupo elegido.
      if (identical(a$accion, "anotar")) {
        anot_aviso(NULL)
        anot_clave(a$clave)
        updateTabsetPanel(session, "vista", selected = "anotaciones")
        return()
      }

      if (identical(a$accion, "asignar")) {
        req(cit_puede(r, "asignar_grupos"))
        usuarios <- tryCatch(auth_listar_usuarios(), error = function(e) NULL)
        req(usuarios)
        aplican <- usuarios[usuarios$rol %in% AUTH_PERMISOS$tomar_grupos, , drop = FALSE]
        todos   <- grupos()
        fila    <- todos[seg_grupo_clave(todos$fecha, todos$hora_inicio,
                                         todos$hora_fin, todos$link) == a$clave, , drop = FALSE]
        grupo_modal(g)
        showModal(modalDialog(
          title = paste("Grupo del", grupo_txt(g)),
          easyClose = TRUE,
          if (nrow(fila)) p(class = "text-muted",
                            sprintf("%s citadas.", n_personas(fila$personas[1]))),
          selectInput(ns("asignar_a"), "Psicólogo que lo aplica", width = "100%",
                      selectize = FALSE,
                      choices = c("Sin asignar" = "",
                                  stats::setNames(aplican$usuario,
                                                  sprintf("%s (%s)", aplican$nombre,
                                                          aplican$usuario))),
                      selected = if (nrow(fila) && !is.na(fila$usuario[1])) fila$usuario[1]
                                 else ""),
          if (nrow(aplican) == 0)
            p(class = "small text-muted mb-0",
              "No hay usuarios con rol de psicólogo: el administrador los crea en la pestaña Administración."),
          footer = tagList(
            modalButton("Cancelar"),
            actionButton(ns("asignar_ok"), "Guardar", class = "btn-primary"))
        ))
        return()
      }

      if (identical(a$accion, "tomar")) req(cit_puede(r, "tomar_grupos"))

      ok <- tryCatch(
        if (identical(a$accion, "tomar")) seg_grupo_tomar(g, yo) else seg_grupo_soltar(g, yo),
        error = function(e) {
          showNotification(paste("No se pudo guardar el cambio.", conditionMessage(e)),
                           type = "error", duration = NULL)
          NULL
        })
      if (is.null(ok)) return()

      if (ok) cit_bitacora(r, if (identical(a$accion, "tomar")) "grupo_tomado" else "grupo_soltado",
                           grupo_txt(g))

      # Tambien cuando no se pudo: la tabla de esta sesion estaba vieja.
      CIT_GRUPOS(CIT_GRUPOS() + 1)
      if (identical(a$accion, "tomar")) {
        if (ok) showNotification(paste("Quedó a cargo del grupo del", grupo_txt(g)),
                                 type = "message")
        else    showNotification(paste("Ese grupo ya no está disponible: lo tomó otra",
                                       "persona, ya empezó o salió de la agenda."),
                                 type = "warning")
      } else {
        if (ok) showNotification(paste("Soltó el grupo del", grupo_txt(g)), type = "message")
        else    showNotification(paste("Ese grupo ya no se puede soltar: ya empezó o",
                                       "no está a su nombre."),
                                 type = "warning")
      }
    })

    observeEvent(input$asignar_ok, {
      g <- grupo_modal()
      req(g, cit_puede(r, "asignar_grupos"))
      destino <- input$asignar_a %||% ""
      removeModal()
      grupo_modal(NULL)

      ok <- tryCatch(
        seg_grupo_asignar(g, if (nzchar(destino)) destino else NA_character_,
                          por = r$usuario$usuario),
        error = function(e) {
          showNotification(paste("No se pudo guardar la asignación.", conditionMessage(e)),
                           type = "error", duration = NULL)
          NULL
        })
      if (is.null(ok)) return()

      if (ok) cit_bitacora(r, if (nzchar(destino)) "grupo_asignado" else "grupo_liberado",
                           paste0(grupo_txt(g), if (nzchar(destino)) paste(" · a", destino)))

      CIT_GRUPOS(CIT_GRUPOS() + 1)
      if (!ok) {
        showNotification(paste("No se pudo asignar: el grupo salió de la agenda, o esa",
                               "persona ya no existe o ya no tiene rol de psicólogo."),
                         type = "warning")
      } else if (nzchar(destino)) {
        showNotification(sprintf("Grupo del %s asignado a %s.", grupo_txt(g), destino),
                         type = "message")
      } else {
        showNotification(sprintf("El grupo del %s quedó sin asignar.", grupo_txt(g)),
                         type = "message")
      }
    })

    # --- anotaciones ---------------------------------------------------------

    output$anot_aviso <- renderUI(alerta(anot_aviso()))

    # Los grupos que puede abrir: quien revisa, todos los que empezaron; el
    # psicólogo, los suyos y los que ya tengan anotaciones; los demás roles, solo
    # los que tengan anotaciones (la del grupo la puede leer cualquiera).
    anot_opciones <- reactive({
      g   <- grupos_datos()
      rol <- r$usuario$rol
      yo  <- r$usuario$usuario
      sel <- if (auth_puede(rol, "revisar_sesiones")) g$empezo
             else if (auth_puede(rol, "registrar_sesion"))
               g$empezo & (g$usuario %in% yo | g$anotaciones > 0)
             else g$anotaciones > 0
      g[sel %in% TRUE, , drop = FALSE]
    })

    # El grupo que se está mirando: el elegido, o el último que empezó.
    anot_actual <- reactive({
      cl <- anot_clave()
      op <- anot_opciones()
      if (is.null(cl) && nrow(op)) {
        cl <- seg_grupo_clave(op$fecha[nrow(op)], op$hora_inicio[nrow(op)],
                              op$hora_fin[nrow(op)], op$link[nrow(op)])
      }
      cl
    })

    output$anot_selector <- renderUI({
      op <- anot_opciones()
      if (nrow(op) == 0) return(NULL)
      claves <- seg_grupo_clave(op$fecha, op$hora_inicio, op$hora_fin, op$link)
      etiquetas <- sprintf("%s · %s–%s · %s · %s",
                           format(op$fecha, "%d/%m/%Y"), op$hora_inicio, op$hora_fin,
                           ifelse(is.na(op$aplicador), "sin psicólogo", op$aplicador),
                           ifelse(op$anotaciones > 0,
                                  sprintf("%s anotaciones", op$anotaciones), "sin anotaciones"))
      div(class = "anot-selector mb-3",
          selectInput(ns("anot_clave"), "Grupo", width = "100%", selectize = FALSE,
                      choices = stats::setNames(claves, etiquetas),
                      selected = anot_actual()))
    })

    observeEvent(input$anot_clave, {
      if (!identical(input$anot_clave, anot_actual())) anot_aviso(NULL)
      anot_clave(input$anot_clave)
    })

    output$anotaciones <- renderUI({
      cl <- anot_actual()
      if (is.null(cl)) {
        return(alerta(paste("Todavía no hay sesiones que anotar. El botón «Anotar» aparece",
                            "desde la hora de inicio de cada grupo."), "secondary"))
      }
      g <- seg_grupo_de_clave(cl)
      req(g)
      perm <- seg_obs_permiso(g, r$usuario$usuario)
      info <- seg_obs_leer(g)
      todos <- grupos_datos()
      fila  <- todos[seg_grupo_clave(todos$fecha, todos$hora_inicio, todos$hora_fin,
                                     todos$link) == cl, , drop = FALSE]
      seccion_anotaciones(ns, g, info, perm, fila)
    })

    observeEvent(input$anot_guardar, {
      cl <- anot_actual()
      req(cl)
      g <- seg_grupo_de_clave(cl)
      req(g)

      # Las personas se releen para tomarlas en el mismo orden con que se
      # dibujaron los campos anot_txt_i.
      info <- seg_obs_leer(g)
      personas <- if (nrow(info$personas)) data.frame(
        id_anonimizado = info$personas$id_anonimizado,
        observacion    = vapply(seq_len(nrow(info$personas)),
                                function(i) input[[paste0("anot_txt_", i)]] %||% "",
                                character(1)),
        stringsAsFactors = FALSE)

      error <- tryCatch({
        seg_obs_guardar(g, input$anot_general %||% "", personas, r$usuario$usuario)
        NULL
      }, error = function(e) conditionMessage(e))
      if (!is.null(error)) return(anot_aviso(alerta(error)))

      cit_bitacora(r, "anotaciones_guardadas", grupo_txt(g))
      CIT_GRUPOS(CIT_GRUPOS() + 1)
      anot_aviso(alerta("Anotaciones guardadas.", "success"))
    })
  })
}


# === Carga de la agenda (pestaña Administración) =============================

mod_agenda_ui <- function(id) {
  ns <- NS(id)

  tagList(
    h4("Agenda de citaciones", class = "mb-1"),
    p(class = "text-muted mb-3",
      "Suba el Excel con la programación. Primero se revisa y, al confirmar, ",
      "reemplaza completa la agenda guardada en la base."),

    uiOutput(ns("actual")),

    card(
      class = "shadow-sm mb-3",
      card_body(
        fileInput(ns("archivo"), "Archivo de la agenda",
                  accept = c(".xlsx", ".xls", ".csv"), width = "100%",
                  buttonLabel = "Elegir archivo…",
                  placeholder = "Ningún archivo seleccionado"),
        div(class = "small text-muted",
            "Excel (primera hoja) o CSV, con una fila por persona citada. ",
            "Columnas obligatorias: ", tags$b("fecha"), ", ",
            tags$b("hora inicio programada"), ", ", tags$b("hora final programada"),
            " e ", tags$b("id"), " (el id anonimizado). ",
            "Opcionales: ", tags$b("link"), " (http o https) y ", tags$b("persona"),
            ", el nombre, que solo ven el psicólogo del grupo y el administrador ",
            "al anotar la sesión.")
      )
    ),

    uiOutput(ns("revision"))
  )
}


mod_agenda_server <- function(id, r = reactiveValues()) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Lo subido, ya revisado. Va en un reactiveVal y no derivado de
    # input$archivo porque fileInput no se puede vaciar: al guardar hay que
    # quitar la revision aunque el archivo siga nombrado en el control.
    revision <- reactiveVal(NULL)
    aviso    <- reactiveVal(NULL)

    actual <- reactive({
      r$citaciones
      req(cit_puede(r, "cargar_agenda"))
      seg_cit_resumen()
    })

    observeEvent(input$archivo, {
      req(cit_puede(r, "cargar_agenda"))
      f <- input$archivo
      aviso(NULL)
      revision(tryCatch({
        cit <- seg_cit_normalizar(seg_cit_leer(f$datapath, f$name))
        if (nrow(cit) == 0) stop("El archivo no trae ninguna citación.", call. = FALSE)
        cit <- cit[order(cit$fecha, cit$hora_inicio, cit$id_anonimizado), , drop = FALSE]
        rownames(cit) <- NULL
        list(ok        = TRUE,
             nombre    = f$name,
             cit       = cit,
             fuera     = seg_cit_fuera_marco(cit),
             capacidad = seg_cit_capacidad(cit),
             huerfanos = seg_grupos_huerfanos(cit))
      }, error = function(e) {
        list(ok = FALSE, nombre = f$name, error = conditionMessage(e))
      }))
    })

    output$actual <- renderUI({
      a <- actual()
      if (!isTRUE(a$citaciones > 0)) {
        return(alerta("Todavía no hay ninguna agenda cargada en la base.", "secondary"))
      }
      div(
        h6("Cargada hoy en la base", class = "text-muted mb-2"),
        div(class = "kpi-fila mb-3",
            cit_caja(fmt_num(a$citaciones), "Citaciones"),
            cit_caja(fmt_num(a$personas), "Personas"),
            cit_caja(format(a$desde, "%d/%m/%Y"), "Primer día", fecha = TRUE),
            cit_caja(format(a$hasta, "%d/%m/%Y"), "Último día", fecha = TRUE)))
    })

    output$revision <- renderUI({
      rv <- revision()
      if (is.null(rv)) return(aviso())

      if (!isTRUE(rv$ok)) {
        return(alerta(tagList(
          tags$b("No se puede cargar ", rv$nombre, "."), " La base no se tocó.",
          div(class = "mt-2", style = "white-space: pre-line;", rv$error))))
      }

      cit <- rv$cit
      a   <- actual()
      h   <- rv$huerfanos
      sesiones <- nrow(unique(cit[, c("fecha", "hora_inicio", "hora_fin", "link")]))

      card(
        class = "shadow-sm",
        card_header(tags$b("Revisión de ", rv$nombre)),
        card_body(
          div(class = "kpi-fila mb-3",
              cit_caja(fmt_num(nrow(cit)), "Citaciones"),
              cit_caja(fmt_num(length(unique(cit$id_anonimizado))), "Personas"),
              cit_caja(fmt_num(sesiones), "Sesiones"),
              cit_caja(format(min(cit$fecha), "%d/%m/%Y"), "Primer día", fecha = TRUE),
              cit_caja(format(max(cit$fecha), "%d/%m/%Y"), "Último día", fecha = TRUE)),

          if (all(is.na(cit$nombre))) alerta(tagList(
            "El archivo no trae la columna del ", tags$b("nombre"),
            " (persona). Las anotaciones de la sesión van a ir por id."), "secondary"),

          if (length(rv$fuera)) alerta(tagList(
            tags$b(fmt_num(length(rv$fuera)),
                   if (length(rv$fuera) == 1) " persona citada no está en el marco"
                   else " personas citadas no están en el marco"),
            " y no va", if (length(rv$fuera) != 1) "n", " a contar en ningún avance (",
            paste(utils::head(rv$fuera, 5), collapse = ", "),
            if (length(rv$fuera) > 5) ", …", "). ",
            "Revise que la columna de id traiga el id anonimizado y no la cédula."),
            "warning"),

          if (nrow(rv$capacidad)) alerta(tagList(
            tags$b(nrow(rv$capacidad),
                   if (nrow(rv$capacidad) == 1) " franja pasa la capacidad"
                   else " franjas pasan la capacidad"),
            sprintf(" de %s personas o %s grupos por hora:",
                    SEG_CIT_POR_HORA, SEG_CIT_GRUPOS_HORA),
            tags$ul(class = "mb-0 mt-1", lapply(utils::head(seq_len(nrow(rv$capacidad)), 10),
              function(i) tags$li(sprintf("%s · %s %s en %s %s",
                                          rv$capacidad$franja[i],
                                          rv$capacidad$personas[i],
                                          if (rv$capacidad$personas[i] == 1) "persona" else "personas",
                                          rv$capacidad$grupos[i],
                                          if (rv$capacidad$grupos[i] == 1) "grupo" else "grupos"))))),
            "warning"),

          if (nrow(h)) alerta(tagList(
            tags$b(nrow(h),
                   if (nrow(h) == 1) " grupo con psicólogo no está en esta agenda"
                   else " grupos con psicólogo no están en esta agenda"),
            if (nrow(h) == 1) " y pierde su asignación al cargarla:"
            else " y pierden su asignación al cargarla:",
            tags$ul(class = "mb-0 mt-1", lapply(utils::head(seq_len(nrow(h)), 10),
              function(i) tags$li(sprintf("%s · %s–%s · %s",
                                          format(h$fecha[i], "%d/%m/%Y"),
                                          h$hora_inicio[i], h$hora_fin[i],
                                          h$aplicador[i])))),
            if (nrow(h) > 10) div(class = "small mt-1", sprintf("y %s más.", nrow(h) - 10))),
            "warning"),

          tabla_citaciones(cit, rv$fuera),

          div(class = "d-flex flex-wrap justify-content-between align-items-center gap-2 mt-3",
              span(class = "small text-muted",
                   if (isTRUE(a$citaciones > 0))
                     sprintf("Al cargar se borran las %s citaciones que hay hoy en la base.",
                             fmt_num(a$citaciones))
                   else "La base no tiene agenda: esta será la primera carga."),
              actionButton(ns("guardar"), "Cargar a la base", icon = icon("upload"),
                           class = "btn-primary"))
        )
      )
    })

    observeEvent(input$guardar, {
      rv <- revision()
      req(isTRUE(rv$ok), cit_puede(r, "cargar_agenda"))
      a <- actual()
      showModal(modalDialog(
        title = "Cargar la agenda a la base",
        easyClose = FALSE,
        p(sprintf("Se van a guardar %s citaciones de %s personas.",
                  fmt_num(nrow(rv$cit)), fmt_num(length(unique(rv$cit$id_anonimizado))))),
        if (isTRUE(a$citaciones > 0))
          p(tags$b(sprintf("Reemplaza las %s citaciones cargadas hoy, que se borran.",
                           fmt_num(a$citaciones)))),
        if (nrow(rv$huerfanos))
          p(tags$b(if (nrow(rv$huerfanos) == 1) "1 grupo pierde su psicólogo."
                   else sprintf("%s grupos pierden su psicólogo.", nrow(rv$huerfanos)))),
        footer = tagList(
          modalButton("Cancelar"),
          actionButton(ns("confirmar"), "Cargar", class = "btn-primary"))
      ))
    })

    observeEvent(input$confirmar, {
      rv <- revision()
      req(isTRUE(rv$ok), cit_puede(r, "cargar_agenda"))
      removeModal()

      error <- tryCatch({ seg_cit_guardar(rv$cit); NULL },
                        error = function(e) conditionMessage(e))
      if (!is.null(error)) {
        showNotification(paste("No se pudo guardar la agenda; la anterior sigue igual.", error),
                         type = "error", duration = NULL)
        return()
      }

      cit_bitacora(r, "agenda_cargada",
                   sprintf("%s citaciones desde %s", nrow(rv$cit), rv$nombre))
      CIT_CARGAS(CIT_CARGAS() + 1)
      revision(NULL)
      aviso(alerta(sprintf("Agenda cargada desde %s: %s citaciones de %s personas.",
                           rv$nombre, fmt_num(nrow(rv$cit)),
                           fmt_num(length(unique(rv$cit$id_anonimizado)))),
                   "success"))
    })
  })
}


# --- piezas de la vista -------------------------------------------------------

# Mismo cajon que la fila de indicadores del seguimiento. Una fecha dd/mm/aaaa no
# cabe en el cuerpo de un numero sin desbordar la caja, asi que va mas pequena.
cit_caja <- function(valor, etiqueta, fecha = FALSE) {
  div(class = "kpi-caja",
      div(class = "kpi-valor", style = if (fecha) "font-size: 1.15rem;", valor),
      div(class = "kpi-etiqueta", etiqueta))
}

# "16/09/2026 de 08:00 a 09:00", desde lo que devuelve seg_grupo_de_clave().
grupo_txt <- function(g) {
  sprintf("%s de %s a %s", format(as.Date(g$fecha), "%d/%m/%Y"), g$hora_inicio, g$hora_fin)
}

n_personas <- function(n) paste(fmt_num(n), if (n == 1) "persona" else "personas")

obs_tenue <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x) || !nzchar(x)) span(class = "col-tenue", "—")
  else x
}

# Solo http(s) llega a un href; seg_cit_normalizar ya rechaza lo demas, esto es
# por si la base se cargo por otro camino.
cit_enlace <- function(link) {
  if (is.na(link) || !nzchar(link)) span(class = "col-tenue", "—")
  else if (!grepl("^https?://", link, ignore.case = TRUE)) link
  else tags$a(href = link, target = "_blank", rel = "noopener", link)
}

# --- estado de las anotaciones de un grupo ---

obs_chip <- function(f) {
  n <- f$anotaciones %||% 0
  if (n > 0) {
    span(class = "chip bien", sprintf("%s %s", n, if (n == 1) "anotación" else "anotaciones"))
  } else if (!is.na(f$usuario) && isTRUE(f$termino)) {
    span(class = "chip medio", "Sin anotar")
  }
}

# Sesiones que `yo` puede anotar y todavía no tienen ninguna: el filtro "Sin
# anotar". Quien revisa, todas las empezadas; el psicólogo, las suyas.
obs_por_anotar <- function(g, yo, rol) {
  sin <- g$empezo & (g$anotaciones %in% 0)
  if (auth_puede(rol, "revisar_sesiones")) return(sin)
  if (auth_puede(rol, "registrar_sesion")) return(sin & g$usuario %in% yo)
  rep(FALSE, nrow(g))
}

# El botón que lleva a las anotaciones. Antes de la hora de inicio no hay nada
# que anotar, pero al psicólogo se le dice desde cuándo podrá: sin esa pista, el
# botón simplemente no existía y no se sabía por qué. Es solo la interfaz:
# seg_obs_permiso() decide al abrir y al guardar.
obs_boton <- function(f, clave, yo, rol) {
  propio <- auth_puede(rol, "registrar_sesion") && identical(f$usuario, yo)
  hay    <- (f$anotaciones %||% 0) > 0

  if (!isTRUE(f$empezo)) {
    if (propio) return(span(class = "obs-pista", sprintf("Anotaciones desde las %s", f$hora_inicio)))
    return(NULL)
  }

  edita <- auth_puede(rol, "revisar_sesiones") || propio
  if (!edita && !hay) return(NULL)

  tags$button(
    type = "button",
    class = paste("btn btn-sm", if (edita && !hay) "btn-primary" else "btn-outline-secondary"),
    `data-grupo` = clave, `data-accion` = "anotar",
    if (!edita) "Ver anotaciones" else if (hay) "Ver o editar" else "Anotar")
}

# --- el bloque de anotaciones ---

# `perm` es seg_obs_permiso(): con editar=FALSE va en solo lectura, y con
# ver_personas=FALSE la parte de cada persona ni se dibuja, así que ni los
# nombres ni sus anotaciones salen del servidor.
seccion_anotaciones <- function(ns, g, info, perm, fila) {
  ed   <- isTRUE(perm$editar)
  s    <- info$sesion
  hay  <- nrow(s) == 1
  pers <- info$personas
  sn   <- function(x) if (is.null(x) || is.na(x)) "" else x

  filas <- lapply(seq_len(nrow(pers)), function(i) {
    f <- pers[i, ]
    tags$tr(
      tags$td(class = "col-persona",
              if (is.na(f$nombre)) span(class = "col-id", f$id_anonimizado)
              else tagList(f$nombre, span(class = "col-medio col-id", f$id_anonimizado))),
      tags$td(class = "col-obs",
              if (ed) textInput(ns(paste0("anot_txt_", i)), NULL, value = sn(f$observacion),
                                width = "100%", placeholder = "Sin anotación")
              else obs_tenue(f$observacion)))
  })

  card(
    class = "shadow-sm",
    card_header(
      tags$b("Grupo del ", grupo_txt(g)),
      span(class = "small text-muted ms-2",
           if (nrow(fila) && !is.na(fila$usuario[1])) paste("Psicólogo:", fila$aplicador[1])
           else "Sin psicólogo asignado",
           " · ", n_personas(nrow(pers)), " citadas",
           if (nzchar(g$link)) tagList(" · ", cit_enlace(g$link)))),
    card_body(
      h6("Anotación del grupo", class = "mb-1"),
      if (ed) textAreaInput(ns("anot_general"), NULL, value = if (hay) sn(s$observacion[1]) else "",
                            width = "100%", rows = 3, resize = "vertical",
                            placeholder = "Cómo estuvo la sesión, novedades, lo que haya que dejar escrito.")
      else div(class = "obs-lectura", obs_tenue(if (hay) s$observacion[1] else NA)),

      if (hay) div(class = "small text-muted",
                   sprintf("Escrita por %s el %s", s$registrado_por[1],
                           fmt_momento_v(s$registrado_en[1])),
                   if (!is.na(s$actualizado_por[1]))
                     sprintf(" · última edición de %s el %s", s$actualizado_por[1],
                             fmt_momento_v(s$actualizado_en[1]))),

      if (isTRUE(perm$ver_personas)) tagList(
        h6("Anotaciones por persona", class = "mt-3 mb-1"),
        p(class = "small text-muted mb-2",
          "Escriba solo donde haga falta: lo que quede en blanco no se guarda.",
          if (nrow(pers) && all(is.na(pers$nombre)))
            tagList(" Los nombres salen del Excel de la agenda; si no aparecen, ",
                    "vuelva a cargarla con la columna ", tags$b("persona"), ".")),
        if (nrow(pers) == 0) alerta("Este grupo no tiene personas citadas en la agenda.", "secondary")
        else div(class = "tabla-dep-caja tabla-obs",
                 tags$table(class = "tabla-dep tabla-per",
                            tags$thead(tags$tr(tags$th("Persona"), tags$th("Anotación"))),
                            tags$tbody(filas))))
      else p(class = "small text-muted mt-3 mb-0",
             "Las anotaciones por persona solo las ven el psicólogo del grupo y el administrador."),

      if (ed) div(class = "d-flex flex-wrap align-items-center gap-2 mt-3",
                  actionButton(ns("anot_guardar"), "Guardar anotaciones", class = "btn-primary"),
                  span(class = "small text-muted",
                       "Se pueden corregir después, por vieja que sea la sesión."))
      else p(class = "small text-muted mt-3 mb-0", "Solo lectura."),

      uiOutput(ns("anot_aviso"))
    )
  )
}

# --- calendario ---

# "Semana del 14 al 20 de septiembre de 2026", también cuando cruza de mes o de
# año. Los nombres van a mano: format(, "%B") depende del idioma del equipo.
cal_titulo_semana <- function(lunes) {
  meses <- c("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
             "agosto", "septiembre", "octubre", "noviembre", "diciembre")
  dom <- lunes + 6
  d1 <- as.integer(format(lunes, "%d")); d2 <- as.integer(format(dom, "%d"))
  m1 <- meses[as.integer(format(lunes, "%m"))]; m2 <- meses[as.integer(format(dom, "%m"))]
  a1 <- format(lunes, "%Y"); a2 <- format(dom, "%Y")
  if (a1 != a2)      sprintf("Semana del %d de %s de %s al %d de %s de %s", d1, m1, a1, d2, m2, a2)
  else if (m1 != m2) sprintf("Semana del %d de %s al %d de %s de %s", d1, m1, d2, m2, a2)
  else               sprintf("Semana del %d al %d de %s de %s", d1, d2, m2, a2)
}

# Un grupo dentro del día: la franja, a quién le toca (si se miran todos), el
# link y cuántos citados. El link se muestra sin "https://" para que quepa, y
# completo al pasar el cursor.
cal_grupo <- function(f, yo, con_nombre, rol = NA_character_) {
  enlace <- if (nzchar(f$link) && grepl("^https?://", f$link, ignore.case = TRUE))
    tags$a(href = f$link, target = "_blank", rel = "noopener", title = f$link,
           sub("^https?://", "", f$link, ignore.case = TRUE))
  else span(class = "col-tenue", "Sin link")

  clave <- seg_grupo_clave(f$fecha, f$hora_inicio, f$hora_fin, f$link)
  chip  <- obs_chip(f)
  boton <- obs_boton(f, clave, yo, rol)

  div(class = paste("cal-grupo", if (f$empezo) "empezo"),
      div(class = "cal-hora", sprintf("%s–%s", f$hora_inicio, f$hora_fin)),
      if (con_nombre) div(class = "cal-psicologo",
                          if (identical(f$usuario, yo)) "Usted" else f$aplicador),
      div(class = "cal-link", enlace),
      div(class = "cal-personas", n_personas(f$personas)),
      if (!is.null(chip) || !is.null(boton)) div(class = "cal-sesion", chip, boton))
}

# La semana de `lunes` con los grupos de `g` (ya filtrados). De lunes a viernes
# siempre; sábado y domingo solo si tienen grupos. Si la semana está vacía dice
# cuándo es el próximo y ofrece ir a esa semana (input cal_proximo).
calendario_semana <- function(g, lunes, hoy, yo, con_nombre, ns, rol = NA_character_) {
  nombres <- c("Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo")
  dias <- lunes + 0:6
  sem  <- g[g$fecha >= lunes & g$fecha <= lunes + 6, , drop = FALSE]
  sem  <- sem[order(sem$fecha, sem$hora_inicio, sem$hora_fin), , drop = FALSE]
  ver  <- c(dias[1:5], dias[6:7][dias[6:7] %in% sem$fecha])

  resumen <- if (nrow(sem))
    sprintf("%s %s · %s citadas", nrow(sem), if (nrow(sem) == 1) "grupo" else "grupos",
            n_personas(sum(sem$personas)))

  vacio <- if (nrow(sem) == 0) {
    sig <- g$fecha[g$fecha > lunes + 6]
    alerta(tagList(
      "No hay grupos asignados en esta semana.",
      if (length(sig)) tagList(
        " El próximo es el ", format(min(sig), "%d/%m/%Y"), ". ",
        actionLink(ns("cal_proximo"), "Ir a esa semana"))),
      "secondary")
  }

  tagList(
    div(class = "cal-titulo", cal_titulo_semana(lunes),
        if (!is.null(resumen)) span(class = "cal-resumen", resumen)),
    vacio,
    div(class = "cal-semana",
        lapply(ver, function(d) {
          del_dia <- sem[sem$fecha == d, , drop = FALSE]
          div(class = paste("cal-dia", if (d == hoy) "hoy"),
              div(class = "cal-dia-titulo",
                  span(class = "cal-dia-nombre", nombres[as.integer(d - lunes) + 1L]),
                  span(format(d, "%d/%m"))),
              if (nrow(del_dia) == 0) div(class = "cal-vacio", "Sin grupos")
              else lapply(seq_len(nrow(del_dia)),
                          function(i) cal_grupo(del_dia[i, ], yo, con_nombre, rol)))
        }))
  )
}

# --- tablas ---

# `toma`: puede tomar y soltar sus grupos. `asigna`: puede ponerle o quitarle el
# psicólogo a cualquier grupo.
tabla_grupos <- function(g, yo, toma = FALSE, asigna = FALSE, rol = NA_character_) {
  boton <- function(clave, accion, texto, clase)
    tags$button(type = "button", class = paste("btn btn-sm", clase),
                `data-grupo` = clave, `data-accion` = accion, texto)

  filas <- lapply(seq_len(nrow(g)), function(i) {
    f     <- g[i, ]
    clave <- seg_grupo_clave(f$fecha, f$hora_inicio, f$hora_fin, f$link)
    libre <- is.na(f$usuario)
    mio   <- identical(f$usuario, yo)

    tags$tr(
      class = if (mio) "mio",
      tags$td(class = "col-fecha", format(f$fecha, "%d/%m/%Y"),
              span(class = "col-medio", sprintf("%s–%s", f$hora_inicio, f$hora_fin))),
      tags$td(class = "col-num der", fmt_num(f$personas)),
      tags$td(cit_enlace(f$link)),
      tags$td(if (mio) tags$b("Usted")
              else if (libre) span(class = "col-tenue", if (f$empezo || !toma) "Sin asignar" else "Libre")
              else f$aplicador),
      tags$td(obs_chip(f)),
      tags$td(class = "col-accion",
              if (toma && libre && !f$empezo) boton(clave, "tomar", "Tomar", "btn-primary"),
              if (mio && !f$empezo)           boton(clave, "soltar", "Soltar", "btn-outline-secondary"),
              obs_boton(f, clave, yo, rol),
              if (f$empezo && !asigna)        span(class = "col-tenue small", "Ya empezó"),
              if (asigna)                     boton(clave, "asignar", "Asignar…", "btn-outline-secondary"))
    )
  })

  div(class = "tabla-dep-caja",
      tags$table(
        class = "tabla-dep tabla-per tabla-grupos",
        tags$thead(tags$tr(tags$th("Fecha y franja"), tags$th(class = "der", "Personas"),
                           tags$th("Link"), tags$th("Psicólogo"), tags$th("Anotaciones"),
                           tags$th(""))),
        tags$tbody(filas)))
}

tabla_citaciones <- function(cit, fuera = character(0)) {
  n   <- nrow(cit)
  sub <- utils::head(cit, CIT_VISTA_FILAS)
  con_nombre <- any(!is.na(cit$nombre))

  filas <- lapply(seq_len(nrow(sub)), function(i) {
    tags$tr(
      tags$td(class = "col-id", sub$id_anonimizado[i]),
      if (con_nombre) tags$td(obs_tenue(sub$nombre[i])),
      tags$td(class = "col-fecha", format(sub$fecha[i], "%d/%m/%Y")),
      tags$td(class = "col-fecha", paste(sub$hora_inicio[i], "–", sub$hora_fin[i])),
      tags$td(cit_enlace(sub$link[i])),
      tags$td(if (sub$id_anonimizado[i] %in% fuera) span(class = "chip bajo", "No") else "Sí"))
  })

  tagList(
    div(class = "tabla-dep-caja",
        tags$table(
          class = "tabla-dep tabla-per",
          tags$thead(tags$tr(tags$th("Id"), if (con_nombre) tags$th("Nombre"),
                             tags$th("Fecha"), tags$th("Franja"),
                             tags$th("Link"), tags$th("En el marco"))),
          tags$tbody(filas))),
    if (n > CIT_VISTA_FILAS)
      div(class = "small text-muted mt-1",
          sprintf("Se muestran las primeras %s de %s citaciones.",
                  fmt_num(CIT_VISTA_FILAS), fmt_num(n)))
  )
}

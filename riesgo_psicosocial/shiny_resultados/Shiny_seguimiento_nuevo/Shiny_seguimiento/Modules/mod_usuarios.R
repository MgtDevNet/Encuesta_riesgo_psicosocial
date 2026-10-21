# Modules/mod_usuarios.R
# Módulo 4: pestaña Administración, solo para administradores.
#
#   mod_usuarios_ui(id)
#   mod_usuarios_server(id, r)
#
# Lo mismo que scripts/gestionar_usuarios.R, desde la app: crear cuentas,
# reiniciar claves, cambiar el rol, eliminar y ver la bitácora. Con muchos
# psicólogos no puede depender de la terminal del equipo que corre la app.
#
# Entre los usuarios y la bitácora van la carga de la agenda de citaciones y el
# informe de avance en Word. Son módulos aparte (mod_agenda_*, en
# mod_citaciones.R; mod_informe_*, en mod_seguimiento.R), cada uno con su propio
# permiso --`cargar_agenda` e `informe_avance`--: aquí solo se montan.
#
# Las claves temporales las genera la app (auth_clave_temporal()) y se muestran
# una sola vez, para que el administrador se las entregue a la persona. Al
# entrar, esa persona tiene que cambiarla antes de ver nada.
#
# app.R solo arranca este módulo con el permiso `usuarios`, y además cada salida
# y cada acción vuelven a leer el rol de la base: pudo cambiar con la sesión
# abierta, y una salida se puede pedir a mano desde el navegador aunque la
# pestaña no esté dibujada.

mod_usuarios_ui <- function(id) {
  ns <- NS(id)

  fluidPage(
    class = "py-3",

    # Mismo patrón delegado de los otros módulos: renderUI() rehace la tabla.
    tags$script(HTML(sprintf(
      "$(document).on('click', '#%s [data-usuario]', function(){
         Shiny.setInputValue('%s', {accion:  String($(this).attr('data-accion')),
                                    usuario: String($(this).attr('data-usuario'))},
                             {priority: 'event'});
       });",
      ns("tabla"), ns("accion")
    ))),

    div(class = "d-flex flex-wrap justify-content-between align-items-end gap-2 mb-3",
        div(h4("Usuarios", class = "mb-1"),
            p(class = "text-muted mb-0",
              "Cree las cuentas del equipo, asígneles su rol y administre su acceso.")),
        actionButton(ns("nuevo"), "Crear usuario", icon = icon("user-plus"),
                     class = "btn-primary")),

    uiOutput(ns("tabla")),

    hr(class = "my-4"),
    mod_agenda_ui(ns("agenda")),
    hr(class = "my-4"),
    mod_informe_ui(ns("informe")),
    hr(class = "my-4"),
    mod_borradas_ui(ns("borradas")),
    hr(class = "my-4"),

    h5("Bitácora", class = "mb-1"),
    p(class = "small text-muted mb-2",
      "Los últimos 200 eventos: ingresos, fallos, bloqueos, cierres de sesión y ",
      "cambios de cuentas, roles, grupos y agenda."),
    uiOutput(ns("bitacora"))
  )
}


mod_usuarios_server <- function(id, r = reactiveValues()) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Carga de la agenda de citaciones: revisa su propio permiso en cada acción.
    mod_agenda_server("agenda", r = r)

    # Informe de avance en Word, que antes estaba en la pestaña de Avance.
    # También revisa su propio permiso (`informe_avance`) en cada descarga.
    mod_informe_server("informe", r = r)

    # Personas borradas desde Avance, para restaurarlas. Revisa su propio
    # permiso (`borrar_personas`) en cada acción.
    mod_borradas_server("borradas", r = r)

    recarga     <- reactiveVal(0)
    pendiente   <- reactiveVal(NULL) # acción que espera confirmación
    aviso_nuevo <- reactiveVal(NULL) # error de la ventana de crear

    yo     <- function() r$usuario$usuario
    origen <- function() r$usuario$origen %||% NA_character_
    por    <- function() paste("desde la app por", yo())

    puede <- function() {
      isTRUE(tryCatch(auth_puede_usuario(yo(), "usuarios"), error = function(e) FALSE))
    }

    usuarios <- reactive({
      recarga()
      invalidateLater(60 * 1000)
      req(puede())
      auth_listar_usuarios()
    })

    output$tabla <- renderUI(tabla_usuarios(usuarios(), yo()))

    output$bitacora <- renderUI({
      recarga()
      invalidateLater(60 * 1000)
      req(puede())
      tabla_bitacora(auth_leer_bitacora(200))
    })

    # La clave temporal se muestra una vez y no se guarda en ningún lado.
    mostrar_clave <- function(usuario, clave, titulo) {
      showModal(modalDialog(
        title = titulo,
        easyClose = FALSE,
        p("Entregue esta contraseña temporal a ", tags$b(usuario),
          ". Al entrar tendrá que cambiarla por una propia."),
        div(class = "clave-temporal", clave),
        p(class = "small text-muted mb-0",
          "No se vuelve a mostrar. Si se pierde, reinicie la contraseña otra vez."),
        footer = modalButton("Listo")
      ))
    }

    # --- crear ---------------------------------------------------------------

    output$aviso_nuevo <- renderUI(alerta(aviso_nuevo()))

    observeEvent(input$nuevo, {
      req(puede())
      aviso_nuevo(NULL)
      showModal(modalDialog(
        title = "Crear usuario",
        easyClose = TRUE,
        textInput(ns("nuevo_usuario"), "Usuario", width = "100%"),
        div(class = "text-muted small mb-3",
            "Entre 3 y 32 caracteres: minúsculas, números, punto, guion o guion bajo."),
        textInput(ns("nuevo_nombre"), "Nombre completo", width = "100%"),
        selectInput(ns("nuevo_rol"), "Rol", width = "100%", selectize = FALSE,
                    choices = usr_opciones_rol(), selected = "psicologo"),
        usr_ayuda_roles(),
        uiOutput(ns("aviso_nuevo")),
        footer = tagList(
          modalButton("Cancelar"),
          actionButton(ns("crear"), "Crear", class = "btn-primary"))
      ))
    })

    observeEvent(input$crear, {
      req(puede())
      usuario <- auth_norm(input$nuevo_usuario %||% "")
      clave   <- auth_clave_temporal()
      error <- tryCatch({
        auth_crear_usuario(usuario, clave, input$nuevo_nombre %||% "",
                           rol = input$nuevo_rol %||% "", debe_cambiar = TRUE,
                           detalle = por(), origen = origen())
        NULL
      }, error = function(e) conditionMessage(e))
      if (!is.null(error)) return(aviso_nuevo(error))

      recarga(recarga() + 1)
      mostrar_clave(usuario, clave, "Usuario creado")
    })

    # --- acciones por fila ---------------------------------------------------

    observeEvent(input$accion, {
      req(puede())
      a <- input$accion
      u <- auth_norm(a$usuario %||% "")
      req(a$accion %in% c("reiniciar", "rol", "eliminar"))

      if (identical(u, yo())) {
        showNotification(paste("Sobre su propia cuenta use «Cambiar contraseña», o pídale",
                               "el cambio a otro administrador."), type = "warning")
        return()
      }
      todos <- usuarios()
      fila  <- todos[todos$usuario == u, , drop = FALSE]
      req(nrow(fila) == 1)

      cuerpo <- switch(a$accion,
        reiniciar = p(paste("Se genera una contraseña temporal nueva. La actual deja de servir",
                            "y sus sesiones abiertas se cierran en menos de un minuto.")),
        rol = tagList(
          selectInput(ns("rol_nuevo"), "Rol", width = "100%", selectize = FALSE,
                      choices = usr_opciones_rol(), selected = fila$rol[1]),
          usr_ayuda_roles(),
          p(class = "small text-muted mt-2 mb-0",
            "Su sesión abierta se cierra en menos de un minuto, para que entre con el rol ",
            "nuevo. Si deja de ser psicólogo, sus grupos por empezar quedan libres.")),
        eliminar = p(paste("Pierde el acceso y sus sesiones abiertas se cierran en menos de un",
                           "minuto. Sus grupos por empezar quedan libres; los que ya pasaron",
                           "conservan su nombre. Su rastro en la bitácora se conserva y el",
                           "nombre de usuario no se podrá volver a usar.")))

      pendiente(list(accion = a$accion, usuario = u))
      showModal(modalDialog(
        title = switch(a$accion, reiniciar = "Reiniciar contraseña",
                       rol = "Cambiar rol", eliminar = "Eliminar usuario"),
        easyClose = TRUE,
        p(tags$b(fila$nombre[1]), sprintf(" (%s) · %s", u, auth_rol_txt(fila$rol[1]))),
        cuerpo,
        footer = tagList(
          modalButton("Cancelar"),
          actionButton(ns("confirmar"),
                       switch(a$accion, reiniciar = "Reiniciar", rol = "Cambiar rol",
                              eliminar = "Eliminar"),
                       class = if (a$accion == "eliminar") "btn-danger" else "btn-primary"))
      ))
    })

    observeEvent(input$confirmar, {
      pend <- pendiente()
      req(pend, puede(), !identical(pend$usuario, yo()))
      removeModal()
      pendiente(NULL)

      clave   <- NULL
      cambio  <- TRUE
      error <- tryCatch({
        switch(pend$accion,
          reiniciar = {
            clave <- auth_clave_temporal()
            auth_reset_clave(pend$usuario, clave, detalle = por(), origen = origen())
          },
          rol = {
            cambio <- auth_cambiar_rol(pend$usuario, input$rol_nuevo %||% "",
                                       detalle = por(), origen = origen())
          },
          eliminar = auth_eliminar_usuario(pend$usuario, detalle = por(), origen = origen()))
        NULL
      }, error = function(e) conditionMessage(e))

      recarga(recarga() + 1)
      if (!is.null(error)) {
        showNotification(error, type = "error", duration = NULL)
        return()
      }

      # Cambiar el rol o eliminar pudo liberar grupos: la pestaña de citaciones
      # se refresca en todas las sesiones.
      if (pend$accion %in% c("rol", "eliminar")) CIT_GRUPOS(CIT_GRUPOS() + 1)

      switch(pend$accion,
        reiniciar = mostrar_clave(pend$usuario, clave, "Contraseña reiniciada"),
        rol       = showNotification(
          if (isTRUE(cambio)) sprintf("%s ahora es %s.", pend$usuario,
                                      tolower(auth_rol_txt(input$rol_nuevo)))
          else "El rol quedó igual.", type = "message"),
        eliminar  = showNotification(sprintf("Usuario %s eliminado.", pend$usuario),
                                     type = "message"))
    })
  })
}


# --- piezas de la vista -------------------------------------------------------

usr_opciones_rol <- function() stats::setNames(names(AUTH_ROLES), unname(AUTH_ROLES))

usr_ayuda_roles <- function() {
  tags$ul(class = "small text-muted mb-0 ps-3",
          lapply(names(AUTH_ROLES), function(k)
            tags$li(tags$b(AUTH_ROLES[[k]]), ": ", auth_rol_descripcion(k))))
}

usr_tenue <- function(x, vacio = "—") {
  if (is.null(x) || length(x) == 0 || is.na(x) || !nzchar(x)) span(class = "col-tenue", vacio)
  else x
}

tabla_usuarios <- function(u, yo) {
  if (nrow(u) == 0) return(alerta("No hay usuarios.", "secondary"))

  boton <- function(usuario, accion, texto, clase = "btn-outline-secondary")
    tags$button(type = "button", class = paste("btn btn-sm", clase),
                `data-usuario` = usuario, `data-accion` = accion, texto)

  filas <- lapply(seq_len(nrow(u)), function(i) {
    f      <- u[i, ]
    propio <- identical(f$usuario, yo)
    tags$tr(
      tags$td(class = "col-id", f$usuario),
      tags$td(f$nombre, if (propio) span(class = "col-tenue", " (usted)")),
      tags$td(auth_rol_txt(f$rol)),
      tags$td(class = "col-fecha", fmt_momento_v(f$ultimo_ingreso, vacio = "Nunca")),
      tags$td(
        if (!is.na(f$bloqueado_hasta))
          span(class = "chip bajo",
               sprintf("Bloqueado hasta las %s", format(f$bloqueado_hasta, "%H:%M", tz = SEG_TZ))),
        if (isTRUE(f$debe_cambiar)) span(class = "chip nulo", "Clave temporal")),
      tags$td(class = "col-accion",
              if (!propio) tagList(
                boton(f$usuario, "reiniciar", "Reiniciar clave"),
                boton(f$usuario, "rol", "Cambiar rol"),
                boton(f$usuario, "eliminar", "Eliminar", "btn-outline-danger")))
    )
  })

  div(class = "tabla-dep-caja",
      tags$table(
        class = "tabla-dep tabla-per tabla-usuarios",
        tags$thead(tags$tr(tags$th("Usuario"), tags$th("Nombre"), tags$th("Rol"),
                           tags$th("Último ingreso"), tags$th("Estado"), tags$th(""))),
        tags$tbody(filas)))
}

tabla_bitacora <- function(b) {
  if (nrow(b) == 0) return(alerta("La bitácora está vacía.", "secondary"))

  filas <- lapply(seq_len(nrow(b)), function(i) {
    tags$tr(
      tags$td(class = "col-fecha", fmt_momento_v(b$momento[i])),
      tags$td(class = "col-id", usr_tenue(b$usuario[i])),
      tags$td(gsub("_", " ", b$evento[i], fixed = TRUE)),
      tags$td(usr_tenue(b$detalle[i])),
      tags$td(class = "col-id", usr_tenue(b$origen[i])))
  })

  div(class = "tabla-dep-caja",
      tags$table(
        class = "tabla-dep tabla-per",
        tags$thead(tags$tr(tags$th("Momento"), tags$th("Usuario"), tags$th("Evento"),
                           tags$th("Detalle"), tags$th("Origen"))),
        tags$tbody(filas)))
}

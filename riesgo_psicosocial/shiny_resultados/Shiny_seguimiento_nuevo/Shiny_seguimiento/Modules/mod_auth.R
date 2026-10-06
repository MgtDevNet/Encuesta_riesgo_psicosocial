# Modules/mod_auth.R
# Módulo 1: seguridad / ingreso a la app.
#
#   mod_auth_scripts(id)   JS de la sesión; va una sola vez en la ui fija de app.R
#   mod_auth_ui(id)        puerta de entrada (mientras no hay sesión utilizable)
#   mod_auth_barra_ui(id)  nombre del usuario + salir (barra superior)
#   mod_auth_server(id, r) publica la ficha de sesión en r$usuario
#
# La ficha es list(usuario, nombre, debe_cambiar, rol, sello, origen,
# ingreso), o NULL si nadie ha entrado. Los demás módulos la leen de r$usuario,
# igual que el resto del estado compartido. Los estilos viven en www/custom.css.
#
# La puerta tiene tres caras y el servidor decide cuál se dibuja:
#   - `auth.usuarios` vacía: el formulario de PRIMER ARRANQUE, que pide el código
#     de instalación de .Renviron;
#   - alguien entró con clave temporal: el CAMBIO DE CLAVE y nada más. app.R no
#     dibuja la app ni arranca los módulos hasta que debe_cambiar sea FALSE;
#   - si no, la pantalla de ingreso de siempre.
#
# La sesión se cierra sola tras AUTH_INACTIVIDAD_MIN minutos sin actividad, y
# también si la clave o el rol cambiaron, o si el usuario se borró. Cerrar es
# siempre recargar la página: los módulos guardan estado del usuario anterior.

mod_auth_scripts <- function(id) {
  ns <- NS(id)
  tags$script(HTML(sprintf(
    "(function(){
       // Cierre de sesión: el aviso sobrevive a la recarga en sessionStorage y
       // lo muestra la pantalla de ingreso.
       Shiny.addCustomMessageHandler('auth_cerrar', function(aviso){
         try { if (aviso) sessionStorage.setItem('auth-aviso', aviso); } catch (e) {}
         window.location.reload();
       });
       // Actividad: como mucho un mensaje por minuto, que es la resolución con
       // que el servidor mide la inactividad.
       var ultimo = 0;
       function actividad(){
         var ahora = Date.now();
         if (ahora - ultimo < 60000 || !window.Shiny || !Shiny.setInputValue) return;
         ultimo = ahora;
         Shiny.setInputValue('%s', ahora, {priority: 'event'});
       }
       $(document).on('mousedown mousemove keydown touchstart', actividad);
       $(window).on('scroll wheel', actividad);
     })();",
    ns("actividad"))))
}

mod_auth_ui <- function(id) {
  uiOutput(NS(id)("puerta"))
}


# Enter en cualquiera de los campos equivale a pulsar el botón. El manejador va
# delegado en `document` y con nombre propio (`.auth`), para poder quitarlo
# antes de volver a ponerlo: la puerta se redibuja --al crear el primer usuario,
# por ejemplo-- y sin el .off() quedaría enganchado dos veces y el Enter
# dispararía dos ingresos.
auth_js_enter <- function(campos, boton) {
  tags$script(HTML(sprintf(
    "$(document).off('keydown.auth').on('keydown.auth', '%s', function(e){
       if (e.key === 'Enter') { e.preventDefault(); $('#%s').click(); }
     });",
    paste0("#", campos, collapse = ", "), boton)))
}

auth_txt_clave <- function() {
  sprintf("Al menos %s caracteres, con letras y números.", AUTH_MIN_CLAVE)
}


# --- pantalla de ingreso ------------------------------------------------------

auth_ui_ingreso <- function(ns) {
  div(
    class = "auth-fondo",
    auth_js_enter(c(ns("usuario"), ns("clave")), ns("ingresar")),

    card(
      class = "auth-tarjeta shadow-sm",
      card_body(
        class = "p-4",
        h4("Seguimiento riesgo psicosocial", class = "auth-titulo mb-1"),
        p("Ingrese con sus credenciales para continuar.",
          class = "text-muted auth-sub mb-4"),

        # Por qué se cerró la sesión anterior, si se cerró sola.
        div(id = ns("aviso_cierre")),
        tags$script(HTML(sprintf(
          "try {
             var a = sessionStorage.getItem('auth-aviso');
             if (a) {
               sessionStorage.removeItem('auth-aviso');
               $('#%s').attr('class', 'alert alert-secondary auth-alerta mb-3').text(a);
             }
           } catch (e) {}",
          ns("aviso_cierre")))),

        textInput(ns("usuario"), "Usuario", width = "100%"),
        passwordInput(ns("clave"), "Contraseña", width = "100%"),

        actionButton(ns("ingresar"), "Ingresar", class = "btn-primary w-100 mt-2"),

        uiOutput(ns("mensaje"))
      )
    )
  )
}


# --- cambio de clave obligatorio ---------------------------------------------
# Quien entra con clave temporal no ve nada más. Antes la app se dibujaba detrás
# de una ventana: los datos quedaban a la vista y bastaba quitar la ventana con
# las herramientas del navegador para trabajar con la clave temporal.
#
# No pide la clave actual: la escribió hace un momento para llegar aquí.

auth_ui_cambio_obligatorio <- function(ns, nombre) {
  div(
    class = "auth-fondo",
    auth_js_enter(c(ns("clave_nueva"), ns("clave_confirma")), ns("guardar_clave")),

    card(
      class = "auth-tarjeta shadow-sm",
      card_body(
        class = "p-4",
        h4("Cambie su contraseña", class = "auth-titulo mb-1"),
        p(class = "text-muted auth-sub mb-4",
          sprintf("Hola, %s. Entró con una contraseña temporal; defina una propia para continuar.",
                  nombre)),

        passwordInput(ns("clave_nueva"), "Nueva contraseña", width = "100%"),
        passwordInput(ns("clave_confirma"), "Repita la contraseña", width = "100%"),
        div(class = "text-muted small", auth_txt_clave()),

        actionButton(ns("guardar_clave"), "Guardar y entrar",
                     class = "btn-primary w-100 mt-3"),
        uiOutput(ns("mensaje_clave")),

        div(class = "text-center mt-3",
            actionLink(ns("salir"), "Salir", class = "small text-decoration-none"))
      )
    )
  )
}


# --- primer arranque ----------------------------------------------------------
# Sustituye a `gestionar_usuarios.R crear`, que necesita una terminal capaz de
# apagar el eco y por eso no sirve en Windows. Aquí la cuenta se crea desde el
# navegador y queda guardada en la base: esta pantalla no vuelve a aparecer.
#
# Pide el código de instalación (APP_CODIGO_INSTALACION en .Renviron): la app se
# publica en internet, y sin él cualquiera que abriera la URL con la base vacía
# se quedaba con la primera cuenta, que es de administrador.
#
# La cuenta se crea con debe_cambiar = FALSE, al revés que las que se dan de
# alta desde la terminal o la pestaña Administración: la contraseña no viene asignada
# por un tercero, la eligió aquí mismo la persona que va a usarla.

auth_ui_primer_usuario <- function(ns, hay_codigo) {
  div(
    class = "auth-fondo",
    auth_js_enter(c(ns("codigo"), ns("nuevo_usuario"), ns("nuevo_nombre"),
                    ns("nueva_clave"), ns("nueva_clave2")), ns("crear_primero")),

    card(
      class = "auth-tarjeta shadow-sm",
      card_body(
        class = "p-4",
        h4("Primer arranque", class = "auth-titulo mb-1"),
        p("Todavía no hay ningún usuario registrado. Cree el primero para entrar.",
          class = "text-muted auth-sub mb-4"),

        if (!hay_codigo) alerta(tagList(
          "Para crear la primera cuenta defina ", tags$code("APP_CODIGO_INSTALACION"),
          sprintf(" en el archivo .Renviron de la app, con al menos %s caracteres, ",
                  AUTH_MIN_CODIGO),
          "y reinicie la app."), "warning"),

        passwordInput(ns("codigo"), "Código de instalación", width = "100%"),
        div(class = "text-muted small mb-3",
            "Es el valor de APP_CODIGO_INSTALACION en el .Renviron del equipo donde corre la app."),

        textInput(ns("nuevo_usuario"), "Usuario", width = "100%"),
        div(class = "text-muted small mb-3",
            "Entre 3 y 32 caracteres: minúsculas, números, punto, guion o guion bajo."),

        textInput(ns("nuevo_nombre"), "Nombre completo", width = "100%"),

        passwordInput(ns("nueva_clave"), "Contraseña", width = "100%"),
        passwordInput(ns("nueva_clave2"), "Repita la contraseña", width = "100%"),
        div(class = "text-muted small", auth_txt_clave()),

        actionButton(ns("crear_primero"), "Crear y entrar",
                     class = "btn-primary w-100 mt-3"),

        uiOutput(ns("mensaje_primero"))
      )
    )
  )
}


mod_auth_barra_ui <- function(id) {
  uiOutput(NS(id)("barra"), inline = TRUE)
}


mod_auth_server <- function(id, r = reactiveValues()) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    mensaje         <- reactiveVal(NULL) # error del último intento de ingreso
    mensaje_clave   <- reactiveVal(NULL) # error del cambio de clave
    mensaje_primero <- reactiveVal(NULL) # error del formulario de primer arranque

    # Cuál de las caras de la puerta se dibuja. Se consulta la base una vez al
    # abrir la sesión y se vuelve a TRUE en cuanto se crea el primer usuario,
    # sin necesidad de recargar.
    hay_usuarios <- reactiveVal(isTRUE(tryCatch(auth_hay_usuarios(),
                                                error = function(e) TRUE)))

    origen <- auth_origen(session$request)

    output$puerta <- renderUI({
      s <- r$usuario
      if (!is.null(s) && isTRUE(s$debe_cambiar)) return(auth_ui_cambio_obligatorio(ns, s$nombre))
      if (hay_usuarios()) auth_ui_ingreso(ns)
      else auth_ui_primer_usuario(ns, hay_codigo = !is.null(auth_codigo_instalacion()))
    })

    # --- cierre de sesión ----------------------------------------------------
    # Bitácora y recarga en el navegador, con un aviso que muestra la pantalla
    # de ingreso. Si el navegador no obedece --alguien manipulando la página--,
    # el servidor cierra la sesión igual a los pocos segundos.
    cerrar_sesion <- function(evento, aviso = "") {
      s <- r$usuario
      if (!is.null(s)) try(auth_bitacora(evento, s$usuario, origen = origen), silent = TRUE)
      r$usuario <- NULL
      session$sendCustomMessage("auth_cerrar", aviso)
      later::later(function() try(session$close(), silent = TRUE), 5)
    }

    ultima_actividad <- reactiveVal(Sys.time())
    observeEvent(input$actividad, ultima_actividad(Sys.time()))

    # Una vez por minuto: inactividad, y que el usuario, su clave y su rol sigan siendo
    # los mismos con que se entró. Un error de la base no cierra la sesión: un
    # corte pasajero no debe echar a todo el mundo.
    observe({
      invalidateLater(60 * 1000)
      s <- r$usuario
      if (is.null(s)) return()

      quieto <- difftime(Sys.time(), isolate(ultima_actividad()), units = "mins")
      if (quieto >= AUTH_INACTIVIDAD_MIN) {
        return(cerrar_sesion(
          "sesion_expirada",
          sprintf("Su sesión se cerró tras %s minutos sin actividad.", AUTH_INACTIVIDAD_MIN)))
      }
      vigente <- tryCatch(auth_sesion_vigente(s$usuario, s$sello, s$rol),
                          error = function(e) TRUE)
      if (!vigente) {
        cerrar_sesion("sesion_revocada",
                      "Su sesión se cerró porque cambió su contraseña, su rol o su acceso.")
      }
    })

    # --- primer arranque -----------------------------------------------------

    observeEvent(input$crear_primero, {
      # Se vuelve a preguntar a la base en vez de fiarse del reactiveVal: entre
      # que se dibujó el formulario y se pulsó el botón pudo crearse la cuenta
      # desde otra sesión o desde la terminal.
      if (isTRUE(tryCatch(auth_hay_usuarios(), error = function(e) FALSE))) {
        hay_usuarios(TRUE)
        mensaje_primero(paste("Ya existe un usuario registrado.",
                              "Ingrese con sus credenciales."))
        return()
      }

      esperado <- auth_codigo_instalacion()
      if (is.null(esperado)) {
        mensaje_primero("La app no tiene código de instalación: vea el aviso de arriba.")
        return()
      }
      if (isTRUE(tryCatch(auth_origen_bloqueado(origen), error = function(e) FALSE))) {
        mensaje_primero(auth_msg_espera())
        return()
      }
      if (!identical(input$codigo %||% "", esperado)) {
        try(auth_bitacora("primer_arranque_fallido", NA_character_, origen = origen),
            silent = TRUE)
        updateTextInput(session, "codigo", value = "")
        mensaje_primero("El código de instalación no es correcto.")
        return()
      }

      if (!identical(input$nueva_clave, input$nueva_clave2)) {
        mensaje_primero("Las dos contraseñas no coinciden.")
        return()
      }

      usuario <- auth_norm(input$nuevo_usuario %||% "")
      nombre  <- trimws(input$nuevo_nombre %||% "")

      if (!is.null(m <- auth_validar_usuario(usuario))) {
        mensaje_primero(m); return()
      }
      if (!nzchar(nombre)) {
        mensaje_primero("Escriba el nombre completo."); return()
      }
      if (!is.null(m <- auth_validar_clave(input$nueva_clave))) {
        mensaje_primero(m); return()
      }

      creado <- tryCatch({
        # La primera cuenta es de administrador: si no, nadie podría crear las
        # demás.
        auth_crear_usuario(usuario, input$nueva_clave, nombre,
                           rol = "administrador", debe_cambiar = FALSE,
                           detalle = "primer arranque desde la app", origen = origen)
        TRUE
      }, error = function(e) {
        mensaje_primero(conditionMessage(e))
        FALSE
      })
      if (!creado) return()

      # Entrar de una vez con la cuenta recién creada: se pasa por
      # auth_verificar() y no por un atajo, para que el ingreso quede en la
      # bitácora y la ficha de sesión se arme en un solo sitio.
      res <- auth_verificar(usuario, input$nueva_clave, origen = origen)

      # Las contraseñas no se quedan escritas en el formulario.
      updateTextInput(session, "codigo",       value = "")
      updateTextInput(session, "nueva_clave",  value = "")
      updateTextInput(session, "nueva_clave2", value = "")

      mensaje_primero(NULL)
      hay_usuarios(TRUE)
      if (isTRUE(res$ok)) {
        ultima_actividad(Sys.time())
        r$usuario <- res$usuario
      }
    })

    output$mensaje_primero <- renderUI(alerta(mensaje_primero()))

    # --- ingreso -------------------------------------------------------------

    observeEvent(input$ingresar, {
      req(!is.null(input$usuario))

      res <- tryCatch(
        auth_verificar(input$usuario, input$clave, origen = origen),
        error = function(e) list(
          ok      = FALSE,
          motivo  = paste("No fue posible validar el ingreso:", conditionMessage(e)),
          usuario = NULL
        )
      )

      # La clave nunca se deja escrita en el campo, ni al acertar ni al fallar.
      updateTextInput(session, "clave", value = "")

      if (isTRUE(res$ok)) {
        mensaje(NULL)
        mensaje_clave(NULL)
        ultima_actividad(Sys.time())
        # Con clave temporal, la puerta pasa sola a la pantalla de cambio.
        r$usuario <- res$usuario
      } else {
        r$usuario <- NULL
        mensaje(res$motivo)
      }
    })

    output$mensaje <- renderUI(alerta(mensaje()))

    # --- cambio de contraseña ------------------------------------------------
    # Un solo manejador para las dos formas: la pantalla obligatoria (clave
    # temporal) y la ventana que se abre desde la barra, que sí pide la actual.

    output$mensaje_clave <- renderUI(alerta(mensaje_clave()))

    observeEvent(input$abrir_cambio_clave, {
      req(r$usuario)
      mensaje_clave(NULL)
      showModal(modalDialog(
        title     = "Cambiar contraseña",
        easyClose = TRUE,
        footer    = tagList(
          modalButton("Cancelar"),
          actionButton(ns("guardar_clave"), "Guardar", class = "btn-primary")
        ),
        passwordInput(ns("clave_actual"), "Contraseña actual", width = "100%"),
        passwordInput(ns("clave_nueva"), "Nueva contraseña", width = "100%"),
        passwordInput(ns("clave_confirma"), "Repita la contraseña", width = "100%"),
        div(class = "text-muted small", auth_txt_clave()),
        uiOutput(ns("mensaje_clave"))
      ))
    })

    observeEvent(input$guardar_clave, {
      s <- r$usuario
      req(s)
      obligatorio <- isTRUE(s$debe_cambiar)

      limpiar <- function() {
        for (campo in c("clave_actual", "clave_nueva", "clave_confirma"))
          updateTextInput(session, campo, value = "")
      }

      if (!obligatorio) {
        conf <- tryCatch(auth_confirmar_clave(s$usuario, input$clave_actual %||% "", origen),
                         error = function(e) list(ok = FALSE, motivo = conditionMessage(e)))
        if (!isTRUE(conf$ok)) {
          limpiar()
          mensaje_clave(conf$motivo)
          return()
        }
      }

      if (!identical(input$clave_nueva, input$clave_confirma)) {
        mensaje_clave("Las dos contraseñas no coinciden.")
        return()
      }
      if (!is.null(m <- auth_validar_clave(input$clave_nueva))) {
        mensaje_clave(m)
        return()
      }

      sello <- tryCatch(auth_cambiar_clave(s$usuario, input$clave_nueva, origen = origen),
                        error = function(e) { mensaje_clave(conditionMessage(e)); NULL })
      limpiar()
      if (is.null(sello)) return()

      mensaje_clave(NULL)
      s$debe_cambiar <- FALSE
      s$sello <- sello
      r$usuario <- s
      if (!obligatorio) removeModal()
      showNotification("Contraseña actualizada.", type = "message")
    })

    # --- barra de sesión y salida --------------------------------------------

    output$barra <- renderUI({
      s <- r$usuario
      if (is.null(s)) return(NULL)

      div(
        class = "d-flex align-items-center gap-2",
        span(class = "small text-muted d-none d-md-inline", s$nombre),
        actionLink(ns("abrir_cambio_clave"), "Cambiar contraseña",
                   class = "small text-decoration-none ms-2"),
        actionButton(ns("salir"), "Salir", class = "btn-sm btn-outline-secondary ms-2")
      )
    })

    # Recarga completa: garantiza que no quede nada del usuario anterior en los
    # inputs si otra persona entra en el mismo navegador.
    observeEvent(input$salir, cerrar_sesion("salida"))

    # Además de publicar en r$usuario, se devuelve el reactive para las pruebas
    # y para módulos que prefieran recibirlo como argumento.
    reactive(r$usuario)
  })
}

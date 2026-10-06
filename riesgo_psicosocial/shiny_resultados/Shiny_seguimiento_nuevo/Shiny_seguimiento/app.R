# app.R
# Las librerías deben cargarse ANTES de los source(), porque los módulos y
# helpers ejecutan código a nivel de script al ser importados
# (ej. AUTH_HASH_SENUELO en utils_auth.R).

library(shiny)
library(bslib)        # BS5 theming
library(DBI)          # interfaz generica de base de datos
library(RPostgres)    # driver de PostgreSQL
library(pool)         # pool de conexiones para Shiny
library(scrypt)       # hash de contrasenas
library(stringi)      # stri_trans_general (normalizacion sin tildes) en helpers.R
library(officer)      # informe en Word de la pestana de avance
library(flextable)    # tablas del informe en Word

# La app se sirve SIEMPRE desde su propia carpeta: los source() de abajo, el
# .Renviron, los diccionarios de la calificación y --sobre todo-- la carpeta
# `www/` son rutas relativas al directorio de trabajo. Shiny lo fija solo cuando
# se arranca con runApp() sobre la carpeta; si en cambio se hace source("app.R")
# desde otro sitio, el directorio es otro y `www/` no se sirve: la app carga,
# se conecta y muestra los datos, pero SIN NINGUN ESTILO PROPIO --los cuadros
# caen apilados y el gráfico sale gigante y negro-- porque Bootstrap viene del
# paquete bslib y custom.css no llega. Es un fallo mudo y muy desconcertante,
# asi que se convierte en un error explicito.
local({
  falta <- c("R/utils_db.R", "Modules/mod_auth.R", "www/custom.css",
             "Diccionarios/FormAintralaboral.xlsx")
  falta <- falta[!file.exists(falta)]
  if (length(falta)) {
    stop("\n\nLa app no se esta ejecutando desde su propia carpeta, o la copia ",
         "esta incompleta.\nNo se encuentra: ", paste(falta, collapse = ", "),
         "\nDirectorio actual: ", getwd(),
         "\n\nArranquela apuntando a la carpeta de la app:",
         "\n  shiny::runApp(\"C:/ruta/a/Shiny_seguimiento\", launch.browser = TRUE)",
         "\no abriendo Shiny_seguimiento.Rproj en RStudio y pulsando Run App.\n",
         call. = FALSE)
  }
})

# Los archivos de `www/` se entregan como una DEPENDENCIA HTML y no por la vía
# implícita de Shiny. Shiny sirve `www/` solo cuando reconoce la app como
# directorio, y hay equipos donde eso no ocurre: custom.css devuelve 404, la app
# funciona y muestra los datos pero sin un solo estilo propio --los cuadros caen
# apilados y el gráfico sale gigante y negro-- y nada en la consola lo dice.
#
# Una dependencia es el mismo mecanismo con el que bslib entrega Bootstrap, que
# es justo lo que sí llegaba en esos equipos. Además Shiny arma la URL él mismo,
# así que no depende de dónde esté colgada la página, y la deduplica: grafico.js
# se carga una vez aunque el módulo se dibuje muchas.
#
# `version` hace de cache-busting: la URL lleva el número dentro, así que al
# cambiar custom.css o grafico.js hay que subirlo (era el `?v=N` de antes).
DEP_ESTATICOS <- htmltools::htmlDependency(
  name       = "seguimiento-estaticos",
  version    = "62",
  src        = c(file = normalizePath("www")),
  stylesheet = "custom.css",
  script     = "grafico.js"
)

# Credenciales de conexión. Shiny fija el directorio de trabajo en la carpeta
# de la app, así que este .Renviron local sí se lee (el de arranque de R no).
if (file.exists(".Renviron")) readRenviron(".Renviron")

# Helpers y módulos (se cargan después de las librerías)
source("R/helpers.R")
source("R/utils_db.R")
source("R/utils_auth.R")
source("R/utils_seguimiento.R")
source("R/utils_contactos.R")
source("R/utils_resultados.R")
source("Modules/mod_auth.R", local = TRUE)
source("Modules/mod_seguimiento.R", local = TRUE)
source("Modules/mod_resultados.R", local = TRUE)
source("Modules/mod_citaciones.R", local = TRUE)
source("Modules/mod_usuarios.R", local = TRUE)


APP_TITULO <- "Seguimiento riesgo psicosocial"

# Identidad institucional (Manual de Identidad, Universidad de Antioquia):
# color principal Pantone 357 = CMYK 79/0/87/56 = RGB 0/95/44 = #005F2C, y
# Times New Roman como familia tipografica.
UDEA_VERDE <- "#005F2C"

# El manual no define semanticos. Se derivan fuera de la gama verde para que
# "critico" y "en curso" no se confundan con el institucional, que queda
# reservado a "al dia" (el manual le atribuye ese significado: esperanza).
# Contraste sobre blanco: verde 7,86:1 - rojo 7,57:1 - ambar 6,49:1.
UDEA_CRITICO <- "#9B2C1E"
UDEA_MEDIO   <- "#7D5700"

# En Linux no suele haber Times New Roman: Tinos y Liberation Serif son
# metricamente compatibles y hay que nombrarlas, o la cascada cae en DejaVu
# Serif, que tiene otro color de pagina.
UDEA_SERIF <- font_collection("Times New Roman", "Tinos", "Liberation Serif",
                              "Nimbus Roman", "Times", "serif")

# Los datos se leen en sans: el manual regula piezas de comunicacion e impresos
# (cuerpos de 9 a 12 pt), no tablas de 57 filas en pantalla.
UDEA_SANS <- font_collection("system-ui", "Segoe UI", "Roboto",
                             "Helvetica Neue", "Arial", "sans-serif")

TEMA <- bs_theme(
  version    = 5,
  bootswatch = "flatly",
  primary    = UDEA_VERDE,
  success    = UDEA_VERDE,
  info       = "#456B5D",
  warning    = UDEA_MEDIO,
  danger     = UDEA_CRITICO,
  heading_font = UDEA_SERIF,
  base_font    = UDEA_SANS
) |>
  bs_add_variables(
    # Los nombres reales de Bootstrap llevan el sufijo del esquema (light para
    # navbarPage(inverse = FALSE), dark para inverse = TRUE); se fijan los dos
    # para que la barra no dependa de cual se renderice.
    "navbar-bg" = UDEA_VERDE,

    # Flatly define el color de la pestana activa como $success, que aqui es el
    # mismo verde del fondo de la barra: la pestana seleccionada se volvia
    # invisible. La activa va en blanco puro (7,96:1) y las demas en blanco al
    # 75% (5,22:1), asi la seleccionada es la mas clara de la fila.
    "navbar-light-color"              = "rgba(255, 255, 255, .75)",
    "navbar-light-hover-color"        = "#cfe4d7",
    "navbar-light-active-color"       = "#ffffff",
    "navbar-light-brand-color"        = "#ffffff",
    "navbar-light-brand-hover-color"  = "#ffffff",

    "navbar-dark-color"               = "rgba(255, 255, 255, .75)",
    "navbar-dark-hover-color"         = "#cfe4d7",
    "navbar-dark-active-color"        = "#ffffff",
    "navbar-dark-brand-color"         = "#ffffff",
    "navbar-dark-brand-hover-color"   = "#ffffff"
  )

# Devolver el pool al apagar la app.
onStop(function() try(db_cerrar(), silent = TRUE))


# La app está detrás del módulo de seguridad, así que la cáscara se dibuja
# desde el server: pantalla de ingreso o navbarPage según haya sesión.
ui <- bootstrapPage(
  theme = TEMA,
  title = APP_TITULO,
  DEP_ESTATICOS,
  mod_auth_scripts("auth"),
  uiOutput("pagina")
)


server <- function(input, output, session) {

  # Estado central compartido por todos los módulos.
  r <- reactiveValues(
    usuario    = NULL, # ficha de sesión; la publica mod_auth
    citaciones = 0     # sube cada vez que mod_citaciones reemplaza la agenda
  )

  # Estado de la base: se evalúa una vez por sesión.
  estado_bd <- local({
    conexion <- db_probar()
    if (!isTRUE(conexion)) {
      list(ok = FALSE, motivo = "conexion", detalle = conexion)
    } else {
      tryCatch({
        # Crean lo que falte y no tocan lo que ya esté: en un equipo nuevo la
        # app deja la base con todas sus tablas, aunque todavía estén vacías.
        auth_init_db()
        cto_init_db()
        seg_init_db()

        # Que no haya usuarios NO es un problema de arranque: de eso se
        # encarga el formulario de primer arranque de mod_auth.
        faltan <- seg_faltantes()
        if (length(faltan)) list(ok = FALSE, motivo = "sin_datos", detalle = faltan)
        else                list(ok = TRUE)
      }, error = function(e) {
        list(ok = FALSE, motivo = "esquema", detalle = conditionMessage(e))
      })
    }
  })

  # 0) Seguridad: lo único que corre antes de entrar.
  mod_auth_server("auth", r = r)

  # Los demás módulos arrancan con el primer ingreso válido --con la clave
  # temporal ya cambiada-- y una sola vez por sesión. Antes arrancaban al abrir
  # la página, y sus salidas y acciones quedaban al alcance de quien no había
  # entrado: basta con pedirlas desde el navegador, aunque la interfaz no las
  # dibuje. Salir, o que la sesión caduque, recarga la página, así que nunca hace
  # falta detenerlos.
  observeEvent(
    if (!is.null(r$usuario) && !isTRUE(r$usuario$debe_cambiar)) TRUE,
    {
      # 1) Seguimiento por dependencia
      mod_seguimiento_server("seg", r = r)

      # 2) Resultados por grupos de personas, solo con el permiso
      #    `ver_resultados` (todos menos el auxiliar)
      if (auth_puede(r$usuario$rol, "ver_resultados")) mod_resultados_server("res", r = r)

      # 3) Grupos de aplicación
      mod_citaciones_server("cit", r = r)

      # 4) Administración (usuarios, agenda y bitácora), solo con el permiso
      #    `usuarios` (administrador)
      if (auth_puede(r$usuario$rol, "usuarios")) mod_usuarios_server("usr", r = r)
    },
    once = TRUE
  )

  output$pagina <- renderUI({
    if (!isTRUE(estado_bd$ok)) return(pantalla_arranque(estado_bd))
    if (is.null(r$usuario) || isTRUE(r$usuario$debe_cambiar)) return(mod_auth_ui("auth"))
    pantalla_principal(r$usuario)
  })
}


# --- Cáscara de la app --------------------------------------------------------

# Aquí se van colgando los módulos siguientes como tabPanel().
pantalla_principal <- function(sesion) {
  navbarPage(
    title  = APP_TITULO,
    id     = "main_nav",
    header = tagList(
      div(class = "auth-barra", mod_auth_barra_ui("auth"))
    ),

    # 1) Seguimiento por dependencia
    tabPanel(
      icon  = icon("chart-simple"),
      title = "Avance por dependencia",
      mod_seguimiento_ui("seg")
    ),

    # 2) Resultados por grupos de personas, solo con el permiso
    #    `ver_resultados` (todos menos el auxiliar)
    if (auth_puede(sesion$rol, "ver_resultados")) tabPanel(
      icon  = icon("users"),
      title = "Resultados",
      mod_resultados_ui("res")
    ),

    # 3) Grupos de aplicacion
    tabPanel(
      icon  = icon("calendar-days"),
      title = "Citaciones",
      mod_citaciones_ui("cit", rol = sesion$rol)
    ),

    # 4) Administración (usuarios, agenda y bitácora), solo con el permiso
    #    `usuarios` (administrador)
    if (auth_puede(sesion$rol, "usuarios")) tabPanel(
      icon  = icon("users-gear"),
      title = "Administración",
      mod_usuarios_ui("usr")
    )

    # 5) <siguiente modulo>
    # tabPanel(icon = icon("table"), title = "...", mod_x_ui("x"))
  )
}

# Aviso cuando la app no puede arrancar por la base de datos.
pantalla_arranque <- function(estado) {
  cuerpo <- switch(
    estado$motivo,
    conexion = tagList(
      p("La aplicación no pudo conectarse a PostgreSQL."),
      tags$pre(class = "small text-muted", estado$detalle),
      p(class = "small",
        "Revise que el servidor esté arriba y que .Renviron apunte a la base correcta.")
    ),
    esquema = tagList(
      p("La base respondió, pero no se pudieron preparar sus esquemas."),
      tags$pre(class = "small text-muted", estado$detalle)
    ),
    sin_datos = tagList(
      p("La base está creada, pero le faltan los datos del estudio."),
      tags$ul(class = "small", lapply(estado$detalle, tags$li)),
      p(class = "small",
        "Los dos insumos externos son el marco muestral y el export de ODK; ",
        "el resto lo genera un solo comando desde la terminal:"),
      tags$pre(class = "small",
               "Rscript scripts/preparar_bd.R --marco=<marco.xlsx> --odk=<respuestas.csv>")
    )
  )

  div(
    class = "aviso-arranque",
    card(
      class = "shadow-sm",
      card_body(
        class = "p-4",
        h5("No se puede iniciar la aplicación", class = "mb-3"),
        cuerpo
      )
    )
  )
}


shinyApp(ui, server)

#!/usr/bin/env Rscript
# -----------------------------------------------------------------------------
# Gestion de usuarios desde la terminal.
# Se ejecuta desde la carpeta de la app:
#
#   Rscript scripts/gestionar_usuarios.R listar
#   Rscript scripts/gestionar_usuarios.R crear <usuario> <rol> "Nombre Completo"
#   Rscript scripts/gestionar_usuarios.R reset <usuario>
#   Rscript scripts/gestionar_usuarios.R eliminar <usuario>
#   Rscript scripts/gestionar_usuarios.R rol <usuario> <rol>
#   Rscript scripts/gestionar_usuarios.R bitacora [n]
#
# <rol> es administrador, coordinador, auxiliar o psicologo; lo que puede hacer
# cada uno esta en AUTH_PERMISOS (R/utils_auth.R). Lo mismo se hace desde la
# pestana Administracion de la app, que ven los administradores.
# No hay cuentas desactivadas; para quitarle el acceso a alguien se elimina el
# usuario (su rastro en la bitacora se conserva y sus sesiones se cierran solas).
# Reiniciar la clave tambien quita el bloqueo por intentos fallidos.
#
# La contrasena se pide de forma interactiva: nunca se pasa por argumento,
# para que no quede en el historial del shell ni en la lista de procesos.
# -----------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(DBI); library(RPostgres); library(pool); library(scrypt)
})

# Ubicarse en la raiz de la app sin importar desde donde se invoque.
args_full <- commandArgs(trailingOnly = FALSE)
ruta_script <- sub("^--file=", "", grep("^--file=", args_full, value = TRUE))
if (length(ruta_script) == 1) setwd(dirname(dirname(normalizePath(ruta_script))))

if (file.exists(".Renviron")) readRenviron(".Renviron")
source("R/utils_db.R",   encoding = "UTF-8")
source("R/utils_auth.R", encoding = "UTF-8")

args <- commandArgs(trailingOnly = TRUE)

salir <- function(...) {
  message(...)
  try(db_cerrar(), silent = TRUE)
  quit(status = 1)
}

uso <- function() {
  cat("
Uso:
  listar
  crear <usuario> <rol> \"Nombre Completo\"
  reset <usuario>
  eliminar <usuario>
  rol <usuario> <rol>
  bitacora [n]

Roles: administrador, coordinador, auxiliar, psicologo
")
  quit(status = 1)
}

# Lectura de secretos.
#
# No hay una sola forma que sirva en todas partes, asi que se prueban por orden
# de preferencia y se usa la primera disponible:
#
#   1. stty -echo sobre la terminal. Es lo que funciona en Linux y macOS, pero
#      `stty` no existe en Windows.
#   2. getPass, que si sabe apagar el eco de la consola de Windows.
#   3. El dialogo de RStudio, cuando el script se corre desde ahi.
#   4. askpass, que abre un dialogo del sistema.
#
# Bajo Rscript `interactive()` es FALSE, asi que askpass::askpass() por si solo
# no basta: devolveria NULL, que parece una cancelacion.
#
# Si ninguna sirve, el script NO cae a leer la clave con el eco encendido: se
# detiene y remite al formulario de primer arranque de la app, que hace lo mismo
# desde el navegador y no necesita terminal.

hay_tty <- function() {
  identical(suppressWarnings(
    system2("stty", "size", stdout = FALSE, stderr = FALSE)), 0L)
}

hay_paquete <- function(p) requireNamespace(p, quietly = TRUE)

hay_rstudio <- function() {
  hay_paquete("rstudioapi") && isTRUE(tryCatch(rstudioapi::isAvailable(),
                                               error = function(e) FALSE))
}

# Devuelve list(leer, con): la funcion que lee un secreto y la conexion que hay
# que cerrar al terminar, o NULL si no hay ninguna manera de preguntar.
lector_de_claves <- function() {
  if (hay_tty()) {
    # Una sola conexion para las dos lecturas: reabrir stdin entre una y otra
    # se come lo que ya este en el bufer.
    con <- file("stdin", open = "r")
    return(list(con = con, leer = function(prompt) {
      cat(prompt); flush(stdout())
      system2("stty", "-echo", stdout = FALSE, stderr = FALSE)
      on.exit({
        system2("stty", "echo", stdout = FALSE, stderr = FALSE)
        cat("\n"); flush(stdout())
      }, add = TRUE)
      v <- readLines(con, n = 1L, warn = FALSE)
      if (length(v) == 0) "" else v
    }))
  }

  if (hay_paquete("getPass"))
    return(list(con = NULL,
                leer = function(prompt) getPass::getPass(prompt, noblank = FALSE)))

  if (hay_rstudio())
    return(list(con = NULL,
                leer = function(prompt) rstudioapi::askForPassword(prompt)))

  if (hay_paquete("askpass"))
    return(list(con = NULL,
                leer = function(prompt) askpass::askpass(prompt)))

  NULL
}

pedir_clave <- function(titulo = "Contrasena") {
  lector <- lector_de_claves()
  if (is.null(lector)) {
    salir(paste0(
      "Esta terminal no puede pedir la contrasena sin mostrarla en pantalla.\n",
      "Dos salidas:\n",
      "  - Cree o cambie la cuenta desde la app: si no hay ningun usuario, al\n",
      "    abrirla aparece el formulario de primer arranque.\n",
      "  - O instale getPass y vuelva a intentarlo:\n",
      "      install.packages(\"getPass\")"))
  }

  if (!is.null(lector$con)) on.exit(close(lector$con), add = TRUE)
  c1 <- lector$leer(paste0(titulo, ": "))
  c2 <- lector$leer("Repita la contrasena: ")
  if (is.null(c1) || is.null(c2)) salir("Cancelado.")

  if (!nzchar(c1))        salir("Cancelado.")
  if (!identical(c1, c2)) salir("Las contrasenas no coinciden.")
  if (!is.null(m <- auth_validar_clave(c1))) salir(m)
  c1
}

# La confirmacion no es un secreto, asi que se lee de stdin tal cual. Eso si
# funciona en Windows; lo que no funcionaba era apagar el eco.
confirmar <- function(pregunta) {
  cat(pregunta, " [escriba SI para continuar]: ", sep = ""); flush(stdout())
  con <- file("stdin", open = "r"); on.exit(close(con), add = TRUE)
  v <- tryCatch(readLines(con, n = 1L, warn = FALSE), error = function(e) character(0))
  if (length(v) == 0) salir("\nNo se pudo leer la respuesta: cancelado.")
  identical(toupper(trimws(v)), "SI")
}


conexion <- db_probar()
if (!isTRUE(conexion)) salir(conexion)
auth_init_db()

if (length(args) == 0) uso()
accion <- args[1]

switch(
  accion,

  listar = {
    u <- auth_listar_usuarios()
    if (nrow(u) == 0) cat("No hay usuarios.\n") else print(u, right = FALSE)
  },

  crear = {
    if (length(args) < 4) uso()
    usuario <- args[2]
    rol     <- tolower(args[3])
    # El rol se revisa antes de pedir la clave, para no pedirla en vano.
    if (!is.null(m <- auth_validar_rol(rol))) salir(m)
    nombre  <- paste(args[-(1:3)], collapse = " ")
    clave   <- pedir_clave("Contrasena temporal")
    auth_crear_usuario(usuario, clave, nombre, rol = rol, debe_cambiar = TRUE,
                       detalle = "desde la terminal")
    cat(sprintf("Usuario '%s' creado con rol %s. Debera cambiar la clave al ingresar.\n",
                tolower(usuario), rol))
  },

  reset = {
    if (length(args) < 2) uso()
    clave <- pedir_clave("Nueva contrasena temporal")
    auth_reset_clave(args[2], clave, detalle = "desde la terminal")
    cat(sprintf("Contrasena de '%s' reiniciada. Debera cambiarla al ingresar.\n", args[2]))
  },

  eliminar = {
    if (length(args) < 2) uso()
    if (!confirmar(sprintf(paste("Se eliminara el usuario '%s': pierde el acceso, sus sesiones",
                                 "se cierran y sus grupos por empezar quedan libres."),
                           args[2]))) {
      salir("Cancelado.")
    }
    auth_eliminar_usuario(args[2], detalle = "desde la terminal")
    cat(sprintf("Usuario '%s' eliminado. Su rastro queda en la bitacora.\n", args[2]))
  },

  rol = {
    if (length(args) < 3) uso()
    rol <- tolower(args[3])
    if (!is.null(m <- auth_validar_rol(rol))) salir(m)
    cambio <- auth_cambiar_rol(args[2], rol, detalle = "desde la terminal")
    cat(if (isTRUE(cambio))
          sprintf("'%s' ahora es %s: %s Sus sesiones abiertas se cierran solas.\n",
                  tolower(args[2]), rol, auth_rol_descripcion(rol))
        else sprintf("'%s' ya tenia el rol %s.\n", tolower(args[2]), rol))
  },

  bitacora = {
    n <- if (length(args) >= 2) as.integer(args[2]) else 50L
    b <- auth_leer_bitacora(n)
    if (nrow(b) == 0) cat("Bitacora vacia.\n") else print(b, right = FALSE)
  },

  uso()
)

db_cerrar()

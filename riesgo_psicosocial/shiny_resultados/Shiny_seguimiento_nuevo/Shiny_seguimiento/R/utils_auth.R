# -----------------------------------------------------------------------------
# utils_auth.R
# Capa de datos y reglas de la autenticacion sobre PostgreSQL (esquema `auth`).
# Sin nada de UI: todo lo de aqui se puede llamar desde el modulo, desde
# scripts o desde tests.
#
# Cinco roles (AUTH_ROLES). Avance lo ven todos; lo que los distingue esta en
# AUTH_PERMISOS, que es el unico sitio donde se decide:
#   ver_citaciones  ver la pestana Citaciones              todos menos el
#                                                          especialista
#   ver_resultados  ver la pestana Resultados              todos
#   descargar_datos ver la pestana Descarga de datos y     administrador y
#                   bajar las respuestas con cedula        especialista
#   usuarios        administrar cuentas y ver la bitacora  administrador
#   cargar_agenda   subir el Excel de la agenda            administrador
#   informe_avance  bajar el informe de avance en Word     administrador
#   asignar_grupos  ponerle o quitarle el psicologo a      todos menos el
#                   cualquier grupo                        especialista
#   tomar_grupos    tomar y soltar sus propios grupos      psicologo
#   registrar_sesion  registrar la sesion y observar a    psicologo
#                     cada persona, solo en sus grupos
#   revisar_sesiones  leer y corregir cualquier registro  administrador
#                     de sesion, a cualquier hora
#   borrar_personas   borrar personas desde Avance y      administrador
#                     restaurarlas en Administracion
# El psicologo es quien aplica la encuesta, y un grupo solo se le asigna a un
# psicologo. La interfaz se dibuja segun el rol de la ficha de sesion, pero cada
# accion vuelve a leer el rol de la base (auth_puede_usuario()).
#
# La app se publica en internet (NGROK.md), asi que el ingreso se defiende solo:
#   - clave de al menos AUTH_MIN_CLAVE caracteres, con letras y numeros;
#   - tras AUTH_MAX_FALLOS fallos de un usuario, o AUTH_MAX_FALLOS_ORIGEN desde
#     una misma IP, hay que esperar AUTH_VENTANA_MIN minutos. Se cuenta sobre la
#     bitacora, sin tabla aparte, y se mira ANTES de scrypt: un intento
#     bloqueado no gasta CPU;
#   - scrypt calibrado a ~AUTH_SCRYPT_SEG s. R atiende todas las sesiones con un
#     solo hilo, y a 0,6 s cada ingreso congelaba la app para todos;
#   - la ficha de sesion lleva un sello de la clave y el rol: si cambian o el
#     usuario se borra, las sesiones abiertas se cierran (auth_sesion_vigente()).
# La bitacora registra todo ingreso, fallo, bloqueo y cambio.
# -----------------------------------------------------------------------------

AUTH_ROLES <- c(
  administrador = "Administrador",
  coordinador   = "Coordinador",
  auxiliar      = "Auxiliar administrativo",
  psicologo     = "Psicólogo",
  especialista  = "Especialista"
)

AUTH_PERMISOS <- list(
  ver_citaciones = c("administrador", "coordinador", "auxiliar", "psicologo"),
  ver_resultados = c("administrador", "coordinador", "auxiliar", "psicologo",
                     "especialista"),
  descargar_datos = c("administrador", "especialista"),
  usuarios       = "administrador",
  cargar_agenda  = "administrador",
  informe_avance = "administrador",
  asignar_grupos   = c("administrador", "coordinador", "auxiliar", "psicologo"),
  tomar_grupos     = "psicologo",
  registrar_sesion = "psicologo",
  revisar_sesiones = "administrador",
  borrar_personas  = "administrador"
)

AUTH_PERMISOS_TXT <- c(
  ver_citaciones   = "ve las citaciones",
  ver_resultados   = "ve los resultados",
  descargar_datos  = "descarga las respuestas en Excel",
  usuarios         = "administra usuarios y ve la bitácora",
  cargar_agenda    = "carga la agenda de citaciones",
  informe_avance   = "descarga el informe de avance en Word",
  asignar_grupos   = "asigna grupos a los psicólogos",
  tomar_grupos     = "toma y suelta sus propios grupos",
  registrar_sesion = "registra sus sesiones y observa a cada persona",
  revisar_sesiones = "lee y corrige los registros de sesión",
  borrar_personas  = "borra personas del seguimiento y las restaura"
)

AUTH_MIN_CLAVE         <- 8L
AUTH_MAX_CLAVE         <- 128L
AUTH_MAX_FALLOS        <- 5L
AUTH_MAX_FALLOS_ORIGEN <- 20L
AUTH_VENTANA_MIN       <- 15L
AUTH_INACTIVIDAD_MIN   <- 30L
AUTH_SCRYPT_SEG        <- 0.1
AUTH_MIN_CODIGO        <- 12L

# Eventos de la bitacora que cuentan como intento fallido, y los que prueban que
# la persona tiene la clave vigente: despues de uno de estos ultimos, los fallos
# anteriores ya no cuentan (reiniciar la clave desbloquea).
AUTH_EVENTOS_FALLO   <- "'ingreso_fallido', 'clave_actual_errada', 'primer_arranque_fallido'"
AUTH_EVENTOS_LIMPIAN <- "'ingreso_exitoso', 'clave_cambiada', 'clave_reiniciada'"

auth_hash <- function(clave) scrypt::hashPassword(clave, maxtime = AUTH_SCRYPT_SEG)

# Hash de descarte: se verifica contra el cuando el usuario no existe, para que
# un usuario inexistente y una clave errada tarden lo mismo y no se pueda
# enumerar usuarios midiendo el tiempo de respuesta. Se calibra igual que los
# hashes nuevos.
AUTH_HASH_SENUELO <- auth_hash(
  paste0("senuelo-", paste(sample(letters, 24, TRUE), collapse = ""))
)

auth_norm <- function(usuario) tolower(trimws(as.character(usuario)))


# --- roles y permisos --------------------------------------------------------

auth_puede <- function(rol, permiso) {
  is.character(rol) && length(rol) == 1 && !is.na(rol) && rol %in% AUTH_PERMISOS[[permiso]]
}

auth_rol_txt <- function(rol) {
  unname(ifelse(rol %in% names(AUTH_ROLES), AUTH_ROLES[rol], rol))
}

# Lo que puede hacer un rol, en palabras, desde AUTH_PERMISOS: asi la ayuda de
# la pantalla no se desfasa de las reglas.
auth_rol_descripcion <- function(rol) {
  p <- names(AUTH_PERMISOS)[vapply(AUTH_PERMISOS, function(x) rol %in% x, logical(1))]
  paste0("ve el avance",
         if (length(p)) paste0("; ", paste(AUTH_PERMISOS_TXT[p], collapse = "; ")), ".")
}

# Una lista de roles como un solo parametro: un arreglo de Postgres ($n::text[]).
auth_pg_roles <- function(roles) paste0("{", paste(roles, collapse = ","), "}")

auth_rol <- function(usuario) {
  x <- db_get("SELECT rol FROM auth.usuarios WHERE usuario = $1", params = list(usuario))
  if (nrow(x) == 1) x$rol[1] else NA_character_
}

# Se pregunta a la base y no a la ficha de sesion: el rol puede cambiar con la
# sesion abierta, y lo que quita un permiso tiene que valer desde ese momento.
auth_puede_usuario <- function(usuario, permiso) {
  !is.null(usuario) && auth_puede(auth_rol(usuario), permiso)
}


# --- hash y sello ------------------------------------------------------------

# logN (el costo) de un hash de scrypt. El hash es base64 de "scrypt", un 0, logN,
# r, p...; logN es el octavo byte, que cae entre los caracteres 10 y 11.
auth_hash_logn <- function(h) {
  alfabeto <- c(LETTERS, letters, 0:9, "+", "/")
  i <- match(strsplit(substr(h, 9, 12), "")[[1]], alfabeto) - 1L
  if (length(i) != 4 || anyNA(i)) return(NA_integer_)
  bitwOr(bitwShiftL(bitwAnd(i[2], 15L), 4L), bitwShiftR(i[3], 2L))
}

# Lo que la ficha de sesion guarda de la clave: el final del hash, que cambia
# entero con cada clave nueva (lleva sal). La ficha no carga el hash completo.
auth_sello <- function(h) substr(h, nchar(h) - 15L, nchar(h))


# --- esquema -----------------------------------------------------------------

auth_init_db <- function() {
  db_exec("CREATE SCHEMA IF NOT EXISTS auth")

  db_exec("
    CREATE TABLE IF NOT EXISTS auth.usuarios (
      usuario        text        PRIMARY KEY,
      hash           text        NOT NULL,
      nombre         text        NOT NULL,
      debe_cambiar   boolean     NOT NULL DEFAULT true,
      creado         timestamptz NOT NULL DEFAULT now(),
      ultimo_ingreso timestamptz
    )")

  # Migracion de instalaciones anteriores que tenian bloqueo en columnas.
  # Es idempotente: si las columnas ya no estan, no hace nada.
  for (col in c("activo", "intentos_fallidos", "bloqueado_hasta")) {
    db_exec(sprintf("ALTER TABLE auth.usuarios DROP COLUMN IF EXISTS %s", col))
  }

  # Rol. Se agrega una sola vez, y se reconoce por su restriccion. Quienes ya
  # existian conservan lo que podian hacer: con la marca `coordinador` de la
  # version anterior (cargaba la agenda y administraba usuarios) pasan a
  # administrador, y sin ella a psicologo (tomaba grupos). En una base sin esa
  # marca todos lo podian todo, y todos pasan a administrador. Un `rol` de
  # versiones mas viejas, con otros valores, se descarta.
  db_exec(sprintf("
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_constraint
                      WHERE conrelid = 'auth.usuarios'::regclass
                        AND conname = 'usuarios_rol_valido') THEN
        ALTER TABLE auth.usuarios DROP COLUMN IF EXISTS rol;
        ALTER TABLE auth.usuarios ADD COLUMN rol text;
        IF EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'auth' AND table_name = 'usuarios'
                      AND column_name = 'coordinador') THEN
          UPDATE auth.usuarios
             SET rol = CASE WHEN coordinador THEN 'administrador' ELSE 'psicologo' END;
        ELSE
          UPDATE auth.usuarios SET rol = 'administrador';
        END IF;
        ALTER TABLE auth.usuarios ALTER COLUMN rol SET NOT NULL;
        ALTER TABLE auth.usuarios ADD CONSTRAINT usuarios_rol_valido CHECK (rol IN (%s));
      END IF;
      ALTER TABLE auth.usuarios DROP COLUMN IF EXISTS coordinador;
    END $$", paste0("'", names(AUTH_ROLES), "'", collapse = ", ")))

  # La restriccion se rehace en cada arranque para que acepte los roles de
  # AUTH_ROLES: el bloque de arriba solo la crea una vez, y una base de antes
  # del especialista lo rechazaria al crear la cuenta.
  db_exec(sprintf("
    ALTER TABLE auth.usuarios DROP CONSTRAINT IF EXISTS usuarios_rol_valido,
      ADD CONSTRAINT usuarios_rol_valido CHECK (rol IN (%s))",
    paste0("'", names(AUTH_ROLES), "'", collapse = ", ")))

  db_exec("
    CREATE TABLE IF NOT EXISTS auth.bitacora_accesos (
      id      bigserial   PRIMARY KEY,
      momento timestamptz NOT NULL DEFAULT now(),
      usuario text,
      evento  text        NOT NULL,
      detalle text,
      origen  text
    )")

  db_exec("CREATE INDEX IF NOT EXISTS idx_bitacora_momento
             ON auth.bitacora_accesos (momento DESC)")
  db_exec("CREATE INDEX IF NOT EXISTS idx_bitacora_usuario
             ON auth.bitacora_accesos (usuario)")
  db_exec("CREATE INDEX IF NOT EXISTS idx_bitacora_origen
             ON auth.bitacora_accesos (origen)")

  invisible(TRUE)
}

auth_hay_usuarios <- function() {
  n <- db_get("SELECT count(*) AS n FROM auth.usuarios")$n
  isTRUE(as.numeric(n) > 0)
}


# --- bitacora ----------------------------------------------------------------

# Lo que llega del formulario se recorta: sin eso, cada intento fallido podia
# escribir en la bitacora un "usuario" del tamano que quisiera quien lo mando.
auth_bitacora <- function(evento, usuario = NA_character_,
                          detalle = NA_character_, origen = NA_character_) {
  corto <- function(x, n) {
    if (is.null(x) || length(x) != 1 || is.na(x)) NA_character_
    else substr(as.character(x), 1, n)
  }
  db_exec(
    "INSERT INTO auth.bitacora_accesos (usuario, evento, detalle, origen)
     VALUES ($1, $2, $3, $4)",
    params = list(corto(usuario, 64), evento, corto(detalle, 500), corto(origen, 64))
  )
  invisible(TRUE)
}

auth_leer_bitacora <- function(n = 200) {
  db_get(
    "SELECT momento, usuario, evento, detalle, origen
       FROM auth.bitacora_accesos
      ORDER BY id DESC
      LIMIT $1::int",
    params = list(as.integer(n))
  )
}

# IP de quien entra, desde el request de la sesion. Detras de ngrok REMOTE_ADDR
# es siempre el tunel (127.0.0.1); la IP real llega en X-Forwarded-For, y se
# toma la ULTIMA de la lista porque es la que agrega el tunel: las anteriores
# las pudo escribir el propio cliente. Solo es fiable mientras la app escuche en
# 127.0.0.1 y nadie llegue a ella sin pasar por el tunel.
auth_origen <- function(req) {
  leer <- function(campo) {
    x <- tryCatch(req[[campo]], error = function(e) NULL, warning = function(w) NULL)
    if (is.character(x) && length(x) == 1 && !is.na(x) && nzchar(x)) x else NULL
  }
  xff <- leer("HTTP_X_FORWARDED_FOR")
  if (!is.null(xff)) {
    ips <- trimws(strsplit(xff, ",", fixed = TRUE)[[1]])
    ips <- ips[nzchar(ips)]
    if (length(ips)) return(substr(ips[length(ips)], 1, 64))
  }
  x <- leer("REMOTE_ADDR")
  if (is.null(x)) NA_character_ else x
}


# --- bloqueos por intentos fallidos ------------------------------------------

# Subconsulta que devuelve una fila con `hasta` si el usuario de `col` esta
# bloqueado. Cuenta los fallos de la ventana posteriores a la ultima prueba de
# clave vigente; el bloqueo vence cuando el fallo numero AUTH_MAX_FALLOS,
# contando desde el mas reciente, sale de la ventana. `col` es "$1" o una
# columna de la consulta de afuera; las constantes son enteros del codigo.
auth_sql_bloqueo <- function(col) {
  sprintf("
    SELECT f.momento + make_interval(mins => %1$d) AS hasta
      FROM auth.bitacora_accesos f
     WHERE f.usuario = %2$s AND f.evento IN (%3$s)
       AND f.momento > now() - make_interval(mins => %1$d)
       AND f.momento > COALESCE((SELECT max(l.momento) FROM auth.bitacora_accesos l
                                  WHERE l.usuario = %2$s AND l.evento IN (%4$s)),
                                '-infinity')
     ORDER BY f.momento DESC
     OFFSET %5$d LIMIT 1",
    AUTH_VENTANA_MIN, col, AUTH_EVENTOS_FALLO, AUTH_EVENTOS_LIMPIAN, AUTH_MAX_FALLOS - 1L)
}

# Hasta cuando esta bloqueado `usuario`, o NULL si no lo esta. Tambien vale para
# nombres que no existen: si no, el bloqueo delataria cuales si.
auth_bloqueado_hasta <- function(usuario) {
  x <- db_get(auth_sql_bloqueo("$1"), params = list(substr(usuario, 1, 64)))
  if (nrow(x) == 0) NULL else x$hasta[1]
}

# Sin IP real (acceso local, o un tunel que no mande X-Forwarded-For) no se
# limita por origen: todos compartirian 127.0.0.1, y los fallos de cualquiera
# bloquearian a todos.
auth_origen_bloqueado <- function(origen) {
  if (is.null(origen) || is.na(origen) || origen %in% c("127.0.0.1", "::1")) return(FALSE)
  x <- db_get(sprintf("
    SELECT count(*) >= %d AS bloqueado
      FROM auth.bitacora_accesos
     WHERE origen = $1 AND evento IN (%s)
       AND momento > now() - make_interval(mins => %d)",
    AUTH_MAX_FALLOS_ORIGEN, AUTH_EVENTOS_FALLO, AUTH_VENTANA_MIN),
    params = list(origen))
  isTRUE(x$bloqueado[1])
}

auth_msg_espera <- function(hasta = NULL) {
  m <- if (is.null(hasta)) AUTH_VENTANA_MIN
       else max(1, ceiling(as.numeric(difftime(hasta, Sys.time(), units = "mins"))))
  sprintf("Demasiados intentos fallidos. Espere %s %s e intente de nuevo.",
          m, if (m == 1) "minuto" else "minutos")
}


# --- validaciones ------------------------------------------------------------

auth_validar_usuario <- function(usuario) {
  if (!is.character(usuario) || length(usuario) != 1 || is.na(usuario) || !nzchar(usuario)) {
    return("El usuario no puede estar vacio.")
  }
  if (!grepl("^[a-z0-9._-]{3,32}$", usuario)) {
    return(paste("El usuario debe tener entre 3 y 32 caracteres:",
                 "minusculas, numeros, punto, guion o guion bajo."))
  }
  NULL
}

auth_validar_clave <- function(clave) {
  if (!is.character(clave) || length(clave) != 1 || is.na(clave) || !nzchar(clave)) {
    return("La contrasena no puede estar vacia.")
  }
  if (nchar(clave) < AUTH_MIN_CLAVE) {
    return(sprintf("La contrasena debe tener al menos %s caracteres.", AUTH_MIN_CLAVE))
  }
  if (nchar(clave) > AUTH_MAX_CLAVE) {
    return(sprintf("La contrasena no puede pasar de %s caracteres.", AUTH_MAX_CLAVE))
  }
  if (!grepl("[A-Za-z]", clave) || !grepl("[0-9]", clave)) {
    return("La contrasena debe combinar letras y numeros.")
  }
  NULL
}

auth_validar_rol <- function(rol) {
  if (!is.character(rol) || length(rol) != 1 || !rol %in% names(AUTH_ROLES)) {
    return(paste("Rol desconocido. Use uno de:", paste(names(AUTH_ROLES), collapse = ", ")))
  }
  NULL
}

# Codigo del formulario de primer arranque, desde .Renviron. Sin el, en internet
# cualquiera que abriera la URL con la base vacia se quedaba con la primera
# cuenta, que es de administrador. NULL si no esta o es demasiado corto.
auth_codigo_instalacion <- function() {
  x <- Sys.getenv("APP_CODIGO_INSTALACION", "")
  if (nchar(x) >= AUTH_MIN_CODIGO) x else NULL
}

# Clave temporal para entregar a mano: 10 caracteres sin los que se confunden al
# dictarlos (0/O, 1/l/I), con letras y numeros. El azar sale de openssl y no de
# sample(), cuya semilla es predecible.
auth_clave_temporal <- function() {
  simbolos <- strsplit("abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789", "")[[1]]
  repeat {
    b     <- as.integer(openssl::rand_bytes(10))
    clave <- paste(simbolos[b %% length(simbolos) + 1L], collapse = "")
    if (is.null(auth_validar_clave(clave))) return(clave)
  }
}


# --- gestion de usuarios -----------------------------------------------------
# `detalle` y `origen` solo van a la bitacora: de donde salio el cambio (la
# terminal, la app y quien lo hizo) y desde que IP.

auth_crear_usuario <- function(usuario, clave, nombre, rol, debe_cambiar = TRUE,
                               detalle = NA_character_, origen = NA_character_) {
  usuario <- auth_norm(usuario)
  if (!is.null(m <- auth_validar_usuario(usuario))) stop(m, call. = FALSE)
  if (!is.null(m <- auth_validar_clave(clave)))     stop(m, call. = FALSE)
  if (!is.null(m <- auth_validar_rol(rol)))         stop(m, call. = FALSE)
  if (!nzchar(trimws(nombre))) stop("El nombre no puede estar vacio.", call. = FALSE)

  auth_init_db()

  # Un nombre de usuario eliminado no se reutiliza: la cuenta nueva heredaria su
  # rastro en la bitacora y los grupos que aplico.
  if (nrow(db_get("SELECT 1 FROM auth.bitacora_accesos
                    WHERE usuario = $1 AND evento = 'usuario_eliminado' LIMIT 1",
                  params = list(usuario)))) {
    stop("Ese usuario existio y fue eliminado; use otro nombre de usuario.", call. = FALSE)
  }

  n <- db_exec(
    "INSERT INTO auth.usuarios (usuario, hash, nombre, debe_cambiar, rol)
     VALUES ($1, $2, $3, $4::boolean, $5)
     ON CONFLICT (usuario) DO NOTHING",
    params = list(usuario, auth_hash(clave), trimws(nombre), isTRUE(debe_cambiar), rol)
  )
  if (n == 0) stop("Ese usuario ya existe.", call. = FALSE)

  auth_bitacora("usuario_creado", usuario,
                paste(c(auth_rol_txt(rol), if (!is.na(detalle)) detalle), collapse = "; "),
                origen)
  invisible(TRUE)
}

# Devuelve el sello de la clave nueva, para que la sesion que la cambio siga
# vigente.
auth_cambiar_clave <- function(usuario, clave_nueva, origen = NA_character_) {
  usuario <- auth_norm(usuario)
  if (!is.null(m <- auth_validar_clave(clave_nueva))) stop(m, call. = FALSE)

  hash <- auth_hash(clave_nueva)
  n <- db_exec(
    "UPDATE auth.usuarios SET hash = $2, debe_cambiar = false WHERE usuario = $1",
    params = list(usuario, hash)
  )
  if (n == 0) stop("No existe ese usuario.", call. = FALSE)

  auth_bitacora("clave_cambiada", usuario, origen = origen)
  invisible(auth_sello(hash))
}

auth_reset_clave <- function(usuario, clave_temporal, detalle = NA_character_,
                             origen = NA_character_) {
  usuario <- auth_norm(usuario)
  if (!is.null(m <- auth_validar_clave(clave_temporal))) stop(m, call. = FALSE)

  n <- db_exec(
    "UPDATE auth.usuarios SET hash = $2, debe_cambiar = true WHERE usuario = $1",
    params = list(usuario, auth_hash(clave_temporal))
  )
  if (n == 0) stop("No existe ese usuario.", call. = FALSE)

  auth_bitacora("clave_reiniciada", usuario, detalle, origen)
  invisible(TRUE)
}

# Grupos por empezar de `usuario`, que quedan libres cuando deja de poder
# aplicarlos: lo eliminan o deja de ser psicologo. Los que ya pasaron conservan
# su nombre, porque son el registro de quien aplico. La hora es la del campo, la
# misma SEG_TZ de utils_seguimiento.R. La tabla puede no existir si este archivo
# se usa sin el esquema de seguimiento. Devuelve cuantos libero.
auth_liberar_grupos <- function(usuario) {
  if (is.na(db_get("SELECT to_regclass('seguimiento.grupos_aplicador')::text AS t")$t)) return(0)
  db_exec("
    DELETE FROM seguimiento.grupos_aplicador
     WHERE usuario = $1
       AND (fecha + hora_inicio) > (now() AT TIME ZONE 'America/Bogota')",
    params = list(usuario))
}

auth_detalle_libres <- function(libres, detalle) {
  partes <- c(if (!is.null(detalle) && !is.na(detalle)) detalle,
              if (libres > 0) sprintf("%s grupos por empezar quedaron libres", libres))
  if (length(partes)) paste(partes, collapse = "; ") else NA_character_
}

# Como no hay cuentas desactivables, quitarle el acceso a alguien es borrarlo.
# Su rastro en la bitacora se conserva a proposito, y sus sesiones abiertas se
# cierran solas en menos de un minuto (auth_sesion_vigente()). No se puede
# borrar al ultimo administrador: nadie podria administrar usuarios.
auth_eliminar_usuario <- function(usuario, detalle = NA_character_,
                                  origen = NA_character_) {
  usuario <- auth_norm(usuario)
  n <- db_exec("
    DELETE FROM auth.usuarios
     WHERE usuario = $1
       AND (NOT (rol = ANY($2::text[]))
            OR EXISTS (SELECT 1 FROM auth.usuarios o
                        WHERE o.rol = ANY($2::text[]) AND o.usuario <> $1))",
    params = list(usuario, auth_pg_roles(AUTH_PERMISOS$usuarios)))
  if (n == 0) auth_error_sin_cambio(usuario)

  libres <- auth_liberar_grupos(usuario)
  auth_bitacora("usuario_eliminado", usuario, auth_detalle_libres(libres, detalle), origen)
  invisible(TRUE)
}

# Devuelve TRUE si cambio algo. Quien deja de poder tomar grupos suelta los que
# tenia por empezar.
auth_cambiar_rol <- function(usuario, rol, detalle = NA_character_,
                             origen = NA_character_) {
  usuario <- auth_norm(usuario)
  if (!is.null(m <- auth_validar_rol(rol))) stop(m, call. = FALSE)

  antes <- auth_rol(usuario)
  if (is.na(antes)) stop("No existe ese usuario.", call. = FALSE)
  if (identical(antes, rol)) return(invisible(FALSE))

  n <- db_exec("
    UPDATE auth.usuarios SET rol = $2
     WHERE usuario = $1
       AND ($2 = ANY($3::text[]) OR NOT (rol = ANY($3::text[]))
            OR EXISTS (SELECT 1 FROM auth.usuarios o
                        WHERE o.rol = ANY($3::text[]) AND o.usuario <> $1))",
    params = list(usuario, rol, auth_pg_roles(AUTH_PERMISOS$usuarios)))
  if (n == 0) auth_error_sin_cambio(usuario)

  libres <- if (auth_puede(rol, "tomar_grupos")) 0 else auth_liberar_grupos(usuario)
  auth_bitacora("rol_cambiado", usuario,
                auth_detalle_libres(libres, paste(c(
                  sprintf("de %s a %s", auth_rol_txt(antes), auth_rol_txt(rol)),
                  if (!is.na(detalle)) detalle), collapse = "; ")),
                origen)
  invisible(TRUE)
}

auth_listar_usuarios <- function() {
  db_get(sprintf("
    SELECT u.usuario, u.nombre, u.rol, u.debe_cambiar, u.creado,
           u.ultimo_ingreso, b.hasta AS bloqueado_hasta
      FROM auth.usuarios u
      LEFT JOIN LATERAL (%s) b ON TRUE
     ORDER BY u.usuario", auth_sql_bloqueo("u.usuario")))
}

# Por que un UPDATE o DELETE protegido no toco nada: o no existe, o es el ultimo
# administrador.
auth_error_sin_cambio <- function(usuario) {
  if (nrow(db_get("SELECT 1 FROM auth.usuarios WHERE usuario = $1", params = list(usuario)))) {
    stop("Es el unico administrador. Antes dele ese rol a otra persona.", call. = FALSE)
  }
  stop("No existe ese usuario.", call. = FALSE)
}


# --- verificacion de credenciales --------------------------------------------

# Devuelve list(ok, motivo, usuario). En `usuario` va la ficha de sesion que
# consumen los demas modulos: usuario, nombre, debe_cambiar, rol, sello, origen,
# ingreso.
auth_verificar <- function(usuario, clave, origen = NA_character_) {
  fallo <- function(motivo) list(ok = FALSE, motivo = motivo, usuario = NULL)

  # Mensaje deliberadamente generico: no revela si el usuario existe.
  generico <- "Usuario o contrasena incorrectos."

  vacio <- function(x) !is.character(x) || length(x) != 1 || is.na(x) || !nzchar(trimws(x))
  if (vacio(usuario) || vacio(clave)) return(fallo("Escriba usuario y contrasena."))
  usuario <- substr(auth_norm(usuario), 1, 64)

  if (auth_origen_bloqueado(origen)) {
    auth_bitacora("ingreso_bloqueado", usuario, "por origen", origen)
    return(fallo(auth_msg_espera()))
  }
  hasta <- auth_bloqueado_hasta(usuario)
  if (!is.null(hasta)) {
    auth_bitacora("ingreso_bloqueado", usuario, "por usuario", origen)
    return(fallo(auth_msg_espera(hasta)))
  }

  # Un nombre con forma invalida no puede existir: no se consulta.
  u <- if (is.null(auth_validar_usuario(usuario))) db_get(
    "SELECT usuario, hash, nombre, debe_cambiar, rol
       FROM auth.usuarios WHERE usuario = $1",
    params = list(usuario))

  if (is.null(u) || nrow(u) == 0) {
    # Se verifica igual para no delatar por tiempo de respuesta que no existe.
    try(scrypt::verifyPassword(AUTH_HASH_SENUELO, clave), silent = TRUE)
    auth_bitacora("ingreso_fallido", usuario, "usuario inexistente", origen)
    return(fallo(generico))
  }

  hash <- u$hash[1]
  correcta <- isTRUE(tryCatch(scrypt::verifyPassword(hash, clave),
                              error = function(e) FALSE))

  if (!correcta) {
    auth_bitacora("ingreso_fallido", usuario, "clave incorrecta", origen)
    return(fallo(generico))
  }

  # Un hash calibrado con el costo anterior (~0,6 s) se rehace con el actual,
  # aprovechando que en este momento se tiene la clave. El margen de 2 evita
  # rehacerlo por la variacion normal de la calibracion entre arranques.
  if (isTRUE(auth_hash_logn(hash) >= auth_hash_logn(AUTH_HASH_SENUELO) + 2L)) {
    hash <- auth_hash(clave)
    db_exec("UPDATE auth.usuarios SET hash = $2 WHERE usuario = $1",
            params = list(usuario, hash))
  }

  db_exec("UPDATE auth.usuarios SET ultimo_ingreso = now() WHERE usuario = $1",
          params = list(usuario))
  auth_bitacora("ingreso_exitoso", usuario, origen = origen)

  list(
    ok      = TRUE,
    motivo  = NULL,
    usuario = list(
      usuario      = u$usuario[1],
      nombre       = u$nombre[1],
      debe_cambiar = isTRUE(u$debe_cambiar[1]),
      rol          = u$rol[1],
      sello        = auth_sello(hash),
      origen       = origen,
      ingreso      = Sys.time()
    )
  )
}

# Para cambiar la clave con la sesion abierta se pide la actual. Un error cuenta
# como intento fallido: si no, una sesion olvidada serviria para adivinarla sin
# limite.
auth_confirmar_clave <- function(usuario, clave, origen = NA_character_) {
  hasta <- auth_bloqueado_hasta(usuario)
  if (!is.null(hasta)) return(list(ok = FALSE, motivo = auth_msg_espera(hasta)))

  h <- db_get("SELECT hash FROM auth.usuarios WHERE usuario = $1", params = list(usuario))
  ok <- nrow(h) == 1 && is.character(clave) && length(clave) == 1 && !is.na(clave) &&
        isTRUE(tryCatch(scrypt::verifyPassword(h$hash[1], clave), error = function(e) FALSE))
  if (!ok) {
    auth_bitacora("clave_actual_errada", usuario, origen = origen)
    return(list(ok = FALSE, motivo = "La contrasena actual no es correcta."))
  }
  list(ok = TRUE, motivo = NULL)
}

# La sesion sigue valiendo si el usuario existe, con la misma clave y el mismo
# rol con que entro. Borrarlo, reiniciarle la clave, cambiarle el rol o que
# cambie la clave desde otro equipo cierra las sesiones que tenga abiertas; con
# el rol nuevo, entra de nuevo y ve lo que le corresponde.
auth_sesion_vigente <- function(usuario, sello, rol) {
  x <- db_get("SELECT right(hash, 16) AS sello, rol FROM auth.usuarios WHERE usuario = $1",
              params = list(usuario))
  nrow(x) == 1 && identical(x$sello[1], sello) && identical(x$rol[1], rol)
}

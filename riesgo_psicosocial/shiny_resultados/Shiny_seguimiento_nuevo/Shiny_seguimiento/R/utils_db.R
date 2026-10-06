# -----------------------------------------------------------------------------
# utils_db.R
# Conexion a PostgreSQL. Un unico pool para toda la app, creado de forma
# perezosa la primera vez que alguien consulta y cerrado al apagar la app.
#
# La configuracion se lee de variables de entorno (.Renviron), nunca del codigo.
# Por defecto apunta al socket local, que es como esta autenticando este equipo
# (peer auth), asi que no hace falta contrasena.
# -----------------------------------------------------------------------------

.db <- new.env(parent = emptyenv())

db_config <- function() {
  list(
    host     = Sys.getenv("PG_HOST",     "postgres"),
    port     = as.integer(Sys.getenv("PG_PORT", "5432")),
    dbname   = Sys.getenv("PG_DB",       "riesgo_psicosocial"),
    user     = Sys.getenv("PG_USER",     Sys.info()[["user"]]),
    password = Sys.getenv("PG_PASSWORD", "")
  )
}
# 
# db_config <- function() {
#   list(
#     host     = Sys.getenv("PG_HOST",     "localhost"),
#     port     = as.integer(Sys.getenv("PG_PORT", "5432")),
#     dbname   = Sys.getenv("PG_DB",       "riesgo_psicosocial"),
#     user     = Sys.getenv("PG_USER",     "erps_user"),
#     password = Sys.getenv("PG_PASSWORD", "123456")
#   )
# }

db_pool <- function() {
  if (is.null(.db$pool) || !pool::dbIsValid(.db$pool)) {
    cfg <- db_config()
    .db$pool <- pool::dbPool(
      drv         = RPostgres::Postgres(),
      host        = cfg$host,
      port        = cfg$port,
      dbname      = cfg$dbname,
      user        = cfg$user,
      password    = cfg$password,
      # Silencia los NOTICE de "ya existe" que emiten los CREATE ... IF NOT EXISTS.
      options     = "-c client_min_messages=warning",
      minSize     = 1,
      maxSize     = 5,
      idleTimeout = 60 * 1000
    )
  }
  .db$pool
}

db_cerrar <- function() {
  if (!is.null(.db$pool) && pool::dbIsValid(.db$pool)) pool::poolClose(.db$pool)
  .db$pool <- NULL
  invisible(TRUE)
}

# Nota: RPostgres usa marcadores $1, $2, ... (no `?`).
db_get <- function(sql, params = NULL) {
  DBI::dbGetQuery(db_pool(), sql, params = params)
}

db_exec <- function(sql, params = NULL) {
  DBI::dbExecute(db_pool(), sql, params = params)
}

db_tx <- function(f) {
  pool::poolWithTransaction(db_pool(), f)
}

# Diagnostico legible: TRUE si conecta, si no un mensaje con la causa.
db_probar <- function() {
  cfg <- db_config()
  tryCatch({
    db_get("SELECT 1")
    TRUE
  }, error = function(e) {
    sprintf("No se pudo conectar a PostgreSQL (%s@%s:%s/%s): %s",
            cfg$user, cfg$host, cfg$port, cfg$dbname, conditionMessage(e))
  })
}

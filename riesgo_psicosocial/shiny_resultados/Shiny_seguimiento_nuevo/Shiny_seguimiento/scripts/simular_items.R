#!/usr/bin/env Rscript
# -----------------------------------------------------------------------------
# simular_items.R
# Vuelve a simular los items de la Bateria en seguimiento.respuestas_odk.
#
#   Rscript scripts/simular_items.R
#
# Por que hacia falta: la simulacion anterior generaba valores 1..5 uniformes,
# que no es lo que entrega el formulario. En el XLSForm los items se responden
# con estas listas, y son las que definen el valor que ODK guarda:
#
#   likert       0 Nunca .. 4 Siempre      (87 items)
#   likert_rev   4 Nunca .. 0 Siempre     (164 items, ya invertidos en el form)
#   estres1      0 / 3 / 6 / 9             (9 items)
#   estres2      0 / 2 / 4 / 6            (13 items)
#   estres3      0 / 1 / 2 / 3             (9 items)
#
# Consecuencia importante: como el formulario ya aplica la inversion, el valor
# numerico SIEMPRE apunta en el sentido del riesgo --mas alto es peor-- en los
# 251 items intralaborales y extralaborales. Por eso aqui se simula una sola
# propension latente por persona y se usa igual para las dos listas: no hay que
# invertir nada, y la calificacion de conectar_bd.R puede seguir sumando crudo.
#
# Que NO se toca:
#   - el patron de vacios. Un NA se deja NA, asi que los saltos del formulario
#     (quien no atiende publico no contesta ila_p106..114) y los cuestionarios
#     incompletos siguen exactamente como estaban, y `completa` no se mueve.
#   - ninguna columna que no sea un item, ni las claves: se hace UPDATE por
#     `clave`, nunca DELETE ni TRUNCATE (seguimiento.puntajes referencia esta
#     tabla con ON DELETE CASCADE).
# -----------------------------------------------------------------------------

suppressMessages({
  library(DBI); library(RPostgres); library(readxl)
})

SEMILLA <- 4321          # la misma de la simulacion original
set.seed(SEMILLA)

# Cuanto pesa la persona y cuanto la dimension en el valor de cada item. Ver el
# comentario del bloque 3: SD_THETA es lo que gobierna la forma de la
# distribucion de riesgo que sale al final.
SD_THETA <- 0.50
SD_DIM   <- 0.45

# El XLSForm vive en la raiz del proyecto y los diccionarios en
# Shiny_seguimiento/Diccionarios. Se buscan desde donde se haya lanzado el
# script --la carpeta de la app o la raiz-- en vez de exigir un cwd concreto.
buscar <- function(rel) {
  for (base in c(".", "..", "Shiny_seguimiento", "../Shiny_seguimiento")) {
    p <- file.path(base, rel)
    if (file.exists(p)) return(normalizePath(p))
  }
  stop("no encuentro ", rel, " desde ", getwd())
}
FORM     <- buscar("Form Riesgo Psicosocial.xlsx")
RAIZ_APP <- dirname(buscar("conectar_bd.R"))
DICC <- dirname(buscar(file.path("Diccionarios", "FormAintralaboral.xlsx")))

con <- dbConnect(RPostgres::Postgres(),
                 host     = Sys.getenv("PG_HOST", "postgres"),
                 port     = as.integer(Sys.getenv("PG_PORT", "5432")),
                 dbname   = Sys.getenv("PG_DB", "riesgo_psicosocial"),
                 user     = Sys.getenv("PG_USER", Sys.info()[["user"]]),
                 password = Sys.getenv("PG_PASSWORD", "1568"),
                 timezone = "America/Bogota")
on.exit(if (dbIsValid(con)) dbDisconnect(con))


# --- 1. que lista usa cada item ----------------------------------------------
sv <- as.data.frame(read_excel(FORM, sheet = "survey"))
it <- sv[!is.na(sv$name) & grepl("^(ila_p|ilb_p|el_p|ee_p)[0-9]+$", sv$name),
         c("type", "name")]
it$lista <- sub("^select_one ", "", it$type)

# Los valores que puede tomar cada lista, EN ORDEN DE RIESGO CRECIENTE. Para
# likert_rev eso es 0,1,2,3,4 igual que para likert: la lista ya esta invertida
# en el formulario, asi que el nivel 4 --el de mas riesgo-- vale 4 en las dos.
VALORES <- list(
  likert     = 0:4,
  likert_rev = 0:4,
  estres1    = c(0, 3, 6, 9),
  estres2    = c(0, 2, 4, 6),
  estres3    = c(0, 1, 2, 3))

stopifnot(all(it$lista %in% names(VALORES)))
items <- setNames(it$lista, it$name)


# --- 2. dimensiones: sus items, su maximo y su baremo -------------------------
# La calibracion se hace DIMENSION POR DIMENSION, no por cuestionario. Calibrar
# solo el total deja cada dimension donde caiga: en la primera version
# "Recompensas" salia 60% en riesgo muy alto y "Demandas del trabajo" 65% sin
# riesgo, no porque los datos dijeran eso sino porque cada dimension tiene un
# baremo distinto --el corte de "muy alto" va del 20% en Recompensas al 90% en
# Demandas de carga mental-- y una media comun no le sirve a las dos.

DICCS <- list(
  list(f = "FormAintralaboral", suf = "_FormA", prefijo = "ila_p"),
  list(f = "FormBintralaboral", suf = "_FormB", prefijo = "ilb_p"),
  list(f = "Formextralaboral",  suf = "_extra", prefijo = "el_p"),
  list(f = "Formestres",        suf = "_estres", prefijo = "ee_p"))

dim_items <- list()   # dimension -> items
dim_max   <- c()      # dimension -> puntaje bruto maximo
dim_de    <- c()      # item -> dimension

for (x in DICCS) {
  ruta <- file.path(DICC, paste0(x$f, ".xlsx"))
  d1 <- as.data.frame(read_excel(ruta, sheet = 1))
  for (dd in unique(d1$Dimension)) {
    k <- paste0(make.names(dd), x$suf)
    dim_items[[k]] <- d1$Pregunta[d1$Dimension == dd]
    dim_de[dim_items[[k]]] <- k
  }
  # El maximo se calcula desde el formulario y no se lee del diccionario: es la
  # suma de los valores mas altos de las listas de sus items, y asi la
  # calibracion no depende de una hoja de maximos que pueda estar desfasada
  # (la de estres lo esta: dice 61.16 donde el formulario da 186).
  for (dd in unique(d1$Dimension)) {
    k <- paste0(make.names(dd), x$suf)
    dim_max[k] <- sum(vapply(dim_items[[k]],
                             function(i) max(VALORES[[items[[i]]]]), numeric(1)))
  }
}

# Los baremos salen del propio conectar_bd.R --se extraen sus `criterios <-
# list(...)` sin ejecutarlo-- para no tener dos copias de los mismos numeros.
baremos <- local({
  ex <- parse(file.path(RAIZ_APP, "conectar_bd.R")); e <- new.env(); out <- list()
  for (q in ex) if (is.call(q) && identical(as.character(q[[1]]), "<-") &&
                    identical(as.character(q[[2]]), "criterios")) {
    v <- eval(q[[3]], e); out[names(v)] <- v
  }
  # Estres no esta en una lista `criterios`: su clasificacion va escrita a mano.
  out[["Total_estres"]] <- c(7.8, 12.6, 17.7, 25.0)
  out
})

faltan <- setdiff(names(dim_items), names(baremos))
if (length(faltan)) stop("sin baremo: ", paste(faltan, collapse = ", "))


# --- 3. propension al riesgo de cada persona ---------------------------------
d <- dbGetQuery(con, sprintf(
  "SELECT clave, forma_cuestionario, tipo_cargo, %s FROM seguimiento.respuestas_odk ORDER BY clave",
  paste(names(items), collapse = ", ")))
n <- nrow(d)
cat("respuestas a resimular:", n, "\n")

# theta: cuanto riesgo reporta esta persona, en desviaciones estandar. Es la
# perilla que decide la forma de la distribucion final: como el puntaje de una
# dimension suma varios items, el ruido de cada item se promedia y casi toda la
# dispersion entre personas viene de aqui. Con 0.85 la cola en "muy alto" se va
# al 22%; con 0.50 el reparto queda en 33/23/18/14/11, el gradiente decreciente
# que se ve en una poblacion real.
theta <- rnorm(n, 0, SD_THETA)

# Los cargos operativos y auxiliares reportan algo mas de riesgo que los
# profesionales y las jefaturas. Es un supuesto de la simulacion, no un dato,
# pero sin el los cruces por tipo de cargo salen todos identicos y no sirven
# para probar la pantalla de resultados.
theta <- theta + c(`1` = -0.15, `2` = -0.10, `3` = 0.15, `4` = 0.30)[
  as.character(d$tipo_cargo)]
theta[is.na(theta)] <- 0


# --- 4. calibrar cada dimension contra su propio baremo ----------------------
# Se despeja un desplazamiento por dimension para que su MEDIANA caiga en el
# limite del riesgo bajo --el segundo corte del baremo--. Asi cada dimension
# queda centrada en su propia escala y el reparto de las cinco categorias sale
# parecido en todas, que es lo que permite compararlas en la pantalla.
sd_z    <- sqrt(SD_THETA^2 + 1)
CORTE_5 <- qnorm(c(0.30, 0.56, 0.76, 0.90), 0, sd_z)
CORTE_4 <- qnorm(c(0.34, 0.64, 0.87), 0, sd_z)

eps <- matrix(rnorm(n * length(items)), nrow = n,
              dimnames = list(NULL, names(items)))

valores_de <- function(nm, mu) {
  vals <- VALORES[[items[[nm]]]]
  z <- mu + theta + eps[, nm]
  vals[findInterval(z, if (length(vals) == 5) CORTE_5 else CORTE_4) + 1L]
}

# Quien contesta cada dimension: el intralaboral depende de la forma; el
# extralaboral y el de estres los contestan todos.
pobl_de <- function(k) {
  if (grepl("_FormA$", k)) d$forma_cuestionario == "A"
  else if (grepl("_FormB$", k)) d$forma_cuestionario == "B"
  else rep(TRUE, n)
}

# Ojo con los saltos: "Relacion con los colaboradores" solo la contestan los que
# tienen personal a cargo y "Demandas emocionales" los que atienden publico. Si
# la mediana se saca sobre toda la forma, los que no contestaron entran como
# cero --rowSums con na.rm-- y arrastran la calibracion al suelo: en la primera
# version esa dimension quedaba con el 87% en "sin riesgo". Se calibra solo
# sobre quien de verdad respondio el bloque.
mediana_de <- function(k, mu) {
  m <- vapply(dim_items[[k]], function(nm) {
    v <- valores_de(nm, mu); v[is.na(d[[nm]])] <- NA_real_; v
  }, numeric(n))
  f <- pobl_de(k) & rowSums(!is.na(m)) > 0
  median(100 * rowSums(m[f, , drop = FALSE], na.rm = TRUE) / dim_max[[k]], na.rm = TRUE)
}

cat("calibrando", length(dim_items), "dimensiones contra su baremo...\n")
mu_dim <- c()
for (k in names(dim_items)) {
  objetivo <- baremos[[k]][2]          # limite del riesgo bajo
  mu_dim[k] <- tryCatch(
    uniroot(function(mu) mediana_de(k, mu) - objetivo, c(-6, 6), tol = 1e-3)$root,
    error = function(e) 0)
}


# --- 5. generar ---------------------------------------------------------------
for (nm in names(items)) {
  nuevo <- valores_de(nm, mu_dim[[dim_de[[nm]]]])
  # el patron de vacios se respeta tal cual: saltos y cuestionarios incompletos
  nuevo[is.na(d[[nm]])] <- NA_integer_
  d[[nm]] <- as.integer(nuevo)
}


# --- 6. escribir de vuelta ----------------------------------------------------
# UPDATE por clave desde una tabla de paso. Nunca DELETE ni TRUNCATE.
cat("escribiendo...\n")
dbBegin(con)
tryCatch({
  dbExecute(con, "DROP TABLE IF EXISTS pg_temp.items_nuevos")
  dbWriteTable(con, DBI::Id(schema = "pg_temp", table = "items_nuevos"),
               d[, c("clave", names(items))], temporary = TRUE)
  sets <- paste(sprintf("%s = t.%s", names(items), names(items)), collapse = ",\n    ")
  k <- dbExecute(con, sprintf(
    "UPDATE seguimiento.respuestas_odk o SET\n    %s\n    FROM pg_temp.items_nuevos t WHERE t.clave = o.clave", sets))
  dbCommit(con)
  cat("actualizadas", k, "filas\n")
}, error = function(e) { dbRollback(con); stop(e) })

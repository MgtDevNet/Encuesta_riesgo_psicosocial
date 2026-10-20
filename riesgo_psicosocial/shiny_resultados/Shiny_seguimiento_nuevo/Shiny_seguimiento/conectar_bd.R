#!/usr/bin/env Rscript
# -----------------------------------------------------------------------------
# conectar_bd.R
# Conexion a la base `riesgo_psicosocial` desde fuera de la app de seguimiento.
#
# OJO: esto NO es un helper de conexion. Ejecutarlo --por source() o por
# Rscript-- reescribe seguimiento.respuestas de cabo a rabo. Para solo abrir una
# conexion, copiar bd_conectar() de aqui abajo; no sourcear el archivo entero.
#
# Despues de la conexion, el script arma paso a paso `respuestas_bd` --las ocho
# columnas de identificacion mas las 56 de clasificacion que consulta la Shiny--
# calculandolo todo desde la base original seguimiento.respuestas_odk, y con eso
# REESCRIBE seguimiento.respuestas (bloque 9). marco y metas no se tocan.
#
# Los datos de conexion salen de las variables PG_* si estan definidas; si no,
# de los valores por defecto de aqui abajo.
# -----------------------------------------------------------------------------

library(DBI)
library(RPostgres)
library(dplyr)
library(magrittr)
library(tidyverse)
library(readxl)
library(dplyr)
library(stringr)

BD_TZ <- "America/Bogota"

# Las credenciales viven en .Renviron, igual que para la app. Rscript no lee el
# .Renviron de la carpeta --solo el del arranque de R-- asi que hay que pedirlo.
if (file.exists(".Renviron")) readRenviron(".Renviron")

# bd_conectar <- function() {
#   DBI::dbConnect(
#     RPostgres::Postgres(),
#     host     = Sys.getenv("PG_HOST", "postgres"),
#     port     = as.integer(Sys.getenv("PG_PORT", "5432")),
#     dbname   = Sys.getenv("PG_DB",   "riesgo_psicosocial"),
#     user     = Sys.getenv("PG_USER", Sys.info()[["user"]]), #
#     # Vacia por defecto, como en utils_db.R: el equipo donde corre esto
#     # autentica por socket local (peer) y no pide contrasena. Donde si la pida,
#     # va en .Renviron; nunca en el codigo.
#     password = Sys.getenv("PG_PASSWORD", ""),
#     # Sin esto RPostgres abre la conexion en UTC, y entonces: los ::date cortan
#     # el dia a las 19:00 de Medellin (un envio nocturno cae en la jornada
#     # siguiente e inventa un dia de campo) y los POSIXct vuelven etiquetados en
#     # UTC, asi que un envio de las 18:31 se imprime como 23:31.
#     timezone = BD_TZ
#   )
# }
bd_conectar <- function() {
  DBI::dbConnect(
    RPostgres::Postgres(),
    host     = Sys.getenv("PG_HOST", "localhost"),
    port     = as.integer(Sys.getenv("PG_PORT", "5432")),
    dbname   = Sys.getenv("PG_DB",   "riesgo_psicosocial"),
    user     = Sys.getenv("PG_USER", "erps_user"), #
    # Vacia por defecto, como en utils_db.R: el equipo donde corre esto
    # autentica por socket local (peer) y no pide contrasena. Donde si la pida,
    # va en .Renviron; nunca en el codigo.
    password = Sys.getenv("PG_PASSWORD", "123456"),
    # Sin esto RPostgres abre la conexion en UTC, y entonces: los ::date cortan
    # el dia a las 19:00 de Medellin (un envio nocturno cae en la jornada
    # siguiente e inventa un dia de campo) y los POSIXct vuelven etiquetados en
    # UTC, asi que un envio de las 18:31 se imprime como 23:31.
    timezone = BD_TZ
  )
}

con <- bd_conectar()

# RPostgres usa marcadores $1, $2, ... (no `?`).
bd_get  <- function(sql, params = NULL) DBI::dbGetQuery(con, sql, params = params)
bd_exec <- function(sql, params = NULL) DBI::dbExecute(con, sql, params = params)
bd_cerrar <- function() if (DBI::dbIsValid(con)) DBI::dbDisconnect(con)


# =============================================================================
# 1. Leer la base original
# =============================================================================
# El formulario de ODK tal como lo baja conexion_resultados_odk.R, en la tabla
# de la etapa activa (ETAPA en docker/.env): odk_respuestas_piloto u
# odk_respuestas_reales. Es la misma regla de seg_tabla_odk() en
# R/utils_seguimiento.R, que aqui todavia no esta cargado.
etapa <- tolower(trimws(Sys.getenv("ETAPA")))
if (!nzchar(etapa)) etapa <- "piloto"
if (!etapa %in% c("piloto", "reales")) {
  stop("ETAPA debe ser 'piloto' o 'reales' (esta en '", etapa, "').", call. = FALSE)
}
data <- bd_get(sprintf("SELECT * FROM public.odk_respuestas_%s ORDER BY clave", etapa))

# estado_civil volvio al formulario el 2026-10-20. La descarga le agrega la
# columna a la tabla de ODK la primera vez que corre con el codigo nuevo; hasta
# entonces la tabla no la tiene y todos quedan sin dato.
if (!"estado_civil" %in% names(data)) data$estado_civil <- NA_character_

data <- data %>% 
  mutate(across(c(
        ila_p1,            
        ila_p2,            
        ila_p3,            
        ila_p4,            
        ila_p5,            
        ila_p6,            
        ila_p7,            
        ila_p8,            
        ila_p9,            
        ila_p10,           
        ila_p11,           
        ila_p12,           
        ila_p13,           
        ila_p14,           
        ila_p15,           
        ila_p16,           
        ila_p17,           
        ila_p18,           
        ila_p19,           
        ila_p20,           
        ila_p21,           
        ila_p22,           
        ila_p23,           
        ila_p24,           
        ila_p25,           
        ila_p26,           
        ila_p27,           
        ila_p28,           
        ila_p29,           
        ila_p30,           
        ila_p31,           
        ila_p32,           
        ila_p33,           
        ila_p34,           
        ila_p35,           
        ila_p36,           
        ila_p37,           
        ila_p38,           
        ila_p39,           
        ila_p40,           
        ila_p41,           
        ila_p42,           
        ila_p43,           
        ila_p44,           
        ila_p45,           
        ila_p46,           
        ila_p47,           
        ila_p48,           
        ila_p49,           
        ila_p50,           
        ila_p51,           
        ila_p52,           
        ila_p53,           
        ila_p54,           
        ila_p55,           
        ila_p56,           
        ila_p57,           
        ila_p58,           
        ila_p59,           
        ila_p60,           
        ila_p61,           
        ila_p62,           
        ila_p63,           
        ila_p64,           
        ila_p65,           
        ila_p66,           
        ila_p67,           
        ila_p68,           
        ila_p69,           
        ila_p70,           
        ila_p71,           
        ila_p72,           
        ila_p73,           
        ila_p74,           
        ila_p75,           
        ila_p76,           
        ila_p77,           
        ila_p78,           
        ila_p79,           
        ila_p80,           
        ila_p81,           
        ila_p82,           
        ila_p83,           
        ila_p84,           
        ila_p85,           
        ila_p86,           
        ila_p87,           
        ila_p88,           
        ila_p89,           
        ila_p90,           
        ila_p91,           
        ila_p92,           
        ila_p93,           
        ila_p94,           
        ila_p95,           
        ila_p96,           
        ila_p97,           
        ila_p98,           
        ila_p99,           
        ila_p100,          
        ila_p101,          
        ila_p102,          
        ila_p103,          
        ila_p104,          
        ila_p105,          
        ila_p106,          
        ila_p107,          
        ila_p108,          
        ila_p109,          
        ila_p110,          
        ila_p111,          
        ila_p112,          
        ila_p113,          
        ila_p114,          
        ila_p115,          
        ila_p116,          
        ila_p117,          
        ila_p118,          
        ila_p119,          
        ila_p120,          
        ila_p121,          
        ila_p122,          
        ila_p123,
        
        # Preguntas formulario Intralaboral Forma B          
        ilb_p1,            
        ilb_p2,            
        ilb_p3,            
        ilb_p4,            
        ilb_p5,            
        ilb_p6,            
        ilb_p7,            
        ilb_p8,            
        ilb_p9,            
        ilb_p10,           
        ilb_p11,           
        ilb_p12,           
        ilb_p13,           
        ilb_p14,           
        ilb_p15,           
        ilb_p16,           
        ilb_p17,           
        ilb_p18,           
        ilb_p19,           
        ilb_p20,           
        ilb_p21,           
        ilb_p22,           
        ilb_p23,           
        ilb_p24,           
        ilb_p25,           
        ilb_p26,           
        ilb_p27,           
        ilb_p28,           
        ilb_p29,           
        ilb_p30,           
        ilb_p31,           
        ilb_p32,           
        ilb_p33,           
        ilb_p34,           
        ilb_p35,           
        ilb_p36,           
        ilb_p37,           
        ilb_p38,           
        ilb_p39,           
        ilb_p40,           
        ilb_p41,           
        ilb_p42,           
        ilb_p43,           
        ilb_p44,           
        ilb_p45,           
        ilb_p46,           
        ilb_p47,           
        ilb_p48,           
        ilb_p49,           
        ilb_p50,           
        ilb_p51,           
        ilb_p52,           
        ilb_p53,           
        ilb_p54,           
        ilb_p55,           
        ilb_p56,           
        ilb_p57,           
        ilb_p58,           
        ilb_p59,           
        ilb_p60,           
        ilb_p61,           
        ilb_p62,           
        ilb_p63,           
        ilb_p64,           
        ilb_p65,           
        ilb_p66,           
        ilb_p67,           
        ilb_p68,           
        ilb_p69,           
        ilb_p70,           
        ilb_p71,           
        ilb_p72,           
        ilb_p73,           
        ilb_p74,           
        ilb_p75,           
        ilb_p76,           
        ilb_p77,           
        ilb_p78,           
        ilb_p79,           
        ilb_p80,           
        ilb_p81,           
        ilb_p82,           
        ilb_p83,           
        ilb_p84,           
        ilb_p85,           
        ilb_p86,           
        ilb_p87,           
        ilb_p88,           
        ilb_p89,           
        ilb_p90,           
        ilb_p91,           
        ilb_p92,           
        ilb_p93,           
        ilb_p94,           
        ilb_p95,           
        ilb_p96,           
        ilb_p97,
        
        # FORMULARIO EXTRALABORAL
        el_p1,             
        el_p2,             
        el_p3,             
        el_p4,             
        el_p5,             
        el_p6,             
        el_p7,             
        el_p8,             
        el_p9,             
        el_p10,            
        el_p11,            
        el_p12,            
        el_p13,            
        el_p14,            
        el_p15,            
        el_p16,            
        el_p17,            
        el_p18,            
        el_p19,            
        el_p20,            
        el_p21,            
        el_p22,            
        el_p23,            
        el_p24,            
        el_p25,            
        el_p26,            
        el_p27,            
        el_p28,            
        el_p29,            
        el_p30,            
        el_p31,
        
        # FORMULARIO ESTRES
        ee_p1,             
        ee_p2,             
        ee_p3,             
        ee_p4,             
        ee_p5,             
        ee_p6,             
        ee_p7,             
        ee_p8,             
        ee_p9,             
        ee_p10,            
        ee_p11,            
        ee_p12,            
        ee_p13,            
        ee_p14,            
        ee_p15,            
        ee_p16,            
        ee_p17,            
        ee_p18,            
        ee_p19,            
        ee_p20,            
        ee_p21,            
        ee_p22,            
        ee_p23,            
        ee_p24,            
        ee_p25,            
        ee_p26,            
        ee_p27,            
        ee_p28,            
        ee_p29,            
        ee_p30,            
        ee_p31
      ), as.numeric))

data %>% dim()

# =============================================================================
# 2. Nombres de los bloques de items
# =============================================================================
# Cuatro bloques. Cada persona contesta UNO de los dos intralaborales --el que
# le corresponde por su forma-- mas extralaboral y estres, que son para todos.

items_ila <- paste0("ila_p", 1:123)   # intralaboral forma A
items_ilb <- paste0("ilb_p", 1:97)    # intralaboral forma B
items_el  <- paste0("el_p",  1:31)    # extralaboral
items_ee  <- paste0("ee_p",  1:31)    # estres


# =============================================================================
# 3. Definicion de saltos
# =============================================================================
# definicion de saltos

es_a      <- data$forma_cuestionario == "A"
atiende   <- ifelse(es_a, data$ila_val1, data$ilb_val1) %in% 1
con_gente <- es_a & data$ila_val2 %in% 1



# =============================================================================
# 4. Contar los items en blanco, bloque por bloque
# =============================================================================

blancos_tronco_a <- rowSums(is.na(data[, paste0("ila_p",   1:105)]))
blancos_tronco_b <- rowSums(is.na(data[, paste0("ilb_p",    1:88)]))
blancos_emocion_a <- rowSums(is.na(data[, paste0("ila_p", 106:114)]))
blancos_emocion_b <- rowSums(is.na(data[, paste0("ilb_p",  89:97)]))
blancos_colabora  <- rowSums(is.na(data[, paste0("ila_p", 115:123)]))
blancos_el <- rowSums(is.na(data[, items_el]))
blancos_ee <- rowSums(is.na(data[, items_ee]))


# =============================================================================
# 5. El bloque intralaboral, completo o no
# =============================================================================
# Cada condicional se lee "o no le tocaba, o lo respondio entero": si no
# atiende publico, !atiende ya es TRUE y el bloque se ignora este como este.

intra_completo <- ifelse(
  es_a,
  blancos_tronco_a == 0 &
    (!atiende   | blancos_emocion_a == 0) &
    (!con_gente | blancos_colabora  == 0),
  blancos_tronco_b == 0 &
    (!atiende   | blancos_emocion_b == 0))



# =============================================================================
# 6. La variable `completa`
# =============================================================================
# Extralaboral y estres no tienen filtros: los responden todos, asi que se
# exigen enteros siempre.

completa <- intra_completo & blancos_el == 0 & blancos_ee == 0

# =============================================================================
# 7. calificacion de la escala 
# =============================================================================
# Lectura de las preguntas por encuesta. Los diccionarios estan en Diccionarios/,
# no junto al script: este bloque viene de calificacion_puntajes.R, que se
# ejecutaba desde la carpeta donde estaban los .xlsx.
DICC_A      <- file.path("Diccionarios", "FormAintralaboral.xlsx")
DICC_B      <- file.path("Diccionarios", "FormBintralaboral.xlsx")
DICC_EXTRA  <- file.path("Diccionarios", "Formextralaboral.xlsx")
DICC_ESTRES <- file.path("Diccionarios", "Formestres.xlsx")

DimilA     <- read_excel(DICC_A,      sheet = 1)
DimilB     <- read_excel(DICC_B,      sheet = 1)
DimiExtra  <- read_excel(DICC_EXTRA,  sheet = 1)
DimiEstres <- read_excel(DICC_ESTRES, sheet = 1)

# funciones útiles
aprox_decimal <- function(valor){
  return (round(valor * 100,1))
  
}


#función para calcular los puntajes brutos 
cal_pun_brutos <- function(datos, agrupacion, sufijo = "") {
  
  # Detectar qué columnas existen
  tiene_dominio <- "Dominio" %in% names(agrupacion)
  tiene_dominios <- "Dominios" %in% names(agrupacion)
  tiene_dimension <- "Dimension" %in% names(agrupacion)
  
  # Procesar por Dominio/Dominios si existe
  if (tiene_dominio || tiene_dominios) {
    col_dominio <- if (tiene_dominio) "Dominio" else "Dominios"
    
    puntajes_dom <- agrupacion %>%
      group_by(across(all_of(col_dominio))) %>%
      summarise(
        preguntas = list(Pregunta),
        .groups = "drop"
      ) %>%
      rename(dominio = all_of(col_dominio))
    
    for (i in seq_len(nrow(puntajes_dom))) {
      
      dominio <- puntajes_dom$dominio[i]
      preguntas <- puntajes_dom$preguntas[[i]]
      
      nombre_bruto <- paste0(
        "puntaje_bruto_dom_",
        make.names(dominio),
        if (sufijo != "") paste0("_", sufijo) else ""
      )
      
      datos[[nombre_bruto]] <- rowSums(
        datos[, preguntas, drop = FALSE],
        na.rm = TRUE
      )
    }
  }
  
  # Procesar por Dimensión si existe y es diferente a los dominios
  if (tiene_dimension) {
    
    puntajes_dim <- agrupacion %>%
      group_by(Dimension) %>%
      summarise(
        preguntas = list(Pregunta),
        .groups = "drop"
      )
    
    for (i in seq_len(nrow(puntajes_dim))) {
      
      dimension <- puntajes_dim$Dimension[i]
      preguntas <- puntajes_dim$preguntas[[i]]
      
      nombre_bruto <- paste0(
        "puntaje_bruto_dim_",
        make.names(dimension),
        if (sufijo != "") paste0("_", sufijo) else ""
      )
      
      datos[[nombre_bruto]] <- rowSums(
        datos[, preguntas, drop = FALSE],
        na.rm = TRUE
      )
    }
  }
  
  return(datos)
}


#función para calcular los puntajes transformados
cal_pun_normalizados <- function(datos, archivo_excel = DICC_A, sufijo = "") {
  
  # Leer todas las hojas disponibles
  hojas <- excel_sheets(archivo_excel)
  
  # Detectar qué hojas existen
  tiene_sheet2 <- "Sheet2" %in% hojas || length(hojas) >= 2
  tiene_sheet3 <- "Sheet3" %in% hojas || length(hojas) >= 3
  
  # Leer valores si existen
  valores_dim <- NULL
  valores_dom <- NULL
  
  if (tiene_sheet2) {
    valores_sheet2 <- read_excel(archivo_excel, sheet = 2)
    # Detectar si es dimensiones, dominios o total (estrés)
    if ("Dimension" %in% names(valores_sheet2)) {
      valores_dim <- valores_sheet2
    } else if ("Dominio" %in% names(valores_sheet2)) {
      valores_dom <- valores_sheet2
    } else if ("Total" %in% names(valores_sheet2)) {
      # Estructura especial: convertir "Total" a "Dimension"
      valores_sheet2 <- valores_sheet2 %>%
        rename(Dimension = Total) %>%
        mutate(Dimension = "Total")  # Normalizar a "Total" para coincidir con brutos
      valores_dim <- valores_sheet2
    }
  }
  
  if (tiene_sheet3) {
    valores_sheet3 <- read_excel(archivo_excel, sheet = 3)
    # Detectar si es dimensiones, dominios o total
    if ("Dimension" %in% names(valores_sheet3)) {
      valores_dim <- valores_sheet3
    } else if ("Dominio" %in% names(valores_sheet3)) {
      valores_dom <- valores_sheet3
    }
    # No procesar "Total" de sheet 3, es el puntaje total general
  }
  
  # Normalizar dimensiones si existen
  if (!is.null(valores_dim)) {
    for (i in seq_len(nrow(valores_dim))) {
      
      dimension <- valores_dim$Dimension[i]
      valor <- valores_dim$Valor[i]
      
      nombre_bruto <- paste0(
        "puntaje_bruto_dim_",
        make.names(dimension),
        if (sufijo != "") paste0("_", sufijo) else ""
      )
      
      nombre_norm <- paste0(
        "puntaje_norm_dim_",
        make.names(dimension),
        if (sufijo != "") paste0("_", sufijo) else ""
      )
      
      if (nombre_bruto %in% names(datos)) {
        datos[[nombre_norm]] <- datos[[nombre_bruto]] / valor
      }
    }
  }
  
  # Normalizar dominios si existen
  if (!is.null(valores_dom)) {
    for (i in seq_len(nrow(valores_dom))) {
      
      dominio <- valores_dom$Dominio[i]
      valor <- valores_dom$Valor[i]
      
      nombre_bruto <- paste0(
        "puntaje_bruto_dom_",
        make.names(dominio),
        if (sufijo != "") paste0("_", sufijo) else ""
      )
      
      nombre_norm <- paste0(
        "puntaje_norm_dom_",
        make.names(dominio),
        if (sufijo != "") paste0("_", sufijo) else ""
      )
      
      if (nombre_bruto %in% names(datos)) {
        datos[[nombre_norm]] <- datos[[nombre_bruto]] / valor
      }
    }
  }
  
  return(datos)
}

#función para calcular puntaje bruto total
cal_pun_bruto_total <- function(datos) {
  
  # FormA: ila_*
  preguntas_ila <- grep("^ila_p", names(datos), value = TRUE)
  if (length(preguntas_ila) > 0) {
    datos$puntaje_bruto_total_FormA <- rowSums(
      datos[, preguntas_ila, drop = FALSE],
      na.rm = TRUE
    )
  }
  
  # FormB: ilb_*
  preguntas_ilb <- grep("^ilb_p", names(datos), value = TRUE)
  if (length(preguntas_ilb) > 0) {
    datos$puntaje_bruto_total_FormB <- rowSums(
      datos[, preguntas_ilb, drop = FALSE],
      na.rm = TRUE
    )
  }
  
  # Extralaboral: el_*
  preguntas_el <- grep("^el_p", names(datos), value = TRUE)
  if (length(preguntas_el) > 0) {
    datos$puntaje_bruto_total_extra <- rowSums(
      datos[, preguntas_el, drop = FALSE],
      na.rm = TRUE
    )
  }
  
  #Estrés: ee_* (suma de promedios ponderados por bloque)
  bloques_estres <- list(
    list(items = 1:8,   mult = 4),
    list(items = 9:12,  mult = 3),
    list(items = 13:22, mult = 2),
    list(items = 23:31, mult = 1)
  )
  if (all(paste0("ee_p", 1:31) %in% names(datos))) {
    datos$puntaje_bruto_total_estres <- Reduce(`+`, lapply(bloques_estres, function(b) {
      rowMeans(datos[, paste0("ee_p", b$items), drop = FALSE]) * b$mult
    }))
  }


  
  # Puntaje general (intra + extralaboral) para FormA
  if ("puntaje_bruto_total_FormA" %in% names(datos) && "puntaje_bruto_total_extra" %in% names(datos)) {
    datos$puntaje_bruto_total_intra_extra_FormA <- datos$puntaje_bruto_total_FormA + datos$puntaje_bruto_total_extra
  }
  
  # Puntaje general (intra + extralaboral) para FormB
  if ("puntaje_bruto_total_FormB" %in% names(datos) && "puntaje_bruto_total_extra" %in% names(datos)) {
    datos$puntaje_bruto_total_intra_extra_FormB <- datos$puntaje_bruto_total_FormB + datos$puntaje_bruto_total_extra
  }
  
  return(datos)
}


#función para calcular el puntaje bruto normalizado
cal_pun_total_normalizados <- function(datos, archivo_A = DICC_A,
                                       archivo_B = DICC_B,
                                       archivo_extra = DICC_EXTRA,
                                       archivo_estres = DICC_ESTRES) {
  
  # Procesar FormA
  sheet4_A <- read_excel(archivo_A, sheet = 4)
  if ("Total" %in% names(sheet4_A)) {
    valor_total_A <- sheet4_A$Valor[1]
    valor_general_A <- sheet4_A$Valor[2]  # Segunda fila: evaluación general
    
    if ("puntaje_bruto_total_FormA" %in% names(datos)) {
      datos$puntaje_norm_total_FormA <- datos$puntaje_bruto_total_FormA / valor_total_A
    }
    
    if ("puntaje_bruto_total_intra_extra_FormA" %in% names(datos)) {
      datos$puntaje_norm_total_intra_extra_FormA <- datos$puntaje_bruto_total_intra_extra_FormA / valor_general_A
    }
  }
  
  # Procesar FormB
  sheet4_B <- read_excel(archivo_B, sheet = 4)
  if ("Total" %in% names(sheet4_B)) {
    valor_total_B <- sheet4_B$Valor[1]
    valor_general_B <- sheet4_B$Valor[2]  # Segunda fila: evaluación general
    
    if ("puntaje_bruto_total_FormB" %in% names(datos)) {
      datos$puntaje_norm_total_FormB <- datos$puntaje_bruto_total_FormB / valor_total_B
    }
    
    if ("puntaje_bruto_total_intra_extra_FormB" %in% names(datos)) {
      datos$puntaje_norm_total_intra_extra_FormB <- datos$puntaje_bruto_total_intra_extra_FormB / valor_general_B
    }
  }
  
  # Procesar Extralaboral
  sheet3_extra <- read_excel(archivo_extra, sheet = 3)
  if ("Total" %in% names(sheet3_extra)) {
    valor_total_extra <- sheet3_extra$Valor[1]
    if ("puntaje_bruto_total_extra" %in% names(datos)) {
      datos$puntaje_norm_total_extra <- datos$puntaje_bruto_total_extra / valor_total_extra
    }
  }
  
  # Procesar Estrés
  sheet2_estres <- read_excel(archivo_estres, sheet = 2)
  if ("Valor" %in% names(sheet2_estres)) {
    valor_total_estres <- sheet2_estres$Valor[1]
    if ("puntaje_bruto_total_estres" %in% names(datos)) {
      datos$puntaje_norm_total_estres <- datos$puntaje_bruto_total_estres / valor_total_estres
    }
  }
  
  return(datos)
}


# Procesar Formulario A
data <- cal_pun_brutos(data, DimilA, sufijo = "FormA")
data <- cal_pun_normalizados(data, archivo_excel = DICC_A, sufijo = "FormA")

# Procesar Formulario B
data <- cal_pun_brutos(data, DimilB, sufijo = "FormB")
data <- cal_pun_normalizados(data, archivo_excel = DICC_B, sufijo = "FormB")

# Procesar Formulario extralaboral
data <- cal_pun_brutos(data, DimiExtra, sufijo = "extra")
data <- cal_pun_normalizados(data, archivo_excel = DICC_EXTRA, sufijo = "extra")

# Procesar Formulario estrés
data <- cal_pun_brutos(data, DimiEstres, sufijo = "estres")
data <- cal_pun_normalizados(data, archivo_excel = DICC_ESTRES, sufijo = "estres")

# Calcular puntajes totales brutos
data <- cal_pun_bruto_total(data)

# Calcular puntajes totales normalizados
data <- cal_pun_total_normalizados(data)

#data %>% select(ends_with("_estres")) %>% head()
# puntaje_bruto_dim_Total_estres puntaje_norm_dim_Total_estres puntaje_bruto_total_estres
# 1                             17                     0.2779595                         17
# 2                             23                     0.3760628                         23
# 3                             28                     0.4578156                         28
# 4                             33                     0.5395683                         33
# 5                             22                     0.3597122                         22
# 6                             63                     1.0300850                         63
# puntaje_norm_total_estres
# 1                 0.2779595
# 2                 0.3760628
# 3                 0.4578156
# 4                 0.5395683
# 5                 0.3597122
# 6                 1.0300850

# Organizar los puntajes para la clasificación
data %<>%
  mutate(across(contains("norm"), aprox_decimal))





data %<>%
  mutate(
    across(
      matches("^puntaje_.*_FormA$"),
      ~ if_else(forma_cuestionario == "B", NA, .)
    ),
    across(
      matches("^puntaje_.*_FormB$"),
      ~ if_else(forma_cuestionario == "A", NA, .)
    )
  )

# CLASIFICACIONES ----

# INTRALABORAL, FORMA A ----

## DIMENSIONES ----
# Definir criterios por dimensión 
criterios <- list(
  "Características.del.liderazgo_FormA" = c(3.8, 15.4, 30.8, 46.2),
  "Relaciones.sociales.en.el.trabajo_FormA" = c(5.4, 16.1, 25.0, 37.5),
  "Retroalimentación.del.desempeño_FormA" = c(10.0, 25.0, 40.0, 55.0),
  "Relación.con.los.colaboradores_FormA" = c(13.9, 25.0, 33.3, 47.2),
  "Claridad.de.rol_FormA" = c(0.9, 10.7, 21.4, 39.3),
  "Capacitación_FormA" = c(0.9, 16.7, 33.3, 50.0),
  "Participación.y.manejo.del.cambio_FormA" = c(12.5, 25.0, 37.5, 50.0),
  "Oportunidades.para.el.uso.y.desarrollo.de.habilidades.y.conocimientos_FormA" = c(0.9, 6.3, 18.8, 31.3),
  "Control.y.autonomía.sobre.el.trabajo_FormA" = c(8.3, 25.0, 41.7, 58.3),
  "Demandas.ambientales.y.de.esfuerzo.físico_FormA" = c(14.6, 22.9, 31.3, 39.6),
  "Demandas.emocionales_FormA" = c(16.7, 25.0, 33.3, 47.2),
  "Demandas.cuantitativas_FormA" = c(25.0, 33.3, 45.8, 54.2),
  "Influencia.del.trabajo.sobre.el.entorno.extralaboral_FormA" = c(18.8, 31.3, 43.8, 50.0),
  "Exigencias.de.responsabilidad.del.cargo_FormA" = c(37.5, 54.2, 66.7, 79.2),
  "Demandas.de.carga.mental_FormA" = c(60.0, 70.0, 80.0, 90.0),
  "Consistencia.del.rol_FormA" = c(15.0, 25.0, 35.0, 45.0),
  "Demandas.de.la.jornada.de.trabajo_FormA" = c(8.3, 25.0, 33.3, 50.0),
  "Recompensas.derivadas.de.la.pertenencia.a.la.organización.y.del.trabajo.que.se.realiza_FormA" = c(0.9, 5.0, 10.0, 20.0),
  "Reconocimiento.y.compensación_FormA" = c(4.2, 16.7, 25.0, 37.5)
)

# Loop de clasificación
vars_puntaje <- names(data)[str_detect(names(data), "puntaje_norm_dim_.*_FormA")]

for (var in vars_puntaje) {
  nombre_dim <- str_remove(var, "puntaje_norm_dim_")
  nombre_clasificacion <- paste0("clasificacion_dim_", nombre_dim)
  
  limites <- criterios[[nombre_dim]]
  
  data[[nombre_clasificacion]] <- case_when(
    data$forma_cuestionario == "B" ~ NA_character_,
    is.na(data[[var]]) ~ NA_character_,
    data[[var]] <= limites[1] ~ "Sin riesgo o riesgo despreciable",
    data[[var]] <= limites[2] ~ "Riesgo bajo",
    data[[var]] <= limites[3] ~ "Riesgo medio",
    data[[var]] <= limites[4] ~ "Riesgo alto",
    TRUE ~ "Riesgo muy alto"
  )
}

## DOMINIOS ----

# Definir criterios por dominio FormA CON _FormA
criterios <- list(
  "Liderazgo.y.relaciones.sociales.en.el.trabajo_FormA" = c(9.1, 17.7, 25.6, 34.8),
  "Control.sobre.el.trabajo_FormA" = c(10.7, 19.0, 29.8, 40.5),
  "Demandas.del.trabajo_FormA" = c(28.5, 35.0, 41.5, 47.5),
  "Recompensas_FormA" = c(4.5, 11.4, 20.5, 29.5)
)

# Loop de clasificación
vars_puntaje <- names(data)[str_detect(names(data), "puntaje_norm_dom_.*_FormA")]

for (var in vars_puntaje) {
  nombre_dom <- str_remove(var, "puntaje_norm_dom_")
  nombre_clasificacion <- paste0("clasificacion_dom_", nombre_dom)
  
  limites <- criterios[[nombre_dom]]
  
  data[[nombre_clasificacion]] <- case_when(
    data$forma_cuestionario == "B" ~ NA_character_,
    is.na(data[[var]]) ~ NA_character_,
    data[[var]] <= limites[1] ~ "Sin riesgo o riesgo despreciable",
    data[[var]] <= limites[2] ~ "Riesgo bajo",
    data[[var]] <= limites[3] ~ "Riesgo medio",
    data[[var]] <= limites[4] ~ "Riesgo alto",
    TRUE ~ "Riesgo muy alto"
  )
}

## TOTAL GENERAL INTRALABORAL ----

data <- data %>%
  mutate(
    clasificacion_total_FormA = case_when(
      data$forma_cuestionario == "B" ~ NA_character_,
      is.na(puntaje_norm_total_FormA) ~ NA_character_,
      puntaje_norm_total_FormA <= 19.7 ~ "Sin riesgo o riesgo despreciable",
      puntaje_norm_total_FormA <= 25.8 ~ "Riesgo bajo",
      puntaje_norm_total_FormA <= 31.5 ~ "Riesgo medio",
      puntaje_norm_total_FormA <= 38.0 ~ "Riesgo alto",
      TRUE ~ "Riesgo muy alto"
    )
  )


## TOTAL GENERAL INTRA-EXTRA ----
# Clasificar puntaje_norm_total_FormA
data <- data %>%
  mutate(
    clasificacion_total_intra_extra_FormA = case_when(
      data$forma_cuestionario == "B" ~ NA_character_,
      is.na(puntaje_norm_total_intra_extra_FormA) ~ NA_character_,
      puntaje_norm_total_intra_extra_FormA <= 18.8 ~ "Sin riesgo o riesgo despreciable",
      puntaje_norm_total_intra_extra_FormA <= 24.4 ~ "Riesgo bajo",
      puntaje_norm_total_intra_extra_FormA <= 29.5 ~ "Riesgo medio",
      puntaje_norm_total_intra_extra_FormA <= 35.4 ~ "Riesgo alto",
      TRUE ~ "Riesgo muy alto"
    )
  )

# INTRALABORAL FORMB ----
## DIMENSIONES ----

# Definir criterios por dimensión FormB CON _FormB
criterios <- list(
  "Características.del.liderazgo_FormB" = c(3.8, 13.5, 25.0, 38.5),
  "Relaciones.sociales.en.el.trabajo_FormB" = c(6.3, 14.6, 27.1, 37.5),
  "Retroalimentación.del.desempeño_FormB" = c(5.0, 20.0, 30.0, 50.0),
  "Claridad.de.rol_FormB" = c(0.9, 5.0, 15.0, 30.0),
  "Capacitación_FormB" = c(0.9, 16.7, 25.0, 50.0),
  "Participación.y.manejo.del.cambio_FormB" = c(16.7, 33.3, 41.7, 58.3),
  "Oportunidades.para.el.uso.y.desarrollo.de.habilidades.y.conocimientos_FormB" = c(12.5, 25.0, 37.5, 56.3),
  "Control.y.autonomía.sobre.el.trabajo_FormB" = c(33.3, 50.0, 66.7, 75.0),
  "Demandas.ambientales.y.de.esfuerzo.físico_FormB" = c(22.9, 31.3, 39.6, 47.9),
  "Demandas.emocionales_FormB" = c(19.4, 27.8, 38.9, 47.2),
  "Demandas.cuantitativas_FormB" = c(16.7, 33.3, 41.7, 50.0),
  "Influencia.del.trabajo.sobre.el.entorno.extralaboral_FormB" = c(12.5, 25.0, 31.3, 50.0),
  "Demandas.de.carga.mental_FormB" = c(50.0, 65.0, 75.0, 85.0),
  "Demandas.de.la.jornada.de.trabajo_FormB" = c(25.0, 37.5, 45.8, 58.3),
  "Recompensas.derivadas.de.la.pertenencia.a.la.organización.y.del.trabajo.que.se.realiza_FormB" = c(0.9, 6.3, 12.5, 18.8),
  "Reconocimiento.y.compensación_FormB" = c(0.9, 12.5, 25.0, 37.5)
)

# Loop de clasificación
vars_puntaje <- names(data)[str_detect(names(data), "puntaje_norm_dim_.*_FormB")]

for (var in vars_puntaje) {
  nombre_dim <- str_remove(var, "puntaje_norm_dim_")
  nombre_clasificacion <- paste0("clasificacion_dim_", nombre_dim)
  
  limites <- criterios[[nombre_dim]]
  
  data[[nombre_clasificacion]] <- case_when(
    data$forma_cuestionario == "A" ~ NA_character_,
    is.na(data[[var]]) ~ NA_character_,
    data[[var]] <= limites[1] ~ "Sin riesgo o riesgo despreciable",
    data[[var]] <= limites[2] ~ "Riesgo bajo",
    data[[var]] <= limites[3] ~ "Riesgo medio",
    data[[var]] <= limites[4] ~ "Riesgo alto",
    TRUE ~ "Riesgo muy alto"
  )
}

## DOMINOS ----

# Definir criterios por dominio FormB CON _FormB
criterios <- list(
  "Liderazgo.y.relaciones.sociales.en.el.trabajo_FormB" = c(8.3, 17.5, 26.7, 38.3),
  "Control.sobre.el.trabajo_FormB" = c(19.4, 26.4, 34.7, 43.1),
  "Demandas.del.trabajo_FormB" = c(26.9, 33.3, 37.8, 44.2),
  "Recompensas_FormB" = c(2.5, 10.0, 17.5, 27.5)
)

# Loop de clasificación
vars_puntaje <- names(data)[str_detect(names(data), "puntaje_norm_dom_.*_FormB")]

for (var in vars_puntaje) {
  nombre_dom <- str_remove(var, "puntaje_norm_dom_")
  nombre_clasificacion <- paste0("clasificacion_dom_", nombre_dom)
  
  limites <- criterios[[nombre_dom]]
  
  data[[nombre_clasificacion]] <- case_when(
    data$forma_cuestionario == "A" ~ NA_character_,
    is.na(data[[var]]) ~ NA_character_,
    data[[var]] <= limites[1] ~ "Sin riesgo o riesgo despreciable",
    data[[var]] <= limites[2] ~ "Riesgo bajo",
    data[[var]] <= limites[3] ~ "Riesgo medio",
    data[[var]] <= limites[4] ~ "Riesgo alto",
    TRUE ~ "Riesgo muy alto"
  )
}

## TOTAL GENERAL INTRALABORAL ----


# Clasificar puntaje_norm_total_FormB
data <- data %>%
  mutate(
    clasificacion_total_FormB = case_when(
      data$forma_cuestionario == "A" ~ NA_character_,
      is.na(puntaje_norm_total_FormB) ~ NA_character_,
      puntaje_norm_total_FormB <= 20.6 ~ "Sin riesgo o riesgo despreciable",
      puntaje_norm_total_FormB <= 26.0 ~ "Riesgo bajo",
      puntaje_norm_total_FormB <= 31.2 ~ "Riesgo medio",
      puntaje_norm_total_FormB <= 38.7 ~ "Riesgo alto",
      TRUE ~ "Riesgo muy alto"
    )
  )

## TOTAL GENERAL INTRA-EXTRA ----
# Clasificar puntaje_norm_total_FormA
data <- data %>%
  mutate(
    clasificacion_total_intra_extra_FormB = case_when(
      data$forma_cuestionario == "A" ~ NA_character_,
      is.na(puntaje_norm_total_intra_extra_FormB) ~ NA_character_,
      puntaje_norm_total_intra_extra_FormB <= 19.9 ~ "Sin riesgo o riesgo despreciable",
      puntaje_norm_total_intra_extra_FormB <= 24.8 ~ "Riesgo bajo",
      puntaje_norm_total_intra_extra_FormB <= 29.5 ~ "Riesgo medio",
      puntaje_norm_total_intra_extra_FormB <= 35.4 ~ "Riesgo alto",
      TRUE ~ "Riesgo muy alto"
    )
  )

# EXTRALABORAL ----

## DIMENSIONES ----

### JEFES ----
# Definir criterios para dimensiones extralaborales
criterios <- list(
  "Balance.entre.la.vida.laboral.y.familiar_extra" = c(6.3, 25.0, 37.5, 50.0),
  "Relaciones.familiares_extra" = c(8.3, 25.0, 33.3, 50.0),
  "Comunicación.y.relaciones.interpersonales_extra" = c(0.9, 10.0, 20.0, 30.0),
  "Situación.económica.del.grupo.familiar_extra" = c(8.3, 25.0, 33.3, 50.0),
  "Características.de.la.vivienda.y.de.su.entorno_extra" = c(5.6, 11.1, 13.9, 22.2),
  "Influencia.del.entorno.extralaboral.sobre.el.trabajo_extra" = c(8.3, 16.7, 25.0, 41.7),
  "Desplazamiento.vivienda...trabajo...vivienda_extra" = c(0.9, 12.5, 25.0, 43.8)
)

# Loop de clasificación
vars_puntaje <- names(data)[str_detect(names(data), "^puntaje_norm_dim.*_extra$")]

for (var in vars_puntaje) {
  nombre_dim <- str_remove(var, "puntaje_norm_dim_")
  nombre_clasificacion <- paste0("clasificacion_", nombre_dim, "_FormA")
  
  limites <- criterios[[nombre_dim]]
  
  data[[nombre_clasificacion]] <- case_when(
    data$forma_cuestionario == "B" ~ NA_character_,
    is.na(data[[var]]) ~ NA_character_,
    data[[var]] <= limites[1] ~ "Sin riesgo o riesgo despreciable",
    data[[var]] <= limites[2] ~ "Riesgo bajo",
    data[[var]] <= limites[3] ~ "Riesgo medio",
    data[[var]] <= limites[4] ~ "Riesgo alto",
    TRUE ~ "Riesgo muy alto"
  )
}

## TOTAL ---

data <- data %>%
  mutate(
    clasificacion_total_extra_FormA = case_when(
      data$forma_cuestionario == "B" ~ NA_character_,
      is.na(puntaje_norm_total_extra) ~ NA_character_,
      puntaje_norm_total_extra <= 11.3 ~ "Sin riesgo o riesgo despreciable",
      puntaje_norm_total_extra <= 16.9 ~ "Riesgo bajo",
      puntaje_norm_total_extra <= 22.6 ~ "Riesgo medio",
      puntaje_norm_total_extra <= 29 ~ "Riesgo alto",
      TRUE ~ "Riesgo muy alto"
    )
  )

### EMPLEADOS ---- 

# Definir criterios actualizados para dimensiones extralaborales
criterios <- list(
  "Balance.entre.la.vida.laboral.y.familiar_extra" = c(6.3, 25.0, 37.5, 50.0),
  "Relaciones.familiares_extra" = c(8.3, 25.0, 33.3, 50.0),
  "Comunicación.y.relaciones.interpersonales_extra" = c(5.0, 15.0, 25.0, 35.0),
  "Situación.económica.del.grupo.familiar_extra" = c(16.7, 25.0, 41.7, 50.0),
  "Características.de.la.vivienda.y.de.su.entorno_extra" = c(5.6, 11.1, 16.7, 27.8),
  "Influencia.del.entorno.extralaboral.sobre.el.trabajo_extra" = c(0.9, 16.7, 25.0, 41.7),
  "Desplazamiento.vivienda...trabajo...vivienda_extra" = c(0.9, 12.5, 25.0, 43.8)
)

# Loop de clasificación
vars_puntaje <- names(data)[str_detect(names(data), "^puntaje_norm_dim.*_extra$")]

for (var in vars_puntaje) {
  nombre_dim <- str_remove(var, "puntaje_norm_dim_")
  nombre_clasificacion <- paste0("clasificacion_", nombre_dim, "_FormB")
  
  limites <- criterios[[nombre_dim]]
  
  data[[nombre_clasificacion]] <- case_when(
    data$forma_cuestionario == "A" ~ NA_character_,
    is.na(data[[var]]) ~ NA_character_,
    data[[var]] <= limites[1] ~ "Sin riesgo o riesgo despreciable",
    data[[var]] <= limites[2] ~ "Riesgo bajo",
    data[[var]] <= limites[3] ~ "Riesgo medio",
    data[[var]] <= limites[4] ~ "Riesgo alto",
    TRUE ~ "Riesgo muy alto"
  )
}

data <- data %>%
  mutate(
    clasificacion_total_extra_FormB = case_when(
      data$forma_cuestionario == "A" ~ NA_character_,
      is.na(puntaje_norm_total_extra) ~ NA_character_,
      puntaje_norm_total_extra <= 12.9 ~ "Sin riesgo o riesgo despreciable",
      puntaje_norm_total_extra <= 17.7 ~ "Riesgo bajo",
      puntaje_norm_total_extra <= 24.2 ~ "Riesgo medio",
      puntaje_norm_total_extra <= 32.3 ~ "Riesgo alto",
      TRUE ~ "Riesgo muy alto"
    )
  )

# ESTRES ----
## DIMENSIONES ---- 

#FALTA CAMBIAR LOS VALORES
### JEFES ----

data <- data %>% mutate(
  clasificacion_Total_estres_FormA = case_when(
    data$forma_cuestionario == "B" ~ NA_character_,
    is.na(puntaje_norm_total_estres) ~ NA_character_,
    puntaje_norm_total_estres <= 7.8 ~ "Sin riesgo o riesgo despreciable",
    puntaje_norm_total_estres <= 12.6 ~ "Riesgo bajo",
    puntaje_norm_total_estres <= 17.7 ~ "Riesgo medio",
    puntaje_norm_total_estres <= 25 ~ "Riesgo alto",
    TRUE ~ "Riesgo muy alto"
  )
)
### TRABAJADORES ----
data <- data %>% mutate(
  clasificacion_Total_estres_FormB = case_when(
    data$forma_cuestionario == "A" ~ NA_character_,
    is.na(puntaje_norm_total_estres) ~ NA_character_,
    puntaje_norm_total_estres <= 6.5 ~ "Sin riesgo o riesgo despreciable",
    puntaje_norm_total_estres <= 11.8 ~ "Riesgo bajo",
    puntaje_norm_total_estres <= 17 ~ "Riesgo medio",
    puntaje_norm_total_estres <= 23.4 ~ "Riesgo alto",
    TRUE ~ "Riesgo muy alto"
  )
)






# =============================================================================
# 8. Del data.frame de trabajo a las columnas de seguimiento.respuestas
# =============================================================================
# El bloque 7 deja las clasificaciones dentro de `data` con el nombre largo del
# diccionario --clasificacion_dim_Caracteristicas.del.liderazgo_FormA-- y la
# Shiny las pide con el nombre corto de la base --clas_dim_a_caracteristicas
# _liderazgo-- (ver el catalogo de R/utils_resultados.R). Sin esta traduccion
# las setenta columnas calculadas se quedan en memoria y a la base solo llegan
# las ocho de identificacion: es el paso que faltaba.

NIVELES_RIESGO <- c("Sin riesgo o riesgo despreciable", "Riesgo bajo",
                    "Riesgo medio", "Riesgo alto", "Riesgo muy alto")

# make.names(etiqueta del diccionario) -> clave de la base. La clave es la de
# RES_DOMS / RES_DIMS / RES_EXTRA en utils_resultados.R: si aqui se cambia una,
# hay que cambiarla alli, y al reves. El nombre largo no sirve como columna
# --Postgres corta los identificadores en 63 bytes y varias etiquetas se pasan.
CLAVE_DOM <- c(
  "Liderazgo.y.relaciones.sociales.en.el.trabajo" = "liderazgo_relaciones_sociales_trabajo",
  "Control.sobre.el.trabajo"                      = "control_trabajo",
  "Demandas.del.trabajo"                          = "demandas_trabajo",
  "Recompensas"                                   = "recompensas")

CLAVE_DIM <- c(
  "Características.del.liderazgo"                     = "caracteristicas_liderazgo",
  "Relaciones.sociales.en.el.trabajo"                 = "relaciones_sociales_trabajo",
  "Retroalimentación.del.desempeño"                   = "retroalimentacion_desempeno",
  "Relación.con.los.colaboradores"                    = "relacion_colaboradores",
  "Claridad.de.rol"                                   = "claridad_rol",
  "Capacitación"                                      = "capacitacion",
  "Participación.y.manejo.del.cambio"                 = "participacion_manejo_cambio",
  "Oportunidades.para.el.uso.y.desarrollo.de.habilidades.y.conocimientos" =
    "oportunidades_uso_desarrollo_habilidades",
  "Control.y.autonomía.sobre.el.trabajo"              = "control_autonomia_trabajo",
  "Demandas.ambientales.y.de.esfuerzo.físico"         = "demandas_ambientales_esfuerzo_fisico",
  "Demandas.emocionales"                              = "demandas_emocionales",
  "Demandas.cuantitativas"                            = "demandas_cuantitativas",
  "Influencia.del.trabajo.sobre.el.entorno.extralaboral" =
    "influencia_trabajo_entorno_extralaboral",
  "Demandas.de.carga.mental"                          = "demandas_carga_mental",
  "Demandas.de.la.jornada.de.trabajo"                 = "demandas_jornada_trabajo",
  "Exigencias.de.responsabilidad.del.cargo"           = "exigencias_responsabilidad_cargo",
  "Consistencia.del.rol"                              = "consistencia_rol",
  "Recompensas.derivadas.de.la.pertenencia.a.la.organización.y.del.trabajo.que.se.realiza" =
    "recompensas_derivadas_pertenencia_organizacion",
  "Reconocimiento.y.compensación"                     = "reconocimiento_compensacion")

# Las tres dimensiones que solo existen en la forma A: el diccionario de la B
# no las trae, asi que el bloque de la B tiene 16 columnas y el de la A, 19.
SOLO_A <- c("Relación.con.los.colaboradores",
            "Exigencias.de.responsabilidad.del.cargo",
            "Consistencia.del.rol")

CLAVE_EX <- c(
  "Balance.entre.la.vida.laboral.y.familiar"             = "balance_vida_laboral_familiar",
  "Relaciones.familiares"                                = "relaciones_familiares",
  "Comunicación.y.relaciones.interpersonales"            = "comunicacion_relaciones_interpersonales",
  "Situación.económica.del.grupo.familiar"               = "situacion_economica_grupo_familiar",
  "Características.de.la.vivienda.y.de.su.entorno"       = "caracteristicas_vivienda_entorno",
  "Influencia.del.entorno.extralaboral.sobre.el.trabajo" = "influencia_entorno_extralaboral_trabajo",
  "Desplazamiento.vivienda...trabajo...vivienda"         = "desplazamiento_vivienda_trabajo_vivienda")

# columna de la base -> columna(s) de `data` de donde sale.
#
# Intralaboral: una columna por forma, porque A y B son instrumentos distintos
# con baremos distintos y la Shiny los cuenta por separado (quien contesto la B
# tiene NA en todas las columnas de la A, y eso es lo que hace que cada bloque
# se cuente sobre su propia poblacion).
#
# Extralaboral y estres: UNA sola columna, aunque el bloque 7 las clasifique dos
# veces. El cuestionario es el mismo para todos y solo cambia el baremo --jefes
# contra trabajadores--, asi que el nivel resultante es una sola medida; cada
# persona tiene lleno unicamente el calculo de su forma y el otro es NA.
origen <- list()

for (f in c("A", "B")) {
  fl      <- tolower(f)
  dims_f  <- if (f == "A") names(CLAVE_DIM) else setdiff(names(CLAVE_DIM), SOLO_A)

  for (d in dims_f)
    origen[[sprintf("clas_dim_%s_%s", fl, CLAVE_DIM[[d]])]] <-
      sprintf("clasificacion_dim_%s_Form%s", d, f)

  for (d in names(CLAVE_DOM))
    origen[[sprintf("clas_dom_%s_%s", fl, CLAVE_DOM[[d]])]] <-
      sprintf("clasificacion_dom_%s_Form%s", d, f)

  origen[[sprintf("clas_total_intra_%s", fl)]] <-
    sprintf("clasificacion_total_Form%s", f)
  origen[[sprintf("clas_total_intraextra_%s", fl)]] <-
    sprintf("clasificacion_total_intra_extra_Form%s", f)
}

for (d in names(CLAVE_EX))
  origen[[sprintf("clas_dim_ex_%s", CLAVE_EX[[d]])]] <-
    sprintf("clasificacion_%s_extra_Form%s", d, c("A", "B"))

origen[["clas_total_extra"]]  <- paste0("clasificacion_total_extra_Form",  c("A", "B"))
origen[["clas_total_estres"]] <- paste0("clasificacion_Total_estres_Form", c("A", "B"))

cols_bd <- names(origen)

# Un nombre mal escrito en los mapas de arriba, o una etiqueta cambiada en un
# .xlsx, dejaria la columna en NA sin decir nada: la Shiny la mostraria como un
# grupo sin datos y no habria por donde saber que falto. Se para antes.
faltantes <- setdiff(unlist(origen, use.names = FALSE), names(data))
if (length(faltantes))
  stop("faltan en `data` estas columnas de clasificacion:\n  ",
       paste(faltantes, collapse = "\n  "))

# Junta los origenes de una columna: el primero que no sea NA. Con un solo
# origen es una copia; con dos --extralaboral y estres-- toma el calculo de la
# forma que la persona contesto, porque el de la otra forma vale NA.
unir <- function(cols) {
  v <- as.character(data[[cols[1]]])
  for (k in cols[-1]) {
    otro <- as.character(data[[k]])
    v <- ifelse(is.na(v), otro, v)
  }
  v
}

clasificaciones <- lapply(origen, unir)

# La columna es del tipo ENUM nivel_riesgo: un nivel mal escrito lo rechazaria
# Postgres a mitad del COPY, con la tabla ya borrada. Se revisa aqui.
raros <- setdiff(unique(unlist(clasificaciones, use.names = FALSE)), c(NIVELES_RIESGO, NA))
if (length(raros))
  stop("niveles que no estan en el tipo nivel_riesgo: ",
       paste(sprintf("'%s'", raros), collapse = ", "))



# --- caracterizacion que trae el formulario -----------------------------------
# La ficha de datos generales y la de datos ocupacionales de la Bateria. Hasta
# ahora la Shiny las leia uniendo con seguimiento.respuestas_odk en cada
# consulta (ver res_datos() en R/utils_resultados.R); guardarlas aqui deja la
# tabla de resultados completa por si sola.
#
# NO se copian `nombre`, `cedula`, `cal_nombre`, `cal_naci`, `cal_sexo` ni
# `deviceid`: son identificadores directos y esta tabla es la anonimizada, la
# que se cruza por id_anonimizado. Tampoco `ocupacion`, que es la misma columna
# que `cargo` fila por fila.
#
# Se guarda la ETIQUETA, no el codigo de ODK. La tabla ya guarda las
# clasificaciones en texto y no en numero, y asi una consulta suelta contra la
# base se lee sin tener que ir al XLSForm a buscar que significa un 3.

# El 3 (no binario) se agrego al formulario despues del primer despliegue.
ETQ_SEXO <- c("1" = "Masculino", "2" = "Femenino", "3" = "No binario")

ETQ_ESTADO_CIVIL <- c(
  "1" = "Soltero (a)",   "2" = "Casado (a)",  "3" = "Unión libre",
  "4" = "Separado (a)",  "5" = "Divorciado (a)", "6" = "Viudo (a)",
  "7" = "Sacerdote / Monja")

ETQ_NIVEL_ACAD <- c(
  "0" = "Ninguno", "1" = "Primaria incompleta", "2" = "Primaria completa",
  "3" = "Bachillerato incompleto", "4" = "Bachillerato completo",
  "5" = "Técnico / tecnológico incompleto", "6" = "Técnico / tecnológico completo",
  "7" = "Profesional incompleto", "8" = "Profesional completo",
  "9" = "Carrera militar / policía", "10" = "Post-grado incompleto",
  "11" = "Post-grado completo")

# El 0 es finca y el 9 es "no se": son respuestas, no vacios, y por eso se
# guardan como categoria propia en vez de volverlas NULL.
ETQ_ESTRATO <- c(
  "1" = "Estrato 1", "2" = "Estrato 2", "3" = "Estrato 3",
  "4" = "Estrato 4", "5" = "Estrato 5", "6" = "Estrato 6",
  "0" = "Finca",     "9" = "No sé")

ETQ_VIVIENDA <- c("1" = "Propia", "2" = "En arriendo", "3" = "Familiar")

# ETQ_TIPO_CARGO <- c(
#   "1" = "Jefatura - tiene personal a cargo",
#   "2" = "Profesional, analista, técnico, tecnólogo",
#   "3" = "Auxiliar, asistente administrativo, asistente técnico",
#   "4" = "Operario, operador, ayudante, servicios generales")
# 
# ETQ_TIPO_CONTRATO <- c(
#   "1" = "Temporal de menos de 1 año", "2" = "Temporal de 1 año o más",
#   "3" = "Término indefinido",         "4" = "Cooperado (cooperativa)",
#   "5" = "Prestación de servicios",    "6" = "No sé")

ETQ_TIPO_SALARIO <- c(
  "1" = "Fijo (diario, semanal, quincenal o mensual)",
  "2" = "Una parte fija y otra variable",
  "3" = "Todo variable (a destajo, por producción, por comisión)")

# Un codigo que no este en la lista devuelve NA en vez de romper; la guarda de
# mas abajo avisa si eso pasa, porque significa que el XLSForm cambio.
etq <- function(x, mapa) unname(mapa[as.character(x)])

# Los anos de antiguedad vienen partidos en dos preguntas: `anos_lab` dice si
# lleva menos de un ano (1) o mas (2), y solo en el segundo caso se pregunta el
# numero en `anos_lab_num`. Se juntan en una sola cifra, con 0 = menos de un
# ano. Igual para el cargo.
anos_de <- function(sel, num) ifelse(sel %in% 1, 0L, as.integer(num))

socio <- data.frame(
  # ficha de datos generales
  sexo            = etq(data$sexo, ETQ_SEXO),
  nacimiento      = as.Date(data$nacimiento),
  edad_anios      = as.integer(floor(as.numeric(
                      difftime(as.Date(data$submission_date),
                               as.Date(data$nacimiento), units = "days")) / 365.25)),
  estado_civil    = etq(data$estado_civil,    ETQ_ESTADO_CIVIL),
  nivel_academico = etq(data$nivel_academico, ETQ_NIVEL_ACAD),
  estrato         = etq(data$estrato,         ETQ_ESTRATO),
  vivienda        = etq(data$vivienda,        ETQ_VIVIENDA),
  dependientes    = as.integer(data$dependientes),
  departamento    = data$departamento,
  ciudad          = data$ciudad,

  # ficha de datos ocupacionales
  departamento_lab = data$departamento_lab,
  ciudad_lab       = data$ciudad_lab,
  anos_empresa     = anos_de(data$anos_lab,   data$anos_lab_num),
  cargo            = data$cargo,
  #tipo_cargo       = etq(data$tipo_cargo,     ETQ_TIPO_CARGO),
  anos_cargo       = anos_de(data$anos_cargo, data$anos_cargo_num),
  area             = data$area,
  #tipo_contrato    = etq(data$tipo_contrato,  ETQ_TIPO_CONTRATO),
  horas_diarias    = as.integer(data$horas),
  tipo_salario     = etq(data$tipo_salario,   ETQ_TIPO_SALARIO),

  stringsAsFactors = FALSE)

# Tipo de cada una para el CREATE TABLE del bloque 9.
TIPO_SOCIO <- c(
  sexo = "text",
  nacimiento = "date",
  edad_anios = "int",
  estado_civil = "text",
  nivel_academico = "text",
  estrato = "text",
  vivienda = "text",
  dependientes = "int",
  departamento = "text",
  ciudad = "text",
  departamento_lab = "text",
  ciudad_lab = "text",
  anos_empresa = "int",
  cargo = "text",
  #tipo_cargo = "text",
  anos_cargo = "int",
  area = "text",
  #tipo_contrato = "text",
  horas_diarias = "int",
  tipo_salario = "text")

stopifnot(setequal(names(socio), names(TIPO_SOCIO)))
cols_socio <- names(socio)

# Si el XLSForm agrega una opcion y aqui no se refleja, etq() la vuelve NA en
# silencio y el cruce pierde gente sin decir nada. Se compara el numero de
# vacios de la columna traducida contra el de la original.
for (v in c(sexo = "sexo", estado_civil = "estado_civil",
            nivel_academico = "nivel_academico", estrato = "estrato",
            vivienda = "vivienda", tipo_salario = "tipo_salario")) {
  perdidos <- sum(is.na(socio[[v]])) - sum(is.na(data[[v]]))
  if (perdidos > 0)
    stop(sprintf("%s: %d codigos sin etiqueta (%s). Revisar la lista del XLSForm.",
                 v, perdidos,
                 paste(sort(unique(data[[v]][is.na(socio[[v]]) & !is.na(data[[v]])])),
                       collapse = ", ")))
}


# --- el data.frame que se escribe --------------------------------------------
#   1 clave               text          KEY del envio en ODK
#   2 id_anonimizado      text          persona del marco
#   3 submission_date     timestamptz   momento del envio
#   4 inicio              timestamptz
#   5 fin                 timestamptz
#   6 duracion_min        numeric
#   7 forma_cuestionario  text          A o B
#   8 completa            boolean       calculada en el bloque 6
#   9 acepta              boolean       consentimiento informado del formulario
#  10 encuestados         boolean       siempre TRUE (ver mas abajo)
#  11 resultado_final_persona smallint  1 = encuesta efectiva, 2 = no efectiva
#  12+ caracterizacion    text/int/date las de `cols_socio`, del formulario
#     + clas_*            nivel_riesgo  las de `cols_bd`
# Las siete primeras salen tal cual de la base original.

# --- consentimiento -----------------------------------------------------------
# `consentimiento` es el select_one `yn` del XLSForm --"Acepto participar en esta
# encuesta"-- con 1 = Si y 2 = No. Se guarda como booleano y no como etiqueta,
# igual que `completa`: es un si/no, no una lista de opciones.
#
# Viene aqui y no se deja en seguimiento.respuestas_odk por la misma razon que la
# caracterizacion: que la Shiny no tenga que unir con la tabla cruda en cada
# consulta.
#
# Quien marca "No" SI envio formulario y sigue contando como encuestado --el
# indicador mide envios recibidos-- pero no hizo la encuesta: la lista de
# personas del seguimiento lo separa como rechazo (ver seg_personas()).
#
# Un codigo que no este en la lista se detiene aqui y no se traduce en silencio,
# igual que las etiquetas de la caracterizacion: un 3 convertido en NA seria una
# persona que dejaria de aparecer como rechazo sin que nadie se entere.
raros_cons <- setdiff(unique(stats::na.omit(data$consentimiento)), c(1, 2))
if (length(raros_cons))
  stop("consentimiento con codigos que no estan en la lista yn (1 = Si, 2 = No): ",
       paste(sort(raros_cons), collapse = ", "))

acepta <- data$consentimiento == 1

respuestas <- data.frame(
  clave              = data$clave,
  id_anonimizado     = data$id_anonimizado,
  submission_date    = data$submission_date,
  inicio             = data$inicio,
  fin                = data$fin,
  duracion_min       = data$duracion_min,
  forma_cuestionario = data$forma_cuestionario,
  completa           = completa,
  acepta             = acepta,

  # --- desenlace de la persona ------------------------------------------------
  # Las dos variables pedidas, en la tabla que se pidio. OJO CON LO QUE PUEDEN
  # decir aqui: esta tabla tiene una fila por ENVIO y solo contiene a quien
  # respondio, asi que cada fila es, por definicion, alguien encuestado.
  #
  #   encuestados              TRUE en TODAS las filas. No hay otra cosa que
  #                            pueda valer: tener fila aqui ES haber enviado.
  #   resultado_final_persona  solo puede ser 1 o 2, que son las dos categorias
  #                            que exigen un envio.
  #
  # Las otras cuatro --3 rechazo insistente, 4 rechazo ausente, 5 pendiente,
  # 6 agendado hoy-- piden justamente que la persona NO tenga envio, y esas
  # personas (hoy 1.727 de 3.357) no tienen fila en esta tabla. Para verlas hay
  # que ir a seguimiento.estado_persona, que sale del marco.
  #
  # Se calculan aqui y no con un UPDATE posterior porque salen de la MISMA fila
  # --de `acepta`-- y no de ninguna otra tabla: asi no pueden quedar
  # desactualizadas, ni siquiera entre una carga y la siguiente.
  encuestados        = TRUE,
  resultado_final_persona = ifelse(acepta %in% TRUE, 1L, 2L),

  stringsAsFactors   = FALSE)

respuestas_bd <- cbind(
  respuestas,
  socio,
  stats::setNames(as.data.frame(clasificaciones, stringsAsFactors = FALSE,
                                check.names = FALSE),
                  cols_bd))


# =============================================================================
# 9. Reescribir seguimiento.respuestas
# =============================================================================
# Se borra y se vuelve a crear con las ocho columnas de arriba, para que la
# tabla no arrastre columnas viejas si el data.frame cambia de forma.
#
# Todo va dentro de una transaccion. Si algo falla a mitad, R se detiene sin
# llegar al COMMIT y Postgres deshace el DROP al cerrar la conexion: la tabla
# que consulta la Shiny queda como estaba. Nada se ve afuera hasta el COMMIT.
#
# seguimiento.marco y seguimiento.metas no se tocan (las metas son lo que edita
# el usuario en la app).

# El DROP toma un lock exclusivo sobre la tabla que la Shiny esta consultando, y
# ese lock no se suelta hasta que la transaccion termine. Si algo revienta entre
# el BEGIN y el COMMIT sin este tryCatch, la transaccion queda abierta y la app
# se queda esperando hasta que alguien mate el proceso de R. Aqui se deshace en
# el momento, se cierra la conexion y se corta con un mensaje que dice que la
# tabla quedo intacta.
invisible(tryCatch({

bd_exec("BEGIN")

# seguimiento.estado_persona es una VISTA que cuelga de esta tabla (ver
# seg_crear_vista_estado() en R/utils_seguimiento.R), y Postgres no deja soltar
# una tabla con dependientes: sin esta linea el DROP de abajo falla y la carga
# entera se detiene. Se borra aqui, explicitamente y dentro de la misma
# transaccion, en vez de poner CASCADE: CASCADE se llevaria por delante
# cualquier otra vista que alguien haya creado sobre `respuestas` sin decirlo.
# Se vuelve a crear mas abajo, dentro de esta misma transaccion: quien consulte
# la base mientras corre la carga nunca ve la vista desaparecida.
bd_exec("DROP VIEW IF EXISTS seguimiento.estado_persona")

bd_exec("DROP TABLE IF EXISTS public.respuestas_procesadas")

# El tipo guarda el orden de los cinco niveles, asi que ORDER BY y las
# comparaciones (>= 'Riesgo alto') salen bien sin tabla de apoyo. CREATE TYPE no
# admite IF NOT EXISTS y el DROP TABLE no se lleva el tipo, de ahi el bloque DO.
bd_exec(sprintf("
  DO $$ BEGIN
    CREATE TYPE nivel_riesgo AS ENUM (%s);
  EXCEPTION WHEN duplicate_object THEN NULL;
  END $$;", paste(sprintf("'%s'", NIVELES_RIESGO), collapse = ", ")))

bd_exec(sprintf("
  CREATE TABLE public.respuestas_procesadas (
    clave              text PRIMARY KEY,
    id_anonimizado     text,
    submission_date    timestamptz,
    inicio             timestamptz,
    fin                timestamptz,
    duracion_min       numeric,
    forma_cuestionario text,
    completa           boolean,
    acepta             boolean,
    encuestados        boolean,
    resultado_final_persona smallint,
    %s,
    %s
  )",
  paste(paste(cols_socio, TIPO_SOCIO[cols_socio]), collapse = ",\n    "),
  paste(paste(cols_bd, "nivel_riesgo"),            collapse = ",\n    ")))

DBI::dbAppendTable(con, DBI::Id(schema = "public", table = "respuestas_procesadas"),
                   respuestas_bd)

# R escribe los double con toda su precision y numeric los guarda tal cual, asi
# que 54.6 quedaria como 54.600000000000001. Se redondea del lado de la base.
bd_exec("UPDATE public.respuestas_procesadas SET duracion_min = round(duracion_min, 1)")

# La app cruza respuestas con marco por id_anonimizado en cada consulta.
bd_exec("CREATE INDEX idx_resp_id ON public.respuestas_procesadas (id_anonimizado)")

# La vista que se borro arriba. Se usa la MISMA definicion de la app
# (seg_crear_vista_estado() en R/utils_seguimiento.R) para no tener dos copias
# del SQL que se puedan desalinear. Ese archivo habla con la base por
# db_get()/db_exec() --el pool de la app--, asi que se carga en un entorno
# aparte donde esas dos funciones apuntan a la conexion de este script, que es
# la que tiene abierta la transaccion.
vista <- new.env()
vista$db_get  <- bd_get
vista$db_exec <- bd_exec
sys.source("R/utils_seguimiento.R", envir = vista, keep.source = FALSE)
if (!isTRUE(vista$seg_crear_vista_estado())) {
  cat("AVISO: seguimiento.estado_persona no se creo (faltan seguimiento.contactos",
      "o seguimiento.citaciones); la app la creara al arrancar.\n")
}

bd_exec("COMMIT")

}, error = function(e) {
  try(bd_exec("ROLLBACK"), silent = TRUE)
  bd_cerrar()
  stop("seguimiento.respuestas NO se reescribio y quedo como estaba: ",
       conditionMessage(e), call. = FALSE)
}))

cat(sprintf("public.respuestas_procesadas reescrita: %s filas, %s completas, %s sin consentimiento, %s columnas de caracterizacion, %s de clasificacion\n",
            nrow(respuestas), sum(respuestas$completa),
            sum(!respuestas$acepta, na.rm = TRUE),
            length(cols_socio), length(cols_bd)))

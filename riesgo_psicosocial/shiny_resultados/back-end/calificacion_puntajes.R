setwd(dirname(rstudioapi::getActiveDocumentContext()$path))
freshr::freshr()

# Cálculo de puntajes brutos y normalizados --------

library(magrittr)
library(tidyverse)
library(readxl)
library(dplyr)
library(stringr)

#lectura de simulación de las respuestas
data <-
  read.csv("Simulacion_respuestas_ODK.csv")

#lectura de las preguntas por encuesta 
DimilA <- read_excel("FormAintralaboral.xlsx", sheet = 1)
DimilB <- read_excel("FormBintralaboral.xlsx", sheet = 1)
DimiExtra <- read_excel("Formextralaboral.xlsx", sheet = 1)
DimiEstres <- read_excel("Formestres.xlsx", sheet = 1)

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
cal_pun_normalizados <- function(datos, archivo_excel = "FormAintralaboral.xlsx", sufijo = "") {

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

  # Estrés: ee_*
  preguntas_ee <- grep("^ee_p", names(datos), value = TRUE)
  if (length(preguntas_ee) > 0) {
    datos$puntaje_bruto_total_estres <- rowSums(
      datos[, preguntas_ee, drop = FALSE],
      na.rm = TRUE
    )
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
cal_pun_total_normalizados <- function(datos, archivo_A = "FormAintralaboral.xlsx",
                                       archivo_B = "FormBintralaboral.xlsx",
                                       archivo_extra = "Formextralaboral.xlsx",
                                       archivo_estres = "Formestres.xlsx") {

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
data <- cal_pun_normalizados(data, archivo_excel = "FormAintralaboral.xlsx", sufijo = "FormA")

# Procesar Formulario B
data <- cal_pun_brutos(data, DimilB, sufijo = "FormB")
data <- cal_pun_normalizados(data, archivo_excel = "FormBintralaboral.xlsx", sufijo = "FormB")

# Procesar Formulario extralaboral
data <- cal_pun_brutos(data, DimiExtra, sufijo = "extra")
data <- cal_pun_normalizados(data, archivo_excel = "Formextralaboral.xlsx", sufijo = "extra")

# Procesar Formulario estrés
data <- cal_pun_brutos(data, DimiEstres, sufijo = "estres")
data <- cal_pun_normalizados(data, archivo_excel = "Formestres.xlsx", sufijo = "estres")

# Calcular puntajes totales brutos
data <- cal_pun_bruto_total(data)

# Calcular puntajes totales normalizados
data <- cal_pun_total_normalizados(data)

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
  "Relación.con.los.colaboradores_FormA" = c(13.9, 26.0, 33.3, 47.2),
  "Claridad.de.rol_FormA" = c(0.9, 10.7, 21.4, 39.3),
  "Capacitación_FormA" = c(0.9, 16.7, 33.3, 50.0),
  "Participación.y.manejo.del.cambio_FormA" = c(12.5, 25.0, 37.5, 50.0),
  "Oportunidades.para.el.uso.y.desarrollo.de.habilidades.y.conocimientos_FormA" = c(0.9, 6.3, 18.8, 31.3),
  "Control.y.autonomía.sobre.el.trabajo_FormA" = c(8.3, 25.0, 41.7, 58.3),
  "Demandas.ambientales.y.de.esfuerzo.físico_FormA" = c(14.6, 22.9, 31.3, 39.6),
  "Demandas.emocionales_FormA" = c(16.7, 25.0, 33.3, 47.2),
  "Demandas.cuantitativas_FormA" = c(25.0, 33.3, 43.8, 54.2),
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
data %>% select(contains("puntaje_norm_dom")) %>% names()

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
data %>% select(contains("puntaje_norm_dim")) %>% names()

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
data %>% select(contains("puntaje_norm_dom")) %>% names()

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
data %>%
  select(matches("^puntaje_norm_dim.*_FormA")) %>% names()

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
data %>%
  select(matches("^puntaje_norm.*_extra$")) %>% names()

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

# CLASIFICACIÓN ESTRES ----
## DIMENSIONES ---- 

#FALTA CAMBIAR LOS VALORES
### JEFES ----
data %>% select(contains("estres")) %>% names()

data <- data %>% mutate(
  clasificacion_Total_estres_FormA = case_when(
    data$forma_cuestionario == "B" ~ NA_character_,
    is.na(puntaje_norm_dim_Total_estres) ~ NA_character_,
    puntaje_norm_dim_Total_estres <= 7.8 ~ "Sin riesgo o riesgo despreciable",
    puntaje_norm_dim_Total_estres <= 12.6 ~ "Riesgo bajo",
    puntaje_norm_dim_Total_estres <= 17.7 ~ "Riesgo medio",
    puntaje_norm_dim_Total_estres <= 25 ~ "Riesgo alto",
    TRUE ~ "Riesgo muy alto"
  )
)
### TRABAJADORES ----
data <- data %>% mutate(
  clasificacion_Total_estres_FormB = case_when(
    data$forma_cuestionario == "A" ~ NA_character_,
    is.na(puntaje_norm_dim_Total_estres) ~ NA_character_,
    puntaje_norm_dim_Total_estres <= 6.5 ~ "Sin riesgo o riesgo despreciable",
    puntaje_norm_dim_Total_estres <= 11.8 ~ "Riesgo bajo",
    puntaje_norm_dim_Total_estres <= 17 ~ "Riesgo medio",
    puntaje_norm_dim_Total_estres <= 23.4 ~ "Riesgo alto",
    TRUE ~ "Riesgo muy alto"
  )
)


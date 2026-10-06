
setwd(dirname(rstudioapi::getActiveDocumentContext()$path))

# función across: sirve para aplicar una función a múltiples columnas 

#across(columnas, función)

library(dplyr)

df <- data.frame(
  nombre = c("Juan", "María"),
  peso = c(75.345, 62.890),
  altura = c(1.785, 1.650)
)

df
df |> class()

# Sin across (repetitivo - ❌ MALO)
df %>%
  mutate(peso = round(peso, 2),
         altura = round(altura, 2))

# Con across (limpio - ✅ BUENO)
df %>%
  mutate(across(c(peso, altura), round, digits = 2))

# O seleccionar por tipo
df %>%
  mutate(across(where(is.numeric), round, digits = 2))

# por ejemplo aplicar varias funciones a la vez
df %>%
  summarise(across(c(peso, altura),
                   list(media = mean,
                        desv_est = sd,
                        min = min,
                        max = max)))

# Resultado:
# peso_media  peso_desv_est  peso_min  peso_max  altura_media ...

# Nota: mutate + across crea columnas nuevas
# y mutate + summarise crea columnas de resúmen, reduce a 1 fila, es como un group by


# Dataset de ventas por tienda y mes
ventas <- data.frame(
  tienda = c("A", "A", "B", "B", "C", "C"),
  mes = c("Ene", "Feb", "Ene", "Feb", "Ene", "Feb"),
  ingresos = c(5000, 6000, 7000, 8000, 4000, 5000),
  gastos = c(2000, 2500, 3000, 3500, 1800, 2200)
)

# Resumen total por tienda
ventas %>%
  group_by(tienda) %>%
  summarise(across(c(ingresos, gastos),
                   list(total = sum,
                        promedio = mean)))

# Resultado:
#   tienda  ingresos_total  ingresos_promedio  gastos_total  gastos_promedio
# 1 A              11000              5500           4500              2250
# 2 B              15000              7500           6500              3250
# 3 C               9000              4500           4000              2000









data %>% dim()
data %>% names()

data %>% 
  filter(
    forma_cuestionario == "B"
  ) %>% 
  count(puntaje_bruto_total_FormA)





data %>%
  select(matches("^puntaje_norm_dom.*_FormA")) %>% names()
data %>%
  select(matches("^clasificacion_dom.*_FormA")) %>% names()

data %>%
  select(matches("^puntaje_norm_dom.*_FormB")) %>% names()
data %>%
  select(matches("^clasificacion_dom.*_FormB")) %>% names()

data %>%
  select(matches("*_FormB")) %>% names()

data %>%
  select(contains("Balance.entre.la.vida.laboral.y.familiar_extra")) %>% names()

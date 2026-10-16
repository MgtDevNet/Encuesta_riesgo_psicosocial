library(tidyverse)
library(httr)

# Credenciales desde el .Renviron de la carpeta del script
readRenviron(r"(\\wsl.localhost\Ubuntu\home\mgtdev\trabajo\riesgo_psicosocial\descarga_datos_reales\.Renviron)")
usr <- Sys.getenv("ODK_USER")
psw <- Sys.getenv("ODK_PASSWORD")
url_odk <- Sys.getenv("ODK_URL")
#ODK_URL=https://roman-april-gigahertz.ngrok-free.dev/v1/projects/1

# Misma función de aplanado del script
unnest_all <- function(df) {
  x <- df %>% sapply(typeof)
  while (any(x == "list")) {
    df <- df %>%
      unnest_wider(where(is.list), names_repair = "unique_quiet") %>%
      select(-matches("^ejemplo"))
    x <- df %>% sapply(typeof)
  }
  df
}



# Descarga completa: sin filtro de fecha, solo excluye rechazados
url <- paste0(
  url_odk,"/forms/riesgo_psicosocial.svc/Submissions",
  "?$filter=__system/reviewState%20ne%20'rejected'"
)

response <- httr::RETRY("GET", url, times = 3, httr::authenticate(usr, psw))
httr::stop_for_status(response)

# JSON tal cual llega (lista anidada)
json_crudo <- httr::content(response)

# Aplanado a una fila por envío, sin más transformaciones
odk <- json_crudo %>%
  unlist(recursive = FALSE) %>%
  enframe() %>%
  filter(name != "@odata.context") %>%
  unnest_wider(value, names_repair = "unique") %>%
  select(-name) %>%
  unnest_all()

# ¿Existe la columna y cuántos vacíos tiene?
"cedula" %in% names(odk)
sum(is.na(odk$cedula))

# Ver los valores junto al ID del envío
odk %>% select(`__id`, cedula, cal_nombre, cal_sexo)

odk %>% count(cedula)

odk %>% View()

 # El primer envío exactamente como lo manda ODK, antes de aplanar
str(json_crudo$value[[1]], max.level = 2)

odk %>% names()
odk %>% select(cedula, empleado_registrado)

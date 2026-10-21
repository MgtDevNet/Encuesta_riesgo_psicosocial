library(googlesheets4)
library(dplyr)

# 1. Desactivar la autenticación interactiva previa
gs4_deauth()

# 2. Autenticar con el archivo JSON de la Cuenta de Servicio
# La llave NO va a git (ver .gitignore): se pasa por fuera, como el .Renviron.
# Su ruta va en el .Renviron de esta carpeta, en la linea
#   GOOGLE_SA_KEY=<ruta completa al archivo .json>
readRenviron("/home/decm/Encuesta_riesgo_psicosocial/riesgo_psicosocial/descarga_datos_reales/.Renviron")
llave_google <- Sys.getenv("GOOGLE_SA_KEY")
if (!nzchar(llave_google) || !file.exists(llave_google)) {
  stop("Falta GOOGLE_SA_KEY en el .Renviron, o el archivo no existe: '", llave_google, "'")
}
gs4_auth(path = llave_google)

# 3. ID de tu Google Sheet (es la cadena larga en la URL entre /d/ y /edit)
# Ejemplo: https://docs.google.com/spreadsheets/d/1A2B3C4D5E6F7G8H9I0J/edit
sheet_id <- "1vKfcjjDbzE7ybtQem4WEd6oOVy6THGbAancw5GTWSIk"

# 4. Leer los datos de la pestaña de respuestas
datos_formulario <- read_sheet(sheet_id, sheet = "Respuestas de formulario 1")

# Visualizar los datos
head(datos_formulario)

View(datos_formulario)

# 
# Campus 
# Tipo de pregunta
# 1.
# Ciudad Universitaria
# 2.
# Ciudadela Universitaria de Robledo
# 3.
# Área de la Salud
# 4.
# Seccional Oriente
# 5.
# Seccional Urabá
# 6.
# Seccional Bajo Cauca
# 7.
# Seccional Magdalena Medio
# 8.
# Seccional Suroeste
# 9.
# Seccional Occidente

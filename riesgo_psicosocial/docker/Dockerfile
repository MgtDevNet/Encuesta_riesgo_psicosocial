# Usa una imagen con más dependencias preinstaladas (R + tidyverse)
# Version FIJA de R (4.6.1), la misma con la que se probo la app: con `latest`
# un servidor nuevo podria construir con otro R y otros paquetes.
FROM rocker/tidyverse:4.6.1

# Establece el directorio de trabajo
WORKDIR /app

# Instala Shiny y librerías adicionales necesarias
RUN R --slave -e 'install.packages(c("shiny", "pool", "scrypt"), repos="https://cloud.r-project.org")'

# Instala librerías que no vienen en rocker/tidyverse
# (tidyverse, dplyr, readxl, stringr, magrittr ya están incluidas)
RUN R --slave -e '\
    install.packages(c(\
        "bslib",\
        "DBI",\
        "RPostgres",\
        "stringi",\
        "officer",\
        "flextable",\
        "writexl"\
    ), repos="https://cloud.r-project.org")\
    '

# Copia tu aplicación Shiny a la carpeta /app
# La ruta relativa es desde el contexto de build (la carpeta docker/)
# Así que .. sube un nivel hasta riesgo_psicosocial
COPY shiny_resultados/Shiny_seguimiento_nuevo/Shiny_seguimiento /app

# Expone el puerto 7788 (donde corre tu Shiny)
EXPOSE 7788

# Comando para ejecutar la app Shiny
# Escucha en 0.0.0.0:7788 (accesible desde afuera del contenedor)
CMD ["R", "--slave", "-e", "shiny::runApp('/app', port = 7788, host = '0.0.0.0')"]

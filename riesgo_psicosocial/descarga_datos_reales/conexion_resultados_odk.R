library(tidyverse)
library(httr)
library(DBI)
library(RPostgres)
library(lubridate)

# 1. Función auxiliar para desanidar listas
unnest_all <- function(df) {
  x <- df %>% sapply(typeof)
  while (any(x == "list")) {
    df <- df %>% 
      unnest_wider(where(is.list), names_repair = "unique_quiet") %>% 
      select(-matches("^ejemplo"))
    x <- df %>% sapply(typeof)
  }
  return(df)
}

# 2. Configuración de variables
# Las credenciales viven en un archivo .Renviron junto a este script (NO se
# versiona). Rscript no lee el .Renviron de la carpeta por su cuenta, asi que
# se busca en la carpeta del script y en el directorio de trabajo.
args_file   <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
dir_script  <- if (length(args_file) == 1) dirname(normalizePath(args_file)) else getwd()

# Las PG_* que ya trae el entorno mandan sobre las del archivo. Dentro del
# contenedor de la Shiny (como lo corre actualizar_datos.sh) docker-compose.yml
# define PG_HOST=postgres, y el PG_HOST=localhost del .Renviron --pensado para
# correr en WSL-- lo pisaria: dentro del contenedor, localhost es el propio
# contenedor y no la base. Fuera de Docker no hay PG_* en el entorno y se usa
# el archivo como siempre.
pg_entorno <- Sys.getenv(c("PG_HOST", "PG_PORT", "PG_DB", "PG_USER", "PG_PASSWORD"),
                         unset = NA)
for (f in unique(c(file.path(dir_script, ".Renviron"), ".Renviron"))) {
  if (file.exists(f)) readRenviron(f)
}
pg_entorno <- pg_entorno[!is.na(pg_entorno)]
if (length(pg_entorno)) do.call(Sys.setenv, as.list(pg_entorno))

usr <- Sys.getenv("ODK_USER")
psw <- Sys.getenv("ODK_PASSWORD")
if (usr == "" || psw == "") {
  stop("Faltan ODK_USER y/o ODK_PASSWORD. Definalas en ", file.path(dir_script, ".Renviron"))
}
# La tabla depende de la etapa de la encuesta (ETAPA en docker/.env, que
# docker-compose pasa al contenedor): odk_respuestas_piloto u
# odk_respuestas_reales. conectar_bd.R y la Shiny usan la misma regla.
etapa <- tolower(trimws(Sys.getenv("ETAPA")))
if (!nzchar(etapa)) etapa <- "piloto"
if (!etapa %in% c("piloto", "reales")) {
  stop("ETAPA debe ser 'piloto' o 'reales' (esta en '", etapa, "').")
}
tabla_db <- paste0("odk_respuestas_", etapa)

# Llave unica de cada envio de ODK (el instanceID, que llega como `__id`).
# En la tabla queda en la columna clave; ver el select() mas abajo.
col_id <- "clave"



# Codigo de salida del script, para quien lo llame (actualizar_datos.sh):
#    0 = corrio bien y no habia envios nuevos
#   10 = corrio bien e inserto envios nuevos -> hay que recalificar
#    1 = fallo
# Asi el que lo programa decide si corre conectar_bd.R sin tener que leer el log.
estado_salida <- 0L

# 3. Bloque Principal con Manejo de Errores y Control Anti-Duplicados
tryCatch({

  # Conexión a PostgreSQL
  con <- dbConnect(
    RPostgres::Postgres(),
    host     = Sys.getenv("PG_HOST", "localhost"), # IP/nombre de contenedor si aplica
    port     = as.integer(Sys.getenv("PG_PORT", "5432")),
    dbname   = Sys.getenv("PG_DB", "riesgo_psicosocial"),
    user     = Sys.getenv("PG_USER", "erps_user"),
    password = Sys.getenv("PG_PASSWORD", "123456")
  )
  
  # Asegurar desconexión al finalizar la ejecución
  on.exit(dbDisconnect(con), add = TRUE)
  
  # Verificar si existe la tabla para hacer la descarga incremental por fecha
  filtro_fecha <- ""
  if (dbExistsTable(con, tabla_db)) {
    # La columna en la tabla es submission_date (no "__system/submissionDate":
    # unnest_wider aplana __system sin prefijo y el select() la renombra).
    # El cast a timestamptz sirve tanto si la columna es text (ISO 8601, como la
    # deja mutate_all(as.character)) como si ya es timestamptz, y hace que MAX
    # compare fechas y no texto. Sin tryCatch: si la consulta falla, el script
    # debe detenerse y no bajar todo ODK en silencio.
    query_fecha <- sprintf(
      "SELECT MAX(submission_date::timestamptz) AS max_fecha FROM %s",
      dbQuoteIdentifier(con, tabla_db)
    )
    res_fecha <- dbGetQuery(con, query_fecha)$max_fecha

    if (length(res_fecha) == 1 && !is.na(res_fecha)) {
      # Milisegundos incluidos: ODK guarda submissionDate con ms y, sin ellos,
      # `gt` volveria a traer el ultimo envio (el filtro por ID lo descarta igual).
      fecha_utc <- format(res_fecha, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
      filtro_fecha <- paste0("%20and%20__system/submissionDate%20gt%20", fecha_utc)
    }
  }
  
  # Construir URL y consultar ODK
  # La direccion del PROYECTO en ODK Central viene de ODK_URL en el .Renviron:
  #   ODK_URL=https://roman-april-gigahertz.ngrok-free.dev/v1/projects/1
  # Cuando ngrok cambie de direccion, solo se cambia esa linea. Aqui se le pega
  # la parte fija del formulario. Da igual si ODK_URL termina o no en "/".
  odk_url <- sub("/+$", "", Sys.getenv("ODK_URL"))
  if (!nzchar(odk_url)) {
    stop("Falta ODK_URL en ", file.path(dir_script, ".Renviron"),
         " (ej.: ODK_URL=https://xxxx.ngrok-free.dev/v1/projects/1)")
  }
  url_base <- paste0(odk_url, "/forms/riesgo_psicosocial.svc/Submissions")

  # --- estado_civil en envios ya descargados ---------------------------------
  # estado_civil se quito y volvio al formulario el 2026-10-20. Los envios que
  # ya estaban en la tabla se bajaron sin la columna, y la descarga incremental
  # no los vuelve a pedir. La primera vez que corre este codigo --la tabla no
  # tiene la columna-- se agrega y se llena con lo que ODK tenga de cada envio.
  # Va en una transaccion: si ODK falla a mitad, la columna tampoco queda y se
  # reintenta en la corrida siguiente. Los envios de antes del cambio del
  # formulario no tienen el dato en ODK y quedan vacios.
  if (dbExistsTable(con, tabla_db) &&
      !"estado_civil" %in% dbListFields(con, tabla_db)) {
    resp_ec <- httr::RETRY(
      "GET",
      paste0(url_base, "?$select=__id,general/estado_civil"),
      times = 3,
      httr::authenticate(usr, psw)
    )
    httr::stop_for_status(resp_ec)
    envios_ec <- httr::content(resp_ec)$value
    ec <- tibble(
      clave        = vapply(envios_ec, function(x) x[["__id"]], ""),
      estado_civil = vapply(envios_ec, function(x) {
        v <- x[["general"]][["estado_civil"]]
        if (is.null(v)) NA_character_ else as.character(v)
      }, "")
    ) %>% filter(!is.na(estado_civil))

    dbWithTransaction(con, {
      dbExecute(con, sprintf("ALTER TABLE %s ADD COLUMN estado_civil text",
                             dbQuoteIdentifier(con, tabla_db)))
      if (nrow(ec) > 0) {
        dbWriteTable(con, "tmp_estado_civil", ec, temporary = TRUE)
        n_ec <- dbExecute(con, sprintf(
          "UPDATE %s t SET estado_civil = e.estado_civil
             FROM tmp_estado_civil e WHERE t.clave = e.clave",
          dbQuoteIdentifier(con, tabla_db)))
      } else {
        n_ec <- 0L
      }
    })
    cat(sprintf("[INFO] Columna estado_civil agregada a '%s'; %d envios ya descargados la recibieron de ODK.\n",
                tabla_db, n_ec))
    # respuestas_procesadas no la tiene todavia: hay que recalificar.
    estado_salida <- 10L
  }
  
  url_filtro <- paste0("?$filter=__system/reviewState%20ne%20'rejected'", filtro_fecha)
  
  response <- httr::RETRY(
    "GET", 
    paste0(url_base, url_filtro),
    times = 3, 
    encode = "json",
    httr::authenticate(usr, psw)
  )
  
  # Lanza error explícito si la petición HTTP falla
  httr::stop_for_status(response)
  
  # Procesar datos recibidos
  datos_raw <- httr::content(response) %>% 
    unlist(recursive = FALSE) %>% 
    enframe() %>% 
    filter(name != "@odata.context")
  
  if (nrow(datos_raw) > 0) {
    empleados <- datos_raw %>%
      unnest_wider(value, names_repair = "unique") %>% 
      select(-name) %>% 
      unnest_all() %>% 
      rename(X__id = `__id`) %>% 
      mutate_all(as.character)
    
    marco <- dbGetQuery(con, "SELECT * FROM seguimiento.marco")
    marco %>% names()
    # la variable cédula del odk viene vacia
    marco %>% count(tipo_vinculacion)
    
    
    # unir bases de datos
    aux <- left_join(
      empleados,
      marco,
      by = c("cedula"="id_anonimizado"
             #"cal_nombre" = "nombre",
             
      )
    )
    
    # creación de variables adicionales
    aux <- aux %>%
      mutate(
        duracion_min = round(as.numeric(
          difftime(ymd_hms(endtime), ymd_hms(starttime), units = "mins"))
          ,1),
        sexo.x = 
          case_when(
            sexo.x == "M" ~ 1,
            sexo.x == "F" ~ 2,
            T ~ 3
            
          ),
        form_intra = if_else(forma == "A",1,2),
        # registrados: fecha del marco (numero de serie de Excel);
        # no registrados: ODK solo trae el año, se toma el 1 de julio
        # para que conectar_bd.R pueda calcular la edad con as.Date()
        nacimiento = coalesce(
          as.character(as.Date(as.numeric(fechanacimiento), origin = "1899-12-30")),
          if_else(is.na(nacimiento), NA_character_, paste0(nacimiento, "-07-01"))
        )
      )
    
    # selección de variables. 
    empleados <- aux %>%
      select(
        "nombre" = nombre.x, # VERIFICADO ESTA EN ODK
        
        tipo_vinculacion, # VERIFICADO. MARCO MUESTRAL
        # HAY QUE LLENAR ESTE DESDE SHINY CON CATEGORÍAS
        
        "sexo" = sexo.x, # 1 es Masculina y 2 es femenino VERIFICADO
        # ojo ahora se agrego no binario y es 3. ESTA EN ODK
        
        #cal_sexo, # NA EN NO REGISTRADOS
        
        #cal_naci, # NA EN NO REGISTRADOS
        
        consentimiento, #
        # 1 es si y 2 es no. VERIFICADO ESTA EN ODK
        
        "submission_date" = submissionDate,  # VERIFICADO ESTA EN ODK
        
        "inicio" = starttime, # VERIFICADO ESTA EN ODK        
        
        "fin" = endtime,      # VERIFICADO ESTA EN ODK   
        
        "duracion_min" = duracion_min,    # VERIFICADO ESTA EN ODK  
        
        "deviceid" = deviceId,          # VERIFICADO ESTA EN ODK
        
        # clave = el ENVIO (instanceID de ODK); id_anonimizado = la PERSONA,
        # el mismo id de seguimiento.marco. Es lo que asumen conectar_bd.R y
        # la Shiny: no invertirlos.
        "clave" = X__id, # ESTA EN ODK

        "id_anonimizado" = cedula, # ESTA EN ODK
        
        
        "dependencia" = dependencia,      # VERIFICADO, MARCO MUESTRAL 
        # HAY QUE LLENARLO DESDE SHINY 
        
        
        
        "nivel_empleo" = nivel_empleo,# VERIFICADO
        # HAY QUE LLENARLO DESDE SHINY
        
        "forma_cuestionario" = forma,# VERIFICADO ESTA EN ODK
        
        nacimiento,  # marco si esta registrado, si no el año de ODK
        # (ver el mutate de arriba)
        
        # Volvio al formulario el 2026-10-20. any_of(): un lote que solo traiga
        # envios de la version vieja del formulario puede no tener la columna,
        # y entonces queda vacia en vez de romper la descarga.
        any_of("estado_civil"),
        # ETQ_ESTADO_CIVIL <- c(
        #   "1" = "Soltero (a)",
        #   "2" = "Casado (a)",
        #   "3" = "Unión libre",
        #   "4" = "Separado (a)",
        #   "5" = "Divorciado (a)",
        #   "6" = "Viudo (a)",
        #   "7" = "Sacerdote / Monja"
        # )
        
        nivel_academico, # VERIFICADO, ESTA EN ODK
        
        ocupacion, # ESTA EN ODK,
        
        "departamento"=departamento,  # ESTA EN ODK   
        "ciudad"=ciudad,       # ESTA EN ODK 
        estrato,      # ESTA EN ODK      
        vivienda,      # ESTA EN ODK  
        dependientes,  # ESTA EN ODK 
        
        #  Preguntas formulario Intralaboral Forma B    
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
        ee_p31,
        
        
        #consentimiento, YA SE PUSO ARRIBA    
                    
        
        # ojo, no son el mismo pero por facilidad se pone
        "departamento_lab" = departamento_lab,  # ESTA EN ODK 
        "ciudad_lab" = ciudad_lab, # ESTA EN ODK
        
         
        "anos_lab" = trabajo_a_os, # ESTA EN ODK
        "anos_lab_num" = trabajo_a_os, # ESTA EN ODK
        
        "cargo" = cargo, # ESTA EN ODK
        
        #"tipo_cargo" SE ELIMINIO POR PETICIÓN DE DIFARINEY Y JAIME
        
        "anos_cargo" = cargo_a_os,       
        "anos_cargo_num" = cargo_a_os,
        
        "area" = area, #ESTA EN ODK
        
        # "tipo_contrato" SE ELIMINO POR PETICIÓN DE DIFARINEY Y JAIME
        
        "horas",   #ESTA EN ODK          
        "tipo_salario" = tipo_salario,  #ESTA EN ODK   
        form_intra,
        X__id, #ESTA EN ODK
        
        # adicionales
        ila_val1,     #ESTA EN ODK
        ila_val2,     #ESTA EN ODK
        ilb_val1,#ESTA EN ODK
        
        #nuevas
        empleado_registrado #  ES NUEVA Y ESTA EN ODK
        
      )
    
    
    
    
    
    
    
    
    # --- FILTRO ANTI-DUPLICADOS POR ID ---
    # Se filtra por clave (el `__id` de ODK renombrado en el select()).
    # No se usa X__id: al seleccionar la misma columna dos veces, select() no
    # garantiza que sobreviva con ese nombre. Sin tryCatch: si la consulta
    # falla, mejor detenerse que insertar todo otra vez.
    if (!col_id %in% names(empleados)) {
      stop("La columna '", col_id, "' no esta en los datos procesados; revise el select().")
    }

    # Un mismo envio no debe entrar dos veces ni dentro del mismo lote
    empleados <- empleados %>% distinct(.data[[col_id]], .keep_all = TRUE)

    if (dbExistsTable(con, tabla_db)) {
      query_ids <- sprintf("SELECT %s AS id FROM %s",
                           dbQuoteIdentifier(con, col_id),
                           dbQuoteIdentifier(con, tabla_db))
      res_ids <- dbGetQuery(con, query_ids)$id

      empleados <- empleados %>% filter(!.data[[col_id]] %in% res_ids)
    }
    
    # Insertar solo si quedan registros realmente nuevos
    if (nrow(empleados) > 0) {
      if (dbExistsTable(con, tabla_db)) {
        dbWriteTable(con, name = tabla_db, value = empleados, append = TRUE)
      } else {
        dbWriteTable(con, name = tabla_db, value = empleados, overwrite = TRUE)
      }
      estado_salida <- 10L

      cat("\n================================================================\n")
      cat("[INFO] Sincronizacion completada con exito.\n")
      cat(sprintf("Registros nuevos insertados: %d\n", nrow(empleados)))
      cat(sprintf("Tabla de destino: PostgreSQL -> '%s'\n", tabla_db))
      cat(sprintf("Fecha de ejecucion: %s\n", Sys.time()))
      cat("================================================================\n\n")
      
    } else {
      cat("\n================================================================\n")
      cat("[INFO] Sincronizacion completada sin nuevos registros.\n")
      cat("No se encontraron nuevos datos en ODK desde la ultima revision.\n")
      cat(sprintf("Fecha de ejecucion: %s\n", Sys.time()))
      cat("================================================================\n\n")
    }
    
  } else {
    cat("\n================================================================\n")
    cat("[INFO] Sincronizacion completada sin nuevos registros.\n")
    cat("No se encontraron nuevos datos en ODK desde la ultima revision.\n")
    cat(sprintf("Fecha de ejecucion: %s\n", Sys.time()))
    cat("================================================================\n\n")
  }
  
}, error = function(e) {

  estado_salida <<- 1L
  cat("\n================================================================\n")
  cat("[ERROR] Hubo un problema al descargar o actualizar los datos.\n")
  # conditionMessage y no e$message: en los errores de dplyr e$message viene vacio
  cat(sprintf("Detalle del fallo: %s\n", conditionMessage(e)))
  cat(sprintf("Fecha y hora del error: %s\n", Sys.time()))
  cat("================================================================\n\n")
})

# Solo al correr con Rscript: en RStudio, quit() cerraria la sesion.
if (!interactive()) quit(save = "no", status = estado_salida)
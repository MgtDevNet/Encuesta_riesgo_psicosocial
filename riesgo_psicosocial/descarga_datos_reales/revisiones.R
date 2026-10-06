
library(dplyr)
library(magrittr)
library(DBI)
library(RPostgres)

# Lee las credenciales del .Renviron del proyecto (PG_HOST, PG_USER, PG_PASSWORD, ...)
if (file.exists(".Renviron")) readRenviron(".Renviron")

bd_conectar <- function() {
  DBI::dbConnect(
    RPostgres::Postgres(),
    host     = Sys.getenv("PG_HOST", "localhost"),
    port     = as.integer(Sys.getenv("PG_PORT", "5432")),
    dbname   = Sys.getenv("PG_DB",   "riesgo_psicosocial"),
    user     = Sys.getenv("PG_USER", "erps_user"),
    password = Sys.getenv("PG_PASSWORD", "123456"),
    timezone = "America/Bogota"   # si no, las fechas vuelven en UTC
  )
}

con <- bd_conectar()



# Probar la conexión
dbGetQuery(con, "SELECT current_database(), current_user, now()")

# Listar tablas de un esquema
dbGetQuery(con, "
  SELECT table_name FROM information_schema.tables
  WHERE table_schema = 'seguimiento'
")

# Leer una tabla (esquema.tabla)
datos <- dbReadTable(con, Id(schema = "seguimiento", table = "respuestas_odk"))

# Consulta con parámetros (evita inyección SQL; no pegues valores con paste0)
dbGetQuery(con,
           "SELECT * FROM seguimiento.respuestas_odk WHERE forma_cuestionario = $1",
           params = list("A")
)

data_real <- dbGetQuery(con, "SELECT * FROM public.odk_respuestas_intento_1")
data_real$ila_val

marco <- dbGetQuery(con, "SELECT * FROM seguimiento.marco")
data_simul_antes <- dbGetQuery(con, "SELECT * FROM seguimiento.respuestas_odk")
data_simul_desp <- dbGetQuery(con, "SELECT * FROM seguimiento.respuestas")





# dimensiones
data_real %>% dim()
data_simul_antes %>% dim()
data_simul_desp %>% dim()

# variables diferentes
col_real  <- names(data_real)
col_simul <- names(data_simul_antes)

# Columnas en data_real que NO están en data_simul_antes
 #setdiff(col_real, col_simul)

# Columnas en data_simul_antes que NO están en data_real
# estas son las importantes porque son los nombres
# de las columnas que tienen que tener los datos
# para poder hacer los cálculos. 
setdiff(col_simul, col_real)

################################################################################

# "submission_date" - submissionDate                                        LISTO
# "inicio" -  starttime                                                     LISTO
# "fin" - endtime                                                           LISTO
# "duracion_min" - (endtime - starttime) en minutos 
data_real %>% select(endtime,starttime)
data_real %>% select(cal_forma)
 
# "deviceid" - deviceId

# LOS DATOS REALES SIMULADOS ESTÁN AL CONTRARIO, CLAVE COMO X__ID
# E ID_ANONIMIZADO COMO CÉDULA

# "clave" - cedula
#"id_anonimizado" - X__id

#"sede_seccional"  - NO se USA

#"tipo_vinculacion"
data_simul_antes %>% count(tipo_vinculacion)

data_real %>% count(tipo_empleado)
data_real %>% count(clase_empleado)
data_real %>% count(ocupacion)
data_simul_antes %>% count(ocupacion)

data_real %>% count(categoria)

data_real %>% count(empleado_valido)





# "nivel_empleo" - categoria
data_simul_antes %>% count(nivel_empleo)
data_simul_antes %>% count(nivel_empleo)

# "forma_cuestionario"
# "departamento_lab"  
# "ciudad_lab"
# "anos_lab"          
# "anos_lab_num"
# "cargo"             
# "tipo_cargo"
# "anos_cargo"        
# "anos_cargo_num"
# "area"              
# "tipo_contrato"

# tipo de formulario
"form_intra"
data_real %>% count(cal_forma)
data_simul_antes %>% count(forma_cuestionario,tipo_vinculacion)


# forma_cuestionario == cal_forma

col_real %>% class()

col_real[endsWith(col_real, "a_os")]

# SEDE SECCIONAL -----
data_simul_antes %>% count(sede_seccional)
data_simul_desp %>% count(sede_seccional)
data_real %>% count(sede)



# CONSENTIMENTO ---------
# Datos reales
# 1 == SI
# 2 == NO
data_real %>% count(consentimiento)

data_real %>% 
  filter(
    consentimiento == 2
  )

# Datos simulados
# 1 == SI
# 2 == NO
data_simul_antes %>% count(consentimiento)
##########################################


# Unir datos con el marco
library(lubridate)
data_real %>% dim()
marco %>% dim()
marco %>% select(id_anonimizado)

aux <- left_join(
  data_real,
  marco,
  by = c("cedula"="id_anonimizado",
         "cal_nombre" = "nombre",
         "cal_sexo" = "sexo"
         )
)

aux %>% dim()

aux %<>% 
  mutate(
    duracion_min = round(as.numeric(
      difftime(ymd_hms(endtime), ymd_hms(starttime), units = "mins"))
    ,1),
    sexo = if_else(cal_sexo == "M",1,2),
    form_intra = if_else(cal_forma == "A",1,2)
  )

aux %<>% 
  select(
    "nombre" = cal_nombre, # VERIFICADO
    
    tipo_vinculacion, # VERIFICADO
    
    "sexo" = sexo, # 1 es Masculina y 2 es femenino VERIFICADO
    
    consentimiento, # 1 es si y 2 es no. VERIFICADO
    
    "submission_date" = submissionDate,  # VERIFICADO
    
    "inicio" = starttime, # VERIFICADO        
    
    "fin" = endtime,      # VERIFICADO    
    
    "duracion_min" = duracion_min,    # VERIFICADO  
    
    "deviceid" = deviceId,          # VERIFICADO
    
    "clave" = cedula,             # VERIFICADO
    
    "id_anonimizado" = X__id,# VERIFICADO
    
    "dependencia" = dependencia.y,      # VERIFICADO
    
    "sede_seccional" = sede, # FALTA POR PONER EN LA SHINY    
    
    "tipo_vinculacion" = tipo_vinculacion, # VERIFICADO
    
    "nivel_empleo" = nivel_empleo,# VERIFICADO
    
    "forma_cuestionario" = cal_forma,# VERIFICADO
    
    nacimiento,  # verificado
    
    estado_civil,
    # ETQ_ESTADO_CIVIL <- c(
    #   "1" = "Soltero (a)",
    #   "2" = "Casado (a)",
    #   "3" = "Unión libre",
    #   "4" = "Separado (a)",
    #   "5" = "Divorciado (a)",
    #   "6" = "Viudo (a)",
    #   "7" = "Sacerdote / Monja"
    # )
    
    nivel_academico, # VERIFICADO
    
    ocupacion, # OJO, EL NOMBRE EN LA BD ESTA TROCADO
    # ESTO EN VERDAD ES LA PROFESIÓN
    
    "departamento"=departamento,  # VERIFICADO, ES EL DEPARTAMENTO DONDE VIVE (DICCIONARIO)    
    "ciudad"=ciudad,       # VERIFICADO, ES CIUDAD DONDE VIVE (DICCIONARIO)
    estrato,      # VERIFICADO (VER DICCIONARIO)     
    vivienda,      # VERIFICADO (VER DICCIONARIO)  
    dependientes,  # VERFICADO

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
  
  
    consentimiento,    
    cedula,            
          
    # ojo, no son el mismo pero por facilidad se pone
    "departamento_lab" = departamento,  
    "ciudad_lab" = ciudad,
    
    
    "anos_lab" = trabajo_a_os,
    "anos_lab_num" = trabajo_a_os,
    
    "cargo" = categoria.y,
    
    #"tipo_cargo" SE ELIMINIO POR PETICIÓN DE DIFARINEY Y JAIME
    
    "anos_cargo" = cargo_a_os,       
    "anos_cargo_num" = cargo_a_os,
    
    "area" = descripcion_unidad,
    
    # "tipo_contrato" SE ELIMINO POR PETICIÓN DE DIFARINEY Y JAIME
    
    "horas",             
    "tipo_salario" = tipo_salario,     
    form_intra
    
  ) 


aux %>% dim
data_simul_antes %>% dim()


setdiff(data_simul_antes %>% names(), aux %>% names())
# [1] "ila_val1"     no se usa
# [2] "ila_val2"     no se usa
# [3] "ilb_val1"     no se usa
# [4] "cedula"       ya esta en clave
# [5] "cal_nombre"   ya esta
# [6] "cal_naci"     ya esta
# [7] "cal_sexo"     ya esta
# [8] "tipo_cargo"   se elimino y no se pregunta
# [9] "tipo_contrato" se elimino y no se pregunta. 

# Cerrar al terminar -----
dbDisconnect(con)
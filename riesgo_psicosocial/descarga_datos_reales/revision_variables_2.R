aux %>% 
  select(
    cedula,
    nombre,
    sexo,
    cal_sexo
    ) %>% 
  head()

data_real %>% 
  select(
    dependencia
  )

marco %>% dim()

# verificación de tipos de datos de simulación antes
data_simul_antes %>% 
  count(sexo)

data_simul_antes %>% 
  select(nombre,cal_sexo,sexo) %>% 
  head()

data_simul_antes %>% 
  count(consentimiento)

data_real %>% 
  filter(consentimiento == 2)

# NACIMIENTO ----------

# verficar tipo de dato en simulación
data_simul_antes %>% 
  select(nacimiento) %>% 
  head()

# verificar dato en marco y en dato real
aux %>% 
  select(
    nacimiento,
    fechanacimiento
  ) %>% 
  head()

# estado_civil ----------

# verficar tipo de dato en simulación
data_simul_antes %>% 
  select(estado_civil) %>% 
  head()


# verificar dato en marco y en dato real
aux %>% 
  select(
    estado_civil
  ) %>% 
  head()

# sexo ----------

# verficar tipo de dato en simulación
data_simul_antes %>% 
  select(sexo) %>% 
  head()

data_real %>% 
  select(sexo,
         cal_sexo) %>% 
  head()

marco %>% 
  select(
    sexo
  ) %>% 
  head()

aux %>% 
  select(
    sexo.x, # de marco
    sexo.y, # de datos reales
    cal_sexo, # datos reales
  )

# verificar dato en marco y en dato real
aux %>% 
  select(
    estado_civil
  )  

# sede --------- HAY QUE AÑADIR ESTO EN LA SHINY
data_simul_antes %>% 
  select(sede_seccional) %>% 
  head()

data_real %>% 
  select(sede) %>% 
  head()




# nivel académico ----------

# verficar tipo de dato en simulación
data_simul_antes %>% 
  select(nivel_academico) %>% 
  head()


data_real %>% 
  select(nivel_academico) %>% 
  head()


aux %>% 
  select(
    sexo.x, # de marco
    sexo.y, # de datos reales
    cal_sexo, # datos reales
  )

# verificar dato en marco y en dato real
aux %>% 
  select(
    estado_civil
  ) %>% 
  head()

# departamento ----------

# verficar tipo de dato en simulación
data_simul_antes %>% 
  select(departamento) %>% 
  head()

data_real %>% 
  count(departamento) %>% 
  head()

marco %>% 
  count(departamento) %>% 
  head()


# ciudad ----------

# verficar tipo de dato en simulación
data_simul_antes %>% 
  select(ciudad) %>% 
  head()

data_real %>% 
  count(ciudad) %>% 
  head()

marco %>% 
  count(depar) %>% 
  head()

# estrato ----------

# verficar tipo de dato en simulación
data_simul_antes %>% 
  select(estrato) %>% 
  head()

data_real %>% 
  count(estrato) %>% 
  head()

marco %>% 
  count(estrato) %>% 
  head()

# VIVIENDA ----------

# verficar tipo de dato en simulación
data_simul_antes %>% 
  select(vivienda) %>% 
  head()

data_real %>% 
  count(vivienda) %>% 
  head()

marco %>% 
  count(vivienda) %>% 
  head()

# DEPENDIENTES ----------

# verficar tipo de dato en simulación
data_simul_antes %>% 
  select(dependientes) %>% 
  head()

data_real %>% 
  count(cedula) %>% 
  head()

marco %>% 
  count(cedula)

# Tipo CARGO ----------

# verficar tipo de dato en simulación
data_simul_antes %>% 
  select(tipo_cargo) %>% 
  head()

data_real %>% 
  select(
    tipo_salario
  )

marco %>% 
  count(tipo_cargo) %>% 
  head()



# OJITO CON ESTOOOOO, JHON LO VA A ORGANIZAR
# REAL: PROFESION, NOMBRE EN BD: OCUPACIÓN ----------

# verficar tipo de dato en simulación
data_simul_antes %>% 
  select(ocupacion) %>% 
  head()

data_real %>% 
  count(ocupacion) %>% 
  head()


# REAL: OCUPACIÓN, NOMBRE EN BD: PROFESIÓN  ----------

# verficar tipo de dato en simulación
data_simul_antes %>% 
  select(cargo) %>% 
  head()

data_real %>% 
  count(profesion) %>% 
  head()



# categoría, es el cargo 
# verficar tipo de dato en simulación

data_real %>% 
  count(categoria) %>% 
  head()

marco %>% 
  count(categoria)


# años laborando y en el cargo
data_simul_antes %>% 
  select(anos_lab_num) %>% 
  head()

data_real %>% 
  count(trabajo_a_os) %>% 
  head()

# area
data_simul_antes %>% 
  select(area) %>% 
  head()

marco %>% 
  count(
    descripcion_unidad
  )

# tipo contrato
data_simul_antes %>% 
  select(tipo_contrato) %>% 
  head()

data_real %>% 
  count(
    tipo
  )

# form_int
data_simul_antes %>% 
  count(form_intra)  


data_real %>% 
  count(
    tipo
  )


empleados %>% names()

marco %>% 
  count(
    tipo_vinculacion
  )
empleados %>% 
  count(tipo_vinculacion)

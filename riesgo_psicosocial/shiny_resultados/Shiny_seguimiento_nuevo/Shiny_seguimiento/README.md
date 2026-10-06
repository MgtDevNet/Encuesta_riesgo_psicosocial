# Seguimiento riesgo psicosocial

App Shiny modular sobre PostgreSQL. Sigue la estructura de `Shiny_carga`.

## Estructura

```
Shiny_seguimiento/
├── app.R                    # librerías, source(), tema, ui navbarPage + server
├── conectar_bd.R            # califica la escala y reescribe seguimiento.respuestas
├── Shiny_seguimiento.Rproj
├── R/
│   ├── _disable_autoload.R  # el orden de carga lo manda app.R, no Shiny
│   ├── helpers.R            # %||%, to_key(), alerta(), fmt_momento()
│   ├── utils_db.R           # pool de PostgreSQL: db_get(), db_exec(), db_tx()
│   ├── utils_auth.R         # reglas y datos del ingreso (esquema `auth`)
│   ├── utils_seguimiento.R  # esquema `seguimiento` y consultas del avance
│   ├── utils_contactos.R    # bitácora de gestión con cada persona
│   └── utils_resultados.R   # niveles de riesgo por grupos de personas
├── Modules/
│   ├── mod_auth.R           # MÓDULO 1: seguridad
│   ├── mod_seguimiento.R    # MÓDULO 2: avance por dependencia
│   ├── mod_resultados.R     # MÓDULO 3: resultados por grupos
│   ├── mod_citaciones.R     # grupos de aplicación y carga de la agenda
│   └── mod_usuarios.R       # pestaña Administración: usuarios, agenda y bitácora
├── Diccionarios/            # los cuatro .xlsx con que se califica la escala
├── www/
│   ├── custom.css           # estilos propios, cargados después del theme
│   └── grafico.js
├── scripts/
│   ├── preparar_bd.R        # deja la base lista en un equipo nuevo
│   ├── cargar_marco_bateria.R # carga el marco REAL (export de nómina) tal cual
│   ├── cargar_respuestas_odk.sh
│   ├── gestionar_usuarios.R # alta, reset, baja y bitácora desde la terminal
│   ├── exportar_odk_csv.R
│   ├── simular_agenda.R     # agenda de citaciones simulada sobre el marco
│   ├── simular_respuestas.R # crea respuestas simuladas para el marco
│   ├── simular_items.R      # recalibra los ítems de las respuestas que existen
│   └── cargar_datos_simulados.R
└── .Renviron                # credenciales (NO se versiona)
```

Convenciones (las mismas de `Shiny_carga`):

- Las librerías van al tope de `app.R`, **antes** de los `source()`, porque los
  módulos y helpers ejecutan código a nivel de script al importarse.
- Módulos en `Modules/mod_*.R`, cargados con `source(..., local = TRUE)`.
- Helpers en `R/`.
- UI con `navbarPage` + un `tabPanel(icon =, title =)` por módulo.
- Tema con `bs_theme(version = 5, bootswatch = "flatly", ...)` y
  `bs_add_variables()` para los colores de la barra.
- CSS propio en `www/custom.css` y JS en `www/grafico.js`, entregados como una
  `htmlDependency` (`DEP_ESTATICOS` en `app.R`) y no por la vía implícita de
  Shiny: así llegan por el mismo mecanismo que Bootstrap, Shiny arma la URL y no
  dependen de cómo se levante la app. El cache-busting es el campo `version`;
  al cambiar cualquiera de los dos archivos, subir ese número.
- Estado compartido en `r <- reactiveValues(...)`, que se pasa a cada módulo
  como `r = r`. Cada módulo publica lo suyo en `r`.

`R/_disable_autoload.R` apaga la auto-carga de `R/` que hace Shiny, para que el
orden de carga sea exactamente el que declara `app.R` (si no, `R/` se cargaría
dos veces: una por Shiny y otra por los `source()`).

## Puesta en marcha en un equipo nuevo

La app trae **todo lo que necesita** menos dos cosas, que son las únicas que hay
que llevar al equipo destino:

| insumo externo | va a | de dónde sale |
|---|---|---|
| marco muestral (`.xlsx` o `.csv`) | `seguimiento.marco` | la nómina de la institución |
| export de ODK (`.csv`) | `seguimiento.respuestas_odk` | el formulario en campo |
| citaciones (`.xlsx` o `.csv`, **opcional**) | `seguimiento.citaciones` | la agenda de aplicación |

Lo demás —esquemas, tablas, índices, el tipo `nivel_riesgo`, la tabla derivada
`seguimiento.respuestas` con los 56 puntajes clasificados y las metas
iniciales— lo genera la propia app.

```bash
# 1. PostgreSQL: crear la base una sola vez
sudo -u postgres createdb -O $USER riesgo_psicosocial

# 2. Un solo comando deja la base lista (desde la carpeta de la app)
Rscript scripts/preparar_bd.R --marco=../Marco_muestral.xlsx --odk=../respuestas_odk.csv

# 3. Arrancar; el primer usuario se crea desde la propia app
R -e 'shiny::runApp(".", launch.browser = TRUE)'
```

`preparar_bd.R` es idempotente y se puede volver a correr cuantas veces haga
falta. Lo que hace, en orden:

1. Revisa que estén los paquetes de R y los enumera todos de una vez si falta alguno.
2. Prueba la conexión y explica qué revisar si falla.
3. Crea `auth` y `seguimiento` completos (`auth_init_db()`, `seg_init_db()`,
   `cto_init_db()`, las mismas que corre la app al arrancar).
4. Carga el marco —lo **reemplaza entero**: es una foto de la nómina, y quien ya
   no está tiene que salir del denominador— validando columnas e ids repetidos.
5. Carga el export de ODK por *upsert*, con `scripts/cargar_respuestas_odk.sh`.
6. Ejecuta `conectar_bd.R`, que califica la escala con los diccionarios de
   `Diccionarios/` y reescribe `seguimiento.respuestas`.
7. Siembra las metas que falten con los elegibles del marco. Las metas ya
   editadas **no se tocan nunca**.
8. Imprime el conteo de cada tabla y qué falta todavía.

Opciones:

```bash
Rscript scripts/preparar_bd.R                       # solo verifica y deriva
Rscript scripts/preparar_bd.R --marco=<archivo>     # + carga el marco
Rscript scripts/preparar_bd.R --odk=<archivo.csv>   # + carga ODK
Rscript scripts/preparar_bd.R --citaciones=<archivo> # + carga la agenda
Rscript scripts/preparar_bd.R --solo-esquema        # crea las tablas vacías y nada más
Rscript scripts/preparar_bd.R --marco=<archivo> --limpiar   # + borra lo que colgaba del marco viejo
```

`--marco=` acepta los **dos formatos** que existen y reconoce solo cuál es cuál,
así que no hay que saber de antemano qué archivo llegó:

| Formato | Cómo se reconoce | Quién lo carga |
|---|---|---|
| Canónico | hoja `Marco_muestral`, o cualquier hoja/CSV con `id_anonimizado` y `dependencia` | el propio `preparar_bd.R` |
| Nómina | encabezados en la fila 5 con `IDENTIFICACION` y `DESCRIPCION_DEPENDENCIA` | delega en `cargar_marco_bateria.R` |

En los dos casos **la hoja del marco es la primera del libro**, y solo esa se
mira. El export de nómina trae hojas anexas del reporte —la que llegó tiene una
`Hoja4` con novedades de personal (comisiones, sabáticos, licencias)— y ninguna
entra: están en otra llave, traen gente que ni siquiera figura en la nómina, y
cargarlas descuadraría el marco. Al cargar se avisa cuáles se ignoraron.

Del formato canónico solo se exigen `id_anonimizado` y `dependencia`, que son las
dos `NOT NULL` de la tabla; las otras doce se cargan si vienen y se avisan si no.
Ninguna fuente real las trae todas, y la app oculta sola los filtros sin dato.

Cuando delega en la nómina, **conserva** por defecto lo que cuelga del marco
(respuestas, citaciones, contactos): recargar el mismo marco no puede llevarse
por delante el export de ODK ya cargado, y lo que quede huérfano se avisa en el
resumen final. `--limpiar` es lo que hace falta cuando el marco nuevo no comparte
un solo id con el viejo.

Si la conexión no es por socket local, las credenciales van en un `.Renviron` en
la carpeta de la app (`PG_HOST`, `PG_PORT`, `PG_DB`, `PG_USER`, `PG_PASSWORD`);
nunca en el código.

Cuando llegan datos nuevos de campo, basta con repetir el paso 2 con el export
más reciente.

### El marco real

El marco de verdad es un **export de nómina** (`Bateria 2026 (1).xlsx`): 3.357
personas, 163 dependencias, encabezados en la fila 5 y 26 columnas con otros
nombres que los del formato canónico. Se carga **tal cual**, sin transformarlo.
`preparar_bd.R --marco=` lo reconoce y delega solo, pero el cargador también se
puede llamar directo:

```bash
Rscript scripts/cargar_marco_bateria.R "../Bateria 2026 (1).xlsx"
Rscript scripts/cargar_marco_bateria.R <archivo> --conservar   # no borra lo simulado
```

Las 26 columnas del archivo se guardan en `seguimiento.marco` en minúsculas
(los repetidos quedan como `oficio`, `oficio_1`), y **al lado** se calculan las
que consulta la app:

| La app usa | Sale de |
|---|---|
| `id_anonimizado` | `IDENTIFICACION`, el documento |
| `nombre` | `NOMBRE` |
| `dependencia` | `DESCRIPCION_DEPENDENCIA` |
| `tipo_dependencia` | `DESCRIPCION_UNIDAD` |
| `tipo_vinculacion`, `nivel_empleo` | `TIPO_VINCULACION`, `GRUPO` |
| `estado_vinculacion` | `'Activo'`: es la nómina vigente y `NOVEDAD` vale 0 en todas |
| `forma_cuestionario` | Sorteo con la proporción A/B de las respuestas ya cargadas. **Es provisional**: cuando llegue el dato real se cambia en el script y se vuelve a cargar |

`sede_seccional`, `municipio`, `dedicacion`, `modalidad_trabajo` y
`trabaja_por_turnos` no existen en el archivo y quedan vacías; el filtro de sede
no se dibuja cuando el marco no trae sedes.

**Este archivo trae documento y nombre**, y es la primera vez que datos
personales entran a la base: hasta entonces la app trabajaba solo con
`id_anonimizado`. La tabla de personas muestra el nombre y, debajo, el
documento. Téngalo en cuenta antes de publicar la app (ver `NGROK.md`).

Por defecto la carga **borra lo simulado** que cuelga del marco anterior
—respuestas, puntajes, citaciones, grupos y anotaciones—, porque sus ids no
existen en el marco nuevo. Las metas no se borran, pero conviene reajustarlas:
las del marco viejo quedan con denominadores que no corresponden.

### Simulaciones sobre el marco cargado

```bash
Rscript scripts/simular_agenda.R      # agenda de citaciones (--excel deja el .xlsx)
Rscript scripts/simular_respuestas.R  # crea las respuestas en respuestas_odk
Rscript scripts/simular_items.R       # calibra los ítems contra los baremos
Rscript conectar_bd.R                 # califica y reescribe seguimiento.respuestas
```

En ese orden: `simular_items.R` solo recalibra filas que ya existen, así que
antes tienen que nacer con `simular_respuestas.R`. La agenda va primero porque
el envío simulado de cada persona cae después de su citación, como en campo.

`simular_agenda.R` arma la jornada real del operativo: **cuatro sesiones al
día** (08:00–09:30, 10:00–11:30, 13:30–15:00 y 15:30–17:00), de **hora y
media** cada una y con un máximo de **30 personas por grupo**. Las franjas no
comparten ninguna hora de reloj, así que con dos sesiones simultáneas quedan 60
personas por hora, por debajo del tope de 100 que verifica la app
(`seg_cit_capacidad`). Los parámetros están al tope del script: `FRANJAS`,
`DURACION_MIN` y `POR_GRUPO`.

Los grupos se reparten a lo largo de todo el periodo, con sesiones ya pasadas
—que alimentan "citados sin responder"— y sesiones futuras, que son las que un
psicólogo puede tomar y anotar.

Con `--solo-excel` no toca la base: vuelca al `.xlsx` la agenda que ya está
cargada. Sirve cuando se quiere el archivo sin volver a sortear las citaciones,
que dejaría huérfanos los grupos asignados y descuadraría las respuestas
simuladas.

### Citaciones

La agenda llega en una base aparte, una fila por persona citada:

| columna | |
|---|---|
| fecha | día de la citación |
| hora inicio programada, hora final programada | la franja |
| id persona | el `id_anonimizado` del marco |
| persona | el nombre (opcional); se carga, pero solo se ve al anotar la sesión |
| link donde se aplica | la sesión (opcional) |

Los encabezados se reconocen con o sin tildes, espacios o guiones bajos, y las
horas con o sin segundos, en formato de 24 horas o con a. m. y p. m. La tabla se
**reemplaza entera** en cada carga: es una foto de la programación.

En una hora se programan hasta **2 grupos** y **100 personas**
(`SEG_CIT_GRUPOS_HORA` y `SEG_CIT_POR_HORA` en `R/utils_seguimiento.R`). Las
franjas que pasan ese cupo y los ids que no están en el marco se avisan al
cargar, pero no detienen la carga.

Con la agenda cargada, la pestaña de avance muestra:

- en el gráfico de días, una línea **Citados** por encima de la cobertura, y en
  la leyenda cuántos de ellos **no han respondido**;
- en *Personas*, el grupo **Citados sin responder** y la columna *Citación*.

Una persona cuenta como citada desde que pasó la **hora final** de su cita, y
como sin responder si no tiene ningún envío. La leyenda y el grupo usan la misma
regla, así que la cifra cuadra.

### Quién no contestó, por día de citación

Al final de la pestaña —después del listado de dependencias y del detalle— hay
un recuadro con un **selector de día**: solo días de citación que ya terminaron,
del más reciente al más antiguo, y cada opción dice cuántas de las citadas ese
día siguen sin responder.

La tabla muestra, de ese día, las personas que **hoy no tienen ningún envío**
—no las que no respondieron esa tarde: a quien respondió después ya no hay que
perseguirlo—. De cada una trae con qué llamarla: dependencia, sede, vinculación,
la franja en que se la citó, **cuántas veces se la ha citado** en total y su
**último contacto** de la bitácora, para no repetir la llamada que ya hizo otro.
Se puede descargar en CSV.

Va sobre toda la universidad, pero respeta los filtros de sede y tipo de la
barra de arriba. Las consultas son `seg_dias_citados()` y `seg_citados_dia()`.

### Grupos de aplicación

Un **grupo** es una sesión de la agenda: la misma fecha, franja y link. En la
pestaña *Citaciones* el **psicólogo**, que es quien aplica la encuesta, ve los
grupos y:

- **toma** un grupo libre que todavía no ha empezado;
- **suelta** uno suyo mientras no haya empezado; desde la hora de inicio queda fijo.

Cada grupo tiene **un solo psicólogo**. Lo garantiza la clave primaria de
`seguimiento.grupos_aplicador`, así que si dos lo toman a la vez solo uno lo
consigue. Cualquier rol con el permiso `asignar_grupos` —hoy, los cuatro— le
pone o le quita el psicólogo a cualquier grupo, también a uno que ya pasó. Un
grupo solo se le puede asignar a alguien con rol de psicólogo.

Desde la app, la agenda la carga el **administrador**, en la pestaña
*Administración* (permiso `cargar_agenda`).

*Citaciones* tiene dos vistas de los mismos grupos:

- **Calendario**: una semana, con cada grupo asignado en su día, su franja, su
  **link** (se abre con un clic) y cuántas personas citó. El psicólogo ve el
  suyo; cualquiera puede elegir a un psicólogo o ver a todos, y entonces cada
  grupo dice a quién le toca. Si la semana está vacía, dice cuándo es el
  próximo grupo y lleva a esa semana. Para el psicólogo es la vista que abre.
- **Grupos**: la tabla para tomar, soltar y asignar.

### Anotaciones de la sesión

La tercera vista de *Citaciones* es **Anotaciones**: un bloque fijo —no una
ventana— con un selector de grupo. Los botones **Anotar** del calendario y de la
tabla llevan ahí con el grupo ya elegido.

Se escribe una anotación para toda la sesión y, cuando hace falta, una para
alguien en particular. **No hay asistencia ni estado de la sesión**: marcar
persona por persona resultó más trabajo del que valía.

Todo va a `seguimiento.observacionespsicologos`, una sola tabla con dos tipos de
fila: `grupo` (la anotación de la sesión) y `persona` (la de un citado). Además
de la sesión (fecha, franja y link) llevan `psicologo`, `registrado_por`,
`registrado_en` y, si se corrigió, `actualizado_por` y `actualizado_en`, solo en
las filas que cambiaron. **Solo se guarda lo que tiene texto**: al borrar el
texto se borra la fila.

- **Quién escribe**: el psicólogo asignado al grupo, desde la hora de inicio y
  **sin plazo**: una sesión vieja se anota cuando aparezca el rato de hacerlo, y
  lo escrito se puede corregir después. El administrador puede escribir o
  corregir cualquier sesión que haya empezado.
- **Quién lee**: la del grupo, cualquier rol. Las de cada persona —y los
  nombres—, solo el psicólogo del grupo y el administrador: a los demás ni se
  les envía.
- **Los nombres** salen de la columna `persona` del Excel de la agenda y se
  guardan en `seguimiento.citaciones.nombre`. Si el archivo no la trae, las
  anotaciones van por id. Ninguna otra pantalla muestra nombres.
- Un grupo que ya terminó, con psicólogo y sin anotaciones, se marca **Sin
  anotar**; el filtro del mismo nombre los reúne.
- Las anotaciones **no se borran** al recargar la agenda: son lo que pasó.
- Guardar queda en la bitácora.

La asignación sobrevive a una recarga de la agenda mientras el grupo siga en
ella; los grupos que salen **pierden su aplicador**, y la revisión antes de
cargar dice cuáles.

### Si la app se ve sin estilos

Si los cuadros de indicadores caen apilados como texto suelto y el gráfico sale
gigante y negro, lo que no está llegando es `www/custom.css` —de ahí sale todo
el diseño; el verde y el rojo que sí se ven son clases de Bootstrap, que viene
del paquete `bslib`—. Por eso los estáticos se entregan como `htmlDependency`,
que es el camino que sí funciona en todos los equipos, y por eso `app.R` se
detiene con un mensaje explícito si no encuentra `www/custom.css` desde su
directorio de trabajo, en vez de arrancar y verse mal en silencio.

### El primer usuario

En un equipo nuevo la tabla `auth.usuarios` está vacía. La app lo detecta y en
vez de la pantalla de ingreso muestra el **formulario de primer arranque**:
código de instalación, usuario, nombre completo y contraseña.

El código es el valor de `APP_CODIGO_INSTALACION` en el `.Renviron` de la app
(al menos 12 caracteres; hay que reiniciar la app después de ponerlo). Sin él
el formulario no crea la cuenta. Se crea, queda guardado en la base, la
sesión se abre de una vez y esa pantalla no vuelve a aparecer.

Se resolvió así porque la vía de la terminal no sirve en Windows: pedir la
contraseña sin mostrarla en pantalla se hacía con `stty -echo`, que no existe
ahí. `gestionar_usuarios.R` ahora prueba, en orden, `stty`, `getPass`, el
diálogo de RStudio y `askpass`, y si ninguna sirve remite a este formulario en
vez de rendirse a medias.

La cuenta creada así **no** obliga a cambiar la contraseña al entrar (a
diferencia de las que se dan de alta desde la terminal): no la asignó un
tercero, la eligió quien la va a usar. Y tiene rol **administrador**: si no,
nadie podría crear las demás cuentas.

El código existe porque la app se publica en internet (`NGROK.md`): sin él,
cualquiera que abriera la URL con la base vacía se quedaba con la primera
cuenta, que además es de administrador.

### Qué hace la app cuando falta algo

La app nunca arranca contra una base a medias. Al abrirse crea lo que falte y,
si todavía no hay datos, muestra qué falta y el comando exacto en vez de la
pantalla de ingreso. Los avisos de arranque son tres: no hay conexión, no se
pudo preparar el esquema y faltan datos (`seg_faltantes()`).

## Módulo 1: seguridad

Hay **cuatro roles** y no hay desactivación de cuentas. *Avance por dependencia*
y *Resultados* los ven todos; lo que cambia entre roles es:

| permiso | administrador | coordinador | auxiliar administrativo | psicólogo |
|---|:-:|:-:|:-:|:-:|
| asignar grupos a los psicólogos (`asignar_grupos`) | ✓ | ✓ | ✓ | ✓ |
| tomar y soltar sus propios grupos (`tomar_grupos`) |  |  |  | ✓ |
| cargar la agenda de citaciones (`cargar_agenda`) | ✓ |  |  |  |
| anotar sus sesiones y a cada persona (`registrar_sesion`) |  |  |  | ✓ |
| leer y corregir cualquier anotación (`revisar_sesiones`) | ✓ |  |  |  |
| administrar usuarios y ver la bitácora (`usuarios`) | ✓ |  |  |  |

El psicólogo es quien aplica la encuesta, y un grupo solo se le asigna a un
psicólogo. La matriz vive en `AUTH_PERMISOS` (`R/utils_auth.R`), que es el
único sitio donde se decide: cambiarla ahí cambia la app, el script y las
reglas del SQL. La **bitácora** registra cada ingreso, cada fallo y cada cambio.

```r
server <- function(input, output, session) {
  r <- reactiveValues(usuario = NULL)
  mod_auth_server("auth", r = r)     # publica la ficha de sesión en r$usuario
}
```

`r$usuario` es `NULL` o `list(usuario, nombre, debe_cambiar, rol, sello, origen, ingreso)`.
Los demás módulos **no arrancan** hasta que hay un ingreso válido con la clave
temporal ya cambiada: si arrancaran al abrir la página, sus salidas y acciones
se podrían pedir desde el navegador sin haber entrado.
El `rol` de la ficha solo decide qué se dibuja; cada acción lo vuelve a leer de
la base (`auth_puede_usuario()`). Si el rol cambia, la sesión abierta se cierra
en menos de un minuto para que la persona entre con el nuevo.

Lo que hace el módulo:

- Contraseñas con `scrypt` (salt por hash), calibrado a ~0,1 s: R atiende a
  todas las sesiones con un solo hilo, y a 0,6 s cada ingreso congelaba la app
  para todos. Los hashes antiguos se rehacen solos al siguiente ingreso.
- La contraseña debe tener **al menos 8 caracteres** y combinar letras y números.
- Tras **5 fallos** de un mismo usuario, o **20** desde una misma IP, hay que
  esperar **15 minutos**. Se cuenta sobre la bitácora y se mira antes de scrypt,
  así que un intento bloqueado no gasta CPU. Reiniciar la clave desbloquea.
- Quien entra con clave temporal solo ve la pantalla para cambiarla: la app no
  se dibuja ni arranca detrás.
- Cambiar la contraseña con la sesión abierta pide la actual; un error cuenta
  como intento fallido.
- La sesión se cierra tras **30 minutos sin actividad**, y en menos de un minuto
  si la clave o el rol cambian o el usuario se elimina desde otro lado.
- Mensaje de error genérico y verificación contra un hash señuelo cuando el
  usuario no existe: no se puede enumerar usuarios ni por mensaje ni por tiempo.
- Toda consulta va parametrizada (`$1`, `$2`): no hay concatenación de SQL.
- Bitácora en `auth.bitacora_accesos`: ingresos, fallos, bloqueos, salidas,
  cierres de sesión, cambios de clave, altas, bajas, cambios de rol,
  grupos tomados, soltados y asignados, y cargas de agenda. Sobrevive al borrado
  del usuario. El `origen` es la IP real: detrás de ngrok se toma de
  `X-Forwarded-For`, lo que solo es fiable mientras la app escuche en
  `127.0.0.1`.
- Salir recarga la sesión completa, para que no quede nada del usuario anterior.
- Si no hay ningún usuario, la puerta es el formulario de primer arranque en vez
  de la pantalla de ingreso (`mod_auth_ui()` es un `uiOutput`; decide el server).

Los límites están al tope de `R/utils_auth.R` (`AUTH_MIN_CLAVE`,
`AUTH_MAX_FALLOS`, `AUTH_MAX_FALLOS_ORIGEN`, `AUTH_VENTANA_MIN`,
`AUTH_INACTIVIDAD_MIN`, `AUTH_SCRYPT_SEG`).

### Tabla `auth.usuarios`

| columna | |
|---|---|
| `usuario` | clave primaria, minúsculas |
| `hash` | scrypt |
| `nombre` | nombre para mostrar |
| `debe_cambiar` | obliga a cambiar la clave al ingresar |
| `rol` | `administrador`, `coordinador`, `auxiliar` o `psicologo` (restricción `usuarios_rol_valido`) |
| `creado`, `ultimo_ingreso` | timestamptz |

`auth_init_db()` migra sola las instalaciones anteriores: elimina las columnas
`activo`, `intentos_fallidos` y `bloqueado_hasta` si todavía existen, y agrega
`rol` conservando lo que cada quien podía hacer. Con la marca `coordinador` de
la versión anterior queda **administrador**, y sin ella **psicólogo**; en una
base sin esa marca, donde todos lo podían todo, todos quedan **administrador**.
Después borra `coordinador`. Un `rol` de versiones más viejas, con otros
valores, se descarta.

## Administración de usuarios

```bash
Rscript scripts/gestionar_usuarios.R listar
Rscript scripts/gestionar_usuarios.R crear <usuario> <rol> "Nombre Completo"
Rscript scripts/gestionar_usuarios.R reset <usuario>
Rscript scripts/gestionar_usuarios.R eliminar <usuario>
Rscript scripts/gestionar_usuarios.R rol <usuario> <rol>
Rscript scripts/gestionar_usuarios.R bitacora [n]
```

`<rol>` es `administrador`, `coordinador`, `auxiliar` o `psicologo`.

Los administradores hacen lo mismo desde la pestaña **Administración** de la
app, sin terminal. Ahí la contraseña temporal la genera la app y se muestra una
sola vez para entregársela a la persona, que tiene que cambiarla al entrar. La
pestaña también tiene la carga de la agenda de citaciones, quién está bloqueado
por intentos fallidos y los últimos 200 eventos de la bitácora.

Cambiar el rol cierra la sesión abierta de esa persona en menos de un minuto,
para que entre con los permisos nuevos. Si deja de ser psicólogo, sus grupos
por empezar quedan libres. Nadie puede cambiarse el rol ni eliminarse a sí mismo
desde la app, y no se puede dejar la app sin ningún administrador.

Como no hay cuentas desactivables, quitarle el acceso a alguien es **eliminarlo**
(en la terminal pide confirmación escribiendo `SI`). Sus sesiones abiertas se
cierran en menos de un minuto, sus grupos por empezar quedan libres y su rastro
en la bitácora se conserva. El nombre de usuario eliminado **no se puede volver
a usar**, para que la cuenta nueva no herede su historial.

La contraseña nunca se pasa como argumento, para que no quede en el historial
del shell ni en la lista de procesos. Para pedirla sin mostrarla en pantalla se
prueban por orden: `stty -echo` (Linux y macOS), `getPass` (la que funciona en
la consola de Windows), el diálogo de RStudio y `askpass`. Si ninguna está
disponible el script **se detiene**: no cae a leerla con el eco encendido, y
remite al formulario de primer arranque de la app o a `install.packages("getPass")`.

Necesita una terminal real: no funciona con la entrada redirigida desde un
archivo o una tubería.

## Pruebas

```bash
Rscript tests/test_mod_auth.R    # 21 pruebas; no necesita base de datos
Rscript tests/test_auth_db.R     # 37 pruebas; necesita PostgreSQL; se limpia solo
```

`test_auth_db.R` usa el usuario desechable `zz.prueba.temporal` y lo borra al
terminar, incluidas sus entradas de bitácora.

## Agregar el módulo siguiente

1. Crear `Modules/mod_<nombre>.R` con `mod_<nombre>_ui(id)` y
   `mod_<nombre>_server(id, r = reactiveValues())`.
2. Agregar `source("Modules/mod_<nombre>.R", local = TRUE)` en `app.R`.
3. Agregar su `tabPanel()` en `pantalla_principal()`.
4. Agregar `mod_<nombre>_server("<id>", r = r)` en el `server`.

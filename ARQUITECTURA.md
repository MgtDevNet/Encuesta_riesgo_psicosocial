# Arquitectura del código

Mapa para quien va a **leer o modificar** el código del aplicativo de seguimiento de la Batería de Riesgo Psicosocial (Universidad de Antioquia). Describe el código **al 11 de noviembre de 2026**.

Este archivo da la vista de conjunto. El detalle de cada decisión está en los comentarios del propio código: cada archivo empieza con una cabecera que explica qué hace y por qué. La instalación, la operación del servidor y el uso de las pantallas están en los documentos Word (guía de instalación, conceptos y manuales), que no van en el repositorio.

---

## 1. Piezas

| Pieza | Qué es | Dónde |
|---|---|---|
| Base de datos | PostgreSQL 16 en Docker | `riesgo_psicosocial/docker/docker-compose.yml` (servicio `postgres`) |
| Aplicación | Shiny (R 4.6.1) en Docker | `riesgo_psicosocial/shiny_resultados/Shiny_seguimiento_nuevo/Shiny_seguimiento/` (en el contenedor: `/app`) |
| Descargas | Scripts R que corren **dentro** del contenedor de la Shiny, llamados por cron en el servidor | `riesgo_psicosocial/descarga_datos_reales/` (en el contenedor: `/descarga`, solo lectura) |
| Respaldos | `pg_dump` periódico; el más reciente se restaura solo en un equipo nuevo | `riesgo_psicosocial/docker/respaldar_bd.sh`, `restaurar_respaldo.sh` |

En adelante, `app/` es la carpeta de la aplicación.

## 2. Recorrido de los datos

```
ODK Central ──► descarga_datos_reales/conexion_resultados_odk.R
                  └─► public.odk_respuestas_<etapa>      (solo agrega envíos nuevos, sin los rechazados)
                         │
                         ▼
                app/conectar_bd.R  (califica con app/Diccionarios/)
                  └─► public.respuestas_procesadas       (se REESCRIBE entera en cada corrida)
                  └─► vistas public.respuestas_procesadas_exportacion(_ind)
                         │
Nómina (Excel) ─► app/scripts/cargar_marco_bateria.R ─► seguimiento.marco
                         │
                         ▼
        vista seguimiento.marco_completo  =  marco  +  no registrados completados
                                              ±  contratos < 6 meses usados  −  personas borradas
                         │
                         ▼
                 Aplicación Shiny (app/app.R + R/ + Modules/)

Google Sheet ──► descarga_datos_reales/agenda_desde_google_sheets.R --cargar ─► seguimiento.citaciones
```

- `descarga_datos_reales/actualizar_datos.sh` encadena descarga y calificación (cron cada 15 min). `actualizar_agenda.sh` corre la agenda (cron cada 30 min).
- La etapa (`ETAPA` en `docker/.env`: `piloto` o `reales`) decide la tabla `odk_respuestas_<etapa>`. Ver `seg_etapa()` y `seg_tabla_odk()`.
- La aplicación se entera sola de los cambios: `app.R` consulta cada minuto una «firma» de las respuestas y de la agenda (`reactivePoll`) y avisa a los módulos por `r$respuestas` y `r$citaciones`.

## 3. La aplicación

`app.R` carga primero las librerías y después los archivos con `source()` en un orden fijo (`R/_disable_autoload.R` apaga la carga automática de Shiny). Al arrancar crea o actualiza el esquema (`auth_init_db()`, `seg_init_db()`, `cto_init_db()`): **no hay migraciones aparte**, cada función crea lo que falta y no toca lo que ya existe.

| Archivo | Contenido |
|---|---|
| `R/helpers.R` | Utilidades generales: formato de números y fechas (`fmt_*`, en hora de Colombia vía `fmt_local()`), umbrales del semáforo, `escribir_excel()`. |
| `R/utils_db.R` | Conexión: un único `pool`; `db_get()`, `db_exec()`, `db_tx()`. |
| `R/utils_auth.R` | Usuarios, roles y permisos (`AUTH_ROLES`, `AUTH_PERMISOS`), contraseñas (scrypt), bloqueos y bitácora. |
| `R/utils_seguimiento.R` | Todo el avance: esquema `seguimiento`, `marco_completo`, metas, `seg_avance()`, detalle, personas, indicadores, series, agenda y grupos, no registrados, contratos < 6 meses, personas borradas. |
| `R/utils_contactos.R` | Bitácora de contactos (rechazo, ausente, reabrir) y `cto_aplicar()`. |
| `R/utils_resultados.R` | Resultados de la Batería: catálogo de medidas, `res_datos()`, repartos, comparaciones, desagregación, vistas de exportación. |
| `R/utils_informe.R` | Informe individual en Word sobre `plantillas/informe_individual.docx`. |
| `R/utils_informe_unidad.R` | Informe en PowerPoint por unidad, dependencia o universidad sobre `plantillas/informe_unidad.pptx`. |
| `Modules/mod_auth.R` | Ingreso, cambio de contraseña, cierre por inactividad. |
| `Modules/mod_seguimiento.R` | Pestaña Avance por dependencia (y el informe de avance en Word y la lista de personas borradas, que se muestran en Administración). |
| `Modules/mod_resultados.R` | Pestaña Resultados. |
| `Modules/mod_descarga.R` | Pestaña Descarga de datos. |
| `Modules/mod_citaciones.R` | Pestaña Citaciones y la carga de agenda (que se muestra en Administración). |
| `Modules/mod_usuarios.R` | Pestaña Administración. |
| `conectar_bd.R` | Calificación de la Batería. Script aparte, no lo carga la app. |
| `scripts/` | `cargar_marco_bateria.R` (nómina → marco), `preparar_bd.R` (base nueva desde cero), `gestionar_usuarios.R` (usuarios por terminal). |
| `www/` | `custom.css` y `grafico.js` (cruceta y tooltip de los gráficos). |

Convención: los archivos de `R/` no tienen interfaz (se pueden probar sueltos desde un `Rscript`); los de `Modules/` son módulos Shiny (`mod_x_ui()` / `mod_x_server()`) y solo arman pantallas.

## 4. Tablas

| Tabla | Quién la escribe | Ojo |
|---|---|---|
| `auth.usuarios`, `auth.bitacora_accesos` | La app (Administración) y `gestionar_usuarios.R` | La bitácora guarda todo ingreso, descarga y decisión. |
| `seguimiento.marco` | `cargar_marco_bateria.R` | Se reemplaza entera al cargar una nómina. `id_anonimizado` **es la cédula**. |
| `seguimiento.metas` | `seg_sembrar_metas()` | Llave (dependencia, tipo_dependencia). Al cambiar el marco: `--rehacer-metas`. |
| `seguimiento.citaciones` | La agenda (Google Sheet o Excel) | Se reemplaza entera en cada carga. |
| `seguimiento.grupos_aplicador`, `observacionespsicologos` | Citaciones | Asignaciones de psicólogos y anotaciones. |
| `seguimiento.contactos` | Avance (registrar contacto) | Manda el **último** contacto de cada persona. |
| `seguimiento.empleados_no_registrados` | Avance (completar / no usar) | Quien respondió sin estar en el marco, por etapa. |
| `seguimiento.decision_post_corte` | Avance (usar / no usar) | Contratos < 6 meses, por etapa. Sin fila = no se usa. |
| `seguimiento.personas_borradas` | Avance (borrar) / Administración (restaurar) | Borrado lógico: las respuestas no se tocan. |
| `public.odk_respuestas_<etapa>` | `conexion_resultados_odk.R` | Respuestas crudas; nunca se reescribe. |
| `public.respuestas_procesadas` | `conectar_bd.R` | Se reescribe entera: no guarde nada a mano allí. |

Vistas: `seguimiento.marco_completo` y `seguimiento.estado_persona` (las crea la app al arrancar), `public.respuestas_procesadas_exportacion` y `_exportacion_ind` (las crea `conectar_bd.R`).

## 5. Dónde cambiar cada cosa

| Si quiere cambiar… | Está en |
|---|---|
| Qué puede hacer cada rol | `AUTH_PERMISOS` en `R/utils_auth.R` |
| Fecha de corte de vinculación (contratos < 6 meses) | `SEG_CORTE_VINCULACION` en `R/utils_seguimiento.R` (y `--corte=` al cargar el marco) |
| Mínimo de encuestas para mostrar un grupo (7) | `SEG_MIN_N` en `R/utils_seguimiento.R` y `RES_MIN_N` en `R/utils_resultados.R` |
| Umbrales del semáforo (60 % y 90 %) | `AVANCE_CORTE_MEDIO` y `AVANCE_CORTE_BIEN` en `R/helpers.R` |
| Umbral de los focos de atención (2 pp) | `RES_UMBRAL_SIMILAR` en `R/utils_resultados.R` |
| Variables para filtrar y desagregar en Resultados | `RES_CRUCES` en `R/utils_resultados.R` |
| Forma A/B por grupo de nómina | `FORMA_GRUPO` en `scripts/cargar_marco_bateria.R` (o columna `FORMA` del Excel) |
| Capacidad de la agenda | `SEG_CIT_POR_HORA` y `SEG_CIT_GRUPOS_HORA` en `R/utils_seguimiento.R` |
| Opciones de la bitácora de contactos | `CTO_RESULTADOS` y `CTO_CIERRES` en `R/utils_contactos.R` |
| Ítems, dimensiones y baremos | `Diccionarios/*.xlsx` y `conectar_bd.R` (después, recalificar) |
| Google Sheet de inscripciones | `sheet_id` en `descarga_datos_reales/agenda_desde_google_sheets.R` |
| Formulario de ODK | `url_base` en `descarga_datos_reales/conexion_resultados_odk.R` |
| Textos y diapositivas de los informes | `plantillas/` y `R/utils_informe*.R` |

## 6. Reglas que no hay que romper

Romperlas no da error: descuadra cifras en silencio.

1. **Consulte `seguimiento.marco_completo`, no `seguimiento.marco`.** La vista ya suma a los no registrados completados y a los contratos < 6 meses usados, y quita a las personas borradas. Algunas funciones leen `marco` a propósito porque necesitan el marco oficial tal cual (la carga de la nómina, las metas, la detección de no registrados y de contratos < 6 meses, las opciones de los selectores): si escribe una consulta nueva y duda, use `marco_completo`.
2. **Excluya `seguimiento.personas_borradas`** en cualquier consulta nueva sobre personas que no pase por `marco_completo`.
3. **Una dependencia es el par (dependencia, unidad).** Hay nombres repetidos en varias unidades; la clave en SQL es `dependencia || ' · ' || tipo_dependencia`.
4. **Esperados = meta + no registrados usados + contratos < 6 meses usados.** Ver `seg_avance()`. Las metas van por dependencia y unidad.
5. **Una persona, no un envío.** Quien respondió dos veces tiene dos filas en las respuestas: cuente con `count(DISTINCT id_anonimizado)` o con el envío más reciente.
6. **Horas en hora de Colombia.** RPostgres entrega los `timestamptz` en UTC: formatee con `fmt_momento()` / `fmt_dia()` (o `tz = SEG_TZ`), nunca con `format()` a secas.
7. **Permisos dos veces.** La interfaz se dibuja con `auth_puede(rol, …)`, pero cada acción vuelve a comprobar con `auth_puede_usuario(usuario, …)` contra la base: el rol pudo cambiar con la sesión abierta.
8. **Grupos de menos de 7 encuestas no se muestran** (`SEG_MIN_N`, `RES_MIN_N`): es confidencialidad, no un error.
9. **`conectar_bd.R` tiene finales de línea de Windows (CRLF)**: edítelo sin convertirlos.
10. **El código de la app va copiado dentro de la imagen de Docker**: después de cambiarlo, `docker compose up -d --build shiny`. Lo de `descarga_datos_reales/` no necesita `--build`.

## 7. Cómo probar un cambio

1. Trabaje en una **copia local** (guía de instalación, sección 3): `docker compose up -d` desde `riesgo_psicosocial/docker` restaura el respaldo de `backups/` la primera vez.
2. Aplique el cambio con `docker compose up -d --build shiny` y compare las cifras de la app antes y después (Esperados, Encuestados, Faltan). Si una cifra cambia sin que el cambio debiera tocarla, algo está mal.
3. Para probar funciones sueltas sin la interfaz, dentro del contenedor:
   ```bash
   docker exec -it -w /app riesgo_psicosocial_shiny R
   ```
   y en R:
   ```r
   library(DBI); library(pool)
   for (f in c("R/helpers.R", "R/utils_db.R", "R/utils_auth.R", "R/utils_seguimiento.R",
               "R/utils_contactos.R", "R/utils_resultados.R")) source(f)
   seg_totales(seg_avance())$planeado   # por ejemplo: los Esperados de toda la universidad
   ```
   Es el mismo orden de `app.R`: los archivos dependen unos de otros.
4. Para volver a empezar la copia desde el respaldo: `docker compose down -v` y `docker compose up -d` (**solo en la copia local; nunca en el servidor**).
5. Guarde el cambio en Git con un mensaje claro y llévelo al servidor (guía de instalación, sección 4).

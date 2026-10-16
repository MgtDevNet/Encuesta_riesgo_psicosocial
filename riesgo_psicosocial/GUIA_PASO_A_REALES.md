# 🚀 Guía: pasar del piloto a las respuestas reales

Pasos para dejar la aplicación trabajando con las **respuestas reales** cuando termine el piloto.

Todos los comandos se escriben en la terminal de **WSL**, desde la carpeta `riesgo_psicosocial`.

---

## Paso 0. En ODK Central: sacar las respuestas del piloto

El formulario de ODK es el mismo en las dos etapas. Si no haces esto, las respuestas del piloto se
mezclan con las reales.

En ODK Central, entra al formulario `riesgo_psicosocial` → **Submissions** y marca cada envío del
piloto como **Rejected** (rechazado). No hace falta borrarlos: el script de descarga ya ignora los
rechazados.

---

## Paso 1. Sacar un respaldo de la base

```bash
docker exec riesgo_psicosocial_postgres pg_dump -U erps_user -d riesgo_psicosocial -Fc -f /tmp/bd.dump
docker cp riesgo_psicosocial_postgres:/tmp/bd.dump ./backups/fin_piloto.dump
```

Si algo sale mal, con este archivo se recupera todo.

---

## Paso 2. Guardar los resultados del piloto

La calificación de las respuestas reales va a reemplazar la tabla de resultados, así que primero se
guarda una copia aparte:

```bash
docker exec riesgo_psicosocial_postgres psql -U erps_user -d riesgo_psicosocial -c "CREATE TABLE public.respuestas_procesadas_piloto AS TABLE public.respuestas_procesadas"
```

Las respuestas crudas del piloto no necesitan este paso: siguen en `odk_respuestas_piloto` y nadie
las toca.

---

## Paso 3 (opcional). Limpiar el seguimiento del piloto

Si durante el piloto registraron contactos, citaciones o anotaciones de psicólogos, esos datos pasan
a la etapa real y afectan el avance. Por ejemplo, un "rechazo" del piloto dejaría a esa persona como
caso cerrado. Si quieres empezar en limpio:

```bash
docker exec riesgo_psicosocial_postgres psql -U erps_user -d riesgo_psicosocial -c "TRUNCATE seguimiento.contactos, seguimiento.citaciones, seguimiento.grupos_aplicador, seguimiento.observacionespsicologos"
```

Los empleados no registrados **no** hay que limpiarlos: la app los separa sola por etapa (columna
`etapa` de `seguimiento.empleados_no_registrados`).

---

## Paso 4. Cambiar la etapa

Abre `docker/.env` y cambia esta línea:

```
ETAPA=piloto
```

por:

```
ETAPA=reales
```

---

## Paso 5. Reiniciar la app

```bash
cd docker
docker compose up -d
cd ..
```

No hace falta `--build`, porque el código no cambió; solo la configuración.

---

## Paso 6. Descargar y calificar

```bash
bash descarga_datos_reales/actualizar_datos.sh --calificar
```

Como la tabla `odk_respuestas_reales` todavía no existe, el script baja todo de ODK (menos lo
rechazado) y la crea. Después de esto, el cron sigue solo cada 15 minutos.

---

## Paso 7. Comprobar que quedó bien

1. Abre la app. En **Avance**, al final, la tabla de no registrados debe decir **"· etapa reales"**.
   Al principio debería estar vacía o tener solo personas nuevas.
2. Los encuestados deben ser solo las respuestas reales. Si aparecen respuestas del piloto, faltó
   rechazarlas en ODK (Paso 0).
3. Si quieres revisar la base, en DBeaver deberías ver **`odk_respuestas_piloto`**,
   **`odk_respuestas_reales`** y **`respuestas_procesadas_piloto`**.

---

## Resumen rápido

| # | Qué | Dónde |
|-|-|-|
| 0 | Rechazar los envíos del piloto | ODK Central |
| 1 | Respaldo | terminal |
| 2 | Guardar `respuestas_procesadas_piloto` | terminal |
| 3 | (Opcional) limpiar contactos y citaciones | terminal |
| 4 | `ETAPA=reales` | `docker/.env` |
| 5 | `docker compose up -d` | terminal, carpeta `docker` |
| 6 | `actualizar_datos.sh --calificar` | terminal |
| 7 | Revisar la app | navegador |

---

## Si algo sale mal

Vuelve a poner `ETAPA=piloto` en `docker/.env` y corre `docker compose up -d` desde la carpeta
`docker`: la app queda como estaba en el piloto. La tabla `odk_respuestas_reales` puede quedarse ahí
sin estorbar.

Si hace falta recuperar la base completa, el respaldo del Paso 1 está en `backups/fin_piloto.dump`
(ver Parte 2, paso 3 de `INSTRUCCIONES_DOCKER.md` para cargarlo).

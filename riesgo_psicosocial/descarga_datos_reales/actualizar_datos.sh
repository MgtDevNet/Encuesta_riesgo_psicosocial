#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# actualizar_datos.sh
# Lo que corre el cron: trae de ODK los envios nuevos y, si llego alguno, los
# califica para que la Shiny los muestre.
#
#   1. conexion_resultados_odk.R  ODK -> public.odk_respuestas_<etapa> (ETAPA en docker/.env)
#   2. conectar_bd.R              -> public.respuestas_procesadas (lo que lee la app)
#
# Los dos pasos corren DENTRO del contenedor de la Shiny: asi usan exactamente
# el mismo R y los mismos paquetes que la app, y este equipo solo necesita
# Docker, sin instalar R. Esta carpeta se monta en el contenedor como /descarga
# (ver docker-compose.yml). El paso 2 solo corre si el paso 1 inserto envios
# nuevos (codigo de salida 10), o si una calificacion anterior quedo pendiente
# porque fallo.
#
# Uso en el crontab (cada 15 minutos):
#   */15 * * * * /bin/bash /ruta/a/descarga_datos_reales/actualizar_datos.sh >> /ruta/a/descarga_datos_reales/logs_conexion.txt 2>&1
#
# Para forzar la calificacion aunque no haya envios nuevos:
#   bash actualizar_datos.sh --calificar
# -----------------------------------------------------------------------------
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTENEDOR="${CONTENEDOR_SHINY:-riesgo_psicosocial_shiny}"
PENDIENTE="$DIR/.calificacion_pendiente"
CANDADO="$DIR/.actualizar_datos.lock"

# cron arranca con un PATH minimo: sin esto puede no encontrar Rscript ni docker.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Una corrida a la vez. Calificar puede tardar mas de 15 minutos cuando haya
# miles de respuestas, y dos conectar_bd.R a la vez se pisarian la tabla.
exec 9>"$CANDADO"
if ! flock -n 9; then
  log "Otra actualizacion sigue corriendo; se omite esta."
  exit 0
fi

[ "${1:-}" = "--calificar" ] && touch "$PENDIENTE"

if ! docker inspect -f '{{.State.Running}}' "$CONTENEDOR" 2>/dev/null | grep -q true; then
  log "ERROR: el contenedor $CONTENEDOR no esta corriendo; no se puede descargar ni calificar."
  exit 1
fi

# --- 1. Descarga de ODK -------------------------------------------------------
log "Descargando envios de ODK..."
docker exec "$CONTENEDOR" Rscript /descarga/conexion_resultados_odk.R
codigo=$?

# 126/127 = docker no pudo ejecutar el script: casi siempre es que el contenedor
# se creo antes de montar /descarga y hay que recrearlo.
if [ "$codigo" = 126 ] || [ "$codigo" = 127 ] || \
   ! docker exec "$CONTENEDOR" test -f /descarga/conexion_resultados_odk.R; then
  log "ERROR: el contenedor no ve /descarga. Recreelo: docker compose up -d shiny (desde docker/)."
fi

case "$codigo" in
  0)  log "Sin envios nuevos." ;;
  10) log "Llegaron envios nuevos."
      touch "$PENDIENTE" ;;
  *)  log "ERROR: la descarga de ODK fallo (codigo $codigo)." ;;
esac

# --- 2. Calificacion ----------------------------------------------------------
# La marca de pendiente se borra solo cuando conectar_bd.R termina bien: si
# falla, la proxima corrida lo vuelve a intentar aunque ODK no traiga nada nuevo.
if [ -f "$PENDIENTE" ]; then
  log "Calificando con conectar_bd.R en $CONTENEDOR..."
  if docker exec "$CONTENEDOR" sh -c "cd /app && Rscript conectar_bd.R"; then
    rm -f "$PENDIENTE"
    log "Calificacion lista: la Shiny mostrara los envios nuevos en menos de un minuto."
  else
    log "ERROR: conectar_bd.R fallo; se reintentara en la proxima corrida."
    exit 1
  fi
fi

# Si la descarga fallo, el cron lo registra como fallo aunque la calificacion
# pendiente haya salido bien.
[ "$codigo" = 0 ] || [ "$codigo" = 10 ] || exit 1
exit 0

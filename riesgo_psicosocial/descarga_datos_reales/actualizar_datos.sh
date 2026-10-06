#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# actualizar_datos.sh
# Lo que corre el cron: trae de ODK los envios nuevos y, si llego alguno, los
# califica para que la Shiny los muestre.
#
#   1. conexion_resultados_odk.R  ODK -> public.odk_respuestas_intento_2
#   2. conectar_bd.R              -> public.respuestas_procesadas (lo que lee la app)
#
# El paso 2 corre DENTRO del contenedor de la Shiny: asi usa exactamente el
# mismo codigo, diccionarios y paquetes que la app, y este equipo no necesita
# tenerlos instalados. Solo corre si el paso 1 inserto envios nuevos (codigo de
# salida 10), o si una calificacion anterior quedo pendiente porque fallo.
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

# --- 1. Descarga de ODK -------------------------------------------------------
log "Descargando envios de ODK..."
Rscript "$DIR/conexion_resultados_odk.R"
codigo=$?

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
  if ! docker inspect -f '{{.State.Running}}' "$CONTENEDOR" 2>/dev/null | grep -q true; then
    log "ERROR: el contenedor $CONTENEDOR no esta corriendo; la calificacion queda pendiente."
    exit 1
  fi
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

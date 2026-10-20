#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# actualizar_agenda.sh
# Lo que corre el cron: lee las inscripciones del Google Sheet y, si cambiaron,
# reemplaza la agenda de citaciones en la base (agenda_desde_google_sheets.R
# --cargar). La Shiny la muestra en menos de un minuto, sin recargar.
#
# Corre DENTRO del contenedor de la Shiny, como actualizar_datos.sh: usa el
# mismo R, los mismos paquetes y las mismas funciones de la agenda que la app.
# Esta carpeta se monta en el contenedor como /descarga (ver docker-compose.yml).
#
# Uso en el crontab (cada 30 minutos):
#   */30 * * * * /bin/bash /ruta/a/descarga_datos_reales/actualizar_agenda.sh >> /ruta/a/descarga_datos_reales/logs_agenda.txt 2>&1
# -----------------------------------------------------------------------------
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTENEDOR="${CONTENEDOR_SHINY:-riesgo_psicosocial_shiny}"
CANDADO="$DIR/.actualizar_agenda.lock"

# cron arranca con un PATH minimo: sin esto puede no encontrar docker.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

exec 9>"$CANDADO"
if ! flock -n 9; then
  log "Otra actualizacion de la agenda sigue corriendo; se omite esta."
  exit 0
fi

if ! docker inspect -f '{{.State.Running}}' "$CONTENEDOR" 2>/dev/null | grep -q true; then
  log "ERROR: el contenedor $CONTENEDOR no esta corriendo; no se puede actualizar la agenda."
  exit 1
fi

log "Leyendo la agenda del Google Sheet..."
docker exec "$CONTENEDOR" Rscript /descarga/agenda_desde_google_sheets.R --cargar
codigo=$?

case "$codigo" in
  0)  log "La agenda no cambio." ;;
  10) log "Agenda actualizada en la base." ;;
  *)  log "ERROR: la actualizacion de la agenda fallo (codigo $codigo); la agenda anterior sigue igual."
      exit 1 ;;
esac
exit 0

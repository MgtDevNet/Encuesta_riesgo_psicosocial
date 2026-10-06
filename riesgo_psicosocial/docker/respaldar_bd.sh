#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# respaldar_bd.sh
# Saca una copia completa de la base (marco, respuestas, usuarios, citaciones,
# contactos, metas, observaciones) y borra las copias de mas de DIAS_RETENCION
# dias. Lo corre el cron; tambien se puede correr a mano:
#   bash respaldar_bd.sh
#
# Las copias quedan en riesgo_psicosocial/backups/ como bd_AAAA-MM-DD_HHMM.dump
# (formato de pg_restore; ver INSTRUCCIONES_DOCKER.md para restaurarlas). Esa
# carpeta esta en .gitignore: las copias tienen datos personales y NO van a git.
#
# Uso en el crontab (12:30 y 17:30, en horario en que el equipo esta encendido):
#   30 12,17 * * * /bin/bash /ruta/a/riesgo_psicosocial/docker/respaldar_bd.sh >> /ruta/a/riesgo_psicosocial/backups/respaldos.log 2>&1
#
# Variables opcionales:
#   DESTINO_RESPALDOS  carpeta de destino (por defecto riesgo_psicosocial/backups)
#   DIAS_RETENCION     dias que se guardan las copias (por defecto 30)
# -----------------------------------------------------------------------------
set -u

PROYECTO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINO="${DESTINO_RESPALDOS:-$PROYECTO/backups}"
DIAS="${DIAS_RETENCION:-30}"
CONTENEDOR="${CONTENEDOR_BD:-riesgo_psicosocial_postgres}"
TMP="/tmp/respaldo_en_curso.dump"

# cron arranca con un PATH minimo: sin esto puede no encontrar docker.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if ! docker inspect -f '{{.State.Running}}' "$CONTENEDOR" 2>/dev/null | grep -q true; then
  log "ERROR: el contenedor $CONTENEDOR no esta corriendo; no se saco la copia."
  exit 1
fi

mkdir -p "$DESTINO"
ARCHIVO="$DESTINO/bd_$(date '+%Y-%m-%d_%H%M').dump"

# El usuario y la base se leen DENTRO del contenedor (las variables con que se
# creo, que vienen de docker/.env), asi este script no repite credenciales.
# pg_dump trabaja sobre una foto consistente de la base: se puede correr
# mientras la app o la descarga de ODK estan escribiendo.
if ! docker exec "$CONTENEDOR" sh -c \
     'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc -f '"$TMP"; then
  log "ERROR: pg_dump fallo; no se saco la copia."
  docker exec "$CONTENEDOR" rm -f "$TMP" >/dev/null 2>&1
  exit 1
fi

# Se comprueba que la copia se pueda leer ANTES de darla por buena: una copia
# corrupta que nadie revisa es peor que no tenerla.
if ! docker exec "$CONTENEDOR" pg_restore -l "$TMP" >/dev/null 2>&1; then
  log "ERROR: la copia generada no se puede leer; se descarta."
  docker exec "$CONTENEDOR" rm -f "$TMP" >/dev/null 2>&1
  exit 1
fi

# Se copia con otro nombre y se renombra al final: si algo se corta a mitad,
# nunca queda un bd_*.dump incompleto que parezca valido.
if ! docker cp "$CONTENEDOR:$TMP" "$ARCHIVO.parcial" >/dev/null; then
  log "ERROR: no se pudo copiar el respaldo fuera del contenedor."
  rm -f "$ARCHIVO.parcial"
  docker exec "$CONTENEDOR" rm -f "$TMP" >/dev/null 2>&1
  exit 1
fi
mv "$ARCHIVO.parcial" "$ARCHIVO"
docker exec "$CONTENEDOR" rm -f "$TMP" >/dev/null 2>&1

TAM="$(du -h "$ARCHIVO" | cut -f1)"
log "Copia lista: $ARCHIVO ($TAM)"

# Retencion: solo toca los bd_AAAA-MM-DD_HHMM.dump que crea este script; nunca
# bd.dump ni otras copias hechas a mano.
BORRADOS="$(find "$DESTINO" -maxdepth 1 -type f -name 'bd_????-??-??_????.dump' -mtime +"$DIAS" -print -delete | wc -l)"
[ "$BORRADOS" -gt 0 ] && log "Borradas $BORRADOS copias de mas de $DIAS dias."

exit 0

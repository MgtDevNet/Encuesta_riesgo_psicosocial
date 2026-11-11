#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# restaurar_respaldo.sh
# Restaura sola la base la PRIMERA vez que se levanta el proyecto en un equipo.
#
# docker-compose.yml lo monta en /docker-entrypoint-initdb.d/ del contenedor de
# PostgreSQL, y la imagen oficial lo corre una unica vez: cuando el volumen de
# la base esta vacio (equipo nuevo, o despues de `docker compose down -v`). En
# un equipo que ya tiene la base no corre nunca, asi que no pisa nada.
#
# Toma el respaldo mas reciente de riesgo_psicosocial/backups/ con nombre
# bd_AAAA-MM-DD_HHMM.dump (los que saca respaldar_bd.sh), montada como
# /respaldos. Si no hay ninguno, deja la base vacia y la app crea sus tablas.
#
# Mientras corre, PostgreSQL solo escucha por el socket interno: el healthcheck
# de docker-compose.yml pregunta por TCP, asi que la Shiny no arranca --ni crea
# tablas vacias que choquen con el respaldo-- hasta que la restauracion termina.
# -----------------------------------------------------------------------------
set -e

respaldo="$(ls -1 /respaldos/bd_*.dump 2>/dev/null | sort | tail -n 1 || true)"

if [ -z "$respaldo" ]; then
  echo "restaurar_respaldo: no hay respaldos bd_*.dump en backups/; la base queda vacia."
  exit 0
fi

echo "restaurar_respaldo: restaurando $respaldo ..."
pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner "$respaldo"
echo "restaurar_respaldo: listo. Personas en el marco: $(psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc 'SELECT count(*) FROM seguimiento.marco')"

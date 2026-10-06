#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# cargar_respuestas_odk.sh
# Carga Simulacion_respuestas_ODK.csv en seguimiento.respuestas_odk.
#
#   scripts/cargar_respuestas_odk.sh [ruta/al/archivo.csv]
#
# Es idempotente: al terminar, la tabla tiene exactamente las filas del CSV.
# Todo va dentro de una transaccion; si algo falla a mitad, el ROLLBACK deja la
# base como estaba y la Shiny no llega a ver nada raro.
#
# NO se usa TRUNCATE: seguimiento.puntajes referencia respuestas_odk(clave) con
# ON DELETE CASCADE, y vaciar la tabla padre se llevaria por delante los 74 mil
# puntajes ya calculados. En su lugar se carga a una tabla de paso y se hace
# upsert por clave; solo se borran las claves que ya no vienen en el CSV (y esas
# si deben perder sus puntajes).
#
# La lista de columnas del \copy va en el ORDEN DEL CSV, no en el de la tabla, y
# traduce los nombres de ODK a los de la base: SubmissionDate, start, end y KEY
# son submission_date, inicio, fin y clave; los "años_*" van sin enye. Si el
# formulario cambia de columnas, hay que actualizar esa lista.
#
# El SET TIME ZONE hace falta porque el CSV trae las marcas de tiempo sin huso
# (2026-08-07T18:31:35): sin el, Postgres las lee como UTC y todos los envios
# quedan cinco horas corridos.
# -----------------------------------------------------------------------------
set -euo pipefail

CSV="${1:-$(dirname "$0")/../../Simulacion_respuestas_ODK.csv}"
CSV="$(readlink -f "$CSV")"
PGDB="${PG_DB:-riesgo_psicosocial}"

[ -f "$CSV" ] || { echo "No se encuentra: $CSV" >&2; exit 1; }
echo "cargando $CSV en $PGDB ..."

psql -d "$PGDB" -v ON_ERROR_STOP=1 <<SQL
BEGIN;
SET LOCAL TIME ZONE 'America/Bogota';

DROP TABLE IF EXISTS seguimiento.respuestas_odk_stage;
CREATE TABLE seguimiento.respuestas_odk_stage (LIKE seguimiento.respuestas_odk);

\copy seguimiento.respuestas_odk_stage (submission_date, inicio, fin, duracion_min, deviceid, clave, id_anonimizado, dependencia, sede_seccional, tipo_vinculacion, nivel_empleo, forma_cuestionario, consentimiento, cedula, cal_nombre, cal_naci, cal_sexo, nombre, sexo, nacimiento, estado_civil, nivel_academico, ocupacion, departamento, ciudad, estrato, vivienda, dependientes, departamento_lab, ciudad_lab, anos_lab, anos_lab_num, cargo, tipo_cargo, anos_cargo, anos_cargo_num, area, tipo_contrato, horas, tipo_salario, form_intra, ila_val1, ila_val2, ila_p1, ila_p2, ila_p3, ila_p4, ila_p5, ila_p6, ila_p7, ila_p8, ila_p9, ila_p10, ila_p11, ila_p12, ila_p13, ila_p14, ila_p15, ila_p16, ila_p17, ila_p18, ila_p19, ila_p20, ila_p21, ila_p22, ila_p23, ila_p24, ila_p25, ila_p26, ila_p27, ila_p28, ila_p29, ila_p30, ila_p31, ila_p32, ila_p33, ila_p34, ila_p35, ila_p36, ila_p37, ila_p38, ila_p39, ila_p40, ila_p41, ila_p42, ila_p43, ila_p44, ila_p45, ila_p46, ila_p47, ila_p48, ila_p49, ila_p50, ila_p51, ila_p52, ila_p53, ila_p54, ila_p55, ila_p56, ila_p57, ila_p58, ila_p59, ila_p60, ila_p61, ila_p62, ila_p63, ila_p64, ila_p65, ila_p66, ila_p67, ila_p68, ila_p69, ila_p70, ila_p71, ila_p72, ila_p73, ila_p74, ila_p75, ila_p76, ila_p77, ila_p78, ila_p79, ila_p80, ila_p81, ila_p82, ila_p83, ila_p84, ila_p85, ila_p86, ila_p87, ila_p88, ila_p89, ila_p90, ila_p91, ila_p92, ila_p93, ila_p94, ila_p95, ila_p96, ila_p97, ila_p98, ila_p99, ila_p100, ila_p101, ila_p102, ila_p103, ila_p104, ila_p105, ila_p106, ila_p107, ila_p108, ila_p109, ila_p110, ila_p111, ila_p112, ila_p113, ila_p114, ila_p115, ila_p116, ila_p117, ila_p118, ila_p119, ila_p120, ila_p121, ila_p122, ila_p123, ilb_val1, ilb_p1, ilb_p2, ilb_p3, ilb_p4, ilb_p5, ilb_p6, ilb_p7, ilb_p8, ilb_p9, ilb_p10, ilb_p11, ilb_p12, ilb_p13, ilb_p14, ilb_p15, ilb_p16, ilb_p17, ilb_p18, ilb_p19, ilb_p20, ilb_p21, ilb_p22, ilb_p23, ilb_p24, ilb_p25, ilb_p26, ilb_p27, ilb_p28, ilb_p29, ilb_p30, ilb_p31, ilb_p32, ilb_p33, ilb_p34, ilb_p35, ilb_p36, ilb_p37, ilb_p38, ilb_p39, ilb_p40, ilb_p41, ilb_p42, ilb_p43, ilb_p44, ilb_p45, ilb_p46, ilb_p47, ilb_p48, ilb_p49, ilb_p50, ilb_p51, ilb_p52, ilb_p53, ilb_p54, ilb_p55, ilb_p56, ilb_p57, ilb_p58, ilb_p59, ilb_p60, ilb_p61, ilb_p62, ilb_p63, ilb_p64, ilb_p65, ilb_p66, ilb_p67, ilb_p68, ilb_p69, ilb_p70, ilb_p71, ilb_p72, ilb_p73, ilb_p74, ilb_p75, ilb_p76, ilb_p77, ilb_p78, ilb_p79, ilb_p80, ilb_p81, ilb_p82, ilb_p83, ilb_p84, ilb_p85, ilb_p86, ilb_p87, ilb_p88, ilb_p89, ilb_p90, ilb_p91, ilb_p92, ilb_p93, ilb_p94, ilb_p95, ilb_p96, ilb_p97, el_p1, el_p2, el_p3, el_p4, el_p5, el_p6, el_p7, el_p8, el_p9, el_p10, el_p11, el_p12, el_p13, el_p14, el_p15, el_p16, el_p17, el_p18, el_p19, el_p20, el_p21, el_p22, el_p23, el_p24, el_p25, el_p26, el_p27, el_p28, el_p29, el_p30, el_p31, ee_p1, ee_p2, ee_p3, ee_p4, ee_p5, ee_p6, ee_p7, ee_p8, ee_p9, ee_p10, ee_p11, ee_p12, ee_p13, ee_p14, ee_p15, ee_p16, ee_p17, ee_p18, ee_p19, ee_p20, ee_p21, ee_p22, ee_p23, ee_p24, ee_p25, ee_p26, ee_p27, ee_p28, ee_p29, ee_p30, ee_p31) FROM '$CSV' WITH (FORMAT csv, HEADER true)

-- El INSERT nombra las 326 columnas dos veces (lista y SET), asi que se arma
-- desde el catalogo en vez de escribirlo a mano.
DO \$\$
DECLARE cols text; sets text;
BEGIN
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position),
         string_agg(format('%I = EXCLUDED.%I', column_name, column_name),
                    ', ' ORDER BY ordinal_position)
    INTO cols, sets
    FROM information_schema.columns
   WHERE table_schema = 'seguimiento' AND table_name = 'respuestas_odk';

  EXECUTE format(
    'INSERT INTO seguimiento.respuestas_odk (%s) SELECT %s
       FROM seguimiento.respuestas_odk_stage
       ON CONFLICT (clave) DO UPDATE SET %s', cols, cols, sets);
END \$\$;

DELETE FROM seguimiento.respuestas_odk r
 WHERE NOT EXISTS (SELECT 1 FROM seguimiento.respuestas_odk_stage s
                    WHERE s.clave = r.clave);

-- No se redondea duracion_min: COPY guarda el texto del CSV tal cual, que ya
-- viene con un decimal. El round(.,1) que hace conectar_bd.R es para lo que
-- escribe R, que si manda los double con toda su precision.

DROP TABLE seguimiento.respuestas_odk_stage;
COMMIT;
SQL

psql -d "$PGDB" -c "SELECT count(*) AS filas,
                           count(DISTINCT id_anonimizado) AS personas,
                           min(submission_date) AS primer_envio,
                           max(submission_date) AS ultimo_envio
                      FROM seguimiento.respuestas_odk"

psql -d "$PGDB" -c "SELECT count(*) AS respuestas_sin_marco
                      FROM seguimiento.respuestas_odk r
                     WHERE NOT EXISTS (SELECT 1 FROM seguimiento.marco m
                                        WHERE m.id_anonimizado = r.id_anonimizado)"

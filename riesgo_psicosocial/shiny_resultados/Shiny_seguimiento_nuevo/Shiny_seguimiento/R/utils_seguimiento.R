# -----------------------------------------------------------------------------
# utils_seguimiento.R
# Consultas del avance de la aplicación por dependencia. Sin nada de UI.
#
# Población elegible = personas del marco con estado_vinculacion 'Activo'.
# Planeado = meta editable por dependencia (tabla seguimiento.metas).
# Encuestados = elegibles con al menos una respuesta registrada.
# -----------------------------------------------------------------------------

# Mínimo de encuestas para mostrar promedios agregados de una dependencia.
# Evita que un promedio delate la respuesta de una persona concreta, que es
# justo lo que la Batería exige reservar (manual general, §6.2).
SEG_MIN_N <- 7L

# --- Arranque del esquema -----------------------------------------------------
# Igual que auth_init_db() y cto_init_db(): crea lo que falte y no toca lo que
# ya este. Aqui se declaran las DOS tablas que se cargan desde fuera --el marco
# y el export de ODK-- para que en un equipo nuevo exista donde volcarlas antes
# de haber corrido nada. seguimiento.respuestas no se crea aqui: la escribe
# conectar_bd.R, que es quien sabe cuantas columnas de clasificacion tiene.

# Las 326 columnas del formulario, en el mismo orden en que las manda ODK. Los
# items van por bloque: forma A (con sus dos preguntas de filtro), forma B (con
# la suya), extralaboral y estres. Las trece ultimas son la caracterizacion
# laboral, que se agrego despues del primer despliegue y por eso va al final.
SEG_ODK_COLUMNAS <- c(
  "submission_date timestamptz", "inicio timestamptz", "fin timestamptz",
  "duracion_min numeric", "deviceid text", "clave text PRIMARY KEY",
  "id_anonimizado text", "dependencia text", "sede_seccional text",
  "tipo_vinculacion text", "nivel_empleo text", "forma_cuestionario text",
  "nombre text", "sexo smallint", "nacimiento timestamptz",
  "estado_civil smallint", "nivel_academico smallint", "ocupacion text",
  "departamento text", "ciudad text", "estrato smallint", "vivienda smallint",
  "dependientes smallint",
  "ila_val1 smallint", "ila_val2 smallint", paste0("ila_p", 1:123, " smallint"),
  "ilb_val1 smallint",                      paste0("ilb_p", 1:97,  " smallint"),
  paste0("el_p", 1:31, " smallint"),
  paste0("ee_p", 1:31, " smallint"),
  "consentimiento smallint", "cedula text", "cal_nombre text",
  "cal_naci timestamptz", "cal_sexo smallint",
  "departamento_lab text", "ciudad_lab text",
  "anos_lab smallint", "anos_lab_num smallint",
  "cargo text", "tipo_cargo smallint",
  "anos_cargo smallint", "anos_cargo_num smallint",
  "area text", "tipo_contrato smallint", "horas smallint",
  "tipo_salario smallint", "form_intra smallint")

seg_init_db <- function() {
  db_exec("CREATE SCHEMA IF NOT EXISTS seguimiento")

  # El marco muestral: una fila por persona de la institucion, la haya
  # contestado o no. Es el denominador de todo el seguimiento.
  db_exec("
    CREATE TABLE IF NOT EXISTS seguimiento.marco (
      id_anonimizado               text PRIMARY KEY,
      dependencia                  text NOT NULL,
      tipo_dependencia             text,
      nivel_jerarquico_dependencia text,
      centro_costo                 text,
      sede_seccional               text,
      municipio                    text,
      tipo_vinculacion             text,
      nivel_empleo                 text,
      forma_cuestionario           text,
      estado_vinculacion           text,
      dedicacion                   text,
      modalidad_trabajo            text,
      trabaja_por_turnos           text
    )")

  # Columnas del archivo de nomina, que se carga TAL CUAL (ver
  # scripts/cargar_marco_bateria.R): las de arriba son las que consulta la app y
  # se derivan de estas al cargar. Se agregan sueltas y no en el CREATE para no
  # romper una instalacion que ya tenga la tabla con las catorce de siempre.
  #
  # `nombre` es la primera vez que la app guarda el nombre de una persona del
  # marco. Antes solo estaba el id: ahora la nomina real llega con nombre y
  # documento, y la pestana de personas los muestra.
  # Los nombres son los del archivo en minusculas; los repetidos (OFICIO y
  # CATEGORIA vienen dos veces) llevan sufijo, y col_15 es la columna que viene
  # sin encabezado. Los produce cargar_marco_bateria.R.
  for (col in c("identificacion", "nombre", "tipo_dcto", "novedad", "concepto",
                "fechanacimiento", "sexo", "descripcion_tipoe", "clase_tipo_empleado",
                "secuencvinculac", "categoria", "categoria_1", "nro_contrato_cat",
                "fechainivinc", "fechafinvinc", "col_15", "oficio", "oficio_1",
                "grupo", "codigo_unidad", "descripcion_unidad", "codigo_dependencia",
                "descripcion_dependencia", "totalvinc", "totalempl")) {
    db_exec(sprintf("ALTER TABLE seguimiento.marco ADD COLUMN IF NOT EXISTS %s text", col))
  }
  db_exec("CREATE INDEX IF NOT EXISTS idx_marco_dep
             ON seguimiento.marco (dependencia)")

  # El formulario crudo, tal como sale de ODK. Es el origen del que se deriva
  # seguimiento.respuestas, y ademas el modulo de resultados lo consulta
  # directamente para la caracterizacion de la persona (sexo, estrato, nivel
  # academico y fecha de nacimiento).
  db_exec(sprintf("
    CREATE TABLE IF NOT EXISTS seguimiento.respuestas_odk (
      %s
    )", paste(SEG_ODK_COLUMNAS, collapse = ",\n      ")))
  db_exec("CREATE INDEX IF NOT EXISTS idx_odk_id
             ON seguimiento.respuestas_odk (id_anonimizado)")
  db_exec("CREATE INDEX IF NOT EXISTS idx_odk_dep
             ON seguimiento.respuestas_odk (dependencia)")

  # Las metas son lo unico que se edita desde el lado del seguimiento, asi que
  # esta tabla nunca se reescribe: solo se le agregan las dependencias nuevas.
  db_exec("
    CREATE TABLE IF NOT EXISTS seguimiento.metas (
      dependencia     text PRIMARY KEY,
      planeado        integer     NOT NULL DEFAULT 0,
      nota            text,
      actualizado     timestamptz NOT NULL DEFAULT now(),
      actualizado_por text
    )")

  # Las citaciones: a quien se cita, que dia, en que franja y por que link. Es el
  # TERCER insumo externo --llega en una base aparte, como el marco y ODK-- y se
  # reemplaza entero en cada carga (scripts/preparar_bd.R --citaciones=): es una
  # foto de la agenda, y una cita que se quito de la programacion tiene que dejar
  # de contar.
  #
  # Sin clave foranea contra el marco, por la misma razon que contactos: el marco
  # se recarga desde fuera y no debe arrastrar la agenda consigo.
  #
  # El nombre SI se guarda, aunque el resto de la app trabaje solo con
  # id_anonimizado: el psicologo que aplica tiene delante personas, no ids, y sin
  # el nombre no puede anotar a quien atendio. Solo lo ve quien puede anotar esa
  # sesion --el psicologo del grupo y el administrador--, en la pestana de
  # anotaciones; ninguna otra pantalla lo muestra. Es opcional: si el archivo no
  # trae la columna, queda en NULL y las anotaciones van por id.
  db_exec("
    CREATE TABLE IF NOT EXISTS seguimiento.citaciones (
      id_anonimizado text NOT NULL,
      fecha          date NOT NULL,
      hora_inicio    time NOT NULL,
      hora_fin       time NOT NULL,
      link           text,
      nombre         text
    )")
  db_exec("ALTER TABLE seguimiento.citaciones ADD COLUMN IF NOT EXISTS nombre text")
  db_exec("CREATE INDEX IF NOT EXISTS idx_citaciones_persona
             ON seguimiento.citaciones (id_anonimizado)")

  # Quien aplica cada grupo de la agenda. Un grupo no tiene id propio --la agenda
  # se reemplaza entera-- asi que se identifica por fecha, franja y link, y la
  # asignacion sobrevive a una recarga mientras el grupo siga en la agenda. El
  # link sin valor se guarda como '' para que pueda ir en la clave primaria, que
  # es la que garantiza una sola persona por grupo aunque dos lo tomen a la vez.
  # Sin clave foranea contra auth.usuarios: borrar una cuenta no debe borrar
  # quien aplico los grupos que ya pasaron.
  db_exec("
    CREATE TABLE IF NOT EXISTS seguimiento.grupos_aplicador (
      fecha        date        NOT NULL,
      hora_inicio  time        NOT NULL,
      hora_fin     time        NOT NULL,
      link         text        NOT NULL DEFAULT '',
      usuario      text        NOT NULL,
      asignado     timestamptz NOT NULL DEFAULT now(),
      asignado_por text        NOT NULL,
      PRIMARY KEY (fecha, hora_inicio, hora_fin, link)
    )")

  # Anotaciones de los psicologos sobre cada sesion. Una sola tabla con dos tipos
  # de fila: 'grupo' (la anotacion de toda la sesion) y 'persona' (la de alguien
  # en particular). Solo se guarda lo que tenga texto: una anotacion vacia se
  # borra. El indice unico deja una fila de grupo por sesion y una por persona.
  #
  # No lleva asistencia ni estado de la sesion: marcar persona por persona
  # resulto mas trabajo del que valia. Lo que hace falta es poder escribir.
  #
  # Es el registro de lo que paso, asi que --a diferencia de grupos_aplicador--
  # no se borra al recargar la agenda, y no tiene clave foranea contra el marco
  # ni contra la agenda, por la misma razon que contactos. `psicologo` es a quien
  # estaba asignado el grupo al registrar; `registrado_por` y `actualizado_por`,
  # quien escribio (el administrador puede corregir).
  db_exec("
    CREATE TABLE IF NOT EXISTS seguimiento.observacionespsicologos (
      id                   bigserial   PRIMARY KEY,
      tipo                 text        NOT NULL,
      fecha                date        NOT NULL,
      hora_inicio          time        NOT NULL,
      hora_fin             time        NOT NULL,
      link                 text        NOT NULL DEFAULT '',
      id_anonimizado       text,
      observacion          text        NOT NULL,
      psicologo            text,
      registrado_por       text        NOT NULL,
      registrado_en        timestamptz NOT NULL DEFAULT now(),
      actualizado_por      text,
      actualizado_en       timestamptz,
      CONSTRAINT obs_psicologos_tipo CHECK (
        (tipo = 'grupo'   AND id_anonimizado IS NULL) OR
        (tipo = 'persona' AND id_anonimizado IS NOT NULL))
    )")

  # Migracion de la primera version, que pedia asistencia y estado de la sesion.
  # Es idempotente: si las columnas ya no estan, no hace nada.
  db_exec("ALTER TABLE seguimiento.observacionespsicologos
             DROP CONSTRAINT IF EXISTS obs_psicologos_tipo")
  for (col in c("estado_sesion", "motivo", "motivo_otro", "asistencia",
                "requiere_seguimiento")) {
    db_exec(sprintf("ALTER TABLE seguimiento.observacionespsicologos
                       DROP COLUMN IF EXISTS %s", col))
  }
  db_exec("DELETE FROM seguimiento.observacionespsicologos WHERE observacion IS NULL")
  db_exec("ALTER TABLE seguimiento.observacionespsicologos
             ALTER COLUMN observacion SET NOT NULL")
  db_exec("
    ALTER TABLE seguimiento.observacionespsicologos
      ADD CONSTRAINT obs_psicologos_tipo CHECK (
        (tipo = 'grupo'   AND id_anonimizado IS NULL) OR
        (tipo = 'persona' AND id_anonimizado IS NOT NULL))")
  db_exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_obs_psicologos_clave
             ON seguimiento.observacionespsicologos
                (fecha, hora_inicio, hora_fin, link, (COALESCE(id_anonimizado, '')))")
  db_exec("CREATE INDEX IF NOT EXISTS idx_obs_psicologos_persona
             ON seguimiento.observacionespsicologos (id_anonimizado)")

  # Las dos variables del desenlace, dentro de seguimiento.respuestas. La tabla
  # la escribe conectar_bd.R --que ya las trae-- pero una instalacion que
  # todavia no haya recargado los datos se quedaria sin ellas: se agregan y se
  # rellenan aqui, que cuesta nada y no obliga a esperar a la proxima carga.
  #
  # Salen de `acepta`, de la MISMA fila, asi que este UPDATE no puede quedar
  # desactualizado: no dependen de ninguna otra tabla. Y `encuestados` es TRUE
  # en todas las filas porque tener fila aqui ES haber enviado; las personas sin
  # envio --las categorias 3 a 6-- no estan en esta tabla y hay que buscarlas en
  # seguimiento.estado_persona.
  #
  # El WHERE deja el UPDATE en cero filas a partir de la segunda vez, asi que
  # arrancar la app no reescribe la tabla entera cada vez.
  if (isTRUE(nrow(db_get("SELECT 1 FROM information_schema.tables
                           WHERE table_schema = 'public'
                             AND table_name   = 'respuestas_procesadas'")) > 0)) {
    # db_exec("ALTER TABLE seguimiento.respuestas
    #            ADD COLUMN IF NOT EXISTS encuestados boolean")
    db_exec("ALTER TABLE public.respuestas_procesadas
               ADD COLUMN IF NOT EXISTS encuestados boolean")
    # db_exec("ALTER TABLE seguimiento.respuestas
    #            ADD COLUMN IF NOT EXISTS resultado_final_persona smallint")
    db_exec("ALTER TABLE public.respuestas_procesadas
               ADD COLUMN IF NOT EXISTS resultado_final_persona smallint")
    # db_exec("UPDATE seguimiento.respuestas
    #             SET encuestados             = TRUE,
    #                 resultado_final_persona = CASE WHEN acepta IS TRUE THEN 1 ELSE 2 END
    #           WHERE encuestados IS DISTINCT FROM TRUE
    #              OR resultado_final_persona IS DISTINCT FROM
    #                 CASE WHEN acepta IS TRUE THEN 1 ELSE 2 END")
    db_exec("UPDATE public.respuestas_procesadas
                SET encuestados             = TRUE,
                    resultado_final_persona = CASE WHEN acepta IS TRUE THEN 1 ELSE 2 END
              WHERE encuestados IS DISTINCT FROM TRUE
                 OR resultado_final_persona IS DISTINCT FROM
                    CASE WHEN acepta IS TRUE THEN 1 ELSE 2 END")
  }

  seg_crear_vista_estado()

  invisible(TRUE)
}


# --- estado final de cada persona --------------------------------------------
# Una fila por PERSONA del marco con las dos variables que resumen en que acabo
# su caso: `encuestados` (booleana) y `resultado_final_persona` (categorica).
#
# Va en una VISTA y no en columnas de seguimiento.respuestas, por dos razones
# que no son de estilo:
#
#   1. `respuestas` tiene una fila por ENVIO --`clave` es su clave primaria-- y
#      solo contiene a quien respondio. Las categorias 3 y 4 piden justamente
#      que `acepta` este vacio: esas personas no tienen fila ahi, y tampoco la
#      tienen las que estan citadas para hoy. La unidad de estas variables es la
#      persona, y la unica tabla con TODAS las personas es el marco.
#   2. conectar_bd.R BORRA Y REESCRIBE seguimiento.respuestas en cada carga (ver
#      el encabezado de utils_contactos.R, que sigue la misma regla). Una columna
#      agregada ahi se pierde en la siguiente corrida; una vista se recalcula
#      sola y nunca se desactualiza.
#
# Como la vista depende de `respuestas`, el DROP de conectar_bd.R fallaria con
# ella puesta: ese script la borra antes, en la misma transaccion, y la
# reconstruye esta funcion --que corre al arrancar la app y desde
# scripts/preparar_bd.R--.
#
# REGLAS. Se leen de arriba abajo y la primera que acierta manda, asi que el
# orden ES la definicion:
#
#   encuestados
#     TRUE   tiene al menos un envio, haya aceptado o no. Es la misma poblacion
#            que el indicador "Encuestados" de la pestana de avance.
#     NULL   esta citada para HOY: su caso sigue abierto y todavia no se puede
#            juzgar. Va ANTES del rechazo a proposito.
#     FALSE  sin envio, y su ultimo contacto de la bitacora fue 'rechazo'.
#     NULL   todo lo demas: la gestion sigue abierta, o esta ausente, o nadie la
#            ha tocado. Solo el rechazo explicito cierra en FALSE.
#
#   resultado_final_persona
#     1 Encuesta efectiva     envio con acepta = TRUE
#     2 Encuesta no efectiva  envio con acepta = FALSE
#     6 Agendado hoy          sin envio, citada para hoy
#     3 Rechazo insistente    sin envio, ultimo contacto 'rechazo'
#     4 Rechazo ausente       sin envio, ultimo contacto 'ausente'
#     5 Pendiente             sin envio y sin nada de lo anterior
#
# Quien tiene envio cae SIEMPRE en 1 o 2, aunque despues alguien le registre un
# rechazo: es lo que pide la definicion de 3 y 4 ("acepta vacio"), y ademas el
# envio ya existe y no se puede deshacer.
#
# `acepta` y el envio salen del envio MAS RECIENTE, igual que en seg_personas():
# quien mando el cuestionario dos veces es una sola persona y manda su ultimo
# envio. El contacto, del mas reciente de la bitacora, igual que en
# cto_resumen_dependencia().
#
# "Hoy" es hoy en la zona del campo y no en la del servidor, por lo mismo que
# seg_hoy() y seg_serie() (ver SEG_TZ): con la conexion en UTC, a partir de las
# 19:00 de Medellin "hoy" seria manana y los citados del dia desaparecerian.
#
# La vista NO filtra por estado_vinculacion: trae a todo el marco y publica
# `elegible`, para que quien la consulte decida. Filtrarla por dentro escondería
# a los no elegibles sin que nadie se entere; con la columna a la vista, el
# denominador del modulo es `WHERE elegible`.
#
# En un equipo nuevo `seguimiento.respuestas` todavia no existe --la escribe
# conectar_bd.R, no seg_init_db()-- y un CREATE VIEW sobre una tabla que no esta
# falla entero. Como esta funcion la llama seg_init_db(), ese error saldria por
# la pantalla de arranque de la app como un problema de esquema y la instalacion
# nueva no arrancaria. Se comprueba antes y se sale en silencio: preparar_bd.R
# vuelve a llamar a seg_init_db() despues de derivar la tabla, y ahi si se crea.
seg_crear_vista_estado <- function() {
  hay <- function(tabla, esquema = "seguimiento") isTRUE(nrow(db_get(
    "SELECT 1 FROM information_schema.tables
      WHERE table_schema = $1 AND table_name = $2",
    params = list(esquema, tabla))) > 0)
  if (!hay("respuestas_procesadas", "public") ||
      !hay("contactos") || !hay("citaciones")) {
    return(invisible(FALSE))
  }

  # Las versiones anteriores de la vista publicaban `completa`, y CREATE OR
  # REPLACE VIEW no deja quitar columnas: se borra primero, solo si todavia la
  # trae, para no rehacerla en cada arranque.
  vieja <- isTRUE(nrow(db_get(
    "SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'seguimiento' AND table_name = 'estado_persona'
        AND column_name  = 'completa'")) > 0)
  if (vieja) db_exec("DROP VIEW seguimiento.estado_persona")

  db_exec(sprintf("
    CREATE OR REPLACE VIEW seguimiento.estado_persona AS
    WITH env AS (
      SELECT DISTINCT ON (id_anonimizado)
             id_anonimizado, clave, submission_date, acepta
        FROM public.respuestas_procesadas
       ORDER BY id_anonimizado, submission_date DESC NULLS LAST, clave DESC
    ),
    cto AS (
      SELECT DISTINCT ON (id_anonimizado) id_anonimizado, fecha, resultado
        FROM seguimiento.contactos
       ORDER BY id_anonimizado, fecha DESC, id DESC
    ),
    agenda AS (
      SELECT DISTINCT id_anonimizado
        FROM seguimiento.citaciones
       WHERE fecha = (now() AT TIME ZONE '%s')::date
    )
    SELECT m.id_anonimizado,
           m.dependencia,
           m.sede_seccional,
           (m.estado_vinculacion = 'Activo')       AS elegible,
           e.clave                                 AS clave_envio,
           e.submission_date,
           e.acepta,
           k.resultado                             AS ultimo_resultado,
           k.fecha                                 AS ultimo_contacto,
           (a.id_anonimizado IS NOT NULL)          AS agendado_hoy,

           CASE
             WHEN e.id_anonimizado IS NOT NULL THEN TRUE
             WHEN a.id_anonimizado IS NOT NULL THEN NULL
             WHEN k.resultado = 'rechazo'      THEN FALSE
             ELSE NULL
           END AS encuestados,

           CASE
             WHEN e.acepta IS TRUE             THEN 1
             WHEN e.id_anonimizado IS NOT NULL THEN 2
             WHEN a.id_anonimizado IS NOT NULL THEN 6
             WHEN k.resultado = 'rechazo'      THEN 3
             WHEN k.resultado = 'ausente'      THEN 4
             ELSE 5
           END AS resultado_final_persona,

           CASE
             WHEN e.acepta IS TRUE             THEN 'Encuesta efectiva'
             WHEN e.id_anonimizado IS NOT NULL THEN 'Encuesta no efectiva'
             WHEN a.id_anonimizado IS NOT NULL THEN 'Agendado hoy'
             WHEN k.resultado = 'rechazo'      THEN 'Rechazo insistente'
             WHEN k.resultado = 'ausente'      THEN 'Rechazo ausente'
             ELSE 'Pendiente'
           END AS resultado_final_txt
      FROM seguimiento.marco m
      LEFT JOIN env    e ON e.id_anonimizado = m.id_anonimizado
      LEFT JOIN cto    k ON k.id_anonimizado = m.id_anonimizado
      LEFT JOIN agenda a ON a.id_anonimizado = m.id_anonimizado", SEG_TZ))
  invisible(TRUE)
}


# Las seis categorias, en el orden en que se leen. El numero es el que guarda la
# vista; el texto, el mismo que publica `resultado_final_txt`.
SEG_RESULTADO_FINAL <- c(
  "1" = "Encuesta efectiva",
  "2" = "Encuesta no efectiva",
  "3" = "Rechazo insistente",
  "4" = "Rechazo ausente",
  "5" = "Pendiente",
  "6" = "Agendado hoy")


# La vista entera, o solo los elegibles con `elegible = TRUE`, que es el
# denominador con el que trabaja el resto del modulo.
seg_estado_personas <- function(solo_elegibles = TRUE) {
  db_get(sprintf("SELECT * FROM seguimiento.estado_persona %s
                   ORDER BY dependencia, id_anonimizado",
                 if (isTRUE(solo_elegibles)) "WHERE elegible" else ""))
}


# Recuento por categoria, para el informe y para la tarjeta de la pestana. Trae
# las seis SIEMPRE, aunque alguna este en cero: una categoria que desaparece de
# la tabla se lee como que no existe, no como que no tiene a nadie.
#
# `dependencias` es la lista ya resuelta por el listado, igual que en seg_serie()
# y por la misma razon: el buscador filtra en R y nunca llega al SQL, asi que
# pasarle sede y tipo dejaria esta tarjeta contando una poblacion distinta de la
# que cuentan los indicadores de arriba. NULL o vacio = todas.
seg_resumen_final <- function(dependencias = NULL, solo_elegibles = TRUE) {
  x <- db_get(sprintf("
    SELECT resultado_final_persona AS codigo, count(*)::int AS personas
      FROM seguimiento.estado_persona
     WHERE ($1::boolean IS FALSE OR dependencia = ANY(string_to_array($2, chr(1))))
       %s
     GROUP BY 1", if (isTRUE(solo_elegibles)) "AND elegible" else ""),
    params = list(length(dependencias) > 0, pg_lista(dependencias)))
  out <- data.frame(
    codigo   = as.integer(names(SEG_RESULTADO_FINAL)),
    etiqueta = unname(SEG_RESULTADO_FINAL),
    personas = 0L,
    stringsAsFactors = FALSE)
  i <- match(x$codigo, out$codigo)
  out$personas[i] <- x$personas
  out$pct <- if (sum(out$personas) > 0)
    round(100 * out$personas / sum(out$personas), 1) else 0
  out
}


# Da de alta las dependencias del marco que todavia no tienen meta, con los
# elegibles como valor inicial. ON CONFLICT DO NOTHING: una meta ya editada no
# se pisa nunca, ni siquiera si el marco cambio de tamano.
seg_sembrar_metas <- function(usuario = "carga inicial") {
  db_exec("
    INSERT INTO seguimiento.metas (dependencia, planeado, nota, actualizado_por)
    SELECT dependencia,
           count(*) FILTER (WHERE estado_vinculacion = 'Activo'),
           'Valor inicial = elegibles del marco', $1
      FROM seguimiento.marco
     GROUP BY dependencia
    ON CONFLICT (dependencia) DO NOTHING", params = list(usuario))
}


# Filas de una tabla, o NA si la tabla no existe. El nombre es literal del
# codigo, nunca entrada del usuario.
seg_conteo <- function(tabla) {
  tryCatch(as.integer(db_get(paste("SELECT count(*) AS n FROM", tabla))$n),
           error = function(e) NA_integer_)
}


# Que le falta a la base para que la app tenga algo que mostrar. Devuelve un
# vector de mensajes en el orden en que hay que resolverlos; vacio = todo listo.
# Lo usan la pantalla de arranque de la app y scripts/preparar_bd.R.
seg_faltantes <- function() {
  falta <- character(0)

  if (!isTRUE(seg_conteo("seguimiento.marco") > 0))
    falta <- c(falta, paste(
      "seguimiento.marco no tiene registros: cargue el marco muestral",
      "(Rscript scripts/preparar_bd.R --marco=<archivo.xlsx>)."))

  if (!isTRUE(seg_conteo("seguimiento.respuestas_odk") > 0))
    falta <- c(falta, paste(
      "seguimiento.respuestas_odk no tiene registros: cargue el export de ODK",
      "(Rscript scripts/preparar_bd.R --odk=<archivo.csv>)."))

  # NA = la tabla no existe todavia. Cero filas con ODK cargado tambien es un
  # problema, pero eso ya lo denuncia la linea de arriba.
  # if (is.na(seg_conteo("seguimiento.respuestas")))
  #   falta <- c(falta, paste(
  #     "falta seguimiento.respuestas, la tabla derivada que consulta la app:",
  #     "se genera con Rscript scripts/preparar_bd.R."))
  if (is.na(seg_conteo("public.respuestas_procesadas")))
    falta <- c(falta, paste(
      "falta public.respuestas_procesadas, la tabla derivada que consulta la app:",
      "se genera con Rscript scripts/preparar_bd.R."))

  falta
}



seg_hay_datos <- function() {
  n <- tryCatch(db_get("SELECT count(*) AS n FROM seguimiento.marco")$n,
                error = function(e) 0)
  isTRUE(as.numeric(n) > 0)
}

seg_sedes <- function() {
  sort(db_get("SELECT DISTINCT sede_seccional AS s FROM seguimiento.marco
                WHERE sede_seccional IS NOT NULL")$s)
}

seg_tipos_dependencia <- function() {
  sort(db_get("SELECT DISTINCT tipo_dependencia AS t FROM seguimiento.marco
                WHERE tipo_dependencia IS NOT NULL")$t)
}


# RPostgres no sabe vincular un vector de R como arreglo de Postgres: lo trata
# como varias ejecuciones. Se manda entonces un solo texto y se parte del lado
# de la base. El separador es chr(1), que no aparece en ningún nombre.
SEG_SEP <- ""

pg_lista <- function(x) paste(x, collapse = SEG_SEP)

# Una fila por PERSONA que ya respondio, para unirla contra el marco sin
# multiplicar filas.
#
# `seguimiento.respuestas` tiene `clave` --el ENVIO-- como clave primaria, asi
# que quien contesto dos veces trae dos filas. En un LEFT JOIN contra el marco
# esa persona aparece duplicada, y entonces todo count(*) que cuelgue del join
# --los elegibles, el total del marco, el reparto A/B, los elegibles por
# categoria del detalle-- la cuenta dos veces. Los encuestados no, porque van
# con count(DISTINCT): el descuadre no se ve por ninguna parte, simplemente el
# avance baja y el denominador crece sin que ninguna cifra lo avise.
#
# Interponer el DISTINCT deja el join en 1:0 o 1:1 y el problema no vuelve a
# existir, en vez de tener que acordarse de poner DISTINCT en cada agregado
# nuevo. Es la misma regla que ya siguen seg_personas() (LATERAL LIMIT 1) y
# seg_serie() (el primer envio): la unidad es la persona, nunca el envio.
# SEG_RESPONDIO <- "(SELECT DISTINCT id_anonimizado FROM seguimiento.respuestas)"
SEG_RESPONDIO <- "(SELECT DISTINCT id_anonimizado FROM public.respuestas_procesadas)"

# La forma (A o B) que la persona CONTESTO, de su envio mas reciente. Es la
# buena: la trae el formulario de ODK. La del marco es un sorteo provisional
# (ver scripts/cargar_marco_bateria.R) y solo sirve para quien aun no responde.
# Se une como `f` y se lee con SEG_FORMA, la misma regla de seg_personas(), para
# que elegibles y encuestados de cada forma se clasifiquen igual y cuadren.
SEG_FORMA_ODK <- "(SELECT DISTINCT ON (id_anonimizado) id_anonimizado,
                          forma_cuestionario AS forma
                     FROM public.respuestas_procesadas
                    WHERE forma_cuestionario IN ('A', 'B')
                    ORDER BY id_anonimizado, submission_date DESC NULLS LAST, clave DESC)"
SEG_FORMA <- "COALESCE(f.forma, m.forma_cuestionario)"

# Una fila por persona con contactos y si su ULTIMO contacto cerro el caso
# (rechazo o ausente), igual que cto_resumen_dependencia(): el desenlace lo
# decide el ultimo contacto, asi que un contacto nuevo reabre el caso.
seg_sql_cierre <- function() {
  sprintf("
    SELECT DISTINCT ON (id_anonimizado) id_anonimizado,
           (resultado IN (%s)) AS cerrado
      FROM seguimiento.contactos
     ORDER BY id_anonimizado, fecha DESC, id DESC",
    paste0("'", CTO_CIERRES, "'", collapse = ", "))
}

# Una fila por dependencia con el avance. `sedes` y `tipos` son vectores de
# filtro; NULL o vacío = sin filtrar.
#
# La forma del cuestionario (A o B) es SEG_FORMA: la que la persona contesto en
# ODK si ya respondio, y la del marco si no. Tiene que estar definida tambien
# para quien todavia no ha respondido, que es justo el que hay que ir a buscar,
# y solo el marco la tiene para ellos. Elegibles y encuestados usan la misma
# regla, asi que los encuestados de una forma nunca superan a sus elegibles.
#
# `faltan` descuenta los casos que la bitacora cerro --rechazo o ausente en el
# ultimo contacto de alguien que no ha enviado nada--: ya no hay a quien
# perseguir. Es la misma regla de cto_aplicar(), asi que el "Faltan" del listado
# y el de la pestana Personas del detalle dicen el mismo numero. El avance no
# cambia: un caso cerrado no es un encuestado.
seg_avance <- function(sedes = NULL, tipos = NULL) {
  usar_sede <- length(sedes) > 0
  usar_tipo <- length(tipos) > 0

  a <- db_get(sprintf("
    WITH base AS (
      SELECT m.dependencia,
             min(m.sede_seccional)  AS sede_seccional,
             min(m.tipo_dependencia) AS tipo_dependencia,
             (count(*) FILTER (WHERE m.estado_vinculacion = 'Activo'))::int AS elegibles,
             count(*)::int                                              AS total_marco,
             (count(DISTINCT r.id_anonimizado) FILTER (
               WHERE m.estado_vinculacion = 'Activo'))::int             AS encuestados,
             (count(*) FILTER (WHERE m.estado_vinculacion = 'Activo'
                                 AND %1$s = 'A'))::int                  AS elegibles_a,
             (count(*) FILTER (WHERE m.estado_vinculacion = 'Activo'
                                 AND %1$s = 'B'))::int                  AS elegibles_b,
             (count(DISTINCT r.id_anonimizado) FILTER (
               WHERE m.estado_vinculacion = 'Activo'
                 AND %1$s = 'A'))::int                                  AS encuestados_a,
             (count(DISTINCT r.id_anonimizado) FILTER (
               WHERE m.estado_vinculacion = 'Activo'
                 AND %1$s = 'B'))::int                                  AS encuestados_b,
             (count(*) FILTER (WHERE m.estado_vinculacion = 'Activo'
                                 AND r.id_anonimizado IS NULL
                                 AND k.cerrado))::int                   AS cerrados
        FROM seguimiento.marco m
        LEFT JOIN %2$s r ON m.id_anonimizado = r.id_anonimizado
        LEFT JOIN (%3$s) k ON m.id_anonimizado = k.id_anonimizado
        LEFT JOIN %4$s f ON m.id_anonimizado = f.id_anonimizado
       WHERE ($1::boolean IS FALSE OR m.sede_seccional   = ANY(string_to_array($2, chr(1))))
         AND ($3::boolean IS FALSE OR m.tipo_dependencia = ANY(string_to_array($4, chr(1))))
       GROUP BY m.dependencia
    )
    SELECT b.dependencia, b.sede_seccional, b.tipo_dependencia,
           b.elegibles, b.total_marco, b.encuestados,
           b.elegibles_a, b.elegibles_b, b.encuestados_a, b.encuestados_b,
           b.cerrados,
           COALESCE(mt.planeado, b.elegibles)::int                  AS planeado,
           GREATEST(0, COALESCE(mt.planeado, b.elegibles)
                       - b.encuestados - b.cerrados)::int           AS faltan,
           (CASE WHEN COALESCE(mt.planeado, b.elegibles) > 0
                THEN round(100.0 * b.encuestados / COALESCE(mt.planeado, b.elegibles), 1)
                ELSE 0 END)::numeric                                 AS avance,
           mt.nota, mt.actualizado
      FROM base b
      LEFT JOIN seguimiento.metas mt ON mt.dependencia = b.dependencia
     ORDER BY b.dependencia", SEG_FORMA, SEG_RESPONDIO, seg_sql_cierre(),
     SEG_FORMA_ODK),
    params = list(usar_sede, pg_lista(sedes), usar_tipo, pg_lista(tipos)))

  repartir_formas(a)
}


# Meta por forma del cuestionario. `seguimiento.metas` guarda UN solo numero por
# dependencia y no distingue forma, asi que la meta de A y la de B no estan en
# ninguna parte: hay que repartir ese numero segun la mezcla A/B de elegibles de
# la propia dependencia (todas tienen gente de las dos).
#
# Se redondea A y B se lleva el resto, en vez de redondear las dos por separado:
# asi planeado_a + planeado_b = planeado EXACTAMENTE, fila por fila y por tanto
# tambien en el total. Con dos redondeos independientes la suma se iria una
# persona arriba o abajo y los cajones de forma dejarian de cuadrar con el de
# "Planeado", que es justo lo que el resto del modulo se cuida de que no pase.
#
# Si la dependencia no tiene ningun elegible con forma conocida no hay mezcla
# que seguir, y su planeado --que solo puede venir de una meta editada a mano--
# cae entero en A. Es un caso que hoy no existe (el marco siempre trae la forma),
# pero repartir sobre cero perderia ese planeado y romperia la suma.
repartir_formas <- function(a) {
  if (is.null(a) || nrow(a) == 0) {
    a$planeado_a <- integer(0)
    a$planeado_b <- integer(0)
    return(a)
  }
  con_forma <- a$elegibles_a + a$elegibles_b
  a$planeado_a <- as.integer(ifelse(con_forma > 0,
                                    round(a$planeado * a$elegibles_a / con_forma),
                                    a$planeado))
  a$planeado_b <- as.integer(a$planeado - a$planeado_a)
  a
}


# La app ya no edita metas --el formulario del detalle se quito-- pero la
# escritura se conserva: `seguimiento.metas` sigue siendo editable desde fuera
# (un script o SQL a mano), y esta es la unica ruta que valida el numero y deja
# constancia de quien y cuando.
seg_guardar_meta <- function(dependencia, planeado, usuario = NA_character_,
                             nota = NA_character_) {
  planeado <- suppressWarnings(as.integer(planeado))
  if (is.na(planeado) || planeado < 0) {
    stop("El número planeado debe ser un entero mayor o igual a cero.", call. = FALSE)
  }
  db_exec("
    INSERT INTO seguimiento.metas (dependencia, planeado, nota, actualizado, actualizado_por)
    VALUES ($1, $2::int, $3, now(), $4)
    ON CONFLICT (dependencia) DO UPDATE
       SET planeado = EXCLUDED.planeado,
           nota = EXCLUDED.nota,
           actualizado = now(),
           actualizado_por = EXCLUDED.actualizado_por",
    params = list(dependencia, planeado, nota, usuario))
  invisible(TRUE)
}


# --- detalle de una dependencia ----------------------------------------------

seg_detalle <- function(dependencia) {
  cab <- db_get(sprintf("
    SELECT m.dependencia,
           min(m.sede_seccional)   AS sede_seccional,
           min(m.municipio)        AS municipio,
           min(m.tipo_dependencia) AS tipo_dependencia,
           min(m.nivel_jerarquico_dependencia) AS nivel_jerarquico,
           min(m.centro_costo)     AS centro_costo,
           count(*)::int           AS total_marco,
           (count(*) FILTER (WHERE m.estado_vinculacion = 'Activo'))::int AS elegibles,
           (count(DISTINCT r.id_anonimizado) FILTER (
             WHERE m.estado_vinculacion = 'Activo'))::int           AS encuestados,
           (count(*) FILTER (WHERE m.estado_vinculacion = 'Activo'
                               AND r.id_anonimizado IS NULL
                               AND k.cerrado))::int                 AS cerrados
      FROM seguimiento.marco m
      LEFT JOIN %s r ON m.id_anonimizado = r.id_anonimizado
      LEFT JOIN (%s) k ON m.id_anonimizado = k.id_anonimizado
     WHERE m.dependencia = $1
     GROUP BY m.dependencia", SEG_RESPONDIO, seg_sql_cierre()), params = list(dependencia))

  meta <- db_get("SELECT planeado, nota, actualizado, actualizado_por
                    FROM seguimiento.metas WHERE dependencia = $1",
                 params = list(dependencia))

  # La forma sale de SEG_FORMA (ODK si respondio, marco si no), igual que en
  # seg_avance(); el resto de campos son atributos del marco.
  por <- function(campo) {
    expr <- if (campo == "forma_cuestionario") SEG_FORMA else paste0("m.", campo)
    db_get(sprintf("
      SELECT %1$s AS categoria,
             (count(*) FILTER (WHERE m.estado_vinculacion = 'Activo'))::int AS elegibles,
             (count(DISTINCT r.id_anonimizado) FILTER (
               WHERE m.estado_vinculacion = 'Activo'))::int           AS encuestados
        FROM seguimiento.marco m
        LEFT JOIN %2$s r ON m.id_anonimizado = r.id_anonimizado
        LEFT JOIN %3$s f ON m.id_anonimizado = f.id_anonimizado
       WHERE m.dependencia = $1
       GROUP BY 1 ORDER BY 1", expr, SEG_RESPONDIO, SEG_FORMA_ODK),
           params = list(dependencia))
  }

  # campo <- db_get("
  #   SELECT count(*)::int                              AS n,
  #          round(avg(r.duracion_min)::numeric, 1)      AS duracion_media,
  #          min(r.submission_date)                      AS primera,
  #          max(r.submission_date)                      AS ultima
  #     FROM seguimiento.respuestas r
  #     JOIN seguimiento.marco m USING (id_anonimizado)
  #    WHERE m.dependencia = $1", params = list(dependencia))
  campo <- db_get("
    SELECT count(*)::int                              AS n,
           round(avg(r.duracion_min)::numeric, 1)      AS duracion_media,
           min(r.submission_date)                      AS primera,
           max(r.submission_date)                      AS ultima
      FROM public.respuestas_procesadas r
      JOIN seguimiento.marco m ON m.id_anonimizado = r.id_anonimizado
     WHERE m.dependencia = $1", params = list(dependencia))

  # Misma definicion de acumulado que usa el grafico global: personas por su
  # primer envio, no filas de respuesta. Si aqui se contara distinto, la curva
  # del detalle no cerraria en el `encuestados` de su propia cabecera.
  serie <- seg_serie(dependencia)

  list(cabecera = cab, meta = meta, campo = campo, serie = serie,
       # Los mismos tres indicadores de la fila de arriba, restringidos a esta
       # dependencia. Se piden aqui --y no en el render-- para que el detalle
       # entero salga de una sola llamada, como el resto de esta lista.
       indicadores = seg_totales_indicadores(dependencia),
       por_forma = por("forma_cuestionario"),
       por_vinculacion = por("tipo_vinculacion"),
       por_nivel = por("nivel_empleo"),
       por_estado = por("estado_vinculacion"))
}


# --- personas de una dependencia ---------------------------------------------

# Una fila por PERSONA del marco, nunca por respuesta. Es la diferencia que
# manda en toda la vista: `respuestas.clave` es la clave primaria, asi que una
# misma persona puede tener varios envios, y contar respuestas inflaria el
# numerador. El LEFT JOIN LATERAL trae a lo sumo un envio por persona --el mas
# reciente, que es el que describe su situacion actual-- y deja NULL a quien no
# ha respondido, en vez de perderlo como haria un JOIN normal.
#
# La situacion se decide aqui, en un solo CASE, para que la app no tenga dos
# clasificaciones distintas del mismo dato. Es excluyente y en este orden:
#
#   no_elegible  estado_vinculacion distinto de 'Activo' (fuera del denominador,
#                haya respondido o no: es la misma poblacion que excluye
#                seg_avance(), y si contara aqui los dos numeros no cuadrarian)
#   falta        elegible sin ningun envio
#   rechazo      elegible cuyo ultimo envio NO acepto el consentimiento
#   efectiva     elegible cuyo ultimo envio acepto el consentimiento
#
# No hay "completa"/"incompleta": el formulario tiene todas las preguntas
# obligatorias, asi que quien acepta contesta entero. `efectiva` es la misma
# regla de seg_sql_efectiva() y de la vista estado_persona, y por eso el conteo
# de esta tabla cuadra con el cajon "Efectividad" y con la pestana de
# resultados. El rechazo no cambia el conteo de encuestados: el indicador mide
# envios recibidos y ese envio existe (ver la decision en seg_avance()).
#
# La citacion va aparte de la situacion, porque no la cambia: estar citado no
# es haber respondido. `cita_*` es la citacion MAS RECIENTE, aunque todavia no
# haya llegado --dice cuando se la espera--, y `citado` dice si ya se le paso la
# hora final de alguna, que es desde cuando se le puede reclamar la respuesta.
seg_personas <- function(dependencia) {
  db_get(sprintf("
    SELECT m.id_anonimizado,
           m.nombre,
           m.tipo_vinculacion,
           m.nivel_empleo,
           m.estado_vinculacion,
           m.dedicacion,
           m.modalidad_trabajo,
           COALESCE(r.forma_cuestionario, m.forma_cuestionario) AS forma,
           r.submission_date,
           r.duracion_min,
           ci.fecha                           AS cita_fecha,
           to_char(ci.hora_inicio, 'HH24:MI') AS cita_inicio,
           to_char(ci.hora_fin,    'HH24:MI') AS cita_fin,
           ci.link                            AS cita_link,
           EXISTS (SELECT 1 FROM seguimiento.citaciones cc
                    WHERE cc.id_anonimizado = m.id_anonimizado
                      AND cc.fecha + cc.hora_fin <= $2::timestamp) AS citado,
           CASE
             WHEN m.estado_vinculacion IS DISTINCT FROM 'Activo' THEN 'no_elegible'
             WHEN r.clave IS NULL                                THEN 'falta'
             WHEN r.acepta IS TRUE                               THEN 'efectiva'
             ELSE 'rechazo'
           END AS situacion
      FROM seguimiento.marco m
      LEFT JOIN LATERAL (
        SELECT rr.clave, rr.forma_cuestionario, rr.submission_date,
               rr.duracion_min, %s AS acepta
          -- FROM seguimiento.respuestas rr
          FROM public.respuestas_procesadas rr
         WHERE rr.id_anonimizado = m.id_anonimizado
         ORDER BY rr.submission_date DESC NULLS LAST, rr.clave DESC
         LIMIT 1
      ) r ON TRUE
      LEFT JOIN LATERAL (
        SELECT c.fecha, c.hora_inicio, c.hora_fin, c.link
          FROM seguimiento.citaciones c
         WHERE c.id_anonimizado = m.id_anonimizado
         ORDER BY c.fecha DESC, c.hora_inicio DESC
         LIMIT 1
      ) ci ON TRUE
     WHERE m.dependencia = $1
     ORDER BY m.id_anonimizado", seg_sql_acepta()),
    params = list(dependencia, seg_ahora()))
}


# --- citados de un dia --------------------------------------------------------
# Para el recuadro "quien no contesto" de la pestana de avance: se elige un dia
# de citacion y salen las personas citadas ese dia que HOY siguen sin ningun
# envio. No es lo mismo que "no respondio ese dia": a quien respondio despues ya
# no hay que perseguirlo, y este recuadro es para perseguir.
#
# Solo cuenta lo elegible --activos del marco, el denominador de todo el
# modulo-- y solo dias cuya hora final ya paso: antes de eso nadie esta en mora.
# `sedes` y `tipos` son los filtros de la barra de arriba.

# Condicion de poblacion compartida por las dos consultas ($1..$4).
SEG_DIA_POBLACION <- "
  m.estado_vinculacion = 'Activo'
  AND ($1::boolean IS FALSE OR m.sede_seccional  = ANY(string_to_array($2, chr(1))))
  AND ($3::boolean IS FALSE OR m.tipo_dependencia = ANY(string_to_array($4, chr(1))))"

# Sin ningun envio: cualquier respuesta con fecha cuenta, completa o no, porque
# el recuadro pregunta quien no contesto, no quien contesto bien.
SEG_DIA_SIN_ENVIO <- "
  -- NOT EXISTS (SELECT 1 FROM seguimiento.respuestas r
  NOT EXISTS (SELECT 1 FROM public.respuestas_procesadas r
               WHERE r.id_anonimizado = m.id_anonimizado
                 AND r.submission_date IS NOT NULL)"

# Un dia por fila, del mas reciente al mas antiguo: cuantas personas se citaron y
# cuantas de ellas siguen sin responder. Es lo que rotula el selector de dia.
seg_dias_citados <- function(sedes = NULL, tipos = NULL, ahora = seg_ahora()) {
  db_get(sprintf("
    WITH cit AS (
      SELECT c.fecha, m.id_anonimizado, (%s) AS sin_envio
        FROM seguimiento.citaciones c
        JOIN seguimiento.marco m USING (id_anonimizado)
       WHERE c.fecha + c.hora_fin <= $5::timestamp AND %s
    )
    SELECT fecha AS dia,
           count(DISTINCT id_anonimizado)::int AS citados,
           count(DISTINCT id_anonimizado) FILTER (WHERE sin_envio)::int AS sin_responder
      FROM cit
     GROUP BY fecha
     ORDER BY fecha DESC", SEG_DIA_SIN_ENVIO, SEG_DIA_POBLACION),
    params = list(length(sedes) > 0, pg_lista(sedes),
                  length(tipos) > 0, pg_lista(tipos), ahora))
}

# Las personas citadas en `dia` que siguen sin responder. Trae con que llamarlas:
# donde trabajan, en que franja se las cito, cuantas veces se las ha citado en
# total y como fue el ultimo contacto de la bitacora --para no repetir la llamada
# que ya hizo otra persona--.
seg_citados_dia <- function(dia, sedes = NULL, tipos = NULL, ahora = seg_ahora()) {
  db_get(sprintf("
    SELECT m.id_anonimizado,
           m.nombre,
           m.dependencia,
           m.sede_seccional AS sede,
           m.tipo_vinculacion,
           string_agg(DISTINCT to_char(c.hora_inicio, 'HH24:MI') || '-' ||
                               to_char(c.hora_fin, 'HH24:MI'), ', ') AS franjas,
           max(c.link) AS link,
           (SELECT count(*) FROM seguimiento.citaciones cc
             WHERE cc.id_anonimizado = m.id_anonimizado
               AND cc.fecha + cc.hora_fin <= $6::timestamp)::int AS citaciones,
           (SELECT count(*) FROM seguimiento.contactos k
             WHERE k.id_anonimizado = m.id_anonimizado)::int AS contactos,
           (SELECT k.fecha FROM seguimiento.contactos k
             WHERE k.id_anonimizado = m.id_anonimizado
             ORDER BY k.fecha DESC, k.id DESC LIMIT 1) AS ultimo_contacto,
           (SELECT k.resultado FROM seguimiento.contactos k
             WHERE k.id_anonimizado = m.id_anonimizado
             ORDER BY k.fecha DESC, k.id DESC LIMIT 1) AS ultimo_resultado
      FROM seguimiento.citaciones c
      JOIN seguimiento.marco m USING (id_anonimizado)
     WHERE c.fecha = $5::date AND c.fecha + c.hora_fin <= $6::timestamp
       AND %s AND %s
     GROUP BY m.id_anonimizado
     ORDER BY m.dependencia, m.id_anonimizado", SEG_DIA_POBLACION, SEG_DIA_SIN_ENVIO),
    params = list(length(sedes) > 0, pg_lista(sedes),
                  length(tipos) > 0, pg_lista(tipos), as.character(dia), ahora))
}


# La columna `acepta` la escribe conectar_bd.R con el consentimiento del
# formulario. Mientras no se vuelvan a cargar los datos la tabla no la tiene, y
# una consulta que la nombre falla entera: se pregunta una vez por sesion y, si
# no esta, se lee como si todos hubieran aceptado --que es exactamente como se
# comportaba la app antes--. Este apoyo se puede borrar cuando la instalacion ya
# haya recargado los datos al menos una vez.
.seg <- new.env(parent = emptyenv())

#
# `alias` es el de la tabla de respuestas en la consulta que la usa.
seg_sql_acepta <- function(alias = "rr") {
  if (is.null(.seg$acepta)) {
    .seg$acepta <- tryCatch(
      nrow(db_get("SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public'
                      AND table_name   = 'respuestas_procesadas'
                      AND column_name  = 'acepta'")) > 0,
      error = function(e) FALSE)
  }
  if (isTRUE(.seg$acepta)) paste0(alias, ".acepta") else "TRUE"
}

# Si el envio MAS RECIENTE de cada persona acepto el consentimiento: es lo que
# hace efectiva a una encuesta. Sale del ultimo envio, igual que la vista
# estado_persona y la situacion de seg_personas(), para que la persona que la
# vista cuenta como "Encuesta efectiva" sea la misma que cuentan los cajones.
# Va como agregado para usarlo dentro de un GROUP BY por persona sobre
# `seguimiento.respuestas r`.
seg_sql_efectiva <- function() {
  sprintf("(array_agg(%s ORDER BY r.submission_date DESC NULLS LAST, r.clave DESC))[1] IS TRUE",
          seg_sql_acepta("r"))
}


# --- totales para la fila de indicadores -------------------------------------

# Las cifras por forma se suman fila por fila, nunca se recalculan sobre el
# total: el reparto ya se hizo dependencia por dependencia (ver
# repartir_formas()), y repartir otra vez sobre la mezcla global daria un numero
# distinto en cuanto las dependencias grandes tengan otra mezcla que las chicas.
seg_totales <- function(avance) {
  if (is.null(avance) || nrow(avance) == 0) {
    return(list(planeado = 0, encuestados = 0, faltan = 0, avance = 0,
                dependencias = 0, completas = 0,
                planeado_a = 0, encuestados_a = 0,
                planeado_b = 0, encuestados_b = 0))
  }
  pl <- sum(avance$planeado); en <- sum(avance$encuestados)
  list(
    planeado      = pl,
    encuestados   = en,
    # Se suma el `faltan` que ya viene recortado por fila, en vez de restar los
    # dos totales. No es lo mismo: una dependencia con la meta por debajo de lo
    # ya encuestado aporta cero al listado --el SQL la recorta con GREATEST-- y
    # aportaria un negativo a la resta global, que se comeria lo que falta en
    # las demas. El indicador diria 1.629 con el listado de abajo sumando 1.639,
    # sin avisar de nada. Hoy no puede pasar porque nadie supera su meta, pero
    # `seguimiento.metas` se edita desde fuera (ver seg_guardar_meta()).
    faltan        = sum(avance$faltan),
    avance        = if (pl > 0) round(100 * en / pl, 1) else 0,
    dependencias  = nrow(avance),
    completas     = sum(avance$avance >= 100),
    planeado_a    = sum(avance$planeado_a),
    encuestados_a = sum(avance$encuestados_a),
    planeado_b    = sum(avance$planeado_b),
    encuestados_b = sum(avance$encuestados_b)
  )
}


# --- serie acumulada ----------------------------------------------------------

# Una fila por dia con las personas que respondieron POR PRIMERA VEZ ese dia.
# La unidad es la PERSONA y no la respuesta, igual que en seg_personas(): quien
# envio el cuestionario dos veces entra el dia de su primer envio y no se vuelve
# a contar. Asi el acumulado del ultimo dia es exactamente el `encuestados` de
# seg_avance(), y la curva no termina en un numero distinto del indicador que
# tiene justo encima. Contar filas de `respuestas` daria de mas.
#
# El filtro es la lista de dependencias ya resuelta por el listado, no sede ni
# tipo: asi el grafico mide la misma poblacion que los indicadores, incluido el
# buscador, que filtra en R y no llega al SQL. NULL o vacio = todas.
# RPostgres abre la conexion en UTC, no en la zona del servidor. Sin convertir,
# `::date` corta el dia a las 19:00 de Medellin: todo lo que se responda en la
# noche cae en el dia siguiente e inventa una jornada de campo que no existio.
SEG_TZ <- "America/Bogota"

# Devuelve dos cuentas por dia, que son las dos que mide el operativo:
#
#   n            personas que enviaron por primera vez ese dia, hayan aceptado o
#                no la encuesta. Acumulado, es la COBERTURA: hasta donde llego el
#                operativo, cuanta gente respondio al llamado.
#   n_efectivas  de las anteriores, las que ACEPTARON el consentimiento (en su
#                ultimo envio, ver seg_sql_efectiva()). Entran el mismo dia que
#                en `n`, el de su primer envio. Acumulado contra el anterior da
#                la EFECTIVIDAD: de quienes respondieron, cuantos dijeron que si.
#   n_citados    personas cuya PRIMERA citacion termino ese dia. Acumulado, es a
#                cuanta gente ya se le paso la hora de la cita.
#   n_citados_resp  citados que ya enviaron algo, en el dia en que se cumplieron
#                las dos cosas (el mas tardio entre la cita y el primer envio).
#                Los citados sin responder de un dia son los dos acumulados
#                restados; no la resta de citados menos cobertura, porque a la
#                cobertura tambien llega quien respondio sin que lo citaran.
#
# Las efectivas son un subconjunto de los encuestados CON LA MISMA FECHA: el
# consentimiento se contesta en el mismo envio, asi que no tiene un dia propio.
seg_serie <- function(dependencias = NULL, ahora = seg_ahora()) {
  usar_dep <- length(dependencias) > 0
  db_get(sprintf("
    WITH pob AS (
      SELECT m.id_anonimizado
        FROM seguimiento.marco m
       WHERE m.estado_vinculacion = 'Activo'
         AND ($1::boolean IS FALSE OR m.dependencia = ANY(string_to_array($2, chr(1))))
    ),
    primera AS (
      SELECT r.id_anonimizado,
             (min(r.submission_date) AT TIME ZONE $3::text)::date AS dia,
             %s                                                   AS efectiva
        -- FROM seguimiento.respuestas r
        FROM public.respuestas_procesadas r
        JOIN pob ON pob.id_anonimizado = r.id_anonimizado
       WHERE r.submission_date IS NOT NULL
       GROUP BY r.id_anonimizado
    ),
    cita AS (
      SELECT c.id_anonimizado, min(c.fecha) AS dia_cita
        FROM seguimiento.citaciones c
        JOIN pob USING (id_anonimizado)
       WHERE c.fecha + c.hora_fin <= $4::timestamp
       GROUP BY c.id_anonimizado
    ),
    ev AS (
      SELECT p.dia, p.efectiva, c.dia_cita,
             CASE WHEN p.dia IS NOT NULL AND c.dia_cita IS NOT NULL
                  THEN greatest(p.dia, c.dia_cita) END AS dia_cita_resp
        FROM primera p
        FULL JOIN cita c USING (id_anonimizado)
    ),
    dias AS (
      SELECT dia FROM ev WHERE dia IS NOT NULL
      UNION
      SELECT dia_cita FROM ev WHERE dia_cita IS NOT NULL
    )
    SELECT d.dia,
           (count(*) FILTER (WHERE e.dia           = d.dia))::int AS n,
           (count(*) FILTER (WHERE e.dia           = d.dia
                               AND e.efectiva))::int              AS n_efectivas,
           (count(*) FILTER (WHERE e.dia_cita      = d.dia))::int AS n_citados,
           (count(*) FILTER (WHERE e.dia_cita_resp = d.dia))::int AS n_citados_resp
      FROM dias d
      JOIN ev e ON e.dia = d.dia OR e.dia_cita = d.dia
     GROUP BY d.dia
     ORDER BY d.dia", seg_sql_efectiva()),
    params = list(usar_dep, pg_lista(dependencias), SEG_TZ, ahora))
}


# --- serie de los indicadores de la barra de metricas -------------------------
# Las cuentas que necesitan Efectividad, Cobertura Citados y Cobertura
# Esperados, con una fila por dia. Va aparte de seg_serie() --que alimenta la
# curva de Avance-- porque sus consumidores agrupan el resultado en periodos, no
# lo acumulan directamente.
#
# Las tres cuentas son de PERSONAS y cada una entra UNA sola vez, el dia en que
# le paso lo suyo por primera vez. Es la misma regla de seg_serie(), y es lo que
# permite que al acumular la serie el total sea gente y no eventos:
#
#   encuestados  el dia de su primer envio (cualquiera, acepte o no)
#   efectivas    de los anteriores, los que aceptaron el consentimiento, el
#                mismo dia. Es la misma cuenta que la curva de Avance
#                (n_efectivas de seg_serie()), para que la Efectividad diga lo
#                mismo en los dos graficos.
#   citados      el dia en que termino su PRIMERA citacion ya pasada
#
# Solo cuentan las citaciones cuya hora final ya transcurrio. La agenda cargada
# llega semanas mas alla de hoy, y contar esas citas meteria en el denominador
# gente a la que todavia no se le puede reclamar nada: la Cobertura Citados
# caeria semana a semana sin que hubiera pasado nada. Es la misma condicion que
# ya usan seg_serie() y seg_citados_dia().
#
# La poblacion son los ACTIVOS del marco, igual que en todo el modulo. El
# denominador "marco" de Cobertura Esperados sale de seg_marco_total(), que
# cuenta esa misma poblacion: hoy son los 3.357 de siempre.
seg_serie_indicadores <- function(dependencias = NULL, ahora = seg_ahora()) {
  usar_dep <- length(dependencias) > 0
  db_get(sprintf("
    WITH pob AS (
      SELECT m.id_anonimizado
        FROM seguimiento.marco m
       WHERE m.estado_vinculacion = 'Activo'
         AND ($1::boolean IS FALSE OR m.dependencia = ANY(string_to_array($2, chr(1))))
    ),
    primera AS (
      SELECT r.id_anonimizado,
             (min(r.submission_date) AT TIME ZONE $3::text)::date AS dia_env,
             %s                                                   AS efectiva
        -- FROM seguimiento.respuestas r
        FROM public.respuestas_procesadas r
        JOIN pob ON pob.id_anonimizado = r.id_anonimizado
       WHERE r.submission_date IS NOT NULL
       GROUP BY r.id_anonimizado
    ),
    cita AS (
      SELECT c.id_anonimizado, min(c.fecha) AS dia_cit
        FROM seguimiento.citaciones c
        JOIN pob USING (id_anonimizado)
       WHERE c.fecha + c.hora_fin <= $4::timestamp
       GROUP BY c.id_anonimizado
    ),
    ev AS (
      SELECT p.dia_env, p.efectiva, c.dia_cit
        FROM primera p FULL JOIN cita c USING (id_anonimizado)
    ),
    dias AS (
      SELECT dia_env AS dia FROM ev WHERE dia_env IS NOT NULL
      UNION
      SELECT dia_cit FROM ev WHERE dia_cit IS NOT NULL
    )
    SELECT d.dia,
           (count(*) FILTER (WHERE e.dia_env = d.dia))::int AS encuestados,
           (count(*) FILTER (WHERE e.dia_env = d.dia
                               AND e.efectiva))::int         AS efectivas,
           (count(*) FILTER (WHERE e.dia_cit = d.dia))::int AS citados
      FROM dias d
      JOIN ev e ON e.dia_env = d.dia OR e.dia_cit = d.dia
     GROUP BY d.dia
     ORDER BY d.dia", seg_sql_efectiva()),
    params = list(usar_dep, pg_lista(dependencias), SEG_TZ, ahora))
}


# Los cuatro conteos de PERSONAS que alimentan los tres indicadores, una fila
# por forma del cuestionario (A y B) mas lo que venga sin forma. El total no se
# consulta: se suma en R (ver seg_totales_indicadores()), que es lo mismo y una
# consulta menos.
#
#   marco        personas activas del marco en la seleccion
#   encuestados  las que tienen al menos un envio, aceptaran o no
#   efectivas    las que aceptaron el consentimiento en su ultimo envio
#   citados      las que tienen al menos una citacion cuya hora ya paso
#
# La forma es SEG_FORMA, igual que en seg_avance(): la que contesto en ODK si ya
# respondio, la del marco si no.
#
# `efectivas` usa la misma regla que seg_serie_indicadores() (seg_sql_efectiva()),
# asi que el numero grande del cajon y el de la cabecera del grafico de
# Efectividad no se pueden contradecir.
seg_conteos_forma <- function(dependencias = NULL, ahora = seg_ahora()) {
  usar_dep <- length(dependencias) > 0
  db_get(sprintf("
    WITH pob AS (
      SELECT m.id_anonimizado, %2$s AS forma
        FROM seguimiento.marco m
        LEFT JOIN %3$s f ON m.id_anonimizado = f.id_anonimizado
       WHERE m.estado_vinculacion = 'Activo'
         AND ($1::boolean IS FALSE OR m.dependencia = ANY(string_to_array($2, chr(1))))
    ),
    env AS (
      SELECT r.id_anonimizado, %1$s AS efectiva
        -- FROM seguimiento.respuestas r
        FROM public.respuestas_procesadas r
        JOIN pob ON pob.id_anonimizado = r.id_anonimizado
       GROUP BY r.id_anonimizado
    ),
    p AS (
      SELECT pob.forma,
             (env.id_anonimizado IS NOT NULL)              AS encuestado,
             COALESCE(env.efectiva, FALSE)                 AS efectiva,
             EXISTS (SELECT 1 FROM seguimiento.citaciones c
                      WHERE c.id_anonimizado = pob.id_anonimizado
                        AND c.fecha + c.hora_fin <= $3::timestamp) AS citado
        FROM pob
        LEFT JOIN env USING (id_anonimizado)
    )
    SELECT forma,
           count(*)::int                             AS marco,
           (count(*) FILTER (WHERE encuestado))::int AS encuestados,
           (count(*) FILTER (WHERE efectiva))::int   AS efectivas,
           (count(*) FILTER (WHERE citado))::int     AS citados
      FROM p
     GROUP BY forma
     ORDER BY forma", seg_sql_efectiva(), SEG_FORMA, SEG_FORMA_ODK),
    params = list(usar_dep, pg_lista(dependencias), ahora))
}


# Los tres indicadores para el total y para cada forma, listos para la fila de
# cajones. Devuelve una lista con `total`, `A` y `B`; cada una trae los cuatro
# conteos y los tres porcentajes.
#
# Un denominador en cero no da cero por ciento: da NA, que fmt_pct() pinta como
# raya. Un cero afirmaria que la razon se midio y dio cero, cuando lo que pasa
# es que no hay con que medirla --una seleccion sin nadie citado todavia-- y es
# la misma regla que sigue pct_formas().
seg_totales_indicadores <- function(dependencias = NULL, ahora = seg_ahora()) {
  x <- seg_conteos_forma(dependencias, ahora)
  cols <- c("marco", "encuestados", "efectivas", "citados")

  # LAS FORMULAS. Viven aqui y en INDICADORES (mod_seguimiento.R), que tiene que
  # decir lo mismo:
  #
  #   Efectividad          efectivas   / encuestados
  #   No efectivas         (encuestados - efectivas) / encuestados
  #   Cobertura Citados    encuestados / citados
  #   Cobertura Esperados  encuestados / marco
  arma <- function(fila) {
    r <- as.list(stats::setNames(as.integer(fila[cols]), cols))
    razon <- function(num, den) if (isTRUE(den > 0)) round(100 * num / den, 1) else NA_real_
    # De quienes respondieron, cuantos aceptaron el consentimiento.
    r$efectividad   <- razon(r$efectivas,   r$encuestados)
    # Lo contrario: encuestados que no aceptaron. Se resta y no se consulta,
    # para que las dos cifras sumen siempre los encuestados y los dos
    # porcentajes el 100%.
    r$no_efectivas     <- r$encuestados - r$efectivas
    r$pct_no_efectivas <- razon(r$no_efectivas, r$encuestados)
    # El numerador son TODOS los encuestados, tambien quien respondio sin que
    # lo citaran, asi que la Cobertura Citados puede pasar de 100%.
    r$cob_citados   <- razon(r$encuestados, r$citados)
    r$cob_esperados <- razon(r$encuestados, r$marco)
    r
  }

  fila_forma <- function(f) {
    i <- which(!is.na(x$forma) & x$forma == f)
    if (length(i) == 0) stats::setNames(rep(0L, length(cols)), cols)
    else stats::setNames(as.integer(x[i[1], cols]), cols)
  }
  total <- if (nrow(x) == 0) stats::setNames(rep(0L, length(cols)), cols)
           else stats::setNames(colSums(x[, cols, drop = FALSE]), cols)

  list(total = arma(total), A = arma(fila_forma("A")), B = arma(fila_forma("B")))
}


# El denominador fijo de Cobertura Esperados: cuanta gente hay en el marco de la
# seleccion. No depende del dia --el marco es una foto, no una serie-- asi que
# es un solo numero que el grafico repite en todos los periodos.
seg_marco_total <- function(dependencias = NULL) {
  usar_dep <- length(dependencias) > 0
  x <- db_get("
    SELECT count(*)::int AS n
      FROM seguimiento.marco m
     WHERE m.estado_vinculacion = 'Activo'
       AND ($1::boolean IS FALSE OR m.dependencia = ANY(string_to_array($2, chr(1))))",
    params = list(usar_dep, pg_lista(dependencias)))
  if (is.null(x) || nrow(x) == 0) 0L else as.integer(x$n[1])
}


# Serie diaria -> periodos, por dia o por semana. Transformacion pura sobre lo
# que devuelve seg_serie_indicadores(); no vuelve a la base, igual que
# seg_semanas().
#
# Rellena los periodos vacios en vez de saltarlos, por la misma razon que alli:
# un hueco de campo es informacion, y saltarlo dibujaria dos periodos seguidos
# donde en realidad hubo tres. El relleno llega hasta `hasta` --hoy-- para que el
# ultimo periodo sea siempre el que esta en curso.
#
# `desde` fija el arranque (el inicio de campo) aunque la seleccion no tenga nada
# hasta mas tarde, para que S3 sea la misma semana en toda la app.
#
# Devuelve una fila por periodo con inicio, fin, las tres cuentas del periodo,
# sus tres acumulados y `en_curso`.
seg_periodos <- function(serie, por = "semana", hasta = seg_hoy(), desde = NULL) {
  cols  <- c("encuestados", "efectivas", "citados")
  vacio <- data.frame(inicio = as.Date(character(0)), fin = as.Date(character(0)),
                      encuestados = integer(0), efectivas = integer(0),
                      citados = integer(0),
                      encuestados_ac = integer(0), efectivas_ac = integer(0),
                      citados_ac = integer(0), en_curso = logical(0))
  if (is.null(serie) || nrow(serie) == 0) return(vacio)

  dias <- as.Date(serie$dia)
  ok   <- !is.na(dias)
  if (!any(ok)) return(vacio)
  dias <- dias[ok]
  serie <- serie[ok, , drop = FALSE]

  semanal <- identical(por, "semana")
  clave <- if (semanal) seg_lunes(dias) else dias
  hasta <- as.Date(hasta)
  tope  <- if (semanal) seg_lunes(hasta) else hasta
  ini   <- if (is.null(desde)) min(clave)
           else min(c(if (semanal) seg_lunes(desde) else as.Date(desde), min(clave)))
  todas <- seq(ini, max(c(tope, max(clave))), by = if (semanal) 7 else 1)

  f   <- factor(as.character(clave), levels = as.character(todas))
  out <- data.frame(inicio = todas,
                    fin    = if (semanal) todas + 4L else todas,
                    stringsAsFactors = FALSE)
  for (cl in cols) {
    v <- as.integer(tapply(as.integer(serie[[cl]]), f, sum))
    v[is.na(v)] <- 0L
    out[[cl]] <- v
    out[[paste0(cl, "_ac")]] <- cumsum(v)
  }
  out$en_curso <- out$inicio == tope
  out
}


# --- serie semanal ------------------------------------------------------------

# Momento del ultimo envio recibido en la seleccion. Es el "corte" que rotula el
# grafico semanal: la barra de la semana en curso no llega hasta el viernes,
# llega hasta aqui. Decirlo con hora y todo evita que una semana a medias se lea
# como una caida del ritmo. Misma poblacion que seg_serie() --solo activos-- para
# que el corte describa la serie que acompana y no otra.
seg_ultimo_envio <- function(dependencias = NULL) {
  usar_dep <- length(dependencias) > 0
  x <- db_get("
    SELECT max(r.submission_date) AS ultimo
      -- FROM seguimiento.respuestas r
      FROM public.respuestas_procesadas r
      JOIN seguimiento.marco m ON m.id_anonimizado = r.id_anonimizado
     WHERE m.estado_vinculacion = 'Activo'
       AND ($1::boolean IS FALSE OR m.dependencia = ANY(string_to_array($2, chr(1))))",
    params = list(usar_dep, pg_lista(dependencias)))
  if (is.null(x) || nrow(x) == 0) return(NA)
  x$ultimo[1]
}


# Lunes de la semana a la que pertenece una fecha. %u numera los dias con el
# lunes en 1 y no depende del idioma del sistema, a diferencia de %a o de
# as.POSIXlt()$wday, que empieza en domingo.
seg_lunes <- function(d) {
  d <- as.Date(d)
  d - (as.integer(format(d, "%u")) - 1L)
}

# Hoy en la zona del campo, no en la del servidor: si algun dia la app corre en
# otra maquina, la semana "en curso" tiene que seguir siendo la de Medellin.
seg_hoy <- function() as.Date(format(Sys.time(), "%Y-%m-%d", tz = SEG_TZ))

# El momento actual en la zona del campo, como texto que Postgres lee como
# `timestamp` sin zona. Una citacion cuenta como hecha cuando ya paso su hora
# final: a quien citaron hoy a las 15:00 no se le puede reclamar a las 10:00.
seg_ahora <- function() format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = SEG_TZ)


# Lunes de la primera semana con envios de TODA la campana, sin filtro ninguno.
# Es el origen de la numeracion de las semanas (S1, S2...): si cada grafico
# empezara a contar en su propio primer envio, la S3 del detalle de una facultad
# seria una semana distinta de la S3 del global, y las dos vistas dejarian de
# poder compararse. Con un origen unico, S3 es la misma semana en toda la app.
seg_inicio_campo <- function() {
  x <- db_get("
    SELECT (min(r.submission_date) AT TIME ZONE $1::text)::date AS d
      -- FROM seguimiento.respuestas r
      FROM public.respuestas_procesadas r
      JOIN seguimiento.marco m ON m.id_anonimizado = r.id_anonimizado
     WHERE m.estado_vinculacion = 'Activo'", params = list(SEG_TZ))
  if (is.null(x) || nrow(x) == 0 || is.na(x$d[1])) return(NULL)
  seg_lunes(x$d[1])
}


# Serie diaria -> serie semanal. Es una transformacion pura sobre lo que devuelve
# seg_serie(); no vuelve a la base. Asi el grafico semanal y la curva diaria
# cuentan exactamente las mismas personas --una por su primer envio-- y el
# acumulado de la ultima semana cierra en el mismo `encuestados` de los
# indicadores, que es la regla que sigue todo el modulo.
#
# La semana va de lunes a viernes, que es la jornada de campo. No hay envios en
# fin de semana; si algun dia los hubiera, caen en la semana que empezo ese lunes
# y no se pierde a nadie, porque perderlos descuadraria el acumulado.
#
# Las semanas sin ningun envio se rellenan con cero en vez de saltarse: un hueco
# de campo es informacion, y saltarlo dibujaria dos semanas seguidas donde en
# realidad hubo tres. El relleno llega hasta la semana en curso, para que la
# ultima barra sea siempre "lo que va de esta semana", aunque este vacia.
#
# Devuelve una fila por semana con:
#   inicio, fin  lunes y viernes de la semana
#   nuevos       personas que respondieron POR PRIMERA VEZ esa semana
#   previo       acumulado con el que se llegaba a esa semana
#   acum         previo + nuevos (la altura total de la barra)
#   en_curso     TRUE en la semana que todavia no ha terminado
#
# `desde` fija el lunes en el que arranca la serie --el inicio de campo, ver
# seg_inicio_campo()-- aunque la seleccion no tenga envios hasta mas tarde. Las
# semanas de mas quedan en cero, que es exactamente lo que paso: esa dependencia
# empezo tarde. Sin eso, cada grafico numeraria sus semanas desde su propio
# primer envio y S1 significaria una cosa distinta en cada pantalla.
seg_semanas <- function(serie, hasta = seg_hoy(), desde = NULL) {
  vacio <- data.frame(inicio = as.Date(character(0)), fin = as.Date(character(0)),
                      nuevos = integer(0), previo = integer(0), acum = integer(0),
                      en_curso = logical(0))
  if (is.null(serie) || nrow(serie) == 0) return(vacio)

  dias <- as.Date(serie$dia)
  n    <- as.integer(serie$n)
  ok   <- !is.na(dias) & !is.na(n)
  if (!any(ok)) return(vacio)
  dias <- dias[ok]; n <- n[ok]

  lun   <- seg_lunes(dias)
  hasta <- as.Date(hasta)
  ini   <- if (is.null(desde)) min(lun) else min(c(seg_lunes(desde), min(lun)))
  todas <- seq(ini, max(c(seg_lunes(hasta), max(lun))), by = 7)

  nuevos <- as.integer(tapply(
    n, factor(as.character(lun), levels = as.character(todas)), sum))
  nuevos[is.na(nuevos)] <- 0L
  acum <- cumsum(nuevos)

  data.frame(inicio   = todas,
             fin      = todas + 4L,
             nuevos   = nuevos,
             previo   = acum - nuevos,
             acum     = acum,
             en_curso = todas == seg_lunes(hasta),
             stringsAsFactors = FALSE)
}


# --- citaciones ---------------------------------------------------------------
# La agenda llega en una base aparte con: fecha, hora de inicio programada, hora
# final programada, id de la persona, nombre y link donde se aplica. Estas dos
# funciones son puras --reciben un data.frame y no tocan la base-- para poder
# probarlas sueltas; la carga la hace scripts/preparar_bd.R.

# Capacidad de la agenda: en una hora se programan hasta dos grupos, y entre los
# dos hasta cien personas. No es una regla de la base --una franja pasada de
# cupo se carga igual, porque la agenda es la que es-- sino un aviso al cargar:
# una hora con 140 citados casi siempre es un error de programacion.
SEG_CIT_POR_HORA    <- 100L
SEG_CIT_GRUPOS_HORA <- 2L

# Nombres con que puede venir cada columna. Se comparan en minusculas y sin
# tildes, espacios ni signos: "Hora inicio programada", "hora_inicio_programada"
# y "HORAINICIOPROGRAMADA" son la misma. El nombre de la persona no se busca
# porque no se carga (ver seg_init_db()). El link es opcional.
SEG_CIT_COLUMNAS <- list(
  fecha          = c("fecha", "fechaprogramada", "fechacitacion"),
  hora_inicio    = c("horainicioprogramada", "horainicio", "horaprogramadainicio"),
  hora_fin       = c("horafinalprogramada", "horafinprogramada", "horafinal", "horafin"),
  id_anonimizado = c("idpersona", "idanonimizado", "id"),
  link           = c("link", "linkdondeseaplica", "enlace", "url"),
  nombre         = c("persona", "nombre", "nombrepersona", "nombrecompleto",
                     "nombreyapellidos", "nombres"))

# Fecha desde lo que entregue Excel o un CSV: Date, fecha-hora, numero de serie
# de Excel o texto. El formato del texto se decide por su forma y no probando
# uno tras otro: as.Date("16-07-2026", "%Y-%m-%d") no falla, devuelve el ano 16.
seg_cit_fecha <- function(v) {
  if (inherits(v, "Date"))   return(v)
  if (inherits(v, "POSIXt")) return(as.Date(format(v, "%Y-%m-%d", tz = "UTC")))
  if (is.numeric(v))         return(as.Date(v, origin = "1899-12-30"))
  s   <- trimws(as.character(v))
  out <- rep(as.Date(NA), length(s))
  for (f in list(c("^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}",  "%Y-%m-%d"),
                 c("^[0-9]{4}/[0-9]{1,2}/[0-9]{1,2}",  "%Y/%m/%d"),
                 c("^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}",  "%d/%m/%Y"),
                 c("^[0-9]{1,2}-[0-9]{1,2}-[0-9]{4}",  "%d-%m-%Y"))) {
    i <- !is.na(s) & grepl(f[1], s)
    out[i] <- as.Date(s[i], format = f[2])
  }
  out
}

# Hora "HH:MM" desde lo que entregue Excel o un CSV: la fecha-hora con que
# readxl lee una celda de hora (1899-12-31 08:00), la fraccion de dia de un CSV
# exportado sin formato (0,333) o texto ("8:00", "08:00:00", "2:30 p. m.").
seg_cit_hora <- function(v) {
  if (inherits(v, "POSIXt")) {
    return(ifelse(is.na(v), NA_character_, format(v, "%H:%M", tz = "UTC")))
  }
  if (is.numeric(v)) {
    # 0,99999 redondea a 1440 minutos, que seria "24:00": se queda en 23:59.
    m <- pmin(round(v * 24 * 60), 1439)
    return(ifelse(is.na(v) | v < 0 | v >= 1, NA_character_,
                  sprintf("%02d:%02d", m %/% 60, m %% 60)))
  }
  # "12:00 m." es el mediodia en la escritura colombiana; solo vale con las 12.
  s  <- gsub("[[:space:].]", "", to_key(as.character(v)))
  mt <- regmatches(s, regexec("^([0-9]{1,2}):([0-9]{2})(:[0-9]{2})?(am|pm|m)?$", s))
  vapply(mt, function(g) {
    if (length(g) == 0) return(NA_character_)
    h  <- as.integer(g[2]); mi <- as.integer(g[3])
    if (identical(g[5], "m") && h != 12L) return(NA_character_)
    if (identical(g[5], "pm") && h < 12L) h <- h + 12L
    if (identical(g[5], "am") && h == 12L) h <- 0L
    if (h > 23L || mi > 59L) return(NA_character_)
    sprintf("%02d:%02d", h, mi)
  }, character(1))
}

# De la base de origen a la tabla seguimiento.citaciones. Se detiene --antes de
# que nadie toque la tabla-- si falta una columna o si alguna fila no se puede
# leer, diciendo cuales: cargar a medias dejaria citados que no existen o
# personas sin cita que si la tenian. Las filas totalmente vacias, que Excel
# suele dejar al final, se descartan sin ruido; las repetidas, tambien.
seg_cit_normalizar <- function(x) {
  x <- as.data.frame(x, stringsAsFactors = FALSE)
  claves <- gsub("[^a-z0-9]", "", to_key(names(x)))
  cual <- vapply(SEG_CIT_COLUMNAS, function(alias) {
    i <- match(alias, claves)
    i <- i[!is.na(i)]
    if (length(i)) i[1] else NA_integer_
  }, integer(1))

  obligatorias <- c("fecha", "hora_inicio", "hora_fin", "id_anonimizado")
  faltan <- obligatorias[is.na(cual[obligatorias])]
  if (length(faltan)) {
    stop("A la base de citaciones le faltan columnas: ", paste(faltan, collapse = ", "),
         ".\nColumnas encontradas: ", paste(names(x), collapse = ", "), call. = FALSE)
  }

  # Un id que Excel guardo como numero: as.character(100000) da "1e+05".
  id <- x[[cual[["id_anonimizado"]]]]
  id <- if (is.numeric(id)) ifelse(is.na(id), NA_character_,
                                   formatC(id, format = "fg", digits = 15))
        else as.character(id)

  cit <- data.frame(
    id_anonimizado = trimws(id),
    fecha          = seg_cit_fecha(x[[cual[["fecha"]]]]),
    hora_inicio    = seg_cit_hora(x[[cual[["hora_inicio"]]]]),
    hora_fin       = seg_cit_hora(x[[cual[["hora_fin"]]]]),
    link           = if (is.na(cual[["link"]])) NA_character_
                     else trimws(as.character(x[[cual[["link"]]]])),
    nombre         = if (is.na(cual[["nombre"]])) NA_character_
                     else trimws(as.character(x[[cual[["nombre"]]]])),
    stringsAsFactors = FALSE)
  cit$link[!is.na(cit$link) & !nzchar(cit$link)] <- NA_character_
  cit$nombre[!is.na(cit$nombre) & !nzchar(cit$nombre)] <- NA_character_

  m     <- as.matrix(x)
  vacia <- rowSums(!is.na(m) & nzchar(trimws(m))) == 0
  fila  <- which(!vacia) + 1L          # +1 por la fila de encabezados
  cit   <- cit[!vacia, , drop = FALSE]

  mala <- is.na(cit$id_anonimizado) | !nzchar(cit$id_anonimizado) |
          is.na(cit$fecha) | is.na(cit$hora_inicio) | is.na(cit$hora_fin)
  if (any(mala)) {
    stop(sum(mala), " filas de citaciones no se pueden leer (sin id, o fecha u ",
         "hora en un formato desconocido). Filas del archivo: ",
         paste(utils::head(fila[mala], 10), collapse = ", "), call. = FALSE)
  }

  # "HH:MM" con ceros a la izquierda se ordena bien como texto.
  invertida <- cit$hora_fin <= cit$hora_inicio
  if (any(invertida)) {
    stop(sum(invertida), " citaciones tienen la hora final igual o anterior a la ",
         "inicial. Filas del archivo: ",
         paste(utils::head(fila[invertida], 10), collapse = ", "), call. = FALSE)
  }

  # El link se muestra como enlace en la app: solo http(s). Un link sin esquema
  # ("meet.google.com/abc") se completa con https://; otro esquema, como
  # javascript:, detiene la carga.
  sin_esquema <- !is.na(cit$link) & !grepl("^[a-z][a-z0-9+.-]*:", cit$link, ignore.case = TRUE)
  cit$link[sin_esquema] <- paste0("https://", cit$link[sin_esquema])
  link_malo <- !is.na(cit$link) & !grepl("^https?://", cit$link, ignore.case = TRUE)
  if (any(link_malo)) {
    stop(sum(link_malo), " citaciones tienen un link que no es http ni https. ",
         "Filas del archivo: ",
         paste(utils::head(fila[link_malo], 10), collapse = ", "), call. = FALSE)
  }

  cit <- unique(cit)
  rownames(cit) <- NULL
  cit
}

# Franjas que pasan la capacidad: una fila por fecha y hora de reloj con mas de
# SEG_CIT_POR_HORA personas o mas de SEG_CIT_GRUPOS_HORA grupos. Un grupo es una
# sesion: la misma fecha, la misma franja y el mismo link. Cada cita cuenta en
# todas las horas que toca, no solo en la de inicio: un grupo de 7:30 a 8:30 se
# cruza con uno de 8:00 a 9:00. La hora en que termina en punto no se ocupa.
seg_cit_capacidad <- function(cit) {
  vacio <- data.frame(franja = character(0), personas = integer(0), grupos = integer(0))
  if (is.null(cit) || nrow(cit) == 0) return(vacio)
  minutos <- function(h) as.integer(substr(h, 1, 2)) * 60L + as.integer(substr(h, 4, 5))
  ini <- minutos(cit$hora_inicio) %/% 60L
  fin <- (minutos(cit$hora_fin) - 1L) %/% 60L
  k   <- rep(seq_len(nrow(cit)), fin - ini + 1L)
  franja   <- sprintf("%s %02d", format(cit$fecha[k]),
                      unlist(mapply(seq, ini, fin, SIMPLIFY = FALSE)))
  grupo    <- paste(cit$hora_inicio, cit$hora_fin, cit$link)[k]
  personas <- tapply(cit$id_anonimizado[k], franja, function(z) length(unique(z)))
  grupos   <- tapply(grupo, franja, function(z) length(unique(z)))
  out <- data.frame(franja   = paste0(names(personas), ":00"),
                    personas = as.integer(personas),
                    grupos   = as.integer(grupos[names(personas)]),
                    stringsAsFactors = FALSE)
  out <- out[out$personas > SEG_CIT_POR_HORA | out$grupos > SEG_CIT_GRUPOS_HORA, ,
             drop = FALSE]
  rownames(out) <- NULL
  out
}

# El archivo de la agenda tal como llega: Excel (primera hoja) o CSV. `nombre`
# decide el formato por la extension; va aparte de la ruta porque el archivo que
# se sube desde la app queda en una ruta temporal que no conserva el nombre.
seg_cit_leer <- function(ruta, nombre = ruta) {
  if (grepl("\\.xlsx?$", nombre, ignore.case = TRUE)) {
    return(as.data.frame(readxl::read_excel(ruta, sheet = 1)))
  }
  if (!grepl("\\.csv$", nombre, ignore.case = TRUE)) {
    stop("La agenda tiene que venir en Excel (.xlsx, .xls) o en CSV.", call. = FALSE)
  }
  # La codificacion se resuelve antes de leer. Excel en Windows guarda el CSV en
  # ANSI (CP1252), y leido como UTF-8 read.csv se detiene en la primera tilde
  # con solo un warning: la agenda llegaba cortada sin ningun error.
  bytes <- readBin(ruta, "raw", file.size(ruta))
  texto <- tryCatch(rawToChar(bytes), error = function(e)
    stop("El CSV no se puede leer como texto; puede estar guardado en Unicode (UTF-16). ",
         "Guárdelo desde Excel como «CSV UTF-8».", call. = FALSE))
  if (validUTF8(texto)) {
    Encoding(texto) <- "UTF-8"
  } else {
    # CP1252 deja sin definir cinco bytes; latin1 los acepta todos.
    texto <- iconv(texto, "CP1252", "UTF-8")
    if (is.na(texto)) texto <- iconv(rawToChar(bytes), "latin1", "UTF-8")
  }
  texto <- sub("^﻿", "", texto)

  leer <- function(fun) fun(text = texto, stringsAsFactors = FALSE, check.names = FALSE,
                            colClasses = "character", encoding = "UTF-8")
  x <- leer(utils::read.csv)
  # Un CSV guardado desde Excel en espanol va con punto y coma: leido con coma
  # queda en una sola columna.
  if (ncol(x) == 1) x <- leer(utils::read.csv2)
  x
}

# Ids de la agenda que no estan en el marco. No detienen la carga, pero no
# cuentan en ningun avance: casi siempre es que la columna trae la cedula.
seg_cit_fuera_marco <- function(cit) {
  marco <- db_get("SELECT id_anonimizado FROM seguimiento.marco")$id_anonimizado
  unique(cit$id_anonimizado[!cit$id_anonimizado %in% marco])
}

# Reemplaza la agenda entera en una sola transaccion: si el INSERT falla, la
# agenda anterior sigue ahi. Los grupos que no quedan en la agenda nueva pierden
# su aplicador en la misma transaccion (seg_grupos_huerfanos() los anticipa).
seg_cit_guardar <- function(cit) {
  db_tx(function(con) {
    DBI::dbExecute(con, "TRUNCATE seguimiento.citaciones")
    DBI::dbAppendTable(con, DBI::Id(schema = "seguimiento", table = "citaciones"), cit)
    DBI::dbExecute(con, "
      DELETE FROM seguimiento.grupos_aplicador g
       WHERE NOT EXISTS (SELECT 1 FROM seguimiento.citaciones c
                          WHERE c.fecha = g.fecha AND c.hora_inicio = g.hora_inicio
                            AND c.hora_fin = g.hora_fin AND COALESCE(c.link, '') = g.link)")
  })
  invisible(nrow(cit))
}

# Lo que hay cargado hoy, para mostrarlo antes de reemplazarlo.
seg_cit_resumen <- function() {
  db_get("
    SELECT count(*)::int                       AS citaciones,
           count(DISTINCT id_anonimizado)::int AS personas,
           min(fecha)                          AS desde,
           max(fecha)                          AS hasta
      FROM seguimiento.citaciones")
}


# --- grupos y aplicadores -----------------------------------------------------
# Un grupo es una sesion de la agenda: la misma fecha, franja y link (la misma
# definicion de seg_cit_capacidad()). El psicologo --AUTH_PERMISOS$tomar_grupos
# en utils_auth.R-- toma un grupo libre y lo suelta mientras no haya empezado;
# quien tenga el permiso `asignar_grupos` le pone o le quita el psicologo a cualquier
# grupo, a cualquier hora. Las reglas van dentro de cada SQL y no en un
# SELECT previo: entre mirar y escribir, otra sesion pudo tomar el grupo.

# Clave de texto con que la pagina devuelve un grupo al servidor. El link va al
# final porque es el unico campo que puede traer "|".
seg_grupo_clave <- function(fecha, hora_inicio, hora_fin, link) {
  paste(format(fecha), hora_inicio, hora_fin, ifelse(is.na(link), "", link), sep = "|")
}

# La clave de vuelta, o NULL si no tiene la forma esperada: viene del navegador.
seg_grupo_de_clave <- function(clave) {
  if (!is.character(clave) || length(clave) != 1 || is.na(clave)) return(NULL)
  m <- regmatches(clave, regexec(
    "^([0-9]{4}-[0-9]{2}-[0-9]{2})\\|([0-9]{2}:[0-9]{2})\\|([0-9]{2}:[0-9]{2})\\|(.*)$",
    clave))[[1]]
  if (length(m) == 0 || is.na(as.Date(m[2], format = "%Y-%m-%d"))) return(NULL)
  list(fecha = m[2], hora_inicio = m[3], hora_fin = m[4], link = m[5])
}

# Condicion comun: el grupo $1..$4 esta en la agenda cargada.
SEG_GRUPO_EN_AGENDA <- "
  EXISTS (SELECT 1 FROM seguimiento.citaciones c
           WHERE c.fecha = $1::date AND c.hora_inicio = $2::time
             AND c.hora_fin = $3::time AND COALESCE(c.link, '') = $4)"

# Los grupos de la agenda con su aplicador. `empezo` se mide en la zona del
# campo (ver seg_ahora()): desde la hora de inicio el grupo ya no se toma ni se
# suelta.
#
# `termino` es para las anotaciones: un grupo asignado que ya termino y no tiene
# ninguna es uno sin anotar. `anotaciones` es cuantas tiene, contando la del
# grupo y las de cada persona.
seg_grupos <- function(ahora = seg_ahora()) {
  db_get("
    SELECT c.fecha,
           to_char(c.hora_inicio, 'HH24:MI')          AS hora_inicio,
           to_char(c.hora_fin,    'HH24:MI')          AS hora_fin,
           COALESCE(c.link, '')                       AS link,
           count(DISTINCT c.id_anonimizado)::int      AS personas,
           g.usuario,
           COALESCE(u.nombre, g.usuario)              AS aplicador,
           (c.fecha + c.hora_inicio) <= $1::timestamp AS empezo,
           (c.fecha + c.hora_fin)    <= $1::timestamp AS termino,
           COALESCE(o.n, 0)                           AS anotaciones
      FROM seguimiento.citaciones c
      LEFT JOIN seguimiento.grupos_aplicador g
             ON g.fecha = c.fecha AND g.hora_inicio = c.hora_inicio
            AND g.hora_fin = c.hora_fin AND g.link = COALESCE(c.link, '')
      LEFT JOIN auth.usuarios u ON u.usuario = g.usuario
      LEFT JOIN LATERAL (
        SELECT count(*)::int AS n FROM seguimiento.observacionespsicologos ob
         WHERE ob.fecha = c.fecha AND ob.hora_inicio = c.hora_inicio
           AND ob.hora_fin = c.hora_fin AND ob.link = COALESCE(c.link, '')) o ON TRUE
     GROUP BY c.fecha, c.hora_inicio, c.hora_fin, COALESCE(c.link, ''), g.usuario, u.nombre,
              o.n
     ORDER BY c.fecha, c.hora_inicio, c.hora_fin, 4",
    params = list(ahora))
}

# `g` es lo que devuelve seg_grupo_de_clave(). Las tres devuelven TRUE si
# escribieron algo y FALSE si la regla no lo permitio.

# Toma un grupo que siga en la agenda, libre y sin empezar, para un usuario que
# todavia exista con un rol que aplica: una sesion abierta de alguien recien
# eliminado, o a quien le quitaron el rol, no toma grupos.
seg_grupo_tomar <- function(g, usuario, ahora = seg_ahora()) {
  db_exec(paste("
    INSERT INTO seguimiento.grupos_aplicador
           (fecha, hora_inicio, hora_fin, link, usuario, asignado_por)
    SELECT $1::date, $2::time, $3::time, $4, $5, $5
     WHERE ($1::date + $2::time) > $6::timestamp
       AND EXISTS (SELECT 1 FROM auth.usuarios
                    WHERE usuario = $5 AND rol = ANY($7::text[]))
       AND", SEG_GRUPO_EN_AGENDA, "
    ON CONFLICT DO NOTHING"),
    params = list(g$fecha, g$hora_inicio, g$hora_fin, g$link, usuario, ahora,
                  auth_pg_roles(AUTH_PERMISOS$tomar_grupos))) > 0
}

# Suelta un grupo propio que no ha empezado.
seg_grupo_soltar <- function(g, usuario, ahora = seg_ahora()) {
  db_exec("
    DELETE FROM seguimiento.grupos_aplicador
     WHERE fecha = $1::date AND hora_inicio = $2::time AND hora_fin = $3::time
       AND link = $4 AND usuario = $5
       AND (fecha + hora_inicio) > $6::timestamp",
    params = list(g$fecha, g$hora_inicio, g$hora_fin, g$link, usuario, ahora)) > 0
}

# Lo que hace quien tiene el permiso `asignar_grupos`: pone a `usuario` en el grupo, en
# lugar de quien estuviera, o lo deja libre con usuario = NA. `usuario` tiene que
# tener un rol que aplica (psicologo). Sin restriccion de hora, para poder
# corregir quien aplico un grupo que ya paso.
seg_grupo_asignar <- function(g, usuario, por) {
  clave <- list(g$fecha, g$hora_inicio, g$hora_fin, g$link)
  if (is.na(usuario) || !nzchar(usuario)) {
    db_exec("
      DELETE FROM seguimiento.grupos_aplicador
       WHERE fecha = $1::date AND hora_inicio = $2::time AND hora_fin = $3::time
         AND link = $4", params = clave)
    return(TRUE)
  }
  db_exec(paste("
    INSERT INTO seguimiento.grupos_aplicador
           (fecha, hora_inicio, hora_fin, link, usuario, asignado_por)
    SELECT $1::date, $2::time, $3::time, $4, $5, $6
     WHERE EXISTS (SELECT 1 FROM auth.usuarios
                    WHERE usuario = $5 AND rol = ANY($7::text[]))
       AND", SEG_GRUPO_EN_AGENDA, "
    ON CONFLICT (fecha, hora_inicio, hora_fin, link) DO UPDATE
       SET usuario = EXCLUDED.usuario, asignado = now(),
           asignado_por = EXCLUDED.asignado_por"),
    params = c(clave, list(usuario, por, auth_pg_roles(AUTH_PERMISOS$tomar_grupos)))) > 0
}

# Asignaciones cuyo grupo no esta en `cit`: al cargar esa agenda se pierden.
seg_grupos_huerfanos <- function(cit) {
  a <- db_get("
    SELECT g.fecha,
           to_char(g.hora_inicio, 'HH24:MI') AS hora_inicio,
           to_char(g.hora_fin,    'HH24:MI') AS hora_fin,
           g.link,
           COALESCE(u.nombre, g.usuario)     AS aplicador
      FROM seguimiento.grupos_aplicador g
      LEFT JOIN auth.usuarios u ON u.usuario = g.usuario
     ORDER BY g.fecha, g.hora_inicio")
  fuera <- !seg_grupo_clave(a$fecha, a$hora_inicio, a$hora_fin, a$link) %in%
            seg_grupo_clave(cit$fecha, cit$hora_inicio, cit$hora_fin, cit$link)
  out <- a[fuera, , drop = FALSE]
  rownames(out) <- NULL
  out
}


# --- anotaciones de los psicologos -------------------------------------------
# Lo que el psicologo escribe de cada sesion: una anotacion para todo el grupo y,
# cuando hace falta, una para alguien en particular. Va en
# seguimiento.observacionespsicologos (ver seg_init_db()). Solo se guarda lo que
# tiene texto: al borrar el texto se borra la fila.
#
# Quien puede que:
#   - escribir o corregir: el psicologo asignado al grupo (AUTH_PERMISOS
#     $registrar_sesion) desde la hora de inicio, sin plazo --una sesion vieja se
#     anota cuando aparezca el rato de hacerlo--, y quien tenga revisar_sesiones
#     (administrador) en cualquier grupo que haya empezado.
#   - leer la del grupo: cualquier rol.
#   - leer las de cada persona, y ver los nombres: el psicologo del grupo
#     --tambien si las escribio y despues se lo reasignaron-- y quien tenga
#     revisar_sesiones. Es informacion sensible sobre personas evaluadas en
#     riesgo psicosocial.

OBS_MAX_TEXTO <- 4000L

obs_texto <- function(x) {
  if (is.null(x) || length(x) != 1 || is.na(x)) return(NA_character_)
  x <- trimws(as.character(x))
  if (!nzchar(x)) NA_character_ else substr(x, 1, OBS_MAX_TEXTO)
}

# Lo que `usuario` puede hacer con el registro del grupo `g` (de
# seg_grupo_de_clave()): list(editar, ver_personas, asignado_a).
seg_obs_permiso <- function(g, usuario, ahora = seg_ahora()) {
  x <- db_get("
    SELECT ($1::date + $2::time) <= $5::timestamp AS empezo,
           (SELECT ga.usuario FROM seguimiento.grupos_aplicador ga
             WHERE ga.fecha = $1::date AND ga.hora_inicio = $2::time
               AND ga.hora_fin = $3::time AND ga.link = $4) AS asignado_a,
           (SELECT o.psicologo FROM seguimiento.observacionespsicologos o
             WHERE o.tipo = 'grupo' AND o.fecha = $1::date AND o.hora_inicio = $2::time
               AND o.hora_fin = $3::time AND o.link = $4) AS psicologo,
           (SELECT o.registrado_por FROM seguimiento.observacionespsicologos o
             WHERE o.tipo = 'grupo' AND o.fecha = $1::date AND o.hora_inicio = $2::time
               AND o.hora_fin = $3::time AND o.link = $4) AS registrado_por",
    params = list(g$fecha, g$hora_inicio, g$hora_fin, g$link, ahora))

  rol      <- if (is.null(usuario)) NA_character_ else auth_rol(usuario)
  revisor  <- auth_puede(rol, "revisar_sesiones")
  registra <- auth_puede(rol, "registrar_sesion")
  asignado <- registra && identical(x$asignado_a[1], usuario)
  autor    <- registra && isTRUE(usuario %in% c(x$psicologo[1], x$registrado_por[1]))

  list(editar       = isTRUE(x$empezo[1]) && (revisor || asignado),
       ver_personas = revisor || asignado || autor,
       asignado_a   = x$asignado_a[1])
}

# La anotacion del grupo (0 o 1 fila) y las personas: las citadas en la agenda
# mas las que ya tienen anotacion, por si la agenda cambio despues. `nombre`
# viene de la agenda y puede ser NA si el archivo no traia la columna; se ordena
# por nombre para que el psicologo lea la lista como la ve en su sesion.
seg_obs_leer <- function(g) {
  p <- list(g$fecha, g$hora_inicio, g$hora_fin, g$link)
  sesion <- db_get("
    SELECT observacion, psicologo, registrado_por, registrado_en,
           actualizado_por, actualizado_en
      FROM seguimiento.observacionespsicologos
     WHERE tipo = 'grupo' AND fecha = $1::date AND hora_inicio = $2::time
       AND hora_fin = $3::time AND link = $4", params = p)
  personas <- db_get("
    SELECT ids.id_anonimizado,
           (SELECT max(c.nombre) FROM seguimiento.citaciones c
             WHERE c.id_anonimizado = ids.id_anonimizado AND c.fecha = $1::date
               AND c.hora_inicio = $2::time AND c.hora_fin = $3::time
               AND COALESCE(c.link, '') = $4) AS nombre,
           o.observacion, o.registrado_por, o.actualizado_por
      FROM (SELECT c.id_anonimizado FROM seguimiento.citaciones c
             WHERE c.fecha = $1::date AND c.hora_inicio = $2::time
               AND c.hora_fin = $3::time AND COALESCE(c.link, '') = $4
            UNION
            SELECT p.id_anonimizado FROM seguimiento.observacionespsicologos p
             WHERE p.tipo = 'persona' AND p.fecha = $1::date AND p.hora_inicio = $2::time
               AND p.hora_fin = $3::time AND p.link = $4) ids
      LEFT JOIN seguimiento.observacionespsicologos o
             ON o.tipo = 'persona' AND o.fecha = $1::date AND o.hora_inicio = $2::time
            AND o.hora_fin = $3::time AND o.link = $4
            AND o.id_anonimizado = ids.id_anonimizado
     ORDER BY 2 NULLS LAST, 1", params = p)
  list(sesion = sesion, personas = personas)
}

# Guarda las anotaciones de una sesion en una transaccion: la del grupo y las de
# cada persona. `general` es el texto del grupo y `personas` un
# data.frame(id_anonimizado, observacion), o NULL. Lo que quede vacio no se
# guarda, y si tenia fila se borra: la tabla solo tiene lo que alguien escribio.
#
# Corregir no pisa quien escribio: marca actualizado_por/actualizado_en, y solo
# en las filas que de verdad cambiaron.
seg_obs_guardar <- function(g, general, personas = NULL, usuario, ahora = seg_ahora()) {
  general <- obs_texto(general)
  if (!is.null(personas) && nrow(personas)) {
    personas$observacion <- vapply(personas$observacion, obs_texto, character(1),
                                   USE.NAMES = FALSE)
  }

  perm <- seg_obs_permiso(g, usuario, ahora)
  if (!isTRUE(perm$editar)) {
    stop("No puede anotar esta sesión: no está a su nombre o todavía no empieza.",
         call. = FALSE)
  }

  clave <- list(g$fecha, g$hora_inicio, g$hora_fin, g$link)
  conflicto <- "ON CONFLICT (fecha, hora_inicio, hora_fin, link, (COALESCE(id_anonimizado, '')))"
  borrar <- function(con, id = NULL) {
    DBI::dbExecute(con, sprintf("
      DELETE FROM seguimiento.observacionespsicologos
       WHERE fecha = $1::date AND hora_inicio = $2::time AND hora_fin = $3::time
         AND link = $4 AND %s",
      if (is.null(id)) "tipo = 'grupo'" else "tipo = 'persona' AND id_anonimizado = $5"),
      params = c(clave, if (!is.null(id)) list(id)))
  }

  db_tx(function(con) {
    if (is.na(general)) {
      borrar(con)
    } else {
      DBI::dbExecute(con, paste("
        INSERT INTO seguimiento.observacionespsicologos AS o
               (tipo, fecha, hora_inicio, hora_fin, link, observacion, psicologo, registrado_por)
        VALUES ('grupo', $1::date, $2::time, $3::time, $4, $5, $6, $7)",
        conflicto, "
        DO UPDATE SET observacion     = EXCLUDED.observacion,
                      psicologo       = COALESCE(o.psicologo, EXCLUDED.psicologo),
                      actualizado_por = EXCLUDED.registrado_por,
                      actualizado_en  = now()
         WHERE o.observacion IS DISTINCT FROM EXCLUDED.observacion"),
        params = c(clave, list(general, perm$asignado_a, usuario)))
    }

    for (i in seq_len(if (is.null(personas)) 0L else nrow(personas))) {
      f <- personas[i, ]
      if (is.na(f$observacion)) {
        borrar(con, f$id_anonimizado)
        next
      }
      DBI::dbExecute(con, paste("
        INSERT INTO seguimiento.observacionespsicologos AS o
               (tipo, fecha, hora_inicio, hora_fin, link, id_anonimizado, observacion,
                psicologo, registrado_por)
        VALUES ('persona', $1::date, $2::time, $3::time, $4, $5, $6, $7, $8)",
        conflicto, "
        DO UPDATE SET observacion     = EXCLUDED.observacion,
                      psicologo       = COALESCE(o.psicologo, EXCLUDED.psicologo),
                      actualizado_por = EXCLUDED.registrado_por,
                      actualizado_en  = now()
         WHERE o.observacion IS DISTINCT FROM EXCLUDED.observacion"),
        params = c(clave, list(f$id_anonimizado, f$observacion, perm$asignado_a, usuario)))
    }
  })
  invisible(TRUE)
}

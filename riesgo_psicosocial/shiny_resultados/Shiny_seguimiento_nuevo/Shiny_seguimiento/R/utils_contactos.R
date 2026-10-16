# -----------------------------------------------------------------------------
# utils_contactos.R
# Bitacora de contactos con las personas que faltan por responder. Sin nada de UI.
#
# Vive en su propia tabla --seguimiento.contactos-- y no como columnas de
# `respuestas` ni de `marco`: conectar_bd.R BORRA Y REESCRIBE
# public.respuestas_procesadas en cada carga de datos, y ahi se perderia el trabajo de
# campo. `metas` ya sigue esa regla (la carga no la toca) y esta tabla se suma a
# ella.
#
# Es un registro historico: nunca se actualiza en sitio ni se borra, solo se
# agregan filas. Una persona puede tener muchos contactos, y de esa pila sale
# tanto el conteo como el estado de hoy.
#
# No hay clave foranea contra seguimiento.marco a proposito: el marco se recarga
# desde fuera de la app y una persona puede desaparecer de el (cambia de
# dependencia, se desvincula) sin que eso deba borrar la constancia de que
# alguien la llamo. El id_anonimizado queda huerfano y no estorba.
# -----------------------------------------------------------------------------

# Los medios que ofrece el formulario. "otro" obliga a escribir cual: sin eso, la
# opcion se vuelve un cajon de sastre que no se puede contar despues.
CTO_MEDIOS <- c("Correo" = "correo", "Llamada" = "llamada", "Otro" = "otro")

# Como termino el seguimiento de esa persona. Van en un solo campo y no en varias
# casillas porque son excluyentes: nadie es a la vez un rechazo y una ausencia, y
# con casillas sueltas si se podria marcar. "contacto" es la opcion normal --se
# le busco y la gestion sigue abierta-- y las otras dos la cierran.
#
# La diferencia entre las dos importa para el informe: el rechazo es una decision
# que la persona tomo y dijo; la ausencia es que no contesto a ninguna
# convocatoria. La primera se respeta; la segunda mide el alcance del operativo.
CTO_RESULTADOS <- c(
  "La gestión sigue abierta"                     = "contacto",
  "Rechazo: manifestó que no participará"        = "rechazo",
  "Ausente: no respondió a ninguna convocatoria" = "ausente"
)

# Los dos que cierran el caso y sacan a la persona de "Faltan".
CTO_CIERRES <- c("rechazo", "ausente")

# Deshace un cierre: la persona que se habia dado por rechazo o ausente avisa
# que al final quiere responder. No va en CTO_RESULTADOS porque no es algo que
# se elija al registrar un contacto cualquiera: tiene su propio boton y su
# propia ventana (ver cto_reabrir()). Como no es un cierre, basta con que sea el
# ULTIMO contacto para que la persona vuelva a "Faltan" en toda la app --lista
# de personas, avance, vista estado_persona--, que ya deciden por el ultimo.
CTO_REAPERTURA <- "reabierto"


cto_init_db <- function() {
  db_exec("CREATE SCHEMA IF NOT EXISTS seguimiento")

  db_exec("
    CREATE TABLE IF NOT EXISTS seguimiento.contactos (
      id             bigserial   PRIMARY KEY,
      id_anonimizado text        NOT NULL,
      fecha          date        NOT NULL,
      medio          text        NOT NULL,
      medio_otro     text,
      resultado      text        NOT NULL DEFAULT 'contacto',
      observacion    text,
      registrado_por text,
      registrado_en  timestamptz NOT NULL DEFAULT now()
    )")

  # Migracion de la primera version, que solo sabia de rechazos y lo guardaba en
  # un booleano. Al aparecer "ausente" el campo se queda corto: dos estados
  # excluyentes no caben en un si/no. Es idempotente --si la columna vieja ya no
  # esta, el bloque no hace nada-- igual que la migracion de auth.usuarios.
  db_exec("ALTER TABLE seguimiento.contactos
             ADD COLUMN IF NOT EXISTS resultado text")
  db_exec("
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'seguimiento'
                    AND table_name   = 'contactos'
                    AND column_name  = 'rechazo') THEN
        UPDATE seguimiento.contactos
           SET resultado = CASE WHEN rechazo THEN 'rechazo' ELSE 'contacto' END
         WHERE resultado IS NULL;
        ALTER TABLE seguimiento.contactos DROP COLUMN rechazo;
      END IF;
    END $$;")
  db_exec("UPDATE seguimiento.contactos SET resultado = 'contacto'
            WHERE resultado IS NULL")
  db_exec("ALTER TABLE seguimiento.contactos
             ALTER COLUMN resultado SET DEFAULT 'contacto'")
  db_exec("ALTER TABLE seguimiento.contactos
             ALTER COLUMN resultado SET NOT NULL")

  db_exec("CREATE INDEX IF NOT EXISTS idx_contactos_persona
             ON seguimiento.contactos (id_anonimizado)")
  db_exec("CREATE INDEX IF NOT EXISTS idx_contactos_fecha
             ON seguimiento.contactos (fecha DESC)")

  invisible(TRUE)
}


# Registra UN contacto para una o varias personas. En lote se guarda una fila
# por persona y no una fila compartida: el historial se lee siempre por persona,
# y una fila con una lista dentro obligaria a desarmarla en cada consulta.
#
# Va en una sola sentencia con unnest() en vez de un bucle de INSERT: N viajes a
# la base por N personas, y sin transaccion un fallo a mitad dejaria media
# seleccion registrada y la otra media no.
cto_registrar <- function(ids, fecha, medio, medio_otro = NA_character_,
                          observacion = NA_character_, resultado = "contacto",
                          usuario = NA_character_) {

  ids <- unique(as.character(ids))
  ids <- ids[!is.na(ids) & nzchar(ids)]
  if (length(ids) == 0) {
    stop("No hay ninguna persona seleccionada.", call. = FALSE)
  }

  fecha <- suppressWarnings(as.Date(fecha))
  if (length(fecha) != 1 || is.na(fecha)) {
    stop("La fecha del contacto no es válida.", call. = FALSE)
  }
  # Es una bitacora de lo que ya paso, no una agenda: una fecha futura solo
  # puede ser un dedazo, y ademas descuadraria el "último contacto".
  if (fecha > seg_hoy()) {
    stop("La fecha del contacto no puede estar en el futuro.", call. = FALSE)
  }

  if (length(medio) != 1 || !medio %in% CTO_MEDIOS) {
    stop("Seleccione el medio de contacto.", call. = FALSE)
  }

  medio_otro <- if (identical(medio, "otro")) {
    x <- limpiar_texto(medio_otro)
    if (is.na(x)) stop("Escriba cuál fue el medio de contacto.", call. = FALSE)
    x
  } else {
    NA_character_
  }

  if (length(resultado) != 1 || !resultado %in% c(CTO_RESULTADOS, CTO_REAPERTURA)) {
    stop("Seleccione cómo termina el seguimiento.", call. = FALSE)
  }

  obs <- limpiar_texto(observacion)

  db_exec("
    INSERT INTO seguimiento.contactos
      (id_anonimizado, fecha, medio, medio_otro, resultado, observacion, registrado_por)
    SELECT p, $2::date, $3, $4, $5, $6, $7
      FROM unnest(string_to_array($1, chr(1))) AS p",
    params = list(paste(ids, collapse = SEG_SEP), format(fecha), medio,
                  medio_otro, resultado, obs, usuario))

  invisible(length(ids))
}


# Reabre el caso de una o varias personas cerradas por la bitacora. Se registra
# como un contacto mas --la bitacora solo agrega, nunca borra-- con resultado
# "reabierto", asi que el historial conserva el cierre y la reapertura.
#
# Solo reabre a quien HOY esta cerrado por su ultimo contacto; el resto de la
# seleccion se ignora y la cuenta devuelta lo dice. Un rechazo del formulario
# ("No acepto") no se puede reabrir desde aqui: ese envio existe y manda sobre la
# bitacora. Si la persona vuelve a responder, lo hace con un envio nuevo.
#
# La fecha es SIEMPRE hoy, no una que se elija: el estado lo decide el ultimo
# contacto por fecha, y una reapertura fechada antes del cierre quedaria debajo
# de el y no reabriria nada. El mismo dia desempata el id, que es mas nuevo.
cto_reabrir <- function(ids, medio, medio_otro = NA_character_,
                        observacion = NA_character_, usuario = NA_character_) {
  ids <- unique(as.character(ids))
  ids <- ids[!is.na(ids) & nzchar(ids)]
  if (length(ids) == 0) stop("No hay ninguna persona seleccionada.", call. = FALSE)

  cerrados <- db_get(sprintf("
    SELECT id_anonimizado FROM (%s) k
     WHERE k.cerrado AND k.id_anonimizado = ANY(string_to_array($1, chr(1)))",
    seg_sql_cierre()),
    params = list(paste(ids, collapse = SEG_SEP)))$id_anonimizado
  if (length(cerrados) == 0) {
    stop("Ninguna de las personas marcadas tiene el caso cerrado.", call. = FALSE)
  }

  cto_registrar(cerrados, seg_hoy(), medio, medio_otro, observacion,
                resultado = CTO_REAPERTURA, usuario = usuario)
}


# Texto de formulario a texto de base: sin espacios de sobra y NA cuando no hay
# nada. Ojo con NA: `%||%` solo atrapa NULL, asi que trimws(NA) devolveria "NA"
# --la palabra-- y se guardaria como si el usuario la hubiera escrito.
limpiar_texto <- function(x) {
  if (length(x) != 1 || is.na(x)) return(NA_character_)
  x <- trimws(as.character(x))
  if (nzchar(x)) x else NA_character_
}


# Una fila por persona CON contactos: cuantos lleva, cuando fue el ultimo, por
# que medio y si hoy esta en rechazo. Una sola consulta por dependencia, que se
# pega despues a la lista de personas.
#
# El desenlace lo decide el ULTIMO contacto y no un "alguna vez dijo que no":
# asi se corrige registrando un contacto nuevo --que es como se corrige todo
# aqui, agregando y no borrando-- y el historial conserva las dos versiones.
cto_resumen_dependencia <- function(dependencia) {
  db_get("
    SELECT c.id_anonimizado,
           count(*)::int AS contactos,
           max(c.fecha)  AS ultimo_contacto,
           (array_agg(c.medio      ORDER BY c.fecha DESC, c.id DESC))[1] AS ultimo_medio,
           (array_agg(c.medio_otro ORDER BY c.fecha DESC, c.id DESC))[1] AS ultimo_medio_otro,
           (array_agg(c.resultado  ORDER BY c.fecha DESC, c.id DESC))[1] AS resultado
      FROM seguimiento.contactos c
      JOIN seguimiento.marco_completo m USING (id_anonimizado)
     WHERE m.dependencia = $1
     GROUP BY c.id_anonimizado",
    params = list(dependencia))
}


cto_historial <- function(id_anonimizado) {
  db_get("
    SELECT fecha, medio, medio_otro, resultado, observacion,
           registrado_por, registrado_en
      FROM seguimiento.contactos
     WHERE id_anonimizado = $1
     ORDER BY fecha DESC, id DESC",
    params = list(id_anonimizado))
}


# Medio en palabras. "Otro" sin el detalle no dice nada, asi que se muestran los
# dos juntos.
cto_medio_txt <- function(medio, otro = NA_character_) {
  if (length(medio) != 1 || is.na(medio)) return("—")
  rotulo <- names(CTO_MEDIOS)[match(medio, CTO_MEDIOS)]
  if (is.na(rotulo)) rotulo <- medio
  if (identical(medio, "otro") && !is.na(otro) && nzchar(otro)) {
    sprintf("%s: %s", rotulo, otro)
  } else {
    rotulo
  }
}


# Pega el resumen de contactos a la lista de personas y aplica el unico cambio
# de situacion que la bitacora puede provocar: a quien se le cerro el caso deja
# de estar en "falta" y pasa a "rechazo" o a "ausente", segun como se cerro.
#
# Solo cambia a quien esta en "falta". Si la persona ya respondio, su respuesta
# manda sobre cualquier contacto posterior --el dato existe, esta en la base--, y
# a quien no es elegible no se le persigue de todas formas. Asi el numero de
# encuestados sigue saliendo enteramente de public.respuestas_procesadas y ningun clic
# en la app puede moverlo.
cto_aplicar <- function(p, resumen) {
  if (is.null(p) || nrow(p) == 0) return(p)

  vacio <- is.null(resumen) || nrow(resumen) == 0
  i <- if (vacio) rep(NA_integer_, nrow(p)) else match(p$id_anonimizado, resumen$id_anonimizado)

  p$contactos       <- if (vacio) 0L else ifelse(is.na(i), 0L, resumen$contactos[i])
  p$ultimo_contacto <- if (vacio) as.Date(NA) else resumen$ultimo_contacto[i]
  p$ultimo_medio    <- if (vacio) NA_character_ else resumen$ultimo_medio[i]
  p$ultimo_medio_otro <- if (vacio) NA_character_ else resumen$ultimo_medio_otro[i]

  cierre <- if (vacio) rep(NA_character_, nrow(p)) else resumen$resultado[i]
  cierre <- ifelse(!is.na(cierre) & cierre %in% CTO_CIERRES, cierre, NA_character_)

  # Se marca cuales cerro la bitacora, para distinguirlos de los que ya venian
  # cerrados por el formulario: en esos el boton de contacto no tendria nada que
  # hacer --el dato manda sobre la bitacora-- y seria un boton que no cumple.
  aplica <- !is.na(cierre) & p$situacion == "falta"
  p$cierre_bitacora <- aplica
  p$situacion <- ifelse(aplica, cierre, p$situacion)

  # UNA sola variable para los casos cerrados sin encuesta, entren por donde
  # entren: quien marco "No acepto" en el formulario (respuestas.acepta), quien
  # se lo dijo a un gestor y quien nunca contesto pese a todas las convocatorias
  # (contactos.resultado). Es la que se lleva el CSV y la que hay que sumar en un
  # informe cuando la pregunta es "de cuanta gente no vamos a tener encuesta".
  #
  # Se llama `no_participa` y no `rechaza` porque no todos rechazaron: un ausente
  # no dijo que no, no dijo nada. La diferencia entre los tres sigue estando en
  # `situacion`, que es la columna a la que hay que ir cuando importa cual fue.
  #
  # Se calcula en este punto y no antes porque es aqui donde las tres fuentes ya
  # estan aplicadas sobre la misma columna; asi nadie tiene que volver a hacer la
  # union por su cuenta y arriesgarse a hacerla distinto.
  #
  # No se pueden juntar mas abajo, en la base: public.respuestas_procesadas se borra y
  # se reescribe en cada carga de datos (ver conectar_bd.R), asi que un cierre
  # anotado a mano dentro de esa tabla desapareceria en la siguiente carga. Cada
  # fuente se queda en su tabla y la union se hace al leer.
  p$no_participa <- p$situacion %in% CTO_CIERRES
  p
}

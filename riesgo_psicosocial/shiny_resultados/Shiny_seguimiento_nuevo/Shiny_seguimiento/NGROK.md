# Publicar la app con ngrok

Hacen falta **dos terminales abiertas al mismo tiempo**. Si cierras cualquiera
de las dos, la URL deja de servir. No queda nada corriendo solo.

URL fija de esta cuenta: `https://breach-proven-earthen.ngrok-free.dev`

---

## Una sola vez

```bash
~/.local/bin/ngrok config add-authtoken TU_TOKEN
```

El token está en <https://dashboard.ngrok.com/get-started/your-authtoken>.
Queda guardado en `~/.config/ngrok/ngrok.yml`; no hay que repetirlo.

---

## Levantar

**Terminal 1 — la app.** Dejar abierta.

```bash
cd ~/Documents/Riesgo_psicosocial/Shiny_seguimiento
Rscript -e "shiny::runApp('.', port = 7788, host = '127.0.0.1', launch.browser = FALSE)"
```

Esperar a que diga `Listening on http://127.0.0.1:7788`.

**Terminal 2 — el túnel.** Dejar abierta.

```bash
~/.local/bin/ngrok http 7788 --url https://breach-proven-earthen.ngrok-free.dev
```

Revisar que la línea `Forwarding` diga **`-> http://localhost:7788`**. Si dice
`:80`, está mal el puerto y la URL va a dar error.

Ya se puede abrir la URL en el navegador.

---

## Ver si está corriendo

```bash
pgrep -af ngrok        # el túnel
ss -ltnp | grep 7788   # la app
```

También sirve el panel local <http://127.0.0.1:4040>, que muestra cada petición
que entra.

---

## Bajar

`Ctrl-C` en cada terminal.

Si se perdieron las terminales:

```bash
pkill -f ngrok
pkill -f "shiny::runApp"
ss -ltnp | grep -E ":(7788|4040)"   # sin salida = todo abajo
```

Bajar el túnel no quita el dominio: sigue reservado a la cuenta.

---

## Antes de compartir la URL

El dominio es fijo, así que la URL es permanente y adivinable una vez que
alguien la vio. El ingreso se defiende solo (bloqueo por intentos fallidos,
claves de 8 caracteres, cierre por inactividad; ver el README), pero no hay
razón para dejar el túnel abierto cuando no se usa: **bajarlo al terminar**.

La app tiene que escuchar en `127.0.0.1`, como en el comando de arriba. La IP
que registra la bitácora sale de la cabecera `X-Forwarded-For` que agrega
ngrok; si la app escuchara en `0.0.0.0`, alguien de la red local podría entrar
sin pasar por el túnel y escribir esa cabecera a su gusto.

Con la base vacía, el formulario de primer arranque pide el código
`APP_CODIGO_INSTALACION` de `.Renviron`: sin él, quien abriera la URL primero se
quedaría con la cuenta de administrador.

La base de datos no queda expuesta: PostgreSQL sigue en el socket de Unix con
autenticación *peer*, así que por el túnel solo se llega a la app.

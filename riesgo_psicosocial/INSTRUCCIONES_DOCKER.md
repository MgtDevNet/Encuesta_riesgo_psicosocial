# 📋 Instrucciones para ejecutar la aplicación Shiny con Docker

Esta guía tiene dos partes:

- **Parte 1 — Quien entrega el proyecto:** saca una copia de la base de datos y entrega la carpeta.
- **Parte 2 — Quien lo recibe:** instala Docker, carga los datos y levanta la aplicación.

La aplicación son dos contenedores que corren en el computador de cada persona:

| Contenedor | Qué es | De dónde sale |
|---|---|---|
| `riesgo_psicosocial_postgres` | La base de datos PostgreSQL 16 | Se descarga la imagen oficial `postgres:16` |
| `riesgo_psicosocial_shiny` | La aplicación Shiny | Se construye con `docker/Dockerfile` y el código de la app |

> ⚠️ **La base de datos de cada computador empieza VACÍA.** Los datos viven en un volumen de Docker
> (`postgres_data`) que es propio de cada máquina; no viajan con la carpeta. Por eso hay que
> llevar una copia de la base (Parte 1) y cargarla (Parte 2, paso 3).

---

## 📦 Estructura de carpetas

```
riesgo_psicosocial/
├── .dockerignore                      # lo que NO se copia a la imagen (credenciales, respaldos)
├── docker/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── .env.example                   # plantilla de la configuración (va a git)
│   └── .env                           # usuario, contraseña y puertos de ESTE equipo — PRIVADO
├── shiny_resultados/
│   └── Shiny_seguimiento_nuevo/
│       └── Shiny_seguimiento/
│           ├── app.R
│           ├── conectar_bd.R          # califica las respuestas y llena public.respuestas_procesadas
│           ├── R/  Modules/  www/  Diccionarios/  scripts/
│           └── ... (resto de archivos)
├── descarga_datos_reales/
│   ├── actualizar_datos.sh            # lo que corre el cron: descarga de ODK + calificación
│   ├── conexion_resultados_odk.R      # descarga de ODK -> public.odk_respuestas_intento_2
│   ├── .Renviron                      # credenciales de ODK (ODK_USER, ODK_PASSWORD) — PRIVADO
│   ├── iniciar_wsl.bat
│   └── logs_conexion.txt              # salida del crontab
└── backups/
    └── bd.dump                        # copia de la base de datos (ver Parte 1)
```

---

# PARTE 1 — Quien entrega el proyecto (en el computador que ya tiene los datos)

### Paso 1: Sacar una copia de la base de datos

Con Docker Desktop abierto y los contenedores corriendo, en PowerShell, desde la carpeta
`riesgo_psicosocial`:

```powershell
docker exec riesgo_psicosocial_postgres pg_dump -U erps_user -d riesgo_psicosocial -Fc -f /tmp/bd.dump
docker cp riesgo_psicosocial_postgres:/tmp/bd.dump ./backups/bd.dump
```

Queda `backups\bd.dump` con TODO: marco, respuestas, usuarios, citaciones y contactos.

> ❗ **No uses `pg_dump ... > archivo.sql` en PowerShell.** PowerShell guarda la salida en
> UTF-16 y `psql` no puede leer ese archivo. Generar la copia dentro del contenedor (`-f`) y
> sacarla con `docker cp`, como arriba, evita el problema.

### Paso 2: Entregar la carpeta

Copia la carpeta **`riesgo_psicosocial` completa** (USB, Drive o .zip). Debe llevar como mínimo:

- `docker\`
- `shiny_resultados\Shiny_seguimiento_nuevo\Shiny_seguimiento\`
- `descarga_datos_reales\`
- `backups\bd.dump`

Entrega siempre la **versión actual** del código.

### Paso 3: Credenciales

Dos archivos tienen contraseñas y **no están en git**:

- `descarga_datos_reales\.Renviron`: usuario y contraseña de ODK.
- `docker\.env`: usuario y contraseña de la base de datos.

Van dentro de la carpeta si la copias entera; si no, envíalos por un canal privado (no por chats
o correos compartidos). En un computador **nuevo** se puede poner otra contraseña de base en
`docker\.env`: la copia (`bd.dump`) no guarda la contraseña, y la base nueva se crea con la que
diga ese archivo.

---

# PARTE 2 — Quien recibe el proyecto

## ✅ Requisitos previos

1. **Docker Desktop**
   - Descarga desde: https://www.docker.com/products/docker-desktop
   - Instala siguiendo el instalador y **reinicia** el computador.
   - Abre Docker Desktop y espera a que diga que está corriendo (*Engine running*).
2. **PowerShell** (incluido en Windows).
3. **WSL con Ubuntu** — solo si este computador va a descargar los datos de ODK solo (paso 6).
   No hace falta instalar R: la descarga corre dentro de Docker.

### Paso 1: Abre PowerShell en la carpeta docker y crea la configuración

Presiona `Windows + R`, escribe `powershell` y presiona Enter. Luego:

```powershell
cd "C:\ruta\a\riesgo_psicosocial\docker"
```

Reemplaza `C:\ruta\a\riesgo_psicosocial` con la ruta donde quedó la carpeta.

Si la carpeta **no** trae `docker\.env` (por ejemplo, porque viene de `git clone`), créalo desde
la plantilla:

```powershell
copy .env.example .env
notepad .env
```

En el Bloc de notas cambia `PG_PASSWORD` por una contraseña nueva, larga y aleatoria. Guarda y
cierra. Sin este archivo, `docker compose` se detiene con el mensaje
`Falta PG_PASSWORD en docker/.env`.

> ❗ La contraseña solo se aplica la **primera vez** que se crea la base (paso 2). Si este
> computador ya tenía la base creada, `PG_PASSWORD` tiene que ser la que se usó entonces;
> cambiarla después en `.env` no cambia la de la base, y la app dejaría de conectarse.

### Paso 2: Levanta SOLO la base de datos

```powershell
docker compose up -d postgres
```

> ❗ **Todavía NO levantes la Shiny.** Al arrancar, la app crea sus tablas vacías, y esas tablas
> chocarían con las de la copia que se carga en el paso siguiente.

Si sale `port is already allocated`, ver **Solución de problemas** al final.

### Paso 3: Carga los datos

Desde la misma carpeta `docker`:

```powershell
docker cp ..\backups\bd.dump riesgo_psicosocial_postgres:/tmp/bd.dump
docker exec riesgo_psicosocial_postgres pg_restore -U erps_user -d riesgo_psicosocial --no-owner /tmp/bd.dump
```

Comprueba que llegó el marco (debe mostrar el número de personas, p. ej. 3644):

```powershell
docker exec riesgo_psicosocial_postgres psql -U erps_user -d riesgo_psicosocial -c "SELECT count(*) FROM seguimiento.marco;"
```

### Paso 4: Levanta la Shiny

```powershell
docker compose up -d --build shiny
```

**Primera vez:** tarda ~10 minutos (descarga R e instala librerías).
**Siguientes veces:** ~1-2 minutos.

Para ver cómo va el arranque:

```powershell
docker compose logs -f shiny
```

Cuando aparezca `Listening on http://0.0.0.0:7788`, ya está lista (`Ctrl + C` para salir de los logs;
la app sigue corriendo).

### Paso 5: Entra a la aplicación

Abre en el navegador:

```
http://localhost:7788
```

Entra con **los mismos usuarios que ya existían**: vienen dentro de la copia de la base.

> Si instalaste **sin copia** (base vacía), crea el primer usuario así:
> ```powershell
> docker exec -it riesgo_psicosocial_shiny Rscript /app/scripts/gestionar_usuarios.R crear admin administrador "Administrador"
> ```

### Paso 6: Descarga de ODK (manual o automática)

`descarga_datos_reales/actualizar_datos.sh` hace todo el ciclo:

1. Descarga de ODK los envíos nuevos → `public.odk_respuestas_intento_2`
2. Si llegó alguno, los califica con `conectar_bd.R` → `public.respuestas_procesadas`
3. La Shiny lo detecta sola en menos de un minuto (la pestaña *Resultados* al recargar la página)

Los dos pasos corren **dentro del contenedor de la Shiny**: el computador solo necesita Docker,
no R. Antes de usarlo, verifica que exista `descarga_datos_reales/.Renviron` con `ODK_USER` y
`ODK_PASSWORD` (y, si la dirección de ODK cambió, `ODK_URL`).

**Manual**, desde Ubuntu (WSL) o desde un servidor Linux:

```bash
cd /ruta/a/riesgo_psicosocial/descarga_datos_reales
bash actualizar_datos.sh               # descarga y, si hay nuevos, califica
bash actualizar_datos.sh --calificar   # además recalifica todo aunque no haya nuevos
```

**Automática cada 15 minutos (cron):**

1. `crontab -e` (la primera vez elige `nano`) y agrega al final, con la ruta de **este** equipo:
   ```
   */15 * * * * /bin/bash /ruta/a/riesgo_psicosocial/descarga_datos_reales/actualizar_datos.sh >> /ruta/a/riesgo_psicosocial/descarga_datos_reales/logs_conexion.txt 2>&1
   ```
   Guarda con `Ctrl+O`, Enter, y sal con `Ctrl+X`.
2. **Solo en WSL:** enciende cron (WSL no lo inicia solo; repítelo tras cada reinicio, o activa
   systemd en `/etc/wsl.conf` con `[boot]` / `systemd=true`):
   ```bash
   sudo service cron start
   ```
   En un servidor Linux en la nube cron ya está encendido.
3. Revisa que corre: `tail -20 /ruta/a/riesgo_psicosocial/descarga_datos_reales/logs_conexion.txt`
   debe mostrar líneas con fecha como `[2026-10-06 10:45:00] Descargando envios de ODK...`.

> ⚠️ En WSL el cron solo corre mientras WSL esté abierto (deja una ventana de Ubuntu abierta o
> usa `iniciar_wsl.bat`). La dirección de ODK por defecto es una URL gratuita de ngrok, que
> cambia cada vez que ngrok se reinicia: si cambia, ponla en `ODK_URL` dentro del `.Renviron`.

---

## 🔄 Uso diario

- **Encender:** abre Docker Desktop. Los contenedores arrancan solos (`restart: unless-stopped`).
  Si no, desde la carpeta `docker`: `docker compose up -d`
- **Apagar:** desde la carpeta `docker`: `docker compose down`
- **Ver los logs de la app:** `docker compose logs -f shiny`
- **Después de cambiar el código de la app:** `docker compose up -d --build shiny`
  (el código va copiado dentro de la imagen; sin `--build` sigue corriendo la versión vieja).

> ❗ **Nunca uses `docker compose down -v`** salvo que quieras borrarlo todo: la `-v` elimina
> el volumen y con él **todos los datos** de la base.

Los datos se guardan solos en el volumen; apagar los contenedores o el computador no los borra.

---

## 🔐 Crear más usuarios

Desde la propia aplicación con el perfil de administrador, o en PowerShell:

```powershell
docker exec -it riesgo_psicosocial_shiny Rscript /app/scripts/gestionar_usuarios.R crear <usuario> <rol> "Nombre Completo"
```

- `<usuario>`: nombre de usuario (sin espacios)
- `<rol>`: `administrador`, `coordinador`, `auxiliar` o `psicologo`
- `"Nombre Completo"`: el nombre real

Ejemplo:

```powershell
docker exec -it riesgo_psicosocial_shiny Rscript /app/scripts/gestionar_usuarios.R crear juan coordinador "Juan Pérez"
```

---

## 🌐 Compartir la aplicación por internet con ngrok (opcional)

1. Descarga ngrok: https://ngrok.com/download
2. En otra ventana de PowerShell: `ngrok http 7788`
3. Comparte la URL que muestra (`https://xxxxx.ngrok-free.dev`).

---

## 💾 Otros comandos útiles

**Sacar una copia de la base** (ver Parte 1, paso 1):
```powershell
docker exec riesgo_psicosocial_postgres pg_dump -U erps_user -d riesgo_psicosocial -Fc -f /tmp/bd.dump
docker cp riesgo_psicosocial_postgres:/tmp/bd.dump ./backups/bd.dump
```

**Recalificar las respuestas** (reescribe `public.respuestas_procesadas` desde
`public.odk_respuestas_intento_2`; la Shiny lo ve sola en menos de un minuto):
```powershell
docker exec -it riesgo_psicosocial_shiny sh -c "cd /app && Rscript conectar_bd.R"
```

**Cargar un marco muestral nuevo** (solo en una base que ya tiene `public.respuestas_procesadas`):
```powershell
docker exec -it riesgo_psicosocial_shiny Rscript /app/scripts/preparar_bd.R --marco=/app/marco.xlsx
```

---

## ❌ Solución de problemas

### `Falta PG_PASSWORD en docker/.env` (o `PG_USER`, `PG_DB`)
No existe `docker/.env` o le falta esa línea. Créalo desde la plantilla (Parte 2, paso 1).

### `port is already allocated` (puerto 5432 o 7788 ocupado)
Otro programa usa ese puerto; lo más común es un PostgreSQL instalado en Windows. Apágalo
(Servicios de Windows → `postgresql-...` → Detener) o cambia el puerto en `docker/.env`, por
ejemplo `PUERTO_BD=127.0.0.1:5433` (y en DBeaver usa 5433). Luego `docker compose up -d`.

### Otro computador de la red no puede abrir la Shiny
Por seguridad, la Shiny solo acepta conexiones del propio equipo (`127.0.0.1`). Para abrirla a
la red local pon `PUERTO_SHINY=7788` en `docker/.env` y ejecuta `docker compose up -d`.

### La app dice "No se pudo conectar a PostgreSQL" después de cambiar `docker/.env`
`PG_PASSWORD` no coincide con la de la base que ya existe (la contraseña solo se aplica al crear
la base). Vuelve a poner la contraseña anterior en `docker/.env` y ejecuta `docker compose up -d`.

### La app dice "No se puede iniciar la aplicación… le faltan los datos del estudio"
La base está vacía o incompleta. Revisa que el paso 3 (cargar los datos) haya terminado sin
errores y que el conteo del marco no dé 0. Si falta `public.respuestas_procesadas`, ejecuta
`conectar_bd.R` (ver *Otros comandos útiles*).

### `pg_restore` muestra errores de "already exists"
La Shiny se levantó antes de cargar la copia y creó tablas vacías. Para empezar de cero
(⚠️ borra lo que haya en la base de ESTE computador):
```powershell
docker compose down -v
docker compose up -d postgres
```
y repite desde el paso 3.

### La app dice "No se pudo conectar a PostgreSQL"
- Espera 30 segundos después de levantar los contenedores y recarga la página.
- Revisa que el contenedor esté corriendo: `docker ps`
- Si persiste: `docker compose restart`

### No veo datos nuevos en la app
- Revisa el final de `descarga_datos_reales/logs_conexion.txt`: debe decir `Calificacion lista`.
  Si dice `ERROR`, el mensaje indica qué falló.
- El avance se actualiza solo en menos de un minuto; la pestaña *Resultados*, al recargar.
- Si cambiaste código, reconstruye: `docker compose up -d --build shiny`

---

## 📝 Notas

✓ Los datos se guardan automáticamente en el volumen de Docker
✓ La aplicación funciona sin internet (la descarga de ODK sí lo necesita)
✓ Docker ocupa ~2-3 GB de disco y ~1 GB de RAM mientras corre

## 📞 ¿Necesitas ayuda?

Si algo no funciona, envía:
1. El mensaje de error exacto
2. El paso donde falla
3. La salida de `docker compose logs shiny`

---

# 📚 Anexo: explicación de docker-compose.yml

> ℹ️ Esta explicación es de una versión anterior del archivo. Lo que cambió desde entonces:
> ya no lleva `version:` (Docker la ignora); usuario, contraseña y puertos se leen de
> `docker/.env` en vez de estar escritos en el archivo; los puertos escuchan solo en
> `127.0.0.1`; Postgres también tiene `restart: unless-stopped`; y la Shiny monta
> `descarga_datos_reales` como `/descarga` (solo lectura) en vez de `marco.xlsx` y el CSV.

## **ESTRUCTURA GENERAL**

```yaml
version: '3.8'

services:
  postgres: ...
  shiny: ...

volumes: ...
networks: ...
```

Esto significa: "Docker, vas a manejar 3 cosas: versión, servicios, volúmenes y redes"

---

## **PARTE 1: VERSION**

```yaml
version: '3.8'
```

**¿Qué es?** La versión del formato de docker-compose

**¿Por qué importa?** Cada versión tiene características diferentes. La 3.8 soporta `healthcheck` en `depends_on` (que usamos).

**Equivalencia:** Como Python 3.8 vs Python 3.9 - versiones diferentes del lenguaje.

---

## **PARTE 2: POSTGRESQL (SERVICIO 1)**

```yaml
services:
  postgres:
    image: postgres:16
```

**¿Qué es?** Levanta un contenedor con PostgreSQL versión 16 (la última versión estable).

**¿Por qué `postgres:16`?** Es la imagen oficial de PostgreSQL en Docker Hub. Viene preinstalada.

---

### **2.1: Nombre del contenedor**

```yaml
    container_name: riesgo_psicosocial_postgres
```

**¿Qué hace?** Le da nombre al contenedor para identificarlo.

**Sin esto:**
```
docker ps
CONTAINER ID  NAMES
abc123...     docker_postgres_1  # Nombre automático (confuso)
```

**Con esto:**
```
docker ps
CONTAINER ID  NAMES
abc123...     riesgo_psicosocial_postgres  # Nombre claro
```

**¿Por qué importa?** Cuando ejecutas `docker exec -it riesgo_psicosocial_postgres ...`, usas este nombre.

---

### **2.2: Variables de entorno**

```yaml
    environment:
      POSTGRES_USER: erps_user
      POSTGRES_PASSWORD: "123456"
      POSTGRES_DB: riesgo_psicosocial
      TZ: America/Bogota
```

**¿Qué hace?** Configura PostgreSQL automáticamente cuando se inicia.

| Variable | Qué hace |
|----------|----------|
| `POSTGRES_USER: erps_user` | Crea un usuario llamado `erps_user` |
| `POSTGRES_PASSWORD: "123456"` | La contraseña es `123456` |
| `POSTGRES_DB: riesgo_psicosocial` | Crea una BD llamada `riesgo_psicosocial` |
| `TZ: America/Bogota` | Zona horaria para que los timestamps sean correctos |

**Sin esto tendrías que:**
```bash
docker exec ... psql -U postgres
CREATE USER erps_user WITH PASSWORD '123456';
CREATE DATABASE riesgo_psicosocial OWNER erps_user;
```

**Con esto:** ¡Automático! 🎉

---

### **2.3: Puertos**

```yaml
    ports:
      - "5432:5432"
```

**¿Qué significa?** `host:contenedor`

```
Tu máquina (host)    Contenedor
─────────────────────────────────
  5432      ←→         5432
            mapeo
```

**¿Por qué?** PostgreSQL dentro del contenedor corre en puerto 5432. Esto mapea ese puerto a tu máquina.

**Equivalencia en la vida real:**

```
Hotel (tu máquina) ←→ Habitación (contenedor)
Puerta externa: 5432 ←→ Puerta interna: 5432
```

Si quisieras acceder desde tu máquina:
```bash
psql -h localhost -p 5432 -U erps_user -d riesgo_psicosocial
```

---

### **2.4: Volúmenes (PERSISTENCIA)**

```yaml
    volumes:
      - postgres_data:/var/lib/postgresql/data
```

**¿Qué significa?** Mapear una carpeta de tu máquina a una carpeta en el contenedor.

```
Tu máquina                  Contenedor
─────────────────────────────────────────
postgres_data (volumen) ←→ /var/lib/postgresql/data
(datos reales aquí)         (PostgreSQL guarda acá)
```

**¿Por qué importa?**

Sin volumen:
```
1. Inicia PostgreSQL, creas datos
2. docker-compose down (paras el contenedor)
3. Reinicia: docker-compose up
4. ❌ PUFF - Todos los datos desaparecieron
```

Con volumen:
```
1. Inicia PostgreSQL, creas datos
2. docker-compose down (paras el contenedor)
3. Datos guardados en postgres_data (tu máquina)
4. Reinicia: docker-compose up
5. ✓ Los datos siguen ahí
```

---

### **2.5: Red**

```yaml
    networks:
      - riesgo_network
```

**¿Qué hace?** Pone PostgreSQL en una red llamada `riesgo_network`.

**¿Por qué?** Shiny está en la misma red. Así pueden comunicarse usando el nombre del servicio:

```
Shiny: "Hola, quiero conectar a `postgres`"
Docker: "Vale, busco `postgres` en la red riesgo_network"
Docker: "Encontrado en 172.21.0.2"
Shiny: "Conectado! ✓"
```

Sin la red:
```
Shiny: "Quiero conectar a postgres"
Docker: "¿Qué es eso? No existe"
❌ FALLA
```

---

### **2.6: Health Check**

```yaml
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U erps_user -d riesgo_psicosocial"]
      interval: 5s
      timeout: 5s
      retries: 5
```

**¿Qué hace?** Cada 5 segundos pregunta: "¿PostgreSQL está listo?"

| Parámetro | Significa |
|-----------|-----------|
| `test:` | El comando a ejecutar |
| `pg_isready -U erps_user...` | Pregunta si PostgreSQL acepta conexiones |
| `interval: 5s` | Pregunta cada 5 segundos |
| `timeout: 5s` | Espera máximo 5 segundos por respuesta |
| `retries: 5` | Si falla, reintenta 5 veces |

**¿Qué pasa?**

```
Tiempo 0s:  Docker: "¿Estás ready?" | PostgreSQL: "Iniciando..." | Status: unhealthy
Tiempo 5s:  Docker: "¿Estás ready?" | PostgreSQL: "Iniciando..." | Status: unhealthy
Tiempo 10s: Docker: "¿Estás ready?" | PostgreSQL: "Iniciando..." | Status: unhealthy
Tiempo 15s: Docker: "¿Estás ready?" | PostgreSQL: "Sí, listo!" | Status: healthy ✓
```

Cuando llega a "healthy", Shiny sabe que puede conectar.

---

## **PARTE 3: SHINY (SERVICIO 2)**

```yaml
  shiny:
    build:
      context: ..
      dockerfile: docker/Dockerfile
```

**¿Qué hace?** En lugar de descargar una imagen (como `postgres:16`), construye una propia.

| Campo | Significa |
|-------|-----------|
| `context: ..` | Busca el Dockerfile un nivel arriba (en `riesgo_psicosocial/`) |
| `dockerfile: docker/Dockerfile` | El archivo Dockerfile está en `docker/Dockerfile` |

**¿Por qué?** Porque Shiny es custom (tu app). No existe en Docker Hub.

---

### **3.1: Nombre del contenedor**

```yaml
    container_name: riesgo_psicosocial_shiny
```

Igual que PostgreSQL - nombre identificable.

---

### **3.2: Variables de entorno**

```yaml
    environment:
      PG_HOST: postgres
      PG_PORT: "5432"
      PG_DB: riesgo_psicosocial
      PG_USER: erps_user
      PG_PASSWORD: "123456"
      TZ: America/Bogota
```

**¿Qué hace?** Configura cómo Shiny se conecta a PostgreSQL.

| Variable | Qué es |
|----------|--------|
| `PG_HOST: postgres` | ← **IMPORTANTE**: es el nombre del SERVICIO, no `localhost` |
| `PG_PORT: "5432"` | Puerto de PostgreSQL |
| `PG_DB: riesgo_psicosocial` | Nombre de la BD |
| `PG_USER: erps_user` | Usuario (igual que en PostgreSQL) |
| `PG_PASSWORD: "123456"` | Contraseña (igual que en PostgreSQL) |

**¿Por qué `postgres` y no `localhost`?**

```
Dentro del contenedor Shiny:
- localhost = "esta máquina" (el contenedor Shiny)
- postgres = "el servicio postgres en la red riesgo_network"

Así que:
PG_HOST: postgres  ← Correcto, conecta a PostgreSQL
PG_HOST: localhost ← Incorrecto, intenta conectar a sí mismo
```

---

### **3.3: Puertos**

```yaml
    ports:
      - "7788:7788"
```

**¿Qué significa?**

```
Tu máquina    Contenedor Shiny
─────────────────────────────
  7788   ←→      7788
         mapeo
```

Así accedes a Shiny desde tu navegador:
```
http://localhost:7788
```

---

### **3.4: Volúmenes**

```yaml
    volumes:
      - ./logs:/app/logs
      - ../../shiny_resultados/.../marco.xlsx:/data/marco.xlsx
      - ../../Simulacion_respuestas_ODK.csv:/data/Simulacion_respuestas_ODK.csv
```

**¿Qué hace?**

| Host | Contenedor | Propósito |
|------|-----------|-----------|
| `./logs` | `/app/logs` | Guarda logs locales |
| `marco.xlsx` | `/data/marco.xlsx` | Acceso a archivo de datos |
| `Simulacion_respuestas_ODK.csv` | `/data/Simulacion_respuestas_ODK.csv` | Acceso a archivo de datos |

**¿Por qué?** El script `preparar_bd.R` necesita leer esos archivos. Los mapea para que Shiny pueda accederlos.

---

### **3.5: Red**

```yaml
    networks:
      - riesgo_network
```

**¿Qué hace?** Pone Shiny en la misma red que PostgreSQL.

Así pueden comunicarse:
```
Shiny: PG_HOST: postgres
Docker: Busco "postgres" en riesgo_network
Docker: Encontrado, aquí está su dirección IP
Shiny: ✓ Conectado
```

---

### **3.6: Depends On (DEPENDENCIA)**

```yaml
    depends_on:
      postgres:
        condition: service_healthy
```

**¿Qué significa?** "No inicies Shiny hasta que PostgreSQL sea `healthy`"

**Paso a paso:**

```
1. Docker inicia PostgreSQL
2. PostgreSQL ejecuta healthcheck
3. Healthcheck dice: "unhealthy" (aún iniciando)
4. Docker NO inicia Shiny (espera)
5. PostgreSQL sigue iniciando...
6. Healthcheck dice: "healthy" (listo)
7. Docker inicia Shiny
8. Shiny se conecta a PostgreSQL
9. ✓ TODO FUNCIONA
```

Sin esto:
```
1. Docker inicia PostgreSQL
2. Docker INMEDIATAMENTE inicia Shiny
3. Shiny intenta conectar a PostgreSQL
4. PostgreSQL aún se está iniciando...
5. ❌ ERROR: Connection refused
```

---

### **3.7: Restart Policy**

```yaml
    restart: unless-stopped
```

**¿Qué significa?** Si Shiny falla, reinicia automáticamente.

| Policy | Comportamiento |
|--------|-----------------|
| `no` | No reinicia |
| `always` | Siempre reinicia (incluso si lo paras) |
| `unless-stopped` | Reinicia PERO respeta si lo paras con `docker stop` |

**¿Por qué?** Si la app se cae, vuelve a iniciarse sola.

---

## **PARTE 4: VOLÚMENES (DEFINICIÓN)**

```yaml
volumes:
  postgres_data:
    driver: local
```

**¿Qué hace?** Define dónde se guardan físicamente los datos.

**¿Dónde están realmente?**

```
Windows:
C:\Users\<tu-usuario>\AppData\Docker\volumes\docker_postgres_data\_data

Linux:
/var/lib/docker/volumes/docker_postgres_data/_data
```

Docker lo maneja automáticamente. No tienes que tocarlo.

---

## **PARTE 5: REDES (DEFINICIÓN)**

```yaml
networks:
  riesgo_network:
    driver: bridge
```

**¿Qué hace?** Crea una red aislada donde se comunican PostgreSQL y Shiny.

**¿Por qué `bridge`?** Es el tipo de red estándar que conecta contenedores entre sí.

**Visualización:**

```
┌─────────────────────────────────────┐
│  riesgo_network (bridge)            │
│  ┌─────────────┐    ┌─────────────┐ │
│  │ postgres    │←──→│   shiny     │ │
│  │ 172.21.0.2  │    │ 172.21.0.3  │ │
│  └─────────────┘    └─────────────┘ │
└─────────────────────────────────────┘
     ↓
   Tu máquina
   localhost:5432 ← PostgreSQL
   localhost:7788 ← Shiny
```

---

## **RESUMEN: ORDEN DE EJECUCIÓN**

Cuando ejecutas `docker-compose up`:

```
1. Docker lee docker-compose.yml
   ↓
2. Define volumen postgres_data y red riesgo_network
   ↓
3. Inicia PostgreSQL
   │ ├─ Crea usuario erps_user
   │ ├─ Crea BD riesgo_psicosocial
   │ └─ Ejecuta healthcheck cada 5s
   ↓
4. Espera a que healthcheck diga "healthy"
   ↓
5. Inicia Shiny
   │ ├─ Construye imagen desde Dockerfile
   │ ├─ Lee variables de entorno
   │ └─ Ejecuta: shiny::runApp('/app', port=7788, host='0.0.0.0')
   ↓
6. Shiny se conecta a PostgreSQL usando PG_HOST: postgres
   ↓
7. ✓ LISTO - Accedes a http://localhost:7788
```

---

# 📚 Anexo: explicación del Dockerfile

> ℹ️ Esta explicación corresponde a una versión anterior del Dockerfile (basada en `r-base`). La versión actual parte de `rocker/tidyverse`, que ya trae tidyverse, readxl, stringr y las librerías del sistema, e instala aparte shiny, pool, scrypt, bslib, DBI, RPostgres, stringi, officer y flextable. Los conceptos (FROM, WORKDIR, RUN, COPY, EXPOSE, CMD) son los mismos.


---

## **LÍNEA 1-2: Base Image**

```dockerfile
# Usa la imagen oficial de R base y instala Shiny
FROM r-base:latest
```

**¿Qué significa?** `FROM` es el punto de partida. Descarga una imagen preexistente.

**¿Qué es `r-base:latest`?**

```
r-base:latest
├─ r-base = Imagen oficial de R de Docker Hub
└─ latest = Última versión disponible
```

**¿Qué tiene adentro `r-base:latest`?**

```
Sistema operativo
    ↓
Linux (Ubuntu)
    ↓
R instalado y listo para usar
    ↓
Compiladores y herramientas
```

**Alternativas que podría usar:**

```dockerfile
FROM rocker/r-shiny:latest    # R + Shiny preinstalado (más pesado)
FROM r-base:4.3.2             # R versión específica (más ligero)
FROM ubuntu:22.04             # Ubuntu puro (tendría que instalar R)
```

**¿Por qué `r-base:latest`?**

```
✓ Ligero (menos datos que descargar)
✓ Tiene R listo
✓ Fácil instalar dependencias
```

**Equivalencia en la vida real:**

```
Sin FROM:
"Construye una computadora desde cero"

Con FROM r-base:latest:
"Toma una computadora que ya tiene R instalado, personalízala"
```

---

## **LÍNEA 4-5: Directorio de trabajo**

```dockerfile
# Establece el directorio de trabajo
WORKDIR /app
```

**¿Qué hace?** Define dónde estamos trabajando dentro del contenedor.

**Sin esto, sería:**

```
Contenedor
├─ / (raíz)
├─ /bin (programas)
├─ /home (usuarios)
└─ ... (confuso dónde copiar archivos)
```

**Con `WORKDIR /app`:**

```
Contenedor
├─ / (raíz)
├─ /app  ← Aquí es nuestro "hogar"
│   ├─ app.R
│   ├─ scripts/
│   └─ R/
└─ ... (resto del sistema)
```

**¿Por qué `/app`?** Es la convención en Docker. Cualquier comando posterior usa esta carpeta como base.

**Equivalencia:**

```bash
# Sin WORKDIR:
cd / && cd app

# Con WORKDIR /app:
# Ya estamos en /app automáticamente
```

---

## **LÍNEA 8-17: Instalar dependencias del sistema**

```dockerfile
# Instala dependencias del sistema necesarias para compilar librerías de R
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libpq-dev \
    libfontconfig1-dev \
    libuv1-dev \
    libfreetype6-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*
```

**¿Qué hace?** Instala librerías del sistema operativo (no de R).

**¿Por qué necesita esto?**

Cuando R compila paquetes como `tidyverse`, `RPostgres`, necesita:

```
R package (código R)
    ↓
Necesita compilar a código C/C++
    ↓
Necesita librerías del sistema
    ↓
Por ejemplo: libssl, libxml, etc.
```

**Desglose del comando:**

```dockerfile
RUN apt-get update
```
Actualiza la lista de paquetes disponibles (como `apt update` en Linux).

```dockerfile
&& apt-get install -y \
```
Instala paquetes. `-y` = "Yes, instala sin preguntar"

```dockerfile
libcurl4-openssl-dev
```
Librería para HTTPS/conexiones web

```dockerfile
libssl-dev
```
Librería de criptografía (SSL/TLS)

```dockerfile
libxml2-dev
```
Librería para parsear XML (usado por tidyverse)

```dockerfile
libpq-dev
```
**IMPORTANTE**: Librería de PostgreSQL (para conectar a BD)

```dockerfile
libfontconfig1-dev
libfreetype6-dev
```
Librerías para gráficos y fuentes

```dockerfile
pkg-config
```
Herramienta para encontrar librerías instaladas

```dockerfile
&& rm -rf /var/lib/apt/lists/*
```
**IMPORTANTE**: Limpia archivos de instalación para reducir tamaño de imagen.

**¿Por qué limpiar?**

```
Sin limpiar:
Imagen = 800 MB (con descargas cacheadas)

Limpiando:
Imagen = 600 MB (sin cachés innecesarios)
```

**Equivalencia en la vida real:**

```
Comprar herramientas (apt-get install)
├─ Destornillador
├─ Martillo
├─ Sierras
└─ Descargas cajas vacías (basura)

Limpiar basura (rm -rf):
└─ Tiras las cajas vacías para ahorrar espacio
```

---

## **LÍNEA 20: Instalar Shiny**

```dockerfile
RUN R --slave -e 'install.packages("shiny", repos="https://cloud.r-project.org")'
```

**¿Qué hace?** Instala el paquete R `shiny`.

**Desglose:**

```dockerfile
RUN
```
Ejecuta un comando en el contenedor

```dockerfile
R --slave
```
Inicia R en modo "sin interacción" (sin mostrar prompt)

```dockerfile
-e 'comando R'
```
Ejecuta el comando R y salir

```dockerfile
install.packages("shiny", repos="https://cloud.r-project.org")
```
Descarga e instala Shiny desde CRAN

**¿Por qué `--slave`?**

```dockerfile
R --slave -e 'install.packages("shiny")'
# "Instala shiny y luego cierra R"

# Sin --slave:
# R abre interactivamente esperando que escribas comandos
```

**¿Por qué `repos="https://cloud.r-project.org"`?**

```
Especifica dónde descargar los paquetes
(hay muchos CRAN mirrors, este es rápido)
```

**¿Por qué Shiny primero (línea 20)?**

```
Porque Shiny es LO MÁS IMPORTANTE
Si falla, no tiene sentido instalar lo demás
(estrategia de fallos temprana)
```

---

## **LÍNEA 24-38: Instalar paquetes R**

```dockerfile
RUN R --slave -e '\
    install.packages(c(\
        "bslib",\
        "DBI",\
        "RPostgres",\
        "pool",\
        "scrypt",\
        "stringi",\
        "dplyr",\
        "magrittr",\
        "tidyverse",\
        "readxl",\
        "stringr"\
    ), repos="https://cloud.r-project.org")\
    '
```

**¿Qué hace?** Instala múltiples paquetes R.

**¿Por qué está separado de Shiny?**

```
Línea 20: Shiny solo (crítico, si falla paras)
Línea 24: Otros paquetes (secundarios)

Si falla Shiny: paras todo
Si falla tidyverse: puedes debuggear sin reconstruir desde cero
```

**¿Qué es la `\` al final?**

```dockerfile
install.packages(c(\
    "bslib",\
    "DBI",\
    ...
))\
```

La `\` al final de la línea = "continúa en la siguiente línea"

**Sin `\`:**

```dockerfile
RUN R --slave -e 'install.packages(c("bslib", "DBI", "RPostgres", "pool", "scrypt", "stringi", "dplyr", "magrittr", "tidyverse", "readxl", "stringr"), repos="https://cloud.r-project.org")'
```

Es una sola línea larga (difícil de leer). Con `\` es más legible.

**¿Qué paquete para qué?**

| Paquete | Función |
|---------|---------|
| `bslib` | Tema Bootstrap para Shiny (interfaz bonita) |
| `DBI` | Interfaz genérica de BD |
| `RPostgres` | **CRÍTICO**: Conectar a PostgreSQL |
| `pool` | Gestionar conexiones a BD |
| `scrypt` | Encriptar contraseñas |
| `stringi` | Manipular strings |
| `dplyr` | Manipular datos (tidyverse) |
| `magrittr` | Pipes `%>%` |
| `tidyverse` | **IMPORTANTE**: Suite completa de análisis |
| `readxl` | Leer archivos Excel |
| `stringr` | Strings avanzado |

---

## **LÍNEA 41-43: Copiar aplicación Shiny**

```dockerfile
# Copia tu aplicación Shiny a la carpeta /app
# La ruta relativa es desde el contexto de build (la carpeta docker/)
# Así que .. sube un nivel hasta riesgo_psicosocial
COPY ../shiny_resultados/Shiny_seguimiento_nuevo/Shiny_seguimiento /app
```

**¿Qué hace?** Copia todos tus archivos Shiny al contenedor.

**¿De dónde a dónde?**

```
Tu máquina (contexto de build = docker/)
│
├─ .. (sube un nivel a riesgo_psicosocial/)
│
└─ shiny_resultados/
    └─ Shiny_seguimiento_nuevo/
        └─ Shiny_seguimiento/
            ├─ app.R
            ├─ conectar_bd.R
            ├─ R/
            └─ ... (todos tus archivos)
                        ↓
                      COPIAR
                        ↓
Contenedor
└─ /app/
    ├─ app.R
    ├─ conectar_bd.R
    ├─ R/
    └─ ... (idéntico)
```

**¿Por qué `..` y no ruta completa?**

```dockerfile
# Así NO funciona:
COPY C:\Users\ENDS\Desktop\riesgo_psicosocial\shiny_resultados\... /app

# Así SÍ funciona:
COPY ../shiny_resultados/Shiny_seguimiento_nuevo/Shiny_seguimiento /app

# Porque el contexto de build es docker-compose.yml
# (context: ..)
```

**Contexto de build:**

```yaml
# En docker-compose.yml:
build:
  context: ..  ← Punto de referencia: carpeta riesgo_psicosocial
  dockerfile: docker/Dockerfile
```

Así que `..` = una carpeta arriba de `docker/` = `riesgo_psicosocial/`

---

## **LÍNEA 46: Exponer puerto**

```dockerfile
EXPOSE 7788
```

**¿Qué hace?** Dice "este contenedor escucha en puerto 7788"

**¿Solo "dice"?** Sí, es documentación. No mapea automáticamente.

```dockerfile
EXPOSE 7788
# Solo documenta que puerto usa
```

**El mapeo real ocurre en docker-compose.yml:**

```yaml
ports:
  - "7788:7788"  ← Aquí sí se mapea
```

**¿Por qué ambos?**

```
EXPOSE = "Hola, este app usa puerto 7788 internamente"
ports:  = "Conecta mi puerto 7788 con tu puerto 7788"
```

---

## **LÍNEA 50: Comando de inicio**

```dockerfile
CMD ["R", "--slave", "-e", "shiny::runApp('/app', port = 7788, host = '0.0.0.0')"]
```

**¿Qué hace?** Cuando el contenedor inicia, ejecuta este comando.

**Desglose:**

```dockerfile
CMD
```
Comando por defecto al iniciar el contenedor

```dockerfile
["R", "--slave", "-e", "..."]
```
Ejecuta R en modo no-interactivo

```dockerfile
"shiny::runApp('/app', port = 7788, host = '0.0.0.0')"
```
Inicia la app Shiny

**¿Qué es `host = '0.0.0.0'`?**

```
0.0.0.0 = "Escucha en TODAS las interfaces de red"

Sin 0.0.0.0 (127.0.0.1):
└─ Solo accesible desde localhost
   (desde dentro del contenedor)

Con 0.0.0.0:
└─ Accesible desde cualquier lugar
   (desde tu máquina, desde internet, etc.)
```

**Equivalencia:**

```bash
# Sin 0.0.0.0:
shiny::runApp(port = 7788, host = '127.0.0.1')
# Solo tú (desde tu máquina) puedes acceder

# Con 0.0.0.0:
shiny::runApp(port = 7788, host = '0.0.0.0')
# Tú + Docker + ngrok + cualquiera puede acceder
```

---

## **RESUMEN: Flujo completo del Dockerfile**

```
1. FROM r-base:latest
   └─ Descarga imagen base con R

2. WORKDIR /app
   └─ Define directorio de trabajo

3. RUN apt-get install [librerías]
   └─ Instala dependencias del sistema

4. RUN R install.packages("shiny")
   └─ Instala Shiny (crítico)

5. RUN R install.packages([lista])
   └─ Instala paquetes R necesarios

6. COPY ../shiny_resultados/.../Shiny_seguimiento /app
   └─ Copia tu app completa

7. EXPOSE 7788
   └─ Documenta puerto

8. CMD ["R", "--slave", "-e", "shiny::runApp(...)"]
   └─ Inicia la app al arrancar el contenedor
```

**Resultado final:**

```
Contenedor listo
├─ Sistema Linux
├─ R instalado
├─ Shiny instalado
├─ Paquetes R instalados
├─ Tu app en /app
└─ Listo para ejecutarse
```

---

## **ANALOGÍA: Construcción de una casa**

```
FROM r-base:latest
└─ Compra un lote con una casa sin terminar

RUN apt-get install [librerías]
└─ Instala electricidad, agua, gas

RUN R install.packages(...)
└─ Amuebla la casa

COPY ... /app
└─ Traes tus cosas personales

EXPOSE 7788
└─ Cuelgas un letrero "Puerta por el puerto 7788"

CMD [...]
└─ Al llegar, automáticamente enciende las luces
```

---


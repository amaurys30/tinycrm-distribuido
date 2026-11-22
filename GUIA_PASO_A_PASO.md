# Guía paso a paso: TinyCRM distribuido en 2 portátiles Windows

Esta guía levanta **un servicio a la vez**, en el orden en que se necesitan. En cada paso se explica qué es el servicio, se da el comando y se muestra cómo comprobar que funciona antes de seguir. Si un paso falla, no avancen: revisen los logs (`docker logs <contenedor>`) o la sección de problemas al final.

- **Portátil 1 = Máquina 1.** DNS, firewall, red DMZ y red interna: los 18 servidores.
- **Portátil 2 = Máquina 2.** Red externa: los actores (usuarios del Cliente A y del Cliente B).

Todos los comandos son para **PowerShell**, salvo algunos de la Fase 14, que usan **Git Bash**.

---

## Así queda montado

```
 PORTÁTIL 2 (Máquina 2)                         PORTÁTIL 1 (Máquina 1)
 red_externa 192.168.0.0/24                     red_externa      red_dmz 192.168.1.0/24          red_interna 192.168.2.0/24
 ┌──────────────────────────┐                   ┌──────────────────────────────────────────────────────────────────────────┐
 │ actor-cliente-a .0.10    │ ─ puerto 53 (DNS) ►│ dns+firewall ──► middleware .1.5 ──► lb-cliente-a .1.6 ──► tinycrm-a1/a2/a3 ─► lb-bd .2.1 ──► pxc1 │
 │ actor-cliente-b .0.11    │ ─ puerto 80 (web) ►│ .0.1/.1.1        │            ──► lb-cliente-b .1.7 ──► tinycrm-b1/b2/b3        .2.1  pxc2 │
 │ actor-cli       .0.20    │                   │                  ▼                                       │                pxc3 │
 │                          │   (WiFi/hotspot)  │          usuarios-db .1.9 ◄── consumer .1.10 ◄── broker .1.8/.2.8 ◄──────┘      │
 └──────────────────────────┘                   └──────────────────────────────────────────────────────────────────────────┘
```

**¿Por qué los portátiles se unen por los puertos 53 y 80?** Docker Desktop en Windows no puede extender una red de contenedores entre dos computadores. Por eso cada portátil tiene sus propias redes, y la red externa se conecta con el portátil 1 a través de la red física (WiFi o hotspot). Desde el portátil 2 solo se ve la IP del portátil 1 y dos puertos:
- el **53**, del DNS, que traduce `www.tiny.com` a la IP del portátil 1;
- el **80**, del firewall, que recibe la aplicación.

Así funciona también en la vida real: el usuario de Internet solo ve la IP pública del DNS y del firewall. Como en el diagrama, **el DNS y el firewall comparten la IP 192.168.0.1**: el contenedor `dns` usa la misma red que el contenedor `firewall`.

---

# PREPARACIÓN (en los DOS portátiles)

## Fase 0. Antes de empezar

### 0.1 Conectar los dos portátiles a la misma red

1. **Lo más recomendable es el hotspot de un celular**, con los dos portátiles conectados a él. El WiFi de la universidad suele bloquear el tráfico entre equipos ("aislamiento de clientes").
2. En cada portátil, abran PowerShell y ejecuten:
   ```powershell
   ipconfig
   ```
   Anoten la **Dirección IPv4** del adaptador **Wi-Fi**. En esta guía se llaman `IP_M1` (portátil 1) e `IP_M2` (portátil 2).
3. ⚠️ **La IP NO puede empezar por `192.168.0.`, `192.168.1.` ni `192.168.2.`**, porque son las redes del proyecto y chocarían. Un hotspot Android suele dar `192.168.43.x` o `10.x`, y un iPhone `172.20.10.x`, así que sirven. Si les sale una de las prohibidas, cambien de red.
4. Marquen la red WiFi como **Privada**: *Configuración → Red e Internet → Wi-Fi → (la red) → Tipo de perfil de red: Privada*.

### 0.2 Darle memoria a Docker (solo el portátil 1)

Docker Desktop usa por defecto solo la mitad de la RAM. Con 16 GB conviene darle unos 12 GB:

```powershell
notepad $env:USERPROFILE\.wslconfig
```

Peguen esto, guarden y cierren:

```
[wsl2]
memory=12GB
processors=6
```

Luego ejecuten `wsl --shutdown` y abran Docker Desktop de nuevo.

### 0.3 Obtener el proyecto

- **Desde GitHub:** `git clone https://github.com/<usuario>/<repositorio>.git C:\sd\tinycrm-distribuido`. Si es desde el .zip, descomprímanlo en esa misma ruta. Usen una ruta corta y sin espacios, y **eviten el Escritorio y OneDrive**.
- El repositorio **no trae** los archivos `.env` ni los certificados, porque son secretos. Se crean en la Fase 1 (portátil 1) y en la Fase 11 (portátil 2).
- **No abran los `.sh` con el Bloc de notas**: cambia los finales de línea y los scripts dejan de funcionar dentro de Linux. Si necesitan editar algo, usen VS Code con "LF" seleccionado abajo a la derecha.
- Para la Fase 14 instalen **Git for Windows**, que trae *Git Bash*: https://git-scm.com/download/win

```powershell
cd C:\sd\tinycrm-distribuido
docker version          # debe mostrar "Server: Docker Desktop"
```

---

# PORTÁTIL 1: MÁQUINA 1 (DMZ y red interna)

## Fase 1. Las redes y la herramienta de pruebas

**Qué es:** el diagrama tiene tres redes. Aquí se crean como redes de Docker con las mismas subredes. La red interna lleva `--internal`, es decir, **sin salida a Internet**, como en el diagrama. El gateway de Docker se pone en la `.254` para que la `.1` quede libre para el firewall y el LB BD.

```powershell
cd C:\sd\tinycrm-distribuido

docker network create --subnet 192.168.0.0/24 --ip-range 192.168.0.128/25 --gateway 192.168.0.254 red_externa
docker network create --subnet 192.168.1.0/24 --ip-range 192.168.1.128/25 --gateway 192.168.1.254 red_dmz
docker network create --subnet 192.168.2.0/24 --ip-range 192.168.2.128/25 --gateway 192.168.2.254 --internal red_interna

docker network ls
```

**Herramienta de pruebas.** Es un contenedor pequeño con `curl`, que se conecta temporalmente a una red para probar los servicios "desde adentro":

```powershell
docker build -t tiny-cliente:1.0 .\cliente
```

✅ **Verificación:** `docker network ls` muestra `red_externa`, `red_dmz` y `red_interna`.

De aquí en adelante, todos los comandos `docker compose` del portátil 1 se ejecutan dentro de la carpeta `maquina1`:

```powershell
cd C:\sd\tinycrm-distribuido\maquina1
Copy-Item .env.example .env      # solo si no existe (clonado desde GitHub)
notepad .env
```

**Certificados HTTPS** (solo si la carpeta `certificados` no tiene `tiny.crt`, por ejemplo al clonar desde GitHub). Desde la raíz del proyecto:
```powershell
cd C:\sd\tinycrm-distribuido
powershell -ExecutionPolicy Bypass -File .\certificados\generar-certificados.ps1
cd maquina1
```
Luego **copien la carpeta `certificados` completa al portátil 2**.

En `.env`:
- **Escriban `IP_MAQUINA1=<IP_M1>`**, la IP del WiFi de ESTE portátil (Fase 0.1). El DNS responde `www.tiny.com` con esa IP.
- **(Opcional)** cambien las contraseñas **ahora**, antes de crear las bases de datos.

Los comandos de esta guía usan claves de ejemplo (`RootCluster2026`, `ClienteA_2026`, `RootUsuarios2026`...). **Reemplácenlas por las que tengan en su `.env`.** Los scripts de `scripts/` leen las claves del `.env` automáticamente.

---

## Fase 2. Cluster DB: 3 nodos de Percona XtraDB Cluster (192.168.2.10, .11, .12)

**Qué es:** un clúster de MySQL con **replicación síncrona** (Galera). Cada escritura se confirma en los tres nodos a la vez, así que todos tienen siempre los mismos datos. Si uno cae, los otros siguen.

**Cómo nace un clúster:**
- **pxc1** se inicia primero y *crea* el clúster (*bootstrap*). Además ejecuta `cluster-bd/init/01-clientes.sh`, que crea **una base de datos y un usuario por cliente**: `tinycrm_cliente_a` con `tinycrm_a`, y `tinycrm_cliente_b` con `tinycrm_b`.
- **pxc2** y **pxc3** se *unen* y reciben una copia completa de los datos (SST).
- El script `cluster-bd/pxc-arranque.sh` decide si cada nodo crea el clúster o se une a uno existente.

### 2.1 pxc1

```powershell
docker compose up -d pxc1
docker logs -f pxc1        # Ctrl+C para salir del log
```

Esperen hasta que en `docker ps` aparezca **`(healthy)`**. Puede tardar 1-3 minutos.

```powershell
docker ps --format "table {{.Names}}\t{{.Status}}"
docker exec pxc1 mysql -uroot -pRootCluster2026 -e "SHOW STATUS LIKE 'wsrep_cluster_size'; SHOW DATABASES;"
```

✅ `wsrep_cluster_size = 1`, y aparecen `tinycrm_cliente_a` y `tinycrm_cliente_b`.

### 2.2 pxc2

```powershell
docker compose up -d pxc2
docker logs -f pxc2        # verán "UNIENDOSE al cluster" y luego la transferencia SST ("Joiner ... Synced")
```

Cuando pxc2 esté `(healthy)`:

```powershell
docker exec pxc1 mysql -uroot -pRootCluster2026 -e "SHOW STATUS LIKE 'wsrep_cluster_size'"
```

✅ El tamaño es 2.

### 2.3 pxc3

```powershell
docker compose up -d pxc3
```

Cuando esté `(healthy)`, el tamaño debe ser **3**.

### 2.4 Probar la replicación

Se escribe en pxc1 y se lee en pxc3:

```powershell
docker exec pxc1 mysql -uroot -pRootCluster2026 -e "CREATE DATABASE prueba; CREATE TABLE prueba.t(id INT PRIMARY KEY, txt VARCHAR(30)); INSERT INTO prueba.t VALUES (1,'hola desde pxc1');"
docker exec pxc3 mysql -uroot -pRootCluster2026 -e "SELECT * FROM prueba.t"
docker exec pxc1 mysql -uroot -pRootCluster2026 -e "DROP DATABASE prueba"
```

✅ pxc3 devuelve `hola desde pxc1`.

---

## Fase 3. Load Balancer BD (192.168.2.1)

**Qué es:** un HAProxy en modo TCP. Las aplicaciones nunca se conectan a un nodo concreto, sino a `192.168.2.1:3306`. HAProxy revisa cada 2 segundos si cada nodo está vivo (`mysql-check`). Envía todo a **pxc1** y deja **pxc2 y pxc3 de respaldo**: si pxc1 cae, pasa a pxc2 al instante. Se usa un solo nodo escritor porque es el patrón recomendado para Galera, ya que evita conflictos de escritura simultánea. Configuración: `balanceadores/lb-bd.cfg`.

```powershell
docker compose up -d lb-bd
docker logs lb-bd
```

**Prueba.** Un cliente MySQL temporal entra a la red interna y se conecta **a través del LB** con el usuario del Cliente A:

```powershell
docker run --rm --network red_interna mysql:8.0 mysql -h 192.168.2.1 -utinycrm_a -pClienteA_2026 -e "SELECT @@hostname AS nodo_que_responde; SHOW DATABASES;"
```

✅ Responde **pxc1**, y `tinycrm_a` **solo ve `tinycrm_cliente_a`**. Ese es el aislamiento de datos entre clientes.

**Prueba de conmutación por falla (opcional, pero muy buena para entender):**

```powershell
docker stop pxc1
docker run --rm --network red_interna mysql:8.0 mysql -h 192.168.2.1 -utinycrm_a -pClienteA_2026 -e "SELECT @@hostname"
docker start pxc1
```

✅ Mientras pxc1 está apagado responde **pxc2**. Al encenderlo, pxc1 se vuelve a unir solo (en su log aparece "UNIENDOSE"). Esperen a que vuelva a estar `(healthy)` antes de seguir.

---

## Fase 4. Broker de mensajería: RabbitMQ (192.168.1.8 y 192.168.2.8)

**Qué es:** una cola de mensajes. Cuando TinyCRM crea un usuario, **publica un evento** y sigue trabajando sin esperar a nadie. Eso es comunicación asíncrona. El broker guarda el evento hasta que alguien lo consuma. Está en las dos redes porque las aplicaciones (red interna) publican y el Consumer (DMZ) lee.

```powershell
docker compose up -d broker
```

✅ Cuando esté `(healthy)`, abran **http://localhost:15672** (usuario `tinycrm`, clave `Broker_2026`). Por ahora no hay colas.

---

## Fase 5. BD Usuarios (192.168.1.9)

**Qué es:** la base de datos central del diagrama ("Usuarios"). Guarda **qué usuario pertenece a qué cliente**. El Middleware la consulta en cada login. Tiene dos tablas: `usuarios` y `eventos_recibidos` (auditoría). Esquema: `usuarios-db/01-esquema.sql`.

```powershell
docker compose up -d usuarios-db
```

Cuando esté `(healthy)`:

```powershell
docker exec usuarios-db mysql -uroot -pRootUsuarios2026 usuarios -e "SHOW TABLES; SELECT * FROM usuarios;"
```

✅ Aparecen las dos tablas, por ahora vacías.

---

## Fase 6. Consumer (192.168.1.10)

**Qué es:** un programa en Python (`consumer/consumer.py`) que escucha la cola `usuarios.sincronizacion`. Por cada evento `USUARIO_CREADO` guarda o actualiza el usuario en la BD Usuarios. Confirma el mensaje (*ACK*) **solo después de guardarlo**. Si la BD falla, el mensaje vuelve a la cola y no se pierde.

```powershell
docker compose up -d --build consumer
docker logs -f consumer
```

✅ El log dice `Escuchando cola 'usuarios.sincronizacion'`. En http://localhost:15672, en la pestaña **Queues**, aparece la cola `usuarios.sincronizacion` con **1 consumer**.

---

## Fase 7. Clúster de aplicación TinyCRM (A: .1.3, .1.13 y .1.23 · B: .1.4, .1.14 y .1.24)

**Qué es:** cada instancia es un contenedor con TinyCRM completo: la interfaz Vue y la API Spring Boot. Hay **3 instancias por cliente**, como indicó el docente. La **misma imagen** se usa 6 veces y solo cambian las variables de entorno:
- `TENANT_ID=A` o `B`
- la base de datos y el usuario de BD de su cliente
- `INSTANCIA=tinycrm-a1`, etc.

Cada instancia está en dos redes: en la DMZ para recibir tráfico de su LB, y en la red interna para hablar con la BD y el broker.

**Qué se le cambió a TinyCRM y por qué:**
- **Sesiones en la BD (Spring Session JDBC):** si una instancia cae, la otra conoce la sesión del usuario. Esto es lo que da la tolerancia a fallos.
- **`/actuator/health`:** permite que el LB sepa si la instancia está viva.
- **Eventos:** al crear un usuario, publica `USUARIO_CREADO` en RabbitMQ después de guardarlo. Además, al arrancar vuelve a publicar todos sus usuarios (resincronización).
- **Usuarios iniciales por cliente:** `admin_a`, `support_a`, `admin_b` y `support_b`.

### 7.1 Construir la imagen

La primera vez tarda **10-15 minutos**, porque descarga las dependencias de npm y Gradle:

```powershell
docker compose build tinycrm-a1
```

### 7.2 Primera instancia del Cliente A

```powershell
docker compose up -d tinycrm-a1
docker logs -f tinycrm-a1
```

En el log deben aparecer:
- `Default admin user created successfully` y `Username: admin_a`, es decir, el usuario quedó creado en el clúster de BD.
- `[EVENTO] Publicado USUARIO_CREADO usuario=admin_a tenant=A`, es decir, el evento se envió al broker.

Ahora miren la cadena completa (broker → consumer → BD Usuarios):

```powershell
docker logs consumer
docker exec usuarios-db mysql -uroot -pRootUsuarios2026 usuarios -e "SELECT username, email, tenant FROM usuarios;"
```

✅ `admin_a` y `support_a` aparecen con `tenant = A`. **Esa es la sincronización de usuarios de la rúbrica.**

**Prueba directa contra la instancia.** Se inicia sesión y se pide la información del sistema:

```powershell
docker run --rm --network red_dmz -e BASE=http://192.168.1.3:8080 tiny-cliente:1.0 bash -c '. /pruebas/comun.sh; login admin_a admin123 /tmp/c; echo; info /tmp/c | jq .'
```

✅ Responde `"tenant": "A"`, `"instancia": "tinycrm-a1"` y `"nodoBD": "pxc1"`.

### 7.3 El resto de instancias

`a2` y `a3` esperan a que `a1` esté sana, para que no creen las tablas al mismo tiempo:

```powershell
docker compose up -d tinycrm-a2 tinycrm-a3
docker compose up -d tinycrm-b1
docker compose up -d tinycrm-b2 tinycrm-b3
docker ps --format "table {{.Names}}\t{{.Status}}"
```

✅ Las seis quedan `(healthy)`, y la BD Usuarios ya tiene también `admin_b` y `support_b` con `tenant = B`.

---

## Fase 8. Load Balancer Cliente A (192.168.1.6) y Cliente B (192.168.1.7)

**Qué es:** un HAProxy **por cliente**. Reparte las peticiones entre las tres instancias de su cliente (*round-robin*) y cada 3 segundos les pregunta `/actuator/health`. Si una no responde, la saca del reparto. Añade la cabecera `X-Servidor` para que se vea qué instancia atendió. Configuración: `balanceadores/lb-cliente-a.cfg` y `lb-cliente-b.cfg`.

```powershell
docker compose up -d lb-cliente-a lb-cliente-b
```

**Paneles de estadísticas:**
- LB Cliente A: **http://localhost:8404**
- LB Cliente B: **http://localhost:8405**

En verde deben verse `tinycrm-a1`, `tinycrm-a2` y `tinycrm-a3` (o `b1`, `b2` y `b3`).

**Prueba de reparto.** Se hacen 12 peticiones al LB A:

```powershell
docker run --rm --network red_dmz -e BASE=http://192.168.1.6:8080 tiny-cliente:1.0 /pruebas/2-balanceo.sh admin_a admin123 12
```

✅ Aproximadamente un tercio para cada una (`tinycrm-a1`, `tinycrm-a2` y `tinycrm-a3`), **con la misma sesión**.

---

## Fase 9. Middleware (192.168.1.5)

**Qué es:** el cerebro del enrutamiento (`middleware/app.py`). Funciona así:
1. Cuando alguien hace **login**, busca el usuario en la BD Usuarios para saber si es del Cliente A o del B.
2. Envía el login **solo al LB de ese cliente**.
3. Si el login sale bien, le entrega una cookie `TINY_CLIENTE` **firmada (HMAC)**. Así, las siguientes peticiones van siempre a su cliente, y nadie puede cambiar la cookie para saltar al otro cliente.
4. Un usuario sin sesión no puede usar la API.

```powershell
docker compose up -d --build middleware
docker logs -f middleware
```

**Prueba.** Al mismo middleware entran un usuario de A y uno de B:

```powershell
docker run --rm --network red_dmz -e BASE=http://192.168.1.5:8080 tiny-cliente:1.0 bash -c '. /pruebas/comun.sh; login admin_a admin123 /tmp/a; echo; info /tmp/a | jq -c .; login admin_b admin123 /tmp/b; echo; info /tmp/b | jq -c .; login fulano x /tmp/x'
```

✅ `admin_a` cae en `tenant A` (tinycrm-a1, a2 o a3), `admin_b` en `tenant B` (b1, b2 o b3) y `fulano` es rechazado con "Usuario no registrado en ningun cliente". El log del middleware muestra cada decisión: `LOGIN 'admin_b' identificado como cliente B`.

---

## Fase 10. Firewall y DNS (192.168.0.1 · 192.168.1.1, publicados en los puertos 80, 443 y 53 del portátil)

**Qué es:** un nginx que es el **único** servicio conectado al exterior. Sus reglas (`firewall/nginx.conf`):
1. Solo acepta el nombre `www.tiny.com`. Si se entra por IP o con otro nombre, corta la conexión.
2. Solo acepta los métodos HTTP normales.
3. Bloquea `/actuator`.
4. Limita la cantidad de peticiones por IP.

**HTTPS (puerto 443):** el firewall atiende `http://` (80) y `https://` (443). Para HTTPS usa el certificado de `www.tiny.com` que está en la carpeta `certificados/`, firmado por la autoridad certificadora del proyecto ("Tiny CA"). El firewall **descifra** el HTTPS y reenvía la petición a la DMZ por HTTP (*terminación TLS*). Los navegadores de los actores confían en la Tiny CA, así que no muestran alertas.

Todo lo demás lo entrega al Middleware. Además, como es el único contenedor en la red externa y en la DMZ, **nada más es alcanzable desde afuera**.

**El DNS:** es un dnsmasq que corre en el contenedor `dns`, pero **dentro de la red del firewall** (`network_mode: service:firewall`). Por eso los dos tienen la IP 192.168.0.1, como en el diagrama. Cuando alguien pregunta por `www.tiny.com`, responde con la **IP del portátil 1** (`IP_MAQUINA1` del `.env`). Cualquier otro nombre (google.com, etc.) lo reenvía a Internet. Como comparten red, el puerto 53 del DNS se publica en el servicio `firewall`.

```powershell
docker compose up -d --build firewall dns
```

**Probar el DNS desde el mismo portátil 1:**

```powershell
nslookup www.tiny.com 127.0.0.1
docker logs dns
```

✅ Responde con la IP del portátil 1 (`IP_MAQUINA1`), y en el log de `dns` aparece la consulta (`query[A] www.tiny.com`).

**Probar el firewall desde el mismo portátil 1.** Se usa `curl.exe`, no `curl`, que en PowerShell es otro comando:

```powershell
curl.exe -s -o NUL -w "%{http_code}`n" -H "Host: www.tiny.com" http://localhost/
curl.exe -s -H "Host: www.tiny.com" http://localhost/actuator/health
curl.exe -v http://localhost/
curl.exe -s -o NUL -w "%{http_code}`n" -k --resolve www.tiny.com:443:127.0.0.1 https://www.tiny.com/
```

✅ Los resultados esperados son, en orden:
1. `200`: la página de TinyCRM.
2. `403`: bloqueado.
3. `Empty reply from server`: el firewall descartó la petición porque no venía para www.tiny.com.
4. `200` por **HTTPS**. El `curl.exe` de Windows no acepta `--cacert`, por eso se usa `-k` (no valida el certificado). La validación real con la Tiny CA la hace el actor-cli del portátil 2 (`1-enrutamiento.sh`, paso 3).

### 10.1 Abrir los puertos 80, 443 y 53 en el Firewall de Windows

Abran **PowerShell como Administrador** (clic derecho → "Ejecutar como administrador"):

```powershell
New-NetFirewallRule -DisplayName "TinyCRM-SD-TCP" -Direction Inbound -Protocol TCP -LocalPort 53,80,443,8404,8405,15672 -Action Allow -Profile Any
New-NetFirewallRule -DisplayName "TinyCRM-SD-DNS" -Direction Inbound -Protocol UDP -LocalPort 53 -Action Allow -Profile Any
```

### 10.2 Estado final del portátil 1

```powershell
docker compose ps
```

✅ Los 18 contenedores están `Up`: pxc1-3, lb-bd, broker, usuarios-db, consumer, tinycrm-a1, a2, a3, b1, b2 y b3, lb-cliente-a, lb-cliente-b, middleware, firewall y dns.

---

# PORTÁTIL 2: MÁQUINA 2 (red externa)

## Fase 11. Preparar el portátil 2

```powershell
cd C:\sd\tinycrm-distribuido

# 1) ¿Me responde el DNS del portátil 1?  (cambien IP_M1 por la IP real)
nslookup www.tiny.com IP_M1

# 2) ¿Llego al firewall del portátil 1? (HTTP y HTTPS)
Test-NetConnection IP_M1 -Port 80
Test-NetConnection IP_M1 -Port 443
curl.exe -s -o NUL -w "%{http_code}`n" -H "Host: www.tiny.com" http://IP_M1/
```

✅ `nslookup` responde con la IP del portátil 1, `TcpTestSucceeded : True` en los dos puertos y `200`. Si falla, revisen la Fase 10.1 y que los dos portátiles estén en la misma red.

```powershell
# 3) La red externa de este portátil
docker network create --subnet 192.168.0.0/24 --ip-range 192.168.0.128/25 --gateway 192.168.0.254 red_externa

# 4) Escribir la IP del portátil 1: es el DNS de los actores
cd maquina2
Copy-Item .env.example .env      # solo si no existe (clonado desde GitHub)
notepad .env          # IP_MAQUINA1=<IP_M1>
```

---

## Fase 12. Actor de consola (192.168.0.20)

**Qué es:** un "usuario" de la red externa que usa `curl`. Hace exactamente el mismo recorrido que un navegador: DNS → firewall → middleware → LB → TinyCRM. Su DNS es la IP del portátil 1 (`dns:` en `maquina2/docker-compose.yml`).

```powershell
docker compose up -d --build actor-cli
docker exec actor-cli dig +short www.tiny.com
docker exec actor-cli curl -s -I http://www.tiny.com/
docker exec -it actor-cli /pruebas/1-enrutamiento.sh
```

✅ `dig` devuelve la IP del portátil 1 (en el portátil 1, `docker logs dns` muestra la consulta), y `curl` da `HTTP/1.1 200` con la cabecera `X-Firewall: tiny-fw`. En el script, `admin_a` va al Cliente A y `admin_b` al Cliente B.

---

## Fase 13. Actores con navegador (192.168.0.10 y .11)

**Qué es:** dos Firefox que corren dentro de contenedores de la red externa, uno por cliente. Se manejan desde el navegador normal del portátil.

```powershell
docker compose up -d actor-cliente-a actor-cliente-b
```

- **Actor Cliente A:** abran **http://localhost:5800**. Se abre Firefox en `http://www.tiny.com`. Inicien sesión con `admin_a` / `admin123`. También pueden escribir **`https://www.tiny.com`**: aparece el candado, porque Firefox confía en la Tiny CA (`maquina2/firefox-policies.json`).
- **Actor Cliente B:** abran **http://localhost:5801**. Inicien sesión con `admin_b` / `admin123`.

✅ Cada uno ve **solo los usuarios y tickets de su cliente**. Si crean un ticket en A, no aparece en B.

En el Firefox del contenedor pueden abrir `http://www.tiny.com/api/sistema/info`. Muestra qué cliente, qué instancia y qué nodo de BD atendieron la petición. Recarguen la página varias veces y verán alternar `a1` y `a2`.

**Registrar usuarios nuevos** (botón de registro en el login):
- Si el correo es `@clientea.com`, el usuario se crea en el Cliente A.
- Si el correo es `@clienteb.com`, se crea en el Cliente B.
- Si `admin_a` crea un usuario desde el Dashboard, queda en el Cliente A.

Después de unos segundos el usuario aparece en la BD Usuarios del portátil 1, y ya puede iniciar sesión.

---

# PRUEBAS DE LA RÚBRICA (para la sustentación)

## Fase 14. Guion de pruebas

**Desde el portátil 2 (PowerShell)**, recorriendo DNS y firewall como un usuario real:

```powershell
docker exec -it actor-cli /pruebas/1-enrutamiento.sh     # Middleware y enrutamiento (15)
docker exec -it actor-cli /pruebas/2-balanceo.sh         # Balanceador por cliente (10)
docker exec -it actor-cli /pruebas/3-sincronizacion.sh   # Sincronización de usuarios (10)
docker exec -it actor-cli /pruebas/4-aislamiento.sh      # Aislamiento entre clientes (10)
```

**Desde el portátil 1 (Git Bash).** Clic derecho en la carpeta `tinycrm-distribuido` → "Open Git Bash here":

```bash
./scripts/pruebas/tolerancia-app.sh a    # Tolerancia a fallos (15): apaga tinycrm-a1 con tráfico, 0 errores
./scripts/pruebas/cluster-bd.sh          # Clúster de BD (15): replicación, caída de pxc1 y reincorporación
./scripts/pruebas/broker.sh              # Broker (10): Consumer caído, el evento espera en la cola
./scripts/pruebas/aislamiento-bd.sh      # Aislamiento a nivel de datos y de red
./scripts/estado.sh                      # Resumen general
./scripts/ver-registro-usuarios.sh       # BD Usuarios y últimos eventos
```

**Tolerancia a fallos "en vivo"** (la más vistosa):
1. En el portátil 2, abran el navegador del Actor A (http://localhost:5800) con la sesión de `admin_a` iniciada.
2. En el portátil 1 ejecuten `docker stop tinycrm-a1`.
3. Sigan navegando en TinyCRM. **La sesión no se cierra**, porque está guardada en la BD y la atiende `tinycrm-a2`. En http://localhost:8404 se ve `tinycrm-a1` en rojo.
4. Ejecuten `docker start tinycrm-a1`. A los segundos vuelve a verde y retoma su parte del tráfico.

**Orquestación (10):** muestren `docker compose ps` en los dos portátiles y expliquen los `depends_on` y los `healthcheck` del `docker-compose.yml`.

---

## Fase 15. Apagar y volver a encender

**Apagar el portátil 1 en orden** (Git Bash): `./scripts/bajar-todo.sh`

O en PowerShell, dentro de `maquina1`:

```powershell
docker compose stop dns firewall middleware tinycrm-a3 tinycrm-b3 tinycrm-a2 tinycrm-b2 tinycrm-a1 tinycrm-b1 lb-cliente-a lb-cliente-b consumer broker usuarios-db lb-bd
docker compose stop pxc3; docker compose stop pxc2; docker compose stop pxc1
```

> pxc1 se apaga **de último**. Así queda marcado como el nodo que debe recrear el clúster al encender.

**Encender de nuevo:**
- Portátil 1: `docker compose up -d` dentro de `maquina1`. Ya no hace falta ir uno por uno: el compose respeta el orden.
- Portátil 2: `docker compose up -d` dentro de `maquina2`.
- **Si la IP del portátil 1 cambió** (otro día u otro hotspot), actualícenla en los dos `.env`:
  - Portátil 1: `IP_MAQUINA1` en `maquina1\.env`, y luego `docker compose up -d dns`.
  - Portátil 2: `IP_MAQUINA1` en `maquina2\.env`, y luego `docker compose up -d`.

**Arranque automático del clúster:** si pxc1 arranca y ningún otro nodo está encendido, `pxc-arranque.sh` lo marca como nodo de arranque y recrea el clúster solo (en su log aparece `AVISO: safe_to_bootstrap=0 pero ningun otro nodo responde`). Por eso deben apagar **siempre pxc1 de último**: así es el nodo con los datos más recientes.

**Si los pxc no arrancan** (pxc1 se queda en `Waiting` o `unhealthy` y su log dice `UNIENDOSE al cluster` / `non-primary`): ningún nodo quedó marcado para crear el clúster. En PowerShell, dentro de `maquina1`: `..\scripts\reparar-cluster-bd.ps1` (si Windows bloquea el script: `powershell -ExecutionPolicy Bypass -File ..\scripts\reparar-cluster-bd.ps1`). En Git Bash: `./scripts/reparar-cluster-bd.sh`.

**Borrar todo y empezar de cero** (se pierden los datos): `docker compose down -v` en `maquina1`.

---

## Problemas frecuentes

| Problema | Solución |
|---|---|
| `Bind for 0.0.0.0:80 failed: port is already allocated` | Otro programa usa el puerto 80 (IIS, Skype, XAMPP...). Búsquenlo con `netstat -ano \| findstr :80` y ciérrenlo. Si no se puede, cambien en `maquina1\docker-compose.yml` la línea `"80:80"` por `"8080:80"` y usen `http://www.tiny.com:8080`. |
| El portátil 2 no llega al 1 (`TcpTestSucceeded: False`) | Revisen la regla del firewall de Windows (Fase 10.1), que la red sea "Privada" y que estén en la misma red. El WiFi de la universidad suele bloquear: usen el hotspot. |
| `pxc2` o `pxc3` se quedan en `starting` mucho tiempo | Están copiando los datos (SST). Revisen `docker logs -f pxc2`. Si se queda en `Restarting` y el log dice `Could not find a CA (Certificate Authority) file`, están usando una versión vieja de `cluster-bd/pxc-arranque.sh`: reemplácenla y reinicien el clúster desde cero con `docker compose down -v` y la Fase 2. |
| `tinycrm-a1` queda `unhealthy` | Revisen `docker logs tinycrm-a1`. Casi siempre es que lb-bd o el clúster no estaban listos. Se reinicia solo. Si sigue, usen `docker compose restart tinycrm-a1`. |
| El login dice "Usuario no registrado en ningun cliente" | El Consumer no procesó el evento. Revisen `docker logs consumer` y la cola en http://localhost:15672. |
| `Can't connect to MySQL server on '192:3306'` | PowerShell partió el argumento `-h192.168.2.1` en el punto. Escríbanlo con espacio: `-h 192.168.2.1`. Pasa con cualquier argumento pegado a un guion que contenga puntos. |
| `docker logs consumer` dice `'cryptography' package is required for ... caching_sha2_password` | Falta la librería `cryptography` en la imagen. Es una versión vieja de `consumer/requirements.txt`: reemplácenla y ejecuten `docker compose up -d --build consumer`. Los eventos pendientes no se pierden porque siguen en la cola. |
| `https://www.tiny.com` muestra "Advertencia: riesgo de seguridad" en el Firefox del actor | Firefox no cargó la Tiny CA. Revisen que exista `certificados\tiny-ca.crt` en el portátil 2 y recreen el actor: `docker compose up -d --force-recreate actor-cliente-a`. Mientras tanto pueden usar "Avanzado → Aceptar el riesgo". |
| Quieren certificados propios (nuevos) | En el portátil 1, desde la carpeta del proyecto: `docker run --rm -v "${PWD}\certificados:/certs" alpine:3.20 sh -c "apk add -q openssl && tr -d '\r' < /certs/generar-certificados.sh \| sh"`. Copien la carpeta `certificados` al portátil 2 y recreen el firewall, el dns y los actores. |
| Por `https://` la página carga pero **el login no funciona** (por `http://` sí) | CORS: TinyCRM no reconocía el origen `https://www.tiny.com`. En `maquina1\docker-compose.yml` debe estar `SERVER_FORWARD_HEADERS_STRATEGY: framework` (en `x-env-comun`). Apliquen con `docker compose up -d` y esperen a que las 6 instancias queden `healthy`. En F12 → Red, el POST `/api/auth/login` mostraba `403 Invalid CORS request`. |
| Docker se pone muy lento o se cierra | Falta memoria: revisen `.wslconfig` (Fase 0.2) y cierren el navegador y otros programas pesados. |
| `bash\r: No such file or directory` o errores raros en scripts | Un `.sh` quedó con finales de línea de Windows. Vuelvan a descomprimir el `.zip` y no editen con el Bloc de notas. |
| La build de TinyCRM falla en `npm ci` o `gradle` | Es un problema de Internet durante la descarga. Repitan `docker compose build tinycrm-a1`. |
| Cambió la IP del portátil 1 (otro día u otro hotspot) | Actualicen `IP_MAQUINA1` en `maquina1\.env` (y ejecuten `docker compose up -d dns`) y en `maquina2\.env` (y ejecuten `docker compose up -d`). |
| `Bind for 0.0.0.0:53 failed` o `port is already allocated` en el firewall | Windows usa el puerto 53 si **el portátil 1 comparte su propio hotspot** ("Zona con cobertura inalámbrica móvil" o "Conexión compartida a Internet"). Usen el hotspot del celular, o desactiven ese servicio. Para revisar: `netstat -ano \| findstr :53` |
| `nslookup www.tiny.com IP_M1` no responde desde el portátil 2 | Falta la regla UDP 53 de la Fase 10.1, o la red no está marcada como "Privada". |
| `docker logs dns` muestra `failed to create listening socket` | El firewall se reinició y el dns perdió su red. Ejecuten `docker compose up -d --force-recreate dns`. |

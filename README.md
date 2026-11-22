# TinyCRM Distribuido Multi-Cliente

**Proyecto Final · Sistemas Distribuidos 2026-2 · CECAR**

Despliegue distribuido de [TinyCRM](https://github.com/spkdroid/TinyCRM) para la empresa ficticia **ACME**, que ofrece el CRM a dos clientes (**Cliente A** y **Cliente B**) con infraestructura aislada para cada uno. Los dos clientes entran por la misma dirección, `www.tiny.com`. Según el usuario que inicia sesión, el sistema lo envía al clúster y a la base de datos de su cliente.

Todo corre en **contenedores Docker**, repartidos en **2 equipos** según la arquitectura definida por el docente.

---

## Arquitectura

```
                 PORTÁTIL 2 (Máquina 2)                         PORTÁTIL 1 (Máquina 1)
        ┌──── Red Externa 192.168.0.0/24 ────┐      ┌─────────────────────────────────────────────────────────────┐
        │  Actor Cliente A   192.168.0.10    │      │  DNS + Firewall 192.168.0.1 / 192.168.1.1  (puertos 53, 80, 443)
        │  Actor Cliente B   192.168.0.11    │─────►│        │                                                     │
        │  Actor consola     192.168.0.20    │ WiFi │        ▼            ── Red DMZ 192.168.1.0/24 ──             │
        └────────────────────────────────────┘      │  Middleware 192.168.1.5 ──► BD Usuarios 192.168.1.9          │
                                                    │     │            │                     ▲                     │
                                                    │     ▼            ▼                     │ Consumer 192.168.1.10
                                                    │  LB Cliente A  LB Cliente B            │                     │
                                                    │  192.168.1.6   192.168.1.7      Broker RabbitMQ 1.8 / 2.8    │
                                                    │     │            │                     ▲                     │
                                                    │     ▼            ▼     ── Red Interna 192.168.2.0/24 ──      │
                                                    │  TinyCRM A1/A2/A3  TinyCRM B1/B2/B3 ───┘ (eventos)           │
                                                    │          └──────┬───────┘                                    │
                                                    │                 ▼                                            │
                                                    │        LB BD 192.168.2.1 ──► Cluster DB pxc1 / pxc2 / pxc3   │
                                                    └─────────────────────────────────────────────────────────────┘
```

### Componentes

| Componente | Contenedor(es) | IP(s) | Tecnología |
|---|---|---|---|
| Actores (usuarios) | `actor-cliente-a`, `actor-cliente-b`, `actor-cli` | 192.168.0.10 / .11 / .20 | Firefox en contenedor, curl |
| DNS | `dns` | 192.168.0.1 | dnsmasq |
| Firewall | `firewall` | 192.168.0.1 · 192.168.1.1 | nginx (HTTP 80 / HTTPS 443) |
| Middleware | `middleware` | 192.168.1.5 | Python · aiohttp |
| BD Usuarios | `usuarios-db` | 192.168.1.9 | MySQL 8 |
| Broker de mensajería | `broker` | 192.168.1.8 · 192.168.2.8 | RabbitMQ 3.13 |
| Consumer | `consumer` | 192.168.1.10 | Python · pika |
| LB Cliente A / B | `lb-cliente-a`, `lb-cliente-b` | 192.168.1.6 / .7 | HAProxy 3.0 |
| Clúster TinyCRM A | `tinycrm-a1`, `a2`, `a3` | 192.168.1.3/.13/.23 · 192.168.2.3/.13/.23 | Spring Boot + Vue |
| Clúster TinyCRM B | `tinycrm-b1`, `b2`, `b3` | 192.168.1.4/.14/.24 · 192.168.2.4/.14/.24 | Spring Boot + Vue |
| LB BD | `lb-bd` | 192.168.2.1 | HAProxy 3.0 (TCP) |
| Clúster DB | `pxc1`, `pxc2`, `pxc3` | 192.168.2.10 / .11 / .12 | Percona XtraDB Cluster 8.0 (Galera) |

La **Red Interna** se crea con `--internal`, por lo que no tiene salida a Internet. Desde la red externa solo se llega al DNS y al Firewall.

### Recorrido de una petición

1. El actor pregunta al **DNS** por `www.tiny.com` y recibe la IP del portátil 1.
2. Entra por el **Firewall** (puerto 80 o 443), que valida el nombre, el método y la ruta y aplica límites de tasa.
3. El **Middleware** busca al usuario en la **BD Usuarios** y lo envía solo al **LB de su cliente**, con una cookie firmada (HMAC).
4. El **LB** reparte la petición entre las 3 instancias de TinyCRM del cliente, con health checks.
5. **TinyCRM** guarda los datos en el **Clúster DB**, pasando por el **LB BD**. La replicación entre nodos es síncrona.
6. Al crear o eliminar un usuario, TinyCRM publica un evento en el **Broker**. El **Consumer** lo registra en la BD Usuarios.

---

## Cumplimiento de la rúbrica

| Ítem | Implementación | Prueba |
|---|---|---|
| Middleware y enrutamiento por cliente (15) | Búsqueda del usuario en la BD Usuarios y cookie de cliente firmada con HMAC-SHA256 | `1-enrutamiento.sh` |
| Sincronización de usuarios (10) | Eventos `USUARIO_CREADO` / `USUARIO_ELIMINADO` publicados después del COMMIT, UPSERT idempotente y resincronización periódica | `3-sincronizacion.sh` |
| Balanceador por cliente (10) | Un HAProxy por cliente, round-robin, health check `/actuator/health` | `2-balanceo.sh` y paneles `:8404` / `:8405` |
| Clúster de aplicación (15) | 3 instancias por cliente con la misma imagen | `docker compose ps` |
| Clúster de base de datos (15) | Galera con 3 nodos, un escritor y dos de respaldo detrás del LB BD | `cluster-bd.sh` |
| Broker / cola de eventos (10) | Exchange topic `tinycrm.usuarios`, cola durable y ACK manual | `broker.sh` y consola `:15672` |
| Tolerancia a fallos (15) | Sesiones en la BD (Spring Session JDBC), reintentos en HAProxy y conmutación de nodo de BD | `tolerancia-app.sh` |
| Orquestación (10) | `docker-compose.yml` por máquina, con healthchecks y `depends_on` | `docker compose up -d` |
| Aislamiento entre clientes (10) | Segmentación de red, cookie firmada, sesiones separadas y una BD y usuario de BD por cliente | `4-aislamiento.sh` y `aislamiento-bd.sh` |

---

## Estructura del repositorio

```
├── tinycrm/              Código de TinyCRM (adaptado) y su Dockerfile
├── maquina1/             Portátil 1: docker-compose y configuración de cada servicio
│   ├── firewall/         nginx.conf (reglas, HTTP/HTTPS)
│   ├── dns/              dnsmasq
│   ├── middleware/       enrutamiento por cliente (Python)
│   ├── consumer/         consumidor de eventos (Python)
│   ├── usuarios-db/      esquema de la BD central
│   ├── balanceadores/    HAProxy: LB A, LB B, LB BD
│   ├── cluster-bd/       arranque del clúster Percona y creación de las BD por cliente
│   └── .env.example      plantilla de variables
├── maquina2/             Portátil 2: actores (navegadores y consola)
├── cliente/              Imagen de pruebas (curl + scripts de la red externa)
├── certificados/         Scripts para generar el certificado HTTPS (las claves no se suben)
├── scripts/              Estado, apagado, reparación y pruebas de la rúbrica
├── GUIA_PASO_A_PASO.md   Despliegue servicio por servicio
└── README.md
```

---

## Requisitos

- **2 portátiles con Windows 10/11** y **Docker Desktop** (WSL2). El portátil 1 necesita **16 GB de RAM** o más.
- Los dos conectados a la **misma red**. Se recomienda el hotspot de un celular, y la red no puede usar 192.168.0/1/2.x.
- **Git for Windows**, que incluye Git Bash para los scripts de prueba.

---

## Puesta en marcha rápida

> La explicación detallada de cada servicio está en **[GUIA_PASO_A_PASO.md](GUIA_PASO_A_PASO.md)**.

### En los dos portátiles
```powershell
git clone https://github.com/<usuario>/<repositorio>.git C:\sd\tinycrm-distribuido
cd C:\sd\tinycrm-distribuido
```

### Portátil 1
```powershell
# 1. Redes del diagrama
docker network create --subnet 192.168.0.0/24 --ip-range 192.168.0.128/25 --gateway 192.168.0.254 red_externa
docker network create --subnet 192.168.1.0/24 --ip-range 192.168.1.128/25 --gateway 192.168.1.254 red_dmz
docker network create --subnet 192.168.2.0/24 --ip-range 192.168.2.128/25 --gateway 192.168.2.254 --internal red_interna

# 2. Certificados HTTPS (luego copien la carpeta certificados al portátil 2)
powershell -ExecutionPolicy Bypass -File .\certificados\generar-certificados.ps1

# 3. Variables: IP del portátil 1 (ipconfig) y contraseñas
cd maquina1
Copy-Item .env.example .env
notepad .env

# 4. Construir y levantar (la primera vez tarda 10-15 min)
docker build -t tiny-cliente:1.0 ..\cliente
docker compose up -d --build
```

Abran los puertos en el firewall de Windows (**PowerShell como administrador**):
```powershell
New-NetFirewallRule -DisplayName "TinyCRM-SD-TCP" -Direction Inbound -Protocol TCP -LocalPort 53,80,443,8404,8405,15672 -Action Allow -Profile Any
New-NetFirewallRule -DisplayName "TinyCRM-SD-DNS" -Direction Inbound -Protocol UDP -LocalPort 53 -Action Allow -Profile Any
```

### Portátil 2
```powershell
docker network create --subnet 192.168.0.0/24 --ip-range 192.168.0.128/25 --gateway 192.168.0.254 red_externa
cd maquina2
Copy-Item .env.example .env
notepad .env            # IP_MAQUINA1 = IP del portátil 1
docker compose up -d --build
```

### Usar el sistema
- **Actor Cliente A:** http://localhost:5800 → `http://www.tiny.com` o `https://www.tiny.com`
- **Actor Cliente B:** http://localhost:5801

| Usuario | Contraseña | Cliente |
|---|---|---|
| `admin_a` | `admin123` | A |
| `support_a` | `support123` | A |
| `admin_b` | `admin123` | B |
| `support_b` | `support123` | B |

Los usuarios nuevos que se registran con un correo `@clientea.com` quedan en el Cliente A, y los de `@clienteb.com` en el Cliente B.

---

## Pruebas

**Portátil 2 (PowerShell)**, desde la red externa:
```powershell
docker exec -it actor-cli /pruebas/1-enrutamiento.sh
docker exec -it actor-cli /pruebas/2-balanceo.sh
docker exec -it actor-cli /pruebas/3-sincronizacion.sh
docker exec -it actor-cli /pruebas/4-aislamiento.sh
```

**Portátil 1 (Git Bash)**, pruebas de fallas:
```bash
./scripts/pruebas/tolerancia-app.sh a
./scripts/pruebas/cluster-bd.sh
./scripts/pruebas/broker.sh
./scripts/pruebas/aislamiento-bd.sh
./scripts/estado.sh
```

**Paneles (portátil 1):** LB A en `http://localhost:8404`, LB B en `http://localhost:8405` y RabbitMQ en `http://localhost:15672`.

---

## Apagar y encender

**Apagar.** Primero el portátil 2 (`docker compose stop` en `maquina2`). Luego, en el portátil 1, dentro de `maquina1`:
```powershell
docker compose stop dns firewall middleware tinycrm-a3 tinycrm-b3 tinycrm-a2 tinycrm-b2 tinycrm-a1 tinycrm-b1 lb-cliente-a lb-cliente-b consumer broker usuarios-db lb-bd
docker compose stop pxc3; docker compose stop pxc2; docker compose stop pxc1
```
pxc1 siempre se apaga de último, porque es el nodo que vuelve a crear el clúster.

**Encender.** Primero `docker compose up -d` en `maquina1` y, cuando todo esté sano, en `maquina2`. Si la IP del portátil 1 cambió, actualicen `IP_MAQUINA1` en los **dos** `.env` antes de encender.

---

## Cambios realizados a TinyCRM

Los cambios están marcados con `[SD]` en el código:

- **Imagen única** que sirve el frontend (Vue) y la API (Spring Boot).
- **Spring Session JDBC**: las sesiones se guardan en la BD y se comparten entre instancias.
- **Actuator** (`/actuator/health`) para los health checks.
- **Publicación de eventos** de usuarios en RabbitMQ (`eventos/`).
- **Multi-cliente**: `TENANT_ID` por variable de entorno, usuarios iniciales por cliente y endpoint `/api/sistema/info`.
- **CORS y cabeceras reenviadas** para funcionar detrás del proxy por HTTP y HTTPS.
- **Corrección de un bug**: `POST /api/users` guardaba la contraseña sin cifrar.

---

## Créditos

- Aplicación base: [spkdroid/TinyCRM](https://github.com/spkdroid/TinyCRM), con licencia Apache 2.0 (ver `tinycrm/LICENSE`).
- Proyecto académico para la asignatura Sistemas Distribuidos, CECAR, 2026-2.

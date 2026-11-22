"""
Middleware de enrutamiento multi-cliente (192.168.1.5)
=====================================================
Todas las peticiones de www.tiny.com llegan aqui desde el Firewall.

1. LOGIN  (POST /api/auth/login): busca el usuario en la BD central "Usuarios"
   (alimentada por el Consumer desde el Broker) para saber a que cliente
   pertenece, reenvia el login al Load Balancer de ESE cliente y, si es
   exitoso, entrega una cookie firmada (HMAC) con el cliente.
2. RESTO DE PETICIONES: lee la cookie firmada y reenvia la peticion
   unicamente al Load Balancer del cliente del usuario (aislamiento).
3. REGISTRO (POST /api/auth/register): si quien registra ya inicio sesion
   (un admin) se crea en su propio cliente; si es anonimo, el cliente se
   decide por el dominio del correo (@clientea.com -> A, @clienteb.com -> B).
"""
import asyncio
import hashlib
import hmac
import json
import logging
import os
import time

import aiomysql
from aiohttp import ClientSession, ClientTimeout, ClientError, web
from multidict import CIMultiDict

logging.basicConfig(level=logging.INFO, format="%(asctime)s [MIDDLEWARE] %(message)s")
log = logging.getLogger("middleware")

# ----------------------------------------------------------------- config
LBS = {
    "A": os.getenv("LB_CLIENTE_A", "http://192.168.1.6:8080"),
    "B": os.getenv("LB_CLIENTE_B", "http://192.168.1.7:8080"),
}
CLIENTE_ANONIMO = os.getenv("CLIENTE_ANONIMO", "A")  # solo para archivos estaticos sin sesion
DOMINIOS = dict(
    par.split(":") for par in os.getenv("DOMINIOS", "clientea.com:A,clienteb.com:B").split(",") if ":" in par
)
SECRETO = os.getenv("MIDDLEWARE_SECRETO", "cambiar-este-secreto").encode()
COOKIE = os.getenv("COOKIE_CLIENTE", "TINY_CLIENTE")
DB = dict(
    host=os.getenv("USUARIOS_DB_HOST", "192.168.1.9"),
    port=int(os.getenv("USUARIOS_DB_PORT", "3306")),
    user=os.getenv("USUARIOS_DB_USER", "middleware"),
    password=os.getenv("USUARIOS_DB_PASSWORD", "middleware_pwd"),
    db=os.getenv("USUARIOS_DB_NAME", "usuarios"),
)

HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te",
    "trailers", "transfer-encoding", "upgrade", "host", "content-length",
}


# ------------------------------------------------------- cookie firmada
def firmar(cliente: str, usuario: str) -> str:
    carga = f"{cliente}|{usuario}"
    firma = hmac.new(SECRETO, carga.encode(), hashlib.sha256).hexdigest()[:32]
    return f"{carga}|{firma}"


def verificar(valor):
    """Devuelve (cliente, usuario) si la cookie es autentica, si no None."""
    if not valor:
        return None
    partes = valor.split("|")
    if len(partes) != 3:
        return None
    cliente, usuario, firma = partes
    esperada = hmac.new(SECRETO, f"{cliente}|{usuario}".encode(), hashlib.sha256).hexdigest()[:32]
    if not hmac.compare_digest(firma, esperada) or cliente not in LBS:
        log.warning("Cookie de cliente invalida o manipulada: %r", valor)
        return None
    return cliente, usuario


# ------------------------------------------------------------ BD central
async def pool_bd(app):
    if app.get("pool") is None:
        app["pool"] = await aiomysql.create_pool(minsize=1, maxsize=10, autocommit=True, **DB)
    return app["pool"]


async def consultar(app, sql, params):
    pool = await pool_bd(app)
    async with pool.acquire() as con:
        async with con.cursor() as cur:
            await cur.execute(sql, params)
            return await cur.fetchone()


async def cliente_de_usuario(app, identificador):
    fila = await consultar(
        app,
        "SELECT tenant FROM usuarios WHERE (username=%s OR email=%s) AND activo=1 LIMIT 1",
        (identificador, identificador),
    )
    return fila[0] if fila else None


async def usuario_existe(app, username, email):
    fila = await consultar(
        app, "SELECT tenant FROM usuarios WHERE username=%s OR email=%s LIMIT 1", (username, email)
    )
    return fila is not None


# ------------------------------------------------------------- utilidades
def json_resp(status, **datos):
    resp = web.json_response(datos, status=status)
    resp.headers["X-Middleware"] = "tiny-middleware"
    return resp


async def reenviar(request: web.Request, cliente: str, cuerpo: bytes) -> web.Response:
    """Proxy inverso hacia el Load Balancer del cliente."""
    destino = LBS[cliente] + request.rel_url.path_qs
    cabeceras = CIMultiDict()
    for k, v in request.headers.items():
        if k.lower() not in HOP_BY_HOP:
            cabeceras.add(k, v)
    ip_origen = request.headers.get("X-Real-IP") or request.remote or ""
    cabeceras["X-Forwarded-For"] = ", ".join(
        x for x in [request.headers.get("X-Forwarded-For"), request.remote] if x
    )
    cabeceras["X-Forwarded-Host"] = request.host
    cabeceras["X-Cliente"] = cliente

    inicio = time.monotonic()
    try:
        async with request.app["http"].request(
            request.method, destino, headers=cabeceras, data=cuerpo or None, allow_redirects=False
        ) as r:
            datos = await r.read()
            salida = CIMultiDict()
            for k, v in r.headers.items():
                if k.lower() not in HOP_BY_HOP:
                    salida.add(k, v)
            salida["X-Cliente"] = cliente
            salida["X-Middleware"] = "tiny-middleware"
            ms = int((time.monotonic() - inicio) * 1000)
            log.info("%s %s %s -> cliente %s (%s) %s %dms [%s]", ip_origen, request.method,
                     request.rel_url.path, cliente, LBS[cliente], r.status, ms,
                     r.headers.get("X-Servidor", "?"))
            return web.Response(status=r.status, body=datos, headers=salida)
    except (ClientError, asyncio.TimeoutError) as e:
        log.error("LB del cliente %s no disponible: %s", cliente, e)
        return json_resp(502, success=False, message=f"Infraestructura del cliente {cliente} no disponible")


async def leer_json(cuerpo: bytes):
    try:
        return json.loads(cuerpo or b"{}")
    except ValueError:
        return {}


# ---------------------------------------------------------------- rutas
async def manejar(request: web.Request) -> web.StreamResponse:
    app = request.app
    ruta = request.path
    metodo = request.method
    sesion = verificar(request.cookies.get(COOKIE))
    cuerpo = await request.read()

    # 1) LOGIN: identificar al usuario y enrutar a su cliente
    if ruta == "/api/auth/login" and metodo == "POST":
        datos = await leer_json(cuerpo)
        ident = str(datos.get("username", "")).strip()
        try:
            cliente = await cliente_de_usuario(app, ident) if ident else None
        except Exception as e:  # BD central caida
            log.error("BD Usuarios no disponible: %s", e)
            return json_resp(503, success=False, message="Servicio de identificacion no disponible")
        if not cliente:
            log.info("LOGIN rechazado: '%s' no esta registrado en ningun cliente", ident)
            return json_resp(400, success=False, message="Usuario no registrado en ningun cliente")
        log.info("LOGIN '%s' identificado como cliente %s", ident, cliente)
        resp = await reenviar(request, cliente, cuerpo)
        if resp.status == 200:
            try:
                if json.loads(resp.body).get("success"):
                    resp.set_cookie(COOKIE, firmar(cliente, ident), path="/", httponly=True,
                                    samesite="Lax", max_age=30 * 24 * 3600)
            except (ValueError, TypeError):
                pass
        return resp

    # 2) REGISTRO de usuarios
    if ruta == "/api/auth/register" and metodo == "POST":
        datos = await leer_json(cuerpo)
        username = str(datos.get("username", "")).strip()
        email = str(datos.get("email", "")).strip().lower()
        if sesion:
            cliente = sesion[0]  # un admin crea usuarios en su propio cliente
        else:
            dominio = email.split("@")[-1] if "@" in email else ""
            cliente = DOMINIOS.get(dominio)
            if not cliente:
                return json_resp(400, success=False, message=(
                    "El dominio del correo no pertenece a ningun cliente. Use: "
                    + ", ".join("@" + d for d in DOMINIOS)))
        try:
            if await usuario_existe(app, username, email):
                return json_resp(400, success=False, message="El usuario o correo ya existe en la plataforma")
        except Exception as e:
            log.error("BD Usuarios no disponible: %s", e)
            return json_resp(503, success=False, message="Servicio de identificacion no disponible")
        log.info("REGISTRO '%s' <%s> en cliente %s", username, email, cliente)
        return await reenviar(request, cliente, cuerpo)

    # 3) LOGOUT: cerrar en el cliente y borrar la cookie de enrutamiento
    if ruta in ("/api/auth/logout", "/api/auth/logout-all"):
        resp = await reenviar(request, sesion[0], cuerpo) if sesion else json_resp(200, success=True)
        resp.del_cookie(COOKIE, path="/")
        return resp

    # 4) Usuario identificado: todo va a la infraestructura de SU cliente
    if sesion:
        return await reenviar(request, sesion[0], cuerpo)

    # 5) Anonimo: sin acceso a la API; solo archivos estaticos del frontend
    if ruta.startswith("/api/"):
        return json_resp(401, success=False, message="No autenticado")
    return await reenviar(request, CLIENTE_ANONIMO, cuerpo)


async def salud(request):
    try:
        await consultar(request.app, "SELECT 1", ())
        return json_resp(200, estado="ok", bd_usuarios="ok")
    except Exception as e:
        return json_resp(503, estado="degradado", bd_usuarios=str(e))


async def info(request):
    sesion = verificar(request.cookies.get(COOKIE))
    return json_resp(200, cliente=sesion[0] if sesion else None,
                     usuario=sesion[1] if sesion else None,
                     destino=LBS[sesion[0]] if sesion else None)


# --------------------------------------------------------------- arranque
async def al_iniciar(app):
    app["pool"] = None
    app["http"] = ClientSession(timeout=ClientTimeout(total=60, connect=5), auto_decompress=False)
    for intento in range(1, 31):
        try:
            await pool_bd(app)
            log.info("Conectado a la BD Usuarios %s:%s", DB["host"], DB["port"])
            break
        except Exception as e:
            log.warning("BD Usuarios no disponible (intento %d): %s", intento, e)
            await asyncio.sleep(3)


async def al_cerrar(app):
    await app["http"].close()
    if app.get("pool") is not None:
        app["pool"].close()
        await app["pool"].wait_closed()


def crear_app():
    app = web.Application(client_max_size=16 * 1024 * 1024)
    app.on_startup.append(al_iniciar)
    app.on_cleanup.append(al_cerrar)
    app.router.add_get("/middleware/salud", salud)
    app.router.add_get("/middleware/info", info)
    app.router.add_route("*", "/{tail:.*}", manejar)
    return app


if __name__ == "__main__":
    log.info("Clientes: %s | dominios: %s", LBS, DOMINIOS)
    web.run_app(crear_app(), host="0.0.0.0", port=8080, access_log=None)

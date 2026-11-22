"""
Consumer de eventos de usuarios
===============================
Escucha la cola "usuarios.sincronizacion" del Broker (RabbitMQ) y mantiene
la BD central "Usuarios" (192.168.1.9), que el Middleware usa para saber a
que cliente pertenece cada usuario.

Eventos:
  USUARIO_CREADO    -> UPSERT en usuarios (idempotente)
  USUARIO_ELIMINADO -> DELETE en usuarios
Cada evento queda registrado en la tabla eventos_recibidos (auditoria).
ACK manual: si la BD falla el mensaje vuelve a la cola (no se pierde).
"""
import json
import logging
import os
import time

import pika
import pymysql

logging.basicConfig(level=logging.INFO, format="%(asctime)s [CONSUMER] %(message)s")
log = logging.getLogger("consumer")

RABBIT_HOST = os.getenv("RABBITMQ_HOST", "192.168.1.8")
RABBIT_USER = os.getenv("RABBITMQ_USER", "tinycrm")
RABBIT_PASS = os.getenv("RABBITMQ_PASSWORD", "tinycrm_pwd")
EXCHANGE = os.getenv("EXCHANGE", "tinycrm.usuarios")
COLA = os.getenv("COLA", "usuarios.sincronizacion")

DB = dict(
    host=os.getenv("USUARIOS_DB_HOST", "192.168.1.9"),
    port=int(os.getenv("USUARIOS_DB_PORT", "3306")),
    user=os.getenv("USUARIOS_DB_USER", "consumer"),
    password=os.getenv("USUARIOS_DB_PASSWORD", "consumer_pwd"),
    database=os.getenv("USUARIOS_DB_NAME", "usuarios"),
    autocommit=False,
    charset="utf8mb4",
)

_con = None


def bd():
    global _con
    if _con is None or not _con.open:
        _con = pymysql.connect(**DB)
    else:
        _con.ping(reconnect=True)
    return _con


def registrar_evento(cur, evento, resultado):
    cur.execute(
        "INSERT INTO eventos_recibidos (tipo, tenant, username, instancia_origen, resultado, payload) "
        "VALUES (%s,%s,%s,%s,%s,%s)",
        (evento.get("tipo"), evento.get("tenant"), evento.get("username"),
         evento.get("instancia"), resultado, json.dumps(evento)[:4000]),
    )


def aplicar(evento):
    tipo = evento.get("tipo")
    tenant = evento.get("tenant")
    username = evento.get("username")
    if not (tipo and tenant and username):
        raise ValueError("evento incompleto")

    con = bd()
    try:
        with con.cursor() as cur:
            if tipo == "USUARIO_CREADO":
                cur.execute("SELECT tenant FROM usuarios WHERE username=%s FOR UPDATE", (username,))
                fila = cur.fetchone()
                if fila and fila[0] != tenant:
                    resultado = f"CONFLICTO: '{username}' ya pertenece al cliente {fila[0]}"
                    log.warning(resultado)
                elif fila:
                    cur.execute(
                        "UPDATE usuarios SET email=%s, nombre=%s, apellido=%s, rol=%s, activo=%s, "
                        "tenant_usuario_id=%s, actualizado_en=NOW() WHERE username=%s",
                        (evento.get("email"), evento.get("nombre"), evento.get("apellido"),
                         evento.get("rol"), 1 if evento.get("activo", True) else 0,
                         evento.get("usuarioId"), username),
                    )
                    resultado = "ACTUALIZADO" if cur.rowcount else "SIN_CAMBIOS"
                else:
                    cur.execute(
                        "INSERT INTO usuarios (username, email, tenant, tenant_usuario_id, nombre, apellido, rol, activo) "
                        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s)",
                        (username, evento.get("email"), tenant, evento.get("usuarioId"),
                         evento.get("nombre"), evento.get("apellido"), evento.get("rol"),
                         1 if evento.get("activo", True) else 0),
                    )
                    resultado = "CREADO"
                    log.info("Usuario '%s' registrado en el cliente %s (origen %s)",
                             username, tenant, evento.get("instancia"))
            elif tipo == "USUARIO_ELIMINADO":
                cur.execute("DELETE FROM usuarios WHERE username=%s AND tenant=%s", (username, tenant))
                resultado = "ELIMINADO" if cur.rowcount else "NO_EXISTIA"
                log.info("Usuario '%s' del cliente %s eliminado del registro", username, tenant)
            else:
                resultado = "TIPO_DESCONOCIDO"
            # La resincronizacion periodica genera muchos SIN_CAMBIOS: no los auditamos
            if resultado != "SIN_CAMBIOS":
                registrar_evento(cur, evento, resultado)
        con.commit()
    except pymysql.err.IntegrityError as e:
        con.rollback()
        log.warning("Conflicto de integridad para '%s': %s", username, e)
        with con.cursor() as cur:
            registrar_evento(cur, evento, f"ERROR_INTEGRIDAD: {e.args[-1]}"[:200])
        con.commit()
    except Exception:
        con.rollback()
        raise


def al_recibir(canal, metodo, propiedades, cuerpo):
    try:
        evento = json.loads(cuerpo)
    except ValueError:
        log.error("Mensaje no es JSON, se descarta: %r", cuerpo[:200])
        canal.basic_ack(metodo.delivery_tag)
        return
    try:
        aplicar(evento)
        canal.basic_ack(metodo.delivery_tag)
    except ValueError as e:
        log.error("Evento invalido (%s), se descarta: %s", e, evento)
        canal.basic_ack(metodo.delivery_tag)
    except Exception as e:
        log.error("Error aplicando evento (se reintentara): %s", e)
        time.sleep(2)
        canal.basic_nack(metodo.delivery_tag, requeue=True)


def main():
    credenciales = pika.PlainCredentials(RABBIT_USER, RABBIT_PASS)
    parametros = pika.ConnectionParameters(host=RABBIT_HOST, credentials=credenciales,
                                           heartbeat=30, blocked_connection_timeout=60)
    while True:
        try:
            conexion = pika.BlockingConnection(parametros)
            canal = conexion.channel()
            # Misma topologia que declara TinyCRM (RabbitConfig.java)
            canal.exchange_declare(exchange=EXCHANGE, exchange_type="topic", durable=True)
            canal.queue_declare(queue=COLA, durable=True)
            canal.queue_bind(queue=COLA, exchange=EXCHANGE, routing_key="usuario.#")
            canal.basic_qos(prefetch_count=10)
            canal.basic_consume(queue=COLA, on_message_callback=al_recibir)
            log.info("Escuchando cola '%s' en %s", COLA, RABBIT_HOST)
            canal.start_consuming()
        except pika.exceptions.AMQPConnectionError as e:
            log.warning("Broker no disponible (%s). Reintentando en 5s...", e)
            time.sleep(5)
        except Exception as e:
            log.error("Error inesperado: %s. Reintentando en 5s...", e)
            time.sleep(5)


if __name__ == "__main__":
    main()

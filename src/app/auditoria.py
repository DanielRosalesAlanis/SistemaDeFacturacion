"""Bitácora de eventos inmutable en Amazon DynamoDB.

La tabla sale de os.environ["DDB_TABLA_EVENTOS"]; se lee en cada evento,
no al crear la app. Vacía en desarrollo local: el evento sólo va al log.
En Lambda, que falte o esté vacía se registra como error.

put_item se ejecuta de forma síncrona, dentro de la petición (en Lambda un
hilo aparte se congela al devolver la respuesta y la escritura se pierde).
Un fallo de DynamoDB no tumba la operación, porque la transacción en
PostgreSQL ya se confirmó y es la fuente de verdad, pero queda con su
traza en el log (CloudWatch).
Esquema de la tabla: database/dynamodb/eventos_auditoria.json
"""
import json
import logging
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal

from flask import current_app, g, request

log = logging.getLogger("auditoria")
_recurso = None


def _tabla(nombre: str):
    global _recurso
    if _recurso is None:
        import boto3                                  # sólo se importa si se usa DynamoDB
        from botocore.config import Config
        # Tiempos cortos: sin el endpoint de VPC la conexión falla con un error
        # en el log en lugar de colgarse hasta el timeout de la Lambda.
        _recurso = boto3.resource(
            "dynamodb", region_name=current_app.config["AWS_REGION"],
            config=Config(connect_timeout=3, read_timeout=5, retries={"max_attempts": 2}))
    return _recurso.Table(nombre)


def registrar(tipo: str, entidad: str, detalle: dict | None = None, ident=None) -> None:
    ident = ident or g.get("identidad")
    ahora = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
    # Las claves de la tabla y de los GSI (entidad, fecha_evento, id_usuario, tipo) son S
    evento = {
        "entidad": str(entidad),                                   # PK, p. ej. FACTURA#7
        "fecha_evento": f"{ahora}#{uuid.uuid4().hex[:8]}",          # SK
        "tipo": str(tipo),                                         # GSI por_tipo
        "id_usuario": str(ident.id_usuario) if ident else "anonimo",  # GSI por_usuario
        "rol": str(ident.rol) if ident else "",
        "ip": request.headers.get("X-Forwarded-For", request.remote_addr or "")[:64],
        "detalle": json.loads(json.dumps(detalle or {}, default=str), parse_float=Decimal),
    }
    if current_app.config.get("TESTING"):
        log.info("evento %s", json.dumps(evento, default=str, ensure_ascii=False))
        return

    en_lambda = "AWS_LAMBDA_FUNCTION_NAME" in os.environ
    try:
        nombre = os.environ["DDB_TABLA_EVENTOS"].strip()
    except KeyError:
        log.error("Falta la variable DDB_TABLA_EVENTOS; el evento %s (%s) no se guardó", tipo, entidad)
        return
    if not nombre:
        if en_lambda:
            log.error("DDB_TABLA_EVENTOS está vacía; el evento %s (%s) no se guardó", tipo, entidad)
        else:
            log.info("evento %s", json.dumps(evento, default=str, ensure_ascii=False))
        return

    try:
        _tabla(nombre).put_item(Item=evento, ConditionExpression="attribute_not_exists(fecha_evento)")
    except Exception:                                               # noqa: BLE001
        log.exception("No se pudo escribir el evento %s (%s) en DynamoDB %s", tipo, entidad, nombre)
    else:
        log.info("Evento %s (%s) guardado en %s", tipo, entidad, nombre)

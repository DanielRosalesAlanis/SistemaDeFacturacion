"""Bitácora de eventos inmutable en Amazon DynamoDB.

Si DDB_TABLA_EVENTOS está vacía (desarrollo local) los eventos sólo se
escriben en el log. Un fallo de DynamoDB nunca tumba la operación: la
transacción en PostgreSQL ya se confirmó y es la fuente de verdad.
Esquema de la tabla: database/dynamodb/eventos_auditoria.json
"""
import json
import logging
import uuid
from datetime import datetime, timezone
from decimal import Decimal

from flask import current_app, g, request

log = logging.getLogger("auditoria")
_cliente = None


def _tabla():
    global _cliente
    if _cliente is None:
        import boto3            # sólo se importa si se usa DynamoDB
        _cliente = boto3.resource("dynamodb", region_name=current_app.config["AWS_REGION"])
    return _cliente.Table(current_app.config["DDB_TABLA_EVENTOS"])


def registrar(tipo: str, entidad: str, detalle: dict | None = None, ident=None) -> None:
    ident = ident or g.get("identidad")
    ahora = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
    evento = {
        "entidad": entidad,                                     # PK, p. ej. FACTURA#7
        "fecha_evento": f"{ahora}#{uuid.uuid4().hex[:8]}",       # SK
        "tipo": tipo,
        "id_usuario": str(ident.id_usuario) if ident else "anonimo",
        "rol": ident.rol if ident else "",
        "ip": request.headers.get("X-Forwarded-For", request.remote_addr or "")[:64],
        "detalle": json.loads(json.dumps(detalle or {}, default=str), parse_float=Decimal),
    }
    if not current_app.config["DDB_TABLA_EVENTOS"] or current_app.config.get("TESTING"):
        log.info("evento %s", json.dumps(evento, default=str, ensure_ascii=False))
        return
    try:
        _tabla().put_item(Item=evento, ConditionExpression="attribute_not_exists(fecha_evento)")
    except Exception:                                             # noqa: BLE001
        log.exception("No se pudo escribir el evento %s en DynamoDB", tipo)

"""Acceso a PostgreSQL.

Reglas de esta capa:
- Sólo se escribe con CALL facturacion.sp_* y sólo se lee de vistas
  facturacion.vw_* (o de las funciones de reporte).
- Los nombres de procedimientos y vistas salen de listas fijas en este
  archivo; los valores del usuario viajan SIEMPRE como parámetros
  enlazados (%s), nunca concatenados: no hay inyección SQL posible.
- Cada operación corre en su propia transacción; si un SP lanza una
  excepción, PostgreSQL revierte todo.
"""
import json
import logging
import threading
from decimal import Decimal

from flask import current_app, g
from psycopg import errors as pgerr
from psycopg import sql
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb, set_json_loads
from psycopg_pool import ConnectionPool

log = logging.getLogger(__name__)

# Importes dentro de JSONB (comprobantes) como Decimal exacto, nunca float
set_json_loads(lambda texto: json.loads(texto, parse_float=Decimal))

# Firma de cada procedimiento que la aplicación puede llamar (sin los INOUT).
# sp_recalcular_totales y sp_contabilizar son internos y no se exponen.
SP_FIRMAS = {
    "sp_registrar_cliente": ("varchar", "varchar", "varchar", "varchar", "varchar", "varchar"),
    "sp_registrar_servicio": ("int", "varchar", "varchar", "varchar", "numeric", "varchar"),
    "sp_asignar_caracteristica": ("int", "int", "varchar"),
    "sp_asignar_caracteristicas_masivo": ("jsonb",),
    "sp_actualizar_precio": ("int", "numeric", "int"),
    "sp_cambiar_estado_servicio": ("int", "boolean"),
    "sp_crear_factura": ("int", "int"),
    "sp_agregar_detalle": ("int", "int", "int", "numeric"),
    "sp_eliminar_detalle": ("int",),
    "sp_aplicar_descuentos": ("int",),
    "sp_emitir_factura": ("int", "int"),
    "sp_cancelar_factura": ("int", "int"),
    "sp_registrar_pago": ("int", "int", "numeric", "varchar", "int"),
    "sp_cancelar_pago": ("int", "int"),
    "sp_generar_comprobante": ("int",),
    "sp_cierre_fiscal": ("varchar", "date", "int"),
    "sp_registrar_tasa_impuesto": ("varchar", "varchar", "numeric", "date", "int"),
    "sp_registrar_usuario": ("int", "varchar", "varchar", "varchar", "int"),
    "sp_registrar_intento_acceso": ("int", "boolean"),
}

VISTAS = {
    "vw_catalogo_servicios", "vw_ficha_servicio", "vw_facturas", "vw_ventas_categoria",
    "vw_cobranza_metodo", "vw_antiguedad_saldos", "vw_auditoria_tarifas", "vw_polizas",
    "vw_balanza", "vw_usuarios", "vw_impuestos", "vw_clientes", "vw_detalle_factura",
    "vw_pagos", "vw_metodos_pago", "vw_comprobantes", "vw_cierres_fiscales",
    "vw_caracteristicas", "vw_categorias", "vw_factura_impuestos", "vw_empleados",
}


class ErrorNegocio(Exception):
    """Error que se muestra al usuario tal cual, con su código HTTP."""

    def __init__(self, mensaje: str, estado: int = 400):
        super().__init__(mensaje)
        self.mensaje = mensaje
        self.estado = estado


_pool: ConnectionPool | None = None
_candado = threading.Lock()


def _obtener_pool() -> ConnectionPool:
    global _pool
    with _candado:
        if _pool is None:
            # conninfo vacío: libpq toma PGHOST, PGPASSWORD, PGSSLMODE... del entorno
            _pool = ConnectionPool(
                conninfo="",
                min_size=1,
                max_size=current_app.config["POOL_MAX"],
                # UTC fijo: así se guardan todas las fechas, sin importar el servidor
                kwargs={"autocommit": True, "options": "-c statement_timeout=15000 -c TimeZone=UTC"},
                name="facturacion",
                open=True,
                timeout=15,
                # Lambda congela la función entre peticiones y la conexión puede
                # quedar cortada: se verifica cada una antes de entregarla.
                check=ConnectionPool.check_connection,
                max_idle=300,
            )
    return _pool


def conexion():
    fija = current_app.config.get("CONEXION_FIJA")      # sólo en pruebas automatizadas
    if fija is not None:
        return fija
    if "db" not in g:
        g.db = _obtener_pool().getconn()
    return g.db


def liberar(_exc=None) -> None:
    con = g.pop("db", None)
    if con is not None and _pool is not None:
        _pool.putconn(con)


def traducir(e: Exception) -> ErrorNegocio:
    if isinstance(e, pgerr.RaiseException):
        mensaje = e.diag.message_primary or "Operación rechazada"
        if mensaje.startswith("RN-"):
            return ErrorNegocio(mensaje, 422)
        if "no existe" in mensaje:
            return ErrorNegocio(mensaje, 404)
        return ErrorNegocio(mensaje, 400)
    if isinstance(e, pgerr.UniqueViolation):
        return ErrorNegocio("El registro ya existe", 409)
    if isinstance(e, pgerr.IntegrityError):
        return ErrorNegocio("Los datos no cumplen las restricciones de la base", 422)
    if isinstance(e, pgerr.DataError):
        return ErrorNegocio("Dato con formato o tamaño inválido", 400)
    if isinstance(e, pgerr.OperationalError):
        log.warning("Conexión con la base perdida: %s", e)
        return ErrorNegocio("Se perdió la conexión con la base de datos; intenta de nuevo", 503)
    codigo = getattr(e, "sqlstate", None) or "desconocido"
    log.exception("Error de base de datos no previsto (SQLSTATE %s)", codigo)
    # El SQLSTATE no expone datos y permite diagnosticar (p. ej. 42883 = función inexistente)
    return ErrorNegocio(f"Error interno de la base de datos (código {codigo})", 500)


def llamar(nombre: str, *args) -> dict:
    """CALL facturacion.<nombre>(...) y devuelve los parámetros INOUT como dict."""
    firma = SP_FIRMAS[nombre]
    if len(args) != len(firma):
        raise ValueError(f"{nombre} espera {len(firma)} parámetros")
    marcadores = sql.SQL(", ").join(sql.SQL("%s::" + tipo) for tipo in firma)
    consulta = sql.SQL("CALL facturacion.{}({})").format(sql.Identifier(nombre), marcadores)
    valores = [Jsonb(v) if t == "jsonb" else v for v, t in zip(args, firma)]
    con = conexion()
    try:
        with con.transaction(), con.cursor(row_factory=dict_row) as cur:
            cur.execute(consulta, valores)
            return (cur.fetchone() or {}) if cur.description else {}
    except pgerr.Error as e:
        raise traducir(e) from e


def consultar(vista: str, filtros: dict | None = None, uno: bool = False):
    """SELECT * FROM facturacion.<vista> WHERE columna = %s AND ..."""
    if vista not in VISTAS:
        raise ValueError(f"Vista no permitida: {vista}")
    consulta = sql.SQL("SELECT * FROM facturacion.{}").format(sql.Identifier(vista))
    filtros = {k: v for k, v in (filtros or {}).items() if v is not None}
    if filtros:
        consulta += sql.SQL(" WHERE ") + sql.SQL(" AND ").join(
            sql.SQL("{} = %s").format(sql.Identifier(c)) for c in filtros)
    return ejecutar_lectura(consulta, list(filtros.values()), uno)


def ejecutar_lectura(consulta, parametros=(), uno: bool = False):
    """Lectura con SQL fijo definido en el código y parámetros enlazados."""
    con = conexion()
    try:
        with con.transaction(), con.cursor(row_factory=dict_row) as cur:
            cur.execute(consulta, parametros)
            return cur.fetchone() if uno else cur.fetchall()
    except pgerr.Error as e:
        raise traducir(e) from e

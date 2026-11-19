"""Casos de uso del sistema. La API JSON y la interfaz web llaman a estas
funciones; aquí no hay HTTP. El empleado que se manda a cada SP sale de la
identidad del token (ident.id_empleado), nunca de la petición."""
from datetime import date

from . import auditoria, db, seguridad
from .db import ErrorNegocio
from .esquemas import (Cierre, ClienteNuevo, Concepto, Pago, ServicioNuevo, TasaImpuesto,
                       UsuarioNuevo)
from .seguridad import Identidad

# Roles por acción (la base vuelve a validar los que dependen del empleado)
FACTURAR = ("Gerente", "Facturista")
COBRAR = ("Gerente", "Cajero")
GERENTE = ("Gerente",)


def _like(texto: str) -> str:
    return "%" + texto.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


def _o_404(fila, mensaje: str):
    if fila is None:
        raise ErrorNegocio(mensaje, 404)
    return fila


# --- Sesión --------------------------------------------------------------------
def iniciar_sesion(usuario: str, contrasena: str):
    cuenta = db.ejecutar_lectura(
        """SELECT c.*,
                  CASE WHEN c.bloqueado_hasta > localtimestamp
                       THEN ceil(extract(epoch FROM c.bloqueado_hasta - localtimestamp) / 60)::int
                  END AS minutos_bloqueo
             FROM facturacion.fn_credenciales_usuario(%s) c""", [usuario], uno=True)
    if cuenta is None:
        seguridad.verificar_contrasena(contrasena, None)
        auditoria.registrar("LOGIN_FALLIDO", f"USUARIO#{usuario.lower()[:50]}", {"motivo": "usuario inexistente"})
        raise ErrorNegocio("Usuario o contraseña incorrectos", 401)
    entidad = f"USUARIO#{cuenta['id_usuario']}"
    if cuenta["minutos_bloqueo"]:
        raise ErrorNegocio(f"RN-33: Cuenta bloqueada por intentos fallidos; intenta en {cuenta['minutos_bloqueo']} min", 423)

    correcta = seguridad.verificar_contrasena(contrasena, cuenta["contrasena_hash"])
    r = db.llamar("sp_registrar_intento_acceso", cuenta["id_usuario"], correcta)
    if not correcta:
        auditoria.registrar("LOGIN_FALLIDO", entidad, {"bloqueada": bool(r.get("p_bloqueado_hasta"))})
        if r.get("p_bloqueado_hasta"):
            raise ErrorNegocio("RN-33: 5 intentos fallidos; la cuenta queda bloqueada 15 minutos", 423)
        raise ErrorNegocio("Usuario o contraseña incorrectos", 401)
    if not cuenta["activo"]:
        raise ErrorNegocio("La cuenta está desactivada", 403)

    datos = {"id_usuario": cuenta["id_usuario"], "id_empleado": cuenta["id_empleado"],
             "rol": cuenta["rol"], "nombre": cuenta["nombre"], "usuario": usuario.lower()}
    token, expira = seguridad.emitir_token(datos)
    auditoria.registrar("LOGIN_OK", entidad, {"rol": cuenta["rol"]}, ident=seguridad.leer_token(token))
    return token, expira, datos


# --- Catálogo ------------------------------------------------------------------
def catalogo(q: str | None = None, categoria: str | None = None, solo_activos: bool = False):
    return db.ejecutar_lectura(
        """SELECT * FROM facturacion.vw_catalogo_servicios
            WHERE (%(q)s::text IS NULL OR codigo_servicio ILIKE %(p)s OR nombre_servicio ILIKE %(p)s)
              AND (%(c)s::text IS NULL OR nombre_categoria = %(c)s)
              AND (NOT %(a)s OR estado)
            ORDER BY codigo_servicio""",
        {"q": q or None, "p": _like(q or ""), "c": categoria or None, "a": solo_activos})


def categorias():
    return db.consultar("vw_categorias")


def caracteristicas():
    return db.consultar("vw_caracteristicas")


def ficha(codigo: str):
    codigo = codigo.upper()
    servicio = _o_404(db.consultar("vw_catalogo_servicios", {"codigo_servicio": codigo}, uno=True),
                      f"El servicio {codigo} no existe")
    return {"servicio": servicio,
            "caracteristicas": db.consultar("vw_ficha_servicio", {"codigo_servicio": codigo}),
            "cambios_tarifa": db.consultar("vw_auditoria_tarifas", {"codigo_servicio": codigo})}


def registrar_servicio(ident: Identidad, s: ServicioNuevo) -> int:
    r = db.llamar("sp_registrar_servicio", s.id_categoria, s.codigo, s.nombre, s.descripcion, s.precio, s.unidad)
    auditoria.registrar("SERVICIO_REGISTRADO", f"SERVICIO#{r['p_id_servicio']}", s.model_dump(), ident)
    return r["p_id_servicio"]


def asignar_caracteristica(ident: Identidad, id_servicio: int, id_caracteristica: int, valor: str) -> None:
    db.llamar("sp_asignar_caracteristica", id_servicio, id_caracteristica, valor)
    auditoria.registrar("CARACTERISTICA_ASIGNADA", f"SERVICIO#{id_servicio}",
                        {"id_caracteristica": id_caracteristica, "valor": valor}, ident)


def asignacion_masiva(ident: Identidad, asignaciones: list[dict]) -> int:
    r = db.llamar("sp_asignar_caracteristicas_masivo", asignaciones)
    auditoria.registrar("ASIGNACION_MASIVA", "CATALOGO", {"elementos": len(asignaciones), "servicios": r["p_total"]}, ident)
    return r["p_total"]


def actualizar_precio(ident: Identidad, id_servicio: int, precio) -> None:
    db.llamar("sp_actualizar_precio", id_servicio, precio, ident.id_empleado)
    auditoria.registrar("TARIFA_CAMBIADA", f"SERVICIO#{id_servicio}", {"precio": precio}, ident)


def cambiar_estado_servicio(ident: Identidad, id_servicio: int, activo: bool) -> None:
    db.llamar("sp_cambiar_estado_servicio", id_servicio, activo)
    auditoria.registrar("SERVICIO_ESTADO", f"SERVICIO#{id_servicio}", {"activo": activo}, ident)


# --- Clientes ------------------------------------------------------------------
def clientes():
    return db.consultar("vw_clientes")


def registrar_cliente(ident: Identidad, c: ClienteNuevo) -> int:
    r = db.llamar("sp_registrar_cliente", c.nombre, c.apellido, c.rfc, c.correo, c.telefono, c.direccion)
    auditoria.registrar("CLIENTE_REGISTRADO", f"CLIENTE#{r['p_id_cliente']}", {"rfc": c.rfc.upper()}, ident)
    return r["p_id_cliente"]


def metodos_pago():
    return db.consultar("vw_metodos_pago")


# --- Facturas -------------------------------------------------------------------
def facturas(estado: str | None = None):
    return db.consultar("vw_facturas", {"estado": estado})


def factura(id_factura: int) -> dict:
    enc = _o_404(db.consultar("vw_facturas", {"id_factura": id_factura}, uno=True),
                 f"La factura {id_factura} no existe")
    return {"factura": enc,
            "detalle": db.consultar("vw_detalle_factura", {"id_factura": id_factura}),
            "impuestos": db.consultar("vw_factura_impuestos", {"id_factura": id_factura}),
            "pagos": db.consultar("vw_pagos", {"id_factura": id_factura}),
            "polizas": db.consultar("vw_polizas", {"folio": enc["folio"]}),
            "comprobante": db.consultar("vw_comprobantes", {"id_factura": id_factura}, uno=True)}


def crear_factura(ident: Identidad, id_cliente: int) -> int:
    r = db.llamar("sp_crear_factura", id_cliente, ident.id_empleado)
    auditoria.registrar("FACTURA_CREADA", f"FACTURA#{r['p_id_factura']}", {"id_cliente": id_cliente}, ident)
    return r["p_id_factura"]


def agregar_concepto(ident: Identidad, id_factura: int, c: Concepto) -> int:
    r = db.llamar("sp_agregar_detalle", id_factura, c.id_servicio, c.cantidad, c.descuento_pct)
    auditoria.registrar("CONCEPTO_AGREGADO", f"FACTURA#{id_factura}", c.model_dump(), ident)
    return r["p_id_detalle"]


def eliminar_concepto(ident: Identidad, id_detalle: int) -> int:
    renglon = _o_404(db.consultar("vw_detalle_factura", {"id_detalle": id_detalle}, uno=True),
                     f"El concepto {id_detalle} no existe")
    db.llamar("sp_eliminar_detalle", id_detalle)
    auditoria.registrar("CONCEPTO_ELIMINADO", f"FACTURA#{renglon['id_factura']}", {"id_detalle": id_detalle}, ident)
    return renglon["id_factura"]


def aplicar_descuentos(ident: Identidad, id_factura: int) -> int:
    r = db.llamar("sp_aplicar_descuentos", id_factura)
    auditoria.registrar("DESCUENTOS_APLICADOS", f"FACTURA#{id_factura}", {"renglones": r["p_renglones"]}, ident)
    return r["p_renglones"]


def emitir(ident: Identidad, id_factura: int, dias_credito: int) -> None:
    db.llamar("sp_emitir_factura", id_factura, dias_credito)
    auditoria.registrar("FACTURA_EMITIDA", f"FACTURA#{id_factura}", {"dias_credito": dias_credito}, ident)


def cancelar_factura(ident: Identidad, id_factura: int) -> None:
    db.llamar("sp_cancelar_factura", id_factura, ident.id_empleado)
    auditoria.registrar("FACTURA_CANCELADA", f"FACTURA#{id_factura}", {}, ident)


def registrar_pago(ident: Identidad, id_factura: int, p: Pago) -> int:
    r = db.llamar("sp_registrar_pago", id_factura, p.id_metodo_pago, p.monto, p.referencia, ident.id_empleado)
    auditoria.registrar("PAGO_REGISTRADO", f"FACTURA#{id_factura}", {**p.model_dump(), "id_pago": r["p_id_pago"]}, ident)
    return r["p_id_pago"]


def cancelar_pago(ident: Identidad, id_pago: int) -> int:
    pago = _o_404(db.consultar("vw_pagos", {"id_pago": id_pago}, uno=True), f"El pago {id_pago} no existe")
    db.llamar("sp_cancelar_pago", id_pago, ident.id_empleado)
    auditoria.registrar("PAGO_CANCELADO", f"FACTURA#{pago['id_factura']}", {"id_pago": id_pago}, ident)
    return pago["id_factura"]


def generar_comprobante(ident: Identidad, id_factura: int) -> dict:
    r = db.llamar("sp_generar_comprobante", id_factura)
    auditoria.registrar("COMPROBANTE_GENERADO", f"FACTURA#{id_factura}", {}, ident)
    return r["p_comprobante"]


def comprobante(id_factura: int):
    return _o_404(db.consultar("vw_comprobantes", {"id_factura": id_factura}, uno=True),
                  f"La factura {id_factura} no tiene comprobante generado")


# --- Reportes ----------------------------------------------------------------------
def panel() -> dict:
    por_estado = db.ejecutar_lectura(
        """SELECT estado, count(*) AS facturas, coalesce(sum(total), 0) AS total, coalesce(sum(saldo), 0) AS saldo
             FROM facturacion.vw_facturas GROUP BY estado ORDER BY estado""")
    cobranza = db.consultar("vw_cobranza_metodo")
    return {"por_estado": {f["estado"]: f for f in por_estado},
            "por_cobrar": sum(f["saldo"] for f in por_estado if f["estado"] == "EMITIDA"),
            "cobrado": sum(c["cobrado"] for c in cobranza),
            "ventas_categoria": db.consultar("vw_ventas_categoria"),
            "antiguedad": db.consultar("vw_antiguedad_saldos"),
            "cobranza": cobranza}


def antiguedad(fecha_corte: date | None = None):
    if fecha_corte is None:
        return db.consultar("vw_antiguedad_saldos")
    return db.ejecutar_lectura("SELECT * FROM facturacion.fn_antiguedad_saldos(%s::date)", [fecha_corte])


def reporte(vista: str, filtros: dict | None = None):
    return db.consultar(vista, filtros)


def cierre_fiscal(ident: Identidad, c: Cierre) -> int:
    r = db.llamar("sp_cierre_fiscal", c.tipo, c.fecha, ident.id_empleado)
    auditoria.registrar("CIERRE_FISCAL", f"CIERRE#{r['p_id_cierre']}", c.model_dump(), ident)
    return r["p_id_cierre"]


# --- Administración --------------------------------------------------------------
def registrar_tasa(ident: Identidad, t: TasaImpuesto) -> int:
    r = db.llamar("sp_registrar_tasa_impuesto", t.clave, t.tipo, t.tasa, t.vigente_desde, ident.id_empleado)
    auditoria.registrar("TASA_REGISTRADA", f"IMPUESTO#{r['p_id_impuesto']}", t.model_dump(), ident)
    return r["p_id_impuesto"]


def registrar_usuario(ident: Identidad, u: UsuarioNuevo) -> int:
    # La contraseña se cifra aquí; la base sólo recibe el hash bcrypt
    r = db.llamar("sp_registrar_usuario", u.id_empleado, u.nombre_usuario,
                  seguridad.hash_contrasena(u.contrasena), u.rol, ident.id_empleado)
    auditoria.registrar("USUARIO_REGISTRADO", f"USUARIO#{r['p_id_usuario']}",
                        {"id_empleado": u.id_empleado, "rol": u.rol}, ident)
    return r["p_id_usuario"]

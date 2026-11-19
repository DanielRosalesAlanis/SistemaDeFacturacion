"""API REST en /api. Autenticación con JWT (Authorization: Bearer).
Códigos: 200/201 éxito · 400 datos inválidos · 401 sin token o token inválido ·
403 rol sin permiso · 404 no existe · 409 duplicado · 422 regla de negocio
(RN-xx) · 423 cuenta bloqueada · 500 error interno.
Especificación: docs/openapi.yaml"""
from datetime import date

from flask import Blueprint, g, jsonify, request
from pydantic import ValidationError

from . import db, operaciones as op
from .db import ErrorNegocio
from .esquemas import (AsignacionMasiva, Cierre, ClienteNuevo, Concepto, Emision, EstadoServicio,
                       FacturaNueva, Login, NuevoPrecio, Pago, ServicioNuevo, TasaImpuesto,
                       UsuarioNuevo, ValorCaracteristica, errores_legibles)
from .seguridad import api_requiere

api = Blueprint("api", __name__, url_prefix="/api")
TODOS = ()
FACTURAR, COBRAR, GERENTE = op.FACTURAR, op.COBRAR, op.GERENTE


def entrada(modelo):
    datos = request.get_json(silent=True)
    if not isinstance(datos, dict):
        raise ErrorNegocio("Se esperaba un cuerpo JSON (Content-Type: application/json)", 400)
    return modelo.model_validate(datos)


def fecha_param(nombre: str) -> date | None:
    valor = request.args.get(nombre)
    if not valor:
        return None
    try:
        return date.fromisoformat(valor)
    except ValueError:
        raise ErrorNegocio(f"{nombre} debe tener formato AAAA-MM-DD", 400) from None


@api.errorhandler(ErrorNegocio)
def _error_negocio(e: ErrorNegocio):
    return jsonify(error=e.mensaje), e.estado


@api.errorhandler(ValidationError)
def _error_validacion(e: ValidationError):
    return jsonify(error="Datos inválidos", detalle=errores_legibles(e)), 400


# --- Salud y sesión ---------------------------------------------------------------
@api.get("/salud")
def salud():
    db.ejecutar_lectura("SELECT 1 AS ok", uno=True)
    return jsonify(estado="ok", base_de_datos="conectada")


@api.post("/auth/login")
def login():
    datos = entrada(Login)
    token, expira, cuenta = op.iniciar_sesion(datos.usuario, datos.contrasena)
    return jsonify(token=token, tipo="Bearer", expira=expira.isoformat(), usuario=cuenta)


@api.get("/auth/yo")
@api_requiere(*TODOS)
def yo():
    i = g.identidad
    return jsonify(id_usuario=i.id_usuario, id_empleado=i.id_empleado, nombre=i.nombre, usuario=i.usuario, rol=i.rol)


# --- Catálogo ---------------------------------------------------------------------
@api.get("/servicios")
@api_requiere(*TODOS)
def servicios():
    return jsonify(op.catalogo(request.args.get("q"), request.args.get("categoria"),
                               request.args.get("activos") == "1"))


@api.get("/servicios/<codigo>/ficha")
@api_requiere(*TODOS)
def ficha(codigo):
    return jsonify(op.ficha(codigo))


@api.post("/servicios")
@api_requiere(*GERENTE)
def registrar_servicio():
    return jsonify(id_servicio=op.registrar_servicio(g.identidad, entrada(ServicioNuevo))), 201


@api.put("/servicios/<int:id_servicio>/caracteristicas/<int:id_caracteristica>")
@api_requiere(*GERENTE)
def asignar_caracteristica(id_servicio, id_caracteristica):
    op.asignar_caracteristica(g.identidad, id_servicio, id_caracteristica, entrada(ValorCaracteristica).valor)
    return jsonify(mensaje="Característica asignada")


@api.post("/servicios/caracteristicas/masivo")
@api_requiere(*GERENTE)
def asignacion_masiva():
    return jsonify(servicios_afectados=op.asignacion_masiva(g.identidad, entrada(AsignacionMasiva).asignaciones))


@api.patch("/servicios/<int:id_servicio>/precio")
@api_requiere(*FACTURAR)
def actualizar_precio(id_servicio):
    op.actualizar_precio(g.identidad, id_servicio, entrada(NuevoPrecio).precio)
    return jsonify(mensaje="Precio actualizado y auditado")


@api.patch("/servicios/<int:id_servicio>/estado")
@api_requiere(*GERENTE)
def estado_servicio(id_servicio):
    op.cambiar_estado_servicio(g.identidad, id_servicio, entrada(EstadoServicio).activo)
    return jsonify(mensaje="Estado actualizado")


@api.get("/categorias")
@api_requiere(*TODOS)
def categorias():
    return jsonify(op.categorias())


@api.get("/caracteristicas")
@api_requiere(*TODOS)
def caracteristicas():
    return jsonify(op.caracteristicas())


# --- Clientes y métodos de pago ---------------------------------------------------
@api.get("/clientes")
@api_requiere(*TODOS)
def clientes():
    return jsonify(op.clientes())


@api.post("/clientes")
@api_requiere(*FACTURAR)
def registrar_cliente():
    return jsonify(id_cliente=op.registrar_cliente(g.identidad, entrada(ClienteNuevo))), 201


@api.get("/metodos-pago")
@api_requiere(*TODOS)
def metodos_pago():
    return jsonify(op.metodos_pago())


# --- Facturas y pagos ---------------------------------------------------------------
@api.get("/facturas")
@api_requiere(*TODOS)
def facturas():
    return jsonify(op.facturas(request.args.get("estado")))


@api.get("/facturas/<int:id_factura>")
@api_requiere(*TODOS)
def factura(id_factura):
    return jsonify(op.factura(id_factura))


@api.post("/facturas")
@api_requiere(*FACTURAR)
def crear_factura():
    return jsonify(id_factura=op.crear_factura(g.identidad, entrada(FacturaNueva).id_cliente)), 201


@api.post("/facturas/<int:id_factura>/detalle")
@api_requiere(*FACTURAR)
def agregar_concepto(id_factura):
    return jsonify(id_detalle=op.agregar_concepto(g.identidad, id_factura, entrada(Concepto))), 201


@api.delete("/facturas/detalle/<int:id_detalle>")
@api_requiere(*FACTURAR)
def eliminar_concepto(id_detalle):
    op.eliminar_concepto(g.identidad, id_detalle)
    return jsonify(mensaje="Concepto eliminado")


@api.post("/facturas/<int:id_factura>/descuentos")
@api_requiere(*FACTURAR)
def aplicar_descuentos(id_factura):
    return jsonify(renglones_actualizados=op.aplicar_descuentos(g.identidad, id_factura))


@api.post("/facturas/<int:id_factura>/emitir")
@api_requiere(*FACTURAR)
def emitir(id_factura):
    datos = Emision.model_validate(request.get_json(silent=True) or {})
    op.emitir(g.identidad, id_factura, datos.dias_credito)
    return jsonify(op.factura(id_factura)["factura"])


@api.post("/facturas/<int:id_factura>/cancelar")
@api_requiere(*GERENTE)
def cancelar_factura(id_factura):
    op.cancelar_factura(g.identidad, id_factura)
    return jsonify(mensaje="Factura cancelada; se generó la póliza de reversión")


@api.post("/facturas/<int:id_factura>/pagos")
@api_requiere(*COBRAR)
def registrar_pago(id_factura):
    return jsonify(id_pago=op.registrar_pago(g.identidad, id_factura, entrada(Pago))), 201


@api.post("/pagos/<int:id_pago>/cancelar")
@api_requiere(*GERENTE)
def cancelar_pago(id_pago):
    op.cancelar_pago(g.identidad, id_pago)
    return jsonify(mensaje="Pago cancelado; se generó la póliza de reversión")


@api.post("/facturas/<int:id_factura>/comprobante")
@api_requiere(*FACTURAR)
def generar_comprobante(id_factura):
    return jsonify(op.generar_comprobante(g.identidad, id_factura)), 201


@api.get("/facturas/<int:id_factura>/comprobante")
@api_requiere(*TODOS)
def comprobante(id_factura):
    return jsonify(op.comprobante(id_factura))


# --- Reportes y cierres -------------------------------------------------------------
REPORTES = {
    "ventas-categoria": "vw_ventas_categoria",
    "cobranza": "vw_cobranza_metodo",
    "balanza": "vw_balanza",
    "auditoria-tarifas": "vw_auditoria_tarifas",
    "impuestos": "vw_impuestos",
    "cierres": "vw_cierres_fiscales",
}


@api.get("/reportes/antiguedad")
@api_requiere(*TODOS)
def antiguedad():
    return jsonify(op.antiguedad(fecha_param("fecha_corte")))


@api.get("/reportes/polizas")
@api_requiere(*TODOS)
def polizas():
    return jsonify(op.reporte("vw_polizas", {"folio": request.args.get("folio")}))


@api.get("/reportes/<nombre>")
@api_requiere(*TODOS)
def reporte(nombre):
    if nombre not in REPORTES:
        raise ErrorNegocio(f"Reporte desconocido. Disponibles: {', '.join(sorted(REPORTES))}, antiguedad, polizas", 404)
    return jsonify(op.reporte(REPORTES[nombre]))


@api.post("/cierres")
@api_requiere(*GERENTE)
def cierre():
    return jsonify(id_cierre=op.cierre_fiscal(g.identidad, entrada(Cierre))), 201


# --- Administración -----------------------------------------------------------------
@api.post("/impuestos")
@api_requiere(*GERENTE)
def registrar_tasa():
    return jsonify(id_impuesto=op.registrar_tasa(g.identidad, entrada(TasaImpuesto))), 201


@api.get("/usuarios")
@api_requiere(*GERENTE)
def usuarios():
    return jsonify(op.reporte("vw_usuarios"))


@api.post("/usuarios")
@api_requiere(*GERENTE)
def registrar_usuario():
    return jsonify(id_usuario=op.registrar_usuario(g.identidad, entrada(UsuarioNuevo))), 201

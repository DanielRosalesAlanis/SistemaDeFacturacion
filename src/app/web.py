"""Interfaz web (frontend) con plantillas Jinja.

Jinja escapa automáticamente todo lo que se imprime (protección contra XSS).
La sesión es el mismo JWT de la API guardado en una cookie HttpOnly y
SameSite=Strict; cada formulario POST lleva un token CSRF."""
import hmac
from datetime import date

from flask import (Blueprint, current_app, flash, g, make_response, redirect, render_template,
                   request, url_for)
from pydantic import ValidationError

from . import operaciones as op
from .db import ErrorNegocio
from .esquemas import (Cierre, ClienteNuevo, Concepto, Emision, Login, NuevoPrecio, Pago,
                       ServicioNuevo, TasaImpuesto, UsuarioNuevo, ValorCaracteristica,
                       errores_legibles)
from .seguridad import COOKIE, identidad_web, token_csrf, web_requiere

web = Blueprint("web", __name__)
FACTURAR, COBRAR, GERENTE = op.FACTURAR, op.COBRAR, op.GERENTE


# Campos de control del formulario, no datos del modelo (los modelos usan extra="forbid")
CAMPOS_DE_CONTROL = {"csrf", "volver_a"}


def formulario(modelo, **extra):
    datos = {k: (v if v != "" else None) for k, v in request.form.items() if k not in CAMPOS_DE_CONTROL}
    datos.update(extra)
    return modelo.model_validate(datos)


def entero(campo: str) -> int:
    """Id numérico de un <select>; un valor alterado no debe terminar en error 500."""
    valor = request.form.get(campo, "")
    if not valor.isdigit() or not 0 < int(valor) < 2_147_483_647:
        raise ErrorNegocio(f"{campo}: valor inválido", 400)
    return int(valor)


def ejecutar(funcion, mensaje_ok: str | None = None):
    """Ejecuta una operación y muestra el resultado o el error de la regla."""
    try:
        resultado = funcion()
        if mensaje_ok:
            flash(mensaje_ok.format(r=resultado), "ok")
        return resultado, True
    except ValidationError as e:
        flash("Datos inválidos: " + "; ".join(errores_legibles(e)), "error")
    except ErrorNegocio as e:
        flash(e.mensaje, "error")
    return None, False


def volver(por_defecto: str):
    return redirect(request.form.get("volver_a") if (request.form.get("volver_a") or "").startswith("/")
                    and not request.form.get("volver_a", "").startswith("//") else por_defecto)


# --- Sesión ------------------------------------------------------------------------
@web.route("/login", methods=["GET", "POST"])
def login():
    siguiente = request.values.get("siguiente", "/")
    if not siguiente.startswith("/") or siguiente.startswith("//") or siguiente.startswith("/logout"):
        siguiente = "/"                                     # evita redirecciones abiertas y volver a /logout
    if request.method == "GET":
        if identidad_web():
            return redirect(siguiente)
        return render_template("login.html", siguiente=siguiente)
    try:
        datos = Login.model_validate({"usuario": request.form.get("usuario", ""),
                                      "contrasena": request.form.get("contrasena", "")})
        token, expira, _ = op.iniciar_sesion(datos.usuario, datos.contrasena)
    except ValidationError:
        flash("Escribe tu usuario y contraseña", "error")
        return render_template("login.html", siguiente=siguiente), 400
    except ErrorNegocio as e:
        flash(e.mensaje, "error")
        return render_template("login.html", siguiente=siguiente, usuario=request.form.get("usuario", "")), e.estado
    resp = make_response(redirect(siguiente))
    resp.set_cookie(COOKIE, token, expires=expira, httponly=True, samesite="Strict",
                    secure=current_app.config["COOKIE_SEGURA"], path="/")
    return resp


@web.route("/logout", methods=["GET", "POST"])
def logout():
    """Cerrar sesión no exige una sesión válida: si ya expiró, sólo se borra
    la cookie. Con sesión activa se exige POST con token CSRF, para que un
    enlace de otro sitio no pueda cerrarla; un GET (historial, pestaña vieja)
    regresa al panel en lugar de mostrar 405."""
    ident = identidad_web()
    if ident is not None:
        if request.method == "GET":
            return redirect(url_for("web.panel"))
        if not hmac.compare_digest(request.form.get("csrf", ""), token_csrf(ident)):
            flash("La sesión del formulario expiró; inténtalo de nuevo.", "error")
            return redirect(url_for("web.panel"))
    resp = make_response(redirect(url_for("web.login")))
    resp.delete_cookie(COOKIE, path="/")
    return resp


# --- Panel -----------------------------------------------------------------------------
@web.get("/")
@web_requiere()
def panel():
    return render_template("panel.html", p=op.panel())


# --- Catálogo -------------------------------------------------------------------------
@web.get("/catalogo")
@web_requiere()
def catalogo():
    q, categoria = request.args.get("q", ""), request.args.get("categoria", "")
    return render_template("catalogo.html", servicios=op.catalogo(q, categoria), q=q, categoria=categoria,
                           categorias=op.categorias())


@web.post("/catalogo")
@web_requiere(*GERENTE)
def registrar_servicio():
    r, ok = ejecutar(lambda: op.registrar_servicio(g.identidad, formulario(ServicioNuevo)), "Servicio registrado")
    codigo = (request.form.get("codigo") or "").upper()
    return redirect(url_for("web.ficha", codigo=codigo) if ok else url_for("web.catalogo"))


@web.get("/catalogo/<codigo>")
@web_requiere()
def ficha(codigo):
    return render_template("ficha.html", f=op.ficha(codigo), caracteristicas=op.caracteristicas())


@web.post("/catalogo/<int:id_servicio>/precio")
@web_requiere(*FACTURAR)
def precio(id_servicio):
    ejecutar(lambda: op.actualizar_precio(g.identidad, id_servicio, formulario(NuevoPrecio).precio),
             "Precio actualizado; el cambio quedó en la auditoría de tarifas")
    return volver(url_for("web.catalogo"))


@web.post("/catalogo/<int:id_servicio>/estado")
@web_requiere(*GERENTE)
def estado_servicio(id_servicio):
    activo = request.form.get("activo") == "1"
    ejecutar(lambda: op.cambiar_estado_servicio(g.identidad, id_servicio, activo),
             "Servicio activado" if activo else "Servicio desactivado")
    return volver(url_for("web.catalogo"))


@web.post("/catalogo/<int:id_servicio>/caracteristica")
@web_requiere(*GERENTE)
def caracteristica(id_servicio):
    def asignar():
        id_car = entero("id_caracteristica")
        valor = ValorCaracteristica.model_validate({"valor": request.form.get("valor", "")}).valor
        op.asignar_caracteristica(g.identidad, id_servicio, id_car, valor)
    ejecutar(asignar, "Característica asignada")
    return volver(url_for("web.catalogo"))


# --- Clientes ---------------------------------------------------------------------------
@web.get("/clientes")
@web_requiere()
def clientes():
    return render_template("clientes.html", clientes=op.clientes())


@web.post("/clientes")
@web_requiere(*FACTURAR)
def registrar_cliente():
    ejecutar(lambda: op.registrar_cliente(g.identidad, formulario(ClienteNuevo)), "Cliente registrado (id {r})")
    return redirect(url_for("web.clientes"))


# --- Facturas ----------------------------------------------------------------------------
@web.get("/facturas")
@web_requiere()
def facturas():
    estado = request.args.get("estado") or None
    return render_template("facturas.html", facturas=op.facturas(estado), estado=estado,
                           clientes=[c for c in op.clientes() if c["estado"]])


@web.post("/facturas")
@web_requiere(*FACTURAR)
def crear_factura():
    id_factura, ok = ejecutar(lambda: op.crear_factura(g.identidad, entero("id_cliente")),
                              "Borrador creado")
    return redirect(url_for("web.factura", id_factura=id_factura) if ok else url_for("web.facturas"))


@web.get("/facturas/<int:id_factura>")
@web_requiere()
def factura(id_factura):
    return render_template("factura.html", f=op.factura(id_factura), metodos=op.metodos_pago(),
                           servicios=op.catalogo(solo_activos=True))


@web.post("/facturas/<int:id_factura>/detalle")
@web_requiere(*FACTURAR)
def agregar_concepto(id_factura):
    ejecutar(lambda: op.agregar_concepto(g.identidad, id_factura, formulario(Concepto)), "Concepto agregado")
    return redirect(url_for("web.factura", id_factura=id_factura))


@web.post("/facturas/detalle/<int:id_detalle>/eliminar")
@web_requiere(*FACTURAR)
def eliminar_concepto(id_detalle):
    ejecutar(lambda: op.eliminar_concepto(g.identidad, id_detalle), "Concepto eliminado")
    return volver(url_for("web.facturas"))


@web.post("/facturas/<int:id_factura>/descuentos")
@web_requiere(*FACTURAR)
def aplicar_descuentos(id_factura):
    ejecutar(lambda: op.aplicar_descuentos(g.identidad, id_factura), "Descuentos aplicados a {r} renglón(es)")
    return redirect(url_for("web.factura", id_factura=id_factura))


@web.post("/facturas/<int:id_factura>/emitir")
@web_requiere(*FACTURAR)
def emitir(id_factura):
    ejecutar(lambda: op.emitir(g.identidad, id_factura, formulario(Emision).dias_credito), "Factura emitida")
    return redirect(url_for("web.factura", id_factura=id_factura))


@web.post("/facturas/<int:id_factura>/cancelar")
@web_requiere(*GERENTE)
def cancelar_factura(id_factura):
    ejecutar(lambda: op.cancelar_factura(g.identidad, id_factura), "Factura cancelada y póliza revertida")
    return redirect(url_for("web.factura", id_factura=id_factura))


@web.post("/facturas/<int:id_factura>/pagos")
@web_requiere(*COBRAR)
def registrar_pago(id_factura):
    ejecutar(lambda: op.registrar_pago(g.identidad, id_factura, formulario(Pago)), "Pago registrado")
    return redirect(url_for("web.factura", id_factura=id_factura))


@web.post("/pagos/<int:id_pago>/cancelar")
@web_requiere(*GERENTE)
def cancelar_pago(id_pago):
    ejecutar(lambda: op.cancelar_pago(g.identidad, id_pago), "Pago cancelado y póliza revertida")
    return volver(url_for("web.facturas"))


@web.post("/facturas/<int:id_factura>/comprobante")
@web_requiere(*FACTURAR)
def comprobante(id_factura):
    ejecutar(lambda: op.generar_comprobante(g.identidad, id_factura), "Estructura CFDI 4.0 generada")
    return redirect(url_for("web.factura", id_factura=id_factura))


# --- Reportes --------------------------------------------------------------------------
@web.get("/reportes")
@web_requiere()
def reportes():
    try:
        corte = date.fromisoformat(request.args["fecha_corte"]) if request.args.get("fecha_corte") else None
    except ValueError:
        flash("La fecha de corte debe tener formato AAAA-MM-DD", "error")
        corte = None
    return render_template(
        "reportes.html", fecha_corte=corte, antiguedad=op.antiguedad(corte),
        ventas=op.reporte("vw_ventas_categoria"), cobranza=op.reporte("vw_cobranza_metodo"),
        balanza=op.reporte("vw_balanza"), cierres=op.reporte("vw_cierres_fiscales"),
        tarifas=op.reporte("vw_auditoria_tarifas"), hoy=date.today())


@web.post("/reportes/cierre")
@web_requiere(*GERENTE)
def cierre():
    ejecutar(lambda: op.cierre_fiscal(g.identidad, formulario(Cierre)), "Cierre fiscal registrado")
    return redirect(url_for("web.reportes"))


# --- Administración --------------------------------------------------------------------
@web.get("/admin")
@web_requiere(*GERENTE)
def admin():
    return render_template("admin.html", usuarios=op.reporte("vw_usuarios"), empleados=op.reporte("vw_empleados"),
                           impuestos=op.reporte("vw_impuestos"))


@web.post("/admin/usuarios")
@web_requiere(*GERENTE)
def registrar_usuario():
    ejecutar(lambda: op.registrar_usuario(g.identidad, formulario(UsuarioNuevo)), "Usuario creado")
    return redirect(url_for("web.admin"))


@web.post("/admin/impuestos")
@web_requiere(*GERENTE)
def registrar_tasa():
    ejecutar(lambda: op.registrar_tasa(g.identidad, formulario(TasaImpuesto)),
             "Tasa registrada; la anterior se cerró un día antes")
    return redirect(url_for("web.admin"))

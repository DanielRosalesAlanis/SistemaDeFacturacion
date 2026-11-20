"""Sistema de Facturación y Servicios — aplicación Flask (frontend + API REST)."""
import hashlib
import hmac
import logging
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal
from zoneinfo import ZoneInfo

from flask import Flask, g, jsonify, render_template, request
from flask.json.provider import DefaultJSONProvider

from . import db
from .config import cargar_entorno, configuracion
from .seguridad import token_csrf

ZONA_MX = ZoneInfo("America/Mexico_City")


class ProveedorJSON(DefaultJSONProvider):
    """Importes como texto exacto ("11149.92") y fechas en ISO 8601."""

    @staticmethod
    def default(o):
        if isinstance(o, Decimal):
            return str(o)
        if isinstance(o, (datetime, date)):
            return o.isoformat()
        if isinstance(o, uuid.UUID):
            return str(o)
        return DefaultJSONProvider.default(o)


def create_app(extra: dict | None = None) -> Flask:
    cargar_entorno()
    app = Flask(__name__)
    app.json = ProveedorJSON(app)
    app.config.update(configuracion())
    app.config.update(extra or {})
    # La sesión firmada de Flask sólo transporta los avisos (flash); la
    # identidad viaja en el JWT. Su clave se deriva del secreto del JWT.
    app.secret_key = hmac.new(app.config["JWT_SECRETO"].encode(), b"flask-flash", hashlib.sha256).digest()
    app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Strict",
                      SESSION_COOKIE_SECURE=app.config["COOKIE_SEGURA"])
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    # En Lambda el runtime ya instaló su handler en el logger raíz, así que
    # basicConfig no hace nada y el nivel queda en WARNING: sin esta línea
    # los log.info no llegan a CloudWatch.
    logging.getLogger().setLevel(logging.INFO)

    from .api import api
    from .web import web
    app.register_blueprint(api)
    app.register_blueprint(web)
    app.teardown_appcontext(db.liberar)

    # --- Cabeceras de seguridad (OWASP) ----------------------------------------
    @app.after_request
    def cabeceras(resp):
        resp.headers["Content-Security-Policy"] = (
            "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; "
            "form-action 'self'; frame-ancestors 'none'; base-uri 'none'; object-src 'none'")
        resp.headers["X-Content-Type-Options"] = "nosniff"
        resp.headers["X-Frame-Options"] = "DENY"
        resp.headers["Referrer-Policy"] = "no-referrer"
        resp.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
        if app.config["COOKIE_SEGURA"]:
            resp.headers["Strict-Transport-Security"] = "max-age=31536000"
        if not request.path.startswith("/static/"):
            resp.headers["Cache-Control"] = "no-store"
        return resp

    # --- Errores -------------------------------------------------------------------
    def es_api() -> bool:
        return request.path.startswith("/api/")

    @app.errorhandler(db.ErrorNegocio)
    def error_negocio(e):
        if es_api():
            return jsonify(error=e.mensaje), e.estado
        return render_template("error.html", codigo=e.estado, mensaje=e.mensaje), e.estado

    @app.errorhandler(404)
    def no_encontrado(_e):
        if es_api():
            return jsonify(error="Recurso no encontrado"), 404
        return render_template("error.html", codigo=404, mensaje="La página no existe"), 404

    @app.errorhandler(405)
    def metodo(_e):
        if es_api():
            return jsonify(error="Método no permitido"), 405
        return render_template("error.html", codigo=405, mensaje="Método no permitido"), 405

    @app.errorhandler(413)
    def muy_grande(_e):
        return jsonify(error="La petición es demasiado grande"), 413

    @app.errorhandler(500)
    def interno(_e):
        if es_api():
            return jsonify(error="Error interno"), 500
        return render_template("error.html", codigo=500, mensaje="Ocurrió un error interno"), 500

    # --- Plantillas --------------------------------------------------------------------
    @app.context_processor
    def contexto():
        ident = g.get("identidad")
        return {"identidad": ident, "csrf": token_csrf(ident) if ident else "",
                "puede": (lambda *roles: bool(ident) and ident.puede(*roles))}

    @app.template_filter("dinero")
    def dinero(valor):
        if valor is None:
            return "—"
        return f"${Decimal(valor):,.2f}"

    @app.template_filter("fecha")
    def fecha(valor, con_hora: bool = True):
        if valor is None:
            return "—"
        if isinstance(valor, datetime):
            local = valor.replace(tzinfo=timezone.utc).astimezone(ZONA_MX) if valor.tzinfo is None else valor.astimezone(ZONA_MX)
            return local.strftime("%d/%m/%Y %H:%M" if con_hora else "%d/%m/%Y")
        return valor.strftime("%d/%m/%Y")

    @app.template_filter("pct")
    def pct(valor):
        return f"{Decimal(valor) * 100:.4g} %"

    return app

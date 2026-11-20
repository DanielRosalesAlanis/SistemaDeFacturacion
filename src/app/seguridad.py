"""Autenticación (JWT), contraseñas (bcrypt), control de acceso por rol y CSRF.

- La API recibe el token en "Authorization: Bearer <jwt>".
- La interfaz web lo guarda en una cookie HttpOnly + SameSite=Strict
  (JavaScript no puede leerla) y cada formulario lleva un token CSRF
  derivado del identificador único del JWT.
- El id del empleado que se manda a los SP sale SIEMPRE del token, nunca
  de lo que escribe el usuario.
"""
import hashlib
import hmac
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from functools import wraps

import bcrypt
import jwt
from flask import current_app, flash, g, jsonify, redirect, render_template, request, url_for

COOKIE = "sesion"
ROLES = ("Gerente", "Facturista", "Cajero", "Auxiliar")
_HASH_FICTICIO = bcrypt.hashpw(b"no-existe", bcrypt.gensalt(12))


@dataclass(frozen=True)
class Identidad:
    id_usuario: int
    id_empleado: int
    rol: str
    nombre: str
    usuario: str
    jti: str

    def puede(self, *roles: str) -> bool:
        return not roles or self.rol in roles


# --- Contraseñas -----------------------------------------------------------
def hash_contrasena(texto: str) -> str:
    return bcrypt.hashpw(texto.encode(), bcrypt.gensalt(12)).decode()


def verificar_contrasena(texto: str, hash_guardado: str | None) -> bool:
    if not hash_guardado:
        bcrypt.checkpw(texto.encode(), _HASH_FICTICIO)    # mismo tiempo de respuesta
        return False
    return bcrypt.checkpw(texto.encode(), hash_guardado.encode())


def validar_politica(texto: str) -> str | None:
    if len(texto) < 10:
        return "La contraseña debe tener al menos 10 caracteres"
    if not any(c.isalpha() for c in texto) or not any(c.isdigit() for c in texto):
        return "La contraseña debe combinar letras y números"
    return None


# --- JWT ---------------------------------------------------------------------
def emitir_token(cuenta: dict) -> tuple[str, datetime]:
    ahora = datetime.now(timezone.utc)
    expira = ahora + timedelta(minutes=current_app.config["JWT_MINUTOS"])
    datos = {
        "sub": str(cuenta["id_usuario"]),
        "emp": cuenta["id_empleado"],
        "rol": cuenta["rol"],
        "nombre": cuenta["nombre"],
        "usr": cuenta["usuario"],
        "iat": ahora,
        "exp": expira,
        "jti": secrets.token_urlsafe(16),
    }
    return jwt.encode(datos, current_app.config["JWT_SECRETO"], algorithm="HS256"), expira


def leer_token(token: str) -> Identidad:
    d = jwt.decode(token, current_app.config["JWT_SECRETO"], algorithms=["HS256"],
                   options={"require": ["exp", "iat", "sub", "emp", "rol", "jti"]})
    if d["rol"] not in ROLES:
        raise jwt.InvalidTokenError("rol desconocido")
    return Identidad(int(d["sub"]), int(d["emp"]), d["rol"], d.get("nombre", ""), d.get("usr", ""), d["jti"])


def sigue_vigente(ident: Identidad) -> bool:
    """El JWT es válido JWT_MINUTOS aunque la cuenta cambie. En cada petición
    se confirma en la base que siga activa y con el mismo rol: desactivar
    una cuenta o cambiarle el rol cierra sus sesiones al instante."""
    from . import db                          # import local: db no depende de este módulo
    c = db.ejecutar_lectura(
        "SELECT id_usuario, rol, activo FROM facturacion.fn_credenciales_usuario(%s)",
        [ident.usuario], uno=True)
    return bool(c) and c["activo"] and c["id_usuario"] == ident.id_usuario and c["rol"] == ident.rol


def token_csrf(ident: Identidad) -> str:
    return hmac.new(current_app.config["JWT_SECRETO"].encode(), ident.jti.encode(), hashlib.sha256).hexdigest()


# --- Decoradores ------------------------------------------------------------
def api_requiere(*roles: str):
    """Protege un endpoint JSON: token Bearer válido y, si se indica, uno de los roles."""
    def decorador(vista):
        @wraps(vista)
        def envoltura(*args, **kwargs):
            encabezado = request.headers.get("Authorization", "")
            if not encabezado.startswith("Bearer "):
                return jsonify(error="Falta el token: Authorization: Bearer <jwt>"), 401
            try:
                g.identidad = leer_token(encabezado[7:])
            except jwt.ExpiredSignatureError:
                return jsonify(error="El token expiró; inicia sesión de nuevo"), 401
            except jwt.InvalidTokenError:
                return jsonify(error="Token inválido"), 401
            if not sigue_vigente(g.identidad):
                return jsonify(error="La cuenta cambió o fue desactivada; inicia sesión de nuevo"), 401
            if not g.identidad.puede(*roles):
                return jsonify(error=f"Acción permitida sólo a: {', '.join(roles)}"), 403
            return vista(*args, **kwargs)
        return envoltura
    return decorador


def identidad_web() -> Identidad | None:
    token = request.cookies.get(COOKIE)
    if not token:
        return None
    try:
        ident = leer_token(token)
    except jwt.InvalidTokenError:
        return None
    return ident if sigue_vigente(ident) else None


def web_requiere(*roles: str):
    """Protege una página: sesión válida, rol y token CSRF en los POST."""
    def decorador(vista):
        @wraps(vista)
        def envoltura(*args, **kwargs):
            ident = identidad_web()
            if ident is None:
                # Sólo se vuelve a páginas GET: regresar a un POST (p. ej. /logout)
                # tras el login terminaría en "405 Método no permitido"
                if request.method == "GET":
                    return redirect(url_for("web.login", siguiente=request.path))
                return redirect(url_for("web.login"))
            g.identidad = ident
            if request.method == "POST":
                enviado = request.form.get("csrf", "")
                if not hmac.compare_digest(enviado, token_csrf(ident)):
                    flash("La sesión del formulario expiró; inténtalo de nuevo.", "error")
                    return redirect(request.referrer or url_for("web.panel"))
            if not ident.puede(*roles):
                return render_template("error.html", codigo=403,
                                       mensaje=f"Esta acción es sólo para: {', '.join(roles)}"), 403
            return vista(*args, **kwargs)
        return envoltura
    return decorador

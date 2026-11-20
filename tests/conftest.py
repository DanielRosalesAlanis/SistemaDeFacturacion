"""Las pruebas usan la base real (la de .env) dentro de una transacción que
se revierte al final de cada prueba: no dejan datos."""
import os
import sys
from pathlib import Path

import psycopg
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from app import create_app                  # noqa: E402
from app.config import cargar_entorno        # noqa: E402
from app.seguridad import emitir_token       # noqa: E402

CUENTAS = {  # usuario: (id_usuario, id_empleado, rol, nombre)
    "laura.mendez": (1, 1, "Gerente", "Laura Méndez Ríos"),
    "ana.torres": (2, 2, "Facturista", "Ana Torres Vega"),
    "carlos.ruiz": (3, 3, "Cajero", "Carlos Ruiz Pineda"),
    "diego.salas": (4, 4, "Auxiliar", "Diego Salas Ortega"),
}
# En RDS las cuentas de demo tienen otra contraseña (scripts/cambiar_contrasenas_demo.py);
# va en CONTRASENA_DEMO de .env. Demo2026! sólo sirve en una base recién cargada.
cargar_entorno()
CONTRASENA_DEMO = os.environ.get("CONTRASENA_DEMO") or "Demo2026!"


@pytest.fixture(scope="session")
def conexion_sesion():
    cargar_entorno()
    con = psycopg.connect("", autocommit=False, options="-c TimeZone=UTC")
    yield con
    con.rollback()
    con.close()


@pytest.fixture
def conexion(conexion_sesion):
    conexion_sesion.execute("SELECT 1")      # abre la transacción externa de la prueba
    yield conexion_sesion
    conexion_sesion.rollback()               # deshace todo lo que hizo la prueba


@pytest.fixture
def app(conexion):
    return create_app({"TESTING": True, "CONEXION_FIJA": conexion, "COOKIE_SEGURA": False})


@pytest.fixture
def cliente(app):
    return app.test_client()


@pytest.fixture
def token(app):
    """token('ana.torres') → JWT firmado sin pasar por bcrypt (más rápido)."""
    def _token(usuario: str) -> dict:
        id_usuario, id_empleado, rol, nombre = CUENTAS[usuario]
        with app.app_context():
            jwt, _ = emitir_token({"id_usuario": id_usuario, "id_empleado": id_empleado, "rol": rol,
                                   "nombre": nombre, "usuario": usuario})
        return {"Authorization": f"Bearer {jwt}"}
    return _token


@pytest.fixture
def sesion_web(cliente):
    """Inicia sesión por el formulario y devuelve el cliente con su cookie."""
    def _entrar(usuario: str):
        r = cliente.post("/login", data={"usuario": usuario, "contrasena": CONTRASENA_DEMO})
        assert r.status_code == 302, r.data
        return cliente
    return _entrar

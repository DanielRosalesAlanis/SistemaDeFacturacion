"""Pruebas de seguridad: inyección, escalada de rol, tokens falsificados,
fugas de información en las respuestas y validación de campos."""
import base64
import json
import re

import jwt
import pytest


def csrf_de(html: bytes) -> str:
    return re.search(rb'name="csrf" value="([0-9a-f]+)"', html).group(1).decode()


def _b64(d: dict) -> str:
    return base64.urlsafe_b64encode(json.dumps(d).encode()).rstrip(b"=").decode()


GERENTE_FALSO = {"sub": "4", "emp": 4, "rol": "Gerente", "nombre": "x", "usr": "diego.salas",
                 "iat": 1_700_000_000, "exp": 4_000_000_000, "jti": "falso"}


# --- Escalada de rol ------------------------------------------------------------------
@pytest.mark.parametrize("usuario", ["ana.torres", "carlos.ruiz", "diego.salas"])
def test_url_de_admin_rechaza_otros_roles(sesion_web, usuario):
    c = sesion_web(usuario)
    assert c.get("/admin").status_code == 403
    token = csrf_de(c.get("/").data)
    r = c.post("/admin/usuarios", data={"csrf": token, "id_empleado": 5, "nombre_usuario": "intruso",
                                         "contrasena": "Intruso2026x", "rol": "Gerente"})
    assert r.status_code == 403


@pytest.mark.parametrize("metodo, ruta", [("get", "/api/usuarios"), ("post", "/api/usuarios"),
                                          ("post", "/api/impuestos"), ("post", "/api/cierres"),
                                          ("post", "/api/facturas/1/cancelar")])
def test_api_de_gerente_rechaza_a_la_facturista(cliente, token, metodo, ruta):
    r = getattr(cliente, metodo)(ruta, headers=token("ana.torres"), json={})
    assert r.status_code == 403


def test_token_firmado_con_otra_clave_se_rechaza(cliente):
    falso = jwt.encode(GERENTE_FALSO, "clave-adivinada-por-el-atacante-123456", algorithm="HS256")
    assert cliente.get("/api/usuarios", headers={"Authorization": f"Bearer {falso}"}).status_code == 401


def test_token_sin_firma_alg_none_se_rechaza(cliente):
    sin_firma = f"{_b64({'alg': 'none', 'typ': 'JWT'})}.{_b64(GERENTE_FALSO)}."
    assert cliente.get("/api/usuarios", headers={"Authorization": f"Bearer {sin_firma}"}).status_code == 401


def test_cookie_falsificada_no_entra_a_admin(cliente):
    falso = jwt.encode(GERENTE_FALSO, "otra-clave-cualquiera-de-32-caracteres!", algorithm="HS256")
    cliente.set_cookie("sesion", falso)
    r = cliente.get("/admin")
    assert r.status_code == 302 and "/login" in r.headers["Location"]


# --- Revocación: el token deja de servir si la cuenta cambia --------------------------------
def test_token_de_cuenta_desactivada_se_rechaza(cliente, token, conexion):
    h = token("ana.torres")
    assert cliente.get("/api/auth/yo", headers=h).status_code == 200
    conexion.execute("UPDATE facturacion.usuarios SET estado = false WHERE nombre_usuario = 'ana.torres'")
    assert cliente.get("/api/auth/yo", headers=h).status_code == 401


def test_token_con_rol_anterior_se_rechaza(cliente, token, conexion):
    h = token("ana.torres")                           # emitido como Facturista
    conexion.execute("""UPDATE facturacion.usuarios SET id_rol = (SELECT id_rol FROM facturacion.roles
                         WHERE nombre_rol = 'Auxiliar') WHERE nombre_usuario = 'ana.torres'""")
    assert cliente.post("/api/facturas", headers=h, json={"id_cliente": 1}).status_code == 401


def test_sesion_web_de_cuenta_desactivada_vuelve_al_login(sesion_web, conexion):
    c = sesion_web("ana.torres")
    conexion.execute("UPDATE facturacion.usuarios SET estado = false WHERE nombre_usuario = 'ana.torres'")
    r = c.get("/facturas")
    assert r.status_code == 302 and "/login" in r.headers["Location"]


# --- Inyección SQL ----------------------------------------------------------------------
INYECCIONES = ["' OR '1'='1", "'; DROP TABLE facturacion.facturas; --", "1 UNION SELECT usuario, contrasena_hash FROM facturacion.usuarios"]


@pytest.mark.parametrize("carga", INYECCIONES)
def test_inyeccion_sql_en_filtros_no_devuelve_nada(cliente, token, carga):
    h = token("ana.torres")
    assert cliente.get("/api/servicios", query_string={"q": carga}, headers=h).json == []
    assert cliente.get("/api/facturas", query_string={"estado": carga}, headers=h).json == []
    assert cliente.get(f"/api/servicios/{carga}/ficha", headers=h).status_code == 404


@pytest.mark.parametrize("carga", INYECCIONES)
def test_inyeccion_sql_en_login_no_autentica(cliente, carga):
    r = cliente.post("/api/auth/login", json={"usuario": carga, "contrasena": carga})
    assert r.status_code in (400, 401) and "token" not in r.json


# --- Fugas en las respuestas --------------------------------------------------------------
def test_salud_no_revela_la_base(cliente):
    r = cliente.get("/api/salud")
    assert r.json == {"estado": "ok", "base_de_datos": "conectada"}


def test_login_no_publica_credenciales(cliente):
    pagina = cliente.get("/login").data.decode()
    assert "Demo2026" not in pagina and "laura.mendez" not in pagina


def test_errores_de_validacion_no_repiten_la_contrasena(cliente, token):
    r = cliente.post("/api/usuarios", headers=token("laura.mendez"),
                     json={"id_empleado": 5, "nombre_usuario": "nuevo", "contrasena": "sinNumerosSecreta", "rol": "Cajero"})
    assert r.status_code == 400 and "sinNumerosSecreta" not in r.get_data(as_text=True)


# --- Validación de campos ---------------------------------------------------------------
CLIENTE_OK = {"nombre": "Prueba SA", "rfc": "PRU010101AB1", "correo": "contacto@prueba.mx"}


@pytest.mark.parametrize("campo, valor", [("rfc", "12345678901X"), ("rfc", "ABC 010101AB"),
                                          ("correo", "sin-arroba.mx"), ("correo", "a@b"),
                                          ("telefono", "55-ABCD-1234"), ("nombre", "Nulo\x00SA")])
def test_cliente_con_campo_invalido_se_rechaza(cliente, token, campo, valor):
    r = cliente.post("/api/clientes", headers=token("ana.torres"), json={**CLIENTE_OK, campo: valor})
    assert r.status_code == 400 and campo in " ".join(r.json["detalle"])


def test_rfc_en_minusculas_se_normaliza(cliente, token):
    r = cliente.post("/api/clientes", headers=token("ana.torres"), json={**CLIENTE_OK, "rfc": "pru010101ab1"})
    assert r.status_code == 201


def test_asignacion_masiva_ambigua_se_rechaza(cliente, token):
    r = cliente.post("/api/servicios/caracteristicas/masivo", headers=token("laura.mendez"),
                     json={"asignaciones": [{"id_caracteristica": 1, "valor": "x", "id_servicio": 1, "id_categoria": 1}]})
    assert r.status_code == 400


def test_id_alterado_en_formulario_no_causa_error_500(sesion_web):
    c = sesion_web("ana.torres")
    token = csrf_de(c.get("/facturas").data)
    r = c.post("/facturas", data={"csrf": token, "id_cliente": "1 OR 1=1"}, follow_redirects=True)
    assert r.status_code == 200 and "valor inválido" in r.data.decode()

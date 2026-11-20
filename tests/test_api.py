"""Pruebas de la API REST: flujo completo, permisos por rol, JWT y OWASP."""
from datetime import datetime, timedelta, timezone
from decimal import Decimal

import jwt as pyjwt

from conftest import CONTRASENA_DEMO


def test_salud(cliente):
    r = cliente.get("/api/salud")
    assert r.status_code == 200 and r.json["base_de_datos"] == "conectada"


# --- Autenticación ---------------------------------------------------------------
def test_login_correcto_devuelve_jwt(cliente):
    r = cliente.post("/api/auth/login", json={"usuario": "ana.torres", "contrasena": CONTRASENA_DEMO})
    assert r.status_code == 200
    assert r.json["tipo"] == "Bearer" and r.json["usuario"]["rol"] == "Facturista"
    yo = cliente.get("/api/auth/yo", headers={"Authorization": f"Bearer {r.json['token']}"})
    assert yo.json["id_empleado"] == 2


def test_login_incorrecto_no_revela_si_el_usuario_existe(cliente):
    a = cliente.post("/api/auth/login", json={"usuario": "ana.torres", "contrasena": "otra-cosa-1"})
    b = cliente.post("/api/auth/login", json={"usuario": "no.existe", "contrasena": "otra-cosa-1"})
    assert a.status_code == b.status_code == 401
    assert a.json["error"] == b.json["error"]


def test_bloqueo_al_quinto_intento(cliente):
    for _ in range(4):
        assert cliente.post("/api/auth/login", json={"usuario": "diego.salas", "contrasena": "mala-123"}).status_code == 401
    quinto = cliente.post("/api/auth/login", json={"usuario": "diego.salas", "contrasena": "mala-123"})
    assert quinto.status_code == 423
    correcta = cliente.post("/api/auth/login", json={"usuario": "diego.salas", "contrasena": CONTRASENA_DEMO})
    assert correcta.status_code == 423 and "RN-33" in correcta.json["error"]


def test_sin_token_token_alterado_y_expirado(cliente, app, token):
    assert cliente.get("/api/facturas").status_code == 401
    valido = token("ana.torres")["Authorization"]
    alterado = valido[:-3] + ("aaa" if not valido.endswith("aaa") else "bbb")
    assert cliente.get("/api/facturas", headers={"Authorization": alterado}).status_code == 401
    vencido = pyjwt.encode({"sub": "2", "emp": 2, "rol": "Gerente", "jti": "x",
                            "iat": datetime.now(timezone.utc) - timedelta(hours=2),
                            "exp": datetime.now(timezone.utc) - timedelta(hours=1)},
                           app.config["JWT_SECRETO"], algorithm="HS256")
    r = cliente.get("/api/facturas", headers={"Authorization": f"Bearer {vencido}"})
    assert r.status_code == 401 and "expiró" in r.json["error"]


def test_token_firmado_con_otra_clave_no_escala_privilegios(cliente):
    falso = pyjwt.encode({"sub": "4", "emp": 1, "rol": "Gerente", "jti": "x",
                          "iat": datetime.now(timezone.utc), "exp": datetime.now(timezone.utc) + timedelta(hours=1)},
                         "clave-adivinada-por-un-atacante-0123456789", algorithm="HS256")
    assert cliente.post("/api/cierres", json={"tipo": "DIARIO", "fecha": "2026-11-19"},
                        headers={"Authorization": f"Bearer {falso}"}).status_code == 401


# --- RBAC ----------------------------------------------------------------------------
def test_permisos_por_rol(cliente, token):
    assert cliente.post("/api/facturas", json={"id_cliente": 1}, headers=token("diego.salas")).status_code == 403
    assert cliente.post("/api/facturas", json={"id_cliente": 1}, headers=token("carlos.ruiz")).status_code == 403
    assert cliente.post("/api/facturas/2/pagos", json={"id_metodo_pago": 2, "monto": "10"},
                        headers=token("ana.torres")).status_code == 403
    assert cliente.post("/api/facturas/4/cancelar", headers=token("ana.torres")).status_code == 403
    assert cliente.get("/api/usuarios", headers=token("ana.torres")).status_code == 403
    assert cliente.get("/api/facturas", headers=token("diego.salas")).status_code == 200   # consulta sí


# --- Flujo completo -------------------------------------------------------------------
def test_flujo_factura_completo(cliente, token):
    fac, caj, ger = token("ana.torres"), token("carlos.ruiz"), token("laura.mendez")
    r = cliente.post("/api/facturas", json={"id_cliente": 1}, headers=fac)
    assert r.status_code == 201
    idf = r.json["id_factura"]
    assert cliente.post(f"/api/facturas/{idf}/detalle", json={"id_servicio": 13, "cantidad": 12, "descuento_pct": 10},
                        headers=fac).status_code == 201
    emitida = cliente.post(f"/api/facturas/{idf}/emitir", json={"dias_credito": 30}, headers=fac)
    assert emitida.status_code == 200
    assert emitida.json["estado"] == "EMITIDA" and emitida.json["total"] == "11149.92"

    assert cliente.post(f"/api/facturas/{idf}/pagos", json={"id_metodo_pago": 2, "monto": "5000", "referencia": "SPEI-1"},
                        headers=caj).status_code == 201
    cancelar = cliente.post(f"/api/facturas/{idf}/cancelar", headers=ger)
    assert cancelar.status_code == 422 and cancelar.json["error"].startswith("RN-24")
    assert cliente.post(f"/api/facturas/{idf}/pagos", json={"id_metodo_pago": 2, "monto": "6149.92"},
                        headers=caj).status_code == 201

    detalle = cliente.get(f"/api/facturas/{idf}", headers=fac).json
    assert detalle["factura"]["estado"] == "PAGADA" and detalle["factura"]["saldo"] == "0.00"
    assert {m["evento"] for m in detalle["polizas"]} == {"EMISION", "COBRO"}

    cfdi = cliente.post(f"/api/facturas/{idf}/comprobante", headers=fac)
    assert cfdi.status_code == 201 and cfdi.json["Total"] == "11149.92" and cfdi.json["MetodoPago"] == "PPD"


def test_reglas_de_negocio_se_devuelven_como_422(cliente, token):
    fac = token("ana.torres")
    r = cliente.post("/api/facturas/6/detalle", json={"id_servicio": 2, "cantidad": 1, "descuento_pct": 60}, headers=fac)
    assert r.status_code == 422 and r.json["error"].startswith("RN-14")
    r = cliente.post("/api/facturas/2/pagos", json={"id_metodo_pago": 5, "monto": "100"}, headers=token("carlos.ruiz"))
    assert r.status_code == 422 and r.json["error"].startswith("RN-20")
    assert cliente.get("/api/facturas/999999", headers=fac).status_code == 404


def test_retenciones_y_descuento_automatico(cliente, token):
    fac = token("ana.torres")
    idf = cliente.post("/api/facturas", json={"id_cliente": 7}, headers=fac).json["id_factura"]
    cliente.post(f"/api/facturas/{idf}/detalle", json={"id_servicio": 1, "cantidad": 1}, headers=fac)
    f = cliente.get(f"/api/facturas/{idf}", headers=fac).json["factura"]
    assert (f["impuestos"], f["retenciones"], f["total"]) == ("5600.00", "7233.35", "33366.65")

    idf = cliente.post("/api/facturas", json={"id_cliente": 8}, headers=fac).json["id_factura"]
    cliente.post(f"/api/facturas/{idf}/detalle", json={"id_servicio": 1, "cantidad": 1}, headers=fac)
    assert cliente.get(f"/api/facturas/{idf}", headers=fac).json["detalle"][0]["descuento"] == "2800.00"


def test_gerente_crea_usuario_con_hash(cliente, token, conexion):
    ger = token("laura.mendez")
    conexion.execute("INSERT INTO facturacion.empleados(nombre, puesto, correo) VALUES ('Nuevo', 'Cajero', 'nuevo@facturacion.mx')")
    id_emp = conexion.execute("SELECT id_empleado FROM facturacion.empleados WHERE correo = 'nuevo@facturacion.mx'").fetchone()[0]
    debil = cliente.post("/api/usuarios", json={"id_empleado": id_emp, "nombre_usuario": "nuevo.cajero",
                                                "contrasena": "corta", "rol": "Cajero"}, headers=ger)
    assert debil.status_code == 400
    r = cliente.post("/api/usuarios", json={"id_empleado": id_emp, "nombre_usuario": "nuevo.cajero",
                                            "contrasena": "Segura2026x", "rol": "Cajero"}, headers=ger)
    assert r.status_code == 201
    guardado = conexion.execute("SELECT contrasena_hash FROM facturacion.usuarios WHERE nombre_usuario = 'nuevo.cajero'").fetchone()[0]
    assert guardado.startswith("$2b$") and "Segura2026x" not in guardado
    assert all("contrasena_hash" not in u for u in cliente.get("/api/usuarios", headers=ger).json)
    login = cliente.post("/api/auth/login", json={"usuario": "nuevo.cajero", "contrasena": "Segura2026x"})
    assert login.status_code == 200 and login.json["usuario"]["rol"] == "Cajero"


# --- OWASP: inyección y validación ---------------------------------------------------
def test_inyeccion_sql_no_tiene_efecto(cliente, token, conexion):
    aux = token("diego.salas")
    r = cliente.get("/api/servicios", query_string={"q": "' OR 1=1; DROP TABLE facturacion.pagos; --"}, headers=aux)
    assert r.status_code == 200 and r.json == []
    assert cliente.get("/api/servicios/SRV-001'%20OR%20'1'='1/ficha", headers=aux).status_code == 404
    # 400: el usuario sólo admite letras, números, punto, guion y guion bajo; ni llega a la base
    assert cliente.post("/api/auth/login", json={"usuario": "' OR '1'='1", "contrasena": "' OR '1'='1"}).status_code == 400
    assert conexion.execute("SELECT count(*) FROM facturacion.pagos").fetchone()[0] == 4


def test_validacion_de_entradas(cliente, token):
    fac = token("ana.torres")
    assert cliente.post("/api/clientes", json={"nombre": "X", "rfc": "ABC010101AB1", "correo": "a@b.mx",
                                               "id_empleado": 1}, headers=fac).status_code == 400  # campo extra
    assert cliente.post("/api/facturas", data="no es json", headers=fac).status_code == 400
    r = cliente.post("/api/facturas/2/pagos", json={"id_metodo_pago": 2, "monto": "-5"}, headers=token("carlos.ruiz"))
    assert r.status_code == 400 and "contrasena" not in str(r.json)


def test_reportes(cliente, token):
    aux = token("diego.salas")
    for nombre in ["ventas-categoria", "cobranza", "balanza", "auditoria-tarifas", "impuestos", "cierres",
                   "antiguedad", "polizas"]:
        assert cliente.get(f"/api/reportes/{nombre}", headers=aux).status_code == 200, nombre
    assert cliente.get("/api/reportes/antiguedad?fecha_corte=2027-03-01", headers=aux).status_code == 200
    assert cliente.get("/api/reportes/no-existe", headers=aux).status_code == 404
    balanza = cliente.get("/api/reportes/balanza", headers=aux).json
    assert sum(Decimal(b["saldo"]) for b in balanza) == 0

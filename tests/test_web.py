"""Pruebas de la interfaz web: sesión, CSRF, XSS, permisos y que cada página cargue."""
import re

from conftest import CONTRASENA_DEMO


def csrf_de(html: bytes) -> str:
    return re.search(rb'name="csrf" value="([0-9a-f]+)"', html).group(1).decode()


def test_sin_sesion_redirige_al_login(cliente):
    r = cliente.get("/facturas")
    assert r.status_code == 302 and "/login" in r.headers["Location"]


def test_cookie_de_sesion_httponly_y_samesite(cliente):
    r = cliente.post("/login", data={"usuario": "ana.torres", "contrasena": CONTRASENA_DEMO})
    cookie = r.headers["Set-Cookie"]
    assert "HttpOnly" in cookie and "SameSite=Strict" in cookie


def test_login_incorrecto_muestra_error(cliente):
    r = cliente.post("/login", data={"usuario": "ana.torres", "contrasena": "equivocada1"})
    assert r.status_code == 401 and "incorrectos".encode() in r.data


def test_redireccion_abierta_bloqueada(cliente):
    r = cliente.post("/login", data={"usuario": "ana.torres", "contrasena": CONTRASENA_DEMO, "siguiente": "//sitio-malicioso.com"})
    assert r.headers["Location"] == "/"


def test_cabeceras_de_seguridad(cliente):
    r = cliente.get("/login")
    assert "default-src 'self'" in r.headers["Content-Security-Policy"]
    assert r.headers["X-Frame-Options"] == "DENY" and r.headers["X-Content-Type-Options"] == "nosniff"


def test_todas_las_paginas_cargan_para_el_gerente(sesion_web):
    c = sesion_web("laura.mendez")
    for ruta in ["/", "/catalogo", "/catalogo?q=nube", "/catalogo/SRV-013", "/clientes", "/facturas",
                 "/facturas?estado=EMITIDA", "/reportes", "/reportes?fecha_corte=2027-02-01", "/admin"]:
        assert c.get(ruta).status_code == 200, ruta
    for id_factura in range(1, 7):
        assert c.get(f"/facturas/{id_factura}").status_code == 200, id_factura


def test_auxiliar_no_entra_a_administracion(sesion_web):
    c = sesion_web("diego.salas")
    assert c.get("/admin").status_code == 403
    assert b"Administraci" not in c.get("/").data          # tampoco ve el menú


def test_post_sin_csrf_se_rechaza(sesion_web, conexion):
    c = sesion_web("ana.torres")
    antes = conexion.execute("SELECT count(*) FROM facturacion.facturas").fetchone()[0]
    c.post("/facturas", data={"id_cliente": 1})            # sin token CSRF
    assert conexion.execute("SELECT count(*) FROM facturacion.facturas").fetchone()[0] == antes


def test_flujo_web_crear_y_emitir(sesion_web):
    c = sesion_web("ana.torres")
    token = csrf_de(c.get("/facturas").data)
    r = c.post("/facturas", data={"csrf": token, "id_cliente": 1})
    assert r.status_code == 302
    ruta = r.headers["Location"]
    c.post(ruta + "/detalle", data={"csrf": token, "id_servicio": 13, "cantidad": 12, "descuento_pct": 10})
    c.post(ruta + "/emitir", data={"csrf": token, "dias_credito": 30})
    pagina = c.get(ruta).data.decode()
    assert "EMITIDA" in pagina and "$11,149.92" in pagina


def test_regla_de_negocio_se_muestra_al_usuario(sesion_web):
    c = sesion_web("ana.torres")
    token = csrf_de(c.get("/facturas/6").data)
    r = c.post("/facturas/6/detalle", data={"csrf": token, "id_servicio": 2, "cantidad": 1, "descuento_pct": 60},
               follow_redirects=True)
    assert "RN-14" in r.data.decode()


def test_xss_se_escapa(sesion_web):
    c = sesion_web("ana.torres")
    token = csrf_de(c.get("/clientes").data)
    c.post("/clientes", data={"csrf": token, "nombre": "<script>alert('xss')</script>", "rfc": "XSS010101AB1",
                              "correo": "xss@prueba.mx", "direccion": "CP 01000"})
    pagina = c.get("/clientes").data.decode()
    assert "&lt;script&gt;alert(" in pagina and "<script>alert(" not in pagina


def test_cerrar_sesion_vencida_no_termina_en_405(cliente):
    # Pestaña vieja: la cookie ya no sirve y se pulsa «Cerrar sesión»
    cliente.set_cookie("sesion", "token-vencido")
    r = cliente.post("/logout", data={"csrf": "x"})
    assert r.status_code == 302 and r.headers["Location"].endswith("/login")    # sin ?siguiente=/logout
    r = cliente.post("/login", data={"usuario": "ana.torres", "contrasena": CONTRASENA_DEMO,
                                     "siguiente": "/logout"})
    assert r.headers["Location"] == "/"


def test_logout_por_get_no_da_405_ni_cierra_la_sesion(sesion_web):
    c = sesion_web("ana.torres")
    r = c.get("/logout")
    assert r.status_code == 302 and r.headers["Location"] == "/"
    assert c.get("/").status_code == 200                     # la sesión sigue abierta


def test_cambiar_precio_desde_la_ficha_queda_auditado(sesion_web, conexion):
    # El formulario de la ficha manda el campo oculto volver_a; no debe rechazarse
    c = sesion_web("ana.torres")
    token = csrf_de(c.get("/catalogo/SRV-013").data)
    id_servicio = conexion.execute("SELECT id_servicio FROM facturacion.servicios WHERE codigo_servicio = 'SRV-013'").fetchone()[0]
    r = c.post(f"/catalogo/{id_servicio}/precio", data={"csrf": token, "volver_a": "/catalogo/SRV-013", "precio": "975.50"},
               follow_redirects=True)
    assert "Precio actualizado" in r.data.decode() and "inválidos" not in r.data.decode()
    assert conexion.execute("SELECT precio_base FROM facturacion.servicios WHERE id_servicio = %s", [id_servicio]).fetchone()[0] == 975.50
    assert conexion.execute("SELECT count(*) FROM facturacion.vw_auditoria_tarifas WHERE codigo_servicio = 'SRV-013'").fetchone()[0] >= 1


def test_logout_con_csrf_cierra_la_sesion(sesion_web):
    c = sesion_web("ana.torres")
    token = csrf_de(c.get("/").data)
    assert c.post("/logout", data={"csrf": token}).headers["Location"].endswith("/login")
    assert c.get("/").status_code == 302

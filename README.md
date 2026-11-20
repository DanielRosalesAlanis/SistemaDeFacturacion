# Sistema de Facturación y Servicios — Equipo 3

Optativa I · Bases de Datos en la Nube · Proyecto C · AWS Academy Learner Lab

**Integrantes:** Dana Bahena Díaz, Isaac Leonardo López Flores, Renata Lizbeth Ortiz Chávez, Daniel Rosales Alanis

- **Parte 1 · Base de datos** — Isaac Leonardo López Flores (20243ds017@utez.edu.mx): `database/*.sql`, `database/resultado_pruebas.txt`, `scripts/cargar_bd.*`, `scripts/cambiar_contrasenas_demo.py`

Aplicación web en **Flask (Python)** sobre **Amazon RDS for PostgreSQL**. La aplicación incluye el frontend con plantillas Jinja y una API REST con JWT. Las reglas de negocio (RN-01 a RN-33) viven en procedimientos almacenados: la aplicación escribe sólo con `CALL facturacion.sp_*` y lee de las vistas `facturacion.vw_*`.

| Elemento | Cantidad |
| --- | --- |
| Tablas | 20 (10 del modelo ER del equipo + 10 de extensión para la rúbrica) |
| Procedimientos almacenados | 21 |
| Funciones · vistas · triggers | 11 · 21 · 1 |
| Servicios · características · valores | 100 · 50 · 1,220 |
| Pruebas de la base (`database/04_pruebas.sql`) | 63 |
| Pruebas de la aplicación (`tests/`, pytest) | 25 |
| Endpoints de la API (`docs/openapi.yaml`) | 29 |

## Estructura del repositorio

| Ruta | Contenido |
| --- | --- |
| `database/01_esquema.sql` | DDL: esquema `facturacion`, tablas, restricciones e índices |
| `database/02_procedimientos.sql` | Procedimientos almacenados, funciones, trigger y vistas |
| `database/03_datos.sql` | DML: catálogos (100 servicios, 50 características), usuarios de demostración y escenarios |
| `database/04_pruebas.sql` | Verificación de mínimos y de cada regla de negocio |
| `database/dynamodb/` | Esquema JSON de la tabla de eventos de DynamoDB, sus índices y patrones de acceso |
| `src/app/` | Aplicación Flask: `api.py` (REST), `web.py` (páginas), `operaciones.py` (casos de uso), `db.py`, `seguridad.py`, `auditoria.py` |
| `src/app/templates/`, `src/app/static/` | Frontend: plantillas Jinja, CSS y JavaScript |
| `src/wsgi.py` · `src/lambda_handler.py` | Entrada local o en servidor · entrada para AWS Lambda |
| `tests/` | Pruebas de la API y del frontend (pytest) |
| `scripts/cargar_bd.ps1` · `scripts/cargar_bd.sh` | Despliegue automatizado de la base (Windows · macOS/Linux) |
| `docs/` | Reporte de avance con diagramas, `openapi.yaml`, rúbrica y el prototipo estático original |

### Los 10 propósitos de procedimientos de la rúbrica

| # | Propósito | Implementación |
| --- | --- | --- |
| 1 | Folios atómicos | `sp_crear_factura` con `pg_advisory_xact_lock` |
| 2 | Subtotal, IVA y retenciones | `sp_recalcular_totales` + `impuestos_historico` + `factura_impuestos` |
| 3 | Descuentos por cliente o volumen | `fn_descuento_automatico`, `sp_agregar_detalle`, `sp_aplicar_descuentos` |
| 4 | Cancelación y reversión contable | `sp_cancelar_factura`, `sp_cancelar_pago` → `sp_contabilizar` (póliza inversa) |
| 5 | Cierre fiscal diario o mensual | `sp_cierre_fiscal` → `cierres_fiscales` |
| 6 | Validación de estados de pago | `sp_registrar_pago`, `sp_cancelar_pago` (RN-19 a RN-23) |
| 7 | Antigüedad de saldos | `fn_antiguedad_saldos(fecha_corte)` y `vw_antiguedad_saldos` |
| 8 | Estructura para comprobante o timbrado | `sp_generar_comprobante` → JSON CFDI 4.0 en `comprobantes` |
| 9 | Asignación masiva de características | `sp_asignar_caracteristicas_masivo` (JSON, todo o nada) |
| 10 | Auditoría de cambios en tarifas | trigger `tg_auditar_tarifa` → `auditoria_tarifas`, `vw_auditoria_tarifas` |

## Requisitos

- **Python 3.12 o superior**.
- **Cliente de PostgreSQL 16 o superior** (`psql`, `pg_dump`) para cargar la base.
  - Windows: `winget install PostgreSQL.PostgreSQL.18`
  - macOS: `brew install libpq`
  - Ubuntu: `sudo apt install postgresql-client`
- **Acceso de red a RDS.** El security group sólo acepta IPs autorizadas (`/32`). Consulta tu IP con `curl https://checkip.amazonaws.com` y pide que la agreguen.

## Configuración

1. Descarga el certificado de AWS RDS (no se sube a git):
   ```bash
   mkdir -p certs
   curl -o certs/global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
   ```
2. Copia `.env.example` como `.env` y llena `PGPASSWORD` y `JWT_SECRETO`. Para generar el secreto: `python -c "import secrets; print(secrets.token_urlsafe(48))"`.
   - En desarrollo local por http usa `COOKIE_SEGURA=false`.
   - `MOSTRAR_CUENTAS_DEMO=true` muestra los usuarios de demostración en el login (sólo local; nunca en Lambda).
   - `CONTRASENA_DEMO` es la contraseña de las cuentas de demostración en la base de `.env`; la usan las pruebas.
   - **`.env` nunca se sube a git.** Si el Learner Lab cambia el endpoint de RDS, sólo se actualiza `PGHOST`.
3. Instala las dependencias:
   ```bash
   python -m venv .venv
   .venv\Scripts\activate          # Windows   ·   source .venv/bin/activate  (macOS/Linux)
   pip install -r requirements.txt
   ```

## Cargar la base y correr sus pruebas

```powershell
.\scripts\cargar_bd.ps1                      # carga 01 → 02 → 03 y corre 04
.\scripts\cargar_bd.ps1 -SoloPruebas         # sólo pruebas (no modifica datos)
.\scripts\cargar_bd.ps1 -Forzar -Respaldo    # respalda con pg_dump, borra y recarga
.\scripts\cargar_bd.ps1 -EnvFile .env.local  # otra base, p. ej. un PostgreSQL local
```

```bash
scripts/cargar_bd.sh [--env .env] [--forzar] [--respaldo] [--solo-pruebas]   # macOS / Linux
```

> ⚠️ `01_esquema.sql` empieza con `DROP SCHEMA IF EXISTS facturacion CASCADE`. El script de despliegue se detiene si el esquema ya existe, salvo que se use `-Forzar`.

Después de cargar la base en RDS (conectado como `postgres`):

```bash
psql -X -f database/05_usuario_aplicacion.sql              # usuario app_facturacion con mínimo privilegio
psql -X -c "\password app_facturacion"                     # su contraseña va sólo en la Lambda
python scripts/cambiar_contrasenas_demo.py                 # contraseña nueva para las 4 cuentas de demo
```

## Ejecutar la aplicación

```bash
flask --app src/wsgi.py run          # http://127.0.0.1:5000
```

Cuentas de demostración. En una base recién cargada la contraseña es `Demo2026!`; **en RDS se cambió** con `scripts/cambiar_contrasenas_demo.py` y no se guarda en el repositorio:

| Usuario | Rol | Puede |
| --- | --- | --- |
| `laura.mendez` | Gerente | Todo: cancelaciones, precios con variación mayor a ±30 %, impuestos, cierres y usuarios |
| `ana.torres` | Facturista | Clientes, facturas, emisión, comprobante y tarifas hasta ±30 % |
| `carlos.ruiz` | Cajero | Pagos |
| `diego.salas` | Auxiliar | Sólo consulta |

**Páginas:** Panel · Catálogo y ficha técnica · Clientes · Facturas (borrador → emisión → pagos → comprobante, con pólizas) · Reportes (antigüedad de saldos, ventas, cobranza, balanza, cierres, auditoría de tarifas) · Administración (usuarios e impuestos).

**API REST** en `/api` con `Authorization: Bearer <jwt>`. La especificación completa está en [`docs/openapi.yaml`](docs/openapi.yaml); puedes importarla en Postman o abrirla en https://editor.swagger.io.

```bash
curl -X POST http://127.0.0.1:5000/api/auth/login -H "Content-Type: application/json" \
     -d '{"usuario": "ana.torres", "contrasena": "<contraseña>"}'
curl http://127.0.0.1:5000/api/facturas -H "Authorization: Bearer <token>"
```

## Pruebas de la aplicación

```bash
pytest tests -q
```

Corren contra la base de `.env`, dentro de una transacción que se revierte al terminar cada prueba, así que no dejan datos. Cubren:
- El flujo completo de una factura.
- Permisos por rol.
- JWT alterado, vencido o firmado con otra clave.
- Bloqueo tras 5 intentos fallidos.
- Inyección SQL, XSS, CSRF y redirección abierta.
- Escalada de rol por URL y por API, y tokens falsificados (otra clave o `alg: none`).
- Revocación: una cuenta desactivada o con otro rol pierde su sesión al instante.
- Validación de RFC, correo, teléfono y caracteres de control.
- Que cada página cargue.

## Seguridad (rubro 4 de la rúbrica)

| Riesgo | Mitigación |
| --- | --- |
| Inyección SQL | Sólo parámetros enlazados (`%s`). Los nombres de SP y vistas salen de listas fijas en `db.py` |
| XSS | Jinja escapa todo lo que imprime; CSP `default-src 'self'` sin JavaScript en línea |
| CSRF | Cookie `SameSite=Strict` y token CSRF en cada formulario |
| Autenticación | JWT HS256 de 60 minutos. En la web va en una cookie `HttpOnly`; en la API, como `Bearer` |
| Contraseñas | bcrypt (costo 12) en la aplicación; la base rechaza cualquier valor que no sea un hash (RN-32); bloqueo tras 5 intentos (RN-33) |
| Control de acceso | Rol validado en cada endpoint y otra vez dentro de cada SP con `fn_empleado_puede`. El empleado sale del token, nunca de la petición |
| Sesiones | En cada petición se confirma en la base que la cuenta siga activa y con el mismo rol del token |
| Mínimo privilegio en la base | La Lambda entra como `app_facturacion`: sólo ejecuta los SP expuestos y lee vistas (`database/05_usuario_aplicacion.sql`) |
| Validación de entradas | pydantic: tipos, longitudes, RFC, correo, teléfono; sin caracteres de control |
| Respuestas | `/api/salud` y los errores 500 no revelan la base ni el motor; el detalle va a CloudWatch |
| Secretos | Sólo en `.env` o en las variables de la función Lambda; nada en el código ni en git |
| Otras cabeceras | `X-Frame-Options: DENY`, `nosniff`, `Referrer-Policy`, `Cache-Control: no-store` y HSTS con https |
| Bitácora | Eventos inmutables en DynamoDB (`database/dynamodb/`) |

## Despliegue en AWS (arquitectura objetivo)

API Gateway (HTTP API) → Lambda (Python 3.12, 256 MB, rol `LabRole`, handler `lambda_handler.handler`) → RDS, con DynamoDB para la bitácora. Guía paso a paso en la consola: [`docs/DESPLIEGUE_AWS.md`](docs/DESPLIEGUE_AWS.md). Paquete: `python scripts/empaquetar_lambda.py`.

1. Empaqueta `src/`, las dependencias de `requirements.txt` para Linux y `certs/global-bundle.pem`.
2. Define en la función las variables de `.env.example`, con `COOKIE_SEGURA=true`.

La Lambda debe poder llegar a RDS: hay que ponerla en la VPC de la instancia o abrir el security group a su salida. **Estos pasos crean recursos en AWS y requieren autorización del equipo.**

## Costos en el Learner Lab

La instancia es `db.t3.micro` con 20 GiB gp2. **Detén la instancia RDS al terminar cada sesión de trabajo** (RDS → Databases → Actions → Stop temporarily) para no agotar el crédito.

## Documentación

- [Reporte de avance y diagramas](docs/REPORTE_AVANCE.md)
- [Especificación OpenAPI](docs/openapi.yaml)
- [DynamoDB: tabla de eventos](database/dynamodb/README.md)
- [Rúbrica del proyecto](docs/rubrica_proyecto_final.pdf)
- [Prototipo estático original](docs/prototipo/prototipo_facturacion.html) (referencia de diseño; la app real está en `src/`)

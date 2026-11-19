# Sistema de Facturación y Servicios — Equipo 3

Optativa I · Bases de Datos en la Nube · Proyecto C · AWS Academy Learner Lab

Base de datos de facturación de servicios en **Amazon RDS for PostgreSQL**. Las reglas de negocio (RN-01 a RN-33) viven en procedimientos almacenados: la aplicación escribe sólo con `CALL facturacion.sp_*` y lee de las vistas `facturacion.vw_*`.

| Elemento | Cantidad |
| --- | --- |
| Tablas | 20 (10 del modelo ER del equipo + 10 de extensión para la rúbrica) |
| Procedimientos almacenados | 21 |
| Funciones · vistas · triggers | 11 · 11 · 1 |
| Servicios · características · valores | 100 · 50 · 1,220 |
| Pruebas automatizadas | 63 (todas en OK en RDS PostgreSQL 18.3) |

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

Usuarios y roles: `usuarios` (hash bcrypt, bloqueo tras 5 intentos) y `roles`; los permisos de cada SP se validan con `fn_empleado_puede`.
Cuentas de demostración: `laura.mendez` (Gerente), `ana.torres` (Facturista), `carlos.ruiz` (Cajero), `diego.salas` (Auxiliar), todas con contraseña `Demo2026!` **sólo para la demo**.

## Estructura del repositorio

| Ruta | Contenido |
| --- | --- |
| `database/01_esquema.sql` | DDL: esquema `facturacion`, tablas, restricciones e índices |
| `database/02_procedimientos.sql` | Procedimientos almacenados, funciones y vistas |
| `database/03_datos.sql` | DML: catálogos (100 servicios, 50 características) y escenarios de ejemplo |
| `database/04_pruebas.sql` | Verificación de mínimos y de cada regla de negocio |
| `database/resultado_pruebas.txt` | Última corrida de las pruebas |
| `scripts/cargar_bd.ps1` · `scripts/cargar_bd.sh` | Despliegue automatizado (Windows · macOS/Linux) |
| `docs/` | Reporte de avance con diagramas (ER, arquitectura, C4, secuencia) y rúbrica |
| `frontend/prototipo_facturacion.html` | Prototipo navegable de la interfaz (aún sin conexión a la API) |

## Requisitos

- Cliente de PostgreSQL 16 o superior (`psql`, `pg_dump`).
  Windows: `winget install PostgreSQL.PostgreSQL.18` · macOS: `brew install libpq` · Ubuntu: `sudo apt install postgresql-client`
- Acceso de red a la instancia RDS: el security group sólo acepta IPs autorizadas (`/32`). Consulta tu IP con `curl https://checkip.amazonaws.com` y pide que se agregue.

## Configuración

1. Descarga el certificado de AWS RDS (no se sube a git):
   ```bash
   mkdir -p certs
   curl -o certs/global-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
   ```
2. Copia `.env.example` como `.env` y escribe la contraseña en `PGPASSWORD`. **`.env` nunca se sube a git.**
   Si el Learner Lab cambia el endpoint de RDS, sólo se actualiza `PGHOST` en `.env`.

## Cargar la base y correr las pruebas

```powershell
# Windows
.\scripts\cargar_bd.ps1                    # carga 01 → 02 → 03 y corre 04
.\scripts\cargar_bd.ps1 -SoloPruebas       # sólo pruebas (no modifica datos)
.\scripts\cargar_bd.ps1 -Forzar -Respaldo  # respalda con pg_dump, borra y recarga
.\scripts\cargar_bd.ps1 -EnvFile .env.local  # otra base, p. ej. un PostgreSQL local
```

```bash
# macOS / Linux
scripts/cargar_bd.sh [--env .env] [--forzar] [--respaldo] [--solo-pruebas]
```

> ⚠️ `01_esquema.sql` empieza con `DROP SCHEMA IF EXISTS facturacion CASCADE`. El script de despliegue se detiene si el esquema ya existe, salvo que se use `-Forzar`.

`04_pruebas.sql` se puede ejecutar las veces que se quiera: cada prueba corre en una subtransacción y no deja datos.

Para cargarlo a mano (por ejemplo en pgAdmin → Query Tool), abre y ejecuta los archivos en orden: `01`, `02`, `03` y después `04`.

## Conectarse con pgAdmin

Host y base de `.env`, puerto 5432, usuario `postgres`. En la pestaña **Parameters**: *SSL mode* = `verify-full` y *Root certificate* = ruta a `certs/global-bundle.pem`.

## Costos en el Learner Lab

La instancia es `db.t3.micro` con 20 GiB gp2. **Detén la instancia RDS al terminar cada sesión de trabajo** (RDS → Databases → Actions → Stop temporarily) para no agotar el crédito.

## Documentación

- [Reporte de avance y diagramas](docs/REPORTE_AVANCE.md)
- [Rúbrica del proyecto](docs/rubrica_proyecto_final.pdf)

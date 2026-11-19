# Sistema de Facturación y Servicios — Equipo 3

Optativa I · Bases de Datos en la Nube · Proyecto C · AWS Academy Learner Lab

Base de datos de facturación de servicios en **Amazon RDS for PostgreSQL**. Las reglas de negocio (RN-xx) viven en procedimientos almacenados: la aplicación escribe sólo con `CALL facturacion.sp_*` y lee de las vistas `facturacion.vw_*`.

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

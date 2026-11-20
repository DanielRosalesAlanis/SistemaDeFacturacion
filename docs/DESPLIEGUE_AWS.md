# Despliegue en AWS: instrucciones para el agente en la consola

> Para: Claude in Chrome, en la consola de AWS del Learner Lab. Sirve también como manual de despliegue del equipo.
> Objetivo: publicar la aplicación Flask del Sistema de Facturación con este flujo:
> **API Gateway (HTTP API) → Lambda (en la VPC de RDS) → RDS PostgreSQL**, más una tabla **DynamoDB** para la bitácora de eventos.

**No se necesita SQL.** La base de datos ya está cargada y probada en RDS (63 de 63 pruebas). No ejecutes nada en la base.

---

## 0. Reglas (leer antes de empezar)

1. **Región:** sólo `us-east-1` (N. Virginia). Cuenta `144808140456`.
2. **No toques** la instancia `db-teachers-mysql` ni ningún recurso que no esté en esta guía.
3. **No crees roles de IAM.** Usa siempre el rol existente **`LabRole`**.
4. **Nunca** agregues reglas de entrada con origen `0.0.0.0/0`.
5. **Secretos:** cuando un paso pida `PGPASSWORD` o `JWT_SECRETO`, **detente y pide al usuario que los escriba él** en el campo. No los escribas en el chat ni en notas.
6. Si un paso falla por permisos (`AccessDenied`, `not authorized`), **detente** y reporta el mensaje exacto. No busques rutas alternativas.
7. A la instancia RDS `db-billing-postgres` sólo se le cambia la protección contra borrado (paso 9). Nada más.
8. Anota cada ID que se cree. Al final hay que reportarlos (paso 11).

## Datos fijos

| Dato | Valor |
| --- | --- |
| Instancia RDS | `db-billing-postgres` |
| Endpoint RDS | `db-billing-postgres.c7aen0lsxvo7.us-east-1.rds.amazonaws.com` |
| Security group de la Lambda | `secg-lambda-facturacion` |
| Usuario de base de la Lambda | `app_facturacion` (paso 6b) |
| VPC de RDS | `vpc-08c8747b2dfc49016` |
| Security group de RDS | `secg-db-facturacion` |
| Paquete de la función | `C:\Users\danro\SistemaDeFacturacion\build\facturacion_lambda.zip` (8.5 MB) |
| Variables de la función | `C:\Users\danro\SistemaDeFacturacion\build\variables_lambda.txt` (lo abre el usuario) |

---

## 1. Verificar la sesión

1. En el Learner Lab, el indicador junto a «AWS» debe estar en **verde**. Si no, pide al usuario que presione *Start Lab* y espere.
2. En la consola, confirma que la región arriba a la derecha sea **N. Virginia (us-east-1)**.
3. RDS → Databases → `db-billing-postgres` debe estar en **Available**. Si está *Stopped*, pide autorización al usuario para iniciarla (*Actions → Start*) y espera a que pase a *Available*.

## 2. Anotar subredes y tablas de rutas de RDS

1. RDS → Databases → `db-billing-postgres` → pestaña **Connectivity & security**.
2. Anota la **VPC** (debe ser `vpc-08c8747b2dfc49016`) y la lista de **Subnets**.
3. Ve a VPC → **Subnets** y filtra por esa VPC. Para cada subred del paso anterior, anota su **Availability Zone** y su **Route table**.
4. Revisa si `secg-db-facturacion` está asignado a otras instancias (EC2 → Security Groups → `secg-db-facturacion`) y repórtalo al usuario. Sólo se agregará una regla del puerto 5432, que no afecta a MySQL (3306).

## 3. Crear la tabla de DynamoDB

DynamoDB → **Create table**:

| Campo | Valor |
| --- | --- |
| Table name | `facturacion-eventos` |
| Partition key | `entidad` · String |
| Sort key | `fecha_evento` · String |
| Table settings | **Customize settings** |
| Read/write capacity settings | **On-demand** |

En **Secondary indexes → Create global index**, crea dos índices:

| Index name | Partition key | Sort key | Attribute projections |
| --- | --- | --- | --- |
| `por_usuario` | `id_usuario` · String | `fecha_evento` · String | All |
| `por_tipo` | `tipo` · String | `fecha_evento` · String | Include: `entidad`, `id_usuario`, `rol` |

Tag opcional: `Proyecto` = `Facturacion-Equipo3`. Presiona **Create table** y espera a que quede **Active**.

## 4. Security group para la Lambda

EC2 → Security Groups → **Create security group**:

| Campo | Valor |
| --- | --- |
| Name | `secg-lambda-facturacion` |
| Description | `Lambda facturacion-app hacia RDS` |
| VPC | `vpc-08c8747b2dfc49016` |
| Inbound rules | **ninguna** |
| Outbound rules | dejar la predeterminada (All traffic) |

Anota el ID (`sg-...`).

## 5. Permitir que la Lambda llegue a RDS

EC2 → Security Groups → `secg-db-facturacion` → **Edit inbound rules** → **Add rule**:

| Type | Port | Source | Description |
| --- | --- | --- | --- |
| PostgreSQL | 5432 | Custom → **`secg-lambda-facturacion`** (el security group del paso 4, no una IP) | `Lambda facturacion-app` |

**No borres ni cambies** la regla que ya existe para la IP del usuario. Guarda.

## 6. Endpoint de VPC para DynamoDB (gratuito)

Dentro de la VPC la Lambda no tiene salida a internet. Para escribir en DynamoDB necesita este endpoint de tipo Gateway, que no cuesta (un NAT Gateway sí costaría; **no lo crees**).

VPC → **Endpoints** → **Create endpoint**:

| Campo | Valor |
| --- | --- |
| Name | `vpce-dynamodb-facturacion` |
| Type / Service category | **AWS services** |
| Service | `com.amazonaws.us-east-1.dynamodb`, **Type: Gateway** (no Interface) |
| VPC | `vpc-08c8747b2dfc49016` |
| Route tables | marca las tablas de rutas anotadas en el paso 2 |
| Policy | Full access |

Crea y anota el ID (`vpce-...`).

## 6b. Usuario de base de datos para la aplicación (mínimo privilegio)

La Lambda **no** se conecta como `postgres` (el usuario maestro). Usa `app_facturacion`, que sólo puede ejecutar los procedimientos que llama la API y leer las vistas `vw_*`; no puede leer ni modificar tablas directamente.

Lo crea el usuario en su computadora, conectado como `postgres` (Git Bash, con las variables de `.env` cargadas):

```bash
psql -X -f database/05_usuario_aplicacion.sql          # al final muestra:  f | t | t
winpty psql -X -c "\password app_facturacion"          # pide la contraseña; sólo envía el hash
```

Esa contraseña va **sólo** en `PGPASSWORD` de la Lambda (paso 7); el `.env` local sigue con `postgres`. Si se vuelve a cargar `02_procedimientos.sql`, hay que repetir el primer comando.

## 7. Crear la función Lambda

Lambda → **Create function** → *Author from scratch*:

| Campo | Valor |
| --- | --- |
| Function name | `facturacion-app` |
| Runtime | **Python 3.12** |
| Architecture | **x86_64** |
| Execution role | **Use an existing role → `LabRole`** |

Después de crearla:

1. **Code → Upload from → .zip file** → sube `C:\Users\danro\SistemaDeFacturacion\build\facturacion_lambda.zip` → **Save**.
2. **Code → Runtime settings → Edit** → Handler: `lambda_handler.handler` → Save.
3. **Configuration → General configuration → Edit** → Memory: **256 MB**, Timeout: **0 min 30 s** → Save.
4. **Configuration → Environment variables → Edit** → agrega exactamente estas variables:

   | Key | Value |
   | --- | --- |
   | `PGHOST` | `db-billing-postgres.c7aen0lsxvo7.us-east-1.rds.amazonaws.com` |
   | `PGPORT` | `5432` |
   | `PGDATABASE` | `billing` |
   | `PGUSER` | `app_facturacion` (paso 6b; nunca `postgres`) |
   | `PGPASSWORD` | **⛔ detente: que la escriba el usuario** (la de `app_facturacion`) |
   | `PGSSLMODE` | `verify-full` |
   | `PGSSLROOTCERT` | `/var/task/certs/global-bundle.pem` |
   | `JWT_SECRETO` | **⛔ detente: que el usuario lo pegue desde `build\variables_lambda.txt`** |
   | `JWT_MINUTOS` | `60` |
   | `COOKIE_SEGURA` | `true` |
   | `DDB_TABLA_EVENTOS` | `facturacion-eventos` |

   No agregues `AWS_REGION`: Lambda la define sola y rechaza esa clave. **No agregues `MOSTRAR_CUENTAS_DEMO`** (mostraría las cuentas de demostración en el login). Guarda.
5. **Configuration → VPC → Edit**:
   - VPC: `vpc-08c8747b2dfc49016`.
   - Subnets: las subredes de RDS anotadas en el paso 2, al menos 2 en zonas distintas.
   - Security groups: **sólo** `secg-lambda-facturacion` (quita el `default` si aparece).
   - Guarda. Tarda 1 o 2 minutos; espera a que el estado diga *Successful*.
6. **Test** → crea un evento llamado `salud` con este JSON y ejecútalo:

   ```json
   {
     "version": "2.0",
     "routeKey": "$default",
     "rawPath": "/api/salud",
     "rawQueryString": "",
     "headers": {"host": "prueba", "x-forwarded-proto": "https"},
     "requestContext": {"http": {"method": "GET", "path": "/api/salud", "sourceIp": "127.0.0.1", "protocol": "HTTP/1.1"}, "stage": "$default"},
     "isBase64Encoded": false
   }
   ```

   **Resultado esperado:** `statusCode: 200` y en `body` el texto `{"base_de_datos":"conectada","estado":"ok"}`.

   | Si ves | Causa probable |
   | --- | --- |
   | `Task timed out` | Falta la regla del paso 5, o las subredes no son las de RDS |
   | `password authentication failed` | `PGPASSWORD` mal escrita; pide al usuario que la corrija |
   | `JWT_SECRETO falta o es muy corto` | Falta la variable del paso 4 |
   | `No module named ...` | Handler mal escrito (debe ser `lambda_handler.handler`) o zip equivocado |

   Si falla, copia el error completo de la pestaña de resultados y detente.

## 8. Crear la API en API Gateway

API Gateway → **Create API** → **HTTP API → Build**:

1. **Integrations → Add integration → Lambda** → región `us-east-1` → función `facturacion-app`.
2. API name: `facturacion-api` → Next.
3. **Configure routes**, deja exactamente estas dos, ambas hacia `facturacion-app`:

   | Method | Resource path |
   | --- | --- |
   | `ANY` | `/` |
   | `ANY` | `/{proxy+}` |

   Si el asistente propuso otra ruta, como `/facturacion-app`, **elimínala**.
4. **Stages** → deja **`$default`** con **Auto-deploy activado**. No uses un nombre de stage como `prod`, porque agregaría un prefijo que rompe las rutas de la aplicación.
5. Create. Anota el **Invoke URL** (`https://xxxxxxxx.execute-api.us-east-1.amazonaws.com`).

## 9. Verificar la aplicación desplegada

Usa el Invoke URL del paso 8 (sin `/` final) como `<URL>`:

1. Abre `<URL>/api/salud` → debe mostrar `{"base_de_datos":"conectada","estado":"ok"}`.
2. Abre `<URL>/login` → debe aparecer la página «Facturación de servicios».
3. La página de login **no** debe mostrar usuarios ni contraseñas. Pide al usuario que inicie sesión como **`ana.torres`** (la contraseña de las cuentas de demostración en RDS no está en el repositorio; se cambió con `scripts/cambiar_contrasenas_demo.py`). Debe aparecer el **Panel** con «Por cobrar» en **$105,449.20**.
4. Ve a **Facturas** → abre **F-000002** → debe mostrar conceptos, pagos, pólizas y el comprobante CFDI.
5. Cierra sesión con **Salir**.
6. DynamoDB → Tables → `facturacion-eventos` → **Explore table items** → deben aparecer eventos `LOGIN_OK` con `entidad` = `USUARIO#2`.

**No crees facturas ni pagos de prueba**: quedarían en la base de la demo.

## 10. Protección contra borrado de RDS

RDS → Databases → `db-billing-postgres` → **Modify**:
1. Marca **Enable deletion protection** y no cambies nada más.
2. Continue → **Apply immediately** → Modify DB instance.

## 11. Reporte final para el usuario

Entrega esta tabla llena:

| Recurso | Valor |
| --- | --- |
| Invoke URL de la aplicación | |
| ARN de la función `facturacion-app` | |
| ID de `secg-lambda-facturacion` | |
| Regla agregada en `secg-db-facturacion` | sí / no |
| ID del endpoint `vpce-dynamodb-facturacion` | |
| ARN de la tabla `facturacion-eventos` | |
| `<URL>/api/salud` respondió conectada | sí / no |
| Login web y panel con $105,449.20 | sí / no |
| Eventos visibles en DynamoDB | sí / no |
| Deletion protection activada | sí / no |
| Problemas encontrados | |

---

## Notas para el equipo (después del despliegue)

- **Costos:** Lambda, API Gateway y DynamoDB On-Demand casi no cuestan sin uso, y el endpoint Gateway de DynamoDB es gratis. Lo que consume crédito es **RDS**: detenlo al terminar cada sesión (*Actions → Stop temporarily*). Mientras esté detenido, la app responderá con error.
- **Actualizar el código:** ejecuta `python scripts/empaquetar_lambda.py` y sube el nuevo `build/facturacion_lambda.zip` en *Code → Upload from*.
- **Si el Learner Lab cambia el endpoint de RDS:** sólo se actualiza `PGHOST` en las variables de la función.
- **Seguridad:** RDS sólo acepta conexiones de la IP del equipo y de las Lambdas con `secg-lambda-facturacion`. La app usa HTTPS (API Gateway), cookies `Secure` y JWT.

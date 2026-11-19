# DynamoDB: bitácora de eventos inmutable

La aplicación escribe un evento por cada operación relevante: inicio de sesión correcto o fallido, factura creada, emitida o cancelada, pago registrado o cancelado, tarifa cambiada, cierre fiscal y alta de usuarios o tasas.

PostgreSQL sigue siendo la fuente de verdad. DynamoDB guarda la bitácora con escritura rápida y sin esquema fijo. Los eventos sólo se agregan: nunca se actualizan ni se borran, y `put_item` usa `attribute_not_exists` para no sobrescribir.

## Diseño de la tabla `facturacion-eventos`

| Elemento | Valor | Para qué |
| --- | --- | --- |
| Capacidad | On-Demand (`PAY_PER_REQUEST`) | Sin costo fijo; requisito del Learner Lab |
| PK `entidad` | `FACTURA#7`, `USUARIO#3`, `SERVICIO#13`, `CIERRE#1`… | Historia completa de un objeto |
| SK `fecha_evento` | `2026-11-19T22:52:11.783+00:00#a1b2c3d4` | Orden cronológico; el sufijo evita choques en el mismo milisegundo |
| GSI `por_usuario` | `id_usuario` + `fecha_evento` | ¿Qué hizo este usuario y cuándo? |
| GSI `por_tipo` | `tipo` + `fecha_evento` | Todos los `LOGIN_FALLIDO` o `FACTURA_CANCELADA` de un periodo |

Atributos de cada evento: `tipo`, `id_usuario`, `rol`, `ip` y `detalle`, que es un mapa con los datos de la operación (nunca contraseñas).

## Patrones de acceso

```bash
# Historia de la factura 7
aws dynamodb query --table-name facturacion-eventos \
  --key-condition-expression "entidad = :e" --expression-attribute-values '{":e":{"S":"FACTURA#7"}}'

# Inicios de sesión fallidos de hoy
aws dynamodb query --table-name facturacion-eventos --index-name por_tipo \
  --key-condition-expression "tipo = :t AND begins_with(fecha_evento, :d)" \
  --expression-attribute-values '{":t":{"S":"LOGIN_FALLIDO"},":d":{"S":"2026-11-19"}}'
```

## Crear la tabla (requiere autorización del equipo: crea un recurso en AWS)

```bash
aws dynamodb create-table --region us-east-1 --cli-input-json file://database/dynamodb/eventos_auditoria.json
```

Después define `DDB_TABLA_EVENTOS=facturacion-eventos` en `.env` o en las variables de la función Lambda. Sin esa variable, la app sólo escribe los eventos en el log. La función necesita el permiso `dynamodb:PutItem` sobre la tabla. Usa el rol `LabRole` del Learner Lab y verifica en IAM que lo incluya; no crees roles con `*`.

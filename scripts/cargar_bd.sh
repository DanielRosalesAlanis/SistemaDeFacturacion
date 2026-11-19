#!/usr/bin/env bash
# Carga la base de facturación (01 → 02 → 03) y corre las pruebas (04).
# Uso: scripts/cargar_bd.sh [--env .env] [--forzar] [--respaldo] [--solo-pruebas]
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE=".env"; FORZAR=0; RESPALDO=0; SOLO_PRUEBAS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="$2"; shift 2 ;;
    --forzar) FORZAR=1; shift ;;
    --respaldo) RESPALDO=1; shift ;;
    --solo-pruebas) SOLO_PRUEBAS=1; shift ;;
    *) echo "Opción desconocida: $1" >&2; exit 2 ;;
  esac
done

[[ -f "$ENV_FILE" ]] || { echo "No existe $ENV_FILE. Copia .env.example y escribe la contraseña." >&2; exit 1; }
# Lee KEY=valor sin interpretar el valor (la contraseña puede tener $ o espacios)
while IFS='=' read -r k v; do
  [[ "$k" =~ ^[A-Z_]+$ ]] && export "$k=$v"
done < <(grep -E '^[A-Z_]+=' "$ENV_FILE" | tr -d '\r')
[[ -n "${PGPASSWORD:-}" ]] || { echo "PGPASSWORD está vacía en $ENV_FILE." >&2; exit 1; }
export PGCLIENTENCODING=UTF8

echo "Destino: $PGUSER@$PGHOST:$PGPORT/$PGDATABASE (ssl=$PGSSLMODE)"
psql -X -q -t -c "select 'Conectado a ' || version();"

if [[ $SOLO_PRUEBAS -eq 0 ]]; then
  existe=$(psql -X -t -A -c "select count(*) from pg_namespace where nspname = 'facturacion';")
  if [[ "$existe" == "1" ]]; then
    [[ $FORZAR -eq 1 ]] || { echo "El esquema facturacion ya existe y 01_esquema.sql lo BORRA. Usa --forzar (y --respaldo)." >&2; exit 1; }
    if [[ $RESPALDO -eq 1 ]]; then
      mkdir -p respaldos
      archivo="respaldos/facturacion_$(date +%Y%m%d_%H%M).dump"
      pg_dump -n facturacion -Fc -f "$archivo" && echo "Respaldo: $archivo"
    fi
  fi
  for f in 01_esquema.sql 02_procedimientos.sql 03_datos.sql; do
    echo "Cargando database/$f ..."
    psql -X -q -v ON_ERROR_STOP=1 -f "database/$f" 2>&1 | grep -vE 'NOTICE|AVISO|DETAIL|DETALLE|^drop cascades' || true
    [[ ${PIPESTATUS[0]} -eq 0 ]] || { echo "Falló $f" >&2; exit 1; }
  done
fi

echo "Corriendo database/04_pruebas.sql ..."
psql -X -f database/04_pruebas.sql > database/resultado_pruebas.txt 2>&1
ok=$(grep -c "NOTICE:  OK" database/resultado_pruebas.txt || true)
malas=$(grep -cE "FALLA|ERROR" database/resultado_pruebas.txt || true)
echo; echo "Pruebas OK: $ok   ·   Fallas/errores: $malas   ·   Detalle en database/resultado_pruebas.txt"
[[ "$malas" -eq 0 ]] || { grep -E "FALLA|ERROR" database/resultado_pruebas.txt; exit 1; }

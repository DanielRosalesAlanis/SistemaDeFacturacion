"""Configuración leída de variables de entorno (archivo .env en local,
variables de la función en AWS Lambda). Nada sensible vive en el código."""
import os
from pathlib import Path

from dotenv import load_dotenv

RAIZ = Path(__file__).resolve().parents[2]


def cargar_entorno() -> None:
    archivo = Path(os.environ.get("ARCHIVO_ENV", RAIZ / ".env"))
    if archivo.exists():
        load_dotenv(archivo, override=False)
    # libpq resuelve rutas relativas contra el directorio actual; se fija la absoluta
    cert = os.environ.get("PGSSLROOTCERT")
    if cert and not Path(cert).is_absolute():
        os.environ["PGSSLROOTCERT"] = str((RAIZ / cert).resolve())


def configuracion() -> dict:
    secreto = os.environ.get("JWT_SECRETO", "")
    if len(secreto) < 32:
        raise RuntimeError("JWT_SECRETO falta o es muy corto (mínimo 32 caracteres). Revisa .env.example.")
    return {
        "JWT_SECRETO": secreto,
        "JWT_MINUTOS": int(os.environ.get("JWT_MINUTOS", "60")),
        "COOKIE_SEGURA": os.environ.get("COOKIE_SEGURA", "true").lower() != "false",
        # Muestra los usuarios de demostración en el login; apagado salvo que se pida
        "MOSTRAR_CUENTAS_DEMO": os.environ.get("MOSTRAR_CUENTAS_DEMO", "false").lower() == "true",
        "AWS_REGION":os.environ.get("AWS_REGION", "us-east-1"),
        "POOL_MAX": int(os.environ.get("POOL_MAX", "5")),
        "MAX_CONTENT_LENGTH": 256 * 1024,          # cuerpo máximo de una petición
        "JSON_SORT_KEYS": False,
    }

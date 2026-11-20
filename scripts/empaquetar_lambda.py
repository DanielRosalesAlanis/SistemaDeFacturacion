"""Empaqueta la aplicación Flask para AWS Lambda (Python 3.12, x86_64).

Uso:  python scripts/empaquetar_lambda.py
Salida: build/facturacion_lambda.zip  (se sube en la consola de Lambda)

- Descarga las dependencias como wheels de Linux (manylinux), aunque se
  ejecute en Windows o macOS.
- boto3 no se incluye: ya viene en el runtime de Lambda.
- Incluye certs/global-bundle.pem para la conexión SSL verify-full a RDS
  (en Lambda: PGSSLROOTCERT=/var/task/certs/global-bundle.pem).
- Usa zipfile con rutas "/" (Compress-Archive de Windows usa "\" y Lambda
  no las reconoce).
"""
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
DESTINO = RAIZ / "build" / "lambda"
ZIP = RAIZ / "build" / "facturacion_lambda.zip"
DEPENDENCIAS = [
    "flask==3.1.*", "psycopg[binary]==3.2.*", "psycopg-pool==3.2.*", "pyjwt==2.10.*",
    "bcrypt==5.0.*", "pydantic==2.*", "python-dotenv==1.*", "apig-wsgi==2.*", "tzdata",
]


def main() -> None:
    cert = RAIZ / "certs" / "global-bundle.pem"
    if not cert.exists():
        sys.exit("Falta certs/global-bundle.pem (ver README, paso Configuración).")
    shutil.rmtree(DESTINO, ignore_errors=True)
    DESTINO.mkdir(parents=True)

    subprocess.run([
        sys.executable, "-m", "pip", "install", "--quiet", "--disable-pip-version-check",
        "--target", str(DESTINO), "--implementation", "cp", "--python-version", "3.12",
        "--only-binary=:all:", "--platform", "manylinux2014_x86_64",
        "--platform", "manylinux_2_28_x86_64", "--platform", "manylinux_2_34_x86_64",
        *DEPENDENCIAS], check=True)

    shutil.copytree(RAIZ / "src" / "app", DESTINO / "app")
    shutil.copy2(RAIZ / "src" / "lambda_handler.py", DESTINO / "lambda_handler.py")
    (DESTINO / "certs").mkdir()
    shutil.copy2(cert, DESTINO / "certs" / "global-bundle.pem")
    for cache in DESTINO.rglob("__pycache__"):
        shutil.rmtree(cache, ignore_errors=True)

    ZIP.unlink(missing_ok=True)
    with zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for archivo in sorted(DESTINO.rglob("*")):
            if archivo.is_file():
                z.write(archivo, archivo.relative_to(DESTINO).as_posix())
    print(f"Paquete: {ZIP}  ({ZIP.stat().st_size / 1_048_576:.1f} MB)")


if __name__ == "__main__":
    main()

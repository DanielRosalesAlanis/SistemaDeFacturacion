"""Cambia la contraseña de las 4 cuentas de demostración en la base de .env.

Uso:  python scripts/cambiar_contrasenas_demo.py

- Pide la nueva contraseña sin mostrarla (getpass); no se escribe en disco,
  en la terminal ni en el historial.
- Guarda un hash bcrypt distinto por cuenta (cada uno con su sal) y
  desbloquea las cuentas.
- Se conecta con el usuario de .env (debe ser el maestro, postgres): el
  usuario restringido de la aplicación no puede modificar la tabla.
- Después escribe la misma contraseña en CONTRASENA_DEMO de tu .env para que
  las pruebas (pytest) puedan iniciar sesión.
"""
import getpass
import sys
from pathlib import Path

import psycopg

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from app.config import cargar_entorno                         # noqa: E402
from app.seguridad import hash_contrasena, validar_politica   # noqa: E402

CUENTAS = ("laura.mendez", "ana.torres", "carlos.ruiz", "diego.salas")


def main() -> None:
    cargar_entorno()
    nueva = getpass.getpass("Nueva contraseña para las 4 cuentas: ")
    if error := validar_politica(nueva):
        sys.exit(error)
    if nueva == "Demo2026!":
        sys.exit("Esa es la contraseña publicada en el repositorio; elige otra.")
    if getpass.getpass("Repítela: ") != nueva:
        sys.exit("No coinciden.")

    with psycopg.connect("") as con:                  # PGHOST, PGUSER, ... de .env
        print(f"Base: {con.info.user}@{con.info.host}/{con.info.dbname}")
        with con.transaction():
            for usuario in CUENTAS:
                n = con.execute(
                    """UPDATE facturacion.usuarios
                          SET contrasena_hash = %s, intentos_fallidos = 0, bloqueado_hasta = NULL
                        WHERE nombre_usuario = %s""", [hash_contrasena(nueva), usuario]).rowcount
                print(f"  {usuario}: {'actualizada' if n else 'NO EXISTE'}")
    print("Listo. Agrega CONTRASENA_DEMO=<la nueva> a tu .env para las pruebas.")


if __name__ == "__main__":
    main()

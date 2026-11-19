"""Adaptador para AWS Lambda detrás de Amazon API Gateway (HTTP API).

Handler de la función: lambda_handler.handler · Runtime: Python 3.12 ·
Memoria: 256 MB · Rol: LabRole. La configuración (PGHOST, PGPASSWORD,
JWT_SECRETO, DDB_TABLA_EVENTOS, ...) se define como variables de entorno
de la función; el certificado de RDS viaja en el paquete (certs/).
"""
from apig_wsgi import make_lambda_handler

from app import create_app

app = create_app()
handler = make_lambda_handler(app, binary_support=True)

"""Punto de entrada WSGI.

Local:      flask --app src/wsgi.py run          (http://127.0.0.1:5000)
Producción: gunicorn --chdir src wsgi:app        (EC2)  ·  src/lambda_handler.py (Lambda)
"""
from app import create_app

app = create_app()

if __name__ == "__main__":
    app.run(debug=False)

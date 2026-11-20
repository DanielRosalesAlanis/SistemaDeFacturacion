"""Validación de entradas (API JSON y formularios web) con pydantic.
Primera línea de defensa: tipos, tamaños y formatos. Las reglas de
negocio (RN-xx) las aplica la base de datos."""
import re
from datetime import date
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

Dinero = Annotated[Decimal, Field(gt=0, max_digits=12, decimal_places=2)]
Id = Annotated[int, Field(gt=0, lt=2_147_483_647)]
_CONTROL = re.compile(r"[\x00-\x1f\x7f]")
_RFC = re.compile(r"^[A-ZÑ&]{3,4}[0-9]{6}[A-Z0-9]{3}$")      # igual que ck_clientes_rfc


class Base(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    @field_validator("*")
    @classmethod
    def sin_caracteres_de_control(cls, v):
        # Todos los campos son de una línea; NUL y otros caracteres de control
        # no tienen uso legítimo (psycopg rechaza NUL con un error 500)
        if isinstance(v, str) and _CONTROL.search(v):
            raise ValueError("contiene caracteres no permitidos")
        return v


class Login(Base):
    usuario: Annotated[str, Field(min_length=3, max_length=50, pattern=r"^[A-Za-z0-9._-]+$")]
    contrasena: Annotated[str, Field(min_length=1, max_length=128)]


class ClienteNuevo(Base):
    nombre: Annotated[str, Field(min_length=1, max_length=100)]
    apellido: Annotated[str | None, Field(max_length=100)] = None
    rfc: Annotated[str, Field(min_length=12, max_length=13)]
    correo: Annotated[str, Field(min_length=6, max_length=100, pattern=r"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$")]
    telefono: Annotated[str | None, Field(min_length=7, max_length=20, pattern=r"^\+?[0-9 ()-]+$")] = None
    direccion: Annotated[str | None, Field(max_length=255)] = None

    @field_validator("rfc")
    @classmethod
    def formato_rfc(cls, v: str) -> str:
        v = v.upper()
        if not _RFC.fullmatch(v):
            raise ValueError("formato de RFC inválido (p. ej. XAXX010101000)")
        return v


class ServicioNuevo(Base):
    id_categoria: Id
    codigo: Annotated[str, Field(min_length=3, max_length=20, pattern=r"^[A-Za-z0-9-]+$")]
    nombre: Annotated[str, Field(min_length=3, max_length=150)]
    descripcion: Annotated[str | None, Field(max_length=255)] = None
    precio: Dinero
    unidad: Literal["Servicio", "Hora", "Mes", "Año", "Evento"]


class ValorCaracteristica(Base):
    valor: Annotated[str, Field(min_length=1, max_length=100)]


class Asignacion(Base):
    """Un elemento de la asignación masiva: exactamente un destino."""
    id_caracteristica: Id
    valor: Annotated[str, Field(min_length=1, max_length=100)]
    id_servicio: Id | None = None
    codigo_servicio: Annotated[str | None, Field(min_length=3, max_length=20, pattern=r"^[A-Za-z0-9-]+$")] = None
    id_categoria: Id | None = None

    @model_validator(mode="after")
    def un_destino(self):
        if sum(x is not None for x in (self.id_servicio, self.codigo_servicio, self.id_categoria)) != 1:
            raise ValueError("indica sólo uno: id_servicio, codigo_servicio o id_categoria")
        return self


class AsignacionMasiva(Base):
    asignaciones: Annotated[list[Asignacion], Field(min_length=1, max_length=500)]

    def como_json(self) -> list[dict]:
        return [a.model_dump(exclude_none=True) for a in self.asignaciones]


class NuevoPrecio(Base):
    precio: Dinero


class EstadoServicio(Base):
    activo: bool


class FacturaNueva(Base):
    id_cliente: Id


class Concepto(Base):
    id_servicio: Id
    cantidad: Annotated[int, Field(gt=0, le=100_000)]
    descuento_pct: Annotated[Decimal, Field(ge=0, le=100, decimal_places=2)] = Decimal("0")


class Emision(Base):
    dias_credito: Annotated[int, Field(ge=0, le=365)] = 30


class Pago(Base):
    id_metodo_pago: Id
    monto: Dinero
    referencia: Annotated[str | None, Field(max_length=50, pattern=r"^[A-Za-z0-9 ._/#-]+$")] = None


class Cierre(Base):
    tipo: Literal["DIARIO", "MENSUAL"]
    fecha: date


class TasaImpuesto(Base):
    clave: Literal["IVA", "ISR"]
    tipo: Literal["TRASLADO", "RETENCION"]
    tasa: Annotated[Decimal, Field(ge=0, lt=1, decimal_places=6)]
    vigente_desde: date


class UsuarioNuevo(Base):
    id_empleado: Id
    nombre_usuario: Annotated[str, Field(min_length=3, max_length=50, pattern=r"^[A-Za-z0-9._-]+$")]
    contrasena: Annotated[str, Field(min_length=10, max_length=128)]
    rol: Literal["Gerente", "Facturista", "Cajero", "Auxiliar"]

    @field_validator("contrasena")
    @classmethod
    def politica(cls, v: str) -> str:
        if not any(c.isalpha() for c in v) or not any(c.isdigit() for c in v):
            raise ValueError("debe combinar letras y números")
        return v


def errores_legibles(exc) -> list[str]:
    """Mensajes de validación sin repetir el valor recibido (podría ser una contraseña)."""
    return [f"{'.'.join(str(p) for p in e['loc']) or 'cuerpo'}: {e['msg']}"
            for e in exc.errors(include_url=False, include_input=False)]

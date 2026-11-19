<#
.SYNOPSIS
  Carga la base de datos de facturación (01 → 02 → 03) y corre las pruebas (04).

.DESCRIPTION
  Lee la conexión de un archivo .env (variables PG*). Nunca escribe credenciales
  en el código. Si el esquema facturacion ya existe, se detiene salvo que se use
  -Forzar, porque 01_esquema.sql lo borra y lo vuelve a crear.

.EXAMPLE
  .\scripts\cargar_bd.ps1                       # carga en la base de .env y prueba
  .\scripts\cargar_bd.ps1 -SoloPruebas          # sólo corre 04_pruebas.sql
  .\scripts\cargar_bd.ps1 -Forzar -Respaldo     # respalda, borra y recarga
  .\scripts\cargar_bd.ps1 -EnvFile .env.local   # otra base (p. ej. servidor local)
#>
param(
    [string]$EnvFile = ".env",
    [switch]$Forzar,
    [switch]$Respaldo,
    [switch]$SoloPruebas
)
$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

# 1. Variables de conexión -------------------------------------------------
if (-not (Test-Path $EnvFile)) { throw "No existe $EnvFile. Copia .env.example como $EnvFile y escribe la contraseña." }
Get-Content $EnvFile -Encoding UTF8 | Where-Object { $_ -match '^\s*([A-Z_]+)=(.*)$' } |
    ForEach-Object { Set-Item "env:$($Matches[1])" $Matches[2].Trim() }
if (-not $env:PGPASSWORD) { throw "PGPASSWORD está vacía en $EnvFile." }
$env:PGCLIENTENCODING = "UTF8"   # en Windows psql usa WIN1252 por defecto

# 2. Herramientas -----------------------------------------------------------
$psql = (Get-Command psql -ErrorAction SilentlyContinue).Source
if (-not $psql) {
    $psql = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $psql) { throw "No se encontró psql. Instala el cliente de PostgreSQL 16 o superior." }
$pgdump = Join-Path (Split-Path $psql) "pg_dump.exe"

function Invoke-Psql([string[]]$argumentos) {
    & $psql -X -v ON_ERROR_STOP=1 @argumentos
    if ($LASTEXITCODE -ne 0) { throw "psql terminó con código $LASTEXITCODE" }
}

Write-Host "Destino: $env:PGUSER@$env:PGHOST`:$env:PGPORT/$env:PGDATABASE (ssl=$env:PGSSLMODE)"
Invoke-Psql @("-q", "-t", "-c", "select 'Conectado a ' || version();")

# 3. Carga ------------------------------------------------------------------
if (-not $SoloPruebas) {
    $existe = (& $psql -X -t -A -c "select count(*) from pg_namespace where nspname = 'facturacion';").Trim()
    if ($existe -eq "1") {
        if (-not $Forzar) {
            throw "El esquema facturacion ya existe y 01_esquema.sql lo BORRA. Vuelve a ejecutar con -Forzar (y -Respaldo si hay datos que conservar)."
        }
        if ($Respaldo) {
            New-Item -ItemType Directory -Force respaldos | Out-Null
            $archivo = "respaldos/facturacion_" + (Get-Date -Format "yyyyMMdd_HHmm") + ".dump"
            & $pgdump -n facturacion -Fc -f $archivo
            if ($LASTEXITCODE -ne 0) { throw "Falló el respaldo" }
            Write-Host "Respaldo: $archivo"
        }
    }
    foreach ($f in "01_esquema.sql", "02_procedimientos.sql", "03_datos.sql") {
        Write-Host "Cargando database/$f ..."
        cmd /c "`"$psql`" -X -q -v ON_ERROR_STOP=1 -f database/$f 2>&1" |
            Where-Object { $_ -notmatch 'NOTICE|AVISO|DETAIL|DETALLE|^drop cascades' }
        if ($LASTEXITCODE -ne 0) { throw "Falló database/$f (código $LASTEXITCODE)" }
    }
}

# 4. Pruebas ----------------------------------------------------------------
Write-Host "Corriendo database/04_pruebas.sql ..."
$salida = "database/resultado_pruebas.txt"
cmd /c "`"$psql`" -X -f database/04_pruebas.sql > $salida 2>&1"
$texto = Get-Content $salida -Encoding UTF8
$ok    = ($texto | Select-String 'NOTICE:  OK').Count
$malas = @($texto | Select-String 'FALLA|ERROR')
Write-Host ""
Write-Host "Pruebas OK: $ok   ·   Fallas/errores: $($malas.Count)   ·   Detalle en $salida"
if ($malas.Count -gt 0) { $malas | ForEach-Object { Write-Host $_ -ForegroundColor Red }; exit 1 }

# Carga datos de DEMOSTRACIÓN en la base de Docker (docentes, estudiantes, cursos y matrículas)
# para poder probar la evaluación docente, el calendario, etc. con la base nueva y vacía.
#
#   .\docker\datos-demo.ps1
#
# Es idempotente (no duplica), solo crea cuentas con prefijo "demo_" y nunca toca lo que ya existe.
# Las contraseñas se guardan SOLO cifradas. Contraseña de las cuentas demo: Demo#2026
# Requiere Node.js y haber ejecutado "npm install" una vez en la carpeta Backend.

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

function Leer-Env([string]$clave, [string]$defecto = '') {
    $archivo = Join-Path $raiz '.env'
    if (-not (Test-Path $archivo)) { throw "No existe .env. Ejecuta primero  .\docker\iniciar.ps1" }
    $linea = Get-Content $archivo -Encoding UTF8 | Where-Object { $_ -match "^\s*$clave=" } | Select-Object -First 1
    if (-not $linea) { return $defecto }
    return ($linea -replace "^\s*$clave=", '').Trim()
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Se necesita Node.js (https://nodejs.org) para cargar los datos demo.' }
if (-not (Test-Path (Join-Path $raiz 'Backend\node_modules'))) { throw 'Falta instalar dependencias: cd Backend; npm install' }

$estado = (& docker compose ps db --format '{{.Health}}' 2>$null)
if ($estado -ne 'healthy') { throw 'La base de datos de Docker no está lista. Ejecuta  .\docker\iniciar.ps1  y vuelve a intentarlo.' }

# Se conecta por el puerto publicado en ESTE equipo (127.0.0.1:3307), nunca a una base remota.
$env:DB_HOST = '127.0.0.1'
$env:DB_PORT = Leer-Env 'DB_HOST_PORT' '3307'
$env:DB_USER = Leer-Env 'DB_USER'
$env:DB_PASS = Leer-Env 'DB_PASS'
$env:DB_NAME = Leer-Env 'DB_NAME' 'bdgesacad'
$env:NODE_ENV = 'development'

Push-Location (Join-Path $raiz 'Backend')
try {
    & node scripts/seed_dev.js --yes
    if ($LASTEXITCODE -ne 0) { throw "La carga de datos falló (código $LASTEXITCODE)." }
} finally { Pop-Location }

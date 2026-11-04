# Levanta GESACAD completo (base de datos + API + web) con Docker, en un solo paso.
#
#   .\docker\iniciar.ps1                 # crea .env si no existe, construye y arranca
#   .\docker\iniciar.ps1 -SoloGenerar    # solo crea el archivo .env (no arranca nada)
#   .\docker\iniciar.ps1 -WebLocal       # compila la web en TU equipo y la sirve con nginx:
#                                        # no descarga la imagen de Flutter (varios GB); ideal
#                                        # con internet lento
#   -NoAbrir                             # no abre el navegador al terminar
#
# Si no existe el archivo .env, lo crea con contraseñas ALEATORIAS (nada de valores de
# ejemplo) y muestra una sola vez la contraseña del administrador. Si ya existe, NO lo toca.

param([switch]$SoloGenerar, [switch]$WebLocal, [switch]$NoAbrir)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz
$archivo = if ($env:ENV_FILE) { $env:ENV_FILE } else { Join-Path $raiz '.env' }

function Nuevo-Texto([int]$largo) {
    # Solo letras y números: no estorban en YAML, en la terminal ni en MySQL.
    $caracteres = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
    $bytes = New-Object byte[] $largo
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    -join ($bytes | ForEach-Object { $caracteres[$_ % $caracteres.Length] })
}

$claveAdmin = $null
if (Test-Path $archivo) {
    Write-Host "Ya existe ${archivo}: se conserva tal cual." -ForegroundColor Yellow
} else {
    $claveAdmin = 'Gs' + (Nuevo-Texto 12) + '-9'   # cumple la política: mayúscula, minúscula, número y símbolo
    $jwt = -join ((1..48) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    $plantilla = Get-Content (Join-Path $raiz '.env.docker.example') -Raw -Encoding UTF8
    $valores = @{
        'MYSQL_ROOT_PASSWORD'      = Nuevo-Texto 24
        'DB_PASS'                  = Nuevo-Texto 24
        'JWT_SECRET'               = $jwt
        'ADMIN_BOOTSTRAP_PASSWORD' = $claveAdmin
    }
    foreach ($k in $valores.Keys) {
        $plantilla = [regex]::Replace($plantilla, "(?m)^$k=.*$", { param($m) "$k=$($valores[$k])" })
    }
    # UTF-8 SIN marca BOM: con BOM, Docker leería mal el nombre de la primera variable.
    [System.IO.File]::WriteAllText($archivo, $plantilla, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "Creado ${archivo} con contraseñas aleatorias." -ForegroundColor Green
}

if ($SoloGenerar) { if ($claveAdmin) { Write-Host "Administrador: admin / $claveAdmin" }; return }

& docker compose version *> $null
if ($LASTEXITCODE -ne 0) { throw 'No se encontró "docker compose". Instala Docker Desktop y vuelve a intentarlo.' }
& docker info *> $null
if ($LASTEXITCODE -ne 0) { throw 'El motor de Docker no responde. Abre Docker Desktop, espera a que diga "Engine running" y repite.' }

$ErrorActionPreference = 'Continue'   # docker/flutter escriben su progreso en stderr: no es un error
if ($WebLocal) {
    # Dirección de la API que usará el navegador (la misma variable que lee compose).
    $api = 'http://localhost:8081'
    $linea = Get-Content $archivo -Encoding UTF8 | Where-Object { $_ -match '^API_BASE_URL=(.+)$' } | Select-Object -First 1
    if ($linea) { $api = ($linea -replace '^API_BASE_URL=', '').Trim() }
    $flutter = if (Test-Path 'C:\flutter_sdk\bin\flutter.bat') { 'C:\flutter_sdk\bin\flutter.bat' } else { 'flutter' }
    Write-Host "`nCompilando la web en este equipo (API: $api)..." -ForegroundColor Cyan
    & $flutter build web --release "--dart-define=API_BASE_URL=$api"
    if ($LASTEXITCODE -ne 0) { throw "flutter build web falló (código $LASTEXITCODE)." }
    $env:WEB_TARGET = 'web-local'
}

Write-Host "`nConstruyendo y arrancando (la primera vez tarda varios minutos)..." -ForegroundColor Cyan
& docker compose up -d --build --wait
if ($LASTEXITCODE -ne 0) { throw "docker compose falló (código $LASTEXITCODE). Revisa:  docker compose logs" }

Write-Host "`n=========================================================" -ForegroundColor Green
Write-Host ' GESACAD está en marcha' -ForegroundColor Green
Write-Host '   Aplicación web : http://localhost:5000'
Write-Host '   API            : http://localhost:8081/health'
if ($claveAdmin) {
    Write-Host "`n   Administrador  : admin"
    Write-Host "   Contraseña     : $claveAdmin   (anótala: solo se muestra ahora; también está en .env)"
}
Write-Host "`n   Ver registros  : docker compose logs -f"
Write-Host '   Detener        : docker compose down'
Write-Host '=========================================================' -ForegroundColor Green

# Abre la aplicación (el puerto 5000, no el 8081 de la API) para no confundirse de dirección.
if (-not $NoAbrir) { try { Start-Process 'http://localhost:5000' } catch { } }

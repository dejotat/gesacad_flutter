# GESACAD - arranca el sistema completo con las imagenes publicadas en Docker Hub.
#
#   .\iniciar.ps1            crea .env (contrasenas aleatorias) si no existe, descarga y arranca
#   .\iniciar.ps1 -NoAbrir   no abre el navegador al terminar
#
# Requisito: Docker Desktop en marcha. No necesita el codigo fuente.
# (Archivo solo con caracteres ASCII a proposito: asi funciona igual en cualquier PowerShell.)

param([switch]$NoAbrir)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$archivo = Join-Path $PSScriptRoot '.env'

function Nuevo-Texto([int]$largo) {
    $caracteres = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
    $bytes = New-Object byte[] $largo
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    -join ($bytes | ForEach-Object { $caracteres[$_ % $caracteres.Length] })
}

$previo = $ErrorActionPreference; $ErrorActionPreference = 'Continue'   # PowerShell 5.1 trata el stderr de docker como error
& docker info *> $null
$dockerOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $previo
if (-not $dockerOk) { throw 'Docker no responde. Abre Docker Desktop, espera a que diga "Engine running" y repite.' }

$claveAdmin = $null
if (Test-Path $archivo) {
    Write-Host 'Ya existe .env: se conserva tal cual.' -ForegroundColor Yellow
} else {
    $claveAdmin = 'Gs' + (Nuevo-Texto 12) + '-9'     # cumple la politica: mayuscula, minuscula, numero y simbolo
    $lineas = @(
        'DB_USER=gesacad',
        ('DB_PASS=' + (Nuevo-Texto 24)),
        ('MYSQL_ROOT_PASSWORD=' + (Nuevo-Texto 24)),
        ('JWT_SECRET=' + (Nuevo-Texto 48)),
        'ADMIN_BOOTSTRAP_USER=admin',
        ('ADMIN_BOOTSTRAP_PASSWORD=' + $claveAdmin)
    )
    # UTF-8 SIN BOM: con BOM Docker lee mal la primera variable.
    [System.IO.File]::WriteAllText($archivo, (($lineas -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host 'Creado .env con contrasenas aleatorias.' -ForegroundColor Green
}

# Si el paquete trae las imagenes (gesacad-imagenes.tar), se cargan sin internet ni cuenta de Docker Hub.
$tar = Join-Path $PSScriptRoot 'gesacad-imagenes.tar'
if (Test-Path $tar) {
    # "docker images -q" no escribe nada si la imagen falta (docker image inspect daria un error fatal en PowerShell 5.1).
    $yaCargada = (& docker images -q dejota0712/gesacad-web:1.0 | Out-String).Trim()
    if (-not $yaCargada) {
        Write-Host "`nCargando las imagenes incluidas en el paquete (1 a 3 minutos)..." -ForegroundColor Cyan
        & docker load -i $tar
        if ($LASTEXITCODE -ne 0) { throw 'No se pudieron cargar las imagenes de gesacad-imagenes.tar.' }
    }
}

Write-Host "`nArrancando (si no hay imagenes locales se descargan de Docker Hub)..." -ForegroundColor Cyan
& docker compose up -d --wait
if ($LASTEXITCODE -ne 0) { throw 'docker compose fallo. Revisa:  docker compose logs' }

Write-Host "`n=========================================================" -ForegroundColor Green
Write-Host ' GESACAD esta en marcha' -ForegroundColor Green
Write-Host '   Aplicacion web : http://localhost:5000'
Write-Host '   API (datos)    : http://localhost:8081/health'
if ($claveAdmin) {
    Write-Host "`n   Usuario        : admin"
    Write-Host "   Contrasena     : $claveAdmin   (anotala: solo se muestra ahora; tambien esta en .env)"
}
Write-Host "`n   Ver registros  : docker compose logs -f"
Write-Host '   Detener        : docker compose down        (conserva los datos)'
Write-Host '   Borrar datos   : docker compose down -v'
Write-Host '=========================================================' -ForegroundColor Green

if (-not $NoAbrir) { try { Start-Process 'http://localhost:5000' } catch { } }

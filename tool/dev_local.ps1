<#
.SYNOPSIS
  Arranca el entorno de desarrollo LOCAL de GESACAD en el orden correcto:
  MySQL -> backend (API) -> app Flutter en Chrome con la URL del backend.

.DESCRIPTION
  Evita los tres errores más comunes:
    1. Abrir el puerto de la API (8081) esperando ver la app. La API solo
       responde datos; la APP se abre en http://localhost:5000.
    2. Ejecutar la app sin apuntarla al backend local (usaría producción).
    3. Olvidar iniciar MySQL o el backend antes de la app.

.EXAMPLE
  .\tool\dev_local.ps1                 # todo: backend + app
  .\tool\dev_local.ps1 -SoloBackend    # solo MySQL + backend
  .\tool\dev_local.ps1 -WebPort 5050   # otro puerto para la app
#>
param(
  [int]$ApiPort = 8081,
  [int]$WebPort = 5000,
  [switch]$SoloBackend
)

$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $root 'Backend'
# En Windows la ruta del SDK con espacios rompe un build hook: se usa la junción si existe.
$flutter = if (Test-Path 'C:\flutter_sdk\bin\flutter.bat') { 'C:\flutter_sdk\bin\flutter.bat' } else { 'flutter' }

function Test-Api {
  try { (Invoke-WebRequest "http://localhost:$ApiPort/health" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200 }
  catch { $false }
}
function Test-PuertoOcupado([int]$Port) {
  [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

Write-Host "`n== GESACAD · entorno local ==" -ForegroundColor Cyan

# 1. MySQL ------------------------------------------------------------------
$svc = Get-Service -Name '*mysql*' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $svc) {
  Write-Host "[!] No encontré un servicio de MySQL. Instálalo o inícialo manualmente." -ForegroundColor Yellow
} elseif ($svc.Status -ne 'Running') {
  Write-Host "Iniciando MySQL ($($svc.Name))..."
  try { Start-Service $svc.Name } catch {
    Write-Host "[x] No pude iniciar MySQL (requiere permisos de administrador). Ábrelo desde Servicios." -ForegroundColor Red; exit 1
  }
} else { Write-Host "[ok] MySQL activo ($($svc.Name))" -ForegroundColor Green }

# 2. Backend ----------------------------------------------------------------
if (Test-Api) {
  Write-Host "[ok] Backend ya activo en http://localhost:$ApiPort" -ForegroundColor Green
} else {
  if (Test-PuertoOcupado $ApiPort) {
    Write-Host "[x] El puerto $ApiPort está ocupado por otro programa que no es el backend de GESACAD." -ForegroundColor Red
    Write-Host "    Ciérralo o usa otro puerto: .\tool\dev_local.ps1 -ApiPort 8082"; exit 1
  }
  if (-not (Test-Path (Join-Path $backend 'node_modules'))) {
    Write-Host "Instalando dependencias del backend (primera vez)..."
    Push-Location $backend; npm install; Pop-Location
  }
  Write-Host "Iniciando backend en una ventana nueva (puerto $ApiPort)..."
  Start-Process powershell -ArgumentList '-NoExit', '-Command',
    "`$env:PORT=$ApiPort; Set-Location '$backend'; `$Host.UI.RawUI.WindowTitle='GESACAD backend :$ApiPort'; npm start"
  $listo = $false
  1..40 | ForEach-Object { if (-not $listo) { Start-Sleep -Milliseconds 750; $listo = Test-Api } }
  if (-not $listo) { Write-Host "[x] El backend no respondió. Revisa su ventana: ¿error de MySQL o del .env?" -ForegroundColor Red; exit 1 }
  Write-Host "[ok] Backend activo en http://localhost:$ApiPort" -ForegroundColor Green
}

# 3. Con qué cuenta entrar ---------------------------------------------------
Write-Host "`nUsuarios de la base LOCAL (cada servidor tiene los suyos):" -ForegroundColor Cyan
Push-Location $backend; try { node scripts/list_users.js } catch { } ; Pop-Location

if ($SoloBackend) { Write-Host "Listo. Solo backend (-SoloBackend)."; exit 0 }

# 4. App --------------------------------------------------------------------
if (Test-PuertoOcupado $WebPort) {
  Write-Host "[!] El puerto $WebPort de la app está ocupado; usa -WebPort <otro>." -ForegroundColor Yellow
}
Write-Host "`nLa APP se abrirá en  http://localhost:$WebPort   (NO en :$ApiPort, que es solo la API)" -ForegroundColor Cyan
Push-Location $root
& $flutter run -d chrome --web-port $WebPort "--dart-define=API_BASE_URL=http://localhost:$ApiPort"
Pop-Location

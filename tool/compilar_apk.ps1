# Compila el APK de GESACAD con las notificaciones push activadas.
#
# Uso (PowerShell, desde la carpeta del proyecto):
#     .\tool\compilar_apk.ps1            # APK de producción (release)
#     .\tool\compilar_apk.ps1 -Debug     # APK de depuración
#
# Lee la configuración de Firebase de "firebase.env" (cópialo de firebase.env.example).
# Si el archivo no existe o está vacío, compila SIN push: la app funciona igual con su bandeja.
# Usa el acceso directo C:\flutter_sdk porque la ruta del SDK tiene espacios (ver CLAUDE.md).

param([switch]$Debug)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

$flutter = 'C:\flutter_sdk\bin\flutter.bat'
if (-not (Test-Path $flutter)) { throw "No se encontró $flutter (acceso directo al SDK de Flutter)." }

$defines = @()
$archivo = Join-Path $raiz 'firebase.env'
if (Test-Path $archivo) {
    foreach ($linea in Get-Content $archivo -Encoding UTF8) {
        $l = $linea.Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        $i = $l.IndexOf('=')
        if ($i -lt 1) { continue }
        $clave = $l.Substring(0, $i).Trim()
        $valor = $l.Substring($i + 1).Trim()
        if ($valor) { $defines += "--dart-define=$clave=$valor" }
    }
}

$obligatorias = 'FIREBASE_API_KEY', 'FIREBASE_APP_ID', 'FIREBASE_MESSAGING_SENDER_ID', 'FIREBASE_PROJECT_ID'
$faltan = $obligatorias | Where-Object { -not ($defines -match "--dart-define=$_=") }
if ($faltan) {
    Write-Warning ("Faltan en firebase.env: " + ($faltan -join ', ') + ". Se compila SIN notificaciones push.")
} else {
    Write-Host 'Firebase configurado: el APK incluirá las notificaciones push.' -ForegroundColor Green
}

$modo = if ($Debug) { '--debug' } else { '--release' }
& $flutter build apk $modo @defines
if ($LASTEXITCODE -ne 0) { throw "La compilación falló (código $LASTEXITCODE)." }

$sub = if ($Debug) { 'debug' } else { 'release' }
Write-Host "`nListo: build\app\outputs\flutter-apk\app-$sub.apk" -ForegroundColor Green

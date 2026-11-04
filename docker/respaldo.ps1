# Copia de seguridad y restauración de la base de datos de Docker.
#
#   .\docker\respaldo.ps1                          # crea respaldos\gesacad-AAAAMMDD-HHMMSS.sql
#   .\docker\respaldo.ps1 -Restaurar <archivo.sql> # reemplaza el contenido por el del respaldo
#
# Los respaldos contienen datos personales y contraseñas cifradas: la carpeta respaldos\ está en
# .gitignore. NUNCA la subas a un repositorio ni la compartas.

param([string]$Restaurar)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

$estado = (& docker compose ps db --format '{{.Health}}' 2>$null)
if ($estado -ne 'healthy') { throw 'La base de datos de Docker no está lista. Ejecuta  .\docker\iniciar.ps1  primero.' }

if ($Restaurar) {
    if (-not (Test-Path $Restaurar)) { throw "No existe el archivo: $Restaurar" }
    $ruta = (Resolve-Path $Restaurar).Path
    Write-Host "Se REEMPLAZARÁ el contenido actual de la base por el de:`n  $ruta" -ForegroundColor Yellow
    $r = Read-Host 'Escribe SI para continuar'
    if ($r -ne 'SI') { Write-Host 'Cancelado, no se cambió nada.'; return }
    & docker compose cp $ruta db:/tmp/restaurar.sql
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo copiar el archivo al contenedor.' }
    # El archivo se ejecuta DENTRO del contenedor: así no pasa por la codificación de PowerShell.
    & docker compose exec -T db sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot --default-character-set=utf8mb4 "$MYSQL_DATABASE" < /tmp/restaurar.sql && rm -f /tmp/restaurar.sql'
    if ($LASTEXITCODE -ne 0) { throw 'La restauración falló.' }
    & docker compose restart backend | Out-Null
    Write-Host 'Restauración completa. Se reinició la API para que tome los datos.' -ForegroundColor Green
    return
}

$carpeta = Join-Path $raiz 'respaldos'
New-Item -ItemType Directory -Force $carpeta | Out-Null
$destino = Join-Path $carpeta ("gesacad-{0}.sql" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
& docker compose exec -T db sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqldump -uroot --single-transaction --routines --default-character-set=utf8mb4 "$MYSQL_DATABASE" > /tmp/respaldo.sql'
if ($LASTEXITCODE -ne 0) { throw 'No se pudo generar el respaldo.' }
& docker compose cp db:/tmp/respaldo.sql $destino
if ($LASTEXITCODE -ne 0) { throw 'No se pudo copiar el respaldo al equipo.' }
& docker compose exec -T db rm -f /tmp/respaldo.sql | Out-Null
Write-Host "Respaldo creado: $destino" -ForegroundColor Green

# Copia la base de datos de la NUBE (p. ej. Clever Cloud) a la base de Docker.
#
#   .\docker\migrar-desde-nube.ps1
#
# La base de la nube SOLO SE LEE (mysqldump): no se modifica nada allí. Lo que cambia es la base
# de Docker, que pasa a ser una copia INDEPENDIENTE: lo que agregues después NO llega a la nube.
#
# Pasos: pide los datos de conexión (la contraseña no se muestra ni se guarda) → hace un
# respaldo de la base de Docker actual → descarga la copia de la nube → pide confirmación →
# la restaura en Docker → muestra cuántas filas tiene cada tabla → reinicia la API.
#
# Los archivos .sql quedan en respaldos\ (fuera de git): contienen datos personales.
# Requiere que Docker esté en marcha (.\docker\iniciar.ps1).
#
# Opciones avanzadas: -BaseDestino <nombre> (restaurar en otra base de Docker), -SinPreguntar,
# y las variables de entorno MIGRACION_PASS (contraseña) o parámetros -OrigenHost/-OrigenPuerto/
# -OrigenUsuario/-OrigenBase para no escribirlos.

param(
    [string]$OrigenHost,
    [string]$OrigenPuerto,
    [string]$OrigenUsuario,
    [string]$OrigenBase,
    [string]$BaseDestino,
    [switch]$SinPreguntar
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

$estado = (& docker compose ps db --format '{{.Health}}' 2>$null)
if ($estado -ne 'healthy') { throw 'La base de datos de Docker no está lista. Ejecuta  .\docker\iniciar.ps1  y vuelve a intentarlo.' }

function Preguntar([string]$texto, [string]$valor, [string]$defecto = '') {
    if ($valor) { return $valor }
    $sufijo = if ($defecto) { " [$defecto]" } else { '' }
    $r = Read-Host "$texto$sufijo"
    if ([string]::IsNullOrWhiteSpace($r)) { return $defecto }
    return $r.Trim()
}

# Si existe el archivo .env.nube (copia de .env.nube.example; está en .gitignore) se leen de ahí los
# datos de conexión: así no hay que escribirlos ni pegarlos en ningún chat.
$archivoNube = Join-Path $raiz '.env.nube'
if (Test-Path $archivoNube) {
    $datos = @{}
    foreach ($linea in (Get-Content $archivoNube -Encoding UTF8)) {
        if ($linea -match '^\s*(NUBE_[A-Z]+)=(.*)$') { $datos[$Matches[1]] = $Matches[2].Trim() }
    }
    if (-not $OrigenHost)    { $OrigenHost    = $datos['NUBE_HOST'] }
    if (-not $OrigenPuerto)  { $OrigenPuerto  = $datos['NUBE_PORT'] }
    if (-not $OrigenUsuario) { $OrigenUsuario = $datos['NUBE_USER'] }
    if (-not $OrigenBase)    { $OrigenBase    = $datos['NUBE_DB'] }
    if (-not $env:MIGRACION_PASS -and $datos['NUBE_PASS']) { $env:MIGRACION_PASS = $datos['NUBE_PASS'] }
    Write-Host 'Usando los datos de .env.nube' -ForegroundColor DarkGray
}

Write-Host "`nDatos de la base de la NUBE (solo se lee de ella):" -ForegroundColor Cyan
$OrigenHost    = Preguntar 'Servidor (host)' $OrigenHost
$OrigenPuerto  = Preguntar 'Puerto' $OrigenPuerto '3306'
$OrigenUsuario = Preguntar 'Usuario' $OrigenUsuario
$OrigenBase    = Preguntar 'Nombre de la base' $OrigenBase
if (-not $OrigenHost -or -not $OrigenUsuario -or -not $OrigenBase) { throw 'Faltan datos de conexión.' }

if ($env:MIGRACION_PASS) { $clave = $env:MIGRACION_PASS }
else {
    $seguro = Read-Host 'Contraseña (no se muestra)' -AsSecureString
    $clave = [System.Net.NetworkCredential]::new('', $seguro).Password
}
if (-not $clave) { throw 'Falta la contraseña.' }

$carpeta = Join-Path $raiz 'respaldos'
New-Item -ItemType Directory -Force $carpeta | Out-Null
$marca = Get-Date -Format 'yyyyMMdd-HHmmss'

# ── 1) Respaldo de la base de Docker ANTES de tocarla ────────────────────────
$envBase = '${MYSQL_DATABASE}'   # la base configurada en el contenedor (la expande sh)
if ($BaseDestino) {
    if ($BaseDestino -notmatch '^[A-Za-z0-9_]+$') { throw 'BaseDestino solo admite letras, números y guion bajo.' }
    $envBase = $BaseDestino
}
Write-Host "`n[1/4] Respaldo de la base actual de Docker..." -ForegroundColor Cyan
$previo = Join-Path $carpeta "antes-de-migrar-$marca.sql"
& docker compose exec -T db sh -c "MYSQL_PWD=`$MYSQL_ROOT_PASSWORD mysqldump -uroot --single-transaction --routines --default-character-set=utf8mb4 $envBase > /tmp/previo.sql"
if ($LASTEXITCODE -ne 0) { throw 'No se pudo respaldar la base de Docker (¿existe la base destino?). No se cambió nada.' }
& docker compose cp db:/tmp/previo.sql $previo | Out-Null
& docker compose exec -T db rm -f /tmp/previo.sql | Out-Null
Write-Host "      Guardado: $previo" -ForegroundColor DarkGray

# ── 2) Descarga de la copia desde la nube (solo lectura) ─────────────────────
Write-Host "`n[2/4] Descargando la copia desde $OrigenHost (solo lectura)..." -ForegroundColor Cyan
$nube = Join-Path $carpeta "nube-$marca.sql"
# La contraseña viaja por variable de entorno (no en la línea de comandos).
$env:MYSQL_PWD = $clave
try {
    $argsDump = @(
        'run', '--rm', '-e', 'MYSQL_PWD', '-v', "${carpeta}:/salida", 'mysql:8.4',
        'sh', '-c',
        "mysqldump -h '$OrigenHost' -P '$OrigenPuerto' -u '$OrigenUsuario' --single-transaction --no-tablespaces --skip-lock-tables --set-gtid-purged=OFF --routines --default-character-set=utf8mb4 '$OrigenBase' > /salida/nube-$marca.sql"
    )
    & docker @argsDump
    $codigo = $LASTEXITCODE
} finally {
    Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
    $clave = $null
}
if ($codigo -ne 0 -or -not (Test-Path $nube) -or (Get-Item $nube).Length -lt 200) {
    throw 'No se pudo descargar la copia de la nube. Revisa servidor, puerto, usuario, contraseña y que tu IP tenga acceso. No se cambió nada en Docker.'
}
$tablas = (Select-String -Path $nube -Pattern '^CREATE TABLE ' | Measure-Object).Count
Write-Host ("      Copia lista: {0:N0} KB, {1} tablas." -f ((Get-Item $nube).Length / 1KB), $tablas) -ForegroundColor DarkGray
if ($tablas -eq 0) { throw 'La copia no contiene tablas: se cancela para no vaciar la base de Docker.' }

# ── 3) Confirmación y restauración en Docker ─────────────────────────────────
Write-Host "`n[3/4] Restauración en la base de Docker" -ForegroundColor Cyan
Write-Host '      Se REEMPLAZARÁN las tablas de la base de Docker por las de la nube.' -ForegroundColor Yellow
Write-Host '      (La nube no se modifica. Hay respaldo de lo actual en el archivo de arriba.)' -ForegroundColor Yellow
if (-not $SinPreguntar) {
    $r = Read-Host '      Escribe SI para continuar'
    if ($r -ne 'SI') { Write-Host 'Cancelado: no se cambió nada en Docker.'; return }
}
& docker compose cp $nube db:/tmp/nube.sql | Out-Null
$restaura = "MYSQL_PWD=`$MYSQL_ROOT_PASSWORD mysql -uroot --default-character-set=utf8mb4 $envBase < /tmp/nube.sql && rm -f /tmp/nube.sql"
& docker compose exec -T db sh -c $restaura
if ($LASTEXITCODE -ne 0) { throw "La restauración falló. Puedes volver atrás con:  .\docker\respaldo.ps1 -Restaurar `"$previo`"" }

# ── 4) Verificación ──────────────────────────────────────────────────────────
Write-Host "`n[4/4] Filas por tabla en Docker:" -ForegroundColor Cyan
# Sin comillas dobles internas (PowerShell 5.1 las pierde al llamar a docker) y sin tubería (anteponería un BOM).
$conteo = "export MYSQL_PWD=`$MYSQL_ROOT_PASSWORD; for t in `$(mysql -uroot -N -e 'SHOW TABLES' $envBase); do echo `$t: `$(printf 'SELECT COUNT(*) FROM %s;' `$t | mysql -uroot -N $envBase) filas; done"
& docker compose exec -T db sh -c $conteo

# Usuarios que quedaron en Docker, por rol (sin nombres ni contraseñas): deben ser los de la nube.
Write-Host "`nUsuarios en Docker por rol (deben ser los de la nube):" -ForegroundColor Cyan
$usuarios = "export MYSQL_PWD=`$MYSQL_ROOT_PASSWORD; mysql -uroot -N -e 'SELECT rol, COUNT(*) FROM users GROUP BY rol' $envBase"
& docker compose exec -T db sh -c $usuarios

if (-not $BaseDestino) {
    & docker compose restart backend | Out-Null
    Write-Host "`nListo. Se reinició la API: completa sola lo que falte (columnas nuevas, cifrado de contraseñas antiguas)." -ForegroundColor Green
    Write-Host 'Entra a http://localhost:5000 con tus usuarios de siempre (el "admin" inicial de Docker ya no existe: lo reemplazó la copia).' -ForegroundColor Green
    Write-Host 'Opcional: borra ADMIN_BOOTSTRAP_USER y ADMIN_BOOTSTRAP_PASSWORD de tu .env; con un Admin existente no hacen nada, pero ya no hacen falta.' -ForegroundColor DarkGray
}
Write-Host "Copia de la nube guardada en: $nube  (contiene datos personales: no la subas a git)" -ForegroundColor DarkGray
Remove-Item Env:\MIGRACION_PASS -ErrorAction SilentlyContinue

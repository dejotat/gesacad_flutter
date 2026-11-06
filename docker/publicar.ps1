# Publica las imágenes de GESACAD (base, API y web) en Docker Hub.
#
#   docker login                                          # una vez; la contraseña la escribes TÚ
#   .\docker\publicar.ps1 -Usuario tu_usuario             # construye, etiqueta y MUESTRA lo que subiría
#   .\docker\publicar.ps1 -Usuario tu_usuario -Subir      # además hace el docker push
#   .\docker\publicar.ps1 -Usuario tu_usuario -Version 1.1 -Subir
#
# Sin -Subir NO se publica nada (solo se prepara). Las imágenes no contienen secretos ni datos:
# el .env, los respaldos y los volcados .sql quedan fuera. Las imágenes de Docker Hub son PÚBLICAS
# (salvo que el repositorio se cree como privado en la web de Docker Hub).
#
# La web se publica compilada para hablar con http://localhost:8081 (mismo equipo que Docker).

param(
    [Parameter(Mandatory = $true)][string]$Usuario,
    [string]$Version = '1.0',
    [switch]$Subir
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

if ($Usuario -cnotmatch '^[a-z0-9]{4,30}$') { throw 'El usuario de Docker Hub son 4-30 letras minúsculas o números.' }
$previo = $ErrorActionPreference; $ErrorActionPreference = 'Continue'   # PowerShell 5.1 trata el stderr de docker como error
& docker info *> $null
$dockerOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $previo
if (-not $dockerOk) { throw 'El motor de Docker no responde. Inícialo y repite.' }

Write-Host "`n[1/3] Construyendo la imagen de la base de datos..." -ForegroundColor Cyan
& docker build -f docker/db.Dockerfile -t gesacad-db:latest Backend/db
if ($LASTEXITCODE -ne 0) { throw 'Falló la construcción de la imagen de la base de datos.' }

# La API y la web: se usan las ya construidas por docker compose. Si faltan, se construyen.
foreach ($img in 'gesacad-backend:latest', 'gesacad-web:latest') {
    if (-not ((& docker images -q $img | Out-String).Trim())) { throw "Falta la imagen $img. Ejecuta primero  .\docker\iniciar.ps1" }
}

Write-Host "`n[2/3] Etiquetando como $Usuario/*:$Version y :latest..." -ForegroundColor Cyan
$nombres = 'db', 'backend', 'web'
foreach ($n in $nombres) {
    foreach ($tag in $Version, 'latest') {
        & docker tag "gesacad-$n`:latest" "$Usuario/gesacad-$n`:$tag"
        if ($LASTEXITCODE -ne 0) { throw "No se pudo etiquetar gesacad-$n." }
    }
}
& docker images --format '  {{.Repository}}:{{.Tag}}  {{.Size}}' | Select-String "^  $Usuario/gesacad"

if (-not $Subir) {
    Write-Host "`nListo para publicar, pero NO se subió nada. Para subir:" -ForegroundColor Yellow
    Write-Host "  .\docker\publicar.ps1 -Usuario $Usuario -Version $Version -Subir" -ForegroundColor Yellow
    return
}

Write-Host "`n[3/3] Subiendo a Docker Hub (necesitas haber hecho 'docker login')..." -ForegroundColor Cyan
foreach ($n in $nombres) {
    foreach ($tag in $Version, 'latest') {
        & docker push "$Usuario/gesacad-$n`:$tag"
        if ($LASTEXITCODE -ne 0) { throw "Falló el push de gesacad-$n`:$tag (¿hiciste docker login? ¿el usuario es correcto?)" }
    }
}

Write-Host "`nPublicado. Quien quiera ejecutarlo necesita la carpeta docker\entrega (compose.yaml + iniciar.ps1):" -ForegroundColor Green
Write-Host "  Imágenes: $Usuario/gesacad-db · gesacad-backend · gesacad-web  (versión $Version)" -ForegroundColor Green
Write-Host "  .\iniciar.ps1   (o: docker compose up -d --wait)" -ForegroundColor Green
Write-Host "Páginas: https://hub.docker.com/r/$Usuario/gesacad-web  ·  /gesacad-backend  ·  /gesacad-db" -ForegroundColor Green

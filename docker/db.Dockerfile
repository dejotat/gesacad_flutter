# syntax=docker/dockerfile:1
# =============================================================================
# GESACAD · Base de datos (MySQL 8.4 con el esquema base ya incluido)
# =============================================================================
# Para PUBLICAR: quien descargue las imágenes no tiene el repositorio, así que el esquema base
# (solo estructura, sin datos ni cuentas) va DENTRO de esta imagen. MySQL lo ejecuta una sola vez,
# cuando el volumen está vacío; el resto de tablas las crea el servidor al arrancar.
#
#   docker build -f docker/db.Dockerfile -t gesacad-db:latest Backend/db
# (el contexto es solo la carpeta Backend/db: no entra nada más al build)
# =============================================================================
FROM mysql:8.4

COPY 01-esquema.sql /docker-entrypoint-initdb.d/001-esquema.sql

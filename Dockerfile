# syntax=docker/dockerfile:1
# =============================================================================
# GESACAD · Aplicación web (Flutter compilado + nginx)
# =============================================================================
#   docker build -t gesacad-web --build-arg API_BASE_URL=http://localhost:8081 .
#   docker run -p 8080:8080 gesacad-web
#
# Dos formas de obtener la web (se elige con --target; en compose, con WEB_TARGET):
#   produccion (por defecto)  compila DENTRO de Docker con Flutter. Es lo reproducible, pero la
#                             imagen de Flutter pesa varios GB: la primera vez tarda en descargarse.
#   web-local                 usa la carpeta build/web ya compilada en tu equipo
#                             (flutter build web). Solo descarga nginx (~15 MB): ideal con
#                             internet lento. El script docker/iniciar.ps1 -WebLocal lo hace solo.
# En ambos casos se sirve con nginx sin privilegios (no root, puerto 8080).
# =============================================================================

# ── Etapa 1: compilar ────────────────────────────────────────────────────────
FROM ghcr.io/cirruslabs/flutter:3.41.2 AS compilacion

WORKDIR /app

# Primero solo los archivos de dependencias: mientras no cambien, esta capa (lenta) se reutiliza.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

# Dirección de la API que usará el navegador (se graba en la compilación).
ARG API_BASE_URL=https://gesacad-backend.onrender.com
# --no-web-resources-cdn: el motor de dibujo (CanvasKit, ~7 MB) se sirve desde nuestro nginx
# (comprimido y en caché) en vez de descargarse de un CDN externo en cada carga en frío.
RUN flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=${API_BASE_URL}

# ── Base común: nginx con la configuración de la aplicación ──────────────────
FROM nginxinc/nginx-unprivileged:1.27-alpine AS base-nginx

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY docker/security-headers.inc /etc/nginx/conf.d/security-headers.inc

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:8080/ || exit 1

# ── web-local: sirve lo ya compilado en tu equipo ────────────────────────────
FROM base-nginx AS web-local
COPY build/web /usr/share/nginx/html

# ── produccion (por defecto = última etapa): sirve lo compilado dentro de Docker ──
FROM base-nginx AS produccion
COPY --from=compilacion /app/build/web /usr/share/nginx/html

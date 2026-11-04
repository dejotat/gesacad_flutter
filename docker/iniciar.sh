#!/usr/bin/env bash
# Levanta GESACAD completo (base de datos + API + web) con Docker, en un solo paso.
#
#   ./docker/iniciar.sh                  # crea .env si no existe, construye y arranca
#   ./docker/iniciar.sh --solo-generar   # solo crea el archivo .env (no arranca nada)
#   ./docker/iniciar.sh --web-local      # compila la web en TU equipo y la sirve con nginx:
#                                        # no descarga la imagen de Flutter (varios GB)
#
# Si no existe el archivo .env, lo crea con contraseñas ALEATORIAS (nada de valores de
# ejemplo) y muestra una sola vez la contraseña del administrador. Si ya existe, NO lo toca.
set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$raiz"
archivo="${ENV_FILE:-$raiz/.env}"

# Solo letras y números: no estorban en YAML, en la terminal ni en MySQL.
nuevo_texto() { LC_ALL=C tr -dc 'a-km-zA-HJ-NP-Z2-9' </dev/urandom | head -c "$1"; }

clave_admin=""
if [ -f "$archivo" ]; then
  echo "Ya existe ${archivo}: se conserva tal cual."
else
  clave_admin="Gs$(nuevo_texto 12)-9"   # cumple la política: mayúscula, minúscula, número y símbolo
  jwt="$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c 48)"
  sed -e "s|^MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=$(nuevo_texto 24)|" \
      -e "s|^DB_PASS=.*|DB_PASS=$(nuevo_texto 24)|" \
      -e "s|^JWT_SECRET=.*|JWT_SECRET=$jwt|" \
      -e "s|^ADMIN_BOOTSTRAP_PASSWORD=.*|ADMIN_BOOTSTRAP_PASSWORD=$clave_admin|" \
      .env.docker.example > "$archivo"
  echo "Creado ${archivo} con contraseñas aleatorias."
fi

if [ "${1:-}" = "--solo-generar" ]; then
  [ -n "$clave_admin" ] && echo "Administrador: admin / $clave_admin"
  exit 0
fi

command -v docker >/dev/null || { echo 'No se encontró "docker". Instálalo y vuelve a intentarlo.'; exit 1; }
docker info >/dev/null 2>&1 || { echo 'El motor de Docker no responde. Inícialo y repite.'; exit 1; }

if [ "${1:-}" = "--web-local" ]; then
  api="$(grep -E '^API_BASE_URL=' "$archivo" | head -1 | cut -d= -f2-)"; api="${api:-http://localhost:8081}"
  echo; echo "Compilando la web en este equipo (API: $api)..."
  flutter build web --release "--dart-define=API_BASE_URL=$api"
  export WEB_TARGET=web-local
fi

echo; echo "Construyendo y arrancando (la primera vez tarda varios minutos)..."
docker compose up -d --build --wait

echo
echo "========================================================="
echo " GESACAD está en marcha"
echo "   Aplicación web : http://localhost:5000"
echo "   API            : http://localhost:8081/health"
if [ -n "$clave_admin" ]; then
  echo
  echo "   Administrador  : admin"
  echo "   Contraseña     : $clave_admin   (anótala: solo se muestra ahora; también está en .env)"
fi
echo
echo "   Ver registros  : docker compose logs -f"
echo "   Detener        : docker compose down"
echo "========================================================="

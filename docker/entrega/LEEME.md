# GESACAD con Docker (sin el código fuente)

Sistema de gestión académica (Unicomfacauca): base de datos MySQL, API Node.js y aplicación web.
Las imágenes están publicadas en Docker Hub por **dejota0712**:

- `dejota0712/gesacad-web` · aplicación web
- `dejota0712/gesacad-backend` · API
- `dejota0712/gesacad-db` · MySQL con el esquema base

## Para verlo en otro equipo

1. Instala **Docker Desktop** (https://www.docker.com/products/docker-desktop) y ábrelo hasta que diga *Engine running*.
2. Copia esta carpeta (`compose.yaml` e `iniciar.ps1`) al equipo.
3. En PowerShell, dentro de la carpeta:
   ```
   .\iniciar.ps1
   ```
   Descarga las imágenes, crea un archivo `.env` con contraseñas aleatorias y arranca todo.
4. Se abre **http://localhost:5000**. Entra con el usuario `admin` y la contraseña que muestra el script
   (se muestra una sola vez; también queda en `.env`).

Linux/Mac: crea `.env` a mano (ver la cabecera de `compose.yaml`) y ejecuta `docker compose up -d --wait`.

## Qué verás

La base nace **vacía** con el administrador inicial. Desde la app (Usuarios y Cursos) puedes crear
docentes, estudiantes y cursos. No incluye datos reales de nadie.

## Detalles

- Solo escucha en `localhost` (puertos 5000 web, 8081 API, 3307 base). No se expone a la red.
- La web está compilada para hablar con `http://localhost:8081`: funciona en el equipo donde corre Docker.
- Detener conservando datos: `docker compose down` · Borrar también los datos: `docker compose down -v`.
- Subir archivos (entregas) requiere credenciales de Cloudinary en `.env`
  (`CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`); sin ellas todo funciona menos subir archivos.

# Pruebas de caja negra

Casos de prueba funcionales de GESACAD, organizados por caso de uso.

> **Revisión:** los mensajes de **inicio de sesión** (CU-01) y de **contraseña/usuario en gestión
> de usuarios** (CU-02) se contrastaron con el código el 2026-11-06. Las demás filas (CU-04 y
> CU-05) provienen de la versión original y no se han vuelto a contrastar; solo CE-06 se
> actualizó según el modo sin conexión (las entregas sin red se encolan).
>
> Las pruebas automáticas están en `test/` (app) y `Backend/test/` (API); ver el
> [README](../README.md#pruebas-e-integración-continua).

## CU-01 — Inicio de sesión (RF01)

| ID    | Condición de prueba                  | Resultado esperado                                          |
|-------|--------------------------------------|-------------------------------------------------------------|
| CP-01 | Usuario vacío                        | "El usuario es obligatorio"                                 |
| CP-02 | Contraseña vacía                     | "La contraseña es obligatoria"                              |
| CP-03 | Usuario = "   " (solo espacios)      | "El usuario es obligatorio" (se recorta antes de validar)   |
| CP-04 | Usuario = "ab" (< 3 caracteres)      | "Mínimo 3 caracteres"                                       |
| CP-05 | Usuario = 51 caracteres              | "Máximo 50 caracteres"                                      |
| CP-06 | Contraseña = "ab" (< 3 caracteres)   | "Contraseña muy corta"                                      |
| CP-07 | Credenciales incorrectas             | "Usuario o contraseña incorrectos. Verifica tus datos."     |
| CP-08 | Servidor apagado / timeout           | Mensaje de conexión; con datos en caché se sigue en modo sin conexión |
| CP-09 | Contraseña con símbolos (`p@$$#/`)   | Inicio exitoso (viaja en el cuerpo del `POST /auth/login`, no en la URL) |
| CP-10 | Credenciales Admin válidas           | Navega a `AdminHome`                                        |
| CP-11 | Credenciales Teacher válidas         | Navega a `TeacherHome`                                      |
| CP-12 | Credenciales Student válidas         | Navega a `StudentHome`                                      |
| CP-13 | 8 intentos fallidos seguidos         | La API responde `429` con `Retry-After`                     |
| CP-14 | Token vencido o sesión revocada      | La app vuelve al login indicando el motivo                  |

## CU-02 — Gestión de usuarios (RF03)

| ID    | Condición de prueba                  | Resultado esperado                                          |
|-------|--------------------------------------|-------------------------------------------------------------|
| GU-01 | Nombre de usuario vacío              | "Requerido"                                                 |
| GU-02 | Nombre < 3 caracteres                | "Mínimo 3 caracteres"                                       |
| GU-03 | Nombre > 50 caracteres               | "Máximo 50 caracteres"                                      |
| GU-04 | Nombre duplicado                     | "Ya existe un usuario con ese nombre"                       |
| GU-05 | Contraseña vacía al crear            | "Requerido"                                                 |
| GU-06 | Contraseña fuera de 8–64 caracteres  | "Entre 8 y 64 caracteres"                                   |
| GU-07 | Contraseña sin mayúscula             | "Debe incluir una mayúscula"                                |
| GU-08 | Contraseña sin minúscula             | "Debe incluir una minúscula"                                |
| GU-09 | Contraseña sin número                | "Debe incluir un número"                                    |
| GU-10 | Contraseña sin símbolo               | "Debe incluir un símbolo (!@#$%...)"                        |
| GU-11 | Contraseña que contiene el usuario   | El servidor la rechaza (la barra de seguridad indica "Falta: no usar tu usuario") |
| GU-12 | Eliminar profesor con cursos         | Diálogo de advertencia antes de eliminar                    |

## CU-04 — Crear actividad (RF06, RF07)

| ID    | Condición de prueba                   | Resultado esperado                                         |
|-------|---------------------------------------|------------------------------------------------------------|
| CA-01 | Título vacío                          | "Campo requerido"                                          |
| CA-02 | Descripción vacía                     | "Campo requerido"                                          |
| CA-03 | Ponderado vacío                       | "Requerido"                                                |
| CA-04 | Ponderado = 0 o > 100                 | "Entre 1 y 100"                                            |
| CA-05 | Ponderado > disponible en el curso    | SnackBar rojo con el máximo disponible                     |
| CA-06 | Fecha/hora de cierre ≤ inicio         | "La fecha y hora de cierre deben ser posteriores"          |
| CA-07 | Ponderado disponible = 0 %            | Banner rojo, botón deshabilitado                           |

## CU-05 — Entrega de tareas (RF08)

| ID    | Condición de prueba                | Resultado esperado                                        |
|-------|------------------------------------|-----------------------------------------------------------|
| CE-01 | Plazo de la actividad vencido      | Botón deshabilitado, banner rojo visible                  |
| CE-02 | Actividad ya entregada             | Sección "Tu entrega" visible, estado "Entregado"          |
| CE-03 | Archivo de 6 MB (> 5 MB)           | "El archivo no puede superar 5 MB"                        |
| CE-04 | Tipo de archivo no permitido       | El selector solo muestra extensiones válidas              |
| CE-05 | Archivo válido + servidor OK       | Snackbar verde + estado actualizado                       |
| CE-06 | Archivo válido + sin conexión      | La entrega queda en la cola y se envía sola al volver la red |
| CE-07 | Cancelar el selector de archivos   | No ocurre ninguna acción                                  |

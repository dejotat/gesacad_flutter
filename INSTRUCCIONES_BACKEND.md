# Cambios requeridos en el backend (server.js en Railway)

---

## 1. Agregar 4 endpoints nuevos en server.js

Abre tu `server.js` local y agrega estas rutas **ANTES** de la línea:
```
app.get('/users/:username/:password', ...)
```

### Endpoint: obtener solo estudiantes
```javascript
// Retorna todos los usuarios con rol 'Student' (para matricular en cursos)
app.get('/users/getStudents', (req, res) => {
  const sql = 'SELECT id, username, rol FROM users WHERE rol = ?';
  db.query(sql, ['Student'], (err, result) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(result);
  });
});
```

### Endpoint: obtener solo profesores
```javascript
// Retorna todos los usuarios con rol 'Teacher' (para asignar a cursos)
app.get('/users/getTeachers', (req, res) => {
  const sql = 'SELECT id, username, rol FROM users WHERE rol = ?';
  db.query(sql, ['Teacher'], (err, result) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(result);
  });
});
```

### Endpoint: obtener TODOS los cursos (para el panel Admin)
```javascript
// Retorna todos los cursos del sistema (usado en Gestión de Cursos del Admin)
app.get('/courses/getCourses', (req, res) => {
  const sql = 'SELECT id, name, courseCode FROM courses ORDER BY name ASC';
  db.query(sql, (err, result) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(result);
  });
});
```

### Endpoint: guardar comentario del estudiante al entregar tarea
Encuentra la ruta `app.post('/courses/activities/addResource/:activityId', ...)` en
tu `server.js` y agrega la lectura del campo `comment`:

```javascript
// Dentro del handler de addResource, después de guardar el archivo en Cloudinary:
const comment = req.body.comment || '';

// En el INSERT/UPDATE a la tabla resolutions, agrega el campo comment:
// Ejemplo de cómo debería quedar el INSERT:
const sql = `
  INSERT INTO resolutions (activityId, userId, resolution, dateResolution, comment)
  VALUES (?, ?, ?, NOW(), ?)
  ON DUPLICATE KEY UPDATE
    resolution = VALUES(resolution),
    dateResolution = NOW(),
    comment = VALUES(comment)
`;
db.query(sql, [activityId, userId, fileUrl, comment], (err) => { ... });
```

---

## 2. SQL en Railway MySQL (ejecutar una sola vez)

Ejecuta esto en Railway → MySQL → **Query** (pestaña):

```sql
-- ── Agregar columna de comentario a la tabla de resoluciones ──────────────
-- (Solo ejecutar si la columna no existe todavía)
ALTER TABLE resolutions
  ADD COLUMN IF NOT EXISTS comment TEXT DEFAULT NULL;

-- ── Matricular al admin (jorge, id=6) en todos los cursos existentes ──────
-- Esto permite que el admin vea sus cursos en Gestión de Cursos
-- mientras el endpoint /courses/getCourses no esté disponible.
INSERT IGNORE INTO registration (userId, courseId)
  SELECT 6, id FROM courses;

-- ── Matricular a tilin (Profesor, id=2) en los 3 primeros cursos ─────────
INSERT IGNORE INTO registration (userId, courseId) VALUES (2, 1), (2, 2), (2, 3);

-- ── Matricular a ana (Estudiante, id=3) en los 3 primeros cursos ─────────
INSERT IGNORE INTO registration (userId, courseId) VALUES (3, 1), (3, 2), (3, 3);

-- ── Matricular a johan (Estudiante, id=4) en los 3 primeros cursos ───────
INSERT IGNORE INTO registration (userId, courseId) VALUES (4, 1), (4, 2), (4, 3);
```

> **IMPORTANTE**: El `INSERT IGNORE INTO registration (userId, courseId) SELECT 6, id FROM courses`
> agrega al admin jorge (id=6) en TODOS los cursos existentes.
> Esto es el workaround inmediato para que vea los cursos en la app.

---

## 3. Después de editar server.js

```bash
cd "C:\Users\JORGE TECHNOLOGY\Desktop\PROYECTO FINAL SW\gesacad_flutter\Backend"
git add server.js
git commit -m "agregar endpoints getStudents, getTeachers, getCourses; guardar comentario en resolutions"
git push origin master
```

Railway redesplegará automáticamente en ~2 minutos.

---

## 4. Resumen de qué funciona SIN los cambios del backend

La app Flutter tiene fallbacks automáticos para cuando los endpoints no existen:

| Funcionalidad | Con backend actualizado | Sin actualizar (fallback) |
|---|---|---|
| Cargar profesores en Crear Curso | ✅ /users/getTeachers | ✅ /users/getUsers + filtrar |
| Cargar estudiantes en Crear Curso | ✅ /users/getStudents | ✅ /users/getUsers + filtrar |
| Ver todos los cursos (Admin) | ✅ /courses/getCourses | ⚠️ Solo cursos donde admin fue registrado |
| Comentario estudiante → profesor | ✅ Con columna comment | ❌ El comentario se pierde |
| Abrir archivo DOCX entregado | ✅ Google Docs Viewer | ✅ Google Docs Viewer (ya corregido) |

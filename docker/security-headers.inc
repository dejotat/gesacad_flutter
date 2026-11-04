# Cabeceras de seguridad. Se incluyen en CADA location que use add_header: en nginx, un
# add_header dentro de un location descarta los del nivel superior (por eso no basta ponerlas
# una sola vez en server).
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

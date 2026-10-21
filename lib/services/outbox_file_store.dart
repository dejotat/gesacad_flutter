import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// Dónde se guardan los archivos de las entregas que esperan conexión.
///
/// Los bytes no caben en `SharedPreferences` (límite de ~5 MB en web y
/// serialización costosa), así que se guardan aparte y la operación pendiente
/// solo conserva una referencia ([save] devuelve ese identificador).
abstract class OutboxFileStore {
  /// Guarda [bytes] y devuelve la referencia para recuperarlos.
  Future<String> save(String id, String fileName, Uint8List bytes);

  /// Devuelve los bytes o `null` si ya no existen.
  Future<Uint8List?> read(String ref);

  Future<void> delete(String ref);

  /// Implementación adecuada a la plataforma: archivos en Android/iOS y
  /// memoria en web (el navegador no ofrece un sistema de archivos).
  factory OutboxFileStore.platform() =>
      kIsWeb ? MemoryOutboxStore() : FileSystemOutboxStore();
}

/// Archivos en el directorio privado de la app (sobreviven al cierre de la app).
class FileSystemOutboxStore implements OutboxFileStore {
  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}outbox');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Nombre seguro: solo se usa el id y la extensión, nunca el nombre del
  /// usuario (evita rutas relativas como `../`).
  String _safeName(String id, String fileName) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot >= 0
        ? fileName.substring(dot).replaceAll(RegExp(r'[^A-Za-z0-9.]'), '')
        : '';
    return '$id$ext';
  }

  @override
  Future<String> save(String id, String fileName, Uint8List bytes) async {
    final d = await _dir();
    final f = File('${d.path}${Platform.pathSeparator}${_safeName(id, fileName)}');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  @override
  Future<Uint8List?> read(String ref) async {
    final f = File(ref);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> delete(String ref) async {
    try {
      final f = File(ref);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// Archivos en memoria: se pierden al recargar la página (limitación de web),
/// pero permiten sincronizar si la conexión vuelve con la pestaña abierta.
/// También se usa en las pruebas.
class MemoryOutboxStore implements OutboxFileStore {
  final Map<String, Uint8List> _files = {};

  @override
  Future<String> save(String id, String fileName, Uint8List bytes) async {
    _files[id] = bytes;
    return id;
  }

  @override
  Future<Uint8List?> read(String ref) async => _files[ref];

  @override
  Future<void> delete(String ref) async => _files.remove(ref);
}

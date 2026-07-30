// Servidor HTTP mínimo para reenviar un archivo LOCAL del móvil a la TV por
// la LAN: el móvil sirve el archivo en /f (con soporte de Range para que el
// player pueda hacer seek) y la TV lo reproduce por URL, sin usar Internet.
//
// Un solo archivo activo a la vez: cada `serve()` cierra el server anterior.
import 'dart:async';
import 'dart:io';

/// Rango de bytes ya resuelto (absoluto, ambos extremos inclusive) contra la
/// longitud del archivo.
class _ByteRange {
  final int start;
  final int end;
  const _ByteRange(this.start, this.end);
}

class LocalFileServer {
  HttpServer? _server;
  File? _file;
  int? _length;
  StreamSubscription<HttpRequest>? _sub;

  /// Levanta el server y sirve [filePath] en `/f`. Devuelve la URL LAN que
  /// hay que enviar en el LOAD del canal de casting, p.ej.
  /// `http://192.168.1.23:41231/f`.
  ///
  /// Si ya había un archivo sirviéndose, lo detiene primero (un solo archivo
  /// activo a la vez).
  Future<String> serve(String filePath) async {
    await stop();

    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('El archivo no existe', filePath);
    }

    _file = file;
    _length = await file.length();

    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    _sub = server.listen(
      (request) {
        // No dejamos que un request roto tumbe el server completo.
        unawaited(_handle(request).catchError((_) async {
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          } catch (_) {
            // El socket ya pudo haberse cerrado del lado del cliente.
          }
        }));
      },
      onError: (_) {},
      cancelOnError: false,
    );

    final ip = await lanIp() ?? InternetAddress.loopbackIPv4.address;
    return 'http://$ip:${server.port}/f';
  }

  /// IP LAN (Wi-Fi u otra interfaz no-loopback) del dispositivo, o null si no
  /// se encuentra ninguna IPv4 utilizable.
  Future<String?> lanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {
      // Sin permisos o sin red: dejamos que el caller decida el fallback.
    }
    return null;
  }

  /// Cierra el server (si había uno) y suelta la referencia al archivo.
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    final server = _server;
    _server = null;
    _file = null;
    _length = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final file = _file;
    final length = _length;
    final response = request.response;

    if (file == null || length == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    if (request.uri.path != '/f') {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    if (request.method != 'GET' && request.method != 'HEAD') {
      response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }

    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = _contentTypeFor(file.path);

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    var end = length - 1;
    var isPartial = false;

    if (rangeHeader != null) {
      final range = _parseRange(rangeHeader, length);
      if (range == null) {
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        await response.close();
        return;
      }
      start = range.start;
      end = range.end;
      isPartial = true;
    }

    final contentLength = end - start + 1;
    response.statusCode =
        isPartial ? HttpStatus.partialContent : HttpStatus.ok;
    response.headers.contentLength = contentLength;
    if (isPartial) {
      response.headers
          .set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
    }

    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    // openRead(start, end+1) abre un RandomAccessFile acotado al rango y lo
    // cierra solo al agotar el stream (o si el cliente corta la conexión).
    final stream = file.openRead(start, end + 1);
    try {
      await response.addStream(stream);
    } catch (_) {
      // Cliente cortó la conexión a mitad de transmisión: no hay más que
      // hacer, el stream de openRead ya libera el file handle.
    }
    await response.close();
  }

  /// Parsea `Range: bytes=start-end` (también `bytes=start-` y `bytes=-N`).
  /// Devuelve null si el header es inválido o el rango no es satisfacible
  /// contra [length] (el caller responde 416 en ese caso).
  _ByteRange? _parseRange(String header, int length) {
    const prefix = 'bytes=';
    if (!header.startsWith(prefix)) return null;
    final spec = header.substring(prefix.length).trim();
    if (spec.isEmpty || spec.contains(',')) {
      // No soportamos múltiples rangos en una sola respuesta.
      return null;
    }

    final dash = spec.indexOf('-');
    if (dash < 0) return null;

    final startStr = spec.substring(0, dash).trim();
    final endStr = spec.substring(dash + 1).trim();

    int start;
    int end;
    if (startStr.isEmpty) {
      // Rango de sufijo: los últimos N bytes.
      if (endStr.isEmpty) return null;
      final suffixLength = int.tryParse(endStr);
      if (suffixLength == null || suffixLength <= 0) return null;
      start = length - suffixLength;
      if (start < 0) start = 0;
      end = length - 1;
    } else {
      final parsedStart = int.tryParse(startStr);
      if (parsedStart == null || parsedStart < 0) return null;
      start = parsedStart;
      if (endStr.isEmpty) {
        end = length - 1;
      } else {
        final parsedEnd = int.tryParse(endStr);
        if (parsedEnd == null || parsedEnd < 0) return null;
        end = parsedEnd;
      }
    }

    if (length == 0) return null;
    if (start >= length || start > end) return null;
    if (end >= length) end = length - 1;
    return _ByteRange(start, end);
  }

  ContentType _contentTypeFor(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : '';
    switch (ext) {
      case 'mp4':
      case 'm4v':
        return ContentType('video', 'mp4');
      case 'mkv':
        return ContentType('video', 'x-matroska');
      case 'avi':
        return ContentType('video', 'x-msvideo');
      case 'mov':
        return ContentType('video', 'quicktime');
      case 'webm':
        return ContentType('video', 'webm');
      case 'ts':
        return ContentType('video', 'mp2t');
      case '3gp':
        return ContentType('video', '3gpp');
      case 'mp3':
        return ContentType('audio', 'mpeg');
      case 'aac':
        return ContentType('audio', 'aac');
      default:
        return ContentType('application', 'octet-stream');
    }
  }
}

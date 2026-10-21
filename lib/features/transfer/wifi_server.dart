import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'wifi_page.dart';

/// Something that happened on the server, shown in the transfer screen.
class TransferEvent {
  TransferEvent(this.kind, this.name, {this.bytes});
  final TransferEventKind kind;
  final String name;
  final int? bytes;
  final at = DateTime.now();
}

enum TransferEventKind { connected, download, upload, folder, refused }

/// Local web server for Wi-Fi transfers with a computer on the same network.
///
/// Safety: a random session code is required (query `k`, then a cookie),
/// only private-network clients are accepted, and every path is confined to
/// [root].
class WifiServer {
  WifiServer(this.root, {String? code}) : code = code ?? _newCode();

  final String root;
  final String code;
  HttpServer? _server;
  final _events = StreamController<TransferEvent>.broadcast();
  final _known = <String>{};

  Stream<TransferEvent> get events => _events.stream;
  int? get port => _server?.port;
  bool get running => _server != null;

  static String _newCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => alphabet[r.nextInt(alphabet.length)]).join();
  }

  /// Address of this device on the local network (Wi-Fi or hotspot).
  static Future<String?> localAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    String? fallback;
    for (final i in interfaces) {
      for (final a in i.addresses) {
        if (a.isLoopback || !_isPrivate(a)) continue;
        final name = i.name.toLowerCase();
        if (name.startsWith('wlan') || name.startsWith('ap')) return a.address;
        fallback ??= a.address;
      }
    }
    return fallback;
  }

  static bool _isPrivate(InternetAddress a) {
    final b = a.rawAddress;
    if (b.length != 4) return a.isLinkLocal || a.isLoopback;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 169 && b[1] == 254) ||
        b[0] == 127;
  }

  Future<void> start({int firstPort = 8080}) async {
    if (_server != null) return;
    for (var port = firstPort; port < firstPort + 20; port++) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        break;
      } on SocketException {
        continue;
      }
    }
    final server = _server;
    if (server == null) throw const SocketException('Aucun port libre');
    // Files are streamed as-is with their exact length: no gzip.
    server.autoCompress = false;
    server.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final remote = request.connectionInfo?.remoteAddress;
      if (remote == null || !_isPrivate(remote)) {
        _emit(TransferEventKind.refused, remote?.address ?? '?');
        return _text(response, HttpStatus.forbidden, 'Réseau non autorisé');
      }
      if (!_authorised(request)) {
        return _html(response, unlockPage(), status: HttpStatus.unauthorized);
      }
      if (_known.add(remote.address)) {
        _emit(TransferEventKind.connected, remote.address);
      }
      final path = request.uri.path;
      switch ((request.method, path)) {
        case ('GET', '/'):
          return _html(response, appPage());
        case ('GET', '/api/list'):
          return _list(request);
        case ('GET', '/api/download'):
          return _download(request);
        case ('PUT', '/api/upload'):
          return _upload(request);
        case ('POST', '/api/mkdir'):
          return _mkdir(request);
        default:
          return _text(response, HttpStatus.notFound, 'Introuvable');
      }
    } catch (e) {
      try {
        _text(response, HttpStatus.internalServerError, 'Erreur : $e');
      } catch (_) {}
    }
  }

  /// The code arrives once in the URL, then lives in a cookie.
  bool _authorised(HttpRequest request) {
    final query = request.uri.queryParameters['k'];
    if (query != null && query.toUpperCase() == code) {
      request.response.cookies.add(
        Cookie('nexa', code)
          ..httpOnly = true
          ..path = '/'
          ..sameSite = SameSite.strict,
      );
      return true;
    }
    return request.cookies.any((c) => c.name == 'nexa' && c.value == code);
  }

  /// Resolves a client path inside [root], or null when it escapes.
  String? _resolve(String? relative) {
    final rel = (relative ?? '').replaceAll('\\', '/');
    final full = p.normalize(
      p.join(root, rel.startsWith('/') ? rel.substring(1) : rel),
    );
    if (full != p.normalize(root) && !p.isWithin(root, full)) return null;
    return full;
  }

  String _relative(String full) =>
      p.relative(full, from: root) == '.' ? '' : p.relative(full, from: root);

  Future<void> _list(HttpRequest request) async {
    final dir = _resolve(request.uri.queryParameters['path']);
    if (dir == null || !Directory(dir).existsSync()) {
      return _text(
        request.response,
        HttpStatus.notFound,
        'Dossier introuvable',
      );
    }
    final entries = <Map<String, Object?>>[];
    await for (final e in Directory(dir).list(followLinks: false)) {
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      try {
        final stat = await e.stat();
        entries.add({
          'name': name,
          'dir': stat.type == FileSystemEntityType.directory,
          'size': stat.type == FileSystemEntityType.file ? stat.size : null,
          'modified': stat.modified.millisecondsSinceEpoch,
        });
      } catch (_) {}
    }
    entries.sort((a, b) {
      if (a['dir'] != b['dir']) return a['dir'] == true ? -1 : 1;
      return (a['name']! as String).toLowerCase().compareTo(
        (b['name']! as String).toLowerCase(),
      );
    });
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'path': _relative(dir), 'entries': entries}));
    await request.response.close();
  }

  Future<void> _download(HttpRequest request) async {
    final full = _resolve(request.uri.queryParameters['path']);
    final file = full == null ? null : File(full);
    if (file == null || !file.existsSync()) {
      return _text(
        request.response,
        HttpStatus.notFound,
        'Fichier introuvable',
      );
    }
    final name = p.basename(file.path);
    final response = request.response;
    response.headers
      ..contentType = ContentType.binary
      ..contentLength = await file.length()
      ..set(
        'content-disposition',
        "attachment; filename*=UTF-8''${Uri.encodeComponent(name)}",
      );
    await response.addStream(file.openRead());
    await response.close();
    _emit(TransferEventKind.download, name, bytes: await file.length());
  }

  Future<void> _upload(HttpRequest request) async {
    final dir = _resolve(request.uri.queryParameters['path']);
    final wanted = p.basename(request.uri.queryParameters['name'] ?? '');
    if (dir == null || wanted.isEmpty || wanted.startsWith('.')) {
      return _text(request.response, HttpStatus.badRequest, 'Nom invalide');
    }
    final target = File(_unique(dir, wanted));
    final temp = File('${target.path}.part');
    final sink = temp.openWrite();
    var bytes = 0;
    try {
      await for (final chunk in request) {
        bytes += chunk.length;
        sink.add(chunk);
      }
      await sink.close();
      await temp.rename(target.path);
    } catch (e) {
      await sink.close().catchError((_) {});
      if (temp.existsSync()) temp.deleteSync();
      rethrow;
    }
    _emit(TransferEventKind.upload, p.basename(target.path), bytes: bytes);
    await _text(request.response, HttpStatus.created, p.basename(target.path));
  }

  Future<void> _mkdir(HttpRequest request) async {
    final dir = _resolve(request.uri.queryParameters['path']);
    final name = p.basename(request.uri.queryParameters['name'] ?? '');
    if (dir == null || name.isEmpty || name.startsWith('.')) {
      return _text(request.response, HttpStatus.badRequest, 'Nom invalide');
    }
    final created = Directory(_unique(dir, name))..createSync();
    _emit(TransferEventKind.folder, p.basename(created.path));
    await _text(request.response, HttpStatus.created, p.basename(created.path));
  }

  /// "photo.jpg", then "photo (2).jpg"… — never overwrites.
  static String _unique(String dir, String name) {
    var candidate = p.join(dir, name);
    final base = p.basenameWithoutExtension(name), ext = p.extension(name);
    for (
      var i = 2;
      FileSystemEntity.typeSync(candidate) != FileSystemEntityType.notFound;
      i++
    ) {
      candidate = p.join(dir, '$base ($i)$ext');
    }
    return candidate;
  }

  void _emit(TransferEventKind kind, String name, {int? bytes}) {
    if (!_events.isClosed) _events.add(TransferEvent(kind, name, bytes: bytes));
  }

  static Future<void> _text(HttpResponse r, int status, String text) async {
    r
      ..statusCode = status
      ..headers.contentType = ContentType.text
      ..write(text);
    await r.close();
  }

  static Future<void> _html(
    HttpResponse r,
    String html, {
    int status = HttpStatus.ok,
  }) async {
    r
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..headers.set('cache-control', 'no-store')
      ..write(html);
    await r.close();
  }
}

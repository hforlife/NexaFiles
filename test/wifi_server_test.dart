import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/features/transfer/wifi_server.dart';

void main() {
  late Directory root;
  late WifiServer server;
  late HttpClient client;
  late String base;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('nexa-wifi-');
    File('${root.path}/hello.txt').writeAsStringSync('bonjour');
    Directory('${root.path}/Music').createSync();
    server = WifiServer(root.path, code: 'ABC234');
    await server.start(firstPort: 18080);
    client = HttpClient();
    base = 'http://127.0.0.1:${server.port}';
  });

  tearDown(() async {
    client.close(force: true);
    await server.dispose();
    root.deleteSync(recursive: true);
  });

  Future<(int, String, List<Cookie>)> call(
    String method,
    String path, {
    List<Cookie> cookies = const [],
    List<int>? body,
  }) async {
    final request = await client.openUrl(method, Uri.parse('$base$path'));
    request.cookies.addAll(cookies);
    if (body != null) request.add(body);
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return (response.statusCode, text, response.cookies);
  }

  test('without the code only the unlock page is served', () async {
    final (status, body, _) = await call('GET', '/api/list');
    expect(status, HttpStatus.unauthorized);
    expect(body, contains('code'));
  });

  test('the code in the URL grants a session cookie', () async {
    final (status, _, cookies) = await call('GET', '/?k=abc234');
    expect(status, HttpStatus.ok);
    final session = cookies.where((c) => c.name == 'nexa').toList();
    expect(session, isNotEmpty);

    final (listStatus, json, _) = await call(
      'GET',
      '/api/list?path=',
      cookies: session,
    );
    expect(listStatus, HttpStatus.ok);
    final names = [
      for (final e in (jsonDecode(json)['entries'] as List)) e['name'],
    ];
    // Folders first.
    expect(names, ['Music', 'hello.txt']);
  });

  test('upload, download and folder creation stay inside the root', () async {
    final cookie = [Cookie('nexa', 'ABC234')];
    final (up, name, _) = await call(
      'PUT',
      '/api/upload?path=Music&name=song.txt',
      cookies: cookie,
      body: utf8.encode('la la la'),
    );
    expect(up, HttpStatus.created);
    expect(name, 'song.txt');
    // Never overwrites an existing file.
    final (_, second, _) = await call(
      'PUT',
      '/api/upload?path=Music&name=song.txt',
      cookies: cookie,
      body: utf8.encode('autre'),
    );
    expect(second, 'song (2).txt');

    final (down, content, _) = await call(
      'GET',
      '/api/download?path=Music/song.txt',
      cookies: cookie,
    );
    expect(down, HttpStatus.ok);
    expect(content, 'la la la');

    final (mk, folder, _) = await call(
      'POST',
      '/api/mkdir?path=&name=Photos',
      cookies: cookie,
    );
    expect(mk, HttpStatus.created);
    expect(Directory('${root.path}/$folder').existsSync(), isTrue);
  });

  test('paths escaping the storage root are refused', () async {
    final cookie = [Cookie('nexa', 'ABC234')];
    final (list, _, _) = await call(
      'GET',
      '/api/list?path=../..',
      cookies: cookie,
    );
    expect(list, HttpStatus.notFound);
    final (down, _, _) = await call(
      'GET',
      '/api/download?path=../../etc/hosts',
      cookies: cookie,
    );
    expect(down, HttpStatus.notFound);
    final (up, _, _) = await call(
      'PUT',
      '/api/upload?path=..&name=evil.txt',
      cookies: cookie,
      body: [1, 2, 3],
    );
    expect(up, HttpStatus.badRequest);
    expect(File('${root.parent.path}/evil.txt').existsSync(), isFalse);
  });
}

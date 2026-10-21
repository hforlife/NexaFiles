import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/features/files/file_actions.dart';

void main() {
  test('checksums match the reference values', () async {
    final dir = Directory.systemTemp.createTempSync('nexa-hash-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/abc.txt')..writeAsStringSync('abc');
    final hashes = await fileChecksums(file.path);
    expect(hashes['MD5'], '900150983cd24fb0d6963f7d28e17f72');
    expect(hashes['SHA-1'], 'a9993e364706816aba3e25717850c26c9cd0d89d');
    expect(
      hashes['SHA-256'],
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
}

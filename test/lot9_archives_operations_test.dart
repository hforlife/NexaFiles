import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/core/archives/archive_safety_policy.dart';
import 'package:nexa_file/core/archives/tar_archive_adapter.dart';
import 'package:nexa_file/core/archives/zip_archive_adapter.dart';
import 'package:nexa_file/core/errors/app_failure.dart';
import 'package:nexa_file/core/formats/detected_format.dart';
import 'package:nexa_file/core/formats/format_detector.dart';
import 'package:nexa_file/core/storage/content_source.dart';
import 'package:nexa_file/features/archives/archive_creator.dart';
import 'package:nexa_file/core/archives/archive_core.dart';
import 'package:nexa_file/features/files/file_actions.dart';
import 'package:nexa_file/features/files/file_operation_service.dart';
import 'package:nexa_file/features/operations/operations_controller.dart';

class _FileSource implements MaterializedContentSource {
  _FileSource(this.file);
  final File file;
  @override
  String get id => file.uri.toString();
  @override
  String get displayName => file.uri.pathSegments.last;
  @override
  Future<int?> get length => file.length();
  @override
  Future<Stream<List<int>>> openRead() async => file.openRead();
  @override
  Future<File> materialize() async => file;
}

Future<String> _read(ContentSource source) async =>
    utf8.decode(await (await source.openRead()).expand((c) => c).toList());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('nexa-lot9-'));
  tearDown(() => dir.deleteSync(recursive: true));

  Archive sample() => Archive()
    ..add(ArchiveFile.bytes('notes/a.txt', utf8.encode('alpha')))
    ..add(ArchiveFile.bytes('b.txt', utf8.encode('bravo')));

  group('tar family', () {
    test('lists and reads a .tar.gz', () async {
      final tar = TarEncoder().encodeBytes(sample());
      final file = File('${dir.path}/photos.tar.gz')
        ..writeAsBytesSync(GZipEncoder().encodeBytes(tar));
      final session = await TarFamilyAdapter().open(
        _FileSource(file),
        const ArchiveSafetyPolicy(),
      );
      final entries = await session.listEntries();
      expect(entries.map((e) => e.path), containsAll(['notes/a.txt', 'b.txt']));
      final b = entries.firstWhere((e) => e.path == 'b.txt');
      expect(await _read(await session.openEntry(b)), 'bravo');
      await session.close();
    });

    test('a single .gz file is a one-entry archive', () async {
      final file = File('${dir.path}/journal.txt.gz')
        ..writeAsBytesSync(GZipEncoder().encodeBytes(utf8.encode('bonjour')));
      final session = await TarFamilyAdapter().open(
        _FileSource(file),
        const ArchiveSafetyPolicy(),
      );
      final entries = await session.listEntries();
      expect(entries.single.path, 'journal.txt');
      expect(await _read(await session.openEntry(entries.single)), 'bonjour');
      await session.close();
    });

    test('formats are detected from their magic bytes', () {
      final d = FormatDetector();
      expect(
        d.detect(prefix: [0x1f, 0x8b, 8], fileName: 'x.tgz').container,
        ContainerFormat.gzip,
      );
      expect(
        d.detect(prefix: utf8.encode('BZh91AY'), fileName: 'x.bz2').container,
        ContainerFormat.bzip2,
      );
      expect(
        d
            .detect(prefix: [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0], fileName: 'x.xz')
            .container,
        ContainerFormat.xz,
      );
      expect(
        d.detect(prefix: [0, 0, 0], fileName: 'backup.tar').container,
        ContainerFormat.tar,
      );
    });
  });

  group('encrypted zip', () {
    late File zip;
    setUp(() {
      final bytes = ZipEncoder(password: 'sesame').encodeBytes(sample());
      zip = File('${dir.path}/secret.zip')..writeAsBytesSync(bytes);
    });

    test('entries are flagged and need the password', () async {
      final session = await ZipArchiveAdapter().open(
        _FileSource(zip),
        const ArchiveSafetyPolicy(),
      );
      final entries = await session.listEntries();
      expect(
        entries.where((e) => !e.isDirectory).every((e) => e.encrypted),
        isTrue,
      );
      await expectLater(
        session.openEntry(entries.first),
        throwsA(isA<PasswordRequiredFailure>()),
      );
      await session.close();
    });

    test('a wrong password is reported as such', () async {
      final session = await ZipArchiveAdapter().open(
        _FileSource(zip),
        const ArchiveSafetyPolicy(),
        password: 'nope',
      );
      final entry = (await session.listEntries()).first;
      await expectLater(
        session.openEntry(entry),
        throwsA(isA<WrongPasswordFailure>()),
      );
      await session.close();
    });

    test('the right password reads the content', () async {
      final session = await ZipArchiveAdapter().open(
        _FileSource(zip),
        const ArchiveSafetyPolicy(),
        password: 'sesame',
      );
      final entry = (await session.listEntries()).firstWhere(
        (e) => e.path == 'b.txt',
      );
      expect(await _read(await session.openEntry(entry)), 'bravo');
      await session.close();
    });
  });

  group('archive creation', () {
    late Directory src;
    setUp(() {
      src = Directory('${dir.path}/src/docs')..createSync(recursive: true);
      File('${src.path}/one.txt').writeAsStringSync('un');
      Directory('${src.path}/sub').createSync();
      File('${src.path}/sub/two.txt').writeAsStringSync('deux');
    });

    Future<List<OperationProgress>> run(
      ArchiveKind kind,
      String out, {
      String? password,
    }) => ArchiveCreator()
        .create(
          sources: [src.path],
          output: out,
          kind: kind,
          password: password,
          token: CancellationToken(),
        )
        .toList();

    test('zip keeps the folder tree and can be password protected', () async {
      final out = '${dir.path}/docs.zip';
      final events = await run(ArchiveKind.zip, out, password: 'pw');
      expect(events.last.finished, isTrue);
      final session = await ZipArchiveAdapter().open(
        _FileSource(File(out)),
        const ArchiveSafetyPolicy(),
        password: 'pw',
      );
      final entries = await session.listEntries();
      expect(
        entries.map((e) => e.path),
        containsAll(['docs/one.txt', 'docs/sub/two.txt']),
      );
      final two = entries.firstWhere((e) => e.path == 'docs/sub/two.txt');
      expect(two.encrypted, isTrue);
      expect(await _read(await session.openEntry(two)), 'deux');
      await session.close();
    });

    test('tar.gz round trips through the tar adapter', () async {
      final out = '${dir.path}/docs.tar.gz';
      await run(ArchiveKind.tarGz, out);
      expect(File('$out.part.tar').existsSync(), isFalse);
      final session = await TarFamilyAdapter().open(
        _FileSource(File(out)),
        const ArchiveSafetyPolicy(),
      );
      final entries = await session.listEntries();
      final one = entries.firstWhere((e) => e.path == 'docs/one.txt');
      expect(await _read(await session.openEntry(one)), 'un');
      await session.close();
    });
  });

  group('operations', () {
    test('a job reports progress, then runs onDone', () async {
      final ops = OperationsController();
      var done = false;
      final finished = ops.finished.first;
      final job = ops.start(
        kind: OperationKind.copy,
        title: 'Copie',
        run: (_) => Stream.fromIterable(const [
          OperationProgress(done: 1, total: 2),
          OperationProgress(done: 2, total: 2, finished: true),
        ]),
        onDone: () => done = true,
      );
      expect(ops.busy, isTrue);
      expect(await finished, same(job));
      expect(job.state, OperationState.done);
      expect(job.progress.done, 2);
      expect(done, isTrue);
      expect(ops.busy, isFalse);
    });

    test('cancelling marks the job cancelled', () async {
      final ops = OperationsController();
      final controller = StreamController<OperationProgress>();
      final job = ops.start(
        kind: OperationKind.extract,
        title: 'Extraction',
        run: (token) {
          // The worker notices the token and stops with OperationCancelled.
          Timer.periodic(const Duration(milliseconds: 5), (t) {
            if (!token.isCancelled) return;
            t.cancel();
            controller.addError(const OperationCancelled());
          });
          return controller.stream;
        },
      );
      final finished = ops.finished.first;
      ops.cancel(job);
      await finished;
      expect(job.state, OperationState.cancelled);
      await controller.close();
    });

    test('an error marks the job failed with a readable message', () async {
      final ops = OperationsController();
      final finished = ops.finished.first;
      final job = ops.start(
        kind: OperationKind.compress,
        title: 'Compression',
        run: (_) => Stream.error(const InsufficientSpaceFailure()),
      );
      await finished;
      expect(job.state, OperationState.failed);
      expect(job.error, 'Espace de stockage insuffisant');
    });
  });

  test('single root folder is detected for smart extraction', () {
    ArchiveEntry e(String path, {bool dir = false}) => ArchiveEntry(
      path: path,
      compressedSize: 1,
      uncompressedSize: 1,
      isDirectory: dir,
    );
    expect(
      singleRootFolder([
        e('Projet/', dir: true),
        e('Projet/a.txt'),
        e('Projet/sub/b.txt'),
      ]),
      'Projet',
    );
    expect(singleRootFolder([e('a.txt'), e('Projet/b.txt')]), isNull);
    expect(singleRootFolder([e('A/x.txt'), e('B/y.txt')]), isNull);
  });
}

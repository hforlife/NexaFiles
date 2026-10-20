import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/core/formats/detected_format.dart';
import 'package:nexa_file/core/formats/format_detector.dart';

void main() {
  const zip = [0x50, 0x4b, 0x03, 0x04];
  final detector = FormatDetector();
  test('semantic ZIP formats never become generic archives', () {
    expect(
      detector.detect(prefix: zip, fileName: 'sample.zip').content,
      ContentKind.archive,
    );
    expect(
      detector.detect(prefix: zip, fileName: 'sample.apk').content,
      ContentKind.apk,
    );
    expect(
      detector.detect(prefix: zip, fileName: 'sample.docx').content,
      ContentKind.officeWord,
    );
    expect(
      detector.detect(prefix: zip, fileName: 'sample.xlsx').content,
      ContentKind.officeSpreadsheet,
    );
    expect(
      detector.detect(prefix: zip, fileName: 'sample.pptx').content,
      ContentKind.officePresentation,
    );
    expect(
      detector.detect(prefix: zip, fileName: 'sample.epub').content,
      ContentKind.epub,
    );
    expect(
      detector.detect(prefix: zip, fileName: 'sample.cbz').content,
      ContentKind.comic,
    );
  });
  test('APK can be identified by minimal structure', () {
    final result = detector.detect(
      prefix: zip,
      fileName: 'download.bin',
      archiveEntries: const [
        'AndroidManifest.xml',
        'classes.dex',
        'resources.arsc',
      ],
    );
    expect(result.content, ContentKind.apk);
  });
  test('magic PDF keeps precedence over misleading extension', () {
    expect(
      detector
          .detect(
            prefix: const [0x25, 0x50, 0x44, 0x46, 0x2d],
            fileName: 'fake.apk',
          )
          .content,
      ContentKind.pdf,
    );
  });
  test('audio and video use canonical media kinds', () {
    expect(
      detector
          .detect(
            prefix: const [],
            mimeType: 'audio/mpeg',
            fileName: 'track.bin',
          )
          .content,
      ContentKind.audio,
    );
    expect(
      detector.detect(prefix: const [], fileName: 'movie.mp4').content,
      ContentKind.video,
    );
  });
}

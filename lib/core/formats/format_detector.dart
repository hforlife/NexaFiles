import 'dart:convert';
import 'detected_format.dart';

class FormatDetector {
  DetectedFormat detect({
    required List<int> prefix,
    String? mimeType,
    String? fileName,
    Iterable<String>? archiveEntries,
  }) {
    final name = (fileName ?? '').toLowerCase();
    if (_has(prefix, [0x25, 0x50, 0x44, 0x46, 0x2d])) {
      return const DetectedFormat(
        container: ContainerFormat.none,
        content: ContentKind.pdf,
        confidence: 1,
        evidence: ['magic:pdf'],
      );
    }
    if (_has(prefix, [0x52, 0x61, 0x72, 0x21, 0x1a, 0x07])) {
      return DetectedFormat(
        container: ContainerFormat.rar,
        content: name.endsWith('.cbr')
            ? ContentKind.comic
            : ContentKind.archive,
        confidence: .99,
        evidence: const ['magic:rar'],
      );
    }
    if (_has(prefix, [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c])) {
      return DetectedFormat(
        container: ContainerFormat.sevenZip,
        content: name.endsWith('.cb7')
            ? ContentKind.comic
            : ContentKind.archive,
        confidence: 1,
        evidence: const ['magic:7z'],
      );
    }
    // Compressed streams: tarballs (.tar.gz, .tgz…) or single files (.gz).
    for (final (magic, container, tag) in const [
      ([0x1f, 0x8b], ContainerFormat.gzip, 'magic:gzip'),
      ([0x42, 0x5a, 0x68], ContainerFormat.bzip2, 'magic:bzip2'),
      ([0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00], ContainerFormat.xz, 'magic:xz'),
    ]) {
      if (_has(prefix, magic)) {
        return DetectedFormat(
          container: container,
          content: ContentKind.archive,
          confidence: .95,
          evidence: [tag],
        );
      }
    }
    // A plain tar has its signature at offset 257, beyond a short prefix.
    if (name.endsWith('.tar')) {
      return const DetectedFormat(
        container: ContainerFormat.tar,
        content: ContentKind.archive,
        confidence: .8,
        evidence: ['extension:tar'],
      );
    }
    if (_has(prefix, [0x50, 0x4b, 0x03, 0x04]) ||
        _has(prefix, [0x50, 0x4b, 0x05, 0x06])) {
      final entries =
          archiveEntries?.map((e) => e.toLowerCase()).toList() ??
          const <String>[];
      final imageCount = entries
          .where((e) => RegExp(r'\.(jpe?g|png|webp)$').hasMatch(e))
          .length;
      final epub =
          entries.contains('mimetype') &&
          entries.any((e) => e == 'meta-inf/container.xml');
      final ooxml = entries.contains('[content_types].xml');
      final office = ooxml && entries.any((e) => e.startsWith('word/'))
          ? ContentKind.officeWord
          : ooxml && entries.any((e) => e.startsWith('xl/'))
          ? ContentKind.officeSpreadsheet
          : ooxml && entries.any((e) => e.startsWith('ppt/'))
          ? ContentKind.officePresentation
          : null;
      final apkStructure =
          entries.contains('androidmanifest.xml') &&
          (entries.contains('resources.arsc') ||
              entries.any(
                (e) => e.startsWith('classes') && e.endsWith('.dex'),
              ));
      final semantic =
          apkStructure ||
              name.endsWith('.apk') ||
              mimeType == 'application/vnd.android.package-archive'
          ? ContentKind.apk
          : office ??
                (name.endsWith('.docx')
                    ? ContentKind.officeWord
                    : name.endsWith('.xlsx')
                    ? ContentKind.officeSpreadsheet
                    : name.endsWith('.pptx')
                    ? ContentKind.officePresentation
                    : null);
      final epubByName = name.endsWith('.epub');
      final comic =
          name.endsWith('.cbz') ||
          (imageCount >= 5 &&
              entries.isNotEmpty &&
              imageCount / entries.length >= .7);
      return DetectedFormat(
        container: ContainerFormat.zip,
        content:
            semantic ??
            (epub || epubByName
                ? ContentKind.epub
                : (comic ? ContentKind.comic : ContentKind.archive)),
        confidence: semantic != null || epub || epubByName || comic ? .98 : .94,
        evidence: [
          'magic:zip',
          if (semantic == ContentKind.apk) 'semantic:apk',
          if (office != null) 'structure:ooxml',
          if (epub) 'structure:epub',
          if (imageCount > 0) 'images:$imageCount',
        ],
      );
    }
    if (_has(prefix, [0xff, 0xd8, 0xff]) ||
        _has(prefix, [0x89, 0x50, 0x4e, 0x47]) ||
        _has(prefix, [0x47, 0x49, 0x46, 0x38]) ||
        (prefix.length >= 12 &&
            ascii.decode(prefix.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
            ascii.decode(prefix.sublist(8, 12), allowInvalid: true) ==
                'WEBP')) {
      return const DetectedFormat(
        container: ContainerFormat.none,
        content: ContentKind.image,
        confidence: 1,
        evidence: ['magic:image'],
      );
    }
    if (mimeType?.startsWith('audio/') == true ||
        RegExp(r'\.(mp3|m4a|aac|ogg|wav|flac)$').hasMatch(name)) {
      return const DetectedFormat(
        container: ContainerFormat.none,
        content: ContentKind.audio,
        confidence: .9,
        evidence: ['mime/extension:audio'],
      );
    }
    if (mimeType?.startsWith('video/') == true ||
        RegExp(r'\.(mp4|m4v|webm|mkv|3gp)$').hasMatch(name)) {
      return const DetectedFormat(
        container: ContainerFormat.none,
        content: ContentKind.video,
        confidence: .9,
        evidence: ['mime/extension:video'],
      );
    }
    if (name.endsWith('.md') ||
        name.endsWith('.markdown') ||
        mimeType == 'text/markdown') {
      return const DetectedFormat(
        container: ContainerFormat.none,
        content: ContentKind.markdown,
        confidence: .85,
        evidence: ['mime/extension:markdown'],
      );
    }
    if (mimeType?.startsWith('text/') == true ||
        mimeType == 'application/json' ||
        mimeType == 'application/xml' ||
        _plainText.hasMatch(name)) {
      return const DetectedFormat(
        container: ContainerFormat.none,
        content: ContentKind.text,
        confidence: .6,
        evidence: ['mime/extension:text'],
      );
    }
    return const DetectedFormat(
      container: ContainerFormat.none,
      content: ContentKind.unknown,
      confidence: 0,
    );
  }

  bool _has(List<int> bytes, List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }
}

/// Plain-text formats opened (and editable) in the text reader.
final _plainText = RegExp(
  r'\.(txt|log|json|xml|ya?ml|ini|conf|cfg|properties|toml|env|csv|tsv|srt|'
  r'vtt|sh|bat|py|js|ts|dart|kt|java|c|cc|cpp|h|css|sql|gradle|gitignore)$',
);

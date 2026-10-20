import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// One spine item, in reading order.
class EpubChapter {
  const EpubChapter(this.title, this.href);
  final String title;

  /// Path inside the EPUB, from its root (e.g. `OEBPS/text/ch01.xhtml`).
  final String href;
}

/// What a reader needs from an EPUB package: metadata, spine and cover.
class EpubPackage {
  const EpubPackage({
    required this.title,
    required this.author,
    required this.chapters,
    required this.coverHref,
  });
  final String? title, author, coverHref;
  final List<EpubChapter> chapters;
}

/// Path of the package document (OPF) declared by `META-INF/container.xml`.
String? epubRootFile(String containerXml) {
  final document = XmlDocument.parse(containerXml);
  for (final rootFile in document.descendantElements) {
    if (rootFile.localName == 'rootfile') {
      final path = rootFile.getAttribute('full-path');
      if (path != null && path.isNotEmpty) return path;
    }
  }
  return null;
}

/// Parses the OPF at [opfPath]. [read] returns the text of another file of
/// the package (used for the EPUB 3 nav document or the EPUB 2 NCX).
EpubPackage parseEpubPackage(
  String opfPath,
  String opfXml,
  String? Function(String path) read,
) {
  final opf = XmlDocument.parse(opfXml).rootElement;
  final base = p.posix.dirname(opfPath);
  String resolve(String href) => p.posix.normalize(
    p.posix.join(
      base == '.' ? '' : base,
      Uri.decodeFull(href.split('#').first),
    ),
  );

  String? meta(String name) {
    for (final element in opf.descendantElements) {
      if (element.localName == name && element.innerText.trim().isNotEmpty) {
        return element.innerText.trim();
      }
    }
    return null;
  }

  final manifest = <String, XmlElement>{};
  for (final item in opf.descendantElements) {
    if (item.localName == 'item' && item.getAttribute('id') != null) {
      manifest[item.getAttribute('id')!] = item;
    }
  }
  String? hrefOf(XmlElement? item) {
    final href = item?.getAttribute('href');
    return href == null ? null : resolve(href);
  }

  // Cover: EPUB 3 "cover-image" property, else EPUB 2 <meta name="cover">.
  var cover = hrefOf(
    manifest.values
        .where(
          (i) => (i.getAttribute('properties') ?? '')
              .split(' ')
              .contains('cover-image'),
        )
        .firstOrNull,
  );
  if (cover == null) {
    final coverId = opf.descendantElements
        .where(
          (e) => e.localName == 'meta' && e.getAttribute('name') == 'cover',
        )
        .firstOrNull
        ?.getAttribute('content');
    cover = hrefOf(manifest[coverId]);
  }

  // Table of contents titles, keyed by resolved chapter path.
  final titles = <String, String>{};
  final nav = manifest.values
      .where(
        (i) => (i.getAttribute('properties') ?? '').split(' ').contains('nav'),
      )
      .firstOrNull;
  final ncx = manifest.values
      .where((i) => i.getAttribute('media-type') == 'application/x-dtbncx+xml')
      .firstOrNull;
  void collect(XmlElement? item, bool isNav) {
    final path = hrefOf(item);
    final xml = path == null ? null : read(path);
    if (path == null || xml == null) return;
    final tocBase = p.posix.dirname(path);
    String target(String href) => p.posix.normalize(
      p.posix.join(
        tocBase == '.' ? '' : tocBase,
        Uri.decodeFull(href.split('#').first),
      ),
    );
    try {
      final root = XmlDocument.parse(xml).rootElement;
      if (isNav) {
        for (final a in root.descendantElements) {
          final href = a.getAttribute('href');
          if (a.localName == 'a' && href != null) {
            titles.putIfAbsent(target(href), () => _clean(a.innerText));
          }
        }
      } else {
        for (final point in root.descendantElements) {
          if (point.localName != 'navPoint') continue;
          final label = point.descendantElements
              .where((e) => e.localName == 'text')
              .firstOrNull;
          final src = point.descendantElements
              .where((e) => e.localName == 'content')
              .firstOrNull
              ?.getAttribute('src');
          if (label != null && src != null) {
            titles.putIfAbsent(target(src), () => _clean(label.innerText));
          }
        }
      }
    } on XmlException {
      // A broken table of contents only costs us the chapter titles.
    }
  }

  collect(nav, true);
  if (titles.isEmpty) collect(ncx, false);

  final chapters = <EpubChapter>[];
  for (final ref in opf.descendantElements) {
    if (ref.localName != 'itemref') continue;
    if (ref.getAttribute('linear') == 'no') continue;
    final href = hrefOf(manifest[ref.getAttribute('idref')]);
    if (href == null || chapters.any((c) => c.href == href)) continue;
    final title = titles[href];
    chapters.add(
      EpubChapter(
        title == null || title.isEmpty
            ? 'Chapitre ${chapters.length + 1}'
            : title,
        href,
      ),
    );
  }
  return EpubPackage(
    title: meta('title'),
    author: meta('creator'),
    chapters: chapters,
    coverHref: cover,
  );
}

String _clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Plain text of an XHTML chapter, for search.
String epubPlainText(String html) => html
    .replaceAll(
      RegExp(
        r'<(script|style|head)\b[^>]*>.*?</\1>',
        caseSensitive: false,
        dotAll: true,
      ),
      ' ',
    )
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

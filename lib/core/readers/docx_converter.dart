import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// A Word document converted for reading: one HTML page plus its images,
/// keyed by the relative path used in the HTML (`media/image1.png`).
class DocxDocument {
  const DocxDocument(this.title, this.html, this.media);
  final String title, html;
  final Map<String, Uint8List> media;
}

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _browserImages = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};

/// Converts .docx bytes to readable HTML. Covers the content people read:
/// headings, emphasis, alignment, lists, tables, images, links and line breaks.
/// Layout details (fonts, columns, headers/footers) are intentionally dropped.
DocxDocument convertDocx(Uint8List bytes, {required String fallbackTitle}) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String? text(String name) {
    final file = zip.findFile(name);
    return file == null
        ? null
        : utf8.decode(file.content, allowMalformed: true);
  }

  final body = text('word/document.xml');
  if (body == null) throw const FormatException('Document Word invalide');
  final converter = _Converter(
    zip,
    relationships: _relationships(text('word/_rels/document.xml.rels')),
    headingLevels: _headingLevels(text('word/styles.xml')),
    orderedLists: _orderedLists(text('word/numbering.xml')),
  );
  final title = _coreTitle(text('docProps/core.xml')) ?? fallbackTitle;
  final content = converter.convert(XmlDocument.parse(body));
  final html =
      '<!DOCTYPE html><html><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<title>${_escape(title)}</title><style>$_css</style></head>'
      '<body>$content</body></html>';
  return DocxDocument(title, html, converter.media);
}

const _css =
    'body{margin:0;padding:16px 0 48px;font-size:17px;word-wrap:break-word}'
    'p{margin:0 0 .7em}h1,h2,h3,h4,h5,h6{margin:1.2em 0 .5em;line-height:1.25}'
    'table{border-collapse:collapse;margin:1em 0;max-width:100%}'
    'td{border:1px solid #9995;padding:4px 8px;vertical-align:top}'
    'td p{margin:0}img{max-width:100%;height:auto}'
    'ul,ol{margin:0 0 .7em;padding-left:1.6em}a{color:inherit}';

class _Converter {
  _Converter(
    this.zip, {
    required this.relationships,
    required this.headingLevels,
    required this.orderedLists,
  });
  final Archive zip;
  final Map<String, String> relationships, headingLevels;
  final Set<String> orderedLists;
  final media = <String, Uint8List>{};
  final _out = StringBuffer();

  /// Open lists, outermost first: true for numbered, false for bullets.
  final _lists = <bool>[];

  String convert(XmlDocument document) {
    final body = document.rootElement.findElements('body', namespace: _w);
    for (final element in body.expand((b) => b.childElements)) {
      _block(element);
    }
    _closeLists(0);
    return _out.toString();
  }

  void _block(XmlElement element) {
    switch (element.localName) {
      case 'p':
        _paragraph(element);
      case 'tbl':
        _closeLists(0);
        _table(element);
      case 'sdt':
        for (final child in _children(element, 'sdtContent')) {
          child.childElements.forEach(_block);
        }
    }
  }

  void _paragraph(XmlElement paragraph) {
    final props = _child(paragraph, 'pPr');
    final style = _attr(_child(props, 'pStyle'), 'val');
    final numbering = _child(props, 'numPr');
    final numId = _attr(_child(numbering, 'numId'), 'val');
    final inline = StringBuffer();
    _inline(paragraph, inline);
    final content = inline.isEmpty ? '<br>' : inline.toString();
    final align = switch (_attr(_child(props, 'jc'), 'val')) {
      'center' => 'center',
      'right' || 'end' => 'right',
      'both' || 'distribute' => 'justify',
      _ => null,
    };
    final styleAttr = align == null ? '' : ' style="text-align:$align"';

    if (numId != null && numId != '0') {
      final level =
          int.tryParse(_attr(_child(numbering, 'ilvl'), 'val') ?? '0') ?? 0;
      _openList(level, orderedLists.contains(numId));
      _out.write('<li$styleAttr>$content</li>');
      return;
    }
    _closeLists(0);
    final heading = headingLevels[style];
    final tag = heading == null ? 'p' : 'h$heading';
    _out.write('<$tag$styleAttr>$content</$tag>');
  }

  void _openList(int level, bool ordered) {
    _closeLists(level + 1);
    while (_lists.length <= level) {
      _lists.add(ordered);
      _out.write(ordered ? '<ol>' : '<ul>');
    }
  }

  void _closeLists(int keep) {
    while (_lists.length > keep) {
      _out.write(_lists.removeLast() ? '</ol>' : '</ul>');
    }
  }

  void _table(XmlElement table) {
    _out.write('<table>');
    for (final row in _children(table, 'tr')) {
      _out.write('<tr>');
      for (final cell in _children(row, 'tc')) {
        final span = _attr(_child(_child(cell, 'tcPr'), 'gridSpan'), 'val');
        _out.write(span == null ? '<td>' : '<td colspan="$span">');
        final saved = List.of(_lists);
        _lists.clear();
        cell.childElements.forEach(_block);
        _closeLists(0);
        _lists.addAll(saved);
        _out.write('</td>');
      }
      _out.write('</tr>');
    }
    _out.write('</table>');
  }

  /// Runs and the containers that hold them (links, insertions, fields).
  void _inline(XmlElement parent, StringBuffer out) {
    for (final child in parent.childElements) {
      switch (child.localName) {
        case 'r':
          _run(child, out);
        case 'hyperlink':
          final target = relationships[child.getAttribute('id', namespace: _r)];
          final inner = StringBuffer();
          _inline(child, inner);
          out.write(
            target == null ? inner : '<a href="${_escape(target)}">$inner</a>',
          );
        case 'ins' || 'smartTag' || 'fldSimple' || 'customXml':
          _inline(child, out);
        case 'sdt':
          for (final content in _children(child, 'sdtContent')) {
            _inline(content, out);
          }
      }
    }
  }

  void _run(XmlElement run, StringBuffer out) {
    final props = _child(run, 'rPr');
    final text = StringBuffer();
    for (final child in run.childElements) {
      switch (child.localName) {
        case 't':
          text.write(_escape(child.innerText));
        case 'tab':
          text.write('&emsp;');
        case 'br' || 'cr':
          if (child.getAttribute('type', namespace: _w) != 'page') {
            text.write('<br>');
          }
        case 'noBreakHyphen':
          text.write('-');
        case 'drawing' || 'pict' || 'object':
          text.write(_image(child));
      }
    }
    if (text.isEmpty) return;
    var html = text.toString();
    bool on(String name) {
      final flag = _child(props, name);
      if (flag == null) return false;
      final value = _attr(flag, 'val');
      return value == null || !{'0', 'false', 'none'}.contains(value);
    }

    if (on('b')) html = '<b>$html</b>';
    if (on('i')) html = '<i>$html</i>';
    if (on('u')) html = '<u>$html</u>';
    if (on('strike') || on('dstrike')) html = '<s>$html</s>';
    switch (_attr(_child(props, 'vertAlign'), 'val')) {
      case 'superscript':
        html = '<sup>$html</sup>';
      case 'subscript':
        html = '<sub>$html</sub>';
    }
    out.write(html);
  }

  /// `<img>` for an embedded picture (DrawingML or legacy VML).
  String _image(XmlElement container) {
    final ids = [
      for (final node in container.descendantElements)
        if (node.localName == 'blip')
          node.getAttribute('embed', namespace: _r)
        else if (node.localName == 'imagedata')
          node.getAttribute('id', namespace: _r),
    ].whereType<String>();
    final buffer = StringBuffer();
    for (final id in ids) {
      final target = relationships[id];
      if (target == null) continue;
      final inZip = p.posix.normalize(p.posix.join('word', target));
      if (!inZip.startsWith('word/')) continue; // never leave the package
      final name = 'media/${p.posix.basename(inZip)}';
      if (!_browserImages.contains(p.posix.extension(name).toLowerCase())) {
        continue; // EMF/WMF and friends cannot be shown by a WebView
      }
      final file = zip.findFile(inZip);
      if (file == null) continue;
      media[name] = file.content;
      buffer.write('<img src="${_escape(name)}" alt="">');
    }
    return buffer.toString();
  }
}

XmlElement? _child(XmlElement? parent, String name) =>
    parent?.getElement(name, namespace: _w);
Iterable<XmlElement> _children(XmlElement parent, String name) =>
    parent.findElements(name, namespace: _w);
String? _attr(XmlElement? element, String name) =>
    element?.getAttribute(name, namespace: _w);

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Relationship id → target (images relative to `word/`, external links).
Map<String, String> _relationships(String? xml) {
  if (xml == null) return const {};
  return {
    for (final rel in XmlDocument.parse(xml).descendantElements)
      if (rel.localName == 'Relationship' &&
          rel.getAttribute('Id') != null &&
          rel.getAttribute('Target') != null)
        rel.getAttribute('Id')!: rel.getAttribute('Target')!,
  };
}

/// Style id → heading level (1–6), from built-in names ("heading 2",
/// "Titre 2", "Title") or the outline level of the style.
Map<String, String> _headingLevels(String? xml) {
  if (xml == null) return const {};
  final result = <String, String>{};
  for (final style in XmlDocument.parse(xml).descendantElements) {
    if (style.localName != 'style') continue;
    final id = style.getAttribute('styleId', namespace: _w);
    if (id == null) continue;
    final name = (_attr(_child(style, 'name'), 'val') ?? '').toLowerCase();
    final outline = _attr(_child(_child(style, 'pPr'), 'outlineLvl'), 'val');
    final match = RegExp(
      r'^(heading|titre|überschrift|título)\s*(\d)$',
    ).firstMatch(name);
    final level = name == 'title'
        ? 1
        : match != null
        ? int.parse(match.group(2)!)
        : outline != null
        ? (int.tryParse(outline) ?? 9) + 1
        : null;
    if (level != null && level >= 1 && level <= 6) result[id] = '$level';
  }
  return result;
}

/// Numbering ids whose first level is numbered (decimal, letters, roman…).
Set<String> _orderedLists(String? xml) {
  if (xml == null) return const {};
  final root = XmlDocument.parse(xml).rootElement;
  final ordered = <String>{};
  for (final abstract in _children(root, 'abstractNum')) {
    final level = _children(abstract, 'lvl').firstOrNull;
    final format = _attr(_child(level, 'numFmt'), 'val');
    if (format != null && format != 'bullet' && format != 'none') {
      ordered.add(_attr(abstract, 'abstractNumId') ?? '');
    }
  }
  return {
    for (final num in _children(root, 'num'))
      if (ordered.contains(_attr(_child(num, 'abstractNumId'), 'val')))
        _attr(num, 'numId') ?? '',
  };
}

String? _coreTitle(String? xml) {
  if (xml == null) return null;
  final title = XmlDocument.parse(
    xml,
  ).descendantElements.where((e) => e.localName == 'title').firstOrNull;
  final value = title?.innerText.trim();
  return value == null || value.isEmpty ? null : value;
}

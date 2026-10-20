import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/core/readers/docx_converter.dart';
import 'package:nexa_file/features/reader/media_reader_screens.dart';

const _ns =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"';

Uint8List _docx(String body, {Map<String, List<int>> extra = const {}}) {
  final files = <String, List<int>>{
    'word/document.xml': utf8.encode(
      '<w:document $_ns><w:body>$body</w:body></w:document>',
    ),
    'word/styles.xml': utf8.encode(
      '<w:styles $_ns>'
      '<w:style w:styleId="Titre1"><w:name w:val="Titre 1"/></w:style>'
      '<w:style w:styleId="H2"><w:name w:val="heading 2"/></w:style>'
      '</w:styles>',
    ),
    'word/numbering.xml': utf8.encode(
      '<w:numbering $_ns>'
      '<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0">'
      '<w:numFmt w:val="decimal"/></w:lvl></w:abstractNum>'
      '<w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0">'
      '<w:numFmt w:val="bullet"/></w:lvl></w:abstractNum>'
      '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
      '<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>'
      '</w:numbering>',
    ),
    'word/_rels/document.xml.rels': utf8.encode(
      '<Relationships>'
      '<Relationship Id="img" Target="media/photo.png"/>'
      '<Relationship Id="emf" Target="media/chart.emf"/>'
      '<Relationship Id="evil" Target="../../secret.png"/>'
      '<Relationship Id="link" Target="https://example.org" '
      'TargetMode="External"/>'
      '</Relationships>',
    ),
    'word/media/photo.png': [1, 2, 3],
    'word/media/chart.emf': [4, 5],
    'secret.png': [9],
    'docProps/core.xml': utf8.encode(
      '<cp:coreProperties xmlns:cp="c" xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>Rapport annuel</dc:title></cp:coreProperties>',
    ),
    ...extra,
  };
  final archive = Archive();
  files.forEach(
    (name, data) => archive.addFile(ArchiveFile(name, data.length, data)),
  );
  return _zip(archive);
}

String _p(String runs, {String? style, String? num, int level = 0}) =>
    '<w:p><w:pPr>'
    '${style == null ? '' : '<w:pStyle w:val="$style"/>'}'
    '${num == null ? '' : '<w:numPr><w:ilvl w:val="$level"/><w:numId w:val="$num"/></w:numPr>'}'
    '</w:pPr>$runs</w:p>';
String _r(String text, {String props = ''}) =>
    '<w:r><w:rPr>$props</w:rPr><w:t xml:space="preserve">$text</w:t></w:r>';

Uint8List _zip(Archive archive) =>
    Uint8List.fromList(ZipEncoder().encode(archive));

void main() {
  group('DOCX conversion', () {
    test('headings from localized style names, emphasis, title', () {
      final doc = convertDocx(
        _docx(
          _p(_r('Introduction'), style: 'Titre1') +
              _p(_r('Détails'), style: 'H2') +
              _p(
                _r('gras', props: '<w:b/>') +
                    _r(' et ') +
                    _r('italique', props: '<w:i/>'),
              ),
        ),
        fallbackTitle: 'fichier',
      );
      expect(doc.title, 'Rapport annuel');
      expect(doc.html, contains('<h1>Introduction</h1>'));
      expect(doc.html, contains('<h2>Détails</h2>'));
      expect(doc.html, contains('<b>gras</b> et <i>italique</i>'));
    });

    test('numbered and bullet lists, nested by level', () {
      final html = convertDocx(
        _docx(
          _p(_r('un'), num: '1') +
              _p(_r('un.a'), num: '1', level: 1) +
              _p(_r('deux'), num: '1') +
              _p(_r('fin')) +
              _p(_r('puce'), num: '2'),
        ),
        fallbackTitle: 'f',
      ).html;
      expect(
        html,
        contains(
          '<ol><li>un</li><ol><li>un.a</li></ol><li>deux</li></ol><p>fin</p>',
        ),
      );
      expect(html, contains('<ul><li>puce</li></ul>'));
    });

    test('tables keep horizontal merges', () {
      final html = convertDocx(
        _docx(
          '<w:tbl><w:tr>'
          '<w:tc><w:tcPr><w:gridSpan w:val="2"/></w:tcPr>${_p(_r('A'))}</w:tc>'
          '</w:tr><w:tr><w:tc>${_p(_r('B'))}</w:tc><w:tc>${_p(_r('C'))}</w:tc>'
          '</w:tr></w:tbl>',
        ),
        fallbackTitle: 'f',
      ).html;
      expect(
        html,
        contains(
          '<table><tr><td colspan="2"><p>A</p></td></tr>'
          '<tr><td><p>B</p></td><td><p>C</p></td></tr></table>',
        ),
      );
    });

    test('images are extracted; unsafe paths and EMF are skipped', () {
      final doc = convertDocx(
        _docx(
          _p(
            '<w:r><w:drawing><a:blip r:embed="img"/></w:drawing></w:r>'
            '<w:r><w:drawing><a:blip r:embed="emf"/></w:drawing></w:r>'
            '<w:r><w:drawing><a:blip r:embed="evil"/></w:drawing></w:r>',
          ),
        ),
        fallbackTitle: 'f',
      );
      expect(doc.media.keys, ['media/photo.png']);
      expect(doc.media['media/photo.png'], [1, 2, 3]);
      expect(doc.html, contains('<img src="media/photo.png" alt="">'));
      expect(doc.html, isNot(contains('secret')));
      expect(doc.html, isNot(contains('chart.emf')));
    });

    test('links, breaks, tracked changes and HTML escaping', () {
      final html = convertDocx(
        _docx(
          _p(
            '<w:hyperlink r:id="link">${_r('site')}</w:hyperlink>'
            '<w:r><w:br/></w:r>'
            '<w:ins>${_r('ajouté')}</w:ins>'
            '<w:del><w:r><w:delText>retiré</w:delText></w:r></w:del>'
            '${_r('&lt;script&gt;alert(1)&lt;/script&gt; &amp; co')}',
          ),
        ),
        fallbackTitle: 'f',
      ).html;
      expect(
        html,
        contains('<a href="https://example.org">site</a><br>ajouté'),
      );
      expect(html, isNot(contains('retiré')));
      expect(html, contains('&lt;script&gt;alert(1)&lt;/script&gt; &amp; co'));
      expect(html, isNot(contains('<script>')));
    });

    test('falls back to the file name without core properties', () {
      final archive = ZipDecoder().decodeBytes(_docx(_p(_r('x'))));
      final stripped = Archive();
      for (final f in archive.files) {
        if (f.name != 'docProps/core.xml') stripped.addFile(f);
      }
      expect(
        convertDocx(_zip(stripped), fallbackTitle: 'notes').title,
        'notes',
      );
    });

    test('rejects a ZIP that is not a Word document', () {
      final archive = Archive()..addFile(ArchiveFile('a.txt', 1, [65]));
      expect(
        () => convertDocx(_zip(archive), fallbackTitle: 'f'),
        throwsFormatException,
      );
    });
  });

  test('media time format', () {
    expect(formatMediaTime(const Duration(seconds: 5)), '0:05');
    expect(formatMediaTime(const Duration(minutes: 3, seconds: 7)), '3:07');
    expect(
      formatMediaTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });
}

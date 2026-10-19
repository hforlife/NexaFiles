import 'dart:convert';

sealed class ReadingLocator {
  const ReadingLocator();
  Map<String, Object?> toJson();
  String encode() => jsonEncode(toJson());
  static ReadingLocator decode(String value) {
    final map = jsonDecode(value) as Map<String, dynamic>;
    switch (map['type']) {
      case 'pdf':
        return PdfLocator(map['page'] as int);
      case 'comic':
        return ComicLocator(map['page'] as int);
      case 'epub':
        return EpubLocator(map['cfi'] as String, map['chapter'] as int?);
      default:
        throw const FormatException('Unknown locator');
    }
  }
}

class PdfLocator extends ReadingLocator {
  const PdfLocator(this.page);
  final int page;
  @override
  Map<String, Object?> toJson() => {'type': 'pdf', 'page': page};
}

class ComicLocator extends ReadingLocator {
  const ComicLocator(this.page);
  final int page;
  @override
  Map<String, Object?> toJson() => {'type': 'comic', 'page': page};
}

class EpubLocator extends ReadingLocator {
  const EpubLocator(this.cfi, [this.chapter]);
  final String cfi;
  final int? chapter;
  @override
  Map<String, Object?> toJson() =>
      {'type': 'epub', 'cfi': cfi, 'chapter': chapter};
}

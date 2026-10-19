import 'dart:typed_data';

class ComicPage {
  const ComicPage(
      {required this.index, required this.name, required this.bytes});
  final int index;
  final String name;
  final Uint8List bytes;
}

abstract interface class ComicPageSource {
  Future<int> get pageCount;
  Future<ComicPage> getPage(int index);
  Future<void> preload(int from, int count);
  Future<void> dispose();
}

int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+|\D+)');
  final aa = re.allMatches(a.toLowerCase()).map((e) => e.group(0)!).toList(),
      bb = re.allMatches(b.toLowerCase()).map((e) => e.group(0)!).toList();
  for (var i = 0; i < aa.length && i < bb.length; i++) {
    final an = int.tryParse(aa[i]), bn = int.tryParse(bb[i]);
    final c =
        an != null && bn != null ? an.compareTo(bn) : aa[i].compareTo(bb[i]);
    if (c != 0) return c;
  }
  return aa.length.compareTo(bb.length);
}

bool isComicImage(String name) =>
    RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(name);

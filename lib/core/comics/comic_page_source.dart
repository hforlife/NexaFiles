import 'dart:typed_data';

class ComicPage {
  const ComicPage({
    required this.index,
    required this.name,
    required this.bytes,
  });
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

/// "page2" < "page10": digit runs compare by value, the rest by character,
/// case-insensitively. Runs while sorting large folders, so it scans the
/// strings in place instead of tokenizing them.
int naturalCompare(String a, String b) {
  a = a.toLowerCase();
  b = b.toLowerCase();
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i), cb = b.codeUnitAt(j);
    if (_isDigit(ca) && _isDigit(cb)) {
      var endA = i, endB = j;
      while (endA < a.length && _isDigit(a.codeUnitAt(endA))) {
        endA++;
      }
      while (endB < b.length && _isDigit(b.codeUnitAt(endB))) {
        endB++;
      }
      // Ignore leading zeros, then the longer number is the bigger one.
      var startA = i, startB = j;
      while (startA < endA - 1 && a.codeUnitAt(startA) == 0x30) {
        startA++;
      }
      while (startB < endB - 1 && b.codeUnitAt(startB) == 0x30) {
        startB++;
      }
      final lengthA = endA - startA, lengthB = endB - startB;
      if (lengthA != lengthB) return lengthA.compareTo(lengthB);
      for (var k = 0; k < lengthA; k++) {
        final d = a.codeUnitAt(startA + k) - b.codeUnitAt(startB + k);
        if (d != 0) return d.sign;
      }
      i = endA;
      j = endB;
    } else {
      if (ca != cb) return ca.compareTo(cb);
      i++;
      j++;
    }
  }
  return (a.length - i).compareTo(b.length - j);
}

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

final _comicImage = RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false);

bool isComicImage(String name) => _comicImage.hasMatch(name);

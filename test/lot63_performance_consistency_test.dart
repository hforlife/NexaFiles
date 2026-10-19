import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/features/files/files_controller.dart';
import 'package:nexa_file/features/reader/comic_reader_screen.dart';

void main() {
  test('single-page controls advance one page', () {
    expect(pageStepForMode(ComicReadingMode.single), 1);
    expect(
        steppedComicPage(
            current: 10,
            pageCount: 30,
            mode: ComicReadingMode.single,
            direction: 1),
        11);
  });
  test('double-page controls advance and rewind two pages', () {
    expect(pageStepForMode(ComicReadingMode.doublePage), 2);
    expect(
        steppedComicPage(
            current: 10,
            pageCount: 30,
            mode: ComicReadingMode.doublePage,
            direction: 1),
        12);
    expect(
        steppedComicPage(
            current: 10,
            pageCount: 30,
            mode: ComicReadingMode.doublePage,
            direction: -1),
        8);
  });
  test('double-page controls respect document bounds', () {
    expect(
        steppedComicPage(
            current: 0,
            pageCount: 5,
            mode: ComicReadingMode.doublePage,
            direction: -1),
        0);
    expect(
        steppedComicPage(
            current: 4,
            pageCount: 5,
            mode: ComicReadingMode.doublePage,
            direction: 1),
        4);
  });
  test('dot-prefixed entries are hidden by default rule', () {
    expect(isHiddenFileName('.nom'), isTrue);
    expect(isHiddenFileName('nom'), isFalse);
    expect(isHiddenFileName('photo.jpg'), isFalse);
  });
}

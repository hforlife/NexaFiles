import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/features/reader/comic_reader_screen.dart';
import 'package:nexa_file/features/reader/reader_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

ComicTapAction _tap(
  double x,
  double y,
  ComicTapLayout layout, {
  bool manga = false,
}) => comicTapAction(
  dx: x * 1000,
  dy: y * 2000,
  width: 1000,
  height: 2000,
  direction: manga
      ? ComicReadingDirection.rightToLeft
      : ComicReadingDirection.leftToRight,
  layout: layout,
);

void main() {
  group('tap layouts', () {
    test('edges: thirds, centre toggles the controls', () {
      expect(_tap(.1, .5, ComicTapLayout.edges), ComicTapAction.previous);
      expect(_tap(.5, .5, ComicTapLayout.edges), ComicTapAction.toggleControls);
      expect(_tap(.9, .5, ComicTapLayout.edges), ComicTapAction.next);
    });

    test('manga mirrors the zones', () {
      expect(
        _tap(.1, .5, ComicTapLayout.edges, manga: true),
        ComicTapAction.next,
      );
      expect(
        _tap(.1, .9, ComicTapLayout.kindle, manga: true),
        ComicTapAction.next,
      );
    });

    test('L shape: top and left go back, bottom and right go forward', () {
      expect(_tap(.5, .1, ComicTapLayout.lShape), ComicTapAction.previous);
      expect(_tap(.1, .9, ComicTapLayout.lShape), ComicTapAction.previous);
      expect(
        _tap(.5, .5, ComicTapLayout.lShape),
        ComicTapAction.toggleControls,
      );
      expect(_tap(.9, .5, ComicTapLayout.lShape), ComicTapAction.next);
      expect(_tap(.5, .9, ComicTapLayout.lShape), ComicTapAction.next);
    });

    test('kindle: narrow back strip, top strip opens the menu', () {
      expect(_tap(.1, .5, ComicTapLayout.kindle), ComicTapAction.previous);
      expect(_tap(.5, .5, ComicTapLayout.kindle), ComicTapAction.next);
      expect(
        _tap(.5, .05, ComicTapLayout.kindle),
        ComicTapAction.toggleControls,
      );
    });

    test('off: every tap toggles the controls', () {
      for (final x in [.05, .5, .95]) {
        expect(_tap(x, .5, ComicTapLayout.off), ComicTapAction.toggleControls);
      }
    });

    test('default call keeps the historical edges behaviour', () {
      expect(
        comicTapAction(
          dx: 950,
          width: 1000,
          direction: ComicReadingDirection.leftToRight,
        ),
        ComicTapAction.next,
      );
    });
  });

  test('reader options survive a restart', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await ReaderPrefs.load()).doubleTapZoom, isFalse);
    await const ReaderPrefs(
      orientation: ReaderOrientation.landscape,
      tapLayout: ComicTapLayout.kindle,
      doubleTapZoom: true,
    ).save();
    final loaded = await ReaderPrefs.load();
    expect(loaded.orientation, ReaderOrientation.landscape);
    expect(loaded.tapLayout, ComicTapLayout.kindle);
    expect(loaded.doubleTapZoom, isTrue);
  });
}

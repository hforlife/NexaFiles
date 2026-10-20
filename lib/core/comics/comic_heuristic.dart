import '../archives/archive_core.dart';
import 'comic_page_source.dart';

class ComicHeuristic {
  const ComicHeuristic({this.minimumImages = 5, this.minimumImageRatio = .7});
  final int minimumImages;
  final double minimumImageRatio;
  bool isComic(Iterable<ArchiveEntry> entries) {
    final files = entries
            .where((e) => !e.isDirectory && !_ignored(e.path))
            .toList(),
        images = files.where((e) => isComicImage(e.path)).length;
    return images >= minimumImages &&
        files.isNotEmpty &&
        images / files.length >= minimumImageRatio;
  }

  bool _ignored(String path) {
    final name = path.split('/').last.toLowerCase();
    return name.startsWith('.') ||
        name == 'thumbs.db' ||
        name == 'comicinfo.xml' ||
        path.contains('__MACOSX');
  }
}

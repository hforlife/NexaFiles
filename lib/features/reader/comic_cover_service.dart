import 'dart:io';
import 'dart:ui' as ui;
import '../../core/cache/cache_manager.dart';
import '../../core/comics/comic_page_source.dart';
import '../../core/database/app_database.dart';

class ComicCoverService {
  ComicCoverService(this.cache, this.database);
  final CacheManager cache;
  final AppDatabase database;
  Future<void> ensureCover(String itemId, ComicPageSource source) async {
    try {
      final page = await source.getPage(0),
          codec = await ui.instantiateImageCodec(page.bytes, targetWidth: 300),
          frame = await codec.getNextFrame(),
          data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final dir = await cache.directory(CacheCategory.covers),
          file = File('${dir.path}/${itemId.hashCode.toUnsigned(32)}.png');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await database.updateCover(itemId, file.path);
      frame.image.dispose();
      codec.dispose();
    } catch (_) {}
  }
}

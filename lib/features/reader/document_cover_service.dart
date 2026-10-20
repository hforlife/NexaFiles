import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../../core/cache/cache_manager.dart';
import '../../core/database/app_database.dart';
import '../../core/readers/document_adapters.dart';

class DocumentCoverService {
  DocumentCoverService(this.cache, this.database);
  final CacheManager cache;
  final AppDatabase database;
  Future<void> ensurePdf(String itemId, PdfReaderSession session) async {
    try {
      await _save(itemId, await session.renderThumbnail(0));
    } catch (_) {}
  }

  Future<void> ensureEpub(String itemId, EpubReaderSession session) async {
    final bytes = session.coverBytes;
    if (bytes == null) return;
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 300),
          frame = await codec.getNextFrame(),
          data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data != null) await _save(itemId, data.buffer.asUint8List());
      frame.image.dispose();
      codec.dispose();
    } catch (_) {}
  }

  Future<void> _save(String itemId, Uint8List bytes) async {
    final dir = await cache.directory(CacheCategory.covers),
        file = File('${dir.path}/${itemId.hashCode.toUnsigned(32)}.png');
    await file.writeAsBytes(bytes, flush: true);
    await database.updateCover(itemId, file.path);
    await cache.enforceLimit();
  }
}

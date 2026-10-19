import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum CacheCategory { covers, comicPages, archiveTemp, readerTemp }

class CacheManager {
  CacheManager({this.maxBytes = 536870912});
  final int maxBytes;
  Future<Directory> directory(CacheCategory category) async {
    final root = await getTemporaryDirectory(),
        dir = Directory(p.join(root.path, 'nexa_cache', category.name));
    await dir.create(recursive: true);
    return dir;
  }

  Future<int> usage([CacheCategory? category]) async {
    final roots = category == null ? CacheCategory.values : [category];
    var total = 0;
    for (final value in roots) {
      final dir = await directory(value);
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) total += await entity.length();
      }
    }
    return total;
  }

  Future<void> remove(CacheCategory category, String key) async {
    final root = await directory(category),
        candidate = File(p.join(root.path, p.basename(key)));
    if (await candidate.exists()) await candidate.delete();
  }

  Future<void> clear(CacheCategory category) async {
    final dir = await directory(category);
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
  }

  Future<void> clearAll() async {
    for (final category in CacheCategory.values) {
      await clear(category);
    }
  }

  Future<void> enforceLimit() async {
    if (await usage() <= maxBytes) return;
    final files = <File>[];
    for (final category in CacheCategory.values) {
      final dir = await directory(category);
      files.addAll(await dir
          .list(recursive: true)
          .where((e) => e is File)
          .cast<File>()
          .toList());
    }
    files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    for (final file in files) {
      await file.delete();
      if (await usage() <= maxBytes) return;
    }
  }
}

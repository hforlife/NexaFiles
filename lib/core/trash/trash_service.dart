import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/storage_entry.dart';
import '../storage/storage_repository.dart';

class TrashItem {
  const TrashItem({
    required this.id,
    required this.name,
    required this.originalParent,
    required this.trashUri,
    required this.deletedAt,
    this.size,
  });
  final String id, name, originalParent, trashUri;
  final DateTime deletedAt;
  final int? size;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'originalParent': originalParent,
    'trashUri': trashUri,
    'deletedAt': deletedAt.millisecondsSinceEpoch,
    'size': size,
  };
  factory TrashItem.fromJson(Map<String, dynamic> j) => TrashItem(
    id: j['id'],
    name: j['name'],
    originalParent: j['originalParent'],
    trashUri: j['trashUri'],
    deletedAt: DateTime.fromMillisecondsSinceEpoch(j['deletedAt']),
    size: j['size'],
  );
}

class TrashService {
  TrashService(this.storage);
  final StorageRepository storage;
  // v2: entries are file:// paths (v1 held SAF URIs, no longer reachable).
  static const key = 'nexa.trash.v2';
  Future<List<TrashItem>> list() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(key) ?? const [])
        .map((e) => TrashItem.fromJson(jsonDecode(e)))
        .toList();
  }

  Future<void> _save(List<TrashItem> items) async =>
      (await SharedPreferences.getInstance()).setStringList(
        key,
        items.map((e) => jsonEncode(e.toJson())).toList(),
      );
  Future<bool> moveToTrash(
    StorageEntry entry,
    Uri originalParent,
    Uri root,
  ) async {
    try {
      final children = await storage.list(root);
      var trash = children
          .where(
            (e) =>
                e.kind == StorageEntryKind.directory &&
                e.displayName == '.NexaTrash',
          )
          .firstOrNull;
      trash ??= await storage.createDirectory(root, '.NexaTrash');
      final moved = await storage.move(
        entry.uri,
        trash.uri,
        targetName:
            '${DateTime.now().microsecondsSinceEpoch}_${entry.displayName}',
      );
      final items = await list();
      items.add(
        TrashItem(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          name: entry.displayName,
          originalParent: '$originalParent',
          trashUri: '${moved.uri}',
          deletedAt: DateTime.now(),
          size: entry.size,
        ),
      );
      await _save(items);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> restore(TrashItem item) async {
    final target = Uri.parse(item.originalParent),
        names = (await storage.list(
          target,
        )).map((e) => e.displayName.toLowerCase()).toSet();
    var name = item.name, index = 2;
    while (names.contains(name.toLowerCase())) {
      final dot = item.name.lastIndexOf('.');
      name = dot > 0
          ? '${item.name.substring(0, dot)} ($index)${item.name.substring(dot)}'
          : '${item.name} ($index)';
      index++;
    }
    await storage.move(Uri.parse(item.trashUri), target, targetName: name);
    final items = await list()
      ..removeWhere((e) => e.id == item.id);
    await _save(items);
  }

  Future<void> deletePermanently(TrashItem item) async {
    await storage.delete(Uri.parse(item.trashUri));
    final items = await list()
      ..removeWhere((e) => e.id == item.id);
    await _save(items);
  }

  /// Deletes for good what has been in the trash longer than [age].
  Future<int> purgeOlderThan(Duration age) async {
    final limit = DateTime.now().subtract(age);
    var purged = 0;
    for (final item in await list()) {
      if (!item.deletedAt.isBefore(limit)) continue;
      try {
        await deletePermanently(item);
        purged++;
      } catch (_) {}
    }
    return purged;
  }

  Future<void> empty() async {
    for (final item in await list()) {
      try {
        await storage.delete(Uri.parse(item.trashUri));
      } catch (_) {}
    }
    await _save([]);
  }
}

import 'dart:collection';
import 'package:flutter/services.dart';
import '../storage/storage_entry.dart';

class FilePreviewService {
  FilePreviewService._();
  static final instance = FilePreviewService._();
  static const _channel = MethodChannel('nexa_file/storage');
  final LinkedHashMap<String, Future<Uint8List?>> _memory = LinkedHashMap();
  Future<Uint8List?> imageThumbnail(StorageEntry entry) {
    final key = '${entry.uri}@${entry.modifiedAt?.millisecondsSinceEpoch}';
    final hit = _memory.remove(key);
    if (hit != null) {
      _memory[key] = hit;
      return hit;
    }
    final value = _channel
        .invokeMethod<Uint8List>('thumbnail', {'uri': '${entry.uri}'})
        .catchError((_) => null)
        .then((v) => v == null || v.isEmpty ? null : v);
    _memory[key] = value;
    while (_memory.length > 32) {
      _memory.remove(_memory.keys.first);
    }
    return value;
  }
}

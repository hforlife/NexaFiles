import 'dart:collection';
import 'package:flutter/services.dart';
import '../storage/storage_entry.dart';

/// Tags and embedded cover read from an audio file.
class AudioInfo {
  const AudioInfo({this.title, this.artist, this.album, this.art});
  final String? title, artist, album;
  final Uint8List? art;
  static const empty = AudioInfo();
}

/// Thumbnails and audio tags from the platform. Thumbnails are cached on
/// disk natively; this keeps the recent ones in memory so scrolling back
/// does not even cross the channel.
class FilePreviewService {
  FilePreviewService._();
  static final instance = FilePreviewService._();
  static const _channel = MethodChannel('nexa_file/storage');
  static const _memoryLimit = 160;
  final LinkedHashMap<String, Future<Uint8List?>> _memory = LinkedHashMap();
  final Map<String, Future<AudioInfo>> _audio = {};

  Future<Uint8List?> imageThumbnail(StorageEntry entry) {
    final key = '${entry.uri}@${entry.modifiedAt?.millisecondsSinceEpoch}';
    final hit = _memory.remove(key);
    if (hit != null) {
      _memory[key] = hit;
      return hit;
    }
    final value = _channel
        .invokeMethod<Uint8List>('thumbnail', {'path': entry.uri.toFilePath()})
        .catchError((_) => null)
        .then((v) => v == null || v.isEmpty ? null : v);
    _memory[key] = value;
    while (_memory.length > _memoryLimit) {
      _memory.remove(_memory.keys.first);
    }
    return value;
  }

  /// Title, artist, album and cover of the audio file at [uri].
  Future<AudioInfo> audioInfo(String uri) {
    if (_audio.length > 64) _audio.clear();
    return _audio[uri] ??= _channel
        .invokeMapMethod<String, Object?>('audioInfo', {
          'path': Uri.parse(uri).toFilePath(),
        })
        .then((m) {
          String? text(String key) {
            final v = (m?[key] as String?)?.trim();
            return v == null || v.isEmpty ? null : v;
          }

          return AudioInfo(
            title: text('title'),
            artist: text('artist'),
            album: text('album'),
            art: m?['art'] as Uint8List?,
          );
        })
        .catchError((_) => AudioInfo.empty);
  }
}

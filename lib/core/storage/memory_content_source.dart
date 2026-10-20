import 'dart:typed_data';
import 'content_source.dart';

class MemoryContentSource implements ContentSource {
  MemoryContentSource({
    required this.id,
    required this.displayName,
    required this.bytes,
  });
  @override
  final String id;
  @override
  final String displayName;
  final Uint8List bytes;
  @override
  Future<int?> get length async => bytes.length;
  @override
  Future<Stream<List<int>>> openRead() async => Stream.value(bytes);
}

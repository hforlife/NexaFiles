import 'dart:io';

abstract interface class ContentSource {
  String get id;
  String get displayName;
  Future<int?> get length;
  Future<Stream<List<int>>> openRead();
}

abstract interface class MaterializedContentSource implements ContentSource {
  Future<File> materialize();
}

import '../errors/app_failure.dart';

class ArchiveSafetyPolicy {
  const ArchiveSafetyPolicy({
    this.maxEntries = 10000,
    this.maxTotalBytes = 2147483648,
    this.maxEntryBytes = 536870912,
    this.maxCompressionRatio = 200,
    this.maxDepth = 32,
  });
  final int maxEntries, maxTotalBytes, maxEntryBytes, maxDepth;
  final double maxCompressionRatio;
  void validate(
    Iterable<({String path, int compressedSize, int uncompressedSize})>
    entries, {
    int? availableBytes,
  }) {
    final values = entries.toList();
    if (values.length > maxEntries) {
      throw const ArchiveFailure('Archive contenant trop de fichiers');
    }
    var total = 0;
    for (final entry in values) {
      final path = entry.path.replaceAll('\\', '/');
      final parts = path.split('/');
      if (path.startsWith('/') ||
          RegExp(r'^[A-Za-z]:/').hasMatch(path) ||
          parts.contains('..')) {
        throw const ArchiveFailure('Chemin dangereux dans l’archive');
      }
      if (parts.where((p) => p.isNotEmpty).length > maxDepth) {
        throw const ArchiveFailure('Archive trop profonde');
      }
      if (entry.uncompressedSize < 0 ||
          entry.compressedSize < 0 ||
          entry.uncompressedSize > maxEntryBytes) {
        throw const ArchiveFailure('Entrée d’archive trop volumineuse');
      }
      if ((entry.compressedSize == 0 && entry.uncompressedSize > 0) ||
          (entry.compressedSize > 0 &&
              entry.uncompressedSize / entry.compressedSize >
                  maxCompressionRatio)) {
        throw const ArchiveFailure('Ratio de compression dangereux');
      }
      total += entry.uncompressedSize;
      if (total > maxTotalBytes) {
        throw const ArchiveFailure('Archive trop volumineuse');
      }
    }
    if (availableBytes != null && total > availableBytes) {
      throw const InsufficientSpaceFailure();
    }
  }
}

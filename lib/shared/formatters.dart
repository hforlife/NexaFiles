/// Human readable size, e.g. `12.3 Mo`.
String formatBytes(int? bytes) {
  if (bytes == null || bytes < 0) return 'Taille inconnue';
  if (bytes < 1024) return '$bytes o';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
  if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} Mo';
  return '${(bytes / 1073741824).toStringAsFixed(1)} Go';
}

/// Title derived from a file name: extension removed, `_`/`-` turned into spaces.
String fallbackTitle(String name) {
  final dot = name.lastIndexOf('.');
  final value = (dot > 0 ? name.substring(0, dot) : name)
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim();
  return value.isEmpty ? name : value;
}

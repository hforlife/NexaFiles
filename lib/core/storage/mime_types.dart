const _mimeByExtension = {
  // Images
  'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
  'gif': 'image/gif', 'webp': 'image/webp', 'bmp': 'image/bmp',
  'heic': 'image/heic', 'heif': 'image/heif', 'svg': 'image/svg+xml',
  // Video
  'mp4': 'video/mp4', 'm4v': 'video/mp4', 'mkv': 'video/x-matroska',
  'webm': 'video/webm', 'mov': 'video/quicktime', 'avi': 'video/x-msvideo',
  '3gp': 'video/3gpp',
  // Audio
  'mp3': 'audio/mpeg', 'm4a': 'audio/mp4', 'aac': 'audio/aac',
  'ogg': 'audio/ogg', 'opus': 'audio/opus', 'wav': 'audio/wav',
  'flac': 'audio/flac',
  // Documents & reading
  'pdf': 'application/pdf', 'epub': 'application/epub+zip',
  'txt': 'text/plain', 'md': 'text/markdown', 'markdown': 'text/markdown',
  'html': 'text/html', 'htm': 'text/html', 'csv': 'text/csv',
  'json': 'application/json', 'xml': 'text/xml',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'odt': 'application/vnd.oasis.opendocument.text',
  'cbz': 'application/vnd.comicbook+zip',
  'cbr': 'application/vnd.comicbook-rar', 'cb7': 'application/x-cb7',
  // Archives & apps
  'zip': 'application/zip', 'rar': 'application/vnd.rar',
  '7z': 'application/x-7z-compressed', 'tar': 'application/x-tar',
  'gz': 'application/gzip',
  'apk': 'application/vnd.android.package-archive',
};

/// MIME type guessed from the file extension, or null when unknown.
String? mimeTypeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  return _mimeByExtension[fileName.substring(dot + 1).toLowerCase()];
}

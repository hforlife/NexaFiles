enum ContainerFormat { none, zip, rar, sevenZip }

enum ContentKind {
  pdf,
  epub,
  comic,
  image,
  audio,
  video,
  text,
  markdown,
  officeWord,
  officeSpreadsheet,
  officePresentation,
  apk,
  archive,
  unknown
}

class DetectedFormat {
  const DetectedFormat(
      {required this.container,
      required this.content,
      required this.confidence,
      this.evidence = const []});
  final ContainerFormat container;
  final ContentKind content;
  final double confidence;
  final List<String> evidence;
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/local_storage_repository.dart';
import '../storage/storage_repository.dart';
import '../readers/reader_core.dart';
import '../archives/archive_core.dart';
import '../archives/zip_archive_adapter.dart';
import '../archives/native_archive_adapter.dart';
import '../archives/tar_archive_adapter.dart';
import '../formats/detected_format.dart';
import '../comics/comic_reader_adapter.dart';
import '../readers/document_adapters.dart';
import '../readers/media_adapters.dart';

final storageRepositoryProvider = Provider<StorageRepository>(
  (_) => LocalStorageRepository(),
);
final archiveRegistryProvider = Provider<ArchiveRegistry>(
  (_) => ArchiveRegistry([
    ZipArchiveAdapter(),
    NativeArchiveAdapter(ContainerFormat.rar),
    NativeArchiveAdapter(ContainerFormat.sevenZip),
    TarFamilyAdapter(),
  ]),
);
final readerRegistryProvider = Provider<ReaderRegistry>(
  (ref) => ReaderRegistry([
    ComicReaderAdapter(ref.read(archiveRegistryProvider)),
    PdfReaderAdapter(),
    const EpubReaderAdapter(),
    const TextReaderAdapter(),
    const ImageReaderAdapter(),
    const MediaReaderAdapter(),
    const DocxReaderAdapter(),
  ]),
);

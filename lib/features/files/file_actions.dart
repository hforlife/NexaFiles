import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/archives/archive_core.dart';
import '../../core/cache/file_preview_service.dart';
import '../../core/errors/app_failure.dart';
import '../../core/formats/detected_format.dart';
import '../../core/formats/format_detector.dart';
import '../../core/platform/providers.dart';
import '../../core/storage/storage_entry.dart';
import '../../core/trash/trash_service.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/text_prompt.dart';
import '../archives/archive_browser_screen.dart';
import '../archives/archive_creator.dart';
import '../archives/archive_extraction_service.dart';
import 'destination_picker.dart';
import 'file_operation_service.dart';
import 'file_tiles.dart';
import 'files_controller.dart';
import '../home/home_link.dart';
import '../operations/operations_controller.dart';

/// Archives NexaFiles can extract (comic archives included).
bool isExtractable(StorageEntry entry) =>
    entry.kind == StorageEntryKind.file &&
    RegExp(
      r'\.(zip|rar|7z|cbz|cbr|cb7|tar|gz|tgz|bz2|tbz2|xz|txz)$',
      caseSensitive: false,
    ).hasMatch(entry.displayName);

/// One file action: (value, icon, label); null marks a separator.
typedef FileActionSpec = (String, IconData, String)?;

/// Actions offered for [entry], shared by menus and sheets.
List<FileActionSpec> fileActionSpecs(
  StorageEntry entry, {
  bool favorite = false,
  bool canFavorite = false,
}) {
  final file = entry.kind == StorageEntryKind.file;
  return [
    if (isExtractable(entry)) ...[
      ('extract_folder', Icons.unarchive_rounded, 'Extraire dans un dossier'),
      ('extract_here', Icons.move_to_inbox_rounded, 'Extraire ici'),
      ('extract_to', Icons.drive_file_move_rounded, 'Extraire vers…'),
      ('browse', Icons.folder_zip_outlined, 'Parcourir l’archive'),
      null,
    ],
    ('compress', Icons.archive_outlined, 'Compresser…'),
    if (file) ('open', Icons.open_in_new_rounded, 'Ouvrir avec…'),
    if (file) ('share', Icons.ios_share_rounded, 'Partager'),
    ('rename', Icons.edit_outlined, 'Renommer'),
    if (!file)
      (
        'shortcut',
        Icons.add_to_home_screen_rounded,
        'Raccourci sur l’écran d’accueil',
      ),
    if (canFavorite && !file)
      (
        'favorite',
        favorite ? Icons.star_rounded : Icons.star_outline_rounded,
        favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
      ),
    ('info', Icons.info_outline_rounded, 'Informations'),
    ('delete', Icons.delete_outline_rounded, 'Supprimer'),
  ];
}

/// Popup menu entries for [entry].
List<PopupMenuEntry<String>> fileMenuItems(
  StorageEntry entry, {
  bool favorite = false,
  bool canFavorite = false,
}) => [
  for (final spec in fileActionSpecs(
    entry,
    favorite: favorite,
    canFavorite: canFavorite,
  ))
    if (spec == null)
      const PopupMenuDivider()
    else
      PopupMenuItem(
        value: spec.$1,
        child: Row(
          children: [
            Icon(spec.$2, size: 20),
            const SizedBox(width: 12),
            Text(spec.$3),
          ],
        ),
      ),
];

/// Bottom sheet of actions (long press in grids); returns the chosen one.
Future<String?> showFileActionsSheet(
  BuildContext context,
  StorageEntry entry,
) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (c) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: SizedBox.square(
              dimension: 44,
              child: EntryVisual(entry: entry, item: null, size: 44),
            ),
            title: Text(
              entry.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(formatBytes(entry.size)),
          ),
          const Divider(),
          for (final spec in fileActionSpecs(entry))
            if (spec == null)
              const Divider()
            else
              ListTile(
                leading: Icon(spec.$2),
                title: Text(spec.$3),
                onTap: () => Navigator.pop(c, spec.$1),
              ),
        ],
      ),
    ),
  ),
);

/// Runs file actions from any screen. [onChanged] refreshes the caller's
/// list after an action that modifies the storage.
class FileActions {
  FileActions(this.context, this.ref, {required this.onChanged});
  final BuildContext context;
  final WidgetRef ref;
  final Future<void> Function() onChanged;

  /// Handles the shared actions; returns false for unknown ones.
  Future<bool> handle(String action, StorageEntry entry) async {
    switch (action) {
      case 'open':
        await _guard(
          () => ref
              .read(storageRepositoryProvider)
              .openExternal(entry.uri, mimeType: entry.mimeType),
        );
      case 'share':
        await share([entry]);
      case 'rename':
        await rename(entry);
      case 'info':
        await showFileInfo(context, entry);
      case 'delete':
        await delete([entry]);
      case 'extract_here':
        await _extract(entry, _ExtractTarget.here);
      case 'extract_folder':
        await _extract(entry, _ExtractTarget.folder);
      case 'extract_to':
        await _extract(entry, _ExtractTarget.choose);
      case 'browse':
        await browse(entry);
      case 'compress':
        await compress([entry]);
      case 'shortcut':
        final ok = await HomeLink.pinFolder(
          entry.uri.toFilePath(),
          entry.displayName,
        );
        if (!ok) {
          _message('Votre écran d’accueil ne permet pas les raccourcis.');
        }
      default:
        return false;
    }
    return true;
  }

  Future<void> share(List<StorageEntry> entries) async {
    final files = [
      for (final e in entries)
        if (e.kind == StorageEntryKind.file) e,
    ];
    if (files.isEmpty) {
      _message('Sélectionnez au moins un fichier.');
      return;
    }
    await _guard(
      () => ref
          .read(storageRepositoryProvider)
          .share(
            files.map((e) => e.uri).toList(),
            mimeType: files.length == 1 ? files.first.mimeType : null,
          ),
    );
  }

  Future<void> rename(StorageEntry entry) async {
    final name = await askName(context, 'Renommer', entry.displayName);
    if (name == null || name == entry.displayName) return;
    await _guard(() async {
      await ref.read(storageRepositoryProvider).rename(entry.uri, name);
      _message('Élément renommé');
      await onChanged();
    });
  }

  /// Moves [entries] to the trash of their volume; offers a permanent
  /// delete for what cannot be trashed.
  Future<void> delete(List<StorageEntry> entries) async {
    if (entries.isEmpty) return;
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(
              entries.length == 1
                  ? 'Mettre « ${entries.first.displayName} » à la corbeille ?'
                  : 'Mettre ${entries.length} éléments à la corbeille ?',
            ),
            content: const Text(
              'Vous pourrez les restaurer depuis Outils › Corbeille.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Mettre à la corbeille'),
              ),
            ],
          ),
        ) ??
        false;
    if (!yes) return;
    final storage = ref.read(storageRepositoryProvider);
    final roots = ref.read(filesControllerProvider).roots;
    final trash = TrashService(storage), failed = <StorageEntry>[];
    var moved = 0;
    for (final entry in entries) {
      final path = entry.uri.toFilePath();
      final root = roots
          .where((r) => p.isWithin(r.uri.toFilePath(), path))
          .firstOrNull;
      final ok =
          root != null &&
          await trash.moveToTrash(entry, Uri.file(p.dirname(path)), root.uri);
      ok ? moved++ : failed.add(entry);
    }
    if (failed.isNotEmpty && context.mounted) {
      final permanent =
          await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text('${failed.length} élément(s) non déplaçable(s)'),
              content: const Text(
                'Ces éléments ne peuvent pas aller dans la corbeille. Les '
                'supprimer définitivement ?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Conserver'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Supprimer définitivement'),
                ),
              ],
            ),
          ) ??
          false;
      if (permanent) {
        moved += (await FileOperationService(
          storage,
        ).deleteAll(failed)).succeeded;
      }
    }
    await onChanged();
    _message('$moved élément(s) traité(s)');
  }

  /// Removes [entries] without asking: to the trash of their volume, or
  /// for good when [permanent]. Returns how many were removed.
  Future<int> removeEntries(
    List<StorageEntry> entries, {
    required bool permanent,
  }) async {
    final storage = ref.read(storageRepositoryProvider);
    var removed = 0;
    if (permanent) {
      removed = (await FileOperationService(
        storage,
      ).deleteAll(entries)).succeeded;
    } else {
      final roots = ref.read(filesControllerProvider).roots;
      final trash = TrashService(storage);
      for (final entry in entries) {
        final path = entry.uri.toFilePath();
        final root = roots
            .where((r) => p.isWithin(r.uri.toFilePath(), path))
            .firstOrNull;
        if (root != null &&
            await trash.moveToTrash(
              entry,
              Uri.file(p.dirname(path)),
              root.uri,
            )) {
          removed++;
        }
      }
    }
    await onChanged();
    return removed;
  }

  /// Opens the in-app archive browser.
  Future<void> browse(StorageEntry entry) async {
    final session = await _openArchive(entry);
    if (session == null || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArchiveBrowserScreen(
          name: entry.displayName,
          session: session,
          storage: ref.read(storageRepositoryProvider),
          roots: ref.read(filesControllerProvider).roots,
          defaultDestination: Uri.file(p.dirname(entry.uri.toFilePath())),
        ),
      ),
    );
    await onChanged();
  }

  Future<void> _extract(StorageEntry entry, _ExtractTarget target) async {
    final storage = ref.read(storageRepositoryProvider);
    final parent = Uri.file(p.dirname(entry.uri.toFilePath()));
    // Archive (and password) first: cancelling leaves nothing behind.
    final session = await _openArchive(entry);
    if (session == null || !context.mounted) return;
    Uri? destination;
    switch (target) {
      case _ExtractTarget.here:
        destination = parent;
      case _ExtractTarget.choose:
        destination = await Navigator.push<Uri>(
          context,
          MaterialPageRoute(
            builder: (_) => DestinationPicker(
              storage: storage,
              roots: ref.read(filesControllerProvider).roots,
              title: 'Extraire vers…',
            ),
          ),
        );
      case _ExtractTarget.folder:
        // An archive already wrapped in one folder ("Projet/…") goes
        // straight next to it, instead of "Projet/Projet/…".
        final root = singleRootFolder(await session.listEntries());
        if (root != null && await _uniqueName(parent, root) == root) {
          destination = parent;
          break;
        }
        final name = await _uniqueName(parent, _archiveBase(entry.displayName));
        final folder = await _guard(
          () => storage.createDirectory(parent, name),
        );
        destination = folder?.uri;
    }
    if (destination == null) {
      await session.close();
      return;
    }
    final target0 = destination;
    ref
        .read(operationsProvider)
        .start(
          kind: OperationKind.extract,
          title: 'Extraction de ${entry.displayName}',
          destination: target0,
          run: (token) => _closingWhenDone(
            ArchiveExtractionService(storage)
                .extract(session, target0, cancellation: token)
                .map(
                  (e) => OperationProgress(
                    done: e.completed,
                    total: e.total,
                    current: e.current,
                    finished: e.done,
                  ),
                ),
            session.close,
          ),
          onDone: onChanged,
        );
  }

  /// Compresses [entries] into a new archive next to them.
  Future<void> compress(List<StorageEntry> entries) async {
    if (entries.isEmpty) return;
    final parent = Uri.file(p.dirname(entries.first.uri.toFilePath()));
    final suggested = entries.length == 1
        ? (entries.first.kind == StorageEntryKind.directory
              ? entries.first.displayName
              : p.basenameWithoutExtension(entries.first.displayName))
        : p.basename(parent.toFilePath());
    final choice = await showDialog<_CompressChoice>(
      context: context,
      builder: (_) => _CompressDialog(
        initialName: suggested.isEmpty ? 'Archive' : suggested,
        count: entries.length,
      ),
    );
    if (choice == null) return;
    final name = await _uniqueName(
      parent,
      '${choice.name}.${choice.kind.extension}',
    );
    final output = p.join(parent.toFilePath(), name);
    ref
        .read(operationsProvider)
        .start(
          kind: OperationKind.compress,
          title: 'Compression de $name',
          destination: parent,
          run: (token) => ArchiveCreator().create(
            sources: [for (final e in entries) e.uri.toFilePath()],
            output: output,
            kind: choice.kind,
            password: choice.password,
            token: token,
          ),
          onDone: onChanged,
        );
  }

  /// "name", "name (2)", "name (3)"… — first one free in [parent].
  Future<String> _uniqueName(Uri parent, String wanted) async {
    final taken = {
      for (final e in await ref.read(storageRepositoryProvider).list(parent))
        e.displayName.toLowerCase(),
    };
    if (!taken.contains(wanted.toLowerCase())) return wanted;
    // Keep a compound extension (".tar.gz") after the counter.
    final match = RegExp(r'^(.*?)((\.tar)?\.[^.]+)?$').firstMatch(wanted)!;
    final base = match.group(1)!, ext = match.group(2) ?? '';
    for (var i = 2; ; i++) {
      final name = '$base ($i)$ext';
      if (!taken.contains(name.toLowerCase())) return name;
    }
  }

  /// Opens [entry] as an archive, asking for its password when needed
  /// and checking it on the smallest encrypted entry (3 attempts).
  Future<ArchiveSession?> _openArchive(StorageEntry entry) async {
    final storage = ref.read(storageRepositoryProvider);
    final DetectedFormat format;
    try {
      final prefix = await storage.readPrefix(entry.uri);
      final detected = FormatDetector().detect(
        prefix: prefix,
        mimeType: entry.mimeType,
        fileName: entry.displayName,
      );
      if (detected.container == ContainerFormat.none) {
        throw const FormatException('Format d’archive non pris en charge');
      }
      // Comics are archives too: extract them like any ZIP / RAR / 7z.
      format = DetectedFormat(
        container: detected.container,
        content: ContentKind.archive,
        confidence: detected.confidence,
        evidence: detected.evidence,
      );
    } catch (e) {
      _message(_text(e));
      return null;
    }
    String? password;
    var wrong = false;
    for (var attempt = 0; attempt < 4; attempt++) {
      ArchiveSession? session;
      try {
        session = await ref
            .read(archiveRegistryProvider)
            .open(storage.sourceFor(entry), format, password: password);
        final locked = [
          for (final e in await session.listEntries())
            if (e.encrypted && !e.isDirectory) e,
        ]..sort((a, b) => a.uncompressedSize.compareTo(b.uncompressedSize));
        if (locked.isEmpty) return session;
        if (password == null) throw const PasswordRequiredFailure();
        await session.openEntry(locked.first); // throws on a wrong password
        return session;
      } on PasswordRequiredFailure {
        await session?.close();
      } on WrongPasswordFailure {
        await session?.close();
        wrong = true;
      } catch (e) {
        await session?.close();
        _message(_text(e));
        return null;
      }
      if (!context.mounted || attempt == 3) return null;
      password = await askPassword(context, entry.displayName, wrong: wrong);
      if (password == null) return null;
    }
    return null;
  }

  static String _text(Object e) => e is AppFailure
      ? e.userMessage
      : e.toString().replaceFirst(RegExp(r'^\w+(Failure|Exception): '), '');

  Future<T?> _guard<T>(Future<T> Function() task) async {
    try {
      return await task();
    } catch (e) {
      _message(_text(e));
      return null;
    }
  }

  void _message(String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

enum _ExtractTarget { here, folder, choose }

/// The only top-level folder of an archive, or null when entries sit at
/// the root or under several folders.
String? singleRootFolder(List<ArchiveEntry> entries) {
  String? root;
  for (final e in entries) {
    final parts = e.path
        .replaceAll('\\', '/')
        .split('/')
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) continue;
    // A file at the top level means there is no wrapping folder.
    if (parts.length == 1 && !e.isDirectory) return null;
    if (root == null) {
      root = parts.first;
    } else if (root != parts.first) {
      return null;
    }
  }
  return root;
}

/// "photos.tar.gz" → "photos", "manga.cbz" → "manga".
String _archiveBase(String name) =>
    name.replaceFirst(RegExp(r'(\.tar)?\.[^.]+$', caseSensitive: false), '');

/// Forwards [stream] and runs [cleanup] once it ends, whatever the outcome.
Stream<T> _closingWhenDone<T>(
  Stream<T> stream,
  Future<void> Function() cleanup,
) {
  final controller = StreamController<T>();
  controller.onListen = () {
    stream.listen(
      controller.add,
      onError: (Object e, StackTrace st) async {
        await cleanup();
        controller.addError(e, st);
        await controller.close();
      },
      onDone: () async {
        await cleanup();
        await controller.close();
      },
      cancelOnError: true,
    );
  };
  return controller.stream;
}

/// Asks for an archive password; null when cancelled.
Future<String?> askPassword(
  BuildContext context,
  String archive, {
  bool wrong = false,
}) async {
  final value = await showTextPrompt(
    context,
    icon: Icons.lock_rounded,
    title: 'Archive protégée',
    message: wrong
        ? 'Mot de passe incorrect pour « $archive ». Réessayez.'
        : '« $archive » est protégée par un mot de passe.',
    hint: 'Mot de passe',
    errorText: wrong ? 'Mot de passe incorrect' : null,
    confirm: 'Déverrouiller',
    obscure: true,
  );
  return value == null || value.isEmpty ? null : value;
}

class _CompressChoice {
  const _CompressChoice(this.name, this.kind, this.password);
  final String name;
  final ArchiveKind kind;
  final String? password;
}

/// Name, format and optional password of a new archive.
class _CompressDialog extends StatefulWidget {
  const _CompressDialog({required this.initialName, required this.count});
  final String initialName;
  final int count;
  @override
  State<_CompressDialog> createState() => _CompressDialogState();
}

class _CompressDialogState extends State<_CompressDialog> {
  late final name = TextEditingController(text: widget.initialName);
  final password = TextEditingController();
  ArchiveKind kind = ArchiveKind.zip;
  bool protect = false, hidden = true;

  @override
  void dispose() {
    name.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.archive_rounded),
    title: Text(
      widget.count == 1 ? 'Compresser' : 'Compresser ${widget.count} éléments',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Nom de l’archive',
              suffixText: '.${kind.extension}',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ArchiveKind>(
              showSelectedIcon: false,
              segments: [
                for (final k in ArchiveKind.values)
                  ButtonSegment(value: k, label: Text(k.label)),
              ],
              selected: {kind},
              onSelectionChanged: (v) => setState(() => kind = v.first),
            ),
          ),
          const SizedBox(height: 8),
          if (kind.supportsPassword) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: protect,
              title: const Text('Protéger par mot de passe'),
              subtitle: const Text('Chiffrement AES-256'),
              onChanged: (v) => setState(() => protect = v),
            ),
            if (protect)
              TextField(
                controller: password,
                obscureText: hidden,
                decoration: InputDecoration(
                  hintText: 'Mot de passe',
                  suffixIcon: IconButton(
                    tooltip: hidden ? 'Afficher' : 'Masquer',
                    onPressed: () => setState(() => hidden = !hidden),
                    icon: Icon(
                      hidden
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                  ),
                ),
              ),
          ] else
            Text(
              kind == ArchiveKind.sevenZip
                  ? 'Le mot de passe est disponible avec le format ZIP.'
                  : 'TAR.GZ : idéal pour les sauvegardes, sans mot de passe.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () {
          final value = name.text.trim();
          if (value.isEmpty) return;
          if (protect && kind.supportsPassword && password.text.isEmpty) {
            return;
          }
          Navigator.pop(
            context,
            _CompressChoice(
              value,
              kind,
              protect && kind.supportsPassword ? password.text : null,
            ),
          );
        },
        child: const Text('Compresser'),
      ),
    ],
  );
}

/// Asks for a name; returns null when cancelled or empty.
Future<String?> askName(
  BuildContext context,
  String title,
  String initial,
) async {
  final name = (await showTextPrompt(
    context,
    title: title,
    initial: initial,
    selectBaseName: true,
  ))?.trim();
  return name == null || name.isEmpty ? null : name;
}

/// Details of a file or folder, with an advanced section.
Future<void> showFileInfo(BuildContext context, StorageEntry entry) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FileInfoSheet(entry: entry),
    );

class _FileInfoSheet extends ConsumerStatefulWidget {
  const _FileInfoSheet({required this.entry});
  final StorageEntry entry;
  @override
  ConsumerState<_FileInfoSheet> createState() => _FileInfoSheetState();
}

class _FileInfoSheetState extends ConsumerState<_FileInfoSheet> {
  late final Future<Map<String, String>> advanced = _advanced();

  StorageEntry get entry => widget.entry;
  bool get isDir => entry.kind == StorageEntryKind.directory;

  Future<Map<String, String>> _advanced() async {
    final path = entry.uri.toFilePath();
    final values = <String, String>{};
    try {
      final stat = await FileStat.stat(path);
      values['Droits'] = stat.modeString();
      values['Accès'] = [
        stat.accessed.year > 1970 ? _date(stat.accessed) : null,
      ].whereType<String>().join();
      if (values['Accès']!.isEmpty) values.remove('Accès');
    } catch (_) {}
    values['Masqué'] = entry.displayName.startsWith('.') ? 'Oui' : 'Non';
    if (isDir) {
      // compute(): a closure created here would drag this State along.
      final (files, dirs, bytes, partial) = await compute(_folderStats, path);
      values['Contenu'] =
          '$files fichier${files > 1 ? 's' : ''}, $dirs dossier${dirs > 1 ? 's' : ''}'
          '${partial ? ' (au moins)' : ''}';
      values['Taille totale'] = '${formatBytes(bytes)}${partial ? '+' : ''}';
      return values;
    }
    values['Type MIME'] = entry.mimeType ?? 'Inconnu';
    final ext = p.extension(entry.displayName);
    if (ext.isNotEmpty) values['Extension'] = ext.substring(1).toUpperCase();
    try {
      final prefix = await ref
          .read(storageRepositoryProvider)
          .readPrefix(entry.uri);
      final format = FormatDetector().detect(
        prefix: prefix,
        mimeType: entry.mimeType,
        fileName: entry.displayName,
      );
      values['Format détecté'] = [
        _contentLabel(format.content),
        if (format.container != ContainerFormat.none)
          'conteneur ${format.container.name.toUpperCase()}',
      ].join(' · ');
      values['Signature'] = prefix
          .take(8)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ')
          .toUpperCase();
    } catch (_) {}
    final mime = entry.mimeType ?? '';
    if (mime.startsWith('image/') && (entry.size ?? 0) < 60 * 1024 * 1024) {
      try {
        final bytes = await File(path).readAsBytes();
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        values['Dimensions'] = '${descriptor.width} × ${descriptor.height} px';
        descriptor.dispose();
        buffer.dispose();
      } catch (_) {}
    }
    if (mime.startsWith('audio/')) {
      final info = await FilePreviewService.instance.audioInfo('${entry.uri}');
      if (info.title != null) values['Titre'] = info.title!;
      if (info.artist != null) values['Artiste'] = info.artist!;
      if (info.album != null) values['Album'] = info.album!;
    }
    return values;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = entry.uri.toFilePath();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox.square(
                    dimension: 64,
                    child: EntryVisual(entry: entry, item: null, size: 64),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.displayName,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(
                          isDir ? 'Dossier' : fileTypeLabel(entry),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!isDir)
                _Row(
                  'Taille',
                  entry.size == null
                      ? 'Inconnue'
                      : '${formatBytes(entry.size)} (${_grouped(entry.size!)} octets)',
                ),
              _Row('Emplacement', p.dirname(path)),
              _Row(
                'Modifié',
                entry.modifiedAt == null ? 'Inconnu' : _date(entry.modifiedAt!),
              ),
              const SizedBox(height: 8),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text(
                    'Informations avancées',
                    style: theme.textTheme.titleSmall,
                  ),
                  children: [
                    _Row(
                      'Chemin',
                      path,
                      trailing: IconButton(
                        tooltip: 'Copier le chemin',
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: path));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Chemin copié')),
                          );
                        },
                      ),
                    ),
                    FutureBuilder<Map<String, String>>(
                      future: advanced,
                      builder: (context, snapshot) {
                        final data = snapshot.data;
                        if (data == null) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return Column(
                          children: [
                            for (final e in data.entries) _Row(e.key, e.value),
                          ],
                        );
                      },
                    ),
                    if (!isDir) _Checksums(path: path),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Counts a folder's content, capped so huge trees stay quick.
(int, int, int, bool) _folderStats(String path) {
  var files = 0, dirs = 0, bytes = 0, seen = 0;
  try {
    for (final e in Directory(
      path,
    ).listSync(recursive: true, followLinks: false)) {
      if (++seen > 50000) return (files, dirs, bytes, true);
      if (e is File) {
        files++;
        try {
          bytes += e.lengthSync();
        } catch (_) {}
      } else if (e is Directory) {
        dirs++;
      }
    }
  } catch (_) {
    return (files, dirs, bytes, true);
  }
  return (files, dirs, bytes, false);
}

String _contentLabel(ContentKind kind) => switch (kind) {
  ContentKind.pdf => 'PDF',
  ContentKind.epub => 'Livre EPUB',
  ContentKind.comic => 'Bande dessinée',
  ContentKind.image => 'Image',
  ContentKind.audio => 'Audio',
  ContentKind.video => 'Vidéo',
  ContentKind.archive => 'Archive',
  ContentKind.apk => 'Application Android',
  ContentKind.unknown => 'Inconnu',
  _ => kind.name,
};

String _grouped(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]} ',
);

String _date(DateTime value) {
  final d = value.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} à ${two(d.hour)}:${two(d.minute)}';
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.trailing});
  final String label, value;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// MD5 / SHA-1 / SHA-256 of a file, computed on demand in one pass.
class _Checksums extends StatefulWidget {
  const _Checksums({required this.path});
  final String path;
  @override
  State<_Checksums> createState() => _ChecksumsState();
}

class _ChecksumsState extends State<_Checksums> {
  Future<Map<String, String>>? hashes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (hashes == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () =>
                setState(() => hashes = compute(fileChecksums, widget.path)),
            icon: const Icon(Icons.fingerprint_rounded),
            label: const Text('Calculer les empreintes'),
          ),
        ),
      );
    }
    return FutureBuilder<Map<String, String>>(
      future: hashes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Row('Empreintes', 'Lecture impossible');
        }
        final data = snapshot.data;
        if (data == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(
                  'Calcul des empreintes…',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          );
        }
        return Column(
          children: [
            for (final e in data.entries)
              _Row(
                e.key,
                e.value,
                trailing: IconButton(
                  tooltip: 'Copier',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: e.value));
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('${e.key} copié')));
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Reads [path] once and feeds three digests (isolate entry point).
Future<Map<String, String>> fileChecksums(String path) async {
  final sinks = [_DigestSink(), _DigestSink(), _DigestSink()];
  final inputs = [
    md5.startChunkedConversion(sinks[0]),
    sha1.startChunkedConversion(sinks[1]),
    sha256.startChunkedConversion(sinks[2]),
  ];
  await for (final chunk in File(path).openRead()) {
    for (final input in inputs) {
      input.add(chunk);
    }
  }
  for (final input in inputs) {
    input.close();
  }
  return {
    'MD5': '${sinks[0].value}',
    'SHA-1': '${sinks[1].value}',
    'SHA-256': '${sinks[2].value}',
  };
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

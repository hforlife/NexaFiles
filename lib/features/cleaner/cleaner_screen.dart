import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../app/theme/design_tokens.dart';
import '../../core/platform/providers.dart';
import '../../core/storage/media_index.dart';
import '../../core/storage/storage_entry.dart';
import '../../core/trash/trash_service.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/nexa_ui.dart';
import '../files/file_actions.dart';
import '../files/file_tiles.dart';
import '../files/files_controller.dart';
import '../tools/trash_screen.dart';

/// A file the cleaner suggests removing.
class CleanItem {
  const CleanItem(this.entry, {this.note, this.preselected = true});
  final StorageEntry entry;

  /// Why it is listed ("Déjà installée", "Copie de …").
  final String? note;

  /// Checked by default (duplicates keep their oldest copy unchecked).
  final bool preselected;
  int get size => entry.size ?? 0;
}

/// One analysis of the cleaner (large files, duplicates…).
class _Section {
  const _Section({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.load,
    this.grouped = false,
  });
  final String title, description;
  final IconData icon;
  final Color color;
  final Future<List<CleanItem>> Function() load;

  /// Items come in groups of identical files (duplicates).
  final bool grouped;
}

/// Finds what can be removed to free space: large files, duplicates,
/// installed APKs, old downloads and empty folders. Nothing is removed
/// without the user picking and confirming it.
class CleanerScreen extends ConsumerStatefulWidget {
  const CleanerScreen({super.key});
  @override
  ConsumerState<CleanerScreen> createState() => _CleanerScreenState();
}

class _CleanerScreenState extends ConsumerState<CleanerScreen> {
  late final List<_Section> sections = [
    _Section(
      title: 'Gros fichiers',
      description: 'Fichiers de plus de 100 Mo',
      icon: Icons.storage_rounded,
      color: AppColors.video,
      load: () async => [
        for (final e in await const MediaIndex().search(
          '',
          filters: const SearchFilters(
            minSize: 100 * 1024 * 1024,
            sort: SearchSort.size,
            folders: false,
          ),
          limit: 200,
        ))
          CleanItem(e, preselected: false),
      ],
    ),
    _Section(
      title: 'Doublons',
      description: 'Fichiers identiques : la copie la plus ancienne est gardée',
      icon: Icons.copy_all_rounded,
      color: AppColors.reading,
      grouped: true,
      load: () async => [
        for (final group in await const MediaIndex().duplicates())
          for (final (i, e) in group.files.indexed)
            CleanItem(
              e,
              note: i == 0
                  ? 'Original conservé · ${group.files.length} copies'
                  : group.certain
                  ? 'Copie identique'
                  : 'Copie probable (très gros fichier)',
              preselected: i > 0 && group.certain,
            ),
      ],
    ),
    _Section(
      title: 'APK déjà installées',
      description: 'Fichiers d’installation devenus inutiles',
      icon: Icons.android_rounded,
      color: AppColors.apk,
      load: () async {
        final apks = await const MediaIndex().search(
          '',
          filters: const SearchFilters(
            categories: {'apps'},
            sort: SearchSort.size,
            folders: false,
          ),
        );
        return [
          for (final info in await const MediaIndex().apkStatus(apks))
            CleanItem(
              info.entry,
              note: [
                ?info.label,
                ?info.version,
                switch (info.state) {
                  ApkState.installed => 'Déjà installée',
                  ApkState.update => 'Mise à jour disponible',
                  ApkState.notInstalled => 'Non installée',
                  ApkState.invalid => 'Fichier APK invalide',
                },
              ].join(' · '),
              preselected:
                  info.state == ApkState.installed ||
                  info.state == ApkState.invalid,
            ),
        ];
      },
    ),
    _Section(
      title: 'Vieux téléchargements',
      description: 'Dans Téléchargements depuis plus de 90 jours',
      icon: Icons.download_rounded,
      color: AppColors.document,
      load: () async {
        final root = _primaryRoot();
        if (root == null) return const [];
        return [
          for (final e in await const MediaIndex().search(
            '',
            filters: SearchFilters(
              under: p.join(root, 'Download'),
              modifiedBefore: DateTime.now().subtract(const Duration(days: 90)),
              sort: SearchSort.size,
              folders: false,
            ),
          ))
            CleanItem(e, preselected: false),
        ];
      },
    ),
    _Section(
      title: 'Dossiers vides',
      description: 'Dossiers sans aucun contenu',
      icon: Icons.folder_off_outlined,
      color: AppColors.folder,
      load: () async {
        final root = _primaryRoot();
        if (root == null) return const [];
        // compute(): a closure created here would drag this State along.
        final paths = await compute(_emptyFolders, root);
        return [
          for (final path in paths)
            CleanItem(
              StorageEntry(
                uri: Uri.file(path),
                displayName: p.basename(path),
                kind: StorageEntryKind.directory,
              ),
              note: p.relative(p.dirname(path), from: root),
            ),
        ];
      },
    ),
  ];

  late List<Future<List<CleanItem>>> results = [
    for (final s in sections) s.load(),
  ];
  late Future<int> trashSize = _trashSize();

  String? _primaryRoot() {
    final roots = ref.read(filesControllerProvider).roots;
    final root = roots.where((r) => r.primary).firstOrNull ?? roots.firstOrNull;
    return root?.uri.toFilePath();
  }

  Future<int> _trashSize() async => (await TrashService(
    ref.read(storageRepositoryProvider),
  ).list()).fold<int>(0, (s, e) => s + (e.size ?? 0));

  void _reload([int? index]) => setState(() {
    if (index == null) {
      results = [for (final s in sections) s.load()];
    } else {
      results[index] = sections[index].load();
    }
    trashSize = _trashSize();
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nettoyage'),
        actions: [
          IconButton(
            tooltip: 'Relancer l’analyse',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            FutureBuilder<List<List<CleanItem>>>(
              // A failed analysis counts as empty, not as "still running".
              future: Future.wait([
                for (final r in results)
                  r.catchError((Object _) => const <CleanItem>[]),
              ]),
              builder: (context, snapshot) {
                final ready = snapshot.hasData;
                final total = [
                  for (final list in snapshot.data ?? const <List<CleanItem>>[])
                    for (final item in list)
                      if (item.preselected) item.size,
                ].fold<int>(0, (a, b) => a + b);
                return _Summary(ready: ready, bytes: total);
              },
            ),
            const SizedBox(height: 12),
            FutureBuilder<int>(
              future: trashSize,
              builder: (context, snapshot) => _SectionCard(
                icon: Icons.delete_outline_rounded,
                color: AppColors.pdf,
                title: 'Corbeille',
                subtitle: snapshot.data == null
                    ? 'Calcul…'
                    : snapshot.data == 0
                    ? 'Vide · purge automatique après 30 jours'
                    : '${formatBytes(snapshot.data)} récupérables · purge auto à 30 jours',
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TrashScreen()),
                  );
                  if (mounted) setState(() => trashSize = _trashSize());
                },
              ),
            ),
            for (final (i, section) in sections.indexed)
              FutureBuilder<List<CleanItem>>(
                future: results[i],
                builder: (context, snapshot) {
                  final items = snapshot.data;
                  final bytes = items == null
                      ? 0
                      : section.grouped
                      ? items
                            .where((e) => e.preselected)
                            .fold<int>(0, (s, e) => s + e.size)
                      : items.fold<int>(0, (s, e) => s + e.size);
                  final count = section.grouped
                      ? items?.where((e) => e.preselected).length
                      : items?.length;
                  return _SectionCard(
                    icon: section.icon,
                    color: section.color,
                    title: section.title,
                    subtitle: snapshot.hasError
                        ? 'Analyse impossible'
                        : items == null
                        ? 'Analyse…'
                        : count == 0
                        ? 'Rien à signaler'
                        : '$count élément${count! > 1 ? 's' : ''}'
                              '${bytes > 0 ? ' · ${formatBytes(bytes)}' : ''}',
                    loading: items == null && !snapshot.hasError,
                    onTap: items == null || items.isEmpty
                        ? null
                        : () async {
                            final changed = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _CleanerListScreen(
                                  title: section.title,
                                  description: section.description,
                                  items: items,
                                  grouped: section.grouped,
                                ),
                              ),
                            );
                            if (changed == true) _reload(i);
                          },
                  );
                },
              ),
            const SizedBox(height: 12),
            Text(
              'NexaFiles ne supprime rien sans votre confirmation. Les '
              'éléments mis à la corbeille restent récupérables 30 jours.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty folders under [root] (hidden and Android/ excluded), capped.
List<String> _emptyFolders(String root) {
  final found = <String>[];
  void walk(Directory dir, int depth) {
    if (found.length >= 300 || depth > 12) return;
    List<FileSystemEntity> children;
    try {
      children = dir.listSync(followLinks: false);
    } catch (_) {
      return;
    }
    if (children.isEmpty && dir.path != root) {
      found.add(dir.path);
      return;
    }
    for (final child in children) {
      if (child is! Directory) continue;
      final name = p.basename(child.path);
      if (name.startsWith('.')) continue;
      if (depth == 0 && name == 'Android') continue;
      walk(child, depth + 1);
    }
  }

  walk(Directory(root), 0);
  return found;
}

class _Summary extends StatelessWidget {
  const _Summary({required this.ready, required this.bytes});
  final bool ready;
  final int bytes;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), accent = theme.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            IconBubble(
              icon: Icons.cleaning_services_rounded,
              color: accent,
              size: 56,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ready ? 'Espace récupérable' : 'Analyse du stockage…',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    ready ? formatBytes(bytes) : '—',
                    style: theme.textTheme.headlineMedium,
                  ),
                  Text(
                    'Suggestions cochées par défaut',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (!ready)
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.loading = false,
  });
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback? onTap;
  final bool loading;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: IconBubble(icon: icon, color: color, size: 44),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : onTap == null
            ? null
            : const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    ),
  );
}

/// Items of one analysis, with checkboxes and a remove button.
class _CleanerListScreen extends ConsumerStatefulWidget {
  const _CleanerListScreen({
    required this.title,
    required this.description,
    required this.items,
    required this.grouped,
  });
  final String title, description;
  final List<CleanItem> items;
  final bool grouped;
  @override
  ConsumerState<_CleanerListScreen> createState() => _CleanerListState();
}

class _CleanerListState extends ConsumerState<_CleanerListScreen> {
  late final List<CleanItem> items = [...widget.items];
  late final Set<Uri> selected = {
    for (final i in items)
      if (i.preselected) i.entry.uri,
  };
  bool busy = false, changed = false;

  int get selectedBytes => items
      .where((i) => selected.contains(i.entry.uri))
      .fold<int>(0, (s, i) => s + i.size);

  Future<void> _remove() async {
    final chosen = [
      for (final i in items)
        if (selected.contains(i.entry.uri)) i.entry,
    ];
    if (chosen.isEmpty) return;
    final permanent = await showModalBottomSheet<bool>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Supprimer ${chosen.length} élément${chosen.length > 1 ? 's' : ''} '
                '(${formatBytes(selectedBytes)}) ?',
                style: Theme.of(c).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded),
                title: const Text('Supprimer définitivement'),
                subtitle: const Text('Libère l’espace tout de suite'),
                onTap: () => Navigator.pop(c, true),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Mettre à la corbeille'),
                subtitle: const Text(
                  'Récupérable 30 jours, l’espace est libéré ensuite',
                ),
                onTap: () => Navigator.pop(c, false),
              ),
            ],
          ),
        ),
      ),
    );
    if (permanent == null || !mounted) return;
    setState(() => busy = true);
    final removed = await FileActions(
      context,
      ref,
      onChanged: () async {},
    ).removeEntries(chosen, permanent: permanent);
    if (!mounted) return;
    setState(() {
      busy = false;
      changed = true;
      items.removeWhere(
        (i) =>
            selected.contains(i.entry.uri) &&
            !File.fromUri(i.entry.uri).existsSync() &&
            !Directory.fromUri(i.entry.uri).existsSync(),
      );
      selected.removeWhere((u) => !items.any((i) => i.entry.uri == u));
      if (widget.grouped) _dropLoneOriginals();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$removed élément(s) supprimé(s)')));
  }

  /// A duplicate group reduced to its original has nothing left to clean.
  void _dropLoneOriginals() {
    final kept = <CleanItem>[];
    var group = <CleanItem>[];
    void flush() {
      if (group.length > 1) kept.addAll(group);
      group = [];
    }

    for (final item in items) {
      if (item.note?.startsWith('Original') ?? false) flush();
      group.add(item);
    }
    flush();
    items
      ..clear()
      ..addAll(kept);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allSelected = items.isNotEmpty && selected.length == items.length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            TextButton(
              onPressed: items.isEmpty
                  ? null
                  : () => setState(() {
                      allSelected
                          ? selected.clear()
                          : selected.addAll(items.map((i) => i.entry.uri));
                    }),
              child: Text(allSelected ? 'Aucun' : 'Tout'),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: items.isEmpty
            ? const EmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'C’est propre',
                message: 'Il n’y a plus rien à nettoyer ici.',
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 120),
                itemCount: items.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Text(
                        widget.description,
                        style: theme.textTheme.bodySmall,
                      ),
                    );
                  }
                  final item = items[i - 1];
                  final checked = selected.contains(item.entry.uri);
                  final groupStart =
                      widget.grouped &&
                      (item.note?.startsWith('Original') ?? false);
                  return Column(
                    children: [
                      if (groupStart && i > 1)
                        const Divider(indent: 16, endIndent: 16),
                      CheckboxListTile(
                        value: checked,
                        onChanged: (v) => setState(
                          () => v == true
                              ? selected.add(item.entry.uri)
                              : selected.remove(item.entry.uri),
                        ),
                        secondary: SizedBox.square(
                          dimension: 46,
                          child: EntryVisual(
                            entry: item.entry,
                            item: null,
                            size: 46,
                          ),
                        ),
                        title: Text(
                          item.entry.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            if (item.entry.kind == StorageEntryKind.file)
                              formatBytes(item.entry.size),
                            ?item.note,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  );
                },
              ),
        bottomNavigationBar: items.isEmpty
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: busy || selected.isEmpty ? null : _remove,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_sweep_rounded),
                  label: Text(
                    selected.isEmpty
                        ? 'Sélectionnez des éléments'
                        : 'Supprimer ${selected.length} · ${formatBytes(selectedBytes)}',
                  ),
                ),
              ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/router/app_tabs.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/storage/media_index.dart';
import '../../core/storage/storage_entry.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../files/category_screen.dart';
import '../files/file_actions.dart';
import '../files/file_tiles.dart';
import '../files/files_controller.dart';
import '../reader/file_opener.dart';

/// Size thresholds offered as filters.
const _sizes = <(int?, String)>[
  (null, 'Toutes les tailles'),
  (1024 * 1024, 'Plus de 1 Mo'),
  (10 * 1024 * 1024, 'Plus de 10 Mo'),
  (100 * 1024 * 1024, 'Plus de 100 Mo'),
  (1024 * 1024 * 1024, 'Plus de 1 Go'),
];

/// Age windows offered as filters (in days; 0 = today).
const _ages = <(int?, String)>[
  (null, 'Toutes les dates'),
  (0, 'Aujourd’hui'),
  (7, '7 derniers jours'),
  (30, '30 derniers jours'),
  (365, 'Cette année'),
];

/// Searches the whole storage through Android's media index, with type,
/// size and date filters.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _historyKey = 'search.history';
  final input = TextEditingController();
  Timer? debounce;
  Set<String> types = {};
  int? minSize, age;
  SearchSort sort = SearchSort.date;
  List<StorageEntry>? results;
  bool loading = false;
  int _token = 0;
  List<String> history = [];

  late final actions = FileActions(context, ref, onChanged: _run);

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() => history = p.getStringList(_historyKey) ?? []);
      }
    });
  }

  @override
  void dispose() {
    debounce?.cancel();
    input.dispose();
    super.dispose();
  }

  bool get _hasQuery =>
      input.text.trim().isNotEmpty ||
      types.isNotEmpty ||
      minSize != null ||
      age != null;

  void _changed() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 280), _run);
    setState(() {});
  }

  Future<void> _run() async {
    if (!mounted) return;
    if (!_hasQuery) {
      setState(() => results = null);
      return;
    }
    final token = ++_token;
    setState(() => loading = true);
    final now = DateTime.now();
    final after = age == null
        ? null
        : age == 0
        ? DateTime(now.year, now.month, now.day)
        : now.subtract(Duration(days: age!));
    try {
      final found = await const MediaIndex().search(
        input.text,
        filters: SearchFilters(
          categories: types,
          minSize: minSize,
          modifiedAfter: after,
          sort: sort,
        ),
      );
      if (!mounted || token != _token) return;
      setState(() {
        results = found;
        loading = false;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        results = const [];
        loading = false;
      });
    }
  }

  Future<void> _remember(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    history = [q, ...history.where((h) => h != q)].take(8).toList();
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_historyKey, history);
  }

  Future<void> _open(StorageEntry entry, List<StorageEntry> all) async {
    unawaited(_remember(input.text));
    if (entry.kind == StorageEntryKind.directory) {
      // Folders open in the Files tab, like any other folder.
      Navigator.of(context).popUntil((r) => r.isFirst);
      ref.read(currentTabProvider.notifier).state = AppTab.files;
      await ref.read(filesControllerProvider.notifier).openDirectory(entry);
      return;
    }
    try {
      await openFile(
        context,
        ref,
        entry,
        siblings: [
          for (final e in all)
            if (e.kind == StorageEntryKind.file) e,
        ],
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir ce fichier.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: input,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => _changed(),
          onSubmitted: (v) {
            _remember(v);
            _run();
          },
          decoration: InputDecoration(
            hintText: 'Rechercher dans tout le stockage',
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            suffixIcon: input.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Effacer',
                    onPressed: () {
                      input.clear();
                      _changed();
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        actions: [
          PopupMenuButton<SearchSort>(
            tooltip: 'Trier',
            icon: const Icon(Icons.swap_vert_rounded),
            initialValue: sort,
            onSelected: (v) {
              setState(() => sort = v);
              _run();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: SearchSort.date,
                child: Text('Plus récents'),
              ),
              PopupMenuItem(
                value: SearchSort.size,
                child: Text('Plus volumineux'),
              ),
              PopupMenuItem(value: SearchSort.name, child: Text('Nom')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              children: [
                _FilterButton(
                  icon: Icons.category_outlined,
                  label: types.isEmpty
                      ? 'Type'
                      : types.length == 1
                      ? _typeLabel(types.first)
                      : '${types.length} types',
                  active: types.isNotEmpty,
                  onTap: _pickTypes,
                ),
                _FilterButton(
                  icon: Icons.straighten_rounded,
                  label: minSize == null
                      ? 'Taille'
                      : _sizes.firstWhere((s) => s.$1 == minSize).$2,
                  active: minSize != null,
                  onTap: () =>
                      _pickOne('Taille', _sizes, minSize, (v) => minSize = v),
                ),
                _FilterButton(
                  icon: Icons.event_outlined,
                  label: age == null
                      ? 'Date'
                      : _ages.firstWhere((s) => s.$1 == age).$2,
                  active: age != null,
                  onTap: () => _pickOne('Date', _ages, age, (v) => age = v),
                ),
                if (types.isNotEmpty || minSize != null || age != null)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        types = {};
                        minSize = null;
                        age = null;
                      });
                      _run();
                    },
                    child: const Text('Réinitialiser'),
                  ),
              ],
            ),
          ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    final list = results;
    if (list == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
        children: [
          if (history.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Recherches récentes',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      setState(() => history = []);
                      final p = await SharedPreferences.getInstance();
                      await p.remove(_historyKey);
                    },
                    child: const Text('Effacer'),
                  ),
                ],
              ),
            ),
            for (final h in history)
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: Text(h),
                onTap: () {
                  input.text = h;
                  input.selection = TextSelection.collapsed(offset: h.length);
                  _run();
                },
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: Text(
              'Parcourir par type',
              style: theme.textTheme.titleSmall,
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in categories)
                ActionChip(
                  avatar: Icon(c.icon, color: c.color, size: 18),
                  label: Text(c.label),
                  onPressed: () {
                    setState(() => types = {c.key});
                    _run();
                  },
                ),
            ],
          ),
        ],
      );
    }
    if (list.isEmpty && !loading) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Aucun résultat',
        message: 'Essayez un autre mot ou retirez des filtres.',
      );
    }
    final total = list.fold<int>(0, (s, e) => s + (e.size ?? 0));
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: list.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              '${list.length >= 500 ? '500+' : list.length} résultat'
              '${list.length > 1 ? 's' : ''} · ${formatBytes(total)}',
              style: theme.textTheme.bodySmall,
            ),
          );
        }
        final entry = list[i - 1];
        return FileTile(
          entry: entry,
          item: null,
          onTap: () => _open(entry, list),
          onLongPress: () async {
            HapticFeedback.selectionClick();
            final action = await showFileActionsSheet(context, entry);
            if (action != null) await actions.handle(action, entry);
          },
          onMenu: (action) => actions.handle(action, entry),
        );
      },
    );
  }

  Future<void> _pickTypes() async {
    final picked = {...types};
    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Types de fichiers',
                  style: Theme.of(c).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final key in [
                      ...categories.map((c) => c.key),
                      'folders',
                    ])
                      FilterChip(
                        label: Text(_typeLabel(key)),
                        selected: picked.contains(key),
                        onSelected: (v) => setSheet(
                          () => v ? picked.add(key) : picked.remove(key),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Appliquer'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    setState(() => types = picked);
    _run();
  }

  Future<void> _pickOne(
    String title,
    List<(int?, String)> options,
    int? current,
    void Function(int?) apply,
  ) async {
    final value = await showModalBottomSheet<(int?, String)>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title, style: Theme.of(c).textTheme.titleLarge),
              ),
            ),
            for (final o in options)
              ListTile(
                title: Text(o.$2),
                trailing: o.$1 == current
                    ? Icon(
                        Icons.check_rounded,
                        color: Theme.of(c).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(c, o),
              ),
          ],
        ),
      ),
    );
    if (value == null) return;
    setState(() => apply(value.$1));
    _run();
  }
}

String _typeLabel(String key) => key == 'folders'
    ? 'Dossiers'
    : categories.firstWhere((c) => c.key == key).label;

/// Pill opening a filter sheet; filled with the accent when active.
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final s = context.surfaces, accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active ? accent.withValues(alpha: .14) : s.card,
        shape: StadiumBorder(side: BorderSide(color: active ? accent : s.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: active ? accent : s.muted),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppFonts.body,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: active ? accent : s.ink,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: active ? accent : s.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

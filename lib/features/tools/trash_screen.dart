import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/platform/providers.dart';
import '../../core/trash/trash_service.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/nexa_ui.dart';

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});
  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  late Future<List<TrashItem>> items;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  TrashService get service => TrashService(ref.read(storageRepositoryProvider));
  // Block body on purpose: an arrow body would return the Future, which
  // setState() rejects when this is passed as its callback.
  void _reload() {
    items = service.list();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Corbeille'),
      actions: [
        IconButton(
          tooltip: 'Vider la corbeille',
          onPressed: _empty,
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
        const SizedBox(width: 4),
      ],
    ),
    body: FutureBuilder<List<TrashItem>>(
      future: items,
      builder: (c, s) {
        if (!s.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = s.data!;
        if (list.isEmpty) {
          return const EmptyState(
            icon: Icons.delete_outline_rounded,
            title: 'La corbeille est vide',
            message:
                'Les fichiers supprimés depuis NexaFiles arrivent ici et '
                'peuvent être restaurés à leur emplacement d’origine.',
          );
        }
        final total = list.fold<int>(0, (sum, e) => sum + (e.size ?? 0));
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const IconBubble(
                      icon: Icons.delete_outline_rounded,
                      color: AppColors.pdf,
                      size: 48,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${list.length} élément${list.length > 1 ? 's' : ''}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '${formatBytes(total)} · restaurables à leur '
                            'emplacement d’origine',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final item in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: _icon(item.name),
                    title: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        _deleted(item.deletedAt),
                        if (item.size != null) formatBytes(item.size),
                      ].join(' · '),
                    ),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Actions',
                      icon: const Icon(Icons.more_horiz_rounded),
                      onSelected: (v) => _action(v, item),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'restore',
                          child: Row(
                            children: [
                              Icon(Icons.restore_rounded, size: 20),
                              SizedBox(width: 12),
                              Text('Restaurer'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_forever_outlined, size: 20),
                              SizedBox(width: 12),
                              Text('Supprimer définitivement'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _icon(String name) {
    final dot = name.lastIndexOf('.');
    final category = dot < 0
        ? FileCategory.other
        : FileCategory.fromExtension(name.substring(dot + 1));
    return IconBubble(icon: category.icon, color: category.color, size: 42);
  }

  String _deleted(DateTime value) {
    final d = value.toLocal(), now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(d.hour)}:${two(d.minute)}';
    if (days == 0) return 'Supprimé aujourd’hui à $time';
    if (days == 1) return 'Supprimé hier à $time';
    if (days < 7) return 'Supprimé il y a $days jours';
    return 'Supprimé le ${two(d.day)}/${two(d.month)}/${d.year}';
  }

  Future<void> _action(String action, TrashItem item) async {
    if (action == 'restore') await service.restore(item);
    if (action == 'delete') {
      final yes = await _confirm('Supprimer définitivement « ${item.name} » ?');
      if (yes) await service.deletePermanently(item);
    }
    if (mounted) setState(_reload);
  }

  Future<void> _empty() async {
    if (await _confirm('Vider définitivement toute la corbeille ?')) {
      await service.empty();
      if (mounted) setState(_reload);
    }
  }

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(text),
          content: const Text('Cette action est irréversible.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(c).colorScheme.error,
                foregroundColor: Theme.of(c).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ) ??
      false;
}

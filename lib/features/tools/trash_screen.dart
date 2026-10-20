import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/platform/providers.dart';
import '../../core/trash/trash_service.dart';

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
  void _reload() => items = service.list();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Corbeille'),
      actions: [
        IconButton(
          tooltip: 'Vider la corbeille',
          onPressed: _empty,
          icon: const Icon(Icons.delete_forever),
        ),
      ],
    ),
    body: FutureBuilder<List<TrashItem>>(
      future: items,
      builder: (c, s) {
        if (!s.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.data!.isEmpty) {
          return const Center(child: Text('La corbeille est vide'));
        }
        return ListView(
          children: [
            for (final item in s.data!)
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(item.name),
                subtitle: Text('Supprimé le ${item.deletedAt.toLocal()}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => _action(v, item),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'restore', child: Text('Restaurer')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Supprimer définitivement'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ) ??
      false;
}

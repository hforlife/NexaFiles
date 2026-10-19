import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/cache/cache_manager.dart';
import '../../core/database/database_provider.dart';
import '../recents/recents_screen.dart';
import '../../shared/formatters.dart';

class StorageDataScreen extends ConsumerStatefulWidget {
  const StorageDataScreen({super.key});
  @override
  ConsumerState<StorageDataScreen> createState() => _StorageDataScreenState();
}

class _StorageDataScreenState extends ConsumerState<StorageDataScreen> {
  int? bytes;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final value = await CacheManager().usage();
    if (mounted) setState(() => bytes = value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Stockage et données')),
      body: ListView(children: [
        ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Cache de lecture'),
            subtitle: Text(bytes == null
                ? 'Calcul…'
                : '${formatBytes(bytes)} • La progression et les signets sont conservés'),
            trailing: FilledButton(
                onPressed: busy ? null : _clearCache,
                child: const Text('Vider'))),
        const Divider(),
        ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Réinitialiser progression et historique'),
            subtitle: const Text(
                'Efface les positions de lecture et les fichiers récents. Les favoris, collections et signets restent conservés.'),
            onTap: busy ? null : _reset)
      ]));
  Future<void> _clearCache() async {
    setState(() => busy = true);
    await CacheManager().clearAll();
    await _measure();
    if (mounted) {
      setState(() => busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache vidé. Progression conservée.')));
    }
  }

  Future<void> _reset() async {
    final yes = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
                    title: const Text('Réinitialiser la progression ?'),
                    content: const Text(
                        'Les positions de lecture et l’historique récent seront supprimés. Cette action n’efface pas les fichiers.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Réinitialiser'))
                    ])) ??
        false;
    if (!yes) return;
    setState(() => busy = true);
    await ref.read(databaseProvider).resetProgressAndHistory();
    ref.read(recentOpenEpochProvider.notifier).state++;
    if (mounted) {
      setState(() => busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Progression et historique réinitialisés.')));
    }
  }
}

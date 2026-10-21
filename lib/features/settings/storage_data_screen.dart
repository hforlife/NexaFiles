import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/cache/cache_manager.dart';
import '../../core/database/database_provider.dart';
import '../recents/recents_screen.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/nexa_ui.dart';
import '../../app/theme/design_tokens.dart';

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Stockage et données')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconBubble(
                        icon: Icons.cleaning_services_rounded,
                        color: AppColors.image,
                        size: 48,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cache de lecture',
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              bytes == null ? 'Calcul…' : formatBytes(bytes),
                              style: theme.textTheme.headlineSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Pages extraites, couvertures et miniatures. La '
                    'progression et les signets sont conservés.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: busy ? null : _clearCache,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Vider le cache'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconBubble(
                        icon: Icons.restart_alt_rounded,
                        color: AppColors.pdf,
                        size: 48,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Progression et historique',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Efface les positions de lecture et les fichiers récents. '
                    'Les favoris, collections et signets restent conservés.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      onPressed: busy ? null : _reset,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('Réinitialiser'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCache() async {
    setState(() => busy = true);
    await CacheManager().clearAll();
    await _measure();
    if (mounted) {
      setState(() => busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache vidé. Progression conservée.')),
      );
    }
  }

  Future<void> _reset() async {
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Réinitialiser la progression ?'),
            content: const Text(
              'Les positions de lecture et l’historique récent seront supprimés. Cette action n’efface pas les fichiers.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Réinitialiser'),
              ),
            ],
          ),
        ) ??
        false;
    if (!yes) return;
    setState(() => busy = true);
    await ref.read(databaseProvider).resetProgressAndHistory();
    ref.read(recentOpenEpochProvider.notifier).state++;
    if (mounted) {
      setState(() => busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Progression et historique réinitialisés.'),
        ),
      );
    }
  }
}

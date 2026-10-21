import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database_provider.dart';
import '../settings/storage_data_screen.dart';
import '../../shared/formatters.dart';
import '../files/files_controller.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/widgets/nexa_ui.dart';
import '../files/category_screen.dart';
import '../cleaner/cleaner_screen.dart';
import '../operations/operations_ui.dart';
import '../search/search_screen.dart';
import '../transfer/wifi_transfer_screen.dart';
import 'trash_screen.dart';

class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: EdgeInsets.fromLTRB(16, 8, 16, dockInset(context)),
    children: [
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
        childAspectRatio: 1.05,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        children: [
          _Tool(
            icon: Icons.cleaning_services_rounded,
            title: 'Nettoyage',
            subtitle: 'Doublons, gros fichiers, APK',
            color: AppColors.image,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CleanerScreen()),
            ),
          ),
          _Tool(
            icon: Icons.wifi_tethering_rounded,
            title: 'Transfert Wi-Fi',
            subtitle: 'Échanger avec un ordinateur',
            color: AppColors.reading,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WifiTransferScreen()),
            ),
          ),
          _Tool(
            icon: Icons.manage_search_rounded,
            title: 'Recherche',
            subtitle: 'Dans tout le stockage',
            color: AppColors.document,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          _Tool(
            icon: Icons.sync_alt_rounded,
            title: 'Opérations',
            subtitle: 'Copies et extractions en cours',
            color: AppColors.archive,
            onTap: () => showOperationsSheet(context),
          ),
          _Tool(
            icon: Icons.delete_outline,
            title: 'Corbeille',
            subtitle: 'Restaurer ou supprimer',
            color: AppColors.pdf,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TrashScreen()),
            ),
          ),
          _Tool(
            icon: Icons.archive_outlined,
            title: 'Archives',
            subtitle: 'Toutes vos archives',
            color: AppColors.archive,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CategoryScreen(
                  category: categories.firstWhere((c) => c.key == 'archives'),
                ),
              ),
            ),
          ),
          _Tool(
            icon: Icons.data_usage_rounded,
            title: 'Stockage et données',
            subtitle: 'Cache et progression',
            color: AppColors.image,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StorageDataScreen()),
            ),
          ),
          _Tool(
            icon: Icons.folder_special_outlined,
            title: 'Dossiers bibliothèque',
            subtitle: 'Racines surveillées',
            color: AppColors.reading,
            onTap: () => _roots(context, ref),
          ),
          _Tool(
            icon: Icons.storage_rounded,
            title: 'Stockage',
            subtitle: 'Volumes et espace libre',
            color: AppColors.document,
            onTap: () => _storage(context, ref),
          ),
        ],
      ),
      const SizedBox(height: 28),
      Row(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'NexaFiles travaille hors ligne : tout reste sur votre appareil.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    ],
  );
  Future<void> _roots(BuildContext context, WidgetRef ref) async {
    final roots = await ref.read(databaseProvider).scanRoots();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Dossiers de bibliothèque')),
            for (final root in roots)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(root.name),
                subtitle: Text(
                  root.lastScanAt == null
                      ? 'Jamais analysé'
                      : 'Analysé ${root.lastScanAt}',
                ),
              ),
            if (roots.isEmpty)
              const ListTile(
                title: Text('Aucun dossier configuré'),
                subtitle: Text('Ajoutez-en depuis l’onglet Bibliothèque.'),
              ),
          ],
        ),
      ),
    );
  }

  void _storage(BuildContext context, WidgetRef ref) {
    final roots = ref.read(filesControllerProvider).roots;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Volumes de stockage')),
            for (final root in roots)
              ListTile(
                leading: Icon(
                  root.removable ? Icons.sd_card_outlined : Icons.phone_android,
                ),
                title: Text(root.name),
                subtitle: Text(
                  '${formatBytes(root.freeBytes)} libres sur ${formatBytes(root.totalBytes)}\n${root.uri.toFilePath()}',
                ),
              ),
            if (roots.isEmpty)
              const ListTile(
                title: Text('Aucun volume accessible'),
                subtitle: Text(
                  'Autorisez l’accès aux fichiers depuis l’onglet Fichiers.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBubble(icon: icon, color: color, size: 46),
                const Spacer(),
                Icon(
                  Icons.arrow_outward_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const Spacer(),
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            Text(
              subtitle,
              maxLines: 2,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

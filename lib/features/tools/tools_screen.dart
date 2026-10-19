import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/router/app_router.dart';
import '../../core/database/database_provider.dart';
import '../../core/platform/providers.dart';
import '../settings/storage_data_screen.dart';
import 'trash_screen.dart';

class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
        Text('Actions rapides', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
            childAspectRatio: 1.15,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _Tool(
                  icon: Icons.delete_outline,
                  title: 'Corbeille',
                  subtitle: 'Restaurer ou supprimer',
                  color: Colors.red,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const TrashScreen()))),
              _Tool(
                  icon: Icons.archive_outlined,
                  title: 'Archives',
                  subtitle: 'Parcourir et extraire',
                  color: Colors.deepPurple,
                  onTap: () =>
                      Navigator.pushReplacementNamed(context, AppRoutes.files)),
              _Tool(
                  icon: Icons.cleaning_services_outlined,
                  title: 'Stockage et données',
                  subtitle: 'Cache et progression',
                  color: Colors.teal,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const StorageDataScreen()))),
              _Tool(
                  icon: Icons.folder_special_outlined,
                  title: 'Dossiers bibliothèque',
                  subtitle: 'Racines surveillées',
                  color: Colors.orange,
                  onTap: () => _roots(context, ref)),
              _Tool(
                  icon: Icons.storage_rounded,
                  title: 'Emplacements',
                  subtitle: 'Accès SAF autorisés',
                  color: Colors.blue,
                  onTap: () => _storage(context, ref))
            ]),
        const SizedBox(height: 28),
        Text(
            'NexaFiles travaille hors ligne et n’affiche ici que les outils disponibles.',
            style: Theme.of(context).textTheme.bodyMedium)
      ]);
  Future<void> _roots(BuildContext context, WidgetRef ref) async {
    final roots = await ref.read(databaseProvider).scanRoots();
    if (!context.mounted) return;
    showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              const ListTile(title: Text('Dossiers de bibliothèque')),
              for (final root in roots)
                ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(root.name),
                    subtitle: Text(root.lastScanAt == null
                        ? 'Jamais analysé'
                        : 'Analysé ${root.lastScanAt}')),
              if (roots.isEmpty)
                const ListTile(
                    title: Text('Aucun dossier configuré'),
                    subtitle: Text('Ajoutez-en depuis l’onglet Bibliothèque.'))
            ])));
  }

  Future<void> _storage(BuildContext context, WidgetRef ref) async {
    final roots = await ref.read(storageRepositoryProvider).grantedRoots();
    if (!context.mounted) return;
    showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              const ListTile(title: Text('Emplacements autorisés')),
              for (final root in roots)
                ListTile(
                    leading: const Icon(Icons.storage_rounded),
                    title: Text(root.displayName),
                    subtitle: Text('${root.uri}',
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (roots.isEmpty)
                const ListTile(title: Text('Aucun emplacement autorisé'))
            ])));
  }
}

class _Tool extends StatelessWidget {
  const _Tool(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.color,
      required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
      child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                        backgroundColor: color.withOpacity(.14),
                        child: Icon(icon, color: color)),
                    const Spacer(),
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(subtitle,
                        maxLines: 2,
                        style: Theme.of(context).textTheme.bodySmall)
                  ]))));
}

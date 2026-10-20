import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/i18n/app_strings.dart';
import '../../core/settings/settings_controller.dart';
import 'comic_settings_section.dart';
import 'document_settings_section.dart';
import 'storage_data_screen.dart';
import '../files/files_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context),
        settings = ref.watch(settingsProvider),
        files = ref.watch(filesControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        children: [
          _Header(s.appearance),
          RadioGroup<ThemeMode>(
            groupValue: settings.themeMode,
            onChanged: (v) => settings.setThemeMode(v!),
            child: Column(
              children: [
                RadioListTile(value: ThemeMode.system, title: Text(s.system)),
                RadioListTile(value: ThemeMode.light, title: Text(s.light)),
                RadioListTile(value: ThemeMode.dark, title: Text(s.dark)),
              ],
            ),
          ),
          const Divider(),
          const _Header('Langue / Language'),
          SegmentedButton<Locale>(
            segments: const [
              ButtonSegment(value: Locale('fr'), label: Text('Français')),
              ButtonSegment(value: Locale('en'), label: Text('English')),
            ],
            selected: {settings.locale},
            onSelectionChanged: (v) => settings.setLocale(v.first),
          ),
          const Divider(),
          _Header(s.reading),
          const ComicSettingsSection(),
          const DocumentSettingsSection(),
          _Header(s.storage),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_outlined),
            title: const Text('Afficher les fichiers cachés'),
            subtitle: const Text(
              'Affiche les éléments dont le nom commence par un point',
            ),
            value: files.showHidden,
            onChanged: ref.read(filesControllerProvider.notifier).setShowHidden,
          ),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Stockage et données'),
            subtitle: const Text('Cache, progression et historique'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StorageDataScreen()),
            ),
          ),
          _Header(s.about),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('À propos de NexaFiles'),
            subtitle: const Text('Version 1.0.0+1'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'NexaFiles',
              applicationVersion: '1.0.0+1',
              applicationLegalese:
                  'Gestionnaire de fichiers et lecteur hors ligne.',
              children: [
                const Text(
                  'NexaFiles organise, ouvre et lit vos documents, livres et bandes dessinées en respectant les autorisations Android.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

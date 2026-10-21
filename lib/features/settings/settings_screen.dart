import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/i18n/app_strings.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/settings/settings_controller.dart';
import '../../shared/widgets/nexa_logo.dart';
import 'comic_settings_section.dart';
import 'document_settings_section.dart';
import 'reader_options_section.dart';
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
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _Header(s.appearance),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: const Icon(Icons.brightness_auto_rounded),
                    label: Text(s.system),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(Icons.light_mode_rounded),
                    label: Text(s.light),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(Icons.dark_mode_rounded),
                    label: Text(s.dark),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (v) => settings.setThemeMode(v.first),
              ),
            ),
          ),
          const _SubHeader('Couleur d’accent'),
          _AccentPicker(value: settings.accent, onChanged: settings.setAccent),
          const Divider(),
          const _Header('Langue / Language'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<Locale>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: Locale('fr'), label: Text('Français')),
                  ButtonSegment(value: Locale('en'), label: Text('English')),
                ],
                selected: {settings.locale},
                onSelectionChanged: (v) => settings.setLocale(v.first),
              ),
            ),
          ),
          const Divider(),
          _Header(s.reading),
          const ReaderOptionsSection(),
          const SizedBox(height: 8),
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
              applicationIcon: const NexaLogo(size: 56),
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

class _SubHeader extends StatelessWidget {
  const _SubHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 16, 10),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// Swatches for the accent colour, with a live preview of both worlds.
class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.value, required this.onChanged});
  final Color value;
  final ValueChanged<Color> onChanged;
  @override
  Widget build(BuildContext context) {
    final current = AppAccents.of(value), s = context.surfaces;
    final brightness = Theme.of(context).brightness;
    final salon = NexaSurfaces.salon(brightness);
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final preset in AppAccents.presets)
                Semantics(
                  button: true,
                  selected: preset.name == current.name,
                  label: preset.name,
                  excludeSemantics: true,
                  child: Tooltip(
                    message: preset.name,
                    child: GestureDetector(
                      onTap: () => onChanged(preset.color),
                      child: AnimatedContainer(
                        duration: AppMotion.fast,
                        width: 44,
                        height: 44,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: preset.name == current.name
                                ? s.ink
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: preset.color,
                            shape: BoxShape.circle,
                          ),
                          child: preset.name == current.name
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 20,
                                  color: AppTheme.onColor(preset.color),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Live preview: the file manager and the library side by side.
          Row(
            children: [
              Expanded(
                child: _Preview(
                  background: s.canvas,
                  card: s.card,
                  ink: s.ink,
                  accent: accent,
                  title: 'Fichiers',
                  family: AppFonts.display,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Preview(
                  background: salon.canvas,
                  card: salon.card,
                  ink: salon.ink,
                  accent: accent,
                  title: 'Bibliothèque',
                  family: AppFonts.serif,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(current.name, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.background,
    required this.card,
    required this.ink,
    required this.accent,
    required this.title,
    required this.family,
  });
  final Color background, card, ink, accent;
  final String title, family;
  @override
  Widget build(BuildContext context) => Container(
    height: 92,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: context.surfaces.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          style: TextStyle(
            fontFamily: family,
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: ink,
          ),
        ),
        const Spacer(),
        Row(
          children: [
            Container(
              width: 34,
              height: 26,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 26,
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 16, 10),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 1.3,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

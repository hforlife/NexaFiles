import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/app_info.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/widgets/nexa_logo.dart';
import '../../shared/widgets/nexa_ui.dart';

/// « À propos » : the app, its developer and how to reach them.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), s = context.surfaces;
    return Scaffold(
      appBar: AppBar(title: const Text('À propos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SizedBox(height: 12),
          const Center(child: NexaLogo(size: 96)),
          const SizedBox(height: 16),
          Center(
            child: Text.rich(
              TextSpan(
                text: 'Nexa',
                children: [
                  TextSpan(
                    text: 'Files',
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                ],
              ),
              style: theme.textTheme.headlineLarge,
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Version ${AppInfo.version} (${AppInfo.build})',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Gestionnaire de fichiers et lecteur hors ligne : documents, '
            'livres, mangas, musique et vidéos, sans publicité ni collecte '
            'de données. Tout reste sur votre appareil.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: s.muted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Text(
                    'DÉVELOPPÉ PAR',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: s.muted,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(AppInfo.developer, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => showContactSheet(context),
                      icon: const Icon(Icons.support_agent_rounded),
                      label: const Text('Contacter le développeur'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: IconBubble(
                icon: Icons.description_outlined,
                color: theme.colorScheme.primary,
                size: 42,
              ),
              title: const Text('Licences open source'),
              subtitle: const Text('Bibliothèques et polices utilisées'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showLicensePage(
                context: context,
                applicationName: AppInfo.name,
                applicationVersion: AppInfo.version,
                applicationIcon: const Padding(
                  padding: EdgeInsets.all(12),
                  child: NexaLogo(size: 64),
                ),
                applicationLegalese: '© 2026 ${AppInfo.developer}',
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '© 2026 ${AppInfo.developer}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// E-mail, phone calls and WhatsApp for the developer.
Future<void> showContactSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => const _ContactSheet(),
    );

class _ContactSheet extends StatelessWidget {
  const _ContactSheet();

  Future<void> _open(BuildContext context, Uri uri) async {
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune application pour cette action.')),
      );
    }
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('« $text » copié')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Text(
                'Contacter ${AppInfo.developer}',
                style: theme.textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Text(
                'Une question, un bug ou une idée ? Écrivez-nous.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            ListTile(
              leading: IconBubble(
                icon: Icons.mail_rounded,
                color: accent,
                size: 42,
              ),
              title: const Text('E-mail'),
              subtitle: const Text(AppInfo.email),
              onTap: () => _open(
                context,
                Uri(
                  scheme: 'mailto',
                  path: AppInfo.email,
                  query:
                      'subject=${Uri.encodeComponent('NexaFiles ${AppInfo.version}')}',
                ),
              ),
              onLongPress: () => _copy(context, AppInfo.email),
            ),
            for (final (display, digits) in AppInfo.phones)
              ListTile(
                leading: const IconBubble(
                  icon: Icons.call_rounded,
                  color: AppColors.apk,
                  size: 42,
                ),
                title: Text(display),
                subtitle: const Text('Appeler · appui long pour copier'),
                onTap: () =>
                    _open(context, Uri(scheme: 'tel', path: '+$digits')),
                onLongPress: () => _copy(context, display),
                trailing: IconButton(
                  tooltip: 'WhatsApp',
                  onPressed: () =>
                      _open(context, Uri.parse('https://wa.me/$digits')),
                  icon: const Icon(
                    Icons.chat_rounded,
                    color: Color(0xFF25D366),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/nexa_ui.dart';
import '../files/files_controller.dart';
import 'wifi_server.dart';

/// Shares the phone's storage with a computer on the same Wi-Fi, through a
/// small web server that only lives while this screen is open.
class WifiTransferScreen extends ConsumerStatefulWidget {
  const WifiTransferScreen({super.key});
  @override
  ConsumerState<WifiTransferScreen> createState() => _WifiTransferState();
}

class _WifiTransferState extends ConsumerState<WifiTransferScreen> {
  WifiServer? server;
  String? address;
  String? error;
  bool starting = true;
  final events = <TransferEvent>[];
  StreamSubscription<TransferEvent>? sub;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      starting = true;
      error = null;
    });
    final roots = ref.read(filesControllerProvider).roots;
    final root = roots.where((r) => r.primary).firstOrNull ?? roots.firstOrNull;
    if (root == null) {
      setState(() {
        starting = false;
        error = 'Autorisez d’abord l’accès aux fichiers.';
      });
      return;
    }
    final ip = await WifiServer.localAddress();
    if (ip == null) {
      setState(() {
        starting = false;
        error =
            'Connectez le téléphone à un réseau Wi-Fi (ou activez son '
            'point d’accès), puis réessayez.';
      });
      return;
    }
    final s = WifiServer(root.uri.toFilePath());
    try {
      await s.start();
    } catch (e) {
      setState(() {
        starting = false;
        error = 'Impossible de démarrer le serveur : $e';
      });
      return;
    }
    sub = s.events.listen((e) {
      if (mounted) setState(() => events.insert(0, e));
    });
    if (!mounted) {
      await s.dispose();
      return;
    }
    setState(() {
      server = s;
      address = ip;
      starting = false;
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    server?.dispose();
    super.dispose();
  }

  String get url => 'http://$address:${server!.port}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), s = context.surfaces;
    final accent = theme.colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Transfert Wi-Fi')),
      body: starting
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? EmptyState(
              icon: Icons.wifi_off_rounded,
              title: 'Transfert indisponible',
              message: error!,
              action: FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: AppColors.apk,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Serveur actif',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: AppColors.apk,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Sur votre ordinateur, connecté au même Wi-Fi, '
                          'ouvrez cette adresse dans le navigateur :',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: s.muted,
                          ),
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: '$url/?k=${server!.code}'),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Adresse copiée')),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              url,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: accent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('Code d’accès', style: theme.textTheme.bodySmall),
                        const SizedBox(height: 4),
                        SelectableText(
                          server!.code,
                          style: theme.textTheme.displaySmall?.copyWith(
                            letterSpacing: 8,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          // The QR embeds the code: scanning connects directly.
                          child: QrImageView(
                            data: '$url/?k=${server!.code}',
                            size: 180,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.circle,
                              color: Color(0xFF1E1B4B),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.circle,
                              color: Color(0xFF1E1B4B),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Ou scannez ce code avec une tablette ou un autre '
                          'téléphone.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        IconBubble(
                          icon: Icons.shield_outlined,
                          color: accent,
                          size: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Seuls les appareils de votre réseau local et '
                            'connaissant le code peuvent se connecter. Le '
                            'serveur s’arrête dès que vous quittez cet écran.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionTitle(
                  'Activité',
                  padding: EdgeInsets.fromLTRB(4, 20, 4, 8),
                ),
                if (events.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'En attente d’une connexion…',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: s.muted,
                      ),
                    ),
                  )
                else
                  for (final e in events.take(50))
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: Icon(_icon(e.kind), color: _color(e.kind)),
                      title: Text(
                        _label(e),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          '${e.at.hour.toString().padLeft(2, '0')}:'
                              '${e.at.minute.toString().padLeft(2, '0')}',
                          if (e.bytes != null) formatBytes(e.bytes),
                        ].join(' · '),
                      ),
                    ),
              ],
            ),
      bottomNavigationBar: server == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Arrêter le transfert'),
              ),
            ),
    );
  }

  IconData _icon(TransferEventKind k) => switch (k) {
    TransferEventKind.connected => Icons.computer_rounded,
    TransferEventKind.download => Icons.download_rounded,
    TransferEventKind.upload => Icons.upload_rounded,
    TransferEventKind.folder => Icons.create_new_folder_outlined,
    TransferEventKind.refused => Icons.block_rounded,
  };

  Color _color(TransferEventKind k) => switch (k) {
    TransferEventKind.refused => Theme.of(context).colorScheme.error,
    TransferEventKind.upload => AppColors.apk,
    _ => Theme.of(context).colorScheme.primary,
  };

  String _label(TransferEvent e) => switch (e.kind) {
    TransferEventKind.connected => 'Appareil connecté (${e.name})',
    TransferEventKind.download => 'Envoyé à l’ordinateur : ${e.name}',
    TransferEventKind.upload => 'Reçu : ${e.name}',
    TransferEventKind.folder => 'Dossier créé : ${e.name}',
    TransferEventKind.refused => 'Connexion refusée (${e.name})',
  };
}

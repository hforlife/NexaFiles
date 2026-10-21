import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/router/app_tabs.dart';
import '../../core/platform/providers.dart';
import '../cleaner/cleaner_screen.dart';
import '../files/category_screen.dart';
import '../files/files_controller.dart';
import '../player/audio_player_controller.dart';
import '../player/audio_player_screen.dart';
import '../search/search_screen.dart';

/// Home-screen integration: pinned folder shortcuts and widgets.
abstract final class HomeLink {
  static const channel = MethodChannel('nexa_file/home');

  /// Asks the launcher to pin a shortcut opening [path].
  static Future<bool> pinFolder(String path, String label) async {
    try {
      final supported =
          await channel.invokeMethod<bool>('canPinShortcuts') ?? false;
      if (!supported) return false;
      return await channel.invokeMethod<bool>('pinFolder', {
            'path': path,
            'label': label,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static (bool, String?, String?, bool)? _lastPlayer;

  /// Mirrors the player in the "Lecture en cours" widget (only on change).
  static void syncPlayer(AudioPlayerController player) {
    final state = (
      player.active,
      player.title,
      player.subtitle,
      player.playing,
    );
    if (state == _lastPlayer) return;
    _lastPlayer = state;
    channel
        .invokeMethod('updatePlayer', {
          'active': player.active,
          'title': player.active ? player.title : null,
          'subtitle': player.subtitle,
          'playing': player.playing,
        })
        .catchError((_) => null);
  }
}

/// Runs the actions sent by shortcuts and widgets (open a folder, search,
/// music…), at launch and while the app is running.
class HomeActionsListener extends ConsumerStatefulWidget {
  const HomeActionsListener({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<HomeActionsListener> createState() => _HomeActionsState();
}

class _HomeActionsState extends ConsumerState<HomeActionsListener> {
  @override
  void initState() {
    super.initState();
    HomeLink.channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'action':
          await _run(Map<String, Object?>.from(call.arguments as Map));
        case 'control':
          final player = ref.read(audioPlayerProvider);
          switch (call.arguments) {
            case 'toggle':
              await player.toggle();
            case 'next':
              await player.next();
            case 'previous':
              await player.previous();
          }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final initial = await HomeLink.channel.invokeMapMethod<String, Object?>(
          'initialAction',
        );
        if (initial != null) await _run(initial);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    HomeLink.channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _run(Map<String, Object?> data) async {
    if (!mounted) return;
    final action = data['action'] as String? ?? '';
    final navigator = Navigator.of(context);
    navigator.popUntil((r) => r.isFirst);
    void push(Widget screen) =>
        navigator.push(MaterialPageRoute(builder: (_) => screen));
    switch (action) {
      case 'open_path':
        final path = data['path'] as String?;
        if (path == null) return;
        final entry = await ref
            .read(storageRepositoryProvider)
            .get(Uri.file(path));
        if (entry == null || !mounted) {
          _say('Ce dossier n’existe plus.');
          return;
        }
        ref.read(currentTabProvider.notifier).state = AppTab.files;
        await ref.read(filesControllerProvider.notifier).openDirectory(entry);
      case 'search':
        push(const SearchScreen());
      case 'cleaner':
        push(const CleanerScreen());
      case 'player':
        if (ref.read(audioPlayerProvider).active) {
          await openAudioPlayer(context);
        } else {
          _openCategory('audio', push);
        }
      case final String c when c.startsWith('category:'):
        _openCategory(c.substring('category:'.length), push);
      default:
        ref.read(currentTabProvider.notifier).state = AppTab.files;
    }
  }

  void _openCategory(String key, void Function(Widget) push) {
    final category = categories.where((c) => c.key == key).firstOrNull;
    if (category != null) push(CategoryScreen(category: category));
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

import 'dart:typed_data';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/design_tokens.dart';
import 'audio_player_controller.dart';

/// Opens the full "now playing" screen over the current route.
Future<void> openAudioPlayer(BuildContext context) =>
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: AppMotion.normal,
        reverseTransitionDuration: AppMotion.normal,
        pageBuilder: (_, _, _) => const AudioPlayerScreen(),
        transitionsBuilder: (_, animation, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: AppMotion.curve)),
          child: child,
        ),
      ),
    );

/// Square cover: embedded art, else an accent gradient with a note.
class AudioArtwork extends StatelessWidget {
  const AudioArtwork({
    super.key,
    required this.art,
    required this.size,
    this.radius = AppRadius.lg,
  });
  final Uint8List? art;
  final double size, radius;
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final hsl = HSLColor.fromColor(accent);
    final deep = hsl
        .withLightness((hsl.lightness - .2).clamp(0, 1))
        .withHue((hsl.hue + 30) % 360)
        .toColor();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: art != null
            ? Image.memory(
                art!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: (size * 2.5).round(),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [accent, deep],
                  ),
                ),
                child: Icon(
                  Icons.music_note_rounded,
                  size: size * .42,
                  color: AppTheme.onColor(accent).withValues(alpha: .9),
                ),
              ),
      ),
    );
  }
}

class AudioPlayerScreen extends ConsumerWidget {
  const AudioPlayerScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerProvider);
    final c = player.controller, accent = Theme.of(context).colorScheme.primary;
    if (c == null) {
      // Stopped from elsewhere: nothing left to show.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.maybePop(context);
      });
      return const Scaffold(backgroundColor: Colors.black);
    }
    final width = MediaQuery.sizeOf(context).width;
    final artSize = (width - 64).clamp(160.0, 360.0);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred cover as backdrop, darkened for contrast.
          if (player.info.art != null)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Image.memory(
                player.info.art!,
                fit: BoxFit.cover,
                cacheWidth: 120,
                gaplessPlayback: true,
              ),
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -.5),
                  radius: 1.2,
                  colors: [accent.withValues(alpha: .55), Colors.black],
                ),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Color(0xE6000000)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                children: [
                  _header(context, player),
                  const Spacer(),
                  Hero(
                    tag: 'audio-artwork',
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x80000000),
                            blurRadius: 40,
                            offset: Offset(0, 18),
                          ),
                        ],
                      ),
                      child: AudioArtwork(art: player.info.art, size: artSize),
                    ),
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          player.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.display,
                            fontWeight: FontWeight.w800,
                            fontSize: 26,
                            height: 1.15,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          player.subtitle ?? 'Artiste inconnu',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.body,
                            fontSize: 15,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (player.error != null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Lecture impossible pour ce fichier.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  else
                    _Progress(controller: c, accent: accent),
                  const SizedBox(height: 8),
                  _controls(player, accent),
                  const SizedBox(height: 12),
                  _footer(context, player, accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, AudioPlayerController player) => Row(
    children: [
      IconButton(
        tooltip: 'Réduire',
        color: Colors.white,
        iconSize: 30,
        onPressed: () => Navigator.maybePop(context),
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
      ),
      Expanded(
        child: Column(
          children: [
            const Text(
              'LECTURE EN COURS',
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
                color: Colors.white60,
              ),
            ),
            if (player.queue.length > 1)
              Text(
                '${player.index + 1} sur ${player.queue.length}',
                style: const TextStyle(
                  fontFamily: AppFonts.body,
                  fontSize: 12,
                  color: Colors.white54,
                ),
              ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Arrêter la lecture',
        color: Colors.white,
        onPressed: () async {
          await player.stop();
        },
        icon: const Icon(Icons.close_rounded),
      ),
    ],
  );

  Widget _controls(AudioPlayerController player, Color accent) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      IconButton(
        tooltip: player.shuffle
            ? 'Lecture aléatoire activée'
            : 'Lecture aléatoire',
        color: player.shuffle ? accent : Colors.white70,
        onPressed: player.queue.length > 1 ? player.toggleShuffle : null,
        icon: const Icon(Icons.shuffle_rounded),
      ),
      IconButton(
        tooltip: 'Précédent',
        color: Colors.white,
        iconSize: 34,
        onPressed: player.previous,
        icon: const Icon(Icons.skip_previous_rounded),
      ),
      SizedBox.square(
        dimension: 76,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: player.toggle,
            child: Semantics(
              button: true,
              label: player.playing ? 'Pause' : 'Lecture',
              child: Icon(
                player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 44,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
      IconButton(
        tooltip: 'Suivant',
        color: Colors.white,
        iconSize: 34,
        onPressed: player.hasNext ? player.next : null,
        icon: const Icon(Icons.skip_next_rounded),
      ),
      IconButton(
        tooltip: switch (player.repeat) {
          RepeatMode.off => 'Répéter',
          RepeatMode.all => 'Répéter tout',
          RepeatMode.one => 'Répéter ce titre',
        },
        color: player.repeat == RepeatMode.off ? Colors.white70 : accent,
        onPressed: player.cycleRepeat,
        icon: Icon(
          player.repeat == RepeatMode.one
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
        ),
      ),
    ],
  );

  Widget _footer(
    BuildContext context,
    AudioPlayerController player,
    Color accent,
  ) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.white70),
        onPressed: () => player.seekBy(-10),
        icon: const Icon(Icons.replay_10_rounded),
        label: const Text('10 s'),
      ),
      TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.white),
        onPressed: player.queue.length > 1
            ? () => _queue(context, player, accent)
            : null,
        icon: const Icon(Icons.queue_music_rounded),
        label: const Text('File d’attente'),
      ),
      TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.white70),
        onPressed: () => player.seekBy(10),
        icon: const Icon(Icons.forward_10_rounded),
        label: const Text('10 s'),
      ),
    ],
  );

  void _queue(
    BuildContext context,
    AudioPlayerController player,
    Color accent,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .6,
        builder: (_, scroll) => ListView.builder(
          controller: scroll,
          itemCount: player.queue.length,
          itemBuilder: (_, i) {
            final current = i == player.index;
            return ListTile(
              leading: current
                  ? Icon(Icons.graphic_eq_rounded, color: accent)
                  : Text('${i + 1}', style: Theme.of(c).textTheme.labelLarge),
              title: Text(
                player.queue[i].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: current
                    ? TextStyle(color: accent, fontWeight: FontWeight.w800)
                    : null,
              ),
              onTap: () {
                Navigator.pop(c);
                player.jumpTo(i);
              },
            );
          },
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.controller, required this.accent});
  final VideoPlayerController controller;
  final Color accent;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller,
    builder: (context, value, _) {
      final total = value.duration.inMilliseconds;
      final position = value.position.inMilliseconds.clamp(0, total);
      const style = TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 12,
        color: Colors.white70,
        fontFeatures: [FontFeature.tabularFigures()],
      );
      return Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: total == 0 ? 0 : position.toDouble(),
              max: total == 0 ? 1 : total.toDouble(),
              onChanged: total == 0
                  ? null
                  : (v) => controller.seekTo(Duration(milliseconds: v.round())),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatMediaTime(value.position), style: style),
                Text(formatMediaTime(value.duration), style: style),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// Compact player shown above the dock while music plays.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerProvider);
    final c = player.controller;
    if (c == null) return const SizedBox.shrink();
    final s = context.surfaces, accent = Theme.of(context).colorScheme.primary;
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 592),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Material(
            color: s.ink,
            elevation: 8,
            shadowColor: Colors.black45,
            borderRadius: BorderRadius.circular(AppRadius.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => openAudioPlayer(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'audio-artwork',
                          child: AudioArtwork(
                            art: player.info.art,
                            size: 44,
                            radius: AppRadius.xs,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                player.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: AppFonts.body,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: s.canvas,
                                ),
                              ),
                              Text(
                                player.subtitle ?? 'Lecture en cours',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: AppFonts.body,
                                  fontSize: 12,
                                  color: s.canvas.withValues(alpha: .65),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: player.playing ? 'Pause' : 'Lecture',
                          color: s.canvas,
                          onPressed: player.toggle,
                          icon: Icon(
                            player.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Suivant',
                          color: s.canvas,
                          onPressed: player.hasNext ? player.next : null,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                        IconButton(
                          tooltip: 'Arrêter la lecture',
                          color: s.canvas.withValues(alpha: .7),
                          onPressed: player.stop,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: c,
                    builder: (_, value, _) {
                      final total = value.duration.inMilliseconds;
                      return LinearProgressIndicator(
                        value: total == 0
                            ? 0
                            : value.position.inMilliseconds / total,
                        minHeight: 3,
                        color: accent,
                        backgroundColor: s.canvas.withValues(alpha: .12),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

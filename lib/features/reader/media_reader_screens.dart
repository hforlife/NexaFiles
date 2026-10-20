import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../core/readers/media_adapters.dart';

class MediaTrack {
  const MediaTrack(this.uri, this.title);
  final String uri, title;
}

VideoPlayerController _controllerFor(String uri) =>
    VideoPlayerController.file(File(Uri.parse(uri).toFilePath()));

String formatMediaTime(Duration value) {
  final h = value.inHours, m = value.inMinutes % 60, s = value.inSeconds % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
  return '${h > 0 ? '$h:' : ''}$mm:${s.toString().padLeft(2, '0')}';
}

/// Seek bar + elapsed / total time, driven by the controller.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.controller, this.color});
  final VideoPlayerController controller;
  final Color? color;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller,
    builder: (context, value, _) {
      final total = value.duration.inMilliseconds;
      final position = value.position.inMilliseconds.clamp(0, total);
      final style = TextStyle(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      return Row(
        children: [
          Text(formatMediaTime(value.position), style: style),
          Expanded(
            child: Slider(
              value: total == 0 ? 0 : position.toDouble(),
              max: total == 0 ? 1 : total.toDouble(),
              onChanged: total == 0
                  ? null
                  : (v) => controller.seekTo(Duration(milliseconds: v.round())),
            ),
          ),
          Text(formatMediaTime(value.duration), style: style),
        ],
      );
    },
  );
}

class AudioReaderScreen extends StatefulWidget {
  const AudioReaderScreen({
    super.key,
    required this.session,
    required this.title,
    this.tracks = const [],
    this.initialIndex = 0,
  });
  final MediaReaderSession session;
  final String title;

  /// Other tracks of the folder; playback continues through them.
  final List<MediaTrack> tracks;
  final int initialIndex;
  @override
  State<AudioReaderScreen> createState() => _AudioReaderScreenState();
}

class _AudioReaderScreenState extends State<AudioReaderScreen> {
  VideoPlayerController? controller;
  Object? error;
  late int index;
  bool _advancing = false;

  List<MediaTrack> get tracks => widget.tracks.isEmpty
      ? [MediaTrack(widget.session.source.id, widget.title)]
      : widget.tracks;
  MediaTrack get current => tracks[index];

  @override
  void initState() {
    super.initState();
    index = widget.initialIndex.clamp(0, tracks.length - 1);
    _load();
  }

  Future<void> _load() async {
    final previous = controller;
    final next = _controllerFor(current.uri);
    setState(() {
      controller = next;
      error = null;
    });
    await previous?.dispose();
    try {
      await next.initialize();
      next.addListener(_onTick);
      await next.play();
    } catch (e) {
      if (mounted && identical(controller, next)) setState(() => error = e);
    }
    if (mounted) setState(() {});
  }

  /// Moves to the next track when the current one finishes.
  void _onTick() {
    final value = controller?.value;
    if (value == null || _advancing || !value.isInitialized) return;
    final finished =
        value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying;
    if (finished && index + 1 < tracks.length) {
      _advancing = true;
      _skip(1).whenComplete(() => _advancing = false);
    }
  }

  Future<void> _skip(int delta) async {
    final next = index + delta;
    if (next < 0 || next >= tracks.length) return;
    setState(() => index = next);
    await _load();
  }

  void _seekBy(int seconds) {
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    c.seekTo(c.value.position + Duration(seconds: seconds));
  }

  @override
  void dispose() {
    controller?.removeListener(_onTick);
    controller?.dispose();
    widget.session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller, theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(current.title, maxLines: 1)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Icon(
                  Icons.music_note_rounded,
                  size: 96,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                current.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
              if (tracks.length > 1)
                Text(
                  '${index + 1} / ${tracks.length}',
                  style: theme.textTheme.bodySmall,
                ),
              const Spacer(),
              if (error != null)
                const Text('Lecture impossible pour ce fichier.')
              else if (c == null || !c.value.isInitialized)
                const LinearProgressIndicator()
              else
                _ProgressBar(controller: c),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: 'Précédent',
                    onPressed: index > 0 ? () => _skip(-1) : null,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  IconButton(
                    tooltip: 'Reculer de 10 s',
                    onPressed: () => _seekBy(-10),
                    icon: const Icon(Icons.replay_10_rounded),
                  ),
                  if (c != null)
                    ValueListenableBuilder(
                      valueListenable: c,
                      builder: (context, value, _) => IconButton.filled(
                        iconSize: 40,
                        tooltip: value.isPlaying ? 'Pause' : 'Lecture',
                        onPressed: value.isInitialized
                            ? () => value.isPlaying ? c.pause() : c.play()
                            : null,
                        icon: Icon(
                          value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Avancer de 10 s',
                    onPressed: () => _seekBy(10),
                    icon: const Icon(Icons.forward_10_rounded),
                  ),
                  IconButton(
                    tooltip: 'Suivant',
                    onPressed: index + 1 < tracks.length
                        ? () => _skip(1)
                        : null,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VideoReaderScreen extends StatefulWidget {
  const VideoReaderScreen({
    super.key,
    required this.session,
    required this.title,
  });
  final MediaReaderSession session;
  final String title;
  @override
  State<VideoReaderScreen> createState() => _VideoReaderScreenState();
}

class _VideoReaderScreenState extends State<VideoReaderScreen> {
  late final controller = _controllerFor(widget.session.source.id);
  bool controls = true, fullscreen = false;
  Object? error;
  Timer? hideTimer;

  @override
  void initState() {
    super.initState();
    controller.initialize().then(
      (_) {
        if (!mounted) return;
        setState(() {});
        controller.play();
        _scheduleHide();
      },
      onError: (Object e) {
        if (mounted) setState(() => error = e);
      },
    );
  }

  void _scheduleHide() {
    hideTimer?.cancel();
    hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && controller.value.isPlaying) {
        setState(() => controls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => controls = !controls);
    if (controls) _scheduleHide();
  }

  Future<void> _toggleFullscreen() async {
    fullscreen = !fullscreen;
    if (fullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await _restoreSystemUi();
    }
    if (mounted) setState(() {});
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const []);
  }

  @override
  void dispose() {
    hideTimer?.cancel();
    _restoreSystemUi();
    controller.dispose();
    widget.session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = controller.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          children: [
            Center(
              child: error != null
                  ? const Text(
                      'Lecture impossible pour cette vidéo.',
                      style: TextStyle(color: Colors.white),
                    )
                  : ready
                  ? AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    )
                  : const CircularProgressIndicator(),
            ),
            IgnorePointer(
              ignoring: !controls,
              child: AnimatedOpacity(
                opacity: controls ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: _overlay(ready),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _overlay(bool ready) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.black54, Colors.transparent, Colors.black54],
      ),
    ),
    child: SafeArea(
      child: Column(
        children: [
          Row(
            children: [
              const BackButton(color: Colors.white),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              IconButton(
                tooltip: fullscreen ? 'Quitter le plein écran' : 'Plein écran',
                color: Colors.white,
                onPressed: _toggleFullscreen,
                icon: Icon(
                  fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (ready)
            ValueListenableBuilder(
              valueListenable: controller,
              builder: (context, value, _) => IconButton.filledTonal(
                iconSize: 48,
                tooltip: value.isPlaying ? 'Pause' : 'Lecture',
                onPressed: () {
                  value.isPlaying ? controller.pause() : controller.play();
                  _scheduleHide();
                },
                icon: Icon(
                  value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
            ),
          const Spacer(),
          if (ready)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ProgressBar(controller: controller, color: Colors.white),
            ),
        ],
      ),
    ),
  );
}

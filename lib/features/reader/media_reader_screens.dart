import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../core/readers/media_adapters.dart';
import '../player/audio_player_controller.dart';
import 'reader_kit.dart';

export '../player/audio_player_controller.dart'
    show MediaTrack, formatMediaTime;

/// Seek bar + elapsed / total time, driven by the controller.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.controller});
  final VideoPlayerController controller;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller,
    builder: (context, value, _) {
      final total = value.duration.inMilliseconds;
      final position = value.position.inMilliseconds.clamp(0, total);
      const style = TextStyle(
        color: ReaderColors.text,
        fontSize: 12,
        fontFeatures: [FontFeature.tabularFigures()],
      );
      return Row(
        children: [
          const SizedBox(width: 8),
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
          const SizedBox(width: 8),
        ],
      );
    },
  );
}

class VideoReaderScreen extends StatefulWidget {
  const VideoReaderScreen({
    super.key,
    required this.session,
    required this.title,
    this.onOpenExternal,
  });
  final MediaReaderSession session;
  final String title;

  /// Hands the file to another app when it cannot be played here.
  final VoidCallback? onOpenExternal;
  @override
  State<VideoReaderScreen> createState() => _VideoReaderScreenState();
}

class _VideoReaderScreenState extends State<VideoReaderScreen> {
  late VideoPlayerController controller;
  bool controls = true, fullscreen = false;
  Object? error;
  Timer? hideTimer;

  /// Some devices (seen on Huawei) cannot decode into Flutter's texture
  /// surface ("MediaCodecVideoRenderer error") but play fine in a native
  /// SurfaceView: on failure we retry once with a platform view.
  bool _platformView = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    controller = VideoPlayerController.file(
      File(Uri.parse(widget.session.source.id).toFilePath()),
      viewType: _platformView
          ? VideoViewType.platformView
          : VideoViewType.textureView,
    )..addListener(_watchErrors);
    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      controller.play();
      _scheduleHide();
    }, onError: (Object e) => _failed(e));
  }

  /// Decoder errors can also surface after initialisation, on first frame.
  void _watchErrors() {
    final value = controller.value;
    if (value.hasError && error == null) {
      _failed(value.errorDescription ?? 'Erreur du décodeur vidéo');
    }
  }

  void _failed(Object e) {
    if (!mounted) return;
    if (!_platformView) {
      final old = controller;
      old.removeListener(_watchErrors);
      setState(() {
        _platformView = true;
        _start();
      });
      old.dispose();
      return;
    }
    setState(() => error = e);
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
      // Vertical videos stay in portrait; only wide ones rotate.
      final wide = controller.value.aspectRatio >= 1;
      await SystemChrome.setPreferredOrientations(
        wide
            ? const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const [DeviceOrientation.portraitUp],
      );
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
    controller.removeListener(_watchErrors);
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
        onDoubleTapDown: ready ? _doubleTapSeek : null,
        onDoubleTap: ready ? () {} : null,
        child: Stack(
          children: [
            Center(
              child: error != null
                  ? _errorView()
                  : ready
                  ? AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    )
                  : const CircularProgressIndicator(color: Colors.white54),
            ),
            if (error == null)
              Positioned.fill(
                child: ReaderFade(visible: controls, child: _overlay(ready)),
              ),
            if (error != null)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: ReaderTopBar(title: widget.title),
              ),
          ],
        ),
      ),
    );
  }

  /// Double tap on the left / right half seeks 10 s back / forward.
  void _doubleTapSeek(TapDownDetails d) {
    final width = MediaQuery.sizeOf(context).width;
    final delta = d.localPosition.dx < width / 2 ? -10 : 10;
    controller.seekTo(controller.value.position + Duration(seconds: delta));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 700),
          content: Text(delta < 0 ? '− 10 s' : '+ 10 s'),
        ),
      );
  }

  Widget _errorView() => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 56),
        const SizedBox(height: 16),
        const Text(
          'Cette vidéo ne peut pas être lue ici',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _errorText(error!),
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white60, fontSize: 13),
        ),
        if (widget.onOpenExternal != null) ...[
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: widget.onOpenExternal,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Ouvrir avec une autre app'),
          ),
        ],
      ],
    ),
  );

  /// Short, readable reason (codec, missing file…) for bug reports.
  String _errorText(Object e) {
    final text = e is PlatformException ? (e.message ?? e.code) : e.toString();
    return text.replaceFirst(RegExp(r'^\w+Exception: '), '');
  }

  Widget _overlay(bool ready) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x99000000), Colors.transparent, Color(0x99000000)],
        stops: [0, .5, 1],
      ),
    ),
    child: Column(
      children: [
        ReaderTopBar(
          title: widget.title,
          actions: [
            IconButton(
              tooltip: fullscreen ? 'Quitter le plein écran' : 'Plein écran',
              onPressed: _toggleFullscreen,
              icon: Icon(
                fullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
              ),
            ),
          ],
        ),
        const Spacer(),
        if (ready)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Reculer de 10 s',
                color: Colors.white,
                iconSize: 36,
                onPressed: () {
                  controller.seekTo(
                    controller.value.position - const Duration(seconds: 10),
                  );
                  _scheduleHide();
                },
                icon: const Icon(Icons.replay_10_rounded),
              ),
              const SizedBox(width: 28),
              ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, value, _) => SizedBox.square(
                  dimension: 72,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        value.isPlaying
                            ? controller.pause()
                            : controller.play();
                        _scheduleHide();
                      },
                      child: Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 42,
                        color: Colors.black,
                        semanticLabel: value.isPlaying ? 'Pause' : 'Lecture',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 28),
              IconButton(
                tooltip: 'Avancer de 10 s',
                color: Colors.white,
                iconSize: 36,
                onPressed: () {
                  controller.seekTo(
                    controller.value.position + const Duration(seconds: 10),
                  );
                  _scheduleHide();
                },
                icon: const Icon(Icons.forward_10_rounded),
              ),
            ],
          ),
        const Spacer(),
        if (ready)
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ReaderGlass(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _ProgressBar(controller: controller),
            ),
          ),
      ],
    ),
  );
}

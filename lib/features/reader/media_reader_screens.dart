import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/readers/media_adapters.dart';

class MediaTrack {
  const MediaTrack(this.uri, this.title);
  final String uri, title;
}

class AudioReaderScreen extends StatefulWidget {
  const AudioReaderScreen(
      {super.key,
      required this.session,
      required this.title,
      this.tracks = const [],
      this.initialIndex = 0});
  final MediaReaderSession session;
  final String title;
  final List<MediaTrack> tracks;
  final int initialIndex;
  @override
  State<AudioReaderScreen> createState() => _AudioReaderScreenState();
}

class _AudioReaderScreenState extends State<AudioReaderScreen> {
  static const channel = MethodChannel('nexa_file/audio');
  Timer? timer;
  int position = 0, duration = 1, index = 0;
  bool playing = false, loading = true;
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
    if (mounted) setState(() => loading = true);
    final state = await channel
        .invokeMapMethod<Object?, Object?>('load', {'uri': current.uri});
    duration = ((state?['duration'] as int?)?.clamp(1, 1 << 31) ?? 1).toInt();
    position = 0;
    timer ??= Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
    if (mounted) setState(() => loading = false);
  }

  Future<void> _poll() async {
    final state = await channel.invokeMapMethod<Object?, Object?>('state');
    if (mounted && state != null) {
      setState(() {
        position = state['position'] as int;
        duration = (state['duration'] as int).clamp(1, 1 << 31).toInt();
        playing = state['playing'] as bool;
      });
    }
  }

  Future<void> _skip(int delta) async {
    final next = index + delta;
    if (next < 0 || next >= tracks.length) return;
    setState(() => index = next);
    await _load();
    await channel.invokeMethod<void>('play');
  }

  @override
  void dispose() {
    timer?.cancel();
    channel.invokeMethod<void>('dispose');
    widget.session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(current.title)),
      body: Center(
          child: loading
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.album, size: 140),
                    const SizedBox(height: 20),
                    Text(current.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge),
                    Slider(
                        value: position.clamp(0, duration).toDouble(),
                        max: duration.toDouble(),
                        onChanged: (v) => setState(() => position = v.round()),
                        onChangeEnd: (v) => channel
                            .invokeMethod('seek', {'position': v.round()})),
                    Text('${_time(position)} / ${_time(duration)}'),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(
                          onPressed: index > 0 ? () => _skip(-1) : null,
                          icon: const Icon(Icons.skip_previous)),
                      IconButton.filled(
                          onPressed: () async {
                            await channel
                                .invokeMethod(playing ? 'pause' : 'play');
                            _poll();
                          },
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow)),
                      IconButton(
                          onPressed:
                              index + 1 < tracks.length ? () => _skip(1) : null,
                          icon: const Icon(Icons.skip_next))
                    ])
                  ]))));
  String _time(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

class VideoReaderScreen extends StatefulWidget {
  const VideoReaderScreen(
      {super.key, required this.session, required this.title});
  final MediaReaderSession session;
  final String title;
  @override
  State<VideoReaderScreen> createState() => _VideoReaderScreenState();
}

class _VideoReaderScreenState extends State<VideoReaderScreen> {
  bool full = false;
  Future<void> _toggle() async {
    full = !full;
    if (full) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight
      ]);
    } else {
      await _restore();
    }
    if (mounted) setState(() {});
  }

  Future<void> _restore() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight
    ]);
  }

  @override
  void dispose() {
    _restore();
    widget.session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.black,
      appBar: full
          ? null
          : AppBar(title: Text(widget.title), actions: [
              IconButton(
                  tooltip: 'Plein écran',
                  onPressed: _toggle,
                  icon: const Icon(Icons.fullscreen))
            ]),
      body: Stack(children: [
        Positioned.fill(
            child: AndroidView(
                viewType: 'nexa_file/video',
                creationParams: {'uri': widget.session.source.id},
                creationParamsCodec: const StandardMessageCodec())),
        if (full)
          Positioned(
              right: 12,
              top: 12,
              child: IconButton.filledTonal(
                  tooltip: 'Quitter le plein écran',
                  onPressed: _toggle,
                  icon: const Icon(Icons.fullscreen_exit)))
      ]));
}

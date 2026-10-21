import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../core/cache/file_preview_service.dart';
import '../home/home_link.dart';

/// One playable file of the queue.
class MediaTrack {
  const MediaTrack(this.uri, this.title);
  final String uri, title;
}

enum RepeatMode { off, all, one }

/// App-wide audio playback. It outlives the player screen, so music keeps
/// playing when the screen is minimised to the mini player.
final audioPlayerProvider = ChangeNotifierProvider<AudioPlayerController>((
  ref,
) {
  final player = AudioPlayerController();
  // Keeps the "Lecture en cours" home-screen widget up to date.
  player.addListener(() => HomeLink.syncPlayer(player));
  return player;
});

class AudioPlayerController extends ChangeNotifier {
  AudioPlayerController({VideoPlayerController Function(String uri)? factory})
    : _factory = factory ?? _fileController;

  static VideoPlayerController _fileController(String uri) =>
      VideoPlayerController.file(
        File(Uri.parse(uri).toFilePath()),
        // Keeps playing when the app goes to the background.
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
      );

  final VideoPlayerController Function(String uri) _factory;
  final _random = Random();

  List<MediaTrack> queue = const [];
  int index = 0;
  VideoPlayerController? controller;
  AudioInfo info = AudioInfo.empty;
  Object? error;
  RepeatMode repeat = RepeatMode.off;
  bool shuffle = false;
  bool _playing = false, _advancing = false;
  int _loadToken = 0;

  bool get active => controller != null;
  bool get playing => _playing;
  MediaTrack? get current => queue.isEmpty ? null : queue[index];

  /// Display title: tag title, else the file name without extension.
  String get title {
    final t = info.title;
    if (t != null) return t;
    final name = current?.title ?? '';
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  String? get subtitle {
    final parts = [?info.artist, ?info.album];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  bool get hasNext =>
      queue.length > 1 &&
      (index + 1 < queue.length || repeat == RepeatMode.all);
  bool get hasPrevious => index > 0 || repeat == RepeatMode.all;

  /// Plays [tracks] from [start], replacing the current queue.
  Future<void> play(List<MediaTrack> tracks, int start) async {
    if (tracks.isEmpty) return;
    final same =
        listEquals(
          [for (final t in queue) t.uri],
          [for (final t in tracks) t.uri],
        ) &&
        start == index &&
        controller != null;
    if (same) {
      await resume();
      return;
    }
    queue = List.unmodifiable(tracks);
    index = start.clamp(0, tracks.length - 1);
    await _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final previous = controller;
    previous?.removeListener(_onTick);
    final next = _factory(queue[index].uri);
    controller = next;
    error = null;
    info = AudioInfo.empty;
    _playing = false;
    notifyListeners();
    unawaited(previous?.dispose());
    unawaited(
      FilePreviewService.instance.audioInfo(queue[index].uri).then((value) {
        if (token != _loadToken) return;
        info = value;
        notifyListeners();
      }),
    );
    try {
      await next.initialize();
      if (token != _loadToken) return;
      next.addListener(_onTick);
      await next.play();
    } catch (e) {
      if (token == _loadToken) error = e;
    }
    if (token == _loadToken) notifyListeners();
  }

  /// Follows play / pause and moves on when a track ends.
  void _onTick() {
    final value = controller?.value;
    if (value == null || !value.isInitialized) return;
    if (value.isPlaying != _playing) {
      _playing = value.isPlaying;
      notifyListeners();
    }
    final finished =
        value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying;
    if (!finished || _advancing) return;
    _advancing = true;
    final Future<void> step = switch (repeat) {
      RepeatMode.one =>
        controller!.seekTo(Duration.zero).then((_) => controller!.play()),
      _ when hasNext => next(),
      _ => Future.value(),
    };
    step.whenComplete(() => _advancing = false);
  }

  Future<void> next() async {
    if (queue.isEmpty) return;
    if (shuffle && queue.length > 1) {
      var target = index;
      while (target == index) {
        target = _random.nextInt(queue.length);
      }
      index = target;
    } else if (index + 1 < queue.length) {
      index++;
    } else if (repeat == RepeatMode.all) {
      index = 0;
    } else {
      return;
    }
    await _load();
  }

  /// Restarts the track after 3 s, otherwise goes to the previous one.
  Future<void> previous() async {
    final c = controller;
    if (c != null && c.value.position > const Duration(seconds: 3)) {
      await c.seekTo(Duration.zero);
      return;
    }
    if (index > 0) {
      index--;
    } else if (repeat == RepeatMode.all) {
      index = queue.length - 1;
    } else {
      await c?.seekTo(Duration.zero);
      return;
    }
    await _load();
  }

  Future<void> jumpTo(int value) async {
    if (value < 0 || value >= queue.length || value == index) return;
    index = value;
    await _load();
  }

  Future<void> toggle() async {
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      await c.pause();
      return;
    }
    // Play after the end (queue finished): start the track over.
    final v = c.value;
    if (v.duration > Duration.zero && v.position >= v.duration) {
      await c.seekTo(Duration.zero);
    }
    await c.play();
  }

  Future<void> resume() async => controller?.play();
  Future<void> pause() async => controller?.pause();

  Future<void> seekBy(int seconds) async {
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    await c.seekTo(c.value.position + Duration(seconds: seconds));
  }

  void cycleRepeat() {
    repeat = RepeatMode.values[(repeat.index + 1) % RepeatMode.values.length];
    notifyListeners();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  /// Stops playback and hides the mini player.
  Future<void> stop() async {
    _loadToken++;
    final c = controller;
    controller = null;
    queue = const [];
    index = 0;
    info = AudioInfo.empty;
    _playing = false;
    error = null;
    notifyListeners();
    c?.removeListener(_onTick);
    await c?.dispose();
  }

  @override
  void dispose() {
    controller?.removeListener(_onTick);
    controller?.dispose();
    super.dispose();
  }
}

String formatMediaTime(Duration value) {
  final h = value.inHours, m = value.inMinutes % 60, s = value.inSeconds % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
  return '${h > 0 ? '$h:' : ''}$mm:${s.toString().padLeft(2, '0')}';
}

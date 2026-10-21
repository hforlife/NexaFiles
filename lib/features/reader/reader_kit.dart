import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/design_tokens.dart';
import '../../core/database/app_database.dart';
import 'comic_reader_screen.dart'
    show ComicReadingDirection, ComicTapAction, comicTapAction;

/// Screen orientation while reading.
enum ReaderOrientation { auto, portrait, landscape }

/// Which part of the screen turns pages in the comic reader.
enum ComicTapLayout {
  /// Left / right thirds, centre toggles the controls.
  edges,

  /// "L": top and left go back, bottom and right go forward.
  lShape,

  /// Kindle style: a narrow left strip goes back, the rest goes forward.
  kindle,

  /// Taps only toggle the controls; swipe to turn pages.
  off,
}

/// Reading options shared by every reader, stored globally.
class ReaderPrefs {
  const ReaderPrefs({
    this.orientation = ReaderOrientation.auto,
    this.tapLayout = ComicTapLayout.edges,
    this.doubleTapZoom = false,
  });
  final ReaderOrientation orientation;
  final ComicTapLayout tapLayout;

  /// Off by default: a double-tap listener delays every single tap
  /// (~300 ms) while Flutter waits for a possible second tap.
  final bool doubleTapZoom;

  static const _orientation = 'reader.orientation',
      _tapLayout = 'reader.tapLayout',
      _doubleTap = 'reader.doubleTapZoom';

  static Future<ReaderPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    return ReaderPrefs(
      orientation:
          ReaderOrientation.values.asNameMap()[p.getString(_orientation)] ??
          ReaderOrientation.auto,
      tapLayout:
          ComicTapLayout.values.asNameMap()[p.getString(_tapLayout)] ??
          ComicTapLayout.edges,
      doubleTapZoom: p.getBool(_doubleTap) ?? false,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_orientation, orientation.name);
    await p.setString(_tapLayout, tapLayout.name);
    await p.setBool(_doubleTap, doubleTapZoom);
  }

  ReaderPrefs copyWith({
    ReaderOrientation? orientation,
    ComicTapLayout? tapLayout,
    bool? doubleTapZoom,
  }) => ReaderPrefs(
    orientation: orientation ?? this.orientation,
    tapLayout: tapLayout ?? this.tapLayout,
    doubleTapZoom: doubleTapZoom ?? this.doubleTapZoom,
  );
}

/// Locks (or frees) the screen orientation for a reader.
Future<void> applyReaderOrientation(ReaderOrientation value) =>
    SystemChrome.setPreferredOrientations(switch (value) {
      ReaderOrientation.auto => const [],
      ReaderOrientation.portrait => const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ],
      ReaderOrientation.landscape => const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    });

/// Restores free rotation when a reader closes.
Future<void> releaseReaderOrientation() =>
    SystemChrome.setPreferredOrientations(const []);

String orientationLabel(ReaderOrientation value) => switch (value) {
  ReaderOrientation.auto => 'Auto',
  ReaderOrientation.portrait => 'Portrait',
  ReaderOrientation.landscape => 'Paysage',
};

IconData orientationIcon(ReaderOrientation value) => switch (value) {
  ReaderOrientation.auto => Icons.screen_rotation_rounded,
  ReaderOrientation.portrait => Icons.stay_current_portrait_rounded,
  ReaderOrientation.landscape => Icons.stay_current_landscape_rounded,
};

String tapLayoutLabel(ComicTapLayout value) => switch (value) {
  ComicTapLayout.edges => 'Bords gauche / droite',
  ComicTapLayout.lShape => 'Forme en L',
  ComicTapLayout.kindle => 'Style liseuse',
  ComicTapLayout.off => 'Désactivées',
};

/// Colours of the reading chrome: dark glass whatever the app theme.
abstract final class ReaderColors {
  static const Color glass = Color(0xD9121316);
  static const Color line = Color(0x26FFFFFF);
  static const Color text = Colors.white;
  static const Color muted = Color(0xB3FFFFFF);
}

/// Frosted dark panel used for the reader's top bar and bottom controls.
class ReaderGlass extends StatelessWidget {
  const ReaderGlass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(8),
    this.radius = AppRadius.md,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ReaderColors.glass,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: ReaderColors.line),
        ),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

/// Floating top bar: back, title (+ subtitle) and actions.
class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.onBack,
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    minimum: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    child: ReaderGlass(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      radius: AppRadius.pill,
      child: IconTheme(
        data: const IconThemeData(color: ReaderColors.text),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Retour',
              onPressed: onBack ?? () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.body,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: ReaderColors.text,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      style: const TextStyle(
                        fontFamily: AppFonts.body,
                        fontSize: 12,
                        color: ReaderColors.muted,
                      ),
                    ),
                ],
              ),
            ),
            ...actions,
          ],
        ),
      ),
    ),
  );
}

/// Accent-coloured pill showing "page / total"; tappable to jump.
class ReaderPageChip extends StatelessWidget {
  const ReaderPageChip({super.key, required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: accent,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AppTheme.onColor(accent),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lists the bookmarks of [itemId]; tapping one returns its locator.
Future<String?> showBookmarksSheet(
  BuildContext context, {
  required AppDatabase database,
  required String itemId,
  Future<void> Function()? onAdd,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (c) =>
      _BookmarksSheet(database: database, itemId: itemId, onAdd: onAdd),
);

class _BookmarksSheet extends StatefulWidget {
  const _BookmarksSheet({
    required this.database,
    required this.itemId,
    this.onAdd,
  });
  final AppDatabase database;
  final String itemId;

  /// Saves a bookmark at the current position; the list reloads after.
  final Future<void> Function()? onAdd;
  @override
  State<_BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends State<_BookmarksSheet> {
  late Future<List<BookmarkRecord>> items = widget.database.bookmarks(
    widget.itemId,
  );

  void _reload() {
    items = widget.database.bookmarks(widget.itemId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), s = context.surfaces;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Signets', style: theme.textTheme.titleLarge),
                  ),
                  if (widget.onAdd != null)
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        await widget.onAdd!();
                        if (mounted) setState(_reload);
                      },
                      icon: const Icon(Icons.bookmark_add_rounded),
                      label: const Text('Ajouter ici'),
                    ),
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<List<BookmarkRecord>>(
                future: items,
                builder: (context, snapshot) {
                  final list = snapshot.data;
                  if (list == null) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                      child: Text(
                        'Aucun signet pour l’instant. Ajoutez-en un pour revenir '
                        'directement à ce passage.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: s.muted,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final b = list[i];
                      return Dismissible(
                        key: ValueKey(b.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(
                            Icons.delete_outline_rounded,
                            color: theme.colorScheme.onError,
                          ),
                        ),
                        onDismissed: (_) =>
                            widget.database.deleteBookmark(b.id),
                        child: ListTile(
                          leading: Icon(
                            Icons.bookmark_rounded,
                            color: theme.colorScheme.primary,
                          ),
                          title: Text(b.label ?? 'Signet'),
                          subtitle: Text(_date(b.createdAt)),
                          trailing: IconButton(
                            tooltip: 'Supprimer',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () async {
                              await widget.database.deleteBookmark(b.id);
                              if (mounted) setState(_reload);
                            },
                          ),
                          onTap: () => Navigator.pop(context, b.locator),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _date(DateTime value) {
    final d = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Ajouté le ${two(d.day)}/${two(d.month)}/${d.year} à ${two(d.hour)}:${two(d.minute)}';
  }
}

/// Options sheet section: orientation picker as segmented buttons.
class OrientationPicker extends StatelessWidget {
  const OrientationPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final ReaderOrientation value;
  final ValueChanged<ReaderOrientation> onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SegmentedButton<ReaderOrientation>(
      showSelectedIcon: false,
      segments: [
        for (final v in ReaderOrientation.values)
          ButtonSegment(
            value: v,
            icon: Icon(orientationIcon(v)),
            label: Text(orientationLabel(v)),
          ),
      ],
      selected: {value},
      onSelectionChanged: (v) => onChanged(v.first),
    ),
  );
}

/// Small uppercase heading inside option sheets.
class SheetLabel extends StatelessWidget {
  const SheetLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: context.surfaces.muted,
        letterSpacing: 1.3,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

/// Fades and slides reader chrome in and out.
class ReaderFade extends StatelessWidget {
  const ReaderFade({super.key, required this.visible, required this.child});
  final bool visible;
  final Widget child;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: AppMotion.fast,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, .15),
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        child: child,
      ),
    ),
  );
}

/// Row of the four tap layouts, each drawn as a mini diagram.
class TapLayoutPicker extends StatelessWidget {
  const TapLayoutPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final ComicTapLayout value;
  final ValueChanged<ComicTapLayout> onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final v in ComicTapLayout.values)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _TapLayoutTile(
              layout: v,
              selected: value == v,
              onTap: () => onChanged(v),
            ),
          ),
        ),
    ],
  );
}

/// Mini diagram of a tap layout: red = previous, accent = next, grey = menu.
class _TapLayoutTile extends StatelessWidget {
  const _TapLayoutTile({
    required this.layout,
    required this.selected,
    required this.onTap,
  });
  final ComicTapLayout layout;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), accent = theme.colorScheme.primary;
    final line = theme.colorScheme.outlineVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: tapLayoutLabel(layout),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 86,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? accent : line,
                  width: selected ? 2.5 : 1.2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: CustomPaint(
                  painter: _TapLayoutPainter(
                    layout: layout,
                    previous: const Color(0xFFE5484D).withValues(alpha: .55),
                    next: accent.withValues(alpha: .6),
                    menu: line.withValues(alpha: .5),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              switch (layout) {
                ComicTapLayout.edges => 'Bords',
                ComicTapLayout.lShape => 'En L',
                ComicTapLayout.kindle => 'Liseuse',
                ComicTapLayout.off => 'Aucune',
              },
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TapLayoutPainter extends CustomPainter {
  _TapLayoutPainter({
    required this.layout,
    required this.previous,
    required this.next,
    required this.menu,
  });
  final ComicTapLayout layout;
  final Color previous, next, menu;
  @override
  void paint(Canvas canvas, Size size) {
    // Samples the real hit-test function so the diagram never lies. Cells
    // of one action form a single path: no seams between them.
    const steps = 24;
    final cw = size.width / steps, ch = size.height / steps;
    final paths = {for (final a in ComicTapAction.values) a: Path()};
    for (var i = 0; i < steps; i++) {
      for (var j = 0; j < steps; j++) {
        final action = comicTapAction(
          dx: (i + .5) * cw,
          dy: (j + .5) * ch,
          width: size.width,
          height: size.height,
          direction: ComicReadingDirection.leftToRight,
          layout: layout,
        );
        paths[action]!.addRect(Rect.fromLTWH(i * cw, j * ch, cw, ch));
      }
    }
    final colors = {
      ComicTapAction.previous: previous,
      ComicTapAction.next: next,
      ComicTapAction.toggleControls: menu,
    };
    for (final MapEntry(key: action, value: path) in paths.entries) {
      // Union of adjacent rects: filled once, no visible grid.
      canvas.drawPath(
        Path.combine(PathOperation.union, Path(), path),
        Paint()..color = colors[action]!,
      );
    }
  }

  @override
  bool shouldRepaint(_TapLayoutPainter old) =>
      old.layout != layout || old.next != next;
}

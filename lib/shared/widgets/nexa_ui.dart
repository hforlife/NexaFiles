import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/design_tokens.dart';

/// Bottom padding for scrollables living under the floating dock.
double dockInset(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + AppSpacing.lg;

/// Large page title with optional eyebrow and trailing actions.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(20, 12, 12, 8),
  });
  final Widget title;
  final String? eyebrow, subtitle;
  final List<Widget> actions;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), s = context.surfaces;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null)
                  Text(
                    eyebrow!.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: s.muted,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                DefaultTextStyle.merge(
                  style: theme.textTheme.headlineLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: title,
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: s.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (final action in actions)
            Padding(padding: const EdgeInsets.only(left: 8), child: action),
        ],
      ),
    );
  }
}

/// Circular outlined button used in headers.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge = false,
    this.filled = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool badge, filled;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces, accent = context.accent;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? s.ink : s.card,
        shape: CircleBorder(side: BorderSide(color: s.line)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Badge(
              isLabelVisible: badge,
              smallSize: 9,
              backgroundColor: accent,
              alignment: const AlignmentDirectional(.55, -.55),
              child: Center(
                child: Icon(icon, size: 22, color: filled ? s.canvas : s.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Section title with an optional trailing action.
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.text, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 24, 12, 10),
  });
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?trailing,
      ],
    ),
  );
}

/// One entry of the floating dock.
class DockDestination {
  const DockDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
  final IconData icon, selectedIcon;
  final String label;
}

/// Floating navigation: a pill holding the file-manager destinations, and a
/// detached, book-shaped button for the library. Entering the library turns
/// the pill into the library's ink style.
class NexaDock extends StatelessWidget {
  const NexaDock({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelected,
    required this.library,
    required this.librarySelected,
    required this.onLibrary,
  });

  /// File-manager destinations; [selected] indexes them (-1 = none).
  final List<DockDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;
  final DockDestination library;
  final bool librarySelected;
  final VoidCallback onLibrary;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final atelier = NexaSurfaces.atelier(brightness),
        salon = NexaSurfaces.salon(brightness),
        accent = context.accent,
        isLight = brightness == Brightness.light;
    // In the library the pill becomes a dark "ink" bar on paper.
    final pillColor = librarySelected
        ? (isLight ? salon.ink : salon.cardAlt)
        : atelier.card;
    final iconColor = librarySelected
        ? (isLight ? salon.canvas : salon.ink).withValues(alpha: .72)
        : atelier.muted;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      // Centred and capped in landscape so the pill does not stretch.
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SizedBox(
            height: 66,
            child: Row(
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: AppMotion.normal,
                    curve: AppMotion.curve,
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: pillColor,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: librarySelected
                            ? Colors.transparent
                            : atelier.line.withValues(alpha: .8),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isLight ? .10 : .4,
                          ),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < destinations.length; i++)
                          Expanded(
                            flex: i == selected ? 5 : 3,
                            child: _DockItem(
                              key: ValueKey('dock-$i'),
                              destination: destinations[i],
                              selected: i == selected,
                              accent: accent,
                              idleColor: iconColor,
                              onTap: () => onSelected(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _LibraryButton(
                  key: const ValueKey('dock-library'),
                  destination: library,
                  selected: librarySelected,
                  accent: accent,
                  paper: salon.card,
                  onTap: onLibrary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    super.key,
    required this.destination,
    required this.selected,
    required this.accent,
    required this.idleColor,
    required this.onTap,
  });
  final DockDestination destination;
  final bool selected;
  final Color accent, idleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: destination.label,
    onTap: onTap,
    excludeSemantics: true,
    child: Tooltip(
      message: destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: AppMotion.normal,
          curve: AppMotion.curve,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 23,
                  color: selected ? AppTheme.onColor(accent) : idleColor,
                ),
                Flexible(
                  child: AnimatedSize(
                    duration: AppMotion.normal,
                    curve: AppMotion.curve,
                    child: selected
                        ? Padding(
                            padding: const EdgeInsets.only(left: 7),
                            child: Text(
                              destination.label,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: TextStyle(
                                fontFamily: AppFonts.body,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                color: AppTheme.onColor(accent),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Book-shaped library button: a spine stripe on the left and a cover.
class _LibraryButton extends StatelessWidget {
  const _LibraryButton({
    super.key,
    required this.destination,
    required this.selected,
    required this.accent,
    required this.paper,
    required this.onTap,
  });
  final DockDestination destination;
  final bool selected;
  final Color accent, paper;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(accent);
    final deep = hsl.withLightness((hsl.lightness - .16).clamp(0, 1)).toColor();
    final fg = selected ? accent : AppTheme.onColor(accent);
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: destination.label,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: AppMotion.normal,
            curve: AppMotion.curve,
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              gradient: selected
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accent, deep],
                    ),
              color: selected ? paper : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                bottomLeft: Radius.circular(10),
                topRight: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              border: selected ? Border.all(color: accent, width: 2) : null,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: selected ? .25 : .45),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Spine.
                Positioned(
                  left: 9,
                  top: 10,
                  bottom: 10,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      color: fg,
                      size: 27,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft coloured squircle holding an icon.
class IconBubble extends StatelessWidget {
  const IconBubble({
    super.key,
    required this.icon,
    required this.color,
    this.size = 48,
  });
  final IconData icon;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(
        alpha: Theme.of(context).brightness == Brightness.light ? .14 : .24,
      ),
      borderRadius: BorderRadius.circular(size * .32),
    ),
    child: Icon(icon, color: color, size: size * .52),
  );
}

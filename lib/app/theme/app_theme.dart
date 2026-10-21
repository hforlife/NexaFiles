import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// Builds the two themes of the app from the user's accent colour:
/// the file manager ("Atelier") and the library ("Salon de lecture").
abstract final class AppTheme {
  static final Map<(Brightness, int, bool), ThemeData> _cache = {};

  static ThemeData light(Color accent) => build(Brightness.light, accent);
  static ThemeData dark(Color accent) => build(Brightness.dark, accent);

  /// Library variant of the ambient theme: warm surfaces and serif titles.
  static ThemeData library(ThemeData ambient) => build(
    ambient.brightness,
    ambient.extension<_Accent>()?.value ?? ambient.colorScheme.primary,
    library: true,
  );

  static ThemeData build(
    Brightness brightness,
    Color accent, {
    bool library = false,
  }) => _cache.putIfAbsent((
    brightness,
    accent.toARGB32(),
    library,
  ), () => _build(brightness, accent, library));

  static ThemeData _build(Brightness brightness, Color accent, bool library) {
    final isLight = brightness == Brightness.light;
    final s = library
        ? NexaSurfaces.salon(brightness)
        : NexaSurfaces.atelier(brightness);
    final base = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    // Keep the exact picked colour in light mode; the dark scheme already
    // brightens it for contrast. A near-black accent ("Encre") stays legible
    // in dark mode through the scheme's own tone.
    final primary = isLight ? accent : base.primary;
    final colors = base.copyWith(
      primary: primary,
      onPrimary: _onColor(primary),
      surface: s.card,
      onSurface: s.ink,
      onSurfaceVariant: s.muted,
      surfaceContainerLowest: s.canvas,
      surfaceContainerLow: s.card,
      surfaceContainer: s.card,
      surfaceContainerHigh: s.cardAlt,
      surfaceContainerHighest: s.cardAlt,
      outline: s.muted.withValues(alpha: .5),
      outlineVariant: s.line,
    );
    final titleFamily = library ? AppFonts.serif : AppFonts.display;
    final soft = primary.withValues(alpha: isLight ? .12 : .22);
    const pillShape = StadiumBorder();

    final text = Typography.material2021(platform: TargetPlatform.android).black
        .apply(
          fontFamily: AppFonts.body,
          bodyColor: s.ink,
          displayColor: s.ink,
        );
    TextStyle? title(TextStyle? style, double size, FontWeight weight) =>
        style?.copyWith(
          fontFamily: titleFamily,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: library ? -.2 : -.6,
          height: 1.15,
        );
    final textTheme = text.copyWith(
      displaySmall: title(text.displaySmall, 34, FontWeight.w800),
      headlineLarge: title(text.headlineLarge, 30, FontWeight.w800),
      headlineMedium: title(text.headlineMedium, 26, FontWeight.w700),
      headlineSmall: title(text.headlineSmall, 22, FontWeight.w700),
      titleLarge: title(text.titleLarge, 19, FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      bodySmall: text.bodySmall?.copyWith(color: s.muted),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      fontFamily: AppFonts.body,
      textTheme: textTheme,
      scaffoldBackgroundColor: s.canvas,
      canvasColor: s.canvas,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      extensions: [s, _Accent(accent)],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: s.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: s.ink,
        titleTextStyle: textTheme.headlineSmall,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: s.card,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: s.line.withValues(alpha: isLight ? .9 : .7)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xxs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        selectedColor: s.ink,
        selectedTileColor: soft,
        iconColor: s.muted,
        titleTextStyle: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: textTheme.bodySmall,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: s.ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: pillShape,
          textStyle: const TextStyle(
            fontFamily: AppFonts.body,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: pillShape,
          foregroundColor: s.ink,
          side: BorderSide(color: s.line, width: 1.4),
          textStyle: const TextStyle(
            fontFamily: AppFonts.body,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: pillShape,
          textStyle: const TextStyle(
            fontFamily: AppFonts.body,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: s.cardAlt,
          foregroundColor: s.muted,
          selectedBackgroundColor: s.card,
          selectedForegroundColor: s.ink,
          side: BorderSide(color: s.cardAlt, width: 3),
          textStyle: const TextStyle(
            fontFamily: AppFonts.body,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 4,
        highlightElevation: 6,
        backgroundColor: primary,
        foregroundColor: _onColor(primary),
        extendedTextStyle: const TextStyle(
          fontFamily: AppFonts.body,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.cardAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        hintStyle: TextStyle(color: s.muted),
        prefixIconColor: s.muted,
      ),
      chipTheme: ChipThemeData(
        shape: pillShape,
        side: BorderSide(color: s.line),
        backgroundColor: s.card,
        selectedColor: s.ink,
        checkmarkColor: s.canvas,
        showCheckmark: false,
        labelStyle: TextStyle(
          fontFamily: AppFonts.body,
          fontWeight: FontWeight.w600,
          color: WidgetStateColor.resolveWith(
            (st) => st.contains(WidgetState.selected) ? s.canvas : s.ink,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: s.card,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: s.line,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.card,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: s.card,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: BorderSide(color: s.line),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: s.ink,
        contentTextStyle: TextStyle(
          fontFamily: AppFonts.body,
          fontWeight: FontWeight.w600,
          color: s.canvas,
        ),
        actionTextColor: primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      dividerTheme: DividerThemeData(color: s.line, space: 1, thickness: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: s.cardAlt,
        linearMinHeight: 6,
        circularTrackColor: s.cardAlt,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: const WidgetStatePropertyAll<Color>(
          Colors.transparent,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? _onColor(primary) : null,
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: primary,
        textColor: _onColor(primary),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Black or white, whichever reads best on [color].
  static Color _onColor(Color color) =>
      color.computeLuminance() > .45 ? const Color(0xFF14161C) : Colors.white;
  static Color onColor(Color color) => _onColor(color);
}

/// Remembers the user's raw accent on the theme so the library variant can
/// be derived from the ambient theme.
@immutable
class _Accent extends ThemeExtension<_Accent> {
  const _Accent(this.value);
  final Color value;
  @override
  _Accent copyWith({Color? value}) => _Accent(value ?? this.value);
  @override
  _Accent lerp(_Accent? other, double t) =>
      other == null ? this : _Accent(Color.lerp(value, other.value, t)!);
}

import 'package:flutter/material.dart';
import 'design_tokens.dart';

abstract final class AppTheme {
  static const Color seed = AppColors.brand;
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final colors =
        ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final background =
        isLight ? const Color(0xFFF6F7FF) : const Color(0xFF0F1117);
    final surface = isLight ? Colors.white : const Color(0xFF181B24);
    final fieldFill =
        isLight ? const Color(0xFFEBEDFB) : const Color(0xFF222633);
    final roundedShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md));
    const pillShape = StadiumBorder();

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: background,
      visualDensity: VisualDensity.standard,
      textTheme:
          Typography.material2021(platform: TargetPlatform.android).black.apply(
                bodyColor: colors.onSurface,
                displayColor: colors.onSurface,
              ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.onSurface,
        titleTextStyle: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: colors.onSurface),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: colors.outlineVariant.withOpacity(0.5)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
        shape: roundedShape,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.primary.withOpacity(isLight ? 0.14 : 0.28),
        indicatorShape: pillShape,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: MaterialStateProperty.resolveWith((states) => IconThemeData(
              size: 26,
              color: states.contains(MaterialState.selected)
                  ? colors.primary
                  : colors.onSurfaceVariant,
            )),
        labelTextStyle: MaterialStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(MaterialState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(MaterialState.selected)
                  ? colors.primary
                  : colors.onSurfaceVariant,
            )),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: pillShape,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: pillShape,
        side: BorderSide(color: colors.outlineVariant),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      )),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
        shape: pillShape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      )),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 4,
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        extendedTextStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: roundedShape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            borderSide: BorderSide(color: colors.primary, width: 2)),
        hintStyle: TextStyle(color: colors.onSurfaceVariant),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const MaterialStatePropertyAll<double>(0),
        backgroundColor: MaterialStatePropertyAll<Color>(fieldFill),
        shape: const MaterialStatePropertyAll<OutlinedBorder>(pillShape),
        padding: const MaterialStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: AppSpacing.md)),
      ),
      chipTheme: ChipThemeData(
        shape: pillShape,
        side: BorderSide.none,
        backgroundColor: fieldFill,
        selectedColor: colors.primary.withOpacity(0.18),
        labelStyle:
            TextStyle(fontWeight: FontWeight.w600, color: colors.onSurface),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.inverseSurface,
        contentTextStyle: TextStyle(color: colors.onInverseSurface),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      dividerTheme: DividerThemeData(
          color: colors.outlineVariant.withOpacity(0.6),
          space: 1,
          thickness: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary, linearTrackColor: fieldFill, linearMinHeight: 8,
        // borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      switchTheme: const SwitchThemeData(
          trackOutlineColor:
              MaterialStatePropertyAll<Color>(Colors.transparent)),
    );
  }
}

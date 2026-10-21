import 'package:flutter/material.dart';

/// Espacements basés sur une grille de 4 px.
abstract final class AppSpacing {
  static const double xxs = 4,
      xs = 8,
      sm = 12,
      md = 16,
      lg = 24,
      xl = 32,
      xxl = 48;

  /// Bottom inset that keeps scrollable content clear of the floating dock.
  static const double dockClearance = 120;
}

/// Rayons généreux pour une interface douce et moderne.
abstract final class AppRadius {
  static const double xs = 8, sm = 14, md = 20, lg = 28, pill = 999;
}

abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 260);
  static const Curve curve = Curves.easeOutCubic;
}

/// Embedded font families (see pubspec.yaml).
abstract final class AppFonts {
  /// Body and UI text everywhere.
  static const String body = 'Jakarta';

  /// Titles of the file manager ("Atelier").
  static const String display = 'Bricolage';

  /// Titles of the library ("Salon de lecture").
  static const String serif = 'Fraunces';
}

/// Accent colours the user can pick in Settings.
class AccentPreset {
  const AccentPreset(this.name, this.color);
  final String name;
  final Color color;
}

abstract final class AppAccents {
  static const AccentPreset fallback = AccentPreset(
    'Indigo',
    Color(0xFF4F5BFF),
  );
  static const List<AccentPreset> presets = [
    fallback,
    AccentPreset('Mandarine', Color(0xFFFF6A2B)),
    AccentPreset('Jade', Color(0xFF12A877)),
    AccentPreset('Sakura', Color(0xFFE8508F)),
    AccentPreset('Améthyste', Color(0xFF8A5CF5)),
    AccentPreset('Lagon', Color(0xFF0B9BD8)),
    AccentPreset('Carmin', Color(0xFFE0393E)),
    AccentPreset('Ambre', Color(0xFFE59A0B)),
    AccentPreset('Encre', Color(0xFF2F3340)),
  ];

  static AccentPreset of(Color color) => presets.firstWhere(
    (p) => p.color.toARGB32() == color.toARGB32(),
    orElse: () => AccentPreset('Personnalisée', color),
  );
}

/// The two visual worlds of the app: the cool, crisp file manager and the
/// warm, paper-like library. Exposed on the theme as a [ThemeExtension].
@immutable
class NexaSurfaces extends ThemeExtension<NexaSurfaces> {
  const NexaSurfaces({
    required this.canvas,
    required this.card,
    required this.cardAlt,
    required this.line,
    required this.ink,
    required this.muted,
    required this.library,
  });

  /// Page background.
  final Color canvas;

  /// Raised surfaces (cards, sheets, dock).
  final Color card;

  /// Recessed surfaces (fields, chips, placeholders).
  final Color cardAlt;
  final Color line, ink, muted;

  /// True for the library palette.
  final bool library;

  static NexaSurfaces atelier(Brightness b) => b == Brightness.light
      ? const NexaSurfaces(
          canvas: Color(0xFFF3F4F8),
          card: Color(0xFFFFFFFF),
          cardAlt: Color(0xFFE9EBF1),
          line: Color(0xFFE1E4EC),
          ink: Color(0xFF14161C),
          muted: Color(0xFF6A6F7E),
          library: false,
        )
      : const NexaSurfaces(
          canvas: Color(0xFF0D0E12),
          card: Color(0xFF17191F),
          cardAlt: Color(0xFF21242C),
          line: Color(0xFF2A2D36),
          ink: Color(0xFFF2F3F6),
          muted: Color(0xFF9AA0AE),
          library: false,
        );

  static NexaSurfaces salon(Brightness b) => b == Brightness.light
      ? const NexaSurfaces(
          canvas: Color(0xFFF5EFE5),
          card: Color(0xFFFFFAF2),
          cardAlt: Color(0xFFEBE2D3),
          line: Color(0xFFE2D7C5),
          ink: Color(0xFF221C16),
          muted: Color(0xFF7D7164),
          library: true,
        )
      : const NexaSurfaces(
          canvas: Color(0xFF13100D),
          card: Color(0xFF1E1914),
          cardAlt: Color(0xFF2A241D),
          line: Color(0xFF332C24),
          ink: Color(0xFFF3ECE1),
          muted: Color(0xFFA99C8D),
          library: true,
        );

  @override
  NexaSurfaces copyWith({
    Color? canvas,
    Color? card,
    Color? cardAlt,
    Color? line,
    Color? ink,
    Color? muted,
    bool? library,
  }) => NexaSurfaces(
    canvas: canvas ?? this.canvas,
    card: card ?? this.card,
    cardAlt: cardAlt ?? this.cardAlt,
    line: line ?? this.line,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    library: library ?? this.library,
  );

  @override
  NexaSurfaces lerp(NexaSurfaces? other, double t) {
    if (other == null) return this;
    return NexaSurfaces(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardAlt: Color.lerp(cardAlt, other.cardAlt, t)!,
      line: Color.lerp(line, other.line, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      library: t < .5 ? library : other.library,
    );
  }
}

extension NexaThemeContext on BuildContext {
  NexaSurfaces get surfaces =>
      Theme.of(this).extension<NexaSurfaces>() ??
      NexaSurfaces.atelier(Theme.of(this).brightness);
  Color get accent => Theme.of(this).colorScheme.primary;
}

abstract final class AppColors {
  static const Color folder = Color(0xFFFFB020);
  static const Color image = Color(0xFF00B894);
  static const Color video = Color(0xFFFF6B81);
  static const Color audio = Color(0xFFFF9F1C);
  static const Color pdf = Color(0xFFE5484D);
  static const Color document = Color(0xFF3E8BFF);
  static const Color reading = Color(0xFF8E5CF7);
  static const Color archive = Color(0xFFD6579B);
  static const Color apk = Color(0xFF30B566);
  static const Color other = Color(0xFF7A869A);
}

enum FileCategory {
  folder(Icons.folder_rounded, AppColors.folder),
  image(Icons.image_rounded, AppColors.image),
  video(Icons.play_circle_rounded, AppColors.video),
  audio(Icons.music_note_rounded, AppColors.audio),
  pdf(Icons.picture_as_pdf_rounded, AppColors.pdf),
  document(Icons.description_rounded, AppColors.document),
  reading(Icons.menu_book_rounded, AppColors.reading),
  archive(Icons.folder_zip_rounded, AppColors.archive),
  apk(Icons.android_rounded, AppColors.apk),
  other(Icons.insert_drive_file_rounded, AppColors.other);

  const FileCategory(this.icon, this.color);
  final IconData icon;
  final Color color;

  static FileCategory fromExtension(String? extension) => switch (extension
      ?.toLowerCase()) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' => image,
    'mp4' || 'mkv' || 'mov' || 'avi' || 'webm' || 'm4v' || '3gp' => video,
    'mp3' || 'wav' || 'aac' || 'flac' || 'm4a' || 'ogg' => audio,
    'pdf' => pdf,
    'doc' || 'docx' || 'txt' || 'xls' || 'xlsx' || 'ppt' || 'pptx' => document,
    'epub' || 'mobi' || 'cbz' || 'cbr' || 'cb7' => reading,
    'zip' ||
    'rar' ||
    '7z' ||
    'tar' ||
    'gz' ||
    'tgz' ||
    'bz2' ||
    'tbz2' ||
    'xz' ||
    'txz' => archive,
    'apk' => apk,
    _ => other,
  };

  Color softBackground(Brightness brightness) =>
      color.withValues(alpha: brightness == Brightness.light ? 0.14 : 0.22);
}

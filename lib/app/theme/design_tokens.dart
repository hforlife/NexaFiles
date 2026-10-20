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
}

/// Rayons généreux pour une interface douce et moderne.
abstract final class AppRadius {
  static const double sm = 12, md = 20, lg = 28, pill = 999;
}

abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
  static const Curve curve = Curves.easeOutCubic;
}

abstract final class AppColors {
  static const Color brand = Color(0xFF4F5BFF);
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
    'zip' || 'rar' || '7z' || 'tar' || 'gz' => archive,
    'apk' => apk,
    _ => other,
  };

  Color softBackground(Brightness brightness) =>
      color.withValues(alpha: brightness == Brightness.light ? 0.14 : 0.22);
}

import 'package:flutter/material.dart';
import '../../features/settings/settings_screen.dart';
import 'main_shell.dart';

abstract final class AppRoutes {
  static const files = '/files', settings = '/settings';
}

abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    if (settings.name == AppRoutes.settings) {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const SettingsScreen(),
      );
    }
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => const MainShell(),
    );
  }
}

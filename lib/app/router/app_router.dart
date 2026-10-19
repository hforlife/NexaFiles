import 'package:flutter/material.dart';
import '../../features/settings/settings_screen.dart';
import 'main_shell.dart';

abstract final class AppRoutes {
  static const files = '/files',
      library = '/library',
      recents = '/recents',
      tools = '/tools',
      settings = '/settings';
  static const tabs = [files, library, recents, tools];
}

abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    if (settings.name == AppRoutes.settings)
      return MaterialPageRoute(
          settings: settings, builder: (_) => const SettingsScreen());
    final index = AppRoutes.tabs.indexOf(settings.name ?? '');
    if (index >= 0)
      return MaterialPageRoute(
          settings: settings, builder: (_) => MainShell(initialIndex: index));
    return MaterialPageRoute(
        settings: settings, builder: (_) => const MainShell());
  }
}

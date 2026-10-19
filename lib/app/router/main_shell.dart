import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/files/files_controller.dart';
import '../../features/files/files_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/recents/recents_screen.dart';
import '../../features/tools/tools_screen.dart';
import '../i18n/app_strings.dart';
import 'app_router.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});
  final int initialIndex;
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late int index = widget.initialIndex;
  static const pages = [
    FilesScreen(),
    LibraryScreen(),
    RecentsScreen(),
    ToolsScreen()
  ];
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context),
        titles = [s.files, s.library, s.recents, s.tools];
    return Scaffold(
        appBar: index == 0
            ? null
            : AppBar(title: Text(titles[index]), actions: [
                IconButton(
                    tooltip: s.settings,
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.settings),
                    icon: const Icon(Icons.settings_outlined))
              ]),
        body: IndexedStack(index: index, children: pages),
        bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (value) => setState(() => index = value),
            destinations: [
              NavigationDestination(
                  icon: const Icon(Icons.folder_outlined),
                  selectedIcon: const Icon(Icons.folder),
                  label: s.files),
              NavigationDestination(
                  icon: const Icon(Icons.local_library_outlined),
                  selectedIcon: const Icon(Icons.local_library),
                  label: s.library),
              NavigationDestination(
                  icon: const Icon(Icons.history_outlined),
                  selectedIcon: const Icon(Icons.history),
                  label: s.recents),
              NavigationDestination(
                  icon: const Icon(Icons.build_outlined),
                  selectedIcon: const Icon(Icons.build),
                  label: s.tools)
            ]));
  }
}

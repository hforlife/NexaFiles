import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/files/files_controller.dart';
import '../../features/files/files_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/recents/recents_screen.dart';
import '../../features/tools/tools_screen.dart';
import '../i18n/app_strings.dart';
import 'app_router.dart';
import 'app_tabs.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key});
  static const pages = [
    FilesScreen(),
    LibraryScreen(),
    RecentsScreen(),
    ToolsScreen()
  ];

  /// Single owner of the system back button for every tab: folder navigation
  /// in Files, then back to the Files tab, then leave the app.
  Future<void> _handleBack(BuildContext context, WidgetRef ref) async {
    final tab = ref.read(currentTabProvider);
    if (tab != AppTab.files) {
      ref.read(currentTabProvider.notifier).state = AppTab.files;
      return;
    }
    if (await ref.read(filesControllerProvider.notifier).goBack()) return;
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context),
        titles = [s.files, s.library, s.recents, s.tools],
        tab = ref.watch(currentTabProvider),
        index = tab.index;
    return PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (!didPop) _handleBack(context, ref);
        },
        child: Scaffold(
            appBar: tab == AppTab.files
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
                onDestinationSelected: (value) => ref
                    .read(currentTabProvider.notifier)
                    .state = AppTab.values[value],
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
                ])));
  }
}

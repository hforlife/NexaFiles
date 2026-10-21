import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/files/files_controller.dart';
import '../../features/files/files_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/home/home_link.dart';
import '../../features/operations/operations_ui.dart';
import '../../features/player/audio_player_screen.dart';
import '../../features/recents/recents_screen.dart';
import '../../features/tools/tools_screen.dart';
import '../../shared/widgets/nexa_ui.dart';
import '../i18n/app_strings.dart';
import 'app_router.dart';
import 'app_tabs.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key});
  static const pages = [
    FilesScreen(),
    LibraryScreen(),
    _HeaderedPage(tab: AppTab.recents, child: RecentsScreen()),
    _HeaderedPage(tab: AppTab.tools, child: ToolsScreen()),
  ];

  /// File-manager tabs shown in the dock pill, in order.
  static const _pillTabs = [AppTab.files, AppTab.recents, AppTab.tools];

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
        tab = ref.watch(currentTabProvider),
        // The selection bar of the file manager replaces the dock.
        selecting = ref.watch(
          filesControllerProvider.select((v) => v.selecting),
        );
    void go(AppTab value) =>
        ref.read(currentTabProvider.notifier).state = value;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack(context, ref);
      },
      child: Scaffold(
        extendBody: true,
        body: HomeActionsListener(
          child: OperationsListener(
            child: IndexedStack(index: tab.index, children: pages),
          ),
        ),
        bottomNavigationBar: tab == AppTab.files && selecting
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const OperationsBar(),
                  const MiniPlayer(),
                  NexaDock(
                    destinations: [
                      DockDestination(
                        icon: Icons.folder_outlined,
                        selectedIcon: Icons.folder_rounded,
                        label: s.files,
                      ),
                      DockDestination(
                        icon: Icons.schedule_outlined,
                        selectedIcon: Icons.schedule_rounded,
                        label: s.recents,
                      ),
                      DockDestination(
                        icon: Icons.handyman_outlined,
                        selectedIcon: Icons.handyman_rounded,
                        label: s.tools,
                      ),
                    ],
                    selected: _pillTabs.indexOf(tab),
                    onSelected: (i) => go(_pillTabs[i]),
                    library: DockDestination(
                      icon: Icons.auto_stories_outlined,
                      selectedIcon: Icons.auto_stories_rounded,
                      label: s.library,
                    ),
                    librarySelected: tab == AppTab.library,
                    onLibrary: () => go(AppTab.library),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Recents and Tools: a large title with the settings shortcut.
class _HeaderedPage extends StatelessWidget {
  const _HeaderedPage({required this.tab, required this.child});
  final AppTab tab;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          PageHeader(
            eyebrow: tab == AppTab.recents ? 'Historique' : 'Boîte à outils',
            title: Text(tab == AppTab.recents ? s.recents : s.tools),
            actions: [
              RoundIconButton(
                icon: Icons.settings_outlined,
                tooltip: s.settings,
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.settings),
              ),
            ],
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

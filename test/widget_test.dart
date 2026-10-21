import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexa_file/app/app.dart';
import 'package:nexa_file/app/router/app_tabs.dart';
import 'package:nexa_file/app/router/main_shell.dart';
import 'package:nexa_file/features/library/library_screen.dart';
import 'package:nexa_file/shared/widgets/nexa_ui.dart';
import 'package:nexa_file/core/database/app_database.dart';
import 'package:nexa_file/core/database/database_provider.dart';
import 'package:nexa_file/core/settings/settings_controller.dart';

Future<SettingsController> _pumpApp(
  WidgetTester tester, {
  Future<void> Function(AppDatabase db)? seed,
}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsController.load();
  // Drift relies on real timers: open the database outside the fake clock.
  final database = (await tester.runAsync(() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    await seed?.call(db);
    return db;
  }))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((_) => settings),
        databaseProvider.overrideWithValue(database),
      ],
      child: const NexaFilesApp(),
    ),
  );
  await tester.pump();
  return settings;
}

AppTab _selectedTab(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(MainShell)),
).read(currentTabProvider);

void main() {
  testWidgets('shows NexaFiles navigation', (tester) async {
    await _pumpApp(tester);
    expect(find.text('NexaFiles'), findsOneWidget);
    expect(find.byType(NexaDock), findsOneWidget);
    expect(find.byKey(const ValueKey('dock-library')), findsOneWidget);
  });

  testWidgets('back on another tab returns to Files in the same shell', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('dock-library')));
    await tester.pump();
    expect(_selectedTab(tester), AppTab.library);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(_selectedTab(tester), AppTab.files);
    expect(find.byType(NexaDock), findsOneWidget);
  });

  testWidgets('library shows the resume card, shelves and collection', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      seed: (db) async {
        for (final name in ['One Piece 01.cbz', 'Dune.epub', 'Guide.pdf']) {
          await db.recordRecent(
            id: 'file:///$name',
            uri: 'file:///$name',
            name: name,
            format: name.endsWith('cbz')
                ? 'comic'
                : name.endsWith('epub')
                ? 'epub'
                : 'pdf',
          );
        }
        await db.saveProgress('file:///Dune.epub', '{}', .42);
      },
    );
    await tester.tap(find.byKey(const ValueKey('dock-library')));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Bibliothèque'), findsWidgets);
    expect(find.text('Continuer'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Toute la collection'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(LibraryScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Toute la collection'), findsOneWidget);
    expect(find.text('3 objets'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accent colour is applied to the theme', (tester) async {
    final settings = await _pumpApp(tester);
    const jade = Color(0xFF12A877);
    await settings.setAccent(jade);
    await tester.pump();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.colorScheme.primary, jade);
  });
}

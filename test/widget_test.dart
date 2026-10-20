import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexa_file/app/app.dart';
import 'package:nexa_file/core/database/app_database.dart';
import 'package:nexa_file/core/database/database_provider.dart';
import 'package:nexa_file/core/settings/settings_controller.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsController.load();
  // Drift relies on real timers: open the database outside the fake clock.
  final database = (await tester.runAsync(() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
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
}

int _selectedTab(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

void main() {
  testWidgets('shows NexaFiles navigation', (tester) async {
    await _pumpApp(tester);
    expect(find.text('NexaFiles'), findsOneWidget);
    expect(find.byIcon(Icons.folder), findsOneWidget);
  });

  testWidgets('back on another tab returns to Files in the same shell', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.byIcon(Icons.local_library_outlined));
    await tester.pump();
    expect(_selectedTab(tester), 1);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(_selectedTab(tester), 0);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}

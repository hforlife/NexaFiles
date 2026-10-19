import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexa_file/app/app.dart';
import 'package:nexa_file/core/database/app_database.dart';
import 'package:nexa_file/core/database/database_provider.dart';
import 'package:nexa_file/core/settings/settings_controller.dart';

void main() {
  testWidgets('shows NexaFiles navigation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsController.load();
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(ProviderScope(overrides: [
      settingsProvider.overrideWith((_) => settings),
      databaseProvider.overrideWithValue(database),
    ], child: const NexaFilesApp()));
    await tester.pump();
    expect(find.text('NexaFiles'), findsOneWidget);
    expect(find.byIcon(Icons.folder), findsOneWidget);
  });
}

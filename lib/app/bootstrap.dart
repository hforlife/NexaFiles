import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/settings/settings_controller.dart';
import '../core/database/app_database.dart';
import '../core/database/database_provider.dart';
import 'app.dart';

Future<void> bootstrap() async {
  final settings = await SettingsController.load();
  final database = AppDatabase();
  await database.customSelect('SELECT 1').getSingle();
  runApp(ProviderScope(overrides: [
    settingsProvider.overrideWith((_) => settings),
    databaseProvider.overrideWithValue(database)
  ], child: const NexaFilesApp()));
}

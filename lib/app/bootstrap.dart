import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/settings/settings_controller.dart';
import '../core/database/app_database.dart';
import '../core/database/database_provider.dart';
import 'app.dart';

Future<void> bootstrap() async {
  // Embedded fonts are OFL-licensed: list them with the other licences.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Plus Jakarta Sans',
      'Bricolage Grotesque',
      'Fraunces',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final settings = await SettingsController.load();
  final database = AppDatabase();
  await database.customSelect('SELECT 1').getSingle();
  runApp(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((_) => settings),
        databaseProvider.overrideWithValue(database),
      ],
      child: const NexaFilesApp(),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/app/app_info.dart';
import 'package:nexa_file/app/theme/app_theme.dart';
import 'package:nexa_file/features/settings/about_screen.dart';

void main() {
  testWidgets('about shows the developer and the contact options', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(const Color(0xFF4F5BFF)),
        home: const AboutScreen(),
      ),
    );
    expect(find.text('H Développement'), findsOneWidget);
    await tester.tap(find.text('Contacter le développeur'));
    await tester.pumpAndSettle();
    expect(find.text(AppInfo.email), findsOneWidget);
    expect(find.text('+223 85 49 59 02'), findsOneWidget);
    expect(find.text('+223 68 74 75 04'), findsOneWidget);
    expect(find.byTooltip('WhatsApp'), findsNWidgets(2));
  });
}

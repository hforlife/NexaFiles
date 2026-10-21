import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/shared/widgets/text_prompt.dart';

void main() {
  Future<String?> open(WidgetTester tester, {bool obscure = false}) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showTextPrompt(
              context,
              title: 'Mot de passe',
              obscure: obscure,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'sesame');
    await tester.tap(find.text('Valider'));
    // The closing animation still builds the field: it must stay alive.
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('returns the text and survives the closing animation', (
    tester,
  ) async {
    expect(await open(tester), 'sesame');
    expect(tester.takeException(), isNull);
  });

  testWidgets('password mode can reveal the text', (tester) async {
    expect(await open(tester, obscure: true), 'sesame');
    expect(tester.takeException(), isNull);
  });
}

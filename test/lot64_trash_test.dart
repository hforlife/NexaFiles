import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/core/trash/trash_service.dart';
import 'package:nexa_file/features/tools/trash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('trash metadata survives serialization', () {
    final value = TrashItem(
      id: '1',
      name: 'livre.cbz',
      originalParent: 'content://root/books',
      trashUri: 'content://root/trash/1',
      deletedAt: DateTime.fromMillisecondsSinceEpoch(1234),
      size: 42,
    );
    final restored = TrashItem.fromJson(value.toJson());
    expect(restored.id, value.id);
    expect(restored.name, value.name);
    expect(restored.originalParent, value.originalParent);
    expect(restored.trashUri, value.trashUri);
    expect(restored.deletedAt, value.deletedAt);
    expect(restored.size, value.size);
  });

  testWidgets('emptying the trash reloads the list without error', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: TrashScreen())),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.tap(find.byTooltip('Vider la corbeille'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('La corbeille est vide'), findsOneWidget);
  });
}

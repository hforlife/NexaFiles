import 'package:flutter_test/flutter_test.dart';
import 'package:nexa_file/core/trash/trash_service.dart';

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
}

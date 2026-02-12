import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/constants/firestore_constants.dart';
import 'package:smd_inv/models/board.dart';

void main() {
  group('Board model canonical schema', () {
    test(
      'reads selected_component_ref from required_attributes only',
      () async {
        final db = FakeFirebaseFirestore();
        final boardRef = db
            .collection(FirestoreCollections.boards)
            .doc('board-1');

        await boardRef.set({
          FirestoreFields.name: 'Test Board',
          FirestoreFields.bom: [
            {
              FirestoreFields.qty: 3,
              FirestoreFields.requiredAttributes: {
                'part_type': 'resistor',
                FirestoreFields.value: '10k',
                'size': '0603',
                FirestoreFields.selectedComponentRef: 'inv-123',
              },
            },
          ],
        });

        final snap = await boardRef.get();
        final board = BoardDoc.fromSnap(snap);
        final line = board.bom.first;

        expect(line.selectedComponentRef, 'inv-123');
        final serialized = line.toMap();
        final attrs = Map<String, dynamic>.from(
          serialized[FirestoreFields.requiredAttributes] as Map,
        );
        expect(attrs[FirestoreFields.selectedComponentRef], 'inv-123');
        expect(
          serialized.containsKey(FirestoreFields.selectedComponentRef),
          false,
        );
      },
    );

    test('respects explicit ignored flag and default designators', () async {
      final db = FakeFirebaseFirestore();
      final boardRef = db
          .collection(FirestoreCollections.boards)
          .doc('board-2');

      await boardRef.set({
        FirestoreFields.name: 'Ignored Test',
        FirestoreFields.bom: [
          {
            FirestoreFields.qty: 1,
            '_ignored': true,
            FirestoreFields.requiredAttributes: {'part_type': 'capacitor'},
          },
        ],
      });

      final snap = await boardRef.get();
      final board = BoardDoc.fromSnap(snap);
      final line = board.bom.first;

      expect(line.ignored, true);
      expect(line.designators, '?');
    });

    test('parses qty from numeric/string schema variants', () async {
      final db = FakeFirebaseFirestore();
      final boardRef = db
          .collection(FirestoreCollections.boards)
          .doc('board-3');

      await boardRef.set({
        FirestoreFields.name: 'Qty Parse',
        FirestoreFields.bom: [
          {
            FirestoreFields.qty: 2.0,
            FirestoreFields.requiredAttributes: {'part_type': 'resistor'},
          },
          {
            FirestoreFields.qty: '7',
            FirestoreFields.requiredAttributes: {'part_type': 'capacitor'},
          },
        ],
      });

      final snap = await boardRef.get();
      final board = BoardDoc.fromSnap(snap);
      expect(board.bom[0].qty, 2);
      expect(board.bom[1].qty, 7);
    });
  });
}

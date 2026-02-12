import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/constants/firestore_constants.dart';
import 'package:smd_inv/models/board.dart';
import 'package:smd_inv/services/board_build_service.dart';

void main() {
  group('BoardBuildService', () {
    late FakeFirebaseFirestore db;
    late BoardBuildService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = BoardBuildService(firestore: db);
    });

    test('makeBoards decrements inventory and writes history', () async {
      final invRef = await db.collection(FirestoreCollections.inventory).add({
        FirestoreFields.partNumber: 'R-10K',
        FirestoreFields.type: 'resistor',
        FirestoreFields.value: '10k',
        FirestoreFields.package: '0603',
        FirestoreFields.qty: 100,
      });

      final board = BoardDoc(
        id: 'board-1',
        name: 'Main',
        bom: [
          BomLine(
            designators: 'R1,R2,R3',
            qty: 3,
            requiredAttributes: {
              'part_type': 'resistor',
              FirestoreFields.value: '10k',
              'size': '0603',
              FirestoreFields.selectedComponentRef: invRef.id,
            },
          ),
        ],
      );

      final result = await service.makeBoards(board: board, quantity: 2);

      final invAfter = await invRef.get();
      expect(invAfter.data()?[FirestoreFields.qty], 94);

      final history =
          await db
              .collection(FirestoreCollections.history)
              .doc(result.historyId)
              .get();
      expect(history.exists, true);
      expect(history.data()?[FirestoreFields.action], 'make_board');
      expect(
        (history.data()?[FirestoreFields.consumedItems] as List).length,
        1,
      );
    });

    test(
      'makeBoards fails on unresolved lines and writes no history',
      () async {
        final board = BoardDoc(
          id: 'board-2',
          name: 'Unresolved',
          bom: [
            BomLine(
              designators: 'R1',
              qty: 1,
              requiredAttributes: {
                'part_type': 'resistor',
                FirestoreFields.value: '10k',
                'size': '0603',
              },
            ),
          ],
        );

        expect(
          () => service.makeBoards(board: board, quantity: 1),
          throwsA(isA<BoardBuildException>()),
        );

        final history = await db.collection(FirestoreCollections.history).get();
        expect(history.docs, isEmpty);
      },
    );

    test('makeBoards fails on ambiguous lines and writes no history', () async {
      await db.collection(FirestoreCollections.inventory).add({
        FirestoreFields.partNumber: 'R-A',
        FirestoreFields.type: 'resistor',
        FirestoreFields.value: '10k',
        FirestoreFields.package: '0603',
        FirestoreFields.qty: 10,
      });
      await db.collection(FirestoreCollections.inventory).add({
        FirestoreFields.partNumber: 'R-B',
        FirestoreFields.type: 'resistor',
        FirestoreFields.value: '10k',
        FirestoreFields.package: '0603',
        FirestoreFields.qty: 10,
      });

      final board = BoardDoc(
        id: 'board-3',
        name: 'Ambiguous',
        bom: [
          BomLine(
            designators: 'R1',
            qty: 1,
            requiredAttributes: {
              'part_type': 'resistor',
              FirestoreFields.value: '10k',
              'size': '0603',
            },
          ),
        ],
      );

      expect(
        () => service.makeBoards(board: board, quantity: 1),
        throwsA(isA<BoardBuildException>()),
      );

      final history = await db.collection(FirestoreCollections.history).get();
      expect(history.docs, isEmpty);
    });

    test(
      'makeBoards fails with insufficient stock and leaves state unchanged',
      () async {
        final invRef = await db.collection(FirestoreCollections.inventory).add({
          FirestoreFields.partNumber: 'U-MCU',
          FirestoreFields.type: 'ic',
          FirestoreFields.value: '',
          FirestoreFields.package: 'QFN',
          FirestoreFields.qty: 1,
        });

        final board = BoardDoc(
          id: 'board-4',
          name: 'LowStock',
          bom: [
            BomLine(
              designators: 'U1,U2',
              qty: 2,
              requiredAttributes: {
                'part_type': 'ic',
                FirestoreFields.partNumber: 'U-MCU',
                FirestoreFields.selectedComponentRef: invRef.id,
              },
            ),
          ],
        );

        expect(
          () => service.makeBoards(board: board, quantity: 1),
          throwsA(isA<BoardBuildException>()),
        );

        final invAfter = await invRef.get();
        expect(invAfter.data()?[FirestoreFields.qty], 1);
        final history = await db.collection(FirestoreCollections.history).get();
        expect(history.docs, isEmpty);
      },
    );

    test(
      'makeBoards resolves ambiguous candidates when selected ref is valid',
      () async {
        final chosen = await db.collection(FirestoreCollections.inventory).add({
          FirestoreFields.partNumber: 'R-SEL',
          FirestoreFields.type: 'resistor',
          FirestoreFields.value: '10k',
          FirestoreFields.package: '0603',
          FirestoreFields.qty: 2,
        });
        await db.collection(FirestoreCollections.inventory).add({
          FirestoreFields.partNumber: 'R-OTHER',
          FirestoreFields.type: 'resistor',
          FirestoreFields.value: '10k',
          FirestoreFields.package: '0603',
          FirestoreFields.qty: 50,
        });

        final board = BoardDoc(
          id: 'board-selected',
          name: 'Selected',
          bom: [
            BomLine(
              designators: 'R1',
              qty: 1,
              requiredAttributes: {
                'part_type': 'resistor',
                FirestoreFields.value: '10k',
                'size': '0603',
                FirestoreFields.selectedComponentRef: chosen.id,
              },
            ),
          ],
        );

        final result = await service.makeBoards(board: board, quantity: 2);

        expect(result.consumedByDocId, {chosen.id: 2});
        final chosenAfter = await chosen.get();
        expect(chosenAfter.data()?[FirestoreFields.qty], 0);
      },
    );

    test(
      'makeBoards truncates long unresolved lists in error message',
      () async {
        final board = BoardDoc(
          id: 'board-many',
          name: 'Many',
          bom: List.generate(
            6,
            (i) => BomLine(
              designators: 'U$i',
              qty: 1,
              requiredAttributes: {
                'part_type': 'ic',
                FirestoreFields.partNumber: 'MISS-$i',
              },
            ),
          ),
        );

        await expectLater(
          () => service.makeBoards(board: board, quantity: 1),
          throwsA(
            isA<BoardBuildException>().having(
              (e) => e.message,
              'message',
              contains('+1 more'),
            ),
          ),
        );
      },
    );

    test(
      'undoMakeHistory restores inventory and marks history as undone',
      () async {
        final invRef = await db.collection(FirestoreCollections.inventory).add({
          FirestoreFields.partNumber: 'C-100N',
          FirestoreFields.type: 'capacitor',
          FirestoreFields.value: '100n',
          FirestoreFields.package: '0603',
          FirestoreFields.qty: 30,
        });

        final board = BoardDoc(
          id: 'board-5',
          name: 'Undoable',
          bom: [
            BomLine(
              designators: 'C1,C2',
              qty: 2,
              requiredAttributes: {
                'part_type': 'capacitor',
                FirestoreFields.value: '100n',
                'size': '0603',
                FirestoreFields.selectedComponentRef: invRef.id,
              },
            ),
          ],
        );

        final outcome = await service.makeBoards(board: board, quantity: 3);

        final afterMake = await invRef.get();
        expect(afterMake.data()?[FirestoreFields.qty], 24);

        await service.undoMakeHistory(outcome.historyId);

        final afterUndo = await invRef.get();
        expect(afterUndo.data()?[FirestoreFields.qty], 30);

        final history =
            await db
                .collection(FirestoreCollections.history)
                .doc(outcome.historyId)
                .get();
        expect(history.data()?[FirestoreFields.undoneAt], isNotNull);
      },
    );

    test(
      'undoMakeHistory falls back to exact part_# when doc_id is missing',
      () async {
        await db.collection(FirestoreCollections.inventory).doc('new-id').set({
          FirestoreFields.partNumber: 'R-10K',
          FirestoreFields.type: 'resistor',
          FirestoreFields.value: '10k',
          FirestoreFields.package: '0603',
          FirestoreFields.qty: 5,
        });

        final historyRef = await db
            .collection(FirestoreCollections.history)
            .add({
              FirestoreFields.action: 'make_board',
              FirestoreFields.boardName: 'Fallback',
              FirestoreFields.quantity: 1,
              FirestoreFields.timestamp: Timestamp.now(),
              FirestoreFields.consumedItems: [
                {
                  FirestoreFields.docId: 'missing-id',
                  FirestoreFields.partNumber: 'R-10K',
                  FirestoreFields.quantity: 3,
                },
              ],
            });

        await service.undoMakeHistory(historyRef.id);

        final inv =
            await db
                .collection(FirestoreCollections.inventory)
                .doc('new-id')
                .get();
        expect(inv.data()?[FirestoreFields.qty], 8);
      },
    );

    test(
      'undoMakeHistory recreates inventory row when no match exists',
      () async {
        final historyRef = await db
            .collection(FirestoreCollections.history)
            .add({
              FirestoreFields.action: 'make_board',
              FirestoreFields.boardName: 'Recreate',
              FirestoreFields.quantity: 1,
              FirestoreFields.timestamp: Timestamp.now(),
              FirestoreFields.consumedItems: [
                {
                  FirestoreFields.docId: 'restore-this-id',
                  FirestoreFields.partNumber: 'C-1U',
                  FirestoreFields.type: 'capacitor',
                  FirestoreFields.value: '1u',
                  FirestoreFields.package: '0603',
                  FirestoreFields.quantity: 4,
                },
              ],
            });

        await service.undoMakeHistory(historyRef.id);

        final restored =
            await db
                .collection(FirestoreCollections.inventory)
                .doc('restore-this-id')
                .get();
        expect(restored.exists, true);
        expect(restored.data()?[FirestoreFields.partNumber], 'C-1U');
        expect(restored.data()?[FirestoreFields.qty], 4);
      },
    );

    test(
      'undoMakeHistory recreates with generated id and parses string price',
      () async {
        final historyRef = await db
            .collection(FirestoreCollections.history)
            .add({
              FirestoreFields.action: 'make_board',
              FirestoreFields.boardName: 'Generated',
              FirestoreFields.quantity: 1,
              FirestoreFields.timestamp: Timestamp.now(),
              FirestoreFields.consumedItems: [
                {
                  FirestoreFields.docId: '',
                  FirestoreFields.partNumber: 'IC-RESTORE',
                  FirestoreFields.type: 'ic',
                  FirestoreFields.package: 'QFN',
                  FirestoreFields.pricePerUnit: '1.25',
                  FirestoreFields.quantity: 2,
                },
              ],
            });

        await service.undoMakeHistory(historyRef.id);

        final restored =
            await db
                .collection(FirestoreCollections.inventory)
                .where(FirestoreFields.partNumber, isEqualTo: 'IC-RESTORE')
                .get();
        expect(restored.docs, hasLength(1));
        expect(restored.docs.first.data()[FirestoreFields.qty], 2);
        expect(restored.docs.first.data()[FirestoreFields.pricePerUnit], 1.25);
      },
    );
  });
}

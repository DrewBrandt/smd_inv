import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/constants/firestore_constants.dart';
import 'package:smd_inv/models/board.dart';
import 'package:smd_inv/services/readiness_calculator.dart';

void main() {
  group('ReadinessCalculator', () {
    late FakeFirebaseFirestore db;

    setUp(() {
      db = FakeFirebaseFirestore();
    });

    test('returns zero readiness for empty BOM', () async {
      final board = BoardDoc(id: 'b1', name: 'Empty', bom: const []);
      final readiness = await ReadinessCalculator.calculate(board);

      expect(readiness.buildableQty, 0);
      expect(readiness.readyPct, 0);
      expect(readiness.shortfalls, isEmpty);
      expect(readiness.totalCost, 0);
    });

    test('returns fully ready when all BOM lines are ignored', () async {
      final board = BoardDoc(
        id: 'b2',
        name: 'Ignored',
        bom: [
          BomLine(
            designators: 'R1',
            qty: 1,
            ignored: true,
            requiredAttributes: {
              'part_type': 'resistor',
              FirestoreFields.value: '10k',
              'size': '0603',
            },
          ),
        ],
      );

      final inventory =
          await db.collection(FirestoreCollections.inventory).get();
      final readiness = await ReadinessCalculator.calculate(
        board,
        inventorySnapshot: inventory,
      );
      expect(readiness.buildableQty, 0);
      expect(readiness.readyPct, 1.0);
      expect(readiness.shortfalls, isEmpty);
      expect(readiness.totalCost, 0);
    });

    test('reports shortfall when part is missing from inventory', () async {
      final board = BoardDoc(
        id: 'b3',
        name: 'Missing',
        bom: [
          BomLine(
            designators: 'U1',
            qty: 1,
            requiredAttributes: {
              'part_type': 'ic',
              FirestoreFields.partNumber: 'U-NOT-FOUND',
            },
          ),
        ],
      );

      final inventory =
          await db.collection(FirestoreCollections.inventory).get();
      final readiness = await ReadinessCalculator.calculate(
        board,
        inventorySnapshot: inventory,
      );

      expect(readiness.buildableQty, 0);
      expect(readiness.readyPct, 0);
      expect(readiness.shortfalls, hasLength(1));
      expect(readiness.shortfalls.single.qty, 1);
    });

    test(
      'computes buildable quantity and total cost from matched items',
      () async {
        final rDoc = await db.collection(FirestoreCollections.inventory).add({
          FirestoreFields.type: 'resistor',
          FirestoreFields.value: '10k',
          FirestoreFields.package: '0603',
          FirestoreFields.qty: 10,
          FirestoreFields.pricePerUnit: 0.1,
        });
        final cDoc = await db.collection(FirestoreCollections.inventory).add({
          FirestoreFields.type: 'capacitor',
          FirestoreFields.value: '100n',
          FirestoreFields.package: '0603',
          FirestoreFields.qty: 12,
          FirestoreFields.pricePerUnit: 0.2,
        });

        final board = BoardDoc(
          id: 'b4',
          name: 'Buildable',
          bom: [
            BomLine(
              designators: 'R1,R2',
              qty: 2,
              requiredAttributes: {
                'part_type': 'resistor',
                FirestoreFields.value: '10k',
                'size': '0603',
                FirestoreFields.selectedComponentRef: rDoc.id,
              },
            ),
            BomLine(
              designators: 'C1,C2,C3,C4,C5',
              qty: 5,
              requiredAttributes: {
                'part_type': 'capacitor',
                FirestoreFields.value: '100n',
                'size': '0603',
                FirestoreFields.selectedComponentRef: cDoc.id,
              },
            ),
          ],
        );

        final inventory =
            await db.collection(FirestoreCollections.inventory).get();
        final readiness = await ReadinessCalculator.calculate(
          board,
          inventorySnapshot: inventory,
        );

        expect(readiness.buildableQty, 2);
        expect(readiness.readyPct, 1.0);
        expect(readiness.shortfalls, isEmpty);
        expect(readiness.totalCost, closeTo(1.2, 0.0001));
      },
    );

    test('shortfall quantity uses required minus available', () async {
      final doc = await db.collection(FirestoreCollections.inventory).add({
        FirestoreFields.type: 'ic',
        FirestoreFields.partNumber: 'U-MCU',
        FirestoreFields.qty: 1,
      });

      final board = BoardDoc(
        id: 'b5',
        name: 'Insufficient',
        bom: [
          BomLine(
            designators: 'U1,U2,U3',
            qty: 3,
            requiredAttributes: {
              'part_type': 'ic',
              FirestoreFields.partNumber: 'U-MCU',
              FirestoreFields.selectedComponentRef: doc.id,
            },
          ),
        ],
      );

      final inventory =
          await db.collection(FirestoreCollections.inventory).get();
      final readiness = await ReadinessCalculator.calculate(
        board,
        inventorySnapshot: inventory,
      );

      expect(readiness.buildableQty, 0);
      expect(readiness.readyPct, 0);
      expect(readiness.shortfalls, hasLength(1));
      expect(readiness.shortfalls.single.qty, 2);
    });
  });
}

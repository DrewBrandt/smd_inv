import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/constants/firestore_constants.dart';
import 'package:smd_inv/models/board.dart';
import 'package:smd_inv/models/procurement.dart';
import 'package:smd_inv/services/procurement_planner_service.dart';

void main() {
  group('ProcurementPlannerService', () {
    late FakeFirebaseFirestore db;
    late ProcurementPlannerService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = ProcurementPlannerService(firestore: db);
    });

    test('buildPlan aggregates shortages from board cart quantities', () async {
      final resistorRef = await db.collection(FirestoreCollections.inventory).add({
        FirestoreFields.partNumber: 'R-10K-0603',
        FirestoreFields.type: 'resistor',
        FirestoreFields.value: '10k',
        FirestoreFields.package: '0603',
        FirestoreFields.qty: 10,
        FirestoreFields.vendorLink:
            'https://www.digikey.com/en/products/detail/yageo/RC0603FR-0710KL/726688',
      });
      final capRef = await db.collection(FirestoreCollections.inventory).add({
        FirestoreFields.partNumber: 'CL10A106',
        FirestoreFields.type: 'capacitor',
        FirestoreFields.value: '10u',
        FirestoreFields.package: '0603',
        FirestoreFields.qty: 4,
      });

      final board = BoardDoc(
        id: 'b-main',
        name: 'Main',
        bom: [
          BomLine(
            designators: 'R1,R2',
            qty: 2,
            requiredAttributes: {
              FirestoreFields.selectedComponentRef: resistorRef.id,
              'part_type': 'resistor',
            },
          ),
          BomLine(
            designators: 'C1,C2,C3',
            qty: 3,
            requiredAttributes: {
              FirestoreFields.selectedComponentRef: capRef.id,
              'part_type': 'capacitor',
            },
          ),
        ],
      );

      final plan = await service.buildPlan(
        boardOrders: [BoardOrderRequest(board: board, quantity: 3)],
      );

      expect(plan.issues, isEmpty);
      expect(plan.lines, hasLength(2));
      expect(plan.totalRequiredQty, 15);
      expect(plan.totalShortageQty, 5);

      final resistor = plan.lines.firstWhere(
        (l) => l.inventoryDocId == resistorRef.id,
      );
      final cap = plan.lines.firstWhere((l) => l.inventoryDocId == capRef.id);
      expect(resistor.requiredQty, 6);
      expect(resistor.shortageQty, 0);
      expect(cap.requiredQty, 9);
      expect(cap.shortageQty, 5);

      expect(plan.orderableLines, hasLength(1));
      expect(plan.exportableLines, hasLength(1));
    });

    test('buildPlan emits unresolved issue and fallback order line', () async {
      final boardA = BoardDoc(
        id: 'b-a',
        name: 'A',
        bom: [
          BomLine(
            designators: 'U1',
            qty: 1,
            requiredAttributes: {
              FirestoreFields.partNumber: 'TPS63020',
              'part_type': 'ic',
            },
          ),
        ],
      );
      final boardB = BoardDoc(
        id: 'b-b',
        name: 'B',
        bom: [
          BomLine(
            designators: 'U1',
            qty: 1,
            requiredAttributes: {
              FirestoreFields.partNumber: 'TPS63020',
              'part_type': 'ic',
            },
          ),
        ],
      );

      final plan = await service.buildPlan(
        boardOrders: [
          BoardOrderRequest(board: boardA, quantity: 1),
          BoardOrderRequest(board: boardB, quantity: 2),
        ],
      );

      expect(plan.unresolvedCount, 1);
      final issue = plan.issues.single;
      expect(issue.requiredQty, 3);
      expect(issue.boardNames, containsAll(['A', 'B']));

      expect(plan.lines, hasLength(1));
      final line = plan.lines.single;
      expect(line.source, ProcurementLineSource.bomFallback);
      expect(line.partNumber, 'TPS63020');
      expect(line.shortageQty, 3);
    });

    test('buildPlan emits ambiguous issue without auto-selecting', () async {
      await db.collection(FirestoreCollections.inventory).add({
        FirestoreFields.partNumber: 'R-A',
        FirestoreFields.type: 'resistor',
        FirestoreFields.value: '10k',
        FirestoreFields.package: '0603',
        FirestoreFields.qty: 100,
      });
      await db.collection(FirestoreCollections.inventory).add({
        FirestoreFields.partNumber: 'R-B',
        FirestoreFields.type: 'resistor',
        FirestoreFields.value: '10k',
        FirestoreFields.package: '0603',
        FirestoreFields.qty: 100,
      });

      final board = BoardDoc(
        id: 'b-amb',
        name: 'Ambiguous Board',
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

      final plan = await service.buildPlan(
        boardOrders: [BoardOrderRequest(board: board, quantity: 1)],
      );

      expect(plan.ambiguousCount, 1);
      expect(plan.lines, isEmpty);
    });

    test(
      'buildPlan resolves ambiguous matches when selected_component_ref is valid',
      () async {
        final selected = await db.collection(FirestoreCollections.inventory).add({
          FirestoreFields.partNumber: 'IC-A',
          FirestoreFields.type: 'ic',
          FirestoreFields.value: 'LMV321',
          FirestoreFields.package: 'SOT-23-5',
          FirestoreFields.qty: 1,
        });
        await db.collection(FirestoreCollections.inventory).add({
          FirestoreFields.partNumber: 'IC-B',
          FirestoreFields.type: 'ic',
          FirestoreFields.value: 'LMV321',
          FirestoreFields.package: 'SOT-23-5',
          FirestoreFields.qty: 50,
        });

        final board = BoardDoc(
          id: 'b-selected',
          name: 'Selected Ref Board',
          bom: [
            BomLine(
              designators: 'U1',
              qty: 2,
              requiredAttributes: {
                'part_type': 'ic',
                FirestoreFields.value: 'LMV321',
                'size': 'SOT-23-5',
                FirestoreFields.selectedComponentRef: selected.id,
              },
            ),
          ],
        );

        final plan = await service.buildPlan(
          boardOrders: [BoardOrderRequest(board: board, quantity: 2)],
        );

        expect(plan.ambiguousCount, 0);
        expect(plan.lines, hasLength(1));
        expect(plan.lines.single.inventoryDocId, selected.id);
        expect(plan.lines.single.requiredQty, 4);
        expect(plan.lines.single.shortageQty, 3);
      },
    );

    test('buildPlan sorts issues and lines deterministically on ties', () async {
      await db.collection(FirestoreCollections.inventory).add({
        FirestoreFields.partNumber: 'ZZ-TIE',
        FirestoreFields.type: 'ic',
        FirestoreFields.value: 'V1',
        FirestoreFields.package: 'QFN',
        FirestoreFields.qty: 0,
      });
      await db.collection(FirestoreCollections.inventory).add({
        FirestoreFields.partNumber: 'AA-TIE',
        FirestoreFields.type: 'ic',
        FirestoreFields.value: 'V2',
        FirestoreFields.package: 'QFN',
        FirestoreFields.qty: 0,
      });

      final boardA = BoardDoc(
        id: 'b1',
        name: 'Board A',
        bom: [
          BomLine(
            designators: 'U1',
            qty: 1,
            requiredAttributes: {
              FirestoreFields.partNumber: 'ZZ-TIE',
              'part_type': 'ic',
            },
          ),
          BomLine(
            designators: 'U2',
            qty: 1,
            requiredAttributes: {
              FirestoreFields.partNumber: 'AA-TIE',
              'part_type': 'ic',
            },
          ),
          BomLine(
            designators: 'X1',
            qty: 1,
            requiredAttributes: {'part_type': 'ic', FirestoreFields.partNumber: 'MISS-B'},
          ),
        ],
      );
      final boardB = BoardDoc(
        id: 'b2',
        name: 'Board B',
        bom: [
          BomLine(
            designators: 'X2',
            qty: 1,
            requiredAttributes: {'part_type': 'ic', FirestoreFields.partNumber: 'MISS-A'},
          ),
        ],
      );

      final plan = await service.buildPlan(
        boardOrders: [
          BoardOrderRequest(board: boardA, quantity: 1),
          BoardOrderRequest(board: boardB, quantity: 1),
        ],
      );

      expect(plan.lines, hasLength(4));
      expect(plan.lines[0].partNumber, 'AA-TIE');
      expect(plan.lines[1].partNumber, 'ZZ-TIE');
      expect(plan.lines[2].source, ProcurementLineSource.bomFallback);
      expect(plan.lines[3].source, ProcurementLineSource.bomFallback);
      expect(plan.lines[2].partNumber, 'MISS-A');
      expect(plan.lines[3].partNumber, 'MISS-B');

      expect(plan.issues, hasLength(2));
      expect(plan.issues[0].partLabel, 'MISS-A');
      expect(plan.issues[1].partLabel, 'MISS-B');
    });

    test('buildPlan fallback description uses part type/value/package when part number missing', () async {
      final board = BoardDoc(
        id: 'b-fallback-desc',
        name: 'Fallback Desc',
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
          BomLine(
            designators: 'U9',
            qty: 1,
            requiredAttributes: const {},
          ),
        ],
      );

      final plan = await service.buildPlan(
        boardOrders: [BoardOrderRequest(board: board, quantity: 1)],
      );

      expect(plan.lines, hasLength(2));
      final resistorFallback = plan.lines.firstWhere(
        (l) => l.partType == 'resistor',
      );
      expect(resistorFallback.description, 'resistor 10k 0603');

      final unmapped = plan.lines.firstWhere((l) => l.partType.isEmpty);
      expect(unmapped.description, 'Unmapped BOM part');
    });

    test('extractDigiKeyPartNumber parses DigiKey URLs and fallback', () {
      expect(
        ProcurementPlannerService.extractDigiKeyPartNumber(
          'https://www.digikey.com/en/products/detail/tdk-corporation/C1005X7R1E104K050BB/395948',
          fallbackPartNumber: 'CL10B104KB8NNNC',
        ),
        isNull,
      );

      expect(
        ProcurementPlannerService.extractDigiKeyPartNumber(
          'https://www.digikey.com/en/products/detail/abc/ABC-123-ND/12345',
        ),
        'ABC-123-ND',
      );

      expect(
        ProcurementPlannerService.extractDigiKeyPartNumber(
          'https://example.com/item',
          fallbackPartNumber: '493-15115-1-ND',
        ),
        '493-15115-1-ND',
      );
    });

    test('mergeManualLines appends ad-hoc lines and includes in exports', () {
      const base = ProcurementPlan(lines: [], issues: []);
      final merged = ProcurementPlannerService.mergeManualLines(base, const [
        ManualProcurementLine(
          partNumber: 'STM32F303CBT6',
          digikeyPartNumber: null,
          description: 'MCU spare',
          quantity: 3,
          vendorLink:
              'https://www.digikey.com/en/products/detail/stmicroelectronics/497-15115-1-ND/10106708',
        ),
        ManualProcurementLine(
          partNumber: 'CUSTOM-REG',
          digikeyPartNumber: '296-12345-1-ND',
          description: 'Regulator buffer',
          quantity: 5,
        ),
      ]);

      expect(merged.lines, hasLength(2));
      expect(
        merged.lines.every(
          (line) => line.source == ProcurementLineSource.manual,
        ),
        isTrue,
      );
      expect(merged.totalShortageQty, 8);
      expect(merged.exportableLines, hasLength(2));

      final csv = merged.toDigiKeyCsv();
      expect(csv, contains('296-12345-1-ND'));
      expect(csv, contains('497-15115-1-ND'));

      final quick = merged.toQuickOrderText();
      expect(quick, contains('296-12345-1-ND,5'));
      expect(quick, contains('497-15115-1-ND,3'));
    });

    test('mergeManualLines sorts equal shortages by source then part number', () {
      const base = ProcurementPlan(
        lines: [
          ProcurementLine(
            source: ProcurementLineSource.inventory,
            inventoryDocId: 'x',
            partNumber: 'ZZZ',
            digikeyPartNumber: 'ZZZ-1-ND',
            partType: 'ic',
            package: '',
            description: 'inv',
            requiredQty: 2,
            inStockQty: 0,
            shortageQty: 2,
            unitPrice: null,
            vendorLink: null,
            boardNames: ['B'],
          ),
        ],
        issues: [],
      );
      final merged = ProcurementPlannerService.mergeManualLines(base, const [
        ManualProcurementLine(
          partNumber: 'AAA',
          digikeyPartNumber: 'AAA-1-ND',
          description: 'manual',
          quantity: 2,
        ),
      ]);

      expect(merged.lines, hasLength(2));
      expect(merged.lines[0].source, ProcurementLineSource.inventory);
      expect(merged.lines[1].source, ProcurementLineSource.manual);
    });
  });
}

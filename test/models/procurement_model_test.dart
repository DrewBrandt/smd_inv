import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/models/procurement.dart';

void main() {
  group('ProcurementPlan', () {
    test('orderable/exportable filtering and totals', () {
      const plan = ProcurementPlan(
        lines: [
          ProcurementLine(
            source: ProcurementLineSource.inventory,
            inventoryDocId: 'a',
            partNumber: 'R-10K',
            digikeyPartNumber: null,
            partType: 'resistor',
            package: '0603',
            description: '10k resistor',
            requiredQty: 20,
            inStockQty: 5,
            shortageQty: 15,
            unitPrice: 0.01,
            vendorLink: null,
            boardNames: ['BoardA'],
          ),
          ProcurementLine(
            source: ProcurementLineSource.inventory,
            inventoryDocId: 'b',
            partNumber: '',
            digikeyPartNumber: null,
            partType: 'ic',
            package: 'qfn',
            description: 'No identifier line',
            requiredQty: 4,
            inStockQty: 0,
            shortageQty: 4,
            unitPrice: 1.0,
            vendorLink: null,
            boardNames: ['BoardA'],
          ),
          ProcurementLine(
            source: ProcurementLineSource.inventory,
            inventoryDocId: 'c',
            partNumber: 'C-100N',
            digikeyPartNumber: '399-1234-1-ND',
            partType: 'capacitor',
            package: '0603',
            description: '100n cap',
            requiredQty: 10,
            inStockQty: 10,
            shortageQty: 0,
            unitPrice: 0.02,
            vendorLink: null,
            boardNames: ['BoardB'],
          ),
        ],
        issues: [],
      );

      expect(plan.totalRequiredQty, 34);
      expect(plan.totalShortageQty, 19);
      expect(plan.orderableLines, hasLength(2));
      expect(plan.exportableLines, hasLength(1));
      expect(plan.knownOrderCost, closeTo(4.15, 0.0001));
    });

    test('toDigiKeyCsv includes only exportable shortage lines', () {
      const plan = ProcurementPlan(
        lines: [
          ProcurementLine(
            source: ProcurementLineSource.manual,
            inventoryDocId: null,
            partNumber: 'MPN-1',
            digikeyPartNumber: '111-AAA-ND',
            partType: 'ic',
            package: '',
            description: 'MCU',
            requiredQty: 5,
            inStockQty: 0,
            shortageQty: 5,
            unitPrice: null,
            vendorLink: 'https://www.digikey.com',
            boardNames: ['Manual'],
          ),
          ProcurementLine(
            source: ProcurementLineSource.manual,
            inventoryDocId: null,
            partNumber: '',
            digikeyPartNumber: null,
            partType: 'ic',
            package: '',
            description: 'Missing id',
            requiredQty: 1,
            inStockQty: 0,
            shortageQty: 1,
            unitPrice: null,
            vendorLink: null,
            boardNames: ['Manual'],
          ),
        ],
        issues: [],
      );

      final csv = plan.toDigiKeyCsv();
      expect(csv, contains('111-AAA-ND'));
      expect(csv, isNot(contains('Missing id')));
    });

    test('toQuickOrderText prints part-qty lines', () {
      const plan = ProcurementPlan(
        lines: [
          ProcurementLine(
            source: ProcurementLineSource.manual,
            inventoryDocId: null,
            partNumber: 'MPN-2',
            digikeyPartNumber: null,
            partType: 'ic',
            package: '',
            description: 'MCU',
            requiredQty: 3,
            inStockQty: 0,
            shortageQty: 3,
            unitPrice: null,
            vendorLink: null,
            boardNames: ['Manual'],
          ),
        ],
        issues: [],
      );

      expect(plan.toQuickOrderText(), 'MPN-2,3');
    });
  });

  group('ProcurementIssue/ManualProcurementLine', () {
    test('ProcurementIssue.typeLabel maps enum values', () {
      const unresolved = ProcurementIssue(
        type: ProcurementIssueType.unresolved,
        partLabel: 'U1',
        requiredQty: 1,
        boardNames: ['Main'],
      );
      const ambiguous = ProcurementIssue(
        type: ProcurementIssueType.ambiguous,
        partLabel: 'U2',
        requiredQty: 2,
        boardNames: ['Main'],
      );

      expect(unresolved.typeLabel, 'Unresolved');
      expect(ambiguous.typeLabel, 'Ambiguous');
    });

    test('ManualProcurementLine defaults boardLabel to Manual', () {
      const line = ManualProcurementLine(
        partNumber: 'MPN-9',
        digikeyPartNumber: null,
        description: 'Sensor',
        quantity: 3,
      );

      expect(line.boardLabel, 'Manual');
    });
  });
}

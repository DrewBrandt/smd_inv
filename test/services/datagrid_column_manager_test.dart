import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smd_inv/services/datagrid_column_manager.dart';

void main() {
  group('DataGridColumnManager', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('getMinWidth returns correct minimum widths', () {
      final manager = DataGridColumnManager(
        persistKey: 'test',
        columns: [
          const GridColumnConfig(field: 'qty', label: 'Qty'),
          const GridColumnConfig(field: 'notes', label: 'Notes'),
          const GridColumnConfig(field: 'part_#', label: 'Part #'),
          const GridColumnConfig(field: 'location', label: 'Location'),
          const GridColumnConfig(field: 'unknown', label: 'Unknown'),
        ],
      );

      expect(manager.getMinWidth('qty'), 84);
      expect(manager.getMinWidth('quantity'), 84);
      expect(manager.getMinWidth('count'), 84);
      expect(manager.getMinWidth('notes'), 320);
      expect(manager.getMinWidth('description'), 320);
      expect(manager.getMinWidth('part_#'), 180);
      expect(manager.getMinWidth('location'), 160);
      expect(manager.getMinWidth('unknown'), 140); // default
    });

    test('getMinWidth is case-insensitive', () {
      final manager = DataGridColumnManager(
        persistKey: 'test',
        columns: const [GridColumnConfig(field: 'QTY', label: 'Quantity')],
      );

      expect(manager.getMinWidth('QTY'), 84);
      expect(manager.getMinWidth('qty'), 84);
      expect(manager.getMinWidth('Qty'), 84);
    });

    test('getWeight returns correct expansion weights', () {
      final columns = [
        const GridColumnConfig(field: 'notes', label: 'Notes'),
        const GridColumnConfig(field: 'part_#', label: 'Part #'),
        const GridColumnConfig(field: 'datasheet', label: 'Datasheet'),
        const GridColumnConfig(field: 'other', label: 'Other'),
      ];
      final manager = DataGridColumnManager(persistKey: 'test', columns: columns);

      expect(manager.getWeight(columns[0]), 3.0); // notes
      expect(manager.getWeight(columns[1]), 2.0); // part_#
      expect(manager.getWeight(columns[2]), 0); // datasheet (don't grow)
      expect(manager.getWeight(columns[3]), 1.0); // default
    });

    test('calculateWidths starts with minimum widths', () {
      final columns = [
        const GridColumnConfig(field: 'qty', label: 'Qty'),
        const GridColumnConfig(field: 'notes', label: 'Notes'),
      ];
      final manager = DataGridColumnManager(persistKey: 'test', columns: columns);

      final widths = manager.calculateWidths(const BoxConstraints(maxWidth: double.infinity));

      expect(widths['qty'], 84);
      expect(widths['notes'], 320);
    });

    test('calculateWidths distributes extra space proportionally by weight', () {
      final columns = [
        const GridColumnConfig(field: 'part_#', label: 'Part #'), // weight 2.0, min 180
        const GridColumnConfig(field: 'notes', label: 'Notes'), // weight 3.0, min 320
        const GridColumnConfig(field: 'qty', label: 'Qty'), // weight 1.0, min 84
      ];
      final manager = DataGridColumnManager(persistKey: 'test', columns: columns);

      // Total min = 180 + 320 + 84 = 584
      // Available = 1000
      // Extra = 416
      // Total weight = 2.0 + 3.0 + 1.0 = 6.0
      // part_# gets: 180 + 416 * (2/6) = 180 + 138.67 = 318.67
      // notes gets: 320 + 416 * (3/6) = 320 + 208 = 528
      // qty gets: 84 + 416 * (1/6) = 84 + 69.33 = 153.33

      final widths = manager.calculateWidths(const BoxConstraints(maxWidth: 1000));

      expect(widths['part_#'], closeTo(318.67, 0.1));
      expect(widths['notes'], closeTo(528, 0.1));
      expect(widths['qty'], closeTo(153.33, 0.1));

      // Total should equal maxWidth
      final total = widths.values.fold<double>(0, (a, b) => a + b);
      expect(total, closeTo(1000, 0.1));
    });

    test('calculateWidths respects manually resized columns', () async {
      final columns = [
        const GridColumnConfig(field: 'part_#', label: 'Part #'),
        const GridColumnConfig(field: 'notes', label: 'Notes'),
      ];
      final manager = DataGridColumnManager(persistKey: 'test', columns: columns);

      // Simulate user manually resizing part_# column
      manager.onColumnResizeStart();
      manager.onColumnResizeUpdate('part_#', 300);
      await manager.onColumnResizeEnd();

      final widths = manager.calculateWidths(const BoxConstraints(maxWidth: 1000));

      // part_# should stay at 300 (user preference)
      expect(widths['part_#'], 300);

      // notes should get the remaining space (1000 - 300 = 700)
      expect(widths['notes'], closeTo(700, 0.1));
    });

    test('calculateWidths enforces minimum widths on saved preferences', () async {
      final columns = [
        const GridColumnConfig(field: 'qty', label: 'Qty'), // min 84
        const GridColumnConfig(field: 'notes', label: 'Notes'), // min 320
      ];
      final manager = DataGridColumnManager(persistKey: 'test', columns: columns);

      // Try to set width below minimum
      manager.onColumnResizeStart();
      manager.onColumnResizeUpdate('qty', 50); // Below min of 84
      await manager.onColumnResizeEnd();

      final widths = manager.calculateWidths(const BoxConstraints(maxWidth: 500));

      // qty should be clamped to minimum (84)
      expect(widths['qty'], 84);
      // notes gets the rest
      expect(widths['notes'], 416); // 500 - 84
    });

    test('calculateWidths handles infinite width constraint', () {
      final columns = [
        const GridColumnConfig(field: 'notes', label: 'Notes'),
      ];
      final manager = DataGridColumnManager(persistKey: 'test', columns: columns);

      final widths = manager.calculateWidths(const BoxConstraints(maxWidth: double.infinity));

      // Should just return minimum width
      expect(widths['notes'], 320);
    });

    test('calculateWidths gives extra space to last column when no growable columns', () async {
      final columns = [
        const GridColumnConfig(field: 'datasheet', label: 'Datasheet'), // weight 0
        const GridColumnConfig(field: 'qty', label: 'Qty'), // weight 1.0
      ];
      final manager = DataGridColumnManager(persistKey: 'test', columns: columns);

      // Mark both as manually resized (so they won't grow)
      manager.onColumnResizeStart();
      manager.onColumnResizeUpdate('datasheet', 220);
      manager.onColumnResizeUpdate('qty', 84);
      await manager.onColumnResizeEnd();

      // Total = 220 + 84 = 304
      // Extra = 600 - 304 = 296
      // Should go to last column (qty)
      final widths = manager.calculateWidths(const BoxConstraints(maxWidth: 600));

      expect(widths['datasheet'], 220);
      expect(widths['qty'], closeTo(380, 0.1)); // 84 + 296
    });

    test('loadSavedWidths and saveWidths persist preferences', () async {
      final columns = [
        const GridColumnConfig(field: 'part_#', label: 'Part #'),
        const GridColumnConfig(field: 'notes', label: 'Notes'),
      ];
      final manager = DataGridColumnManager(persistKey: 'test_persist', columns: columns);

      // Simulate user resize
      manager.onColumnResizeStart();
      manager.onColumnResizeUpdate('part_#', 250);
      await manager.onColumnResizeEnd();

      // Create new manager with same key
      final manager2 = DataGridColumnManager(persistKey: 'test_persist', columns: columns);
      await manager2.loadSavedWidths();

      final widths = manager2.calculateWidths(const BoxConstraints(maxWidth: 1000));
      expect(widths['part_#'], 250); // Saved width
      expect(widths['notes'], 750); // Gets remaining space
    });

    test('clearSavedWidths removes all preferences', () async {
      final columns = [
        const GridColumnConfig(field: 'notes', label: 'Notes'),
      ];
      final manager = DataGridColumnManager(persistKey: 'test_clear', columns: columns);

      // Save a width
      manager.onColumnResizeStart();
      manager.onColumnResizeUpdate('notes', 500);
      await manager.onColumnResizeEnd();

      // Clear
      await manager.clearSavedWidths();

      // Create new manager
      final manager2 = DataGridColumnManager(persistKey: 'test_clear', columns: columns);
      await manager2.loadSavedWidths();

      final widths = manager2.calculateWidths(const BoxConstraints(maxWidth: 1000));

      // Should use default minimum + expansion
      expect(widths['notes'], 1000); // All available space
    });

    test('isResizing prevents width redistribution during resize', () async {
      final columns = [
        const GridColumnConfig(field: 'part_#', label: 'Part #'),
        const GridColumnConfig(field: 'notes', label: 'Notes'),
      ];
      final manager = DataGridColumnManager(persistKey: 'test', columns: columns);

      manager.onColumnResizeStart();
      manager.onColumnResizeUpdate('part_#', 300);

      // While resizing, should not redistribute extra space
      final widthsDuringResize = manager.calculateWidths(const BoxConstraints(maxWidth: 1000));

      // Just returns minimum + user widths, no redistribution
      expect(widthsDuringResize['part_#'], 300);
      expect(widthsDuringResize['notes'], 320); // Just minimum

      await manager.onColumnResizeEnd();

      // After resize ends, redistribution should work
      final widthsAfterResize = manager.calculateWidths(const BoxConstraints(maxWidth: 1000));
      expect(widthsAfterResize['part_#'], 300);
      expect(widthsAfterResize['notes'], closeTo(700, 0.1)); // Gets remaining space
    });

    test('handles columns with custom minWidth in config', () {
      final columns = [
        const GridColumnConfig(field: 'custom', label: 'Custom', minWidth: 200),
        const GridColumnConfig(field: 'other', label: 'Other'),
      ];
      final manager = DataGridColumnManager(persistKey: 'test', columns: columns);

      // Should still use the built-in minimum width logic
      // (GridColumnConfig.minWidth is not currently used by manager)
      // Both columns get weight 1.0, so they split the extra space evenly
      // min = 140 + 140 = 280, extra = 220, each gets 110 extra
      final widths = manager.calculateWidths(const BoxConstraints(maxWidth: 500));
      expect(widths['custom'], closeTo(250, 1)); // 140 + 110
      expect(widths['other'], closeTo(250, 1)); // 140 + 110
    });
  });
}

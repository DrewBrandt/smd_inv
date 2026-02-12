import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smd_inv/data/firebase_datagrid_source.dart';
import 'package:smd_inv/data/inventory_repo.dart';
import 'package:smd_inv/data/list_map_source.dart';
import 'package:smd_inv/models/columns.dart';
import 'package:smd_inv/widgets/unified_data_grid.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

class _ErrorInventoryRepo extends InventoryRepo {
  _ErrorInventoryRepo() : super(firestore: FakeFirebaseFirestore());

  @override
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> streamFiltered({
    List<String>? typeFilter,
    List<String>? packageFilter,
    List<String>? locationFilter,
  }) => Stream.error('inventory stream failed');

  @override
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> streamCollection(
    String collectionName,
  ) => Stream.error('collection stream failed');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  List<ColumnSpec> makeColumns() => [
    ColumnSpec(field: 'part_#', label: 'Part #'),
    ColumnSpec(field: 'qty', label: 'Qty', kind: CellKind.integer),
  ];

  test('constructor asserts when data source is not uniquely provided', () {
    expect(() => UnifiedDataGrid(columns: makeColumns()), throwsAssertionError);

    expect(
      () => UnifiedDataGrid(
        columns: makeColumns(),
        collection: 'inventory',
        rows: const [],
      ),
      throwsAssertionError,
    );
  });

  test('factory constructors wire collection and inventory sources', () {
    final collectionGrid = UnifiedDataGrid.collection(
      collection: 'inventory',
      columns: makeColumns(),
    );
    final inventoryGrid = UnifiedDataGrid.inventory(columns: makeColumns());

    expect(collectionGrid.collection, 'inventory');
    expect(collectionGrid.useInventoryStream, isFalse);
    expect(inventoryGrid.useInventoryStream, isTrue);
    expect(inventoryGrid.persistKey, 'inventory_unified');
  });

  testWidgets('local factory renders grid after prefs load', (tester) async {
    final rows = [
      {'part_#': 'R-10K', 'qty': 3},
      {'part_#': 'C-100N', 'qty': 7},
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 500,
            child: UnifiedDataGrid.local(
              rows: rows,
              columns: makeColumns(),
              persistKey: 'local_test_grid',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(SfDataGrid), findsOneWidget);
    expect(find.text('Part #'), findsOneWidget);
    expect(find.text('Qty'), findsOneWidget);
  });

  testWidgets('local factory can be built with editing disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 400,
            child: UnifiedDataGrid.local(
              rows: const [
                {'part_#': 'U-MCU', 'qty': 1},
              ],
              columns: makeColumns(),
              allowEditing: false,
              frozenColumnsCount: 0,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(SfDataGrid), findsOneWidget);
    final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
    expect(grid.allowEditing, isFalse);
    expect(grid.frozenColumnsCount, 0);
  });

  testWidgets('local grid commit updates rows and triggers callback', (
    tester,
  ) async {
    final rows = [
      {'part_#': 'U-MCU', 'qty': 1},
    ];
    var callbackRowsCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 400,
            child: UnifiedDataGrid.local(
              rows: rows,
              columns: makeColumns(),
              onRowsChanged: (updated) => callbackRowsCount = updated.length,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
    final source = grid.source as ListMapDataSource;
    source.newCellValue = '9';
    await source.onCellSubmit(
      source.rows.first,
      RowColumnIndex(0, 0),
      grid.columns[1],
    );
    await tester.pump();

    expect(rows.first['qty'], 9);
    expect(callbackRowsCount, 1);
  });

  testWidgets('inventory mode applies server and search filters', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final repo = InventoryRepo(firestore: db);
    await db.collection('inventory').add({
      'part_#': 'R-10K',
      'type': 'resistor',
      'package': '0603',
      'location': 'A1',
      'qty': 5,
    });
    await db.collection('inventory').add({
      'part_#': 'R-1K',
      'type': 'resistor',
      'package': '0805',
      'location': 'A1',
      'qty': 8,
    });
    await db.collection('inventory').add({
      'part_#': 'C-100N',
      'type': 'capacitor',
      'package': '0603',
      'location': 'A1',
      'qty': 10,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 450,
            child: UnifiedDataGrid(
              columns: makeColumns(),
              useInventoryStream: true,
              inventoryRepo: repo,
              typeFilter: const ['resistor'],
              packageFilter: const ['0603'],
              locationFilter: const ['A1'],
              searchQuery: 'resistor,0603',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
    final source = grid.source as FirestoreDataSource;
    expect(source.rowCount, 1);
  });

  testWidgets('collection mode applies simple search and row menu actions', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final repo = InventoryRepo(firestore: db);
    await db.collection('custom').add({'name': 'alpha board', 'qty': 1});
    await db.collection('custom').add({'name': 'beta board', 'qty': 3});

    final columns = [
      ColumnSpec(field: 'name', label: 'Name'),
      ColumnSpec(field: 'qty', label: 'Qty', kind: CellKind.integer),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 450,
            child: UnifiedDataGrid(
              columns: columns,
              collection: 'custom',
              inventoryRepo: repo,
              searchQuery: 'alpha',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
    expect(grid.onCellLongPress, isNotNull);
    expect(grid.onCellSecondaryTap, isNotNull);
    expect(grid.onColumnResizeStart, isNotNull);
    expect(grid.onColumnResizeUpdate, isNotNull);
    expect(grid.onColumnResizeEnd, isNotNull);

    final startOk = grid.onColumnResizeStart!.call(
      ColumnResizeStartDetails(
        column: grid.columns.first,
        width: 50,
        columnIndex: 0,
      ),
    );
    final updateOk = grid.onColumnResizeUpdate!.call(
      ColumnResizeUpdateDetails(
        column: grid.columns.first,
        width: 10,
        columnIndex: 0,
      ),
    );
    grid.onColumnResizeEnd!.call(
      ColumnResizeEndDetails(
        column: grid.columns.first,
        width: 100,
        columnIndex: 0,
      ),
    );
    expect(startOk, isTrue);
    expect(updateOk, isTrue);

    grid.onCellLongPress!(
      DataGridCellLongPressDetails(
        rowColumnIndex: RowColumnIndex(1, 0),
        column: grid.columns.first,
        globalPosition: const Offset(20, 20),
        localPosition: const Offset(20, 20),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy Reference'), findsOneWidget);
    await tester.tap(find.text('Copy Reference'));
    await tester.pumpAndSettle();
    expect(find.text('Copy Reference'), findsNothing);

    grid.onCellSecondaryTap!(
      DataGridCellTapDetails(
        rowColumnIndex: RowColumnIndex(1, 0),
        column: grid.columns.first,
        globalPosition: const Offset(30, 30),
        localPosition: const Offset(30, 30),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy Reference'), findsOneWidget);
    await tester.tap(find.text('Copy Reference'));
    await tester.pumpAndSettle();

    final gridAfterCopy = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
    final sourceAfterCopy = gridAfterCopy.source as FirestoreDataSource;
    expect(sourceAfterCopy.rowCount, 1);
    gridAfterCopy.onCellLongPress!(
      DataGridCellLongPressDetails(
        rowColumnIndex: RowColumnIndex(1, 0),
        column: gridAfterCopy.columns.first,
        globalPosition: const Offset(25, 25),
        localPosition: const Offset(25, 25),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Row'));
    await tester.pumpAndSettle();
    expect(sourceAfterCopy.rowCount, 0);
  });

  testWidgets('collection and inventory error streams show error text', (
    tester,
  ) async {
    final repo = _ErrorInventoryRepo();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedDataGrid(
            columns: makeColumns(),
            collection: 'custom',
            inventoryRepo: repo,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Error: collection stream failed'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnifiedDataGrid(
            columns: makeColumns(),
            useInventoryStream: true,
            inventoryRepo: repo,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Error: inventory stream failed'),
      findsOneWidget,
    );
  });
}

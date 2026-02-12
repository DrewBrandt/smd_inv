import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/data/list_map_source.dart';
import 'package:smd_inv/models/columns.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

void main() {
  group('ListMapDataSource', () {
    late List<Map<String, dynamic>> rows;
    late List<ColumnSpec> columns;
    late List<Map<String, dynamic>> commits;
    late ListMapDataSource source;

    setUp(() {
      rows = [
        {
          'qty': 3,
          'part_#': 'R-10K',
          'required_attributes': {'value': '10k'},
          'selected': false,
        },
      ];
      columns = [
        ColumnSpec(field: 'part_#'),
        ColumnSpec(field: 'qty', kind: CellKind.integer),
        ColumnSpec(field: 'required_attributes.value'),
        ColumnSpec(field: 'selected', kind: CellKind.checkbox),
      ];
      commits = [];
      source = ListMapDataSource(
        rows: rows,
        columns: columns,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        onCommit: (rowIndex, field, value) {
          commits.add({'rowIndex': rowIndex, 'field': field, 'value': value});
        },
      );
    });

    test('exposes rowCount and builds rows with nested values', () {
      expect(source.rowCount, 1);
      expect(source.rows, hasLength(1));

      final row = source.buildRowForIndex(0);
      expect(row.getCells()[0].value, 'R-10K');
      expect(row.getCells()[1].value, '3');
      expect(row.getCells()[2].value, '10k');
      expect(row.getCells()[3].value, 'false');
    });

    test('onCommitValue updates local map and emits callback', () async {
      await source.onCommitValue(0, 'required_attributes.value', '100n');
      expect(rows[0]['required_attributes']['value'], '100n');
      expect(commits.single['rowIndex'], 0);
      expect(commits.single['field'], 'required_attributes.value');
      expect(commits.single['value'], '100n');
    });

    test('getRowData returns raw row map', () {
      final row = source.getRowData(0);
      expect(identical(row, rows[0]), isTrue);
    });

    test('canSubmitCell validates integer/decimal/text input kinds', () async {
      final row = source.rows.first;
      final intCol = GridColumn(columnName: 'qty', label: const SizedBox());
      final decCol = GridColumn(columnName: 'price', label: const SizedBox());
      final textCol = GridColumn(columnName: 'part_#', label: const SizedBox());
      final decColumns = [
        ...columns,
        ColumnSpec(field: 'price', kind: CellKind.decimal),
      ];
      source = ListMapDataSource(
        rows: rows,
        columns: decColumns,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        onCommit: (rowIndex, field, value) {},
      );

      source.newCellValue = 'abc';
      expect(
        await source.canSubmitCell(row, RowColumnIndex(0, 0), intCol),
        isFalse,
      );

      source.newCellValue = '12.5';
      expect(
        await source.canSubmitCell(row, RowColumnIndex(0, 0), decCol),
        isTrue,
      );

      source.newCellValue = '12.5.1';
      expect(
        await source.canSubmitCell(row, RowColumnIndex(0, 0), decCol),
        isFalse,
      );

      source.newCellValue = 'anything';
      expect(
        await source.canSubmitCell(row, RowColumnIndex(0, 0), textCol),
        isTrue,
      );
    });

    test('onCellSubmit parses integer and skips unchanged values', () async {
      final col = GridColumn(columnName: 'qty', label: const SizedBox());
      final row = source.rows.first;

      source.newCellValue = '7';
      await source.onCellSubmit(row, RowColumnIndex(0, 0), col);

      expect(rows[0]['qty'], 7);
      expect(commits.single['value'], 7);
      expect(source.rows.first.getCells()[1].value, '7');

      source.newCellValue = '7';
      await source.onCellSubmit(source.rows.first, RowColumnIndex(0, 0), col);
      expect(commits, hasLength(1));
    });

    test('onCellSubmit ignores checkbox edits', () async {
      final checkboxCol = GridColumn(
        columnName: 'selected',
        label: const SizedBox(),
      );
      source.newCellValue = 'true';
      await source.onCellSubmit(
        source.rows.first,
        RowColumnIndex(0, 0),
        checkboxCol,
      );
      expect(commits, isEmpty);
      expect(rows[0]['selected'], false);
    });

    test('buildEditWidget handles dropdown fallback and numeric editor', () {
      final row = source.rows.first;
      final dropdownWidget = source.buildEditWidget(
        row,
        RowColumnIndex(0, 0),
        GridColumn(columnName: 'part_#', label: const SizedBox()),
        () {},
      );
      expect(dropdownWidget, isA<Container>());

      final dropdownColumns = [
        ColumnSpec(field: 'dropdown_missing', kind: CellKind.dropdown),
      ];
      source = ListMapDataSource(
        rows: rows,
        columns: dropdownColumns,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        onCommit: (rowIndex, field, value) {},
      );
      final noProvider = source.buildEditWidget(
        source.rows.first,
        RowColumnIndex(0, 0),
        GridColumn(columnName: 'dropdown_missing', label: const SizedBox()),
        () {},
      );
      expect(noProvider, isA<Text>());
      expect((noProvider as Text).data, 'No options provider');

      source = ListMapDataSource(
        rows: rows,
        columns: columns,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        onCommit: (rowIndex, field, value) {},
      );
      final numericEditor = source.buildEditWidget(
        source.rows.first,
        RowColumnIndex(0, 0),
        GridColumn(columnName: 'qty', label: const SizedBox()),
        () {},
      );
      expect(numericEditor, isA<Container>());
      final textField = findTextField(numericEditor!);
      expect(textField.textAlign, TextAlign.right);
      expect(source.editingController.text, '3');
    });

    test('buildRow renders checkbox cell and updates row state on toggle', () {
      final rowAdapter = source.buildRow(source.rows.first);
      final checkboxCell = rowAdapter.cells.last as Center;
      final checkbox = checkboxCell.child as Checkbox;

      checkbox.onChanged?.call(true);
      expect(rows[0]['selected'], true);
    });

    testWidgets(
      'dropdown editor loads options, filters results, and selects a match',
      (tester) async {
        final localRows = [
          {
            'required_attributes': {
              'part_type': 'resistor',
              'value': '10k',
              'size': '0603',
              'selected_component_ref': null,
            },
          },
        ];
        final dropdownColumns = [
          ColumnSpec(
            field: 'required_attributes.selected_component_ref',
            kind: CellKind.dropdown,
            dropdownOptionsProvider:
                (_) async => [
                  {
                    'id': 'docA',
                    'part_#': 'R-10K',
                    'type': 'resistor',
                    'value': '10k',
                    'package': '0603',
                    'qty': '20',
                    'location': 'A1',
                    'description': 'resistor',
                  },
                  {
                    'id': 'docB',
                    'part_#': 'R-1K',
                    'type': 'resistor',
                    'value': '1k',
                    'package': '0603',
                    'qty': '5',
                    'location': 'A2',
                    'description': 'resistor',
                  },
                  {
                    'id': 'docC',
                    'part_#': 'R-0',
                    'type': 'resistor',
                    'value': '0',
                    'package': '0603',
                    'qty': '0',
                    'location': 'A3',
                    'description': 'resistor',
                  },
                ],
          ),
        ];
        final dropdownSource = ListMapDataSource(
          rows: localRows,
          columns: dropdownColumns,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
          onCommit: (rowIndex, field, value) {},
        );

        var submitCalls = 0;
        final editor = dropdownSource.buildEditWidget(
          dropdownSource.rows.first,
          RowColumnIndex(0, 0),
          GridColumn(
            columnName: 'required_attributes.selected_component_ref',
            label: const SizedBox(),
          ),
          () => submitCalls++,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(width: 420, height: 260, child: editor),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Qty: 20'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'R-10K');
        await tester.pumpAndSettle();
        expect(find.text('R-10K'), findsWidgets);

        await tester.enterText(find.byType(TextField), 'does-not-exist');
        await tester.pumpAndSettle();
        expect(find.text('No matches found'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'R-10K');
        await tester.pumpAndSettle();
        await tester.tap(find.text('R-10K').last);
        await tester.pumpAndSettle();

        expect(dropdownSource.newCellValue, 'docA');
        expect(submitCalls, 1);
      },
    );
  });
}

TextField findTextField(Widget widget) {
  if (widget is TextField) return widget;
  if (widget is Container && widget.child != null) {
    return findTextField(widget.child!);
  }
  if (widget is Padding && widget.child != null) {
    return findTextField(widget.child!);
  }
  throw StateError('No TextField found in widget tree');
}

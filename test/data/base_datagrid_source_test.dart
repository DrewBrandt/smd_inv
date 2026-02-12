import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/data/base_datagrid_source.dart';
import 'package:smd_inv/data/datagrid_helpers.dart';
import 'package:smd_inv/models/columns.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launchedUrls.add(url);
    return true;
  }
}

class _TestSource extends BaseDataGridSource {
  final List<Map<String, dynamic>> rowsData;
  final List<Map<String, dynamic>> commits = [];

  _TestSource({
    required this.rowsData,
    required super.columns,
    required super.colorScheme,
  });

  @override
  int get rowCount => rowsData.length;

  @override
  DataGridRow buildRowForIndex(int rowIndex) {
    final row = rowsData[rowIndex];
    return DataGridRow(
      cells:
          columns
              .map(
                (c) => DataGridCell<String>(
                  columnName: c.field,
                  value: getNestedMapValue(row, c.field)?.toString() ?? '',
                ),
              )
              .toList(),
    );
  }

  @override
  Map<String, dynamic> getRowData(int rowIndex) => rowsData[rowIndex];

  @override
  Future<void> onCommitValue(int rowIndex, String path, dynamic parsedValue) async {
    setNestedMapValue(rowsData[rowIndex], path, parsedValue);
    commits.add({'rowIndex': rowIndex, 'path': path, 'value': parsedValue});
  }
}

Future<void> _pumpCell(WidgetTester tester, Widget cell) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: cell))));
  await tester.pumpAndSettle();
}

void main() {
  late UrlLauncherPlatform originalUrlLauncher;
  late _FakeUrlLauncher fakeUrlLauncher;
  late ColorScheme colorScheme;

  setUp(() {
    originalUrlLauncher = UrlLauncherPlatform.instance;
    fakeUrlLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fakeUrlLauncher;
    colorScheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  });

  tearDown(() {
    UrlLauncherPlatform.instance = originalUrlLauncher;
  });

  testWidgets('buildRow handles unknown fields and launches normalized URL cells', (
    tester,
  ) async {
    final source = _TestSource(
      rowsData: [
        {'placeholder': 'x'},
      ],
      columns: [ColumnSpec(field: 'placeholder')],
      colorScheme: colorScheme,
    );

    final unknownAdapter = source.buildRow(
      DataGridRow(
        cells: const [
          DataGridCell<String>(columnName: 'mystery', value: 'raw'),
        ],
      ),
    );
    await _pumpCell(tester, unknownAdapter.cells.single);
    expect(find.text('raw'), findsOneWidget);

    final urlAdapter = source.buildRow(
      DataGridRow(
        cells: const [
          DataGridCell<String>(columnName: 'datasheet', value: 'example.com'),
        ],
      ),
    );
    await _pumpCell(tester, urlAdapter.cells.single);
    await tester.tap(find.text('example.com'));
    await tester.pumpAndSettle();
    expect(fakeUrlLauncher.launchedUrls, contains('https://example.com'));

    final beforeInvalidTap = fakeUrlLauncher.launchedUrls.length;
    final invalidAdapter = source.buildRow(
      DataGridRow(
        cells: const [
          DataGridCell<String>(columnName: 'url', value: 'http://['),
        ],
      ),
    );
    await _pumpCell(tester, invalidAdapter.cells.single);
    await tester.tap(find.text('http://['));
    await tester.pumpAndSettle();
    expect(fakeUrlLauncher.launchedUrls.length, beforeInvalidTap);
  });

  test('canSubmitCell covers fallback, url, and checkbox kinds', () async {
    final source = _TestSource(
      rowsData: [
        {'url': 'https://example.com', 'selected': false},
      ],
      columns: [
        ColumnSpec(field: 'url', kind: CellKind.url),
        ColumnSpec(field: 'selected', kind: CellKind.checkbox),
      ],
      colorScheme: colorScheme,
    );
    final row = source.rows.first;

    source.newCellValue = 'free-text';
    expect(
      await source.canSubmitCell(
        row,
        RowColumnIndex(0, 0),
        GridColumn(columnName: 'missing_field', label: const SizedBox()),
      ),
      isTrue,
    );

    source.newCellValue = 'https://new.example';
    expect(
      await source.canSubmitCell(
        row,
        RowColumnIndex(0, 0),
        GridColumn(columnName: 'url', label: const SizedBox()),
      ),
      isTrue,
    );

    source.newCellValue = 'true';
    expect(
      await source.canSubmitCell(
        row,
        RowColumnIndex(0, 0),
        GridColumn(columnName: 'selected', label: const SizedBox()),
      ),
      isTrue,
    );
  });

  testWidgets('onCellSubmit and edit widgets handle decimal, text, and fallback paths', (
    tester,
  ) async {
    final source = _TestSource(
      rowsData: [
        {
          'price': 0.0,
          'name': 'old',
          'link': 'https://old.example',
        },
      ],
      columns: [
        ColumnSpec(field: 'price', kind: CellKind.decimal),
        ColumnSpec(field: 'name', kind: CellKind.text),
        ColumnSpec(field: 'link', kind: CellKind.url),
      ],
      colorScheme: colorScheme,
    );

    final row = source.rows.first;
    source.newCellValue = '1.25';
    await source.onCellSubmit(
      row,
      RowColumnIndex(0, 0),
      GridColumn(columnName: 'price', label: const SizedBox()),
    );
    expect(source.commits.last['value'], 1.25);

    source.newCellValue = 'updated';
    await source.onCellSubmit(
      source.rows.first,
      RowColumnIndex(0, 0),
      GridColumn(columnName: 'name', label: const SizedBox()),
    );
    expect(source.commits.last['value'], 'updated');

    source.newCellValue = 'https://new.example';
    await source.onCellSubmit(
      source.rows.first,
      RowColumnIndex(0, 0),
      GridColumn(columnName: 'link', label: const SizedBox()),
    );
    expect(source.commits.last['value'], 'https://new.example');

    final unknownEditor = source.buildEditWidget(
      DataGridRow(
        cells: const [
          DataGridCell<String>(columnName: 'missing_fallback', value: 'abc'),
        ],
      ),
      RowColumnIndex(0, 0),
      GridColumn(columnName: 'missing_fallback', label: const SizedBox()),
      () {},
    );
    expect(unknownEditor, isA<Container>());

    var submitCount = 0;
    final decimalEditor = source.buildEditWidget(
      source.rows.first,
      RowColumnIndex(0, 0),
      GridColumn(columnName: 'price', label: const SizedBox()),
      () => submitCount++,
    );
    expect(decimalEditor, isA<Container>());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 320, height: 80, child: decimalEditor),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fieldFinder = find.byType(TextField);
    await tester.enterText(fieldFinder, '1..2');
    await tester.pump();
    expect(source.editingController.text, isNot(contains('..')));

    await tester.enterText(fieldFinder, '1.2');
    await tester.pump();
    expect(source.newCellValue, '1.2');

    await tester.tap(fieldFinder);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submitCount, greaterThan(0));
  });

  testWidgets('dropdown editor handles provider errors with empty-state fallback', (
    tester,
  ) async {
    final sourceWithError = _TestSource(
      rowsData: [
        {
          'required_attributes': {
            'part_type': 'resistor',
            'value': '10k',
            'size': '0603',
          },
          'required_attributes.selected_component_ref': '',
        },
      ],
      columns: [
        ColumnSpec(
          field: 'required_attributes.selected_component_ref',
          kind: CellKind.dropdown,
          dropdownOptionsProvider: (_) async {
            throw StateError('provider failed');
          },
        ),
      ],
      colorScheme: colorScheme,
    );
    final errorEditor = sourceWithError.buildEditWidget(
      sourceWithError.rows.first,
      RowColumnIndex(0, 0),
      GridColumn(
        columnName: 'required_attributes.selected_component_ref',
        label: const SizedBox(),
      ),
      () {},
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SizedBox(width: 420, child: errorEditor))),
    );
    await tester.pumpAndSettle();
    expect(find.text('No inventory matches found'), findsOneWidget);
  });
}

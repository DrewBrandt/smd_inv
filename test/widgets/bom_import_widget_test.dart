import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/constants/firestore_constants.dart';
import 'package:smd_inv/widgets/bom_import_widget.dart';

class _FakeFilePicker extends FilePicker {
  FilePickerResult? pickResult;
  Object? pickError;
  Duration pickDelay = Duration.zero;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    if (pickError != null) throw pickError!;
    if (pickDelay > Duration.zero) {
      await Future<void>.delayed(pickDelay);
    }
    return pickResult;
  }
}

Future<void> _pumpWidget(
  WidgetTester tester, {
  required BomImportWidget widget,
}) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
  await tester.pumpAndSettle();
}

void main() {
  late _FakeFilePicker fakePicker;

  setUp(() {
    fakePicker = _FakeFilePicker();
    FilePicker.platform = fakePicker;
  });

  testWidgets('switches to paste mode and validates empty pasted input', (
    tester,
  ) async {
    var cancelCalls = 0;

    await _pumpWidget(
      tester,
      widget: BomImportWidget(
        onCancel: () => cancelCalls++,
        onImport: (_) {},
        firestore: FakeFirebaseFirestore(),
      ),
    );

    expect(find.text('Import Bill of Materials'), findsOneWidget);
    expect(find.text('Choose CSV File'), findsOneWidget);

    await tester.tap(find.text('Paste BOM Data'));
    await tester.pumpAndSettle();
    expect(find.text('Paste BOM Data'), findsOneWidget);

    await tester.tap(find.text('Parse & Match'));
    await tester.pumpAndSettle();
    expect(find.text('Paste BOM Data'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Please paste BOM data'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cancelCalls, 1);
  });

  testWidgets('parses pasted BOM text and imports reviewed lines', (
    tester,
  ) async {
    List<Map<String, dynamic>>? imported;

    await _pumpWidget(
      tester,
      widget: BomImportWidget(
        onCancel: () {},
        onImport: (lines) => imported = lines,
        firestore: FakeFirebaseFirestore(),
      ),
    );

    await tester.tap(find.text('Paste BOM Data'));
    await tester.pumpAndSettle();

    const bomCsv =
        'Reference,Quantity,Value,Footprint\n'
        'R1,2,10k,Resistor_SMD:R_0603\n'
        'C1,1,100n,Capacitor_SMD:C_0603\n';
    await tester.enterText(find.byType(TextField).last, bomCsv);

    await tester.tap(find.text('Parse & Match'));
    await tester.pumpAndSettle();

    expect(find.text('Review Imported BOM'), findsOneWidget);
    expect(find.textContaining('Parsed 2 lines'), findsOneWidget);

    await tester.tap(find.text('Import Lines'));
    await tester.pumpAndSettle();

    expect(imported, isNotNull);
    expect(imported, hasLength(2));
    expect(imported!.first['designators'], 'R1');
  });

  testWidgets('paste parsing rejects header-only input with no data rows', (
    tester,
  ) async {
    await _pumpWidget(
      tester,
      widget: BomImportWidget(
        onCancel: () {},
        onImport: (_) {},
        firestore: FakeFirebaseFirestore(),
      ),
    );

    await tester.tap(find.text('Paste BOM Data'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Reference,Quantity,Value,Footprint\n',
    );

    await tester.tap(find.text('Parse & Match'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(find.text('No data found in pasted text'), findsOneWidget);
  });

  testWidgets('paste mode back arrow returns to initial mode', (tester) async {
    await _pumpWidget(
      tester,
      widget: BomImportWidget(
        onCancel: () {},
        onImport: (_) {},
        firestore: FakeFirebaseFirestore(),
      ),
    );

    await tester.tap(find.text('Paste BOM Data'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Import Bill of Materials'), findsOneWidget);
    expect(find.text('Choose CSV File'), findsOneWidget);
  });

  testWidgets('review mode can reset back to file chooser', (tester) async {
    await _pumpWidget(
      tester,
      widget: BomImportWidget(
        onCancel: () {},
        onImport: (_) {},
        firestore: FakeFirebaseFirestore(),
      ),
    );

    await tester.tap(find.text('Paste BOM Data'));
    await tester.pumpAndSettle();

    const bomCsv =
        'Reference,Quantity,Value,Footprint\n'
        'U1,1,STM32,QFN-48\n';
    await tester.enterText(find.byType(TextField).last, bomCsv);
    await tester.tap(find.text('Parse & Match'));
    await tester.pumpAndSettle();

    expect(find.text('Review Imported BOM'), findsOneWidget);
    await tester.tap(find.text('Choose Different File'));
    await tester.pumpAndSettle();

    expect(find.text('Import Bill of Materials'), findsOneWidget);
    expect(find.text('Choose CSV File'), findsOneWidget);
  });

  testWidgets('choose CSV shows no-file error when picker is cancelled', (
    tester,
  ) async {
    fakePicker.pickResult = null;

    await _pumpWidget(
      tester,
      widget: BomImportWidget(
        onCancel: () {},
        onImport: (_) {},
        firestore: FakeFirebaseFirestore(),
      ),
    );

    await tester.tap(find.text('Choose CSV File'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No file selected'), findsOneWidget);
  });

  testWidgets('choose CSV shows empty-file message for header-only input', (
    tester,
  ) async {
    const headerOnly = 'Reference,Quantity,Value,Footprint\n';
    fakePicker.pickResult = FilePickerResult([
      PlatformFile(
        name: 'bom.csv',
        size: headerOnly.length,
        bytes: Uint8List.fromList(headerOnly.codeUnits),
      ),
    ]);

    await _pumpWidget(
      tester,
      widget: BomImportWidget(
        onCancel: () {},
        onImport: (_) {},
        firestore: FakeFirebaseFirestore(),
      ),
    );

    await tester.tap(find.text('Choose CSV File'));
    await tester.pumpAndSettle();

    expect(find.text('CSV file is empty'), findsOneWidget);
  });

  testWidgets('choose CSV handles picker exceptions', (tester) async {
    fakePicker.pickError = Exception('picker failed');

    await _pumpWidget(
      tester,
      widget: BomImportWidget(
        onCancel: () {},
        onImport: (_) {},
        firestore: FakeFirebaseFirestore(),
      ),
    );

    await tester.tap(find.text('Choose CSV File'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Error reading CSV'), findsOneWidget);
  });

  testWidgets(
    'choose CSV auto-matches inventory and preserves result metadata',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection(FirestoreCollections.inventory).doc('one').set({
        FirestoreFields.partNumber: 'ONE',
        FirestoreFields.qty: 10,
        FirestoreFields.type: 'ic',
        FirestoreFields.value: 'ONE',
        FirestoreFields.package: 'QFN-32',
      });
      await db.collection(FirestoreCollections.inventory).doc('dup-a').set({
        FirestoreFields.partNumber: 'DUP',
        FirestoreFields.qty: 5,
        FirestoreFields.type: 'ic',
        FirestoreFields.value: 'DUP',
        FirestoreFields.package: 'QFN-32',
        FirestoreFields.location: 'A1',
      });
      await db.collection(FirestoreCollections.inventory).doc('dup-b').set({
        FirestoreFields.partNumber: 'DUP',
        FirestoreFields.qty: 8,
        FirestoreFields.type: 'ic',
        FirestoreFields.value: 'DUP',
        FirestoreFields.package: 'QFN-32',
        FirestoreFields.location: 'B2',
      });

      const csv =
          'Reference,Quantity,Value,Footprint\n'
          'U1,1,ONE,Package_QFN:QFN-32\n'
          'U2,1,DUP,Package_QFN:QFN-32\n'
          'R1,1,10k,Resistor_SMD:R_0603\n'
          'U3,1,DNP,Package_QFN:QFN-32\n';
      fakePicker.pickResult = FilePickerResult([
        PlatformFile(
          name: 'bom.csv',
          size: csv.length,
          bytes: Uint8List.fromList(csv.codeUnits),
        ),
      ]);

      List<Map<String, dynamic>>? imported;
      await _pumpWidget(
        tester,
        widget: BomImportWidget(
          onCancel: () {},
          onImport: (lines) => imported = lines,
          firestore: db,
        ),
      );

      await tester.tap(find.text('Choose CSV File'));
      await tester.pumpAndSettle();

      expect(find.text('Review Imported BOM'), findsOneWidget);
      expect(
        find.textContaining(
          'Parsed 3 lines: 1 matched, 1 ambiguous, 1 missing',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('(1 skipped)'), findsOneWidget);
      expect(
        find.textContaining(
          'resolve unmatched lines in the board editor using Re-pair All',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Import Lines'));
      await tester.pumpAndSettle();

      expect(imported, isNotNull);
      final byDesignator = <String, Map<String, dynamic>>{
        for (final line in imported!) line['designators'].toString(): line,
      };

      final u1 = byDesignator['U1']!;
      final u2 = byDesignator['U2']!;
      final r1 = byDesignator['R1']!;

      expect(u1['_match_status'], 'matched');
      expect(
        (u1['required_attributes'] as Map<String, dynamic>)[FirestoreFields
            .selectedComponentRef],
        'one',
      );
      expect((u1['_matched_part'] as Map<String, dynamic>)['part_#'], 'ONE');

      expect(u2['_match_status'], 'ambiguous');
      expect((u2['_multiple_matches'] as List), hasLength(2));

      expect(r1['_match_status'], 'missing');
    },
  );

  testWidgets('shows initial loading spinner while reading CSV file', (
    tester,
  ) async {
    const bomCsv =
        'Reference,Quantity,Value,Footprint\nR1,1,10k,Resistor_SMD:R_0603\n';
    fakePicker.pickDelay = const Duration(milliseconds: 300);
    fakePicker.pickResult = FilePickerResult([
      PlatformFile(
        name: 'bom.csv',
        size: bomCsv.length,
        bytes: Uint8List.fromList(bomCsv.codeUnits),
      ),
    ]);

    await _pumpWidget(
      tester,
      widget: BomImportWidget(
        onCancel: () {},
        onImport: (_) {},
        firestore: FakeFirebaseFirestore(),
      ),
    );

    await tester.tap(find.text('Choose CSV File'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Review Imported BOM'), findsOneWidget);
  });
}

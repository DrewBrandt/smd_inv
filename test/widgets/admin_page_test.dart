import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/constants/firestore_constants.dart';
import 'package:smd_inv/pages/admin.dart';
import 'package:smd_inv/services/auth_service.dart';
import 'package:smd_inv/services/board_build_service.dart';
import 'package:smd_inv/services/inventory_audit_service.dart';

class _FakeFilePicker extends FilePicker {
  String? saveFilePath;
  FilePickerResult? pickResult;
  Object? saveError;
  Object? pickError;

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
    return pickResult;
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    if (saveError != null) throw saveError!;
    return saveFilePath;
  }
}

class _ThrowingBuildService extends BoardBuildService {
  final Object error;

  _ThrowingBuildService({
    required this.error,
    required FirebaseFirestore firestore,
  }) : super(firestore: firestore);

  @override
  Future<void> undoMakeHistory(String historyId) async {
    throw error;
  }
}

class _FakeAuditService extends InventoryAuditService {
  String exportText = 'part_#,qty\nR-10K,10\n';
  int exportCalls = 0;
  int replaceCalls = 0;
  AuditReplaceResult replaceResult = const AuditReplaceResult(
    previousCount: 0,
    importedCount: 0,
    skippedRows: 0,
  );
  Object? exportError;
  Object? replaceError;
  String? lastImportCsv;

  _FakeAuditService({required FirebaseFirestore firestore})
    : super(firestore: firestore);

  @override
  Future<String> exportInventoryCsv() async {
    exportCalls++;
    if (exportError != null) throw exportError!;
    return exportText;
  }

  @override
  Future<AuditReplaceResult> replaceInventoryFromCsvText(String csvText) async {
    replaceCalls++;
    lastImportCsv = csvText;
    if (replaceError != null) throw replaceError!;
    return replaceResult;
  }
}

Future<void> _pumpAdmin(
  WidgetTester tester, {
  required FakeFirebaseFirestore db,
  required BoardBuildService buildService,
  required InventoryAuditService auditService,
  Future<void> Function(String path, String contents)? writeFile,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AdminPage(
          firestore: db,
          buildService: buildService,
          auditService: auditService,
          writeFile: writeFile,
        ),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _seedHistory(
  FakeFirebaseFirestore db, {
  String action = 'make_board',
}) async {
  await db.collection(FirestoreCollections.history).add({
    FirestoreFields.action: action,
    FirestoreFields.boardName: 'Main',
    FirestoreFields.quantity: 2,
    FirestoreFields.timestamp: Timestamp.now(),
    FirestoreFields.consumedItems: [
      {'doc_id': 'abc', FirestoreFields.quantity: 3},
    ],
  });
}

void main() {
  late _FakeFilePicker fakePicker;

  setUp(() {
    fakePicker = _FakeFilePicker();
    FilePicker.platform = fakePicker;
    AuthService.canEditOverride = (_) => true;
  });

  tearDown(() {
    AuthService.canEditOverride = null;
  });

  testWidgets(
    'shows view-only and empty history states when user cannot edit',
    (tester) async {
      AuthService.canEditOverride = (_) => false;
      final db = FakeFirebaseFirestore();
      final audit = _FakeAuditService(firestore: db);

      await _pumpAdmin(
        tester,
        db: db,
        buildService: BoardBuildService(firestore: db),
        auditService: audit,
      );

      expect(
        find.textContaining('View-only mode. Sign in with a UMD account'),
        findsOneWidget,
      );
      expect(find.text('No history entries yet.'), findsOneWidget);
    },
  );

  testWidgets('undo surfaces BoardBuildException message', (tester) async {
    final db = FakeFirebaseFirestore();
    await _seedHistory(db);
    final audit = _FakeAuditService(firestore: db);

    await _pumpAdmin(
      tester,
      db: db,
      buildService: _ThrowingBuildService(
        error: const BoardBuildException('Already undone'),
        firestore: db,
      ),
      auditService: audit,
    );

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Already undone'), findsOneWidget);
  });

  testWidgets('undo surfaces generic failure message', (tester) async {
    final db = FakeFirebaseFirestore();
    await _seedHistory(db);
    final audit = _FakeAuditService(firestore: db);

    await _pumpAdmin(
      tester,
      db: db,
      buildService: _ThrowingBuildService(
        error: Exception('db unavailable'),
        firestore: db,
      ),
      auditService: audit,
    );

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Undo failed:'), findsOneWidget);
  });

  testWidgets('exports audit CSV to selected path', (tester) async {
    final db = FakeFirebaseFirestore();
    final audit = _FakeAuditService(firestore: db);
    String? writtenPath;
    String? writtenContents;
    const path = r'C:\tmp\audit_export.csv';
    fakePicker.saveFilePath = path;

    await _pumpAdmin(
      tester,
      db: db,
      buildService: BoardBuildService(firestore: db),
      auditService: audit,
      writeFile: (p, c) async {
        writtenPath = p;
        writtenContents = c;
      },
    );

    await tester.tap(find.text('Export CSV'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(audit.exportCalls, 1);
    expect(writtenPath, path);
    expect(writtenContents, contains('part_#'));
  });

  testWidgets('export canceled path does not call write callback', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final audit = _FakeAuditService(firestore: db);
    fakePicker.saveFilePath = null;
    var writeCalls = 0;

    await _pumpAdmin(
      tester,
      db: db,
      buildService: BoardBuildService(firestore: db),
      auditService: audit,
      writeFile: (_, __) async => writeCalls++,
    );

    await tester.tap(find.text('Export CSV'));
    await tester.pump(const Duration(milliseconds: 150));

    expect(audit.exportCalls, 1);
    expect(writeCalls, 0);
  });

  testWidgets('export shows failure snackbar when picker throws', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final audit = _FakeAuditService(firestore: db);
    fakePicker.saveError = Exception('dialog blocked');

    await _pumpAdmin(
      tester,
      db: db,
      buildService: BoardBuildService(firestore: db),
      auditService: audit,
    );

    await tester.tap(find.text('Export CSV'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Export failed:'), findsOneWidget);
  });

  testWidgets('import replace success path uses picked bytes', (tester) async {
    final db = FakeFirebaseFirestore();
    final audit = _FakeAuditService(firestore: db)
      ..replaceResult = const AuditReplaceResult(
        previousCount: 3,
        importedCount: 2,
        skippedRows: 1,
      );
    fakePicker.pickResult = FilePickerResult([
      PlatformFile(
        name: 'audit.csv',
        size: 24,
        bytes: Uint8List.fromList('part_#,qty\nR-10K,5\n'.codeUnits),
      ),
    ]);

    await _pumpAdmin(
      tester,
      db: db,
      buildService: BoardBuildService(firestore: db),
      auditService: audit,
    );

    await tester.tap(find.text('Import & Replace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace All'));
    await tester.pumpAndSettle();

    expect(audit.replaceCalls, 1);
    expect(audit.lastImportCsv, contains('part_#,qty'));
  });

  testWidgets('import replace cancel exits without replacement', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final audit = _FakeAuditService(firestore: db);

    await _pumpAdmin(
      tester,
      db: db,
      buildService: BoardBuildService(firestore: db),
      auditService: audit,
    );

    await tester.tap(find.text('Import & Replace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(audit.replaceCalls, 0);
  });

  testWidgets('import replace reads CSV from file path when bytes are null', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final audit = _FakeAuditService(firestore: db);
    final csvPath =
        '${Directory.current.path}${Platform.pathSeparator}admin_import_test.csv';
    final csvFile = File(csvPath);
    if (await csvFile.exists()) {
      await csvFile.delete();
    }
    await csvFile.writeAsString('part_#,qty\nR-100,9\n');
    fakePicker.pickResult = FilePickerResult([
      PlatformFile(name: 'audit.csv', size: 20, path: csvPath),
    ]);

    await _pumpAdmin(
      tester,
      db: db,
      buildService: BoardBuildService(firestore: db),
      auditService: audit,
    );

    await tester.tap(find.text('Import & Replace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Replace All'));

    var replaced = false;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (audit.replaceCalls == 1) {
        replaced = true;
        break;
      }
    }

    expect(replaced, isTrue);
    expect(audit.lastImportCsv, contains('R-100'));
    if (await csvFile.exists()) {
      await csvFile.delete();
    }
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('ensureCanEdit shows snackbar when action is no longer allowed', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await _seedHistory(db);
    final audit = _FakeAuditService(firestore: db);

    AuthService.canEditOverride = (_) => true;
    await _pumpAdmin(
      tester,
      db: db,
      buildService: BoardBuildService(firestore: db),
      auditService: audit,
    );

    AuthService.canEditOverride = (_) => false;
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(
      find.text('You must sign in with a UMD account to edit admin data.'),
      findsOneWidget,
    );
  });

  testWidgets('history list renders separators for multiple entries', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await _seedHistory(db);
    await _seedHistory(db);
    final audit = _FakeAuditService(firestore: db);

    await _pumpAdmin(
      tester,
      db: db,
      buildService: BoardBuildService(firestore: db),
      auditService: audit,
    );

    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets(
    'import replace handles AuditReplaceException and generic errors',
    (tester) async {
      final db = FakeFirebaseFirestore();
      final audit = _FakeAuditService(firestore: db);
      fakePicker.pickResult = FilePickerResult([
        PlatformFile(
          name: 'audit.csv',
          size: 10,
          bytes: Uint8List.fromList('x'.codeUnits),
        ),
      ]);

      await _pumpAdmin(
        tester,
        db: db,
        buildService: BoardBuildService(firestore: db),
        auditService: audit,
      );

      audit.replaceError = const AuditReplaceException('Malformed CSV');
      await tester.tap(find.text('Import & Replace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace All'));
      await tester.pumpAndSettle();
      expect(audit.replaceCalls, 1);
      expect(audit.lastImportCsv, contains('x'));

      audit.replaceError = null;
      fakePicker.pickError = Exception('picker exploded');
      await tester.tap(find.text('Import & Replace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace All'));
      await tester.pumpAndSettle();
      expect(audit.replaceCalls, 1);
    },
  );
}

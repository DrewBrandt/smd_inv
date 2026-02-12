import 'package:flutter/gestures.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smd_inv/constants/firestore_constants.dart';
import 'package:smd_inv/data/boards_repo.dart';
import 'package:smd_inv/pages/boards_editor.dart';
import 'package:smd_inv/services/auth_service.dart';
import 'package:smd_inv/widgets/bom_import_widget.dart';

class _FakeBoardsRepo extends BoardsRepo {
  String? duplicatedFrom;
  String? deletedId;
  Object? duplicateError;
  Object? deleteError;

  _FakeBoardsRepo() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<String> duplicateBoard(String sourceId, {String? newName}) async {
    if (duplicateError != null) throw duplicateError!;
    duplicatedFrom = sourceId;
    return 'cloned-123';
  }

  @override
  Future<void> deleteBoard(String id) async {
    if (deleteError != null) throw deleteError!;
    deletedId = id;
  }
}

Future<void> _pumpEditor(
  WidgetTester tester,
  FakeFirebaseFirestore db,
  _FakeBoardsRepo fakeRepo,
  String initialLocation,
) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/boards',
        builder:
            (context, state) => const Scaffold(body: Text('Boards Landing')),
      ),
      GoRoute(
        path: '/boards/new',
        builder:
            (context, state) => Scaffold(
              body: BoardEditorPage(
                boardId: null,
                firestore: db,
                boardsRepo: fakeRepo,
              ),
            ),
      ),
      GoRoute(
        path: '/boards/:id',
        builder:
            (context, state) => Scaffold(
              body: BoardEditorPage(
                boardId: state.pathParameters['id'],
                firestore: db,
                boardsRepo: fakeRepo,
              ),
            ),
      ),
    ],
  );

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _seedBoard(
  FakeFirebaseFirestore db,
  String boardId, {
  List<Map<String, dynamic>> bom = const [],
  String name = 'Main Board',
  String? imageUrl,
}) async {
  await db.collection(FirestoreCollections.boards).doc(boardId).set({
    FirestoreFields.name: name,
    FirestoreFields.imageUrl: imageUrl,
    FirestoreFields.bom: bom,
  });
}

Future<void> _seedInventory(FakeFirebaseFirestore db) async {
  await db.collection(FirestoreCollections.inventory).doc('one').set({
    FirestoreFields.partNumber: 'ONE',
    FirestoreFields.type: 'ic',
    FirestoreFields.value: 'ONE',
    FirestoreFields.package: 'QFN-32',
    FirestoreFields.qty: 5,
  });
  await db.collection(FirestoreCollections.inventory).doc('dup-a').set({
    FirestoreFields.partNumber: 'DUP',
    FirestoreFields.type: 'ic',
    FirestoreFields.value: 'DUP',
    FirestoreFields.package: 'QFN-32',
    FirestoreFields.qty: 3,
  });
  await db.collection(FirestoreCollections.inventory).doc('dup-b').set({
    FirestoreFields.partNumber: 'DUP',
    FirestoreFields.type: 'ic',
    FirestoreFields.value: 'DUP',
    FirestoreFields.package: 'QFN-32',
    FirestoreFields.qty: 7,
  });
}

void main() {
  setUp(() {
    AuthService.canEditOverride = (_) => true;
  });

  tearDown(() {
    AuthService.canEditOverride = null;
  });

  testWidgets('Board editor clone action calls repo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    const boardId = 'board-1';
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo();
    await _seedBoard(db, boardId);
    await _pumpEditor(tester, db, fakeRepo, '/boards/$boardId');

    await tester.tap(find.byIcon(Icons.copy_all_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fakeRepo.duplicatedFrom, boardId);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Board editor delete action calls repo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    const boardId = 'board-2';
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo();
    await _seedBoard(db, boardId);
    await _pumpEditor(tester, db, fakeRepo, '/boards/$boardId');

    await tester.tap(find.byIcon(Icons.delete_forever_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Delete').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fakeRepo.deletedId, boardId);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Board editor add line updates BOM summary chip', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    const boardId = 'board-3';
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo();
    await _seedBoard(db, boardId);
    await _pumpEditor(tester, db, fakeRepo, '/boards/$boardId');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Add Line'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('1 total'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Board editor save validates required name', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo();
    await _pumpEditor(tester, db, fakeRepo, '/boards/new');

    await tester.enterText(find.byType(TextField).at(2), 'Description only');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Save Changes'), findsOneWidget);
    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Name is required'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Board editor saves new board and returns to listing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo();
    await _pumpEditor(tester, db, fakeRepo, '/boards/new');

    await tester.enterText(find.byType(TextField).first, 'Fresh Board');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Save Changes'), findsOneWidget);
    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Boards Landing'), findsOneWidget);
    final allBoards = await db.collection(FirestoreCollections.boards).get();
    expect(allBoards.docs, hasLength(1));
    expect(allBoards.docs.single.data()[FirestoreFields.name], 'Fresh Board');
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'Board editor cancel with dirty state keeps editing when chosen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1800, 1200));
      final db = FakeFirebaseFirestore();
      final fakeRepo = _FakeBoardsRepo();
      await _pumpEditor(tester, db, fakeRepo, '/boards/new');

      await tester.enterText(find.byType(TextField).first, 'Unsaved Name');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('Bill of Materials'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('Board editor cancel without changes returns to listing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo();
    await _pumpEditor(tester, db, fakeRepo, '/boards/new');

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Boards Landing'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Board editor clone shows guidance for unsaved board', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo();
    await _pumpEditor(tester, db, fakeRepo, '/boards/new');

    await tester.tap(find.byIcon(Icons.copy_all_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Save this board first'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Board editor clone surfaces repository failures', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    const boardId = 'board-clone-fail';
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo()..duplicateError = Exception('boom');
    await _seedBoard(db, boardId);
    await _pumpEditor(tester, db, fakeRepo, '/boards/$boardId');

    await tester.tap(find.byIcon(Icons.copy_all_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Clone failed:'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Board editor delete warns when board has not been saved', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo();
    await _pumpEditor(tester, db, fakeRepo, '/boards/new');

    await tester.tap(find.byIcon(Icons.delete_forever_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('This board is not saved yet.'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Board editor delete dialog cancel keeps board intact', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    const boardId = 'board-delete-cancel';
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo();
    await _seedBoard(db, boardId);
    await _pumpEditor(tester, db, fakeRepo, '/boards/$boardId');

    await tester.tap(find.byIcon(Icons.delete_forever_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancel').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fakeRepo.deletedId, isNull);
    expect(find.text('Bill of Materials'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Board editor delete surfaces repository failures', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    const boardId = 'board-delete-fail';
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo()..deleteError = Exception('denied');
    await _seedBoard(db, boardId);
    await _pumpEditor(tester, db, fakeRepo, '/boards/$boardId');

    await tester.tap(find.byIcon(Icons.delete_forever_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Delete').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Delete failed:'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Board editor replaces BOM through import flow and can cancel import view', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    const boardId = 'board-import-flow';
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo();
    await _seedBoard(
      db,
      boardId,
      bom: [
        {
          'designators': 'R0',
          'qty': 1,
          FirestoreFields.requiredAttributes: {'part_type': 'resistor'},
          '_match_status': 'missing',
          '_ignored': false,
        },
      ],
    );
    await _pumpEditor(tester, db, fakeRepo, '/boards/$boardId');

    await tester.tap(find.text('Replace BOM'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Replace BOM?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BomImportWidget), findsNothing);

    await tester.tap(find.text('Replace BOM'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Replace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(BomImportWidget), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(BomImportWidget),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BomImportWidget), findsNothing);

    await tester.tap(find.text('Replace BOM'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Replace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final importWidget = tester.widget<BomImportWidget>(
      find.byType(BomImportWidget),
    );
    importWidget.onImport([
      {
        'designators': 'U1',
        'qty': 1,
        FirestoreFields.requiredAttributes: {'part_type': 'ic'},
        '_match_status': 'matched',
        '_ignored': false,
      },
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Imported 1 BOM lines'), findsOneWidget);
    expect(find.text('1 total'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Board editor save sanitizes BOM lines for persisted schema', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    const boardId = 'board-save-sanitize';
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo();

    await _seedBoard(
      db,
      boardId,
      bom: [
        {
          'designators': '  ',
          'qty': 2,
          FirestoreFields.category: 'components',
          FirestoreFields.description: 'Primary resistor',
          FirestoreFields.notes: 'critical',
          FirestoreFields.requiredAttributes: {
            'part_type': 'resistor',
            'value': '10k',
            '_tmp': 'x',
          },
          '_ignored': true,
        },
        {
          'designators': 'C1',
          'qty': 1,
          FirestoreFields.category: '   ',
          FirestoreFields.description: '   ',
          FirestoreFields.requiredAttributes: {
            'part_type': 'capacitor',
            'value': '100n',
          },
        },
      ],
    );

    await _pumpEditor(tester, db, fakeRepo, '/boards/$boardId');

    await tester.enterText(find.byType(TextField).first, 'Updated Board');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save Changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final snap =
        await db.collection(FirestoreCollections.boards).doc(boardId).get();
    final data = snap.data()!;
    final savedBom =
        (data[FirestoreFields.bom] as List).cast<Map<String, dynamic>>();

    expect(savedBom, hasLength(2));
    expect(savedBom.first['designators'], '?');
    expect(savedBom.first[FirestoreFields.qty], 2);
    expect(savedBom.first[FirestoreFields.category], 'components');
    expect(savedBom.first[FirestoreFields.description], 'Primary resistor');
    expect(savedBom.first[FirestoreFields.notes], 'critical');
    expect(
      (savedBom.first[FirestoreFields.requiredAttributes] as Map<String, dynamic>)
          .containsKey('_tmp'),
      isFalse,
    );
    expect(savedBom.first['_ignored'], isTrue);

    expect(savedBom[1].containsKey(FirestoreFields.category), isFalse);
    expect(savedBom[1].containsKey(FirestoreFields.description), isFalse);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Board editor re-pair updates matched, ambiguous, and missing chips', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    const boardId = 'board-repair';
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo();
    await _seedInventory(db);
    await _seedBoard(
      db,
      boardId,
      bom: [
        {
          'designators': 'U1',
          'qty': 1,
          FirestoreFields.requiredAttributes: {
            'part_type': 'resistor',
            FirestoreFields.value: '123k',
            'size': '0603',
            FirestoreFields.partNumber: '',
            FirestoreFields.selectedComponentRef: null,
          },
          '_match_status': 'pending',
          '_ignored': false,
        },
        {
          'designators': 'U2',
          'qty': 1,
          FirestoreFields.requiredAttributes: {
            'part_type': 'ic',
            FirestoreFields.value: 'ONE',
            'size': 'QFN-32',
            FirestoreFields.partNumber: '',
            FirestoreFields.selectedComponentRef: null,
          },
          '_match_status': 'pending',
          '_ignored': false,
        },
        {
          'designators': 'U3',
          'qty': 1,
          FirestoreFields.requiredAttributes: {
            'part_type': 'ic',
            FirestoreFields.value: 'DUP',
            'size': 'QFN-32',
            FirestoreFields.partNumber: '',
            FirestoreFields.selectedComponentRef: 'missing-doc',
          },
          '_match_status': 'pending',
          '_ignored': false,
        },
      ],
    );

    await _pumpEditor(tester, db, fakeRepo, '/boards/$boardId');
    await tester.tap(find.text('Re-pair All'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('1 matched'), findsOneWidget);
    expect(find.text('1 ambiguous'), findsOneWidget);
    expect(find.text('1 missing'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Board editor uses latest permission check in action callbacks', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo();
    await _pumpEditor(tester, db, fakeRepo, '/boards/new');

    AuthService.canEditOverride = (_) => false;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Add Line'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.textContaining('You must sign in with a UMD account'),
      findsOneWidget,
    );
    expect(find.text('No BOM lines yet'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Board editor clear-image affordance marks page dirty', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1200));
    final db = FakeFirebaseFirestore();
    final fakeRepo = _FakeBoardsRepo();
    await _pumpEditor(tester, db, fakeRepo, '/boards/new');

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer();
    await gesture.moveTo(tester.getCenter(find.byIcon(Icons.image_outlined)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}

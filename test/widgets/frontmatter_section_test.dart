import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/widgets/boards_editor/frontmatter.dart';

Future<void> _pumpFrontmatter(
  WidgetTester tester, {
  required double width,
  required bool canEdit,
  required TextEditingController name,
  required TextEditingController desc,
  required TextEditingController image,
  required ValueNotifier<String?> category,
  required VoidCallback onClearImage,
  required VoidCallback onClone,
  required VoidCallback onDelete,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: FrontmatterSection(
              name: name,
              desc: desc,
              category: category,
              image: image,
              onClearImage: onClearImage,
              onClone: onClone,
              onDelete: onDelete,
              canEdit: canEdit,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('categoryColor returns mapped and fallback colors', () {
    expect(categoryColor('Radio', Colors.black), const Color(0xFF77C0FC));
    expect(categoryColor('Missing', Colors.black), Colors.black);
    expect(categoryColor(null, Colors.white), Colors.white);
  });

  testWidgets('compact layout renders disabled controls when view-only', (
    tester,
  ) async {
    final name = TextEditingController(text: 'Board');
    final desc = TextEditingController(text: 'Desc');
    final image = TextEditingController();
    final category = ValueNotifier<String?>('FC');

    await _pumpFrontmatter(
      tester,
      width: 900,
      canEdit: false,
      name: name,
      desc: desc,
      image: image,
      category: category,
      onClearImage: () {},
      onClone: () {},
      onDelete: () {},
    );

    expect(find.text('Clone'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    final textFields = tester.widgetList<TextField>(find.byType(TextField));
    expect(textFields.first.enabled, isFalse);
  });

  testWidgets('wide layout supports category changes and action callbacks', (
    tester,
  ) async {
    final name = TextEditingController(text: 'Board');
    final desc = TextEditingController(text: 'Desc');
    final image = TextEditingController();
    final category = ValueNotifier<String?>('Radio');
    var cloneCalls = 0;
    var deleteCalls = 0;

    await _pumpFrontmatter(
      tester,
      width: 1400,
      canEdit: true,
      name: name,
      desc: desc,
      image: image,
      category: category,
      onClearImage: () {},
      onClone: () => cloneCalls++,
      onDelete: () => deleteCalls++,
    );

    await tester.tap(find.byIcon(Icons.copy_all_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_forever_rounded));
    await tester.pumpAndSettle();

    expect(cloneCalls, 1);
    expect(deleteCalls, 1);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GS').last);
    await tester.pumpAndSettle();

    expect(category.value, 'GS');
  });

  testWidgets('hovering image shows clear affordance and executes callback', (
    tester,
  ) async {
    final name = TextEditingController(text: 'Board');
    final desc = TextEditingController(text: 'Desc');
    final image = TextEditingController();
    final category = ValueNotifier<String?>('FC');
    var clearCalls = 0;

    await _pumpFrontmatter(
      tester,
      width: 1400,
      canEdit: true,
      name: name,
      desc: desc,
      image: image,
      category: category,
      onClearImage: () => clearCalls++,
      onClone: () {},
      onDelete: () {},
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.byIcon(Icons.image_outlined)));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(clearCalls, 1);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smd_inv/models/board.dart';
import 'package:smd_inv/models/readiness.dart';
import 'package:smd_inv/utils/board_category_colors.dart';
import 'package:smd_inv/widgets/board_card.dart';

void main() {
  testWidgets('make button stays enabled when board is not fully buildable', (
    tester,
  ) async {
    var makeCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 560,
            child: ImprovedBoardCard(
              board: BoardDoc(
                id: 'board-1',
                name: 'Main Board',
                bom: [
                  BomLine(
                    designators: 'U1',
                    qty: 1,
                    requiredAttributes: {
                      'part_type': 'ic',
                      'part_#': 'MISSING',
                    },
                  ),
                ],
              ),
              readiness: const Readiness(
                buildableQty: 0,
                readyPct: 0.0,
                shortfalls: [Shortfall('Missing IC', 1)],
              ),
              onOpen: () {},
              onDuplicate: () {},
              onMake: (_) async {
                makeCalls++;
              },
            ),
          ),
        ),
      ),
    );

    final makeButton =
        find
            .ancestor(
              of: find.text('Make'),
              matching: find.byWidgetPredicate(
                (widget) => widget is ButtonStyleButton,
              ),
            )
            .first;
    expect(makeButton, findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(makeButton).onPressed, isNotNull);

    await tester.tap(makeButton);
    await tester.pumpAndSettle();

    expect(find.text('Make Main Board'), findsOneWidget);

    await tester.tap(find.text('Make Boards'));
    await tester.pumpAndSettle();

    expect(makeCalls, 1);
  });

  testWidgets('board card tints category badge and card by board type', (
    tester,
  ) async {
    const radioColor = Color(0xFF77C0FC);
    final theme = ThemeData(useMaterial3: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 560,
            child: ImprovedBoardCard(
              board: BoardDoc(
                id: 'board-radio',
                name: 'Telemetry',
                category: 'Radio',
                bom: const [],
              ),
              readiness: const Readiness(
                buildableQty: 0,
                readyPct: 1.0,
                shortfalls: [],
              ),
              onOpen: () {},
              onDuplicate: () {},
              onMake: (_) async {},
            ),
          ),
        ),
      ),
    );

    final chip = tester.widget<Chip>(find.byType(Chip).first);
    expect(chip.backgroundColor, radioColor.withValues(alpha: 0.16));

    final card = tester.widget<Card>(find.byType(Card));
    expect(
      card.color,
      Color.alphaBlend(
        radioColor.withValues(alpha: 0.05),
        theme.colorScheme.surface,
      ),
    );

    expect(boardCategoryColor('radio', Colors.black), radioColor);
  });
}

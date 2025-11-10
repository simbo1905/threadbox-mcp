// This is a basic Flutter widget test.

import 'package:flutter_test/flutter_test.dart';

import 'package:snake_game/main.dart';

void main() {
  testWidgets('Snake game loads', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SnakeGameApp());

    // Verify that the score is displayed
    expect(find.text('Score: 0'), findsOneWidget);
    
    // Verify that the start button is present
    expect(find.text('Start Game'), findsOneWidget);
  });
}

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_snake_game/src/game_controller.dart';

void main() {
  group('SnakeGameController', () {
    test('initial state is seeded correctly', () {
      final controller = SnakeGameController(rows: 10, columns: 10);

      expect(controller.snake.length, 3);
      expect(controller.snake.first.x, greaterThanOrEqualTo(0));
      expect(controller.snake.first.y, greaterThanOrEqualTo(0));
      expect(controller.isGameOver, isFalse);
      expect(controller.isRunning, isFalse);
      expect(controller.score, 0);
      expect(controller.food, isNotNull);
    });

    test('step advances snake forward', () {
      final controller = SnakeGameController(rows: 10, columns: 10);
      final Point<int> headBefore = controller.snake.first;

      controller.step();
      final Point<int> headAfter = controller.snake.first;

      expect(headAfter.x, headBefore.x + 1);
      expect(headAfter.y, headBefore.y);
      expect(controller.snake.length, 3);
    });

    test('snake grows and scores when eating food', () {
      final controller = SnakeGameController(rows: 10, columns: 10);
      final Point<int> head = controller.snake.first;
      final Point<int> foodPosition = Point<int>(head.x + 1, head.y);

      controller.debugFood = foodPosition;
      controller.step();

      expect(controller.snake.length, 4);
      expect(controller.score, 10);
      expect(controller.highScore, 10);
      expect(controller.food, isNotNull);
    });

    test('collision with wall ends the game', () {
      final controller = SnakeGameController(rows: 6, columns: 6);

      // Position the snake near the right wall.
      controller.debugFood = null;
      for (var i = 0; i < 6; i++) {
        controller.step();
      }

      expect(controller.isGameOver, isTrue);
      expect(controller.isRunning, isFalse);
    });

    test('reversing direction is ignored', () {
      final controller = SnakeGameController(rows: 10, columns: 10);

      controller.queueDirection(SnakeDirection.left);
      controller.step();

      final Point<int> headAfter = controller.snake.first;
      expect(headAfter.x, greaterThan(controller.snake[1].x));
    });
  });
}

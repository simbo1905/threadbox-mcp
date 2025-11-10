import 'dart:math';

import 'package:flutter/material.dart';

class SnakeBoardPainter extends CustomPainter {
  SnakeBoardPainter({
    required this.snake,
    required this.food,
    required this.rows,
    required this.columns,
    required this.isGameOver,
    required this.isRunning,
  });

  final List<Point<int>> snake;
  final Point<int>? food;
  final int rows;
  final int columns;
  final bool isGameOver;
  final bool isRunning;

  static const Color _backgroundColor = Color(0xFF0D0D0D);
  static const Color _gridColor = Color(0xFF1F1F1F);
  static const Color _snakeBodyColor = Color(0xFF4CAF50);
  static const Color _snakeHeadColor = Color(0xFF81C784);
  static const Color _foodColor = Color(0xFFFF7043);

  @override
  void paint(Canvas canvas, Size size) {
    final double cellWidth = size.width / columns;
    final double cellHeight = size.height / rows;

    final Paint backgroundPaint = Paint()..color = _backgroundColor;
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    _drawGrid(canvas, size, cellWidth, cellHeight);
    _drawSnake(canvas, cellWidth, cellHeight);
    _drawFood(canvas, cellWidth, cellHeight);

    if (isGameOver || !isRunning) {
      _drawOverlay(canvas, size);
    }
  }

  void _drawGrid(
      Canvas canvas, Size size, double cellWidth, double cellHeight) {
    final Paint gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;

    for (var col = 0; col <= columns; col++) {
      final double dx = col * cellWidth;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), gridPaint);
    }
    for (var row = 0; row <= rows; row++) {
      final double dy = row * cellHeight;
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
    }
  }

  void _drawSnake(Canvas canvas, double cellWidth, double cellHeight) {
    if (snake.isEmpty) {
      return;
    }

    final Paint bodyPaint = Paint()..color = _snakeBodyColor;
    final Paint headPaint = Paint()..color = _snakeHeadColor;

    for (var i = 0; i < snake.length; i++) {
      final Point<int> segment = snake[i];
      final Rect rect = Rect.fromLTWH(
        segment.x * cellWidth + 2,
        segment.y * cellHeight + 2,
        cellWidth - 4,
        cellHeight - 4,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        i == 0 ? headPaint : bodyPaint,
      );
    }
  }

  void _drawFood(Canvas canvas, double cellWidth, double cellHeight) {
    if (food == null) {
      return;
    }
    final Paint foodPaint = Paint()..color = _foodColor;
    final Rect rect = Rect.fromLTWH(
      food!.x * cellWidth + cellWidth * 0.15,
      food!.y * cellHeight + cellHeight * 0.15,
      cellWidth * 0.7,
      cellHeight * 0.7,
    );
    canvas.drawOval(rect, foodPaint);
  }

  void _drawOverlay(Canvas canvas, Size size) {
    final Paint overlayPaint = Paint()..color = Colors.black.withOpacity(0.35);
    canvas.drawRect(Offset.zero & size, overlayPaint);

    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: isGameOver ? 'Game Over' : 'Paused',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.8);

    final Offset textOffset = Offset(
      (size.width - textPainter.width) / 2,
      (size.height - textPainter.height) / 2,
    );
    textPainter.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(covariant SnakeBoardPainter oldDelegate) {
    return oldDelegate.snake != snake ||
        oldDelegate.food != food ||
        oldDelegate.isGameOver != isGameOver ||
        oldDelegate.isRunning != isRunning;
  }
}

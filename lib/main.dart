import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const SnakeGameApp());
}

class SnakeGameApp extends StatelessWidget {
  const SnakeGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Snake Game',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.greenAccent),
        useMaterial3: true,
        textTheme: const TextTheme(
          headlineSmall: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      home: const SnakeGameScreen(),
    );
  }
}

class SnakeGameScreen extends StatefulWidget {
  const SnakeGameScreen({super.key});

  @override
  State<SnakeGameScreen> createState() => _SnakeGameScreenState();
}

enum Direction { up, down, left, right }

class _SnakeGameScreenState extends State<SnakeGameScreen> {
  static const int _rows = 20;
  static const int _columns = 26;
  static const Duration _tickRate = Duration(milliseconds: 120);

  final FocusNode _focusNode = FocusNode();
  final Random _random = Random();

  late List<Point<int>> _snake;
  late Point<int> _food;
  Direction _direction = Direction.right;
  Direction _pendingDirection = Direction.right;
  Timer? _timer;
  bool _isRunning = false;
  bool _isGameOver = false;
  int _score = 0;
  int _highScore = 0;

  @override
  void initState() {
    super.initState();
    _resetGame();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _resetGame() {
    _snake = [
      const Point(5, 10),
      const Point(4, 10),
      const Point(3, 10),
    ];
    _direction = Direction.right;
    _pendingDirection = Direction.right;
    _score = 0;
    _isGameOver = false;
    _spawnFood();
    _restartTimer();
    _isRunning = true;
    setState(() {});
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_tickRate, (_) => _tick());
  }

  void _spawnFood() {
    final occupied = _snake.toSet();
    Point<int> food;
    do {
      food = Point(_random.nextInt(_columns), _random.nextInt(_rows));
    } while (occupied.contains(food));
    _food = food;
  }

  void _tick() {
    if (!_isRunning || _isGameOver) return;

    setState(() {
      _direction = _pendingDirection;
      final nextHead = _nextHeadPosition();

      final collidedWithWall = nextHead.x < 0 ||
          nextHead.y < 0 ||
          nextHead.x >= _columns ||
          nextHead.y >= _rows;
      final collidedWithSelf = _snake.contains(nextHead);

      if (collidedWithWall || collidedWithSelf) {
        _handleGameOver();
        return;
      }

      _snake.insert(0, nextHead);

      if (nextHead == _food) {
        _score += 10;
        if (_score > _highScore) {
          _highScore = _score;
        }
        _spawnFood();
      } else {
        _snake.removeLast();
      }
    });
  }

  void _handleGameOver() {
    _isGameOver = true;
    _isRunning = false;
    _timer?.cancel();
  }

  void _togglePause() {
    if (_isGameOver) return;

    setState(() {
      if (_isRunning) {
        _timer?.cancel();
      } else {
        _restartTimer();
      }
      _isRunning = !_isRunning;
    });
  }

  void _updateDirection(Direction newDirection) {
    if (_isOppositeDirection(_direction, newDirection)) {
      return;
    }
    _pendingDirection = newDirection;
  }

  bool _isOppositeDirection(Direction a, Direction b) {
    return (a == Direction.up && b == Direction.down) ||
        (a == Direction.down && b == Direction.up) ||
        (a == Direction.left && b == Direction.right) ||
        (a == Direction.right && b == Direction.left);
  }

  Point<int> _nextHeadPosition() {
    final head = _snake.first;
    switch (_direction) {
      case Direction.up:
        return Point(head.x, head.y - 1);
      case Direction.down:
        return Point(head.x, head.y + 1);
      case Direction.left:
        return Point(head.x - 1, head.y);
      case Direction.right:
        return Point(head.x + 1, head.y);
    }
  }

  KeyEventResult _handleKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      _updateDirection(Direction.up);
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyS) {
      _updateDirection(Direction.down);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyA) {
      _updateDirection(Direction.left);
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      _updateDirection(Direction.right);
    } else if (key == LogicalKeyboardKey.space) {
      _togglePause();
    } else if (key == LogicalKeyboardKey.enter && _isGameOver) {
      _resetGame();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKey: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.grey.shade900,
        appBar: AppBar(
          title: const Text('Snake'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: _isRunning ? 'Pause (Space)' : 'Play (Space)',
              icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
              onPressed: _isGameOver ? null : _togglePause,
            ),
            IconButton(
              tooltip: 'Restart',
              icon: const Icon(Icons.refresh),
              onPressed: _resetGame,
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final boardSize = min(constraints.maxWidth, constraints.maxHeight);
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ScoreBoard(score: _score, highScore: _highScore),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: boardSize,
                    height: boardSize * (_rows / _columns),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.greenAccent.withOpacity(0.25),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: SnakeBoard(
                          rows: _rows,
                          columns: _columns,
                          snake: List<Point<int>>.unmodifiable(_snake),
                          food: _food,
                          isGameOver: _isGameOver,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ControlPanel(
                    isRunning: _isRunning,
                    isGameOver: _isGameOver,
                    onPausePressed: _togglePause,
                    onRestartPressed: _resetGame,
                    onDirectionSelected: _updateDirection,
                  ),
                  if (_isGameOver) const SizedBox(height: 12),
                  if (_isGameOver)
                    const Text(
                      'Game Over! Press Enter or Restart.',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class SnakeBoard extends StatelessWidget {
  const SnakeBoard({
    super.key,
    required this.rows,
    required this.columns,
    required this.snake,
    required this.food,
    required this.isGameOver,
  });

  final int rows;
  final int columns;
  final List<Point<int>> snake;
  final Point<int> food;
  final bool isGameOver;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          colors: [
            Colors.grey.shade900,
            Colors.grey.shade800,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: CustomPaint(
        painter: SnakeBoardPainter(
          rows: rows,
          columns: columns,
          snake: snake,
          food: food,
          isGameOver: isGameOver,
        ),
      ),
    );
  }
}

class SnakeBoardPainter extends CustomPainter {
  SnakeBoardPainter({
    required this.rows,
    required this.columns,
    required this.snake,
    required this.food,
    required this.isGameOver,
  });

  final int rows;
  final int columns;
  final List<Point<int>> snake;
  final Point<int> food;
  final bool isGameOver;

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = Size(size.width / columns, size.height / rows);
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.greenAccent.withOpacity(0.35)
      ..strokeWidth = 1;
    final snakePaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill;
    final snakeHeadPaint = Paint()
      ..color = Colors.limeAccent
      ..style = PaintingStyle.fill;
    final foodPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;

    // Draw grid lines lightly for better spatial awareness.
    for (var c = 0; c <= columns; c += 1) {
      final x = c * cellSize.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), borderPaint);
    }
    for (var r = 0; r <= rows; r += 1) {
      final y = r * cellSize.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), borderPaint);
    }

    // Draw snake body.
    for (var i = snake.length - 1; i >= 0; i--) {
      final segment = snake[i];
      final rect = Rect.fromLTWH(
        segment.x * cellSize.width + 1.5,
        segment.y * cellSize.height + 1.5,
        cellSize.width - 3,
        cellSize.height - 3,
      );
      final paint = i == 0 ? snakeHeadPaint : snakePaint;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        paint,
      );
    }

    // Draw food.
    final foodRect = Rect.fromLTWH(
      food.x * cellSize.width + 4,
      food.y * cellSize.height + 4,
      cellSize.width - 8,
      cellSize.height - 8,
    );
    canvas.drawOval(foodRect, foodPaint);

    if (isGameOver) {
      final overlayPaint = Paint()
        ..color = Colors.black.withOpacity(0.45)
        ..style = PaintingStyle.fill;
      canvas.drawRect(Offset.zero & size, overlayPaint);
    }
  }

  @override
  bool shouldRepaint(covariant SnakeBoardPainter oldDelegate) {
    return !listEquals(oldDelegate.snake, snake) ||
        oldDelegate.food != food ||
        oldDelegate.isGameOver != isGameOver;
  }
}

class _ScoreBoard extends StatelessWidget {
  const _ScoreBoard({
    required this.score,
    required this.highScore,
  });

  final int score;
  final int highScore;

  @override
  Widget build(BuildContext context) {
    final textStyle =
        Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ScoreBadge(label: 'Score', value: score, style: textStyle),
        const SizedBox(width: 16),
        _ScoreBadge(label: 'Best', value: highScore, style: textStyle),
      ],
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({
    required this.label,
    required this.value,
    required this.style,
  });

  final String label;
  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.shade800.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 12,
                  letterSpacing: 1.5,
                )),
            const SizedBox(height: 6),
            Text(
              value.toString().padLeft(3, '0'),
              style: style,
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.isRunning,
    required this.isGameOver,
    required this.onPausePressed,
    required this.onRestartPressed,
    required this.onDirectionSelected,
  });

  final bool isRunning;
  final bool isGameOver;
  final VoidCallback onPausePressed;
  final VoidCallback onRestartPressed;
  final void Function(Direction direction) onDirectionSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.tonalIcon(
              onPressed: isGameOver ? null : () => onDirectionSelected(Direction.up),
              icon: const Icon(Icons.keyboard_arrow_up),
              label: const Text('Up'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.tonalIcon(
              onPressed:
                  isGameOver ? null : () => onDirectionSelected(Direction.left),
              icon: const Icon(Icons.keyboard_arrow_left),
              label: const Text('Left'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: onPausePressed,
              icon: Icon(isRunning ? Icons.pause : Icons.play_arrow),
              label: Text(isRunning ? 'Pause' : 'Resume'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed:
                  isGameOver ? null : () => onDirectionSelected(Direction.right),
              icon: const Icon(Icons.keyboard_arrow_right),
              label: const Text('Right'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.tonalIcon(
              onPressed: isGameOver ? null : () => onDirectionSelected(Direction.down),
              icon: const Icon(Icons.keyboard_arrow_down),
              label: const Text('Down'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onRestartPressed,
              icon: const Icon(Icons.refresh),
              label: const Text('Restart'),
            ),
          ],
        ),
      ],
    );
  }
}

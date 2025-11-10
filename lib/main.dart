import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';

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
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const SnakeGameScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SnakeGameScreen extends StatefulWidget {
  const SnakeGameScreen({super.key});

  @override
  State<SnakeGameScreen> createState() => _SnakeGameScreenState();
}

class _SnakeGameScreenState extends State<SnakeGameScreen> {
  static const int gridSize = 20;
  static const int cellSize = 25;
  static const Duration gameSpeed = Duration(milliseconds: 150);

  List<Point<int>> snake = [
    Point(10, 10),
    Point(10, 11),
    Point(10, 12),
  ];
  Point<int>? food;
  Direction direction = Direction.up;
  Direction nextDirection = Direction.up;
  bool isGameOver = false;
  bool isPaused = false;
  int score = 0;
  Timer? gameTimer;

  @override
  void initState() {
    super.initState();
    _generateFood();
    _startGame();
  }

  void _startGame() {
    gameTimer = Timer.periodic(gameSpeed, (timer) {
      if (!isPaused && !isGameOver) {
        setState(() {
          _moveSnake();
        });
      }
    });
  }

  void _generateFood() {
    final random = Random();
    Point<int> newFood;
    do {
      newFood = Point(
        random.nextInt(gridSize),
        random.nextInt(gridSize),
      );
    } while (snake.contains(newFood));
    food = newFood;
  }

  void _moveSnake() {
    direction = nextDirection;
    final head = snake.first;
    Point<int> newHead;

    switch (direction) {
      case Direction.up:
        newHead = Point(head.x, head.y - 1);
        break;
      case Direction.down:
        newHead = Point(head.x, head.y + 1);
        break;
      case Direction.left:
        newHead = Point(head.x - 1, head.y);
        break;
      case Direction.right:
        newHead = Point(head.x + 1, head.y);
        break;
    }

    // Check wall collision
    if (newHead.x < 0 ||
        newHead.x >= gridSize ||
        newHead.y < 0 ||
        newHead.y >= gridSize) {
      _gameOver();
      return;
    }

    // Check self collision
    if (snake.contains(newHead)) {
      _gameOver();
      return;
    }

    snake.insert(0, newHead);

    // Check food collision
    if (newHead == food) {
      score += 10;
      _generateFood();
    } else {
      snake.removeLast();
    }
  }

  void _gameOver() {
    isGameOver = true;
    gameTimer?.cancel();
  }

  void _resetGame() {
    setState(() {
      snake = [
        Point(10, 10),
        Point(10, 11),
        Point(10, 12),
      ];
      direction = Direction.up;
      nextDirection = Direction.up;
      isGameOver = false;
      isPaused = false;
      score = 0;
      _generateFood();
      gameTimer?.cancel();
      _startGame();
    });
  }

  void _togglePause() {
    setState(() {
      isPaused = !isPaused;
    });
  }

  void _handleKeyPress(KeyEvent event) {
    if (isGameOver) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
        _resetGame();
      }
      return;
    }

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
          direction != Direction.down) {
        nextDirection = Direction.up;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
          direction != Direction.up) {
        nextDirection = Direction.down;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
          direction != Direction.right) {
        nextDirection = Direction.left;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
          direction != Direction.left) {
        nextDirection = Direction.right;
      } else if (event.logicalKey == LogicalKeyboardKey.space) {
        _togglePause();
      }
    }
  }

  @override
  void dispose() {
    gameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: _handleKeyPress,
      child: Scaffold(
        backgroundColor: Colors.black87,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Snake Game',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade400,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Score: $score',
                style: const TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green.shade700, width: 3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: CustomPaint(
                  size: Size(gridSize * cellSize.toDouble(),
                      gridSize * cellSize.toDouble()),
                  painter: SnakeGamePainter(
                    snake: snake,
                    food: food,
                    gridSize: gridSize,
                    cellSize: cellSize,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (isGameOver)
                Column(
                  children: [
                    Text(
                      'Game Over!',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade400,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Press SPACE to restart',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                )
              else if (isPaused)
                const Text(
                  'Paused - Press SPACE to resume',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white70,
                  ),
                )
              else
                const Text(
                  'Use Arrow Keys to play | SPACE to pause',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum Direction { up, down, left, right }

class SnakeGamePainter extends CustomPainter {
  final List<Point<int>> snake;
  final Point<int>? food;
  final int gridSize;
  final int cellSize;

  SnakeGamePainter({
    required this.snake,
    required this.food,
    required this.gridSize,
    required this.cellSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background grid
    final gridPaint = Paint()
      ..color = Colors.grey.shade900
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      gridPaint,
    );

    // Draw grid lines
    final linePaint = Paint()
      ..color = Colors.grey.shade800
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (int i = 0; i <= gridSize; i++) {
      canvas.drawLine(
        Offset(i * cellSize.toDouble(), 0),
        Offset(i * cellSize.toDouble(), size.height),
        linePaint,
      );
      canvas.drawLine(
        Offset(0, i * cellSize.toDouble()),
        Offset(size.width, i * cellSize.toDouble()),
        linePaint,
      );
    }

    // Draw food
    if (food != null) {
      final foodPaint = Paint()
        ..color = Colors.red.shade400
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(
          food!.x * cellSize + cellSize / 2,
          food!.y * cellSize + cellSize / 2,
        ),
        cellSize / 2 - 2,
        foodPaint,
      );
    }

    // Draw snake
    for (int i = 0; i < snake.length; i++) {
      final point = snake[i];
      final snakePaint = Paint()
        ..color = i == 0 ? Colors.green.shade400 : Colors.green.shade600
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            point.x * cellSize + 1,
            point.y * cellSize + 1,
            cellSize - 2,
            cellSize - 2,
          ),
          const Radius.circular(4),
        ),
        snakePaint,
      );
    }
  }

  @override
  bool shouldRepaint(SnakeGamePainter oldDelegate) {
    return snake != oldDelegate.snake || food != oldDelegate.food;
  }
}

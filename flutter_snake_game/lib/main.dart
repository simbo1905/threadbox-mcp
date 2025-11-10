import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SnakeGameApp());
}

class SnakeGameApp extends StatelessWidget {
  const SnakeGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF80FF6F),
        secondary: Color(0xFFFF6F61),
        surface: Color(0xFF1C1D20),
        background: Color(0xFF121212),
      ),
    );

    return MaterialApp(
      title: 'Flutter Snake (Linux)',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: const Color(0xFF0E0E11),
        appBarTheme: baseTheme.appBarTheme.copyWith(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      home: const SnakeGamePage(),
    );
  }
}

class SnakeGamePage extends StatefulWidget {
  const SnakeGamePage({super.key});

  @override
  State<SnakeGamePage> createState() => _SnakeGamePageState();
}

enum Direction { up, down, left, right }

enum GameState { ready, playing, paused, gameOver }

class _SnakeGamePageState extends State<SnakeGamePage> {
  static const int _rows = 22;
  static const int _columns = 22;
  static const int _initialSnakeLength = 4;
  static const Duration _baseTick = Duration(milliseconds: 180);
  static const Duration _minTick = Duration(milliseconds: 70);

  final FocusNode _focusNode = FocusNode(debugLabel: 'snake_game_focus');
  final Random _random = Random();

  late List<Point<int>> _snake;
  Point<int>? _food;
  Direction _direction = Direction.right;
  Direction? _queuedDirection;
  GameState _gameState = GameState.ready;
  Timer? _timer;
  Duration _activeTickDuration = _baseTick;

  int _score = 0;
  int _highScore = 0;

  int get _speedLevel => 1 + (_score ~/ 5);

  Duration get _currentTickDuration {
    final reduction = (_speedLevel - 1) * 14;
    final targetMs =
        (_baseTick.inMilliseconds - reduction).clamp(_minTick.inMilliseconds, _baseTick.inMilliseconds);
    return Duration(milliseconds: targetMs);
  }

  @override
  void initState() {
    super.initState();
    _resetGameData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _resetGameData() {
    final startX = _columns ~/ 2 - (_initialSnakeLength ~/ 2);
    final startY = _rows ~/ 2;

    _direction = Direction.right;
    _queuedDirection = null;
    _snake = List<Point<int>>.generate(
      _initialSnakeLength,
      (index) => Point(startX + index, startY),
    );
    _score = 0;
    _food = _randomFoodPosition();
  }

  void _startGame() {
    _timer?.cancel();
    setState(() {
      _resetGameData();
      _gameState = GameState.playing;
    });
    _scheduleTick();
    _focusNode.requestFocus();
  }

  void _pauseGame() {
    if (_gameState != GameState.playing) {
      return;
    }
    _timer?.cancel();
    setState(() {
      _gameState = GameState.paused;
    });
  }

  void _resumeGame() {
    if (_gameState != GameState.paused) {
      return;
    }
    setState(() {
      _gameState = GameState.playing;
    });
    _scheduleTick();
    _focusNode.requestFocus();
  }

  void _scheduleTick() {
    _timer?.cancel();
    _activeTickDuration = _currentTickDuration;
    _timer = Timer.periodic(_activeTickDuration, (_) => _tick());
  }

  void _tick() {
    if (!mounted || _gameState != GameState.playing) {
      return;
    }

    setState(() {
      final Direction nextDirection;
      if (_queuedDirection != null &&
          !_isOppositeDirection(_queuedDirection!, _direction)) {
        nextDirection = _queuedDirection!;
      } else {
        nextDirection = _direction;
      }
      _queuedDirection = null;
      _direction = nextDirection;

      final currentHead = _snake.last;
      final newHead = _stepForward(currentHead, _direction);
      final bool hitWall =
          newHead.x < 0 || newHead.y < 0 || newHead.x >= _columns || newHead.y >= _rows;

      final bool willGrow = _food != null && newHead == _food;
      final Iterable<Point<int>> collisionBody =
          willGrow ? _snake : _snake.skip(1);
      final bool hitSelf = collisionBody.contains(newHead);

      if (hitWall || hitSelf) {
        _timer?.cancel();
        _gameState = GameState.gameOver;
        if (_score > _highScore) {
          _highScore = _score;
        }
        return;
      }

      _snake = List<Point<int>>.from(_snake)..add(newHead);

      if (willGrow) {
        _score += 1;
        if (_score > _highScore) {
          _highScore = _score;
        }
        if (_snake.length == _rows * _columns) {
          // Player wins by filling the board.
          _timer?.cancel();
          _gameState = GameState.gameOver;
          return;
        }
        _food = _randomFoodPosition();
        _maybeAdjustGameSpeed();
      } else {
        _snake.removeAt(0);
      }
    });
  }

  void _maybeAdjustGameSpeed() {
    final newDuration = _currentTickDuration;
    if (newDuration == _activeTickDuration || _gameState != GameState.playing) {
      return;
    }
    _scheduleTick();
  }

  void _queueDirection(Direction direction) {
    if (_gameState != GameState.playing) {
      return;
    }
    if (_snake.length > 1 && _isOppositeDirection(direction, _direction)) {
      return;
    }
    _queuedDirection = direction;
  }

  bool _isOppositeDirection(Direction a, Direction b) {
    return (a == Direction.up && b == Direction.down) ||
        (a == Direction.down && b == Direction.up) ||
        (a == Direction.left && b == Direction.right) ||
        (a == Direction.right && b == Direction.left);
  }

  Point<int> _stepForward(Point<int> head, Direction direction) {
    switch (direction) {
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

  Point<int>? _randomFoodPosition() {
    final occupied = _snake.toSet();
    final available = <Point<int>>[];

    for (var y = 0; y < _rows; y++) {
      for (var x = 0; x < _columns; x++) {
        final candidate = Point<int>(x, y);
        if (!occupied.contains(candidate)) {
          available.add(candidate);
        }
      }
    }

    if (available.isEmpty) {
      return null;
    }
    return available[_random.nextInt(available.length)];
  }

  void _handleKeyEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent || event.repeat) {
      return;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      _queueDirection(Direction.up);
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyS) {
      _queueDirection(Direction.down);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyA) {
      _queueDirection(Direction.left);
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      _queueDirection(Direction.right);
    } else if (key == LogicalKeyboardKey.space) {
      if (_gameState == GameState.playing) {
        _pauseGame();
      } else if (_gameState == GameState.paused) {
        _resumeGame();
      } else {
        _startGame();
      }
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_gameState == GameState.gameOver || _gameState == GameState.ready) {
        _startGame();
      }
    } else if (key == LogicalKeyboardKey.escape) {
      if (_gameState == GameState.playing) {
        _pauseGame();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Snake'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildScoreboard(context),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final boardSize = min(constraints.maxWidth, constraints.maxHeight);
                    return Center(
                      child: SizedBox(
                        width: boardSize,
                        height: boardSize,
                        child: RawKeyboardListener(
                          focusNode: _focusNode,
                          autofocus: true,
                          onKey: _handleKeyEvent,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _focusNode.requestFocus(),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              onEnter: (_) => _focusNode.requestFocus(),
                              child: Stack(
                                children: [
                                  _buildGameBoard(),
                                  if (_gameState != GameState.playing)
                                    _buildOverlay(context),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreboard(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [
        _ScoreTile(label: 'Score', value: _score.toString()),
        _ScoreTile(label: 'Best', value: _highScore.toString()),
        _ScoreTile(label: 'Speed', value: 'x$_speedLevel'),
      ],
    );
  }

  Widget _buildGameBoard() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF181A1E),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF2A2C33), width: 3),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: CustomPaint(
          painter: SnakePainter(
            snake: _snake,
            food: _food,
            rows: _rows,
            columns: _columns,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    late final String title;
    late final String description;
    late final IconData icon;

    switch (_gameState) {
      case GameState.ready:
        title = 'Ready to slither?';
        description = 'Press Enter or Start to play. Use Arrow Keys or WASD to move.';
        icon = Icons.play_circle_fill;
        break;
      case GameState.paused:
        title = 'Paused';
        description = 'Press Space or Resume to keep going.';
        icon = Icons.pause_circle_filled;
        break;
      case GameState.gameOver:
        title = 'Game Over';
        description =
            'Score: $_score\nBest: $_highScore\nPress Enter or Restart to try again.';
        icon = Icons.sentiment_dissatisfied;
        break;
      case GameState.playing:
        return const SizedBox.shrink();
    }

    return Container(
      color: Colors.black.withOpacity(0.55),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            color: const Color(0xFF1F2024).withOpacity(0.9),
            elevation: 12,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (_gameState == GameState.gameOver) ...[
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _startGame,
                      child: const Text('Play Again'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final bool isPlaying = _gameState == GameState.playing;
    final bool isPaused = _gameState == GameState.paused;

    final String primaryLabel;
    final IconData primaryIcon;
    final VoidCallback primaryAction;

    if (isPlaying) {
      primaryLabel = 'Pause';
      primaryIcon = Icons.pause;
      primaryAction = _pauseGame;
    } else if (isPaused) {
      primaryLabel = 'Resume';
      primaryIcon = Icons.play_arrow;
      primaryAction = _resumeGame;
    } else {
      primaryLabel = 'Start';
      primaryIcon = Icons.play_circle_fill;
      primaryAction = _startGame;
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: primaryAction,
          icon: Icon(primaryIcon),
          label: Text(primaryLabel),
        ),
        FilledButton.tonalIcon(
          onPressed: _startGame,
          icon: const Icon(Icons.refresh),
          label: const Text('Restart'),
        ),
        FilledButton.tonalIcon(
          onPressed: isPlaying ? _pauseGame : (isPaused ? _resumeGame : null),
          icon: const Icon(Icons.space_bar),
          label: const Text('Pause/Resume (Space)'),
        ),
      ],
    );
  }
}

class _ScoreTile extends StatelessWidget {
  const _ScoreTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1B1F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF303139)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: textTheme.labelLarge?.copyWith(
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class SnakePainter extends CustomPainter {
  SnakePainter({
    required this.snake,
    required this.food,
    required this.rows,
    required this.columns,
    this.gridLineColor = const Color(0xFF2D2F36),
    this.primaryCellColor = const Color(0xFF202226),
    this.secondaryCellColor = const Color(0xFF181A1F),
    this.snakeBodyColor = const Color(0xFF80FF6F),
    this.snakeHeadColor = const Color(0xFFB6FF93),
    this.foodColor = const Color(0xFFFF6F61),
  });

  final List<Point<int>> snake;
  final Point<int>? food;
  final int rows;
  final int columns;

  final Color gridLineColor;
  final Color primaryCellColor;
  final Color secondaryCellColor;
  final Color snakeBodyColor;
  final Color snakeHeadColor;
  final Color foodColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / columns;
    final cellHeight = size.height / rows;

    // Draw checkerboard background.
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        final rect = Rect.fromLTWH(
          col * cellWidth,
          row * cellHeight,
          cellWidth,
          cellHeight,
        );
        canvas.drawRect(
          rect,
          Paint()
            ..color = ((row + col) % 2 == 0)
                ? primaryCellColor
                : secondaryCellColor,
        );
      }
    }

    // Draw grid lines.
    final gridPaint = Paint()
      ..color = gridLineColor.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var col = 1; col < columns; col++) {
      final x = col * cellWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var row = 1; row < rows; row++) {
      final y = row * cellHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw snake body and head.
    final radius = Radius.circular(min(cellWidth, cellHeight) * 0.35);
    final headIndex = snake.isEmpty ? -1 : snake.length - 1;
    for (var i = 0; i < snake.length; i++) {
      final segment = snake[i];
      final rect = Rect.fromLTWH(
        segment.x * cellWidth + cellWidth * 0.1,
        segment.y * cellHeight + cellHeight * 0.1,
        cellWidth * 0.8,
        cellHeight * 0.8,
      );
      final paint = Paint()
        ..color = i == headIndex ? snakeHeadColor : snakeBodyColor;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
    }

    // Draw food.
    if (food != null) {
      final foodRect = Rect.fromLTWH(
        food!.x * cellWidth + cellWidth * 0.22,
        food!.y * cellHeight + cellHeight * 0.22,
        cellWidth * 0.56,
        cellHeight * 0.56,
      );
      final foodPaint = Paint()
        ..color = foodColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawOval(foodRect, foodPaint);
    }
  }

  @override
  bool shouldRepaint(covariant SnakePainter oldDelegate) {
    return oldDelegate.food != food ||
        !listEquals(oldDelegate.snake, snake) ||
        oldDelegate.rows != rows ||
        oldDelegate.columns != columns;
  }
}

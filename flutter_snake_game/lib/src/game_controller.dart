import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

enum SnakeDirection { up, down, left, right }

class SnakeGameController extends ChangeNotifier {
  SnakeGameController({
    this.rows = 20,
    this.columns = 20,
    this.tickSpeed = const Duration(milliseconds: 160),
  }) : assert(rows > 4 && columns > 4, 'Board must be at least 5x5') {
    _resetSnake();
    _spawnFood();
  }

  final int rows;
  final int columns;
  final Duration tickSpeed;

  final Random _random = Random();

  Timer? _timer;
  List<Point<int>> _snake = <Point<int>>[];
  SnakeDirection _direction = SnakeDirection.right;
  SnakeDirection? _queuedDirection;
  Point<int>? _food;
  bool _isGameOver = false;
  bool _isRunning = false;
  int _score = 0;
  int _highScore = 0;
  int _stepsSinceLastFood = 0;

  List<Point<int>> get snake => List<Point<int>>.unmodifiable(_snake);
  Point<int>? get food => _food;
  bool get isGameOver => _isGameOver;
  bool get isRunning => _isRunning;
  int get score => _score;
  int get highScore => _highScore;

  double get progressToGrowth =>
      (_snake.length / (rows * columns)).clamp(0, 1).toDouble();

  void start() {
    if (_isRunning) {
      return;
    }
    if (_isGameOver) {
      reset();
    }
    _isRunning = true;
    _timer?.cancel();
    _timer = Timer.periodic(tickSpeed, (_) => _tick());
    notifyListeners();
  }

  void pause() {
    if (!_isRunning) {
      return;
    }
    _timer?.cancel();
    _isRunning = false;
    notifyListeners();
  }

  void toggle() {
    if (_isRunning) {
      pause();
    } else {
      start();
    }
  }

  void reset() {
    _timer?.cancel();
    _isRunning = false;
    _isGameOver = false;
    _score = 0;
    _stepsSinceLastFood = 0;
    _queuedDirection = null;

    _resetSnake();
    _spawnFood();
    notifyListeners();
  }

  void disposeController() {
    _timer?.cancel();
    _timer = null;
  }

  void queueDirection(SnakeDirection direction) {
    if (_isGameOver) {
      return;
    }

    // Prevent direct reversal and redundant inputs.
    if (_isOpposite(direction, _direction) || direction == _direction) {
      return;
    }
    _queuedDirection = direction;
  }

  void _tick() {
    if (_isGameOver) {
      pause();
      return;
    }

    if (_queuedDirection != null) {
      if (!_isOpposite(_queuedDirection!, _direction)) {
        _direction = _queuedDirection!;
      }
      _queuedDirection = null;
    }

    final Point<int> newHead = _nextHeadPosition();

    if (_hitsWall(newHead) || _hitsSelf(newHead)) {
      _onGameOver();
      return;
    }

    _snake = <Point<int>>[newHead, ..._snake];

    if (_food != null && newHead == _food) {
      _score += 10;
      _highScore = max(_highScore, _score);
      _spawnFood();
      _stepsSinceLastFood = 0;
    } else {
      _snake.removeLast();
      _stepsSinceLastFood++;

      // Prevent indefinite loops when snake fills the board.
      if (_stepsSinceLastFood > rows * columns) {
        _onGameOver();
        return;
      }
    }

    notifyListeners();
  }

  @visibleForTesting
  void step() {
    _tick();
  }

  @visibleForTesting
  set debugFood(Point<int>? value) {
    _food = value;
  }

  void _onGameOver() {
    _isGameOver = true;
    _isRunning = false;
    _timer?.cancel();
    notifyListeners();
  }

  void _spawnFood() {
    final Set<Point<int>> occupied = _snake.toSet();
    final List<Point<int>> available = <Point<int>>[];
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        final Point<int> candidate = Point<int>(col, row);
        if (!occupied.contains(candidate)) {
          available.add(candidate);
        }
      }
    }

    if (available.isEmpty) {
      _food = null;
      _onGameOver();
      return;
    }

    _food = available[_random.nextInt(available.length)];
  }

  void _resetSnake() {
    final int midRow = rows ~/ 2;
    final int midCol = columns ~/ 2;
    _snake = <Point<int>>[
      Point<int>(midCol, midRow),
      Point<int>(midCol - 1, midRow),
      Point<int>(midCol - 2, midRow),
    ];
    _direction = SnakeDirection.right;
  }

  bool _hitsWall(Point<int> position) {
    return position.x < 0 ||
        position.y < 0 ||
        position.x >= columns ||
        position.y >= rows;
  }

  bool _hitsSelf(Point<int> position) {
    // Skip the tail if it will move away during this tick.
    final Iterable<Point<int>> body = _snake.sublist(0, _snake.length - 1);
    return body.contains(position);
  }

  Point<int> _nextHeadPosition() {
    final Point<int> currentHead = _snake.first;
    switch (_direction) {
      case SnakeDirection.up:
        return Point<int>(currentHead.x, currentHead.y - 1);
      case SnakeDirection.down:
        return Point<int>(currentHead.x, currentHead.y + 1);
      case SnakeDirection.left:
        return Point<int>(currentHead.x - 1, currentHead.y);
      case SnakeDirection.right:
        return Point<int>(currentHead.x + 1, currentHead.y);
    }
  }

  bool _isOpposite(SnakeDirection a, SnakeDirection b) {
    return (a == SnakeDirection.up && b == SnakeDirection.down) ||
        (a == SnakeDirection.down && b == SnakeDirection.up) ||
        (a == SnakeDirection.left && b == SnakeDirection.right) ||
        (a == SnakeDirection.right && b == SnakeDirection.left);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

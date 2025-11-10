import 'dart:async';
import 'dart:math';
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const SnakeGame(),
    );
  }
}

enum Direction { up, down, left, right }

class SnakeGame extends StatefulWidget {
  const SnakeGame({super.key});

  @override
  State<SnakeGame> createState() => _SnakeGameState();
}

class _SnakeGameState extends State<SnakeGame> {
  static const int gridSize = 20;
  static const int initialSpeed = 300; // milliseconds
  
  List<Point<int>> snake = [Point(10, 10)];
  Point<int> food = Point(15, 15);
  Direction direction = Direction.right;
  Direction nextDirection = Direction.right;
  bool isPlaying = false;
  bool isGameOver = false;
  int score = 0;
  Timer? gameTimer;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    gameTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void startGame() {
    setState(() {
      snake = [Point(10, 10)];
      direction = Direction.right;
      nextDirection = Direction.right;
      isPlaying = true;
      isGameOver = false;
      score = 0;
      generateFood();
    });
    
    gameTimer?.cancel();
    gameTimer = Timer.periodic(
      Duration(milliseconds: initialSpeed),
      (timer) => updateGame(),
    );
  }

  void generateFood() {
    final random = Random();
    Point<int> newFood;
    do {
      newFood = Point(random.nextInt(gridSize), random.nextInt(gridSize));
    } while (snake.contains(newFood));
    
    setState(() {
      food = newFood;
    });
  }

  void updateGame() {
    if (!isPlaying || isGameOver) return;

    direction = nextDirection;
    
    Point<int> newHead;
    switch (direction) {
      case Direction.up:
        newHead = Point(snake.first.x, snake.first.y - 1);
        break;
      case Direction.down:
        newHead = Point(snake.first.x, snake.first.y + 1);
        break;
      case Direction.left:
        newHead = Point(snake.first.x - 1, snake.first.y);
        break;
      case Direction.right:
        newHead = Point(snake.first.x + 1, snake.first.y);
        break;
    }

    // Check collision with walls
    if (newHead.x < 0 || newHead.x >= gridSize || 
        newHead.y < 0 || newHead.y >= gridSize) {
      gameOver();
      return;
    }

    // Check collision with self
    if (snake.contains(newHead)) {
      gameOver();
      return;
    }

    setState(() {
      snake.insert(0, newHead);

      // Check if food is eaten
      if (newHead == food) {
        score += 10;
        generateFood();
      } else {
        snake.removeLast();
      }
    });
  }

  void gameOver() {
    setState(() {
      isGameOver = true;
      isPlaying = false;
    });
    gameTimer?.cancel();
  }

  void changeDirection(Direction newDirection) {
    // Prevent 180-degree turns
    if (newDirection == Direction.up && direction != Direction.down) {
      nextDirection = newDirection;
    } else if (newDirection == Direction.down && direction != Direction.up) {
      nextDirection = newDirection;
    } else if (newDirection == Direction.left && direction != Direction.right) {
      nextDirection = newDirection;
    } else if (newDirection == Direction.right && direction != Direction.left) {
      nextDirection = newDirection;
    }
  }

  void handleKeyPress(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        changeDirection(Direction.up);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        changeDirection(Direction.down);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        changeDirection(Direction.left);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        changeDirection(Direction.right);
      } else if (event.logicalKey == LogicalKeyboardKey.space && !isPlaying) {
        startGame();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: _focusNode,
        onKeyEvent: handleKeyPress,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Score display
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  'Score: $score',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
              // Game grid
              Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 2),
                  color: Colors.grey[900],
                ),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: gridSize,
                  ),
                  itemCount: gridSize * gridSize,
                  itemBuilder: (context, index) {
                    final x = index % gridSize;
                    final y = index ~/ gridSize;
                    final point = Point(x, y);

                    bool isSnake = snake.contains(point);
                    bool isHead = snake.first == point;
                    bool isFood = food == point;

                    Color cellColor = Colors.grey[900]!;
                    if (isFood) {
                      cellColor = Colors.red;
                    } else if (isHead) {
                      cellColor = Colors.lightGreen;
                    } else if (isSnake) {
                      cellColor = Colors.green;
                    }

                    return Container(
                      margin: const EdgeInsets.all(0.5),
                      decoration: BoxDecoration(
                        color: cellColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  },
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Game status and controls
              if (!isPlaying && !isGameOver)
                Column(
                  children: [
                    const Text(
                      'Press SPACE or click Start to begin',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: startGame,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 15,
                        ),
                      ),
                      child: const Text(
                        'Start Game',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
              
              if (isGameOver)
                Column(
                  children: [
                    const Text(
                      'Game Over!',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Final Score: $score',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: startGame,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 15,
                        ),
                      ),
                      child: const Text(
                        'Play Again',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
              
              const SizedBox(height: 30),
              
              // Arrow key controls for clarity
              if (isPlaying)
                Column(
                  children: [
                    const Text(
                      'Use Arrow Keys to control',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () => changeDirection(Direction.left),
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          iconSize: 40,
                        ),
                        Column(
                          children: [
                            IconButton(
                              onPressed: () => changeDirection(Direction.up),
                              icon: const Icon(Icons.arrow_upward, color: Colors.white),
                              iconSize: 40,
                            ),
                            IconButton(
                              onPressed: () => changeDirection(Direction.down),
                              icon: const Icon(Icons.arrow_downward, color: Colors.white),
                              iconSize: 40,
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => changeDirection(Direction.right),
                          icon: const Icon(Icons.arrow_forward, color: Colors.white),
                          iconSize: 40,
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

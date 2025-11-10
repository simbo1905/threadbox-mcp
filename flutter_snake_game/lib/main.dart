import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'src/game_controller.dart';
import 'src/snake_painter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SnakeGameApp());
}

class SnakeGameApp extends StatelessWidget {
  const SnakeGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Snake',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4CAF50),
          secondary: Color(0xFFFF7043),
          surface: Color(0xFF101215),
          background: Color(0xFF050505),
        ),
        canvasColor: const Color(0xFF050505),
        scaffoldBackgroundColor: const Color(0xFF050505),
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'RobotoMono'),
        useMaterial3: true,
      ),
      home: ChangeNotifierProvider(
        create: (_) => SnakeGameController(),
        child: const SnakeGameScreen(),
      ),
    );
  }
}

class SnakeGameScreen extends StatefulWidget {
  const SnakeGameScreen({super.key});

  @override
  State<SnakeGameScreen> createState() => _SnakeGameScreenState();
}

class _SnakeGameScreenState extends State<SnakeGameScreen> {
  final FocusNode _focusNode = FocusNode();
  SnakeGameController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= context.read<SnakeGameController>();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller?.disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SnakeGameController controller = context.watch<SnakeGameController>();

    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const SizedBox(height: 16),
            Text(
              'Flutter Snake',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
            ),
            const SizedBox(height: 24),
            _buildStats(controller),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Focus(
                  focusNode: _focusNode,
                  autofocus: true,
                  onKeyEvent: (FocusNode node, KeyEvent event) {
                    if (event is! KeyDownEvent) {
                      return KeyEventResult.ignored;
                    }
                    final LogicalKeyboardKey key = event.logicalKey;
                    if (key == LogicalKeyboardKey.arrowUp ||
                        key == LogicalKeyboardKey.keyW) {
                      controller.queueDirection(SnakeDirection.up);
                      return KeyEventResult.handled;
                    }
                    if (key == LogicalKeyboardKey.arrowDown ||
                        key == LogicalKeyboardKey.keyS) {
                      controller.queueDirection(SnakeDirection.down);
                      return KeyEventResult.handled;
                    }
                    if (key == LogicalKeyboardKey.arrowLeft ||
                        key == LogicalKeyboardKey.keyA) {
                      controller.queueDirection(SnakeDirection.left);
                      return KeyEventResult.handled;
                    }
                    if (key == LogicalKeyboardKey.arrowRight ||
                        key == LogicalKeyboardKey.keyD) {
                      controller.queueDirection(SnakeDirection.right);
                      return KeyEventResult.handled;
                    }
                    if (key == LogicalKeyboardKey.space) {
                      controller.toggle();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                        final double size =
                            min(constraints.maxWidth, constraints.maxHeight);
                        return SizedBox(
                          width: size,
                          height: size,
                          child: AnimatedBuilder(
                            animation: controller,
                            builder: (BuildContext context, _) {
                              return CustomPaint(
                                painter: SnakeBoardPainter(
                                  snake: controller.snake,
                                  food: controller.food,
                                  rows: controller.rows,
                                  columns: controller.columns,
                                  isGameOver: controller.isGameOver,
                                  isRunning: controller.isRunning,
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildControls(controller),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStats(SnakeGameController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          _StatTile(
            label: 'Score',
            value: controller.score.toString().padLeft(3, '0'),
          ),
          _StatTile(
            label: 'High Score',
            value: controller.highScore.toString().padLeft(3, '0'),
          ),
          _StatTile(
            label: 'Length',
            value: controller.snake.length.toString().padLeft(2, '0'),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(SnakeGameController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 16,
        children: <Widget>[
          ElevatedButton.icon(
            onPressed: controller.start,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
          ),
          ElevatedButton.icon(
            onPressed: controller.pause,
            icon: const Icon(Icons.pause),
            label: const Text('Pause'),
          ),
          ElevatedButton.icon(
            onPressed: controller.reset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161920),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            offset: Offset(0, 2),
            blurRadius: 6,
            color: Colors.black54,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white70,
                  letterSpacing: 1.1,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
          ),
        ],
      ),
    );
  }
}

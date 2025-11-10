# Snake Game - Flutter Linux

A classic Snake game built with Flutter for Linux.

## Features

- Classic snake gameplay
- Arrow key controls
- Score tracking
- Game over detection
- Smooth animations
- Modern UI with dark theme

## How to Play

1. **Start the game**: Click the "Start Game" button or press the SPACE bar
2. **Control the snake**: Use arrow keys (↑ ↓ ← →) to change direction
3. **Objective**: Eat the red food to grow longer and increase your score
4. **Avoid**: 
   - Hitting the walls
   - Hitting your own body

## Controls

- **Arrow Keys**: Control snake direction
- **Space Bar**: Start/Restart game
- **On-screen buttons**: Alternative touch controls (visible during gameplay)

## Running the Game

### From Source
```bash
cd /workspace/snake_game
flutter run -d linux
```

### From Build
The compiled executable is located at:
```bash
/workspace/snake_game/build/linux/x64/release/bundle/snake_game
```

To run the game:
```bash
cd /workspace/snake_game/build/linux/x64/release/bundle
./snake_game
```

## Building

To build the release version for Linux:
```bash
flutter build linux --release
```

## Requirements

- Flutter SDK (3.35.7 or later)
- Linux with GTK 3.0
- OpenGL support

## Game Mechanics

- **Grid Size**: 20x20
- **Starting Length**: 1 segment
- **Speed**: Fixed at 300ms per move
- **Score**: +10 points per food eaten
- **Food**: Spawns randomly on the grid after being eaten

## Development

The game is built using:
- **Flutter**: Cross-platform UI framework
- **Dart**: Programming language
- **GTK 3.0**: Linux windowing system

Main game logic is in `lib/main.dart` with these key components:
- `SnakeGame`: Main game widget
- `Direction`: Enum for snake movement
- Game loop using Timer for continuous updates
- Collision detection for walls and self
- Food generation algorithm

## License

MIT License - Feel free to use and modify!

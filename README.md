# Snake Game - Flutter

A classic Snake game built with Flutter for Linux desktop.

## Features

- Classic snake gameplay with arrow key controls
- Score tracking
- Pause/resume functionality (SPACE key)
- Game over detection with restart option
- Smooth animations and modern UI
- Dark theme with green snake and red food

## Prerequisites

- Flutter SDK (3.0.0 or higher)
- Linux desktop support enabled in Flutter

## Setup

1. Ensure Flutter is installed and Linux desktop support is enabled:
   ```bash
   flutter doctor
   flutter config --enable-linux-desktop
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Generate Linux platform files (if needed):
   ```bash
   flutter create --platforms=linux .
   ```

## Running the Game

Run the game on Linux:
```bash
flutter run -d linux
```

Or build a release version:
```bash
flutter build linux
```

The executable will be in `build/linux/x64/release/bundle/`.

## Controls

- **Arrow Keys**: Move the snake (Up, Down, Left, Right)
- **SPACE**: Pause/Resume the game
- **SPACE** (when game over): Restart the game

## Game Rules

- Control the snake to eat the red food
- Each food eaten increases your score by 10 points
- The snake grows longer with each food eaten
- Avoid hitting the walls or your own tail
- Game ends on collision

## Project Structure

- `lib/main.dart`: Main game logic and UI implementation
- `pubspec.yaml`: Flutter project configuration

## Development

### Running Tests

```bash
flutter test
```

### Linting

```bash
flutter analyze
```

## License

See LICENSE file for details.


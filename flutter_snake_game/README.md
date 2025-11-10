# Flutter Snake Game

A keyboard-driven Snake game built with Flutter, tuned for Linux desktop but compatible with other Flutter targets.

## Features

- Smooth timer-driven game loop with pause/reset controls.
- Responsive board that scales to available window space.
- Keyboard input handling for both arrow keys and WASD.
- Score, high-score, and snake length tracking.
- Material 3 themed UI with helpful overlays for pause/game over states.

## Project Structure

```
flutter_snake_game/
├── analysis_options.yaml
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   └── src/
│       ├── game_controller.dart
│       └── snake_painter.dart
├── linux/
└── test/
```

- `game_controller.dart` keeps the board state, handles collisions, and drives the timer loop.
- `snake_painter.dart` renders the board, snake, and food via `CustomPainter` for efficiency.
- `main.dart` wires input handling, Provider-powered state updates, and the UI shell.

## Getting Started on Linux

1. **Install prerequisites**
   - [Flutter SDK](https://docs.flutter.dev/get-started/install/linux)
   - Linux desktop dependencies (`sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev` on Debian/Ubuntu)

2. **Fetch dependencies**
   ```bash
   flutter pub get
   ```

3. **Enable Linux desktop (first time only)**
   ```bash
   flutter config --enable-linux-desktop
   ```

4. **Run the game**
   ```bash
   flutter run -d linux
   ```

5. **Build a release bundle**
   ```bash
   flutter build linux --release
   ```

### Keyboard Controls

- `Arrow Keys` or `WASD`: Move the snake.
- `Space`: Pause/Resume.
- `Enter`: Restart via UI button or click.

## Testing

```
flutter test
```

## Customisation Ideas

- Add wrap-around mode or walls with obstacles.
- Gradually increase speed as the snake grows.
- Add audio feedback using `audioplayers`.
- Track persistent highscores with `shared_preferences`.

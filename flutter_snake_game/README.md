# Flutter Snake Game (Linux)

This project delivers a classic Snake experience implemented with Flutter and tailored for Linux desktop devices. It focuses on precise keyboard controls, adaptive speed, and a responsive layout that scales nicely across window sizes.

## Features

- Smooth keyboard-driven controls that support both arrow keys and WASD.
- Adaptive game speed that ramps up as the player scores more points.
- Pause/resume handling, restart shortcuts, and a persistent high-score tracker (per session).
- Modern UI with helpful overlays for paused and game-over states.

## Getting Started

1. Ensure Flutter is installed with Linux desktop support enabled. Follow the [official documentation](https://docs.flutter.dev/get-started/install/linux) if you need to set this up.
2. From the repository root:

   ```bash
   cd flutter_snake_game
   flutter pub get
   flutter create . --platforms=linux
   ```

   > The `flutter create` command ensures the Linux runner files are generated. It will not overwrite the existing `lib/main.dart`. If you are prompted about overwriting platform directories, choose the option that keeps your changes (or back up this directory before running the command).

3. Launch the game:

   ```bash
   flutter run -d linux
   ```

## Controls

- `Arrow Keys` / `WASD`: Move the snake.
- `Space`: Pause/Resume.
- `Enter`: Start a new game when on the home or game-over screen.
- `Esc`: Quick pause.

## Project Structure

- `lib/main.dart`: Main Flutter application and game loop implementation.
- `analysis_options.yaml`: Analyzer and lint rules.
- `pubspec.yaml`: Flutter manifest.

Feel free to customise artwork, audio, or gameplay behaviour to tailor the experience further. Have fun! 🐍

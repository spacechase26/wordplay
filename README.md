# Wordplay

A Wordle-style word game, but unlimited — no daily limit, no paywall. Built with Flutter, runs on web and Android.

Play it: https://spacechase26.github.io/wordplay/

## Features

- Classic 5-letter / 6-guess game with the flip reveal
- Unlimited play, new word whenever you want
- Hard mode (have to reuse the hints you've found)
- Stats + streaks saved on your device
- Share your result grid
- Works with the on-screen keyboard or a real one

## Running it

```
flutter pub get
flutter run -d chrome      # or any connected device
```

Build for web:

```
flutter build web --release --base-href "/wordplay/"
```

The game logic lives in `lib/game_logic.dart` and is covered by `test/`.

— Spacechase

import 'dart:math';

import 'words.dart';

/// Status of a single letter tile after a guess is evaluated.
enum LetterStatus { empty, tbd, correct, present, absent }

/// Pure game state + rules for one round of Wordle. No UI, no persistence.
class WordleGame {
  WordleGame({required this.answer, this.maxGuesses = 6})
      : wordLength = answer.length;

  final String answer;
  final int maxGuesses;
  final int wordLength;

  /// Submitted guesses (lowercase, [wordLength] letters each).
  final List<String> guesses = <String>[];

  /// The row currently being typed.
  String current = '';

  bool get isWon => guesses.isNotEmpty && guesses.last == answer;
  bool get isLost => !isWon && guesses.length >= maxGuesses;
  bool get isOver => isWon || isLost;

  /// Pick a random solution from the curated answer pool.
  factory WordleGame.random([Random? rng]) {
    final r = rng ?? Random();
    return WordleGame(answer: kAnswers[r.nextInt(kAnswers.length)]);
  }

  void addLetter(String letter) {
    if (isOver) return;
    if (current.length >= wordLength) return;
    current += letter.toLowerCase();
  }

  void removeLetter() {
    if (current.isEmpty) return;
    current = current.substring(0, current.length - 1);
  }

  /// Returns null on success, or a human-readable error message.
  /// Any [wordLength]-letter input is accepted as a guess — it does not
  /// have to be a real dictionary word.
  String? submit() {
    if (isOver) return null;
    if (current.length < wordLength) return 'Not enough letters';
    guesses.add(current);
    current = '';
    return null;
  }

  /// Hard-mode validation: revealed hints must be reused.
  /// Returns null if [guess] is allowed, else an error message.
  String? hardModeViolation(String guess) {
    if (guesses.isEmpty) return null;
    final prev = guesses.last;
    final status = evaluate(prev, answer);
    // Greens must stay in place.
    for (var i = 0; i < wordLength; i++) {
      if (status[i] == LetterStatus.correct && guess[i] != prev[i]) {
        return '${prev[i].toUpperCase()} must be in position ${i + 1}';
      }
    }
    // Yellows must be present somewhere.
    for (var i = 0; i < wordLength; i++) {
      if (status[i] == LetterStatus.present && !guess.contains(prev[i])) {
        return 'Guess must contain ${prev[i].toUpperCase()}';
      }
    }
    return null;
  }

  /// Evaluate a guess against the answer with correct duplicate-letter
  /// handling (two-pass: greens first, then yellows from the leftovers).
  static List<LetterStatus> evaluate(String guess, String answer) {
    final n = guess.length;
    final result = List<LetterStatus>.filled(n, LetterStatus.absent);
    final counts = <String, int>{};
    for (final c in answer.split('')) {
      counts[c] = (counts[c] ?? 0) + 1;
    }
    for (var i = 0; i < n; i++) {
      if (guess[i] == answer[i]) {
        result[i] = LetterStatus.correct;
        counts[guess[i]] = counts[guess[i]]! - 1;
      }
    }
    for (var i = 0; i < n; i++) {
      if (result[i] == LetterStatus.correct) continue;
      final c = guess[i];
      if ((counts[c] ?? 0) > 0) {
        result[i] = LetterStatus.present;
        counts[c] = counts[c]! - 1;
      }
    }
    return result;
  }

  /// Best status seen so far for each letter, for keyboard coloring.
  Map<String, LetterStatus> keyboardStatuses() {
    final map = <String, LetterStatus>{};
    int rank(LetterStatus s) => switch (s) {
          LetterStatus.correct => 3,
          LetterStatus.present => 2,
          LetterStatus.absent => 1,
          _ => 0,
        };
    for (final g in guesses) {
      final status = evaluate(g, answer);
      for (var i = 0; i < g.length; i++) {
        final c = g[i];
        if (rank(status[i]) > rank(map[c] ?? LetterStatus.empty)) {
          map[c] = status[i];
        }
      }
    }
    return map;
  }

  /// Emoji grid for sharing (🟩🟨⬛), Wordle-style.
  String shareGrid() {
    final buf = StringBuffer();
    for (final g in guesses) {
      for (final s in evaluate(g, answer)) {
        buf.write(switch (s) {
          LetterStatus.correct => '🟩',
          LetterStatus.present => '🟨',
          _ => '⬛',
        });
      }
      buf.write('\n');
    }
    return buf.toString().trimRight();
  }
}

import 'dart:math';

import 'words.dart';

enum LetterStatus { empty, tbd, correct, present, absent }

class WordleGame {
  WordleGame({required this.answer, this.maxGuesses = 6})
      : wordLength = answer.length;

  final String answer;
  final int maxGuesses;
  final int wordLength;

  final List<String> guesses = <String>[];
  String current = '';

  bool get isWon => guesses.isNotEmpty && guesses.last == answer;
  bool get isLost => !isWon && guesses.length >= maxGuesses;
  bool get isOver => isWon || isLost;

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

  // Any full-length guess is accepted; it doesn't have to be a real word.
  String? submit() {
    if (isOver) return null;
    if (current.length < wordLength) return 'Not enough letters';
    guesses.add(current);
    current = '';
    return null;
  }

  // Hard mode: every hint from the previous guess has to be reused.
  String? hardModeViolation(String guess) {
    if (guesses.isEmpty) return null;
    final prev = guesses.last;
    final status = evaluate(prev, answer);
    for (var i = 0; i < wordLength; i++) {
      if (status[i] == LetterStatus.correct && guess[i] != prev[i]) {
        return '${prev[i].toUpperCase()} must be in position ${i + 1}';
      }
    }
    for (var i = 0; i < wordLength; i++) {
      if (status[i] == LetterStatus.present && !guess.contains(prev[i])) {
        return 'Guess must contain ${prev[i].toUpperCase()}';
      }
    }
    return null;
  }

  static List<LetterStatus> evaluate(String guess, String answer) {
    final n = guess.length;
    final result = List<LetterStatus>.filled(n, LetterStatus.absent);
    final counts = <String, int>{};
    for (final c in answer.split('')) {
      counts[c] = (counts[c] ?? 0) + 1;
    }
    // Mark exact matches first so duplicate letters don't double-count.
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

  // Best status seen for each letter, used to colour the keyboard.
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

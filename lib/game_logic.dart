enum LetterStatus { empty, tbd, correct, present, absent }

class WordleGame {
  WordleGame({
    required this.answer,
    Set<String>? validGuesses,
    this.maxGuesses = 6,
  })  : wordLength = answer.length,
        validGuesses = validGuesses ?? const {};

  final String answer;
  final int maxGuesses;
  final int wordLength;

  // Words accepted as a guess. Empty set = accept anything (used in tests).
  final Set<String> validGuesses;

  final List<String> guesses = <String>[];
  String current = '';

  // Cached evaluation per submitted row; guesses are append-only per game.
  final List<List<LetterStatus>> _evals = [];
  Map<String, LetterStatus>? _kbCache;
  int _kbCacheLen = -1;

  bool get isWon => guesses.isNotEmpty && guesses.last == answer;
  bool get isLost => !isWon && guesses.length >= maxGuesses;
  bool get isOver => isWon || isLost;

  void addLetter(String letter) {
    if (isOver) return;
    if (current.length >= wordLength) return;
    current += letter.toLowerCase();
  }

  void removeLetter() {
    if (current.isEmpty) return;
    current = current.substring(0, current.length - 1);
  }

  String? submit() {
    if (isOver) return null;
    if (current.length < wordLength) return 'Not enough letters';
    if (validGuesses.isNotEmpty && !validGuesses.contains(current)) {
      return 'Not in word list';
    }
    guesses.add(current);
    current = '';
    return null;
  }

  // Evaluation for a submitted row, computed once and cached.
  List<LetterStatus> evaluationAt(int row) {
    while (_evals.length <= row) {
      _evals.add(evaluate(guesses[_evals.length], answer));
    }
    return _evals[row];
  }

  // Hard mode: every revealed hint must be reused, including how many times a
  // letter is known to appear (green + yellow occurrences).
  String? hardModeViolation(String guess) {
    if (guesses.isEmpty) return null;
    final prev = guesses.last;
    final status = evaluationAt(guesses.length - 1);

    // Greens must stay in their exact position.
    for (var i = 0; i < wordLength; i++) {
      if (status[i] == LetterStatus.correct && guess[i] != prev[i]) {
        return '${prev[i].toUpperCase()} must be in position ${i + 1}';
      }
    }

    // Each known letter must appear at least as many times as it was revealed.
    final required = <String, int>{};
    for (var i = 0; i < wordLength; i++) {
      if (status[i] == LetterStatus.correct ||
          status[i] == LetterStatus.present) {
        required[prev[i]] = (required[prev[i]] ?? 0) + 1;
      }
    }
    for (final entry in required.entries) {
      final c = entry.key;
      var have = 0;
      for (var i = 0; i < guess.length; i++) {
        if (guess[i] == c) have++;
      }
      if (have < entry.value) {
        return entry.value == 1
            ? 'Guess must contain ${c.toUpperCase()}'
            : 'Guess needs ${entry.value} ${c.toUpperCase()}\'s';
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

  // Best status seen for each letter, used to colour the keyboard. Cached
  // until a new guess is submitted (the only thing that can change it).
  Map<String, LetterStatus> keyboardStatuses() {
    if (_kbCacheLen == guesses.length && _kbCache != null) return _kbCache!;
    final map = <String, LetterStatus>{};
    int rank(LetterStatus s) => switch (s) {
          LetterStatus.correct => 3,
          LetterStatus.present => 2,
          LetterStatus.absent => 1,
          _ => 0,
        };
    for (var row = 0; row < guesses.length; row++) {
      final g = guesses[row];
      final status = evaluationAt(row);
      for (var i = 0; i < g.length; i++) {
        final c = g[i];
        if (rank(status[i]) > rank(map[c] ?? LetterStatus.empty)) {
          map[c] = status[i];
        }
      }
    }
    _kbCacheLen = guesses.length;
    return _kbCache = map;
  }

  String shareGrid() {
    final buf = StringBuffer();
    for (var row = 0; row < guesses.length; row++) {
      for (final s in evaluationAt(row)) {
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

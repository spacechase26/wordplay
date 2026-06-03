import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

// Word lists per length, loaded from assets/words/ and cached.
// answers = solution pool (common, real words); valid = anything you're
// allowed to guess (a big dictionary, includes the answers).
class Dictionary {
  Dictionary(this.length, this.answers, this.valid);

  final int length;
  final List<String> answers;
  final Set<String> valid;

  static const supportedLengths = [4, 5, 6];
  static final Map<int, Dictionary> _cache = {};

  static Future<Dictionary> forLength(int len) async {
    final cached = _cache[len];
    if (cached != null) return cached;
    final answers = await _load('assets/words/answers_$len.txt');
    final valid = await _load('assets/words/valid_$len.txt');
    final dict = Dictionary(len, answers, {...valid, ...answers});
    _cache[len] = dict;
    return dict;
  }

  static Future<List<String>> _load(String path) async {
    final raw = await rootBundle.loadString(path);
    return [
      for (final line in raw.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
  }

  String randomAnswer(Random r) => answers[r.nextInt(answers.length)];

  // Deterministic pick for the daily puzzle.
  String answerForIndex(int i) => answers[i % answers.length];
}

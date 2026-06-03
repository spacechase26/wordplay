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

  // A fixed pseudo-random permutation of [answers] used for the daily puzzle,
  // so consecutive days aren't alphabetically adjacent. Same on every device.
  // Lazy: unlimited-only sessions never build it.
  late final List<String> _dailyOrder = _shuffleStable(answers);

  static const supportedLengths = [4, 5, 6];
  static final Map<int, Dictionary> _cache = {};

  static Future<Dictionary> forLength(int len) async {
    final cached = _cache[len];
    if (cached != null) return cached;
    final answers = await _load('assets/words/answers_$len.txt');
    final validSet = (await _load('assets/words/valid_$len.txt')).toSet();
    // Every answer is already in the valid set, so no merge is needed.
    assert(answers.every(validSet.contains));
    final dict = Dictionary(len, answers, validSet);
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

  // Deterministic, non-sequential pick for day [i] of the daily puzzle.
  String answerForIndex(int i) => _dailyOrder[i % _dailyOrder.length];

  // Fisher-Yates with a fixed-seed xorshift32. Uses only shifts/xor/mask so
  // it gives identical results on web (dart2js) and native — every player
  // gets the same daily sequence.
  static List<String> _shuffleStable(List<String> src) {
    final list = List<String>.of(src);
    var state = 0x9E3779B9; // fixed nonzero seed
    int next() {
      state ^= (state << 13) & 0xFFFFFFFF;
      state ^= state >>> 17;
      state ^= (state << 5) & 0xFFFFFFFF;
      state &= 0xFFFFFFFF;
      return state;
    }

    for (var i = list.length - 1; i > 0; i--) {
      final j = next() % (i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
    return list;
  }
}

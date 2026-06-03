import 'package:flutter_test/flutter_test.dart';
import 'package:wordplay/words.dart';

void main() {
  final sample = [
    for (var c = 0; c < 26; c++)
      String.fromCharCode(97 + c) * 5, // aaaaa, bbbbb, ... zzzzz (sorted)
  ];

  test('daily order is a full permutation of the answers', () {
    final d = Dictionary(5, sample, sample.toSet());
    final seq = [for (var i = 0; i < sample.length; i++) d.answerForIndex(i)];
    expect(seq.toSet(), equals(sample.toSet())); // every word, exactly once
    expect(seq.length, sample.length);
  });

  test('daily order is deterministic across instances', () {
    final a = Dictionary(5, sample, {});
    final b = Dictionary(5, sample, {});
    final seqA = [for (var i = 0; i < 8; i++) a.answerForIndex(i)];
    final seqB = [for (var i = 0; i < 8; i++) b.answerForIndex(i)];
    expect(seqA, equals(seqB));
  });

  test('daily order is not just alphabetical', () {
    final d = Dictionary(5, sample, {});
    final seq = [for (var i = 0; i < sample.length; i++) d.answerForIndex(i)];
    expect(seq, isNot(equals(sample))); // shuffled, not in sorted order
  });

  test('answerForIndex wraps around the cycle', () {
    final d = Dictionary(5, sample, {});
    expect(d.answerForIndex(sample.length), d.answerForIndex(0));
    expect(d.answerForIndex(sample.length + 3), d.answerForIndex(3));
  });
}

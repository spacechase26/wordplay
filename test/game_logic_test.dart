import 'package:flutter_test/flutter_test.dart';
import 'package:wordplay/game_logic.dart';

void main() {
  group('evaluate', () {
    test('all correct', () {
      expect(WordleGame.evaluate('crane', 'crane'),
          everyElement(LetterStatus.correct));
    });

    test('present vs absent', () {
      // answer "abide", guess "crane": a present, e present, rest absent.
      final r = WordleGame.evaluate('crane', 'abide');
      expect(r[0], LetterStatus.absent); // c
      expect(r[1], LetterStatus.absent); // r
      expect(r[2], LetterStatus.present); // a (in abide, wrong spot)
      expect(r[3], LetterStatus.absent); // n
      expect(r[4], LetterStatus.correct); // e matches abide's last letter
    });

    test('duplicate letters split correctly across the answer', () {
      // answer "eaten" has two E's. Guess "eerie" has three E's.
      // One E is green, one yellow, the third must go dark.
      final r = WordleGame.evaluate('eerie', 'eaten');
      // e e r i e  vs  e a t e n
      expect(r[0], LetterStatus.correct); // e matches position 0
      expect(r[1], LetterStatus.present); // second e -> uses the other e
      expect(r[2], LetterStatus.absent); // r
      expect(r[3], LetterStatus.absent); // i
      expect(r[4], LetterStatus.absent); // third e -> no e left
    });
  });

  group('hard mode', () {
    test('green must stay in place', () {
      final g = WordleGame(answer: 'crane');
      g.guesses.add('crony'); // crony vs crane: c,r,n green; o,y absent.
      final v = g.hardModeViolation('blade');
      expect(v, isNotNull); // dropped the green C in position 1
    });

    test('present letter must be reused', () {
      final g = WordleGame(answer: 'crane');
      g.guesses.add('nicer'); // n present, c present, e present, r present
      final v = g.hardModeViolation('boggy'); // contains none of them
      expect(v, isNotNull);
    });

    test('valid hard-mode guess passes', () {
      final g = WordleGame(answer: 'crane');
      g.guesses.add('crony'); // greens: c@0, r@1, n@3.
      final v = g.hardModeViolation('crank'); // keeps all three greens
      expect(v, isNull);
    });
  });

  test('win detection', () {
    final g = WordleGame(answer: 'crane');
    g.current = 'crane';
    expect(g.submit(), isNull);
    expect(g.isWon, isTrue);
    expect(g.isOver, isTrue);
  });

  test('rejects invalid word', () {
    final g = WordleGame(answer: 'crane');
    g.current = 'zzzzz';
    expect(g.submit(), 'Not in word list');
  });
}

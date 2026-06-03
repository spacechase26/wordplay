import 'package:shared_preferences/shared_preferences.dart';

/// Player statistics, persisted on-device via SharedPreferences.
class Stats {
  Stats({
    this.played = 0,
    this.won = 0,
    this.currentStreak = 0,
    this.maxStreak = 0,
    List<int>? distribution,
  }) : distribution = distribution ?? List<int>.filled(6, 0);

  int played;
  int won;
  int currentStreak;
  int maxStreak;

  /// distribution[i] = games won in (i+1) guesses.
  final List<int> distribution;

  int get winPercent => played == 0 ? 0 : ((won / played) * 100).round();

  static const _kPlayed = 'played';
  static const _kWon = 'won';
  static const _kStreak = 'currentStreak';
  static const _kMaxStreak = 'maxStreak';
  static const _kDist = 'distribution';

  static Future<Stats> load() async {
    final p = await SharedPreferences.getInstance();
    final dist = p.getStringList(_kDist)?.map(int.parse).toList();
    return Stats(
      played: p.getInt(_kPlayed) ?? 0,
      won: p.getInt(_kWon) ?? 0,
      currentStreak: p.getInt(_kStreak) ?? 0,
      maxStreak: p.getInt(_kMaxStreak) ?? 0,
      distribution: (dist != null && dist.length == 6) ? dist : null,
    );
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kPlayed, played);
    await p.setInt(_kWon, won);
    await p.setInt(_kStreak, currentStreak);
    await p.setInt(_kMaxStreak, maxStreak);
    await p.setStringList(
        _kDist, distribution.map((e) => e.toString()).toList());
  }

  /// Record a finished game. [guessCount] is 1-based; null/0 means a loss.
  Future<void> record({required bool didWin, int guessCount = 0}) async {
    played++;
    if (didWin) {
      won++;
      currentStreak++;
      if (currentStreak > maxStreak) maxStreak = currentStreak;
      if (guessCount >= 1 && guessCount <= 6) distribution[guessCount - 1]++;
    } else {
      currentStreak = 0;
    }
    await _save();
  }

  Future<void> reset() async {
    played = 0;
    won = 0;
    currentStreak = 0;
    maxStreak = 0;
    for (var i = 0; i < distribution.length; i++) {
      distribution[i] = 0;
    }
    await _save();
  }
}

/// Persisted user settings.
class Settings {
  static const _kHardMode = 'hardMode';

  static Future<bool> hardMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kHardMode) ?? false;
  }

  static Future<void> setHardMode(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHardMode, value);
  }
}

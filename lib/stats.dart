import 'package:shared_preferences/shared_preferences.dart';

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

  // distribution[i] = wins in (i+1) guesses
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

class Settings {
  static const _kHardMode = 'hardMode';
  static const _kLength = 'wordLength';
  static const _kMode = 'mode';

  static Future<bool> hardMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kHardMode) ?? false;
  }

  static Future<void> setHardMode(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHardMode, value);
  }

  static Future<int> length() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kLength) ?? 5;
  }

  static Future<void> setLength(int value) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kLength, value);
  }

  static Future<String> mode() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kMode) ?? 'unlimited';
  }

  static Future<void> setMode(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMode, value);
  }

  static Future<String> themeMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('theme') ?? 'dark';
  }

  static Future<void> setThemeMode(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('theme', value);
  }

  static Future<bool> seenIntro() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('seenIntro') ?? false;
  }

  static Future<void> setSeenIntro() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('seenIntro', true);
  }
}

// Daily-mode results are tracked separately so casual unlimited play
// doesn't inflate the daily streak.
class DailyStats {
  DailyStats({
    this.played = 0,
    this.won = 0,
    this.streak = 0,
    this.maxStreak = 0,
    this.lastWinDay = -2,
  });

  int played;
  int won;
  int streak;
  int maxStreak;
  int lastWinDay;

  int get winPercent => played == 0 ? 0 : ((won / played) * 100).round();

  static Future<DailyStats> load() async {
    final p = await SharedPreferences.getInstance();
    return DailyStats(
      played: p.getInt('d_played') ?? 0,
      won: p.getInt('d_won') ?? 0,
      streak: p.getInt('d_streak') ?? 0,
      maxStreak: p.getInt('d_maxStreak') ?? 0,
      lastWinDay: p.getInt('d_lastWinDay') ?? -2,
    );
  }

  Future<void> record({required int day, required bool didWin}) async {
    played++;
    if (didWin) {
      won++;
      streak = (lastWinDay == day - 1) ? streak + 1 : 1;
      if (streak > maxStreak) maxStreak = streak;
      lastWinDay = day;
    } else {
      streak = 0;
    }
    final p = await SharedPreferences.getInstance();
    await p.setInt('d_played', played);
    await p.setInt('d_won', won);
    await p.setInt('d_streak', streak);
    await p.setInt('d_maxStreak', maxStreak);
    await p.setInt('d_lastWinDay', lastWinDay);
  }
}

class GameSnapshot {
  GameSnapshot(this.answer, this.guesses, this.day);
  final String answer;
  final List<String> guesses;
  final int day; // only meaningful for daily games
}

// Saves the board so a refresh / app restart resumes where you left off.
class GameStore {
  static Future<void> saveUnlimited(String answer, List<String> guesses) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('u_answer', answer);
    await p.setStringList('u_guesses', guesses);
  }

  static Future<GameSnapshot?> loadUnlimited() async {
    final p = await SharedPreferences.getInstance();
    final answer = p.getString('u_answer');
    if (answer == null) return null;
    return GameSnapshot(answer, p.getStringList('u_guesses') ?? [], -1);
  }

  static Future<void> saveDaily(
      int day, String answer, List<String> guesses) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('g_day', day);
    await p.setString('g_answer', answer);
    await p.setStringList('g_guesses', guesses);
  }

  static Future<GameSnapshot?> loadDaily() async {
    final p = await SharedPreferences.getInstance();
    final answer = p.getString('g_answer');
    if (answer == null) return null;
    return GameSnapshot(
        answer, p.getStringList('g_guesses') ?? [], p.getInt('g_day') ?? -1);
  }
}

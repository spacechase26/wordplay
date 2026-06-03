import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_logic.dart';
import 'stats.dart';
import 'words.dart';

void main() => runApp(const WordplayApp());

const _green = Color(0xFF6AAA64);
const _yellow = Color(0xFFC9B458);

enum GameMode { unlimited, daily }

// Per-theme colours that aren't covered by the standard ColorScheme.
@immutable
class GameSkin extends ThemeExtension<GameSkin> {
  const GameSkin({
    required this.panel,
    required this.keyBg,
    required this.keyText,
    required this.tileEmpty,
    required this.tileFilled,
    required this.tileText,
    required this.correct,
    required this.present,
    required this.absent,
    required this.muted,
    required this.toastBg,
    required this.toastText,
  });

  final Color panel, keyBg, keyText, tileEmpty, tileFilled, tileText;
  final Color correct, present, absent, muted, toastBg, toastText;

  static const dark = GameSkin(
    panel: Color(0xFF1E1F21),
    keyBg: Color(0xFF818384),
    keyText: Colors.white,
    tileEmpty: Color(0xFF3A3A3C),
    tileFilled: Color(0xFF565758),
    tileText: Colors.white,
    correct: _green,
    present: _yellow,
    absent: Color(0xFF3A3A3C),
    muted: Color(0xFF9A9BA1),
    toastBg: Colors.white,
    toastText: Colors.black,
  );

  static const light = GameSkin(
    panel: Color(0xFFF3F4F6),
    keyBg: Color(0xFFD3D6DA),
    keyText: Color(0xFF1A1A1B),
    tileEmpty: Color(0xFFD3D6DA),
    tileFilled: Color(0xFF878A8C),
    tileText: Color(0xFF1A1A1B),
    correct: _green,
    present: _yellow,
    absent: Color(0xFF787C7E),
    muted: Color(0xFF6E7177),
    toastBg: Color(0xFF1A1A1B),
    toastText: Colors.white,
  );

  Color status(LetterStatus s) => switch (s) {
        LetterStatus.correct => correct,
        LetterStatus.present => present,
        LetterStatus.absent => absent,
        _ => keyBg,
      };

  @override
  GameSkin copyWith() => this;

  @override
  GameSkin lerp(ThemeExtension<GameSkin>? other, double t) {
    if (other is! GameSkin) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return GameSkin(
      panel: c(panel, other.panel),
      keyBg: c(keyBg, other.keyBg),
      keyText: c(keyText, other.keyText),
      tileEmpty: c(tileEmpty, other.tileEmpty),
      tileFilled: c(tileFilled, other.tileFilled),
      tileText: c(tileText, other.tileText),
      correct: c(correct, other.correct),
      present: c(present, other.present),
      absent: c(absent, other.absent),
      muted: c(muted, other.muted),
      toastBg: c(toastBg, other.toastBg),
      toastText: c(toastText, other.toastText),
    );
  }
}

GameSkin _skin(BuildContext c) => Theme.of(c).extension<GameSkin>()!;

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? const Color(0xFF121213) : Colors.white;
  final onBg = dark ? Colors.white : const Color(0xFF1A1A1B);
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    scaffoldBackgroundColor: bg,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: _green,
      brightness: b,
      surface: bg,
      primary: _green,
      onPrimary: Colors.white,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onBg,
        side: BorderSide(color: onBg.withValues(alpha: 0.3)),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    extensions: [dark ? GameSkin.dark : GameSkin.light],
  );
}

class WordplayApp extends StatefulWidget {
  const WordplayApp({super.key});

  @override
  State<WordplayApp> createState() => _WordplayAppState();
}

class _WordplayAppState extends State<WordplayApp> {
  ThemeMode _mode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    Settings.themeMode().then((m) {
      if (mounted) {
        setState(() => _mode = m == 'light' ? ThemeMode.light : ThemeMode.dark);
      }
    });
  }

  void _toggleTheme() {
    setState(() =>
        _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
    Settings.setThemeMode(_mode == ThemeMode.dark ? 'dark' : 'light');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wordplay by Spacechase',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _mode,
      home: GamePage(onToggleTheme: _toggleTheme),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.onToggleTheme});

  final VoidCallback onToggleTheme;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with TickerProviderStateMixin {
  final _rng = math.Random();

  Dictionary? _dict;
  WordleGame? _game;
  int _length = 5;
  GameMode _mode = GameMode.unlimited;

  Stats _stats = Stats();
  DailyStats _daily = DailyStats();
  bool _hardMode = false;
  bool _busy = false;
  bool _loading = true;

  int _justSubmittedRow = -1;
  int _winRow = -1;
  late final AnimationController _shake;
  final FocusNode _kbFocus = FocusNode();

  static const _flipMs = 300;
  static const _staggerMs = 220;

  int get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day)
        .difference(DateTime(2022, 1, 1))
        .inDays;
  }

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _boot();
  }

  Future<void> _boot() async {
    _stats = await Stats.load();
    _daily = await DailyStats.load();
    _hardMode = await Settings.hardMode();
    _length = await Settings.length();
    _mode =
        await Settings.mode() == 'daily' ? GameMode.daily : GameMode.unlimited;
    final firstTime = !(await Settings.seenIntro());
    await _startFromStorage();
    if (!mounted) return;
    setState(() => _loading = false);
    if (firstTime) {
      Settings.setSeenIntro();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showHelp();
      });
    }
  }

  WordleGame _make(String answer, [List<String> guesses = const []]) {
    final g = WordleGame(answer: answer, validGuesses: _dict!.valid);
    g.guesses.addAll(guesses);
    return g;
  }

  Future<void> _startFromStorage() async {
    if (_mode == GameMode.daily) {
      _dict = await Dictionary.forLength(5);
      final snap = await GameStore.loadDaily();
      if (snap != null && snap.day == _today) {
        _game = _make(snap.answer, snap.guesses);
      } else {
        final answer = _dict!.answerForIndex(_today);
        _game = _make(answer);
        await GameStore.saveDaily(_today, answer, const []);
      }
    } else {
      _dict = await Dictionary.forLength(_length);
      final snap = await GameStore.loadUnlimited();
      if (snap != null && snap.answer.length == _length) {
        _game = _make(snap.answer, snap.guesses);
      } else {
        final answer = _dict!.randomAnswer(_rng);
        _game = _make(answer);
        await GameStore.saveUnlimited(answer, const []);
      }
    }
    _justSubmittedRow = -1;
    _winRow = -1;
    _busy = false;
  }

  void _persist() {
    final g = _game;
    if (g == null) return;
    if (_mode == GameMode.daily) {
      GameStore.saveDaily(_today, g.answer, g.guesses);
    } else {
      GameStore.saveUnlimited(g.answer, g.guesses);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    _kbFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onPhysicalKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _onKey('ENTER');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      _onKey('DEL');
      return KeyEventResult.handled;
    }
    final label = event.character?.toLowerCase() ?? '';
    if (label.length == 1 &&
        label.codeUnitAt(0) >= 0x61 &&
        label.codeUnitAt(0) <= 0x7a) {
      _onKey(label);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onKey(String key) {
    if (!_kbFocus.hasFocus) _kbFocus.requestFocus();
    final game = _game;
    if (game == null || _busy || game.isOver) return;
    if (key == 'ENTER') {
      _submit();
    } else if (key == 'DEL') {
      setState(() => game.removeLetter());
    } else {
      setState(() => game.addLetter(key));
    }
  }

  void _toast(String message, {bool good = false}) {
    final skin = _skin(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: skin.toastText,
                fontWeight: good ? FontWeight.bold : FontWeight.w500)),
        duration: Duration(milliseconds: good ? 1500 : 1100),
        backgroundColor: skin.toastBg,
        width: 220,
      ));
  }

  void _reject(String message) {
    _shake.forward(from: 0);
    _toast(message);
  }

  Future<void> _submit() async {
    final game = _game!;
    if (game.current.length < game.wordLength) {
      _reject('Not enough letters');
      return;
    }
    if (_hardMode) {
      final v = game.hardModeViolation(game.current);
      if (v != null) {
        _reject(v);
        return;
      }
    }
    final rowIndex = game.guesses.length;
    final err = game.submit();
    if (err != null) {
      _reject(err);
      return;
    }
    _persist();

    setState(() {
      _justSubmittedRow = rowIndex;
      _busy = true;
    });

    final total = _staggerMs * (game.wordLength - 1) + _flipMs + 80;
    await Future<void>.delayed(Duration(milliseconds: total));
    if (!mounted) return;
    setState(() => _busy = false);

    if (game.isOver) {
      final didWin = game.isWon;
      if (_mode == GameMode.daily) {
        await _daily.record(day: _today, didWin: didWin);
      } else {
        await _stats.record(
            didWin: didWin, guessCount: didWin ? game.guesses.length : 0);
      }
      if (!mounted) return;
      if (didWin) {
        setState(() => _winRow = rowIndex);
        _toast(_praise(game.guesses.length), good: true);
      } else {
        setState(() {});
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) _showEndDialog(didWin);
    }
  }

  String _praise(int guesses) => const {
        1: 'Genius',
        2: 'Magnificent',
        3: 'Impressive',
        4: 'Splendid',
        5: 'Great',
        6: 'Phew!',
      }[guesses] ??
      'Solved';

  Future<void> _newUnlimited() async {
    _dict = await Dictionary.forLength(_length);
    final answer = _dict!.randomAnswer(_rng);
    setState(() {
      _game = _make(answer);
      _justSubmittedRow = -1;
      _winRow = -1;
      _busy = false;
    });
    await GameStore.saveUnlimited(answer, const []);
    _kbFocus.requestFocus();
  }

  Future<void> _setMode(GameMode m) async {
    if (m == _mode) return;
    await Settings.setMode(m == GameMode.daily ? 'daily' : 'unlimited');
    setState(() {
      _mode = m;
      _loading = true;
    });
    await _startFromStorage();
    if (mounted) setState(() => _loading = false);
    _kbFocus.requestFocus();
  }

  Future<void> _setLength(int n) async {
    if (n == _length) return;
    await Settings.setLength(n);
    setState(() => _length = n);
    await _newUnlimited();
  }

  String _shareText(bool didWin) {
    final g = _game!;
    final tries = didWin ? '${g.guesses.length}' : 'X';
    final tag = _mode == GameMode.daily ? 'Wordplay Daily #$_today' : 'Wordplay';
    final len = g.wordLength != 5 ? ' (${g.wordLength})' : '';
    final hard = _hardMode ? '*' : '';
    return '$tag $tries/6$len$hard\n\n${g.shareGrid()}';
  }

  // ---- dialogs ----

  void _showEndDialog(bool didWin) {
    final daily = _mode == GameMode.daily;
    final skin = _skin(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(didWin ? 'Got it! 🎉' : 'Out of guesses'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!didWin)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(color: skin.muted, fontSize: 16),
                    children: [
                      const TextSpan(text: 'The word was '),
                      TextSpan(
                        text: _game!.answer.toUpperCase(),
                        style: TextStyle(
                            color: Theme.of(ctx).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ),
            daily ? _DailyStatsView(stats: _daily) : _StatsView(stats: _stats),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _shareText(didWin)));
              _toast('Copied to clipboard');
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy result'),
          ),
          if (daily)
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Done'))
          else
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _newUnlimited();
              },
              child: const Text('New game'),
            ),
        ],
      ),
    );
  }

  void _showStats() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Statistics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatsView(stats: _stats),
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 6),
            _DailyStatsView(stats: _daily),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _confirmReset(ctx),
            child: Text('Reset',
                style: TextStyle(color: _skin(ctx).muted)),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _confirmReset(BuildContext statsCtx) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset stats?'),
        content: const Text(
            'This clears your games, streaks and guess distribution. '
            "It can't be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () async {
              await _stats.reset();
              if (mounted) setState(() {});
              if (ctx.mounted) Navigator.pop(ctx);
              if (statsCtx.mounted) Navigator.pop(statsCtx);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _showHelp() {
    final skin = _skin(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How to play'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Guess the hidden word in 6 tries. Your guess has to '
                'be a real word of the right length.'),
            const SizedBox(height: 14),
            _LegendRow(color: skin.correct, text: 'Right letter, right spot'),
            const SizedBox(height: 6),
            _LegendRow(color: skin.present, text: 'Right letter, wrong spot'),
            const SizedBox(height: 6),
            _LegendRow(color: skin.absent, text: 'Not in the word'),
            const SizedBox(height: 14),
            Text(
                'Unlimited: play forever, pick 4, 5 or 6 letters. Daily: one '
                'shared puzzle a day. Hard mode makes you reuse every hint.',
                style: TextStyle(color: skin.muted)),
            const SizedBox(height: 18),
            Center(
              child: Text('Wordplay by Spacechase',
                  style: TextStyle(
                      fontSize: 12, color: skin.muted, letterSpacing: 0.5)),
            ),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
        ],
      ),
    );
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _kbFocus,
      autofocus: true,
      onKeyEvent: _onPhysicalKey,
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('WORDPLAY',
                style: TextStyle(
                    fontWeight: FontWeight.w800, letterSpacing: 5, height: 1)),
            Text('by Spacechase',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: _skin(context).muted,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        shape: Divider.createBorderSide(context, width: 1).let(
            (s) => Border(bottom: s)),
        actions: [
          IconButton(
              tooltip: 'Statistics',
              onPressed: _showStats,
              icon: const Icon(Icons.leaderboard_outlined)),
          if (_mode == GameMode.unlimited)
            IconButton(
                tooltip: 'New word',
                onPressed: _newUnlimited,
                icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'help':
                  _showHelp();
                case 'hard':
                  _toggleHard();
                case 'theme':
                  widget.onToggleTheme();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'help', child: Text('How to play')),
              CheckedPopupMenuItem(
                  value: 'hard', checked: _hardMode, child: const Text('Hard mode')),
              PopupMenuItem(
                value: 'theme',
                child: Row(children: [
                  Icon(
                      Theme.of(context).brightness == Brightness.dark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      size: 20,
                      color: onSurface),
                  const SizedBox(width: 12),
                  Text(Theme.of(context).brightness == Brightness.dark
                      ? 'Light theme'
                      : 'Dark theme'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: (_loading || _game == null)
                ? const _Loader()
                : Column(
                    children: [
                      _buildTopBar(),
                      Expanded(child: Center(child: _buildGrid())),
                      if (_game!.isOver) _buildEndBar(),
                      _Keyboard(
                          statuses: _game!.keyboardStatuses(), onKey: _onKey),
                      const SizedBox(height: 10),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  void _toggleHard() {
    if (_game?.guesses.isNotEmpty ?? false) {
      _reject('Hard mode locks once you guess');
      return;
    }
    setState(() => _hardMode = !_hardMode);
    Settings.setHardMode(_hardMode);
    _toast(_hardMode ? 'Hard mode on' : 'Hard mode off');
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Segment(
            options: const ['Unlimited', 'Daily'],
            selected: _mode == GameMode.daily ? 1 : 0,
            onSelect: (i) =>
                _setMode(i == 1 ? GameMode.daily : GameMode.unlimited),
          ),
          if (_mode == GameMode.unlimited)
            _Segment(
              options: [for (final n in Dictionary.supportedLengths) '$n'],
              selected: Dictionary.supportedLengths.indexOf(_length),
              onSelect: (i) => _setLength(Dictionary.supportedLengths[i]),
            ),
        ],
      ),
    );
  }

  Widget _buildEndBar() {
    final game = _game!;
    final won = game.isWon;
    final daily = _mode == GameMode.daily;
    final skin = _skin(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final spans = <InlineSpan>[
      if (won) ...[
        TextSpan(
            text: 'Solved in ${game.guesses.length}/6 ',
            style: TextStyle(color: onSurface, fontWeight: FontWeight.w600)),
        const TextSpan(text: '🎉'),
      ] else ...[
        const TextSpan(text: 'Answer: '),
        TextSpan(
          text: game.answer.toUpperCase(),
          style: TextStyle(
              color: onSurface,
              fontWeight: FontWeight.bold,
              letterSpacing: 1),
        ),
      ],
      if (daily)
        TextSpan(
            text: '   ·   streak ${_daily.streak}',
            style: TextStyle(color: skin.muted, fontSize: 13)),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: skin.panel, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                  style: TextStyle(color: skin.muted, fontSize: 15),
                  children: spans),
            ),
          ),
          if (daily)
            OutlinedButton(
                onPressed: () => _setMode(GameMode.unlimited),
                child: const Text('Play unlimited'))
          else
            FilledButton(
                onPressed: _newUnlimited, child: const Text('New game')),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final game = _game!;
    final len = game.wordLength;
    return LayoutBuilder(builder: (context, c) {
      final byWidth = c.maxWidth * 0.94 / len - 6;
      final byHeight = c.maxHeight / game.maxGuesses - 6;
      final tile = math.min(byWidth, byHeight).clamp(28.0, 64.0).toDouble();
      return AnimatedBuilder(
        animation: _shake,
        builder: (context, child) => Transform.translate(
            offset: Offset(_shakeOffset(_shake.value), 0), child: child),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children:
              List.generate(game.maxGuesses, (row) => _buildRow(row, tile)),
        ),
      );
    });
  }

  double _shakeOffset(double t) {
    if (t == 0 || t == 1) return 0;
    const twoPi = 6.283185307179586;
    final v = (t * 3 * twoPi).remainder(twoPi);
    return 7 * (1 - t) * (v < 3.14159 ? 1 : -1);
  }

  Widget _buildRow(int row, double tile) {
    final game = _game!;
    final isSubmitted = row < game.guesses.length;
    final isCurrent = row == game.guesses.length && !game.isOver;
    final word =
        isSubmitted ? game.guesses[row] : (isCurrent ? game.current : '');
    final statuses =
        isSubmitted ? WordleGame.evaluate(word, game.answer) : null;
    final flip = row == _justSubmittedRow;
    final bounce = row == _winRow;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(game.wordLength, (col) {
        final letter = col < word.length ? word[col] : '';
        final status = statuses != null ? statuses[col] : LetterStatus.tbd;
        return LetterTile(
          key: ValueKey('$row-$col-${game.answer}'),
          letter: letter,
          status: status,
          filled: letter.isNotEmpty,
          size: tile,
          flip: flip,
          bounce: bounce,
          delayMs: flip ? col * _staggerMs : (bounce ? col * 90 : 0),
        );
      }),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

// One tile: pops when typed, flips to reveal its colour, bounces on a win.
class LetterTile extends StatefulWidget {
  const LetterTile({
    super.key,
    required this.letter,
    required this.status,
    required this.filled,
    required this.size,
    this.flip = false,
    this.bounce = false,
    this.delayMs = 0,
  });

  final String letter;
  final LetterStatus status;
  final bool filled;
  final double size;
  final bool flip;
  final bool bounce;
  final int delayMs;

  @override
  State<LetterTile> createState() => _LetterTileState();
}

class _LetterTileState extends State<LetterTile> with TickerProviderStateMixin {
  late final AnimationController _flipC;
  late final AnimationController _bounceC;
  late final AnimationController _popC;
  bool _flipped = false;
  bool _bounced = false;

  @override
  void initState() {
    super.initState();
    _flipC = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _bounceC = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _popC = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 110));
    if (widget.flip) _scheduleFlip();
    if (widget.bounce) _scheduleBounce();
  }

  @override
  void didUpdateWidget(LetterTile old) {
    super.didUpdateWidget(old);
    if (widget.flip && !old.flip && !_flipped) _scheduleFlip();
    if (widget.bounce && !old.bounce && !_bounced) _scheduleBounce();
    // pop when a letter is freshly typed into the active row
    if (!widget.flip && widget.filled && !old.filled) _popC.forward(from: 0);
  }

  void _scheduleFlip() {
    _flipped = true;
    Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _flipC.forward(from: 0);
    });
  }

  void _scheduleBounce() {
    _bounced = true;
    Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _bounceC.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _flipC.dispose();
    _bounceC.dispose();
    _popC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = _skin(context);
    final revealed = widget.status == LetterStatus.correct ||
        widget.status == LetterStatus.present ||
        widget.status == LetterStatus.absent;

    return AnimatedBuilder(
      animation: Listenable.merge([_flipC, _bounceC, _popC]),
      builder: (context, _) {
        final t = _flipC.value;
        final showColored = !widget.flip || t >= 0.5;
        final angle = (t < 0.5 ? t : 1 - t) * 3.14159;
        final dy = -widget.size * 0.22 * math.sin(3.14159 * _bounceC.value);
        final scale = 1 + 0.10 * math.sin(3.14159 * _popC.value);
        final face = showColored && revealed
            ? _coloredFace(skin)
            : _typingFace(skin);
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(
            scale: scale,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..rotateX(angle),
              child: face,
            ),
          ),
        );
      },
    );
  }

  Widget _box({required Widget child, Color? bg, Border? border}) {
    return Container(
      margin: const EdgeInsets.all(3),
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: bg, border: border, borderRadius: BorderRadius.circular(6)),
      child: child,
    );
  }

  Widget _typingFace(GameSkin skin) => _box(
        border: Border.all(
            color: widget.filled ? skin.tileFilled : skin.tileEmpty, width: 2),
        child: _text(skin.tileText),
      );

  Widget _coloredFace(GameSkin skin) =>
      _box(bg: skin.status(widget.status), child: _text(Colors.white));

  Widget _text(Color color) => Text(
        widget.letter.toUpperCase(),
        style: TextStyle(
            color: color,
            fontSize: widget.size * 0.5,
            fontWeight: FontWeight.bold),
      );
}

// Branded loading state — a row of tiles pulsing in sequence.
class _Loader extends StatefulWidget {
  const _Loader();
  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = _skin(context);
    return Center(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) {
            final phase = (_c.value - i * 0.12) % 1.0;
            final lift = math.sin(math.pi * phase.clamp(0.0, 1.0));
            return Container(
              margin: const EdgeInsets.all(3),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Color.lerp(skin.tileEmpty, skin.correct, lift),
                borderRadius: BorderRadius.circular(5),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// Small pill segmented control for mode and word length.
class _Segment extends StatelessWidget {
  const _Segment(
      {required this.options, required this.selected, required this.onSelect});

  final List<String> options;
  final int selected;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    final skin = _skin(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: skin.panel, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                    color: i == selected ? skin.correct : Colors.transparent,
                    borderRadius: BorderRadius.circular(18)),
                child: Text(options[i],
                    style: TextStyle(
                        color: i == selected ? Colors.white : skin.muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Keyboard extends StatelessWidget {
  const _Keyboard({required this.statuses, required this.onKey});

  final Map<String, LetterStatus> statuses;
  final void Function(String) onKey;

  static const _rows = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];

  @override
  Widget build(BuildContext context) {
    final skin = _skin(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < _rows.length; r++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (r == 2) _key(skin, 'ENTER', flex: 16),
                  for (final c in _rows[r].split(''))
                    _key(skin, c, status: statuses[c]),
                  if (r == 2) _key(skin, 'DEL', flex: 16, icon: Icons.backspace),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _key(GameSkin skin, String label,
      {int flex = 10, LetterStatus? status, IconData? icon}) {
    final colored = status != null;
    final bg = colored ? skin.status(status) : skin.keyBg;
    final fg = colored ? Colors.white : skin.keyText;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.5),
        child: SizedBox(
          height: 56,
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(7),
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              onTap: () => onKey(label),
              child: Center(
                child: icon != null
                    ? Icon(icon, size: 20, color: fg)
                    : Text(
                        label.toUpperCase(),
                        style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.bold,
                            fontSize: label.length > 1 ? 12 : 18),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsView extends StatelessWidget {
  const _StatsView({required this.stats});
  final Stats stats;

  @override
  Widget build(BuildContext context) {
    final skin = _skin(context);
    final maxDist = stats.distribution.fold<int>(1, (m, v) => v > m ? v : m);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Stat('${stats.played}', 'Played'),
            _Stat('${stats.winPercent}', 'Win %'),
            _Stat('${stats.currentStreak}', 'Streak'),
            _Stat('${stats.maxStreak}', 'Max'),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Guess distribution',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                    width: 16,
                    child: Text('${i + 1}',
                        style: TextStyle(color: skin.muted))),
                const SizedBox(width: 6),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor:
                          (stats.distribution[i] / maxDist).clamp(0.06, 1.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: stats.distribution[i] > 0
                              ? skin.correct
                              : skin.tileEmpty,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        alignment: Alignment.centerRight,
                        child: Text('${stats.distribution[i]}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DailyStatsView extends StatelessWidget {
  const _DailyStatsView({required this.stats});
  final DailyStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Daily', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Stat('${stats.played}', 'Played'),
            _Stat('${stats.winPercent}', 'Win %'),
            _Stat('${stats.streak}', 'Streak'),
            _Stat('${stats.maxStreak}', 'Max'),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          Text(label,
              style: TextStyle(fontSize: 12, color: _skin(context).muted)),
        ],
      );
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(5)),
      ),
      const SizedBox(width: 10),
      Text(text),
    ]);
  }
}

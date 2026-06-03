import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_logic.dart';
import 'stats.dart';
import 'words.dart';

void main() => runApp(const WordplayApp());

// colours
const _bg = Color(0xFF121213);
const _panel = Color(0xFF1E1E1F);
const _green = Color(0xFF6AAA64);
const _yellow = Color(0xFFC9B458);
const _gray = Color(0xFF3A3A3C);
const _keyDefault = Color(0xFF818384);
const _tbdBorder = Color(0xFF565758);
const _emptyBorder = Color(0xFF3A3A3C);

Color _colorFor(LetterStatus s) => switch (s) {
      LetterStatus.correct => _green,
      LetterStatus.present => _yellow,
      LetterStatus.absent => _gray,
      _ => _keyDefault,
    };

enum GameMode { unlimited, daily }

class WordplayApp extends StatelessWidget {
  const WordplayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wordplay by Spacechase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(surface: _bg, primary: _green),
      ),
      home: const GamePage(),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

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
  bool _busy = false; // locks input during the reveal animation
  bool _loading = true;

  int _justSubmittedRow = -1; // row to flip
  int _winRow = -1; // row to bounce
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
    await _startFromStorage();
    if (mounted) setState(() => _loading = false);
  }

  WordleGame _build(String answer, [List<String> guesses = const []]) {
    final g = WordleGame(answer: answer, validGuesses: _dict!.valid);
    g.guesses.addAll(guesses);
    return g;
  }

  Future<void> _startFromStorage() async {
    if (_mode == GameMode.daily) {
      _dict = await Dictionary.forLength(5);
      final snap = await GameStore.loadDaily();
      if (snap != null && snap.day == _today) {
        _game = _build(snap.answer, snap.guesses);
      } else {
        final answer = _dict!.answerForIndex(_today);
        _game = _build(answer);
        await GameStore.saveDaily(_today, answer, const []);
      }
    } else {
      _dict = await Dictionary.forLength(_length);
      final snap = await GameStore.loadUnlimited();
      if (snap != null && snap.answer.length == _length) {
        _game = _build(snap.answer, snap.guesses);
      } else {
        final answer = _dict!.randomAnswer(_rng);
        _game = _build(answer);
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

  // physical keyboard -> same handler as the on-screen keys
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
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.black,
                fontWeight: good ? FontWeight.bold : FontWeight.normal)),
        behavior: SnackBarBehavior.floating,
        duration: Duration(milliseconds: good ? 1500 : 1100),
        backgroundColor: Colors.white,
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
      _game = _build(answer);
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

  void _showEndDialog(bool didWin) {
    final daily = _mode == GameMode.daily;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        title: Text(didWin ? 'Got it! 🎉' : 'Out of guesses'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!didWin)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                    children: [
                      const TextSpan(text: 'The word was '),
                      TextSpan(
                        text: _game!.answer.toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
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
            icon: const Icon(Icons.copy),
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
        backgroundColor: _panel,
        title: const Text('Statistics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatsView(stats: _stats),
            const SizedBox(height: 18),
            const Divider(color: Colors.white12),
            const SizedBox(height: 6),
            _DailyStatsView(stats: _daily),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _confirmReset(ctx),
            child: const Text('Reset', style: TextStyle(color: Colors.white38)),
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
        backgroundColor: _panel,
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
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('How to play'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Guess the hidden word in 6 tries. Your guess has to be a '
                'real word of the right length.'),
            SizedBox(height: 12),
            _LegendRow(color: _green, text: 'Right letter, right spot'),
            SizedBox(height: 6),
            _LegendRow(color: _yellow, text: 'Right letter, wrong spot'),
            SizedBox(height: 6),
            _LegendRow(color: _gray, text: 'Not in the word'),
            SizedBox(height: 12),
            Text('Unlimited: play forever, pick 4, 5 or 6 letters. Daily: one '
                'shared puzzle a day. Hard mode makes you reuse every hint.',
                style: TextStyle(color: Colors.white70)),
            SizedBox(height: 16),
            Center(
              child: Text('Wordplay by Spacechase',
                  style: TextStyle(
                      fontSize: 12, color: Colors.white38, letterSpacing: 0.5)),
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _bg,
        centerTitle: true,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('WORDPLAY',
                style: TextStyle(
                    fontWeight: FontWeight.w800, letterSpacing: 4, height: 1)),
            Text('by Spacechase',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: Colors.white54,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        shape:
            const Border(bottom: BorderSide(color: Color(0xFF2A2A2B), width: 1)),
        actions: [
          IconButton(
              onPressed: _showHelp, icon: const Icon(Icons.help_outline)),
          IconButton(
              onPressed: _showStats, icon: const Icon(Icons.leaderboard)),
          Row(children: [
            const Text('Hard', style: TextStyle(fontSize: 12)),
            Switch(
              value: _hardMode,
              onChanged: (v) {
                if ((_game?.guesses.isNotEmpty ?? false)) {
                  _reject('Hard mode locks once you guess');
                  return;
                }
                setState(() => _hardMode = v);
                Settings.setHardMode(v);
              },
            ),
          ]),
          if (_mode == GameMode.unlimited)
            IconButton(
                tooltip: 'New word',
                onPressed: _newUnlimited,
                icon: const Icon(Icons.refresh)),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: (_loading || _game == null)
            ? const Center(child: CircularProgressIndicator(color: _green))
            : Column(
                children: [
                  _buildTopBar(),
                  Expanded(child: Center(child: _buildGrid())),
                  if (_game!.isOver) _buildEndBar(),
                  _Keyboard(
                      statuses: _game!.keyboardStatuses(), onKey: _onKey),
                  const SizedBox(height: 8),
                ],
              ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
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
    final List<InlineSpan> spans = won
        ? [
            TextSpan(
                text: 'Solved in ${game.guesses.length}/6 ',
                style: const TextStyle(color: Colors.white)),
            const TextSpan(text: '🎉'),
          ]
        : [
            const TextSpan(text: 'Answer: '),
            TextSpan(
              text: game.answer.toUpperCase(),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1),
            ),
          ];
    if (daily) {
      spans.add(TextSpan(
          text: '   ·   streak ${_daily.streak}',
          style: const TextStyle(color: Colors.white38, fontSize: 13)));
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
          color: _panel, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
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
      final byWidth = c.maxWidth * 0.92 / len - 6;
      final byHeight = c.maxHeight / game.maxGuesses - 6;
      final tile = math.min(byWidth, byHeight).clamp(28.0, 62.0).toDouble();
      return AnimatedBuilder(
        animation: _shake,
        builder: (context, child) =>
            Transform.translate(offset: Offset(_shakeOffset(_shake.value), 0),
                child: child),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children:
              List.generate(game.maxGuesses, (row) => _buildRow(row, tile)),
        ),
      );
    });
  }

  // damped horizontal wiggle for invalid guesses
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

// One tile: flips to reveal its colour, and bounces on a win.
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
  bool _flipped = false;
  bool _bounced = false;

  @override
  void initState() {
    super.initState();
    _flipC = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _bounceC = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    if (widget.flip) _scheduleFlip();
    if (widget.bounce) _scheduleBounce();
  }

  @override
  void didUpdateWidget(LetterTile old) {
    super.didUpdateWidget(old);
    if (widget.flip && !old.flip && !_flipped) _scheduleFlip();
    if (widget.bounce && !old.bounce && !_bounced) _scheduleBounce();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final revealed = widget.status == LetterStatus.correct ||
        widget.status == LetterStatus.present ||
        widget.status == LetterStatus.absent;

    return AnimatedBuilder(
      animation: Listenable.merge([_flipC, _bounceC]),
      builder: (context, _) {
        final t = _flipC.value;
        final showColored = !widget.flip || t >= 0.5;
        final angle = (t < 0.5 ? t : 1 - t) * 3.14159;
        final dy = -widget.size * 0.22 * math.sin(3.14159 * _bounceC.value);
        final face =
            showColored && revealed ? _coloredFace() : _typingFace();
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..rotateX(angle),
            child: face,
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
      decoration: BoxDecoration(color: bg, border: border),
      child: child,
    );
  }

  Widget _typingFace() => _box(
        border: Border.all(
            color: widget.filled ? _tbdBorder : _emptyBorder, width: 2),
        child: _text(),
      );

  Widget _coloredFace() =>
      _box(bg: _colorFor(widget.status), child: _text());

  Widget _text() => Text(
        widget.letter.toUpperCase(),
        style: TextStyle(
            color: Colors.white,
            fontSize: widget.size * 0.5,
            fontWeight: FontWeight.bold),
      );
}

// Small pill-style segmented control used for mode and word length.
class _Segment extends StatelessWidget {
  const _Segment(
      {required this.options, required this.selected, required this.onSelect});

  final List<String> options;
  final int selected;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: _panel, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                    color: i == selected ? _green : Colors.transparent,
                    borderRadius: BorderRadius.circular(18)),
                child: Text(options[i],
                    style: TextStyle(
                        color: i == selected ? Colors.white : Colors.white60,
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
                  if (r == 2) _key('ENTER', flex: 15),
                  for (final c in _rows[r].split(''))
                    _key(c, status: statuses[c]),
                  if (r == 2) _key('DEL', flex: 15, icon: Icons.backspace),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _key(String label,
      {int flex = 10, LetterStatus? status, IconData? icon}) {
    final bg = status != null ? _colorFor(status) : _keyDefault;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.5),
        child: SizedBox(
          height: 56,
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(5),
            child: InkWell(
              borderRadius: BorderRadius.circular(5),
              onTap: () => onKey(label),
              child: Center(
                child: icon != null
                    ? Icon(icon, size: 20, color: Colors.white)
                    : Text(
                        label.toUpperCase(),
                        style: TextStyle(
                            color: Colors.white,
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
                        style: const TextStyle(color: Colors.white70))),
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
                        color: stats.distribution[i] > 0 ? _green : _gray,
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
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
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
      Container(width: 28, height: 28, color: color),
      const SizedBox(width: 10),
      Text(text),
    ]);
  }
}

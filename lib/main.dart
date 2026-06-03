import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_logic.dart';
import 'stats.dart';

void main() => runApp(const WordplayApp());

// Palette (NYT-style dark theme).
const _bg = Color(0xFF121213);
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
  late WordleGame _game;
  Stats _stats = Stats();
  bool _hardMode = false;
  bool _busy = false; // locks input during reveal animation

  int _justSubmittedRow = -1; // row to play the flip on
  late final AnimationController _shake;
  final FocusNode _kbFocus = FocusNode(); // keeps physical keyboard active

  static const _flipMs = 300;
  static const _staggerMs = 220;

  @override
  void initState() {
    super.initState();
    _game = WordleGame.random();
    _shake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _loadPersisted();
  }

  Future<void> _loadPersisted() async {
    final s = await Stats.load();
    final hm = await Settings.hardMode();
    if (mounted) {
      setState(() {
        _stats = s;
        _hardMode = hm;
      });
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    _kbFocus.dispose();
    super.dispose();
  }

  // ---- Input handling -------------------------------------------------------

  // Route physical keyboard events to the same handler as on-screen taps.
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
    if (label.length == 1 && label.codeUnitAt(0) >= 0x61 &&
        label.codeUnitAt(0) <= 0x7a) {
      _onKey(label);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onKey(String key) {
    // On-screen taps move focus to the button; pull it back so the
    // hardware keyboard keeps working afterwards.
    if (!_kbFocus.hasFocus) _kbFocus.requestFocus();
    if (_busy || _game.isOver) return;
    if (key == 'ENTER') {
      _submit();
    } else if (key == 'DEL') {
      setState(() => _game.removeLetter());
    } else {
      setState(() => _game.addLetter(key));
    }
  }

  void _reject(String message) {
    _shake.forward(from: 0);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1100),
        backgroundColor: Colors.white,
        width: 240,
      ));
  }

  Future<void> _submit() async {
    if (_game.current.length < _game.wordLength) {
      _reject('Not enough letters');
      return;
    }
    if (_hardMode) {
      final v = _game.hardModeViolation(_game.current);
      if (v != null) {
        _reject(v);
        return;
      }
    }
    final rowIndex = _game.guesses.length;
    final err = _game.submit();
    if (err != null) {
      _reject(err);
      return;
    }

    setState(() {
      _justSubmittedRow = rowIndex;
      _busy = true;
    });

    // Wait for the staggered flip to finish before resolving the round.
    final total = _staggerMs * (_game.wordLength - 1) + _flipMs + 80;
    await Future<void>.delayed(Duration(milliseconds: total));
    if (!mounted) return;

    setState(() => _busy = false);

    if (_game.isOver) {
      final didWin = _game.isWon;
      await _stats.record(
          didWin: didWin, guessCount: didWin ? _game.guesses.length : 0);
      if (mounted) setState(() {});
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (mounted) _showEndDialog(didWin);
    }
  }

  void _newGame() {
    setState(() {
      _game = WordleGame.random();
      _justSubmittedRow = -1;
      _busy = false;
    });
    _kbFocus.requestFocus();
  }

  // ---- Dialogs --------------------------------------------------------------

  void _showEndDialog(bool didWin) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1F),
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
                        text: _game.answer.toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            _StatsView(stats: _stats),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              final header =
                  'Wordplay ${didWin ? _game.guesses.length : "X"}/6'
                  '${_hardMode ? "*" : ""}';
              Clipboard.setData(
                  ClipboardData(text: '$header\n\n${_game.shareGrid()}'));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Copied results to clipboard'),
                behavior: SnackBarBehavior.floating,
              ));
            },
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _newGame();
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
        backgroundColor: const Color(0xFF1E1E1F),
        title: const Text('Statistics'),
        content: _StatsView(stats: _stats),
        actions: [
          TextButton(
            onPressed: () async {
              await _stats.reset();
              if (mounted) setState(() {});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Reset', style: TextStyle(color: Colors.white38)),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1F),
        title: const Text('How to play'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Guess the word in 6 tries. Each guess must be a valid '
                '5-letter word.'),
            SizedBox(height: 12),
            _LegendRow(color: _green, text: 'Right letter, right spot'),
            SizedBox(height: 6),
            _LegendRow(color: _yellow, text: 'Right letter, wrong spot'),
            SizedBox(height: 6),
            _LegendRow(color: _gray, text: 'Not in the word'),
            SizedBox(height: 12),
            Text('Unlimited mode: play as many words as you like. Hard mode '
                'forces you to reuse every hint you uncover.',
                style: TextStyle(color: Colors.white70)),
            SizedBox(height: 16),
            Center(
              child: Text('Wordplay by Spacechase',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white38,
                      letterSpacing: 0.5)),
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

  // ---- Build ----------------------------------------------------------------

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
                    fontWeight: FontWeight.w800, letterSpacing: 4, height: 1.0)),
            Text('by Spacechase',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: Colors.white54,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        shape: const Border(
            bottom: BorderSide(color: Color(0xFF2A2A2B), width: 1)),
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
                // Hard mode can only change before guesses are made.
                if (_game.guesses.isNotEmpty) {
                  _reject('Hard mode locks once you guess');
                  return;
                }
                setState(() => _hardMode = v);
                Settings.setHardMode(v);
              },
            ),
          ]),
          IconButton(
              tooltip: 'New game',
              onPressed: _newGame,
              icon: const Icon(Icons.refresh)),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: Center(child: _buildGrid())),
            _Keyboard(statuses: _game.keyboardStatuses(), onKey: _onKey),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final dx = _shakeOffset(_shake.value);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(_game.maxGuesses, (row) => _buildRow(row)),
      ),
    );
  }

  // Damped horizontal wiggle for invalid guesses.
  double _shakeOffset(double t) {
    if (t == 0 || t == 1) return 0;
    const twoPi = 6.283185307179586;
    return 7 * (1 - t) * _signWave((t * 3 * twoPi).remainder(twoPi));
  }

  double _signWave(double v) {
    const pi = 3.141592653589793;
    return v < pi ? 1 : -1;
  }

  Widget _buildRow(int row) {
    final isSubmitted = row < _game.guesses.length;
    final isCurrent = row == _game.guesses.length && !_game.isOver;
    final word =
        isSubmitted ? _game.guesses[row] : (isCurrent ? _game.current : '');
    final statuses =
        isSubmitted ? WordleGame.evaluate(word, _game.answer) : null;
    final animate = row == _justSubmittedRow;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_game.wordLength, (col) {
        final letter = col < word.length ? word[col] : '';
        final status = statuses != null ? statuses[col] : LetterStatus.tbd;
        return LetterTile(
          key: ValueKey('$row-$col-${_game.answer}'),
          letter: letter,
          status: status,
          filled: letter.isNotEmpty,
          animate: animate,
          delayMs: animate ? col * _staggerMs : 0,
        );
      }),
    );
  }
}

/// A single letter tile with a flip-reveal animation.
class LetterTile extends StatefulWidget {
  const LetterTile({
    super.key,
    required this.letter,
    required this.status,
    required this.filled,
    this.animate = false,
    this.delayMs = 0,
  });

  final String letter;
  final LetterStatus status;
  final bool filled;
  final bool animate;
  final int delayMs;

  @override
  State<LetterTile> createState() => _LetterTileState();
}

class _LetterTileState extends State<LetterTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _played = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    if (widget.animate) _scheduleFlip();
  }

  @override
  void didUpdateWidget(LetterTile old) {
    super.didUpdateWidget(old);
    if (widget.animate && !old.animate && !_played) _scheduleFlip();
  }

  void _scheduleFlip() {
    _played = true;
    Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final revealed = widget.status == LetterStatus.correct ||
        widget.status == LetterStatus.present ||
        widget.status == LetterStatus.absent;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // First half shows the "before" face, second half the colored face.
        final showColored = !widget.animate || t >= 0.5;
        final angle = (t < 0.5 ? t : 1 - t) * 3.14159; // 0..pi/2..0
        final face =
            showColored && revealed ? _coloredFace() : _typingFace();
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..rotateX(angle),
          child: face,
        );
      },
    );
  }

  Widget _box({required Widget child, Color? bg, Border? border}) {
    return Container(
      margin: const EdgeInsets.all(3),
      width: 58,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, border: border),
      child: child,
    );
  }

  Widget _typingFace() {
    return _box(
      border: Border.all(
          color: widget.filled ? _tbdBorder : _emptyBorder, width: 2),
      child: _text(Colors.white),
    );
  }

  Widget _coloredFace() {
    return _box(bg: _colorFor(widget.status), child: _text(Colors.white));
  }

  Widget _text(Color color) => Text(
        widget.letter.toUpperCase(),
        style: TextStyle(
            color: color, fontSize: 30, fontWeight: FontWeight.bold),
      );
}

// ---- Keyboard ---------------------------------------------------------------

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

// ---- Stats view -------------------------------------------------------------

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
            _stat('${stats.played}', 'Played'),
            _stat('${stats.winPercent}', 'Win %'),
            _stat('${stats.currentStreak}', 'Streak'),
            _stat('${stats.maxStreak}', 'Max'),
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

  Widget _stat(String value, String label) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold)),
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

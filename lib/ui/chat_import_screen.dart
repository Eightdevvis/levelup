import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/chat_prompts.dart';
import '../data/plan_round.dart';
import '../data/tag_round.dart';
import '../main.dart';
import '../model/library.dart';
import 'program_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Ein Plan aus dem eigenen Chat, in zwei Runden.
///
/// Der Ablauf ist bewusst ein Hin und Her: erst besprichst du dein Vorhaben
/// mit einer KI deiner Wahl, dann übersetzt sie das Besprochene in Übungen,
/// dann ordnet sie die Übungen zu einem Programm. Dazwischen ist jedes Mal
/// die App am Zug — sie kennt die Bibliothek, die KI nicht.
///
/// Der Umweg über zwei Runden hat einen Grund: eine KI, die Übungen erfindet
/// und gleichzeitig einen Plan baut, erfindet auch dann neu, wenn es die Übung
/// längst gibt. Erst wenn feststeht, welche Bausteine da sind, kann sie
/// ordnen statt zu dichten.
class ChatImportScreen extends StatefulWidget {
  const ChatImportScreen({super.key});

  @override
  State<ChatImportScreen> createState() => _ChatImportScreenState();
}

class _ChatImportScreenState extends State<ChatImportScreen> {
  final _roundOne = TextEditingController();
  final _roundTwo = TextEditingController();

  /// Sobald das steht, ist Runde 1 vorbei — daran hängt Schritt 3.
  ResolveResult? _resolved;
  PlanParseResult? _plan;
  String? _error;
  bool _installing = false;

  @override
  void dispose() {
    _roundOne.dispose();
    _roundTwo.dispose();
    super.dispose();
  }

  List<TagCount> get _pool =>
      tagPool(AppScope.of(context).library.exercises.values);

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('// $label KOPIERT')));
  }

  Future<void> _paste(TextEditingController target) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) setState(() => target.text = data!.text!);
  }

  void _resolve() {
    final round = parseRoundOne(_roundOne.text);
    if (round.isEmpty) {
      setState(() {
        _error = round.problems.isEmpty
            ? 'Da war keine einzige Übung drin. Steht die Antwort der KI '
                  'wirklich im Feld?'
            : 'Keine Übung lesbar. ${round.problems.first}';
      });
      return;
    }

    final result = resolveRequests(
      round,
      AppScope.of(context).library.exercises.values,
    );
    setState(() {
      _error = null;
      _resolved = result;
    });
  }

  void _buildPlan() {
    final resolved = _resolved;
    if (resolved == null) return;
    final result = parseRoundTwo(_roundTwo.text, resolved.resolved);
    setState(() {
      _plan = result;
      _error = result.ok ? null : result.error;
    });
  }

  Future<void> _install() async {
    final bundle = _plan?.bundle;
    if (bundle == null) return;

    setState(() => _installing = true);
    final state = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await state.installBundle(bundle);
    if (!mounted) return;

    setState(() => _installing = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '// ÜBERNOMMEN · ${bundle.exercises.length} ÜBUNGEN IN DER BIBLIOTHEK',
        ),
      ),
    );

    final program = bundle.programs.isEmpty ? null : bundle.programs.first;
    if (program == null) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProgramScreen(programId: program.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PLAN AUS DEM CHAT'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: p.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 40),
        children: [
          ..._talkStep(p),
          const SizedBox(height: 20),
          ..._exerciseStep(p),
          if (_resolved != null) ...[
            const SizedBox(height: 20),
            ..._planStep(p),
          ],
          if (_error != null) ...[
            const SizedBox(height: 18),
            ZBox(
              title: 'das ging nicht',
              accent: p.error,
              child: Text(
                _error!,
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 11,
                  height: 1.6,
                  color: p.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // -- Schritt 1: reden -------------------------------------------------------

  List<Widget> _talkStep(Palette p) {
    return [
      _StepHead(number: 1, title: 'Mit deiner KI reden'),
      _Body(
        p,
        'Sprich mit der KI deiner Wahl darüber, worin du besser werden '
        'willst, und bitte sie um konkrete Schritte.',
      ),
      const SizedBox(height: 12),
      ZBox(
        title: 'damit wird es gut',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final tipp in const [
              'Beschreib dein Ziel, deine Lage und deine Vorgeschichte mit '
                  'dem Thema ausführlich. Zu wenig Kontext ist der häufigste '
                  'Grund für einen belanglosen Plan.',
              'Nenne deine Vorbilder — wer kann das, was du können willst.',
              'Bitte die KI ausdrücklich, zu überlegen, wer in deinem Fach '
                  'als besonders talentiert galt, und herauszufinden, wie '
                  'diese Menschen tatsächlich so gut wurden. Nicht die '
                  'Biografie, sondern die Methode.',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '· $tipp',
                  style: TextStyle(
                    fontFamily: Metrics.mono,
                    fontSize: 10.5,
                    height: 1.6,
                    color: p.fgDim,
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  // -- Schritt 2: Übungen -----------------------------------------------------

  List<Widget> _exerciseStep(Palette p) {
    final pool = _pool;

    return [
      _StepHead(number: 2, title: 'Übungen herausschälen'),
      _Body(
        p,
        pool.isEmpty
            ? 'Deine Bibliothek ist noch leer — die KI schreibt diesmal alle '
                  'Übungen selbst, und ihre Tags werden dein Vokabular. Ab dem '
                  'nächsten Plan wird daraus wiederverwendet.'
            : 'Der Text unten trägt die ${pool.length} Tags deiner Bibliothek '
                  'mit. Alles, was die KI damit beschreiben kann, wird '
                  'wiederverwendet statt neu erfunden.',
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: const Icon(Icons.copy_all_outlined, size: 18),
        label: const Text('TEXT FÜR DIE KI KOPIEREN'),
        onPressed: () => _copy(buildTagPrompt(pool), 'TEXT'),
      ),
      const SizedBox(height: 16),
      _Body(p, 'Die Antwort der KI hier einfügen:'),
      const SizedBox(height: 8),
      _PasteField(
        controller: _roundOne,
        hint: '1. ["geige", "rueckkopplung", "aufnahme"]\n2. { "name": … }',
        onPaste: () => _paste(_roundOne),
        onSubmit: _resolve,
        submitLabel: 'ÜBUNGEN AUFLÖSEN',
      ),
      if (_resolved != null) ...[
        const SizedBox(height: 14),
        _ResolveReport(result: _resolved!),
      ],
    ];
  }

  // -- Schritt 3: Plan --------------------------------------------------------

  List<Widget> _planStep(Palette p) {
    final resolved = _resolved!;
    final plan = _plan;

    return [
      _StepHead(number: 3, title: 'Programm bauen lassen'),
      _Body(
        p,
        'Jetzt weiß die App, welche Übungen es gibt. Der nächste Text zeigt '
        'sie der KI mit ihren Kennungen — sie ordnet nur noch.',
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: const Icon(Icons.copy_all_outlined, size: 18),
        label: const Text('TEXT FÜR DIE KI KOPIEREN'),
        onPressed: () => _copy(buildPlanPrompt(resolved.resolved), 'TEXT'),
      ),
      const SizedBox(height: 16),
      _Body(p, 'Die zweite Antwort hier einfügen:'),
      const SizedBox(height: 8),
      _PasteField(
        controller: _roundTwo,
        hint: '{ "program": { … }, "units": [ … ] }',
        onPaste: () => _paste(_roundTwo),
        onSubmit: _buildPlan,
        submitLabel: 'PLAN LESEN',
      ),
      if (plan != null && plan.ok) ...[
        const SizedBox(height: 16),
        _PlanPreview(bundle: plan.bundle!, warnings: plan.warnings),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _installing ? null : _install,
          child: Text(_installing ? 'WIRD ÜBERNOMMEN…' : 'IN MEINE BIBLIOTHEK'),
        ),
      ],
    ];
  }
}

// --- Bausteine der Oberfläche ------------------------------------------------

class _StepHead extends StatelessWidget {
  const _StepHead({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: p.accent, width: Metrics.line),
            ),
            child: Text(
              '$number',
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 11,
                color: p.accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: Metrics.trackWider,
                color: p.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.palette, this.text);

  final Palette palette;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: Metrics.mono,
        fontSize: 11,
        height: 1.65,
        color: palette.fgDim,
      ),
    );
  }
}

class _PasteField extends StatelessWidget {
  const _PasteField({
    required this.controller,
    required this.hint,
    required this.onPaste,
    required this.onSubmit,
    required this.submitLabel,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onPaste;
  final VoidCallback onSubmit;
  final String submitLabel;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    return Column(
      children: [
        TextField(
          controller: controller,
          minLines: 5,
          maxLines: 12,
          style: TextStyle(
            fontFamily: Metrics.mono,
            fontSize: 11.5,
            height: 1.5,
            color: p.fg,
          ),
          decoration: InputDecoration(hintText: hint),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.paste, size: 18),
                label: const Text('EINFÜGEN'),
                onPressed: onPaste,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(onPressed: onSubmit, child: Text(submitLabel)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Was aus Runde 1 wurde.
///
/// Die Lücken stehen hier so groß wie die Treffer: eine Tag-Menge ohne
/// Entsprechung heißt, dass die KI eine Übung vorausgesetzt hat, die es nicht
/// gibt. Wer das nicht sieht, wundert sich später über einen dünnen Plan.
class _ResolveReport extends StatelessWidget {
  const _ResolveReport({required this.result});

  final ResolveResult result;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final luecken = result.unmatched.isNotEmpty || result.problems.isNotEmpty;

    return ZBox(
      title: 'gefunden',
      trailing: '${result.resolved.length} ÜBUNGEN',
      accent: luecken ? p.error : p.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${result.reused} aus der Bibliothek · ${result.created} neu',
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 10.5,
              letterSpacing: 1.2,
              color: p.fgDim,
            ),
          ),
          const SizedBox(height: 10),
          for (final r in result.resolved)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                '${r.isNew ? "+" : "·"} ${r.exercise.name}',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10.5,
                  height: 1.5,
                  color: r.isNew ? p.fg : p.fgDim,
                ),
              ),
            ),
          if (result.unmatched.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'OHNE ENTSPRECHUNG — die KI hat angenommen, es gäbe dazu schon '
              'eine Übung:',
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10,
                letterSpacing: 1.1,
                height: 1.5,
                color: p.error,
              ),
            ),
            const SizedBox(height: 6),
            for (final tags in result.unmatched)
              Text(
                '! [${tags.join(", ")}]',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10.5,
                  height: 1.5,
                  color: p.error,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Bitte die KI, genau diese Übungen auszuschreiben, und füg die '
              'Antwort noch einmal ein.',
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10.5,
                height: 1.6,
                color: p.fgDim,
              ),
            ),
          ],
          if (result.problems.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final problem in result.problems)
              Text(
                '? $problem',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10,
                  height: 1.5,
                  color: p.fgFaint,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PlanPreview extends StatelessWidget {
  const _PlanPreview({required this.bundle, required this.warnings});

  final Bundle bundle;
  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final program = bundle.programs.first;

    return ZBox(
      title: 'plan',
      trailing: '${program.totalWeeks}W',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            program.name,
            style: TextStyle(
              fontFamily: Metrics.display,
              fontSize: 21,
              height: 1.15,
              color: p.fg,
            ),
          ),
          if (program.description != null) ...[
            const SizedBox(height: 8),
            Text(
              program.description!,
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 11,
                height: 1.6,
                color: p.fgDim,
              ),
            ),
          ],
          const SizedBox(height: 12),
          for (final phase in program.phases)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '· ${phase.name} — ${phase.weeks}W à ${phase.schedule.cycleLength} Tage',
                style: TextStyle(
                  fontFamily: Metrics.mono,
                  fontSize: 10.5,
                  height: 1.5,
                  color: p.fgDim,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            '${bundle.exercises.length} ÜBUNGEN · ${bundle.routines.length} '
            'EINHEITEN · ${program.totalDays} TAGE',
            style: TextStyle(
              fontFamily: Metrics.mono,
              fontSize: 10,
              letterSpacing: 1.2,
              color: p.fgDim,
            ),
          ),
          for (final warning in warnings) ...[
            const SizedBox(height: 8),
            Text(
              '! $warning',
              style: TextStyle(
                fontFamily: Metrics.mono,
                fontSize: 10,
                height: 1.5,
                color: p.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
